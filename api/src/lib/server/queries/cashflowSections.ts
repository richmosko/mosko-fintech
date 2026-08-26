// cashflowSections.ts — the SINGLE home for §2.3 cash-flow section vocabulary: which `cat` values
// (the ratified 5-class posting vocabulary — Revenue/Expense/Transfer/Equity/Trade, migration
// `028`) belong to which product-facing section, and what that section is labelled. Backend-owned
// server surface (ARCH §4.1 allowlist).
//
// WHY THIS FILE EXISTS (V1.3 pre-flight sitting item 11a, verified live against
// docs/records/v13-preflight/sitting-log.md at authoring time): "class-set is NOT a reader
// parameter — `where cat = any(p_cats)` drops every NULL-`cat` row and would silently zero the
// S-2 banner on every surface; each surface partitions, vocabulary lives in a shared
// `cashflowSections.ts` module (provisional name; `usEquitySubCats.ts` precedent)." Migration `093`
// (pfin.fn_cashflow_cross_account_rollup) accordingly emits RAW `cat` values only — no product
// label, no section grouping — and SELF-250's own AC5 requires the label to be "sourced from the
// shared section-map module, never typed into the function." This file is that module — the same
// single-source-of-truth shape `usEquitySubCats.ts` already established for the §2.2.3 Sub-Cat
// list, applied here to the §2.3 class/section vocabulary instead.
//
// THE MAPPING, cited from the V1.3 pre-flight sitting's ratified A-10 footnote (item 11, D-2
// option B — "Income → Revenue, Expenses → Expense, Other Cash Flows → Transfer∪Equity"):
//   Income          <- Revenue
//   Expenses        <- Expense
//   Other Cash Flows <- Transfer, Equity
// `Trade` is EXCLUDED from every §2.3 surface (D-2 ruling, "Trade stays excluded across §2.3 —
// mechanical") — it has no section and is deliberately absent from CASHFLOW_CLASS_TO_SECTION.
//
// TWO CONSUMERS, ONE TABLE — SELF-250 (§2.3.2, this migration wave) renders ONLY the Income and
// Expenses sections (093's own `sections` CTE is hard-restricted to `('Revenue','Expense')`);
// SELF-253 (§2.3.3 drill-down) is the Other Cash Flows / Transfer∪Equity consumer. Both read the
// SAME table below rather than each carrying a partial copy — a partial copy is exactly how the
// vocabulary would drift between the two surfaces.
//
// A SECTION KEY, NOT JUST A LABEL. `CashflowSectionKey` is the app-side grouping identity;
// `CASHFLOW_SECTION_LABELS` is the copy layer over it. Keeping the two separate (rather than
// keying everything off the label string) means a future copy change is a one-line edit to the
// label table, not a rename of the grouping key every partition site reads.

/** The ratified 5-class posting vocabulary (migration `028`'s CHECK constraint on
 *  `pfin.user_taxonomy.cat` for `domain = 'cashflow'` rows) — read live from `028` if this ever
 *  needs re-verifying, never trusted as a copy of a copy. */
export type CashflowClass = 'Revenue' | 'Expense' | 'Transfer' | 'Equity' | 'Trade';

/** The three §2.3 product-facing sections. `other_cash_flows` is the D-2 (B) composed section —
 *  it renders identically to Transfer-only today (Equity is CHECK-legal but unseeded — `041`:
 *  12/7/4/4/0) and gains a second contributing class only as-and-when Equity prototypes are
 *  seeded; that is a data fact, not something this module encodes. */
export type CashflowSectionKey = 'income' | 'expenses' | 'other_cash_flows';

/** Product label per section — the ONLY place §2.3 section copy is spelled. A consumer renders
 *  this string; it does not construct its own from the `cat` value. */
export const CASHFLOW_SECTION_LABELS: Record<CashflowSectionKey, string> = {
	income: 'Income',
	expenses: 'Expenses',
	other_cash_flows: 'Other Cash Flows'
};

/** `cat` -> section key. `Trade` has NO entry — it is excluded from every §2.3 surface by the D-2
 *  ruling, not merely unmapped by omission; a lookup miss on `Trade` and a lookup miss on a truly
 *  unrecognized value are the SAME "not part of §2.3" answer, which is why both degrade the same
 *  way in `cashflowSectionKey` below rather than one throwing and the other returning undefined. */
export const CASHFLOW_CLASS_TO_SECTION: Readonly<Partial<Record<CashflowClass, CashflowSectionKey>>> =
	{
		Revenue: 'income',
		Expense: 'expenses',
		Transfer: 'other_cash_flows',
		Equity: 'other_cash_flows'
	};

/** Safe `cat` -> section-key lookup. `undefined` for `Trade` and for any value outside the
 *  ratified vocabulary (a DB/app drift, not a state this module invents a fallback label for) —
 *  mirrors `account-display.ts`'s fallback-to-raw-value discipline, except here there is no
 *  sensible raw fallback (a `cat` with no section has nowhere to render), so the caller gets an
 *  explicit `undefined` to handle rather than a silently wrong section. */
export function cashflowSectionKey(cat: string): CashflowSectionKey | undefined {
	return (CASHFLOW_CLASS_TO_SECTION as Record<string, CashflowSectionKey | undefined>)[cat];
}

/** Safe `cat` -> product label lookup, composing `cashflowSectionKey` + `CASHFLOW_SECTION_LABELS`.
 *  `undefined` under the same conditions as `cashflowSectionKey` — NEVER falls back to the raw
 *  `cat` string, because a raw posting-vocabulary value ("Revenue") is not itself acceptable
 *  product copy the way a raw account-type enum value coincidentally is in `account-display.ts`. */
export function cashflowSectionLabel(cat: string): string | undefined {
	const key = cashflowSectionKey(cat);
	return key ? CASHFLOW_SECTION_LABELS[key] : undefined;
}
