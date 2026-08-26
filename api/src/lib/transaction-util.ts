// transaction-util.ts — browser-side helpers + view types for the SELF-202 manual
// cash-transaction surfaces (entry / edit / recategorize / split). Non-server: ships to
// the browser. The signed-amount transform lives here (single anti-drift point) so the
// entry form, the edit form, and the split editor all convert (direction, magnitude)
// → signed the same way. AMOUNT SIGN CONTRACT (server transaction.ts): `amount` is the
// SIGNED ledger amount (+inflow / −outflow); the entry UX presents a positive magnitude
// + an Inflow/Outflow toggle and derives the sign here (F/CTO-ratified).

import type { ClassifyFailureCode } from '$lib/transactions/classifyFlow';

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

/**
 * Which classifiable() leg refused a row (SELF-249/SELF-248). CLIENT MIRROR of the server's
 * `ClassifiableRefusalReason` (api/src/lib/server/queries/transactions.ts) minus `not_found`
 * (a row that made it into this view exists by construction). Same five strings, so
 * `classifyRefusalCopy` below can serve BOTH a disabled-render reason (this type) and a submit
 * failure `code` (classifyFlow.ts's `ClassifyFailureCode`, a strict superset) from one table.
 */
export type ClassifiableRefusalReason =
	| 'not_standard' // M1 — transaction_type <> 'standard'
	| 'has_security' // M2 — security_id IS NOT NULL
	| 'split_parent' // M4 — split_count > 0. SubCatPicker never actually surfaces this reason
	// (AC7: a split row gets no picker at all, not a disabled one) — kept in the union for
	// parity with the server's reason set, not because a caller is expected to read it.
	| 'is_reversal' // E1 — is_reverse = true
	| 'journaled'; // M3 — annotation.journal_id IS NOT NULL

/**
 * A transaction row as shaped by the account-detail load(). Several fields below (marked EXPECTED
 * CONTRACT) are OPTIONAL: they're additions from issues that ran frontend/backend concurrently
 * (SELF-249's picker-enhancement fields; SELF-340's `security_id`), and Backend's load()
 * extension for a given one may not have landed yet in a given tree. Absent/undefined always
 * reads toward the SAFER default for that field (see each field's own note), never toward
 * silently treating "missing" as "verified." Once Backend wires the loader, no type change is
 * needed here — the fields already exist on this contract.
 */
export type TransactionView = {
	trans_id: number;
	transaction_date: string;
	amount: number;
	vendor: string | null;
	description: string | null;
	transaction_type: string;
	/**
	 * SELF-340 — `pfin.account_trans.security_id`, non-null iff this row is a trade/security leg
	 * (084's biconditional: security_id present ⟺ its annotation's cat='Trade', when classified).
	 * Drives TransactionRow's Edit-button gate: reverseAndReplaceTrans's corrected-row insert
	 * hardcodes `security_id: null` on the replacement (SELF-340 fix) — there is no security-aware
	 * §2.4.3 edit form in V1 (F/CTO ruling, A+C-deferred) — so editing a security-linked row via
	 * the cash-only reverse-and-replace form silently drops the security link.
	 *
	 * ⚠ DEFAULT DIRECTION, deliberately the OPPOSITE of every other EXPECTED-CONTRACT field on
	 * this type: undefined (unwired) reads as "cannot confirm this is cash-only" and HIDES Edit —
	 * fail-closed, not fail-open. Every other field here mirrors a boundary that's already fully
	 * enforced server-side (SELF-248's checkClassifiable shipped and merged before SELF-249 ever
	 * ran), so a permissive client default costs a UX inconsistency at worst. This one does not
	 * have that safety net YET on every tip: as of this field's introduction, Backend's server-side
	 * refusal for a security-linked edit is landing CONCURRENTLY on this same branch, not already
	 * merged — reverseAndReplaceTrans's own corrected-row insert has ALWAYS silently nulled
	 * security_id (nothing currently refuses it), so a permissive default here would leave a real,
	 * live data-corruption window open on any tip where my field lands before Backend's guard does.
	 * Once Backend's field + refusal are both wired, this distinction stops mattering — but until
	 * then, hiding Edit on an unwired row is the safe direction. See TransactionRow's own note.
	 */
	security_id?: number | null;
	is_reverse: boolean;
	replaces_trans_id: number | null;
	created_at: string;
	category: { cat: string | null; sub_cat: string } | null;
	/**
	 * SELF-249 Sec FLAG-D fix — the annotation's RAW sub_cat_id, or null when no override exists
	 * OR the existing annotation is note-only (sub_cat_id itself null). Load-bearing distinction
	 * from `category`: `subCatLabel` (taxonomy.ts) never returns null — a note-only annotation
	 * still produces a non-null `{ cat: null, sub_cat: 'Unsorted' }` — so `category !== null`
	 * conflates "has ANY annotation row" with "has a chosen Sub-Cat". SubCatPicker's `classified`
	 * state keys on THIS field, not on `category`, so a note-only row correctly falls through to
	 * the suggested/hint states instead of rendering a false "solid, nothing to suggest" read.
	 * EXPECTED CONTRACT — see the note above.
	 */
	sub_cat_id?: number | null;
	note: string | null;
	splits: SplitChild[];
	split_count: number;
	/** SELF-249 AC6 — mirrors the server's `checkClassifiable()` predicate (transactions.ts),
	 *  excluding its `not_found` leg. Drives SubCatPicker's disabled-render gate. EXPECTED
	 *  CONTRACT — see the type-level note above; undefined reads as classifiable. */
	classifiable?: boolean;
	/** Populated when `classifiable` is false; null/undefined otherwise. Feeds the disabled-row
	 *  affordance text via `classifyRefusalCopy`. EXPECTED CONTRACT — see the note above. */
	classifiableReason?: ClassifiableRefusalReason | null;
	/** 017:234's provider-category IMMUTABLE display hint. Rendered ghost/muted ONLY when there
	 *  is no override (`category` is null) and no vendor suggestion (`suggested_sub_cat_id` is
	 *  null) — 017's constraint, verbatim: "IMMUTABLE display hint only (R-18). All txns land
	 *  Unsorted; NO auto-map / NO provider_category→sub_cat routing in V1." Applied here:
	 *  display-only, NEVER a write, NEVER auto-mapped to sub_cat_id. EXPECTED CONTRACT — see the
	 *  note above. */
	provider_category?: string | null;
	/** `pfin.fn_suggest_subcat_for_vendor()` result (migration 092) — a posting_prototype id, or
	 *  null when there's no vendor-history match. Meaningful only when `category` is null (an
	 *  existing override always wins over a suggestion). EXPECTED CONTRACT — see the note above. */
	suggested_sub_cat_id?: number | null;
};

/**
 * SELF-249 AC4/AC6 — ONE copy table for BOTH the disabled-row affordance text
 * (`ClassifiableRefusalReason`) and a classify submit failure (`ClassifyFailureCode`,
 * classifyFlow.ts — a strict superset carrying two write-time-only codes this table also
 * covers). Client-authored copy (not a relay of the server's raw message): the server's
 * `CLASSIFIABLE_REFUSAL_MESSAGE` strings are written for a write-time refusal banner; these are
 * written to read equally well as a standing disabled-control note. ⚠ Copy constraint (PM,
 * SELF-249 AC6, verbatim): never say a classified transfer "cancels out" — a journal-less
 * Transfer falls to Suspense, not a clean offset. None of these strings make that claim.
 *
 * Sec NOTE-1: typed as a FULL `Record` over BOTH source unions (not `Record<string, string>`) —
 * the compiler refuses to build this file if a code is ever added to either union without a
 * matching entry here. That caught the five transport-level `ClassifyFailureCode` members
 * (invalid_request/unauthenticated/server_error/network/malformed) this table previously left to
 * the generic fallback. `unauthenticated` deliberately does NOT say "try again" — retrying
 * without re-authenticating fails the identical way, so the copy sends the user to sign in
 * instead of implying a retry will help.
 */
const CLASSIFY_REFUSAL_COPY: Record<ClassifyFailureCode | ClassifiableRefusalReason, string> = {
	not_standard:
		'This is a trade or transfer row — it’s categorized structurally, not through this picker. Use Edit above for a correction.',
	has_security:
		'A securities transaction is categorized by its trade shape, not a Sub-Cat. Use Edit above for a correction.',
	split_parent: 'This transaction is split — classify its individual line items via Split below.',
	is_reversal: 'A reversal row can’t be classified here. Classify the original transaction it replaces.',
	journaled: 'This transaction is posted to a journal. Detach it from the journal, then reclassify.',
	journaled_cat_conflict:
		'This leg is now posted to a journal and can’t take this category. Detach it from the journal, then classify.',
	invalid_sub_cat_id: 'That category is not available. Pick another.',
	// Matches Backend's own TRADE_CONSTRAINT_MESSAGE (transactions.ts) verbatim — one user-facing
	// string for this refusal, not an independently-drifting client paraphrase.
	trade_constraint: 'A Trade category is for security transactions. Pick a cash-flow category instead.',
	not_found: 'This transaction could not be found. Refresh the page and try again.',
	invalid_request: 'That didn’t go through. Refresh the page and pick the category again.',
	unauthenticated: 'Your session has expired. Please sign in again, then reclassify.',
	server_error: 'Something went wrong on our end. Please try again in a moment.',
	network: 'Couldn’t reach the server — check your connection and try again.',
	malformed: 'Something went wrong reading the response. Please refresh the page and try again.'
};

/** code/reason → user-meaningful copy, with a safe generic fallback for a code outside BOTH
 *  known unions (never surfaces a raw server string or a blank error). The table above is
 *  exhaustively typed over every KNOWN code (Sec NOTE-1) — this guard is defense for a genuinely
 *  unrecognized value (a future server code this client hasn't been updated for yet), not a
 *  substitute for keeping the table complete. */
export function classifyRefusalCopy(code: string | null | undefined): string {
	if (code && Object.prototype.hasOwnProperty.call(CLASSIFY_REFUSAL_COPY, code)) {
		return CLASSIFY_REFUSAL_COPY[code as ClassifyFailureCode | ClassifiableRefusalReason];
	}
	return 'Could not save the category. Please try again.';
}

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
