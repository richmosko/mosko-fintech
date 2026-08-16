// asset-classify.ts — browser-side view types + helpers for the SELF-200/SELF-235 symbol
// classify surface (§2.4.1.e / §2.2.1.b). Non-server: ships to the browser. Label + metadata-hint
// formatting lives here (single anti-drift point) so the list row + any future surface shape the
// hint the same way.
//
// `PendingSymbol` / `SymbolListItem` mirror the shapes Backend's loadSymbols() returns (source of
// truth: src/lib/server/queries/pendingSymbols.ts — SymbolListItem/SymbolClassification). They
// are browser-side VIEW TYPES, not a re-import of the server module (Frontend never imports
// `$lib/server/**`); PageData already carries the same shape structurally — these named aliases
// are for the child row prop. If Backend changes the load shape, update these in lockstep.

/** One ever-transacted asset's shared hint fields. `metadata` is the asset's raw jsonb blob
 *  (already-stored linked-provider/manual attributes — AC5: no external fetch); rendered as a
 *  NON-preselected hint. Kept as its own type (rather than folded into SymbolListItem) because the
 *  hint-formatting helpers below only need this subset. */
export type PendingSymbol = {
	asset_id: number;
	symbol: string | null;
	name: string | null;
	asset_type: string;
	metadata: unknown;
};

/** SELF-235 AC1: the caller's CURRENT (Cat, Sub-Cat) for an asset — `null` = unclassified (the
 *  pending state; AC5 badge trigger). Mirrors Backend's SymbolClassification. */
export type SymbolClassification = { sub_cat_id: number; cat: string; sub_cat: string } | null;

/** One row in the SELF-235 full symbols list — PendingSymbol's hint fields plus its current
 *  classification (or `null` = pending). Mirrors Backend's SymbolListItem. */
export type SymbolListItem = PendingSymbol & { classification: SymbolClassification };

/** "Cat › Sub-Cat" chip text for an already-classified row; `null` when pending (the row renders
 *  the neutral "Pending" chip instead — see SymbolClassifyRow). */
export function classificationLabel(c: SymbolClassification): string | null {
	if (!c) return null;
	return c.cat ? `${c.cat} › ${c.sub_cat}` : c.sub_cat;
}

/** Coerce metadata to a plain-object record, or null (arrays / scalars / null are not records). */
function asRecord(meta: unknown): Record<string, unknown> | null {
	if (!meta || typeof meta !== 'object' || Array.isArray(meta)) return null;
	return meta as Record<string, unknown>;
}

/** The `description` metadata value, iff it's a non-empty string — else null. Promoted to the
 *  Name row when the asset has no first-class `name` (UX punch-list §3 suppress note). */
export function descriptionOf(meta: unknown): string | null {
	const rec = asRecord(meta);
	const d = rec?.description;
	return typeof d === 'string' && d.trim() !== '' ? d : null;
}

/** Best display name: first-class `name`, else a promoted metadata `description`, else null. */
export function displayName(p: PendingSymbol): string | null {
	return p.name ?? descriptionOf(p.metadata);
}

/** Primary hint label: "SYMBOL — Name" when both present; else whichever exists; else id fallback.
 *  (Name here includes a promoted `description` so a description-only security still reads.) */
export function pendingLabel(p: PendingSymbol): string {
	const name = displayName(p);
	if (p.symbol && name) return `${p.symbol} — ${name}`;
	return p.symbol ?? name ?? `Asset #${p.asset_id}`;
}

// ── Metadata-key label map (UX punch-list §3) ─────────────────────────────────────────────
// Known linked-provider metadata keys → friendly labels. Lowercased keys. `security_type`/`type`
// → "Provider type" (NOT "Type") to disambiguate the provider's taxonomy value from our own
// asset_type "Type" row, which the row renders first-class.
const HINT_LABELS: Record<string, string> = {
	security_type: 'Provider type',
	type: 'Provider type',
	close_price: 'Close price',
	close_price_as_of: 'Price as of',
	iso_currency_code: 'Currency',
	unofficial_currency_code: 'Currency',
	sector: 'Sector',
	industry: 'Industry',
	exchange: 'Exchange',
	market_identifier_code: 'Market (MIC)',
	mic: 'Market (MIC)',
	is_cash_equivalent: 'Cash equivalent',
	cusip: 'CUSIP',
	isin: 'ISIN',
	figi: 'FIGI',
	sedol: 'SEDOL',
	coupon: 'Coupon',
	coupon_rate: 'Coupon',
	maturity: 'Maturity',
	maturity_date: 'Maturity',
	expiry: 'Expiry',
	expiration_date: 'Expiry',
	contract_multiplier: 'Contract multiplier',
	multiplier: 'Contract multiplier',
	strike: 'Strike',
	strike_price: 'Strike'
};

// Keys never rendered as a hint: those shown first-class elsewhere on the row, plus plumbing /
// ids / cursors / timestamps. `*_datetime` is matched by suffix (covers update_datetime etc.).
const HINT_SUPPRESS = new Set([
	'ticker',
	'ticker_symbol',
	'symbol',
	'name',
	'asset_type',
	'description',
	'institution_id',
	'institution_security_id',
	'security_id',
	'proxy_security_id',
	'item_id',
	'source',
	'sync_cursor',
	'update_datetime',
	'created_at',
	'updated_at'
]);

const ACRONYMS = new Set(['cusip', 'isin', 'figi', 'sedol', 'mic', 'iso']);

function isSuppressed(key: string): boolean {
	const k = key.toLowerCase();
	return HINT_SUPPRESS.has(k) || k.endsWith('_datetime');
}

/** Deterministic humanizer for unknown keys: snake_case/camelCase → Title Case, known acronyms
 *  upper-cased. (Unknown keys SHOW — density-first; cap bounds flooding.) */
function humanizeKey(key: string): string {
	return key
		.replace(/([a-z0-9])([A-Z])/g, '$1 $2') // split camelCase
		.replace(/[_-]+/g, ' ')
		.trim()
		.split(/\s+/)
		.filter(Boolean)
		.map((w) =>
			ACRONYMS.has(w.toLowerCase()) ? w.toUpperCase() : w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()
		)
		.join(' ');
}

/** A metadata key → its display label: known map first, else deterministic humanization. */
export function labelForHintKey(key: string): string {
	return HINT_LABELS[key.toLowerCase()] ?? humanizeKey(key);
}

/**
 * Scalar top-level metadata entries surfaced as display hints (AC3: the hint is SHOWN, never
 * auto-applied / preselected into the picker). Defensive over the unknown jsonb blob: object-only
 * input, scalar values only (nested objects / arrays / nulls skipped), suppress-filtered (keys
 * shown first-class or plumbing), labels via labelForHintKey, booleans → Yes/No, capped so a large
 * blob can't flood the row. INV-1 plain text throughout.
 */
export function hintEntries(meta: unknown, cap = 6): { label: string; value: string }[] {
	const rec = asRecord(meta);
	if (!rec) return [];
	const out: { label: string; value: string }[] = [];
	for (const [k, v] of Object.entries(rec)) {
		if (v == null || typeof v === 'object') continue;
		if (isSuppressed(k)) continue;
		out.push({
			label: labelForHintKey(k),
			value: typeof v === 'boolean' ? (v ? 'Yes' : 'No') : String(v)
		});
		if (out.length >= cap) break;
	}
	return out;
}

// ── SELF-235 AC2 cascading Cat → Sub-Cat picker helpers ───────────────────────────────────────
// The reassignment editor is two selects, not one grouped select (subCatGroupsOf in
// transaction-util.ts, the flat-grouped shape SELF-200 used): pick a Cat first, then a Sub-Cat
// filtered to it. `SubCatOption` (Backend's taxonomy.ts shape) carries no Cat id — Cat is a plain
// label — so the Cat select's `value` IS the label; only the Sub-Cat select's `value` is a real id
// (the one posted as `sub_cat_id`).

type SubCatLike = { id: number; cat: string; sub_cat: string };
type Opt = { value: string; label: string };

/** Browser-side VIEW TYPE mirroring Backend's SubCatOption (src/lib/server/queries/taxonomy.ts) —
 *  NOT a re-import (Frontend never imports `$lib/server/**`); PageData already carries this shape
 *  structurally. Update in lockstep if Backend's shape changes. */
export type SubCatOption = { id: number; cat: string; sub_cat: string; display_order: number | null };

/** Distinct Cat labels for the Cat picker, deduped by first occurrence, server (display_order)
 *  order preserved. */
export function catOptionsOf(subCats: readonly Pick<SubCatLike, 'cat'>[]): Opt[] {
	const seen = new Set<string>();
	const out: Opt[] = [];
	for (const s of subCats) {
		if (seen.has(s.cat)) continue;
		seen.add(s.cat);
		out.push({ value: s.cat, label: s.cat });
	}
	return out;
}

/** Sub-Cat options for ONE chosen Cat — the second cascade step, id-valued (the value posted back
 *  on Save). Empty Cat ⇒ empty list (the Sub-Cat select stays disabled until a Cat is chosen). */
export function subCatOptionsForCat(subCats: readonly SubCatLike[], cat: string): Opt[] {
	if (!cat) return [];
	return subCats.filter((s) => s.cat === cat).map((s) => ({ value: String(s.id), label: s.sub_cat }));
}
