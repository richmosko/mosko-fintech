// transactions.ts — server-side write helpers for the manual cash-transaction surfaces
// (SELF-202 §2.4.3.a; migration 038 / ADR-032). Backend-owned server source.
//
// The immutable 004 ledger means edits are NEVER an UPDATE — they are reverse-and-replace
// (INSERT a reversal + INSERT the corrected row). Splits go through the un-dormed 029 write
// path under the locked child-lifecycle rule ({0 children} XOR {N children Σ=parent}). All
// writes run as the caller through the per-request anon client, so RLS (wr_access-JOIN + the
// aal2 backstop), the 004 matched-account fence, the #10 annotation + #13 split matched-tenant
// fences, and the 029 Σ=parent deferred trigger are the security + correctness boundary. No
// skip/exclusion anywhere (ADR-032).

import type { SupabaseClient } from '@supabase/supabase-js';
import type { ManualTransEdit, SplitSet, StockSplitCreate } from '$lib/server/schemas/transaction';
import { computeImportHash } from '$lib/server/dedup/importHash';
import type { ZoneResolvedAsOf } from '$lib/server/time/asOf';

export type WriteResult =
	| { ok: true; transId?: number }
	| { ok: false; status: number; field?: string; code?: string; message: string };

/** DB raise-message → cross-tenant Sub-Cat classification (the #10 / #13 matched-tenant fences). */
function isCrossTenantSubCat(message: string): boolean {
	return /sub_cat|Decision 3|matched-tenant/i.test(message);
}

/**
 * DB raise-message → migration 092's NEW `fn_account_trans_annotation_journaled_cat_fence`
 * trigger (D-8 / SELF-248 AC10; V1.3 pre-flight sitting items 6a + 15). Keys off the message
 * PREFIX (team-lead, confirmed live against 092's authored text), NOT a bare `/journal/i`
 * substring test: `pfin.fn_account_trans_annotation_matched_journal` (033, the #12 matched-tenant
 * JOURNAL ATTACH fence — a completely different write, this endpoint never sets journal_id) also
 * raises "journal attach rejected: ... (... matched-tenant leg fence ...)" — a real collision a
 * loose "journal" substring test would have folded into this code, mislabeling a cross-tenant
 * journal-attach rejection as this endpoint's own defense-in-depth. 092's two raises both start
 * "journaled-leg classification ..." (the "fence:" unresolvable-prototype leg and the "rejected:"
 * defect-state leg) — a prefix neither of 033's or 023's raises share. Kept as its own named
 * classifier (not folded into `isCrossTenantSubCat`) because the two must map to DISTINCT response
 * codes — D-8 condition 6's binding requirement that the app-level `journaled` pre-check refusal
 * and this DB-level defense-in-depth raise stay DISTINGUISHABLE to the caller.
 */
function isJournaledCatFenceRejection(message: string): boolean {
	return /^journaled-leg classification/i.test(message);
}

/**
 * The single user-facing rendering of 092's journaled-cat-fence rejection, shared by
 * `classifyTrans` (below) and `upsertAnnotation` (SELF-249 Sec FLAG-2) so the two call sites
 * cannot drift onto two different guidance strings for the same DB raise.
 */
const JOURNALED_CAT_CONFLICT_MESSAGE =
	'This leg is now posted to a journal as Revenue, Expense, or Equity — reclassifying it that way is blocked to protect the journal. Detach it, then classify.';
/**
 * DB raise-message → 058 §(4)'s CLOSED-ACCOUNT TRANSFER-IN FENCE.
 *
 * ⚠ EXPORTED AND SHARED ON PURPOSE. Three write paths reach this fence — manual entry
 *   (fn_create_manual_trans, 038), reverse-and-replace (below), and stock-split entry
 *   (fn_create_stock_split, 039) — because all three INSERT into pfin.account_trans, which 058
 *   fences. A private copy per call site is how the classifications in this codebase drift; the
 *   duplicated `isCrossTenantSubCat` (this file AND [account_id]/+page.server.ts, two identical
 *   regexes maintained separately) is the precedent NOT to follow, and is flagged rather than
 *   fixed here — a drive-by dedup of a working fence belongs in its own change.
 *
 * Matches on the `write blocked:` prefix, which 058 chose to be subject-carrying precisely
 * because THREE different fences in this schema use the word "closed" for three different
 * subjects (037's closed JOURNAL freeze raises `journal % cannot close:`; the §2.4.5 onboarding
 * close-gate is a third). Matching on "closed" alone would collide with all of them.
 */
export function isClosedAccountWrite(message: string): boolean {
	return /write blocked:.*is closed/i.test(message);
}

/**
 * The single user-facing rendering of that fence.
 *
 * ⚠ IT CARRIES THE REMEDY, AND THAT IS THE ENTIRE POINT. The generic fallbacks these call sites
 *   used before said "Please try again" — RETRY ADVICE FOR SOMETHING THAT CAN NEVER SUCCEED,
 *   while the database was supplying the exact remedy the app then discarded. A closed account
 *   does not become writable by retrying; it becomes writable by being reopened.
 *
 * The raise interpolates the account id and the table name (tg_table_name). Both are operator
 * detail and neither is surfaced — the user already knows which account they are looking at, and
 * the table name names an implementation.
 */
export const CLOSED_ACCOUNT_WRITE_MESSAGE =
	'This account is closed, so it can no longer accept entries. Reopen it, make the change, then close it again.';

/** DB raise-message → the 029 Σ=parent balance violation. */
function isImbalance(message: string): boolean {
	return /imbalance|sum to|Σ|parent\.amount/i.test(message);
}

// ── fn_create_stock_split (039) raise-message classifiers → friendly, field-scoped errors.
// The RPC RAISEs are the authoritative guard (Zod pre-validates ratio positivity, so a
// bad-ratio raise is normally unreachable; the position/provider/visibility raises are
// DB-only and reachable). Order the checks most-specific-first at the call site.
/** account not owned / not visible under RLS → 404 (no existence leak). */
function isAccountNotVisible(message: string): boolean {
	return /not found or not visible|fail closed/i.test(message);
}
/** the source-of-truth guard: a provider-linked account rejects manual splits. */
function isProviderLinked(message: string): boolean {
	return /provider-linked|linked_source_id|reconciliation/i.test(message);
}
/** no live position for the chosen security as-of the ex-date → nothing to split. */
function isNoPosition(message: string): boolean {
	return /no live position|nothing to split/i.test(message);
}
/** ratio invalid (non-positive-rational) or a no-op (1:1 / zero delta). */
function isBadRatio(message: string): boolean {
	return /positive rational|zero delta|no-op/i.test(message);
}

/** Compare two 4-dp money values (numeric(20,4)); DB may return numeric as string. */
function moneyEq(a: number | string, b: number | string): boolean {
	return Math.abs(Number(a) - Number(b)) < 5e-5;
}

/**
 * Upsert (or clear) the 023 category/note annotation for a transaction. Both null → delete
 * the annotation (revert to Unsorted-pending). Fenced by the #10 chain-resolved matched-tenant
 * trigger (a cross-tenant Sub-Cat fails closed) + ata_* wr_access RLS.
 */
export async function upsertAnnotation(
	supabase: SupabaseClient,
	transId: number,
	subCatId: number | null,
	note: string | null
): Promise<WriteResult> {
	if (subCatId === null && note === null) {
		const { error } = await supabase
			.schema('pfin')
			.from('account_trans_annotation')
			.delete()
			.eq('trans_id', transId);
		if (error) return { ok: false, status: 422, message: 'Could not clear the category.' };
		return { ok: true, transId };
	}
	const { error } = await supabase
		.schema('pfin')
		.from('account_trans_annotation')
		.upsert({ trans_id: transId, sub_cat_id: subCatId, note }, { onConflict: 'trans_id' });
	if (error) {
		// SELF-249 Sec FLAG-2: 092's journaled-cat-fence raise must be classified BEFORE
		// isCrossTenantSubCat. Its defect-state leg's raise text contains "(sub_cat_id %)", which
		// isCrossTenantSubCat's /sub_cat/i test also matches — so without this ORDERING, a user
		// recategorizing a journaled leg saw "That category is not available" (names the wrong
		// problem: the category IS valid, it's the leg's journal attachment that blocks the write)
		// instead of the actionable reclassify-then-attach guidance `classifyTrans` (below) already
		// gives on the same DB raise. Checked first here for the identical reason.
		if (isJournaledCatFenceRejection(error.message))
			return {
				ok: false,
				status: 409,
				field: 'sub_cat_id',
				code: 'journaled_cat_conflict',
				message: JOURNALED_CAT_CONFLICT_MESSAGE
			};
		if (isCrossTenantSubCat(error.message))
			return { ok: false, status: 422, field: 'sub_cat_id', message: 'That category is not available.' };
		return { ok: false, status: 422, field: 'sub_cat_id', message: 'Could not save the category.' };
	}
	return { ok: true, transId };
}

/**
 * E1 write-side refusal (SELF-249 binding option-B item 1 — F/CTO-ruled at the PR #561 Sec joint
 * review, 2026-08-25; Linear SELF-249 comment). The OLD recategorize path
 * (`accounts/[account_id]/+page.server.ts`'s `recategorize` action) must refuse `is_reverse` rows.
 * Measured gap: 084's P3 CASE + its txn CTE carry no `is_reverse` term, and
 * TransactionRow.svelte:224 gates row actions on `!frozen` only — so the shipped UI rendered
 * "Categorize" on reversal rows, and a classified reversal's contra would post as real income or
 * spending.
 *
 * This is the ONLY live leg of `classifyTrans`'s classifiable() set reachable through THIS path —
 * M1 (not_standard) / M4 (split_parent) are inert here (084's P3 CASE / txn CTE never surface
 * those rows to this action to begin with), M2 (has_security) is fenced by 084:1233's
 * biconditional, M3 (journaled) is fenced path-independently by 092's DB trigger (via
 * `isJournaledCatFenceRejection` above, now also reachable through `upsertAnnotation`'s FLAG-2
 * fix). Deliberately NARROW — NOT the full classifiable() gate: Sec's option-A analysis scoped the
 * full gate as needing its own vitest coverage of its own; the ruled scope here is the E1 leg
 * alone. Do not expand this to the other four legs without surfacing that as a scope change.
 *
 * A not-found / not-visible-under-RLS row returns `ok` here rather than a separate refusal — no
 * existence leak, and the write path's own fences (FK + RLS) already produce the correct outcome
 * for that case unchanged by this check.
 */
export async function checkNotReversalForRecategorize(
	supabase: SupabaseClient,
	transId: number
): Promise<'ok' | 'refused' | 'error'> {
	const { data, error } = await supabase
		.schema('pfin')
		.from('account_trans')
		.select('trans_id, is_reverse')
		.eq('trans_id', transId)
		.maybeSingle();
	if (error) {
		console.error('[transactions] recategorize E1 reversal check failed:', error.message);
		return 'error';
	}
	if (data?.is_reverse) return 'refused';
	return 'ok';
}

/** The single user-facing rendering of the E1 refusal above — same reason vocabulary as
 *  `classifyTrans`'s `is_reversal` message (CLASSIFIABLE_REFUSAL_MESSAGE below), adapted to the
 *  recategorize verb per the binding comment's "same reason vocabulary where sensible". */
export const REVERSAL_RECATEGORIZE_MESSAGE =
	'A reversal row cannot be recategorized. Recategorize the original transaction it replaces.';

// ── SELF-248 §2.3.1.a classify backend (V1.3 pre-flight re-derived ACs; docs/records/
// v13-preflight/rederived-acs.md) ─────────────────────────────────────────────────────────

/** Which S-1/S-4 classifiability rule refused the write (AC4 — a typed error naming the rule),
 *  or `not_found` for a row invisible/absent under the caller's own RLS (rd_access). */
export type ClassifiableRefusalReason =
	| 'not_found'
	| 'not_standard' // M1 (030:153) — transaction_type <> 'standard'
	| 'has_security' // M2 (084:1233 biconditional) — security_id IS NOT NULL
	| 'split_parent' // M4 — split_count > 0 (the parent; children carry the categories)
	| 'is_reversal' // E1 (a) — is_reverse = true
	| 'journaled'; // M3 (033:403) — annotation.journal_id IS NOT NULL

const CLASSIFIABLE_REFUSAL_MESSAGE: Record<ClassifiableRefusalReason, string> = {
	not_found: 'Transaction not found.',
	not_standard: 'This is a trade or transfer row — it is categorized structurally, not through this picker.',
	has_security: 'A securities transaction is categorized by its trade shape, not a Sub-Cat.',
	split_parent: 'This transaction is split — classify its individual line items instead.',
	is_reversal: 'A reversal row cannot be classified. Classify the original transaction it replaces.',
	journaled:
		'This transaction is posted to a journal. Detach it from the journal before reclassifying, then re-attach.'
};

type ClassifiabilityResult =
	| { status: 'classifiable'; annotationExists: boolean }
	| { status: 'refused'; reason: ClassifiableRefusalReason }
	| { status: 'error' };

/**
 * The S-1 classifiability predicate (V1.3 pre-flight sitting item 3a; generalized to a write-time
 * refusal by the S-4 ruling, sitting item 6a): `classifiable(row) := transaction_type='standard'
 * AND security_id IS NULL AND split_count=0 AND is_reverse=false AND (annotation IS NULL OR
 * annotation.journal_id IS NULL)`.
 *
 * ⚠ THIS CHECK IS THE ONLY ENFORCEMENT for four of its five legs — M1/M2/M4/E1 carry NO DB fence
 * (SELF-248 AC10 condition 5: the app guard "stays app-layer" for exactly this reason, and the
 * function COMMENT on migration 092's new trigger says so). Only the fifth leg (M3/journaled) is
 * ALSO DB-fenced (092's `fn_..._journaled_cat_fence`, defense-in-depth against a race between this
 * read and the write below). Read-only; runs under the caller's own RLS (rd_access-JOIN via the
 * account chain) — a cross-tenant / not-visible trans_id reads as `not_found`, never a distinct
 * "exists but not yours" signal (no existence leak, the codebase-wide convention).
 */
export async function checkClassifiable(
	supabase: SupabaseClient,
	transId: number
): Promise<ClassifiabilityResult> {
	const { data: trans, error: transErr } = await supabase
		.schema('pfin')
		.from('account_trans')
		.select('trans_id, transaction_type, security_id, is_reverse')
		.eq('trans_id', transId)
		.maybeSingle();
	if (transErr) {
		console.error('[transactions] classifiability trans read failed:', transErr.message);
		return { status: 'error' };
	}
	if (!trans) return { status: 'refused', reason: 'not_found' };
	if (trans.transaction_type !== 'standard') return { status: 'refused', reason: 'not_standard' };
	if (trans.security_id !== null) return { status: 'refused', reason: 'has_security' };
	if (trans.is_reverse) return { status: 'refused', reason: 'is_reversal' };

	// split_count is DERIVED (029/035 precedent — never a stored column): count the child set.
	const { count: splitCount, error: splitErr } = await supabase
		.schema('pfin')
		.from('account_trans_split')
		.select('id', { count: 'exact', head: true })
		.eq('account_trans_id', transId);
	if (splitErr) {
		console.error('[transactions] classifiability split-count read failed:', splitErr.message);
		return { status: 'error' };
	}
	if ((splitCount ?? 0) > 0) return { status: 'refused', reason: 'split_parent' };

	const { data: ann, error: annErr } = await supabase
		.schema('pfin')
		.from('account_trans_annotation')
		.select('trans_id, journal_id')
		.eq('trans_id', transId)
		.maybeSingle();
	if (annErr) {
		console.error('[transactions] classifiability annotation read failed:', annErr.message);
		return { status: 'error' };
	}
	if (ann?.journal_id != null) return { status: 'refused', reason: 'journaled' };

	return { status: 'classifiable', annotationExists: ann != null };
}

/**
 * POST /api/transactions/:id/classify write path (SELF-248 AC1/AC2/AC4/AC6/AC9). UPSERTs
 * pfin.account_trans_annotation on trans_id — INSERT when absent, UPDATE of sub_cat_id ONLY when
 * present. The immutable 004 ledger is NEVER written (AC3/Lock 10 — this function never touches
 * pfin.account_trans).
 *
 * ⚠ DELIBERATELY NOT `upsertAnnotation` ABOVE. That helper's upsert payload always includes
 *   `note` (even when the caller passes null), so reusing it here would NULL OUT an existing
 *   note on every classify — AC1 requires touching ONLY sub_cat_id. Omitting `note`/`metadata`/
 *   `journal_id` from THIS payload entirely means PostgREST's generated `ON CONFLICT DO UPDATE
 *   SET` touches ONLY sub_cat_id (it sets exactly the columns present in the insert payload) —
 *   the other columns on an existing row are untouched. Same table, same trans_id PK, same #10
 *   matched-tenant fence + FK as `upsertAnnotation` / `fn_create_manual_trans` (038) — AC9's "no
 *   second write path" holds: this is a second CALL SITE into the ONE annotation row, not a
 *   second write path.
 *
 * AC6: cross-tenant/cross-vocabulary Sub-Cat rejection is already DB-enforced (the FK to
 * pfin.posting_prototype + the #10 fence, 023/084) — not re-implemented; only mapped to a 400.
 * D-8 condition 6: the app-level `journaled` pre-check refusal (above, in checkClassifiable) and
 * migration 092's new journaled-cat-fence trigger raise are DISTINCT codes (`journaled` vs
 * `journaled_cat_conflict`) even though the fence's raise is normally unreachable through this
 * function (checkClassifiable already refuses `journaled` rows before any write is attempted) —
 * it is defense-in-depth against a race between the read above and this write, not the primary
 * gate.
 */
export async function classifyTrans(
	supabase: SupabaseClient,
	transId: number,
	subCatId: number
): Promise<WriteResult> {
	const check = await checkClassifiable(supabase, transId);
	if (check.status === 'error')
		return { ok: false, status: 500, message: 'Could not verify this transaction. Please try again.' };
	if (check.status === 'refused') {
		if (check.reason === 'not_found') return { ok: false, status: 404, message: CLASSIFIABLE_REFUSAL_MESSAGE.not_found };
		return {
			ok: false,
			status: 409,
			field: 'sub_cat_id',
			code: check.reason,
			message: CLASSIFIABLE_REFUSAL_MESSAGE[check.reason]
		};
	}

	const { error } = await supabase
		.schema('pfin')
		.from('account_trans_annotation')
		.upsert({ trans_id: transId, sub_cat_id: subCatId }, { onConflict: 'trans_id' });

	if (error) {
		console.error('[transactions] classify write failed:', error.code, error.message);
		if (isJournaledCatFenceRejection(error.message))
			return {
				ok: false,
				status: 409,
				field: 'sub_cat_id',
				code: 'journaled_cat_conflict',
				message: JOURNALED_CAT_CONFLICT_MESSAGE
			};
		if (isCrossTenantSubCat(error.message) || error.code === '23503')
			return {
				ok: false,
				status: 400,
				field: 'sub_cat_id',
				code: 'invalid_sub_cat_id',
				message: 'That category is not available.'
			};
		return { ok: false, status: 500, message: 'Could not save the category. Please try again.' };
	}

	return { ok: true, transId };
}

/**
 * Fact edit = reverse-and-replace on the immutable 004 ledger, atomic for the two ledger rows
 * via a single bulk INSERT (one PostgREST statement = one txn). The reversal mirrors the
 * original (negated amount/quantity) and points at it (is_reverse=true, replaces_trans_id); the
 * corrected row is a fresh fact (is_reverse=false, replaces_trans_id NULL). Per the dedup rule,
 * both new rows carry NULL source_provider/provider_txn_id — the provider identity stays on the
 * original only (avoids the 017 account_trans_provider_dedup_idx collision). import_hash differs
 * by row (SELF-204 / ADR-034 D4 + Consequences b): the reversal row is always NULL; the corrected
 * replacement gets a FRESH content hash when the original was manual (source_provider NULL) so an
 * edited manual entry stays detectable against a provider echo, and NULL when the original was
 * provider-sourced (its import_hash stays on the original only). The corrected row's category/note
 * is a follow-up
 * 023 annotation upsert (benign if it fails — the row is then Unsorted-pending, a valid state;
 * the money-critical {reversal, replacement} pair already committed atomically).
 */
export async function reverseAndReplaceTrans(
	supabase: SupabaseClient,
	accountId: number,
	v: ManualTransEdit
): Promise<WriteResult> {
	// (1) The original, RLS-scoped to the caller's account. Not found / not owner → 404.
	const { data: orig } = await supabase
		.schema('pfin')
		.from('account_trans')
		.select('trans_id, account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, is_reverse, source_provider')
		.eq('account_id', accountId)
		.eq('trans_id', v.orig_trans_id)
		.maybeSingle();
	if (!orig) return { ok: false, status: 404, message: 'Transaction not found.' };
	if (orig.is_reverse)
		return { ok: false, status: 409, message: 'A reversal row cannot be edited.' };

	// (2) Double-edit guard: refuse if this row was already reversed (an is_reverse row already
	// points at it). Not a hard DB constraint — TOCTOU-narrow, single-user; a partial-unique
	// index on replaces_trans_id would harden it (Architect flag).
	const { count: reversedCount } = await supabase
		.schema('pfin')
		.from('account_trans')
		.select('trans_id', { count: 'exact', head: true })
		.eq('replaces_trans_id', v.orig_trans_id)
		.eq('is_reverse', true);
	if ((reversedCount ?? 0) > 0)
		return { ok: false, status: 409, message: 'This transaction has already been edited.' };

	// (3) Atomic bulk INSERT of {reversal, corrected}. One statement — both rows pass the
	// account_trans_insert wr_access RLS (same account) + the reversal passes the 004
	// matched-account fence (same account_id as its replaces_trans_id target).
	const reversal = {
		account_id: accountId,
		transaction_date: orig.transaction_date,
		amount: -Number(orig.amount),
		vendor: orig.vendor,
		description: orig.description,
		transaction_type: orig.transaction_type,
		security_id: orig.security_id,
		quantity: -Number(orig.quantity ?? 0),
		is_reverse: true,
		replaces_trans_id: orig.trans_id
	};
	// SELF-204 (ADR-034 D4 + Consequences b): the corrected row is a fresh MANUAL fact — give it a
	// fresh content hash (via the SAME shared module the provider mapper uses) so an edited manual
	// entry stays detectable against a provider echo. BUT when the ORIGINAL was provider-sourced,
	// its provider identity (incl. import_hash) stays on the original ONLY — the replacement carries
	// NULL (per ADR-034 Consequences b; avoids re-imprinting a provider row's identity onto a manual
	// correction). The reversal row (below) always carries NULL. The 040-relaxed hash index is
	// non-unique, so a duplicate manual hash no longer aborts.
	const correctedImportHash =
		orig.source_provider == null
			? computeImportHash({
					accountId,
					date: v.transaction_date,
					amount: v.amount,
					vendor: v.vendor,
					description: v.description
				})
			: null;
	const corrected = {
		account_id: accountId,
		transaction_date: v.transaction_date,
		amount: v.amount,
		vendor: v.vendor,
		description: v.description,
		transaction_type: orig.transaction_type, // preserve the fact-kind (cash = 'standard')
		is_reverse: false,
		import_hash: correctedImportHash
		// security_id NULL + quantity 0 default (017 cash CHECK); provider cols NULL (manual origin)
	};

	const { data: inserted, error: insErr } = await supabase
		.schema('pfin')
		.from('account_trans')
		.insert([reversal, corrected])
		.select('trans_id, is_reverse');
	if (insErr || !inserted) {
		console.error('[transactions] reverse-and-replace INSERT failed:', insErr?.message);
		// 058 §(4): a closed account is FROZEN — this INSERT can never succeed while it is closed,
		// so "try again" is advice that cannot work. 409, not 422: the request is well-formed and
		// the account's STATE is the conflict (same reading as the close control's already-closed
		// refusal).
		if (insErr && isClosedAccountWrite(insErr.message))
			return { ok: false, status: 409, message: CLOSED_ACCOUNT_WRITE_MESSAGE };
		return { ok: false, status: 422, message: 'Could not save the edit. Please try again.' };
	}

	const correctedRow = inserted.find((r) => r.is_reverse === false);
	const newId = correctedRow?.trans_id as number | undefined;

	// (4) Carry the category/note onto the corrected row (best-effort — benign if it fails).
	if (newId && (v.sub_cat_id !== null || v.note !== null)) {
		const ann = await upsertAnnotation(supabase, newId, v.sub_cat_id, v.note);
		if (!ann.ok)
			console.warn('[transactions] corrected row committed but annotation failed:', ann.message);
	}
	return { ok: true, transId: newId };
}

/**
 * Split CREATE or REPLACE — write a balanced child set over the 029 path. REPLACE semantics:
 * delete the whole existing set, then insert the new balanced set (delete-first, so there is
 * NO double-count window — worst case on a partial failure is the split reverts to unsplit,
 * which is money-safe: the parent is then counted whole). We pre-check Σ(lines)=parent.amount
 * for a clean field error; the 029 deferred Σ=parent trigger remains the authoritative backstop.
 *
 * NOTE (atomicity): delete + insert are two PostgREST statements (two txns) — SvelteKit/PostgREST
 * cannot span them in one txn without a DB function (038 authored none; migrations are Architect's).
 * A future fn_replace_split RPC would make REPLACE single-txn; flagged, not blocking (money-safe today).
 */
export async function writeSplitSet(
	supabase: SupabaseClient,
	accountId: number,
	v: SplitSet
): Promise<WriteResult> {
	// (1) Parent, RLS-scoped. Not found / not owner → 404.
	const { data: parent } = await supabase
		.schema('pfin')
		.from('account_trans')
		.select('trans_id, amount, is_reverse')
		.eq('account_id', accountId)
		.eq('trans_id', v.trans_id)
		.maybeSingle();
	if (!parent) return { ok: false, status: 404, message: 'Transaction not found.' };
	if (parent.is_reverse)
		return { ok: false, status: 409, message: 'A reversal row cannot be split.' };

	// (2) Σ pre-check (UX; the deferred trigger is the real gate).
	const linesSum = v.lines.reduce((acc, l) => acc + l.amount, 0);
	if (!moneyEq(linesSum, parent.amount))
		return {
			ok: false,
			status: 400,
			field: 'lines',
			message: `Split lines must sum to ${Number(parent.amount)} (they total ${linesSum}).`
		};

	// (3) REPLACE: clear the existing set first (no double-count window).
	const { error: delErr } = await supabase
		.schema('pfin')
		.from('account_trans_split')
		.delete()
		.eq('account_trans_id', v.trans_id);
	if (delErr) {
		console.error('[transactions] split clear failed:', delErr.message);
		return { ok: false, status: 422, message: 'Could not update the split. Please try again.' };
	}

	// (4) Insert the new balanced set (single statement).
	const rows = v.lines.map((l) => ({
		account_trans_id: v.trans_id,
		sub_cat_id: l.sub_cat_id,
		amount: l.amount,
		note: l.note,
		display_order: l.display_order
	}));
	const { error: insErr } = await supabase.schema('pfin').from('account_trans_split').insert(rows);
	if (insErr) {
		console.error('[transactions] split insert failed:', insErr.message);
		if (isCrossTenantSubCat(insErr.message))
			return { ok: false, status: 422, field: 'lines', message: 'A chosen category is not available.' };
		if (isImbalance(insErr.message))
			return { ok: false, status: 400, field: 'lines', message: `Split lines must sum to ${Number(parent.amount)}.` };
		// Delete already committed → the split is now cleared; ask the user to retry.
		return { ok: false, status: 422, field: 'lines', message: 'Could not save the split (it was cleared — please re-enter).' };
	}
	return { ok: true, transId: v.trans_id };
}

/**
 * UNSPLIT — delete the entire child set → revert to parent-only counting. Single DELETE
 * statement (atomic). RLS-scoped (split_delete wr_access-JOIN via the parent chain), so a
 * cross-tenant parent deletes nothing. Idempotent (no children → no-op).
 */
export async function unsplitTrans(
	supabase: SupabaseClient,
	transId: number
): Promise<WriteResult> {
	const { error } = await supabase
		.schema('pfin')
		.from('account_trans_split')
		.delete()
		.eq('account_trans_id', transId);
	if (error) {
		console.error('[transactions] unsplit failed:', error.message);
		return { ok: false, status: 422, message: 'Could not remove the split. Please try again.' };
	}
	return { ok: true, transId };
}

/**
 * Stock split — record a POSITION-LEVEL book-neutral corp_action via the atomic
 * fn_create_stock_split INVOKER RPC (SELF-203; migration 039 / ADR-033). Everything runs as
 * the caller through the per-request anon client, so the RPC's guards ARE the boundary:
 *   - cross-tenant → the account read / fn_holdings_as_of see nothing → fail closed;
 *   - a provider-linked account is rejected (source-of-truth guard — its splits arrive via the
 *     SELF-204 reconciliation path, never manual fan-in, to avoid double-restatement);
 *   - a 1:1 (no-op) ratio and an empty position are rejected.
 * The RPC INSERTs ONE book-neutral row (amount=0, cost_basis NULL, quantity=delta) + its 023
 * annotation in ONE txn and returns the new corp_action trans_id. We map each RAISE to a
 * friendly, field-scoped WriteResult. NO amount/sign handling here — a split moves quantity,
 * not money.
 */
export async function createStockSplit(
	supabase: SupabaseClient,
	accountId: number,
	v: StockSplitCreate
): Promise<WriteResult> {
	const { data: newId, error: rpcErr } = await supabase
		.schema('pfin')
		.rpc('fn_create_stock_split', {
			p_account_id: accountId,
			p_security_id: v.security_id,
			p_ratio_num: v.ratio_num,
			p_ratio_den: v.ratio_den,
			p_ex_date: v.ex_date
		});

	if (rpcErr) {
		const msg = rpcErr.message;
		console.error('[transactions] createStockSplit RPC failed:', msg);
		// 058 §(4) closed-account fence, checked BEFORE the 039-specific classifications: a closed
		// account rejects the write regardless of which 039 guard would also have had an opinion,
		// and its remedy (reopen first) is the one the user must act on first.
		if (isClosedAccountWrite(msg))
			return { ok: false, status: 409, message: CLOSED_ACCOUNT_WRITE_MESSAGE };
		if (isAccountNotVisible(msg)) return { ok: false, status: 404, message: 'Account not found.' };
		if (isProviderLinked(msg))
			return {
				ok: false,
				status: 422,
				message:
					'This account is linked to a provider — its splits are applied automatically during reconciliation, not entered manually.'
			};
		if (isNoPosition(msg))
			return {
				ok: false,
				status: 422,
				field: 'security_id',
				message: 'No holdings of that security as of the ex-date — nothing to split.'
			};
		if (isBadRatio(msg))
			return {
				ok: false,
				status: 400,
				field: 'ratio_num',
				message: 'Enter a positive split ratio that actually changes the share count (a 1:1 ratio is a no-op).'
			};
		return { ok: false, status: 422, message: 'Could not record the stock split. Please try again.' };
	}

	return { ok: true, transId: newId as number };
}

/** One held-security option for the stock-split picker AND the SELF-325 P-b account-detail
 *  read-side signal. `security_id` is pfin.asset.asset_id — the value the form posts back as
 *  `security_id` (matches Frontend's SecurityOption + fn_create_stock_split's p_security_id).
 *  `quantity` is the current held share count (display). */
export type HeldSecurity = {
	security_id: number;
	symbol: string | null;
	name: string | null;
	quantity: number;
	/**
	 * SELF-325 P-b (F/CTO-ratified, Architect catch criterion): TRUE iff `pfin.fn_asset_priced_flags`
	 * (089) reports this asset priced as of `asOf`. 089 IS the single definition of this predicate —
	 * `pfin.fn_create_manual_purchase` (088) calls the SAME function for its write-time `priced`
	 * composite field, so a purchase's confirmation and its later account-detail rendering can
	 * never disagree about the same holding BY CONSTRUCTION, not by two implementations being kept
	 * in step by hand.
	 *
	 * ⚠ HISTORY (Sec C3 → Sec F1, SELF-325 round 10): this flag was previously computed by a
	 * TypeScript reimplementation in this file that both this comment and 088's header claimed was
	 * "reused verbatim" from 088's inline SQL. That was never achievable — verbatim reuse across a
	 * SQL/TypeScript boundary is impossible by construction — and the claim went unchecked: the TS
	 * took the FIRST row per asset with NO tiebreak among rows sharing the max price_date, which was
	 * NONDETERMINISTIC at a same-date tie (Sec C3), and separately fetched the ENTIRE price history
	 * <= asOf for every held asset with no bound, which could exceed PostgREST's row cap on as few
	 * as two ordinarily-priced holdings and silently render the unpriced marker on a CORRECTLY-PRICED
	 * one (Sec F1). Both defects were one root cause — two implementations required to agree with
	 * nothing forcing agreement — and 089 removes the class rather than re-aligning the instance.
	 * See `loadPricedFlags` and 089's own migration header for the full predicate + imprecision
	 * this function still carries (bool_or over the max-price_date rows; not a valuation primitive).
	 *
	 * Fail-CLOSED on a read error: defaults to `false` (unpriced) rather than `true` — a read
	 * failure must never present as "this holding is fine."
	 */
	priced: boolean;
};

/**
 * Per-asset "has a usable current price" flag, keyed by asset_id — SELF-325 P-b / F1, delegated
 * entirely to `pfin.fn_asset_priced_flags` (089; see HeldSecurity.priced's own comment for the
 * history). One RPC call, one row per DISTINCT requested asset_id — 089's contract guarantees a
 * row for every id passed (never NULL, never absent: an id with no visible usable price returns
 * `false`), so this function's job is purely marshaling the RPC result into a Map, not computing
 * the predicate.
 *
 * ⚠ THIS IS WHAT CLOSES SEC'S F1 (Architect, SELF-325 round 10, verbatim): the result set is now
 * bounded by the caller's HOLDING COUNT, not by price history, so PostgREST's row cap is
 * unreachable BY CONSTRUCTION — never re-introduce a raw `eod_price` fetch here; that is exactly
 * the shape that broke (an asset priced daily by one source for three years is ~750 rows, and two
 * such holdings exceeded the 1000-row cap, silently truncating the highest asset_ids to
 * priced:false).
 *
 * RLS-scoped (089 is SECURITY INVOKER; 019's eod_price_select admits a price row iff global-OR-
 * owned) — the SAME visibility `loadHeldSecurities`'s asset label read already relies on, so no
 * asset here is visible for a price check that wasn't already visible for its label.
 */
async function loadPricedFlags(
	supabase: SupabaseClient,
	assetIds: number[],
	asOf: ZoneResolvedAsOf
): Promise<Map<number, boolean>> {
	const out = new Map<number, boolean>();
	const { data, error } = await supabase
		.schema('pfin')
		.rpc('fn_asset_priced_flags', { p_asset_ids: assetIds, p_as_of: asOf });
	if (error) {
		// Fail-CLOSED: an unverifiable read must never present as "priced" — return an empty map
		// so every asset_id defaults to false at the call site, same as "no price row exists".
		console.error('[transactions] loadPricedFlags RPC failed (fail-closed to unpriced):', error.message);
		return out;
	}
	// 089's asset_id is bigint; this file already trusts fn_holdings_as_of's bigint asset_id as a
	// plain `number` over the SAME PostgREST/.rpc() transport two reads above (loadHeldSecurities'
	// `positions` mapping) — mirrored here, not re-derived, for the same measured wire shape.
	for (const row of (data ?? []) as Array<{ asset_id: number; priced: boolean }>) {
		out.set(row.asset_id, row.priced);
	}
	return out;
}

/**
 * Load the securities CURRENTLY held in an account as-of `asOf` — the option set for the
 * stock-split security picker (SELF-203), now also carrying the SELF-325 P-b `priced` signal
 * consumed by the account-detail holdings view. Three RLS-scoped reads, all fail-soft/fail-closed
 * (logged; [] / false degrades — the picker/marker degrades, never throws):
 *   (1) fn_holdings_as_of (019 INVOKER roll-forward) → (account_id, asset_id, quantity) for
 *       every account; live positions only (qty <> 0). We keep this account's rows.
 *   (2) a pfin.asset label read (RLS: global OR owned) for the held asset_ids → symbol/name.
 *   (3) loadPricedFlags, at the SAME `asOf` as (1) — never call the clock twice: a priced probe
 *       at a different as_of than the holdings read could mark a position unpriced that the
 *       holdings view values, or the reverse.
 * Cash is naturally absent (cash carries no security_id). Sorted by symbol, then name.
 */
export async function loadHeldSecurities(
	supabase: SupabaseClient,
	accountId: number,
	asOf: ZoneResolvedAsOf
): Promise<HeldSecurity[]> {
	const { data: holdings, error: hErr } = await supabase
		.schema('pfin')
		.rpc('fn_holdings_as_of', { p_as_of: asOf });
	if (hErr) {
		console.error('[transactions] loadHeldSecurities holdings read failed:', hErr.message);
		return [];
	}

	const positions = ((holdings ?? []) as Array<{ account_id: number; asset_id: number; quantity: number | string }>)
		.filter((h) => h.account_id === accountId && Number(h.quantity) !== 0);
	if (positions.length === 0) return [];

	const assetIds = positions.map((p) => p.asset_id);
	const { data: assets, error: aErr } = await supabase
		.schema('pfin')
		.from('asset')
		.select('asset_id, symbol, name')
		.in('asset_id', assetIds);
	if (aErr) {
		console.error('[transactions] loadHeldSecurities asset read failed:', aErr.message);
		return [];
	}

	const labelById = new Map(
		((assets ?? []) as Array<{ asset_id: number; symbol: string | null; name: string | null }>).map((a) => [
			a.asset_id,
			a
		])
	);

	const pricedByAssetId = await loadPricedFlags(supabase, assetIds, asOf);

	return positions
		.map((p) => ({
			security_id: p.asset_id,
			symbol: labelById.get(p.asset_id)?.symbol ?? null,
			name: labelById.get(p.asset_id)?.name ?? null,
			quantity: Number(p.quantity),
			priced: pricedByAssetId.get(p.asset_id) ?? false
		}))
		.sort((a, b) => (a.symbol ?? a.name ?? '').localeCompare(b.symbol ?? b.name ?? ''));
}
