// webhookVerify.ts — SELF-206 RT-05 Plaid-webhook signature verification (api/src, Option 1).
//
// CAPABILITY-VERIFY RECONCILIATION (read this before touching AC1):
//   The June ACs / ADR-037 said "signature-verify vs PLAID_WEBHOOK_SECRET (HMAC)". The installed
//   plaid SDK (v27) confirms Plaid's ACTUAL webhook verification is ASYMMETRIC JWT, NOT a static
//   HMAC secret: Plaid signs each webhook with an ES256 JWT in the `Plaid-Verification` header; the
//   PUBLIC key (an EC/P-256 JWK) is fetched by `kid` from Plaid's `/webhook_verification_key/get`.
//   There is NO `PLAID_WEBHOOK_SECRET` primitive in Plaid's model. F/CTO-ratified Option 1: the
//   credentialed JWK *fetch* is delegated to the worker (which alone holds PLAID_CLIENT_ID/SECRET —
//   api/src is credential-less by design); api/src verifies the JWT + body-hash LOCALLY here with
//   the returned PUBLIC key. This is the correct RT-05 satisfaction (ADR-037 AC1 amended same-PR).
//
// SEC V1-SHIP-BLOCK mods enforced here:
//   M1  ES256 alg-pinning — reject alg:none / RS256 / HS256 / anything but ES256 (both at the
//       header pre-check AND via jwtVerify's `algorithms` allowlist — belt + suspenders).
//   M2  Body integrity over the RAW bytes — SHA-256 of the raw body, constant-time compared to the
//       JWT's `request_body_sha256` claim. The handler reads the raw body BEFORE any JSON parse.
//   M3  Bounded `iat` freshness (default 300s) as a replay window; the provider_event_id UNIQUE
//       gate (handler side) is the authoritative replay backstop — iat alone is NOT sufficient.
//   M7  JWK cache hygiene: bounded (size + TTL), keyed by kid; an unknown kid triggers a FRESH
//       credentialed fetch (Plaid rotates keys). Cache values come ONLY from the credentialed
//       fetch — NEVER from the untrusted JWT header/body.
//
// FAIL-CLOSED: any missing header / bad alg / unknown kid unfetchable / bad signature / stale iat /
// body-hash mismatch → { ok:false }. The handler maps that to 401 with NO writes (AC1).

import { createHash, timingSafeEqual } from 'node:crypto';
import { decodeProtectedHeader, importJWK, jwtVerify, type JWK } from 'jose';

/** The verified, trusted claims we carry forward (only what the handler needs). */
export interface PlaidWebhookClaims {
	/** JWT issued-at (unix seconds) — freshness + half of the replay-id (M3). */
	iat: number;
	/** Hex SHA-256 of the raw body, as signed by Plaid (M2) — the other half of the replay-id. */
	requestBodySha256: string;
	/** Key id the JWT was signed with (forensic). */
	kid: string;
}

export type VerifyResult =
	| { ok: true; claims: PlaidWebhookClaims }
	| { ok: false; reason: string };

/** Injected credentialed JWK fetch (worker admission route). MUST return a PUBLIC JWK. */
export type FetchJwk = (kid: string) => Promise<JWK>;

// ── M7: bounded, TTL'd JWK cache keyed by kid ──────────────────────────────────────────────
const JWK_CACHE_TTL_MS = 60 * 60 * 1000; // 1h — Plaid keys rotate slowly; unknown kid refetches anyway.
const JWK_CACHE_MAX = 32; // hard bound (a handful of live kids at most; FIFO-evict beyond this).

interface CachedJwk {
	jwk: JWK;
	fetchedAt: number;
}

/**
 * A bounded, TTL'd JWK cache. Values ONLY ever come from the credentialed `fetchJwk` (never the
 * JWT). An unknown / expired kid triggers a fresh fetch. `now` is injectable for tests.
 */
export class JwkCache {
	private readonly map = new Map<string, CachedJwk>();
	constructor(
		private readonly fetchJwk: FetchJwk,
		private readonly ttlMs: number = JWK_CACHE_TTL_MS,
		private readonly max: number = JWK_CACHE_MAX
	) {}

	async get(kid: string, now: number = Date.now()): Promise<JWK> {
		const hit = this.map.get(kid);
		if (hit && now - hit.fetchedAt < this.ttlMs) return hit.jwk;
		// Miss / expired → credentialed refetch. A throw here propagates → verify fails closed.
		const jwk = await this.fetchJwk(kid);
		this.map.set(kid, { jwk, fetchedAt: now });
		// FIFO eviction to keep the cache bounded (Map preserves insertion order).
		while (this.map.size > this.max) {
			const oldest = this.map.keys().next().value;
			if (oldest === undefined) break;
			this.map.delete(oldest);
		}
		return jwk;
	}
}

/** Constant-time hex-string compare (both sides fixed-length SHA-256 hex = 64 chars). Length
 *  mismatch → false BEFORE timingSafeEqual (which throws on unequal lengths / would leak a
 *  length oracle). */
function constantTimeHexEqual(a: string, b: string): boolean {
	if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
	const ab = Buffer.from(a, 'utf8');
	const bb = Buffer.from(b, 'utf8');
	if (ab.length !== bb.length) return false;
	return timingSafeEqual(ab, bb);
}

/**
 * Verify a Plaid webhook. `rawBody` MUST be the exact raw body string the handler read BEFORE any
 * JSON parse (M2). `verificationHeader` is the `Plaid-Verification` header value (the JWT).
 * Returns the trusted claims on success; { ok:false } (fail-closed) otherwise. NEVER throws —
 * every failure mode maps to { ok:false } so the handler uniformly 401s with no writes.
 */
export async function verifyPlaidWebhook(
	rawBody: string,
	verificationHeader: string | null | undefined,
	opts: { cache: JwkCache; now?: number; maxAgeSeconds?: number }
): Promise<VerifyResult> {
	const now = opts.now ?? Date.now();
	const maxAgeSeconds = opts.maxAgeSeconds ?? 300; // M3: 5-minute freshness window.

	if (typeof verificationHeader !== 'string' || verificationHeader.length === 0) {
		return { ok: false, reason: 'missing_verification_header' };
	}

	// M1 (pre-check): inspect the UNVERIFIED header only to read alg + kid for key selection.
	// We hard-reject any non-ES256 alg HERE (before touching a key) so a downgrade (alg:none /
	// HS256 with the JWK's public bytes as an HMAC key / RS256) can never proceed.
	let header: { alg?: string; kid?: string };
	try {
		header = decodeProtectedHeader(verificationHeader);
	} catch {
		return { ok: false, reason: 'undecodable_header' };
	}
	if (header.alg !== 'ES256') return { ok: false, reason: 'bad_alg' };
	if (typeof header.kid !== 'string' || header.kid.length === 0) {
		return { ok: false, reason: 'missing_kid' };
	}
	const kid = header.kid;

	// M7: the key comes ONLY from the credentialed fetch (via the bounded cache), keyed by the
	// header kid. A fetch failure (worker/Plaid unreachable) → fail closed (Plaid retries).
	let key: Awaited<ReturnType<typeof importJWK>>;
	try {
		const jwk = await opts.cache.get(kid, now);
		key = await importJWK(jwk, 'ES256');
	} catch {
		return { ok: false, reason: 'key_unavailable' };
	}

	// Verify signature — M1 (allowlist): `algorithms:['ES256']` is the second, authoritative alg
	// pin (jose rejects any token whose alg is not in this set, independent of the pre-check).
	let payload: Record<string, unknown>;
	try {
		const res = await jwtVerify(verificationHeader, key, { algorithms: ['ES256'] });
		payload = res.payload as Record<string, unknown>;
	} catch {
		return { ok: false, reason: 'bad_signature' };
	}

	// M3: bounded iat freshness. `iat` is signed; a stale/absent iat is rejected (replay window).
	const iat = typeof payload.iat === 'number' ? payload.iat : Number.NaN;
	if (!Number.isFinite(iat)) return { ok: false, reason: 'missing_iat' };
	const ageSeconds = now / 1000 - iat;
	if (ageSeconds > maxAgeSeconds || ageSeconds < -maxAgeSeconds) {
		return { ok: false, reason: 'stale_iat' };
	}

	// M2: raw-body integrity. The signed `request_body_sha256` claim must equal SHA-256(raw body).
	const claimHash = payload.request_body_sha256;
	if (typeof claimHash !== 'string' || claimHash.length === 0) {
		return { ok: false, reason: 'missing_body_hash' };
	}
	const computed = createHash('sha256').update(rawBody, 'utf8').digest('hex');
	if (!constantTimeHexEqual(computed, claimHash)) {
		return { ok: false, reason: 'body_hash_mismatch' };
	}

	return { ok: true, claims: { iat, requestBodySha256: claimHash, kid } };
}

/**
 * Derive the provider_event_id (the UNIQUE idempotency / replay key on linked_source_sync_audit).
 * Both inputs come from the VERIFIED JWT claims — so it is stable per signed delivery: an exact
 * replay of the same signed request yields the same id (ON CONFLICT DO NOTHING dedups it), while a
 * genuine distinct delivery carries a fresh `iat` and is processed. This is the M3 "authoritative
 * replay backstop" (iat freshness is the coarse window; this is the exact gate).
 */
export function deriveProviderEventId(claims: PlaidWebhookClaims): string {
	return `plaid:${claims.iat}:${claims.requestBodySha256}`;
}
