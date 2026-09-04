// taxLiability.ts — server-side read for pfin.fn_compute_tax_liability (104; SELF-262), the §2.5
// keystone helper. Backend-owned server surface (ARCH §4.1 allowlist).
//
// Calls the SECURITY INVOKER helper through the per-request anon/authenticated client so the
// caller's RLS context propagates (users_id = auth.uid()), NEVER service_role (RT-26 / Lock 11).
// The types below mirror ADR-067 Decision 5's payload contract EXACTLY — key names verbatim, no
// invented or renamed keys — and that ADR (plus 104's `comment on function`) is the canonical home
// for the contract; this module does not restate the rationale, only the shape.
//
// NO as-of ARGUMENT (SELF-264 AC 8a / SELF-266 AC 8a): every §2.5 surface reads server-derived
// today (Seam C — Lock 15's client-toggle allowance is §2.3.3's alone). The RPC is called with NO
// p_data_as_of, so Postgres applies the function's own `default current_date` — there is deliberately
// no second place in this file that could derive "today" and drift from it.
//
// FAIL LOUD, NEVER COERCE. This diverges from this directory's dominant fail-soft convention
// (navComposition.ts / netWorth.ts / staleness.ts degrade to null/UNKNOWN on any read failure).
// That convention exists for surfaces where a degrade lets the REST of the page still render. Here
// the payload IS the page for both SELF-264 and SELF-266 — there is no partial rendering that makes
// sense off a malformed or missing tax-liability payload, and silently coercing a missing top-level
// key into `undefined` is exactly the kind of ?? 0 collapse ADR-067 Decision 5(a)'s envelope design
// exists to make impossible. An RPC error or a payload missing any of the six top-level keys throws
// TaxLiabilityPayloadError; the loader lets it propagate (SvelteKit's default 500) rather than
// rendering a page that looks live off dead data.

import type { SupabaseClient } from '@supabase/supabase-js';

/** Thrown by loadTaxLiability on an RPC error or a payload failing the top-level shape guard. */
export class TaxLiabilityPayloadError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'TaxLiabilityPayloadError';
	}
}

// ---------------------------------------------------------------------------------------------
// §2.5.1 decomposition (ADR-067 Decision 5; 104's `decomposition` key).
// ---------------------------------------------------------------------------------------------

/** One Sub-Cat row in the Ordinary Income decomposition (104's `inc` CTE, Revenue-class-scoped). */
export type OrdinaryIncomeRow = {
	sub_cat_id: number;
	cat: string;
	sub_cat: string;
	/** pfin.tax_character's five seeded codes (011), or NULL on a tax-relevant row with no character. */
	tax_character: string | null;
	amount: number;
};

/**
 * Always `{status:'unavailable', reason:'no_sale_recording_capability'}` under R1 — the CG section
 * keys on the STRUCTURAL fact that no sale-recording capability exists, never on a `lot_match` row
 * count (ADR-067 Decision 5(b) / 104 header's dormant clause). There is deliberately no `rows` key.
 */
export type CapitalGainsUnavailable = {
	status: 'unavailable';
	reason: string;
};

export type TaxDecomposition = {
	ordinary_income: {
		rows: OrdinaryIncomeRow[];
		total: number;
	};
	capital_gains: CapitalGainsUnavailable;
	unclassified: {
		count_ytd: number;
	};
};

// ---------------------------------------------------------------------------------------------
// §2.5.2 / §2.5.3 jurisdictions (104's `jurisdictions` key — object keyed 'federal' | 'california').
// ---------------------------------------------------------------------------------------------

export type TaxJurisdictionKey = 'federal' | 'california';

/** schedules.{schedule_type} — present for every schedule the jurisdiction needs (104's jur_json). */
export type TaxScheduleInfo = {
	present: boolean;
	/** The resolved schedule's tax_year (E22 fallback), or null when nothing resolved. */
	basis_year: number | null;
	/** True if a current-year schedule exists but holds zero bracket rows (Sec F-1, two-term flag). */
	current_year_schedule_empty: boolean;
	/**
	 * LT-CG-ONLY (Sec F-2). Absent on ordinary schedule blocks. True when the resolved LT CG
	 * schedule's stored standard_deduction is non-zero and the walk ignored it (PRD §2.5.3 step 5).
	 */
	standard_deduction_ignored?: boolean;
};

export type TaxInstallment = {
	quarter: 1 | 2 | 3 | 4;
	due_date: string;
	/** Q1-Q3: truncated equal cents. Q4: the residual — sum is exact to annual_liability (Sec M-8/N-2). */
	amount: number;
};

/** ytd_paid — NULL-vs-$0 is Sec B3's enforced-by-construction envelope; never collapse with `?? 0`. */
export type YtdPaidEnvelope =
	| { status: 'unavailable'; reason: string }
	| { status: 'designated'; amount: number };

/** funds_due — same envelope discipline as ytd_paid, distinct status vocabulary ('computed'). */
export type FundsDueEnvelope =
	| { status: 'unavailable'; reason: string }
	| { status: 'computed'; amount: number };

export type TaxJurisdictionPayload = {
	/** Whether EVERY schedule this jurisdiction needs resolved (federal needs ordinary AND LT CG). */
	status: 'computed' | 'unavailable';
	/** Present only when status === 'unavailable' (jsonb_strip_nulls on the envelope half). */
	reason?: string;
	/**
	 * NULL when status === 'unavailable' (Sec N-4 — SQL LEAST ignores nulls, so this is gated on
	 * `computed` at the DB layer). Read `schedules.{type}.basis_year` for the per-schedule figure.
	 */
	basis_year: number | null;
	/** Keyed by pfin.tax_schedule_type_enum value: federal_ordinary / federal_lt_cg / california_ordinary. */
	schedules: Record<string, TaxScheduleInfo>;
	inputs: {
		ordinary_input: number;
		lt_cg_input: number;
		/** The ORDINARY schedule's stored value — the one actually subtracted; never the LT CG one. */
		standard_deduction: number | null;
	};
	taxable_income: {
		ordinary: number | null;
		lt_cg: number | null;
	};
	/** Already rounded to 2dp (Sec N-5). No unrounded key exists — this is the only annual figure. */
	annual_liability: number | null;
	/** Informational reference only (μ-2) — drives nothing. */
	tax_balance_prior_year: number | null;
	installments: TaxInstallment[] | null;
	/** The upcoming installment's ordinal: due dates strictly before as_of, plus one, capped at 4. */
	installments_due_through_next: number;
	next_due_date: string;
	ytd_paid: YtdPaidEnvelope;
	funds_due: FundsDueEnvelope;
	/**
	 * OMITTED ENTIRELY (not null, not 0) when status === 'unavailable' (E26 ruling 5). `lt_cg` is
	 * itself omitted on a jurisdiction with no LT CG schedule (california) via jsonb_strip_nulls.
	 */
	applied_marginal_rate?: {
		ordinary: number;
		lt_cg?: number;
	};
};

// ---------------------------------------------------------------------------------------------
// §2.5.4 NAV components (104's `nav_components` key — consumed by SELF-268 → 051).
// ---------------------------------------------------------------------------------------------

export type NavComponentEnvelope =
	| { status: 'unavailable'; reason: string }
	| { status: 'computed'; amount: number };

export type TaxNavComponents = {
	realized_tax_liab: NavComponentEnvelope;
	/** Clamped at zero (R9) — deliberately asymmetric with ytd_paid, which is not clamped (E11-4). */
	unrealized_tax_liab: NavComponentEnvelope;
};

// ---------------------------------------------------------------------------------------------
// R8 render-window boundary (104's `prior_year_q4_window` key — computed once, cited by SELF-266
// AC 2a and SELF-267 AC 4(c), never re-derived).
// ---------------------------------------------------------------------------------------------

export type PriorYearQ4Window = {
	/** Open between Jan 1 and Jan 15 inclusive. Date-only — carries no paid-ness field (E26-2). */
	open: boolean;
	tax_year: number;
	due_date: string;
};

/** The full pfin.fn_compute_tax_liability(date) jsonb return — ADR-067 Decision 5's canonical shape. */
export type TaxLiabilityPayload = {
	as_of: string;
	tax_year: number;
	decomposition: TaxDecomposition;
	jurisdictions: Record<TaxJurisdictionKey, TaxJurisdictionPayload>;
	nav_components: TaxNavComponents;
	prior_year_q4_window: PriorYearQ4Window;
};

/** The six top-level keys ADR-067 Decision 5 names — the runtime guard checks all six are present. */
const REQUIRED_TOP_LEVEL_KEYS = [
	'as_of',
	'tax_year',
	'decomposition',
	'jurisdictions',
	'nav_components',
	'prior_year_q4_window'
] as const;

/**
 * Load the caller's §2.5 tax-liability payload via pfin.fn_compute_tax_liability, RLS-scoped
 * through the per-request client. NO p_data_as_of — server-derived today (AC 8a on both SELF-264
 * and SELF-266). Throws TaxLiabilityPayloadError on an RPC error or a payload failing the
 * top-level shape guard — see the module header for why this diverges from this directory's
 * dominant fail-soft convention.
 */
export async function loadTaxLiability(supabase: SupabaseClient): Promise<TaxLiabilityPayload> {
	const { data, error } = await supabase.schema('pfin').rpc('fn_compute_tax_liability');

	if (error) {
		throw new TaxLiabilityPayloadError(
			`[taxLiability] fn_compute_tax_liability failed: ${error.message}`
		);
	}

	if (data === null || data === undefined || typeof data !== 'object' || Array.isArray(data)) {
		throw new TaxLiabilityPayloadError(
			`[taxLiability] fn_compute_tax_liability returned a non-object payload: ${
				Array.isArray(data) ? `array length ${data.length}` : typeof data
			}`
		);
	}

	const missing = REQUIRED_TOP_LEVEL_KEYS.filter((key) => !(key in (data as Record<string, unknown>)));
	if (missing.length > 0) {
		throw new TaxLiabilityPayloadError(
			`[taxLiability] fn_compute_tax_liability payload missing top-level key(s): ${missing.join(', ')}`
		);
	}

	// Passthrough, no reshaping — ADR-067 Decision 5 is the contract's canonical home; this
	// function's job is the guard above, not a second copy of the shape.
	return data as TaxLiabilityPayload;
}
