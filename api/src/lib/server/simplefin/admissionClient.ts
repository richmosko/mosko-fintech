// admissionClient.ts — SERVER-ONLY worker-admission transport for the SimpleFIN claim leg (OQ-2).
//
// SCOPE: the api/src → provider-sync worker INTERNAL boundary, SimpleFIN half. This module is the
// credential-less relay's server half: it forwards the browser's pasted SimpleFIN setup token to
// the worker's Option-C admission endpoint (new leg-S route on the shipped RT-27 fence), adding
// the session-derived tenant + the shared-secret header. It lives in `src/lib/server/**` (ARCH
// §4.1 allowlist) — never ships to the browser.
//
// STRUCTURAL NOTE (deliberate, flagged for the shared-transport lift follow-up): this mirrors the
// shipped `plaid/admissionClient.ts` transport (callWorker / mapUpstreamStatus / admissionConfig /
// workerExchangeResponseSchema) rather than importing Plaid-named symbols. Lifting the shared
// transport to `src/lib/server/providers/` is the design's recommended cleanup (§3b) — deferred
// here to keep the shipped, Sec-reviewed Plaid module + its tests untouched (0-regression). Either
// placement satisfies RT-26 (holds only the shared secret).
//
// SECURITY POSTURE
//  • Holds NO SimpleFIN credential and NO elevated service_role key — only the
//    WORKER_ADMISSION_SHARED_SECRET. This keeps api/src OFF the RT-26 allowlist. The SimpleFIN
//    claim + service_role Vault/INSERT txn live exclusively worker-side (SimpleFINAdapter.connect()).
//  • SC3-C1 (C6-3): `ownerUserId` is a REQUIRED function argument the caller derives from the
//    validated session (auth.uid() via safeGetSession). It is NEVER read from a request body.
//    `buildClaimPayload()` is the pure, deterministic seam that proves the value sent to the worker
//    is the session's, not the body's.
//  • C6-5 redaction: this module never logs the setup token or the shared secret. Operational logs
//    carry the route + upstream status ONLY (no bodies, no tokens).
//  • Transport is the internal Docker network only (http://provider-sync:8081); the worker is
//    unreachable by the browser by construction (DevOps CA-1 private-bind).

import { env } from '$env/dynamic/private';
import { z } from 'zod';

const ADMISSION_HEADER = 'x-worker-admission-secret';
const CLAIM_PATH = '/admission/simplefin/claim';
// Coolify internal service name + DevOps-aligned admission port (ADMISSION_PORT=8081).
// Overridable via WORKER_ADMISSION_URL for local/CI targeting.
const DEFAULT_BASE_URL = 'http://provider-sync:8081';
const TIMEOUT_MS = 10_000;

// ── Env config (memoized, fail-loud at first use — mirrors plaid/admissionClient.ts) ────────────
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
// Plain z.object() STRIPS unknown keys by default (safe for an upstream response — NOT user
// input, so the .strict() input rule does not apply; we deliberately drop surprise fields so
// nothing unexpected reaches the browser). Identical shape to the Plaid exchange response.
const workerAccountSchema = z.object({
	account_id: z.string().min(1),
	name: z.string().optional(),
	type: z.string().optional(),
	subtype: z.string().nullish(),
	currency: z.string().optional()
});

const workerClaimResponseSchema = z.object({
	// bigint pfin id serialized as a decimal STRING — dropped before the browser response
	// (internal id; the browser routes on account_id).
	sourceId: z.string(),
	accounts: z.array(workerAccountSchema)
});

export type AdmissionAccount = z.infer<typeof workerAccountSchema>;
// `sourceId` = the caller's own pfin.linked_source.source_id (bigint serialized as a
// decimal STRING). SURFACED to the browser (SELF-199, ADR-037): the account-attributes
// flow ((ii) client-carries-refs) passes it to fn_land_linked_accounts as the FK to bind
// each landed account. Owner-safe (caller owns the source); a tampered value fails closed
// at the 015 matched-tenant fence (Decision-3 #6) + 021 dedup. Mirrors the Plaid leg.
export type ClaimData = { sourceId: string; accounts: AdmissionAccount[] };

/** Discriminated outcome; on failure carries ONLY a browser-facing HTTP status (no leak). */
export type LegOutcome<T> = { ok: true; data: T } | { ok: false; status: number };

// ── Pure payload builder (SC3-C1 seam — env-free, deterministic, unit-tested) ───────────
/**
 * Builds the leg-S worker payload. `ownerUserId` is ALWAYS the caller-supplied (session-derived)
 * value — the validated body cannot influence it (SC3-C1). The body is already `.strict()`-
 * validated upstream, so it can carry only { setup_token, institutionName? }.
 */
export function buildClaimPayload(
	ownerUserId: string,
	validatedBody: { setup_token: string; institutionName?: string }
): { setup_token: string; ownerUserId: string; institutionName?: string } {
	return {
		setup_token: validatedBody.setup_token,
		ownerUserId, // session-derived arg — NEVER from validatedBody
		...(validatedBody.institutionName ? { institutionName: validatedBody.institutionName } : {})
	};
}

// ── Upstream status → browser status mapping (mirrors the Plaid leg) ────────────────────
// worker 4xx (bad/burned request, incl. 400 setup_token_invalid) → 400 client-correctable;
// worker 5xx (Bridge/admission failure, incl. the worker's 502 envelope) → 500 generic; anything
// else non-2xx (401 secret-mismatch, 404/405 routing) is an internal misconfig that must never
// leak → 500.
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
			// C6-5: status + path ONLY, never the body/token/secret.
			console.error(`[simplefin-admission] worker ${path} returned ${res.status}`);
		}
		return { transportOk: true, status: res.status, json };
	} catch {
		// Network error / DNS / connection refused / timeout-abort → worker unreachable.
		console.error(`[simplefin-admission] worker ${path} unreachable (transport failure)`);
		return { transportOk: false };
	} finally {
		clearTimeout(timer);
	}
}

// ── leg-S — setup-token claim + admission (credential-less relay) ────────────────────────
export async function admitSimplefin(
	ownerUserId: string,
	validatedBody: { setup_token: string; institutionName?: string }
): Promise<LegOutcome<ClaimData>> {
	// C6-4 analogue: a burned setup token must NOT be retried here — a single attempt; on failure
	// we surface the status so the browser obtains a fresh setup token from the SimpleFIN Bridge.
	const call = await callWorker(CLAIM_PATH, buildClaimPayload(ownerUserId, validatedBody));
	if (!call.transportOk) return { ok: false, status: 502 }; // worker unreachable → bad gateway
	if (call.status === 200) {
		const parsed = workerClaimResponseSchema.safeParse(call.json);
		if (!parsed.success) return { ok: false, status: 502 }; // malformed upstream
		// Forward sourceId (the caller's own linked_source id) alongside the account refs —
		// the browser needs it for the SELF-199 attributes flow (see ClaimData above).
		return { ok: true, data: { sourceId: parsed.data.sourceId, accounts: parsed.data.accounts } };
	}
	return { ok: false, status: mapUpstreamStatus(call.status) };
}
