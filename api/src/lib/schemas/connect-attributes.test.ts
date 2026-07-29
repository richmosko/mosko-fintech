// connect-attributes.test.ts — the CLIENT-side .strict() mirror for the SELF-199 attribute
// submit. Pins the discipline that matters: .strict() (no mass-assignment), the value-sets,
// the 1..200 bounds, and the envelope-level guards (linked_source_id present, ≥1 account).
// This mirror must never be looser than Backend's server schema.

import { describe, it, expect } from 'vitest';
import {
	connectAccountAttributesSchema,
	connectAttributesSubmitSchema
} from './connect-attributes';

const validAccount = {
	account_id: 'plaid_abc',
	name: 'Vanguard brokerage',
	scope: 'Rich personal',
	tax_treatment: 'taxable',
	account_type: 'investment'
};

describe('connectAccountAttributesSchema', () => {
	it('accepts a well-formed attribute set', () => {
		expect(connectAccountAttributesSchema.safeParse(validAccount).success).toBe(true);
	});

	it('is .strict() — rejects an unexpected key (mass-assignment fence)', () => {
		const res = connectAccountAttributesSchema.safeParse({ ...validAccount, is_active: false });
		expect(res.success).toBe(false);
	});

	it('rejects an out-of-set tax_treatment / account_type', () => {
		expect(
			connectAccountAttributesSchema.safeParse({ ...validAccount, tax_treatment: 'roth' }).success
		).toBe(false);
		expect(
			connectAccountAttributesSchema.safeParse({ ...validAccount, account_type: 'checking' })
				.success
		).toBe(false);
	});

	it('enforces name/scope 1..200 and a non-empty account_id', () => {
		expect(connectAccountAttributesSchema.safeParse({ ...validAccount, name: '' }).success).toBe(
			false
		);
		expect(
			connectAccountAttributesSchema.safeParse({ ...validAccount, scope: 'x'.repeat(201) }).success
		).toBe(false);
		expect(
			connectAccountAttributesSchema.safeParse({ ...validAccount, account_id: '' }).success
		).toBe(false);
	});

	it('trims and re-checks name/scope (whitespace-only fails min(1))', () => {
		expect(connectAccountAttributesSchema.safeParse({ ...validAccount, scope: '   ' }).success).toBe(
			false
		);
	});
});

describe('connectAttributesSubmitSchema (envelope)', () => {
	const env = { linked_source_id: '42', accounts: [validAccount] };

	it('accepts a well-formed envelope', () => {
		expect(connectAttributesSubmitSchema.safeParse(env).success).toBe(true);
	});

	it('requires a numeric-string linked_source_id (bigint, not UUID)', () => {
		expect(
			connectAttributesSubmitSchema.safeParse({ ...env, linked_source_id: '' }).success
		).toBe(false);
		// A UUID-shaped value must be rejected — source_id is a bigint decimal string.
		expect(
			connectAttributesSubmitSchema.safeParse({
				...env,
				linked_source_id: 'a1b2c3d4-0000-0000-0000-000000000000'
			}).success
		).toBe(false);
	});

	it('caps the accounts array at 100 (never looser than the server)', () => {
		const many = Array.from({ length: 101 }, (_, i) => ({
			...validAccount,
			account_id: `acct_${i}`
		}));
		expect(connectAttributesSubmitSchema.safeParse({ ...env, accounts: many }).success).toBe(false);
	});

	it('rejects an empty accounts array', () => {
		expect(connectAttributesSubmitSchema.safeParse({ ...env, accounts: [] }).success).toBe(false);
	});

	it('is .strict() at the envelope level too', () => {
		expect(
			connectAttributesSubmitSchema.safeParse({ ...env, provider: 'plaid' }).success
		).toBe(false);
	});
});
