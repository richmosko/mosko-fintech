// mfa.test.ts — unit tests for the CLIENT-SIDE TOTP code Zod mirror (SELF-291).
// Pure Zod (no DOM), mirroring the repo's flow-level unit-test pattern. Proves the client
// mirror is NOT looser than the server's schemas/mfa.ts: same .strict() posture, same
// /^\d{6}$/ shape, same trim, same message string.

import { describe, it, expect } from 'vitest';
import { totpCodeSchema, recoveryCodeSchema, fieldErrors } from './mfa';

const MSG = 'Enter the 6-digit code from your authenticator app.';
const RECOVERY_MSG = 'Enter a valid recovery code.';

describe('totpCodeSchema (client mirror)', () => {
	it('accepts exactly 6 digits', () => {
		const r = totpCodeSchema.safeParse({ code: '123456' });
		expect(r.success).toBe(true);
		if (r.success) expect(r.data.code).toBe('123456');
	});

	it('trims surrounding whitespace before validating (pasted-code tolerance)', () => {
		const r = totpCodeSchema.safeParse({ code: '  654321 ' });
		expect(r.success).toBe(true);
		if (r.success) expect(r.data.code).toBe('654321');
	});

	it.each([
		['too short', '12345'],
		['too long', '1234567'],
		['non-digits', '12ab56'],
		['empty', ''],
		['spaces between digits', '123 456']
	])('rejects a %s code', (_label, code) => {
		const r = totpCodeSchema.safeParse({ code });
		expect(r.success).toBe(false);
		if (!r.success) expect(r.error.issues[0].message).toBe(MSG);
	});

	it('is .strict() — rejects extra keys (mass-assignment fence mirror)', () => {
		// factorId / redirectTo are control fields stripped server-side BEFORE parse; the
		// client shape must reject them too so the mirror is never looser than the server.
		const r = totpCodeSchema.safeParse({ code: '123456', factorId: 'f1' });
		expect(r.success).toBe(false);
	});

	it('rejects a missing code field', () => {
		const r = totpCodeSchema.safeParse({});
		expect(r.success).toBe(false);
	});
});

describe('recoveryCodeSchema (client mirror)', () => {
	it('accepts a normalized 16-char base32 code', () => {
		const r = recoveryCodeSchema.safeParse({ code: 'abcdefgh2345mnop' });
		expect(r.success).toBe(true);
		if (r.success) expect(r.data.code).toBe('abcdefgh2345mnop');
	});

	it('normalizes the grouped display form (dashes + spaces stripped, lowercased)', () => {
		const r = recoveryCodeSchema.safeParse({ code: '  ABCD-EFGH-2345-MNOP ' });
		expect(r.success).toBe(true);
		if (r.success) expect(r.data.code).toBe('abcdefgh2345mnop');
	});

	it('tolerates loose spacing between groups', () => {
		const r = recoveryCodeSchema.safeParse({ code: 'abcd efgh 2345 mnop' });
		expect(r.success).toBe(true);
		if (r.success) expect(r.data.code).toBe('abcdefgh2345mnop');
	});

	it.each([
		['too short after normalization', 'abcd-efgh-2345'],
		['too long after normalization', 'abcdefgh2345mnopq'],
		['base32-invalid chars (0/1/8/9)', 'abcd0189ijklmnop'],
		['empty', '']
	])('rejects a %s code', (_label, code) => {
		const r = recoveryCodeSchema.safeParse({ code });
		expect(r.success).toBe(false);
		if (!r.success) expect(r.error.issues[0].message).toBe(RECOVERY_MSG);
	});

	it('is .strict() — rejects extra keys (mass-assignment fence mirror)', () => {
		const r = recoveryCodeSchema.safeParse({ code: 'abcdefgh2345mnop', users_id: 'u1' });
		expect(r.success).toBe(false);
	});

	it('rejects a missing code field', () => {
		const r = recoveryCodeSchema.safeParse({});
		expect(r.success).toBe(false);
	});
});

describe('fieldErrors', () => {
	it('keys field-level issues by field name', () => {
		const r = totpCodeSchema.safeParse({ code: 'bad' });
		expect(r.success).toBe(false);
		if (!r.success) {
			const errs = fieldErrors(r.error);
			expect(errs.code).toEqual([MSG]);
		}
	});

	it('buckets root-level (.strict) issues under _form', () => {
		const r = totpCodeSchema.safeParse({ code: '123456', extra: 1 });
		expect(r.success).toBe(false);
		if (!r.success) {
			const errs = fieldErrors(r.error);
			expect(errs._form?.length).toBeGreaterThan(0);
		}
	});
});
