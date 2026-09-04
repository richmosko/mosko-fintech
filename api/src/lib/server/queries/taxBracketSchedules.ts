// taxBracketSchedules.ts — server-side read for the /settings/tax-brackets editor (SELF-265
// AC1/AC2/AC8/AC8b). Backend-owned server surface (ARCH §4.1 allowlist).
//
// RLS-scoped via the per-request anon/authenticated client (`locals.supabase`) — the caller's
// own session, never service_role (RT-26 / Lock 11). A cross-tenant caller reads zero rows on
// both tables and fails closed, the same posture cashflowTarget.ts / userSettings.ts already
// apply to this settings family.
//
// TWO FLAT READS, not a PostgREST embedded select (`tax_bracket_schedule(...tax_bracket_row(...))`).
// No embedded-select precedent exists anywhere in this codebase's queries/ today (grepped before
// choosing this shape), and grouping in JS after two simple `.from()` reads is the boring idiom
// this repo already uses everywhere else (mirrors purchases.ts / reconciliation.ts's own
// multi-query-then-join style) — a novel PostgREST embed across two `pfin` tables would need to
// earn its place against that default, and nothing about this loader needs the join pushed into
// the DB.
//
// SHAPE: ALL of the caller's schedules, across every tax_year, grouped by
// pfin.tax_schedule_type_enum into a FIXED THREE-ENTRY list (federal_ordinary / federal_lt_cg /
// california_ordinary — SELF-265 AC1), each carrying every schedule of that type (not just the
// current year) plus two DERIVED fields the editor needs to render the AC7a/E22 CTA without
// re-deriving the fallback logic client-side:
//   - current_year_present: true iff some schedule of this type has tax_year === currentTaxYear.
//   - basis_year: currentTaxYear if present, else the LATEST tax_year strictly less than
//     currentTaxYear that this jurisdiction actually holds a schedule for (the E22 prior-year
//     fallback), else null (no current-or-prior schedule exists for this jurisdiction at all —
//     the AC8(i) UNAVAILABLE case, distinct from the E22 fallback case).
//   ⚠ A schedule dated in the FUTURE (relative to currentTaxYear) does not count as "current" and
//   is not eligible as a fallback basis year — only a year the arithmetic can actually run on
//   (today's or earlier) is a legitimate basis, matching E22's own "prior-year fallback" framing.
//
// currentTaxYear is a CALLER-SUPPLIED integer, deliberately not derived inside this module — the
// caller resolves it from `serverTodayAsOf()` (ADR-044 Decision 2 / the DB-clock discipline
// asOf.ts's own header states), once per request, the same way every other §2.x reader in this
// tree threads "today" through rather than minting a second clock here.
//
// Fail-soft: a schedule-read error degrades the WHOLE page to the three empty jurisdiction
// groups (mirrors cashflowTarget.ts's UNSET degradation); a row-read error degrades only the
// per-schedule `rows` arrays to empty (the schedules themselves still render, just with no
// brackets shown) rather than failing the whole loader over a narrower fault.

import type { SupabaseClient } from '@supabase/supabase-js';

export const TAX_SCHEDULE_TYPES = ['federal_ordinary', 'federal_lt_cg', 'california_ordinary'] as const;
export type TaxScheduleType = (typeof TAX_SCHEDULE_TYPES)[number];

export type TaxBracketRowRecord = {
	bracket_floor: number;
	bracket_rate: number;
};

export type TaxBracketScheduleRecord = {
	id: number;
	tax_year: number;
	schedule_type: TaxScheduleType;
	schedule_label: string;
	standard_deduction: number;
	tax_balance_prior_year: number | null;
	rows: TaxBracketRowRecord[];
};

export type TaxBracketJurisdiction = {
	schedule_type: TaxScheduleType;
	/** Every schedule of this type, ordered tax_year DESCENDING. */
	schedules: TaxBracketScheduleRecord[];
	current_year_present: boolean;
	basis_year: number | null;
};

/** Migration 101's three numerics may arrive as `number` OR `string` — PostgREST's numeric
 *  serialization is not guaranteed to be a JSON number (nav-series.ts's / purchases.ts's own
 *  coercion idiom, duplicated here rather than imported — this repo's query modules do not share
 *  a numeric-coercion helper today). All three are NOT NULL on the DB (101's CHECKs), so a
 *  non-finite transport surprise here is logged rather than silently degraded to 0 — a 0 bracket
 *  floor/rate is a MEANINGFUL value on this surface, not a safe stand-in for "couldn't parse." */
function toNumber(v: number | string, field: string): number {
	const n = Number(v);
	if (!Number.isFinite(n)) {
		console.error(`[taxBracketSchedules] non-finite numeric transport value for ${field}:`, v);
		return 0;
	}
	return n;
}

function toNumberOrNull(v: number | string | null): number | null {
	if (v === null) return null;
	const n = Number(v);
	return Number.isFinite(n) ? n : null;
}

function emptyJurisdictions(): TaxBracketJurisdiction[] {
	return TAX_SCHEDULE_TYPES.map((schedule_type) => ({
		schedule_type,
		schedules: [],
		current_year_present: false,
		basis_year: null
	}));
}

type RawScheduleRow = {
	id: number;
	tax_year: number;
	schedule_type: TaxScheduleType;
	schedule_label: string;
	standard_deduction: number | string;
	tax_balance_prior_year: number | string | null;
};

type RawBracketRow = {
	schedule_id: number;
	bracket_floor: number | string;
	bracket_rate: number | string;
};

/**
 * Load the caller's own tax bracket schedules, grouped into the three jurisdictions, each
 * carrying its own current-year-present flag and fallback basis year (see file header).
 */
export async function loadTaxBracketSchedules(
	supabase: SupabaseClient,
	currentTaxYear: number
): Promise<TaxBracketJurisdiction[]> {
	try {
		const [scheduleResult, rowResult] = await Promise.all([
			supabase
				.schema('pfin')
				.from('tax_bracket_schedule')
				.select('id, tax_year, schedule_type, schedule_label, standard_deduction, tax_balance_prior_year')
				.order('schedule_type', { ascending: true })
				.order('tax_year', { ascending: false }),
			supabase
				.schema('pfin')
				.from('tax_bracket_row')
				.select('schedule_id, bracket_floor, bracket_rate')
				.order('schedule_id', { ascending: true })
				.order('bracket_floor', { ascending: true })
		]);

		if (scheduleResult.error) {
			console.error('[taxBracketSchedules] schedule read failed → degrading to empty:', scheduleResult.error.message);
			return emptyJurisdictions();
		}

		const rowsBySchedule = new Map<number, TaxBracketRowRecord[]>();
		if (rowResult.error) {
			// Narrower fault: schedules still render, just with no brackets shown.
			console.error('[taxBracketSchedules] row read failed → schedules render with empty rows:', rowResult.error.message);
		} else {
			for (const r of (rowResult.data ?? []) as RawBracketRow[]) {
				const list = rowsBySchedule.get(r.schedule_id) ?? [];
				list.push({
					bracket_floor: toNumber(r.bracket_floor, 'bracket_floor'),
					bracket_rate: toNumber(r.bracket_rate, 'bracket_rate')
				});
				rowsBySchedule.set(r.schedule_id, list);
			}
		}

		const schedules: TaxBracketScheduleRecord[] = ((scheduleResult.data ?? []) as RawScheduleRow[]).map((s) => ({
			id: s.id,
			tax_year: s.tax_year,
			schedule_type: s.schedule_type,
			schedule_label: s.schedule_label,
			standard_deduction: toNumber(s.standard_deduction, 'standard_deduction'),
			tax_balance_prior_year: toNumberOrNull(s.tax_balance_prior_year),
			rows: rowsBySchedule.get(s.id) ?? []
		}));

		return TAX_SCHEDULE_TYPES.map((schedule_type) => {
			// Already tax_year DESC from the query's own `.order()` — filtering preserves that order.
			const group = schedules.filter((s) => s.schedule_type === schedule_type);
			const currentYearPresent = group.some((s) => s.tax_year === currentTaxYear);
			const priorYearsPresent = group.filter((s) => s.tax_year < currentTaxYear).map((s) => s.tax_year);
			const basisYear = currentYearPresent
				? currentTaxYear
				: priorYearsPresent.length > 0
					? Math.max(...priorYearsPresent)
					: null;
			return {
				schedule_type,
				schedules: group,
				current_year_present: currentYearPresent,
				basis_year: basisYear
			};
		});
	} catch (e) {
		console.error('[taxBracketSchedules] threw → degrading to empty:', e instanceof Error ? e.message : String(e));
		return emptyJurisdictions();
	}
}
