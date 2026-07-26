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
import type { ManualTransEdit, SplitSet } from '$lib/server/schemas/transaction';

export type WriteResult =
	| { ok: true; transId?: number }
	| { ok: false; status: number; field?: string; message: string };

/** DB raise-message → cross-tenant Sub-Cat classification (the #10 / #13 matched-tenant fences). */
function isCrossTenantSubCat(message: string): boolean {
	return /sub_cat|Decision 3|matched-tenant/i.test(message);
}
/** DB raise-message → the 029 Σ=parent balance violation. */
function isImbalance(message: string): boolean {
	return /imbalance|sum to|Σ|parent\.amount/i.test(message);
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
		if (isCrossTenantSubCat(error.message))
			return { ok: false, status: 422, field: 'sub_cat_id', message: 'That category is not available.' };
		return { ok: false, status: 422, field: 'sub_cat_id', message: 'Could not save the category.' };
	}
	return { ok: true, transId };
}

/**
 * Fact edit = reverse-and-replace on the immutable 004 ledger, atomic for the two ledger rows
 * via a single bulk INSERT (one PostgREST statement = one txn). The reversal mirrors the
 * original (negated amount/quantity) and points at it (is_reverse=true, replaces_trans_id); the
 * corrected row is a fresh fact (is_reverse=false, replaces_trans_id NULL). Per the dedup rule,
 * BOTH new rows carry NULL source_provider/provider_txn_id/import_hash even when the original was
 * provider-sourced — the provider identity stays on the original only (avoids the 017
 * account_trans_provider_dedup_idx collision). The corrected row's category/note is a follow-up
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
		.select('trans_id, account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, is_reverse')
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
	const corrected = {
		account_id: accountId,
		transaction_date: v.transaction_date,
		amount: v.amount,
		vendor: v.vendor,
		description: v.description,
		transaction_type: orig.transaction_type, // preserve the fact-kind (cash = 'standard')
		is_reverse: false
		// security_id NULL + quantity 0 default (017 cash CHECK); provider cols NULL (manual origin)
	};

	const { data: inserted, error: insErr } = await supabase
		.schema('pfin')
		.from('account_trans')
		.insert([reversal, corrected])
		.select('trans_id, is_reverse');
	if (insErr || !inserted) {
		console.error('[transactions] reverse-and-replace INSERT failed:', insErr?.message);
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
