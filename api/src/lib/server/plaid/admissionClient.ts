// admissionClient.ts — SERVER-ONLY worker-admission transport (SELF-197 relay legs).
//
// SCOPE: the api/src → provider-sync worker INTERNAL boundary. This module is the
// credential-less relay's server half: it forwards the browser's Plaid Link flow to
// the worker's Option-C admission endpoint (SELF-212 / ADR-027 (s)/(u)), adding the
// session-derived tenant + the shared-secret header. It lives in `src/lib/server/**`
// (ARCH §4.1 allowlist) — never ships to the browser.
//
// SECURITY POSTURE
//  • Holds NO Plaid client secret and NO elevated service_role key — only the
//    WORKER_ADMISSION_SHARED_SECRET. This keeps api/src OFF the RT-26 allowlist
//    (contract §"Refinements" #4). The Plaid credentials + service_role txn live
//    exclusively worker-side (PlaidAdapter.connect()).
//  • SC3-C1 (C6-3): `ownerUserId` is a REQUIRED function argument the caller derives
//    from the validated session (auth.uid() via safeGetSession). It is NEVER read
//    from a request body. `buildExchangePayload()` is the pure, deterministic seam
//    that proves the value sent to the worker is the session's, not the body's.
//  • C6-5 redaction: this module never logs the public_token or the shared secret.
//    Operational logs carry the route + upstream status ONLY (no bodies, no tokens).
//  • Transport is the internal Docker network only (http://provider-sync:8081); the
//    worker is unreachable by the browser by construction (DevOps CA-1 private-bind).
//
// Contract of record: temp/self212-worker-endpoint-contract.md (BOTH legs POST;
// header x-worker-admission-secret; leg-2 returns {sourceId(string), accounts[]}).

import { env } from '$env/dynamic/private';
import { z } from 'zod';

const ADMISSION_HEADER = 'x-worker-admission-secret';
const LINK_TOKEN_PATH = '/admission/link-token';
const EXCHANGE_PATH = '/admission/exchange';
// Coolify internal service name + DevOps-aligned admission port (ADMISSION_PORT=8081).
// Overridable via WORKER_ADMISSION_URL for local/CI targeting.
const DEFAULT_BASE_URL = 'http://provider-sync:8081';
const TIMEOUT_MS = 10_000;

// ── Env config (memoized, fail-loud at first use — mirrors hooks.server.ts) ────────────
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

// ── Upstream (worker) response schemas — server owns its own source of truth ───────────
// Plain z.object() STRIPS unknown keys by default (safe for an upstream response — this
// is NOT user input, so the .strict() / no-.passthrough input rule does not apply; we
// deliberately drop surprise fields so nothing unexpected reaches the browser).
const workerLinkTokenResponseSchema = z.object({
	link_token: z.string().min(1),
	expiration: z.string().min(1)
});

const workerAccountSchema = z.object({
	account_id: z.string().min(1),
	name: z.string().optional(),
	mask: z.string().nullish(),
	type: z.string().optional(),
	subtype: z.string().nullish(),
	currency: z.string().optional()
});

const workerExchangeResponseSchema = z.object({
	// bigint pfin id serialized as a decimal STRING (JSON-unsafe as a number) — contract
	// §Leg-2. Dropped before the browser response (internal id; browser routes on account_id).
	sourceId: z.string(),
	accounts: z.array(workerAccountSchema)
});

export type LinkTokenData = z.infer<typeof workerLinkTokenResponseSchema>;
export type AdmissionAccount = z.infer<typeof workerAccountSchema>;
export type ExchangeData = { accounts: AdmissionAccount[] };

/** Discriminated outcome; on failure carries ONLY a browser-facing HTTP status (no leak). */
export type LegOutcome<T> = { ok: true; data: T } | { ok: false; status: number };

// ── Institution metadata extraction (Plaid Link onSuccess metadata → optional fwd) ─────
// Lenient pick: metadata is the browser's Plaid Link metadata (non-secret). We forward
// only institution_id / name when present; anything else is ignored.
const institutionMetaSchema = z
	.object({
		institution: z
			.object({
				institution_id: z.string().optional(),
				name: z.string().optional()
			})
			.nullish()
	})
	.partial();

export function extractInstitution(metadata: unknown): {
	institutionId?: string;
	institutionName?: string;
} {
	const parsed = institutionMetaSchema.safeParse(metadata);
	if (!parsed.success || !parsed.data.institution) return {};
	const { institution_id, name } = parsed.data.institution;
	return {
		...(institution_id ? { institutionId: institution_id } : {}),
		...(name ? { institutionName: name } : {})
	};
}

// ── Pure payload builders (SC3-C1 seam — env-free, deterministic, unit-tested) ─────────
export function buildLinkTokenPayload(ownerUserId: string): { ownerUserId: string } {
	return { ownerUserId };
}

/**
 * Builds the leg-2 worker payload. `ownerUserId` is ALWAYS the caller-supplied
 * (session-derived) value — the validated body cannot influence it (SC3-C1). The body
 * is already `.strict()`-validated upstream, so it can carry only { public_token, metadata }.
 */
export function buildExchangePayload(
	ownerUserId: string,
	validatedBody: { public_token: string; metadata?: unknown }
): {
	public_token: string;
	ownerUserId: string;
	institutionId?: string;
	institutionName?: string;
} {
	const inst = extractInstitution(validatedBody.metadata);
	return {
		public_token: validatedBody.public_token,
		ownerUserId, // session-derived arg — NEVER from validatedBody
		...(inst.institutionId ? { institutionId: inst.institutionId } : {}),
		...(inst.institutionName ? { institutionName: inst.institutionName } : {})
	};
}

// ── Upstream status → browser status mapping (SELF-197 failure-mapping AC) ──────────────
// worker 4xx (bad/burned request) → 400 client-correctable; worker 5xx (Plaid/admission
// failure, incl. the worker's 502 envelope) → 500 generic; anything else non-2xx (401
// secret-mismatch, 404/405 routing) is an internal misconfig that must never leak → 500.
export function mapUpstreamStatus(status: number): number {
	if (status === 400 || status === 413) return 400;
	return 500;
}

// ── Transport (fetch + timeout; the ONLY env/network-touching surface) ─────────────────
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
			console.error(`[plaid-admission] worker ${path} returned ${res.status}`);
		}
		return { transportOk: true, status: res.status, json };
	} catch {
		// Network error / DNS / connection refused / timeout-abort → worker unreachable.
		console.error(`[plaid-admission] worker ${path} unreachable (transport failure)`);
		return { transportOk: false };
	} finally {
		clearTimeout(timer);
	}
}

// ── Leg 1 — link_token mint ────────────────────────────────────────────────────────────
export async function mintLinkToken(ownerUserId: string): Promise<LegOutcome<LinkTokenData>> {
	const call = await callWorker(LINK_TOKEN_PATH, buildLinkTokenPayload(ownerUserId));
	if (!call.transportOk) return { ok: false, status: 502 }; // worker unreachable → bad gateway
	if (call.status === 200) {
		const parsed = workerLinkTokenResponseSchema.safeParse(call.json);
		if (!parsed.success) return { ok: false, status: 502 }; // malformed upstream
		return { ok: true, data: parsed.data };
	}
	return { ok: false, status: mapUpstreamStatus(call.status) };
}

// ── Leg 2 — public_token exchange + admission ──────────────────────────────────────────
export async function exchangePublicToken(
	ownerUserId: string,
	validatedBody: { public_token: string; metadata?: unknown }
): Promise<LegOutcome<ExchangeData>> {
	// C6-4: a burned public_token must NOT be retried here — a single attempt; on failure
	// we surface the status so the browser re-runs Link for a fresh token.
	const call = await callWorker(EXCHANGE_PATH, buildExchangePayload(ownerUserId, validatedBody));
	if (!call.transportOk) return { ok: false, status: 502 };
	if (call.status === 200) {
		const parsed = workerExchangeResponseSchema.safeParse(call.json);
		if (!parsed.success) return { ok: false, status: 502 };
		// Drop sourceId (internal pfin id) — browser routes on account_id.
		return { ok: true, data: { accounts: parsed.data.accounts } };
	}
	return { ok: false, status: mapUpstreamStatus(call.status) };
}
