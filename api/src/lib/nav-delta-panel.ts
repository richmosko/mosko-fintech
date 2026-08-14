// nav-delta-panel.ts — SELF-222 client-side shape + predicates for the §2.1.3 multi-horizon
// NAV-delta panel (frontend-owned, non-server). Mirrors `pfin.fn_nav_delta_panel()`'s RETURNS
// TABLE verbatim (migration supabase/migrations/071_fn_nav_delta_panel.sql, SELF-221) — no
// field renamed, no field invented, no state inferred here that the backend didn't already
// resolve structurally.
//
// THE THREE-WAY NULL DISCRIMINATOR (071 CONTRACT) IS STRUCTURAL, NOT A FLAG TO INTERPRET:
//   INSUFFICIENT HISTORY   anchor_date NOT NULL, anchor_checkpoint_date NULL
//   CPI UNRESOLVABLE       cpi_unavailable = true, delta_nominal PRESENT
//   NOT APPLICABLE         cpi_* columns ALL NULL (month / ytd — no Inflation Adjusted value
//                           exists for these horizons at all, per PRD §2.1.3)
// These can co-occur and live in different columns; the predicates below read the columns
// directly rather than collapsing them into one derived "quality" enum (066/071's own
// precedent — see the migration header).
//
// current_checkpoint_date / cpi_basis_period / cpi_any_carried are PANEL-WIDE facts returned
// per-row (071: "a property of the store, not of a horizon" / "comes back TRUE PANEL-WIDE").
// The panel reads them off the row set once, rather than re-deriving a staleness verdict from
// a client-side clock comparison — ADR-044 R2 is the whole reason a second, client-side "is
// this stale" clock check must not exist here; the disclosure IS the returned checkpoint date.

export type NavDeltaHorizon = 'month' | 'ytd' | '1y' | '3y' | '5y';

export interface NavDeltaPanelRow {
	horizon: NavDeltaHorizon;
	anchor_date: string | null;
	anchor_checkpoint_date: string | null;
	current_checkpoint_date: string | null;
	delta_nominal: number | null;
	delta_percent: number | null;
	delta_inflation_adjusted: number | null;
	cpi_basis_period: string | null;
	cpi_any_carried: boolean;
	cpi_unavailable: boolean;
}

// Fixed row order per the 071 CONTRACT ("EXACTLY FIVE ROWS, ALWAYS, in fixed order").
export const HORIZON_ORDER: NavDeltaHorizon[] = ['month', 'ytd', '1y', '3y', '5y'];

export const HORIZON_LABEL: Record<NavDeltaHorizon, string> = {
	month: 'Month',
	ytd: 'YTD',
	'1y': '1-Year',
	'3y': '3-Year',
	'5y': '5-Year'
};

/** Re-orders a possibly-scrambled row set to HORIZON_ORDER, dropping any row whose horizon
 * isn't recognized (defensive — never crash the panel on an unexpected label; the fixed-order
 * guarantee is the backend's, this just doesn't trust wire order blindly). */
export function orderRows(rows: NavDeltaPanelRow[]): NavDeltaPanelRow[] {
	return HORIZON_ORDER.map((h) => rows.find((r) => r.horizon === h)).filter(
		(r): r is NavDeltaPanelRow => r != null
	);
}

// PRD §2.1.3 verbatim: Inflation Adjusted is populated for 1-Year / 3-Year / 5-Year ONLY.
export function isCpiApplicable(horizon: NavDeltaHorizon): boolean {
	return horizon === '1y' || horizon === '3y' || horizon === '5y';
}

// Structural discriminator #1: anchor resolved, no checkpoint ever reached it. Deltas NULL.
export function isInsufficientHistory(row: NavDeltaPanelRow): boolean {
	return row.anchor_date !== null && row.anchor_checkpoint_date === null;
}

// Structural discriminator #2: the nominal figure stands; only the real-terms one is unformed.
// Gated on isCpiApplicable so a future backend change can't silently steer a Month/YTD row into
// this branch — 071 documents cpi_unavailable as false-by-construction there, but the gate here
// doesn't take that on trust.
export function isCpiUnresolvable(row: NavDeltaPanelRow): boolean {
	return isCpiApplicable(row.horizon) && row.cpi_unavailable === true;
}

// delta_percent is NULL — never 0 — when the anchor NAV is non-positive (071 AC2 / migration
// header). "No change" and "cannot be expressed" must not render alike.
export function isPercentInexpressible(row: NavDeltaPanelRow): boolean {
	return row.delta_nominal !== null && row.delta_percent === null;
}

/** null (neutral ink) at exactly zero — mirrors NavCompositionTable's pos/neg fence convention
 * (design-system-spec §5 fence 1): a delta is ACTUAL performance, so pos/neg applies, but a
 * zero delta is not a claim of gain or loss either direction. */
export function signClass(n: number | null): 'pos' | 'neg' | null {
	if (n === null || n === 0) return null;
	return n > 0 ? 'pos' : 'neg';
}

const usd = new Intl.NumberFormat('en-US', {
	style: 'currency',
	currency: 'USD',
	minimumFractionDigits: 0,
	maximumFractionDigits: 0
});

// U+2212 MINUS SIGN, never U+002D hyphen-minus — AC2 verbatim ("−$X,XXX"). Zero renders
// unsigned, matching NavCompositionTable's usdSigned `signDisplay: 'exceptZero'` convention
// already locked for signed-delta cells elsewhere on this surface.
export function formatSignedUsd(n: number): string {
	if (n === 0) return usd.format(0);
	return `${n < 0 ? '−' : '+'}${usd.format(Math.abs(n))}`;
}

export function formatSignedPercent(p: number): string {
	if (p === 0) return '0.0%';
	return `${p < 0 ? '−' : '+'}${Math.abs(p).toFixed(1)}%`;
}

export function monthYear(iso: string): string {
	return new Date(`${iso}T00:00:00Z`).toLocaleDateString('en-US', {
		month: 'long',
		year: 'numeric',
		timeZone: 'UTC'
	});
}

export function fullDate(iso: string): string {
	return new Date(`${iso}T00:00:00Z`).toLocaleDateString('en-US', {
		month: 'long',
		day: 'numeric',
		year: 'numeric',
		timeZone: 'UTC'
	});
}

// current_checkpoint_date is identical on all five rows (071 CONTRACT) — read once rather than
// re-reading per row. Returns null on an empty set (fail-soft; the caller gates rendering).
export function currentCheckpointDate(rows: NavDeltaPanelRow[]): string | null {
	return rows[0]?.current_checkpoint_date ?? null;
}

// cpi_basis_period is likewise one shared denomination (cpi_ye — December of the prior calendar
// year) — read off the first CPI-applicable row rather than assuming index [2].
export function cpiBasisPeriod(rows: NavDeltaPanelRow[]): string | null {
	return rows.find((r) => isCpiApplicable(r.horizon))?.cpi_basis_period ?? null;
}

// Panel-wide carried signal (071 header: "cpi_any_carried comes back TRUE PANEL-WIDE" during
// the Jan/Feb structural window) — true if ANY CPI-applicable row reports it. Rendered as ONE
// series-level basis-line note (§2.4.4: "one series-level mark, not one per point"), not a
// per-cell marker repeated three times for what is functionally one fact.
export function anyCpiCarried(rows: NavDeltaPanelRow[]): boolean {
	return rows.some((r) => isCpiApplicable(r.horizon) && r.cpi_any_carried);
}
