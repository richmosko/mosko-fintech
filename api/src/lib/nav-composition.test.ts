// nav-composition.test.ts — unit battery for the §2.1.5 buildup-ladder logic (SELF-226).
// Browser-safe, dep-free (node env). NavCompositionTable.svelte is a thin presentational
// shell over buildupRows(); exercising it here proves the AC#4 EXACT order + the D5 debt
// sign flip + the AC#6 tax-placeholder flagging deterministically WITHOUT a DOM env.

import { describe, it, expect } from 'vitest';
import { buildupRows, type NavCompositionBuildups } from './nav-composition';

const b: NavCompositionBuildups = {
	total_non_re: 800_000,
	gross_total: 1_000_000,
	debt: 150_000, // POSITIVE magnitude per the 051 contract
	realized_tax_liab: 0,
	unrealized_tax_liab: 0
};

describe('buildupRows — the ratified ladder (AC#4 EXACT order)', () => {
	it('emits the five rows in exactly: Total Non-RE → Gross Total → Debt → Realized → Unrealized', () => {
		expect(buildupRows(b).map((r) => r.key)).toEqual([
			'total_non_re',
			'gross_total',
			'debt',
			'realized_tax_liab',
			'unrealized_tax_liab'
		]);
	});

	it('labels match the ratified copy', () => {
		expect(buildupRows(b).map((r) => r.label)).toEqual([
			'Total Non-RE',
			'Gross Total',
			'Debt',
			'Realized Tax Liab',
			'Unrealized Tax Liab'
		]);
	});
});

describe('buildupRows — Debt sign flip (D5)', () => {
	it('renders debt as a SUBTRACTION: displayValue = −(positive magnitude)', () => {
		const debtRow = buildupRows(b).find((r) => r.key === 'debt');
		expect(debtRow?.displayValue).toBe(-150_000);
	});

	it('leaves the asset buildups (total_non_re, gross_total) as natural positives', () => {
		const rows = buildupRows(b);
		expect(rows.find((r) => r.key === 'total_non_re')?.displayValue).toBe(800_000);
		expect(rows.find((r) => r.key === 'gross_total')?.displayValue).toBe(1_000_000);
	});

	it('a zero-debt household flips to a neutral zero (−0 arithmetic; rendered $0)', () => {
		const debtRow = buildupRows({ ...b, debt: 0 }).find((r) => r.key === 'debt');
		expect(debtRow?.displayValue).toBe(-0);
	});
});

describe('buildupRows — tax placeholder flagging (AC#6 / D7 · V1.1 Option A)', () => {
	it('flags ONLY the two tax rows as placeholders (they carry the V1.4 caption + render $0)', () => {
		const flagged = buildupRows(b)
			.filter((r) => r.isTaxPlaceholder)
			.map((r) => r.key);
		expect(flagged).toEqual(['realized_tax_liab', 'unrealized_tax_liab']);
	});

	it('never flags the asset/debt rows as placeholders', () => {
		const rows = buildupRows(b);
		expect(rows.find((r) => r.key === 'total_non_re')?.isTaxPlaceholder).toBe(false);
		expect(rows.find((r) => r.key === 'gross_total')?.isTaxPlaceholder).toBe(false);
		expect(rows.find((r) => r.key === 'debt')?.isTaxPlaceholder).toBe(false);
	});
});
