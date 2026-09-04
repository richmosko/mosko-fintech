// nav-composition.test.ts — unit battery for the §2.1.5 buildup-ladder logic (SELF-226 · V1.1;
// SELF-268 V1.4 flip, E41 envelope shape). Browser-safe, dep-free (node env).
// NavCompositionTable.svelte is a thin presentational shell over buildupRows() / navFootLabel();
// exercising them here proves the AC#4 EXACT order + the D5 debt sign flip + SELF-268 AC 7 / M-3's
// "exactly one flip in the ladder" invariant + Sec's three-state NAV-foot basis, deterministically
// WITHOUT a DOM env.

import { describe, it, expect } from 'vitest';
import {
	buildupRows,
	navFootBasis,
	navFootLabel,
	navHeadlineBasisNote,
	type NavCompositionBuildups,
	type TaxLineEnvelope
} from './nav-composition';

const computed = (amount: number): TaxLineEnvelope => ({ status: 'computed', amount });
const unavailable = (reason: string): TaxLineEnvelope => ({ status: 'unavailable', reason });

/** `BuildupRow` is a 3-variant union (E41: an unavailable tax-line row carries no `displayValue`
 * at all — that's the type-level guard against a silent $0). A plain `.find(...)?.displayValue`
 * therefore doesn't typecheck across the union; this helper narrows explicitly for the tests below
 * that expect a numeric row (the amount-only rows, or a KNOWN-computed tax row). */
function displayValueOf(rows: ReturnType<typeof buildupRows>, key: string): number | undefined {
	const row = rows.find((r) => r.key === key);
	return row && 'displayValue' in row ? row.displayValue : undefined;
}

const b: NavCompositionBuildups = {
	total_non_re: 800_000,
	gross_total: 1_000_000,
	debt: 150_000, // POSITIVE magnitude per the 051 contract
	realized_tax_liab: computed(5_000), // SELF-268 E41: envelope, amount is POSITIVE (AC 7 / M-3)
	unrealized_tax_liab: computed(2_500) // SELF-268 E41: envelope, amount is POSITIVE (AC 7 / M-3)
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
		expect(displayValueOf(buildupRows(b), 'debt')).toBe(-150_000);
	});

	it('leaves the asset buildups (total_non_re, gross_total) as natural positives', () => {
		const rows = buildupRows(b);
		expect(displayValueOf(rows, 'total_non_re')).toBe(800_000);
		expect(displayValueOf(rows, 'gross_total')).toBe(1_000_000);
	});

	it('a zero-debt household flips to a neutral zero (−0 arithmetic; rendered $0)', () => {
		expect(displayValueOf(buildupRows({ ...b, debt: 0 }), 'debt')).toBe(-0);
	});
});

describe('buildupRows — SELF-268 E41 tax envelopes, computed: real values, NO second sign flip (AC 7 / M-3)', () => {
	it('a NON-ZERO helper value reaches the rendered cell (AC 10 — not merely "$0 is absent")', () => {
		const rows = buildupRows(b);
		const realized = rows.find((r) => r.key === 'realized_tax_liab');
		const unrealized = rows.find((r) => r.key === 'unrealized_tax_liab');
		expect(realized && 'status' in realized && realized.status === 'computed' && realized.displayValue).toBe(5_000);
		expect(unrealized && 'status' in unrealized && unrealized.status === 'computed' && unrealized.displayValue).toBe(2_500);
	});

	it('renders the tax rows UNFLIPPED — positive amount in, positive displayValue out', () => {
		const rows = buildupRows({ ...b, realized_tax_liab: computed(12_345), unrealized_tax_liab: computed(999) });
		const realized = rows.find((r) => r.key === 'realized_tax_liab');
		const unrealized = rows.find((r) => r.key === 'unrealized_tax_liab');
		expect(realized && 'status' in realized && realized.status === 'computed' && realized.displayValue).toBe(12_345);
		expect(unrealized && 'status' in unrealized && unrealized.status === 'computed' && unrealized.displayValue).toBe(999);
	});

	it('exactly ONE flip in the whole ladder: only debt.displayValue is the negation of its raw magnitude', () => {
		const rawByKey: Record<string, number> = {
			total_non_re: b.total_non_re,
			gross_total: b.gross_total,
			debt: b.debt,
			realized_tax_liab: b.realized_tax_liab.status === 'computed' ? b.realized_tax_liab.amount : NaN,
			unrealized_tax_liab: b.unrealized_tax_liab.status === 'computed' ? b.unrealized_tax_liab.amount : NaN
		};
		const flippedKeys = buildupRows(b)
			.filter((r): r is Extract<typeof r, { displayValue: number }> => 'displayValue' in r)
			.filter((r) => {
				const raw = rawByKey[r.key];
				return r.displayValue === -raw && raw !== 0;
			})
			.map((r) => r.key);
		expect(flippedKeys).toEqual(['debt']);
	});
});

describe('buildupRows — SELF-268 E41 tax envelopes, unavailable: NEVER a $0 determination (AC 6)', () => {
	it('an unavailable envelope routes to the no-displayValue row variant, carrying its reason', () => {
		const rows = buildupRows({ ...b, realized_tax_liab: unavailable('no_ledger_designated') });
		const realized = rows.find((r) => r.key === 'realized_tax_liab');
		expect(realized).toMatchObject({ status: 'unavailable', reason: 'no_ledger_designated' });
		expect(realized && 'displayValue' in realized).toBe(false);
	});
});

describe('navFootBasis / navFootLabel — Sec P-5 / option (C): THREE states, never a boolean', () => {
	it('both computed → tax-adjusted', () => {
		expect(navFootBasis(b)).toEqual({ state: 'tax-adjusted' });
		expect(navFootLabel(b)).toBe('Net Assets Value (tax-adjusted)');
	});

	it('both unavailable → unadjusted (fully pre-tax)', () => {
		const both: NavCompositionBuildups = {
			...b,
			realized_tax_liab: unavailable('no_ledger_designated'),
			unrealized_tax_liab: unavailable('no_schedule_any_year')
		};
		expect(navFootBasis(both)).toEqual({ state: 'unadjusted' });
		expect(navFootLabel(both)).toBe('Net Assets Value (pre-tax — tax lines unavailable)');
	});

	it('realized unavailable only → partial, naming the realized line and an action (Sec\'s own example)', () => {
		const partial: NavCompositionBuildups = { ...b, realized_tax_liab: unavailable('no_ledger_designated') };
		expect(navFootBasis(partial)).toEqual({
			state: 'partial',
			unavailableLine: 'realized',
			reason: 'no_ledger_designated'
		});
		expect(navFootLabel(partial)).toBe('Net Assets Value (realized tax not yet deducted — designate a tax-authority ledger)');
	});

	it('unrealized unavailable only → partial, naming the unrealized line (the other partial sub-case)', () => {
		const partial: NavCompositionBuildups = { ...b, unrealized_tax_liab: unavailable('no_schedule_any_year') };
		expect(navFootBasis(partial)).toEqual({
			state: 'partial',
			unavailableLine: 'unrealized',
			reason: 'no_schedule_any_year'
		});
		expect(navFootLabel(partial)).toBe('Net Assets Value (unrealized tax not yet deducted — add a tax bracket schedule)');
	});

	it('an unrecognized reason code degrades to generic action copy rather than throwing or going blank', () => {
		const partial: NavCompositionBuildups = { ...b, realized_tax_liab: unavailable('some_future_reason') };
		expect(navFootLabel(partial)).toBe('Net Assets Value (realized tax not yet deducted — see Settings)');
	});
});

describe('navHeadlineBasisNote — §2.1.1 short form, states the same basis + the AC 4a chart-gross fact', () => {
	it('tax-adjusted → short form + chart note', () => {
		expect(navHeadlineBasisNote(b)).toBe('tax-adjusted; the trend chart below is gross, before tax.');
	});

	it('unadjusted → short form + chart note', () => {
		const both: NavCompositionBuildups = {
			...b,
			realized_tax_liab: unavailable('no_ledger_designated'),
			unrealized_tax_liab: unavailable('no_schedule_any_year')
		};
		expect(navHeadlineBasisNote(both)).toBe('pre-tax — tax lines unavailable; the trend chart below is gross, before tax.');
	});

	it('partial → names which line, + chart note', () => {
		const partial: NavCompositionBuildups = { ...b, realized_tax_liab: unavailable('no_ledger_designated') };
		expect(navHeadlineBasisNote(partial)).toBe('realized tax not yet deducted; the trend chart below is gross, before tax.');
	});
});
