// transaction.test.ts — SELF-202 manual cash-transaction schema coverage (node env).
// Locks the Lock-14 security boundary at the input layer: `.strict()` (mass-assignment),
// the numeric battery (type-confusion), the signed/non-zero amount contract, real-date
// guarding, and the split-set shape (min-2 balanced lines). NO skip/exclusion field exists
// anywhere (ADR-032) — asserted by the .strict() extra-key rejections.

import { describe, it, expect } from 'vitest';
import {
	manualTransCreateSchema,
	manualTransEditSchema,
	recategorizeSchema,
	splitSetSchema,
	unsplitSchema,
	fieldErrors
} from './transaction';

describe('manualTransCreateSchema', () => {
	it('accepts a valid signed cash entry (negative outflow) + optional category/note', () => {
		const r = manualTransCreateSchema.safeParse({
			transaction_date: '2026-07-20',
			amount: '-54.32',
			vendor: 'Costco',
			description: 'weekly groceries',
			sub_cat_id: '7',
			note: 'membership run'
		});
		expect(r.success).toBe(true);
		if (r.success) {
			expect(r.data.amount).toBe(-54.32);
			expect(r.data.sub_cat_id).toBe(7);
		}
	});

	it('accepts a bare uncategorized entry (empty sub_cat / note → null)', () => {
		const r = manualTransCreateSchema.safeParse({
			transaction_date: '2026-07-20',
			amount: '12.00',
			vendor: '',
			description: '',
			sub_cat_id: '',
			note: ''
		});
		expect(r.success).toBe(true);
		if (r.success) {
			expect(r.data.sub_cat_id).toBeNull();
			expect(r.data.vendor).toBeNull();
			expect(r.data.note).toBeNull();
		}
	});

	it('rejects a zero amount (a transaction must move money)', () => {
		const r = manualTransCreateSchema.safeParse({ transaction_date: '2026-07-20', amount: '0' });
		expect(r.success).toBe(false);
		if (!r.success) expect(fieldErrors(r.error)).toHaveProperty('amount');
	});

	it('rejects NaN / Infinity / scientific / currency-string amounts (numeric battery)', () => {
		for (const amount of ['NaN', 'Infinity', '1e5', '$50', '1,500.00', 'abc']) {
			const r = manualTransCreateSchema.safeParse({ transaction_date: '2026-07-20', amount });
			expect(r.success, `amount=${amount} must be rejected`).toBe(false);
		}
	});

	it('rejects an impossible calendar date', () => {
		const r = manualTransCreateSchema.safeParse({ transaction_date: '2026-02-31', amount: '1' });
		expect(r.success).toBe(false);
		if (!r.success) expect(fieldErrors(r.error)).toHaveProperty('transaction_date');
	});

	it('.strict() rejects an unknown key (mass-assignment fence; incl. any "skip"/exclusion field)', () => {
		const r = manualTransCreateSchema.safeParse({
			transaction_date: '2026-07-20',
			amount: '1',
			is_excluded: true,
			transaction_type: 'malicious'
		});
		expect(r.success).toBe(false);
	});
});

describe('manualTransEditSchema (reverse-and-replace)', () => {
	it('requires a positive original trans id', () => {
		const ok = manualTransEditSchema.safeParse({ orig_trans_id: '42', transaction_date: '2026-07-20', amount: '-5' });
		expect(ok.success).toBe(true);
		const bad = manualTransEditSchema.safeParse({ orig_trans_id: '0', transaction_date: '2026-07-20', amount: '-5' });
		expect(bad.success).toBe(false);
	});
});

describe('recategorizeSchema (023 annotation upsert)', () => {
	it('accepts a clear (null sub_cat + null note)', () => {
		const r = recategorizeSchema.safeParse({ trans_id: '9', sub_cat_id: '', note: '' });
		expect(r.success).toBe(true);
		if (r.success) {
			expect(r.data.sub_cat_id).toBeNull();
			expect(r.data.note).toBeNull();
		}
	});
});

describe('splitSetSchema', () => {
	it('accepts a ≥2-line set with signed amounts', () => {
		const r = splitSetSchema.safeParse({
			trans_id: '10',
			lines: [
				{ amount: '-100.00', sub_cat_id: '3' },
				{ amount: '-120.00', sub_cat_id: '4', note: 'household', display_order: '2' }
			]
		});
		expect(r.success).toBe(true);
		if (r.success) {
			expect(r.data.lines).toHaveLength(2);
			expect(r.data.lines[0].amount).toBe(-100);
		}
	});

	it('rejects a single-line split (a 1-line split is just the parent)', () => {
		const r = splitSetSchema.safeParse({ trans_id: '10', lines: [{ amount: '-100.00' }] });
		expect(r.success).toBe(false);
		if (!r.success) expect(fieldErrors(r.error)).toHaveProperty('lines');
	});

	it('rejects a line with a non-finite / zero amount', () => {
		expect(splitSetSchema.safeParse({ trans_id: '1', lines: [{ amount: '0' }, { amount: '-1' }] }).success).toBe(false);
		expect(splitSetSchema.safeParse({ trans_id: '1', lines: [{ amount: 'NaN' }, { amount: '-1' }] }).success).toBe(false);
	});

	it('.strict() rejects an unknown key on a split line', () => {
		const r = splitSetSchema.safeParse({
			trans_id: '1',
			lines: [{ amount: '-1', is_excluded: true }, { amount: '-1' }]
		});
		expect(r.success).toBe(false);
	});
});

describe('unsplitSchema', () => {
	it('needs only a positive trans id', () => {
		expect(unsplitSchema.safeParse({ trans_id: '5' }).success).toBe(true);
		expect(unsplitSchema.safeParse({ trans_id: '5', extra: 1 }).success).toBe(false);
	});
});
