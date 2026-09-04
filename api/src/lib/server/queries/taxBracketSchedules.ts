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
//
// is_seed_template (SELF-265 second pass, E38): each schedule carries whether its
// (tax_year, schedule_type) matches a row `pfin.fn_tax_bracket_seed_template()` (migration 103)
// currently returns — the SAME template `pfin.fn_provision_tax_brackets()` writes at signup and
// 103's backfill wrote for existing users. NEVER hard-coded here: the template lives in the DB,
// so a future migration that seeds e.g. California 2026 changes this marking with no code edit.
// The RPC has EXECUTE granted to `authenticated` (103, confirmed against the migration before
// this was built — no grant was added to reach it). This marking is INFORMATIONAL — the UI's
// cue to render the template affordance — never the fence: `deleteSchedule` in +page.server.ts
// re-derives the same check independently under the caller's own RLS before every delete, rather
// than trusting a value that travelled through form data. A seed-template read failure here
// degrades every schedule's `is_seed_template` to `false` (fail-open, matching this file's
// existing per-concern fail-soft posture) — the enforcement point fails closed instead, see
// +page.server.ts.

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
	/** True iff (tax_year, schedule_type) matches a row `pfin.fn_tax_bracket_seed_template()`
	 *  currently returns — see file header. Informational only; never trust this field as the
	 *  delete fence — `deleteSchedule` re-checks server-side. */
	is_seed_template: boolean;
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

type SeedTemplateRow = {
	schedule_type: TaxScheduleType;
	tax_year: number;
};

/** The set of (tax_year, schedule_type) keys `pfin.fn_tax_bracket_seed_template()` currently
 *  returns, `null` on a read failure — deliberately NOT an empty Set on failure, so a caller can
 *  tell "confirmed nothing is a template" from "couldn't ask" and choose its own fail-open (this
 *  loader) or fail-closed (`deleteSchedule`) posture on that distinction. Exported so
 *  +page.server.ts's `deleteSchedule` uses this SAME derivation rather than a second, driftable
 *  copy of the key format. */
export async function loadSeedTemplateKeys(supabase: SupabaseClient): Promise<Set<string> | null> {
	const { data, error } = await supabase.schema('pfin').rpc('fn_tax_bracket_seed_template');
	if (error) {
		console.error('[taxBracketSchedules] seed-template read failed:', error.message);
		return null;
	}
	const keys = new Set<string>();
	for (const row of (data ?? []) as SeedTemplateRow[]) {
		keys.add(`${row.tax_year}:${row.schedule_type}`);
	}
	return keys;
}

/** True iff (taxYear, scheduleType) is a key `keys` holds — the ONE place the key format
 *  (`${tax_year}:${schedule_type}`) is written, so `loadTaxBracketSchedules` below and
 *  `deleteSchedule` compare identically. */
export function isSeedTemplateKey(
	keys: Set<string>,
	taxYear: number,
	scheduleType: TaxScheduleType
): boolean {
	return keys.has(`${taxYear}:${scheduleType}`);
}

/**
 * Load the caller's own tax bracket schedules, grouped into the three jurisdictions, each
 * carrying its own current-year-present flag and fallback basis year (see file header).
 */
export async function loadTaxBracketSchedules(
	supabase: SupabaseClient,
	currentTaxYear: number
): Promise<TaxBracketJurisdiction[]> {
	try {
		const [scheduleResult, rowResult, seedKeysResult] = await Promise.all([
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
				.order('bracket_floor', { ascending: true }),
			loadSeedTemplateKeys(supabase)
		]);

		// Informational-only: fail OPEN to "nothing is a template" on a read failure, logged. The
		// enforcement point (deleteSchedule) fails CLOSED on the same `null` — see its own comment.
		const seedKeys = seedKeysResult ?? new Set<string>();

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
			is_seed_template: isSeedTemplateKey(seedKeys, s.tax_year, s.schedule_type),
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
