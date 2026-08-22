// purchase.test.ts — SELF-325 manual purchase-path schema coverage (node env).
// Locks the Lock-14 boundary: `.strict()` per mode, the numeric battery (currency + quantity),
// the BIND/MINT discriminated-union fork, real-date guarding, and the MINT asset_type vocabulary
// (excludes 'currency' — the RPC's one explicit rejection).

import { describe, it, expect } from 'vitest';
import { createPurchaseSchema, fieldErrors } from './purchase';

const BASE = {
	trade_date: '2026-08-15',
	quantity: '10',
	cost_basis: '1500.00',
	sub_cat_id: '',
	description: '',
	note: ''
};

describe('createPurchaseSchema — BIND mode', () => {
	it('accepts a valid bind purchase', () => {
		const r = createPurchaseSchema.safeParse({ mode: 'bind', security_id: '501', ...BASE });
		expect(r.success).toBe(true);
		if (r.success && r.data.mode === 'bind') {
			expect(r.data.security_id).toBe(501);
			expect(r.data.quantity).toBe(10);
			expect(r.data.cost_basis).toBe(1500);
			expect(r.data.sub_cat_id).toBeNull();
		}
	});

	it('rejects a zero or negative quantity', () => {
		for (const quantity of ['0', '-5']) {
			const r = createPurchaseSchema.safeParse({ mode: 'bind', security_id: '501', ...BASE, quantity });
			expect(r.success).toBe(false);
		}
	});

	it('rejects a zero or negative cost_basis', () => {
		for (const cost_basis of ['0', '-100']) {
			const r = createPurchaseSchema.safeParse({ mode: 'bind', security_id: '501', ...BASE, cost_basis });
			expect(r.success).toBe(false);
		}
	});

	it('rejects NaN / Infinity / scientific / currency-string quantity and cost_basis (numeric battery)', () => {
		for (const bad of ['NaN', 'Infinity', '1e5', '$50', '1,500.00', 'abc']) {
			expect(createPurchaseSchema.safeParse({ mode: 'bind', security_id: '501', ...BASE, quantity: bad }).success).toBe(
				false
			);
			expect(
				createPurchaseSchema.safeParse({ mode: 'bind', security_id: '501', ...BASE, cost_basis: bad }).success
			).toBe(false);
		}
	});

	it('accepts up to 8 decimal places on quantity (fractional/crypto)', () => {
		const r = createPurchaseSchema.safeParse({ mode: 'bind', security_id: '501', ...BASE, quantity: '0.12345678' });
		expect(r.success).toBe(true);
	});

	it('rejects a non-real calendar date', () => {
		const r = createPurchaseSchema.safeParse({ mode: 'bind', security_id: '501', ...BASE, trade_date: '2026-02-31' });
		expect(r.success).toBe(false);
	});

	it('rejects a missing/invalid security_id', () => {
		expect(createPurchaseSchema.safeParse({ mode: 'bind', ...BASE }).success).toBe(false);
		expect(createPurchaseSchema.safeParse({ mode: 'bind', security_id: '-1', ...BASE }).success).toBe(false);
	});

	it('rejects an asset_type field on a bind submission (mass-assignment / mode confusion)', () => {
		const r = createPurchaseSchema.safeParse({
			mode: 'bind',
			security_id: '501',
			asset_type: 'equity',
			...BASE
		});
		expect(r.success).toBe(false);
	});

	it('accepts an optional sub_cat_id and note/description', () => {
		const r = createPurchaseSchema.safeParse({
			mode: 'bind',
			security_id: '501',
			...BASE,
			sub_cat_id: '7',
			description: 'Opened a position',
			note: 'via broker transfer'
		});
		expect(r.success).toBe(true);
		if (r.success && r.data.mode === 'bind') {
			expect(r.data.sub_cat_id).toBe(7);
			expect(r.data.description).toBe('Opened a position');
		}
	});
});

describe('createPurchaseSchema — MINT mode', () => {
	it('accepts a valid mint purchase (e.g. real_estate)', () => {
		const r = createPurchaseSchema.safeParse({
			mode: 'mint',
			asset_type: 'real_estate',
			asset_name: 'Rental House',
			symbol: '',
			...BASE
		});
		expect(r.success).toBe(true);
		if (r.success && r.data.mode === 'mint') {
			expect(r.data.asset_type).toBe('real_estate');
			expect(r.data.asset_name).toBe('Rental House');
			expect(r.data.symbol).toBeNull();
		}
	});

	it('rejects asset_type = currency (the RPC\'s one explicit MINT rejection)', () => {
		const r = createPurchaseSchema.safeParse({
			mode: 'mint',
			asset_type: 'currency',
			asset_name: 'Cash',
			symbol: '',
			...BASE
		});
		expect(r.success).toBe(false);
	});

	it('rejects an empty asset_name', () => {
		const r = createPurchaseSchema.safeParse({
			mode: 'mint',
			asset_type: 'vehicle',
			asset_name: '',
			symbol: '',
			...BASE
		});
		expect(r.success).toBe(false);
		if (!r.success) expect(fieldErrors(r.error)).toHaveProperty('asset_name');
	});

	it('rejects a security_id field on a mint submission (mode confusion)', () => {
		const r = createPurchaseSchema.safeParse({
			mode: 'mint',
			asset_type: 'vehicle',
			asset_name: 'Truck',
			symbol: '',
			security_id: '501',
			...BASE
		});
		expect(r.success).toBe(false);
	});

	it('rejects an asset_type outside MINT_ASSET_TYPES', () => {
		const r = createPurchaseSchema.safeParse({
			mode: 'mint',
			asset_type: 'nonsense',
			asset_name: 'X',
			symbol: '',
			...BASE
		});
		expect(r.success).toBe(false);
	});

	it('accepts every MINT_ASSET_TYPES value', () => {
		const types = [
			'equity',
			'etf',
			'fund',
			'money_market',
			'bond',
			'future',
			'option',
			'crypto',
			'real_estate',
			'vehicle',
			'metal',
			'collectible',
			'private'
		];
		for (const asset_type of types) {
			const r = createPurchaseSchema.safeParse({ mode: 'mint', asset_type, asset_name: 'X', symbol: '', ...BASE });
			expect(r.success).toBe(true);
		}
	});
});

describe('createPurchaseSchema — mode discriminator', () => {
	it('rejects an unknown mode', () => {
		const r = createPurchaseSchema.safeParse({ mode: 'other', ...BASE });
		expect(r.success).toBe(false);
	});

	it('rejects a missing mode', () => {
		const r = createPurchaseSchema.safeParse({ ...BASE });
		expect(r.success).toBe(false);
	});
});
