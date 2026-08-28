// cashflow-rollup.ts — browser-safe types + presentation helpers for the §2.3.2.b cross-account
// cash-flow rollup UI (SELF-251). NON-server module (ships to the browser) — mirrors
// nonre-allocation.ts's / nav-composition.ts's own established pattern: CashflowRollupTable stays
// purely presentational over the types + helpers here, and this file hand-copies the OUTPUT SHAPE
// of Backend's `$lib/server/queries/cashflowCrossAccountRollup.ts` (SELF-250), never its I/O —
// browser code cannot import `$lib/server/**` (SvelteKit's build-time guard refuses it regardless
// of `import type`). Same hand-kept-copy / drift-risk posture as nonre-allocation.ts: flagged to
// Backend at hand-off, no automated cross-check exists client-side today.
//
// WHY A SEPARATE FILE FROM cashflowSections.ts: that module (also `$lib/server/queries/**`,
// Backend-owned) is the `cat` → section-key/label VOCABULARY used to build a `CashflowSection` —
// this UI never resolves that vocabulary itself. The loader (`+page.server.ts`) already calls the
// real server-side wrapper, whose `normalize()` step has ALREADY attached `sectionKey`/`label` to
// every section before this file's types ever see the payload. This file only mirrors the
// post-normalize SHAPE, so it needs no copy of the vocabulary table at all — one fewer thing that
// can drift.
//
// CONSUME, NEVER RECOMPUTE (frontend-engineer discipline #1): every helper below is presentation
// only — section ORDERING and null/zero FORMATTING. No netting, no exclusion, no classification
// predicate, no re-summation of any column is performed here; `section.total` is rendered exactly
// as the server computed it (AC5 — the period columns overlap, so a client-side re-sum across
// columns would be actively wrong, not just redundant).

/** Mirrors `CashflowSectionKey` (cashflowSections.ts) — the two keys `093` can ever emit into
 *  this rollup (`other_cash_flows` is a real section-vocabulary member but is NEVER a member of
 *  this payload's `sections[]` — 093's own `sections` CTE is hard-restricted to
 *  `('Revenue','Expense')`, see cashflowCrossAccountRollup.ts's AC5 note). */
export type CashflowSectionKey = 'income' | 'expenses' | 'other_cash_flows';

export type CashflowSectionRow = {
	sub_cat: string;
	month: number;
	q1: number | null;
	q2: number | null;
	q3: number | null;
	q4: number | null;
	ytd: number;
};

export type CashflowSectionTotal = {
	month: number;
	q1: number | null;
	q2: number | null;
	q3: number | null;
	q4: number | null;
	ytd: number;
};

export type CashflowSection = {
	cat: string;
	sectionKey: CashflowSectionKey | undefined;
	label: string;
	rows: CashflowSectionRow[];
	total: CashflowSectionTotal;
};

export type CashflowTargets = {
	income_target_annual: number | null;
	expense_target_monthly: number | null;
};

export type CashflowUnclassified = {
	count_ytd: number;
};

export type CashflowCrossAccountRollup = {
	as_of: string;
	sections: CashflowSection[];
	targets: CashflowTargets;
	unclassified: CashflowUnclassified;
};

/** AC1: this rollup renders EXACTLY these two sections, in this order — Income before Expenses.
 *  `093`'s own `sections` CTE is hard-restricted to `('Revenue','Expense')` in this order (see
 *  cashflowCrossAccountRollup.ts's module header), so this ordering is defense-in-depth on an
 *  already-correct contract, not a workaround for a live gap — mirrors nonre-allocation.ts's
 *  `NONRE_TABLE_CAT_ORDER` / `groupsToRender` posture exactly. */
export const CASHFLOW_ROLLUP_SECTION_ORDER: readonly CashflowSectionKey[] = ['income', 'expenses'];

/** Orders `sections` per `CASHFLOW_ROLLUP_SECTION_ORDER`. A section outside that order (an
 *  unrecognized `sectionKey`, including `other_cash_flows` — never expected on THIS payload — or
 *  `undefined`) is APPENDED and logged, never silently dropped — team-lead directive precedent
 *  (nonre-allocation.ts's own `groupsToRender`, 2026-08-20): masking a contract regression is
 *  worse than a visibly-wrong table. */
export function sectionsToRender(sections: CashflowSection[]): CashflowSection[] {
	const known: CashflowSection[] = [];
	const unexpected: CashflowSection[] = [];

	for (const key of CASHFLOW_ROLLUP_SECTION_ORDER) {
		const match = sections.find((s) => s.sectionKey === key);
		if (match) known.push(match);
	}
	for (const s of sections) {
		if (!CASHFLOW_ROLLUP_SECTION_ORDER.includes(s.sectionKey as CashflowSectionKey)) {
			unexpected.push(s);
		}
	}
	if (unexpected.length > 0) {
		console.error(
			'[cashflow-rollup] unexpected section(s) outside the Income/Expenses contract — rendering visibly rather than dropping:',
			unexpected.map((s) => s.cat)
		);
	}
	return [...known, ...unexpected];
}

/** AC8 empty-state gate: true when NEITHER section has any Sub-Cat row. Distinguishes the
 *  zero-transaction empty state from the zero-classified empty state via `unclassified.count_ytd`
 *  at the call site — this helper only answers "is there anything to render as rows at all." */
export function rollupHasNoRows(rollup: CashflowCrossAccountRollup): boolean {
	return rollup.sections.every((s) => s.rows.length === 0);
}

/** AC2: section header caption — the section label plus its target value as inline text; `null`
 *  render as NO caption at all (never "Target: —" or similar placeholder). Income's target is an
 *  ANNUAL figure (`income_target_annual`); Expenses' is MONTHLY (`expense_target_monthly`) — the
 *  two sections read different fields with different units, not a shared "target" lookup. A
 *  stored `$0` target is a real target and gets a caption (AC2's own NULL-vs-zero distinction) —
 *  only `null` suppresses the caption. */
export function sectionTargetCaption(
	section: CashflowSection,
	targets: CashflowTargets,
	usd: Intl.NumberFormat
): string | null {
	if (section.sectionKey === 'income') {
		return targets.income_target_annual === null
			? null
			: `Target ${usd.format(targets.income_target_annual)}/yr`;
	}
	if (section.sectionKey === 'expenses') {
		return targets.expense_target_monthly === null
			? null
			: `Target ${usd.format(targets.expense_target_monthly)}/mo`;
	}
	return null;
}

/** AC8's degenerate-cell rendering, passed through UNCHANGED from the server (never re-derived
 *  here): `null` → em-dash (the quarter hasn't started relative to `as_of`); a real number
 *  (including `0`) → formatted currency. AC10: negative values render with their real sign —
 *  `Intl.NumberFormat`'s own currency formatting already renders a leading minus for a negative
 *  amount, so no `signDisplay` override and no `Math.abs()` is applied anywhere in this file. */
export function fmtPeriodCell(value: number | null, usd: Intl.NumberFormat): string {
	return value === null ? '—' : usd.format(value);
}
