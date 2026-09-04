// nav-composition.test.ts — unit battery for the §2.1.5 buildup-ladder logic (SELF-226 · V1.1;
// SELF-268 V1.4 flip). Browser-safe, dep-free (node env). NavCompositionTable.svelte is a thin
// presentational shell over buildupRows(); exercising it here proves the AC#4 EXACT order + the
// D5 debt sign flip + SELF-268 AC 7 / M-3's "exactly one flip in the ladder" invariant
// deterministically WITHOUT a DOM env.

import { describe, it, expect } from 'vitest';
import { buildupRows, type NavCompositionBuildups } from './nav-composition';

const b: NavCompositionBuildups = {
	total_non_re: 800_000,
	gross_total: 1_000_000,
	debt: 150_000, // POSITIVE magnitude per the 051 contract
	realized_tax_liab: 5_000, // SELF-268: real value, POSITIVE magnitude (AC 7 / M-3)
	unrealized_tax_liab: 2_500 // SELF-268: real value, POSITIVE magnitude (AC 7 / M-3)
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

describe('buildupRows — SELF-268 tax-line flip: real values, NO second sign flip (AC 7 / M-3)', () => {
	it('a NON-ZERO helper value reaches the rendered cell (AC 10 — not merely "$0 is absent")', () => {
		const rows = buildupRows(b);
		expect(rows.find((r) => r.key === 'realized_tax_liab')?.displayValue).toBe(5_000);
		expect(rows.find((r) => r.key === 'unrealized_tax_liab')?.displayValue).toBe(2_500);
	});

	it('renders the tax rows UNFLIPPED — positive magnitude in, positive magnitude out', () => {
		const rows = buildupRows({ ...b, realized_tax_liab: 12_345, unrealized_tax_liab: 999 });
		expect(rows.find((r) => r.key === 'realized_tax_liab')?.displayValue).toBe(12_345);
		expect(rows.find((r) => r.key === 'unrealized_tax_liab')?.displayValue).toBe(999);
	});

	it('exactly ONE flip in the whole ladder: only debt.displayValue is the negation of its raw magnitude', () => {
		const rows = buildupRows(b);
		const flippedKeys = rows
			.filter((r) => {
				const raw = b[r.key as keyof NavCompositionBuildups];
				return r.displayValue === -raw && raw !== 0;
			})
			.map((r) => r.key);
		expect(flippedKeys).toEqual(['debt']);
	});
});
