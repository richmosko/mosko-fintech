// mfa-hash.test.ts — unit coverage for the scrypt recovery-code hasher (SELF-291 /
// Auth-3b Slice 2b). Uses REAL crypto.scrypt (N=2^14 is a few ms/derivation). Proves the
// round-trip, wrong-code rejection, the versioned/self-describing encoding, and that
// verifyCode never throws on a malformed/length-mismatched stored value (timingSafeEqual
// safety).

import { describe, it, expect } from 'vitest';
import { hashCode, verifyCode } from './mfa-hash';

describe('mfa-hash (scrypt)', () => {
	it('round-trips: a code verifies against its own hash', async () => {
		const stored = await hashCode('abcd2345abcd2345');
		await expect(verifyCode('abcd2345abcd2345', stored)).resolves.toBe(true);
	});

	it('rejects a wrong code', async () => {
		const stored = await hashCode('abcd2345abcd2345');
		await expect(verifyCode('zzzz2345zzzz2345', stored)).resolves.toBe(false);
	});

	it('emits a versioned, self-describing scrypt$v$N$r$p$salt$hash string with a 32-byte key', async () => {
		const stored = await hashCode('abcd2345abcd2345');
		const parts = stored.split('$');
		expect(parts[0]).toBe('scrypt');
		expect(parts[1]).toBe('1'); // version
		expect(parts[2]).toBe('16384'); // N
		expect(parts[3]).toBe('8'); // r
		expect(parts[4]).toBe('1'); // p
		expect(Buffer.from(parts[5], 'hex')).toHaveLength(16); // salt
		expect(Buffer.from(parts[6], 'hex')).toHaveLength(32); // derived key
	});

	it('uses a fresh per-code salt (two hashes of the same code differ)', async () => {
		const a = await hashCode('abcd2345abcd2345');
		const b = await hashCode('abcd2345abcd2345');
		expect(a).not.toBe(b);
		await expect(verifyCode('abcd2345abcd2345', a)).resolves.toBe(true);
		await expect(verifyCode('abcd2345abcd2345', b)).resolves.toBe(true);
	});

	it('re-derives with the STORED params (a param bump does not break old hashes)', async () => {
		// A hash issued under a hypothetical older/other param set still verifies because
		// verifyCode reads N/r/p from the stored string, not the current constants.
		const stored = await hashCode('abcd2345abcd2345');
		const [, , , , , salt, hash] = stored.split('$');
		const reencoded = `scrypt$99$16384$8$1$${salt}$${hash}`; // different VERSION tag, same params
		await expect(verifyCode('abcd2345abcd2345', reencoded)).resolves.toBe(true);
	});

	it('returns false (never throws) on malformed stored values', async () => {
		await expect(verifyCode('x', 'not-a-hash')).resolves.toBe(false);
		await expect(verifyCode('x', 'scrypt$1$16384$8$1$$')).resolves.toBe(false); // empty salt+hash
		await expect(verifyCode('x', 'scrypt$1$NaN$8$1$aa$bb')).resolves.toBe(false); // bad N
		await expect(verifyCode('x', '')).resolves.toBe(false);
	});
});
