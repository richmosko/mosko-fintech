// POST /api/transactions/:trans_id/classify — SELF-248 §2.3.1.a classify backend (V1.3
// pre-flight re-derived ACs; docs/records/v13-preflight/rederived-acs.md — this AC list REPLACES
// the prior one in full).
//
// UPSERTs the caller's OWN pfin.account_trans_annotation.sub_cat_id (023; matched-tenant fence
// #10, FK-retargeted to pfin.posting_prototype @ 084) — INSERT when no annotation row exists,
// UPDATE of sub_cat_id ONLY when one does (classifyTrans in transactions.ts). The immutable 004
// ledger is NEVER written (AC3 — Lock 10 is not violated because this endpoint never reaches it).
//
// AC4/S-4 (V1.3 pre-flight sitting item 6a — the write-time generalization of the S-1
// classifiability predicate, sitting item 3a): refuses every write where classifiable() is
// false — transaction_type='standard' AND security_id IS NULL AND split_count=0 AND
// is_reverse=false AND (annotation IS NULL OR annotation.journal_id IS NULL). checkClassifiable
// (transactions.ts) is the ONLY enforcement for four of these five legs (M1/M2/M4/E1 have no DB
// fence — AC10 condition 5); the fifth (M3/journaled) is ALSO DB-fenced by migration 092's new
// `fn_..._journaled_cat_fence` trigger, as defense-in-depth. Each refusal returns a typed `code`
// naming which rule failed.
//
// AC6: cross-tenant / cross-vocabulary Sub-Cat rejection is ALREADY DB-enforced (the FK to
// pfin.posting_prototype + fn_account_trans_annotation_matched_sub_cat, 023/084) — not
// re-implemented here; classifyTrans only maps the raise to a clean 4xx.
//
// D-8 condition 6 (this endpoint's obligation): the app-level `journaled` refusal (pre-check —
// this endpoint never reaches the DB in that case) and migration 092's new journaled-cat-fence
// trigger raise (only reachable on a race between the pre-check read and the write) surface as
// DISTINCT typed codes — `journaled` (409, this endpoint refused before writing) vs
// `journaled_cat_conflict` (409, the DB caught a race the app-level check missed) — so the
// frontend can tell the two apart even though both name the same underlying invariant.
//
// AC9: this is the SAME annotation row fn_create_manual_trans (038) writes — both target
// pfin.account_trans_annotation keyed on trans_id (PK); this endpoint adds no second write path.
//
// users_id is NEVER read from the client (Lock 14 mod #1) — in fact nothing tenant-identifying is
// even a schema field here: tenancy resolves entirely through RLS on the account chain (023/029/
// 004 carry no own users_id). No service_role — anon-key client + RLS + INVOKER-composed fences
// (this endpoint never elevates), so it stays OFF the RT-26 allowlist.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { classifyTransSchema } from '$lib/server/schemas/transaction';
import { fieldErrors } from '$lib/server/schemas/account';
import { classifyTrans } from '$lib/server/queries/transactions';

/** Shape-only guard on the route param (RLS is the tenant/visibility boundary; mirrors
 *  accounts/[account_id]'s parseAccountId). */
function parseTransId(param: string | undefined): number | null {
	const n = Number(param);
	return Number.isInteger(n) && n > 0 ? n : null;
}

export const POST: RequestHandler = async ({ request, locals, params }) => {
	const { user } = await locals.safeGetSession();
	if (!user) return json({ error: 'unauthenticated' }, { status: 401 });

	const transId = parseTransId(params.trans_id);
	if (transId === null) return json({ error: 'invalid_request' }, { status: 400 });

	let raw: unknown;
	try {
		raw = await request.json();
	} catch {
		return json({ error: 'invalid_request' }, { status: 400 });
	}
	const parsed = classifyTransSchema.safeParse(raw);
	if (!parsed.success)
		return json({ error: 'invalid_request', fieldErrors: fieldErrors(parsed.error) }, { status: 400 });

	const result = await classifyTrans(locals.supabase, transId, parsed.data.sub_cat_id);

	if (!result.ok) {
		const body: { error: string; code?: string } = { error: result.message };
		if (result.code) body.code = result.code;
		return json(body, { status: result.status });
	}

	return json({ ok: true, trans_id: transId, sub_cat_id: parsed.data.sub_cat_id });
};
