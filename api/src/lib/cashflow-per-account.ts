// cashflow-per-account.ts — browser-safe types + presentation helpers for the §2.3.3 per-account
// cash-flow drill-down UI (SELF-254). NON-server module (ships to the browser) — mirrors
// cashflow-rollup.ts's own established pattern (SELF-251): CashflowPerAccountTable stays purely
// presentational over the types + helpers here, and this file hand-copies the OUTPUT SHAPE of
// Backend's `$lib/server/queries/cashflowPerAccount.ts` (SELF-253), never its I/O — browser code
// cannot import `$lib/server/**` regardless of `import type`. Same hand-kept-copy / drift-risk
// posture as cashflow-rollup.ts: flagged to Backend at hand-off, no automated cross-check exists
// client-side today.
//
// THREE SECTIONS, ALWAYS, UNLIKE THE ROLLUP. `094`'s own contract: "sections is ALWAYS exactly
// three entries in the PRD's ruled order — income, other_cash_flows, expenses — present even
// when empty." Unlike cashflow-rollup.ts's `CASHFLOW_ROLLUP_SECTION_ORDER` (which defends against
// `093`'s cross-account rollup, hard-restricted to Income/Expenses only), this file's order names
// all three keys the shared `CashflowSectionKey` vocabulary can ever hold.
//
// CONSUME, NEVER RECOMPUTE (frontend-engineer discipline #1): every helper below is presentation
// only — section ORDERING and null/zero FORMATTING. No netting, no sign multiplier, no
// re-summation of any column is performed here; `section.total` is rendered exactly as `094`
// computed it. Period-cell formatting (`fmtPeriodCell`) is REUSED from cashflow-rollup.ts, not
// re-derived — it is a pure `(value, formatter) => string` helper with no per-payload-shape
// assumption, so importing it here carries no coupling to the rollup's own section count/order.

/** Mirrors `CashflowSectionKey` (cashflowSections.ts, Backend-owned) — the full three-member §2.3
 *  vocabulary this payload can emit (unlike cashflow-rollup.ts's own copy, which only ever sees
 *  two of the three). */
export type CashflowPerAccountSectionKey = 'income' | 'other_cash_flows' | 'expenses';

/** One (cat, sub_cat) row inside a section — raw amounts from `094`, unmodified. `cat` is carried
 *  as part of the row's IDENTITY (the middle section spans Transfer ∪ Equity, so `(cat, sub_cat)`
 *  is what makes a row unique — see this component's own `#each` key), never rendered as its own
 *  column: the UI stays flat with no Cat-group headers, matching §2.3.2's own shape (AC2). */
export type CashflowPerAccountRow = {
	cat: string;
	sub_cat: string;
	month: number;
	q1: number | null;
	q2: number | null;
	q3: number | null;
	q4: number | null;
	ytd: number;
};

export type CashflowPerAccountSectionTotal = {
	month: number;
	q1: number | null;
	q2: number | null;
	q3: number | null;
	q4: number | null;
	ytd: number;
};

export type CashflowPerAccountSection = {
	sectionKey: CashflowPerAccountSectionKey;
	label: string;
	cats: string[];
	rows: CashflowPerAccountRow[];
	total: CashflowPerAccountSectionTotal;
};

export type CashflowPerAccountUnclassified = {
	count_ytd: number;
};

/** The full §2.3.3 per-account drill-down payload shape, post `normalize()` (server-side —
 *  `sectionKey`/`label` already attached before this UI ever sees it). ⚠ NO `targets` key (AC7 of
 *  cashflowPerAccount.ts's own contract) — targets are §2.3.2 aggregate concepts and do not
 *  attach to a single-account scope; this type has no field for one and this UI must not
 *  synthesise one. */
export type CashflowPerAccount = {
	as_of: string;
	account_id: number;
	sections: CashflowPerAccountSection[];
	unclassified: CashflowPerAccountUnclassified;
};

/** AC1: this drill-down renders EXACTLY these three sections, in this order — Income, then Other
 *  Cash Flows, then Expenses (the middle position is deliberate — PRD's ruled order, unchanged
 *  from the pre-flight recalibration). `094`'s own contract already guarantees this ordering
 *  server-side; this reordering is defense-in-depth on an already-correct contract, not a
 *  workaround for a live gap — same posture as cashflow-rollup.ts's `sectionsToRender`. */
export const CASHFLOW_PER_ACCOUNT_SECTION_ORDER: readonly CashflowPerAccountSectionKey[] = [
	'income',
	'other_cash_flows',
	'expenses'
];

/** Orders `sections` per `CASHFLOW_PER_ACCOUNT_SECTION_ORDER`. A section outside that order (an
 *  unrecognized `sectionKey`) is APPENDED and logged, never silently dropped — team-lead
 *  directive precedent (nonre-allocation.ts's `groupsToRender` / cashflow-rollup.ts's own
 *  `sectionsToRender`): masking a contract regression is worse than a visibly-wrong table. */
export function sectionsToRender(
	sections: CashflowPerAccountSection[]
): CashflowPerAccountSection[] {
	const known: CashflowPerAccountSection[] = [];
	const unexpected: CashflowPerAccountSection[] = [];

	for (const key of CASHFLOW_PER_ACCOUNT_SECTION_ORDER) {
		const match = sections.find((s) => s.sectionKey === key);
		if (match) known.push(match);
	}
	for (const s of sections) {
		if (!CASHFLOW_PER_ACCOUNT_SECTION_ORDER.includes(s.sectionKey)) {
			unexpected.push(s);
		}
	}
	if (unexpected.length > 0) {
		console.error(
			'[cashflow-per-account] unexpected section(s) outside the 3-section contract — rendering visibly rather than dropping:',
			unexpected.map((s) => s.sectionKey)
		);
	}
	return [...known, ...unexpected];
}

/** AC8's empty-state gate: true when NO section has any Sub-Cat row. This is `rows.length === 0`
 *  across all three sections — NOT the same question as "any unclassified items exist" (an
 *  unclassified item never forms a row at all, classified or not — see the page's own header for
 *  how the two combine: `noRows && count_ytd === 0` is the literal AC8 empty state; `noRows &&
 *  count_ytd > 0` still renders the (empty) tables plus the AC7 banner, which already carries the
 *  actionable message for that case). */
export function perAccountHasNoRows(drilldown: CashflowPerAccount): boolean {
	return drilldown.sections.every((s) => s.rows.length === 0);
}

/** The rendered year, derived from `as_of` (`YYYY-MM-DD`) — used only for the AC8 empty-state
 *  copy ("No transactions in [year] for this account."), never for any date arithmetic a reader
 *  might mistake for a reader-rule restatement. */
export function renderedYear(asOf: string): number {
	return Number(asOf.slice(0, 4));
}
