// rateLimit.ts — a tiny in-memory sliding-window rate limiter for auth surfaces.
// Backend-owned server surface (ARCH §4.1 allowlist). NO service_role, NO DB, NO migration.
//
// WHY IN-MEMORY (not a DB table like the MFA-recovery 026/027 rate-gate): password reset
// rides GoTrue's built-in flow on the anon/session client — there is deliberately NO
// service_role and NO new table here (SELF-288 scope). GoTrue ALREADY enforces the
// authoritative, cross-instance rate-limit server-side (config.toml [auth.rate_limit]
// email_sent + sign_in_sign_ups). This module is a THIN app-level guard layered ON TOP so
// the /forgot-password endpoint can hold a uniform anti-enumeration response and shed
// obvious abuse BEFORE it reaches GoTrue — it is defense-in-depth, not the sole enforcer.
//
// SINGLE-INSTANCE CAVEAT (documented for Sec): the window state is per-process. V1 deploys
// ONE api container on cax21 (ADR-011 Lock 13 3-container topology), so a single Map is the
// whole picture. The moment api/ scales horizontally this guard becomes per-instance and
// GoTrue remains the real distributed backstop — that is by design; do not treat this as a
// hard security boundary. State also resets on restart (acceptable for a coarse abuse gate).
//
// NON-ENUMERATING: keys are opaque (IP, or a SHA-256 of the normalized email — never the
// raw address in memory). A 429 is keyed on the REQUESTER's own attempt volume, not on
// whether any account exists, so it leaks nothing about registration status.

import { createHash } from 'node:crypto';

/** A single limiter rule. */
export interface RateRule {
	/** Max events permitted within `windowMs` before the key is limited. */
	max: number;
	/** Trailing window length in milliseconds. */
	windowMs: number;
}

interface Bucket {
	/** Ascending event timestamps (ms) still inside the trailing window. */
	hits: number[];
}

// Module-level store. Keyed by `${scope}:${id}`; pruned lazily on access + opportunistically
// swept so a burst of one-shot keys cannot grow unbounded.
const store = new Map<string, Bucket>();
let lastSweep = 0;
const SWEEP_INTERVAL_MS = 5 * 60 * 1000;

/** Opportunistic global prune: drop buckets whose newest hit is older than `maxAgeMs`. */
function maybeSweep(now: number, maxAgeMs: number): void {
	if (now - lastSweep < SWEEP_INTERVAL_MS) return;
	lastSweep = now;
	for (const [key, bucket] of store) {
		const newest = bucket.hits[bucket.hits.length - 1] ?? 0;
		if (now - newest > maxAgeMs) store.delete(key);
	}
}

/**
 * Check-and-consume against a rule. Returns `{ limited: false }` and records the hit when
 * under the cap; returns `{ limited: true, retryAfterMs }` WITHOUT recording when at/over
 * the cap (so a limited caller cannot push the window forward indefinitely). Atomic within
 * the single-threaded event loop: prune → count → decide → (maybe) record happens with no
 * intervening await.
 */
export function consumeRateLimit(
	scope: string,
	id: string,
	rule: RateRule,
	now: number = Date.now()
): { limited: boolean; retryAfterMs: number } {
	const key = `${scope}:${id}`;
	maybeSweep(now, rule.windowMs);

	const bucket = store.get(key) ?? { hits: [] };
	const cutoff = now - rule.windowMs;
	// Drop timestamps that have aged out of the trailing window.
	const hits = bucket.hits.filter((t) => t > cutoff);

	if (hits.length >= rule.max) {
		// Oldest surviving hit dictates when a slot frees up.
		const retryAfterMs = Math.max(0, hits[0] + rule.windowMs - now);
		store.set(key, { hits }); // persist the prune
		return { limited: true, retryAfterMs };
	}

	hits.push(now);
	store.set(key, { hits });
	return { limited: false, retryAfterMs: 0 };
}

/**
 * Stable, non-reversible key for an email so the raw address is never a Map key. Email is
 * expected already-normalized (trim+lowercase) by the Zod `emailField()`; we hash the
 * normalized form so the same identity always maps to the same bucket.
 */
export function emailKey(normalizedEmail: string): string {
	return createHash('sha256').update(normalizedEmail).digest('hex');
}

/** Test-only: clear all limiter state between cases. */
export function __resetRateLimitForTests(): void {
	store.clear();
	lastSweep = 0;
}
