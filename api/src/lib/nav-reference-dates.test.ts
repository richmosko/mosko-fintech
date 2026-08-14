// nav-reference-dates.test.ts — pure-logic coverage for the SELF-223 client-side mirror of
// pfin.fn_nav_reference_dates()'s two-way NULL discriminator (AC5) + the plain, unsigned
// formatUsd convention (a NAV LEVEL, not a delta — no sign/color helpers to test here, unlike
// nav-delta-panel.test.ts). Dep-free (no svelte import).

import { describe, it, expect } from 'vitest';
import {
	REFERENCE_ORDER,
	REFERENCE_LABEL,
	isInsufficientHistory,
	isCpiUnresolvable,
	orderReferenceRows,
	formatUsd,
	type NavReferenceDateRow
} from './nav-reference-dates';

// A fully-populated, non-edge-case row — every test below overrides only the fields under test.
function row(
	overrides: Partial<NavReferenceDateRow> & { reference: NavReferenceDateRow['reference'] }
): NavReferenceDateRow {
	return {
		reference_date: '2026-07-31',
		reference_checkpoint_date: '2026-07-31',
		nav: 500_000,
		nav_prior_yr_dollars: 510_000,
		cpi_period: '2026-07-01',
		cpi_basis_period: '2025-12-01',
		cpi_any_carried: false,
		cpi_unavailable: false,
		...overrides
	};
}

describe('REFERENCE_ORDER / REFERENCE_LABEL', () => {
	it('fixed order and labels match the AC verbatim', () => {
		expect(REFERENCE_ORDER).toEqual(['this_month', 'prior_month', 'prior_year_end']);
		expect(REFERENCE_LABEL).toEqual({
			this_month: 'This Month',
			prior_month: 'Prior Month',
			prior_year_end: 'Prior Year-End'
		});
	});
});

describe('isInsufficientHistory — AC5 discriminator #1', () => {
	it('reference_checkpoint_date NULL → true', () => {
		expect(isInsufficientHistory(row({ reference: 'prior_year_end', reference_checkpoint_date: null }))).toBe(
			true
		);
	});
	it('reference_checkpoint_date resolved → false', () => {
		expect(isInsufficientHistory(row({ reference: 'prior_year_end' }))).toBe(false);
	});
});

describe('isCpiUnresolvable — AC5 discriminator #2 (no isCpiApplicable gate needed — every row wants a prior-Yr-$ figure)', () => {
	it('cpi_unavailable = true → true', () => {
		expect(isCpiUnresolvable(row({ reference: 'this_month', cpi_unavailable: true }))).toBe(true);
	});
	it('cpi_unavailable = false → false', () => {
		expect(isCpiUnresolvable(row({ reference: 'this_month' }))).toBe(false);
	});
});

describe('formatUsd — plain, UNSIGNED whole-dollar formatting (a NAV LEVEL, not a delta)', () => {
	it('a positive value has no leading "+" (unlike the delta panel\'s formatSignedUsd)', () => {
		expect(formatUsd(500_000)).toBe('$500,000');
	});
	it('a negative value renders with the locale ordinary minus glyph, not U+2212', () => {
		const out = formatUsd(-500_000);
		expect(out).toContain('500,000');
		expect(out).not.toContain('−');
	});
	it('zero renders as a plain "$0"', () => {
		expect(formatUsd(0)).toBe('$0');
	});
});

describe('orderReferenceRows — fixed order, defensive against scrambled/unknown-label wire order', () => {
	it('re-orders a scrambled set to REFERENCE_ORDER', () => {
		const scrambled = [row({ reference: 'prior_year_end' }), row({ reference: 'this_month' })];
		expect(orderReferenceRows(scrambled).map((r) => r.reference)).toEqual(['this_month', 'prior_year_end']);
	});
	it('drops an unrecognized reference label rather than crashing', () => {
		const withBogus = [
			row({ reference: 'this_month' }),
			{ ...row({ reference: 'prior_month' }), reference: 'bogus' } as unknown as NavReferenceDateRow
		];
		expect(orderReferenceRows(withBogus).map((r) => r.reference)).toEqual(['this_month']);
	});
});
