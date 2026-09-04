// tax-decomposition.ts — browser-safe types + presentation helpers for the §2.5.1 tax-relevant
// income decomposition table (SELF-264). NON-server module (ships to the browser) — mirrors the
// SHAPE of Backend's `$lib/server/queries/taxLiability.ts` (`TaxDecomposition` /
// `OrdinaryIncomeRow` / `CapitalGainsUnavailable`) and `taxes/decomposition/+page.server.ts`'s
// load-return, verified against those files on `feature/self-264-266-backend` (commits 0a7234b /
// 570a4d6 / 0b1e92f) after merge — NOT a guess. Browser code cannot import `$lib/server/**`, so
// this is a hand-kept mirror; if Backend's shape moves, this file needs a matching edit (same
// drift posture as `nonre-allocation.ts` / `cashflow-rollup.ts`'s own mirrors).
//
// KEY CONTRACT FACTS THAT SHAPE THIS TABLE:
//
//   `decomposition.ordinary_income` is `{ rows: OrdinaryIncomeRow[], total: number }` — a FLAT
//   row list (each row carries its own `cat`), not pre-grouped, and ONE `amount` per row — NOT
//   three per-row amounts. Cat-grouping (AC4's "Cat-grouped headers, Sub-Cat rows") is therefore
//   done HERE, client-side, by folding `rows` on `.cat` — a pure presentational fold, not a
//   money-path derivation (mirrors NonReAllocationTable's own `groupsToRender`-style precedent).
//   `total` is server-authoritative — the footing Total row reads it DIRECTLY, never a
//   client-re-summed figure (mirrors NonReAllocationTable's `$Alloc` foot cell reading
//   `allocation.total_non_re` directly). Per-Cat-group SUBTOTALS are NOT server-precomputed, so
//   those ARE client-summed from each group's own rows (same precedent as
//   `groupTargetSubtotal`).
//
//   AC2's "three-column table — Ordinary / ST CG / LT CG" has NO per-row ST CG / LT CG figure
//   anywhere in the shipped payload — `capital_gains` carries no `rows` key at all (R1; see
//   `CapitalGainsSection` below) and no other key names a per-Sub-Cat capital-gain amount. Every
//   row's `amount` renders under the Ordinary column; the ST CG and LT CG columns render "—" for
//   EVERY row, unconditionally — not because of anything about that specific row, but because
//   there is structurally no capital-gain figure to place there in V1.4 (matches the "vacuous
//   under R1-A" carried-forward framing: the table is shaped for when a sale-recording capability
//   lands and `capital_gains` gets rows, but nothing routes there today). This component
//   deliberately does NOT map `tax_character` to a column — that would be re-deriving Backend's
//   own (hardcoded, per migration `011`'s header) tax-routing rule client-side. `tax_character` is
//   rendered as an informational chip only (AC5) — see TaxDecompositionTable.svelte's own header
//   for the bubble-up note this reading produced.

/**
 * One row of `pfin.tax_character` (migration `011`, 5 seeded codes, FK-enforced — GLOBAL
 * shared-read reference data, not a client-side enum), as `+page.server.ts` fetches it: `code` +
 * `label` (+ `display_order`, carried for fidelity with the loader's own row shape — already
 * applied server-side via `.order('display_order')`, not re-sorted here). AC5: this component
 * renders WHATEVER `label` the loader's catalog hands it — it never maintains its own code→label
 * switch, so a V2+ seeded addition to the registry (a 6th code) does not require a client change.
 */
export interface TaxCharacterRow {
	code: string;
	label: string;
	display_order: number | null;
}

export type TaxCharacterCatalog = TaxCharacterRow[];

/**
 * One Sub-Cat row in the Ordinary Income decomposition — mirrors Backend's `OrdinaryIncomeRow`
 * exactly (`taxLiability.ts`, verified post-merge). `tax_character` is nullable (a tax-relevant
 * row with no assigned character); `sub_cat_id` is NOT nullable — this reader is Revenue-class
 * scoped (ADR-067 Consequences: "Revenue-class scope is a fence, not a filter"), so an
 * unclassified item never appears as a row here — it is counted, not listed, via
 * `decomposition.unclassified.count_ytd`.
 */
export interface DecompositionRow {
	sub_cat_id: number;
	cat: string;
	sub_cat: string;
	tax_character: string | null;
	amount: number;
}

/**
 * Resolve a row's `tax_character` code against the loader's catalog — NEVER a bare
 * `catalog.find(...)` at the render site, so a code missing from the catalog (a stale client
 * build against a newly-seeded V2+ code, or a malformed payload) fails visibly rather than
 * throwing or silently rendering `undefined`. `null` (no character assigned) renders as `null`
 * here too — the call site decides how to display "no character," never this function guessing.
 * Falls back to the raw code as its own label — never a guessed English string.
 */
export function lookupTaxCharacter(
	catalog: TaxCharacterCatalog,
	code: string | null
): { code: string; label: string } | null {
	if (code === null) return null;
	const found = catalog.find((c) => c.code === code);
	return found ? { code: found.code, label: found.label } : { code, label: code };
}

/** One Cat-group, folded client-side from `ordinary_income.rows` (see this file's own header). */
export interface DecompositionGroup {
	cat: string;
	rows: DecompositionRow[];
}

/**
 * Fold the FLAT `ordinary_income.rows` list into Cat-groups, preserving each Cat's FIRST-SEEN
 * order (server row order is the ordering authority — this performs no re-sort within or across
 * groups). Pure presentational grouping, not a money-path derivation.
 */
export function groupByCat(rows: DecompositionRow[]): DecompositionGroup[] {
	const order: string[] = [];
	const byCat = new Map<string, DecompositionRow[]>();
	for (const row of rows) {
		if (!byCat.has(row.cat)) {
			byCat.set(row.cat, []);
			order.push(row.cat);
		}
		byCat.get(row.cat)!.push(row);
	}
	return order.map((cat) => ({ cat, rows: byCat.get(cat)! }));
}

/**
 * AC 3a / R1 (A) — the Capital Gains section renders UNAVAILABLE-with-a-reason, never zeros.
 * ADR-067 Decision 5(b): `capital_gains` is `{status, reason}` with NO `rows` key at all — an
 * empty `rows: []` beside a status is a second way to say the same thing and invites a consumer
 * to render it, so this type carries no such key even as an optional. `reason` is `string` (not a
 * narrower literal) — matches Backend's own `CapitalGainsUnavailable` type exactly; R1 guarantees
 * it is `'no_sale_recording_capability'` at runtime today, but this component gates on `status`
 * only and never branches on the specific reason string.
 */
export interface CapitalGainsSection {
	status: 'unavailable';
	reason: string;
}

/** AC 3b — S-2 one-source count: the SAME query that sums Income also counts what it excluded. */
export interface UnclassifiedSummary {
	count_ytd: number;
}

/** `decomposition` — the §2.5.1-relevant slice of `104`'s payload (mirrors `TaxDecomposition`). */
export interface TaxDecomposition {
	ordinary_income: {
		rows: DecompositionRow[];
		/** Server-authoritative footing total — the foot row reads this directly, never a
		 *  client-re-summed figure. */
		total: number;
	};
	capital_gains: CapitalGainsSection;
	unclassified: UnclassifiedSummary;
}

/**
 * The §2.5.1-relevant slice of the full `fn_compute_tax_liability` payload (ADR-067 Decision 5).
 * `data.liability` on the real page is the FULL `TaxLiabilityPayload` (also carrying
 * `jurisdictions` / `nav_components` / `prior_year_q4_window` / `as_of`, per ADR-067 Decision 1 —
 * one composed source, not a per-surface reader) — this interface types only the fields §2.5.1
 * reads; the wider real object satisfies it structurally.
 */
export interface TaxLiabilitySlice {
	tax_year: number;
	decomposition: TaxDecomposition;
}

/** AC7 predicate name, kept trivial and named so a call site reads as intent, not as `> 0`. */
export function hasUnclassifiedItems(unclassified: UnclassifiedSummary): boolean {
	return unclassified.count_ytd > 0;
}

/**
 * PM's copy, minus its trailing "classify" word — the ONE source of the sentence's text. The
 * render boundary makes "classify" a link (matches CashflowRollupTable's own established split
 * between static banner text and its "classify" CTA), so the live template appends a literal
 * `classify` anchor after this string rather than re-typing the sentence.
 */
export function unclassifiedCopyPrefix(unclassified: UnclassifiedSummary): string {
	return `${unclassified.count_ytd} items unclassified — any may be income —`;
}

/** PM's copy, EXACT, as one inert string (e.g. for a plain-text context) — composed from the
 *  SAME prefix the live template renders, so the two can never diverge. */
export function unclassifiedCopy(unclassified: UnclassifiedSummary): string {
	return `${unclassifiedCopyPrefix(unclassified)} classify`;
}

/**
 * A Cat-group's Ordinary-column subtotal — plain addition over the group's own rows, NOT a
 * re-derivation of any server money-path decision (mirrors NonReAllocationTable's
 * `groupTargetSubtotal` for the columns Backend does not precompute).
 */
export function groupSubtotal(rows: DecompositionRow[]): number {
	return rows.reduce((sum, r) => sum + r.amount, 0);
}

/** AC9(i) — the Income section is empty iff there are zero rows at all. */
export function incomeIsEmpty(rows: DecompositionRow[]): boolean {
	return rows.length === 0;
}

/** Cell formatter — NULL renders "—", never "$0" (item 8: NULL/unavailable never coalesced to $0). */
export function fmtCell(amount: number | null, usd: Intl.NumberFormat): string {
	return amount === null ? '—' : usd.format(amount);
}

/**
 * The `/taxes/decomposition` `+page.server.ts` load-return shape, verified against that file
 * post-merge (`taxes/decomposition/+page.server.ts`, commit 570a4d6). `liability` is
 * non-nullable — the loader is FAIL-LOUD (throws `TaxLiabilityPayloadError` on any RPC or shape
 * failure rather than degrading to `null`; SvelteKit's default 500 page handles that case, not a
 * null-check here), diverging from this codebase's dominant fail-soft convention (see
 * `taxLiability.ts`'s own module header for why: "the payload IS the page").
 */
export interface TaxDecompositionPageData {
	liability: TaxLiabilitySlice;
	taxCharacters: TaxCharacterCatalog;
	inventorySeedDeltaMigration: string;
}
