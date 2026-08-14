// nav-delta-panel.test.ts — pure-logic coverage for the SELF-222 client-side mirror of
// pfin.fn_nav_delta_panel()'s three-way NULL discriminator + formatting helpers. Dep-free
// (no svelte import) — the predicates are plain functions over the RETURNS TABLE shape.

import { describe, it, expect } from 'vitest';
import {
	HORIZON_ORDER,
	HORIZON_LABEL,
	isCpiApplicable,
	isInsufficientHistory,
	isCpiUnresolvable,
	isPercentInexpressible,
	orderRows,
	signClass,
	formatSignedUsd,
	formatSignedPercent,
	monthYear,
	fullDate,
	currentCheckpointDate,
	cpiBasisPeriod,
	anyCpiCarried,
	type NavDeltaPanelRow
} from './nav-delta-panel';

// A fully-populated, non-edge-case row — every test below overrides only the fields under test.
function row(overrides: Partial<NavDeltaPanelRow> & { horizon: NavDeltaPanelRow['horizon'] }): NavDeltaPanelRow {
	return {
		anchor_date: '2025-08-31',
		anchor_checkpoint_date: '2025-08-31',
		current_checkpoint_date: '2026-08-12',
		delta_nominal: 15_000,
		delta_percent: 6.2,
		delta_inflation_adjusted: isCpiApplicable(overrides.horizon) ? 9_000 : null,
		cpi_basis_period: isCpiApplicable(overrides.horizon) ? '2025-12-01' : null,
		cpi_any_carried: false,
		cpi_unavailable: false,
		...overrides
	};
}

describe('HORIZON_ORDER / HORIZON_LABEL', () => {
	it('fixed order and labels match the AC verbatim', () => {
		expect(HORIZON_ORDER).toEqual(['month', 'ytd', '1y', '3y', '5y']);
		expect(HORIZON_LABEL).toEqual({
			month: 'Month',
			ytd: 'YTD',
			'1y': '1-Year',
			'3y': '3-Year',
			'5y': '5-Year'
		});
	});
});

describe('isCpiApplicable', () => {
	it('true for 1y/3y/5y, false for month/ytd (PRD §2.1.3 verbatim)', () => {
		expect(isCpiApplicable('month')).toBe(false);
		expect(isCpiApplicable('ytd')).toBe(false);
		expect(isCpiApplicable('1y')).toBe(true);
		expect(isCpiApplicable('3y')).toBe(true);
		expect(isCpiApplicable('5y')).toBe(true);
	});
});

describe('isInsufficientHistory — structural discriminator #1', () => {
	it('anchor_date resolved, anchor_checkpoint_date NULL → true', () => {
		expect(isInsufficientHistory(row({ horizon: '5y', anchor_checkpoint_date: null }))).toBe(true);
	});
	it('both resolved → false', () => {
		expect(isInsufficientHistory(row({ horizon: '5y' }))).toBe(false);
	});
	it('anchor_date itself NULL (should not occur per 071, but defensive) → false, not a crash', () => {
		expect(isInsufficientHistory(row({ horizon: '5y', anchor_date: null, anchor_checkpoint_date: null }))).toBe(
			false
		);
	});
});

describe('isCpiUnresolvable — structural discriminator #2', () => {
	it('cpi_unavailable=true on a CPI-applicable horizon → true', () => {
		expect(isCpiUnresolvable(row({ horizon: '3y', cpi_unavailable: true, delta_inflation_adjusted: null }))).toBe(
			true
		);
	});
	it('cpi_unavailable=false → false', () => {
		expect(isCpiUnresolvable(row({ horizon: '3y' }))).toBe(false);
	});
	it('gated on isCpiApplicable — a stray cpi_unavailable=true on month/ytd never reaches the branch', () => {
		expect(isCpiUnresolvable(row({ horizon: 'month', cpi_unavailable: true }))).toBe(false);
	});
});

describe('isPercentInexpressible — AC2: "no change" vs "cannot be expressed" must not render alike', () => {
	it('delta_nominal present, delta_percent NULL → true (non-positive anchor)', () => {
		expect(isPercentInexpressible(row({ horizon: 'month', delta_percent: null }))).toBe(true);
	});
	it('delta_percent = 0 (a real zero) → false — must NOT be confused with the NULL case', () => {
		expect(isPercentInexpressible(row({ horizon: 'month', delta_nominal: 0, delta_percent: 0 }))).toBe(false);
	});
	it('insufficient-history row (delta_nominal also NULL) → false — that is a different discriminator', () => {
		expect(
			isPercentInexpressible(
				row({ horizon: '5y', anchor_checkpoint_date: null, delta_nominal: null, delta_percent: null })
			)
		).toBe(false);
	});
});

describe('signClass — value-color fence (zero is neutral, matching NavCompositionTable)', () => {
	it('positive → pos, negative → neg, zero → null, NULL → null', () => {
		expect(signClass(100)).toBe('pos');
		expect(signClass(-100)).toBe('neg');
		expect(signClass(0)).toBe(null);
		expect(signClass(null)).toBe(null);
	});
});

describe('formatSignedUsd — AC2 verbatim format, U+2212 minus sign', () => {
	it('positive → "+$X,XXX"', () => {
		expect(formatSignedUsd(1200)).toBe('+$1,200');
	});
	it('negative → "−$X,XXX" using U+2212, never a hyphen-minus', () => {
		const out = formatSignedUsd(-1200);
		expect(out).toBe('−$1,200');
		expect(out).not.toContain('-');
	});
	it('zero → unsigned "$0" (matches NavCompositionTable exceptZero convention)', () => {
		expect(formatSignedUsd(0)).toBe('$0');
	});
});

describe('formatSignedPercent — AC2 verbatim format, U+2212 minus sign', () => {
	it('positive → "+Y.Y%"', () => {
		expect(formatSignedPercent(6.2)).toBe('+6.2%');
	});
	it('negative → "−Y.Y%" using U+2212', () => {
		const out = formatSignedPercent(-6.2);
		expect(out).toBe('−6.2%');
		expect(out).not.toContain('-');
	});
	it('zero → unsigned "0.0%"', () => {
		expect(formatSignedPercent(0)).toBe('0.0%');
	});
});

describe('monthYear / fullDate — UTC-anchored, no local-timezone off-by-one', () => {
	it('monthYear renders month + year only', () => {
		expect(monthYear('2025-12-01')).toBe('December 2025');
	});
	it('fullDate renders month/day/year', () => {
		expect(fullDate('2026-08-12')).toBe('August 12, 2026');
	});
});

describe('currentCheckpointDate / cpiBasisPeriod / anyCpiCarried — panel-wide reads', () => {
	const rows: NavDeltaPanelRow[] = [
		row({ horizon: 'month' }),
		row({ horizon: 'ytd' }),
		row({ horizon: '1y', cpi_any_carried: true }),
		row({ horizon: '3y', cpi_any_carried: true }),
		row({ horizon: '5y', cpi_any_carried: true })
	];

	it('currentCheckpointDate reads off the first row (identical on all five per 071)', () => {
		expect(currentCheckpointDate(rows)).toBe('2026-08-12');
	});
	it('cpiBasisPeriod reads off the first CPI-applicable row, skipping month/ytd', () => {
		expect(cpiBasisPeriod(rows)).toBe('2025-12-01');
	});
	it('anyCpiCarried true when any CPI-applicable row carries it (the Jan/Feb panel-wide case)', () => {
		expect(anyCpiCarried(rows)).toBe(true);
	});
	it('anyCpiCarried false when no CPI-applicable row carries it', () => {
		expect(anyCpiCarried([row({ horizon: '1y' }), row({ horizon: '3y' }), row({ horizon: '5y' })])).toBe(false);
	});
	it('anyCpiCarried ignores a stray cpi_any_carried on month/ytd (gated on isCpiApplicable)', () => {
		expect(
			anyCpiCarried([{ ...row({ horizon: 'month' }), cpi_any_carried: true }, row({ horizon: '1y' })])
		).toBe(false);
	});
	it('empty row set → both null, false — never a crash', () => {
		expect(currentCheckpointDate([])).toBe(null);
		expect(cpiBasisPeriod([])).toBe(null);
		expect(anyCpiCarried([])).toBe(false);
	});
});

describe('orderRows — fixed order, defensive against scrambled/unknown-label wire order', () => {
	it('re-orders a scrambled set to HORIZON_ORDER', () => {
		const scrambled = [row({ horizon: '5y' }), row({ horizon: 'month' }), row({ horizon: '1y' })];
		expect(orderRows(scrambled).map((r) => r.horizon)).toEqual(['month', '1y', '5y']);
	});
	it('drops an unrecognized horizon label rather than crashing', () => {
		const withBogus = [row({ horizon: 'month' }), { ...row({ horizon: 'ytd' }), horizon: 'bogus' } as unknown as NavDeltaPanelRow];
		expect(orderRows(withBogus).map((r) => r.horizon)).toEqual(['month']);
	});
});
