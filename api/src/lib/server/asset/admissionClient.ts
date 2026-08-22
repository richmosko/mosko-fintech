// admissionClient.ts — SERVER-ONLY worker-admission transport for the SELF-325 asset-resolve
// leg (manual purchase-path, Case 3 / public tickers).
//
// SCOPE: the api/src → provider-sync worker INTERNAL boundary, asset-resolve half. This module
// forwards the browser's identified security (symbol/cusip/asset_type/name/currency) to the
// worker's Option-C admission surface's new /asset/resolve route, adding the session-derived
// tenant + the shared-secret header. It lives in `src/lib/server/**` (ARCH §4.1 allowlist) —
// never ships to the browser.
//
// STRUCTURAL NOTE (mirrors the shipped precedent, deliberately): this is a THIRD
// admissionClient.ts, alongside api/src/lib/server/reauth/admissionClient.ts and
// api/src/lib/server/simplefin/admissionClient.ts — same WORKER_ADMISSION_SHARED_SECRET /
// WORKER_ADMISSION_URL pattern. It copies the callWorker/admissionConfig transport shape rather
// than importing a shared module, same deferred-cleanup rationale as the SimpleFIN leg (keep the
// shipped, Sec-reviewed modules untouched; a shared-transport lift is a later follow-up).
//
// SECURITY POSTURE
//  • Holds NO elevated service_role key — only the WORKER_ADMISSION_SHARED_SECRET. This keeps
//    api/src OFF the RT-26 allowlist (the global-asset INSERT under service_role happens
//    exclusively worker-side, via resolveSecurityId inside withServiceRole()).
//  • SC3-C1 (C6-3): `ownerUserId` is a REQUIRED function argument the caller derives from the
//    validated session (auth.uid() via safeGetSession). It is NEVER read from a request body.
//    `buildResolvePayload()` is the pure, deterministic seam that proves the value sent to the
//    worker is the session's, not the body's. It also doubles as the audit subject + future
//    rate-limit key — no rate-limit control exists today (routed to Sec at SELF-325 joint
//    review; the mint path became browser-reachable at this module, so the exposure is
//    user-driven now rather than server-to-server only).
//  • C6-5 redaction: this module never logs the request/response body. Operational logs carry
//    the route + upstream status ONLY.
//  • Transport is the internal Docker network only (http://provider-sync:8081); the worker is
//    unreachable by the browser by construction (DevOps CA-1 private-bind).

import { env } from '$env/dynamic/private';
import { z } from 'zod';

const ADMISSION_HEADER = 'x-worker-admission-secret';
const RESOLVE_PATH = '/asset/resolve';
// Coolify internal service name + DevOps-aligned admission port (ADMISSION_PORT=8081).
// Overridable via WORKER_ADMISSION_URL for local/CI targeting.
const DEFAULT_BASE_URL = 'http://provider-sync:8081';
const TIMEOUT_MS = 10_000;

// ── Env config (memoized, fail-loud at first use — mirrors simplefin/admissionClient.ts) ────────
let cfg: { baseUrl: string; secret: string } | null = null;
function admissionConfig(): { baseUrl: string; secret: string } {
	if (cfg) return cfg;
	const secret = env.WORKER_ADMISSION_SHARED_SECRET;
	if (!secret) {
		throw new Error(
			'Missing WORKER_ADMISSION_SHARED_SECRET — set it in the container runtime env (see .env.example, server tier).'
		);
	}
	const baseUrl = (env.WORKER_ADMISSION_URL || DEFAULT_BASE_URL).replace(/\/+$/, '');
	cfg = { baseUrl, secret };
	return cfg;
}

/** Test-only: clears the memoized env config so a spec can vary process.env per case. */
export function __resetConfigForTests(): void {
	cfg = null;
}

// ── Upstream (worker) response schema — server owns its own source of truth ─────────────
//
// ⚠ WIRE-FORMAT BUG, FIXED (QA freeze-break): `assetId` is a bigint pfin.asset.asset_id,
// serialized by the worker as a DECIMAL STRING (assetResolve.ts's AssetResolveResult — matching
// the SAME convention every other bigint id on this wire already follows: `sourceId` at the
// plaid/simplefin admission legs, `linked_source_id` in schemas/account.ts's
// linkedSourceIdField()). The ORIGINAL schema here was `z.number().int().positive().nullable()`,
// which rejected the worker's own (correct) string wire value — every /asset/resolve call 502'd.
// Validate the digit-string here; the caller (schemas/purchase.ts's securityIdField, already
// `z.coerce.number()`) coerces to a number only where it's actually consumed as the bigint RPC
// param, same as every other bigint id crossing this boundary.
const workerResolveResponseSchema = z.object({
	assetId: z
		.string()
		.regex(/^\d+$/, 'assetId must be a decimal digit-string')
		.nullable()
});

export type ResolveData = { assetId: string | null };

/** Discriminated outcome; on failure carries ONLY a browser-facing HTTP status (no leak). */
export type LegOutcome<T> = { ok: true; data: T } | { ok: false; status: number };

/** The already-`.strict()`-validated body this module forwards (schemas/asset.ts owns the
 *  boundary shape — pattern/length constraints mirror the worker's own §2.3 controls). */
export interface ValidatedResolveBody {
	symbol: string | null;
	cusip: string | null;
	assetType: string;
	name: string | null;
	currency: string;
}

// ── Pure payload builder (SC3-C1 seam — env-free, deterministic, unit-tested) ───────────
/**
 * Builds the asset-resolve worker payload. `ownerUserId` is ALWAYS the caller-supplied
 * (session-derived) value — the validated body cannot influence it (SC3-C1).
 */
export function buildResolvePayload(
	ownerUserId: string,
	validatedBody: ValidatedResolveBody
): {
	ownerUserId: string;
	symbol: string | null;
	cusip: string | null;
	assetType: string;
	name: string | null;
	currency: string;
} {
	return {
		ownerUserId, // session-derived arg — NEVER from validatedBody
		symbol: validatedBody.symbol,
		cusip: validatedBody.cusip,
		assetType: validatedBody.assetType,
		name: validatedBody.name,
		currency: validatedBody.currency
	};
}

// ── Upstream status → browser status mapping (mirrors the SimpleFIN/Plaid legs) ─────────
// The worker's /asset/resolve route has NO client-correctable 4xx of its own (the Zod schema
// there already rejected malformed identity inputs at that boundary before resolution runs) —
// but this module's OWN Zod re-validation (schemas/asset.ts) runs first, so a worker 400 here
// means a schema drift between the two boundaries, not a normal user path. Kept generic 4xx→400
// / else→500 for the same fail-safe reason as every other leg: a server failure must never be
// dressed up as client-correctable.
export function mapUpstreamStatus(status: number): number {
	if (status === 400 || status === 413) return 400;
	return 500;
}

// ── Transport (fetch + timeout; the ONLY env/network-touching surface) ──────────────────
type WorkerCall =
	| { transportOk: true; status: number; json: unknown }
	| { transportOk: false };

async function callWorker(path: string, payload: unknown): Promise<WorkerCall> {
	const { baseUrl, secret } = admissionConfig();
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
	try {
		const res = await fetch(`${baseUrl}${path}`, {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
				[ADMISSION_HEADER]: secret
			},
			body: JSON.stringify(payload),
			signal: controller.signal
		});
		let json: unknown = null;
		try {
			json = await res.json();
		} catch {
			json = null; // non-JSON / empty body — treated as malformed upstream below
		}
		if (res.status !== 200) {
			// C6-5: status + path ONLY, never the body/identity/secret.
			console.error(`[asset-admission] worker ${path} returned ${res.status}`);
		}
		return { transportOk: true, status: res.status, json };
	} catch {
		// Network error / DNS / connection refused / timeout-abort → worker unreachable.
		console.error(`[asset-admission] worker ${path} unreachable (transport failure)`);
		return { transportOk: false };
	} finally {
		clearTimeout(timer);
	}
}

// ── asset-resolve leg — resolve-or-mint a GLOBAL pfin.asset row ─────────────────────────
export async function resolveAsset(
	ownerUserId: string,
	validatedBody: ValidatedResolveBody
): Promise<LegOutcome<ResolveData>> {
	const call = await callWorker(RESOLVE_PATH, buildResolvePayload(ownerUserId, validatedBody));
	if (!call.transportOk) return { ok: false, status: 502 }; // worker unreachable → bad gateway
	if (call.status === 200) {
		const parsed = workerResolveResponseSchema.safeParse(call.json);
		if (!parsed.success) return { ok: false, status: 502 }; // malformed upstream
		return { ok: true, data: { assetId: parsed.data.assetId } };
	}
	return { ok: false, status: mapUpstreamStatus(call.status) };
}
