// asset-classify.ts — browser-side view types + helpers for the SELF-200 pending-symbol
// classify surface (§2.4.1.e). Non-server: ships to the browser. Label + metadata-hint formatting
// lives here (single anti-drift point) so the list row + any future surface shape the hint the
// same way.
//
// `PendingSymbol` mirrors the shape Backend's loadPendingSymbols() returns (source of truth:
// src/lib/server/queries/pendingSymbols.ts). It is a browser-side VIEW TYPE, not a re-import of
// the server module (Frontend never imports `$lib/server/**`); PageData already carries the same
// shape structurally — this named alias is for the child row prop. If Backend changes the load
// shape, update this in lockstep.

/** One held-but-unclassified asset. `metadata` is the asset's raw jsonb blob (already-stored
 *  linked-provider/manual attributes — AC5: no external fetch); rendered as a NON-preselected hint. */
export type PendingSymbol = {
	asset_id: number;
	symbol: string | null;
	name: string | null;
	asset_type: string;
	metadata: unknown;
};

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
