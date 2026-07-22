// mfa-hash.ts — recovery-code hashing (SELF-291 / Auth-3b Slice 2b).
// Backend-owned server surface (ARCH §4.1 allowlist).
//
// ALGO-OF-RECORD: Node built-in **scrypt** (zero-dependency; F/CTO + Sec ratified the
// pivot from bcryptjs 2026-07-22). The `026` column comment says "bcrypt/argon2" — it
// PREDATES this pivot; **scrypt is the algo-of-record per the ADR-030 amendment**
// (Architect authors that amendment; this module is the code home).
//
// Sec spec (ratified):
//   · ASYNC scrypt (promisified) — NOT scryptSync. It is CPU+memory-intensive and
//     redemption runs up to ~10 derivations; async keeps it on the libuv threadpool
//     instead of blocking the event loop. (Recovery is rare + rate-limited → latency fine.)
//   · Params v1: N=16384 (2^14), r=8, p=1, keylen=32; a fresh 16-byte CSPRNG salt PER code
//     (scrypt does not auto-salt like bcrypt). N=2^14 keeps memory ≈ 128·N·r ≈ 16 MB
//     under the 32 MB default maxmem — no maxmem bump (Sec: do NOT go N≥2^16 here).
//   · The salt + params are stored WITH each hash in a VERSIONED encoded string, so a
//     future param change cannot silently break verification of already-issued codes —
//     verify re-derives with the STORED salt+params, not the current constants.
//   · Constant-time compare: `timingSafeEqual` THROWS on length mismatch, so we always
//     compare fixed-length (keylen-byte) derived keys — derive the candidate to the
//     STORED hash's byte-length, and guard a malformed stored value before comparing.

import { randomBytes, scrypt as scryptCb, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(scryptCb) as (
	password: string,
	salt: Buffer,
	keylen: number,
	options: { N: number; r: number; p: number }
) => Promise<Buffer>;

/** Versioned scrypt parameters. Bump `V` (and keep old versions verifiable) on any change. */
const V = 1;
const PARAMS = { N: 16384, r: 8, p: 1 } as const;
const KEYLEN = 32;
const SALT_BYTES = 16;

/**
 * Hash a recovery code. Returns a self-describing, versioned string:
 *   `scrypt$<v>$<N>$<r>$<p>$<saltHex>$<hashHex>`
 * Plaintext is never stored/logged — only this string is persisted in code_hash.
 */
export async function hashCode(code: string): Promise<string> {
	const salt = randomBytes(SALT_BYTES);
	const dk = await scrypt(code, salt, KEYLEN, PARAMS);
	return `scrypt$${V}$${PARAMS.N}$${PARAMS.r}$${PARAMS.p}$${salt.toString('hex')}$${dk.toString('hex')}`;
}

/**
 * Verify a code against a stored hash. Re-derives with the STORED salt + params (never the
 * current constants — so already-issued codes keep verifying across a param bump), then
 * does a constant-time compare of equal-length derived keys. Returns false on any malformed
 * stored value (never throws).
 */
export async function verifyCode(code: string, stored: string): Promise<boolean> {
	try {
		const parts = stored.split('$');
		// scrypt $ v $ N $ r $ p $ salt $ hash  → 7 parts
		if (parts.length !== 7 || parts[0] !== 'scrypt') return false;
		const N = Number(parts[1 + 1]);
		const r = Number(parts[1 + 2]);
		const p = Number(parts[1 + 3]);
		if (!Number.isInteger(N) || !Number.isInteger(r) || !Number.isInteger(p)) return false;
		const salt = Buffer.from(parts[5], 'hex');
		const expected = Buffer.from(parts[6], 'hex');
		if (salt.length === 0 || expected.length === 0) return false;
		// Derive to the STORED hash's byte length so timingSafeEqual never hits a length mismatch.
		const dk = await scrypt(code, salt, expected.length, { N, r, p });
		if (dk.length !== expected.length) return false; // defensive
		return timingSafeEqual(dk, expected);
	} catch {
		return false;
	}
}
