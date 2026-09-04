// tax-quarterly.ts — browser-safe types + pure helpers for the §2.5.3.b quarterly estimated-tax
// tables (SELF-266). Frontend-owned; authors NO server logic and performs NO re-derivation of any
// tax math — every number rendered off these types is exactly what
// api/src/lib/server/queries/taxLiability.ts's `loadTaxLiability` (Backend, SELF-264/266) returns
// off `pfin.fn_compute_tax_liability` (104, SELF-262). This module is a TYPE MIRROR, not an
// import — frontend-engineer never imports from src/lib/server/**, so the shape is independently
// declared here, key-for-key against ADR-067 Decision 5 (the payload contract's canonical home)
// and against `104`'s own `comment on function`. If the two drift, ADR-067 Decision 5 wins.
//
// Only the `jurisdictions` / `prior_year_q4_window` / `tax_year` / `as_of` slice this surface
// consumes is mirrored here — `decomposition` and `nav_components` are absent entirely (SELF-264 /
// SELF-268 own those halves of the payload and mirror them at their own fidelity in their own
// modules). `PriorYearQ4` / `PriorYearQ4Detail` below mirror a SECOND module export — Backend's
// `loadPriorYearQ4` (taxLiability.ts, E39) — not a raw `104` key; see that type's own header.

// ---------------------------------------------------------------------------------------------
// Payload mirror (ADR-067 Decision 5).
// ---------------------------------------------------------------------------------------------

export type TaxJurisdictionKey = 'federal' | 'california';

/** schedules.{schedule_type} — Decision 5(c)/(h). */
export type TaxScheduleInfo = {
	present: boolean;
	basis_year: number | null;
	current_year_schedule_empty: boolean;
	/** LT-CG-ONLY (Sec F-2) — absent on ordinary schedule blocks. */
	standard_deduction_ignored?: boolean;
};

export type TaxInstallment = {
	quarter: 1 | 2 | 3 | 4;
	due_date: string;
	/** Q1-Q3: truncated equal cents. Q4: the residual (Decision 5(d) — never recomputed here). */
	amount: number;
};

/** NULL-vs-$0 is Sec B3's enforced-by-construction envelope — never collapse with `?? 0`. */
export type YtdPaidEnvelope =
	| { status: 'unavailable'; reason: string }
	| { status: 'designated'; amount: number };

/** Same envelope discipline as ytd_paid; 'computed' amount may be NEGATIVE (overpayment, ν-1). */
export type FundsDueEnvelope =
	| { status: 'unavailable'; reason: string }
	| { status: 'computed'; amount: number };

export type TaxJurisdictionPayload = {
	status: 'computed' | 'unavailable';
	reason?: string;
	/** NULL when status === 'unavailable' (Sec N-4). Read schedules.{type}.basis_year instead. */
	basis_year: number | null;
	schedules: Record<string, TaxScheduleInfo>;
	inputs: {
		/** NULL when the ordinary schedule itself did not resolve. */
		ordinary_input: number | null;
		/** NULL on `california` always (no LT CG schedule type there) and on an unresolved LT CG schedule. */
		lt_cg_input: number | null;
		standard_deduction: number | null;
	};
	taxable_income: {
		ordinary: number | null;
		lt_cg: number | null;
	};
	annual_liability: number | null;
	/** Informational reference only (μ-2) — drives nothing rendered here beyond its own line. */
	tax_balance_prior_year: number | null;
	installments: TaxInstallment[] | null;
	installments_due_through_next: number;
	next_due_date: string;
	ytd_paid: YtdPaidEnvelope;
	funds_due: FundsDueEnvelope;
	/** OMITTED ENTIRELY (not null, not 0) when status === 'unavailable' (E26 ruling 5). Each figure
	 *  is typed defensively-nullable (Sec N-1/N-2): `104` wraps the object in `jsonb_strip_nulls`
	 *  today, so a null figure is not currently reachable, but the mirror is closed against both
	 *  shapes independently of that other-layer, other-repo guarantee. */
	applied_marginal_rate?: {
		ordinary: number | null;
		/** Absent on california (no LT CG schedule there); may be a genuine 0 on federal. */
		lt_cg?: number | null;
	};
};

/** R8 render-window boundary — computed once in `104`, cited here, never re-derived. */
export type PriorYearQ4Window = {
	open: boolean;
	tax_year: number;
	due_date: string;
};

/** The slice of `fn_compute_tax_liability`'s payload this surface renders. */
export type TaxQuarterlyLiability = {
	as_of: string;
	tax_year: number;
	jurisdictions: Record<TaxJurisdictionKey, TaxJurisdictionPayload>;
	prior_year_q4_window: PriorYearQ4Window;
};

// ---------------------------------------------------------------------------------------------
// E39 (R8 (B)) — the prior tax year's Q4 row, WITH AMOUNTS (Backend's `+page.server.ts` /
// `taxLiability.ts` loadPriorYearQ4, a SECOND fn_compute_tax_liability call as-of Dec 31 of the
// prior tax year). Mirrors that module's own exported shape exactly — key names verbatim.
//
// ⚠ YTD Paid is DELIBERATELY ABSENT from this shape. R8's own rider (ADR-067 Decision 5(f)):
// "the window is about the obligation row only" — YTD Paid is the designated ledger's balance
// SINCE INCEPTION (not year-scoped), so the figure that already renders on the CURRENT-year
// table's own YTD Paid row (`jurisdiction.ytd_paid`) is the correct one to show beside the prior
// year's outstanding Q4, never a second derivation from the Dec-31 payload.
// ---------------------------------------------------------------------------------------------

export type PriorYearQ4Detail = {
	/** The last element of the Dec-31 payload's `installments[]` — null when unavailable. */
	q4_installment: number | null;
	annual_liability: number | null;
	/** Verbatim `funds_due` envelope from the Dec-31 payload — unavailable stays unavailable, never 0. */
	funds_due_envelope: FundsDueEnvelope;
};

export type PriorYearQ4 = {
	tax_year: number;
	due_date: string;
	as_of: string;
	federal: PriorYearQ4Detail;
	california: PriorYearQ4Detail;
};

// ---------------------------------------------------------------------------------------------
// Display constants (draft copy — PM/UX not yet consulted; flagged at hand-off per house
// convention, e.g. NonReAllocationTable's AC6 note).
// ---------------------------------------------------------------------------------------------

export const JURISDICTION_TABLE_TITLE: Record<TaxJurisdictionKey, string> = {
	federal: 'Federal Income Taxes',
	california: 'California State Income Taxes (CA FTB)'
};

/** Display-only mapping to the §2.4.2 account-attribute enum's own labels (account-display.ts) —
 *  NOT the same key space as `TaxJurisdictionKey` (that one is `irs`/`ftb`); used only to phrase
 *  the "designate an account" CTA copy consistently with TaxJurisdictionField's own wording. */
export const JURISDICTION_AUTHORITY_LABEL: Record<TaxJurisdictionKey, string> = {
	federal: 'IRS (Federal)',
	california: 'FTB (California)'
};

const SCHEDULE_TYPE_LABEL: Record<string, string> = {
	federal_ordinary: 'Federal ordinary',
	federal_lt_cg: 'Federal LT CG',
	california_ordinary: 'California'
};

// ---------------------------------------------------------------------------------------------
// Pure helpers — every one reads only fields already on the payload; none re-derives tax math.
// ---------------------------------------------------------------------------------------------

/**
 * The running obligation through the upcoming installment (ADR-067 Decision 5(i)): the SUM of the
 * first `installments_due_through_next` rows' own `amount` — not a multiplication. Summing the
 * rendered rows (the same operation this codebase's every other "Total" foot performs, e.g.
 * CashflowRollupTable / NonReAllocationTable) is exact at every count including 4, because Q4
 * already carries Decision 5(d)'s rounding residual: at N=4 the sum equals `annual_liability`
 * by construction, without this module substituting that field in or multiplying Q1's amount by
 * 4 (which would be off by the residual — the form Decision 5(i) explicitly rejects).
 */
export function subTotalThroughNext(jurisdiction: TaxJurisdictionPayload): number | null {
	if (!jurisdiction.installments) return null;
	const n = Math.min(Math.max(jurisdiction.installments_due_through_next, 0), 4);
	return jurisdiction.installments.slice(0, n).reduce((sum, i) => sum + i.amount, 0);
}

/** AC3 / ξ-1 — the row to visually emphasize. `installments_due_through_next` is already the
 *  upcoming installment's ordinal, capped at 4 (Decision 5(i)), so this needs no date logic of
 *  its own and by construction stays on Q4 through the whole Sep 16–Jan 15 window. */
export function isCurrentInstallmentRow(
	installment: TaxInstallment,
	jurisdiction: TaxJurisdictionPayload
): boolean {
	return installment.quarter === jurisdiction.installments_due_through_next;
}

const pctFmt = new Intl.NumberFormat('en-US', {
	style: 'percent',
	minimumFractionDigits: 0,
	maximumFractionDigits: 2
});

/** AC4 — Federal's two-figure caption. Never computes a rate; renders only what's on the payload
 *  and 'unavailable' when `applied_marginal_rate` is omitted (an unavailable jurisdiction, or a
 *  defensive gap on a computed one — the two are not distinguished in copy, since neither may
 *  render an invented number). A genuine 0% LT CG (`lt_cg === 0`) is rendered as "0%", not as
 *  unavailable — only an ABSENT/NULL key means unavailable (Sec N-1: `== null` catches both,
 *  since `Intl.NumberFormat.format(null)` renders a fabricated "0%" if a null ever reached it).
 *  `rate.ordinary` is guarded the same way (Sec N-2) — an unguarded format would render "NaN%",
 *  not a fabricated number, but "unavailable" is still the correct copy for a missing rate. */
export function federalRateCaption(jurisdiction: TaxJurisdictionPayload): string {
	const rate = jurisdiction.applied_marginal_rate;
	if (!rate) return 'Federal rates unavailable';
	const ordinary = rate.ordinary == null ? 'unavailable' : pctFmt.format(rate.ordinary);
	const ltCg = rate.lt_cg == null ? 'unavailable' : pctFmt.format(rate.lt_cg);
	return `Federal ordinary: ${ordinary} / Federal LT CG: ${ltCg}`;
}

/** AC4 — California's one-figure caption (no LT CG schedule on this jurisdiction, ever). */
export function californiaRateCaption(jurisdiction: TaxJurisdictionPayload): string {
	const rate = jurisdiction.applied_marginal_rate;
	if (!rate) return 'California rate unavailable';
	return `California: ${rate.ordinary == null ? 'unavailable' : pctFmt.format(rate.ordinary)}`;
}

export type BasisYearNote = { scheduleType: string; label: string; text: string };

/**
 * E22 — one note per schedule whose resolved `basis_year` differs from `tax_year`. States the
 * basis year always; adds a "hasn't been entered yet" clause ONLY when `current_year_schedule_empty`
 * says so (dispatch instruction: never claim a reason the payload doesn't state). A schedule with
 * `present: false` (basis_year null) carries no note here — that jurisdiction is `unavailable` and
 * renders the AC-7a empty state instead, never a basis-year line with nothing to report.
 */
export function basisYearNotes(
	jurisdiction: TaxJurisdictionPayload,
	taxYear: number
): BasisYearNote[] {
	const notes: BasisYearNote[] = [];
	for (const [scheduleType, schedule] of Object.entries(jurisdiction.schedules)) {
		if (!schedule.present || schedule.basis_year === null) continue;
		if (schedule.basis_year === taxYear) continue;
		const label = SCHEDULE_TYPE_LABEL[scheduleType] ?? scheduleType;
		const text = schedule.current_year_schedule_empty
			? `${label} on the ${schedule.basis_year} schedule — no ${taxYear} schedule entered yet.`
			: `${label} on the ${schedule.basis_year} schedule.`;
		notes.push({ scheduleType, label, text });
	}
	return notes;
}

/** Decision 5(h) — the one-line "we ignored the deduction you entered" note, LT-CG-only. */
export function standardDeductionIgnored(jurisdiction: TaxJurisdictionPayload): boolean {
	return jurisdiction.schedules.federal_lt_cg?.standard_deduction_ignored === true;
}

/** Machine `reason` codes (104 header, verbatim) → draft display copy. Never invents a reason the
 *  payload didn't state; an unrecognized code still renders (generic fallback), never crashes. */
const REASON_COPY: Record<string, string> = {
	no_schedule_any_year: 'No bracket schedule on file for this jurisdiction.',
	no_ledger_designated: 'No ledger designated for this jurisdiction.',
	ytd_paid_unavailable: 'YTD Paid is unavailable.'
};

export function reasonCopy(reason: string): string {
	return REASON_COPY[reason] ?? `Unavailable (${reason}).`;
}

/** ISO date ('YYYY-MM-DD') → "Apr 15, 2026". UTC-pinned (matches NavReferenceDatesPanel /
 *  HistoricalExpendituresChart's own `${iso}T00:00:00Z` + `timeZone: 'UTC'` convention) so a due
 *  date never shifts a day under a non-UTC browser clock. */
export function fmtDueDate(iso: string): string {
	return new Date(`${iso}T00:00:00Z`).toLocaleDateString('en-US', {
		month: 'short',
		day: 'numeric',
		year: 'numeric',
		timeZone: 'UTC'
	});
}
