// sharedSecret.ts — CA-6 / C6-6 (Sec SELF-212) constant-time shared-secret verification.
//
// BOTH admission legs (leg-1 link_token mint + leg-2 exchange/admit) sit behind the SAME
// shared secret; leg-1 is NOT "less protected" for being stateless (link_token mint is a
// Plaid cost-abuse vector — C6-6). The secret is `WORKER_ADMISSION_SHARED_SECRET`, a NEW
// high-entropy production-only secret provisioned by DevOps on both api/src and the worker
// (NOT the Supabase service-role key / its env var — RT-26 allowlist unchanged).
//
// Verification is CONSTANT-TIME and FAIL-CLOSED on absent/mismatch (C6-2 / CA-6): no timing
// oracle, no verbose reject. We compare fixed-length SHA-256 digests of both sides so the
// compare is independent of input length (crypto.timingSafeEqual requires equal-length
// buffers and would otherwise throw / leak a length oracle). An absent/empty presented
// secret short-circuits to false BEFORE any compare.

import { createHash, timingSafeEqual } from 'node:crypto';

/**
 * Constant-time equality for a presented secret vs the expected secret. Returns false (fail
 * closed) when `presented` is absent/empty. Length-independent: both sides are reduced to a
 * 32-byte SHA-256 digest before the timing-safe compare, so neither the content nor the
 * length of `presented` leaks through timing.
 */
export function verifySharedSecret(presented: string | undefined | null, expected: string): boolean {
	if (typeof presented !== 'string' || presented.length === 0) return false;
	if (typeof expected !== 'string' || expected.length === 0) return false;
	const a = createHash('sha256').update(presented, 'utf8').digest();
	const b = createHash('sha256').update(expected, 'utf8').digest();
	return timingSafeEqual(a, b);
}

/** The header the internal caller (api/src) presents the shared secret in. Lower-case: Node
 *  normalizes incoming header names to lower-case. */
export const ADMISSION_SECRET_HEADER = 'x-worker-admission-secret';
