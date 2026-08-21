// purchase.test.ts — SELF-325 manual-purchase client Zod mirror (schemas/purchase.ts).
// EXPECTED-CONTRACT caveat: this mirrors 088's own CONTRACT block + RAISES list, built
// ahead of Backend's RPC-arg schema (see purchase.ts's own header) — field names/shape
// will reconcile once Backend confirms. What IS independently verifiable here, and what
// this file asserts, is that this schema behaves the way the file's own docstrings claim:
// `.strict()` posture per branch, the BIND/MINT exclusivity, and each numeric fence 088
// itself raises on.

import { describe, it, expect } from 'vitest';
import { assetResolveSchema, manualPurchaseSchema, looksLikeTicker } from './purchase';

const validBind = {
	mode: 'bind' as const,
	security_id: '42',
	trade_date: '2026-08-21',
	quantity: '10',
	cost_basis: '1000.00',
	sub_cat_id: '',
	description: '',
	note: ''
};

const validMint = {
	mode: 'mint' as const,
	asset_type: 'real_estate',
	asset_name: '123 Main St',
	symbol: '',
	trade_date: '2026-08-21',
	quantity: '1',
	cost_basis: '250000.00',
	sub_cat_id: '',
	description: '',
	note: ''
};

describe('assetResolveSchema — mirrors Backend’s shipped server schema (7bcba2c) verbatim', () => {
	it('accepts symbol-only', () => {
		expect(
			assetResolveSchema.safeParse({ symbol: 'AAPL', cusip: '', asset_type: 'equity', name: '' })
				.success
		).toBe(true);
	});

	it('accepts cusip-only', () => {
		expect(
			assetResolveSchema.safeParse({
				symbol: '',
				cusip: '037833100',
				asset_type: 'equity',
				name: ''
			}).success
		).toBe(true);
	});

	it('rejects both blank (no identity to resolve)', () => {
		const r = assetResolveSchema.safeParse({ symbol: '', cusip: '', asset_type: 'equity', name: '' });
		expect(r.success).toBe(false);
	});

	it('rejects a malformed symbol (spaces / disallowed characters)', () => {
		expect(
			assetResolveSchema.safeParse({ symbol: 'AA PL!', cusip: '', asset_type: 'equity', name: '' })
				.success
		).toBe(false);
	});

	it('rejects a CUSIP that is not exactly 9 characters', () => {
		expect(
			assetResolveSchema.safeParse({ symbol: '', cusip: '12345', asset_type: 'equity', name: '' })
				.success
		).toBe(false);
	});

	it('.strict() rejects an unrecognized field', () => {
		const r = assetResolveSchema.safeParse({
			symbol: 'AAPL',
			cusip: '',
			asset_type: 'equity',
			name: '',
			extra: 'nope'
		});
		expect(r.success).toBe(false);
	});
});

describe('manualPurchaseSchema — BIND mode', () => {
	it('accepts a valid bind purchase', () => {
		const r = manualPurchaseSchema.safeParse(validBind);
		expect(r.success).toBe(true);
	});

	it('rejects a non-positive security_id', () => {
		expect(manualPurchaseSchema.safeParse({ ...validBind, security_id: '0' }).success).toBe(false);
	});

	it('.strict() rejects a stray MINT field on a bind submission (proves per-branch strictness, not a merged/stripped shape)', () => {
		const r = manualPurchaseSchema.safeParse({ ...validBind, asset_name: 'sneaky' });
		expect(r.success).toBe(false);
	});
});

describe('manualPurchaseSchema — MINT mode', () => {
	it('accepts a valid mint purchase', () => {
		expect(manualPurchaseSchema.safeParse(validMint).success).toBe(true);
	});

	it("088 raise mirror: rejects asset_type='currency' — cash is amount-carried, not instrument-carried", () => {
		const r = manualPurchaseSchema.safeParse({ ...validMint, asset_type: 'currency' });
		expect(r.success).toBe(false);
	});

	it('088 raise mirror: rejects an empty (or whitespace-only) mint name', () => {
		expect(manualPurchaseSchema.safeParse({ ...validMint, asset_name: '' }).success).toBe(false);
		expect(manualPurchaseSchema.safeParse({ ...validMint, asset_name: '   ' }).success).toBe(false);
	});

	it('.strict() rejects a stray BIND field on a mint submission', () => {
		const r = manualPurchaseSchema.safeParse({ ...validMint, security_id: '1' });
		expect(r.success).toBe(false);
	});
});

describe('manualPurchaseSchema — mode exclusivity (088’s "both or neither" raise, client mirror)', () => {
	it('rejects an unrecognized mode value', () => {
		expect(manualPurchaseSchema.safeParse({ ...validBind, mode: 'both' }).success).toBe(false);
	});
});

describe('manualPurchaseSchema — 088’s Lock-14 numeric fences (mirrored, fast-feedback)', () => {
	it('rejects zero / negative quantity', () => {
		expect(manualPurchaseSchema.safeParse({ ...validBind, quantity: '0' }).success).toBe(false);
		expect(manualPurchaseSchema.safeParse({ ...validBind, quantity: '-5' }).success).toBe(false);
	});

	it('rejects zero / negative cost_basis', () => {
		expect(manualPurchaseSchema.safeParse({ ...validBind, cost_basis: '0' }).success).toBe(false);
		expect(manualPurchaseSchema.safeParse({ ...validBind, cost_basis: '-1' }).success).toBe(false);
	});

	it('rejects NaN / Infinity passed directly', () => {
		expect(manualPurchaseSchema.safeParse({ ...validBind, quantity: 'NaN' }).success).toBe(false);
		expect(manualPurchaseSchema.safeParse({ ...validBind, cost_basis: 'Infinity' }).success).toBe(
			false
		);
	});

	it('088’s own worked ratio-defect example: quantity 1,000,000 / cost_basis 10.00 derives to 0.0000 — neither operand alone is extreme', () => {
		const r = manualPurchaseSchema.safeParse({
			...validBind,
			quantity: '1000000',
			cost_basis: '10.00'
		});
		expect(r.success).toBe(false);
	});

	it('rejects a real-calendar-date violation', () => {
		expect(manualPurchaseSchema.safeParse({ ...validBind, trade_date: '2026-02-31' }).success).toBe(
			false
		);
	});

	it('accepts an optional sub_cat_id / description / note left blank', () => {
		const r = manualPurchaseSchema.safeParse(validBind);
		expect(r.success).toBe(true);
		if (r.success) {
			expect(r.data.sub_cat_id).toBeNull();
			expect(r.data.description).toBeNull();
			expect(r.data.note).toBeNull();
		}
	});
});

describe('looksLikeTicker — F/CTO ruling: nudge, never block', () => {
	it('flags short all-caps strings', () => {
		expect(looksLikeTicker('AAPL')).toBe(true);
		expect(looksLikeTicker('BRK.B')).toBe(true);
		expect(looksLikeTicker('V')).toBe(true);
	});

	it('does not flag a real company/personal-asset name', () => {
		expect(looksLikeTicker('Acme Holdings LLC')).toBe(false);
		expect(looksLikeTicker('123 Main St')).toBe(false);
		expect(looksLikeTicker('My 1967 Mustang')).toBe(false);
	});

	it('does not flag a long all-caps acronym (a legitimate personal-asset name, not ticker length)', () => {
		expect(looksLikeTicker('NASA')).toBe(true); // 4 letters — still ticker-length, correctly flagged
		expect(looksLikeTicker('UNESCO')).toBe(false); // 6 letters — beyond ticker length, not flagged
	});
});
