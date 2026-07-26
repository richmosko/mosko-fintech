// transaction-util.ts — browser-side helpers + view types for the SELF-202 manual
// cash-transaction surfaces (entry / edit / recategorize / split). Non-server: ships to
// the browser. The signed-amount transform lives here (single anti-drift point) so the
// entry form, the edit form, and the split editor all convert (direction, magnitude)
// → signed the same way. AMOUNT SIGN CONTRACT (server transaction.ts): `amount` is the
// SIGNED ledger amount (+inflow / −outflow); the entry UX presents a positive magnitude
// + an Inflow/Outflow toggle and derives the sign here (F/CTO-ratified).

/** Inflow ('in') = positive; Outflow ('out') = negative. */
export type Direction = 'in' | 'out';

/** A grouped <optgroup> shape for SelectField (cat → its sub-cats). */
export type SubCatGroup = { label: string; options: { value: string; label: string }[] };

/** A split child as shaped by load() — note: labels only, NO sub_cat_id (recovered by label). */
export type SplitChild = {
	id: number;
	amount: number;
	cat: string | null;
	sub_cat: string;
	note: string | null;
	display_order: number | null;
};

/** A transaction row as shaped by the account-detail load(). */
export type TransactionView = {
	trans_id: number;
	transaction_date: string;
	amount: number;
	vendor: string | null;
	description: string | null;
	transaction_type: string;
	is_reverse: boolean;
	replaces_trans_id: number | null;
	created_at: string;
	category: { cat: string | null; sub_cat: string } | null;
	note: string | null;
	splits: SplitChild[];
	split_count: number;
};

/**
 * (direction, positive-magnitude string) → SIGNED decimal string for the POST + client
 * validation. Outflow ⇒ negative. Strips any stray leading '-' the user typed (the field
 * is always presented as positive). Empty magnitude passes through empty so the schema
 * surfaces "Enter an amount." rather than a spurious "-".
 */
export function toSignedAmount(direction: Direction, magnitude: string): string {
	const bare = magnitude.trim().replace(/^-/, '');
	if (bare === '') return '';
	return direction === 'out' ? `-${bare}` : bare;
}

/** SIGNED number → { direction, magnitude } for seeding an edit form from an existing row. */
export function fromSignedAmount(signed: number): { direction: Direction; magnitude: string } {
	return { direction: signed < 0 ? 'out' : 'in', magnitude: String(Math.abs(signed)) };
}

/** Neutral money format — ledger amount, NEVER --c-pos/--c-neg coloured (design §5 fence 1). */
export function money(raw: string | number): string {
	const n = typeof raw === 'number' ? raw : Number(raw);
	if (!Number.isFinite(n)) return String(raw);
	return n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

/** Ten-thousandths (numeric(20,4) scale) for float-safe split-balance math. */
export function toUnits(n: number): number {
	return Math.round(n * 10000);
}

/** Group a flat Sub-Cat option list by `cat` into accessible <optgroup> groups (server order kept). */
export function subCatGroupsOf(
	subCats: { id: number; cat: string; sub_cat: string }[]
): SubCatGroup[] {
	const byCat = new Map<string, { value: string; label: string }[]>();
	for (const s of subCats) {
		if (!byCat.has(s.cat)) byCat.set(s.cat, []);
		byCat.get(s.cat)!.push({ value: String(s.id), label: s.sub_cat });
	}
	return [...byCat.entries()].map(([cat, options]) => ({ label: cat, options }));
}

/**
 * Best-effort recover a sub_cat_id from its (cat, sub_cat) labels — load() embeds labels,
 * not ids, on transactions/splits, so seeding a category picker for edit/recategorize/
 * re-split needs a label→id lookup against the picker groups. No match → '' (Unsorted).
 */
export function matchSubCatId(
	groups: SubCatGroup[],
	cat: string | null,
	sub_cat: string
): string {
	if (!cat) return '';
	const g = groups.find((x) => x.label === cat);
	return g?.options.find((x) => x.label === sub_cat)?.value ?? '';
}
