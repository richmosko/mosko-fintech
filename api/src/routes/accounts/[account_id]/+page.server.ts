// accounts/[account_id]/+page.server.ts — account-detail server surface.
// SELF-201 §2.4.2 (AC #3/#4) + SELF-236 §2.2.1.c (Sub-Cat reassignment).
// Backend-owned server source (ARCH §4.1 allowlist).
//
//  - load(): account row (+ embedded Sub-Cat label) + transaction history +
//    asset-domain Sub-Cat picker options — all RLS-scoped. Non-owner → 404.
//  - actions.toggleActive: single-row RLS-scoped UPDATE of is_active (SELF-201 AC#3).
//  - actions.reassignSubCat: single-row RLS-scoped UPDATE of sub_cat_id (SELF-236).
//    Fenced by account_update RLS (ownership) + the 012 fn_account_matched_sub_cat
//    trigger (BEFORE INSERT OR UPDATE — a reassignment cannot pivot to another
//    tenant's Sub-Cat). Nullable clears the tag → "Unsorted". No migration needed
//    (the trigger + account_update RLS already exist).
//
// AC #3 polarity: is_active (WHERE is_active = TRUE), NOT a new `inactive` column
// (reconciled at 012). CONTRACT for NAV/current-state consumers: filter is_active.
// AC #4: inactive accounts retain account_trans history (schema-guaranteed).
// acct_number intentionally NOT selected — masked-only render posture (SD-15).

import { error, fail, redirect } from '@sveltejs/kit';
import { reassignSubCatSchema, toggleActiveSchema, fieldErrors } from '$lib/server/schemas/account';
import {
	manualTransCreateSchema,
	manualTransEditSchema,
	recategorizeSchema,
	splitSetSchema,
	unsplitSchema
} from '$lib/server/schemas/transaction';
import {
	reverseAndReplaceTrans,
	writeSplitSet,
	unsplitTrans,
	upsertAnnotation,
	type WriteResult
} from '$lib/server/queries/transactions';
import { loadAssetSubCats, loadCashflowSubCats, subCatLabel } from '$lib/server/queries/taxonomy';
import type { PageServerLoad, Actions } from './$types';

// Category label + note (023) and split children (029) embedded per transaction so the
// detail UI can render the current state (category, is-split, breakdown). Both embeds are
// RLS-scoped; the nested user_taxonomy carries the human label.
const TRANSACTION_COLUMNS = `
	trans_id, transaction_date, amount, vendor, description, transaction_type, is_reverse, replaces_trans_id, created_at,
	account_trans_annotation ( sub_cat_id, note, user_taxonomy ( cat, sub_cat ) ),
	account_trans_split ( id, amount, sub_cat_id, note, display_order, user_taxonomy ( cat, sub_cat ) )
`;

/** Map a transactions.ts WriteResult to a SvelteKit action response. */
function toActionResult(r: WriteResult) {
	if (r.ok) return { success: true, transId: r.transId };
	const key = r.field ?? '_form';
	return fail(r.status, { errors: { [key]: [r.message] } });
}

// Embed the Sub-Cat label via the account.sub_cat_id → user_taxonomy FK (012).
const ACCOUNT_COLUMNS =
	'account_id, name, account_type, scope, tax_treatment, sub_cat_id, is_active, created_at, user_taxonomy ( cat, sub_cat )';

function parseAccountId(param: string): number | null {
	const n = Number(param);
	return Number.isInteger(n) && n > 0 ? n : null;
}

/** 012 fn_account_matched_sub_cat raise-message signature → map to the sub_cat field. */
function isCrossTenantSubCat(message: string): boolean {
	return /sub_cat|Decision 3|matched-tenant/i.test(message);
}

export const load: PageServerLoad = async ({ locals, params, url }) => {
	const { user } = await locals.safeGetSession();
	// Preserve where the user was headed so /login can bounce them back (SELF-285).
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const accountId = parseAccountId(params.account_id);
	if (accountId === null) throw error(404, 'Account not found');

	// Embedded read is itself RLS-scoped (user_taxonomy_select = auth.uid()); the
	// matched-tenant write fence guarantees the joined row is the caller's own.
	const { data: row } = await locals.supabase
		.schema('pfin')
		.from('account')
		.select(ACCOUNT_COLUMNS)
		.eq('account_id', accountId)
		.maybeSingle();

	// RLS-filtered: not-owner (or nonexistent) → no row → 404 (no existence leak).
	if (!row) throw error(404, 'Account not found');

	const { user_taxonomy, ...rest } = row;
	const account = { ...rest, ...subCatLabel(user_taxonomy) };

	const { data: transRows } = await locals.supabase
		.schema('pfin')
		.from('account_trans')
		.select(TRANSACTION_COLUMNS)
		.eq('account_id', accountId)
		.order('transaction_date', { ascending: false })
		.order('trans_id', { ascending: false });

	// Shape each row: fold the 1:1 annotation into a { category, note } pair and the 1:many
	// split children into a labelled, ordered array + a derived split_count (035/037 reader
	// rule: split_count>0 → the children are the truth; else the parent). No stored flags.
	// Fields are picked explicitly (not `...rest`) so the ledger columns stay concretely typed
	// for the consuming component. supabase-js can't infer the embed shape → rows typed loose.
	const transactions = ((transRows ?? []) as Array<Record<string, unknown>>).map((r) => {
		const annRaw = r.account_trans_annotation as
			| { note?: string | null; user_taxonomy?: unknown }
			| Array<{ note?: string | null; user_taxonomy?: unknown }>
			| null;
		const ann = Array.isArray(annRaw) ? (annRaw[0] ?? null) : annRaw;
		const splits = ((r.account_trans_split as Array<Record<string, unknown>>) ?? [])
			.map((s) => ({
				id: s.id as number,
				amount: s.amount as number,
				note: (s.note as string | null) ?? null,
				display_order: (s.display_order as number | null) ?? null,
				...subCatLabel(s.user_taxonomy)
			}))
			.sort((a, b) => (a.display_order ?? 0) - (b.display_order ?? 0));
		return {
			trans_id: r.trans_id as number,
			transaction_date: r.transaction_date as string,
			amount: r.amount as number,
			vendor: (r.vendor as string | null) ?? null,
			description: (r.description as string | null) ?? null,
			transaction_type: r.transaction_type as string,
			is_reverse: r.is_reverse as boolean,
			replaces_trans_id: (r.replaces_trans_id as number | null) ?? null,
			created_at: r.created_at as string,
			category: ann ? subCatLabel(ann.user_taxonomy) : null,
			note: (ann?.note as string | null) ?? null,
			splits,
			split_count: splits.length
		};
	});

	// Asset-domain Sub-Cat options for the account reassignment picker (SELF-236); cashflow-
	// domain options for the transaction category pickers (entry/edit/split) — both RLS-scoped.
	const subCats = await loadAssetSubCats(locals.supabase);
	const cashflowSubCats = await loadCashflowSubCats(locals.supabase);

	return { account, transactions, subCats, cashflowSubCats };
};

export const actions: Actions = {
	toggleActive: async ({ request, locals, params }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const accountId = parseAccountId(params.account_id);
		if (accountId === null) return fail(400, { errors: { _form: ['Invalid account.'] } });

		const parsed = toggleActiveSchema.safeParse(Object.fromEntries(await request.formData()));
		if (!parsed.success) return fail(400, { errors: fieldErrors(parsed.error) });

		const { error: updErr } = await locals.supabase
			.schema('pfin')
			.from('account')
			.update({ is_active: parsed.data.is_active })
			.eq('account_id', accountId);

		if (updErr) {
			console.error('[accounts/[account_id]] toggleActive failed:', updErr.message);
			return fail(422, { errors: { _form: ['Could not update the account.'] } });
		}
		return { success: true, is_active: parsed.data.is_active };
	},

	reassignSubCat: async ({ request, locals, params }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const accountId = parseAccountId(params.account_id);
		if (accountId === null) return fail(400, { errors: { _form: ['Invalid account.'] } });

		const parsed = reassignSubCatSchema.safeParse(Object.fromEntries(await request.formData()));
		if (!parsed.success) return fail(400, { errors: fieldErrors(parsed.error) });

		// Single-row RLS-scoped UPDATE. Ownership fenced by account_update RLS
		// (USING/WITH CHECK users_id = auth.uid()); a cross-tenant sub_cat_id is fenced
		// by the 012 fn_account_matched_sub_cat trigger (covers UPDATE, fail-closed).
		// Minimal .select('account_id') only detects the RLS-filtered non-owner (0 rows
		// → null → 404); the fresh label is NOT returned — enhance's default update()
		// re-invalidates load(), which refreshes account.cat/sub_cat from the one place
		// the label lives (identical to toggleActive). Return { success: true } only.
		const { data: updated, error: updErr } = await locals.supabase
			.schema('pfin')
			.from('account')
			.update({ sub_cat_id: parsed.data.sub_cat_id })
			.eq('account_id', accountId)
			.select('account_id')
			.maybeSingle();

		if (updErr) {
			console.error('[accounts/[account_id]] reassignSubCat failed:', updErr.message);
			return fail(422, {
				errors: isCrossTenantSubCat(updErr.message)
					? { sub_cat_id: ['That Sub-Cat is not available.'] }
					: { _form: ['Could not update the Sub-Cat.'] }
			});
		}
		// RLS-filtered non-owner → 0 rows updated → null.
		if (!updated) return fail(404, { errors: { _form: ['Account not found.'] } });

		return { success: true };
	},

	// ── SELF-202 manual cash-transaction surfaces (038 / ADR-032) ──────────────────────
	// (1) Manual cash entry → the atomic fn_create_manual_trans INVOKER RPC (account_trans
	// row + optional 023 annotation, one txn under the caller's RLS). transaction_type is
	// RPC-set ('standard'); the category is p_sub_cat_id (028 class), NOT transaction_type.
	createTrans: async ({ request, locals, params }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });
		const accountId = parseAccountId(params.account_id);
		if (accountId === null) return fail(400, { errors: { _form: ['Invalid account.'] } });

		const raw = Object.fromEntries(await request.formData());
		const parsed = manualTransCreateSchema.safeParse(raw);
		if (!parsed.success) return fail(400, { errors: fieldErrors(parsed.error), values: raw });
		const v = parsed.data;

		const { data: newId, error: rpcErr } = await locals.supabase
			.schema('pfin')
			.rpc('fn_create_manual_trans', {
				p_account_id: accountId,
				p_transaction_date: v.transaction_date,
				p_amount: v.amount,
				p_vendor: v.vendor,
				p_description: v.description,
				p_sub_cat_id: v.sub_cat_id,
				p_note: v.note
			});
		if (rpcErr) {
			console.error('[accounts/[account_id]] createTrans RPC failed:', rpcErr.message);
			return fail(422, {
				errors: isCrossTenantSubCat(rpcErr.message)
					? { sub_cat_id: ['That category is not available.'] }
					: { _form: ['Could not save the transaction. Please try again.'] },
				values: raw
			});
		}
		return { success: true, transId: newId as number };
	},

	// (2a) Fact edit = reverse-and-replace (immutable 004 ledger; NO UPDATE).
	editTransFact: async ({ request, locals, params }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });
		const accountId = parseAccountId(params.account_id);
		if (accountId === null) return fail(400, { errors: { _form: ['Invalid account.'] } });

		const raw = Object.fromEntries(await request.formData());
		const parsed = manualTransEditSchema.safeParse(raw);
		if (!parsed.success) return fail(400, { errors: fieldErrors(parsed.error), values: raw });

		return toActionResult(await reverseAndReplaceTrans(locals.supabase, accountId, parsed.data));
	},

	// (2b) Category/note edit = a 023 annotation upsert (mutable overlay; NOT a ledger touch).
	recategorize: async ({ request, locals, params }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });
		if (parseAccountId(params.account_id) === null)
			return fail(400, { errors: { _form: ['Invalid account.'] } });

		const parsed = recategorizeSchema.safeParse(Object.fromEntries(await request.formData()));
		if (!parsed.success) return fail(400, { errors: fieldErrors(parsed.error) });
		const v = parsed.data;

		return toActionResult(await upsertAnnotation(locals.supabase, v.trans_id, v.sub_cat_id, v.note));
	},

	// (3) Split CREATE / REPLACE — a balanced child set over the 029 write path. `lines` is a
	// JSON array string (variable-length set); Σ(children)=parent.amount (029 deferred trigger).
	splitTrans: async ({ request, locals, params }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });
		const accountId = parseAccountId(params.account_id);
		if (accountId === null) return fail(400, { errors: { _form: ['Invalid account.'] } });

		const raw = Object.fromEntries(await request.formData());
		let lines: unknown;
		try {
			lines = JSON.parse(String(raw.lines ?? ''));
		} catch {
			return fail(400, { errors: { lines: ['Malformed split lines.'] } as Record<string, string[]> });
		}
		const parsed = splitSetSchema.safeParse({ trans_id: raw.trans_id, lines });
		if (!parsed.success) return fail(400, { errors: fieldErrors(parsed.error) });

		return toActionResult(await writeSplitSet(locals.supabase, accountId, parsed.data));
	},

	// (3b) UNSPLIT — delete the entire child set → revert to parent-only counting.
	unsplitTrans: async ({ request, locals, params }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });
		if (parseAccountId(params.account_id) === null)
			return fail(400, { errors: { _form: ['Invalid account.'] } });

		const parsed = unsplitSchema.safeParse(Object.fromEntries(await request.formData()));
		if (!parsed.success) return fail(400, { errors: fieldErrors(parsed.error) });

		return toActionResult(await unsplitTrans(locals.supabase, parsed.data.trans_id));
	}
};
