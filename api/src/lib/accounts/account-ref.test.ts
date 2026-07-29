// account-ref.test.ts — the canonical AccountRef + the subtype→account_type recommendation
// (SELF-199). The recommendation is a UX confirm/override seed, not an authority, so these
// tests pin the mapping behaviour AND the fail-safe "unknown → undefined (user sets)" path.

import { describe, it, expect } from 'vitest';
import { accountRefSchema, recommendAccountType, isKnownAccountType } from './account-ref';
import { ACCOUNT_TYPES } from '$lib/schemas/account-constants';

describe('accountRefSchema (canonical)', () => {
	it('accepts a Plaid-shaped ref (mask, no currency)', () => {
		const r = accountRefSchema.parse({
			account_id: 'plaid_abc',
			name: 'Checking',
			type: 'depository',
			subtype: 'checking',
			mask: '1234'
		});
		expect(r.account_id).toBe('plaid_abc');
		expect(r.mask).toBe('1234');
	});

	it('accepts a SimpleFIN-shaped ref (currency, no mask, type unknown)', () => {
		const r = accountRefSchema.parse({
			account_id: 'sf_1',
			name: 'Fidelity',
			type: 'unknown',
			currency: 'USD'
		});
		expect(r.currency).toBe('USD');
		expect(r.mask).toBeUndefined();
	});

	it('requires a non-empty account_id (the join key)', () => {
		expect(accountRefSchema.safeParse({ account_id: '' }).success).toBe(false);
	});
});

describe('recommendAccountType', () => {
	it('maps common Plaid subtypes to the seeded ACCOUNT_TYPE', () => {
		expect(recommendAccountType({ type: 'depository', subtype: 'checking' })).toBe('depository');
		expect(recommendAccountType({ type: 'depository', subtype: 'savings' })).toBe('depository');
		expect(recommendAccountType({ type: 'investment', subtype: '401k' })).toBe('retirement');
		expect(recommendAccountType({ type: 'investment', subtype: 'ira' })).toBe('retirement');
		expect(recommendAccountType({ type: 'investment', subtype: 'brokerage' })).toBe('investment');
		expect(recommendAccountType({ type: 'credit', subtype: 'credit card' })).toBe('liability');
		expect(recommendAccountType({ type: 'loan', subtype: 'mortgage' })).toBe('liability');
	});

	it('is case/whitespace-insensitive on the provider strings', () => {
		expect(recommendAccountType({ subtype: '  Checking ' })).toBe('depository');
		expect(recommendAccountType({ type: 'CREDIT', subtype: undefined })).toBe('liability');
	});

	it('falls back to the coarse type when the subtype is unmapped', () => {
		expect(recommendAccountType({ type: 'investment', subtype: 'some-new-subtype' })).toBe(
			'investment'
		);
	});

	it('returns undefined for SimpleFIN (type unknown, no subtype) → user sets', () => {
		expect(recommendAccountType({ type: 'unknown' })).toBeUndefined();
		expect(recommendAccountType({})).toBeUndefined();
	});

	it('only ever returns a value in ACCOUNT_TYPES', () => {
		const samples = ['checking', '401k', 'brokerage', 'credit card', 'mortgage', 'nonsense'];
		for (const subtype of samples) {
			const rec = recommendAccountType({ subtype });
			if (rec !== undefined) expect(ACCOUNT_TYPES).toContain(rec);
		}
	});
});

describe('isKnownAccountType', () => {
	it('accepts real types, rejects junk/undefined', () => {
		expect(isKnownAccountType('depository')).toBe(true);
		expect(isKnownAccountType('bogus')).toBe(false);
		expect(isKnownAccountType(undefined)).toBe(false);
	});
});
