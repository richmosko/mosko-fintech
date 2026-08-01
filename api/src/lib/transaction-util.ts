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

/**
 * A held security as shaped by the account-detail load() for the stock-split picker
 * (SELF-203). `security_id` = pfin.asset.asset_id (the value posted to the split RPC).
 * Backend derives the list via fn_holdings_as_of → join pfin.asset for symbol/name;
 * the display label is composed browser-side (securityLabel) so label shape stays here.
 */
export type SecurityOption = { security_id: number; symbol: string | null; name: string | null };

/** "SYMBOL — Name" when both present; else whichever exists; else a stable id fallback. */
export function securityLabel(s: SecurityOption): string {
	if (s.symbol && s.name) return `${s.symbol} — ${s.name}`;
	return s.symbol ?? s.name ?? `Security #${s.security_id}`;
}

/**
 * A manual↔provider candidate-duplicate pair (SELF-204), as shaped by the account-detail
 * load() from pfin.manual_provider_dup_candidate. DETECTION-ONLY: read-only, no action —
 * the user reconciles through existing mechanisms; resolution/reconciled-state is SELF-205.
 */
export type DupCandidate = {
	account_id: number;
	manual_trans_id: number;
	manual_date: string;
	manual_amount: number;
	manual_vendor: string | null;
	manual_description: string | null;
	provider_trans_id: number;
	provider: string;
	provider_txn_id: string;
	provider_date: string;
	provider_amount: number;
	import_hash: string;
};

/**
 * One per-account sync-history row (SELF-204), from pfin.linked_source_sync_history. The two
 * count keys are JSONB-extracted scalars → null when the key is absent. Read-only (no edit/
 * delete affordance — AC requirement, RBAC-tested).
 */
export type SyncHistoryRow = {
	provider: string;
	source: string;
	created_at: string;
	transactions_inserted: number | null;
	transactions_skipped: number | null;
};

/** Sync-trigger source → friendly label; unknown sources pass through raw. (Copy = UX's call.) */
export function syncSourceLabel(source: string): string {
	if (source === 'webhook') return 'Webhook';
	if (source === 'scheduled_poll') return 'Scheduled';
	if (source === 'manual') return 'Manual'; // SELF-317 user-initiated "Sync now" provenance
	return source;
}

/**
 * Deterministic timestamp format — locale AND time-zone pinned (like money()'s pinned locale)
 * so the SSR and client renders match (unpinned toLocale* would drift server-TZ vs browser-TZ
 * → hydration mismatch). Rendered in UTC for determinism; the TZ-display choice is a UX/Visual
 * decision flagged, not settled here.
 */
export function formatTimestamp(iso: string): string {
	const d = new Date(iso);
	if (Number.isNaN(d.getTime())) return iso;
	return d.toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'UTC' });
}

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
