// accounts/[account_id]/+page.server.ts — account-detail server surface.
// SELF-201 §2.4.2 (AC #3/#4).
// Backend-owned server source (ARCH §4.1 allowlist).
//
//  - load(): account row + transaction history — all RLS-scoped. Non-owner → 404.
//  - actions.toggleActive: single-row RLS-scoped UPDATE of is_active (SELF-201 AC#3).
//
// The account-level asset Sub-Cat surface (reassignSubCat action + the asset-domain
// picker + the account.sub_cat_id label embed) is REMOVED — allocation classifies
// per-asset (user_asset_category) / per-transaction (annotations), never per-account.
// The DB column pfin.account.sub_cat_id + its 012 fn_account_matched_sub_cat trigger
// stay dormant (a full column drop is a separate future Architect ADR). The
// per-TRANSACTION cashflow category (account_trans_annotation.sub_cat_id) is unaffected.
//
// AC #3 polarity: is_active (WHERE is_active = TRUE), NOT a new `inactive` column
// (reconciled at 012). CONTRACT for NAV/current-state consumers: filter is_active.
// AC #4: inactive accounts retain account_trans history (schema-guaranteed).
// acct_number intentionally NOT selected — masked-only render posture (SD-15).

import { error, fail, redirect } from '@sveltejs/kit';
import { toggleActiveSchema, updateAttributesSchema, fieldErrors } from '$lib/server/schemas/account';
import { loadConnectionState } from '$lib/server/queries/connectionState';
import {
	manualTransCreateSchema,
	manualTransEditSchema,
	recategorizeSchema,
	splitSetSchema,
	unsplitSchema,
	stockSplitCreateSchema
} from '$lib/server/schemas/transaction';
import {
	reverseAndReplaceTrans,
	writeSplitSet,
	unsplitTrans,
	upsertAnnotation,
	createStockSplit,
	loadHeldSecurities,
	type WriteResult
} from '$lib/server/queries/transactions';
import { loadCashflowSubCats, subCatLabel } from '$lib/server/queries/taxonomy';
import { loadDupCandidates, loadSyncHistory } from '$lib/server/queries/reconciliation';
import { computeImportHash } from '$lib/server/dedup/importHash';
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

// linked_source_id (015) surfaces the source-of-truth status so the UI can restrict manual
// stock-split entry to non-provider-linked accounts (SELF-203 app-layer UX complement; the
// fn_create_stock_split DB guard is the integrity boundary — the UI restriction is defense-
// in-depth for a clean affordance, never the security boundary). acct_number stays unselected.
// account.sub_cat_id + its user_taxonomy label embed are intentionally NOT selected — the
// account-level asset Sub-Cat surface is removed (allocation classifies per-asset/per-txn).
const ACCOUNT_COLUMNS =
	'account_id, name, account_type, scope, tax_treatment, is_active, linked_source_id, created_at';

function parseAccountId(param: string): number | null {
	const n = Number(param);
	return Number.isInteger(n) && n > 0 ? n : null;
}

/** Today's date as an ISO YYYY-MM-DD string — the as-of date for the held-security picker. */
function todayIso(): string {
	return new Date().toISOString().slice(0, 10);
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

	// RLS-scoped single-row read (account_select = users_id = auth.uid()); a
	// non-owner id yields no row → 404 below (no existence leak).
	const { data: row } = await locals.supabase
		.schema('pfin')
		.from('account')
		.select(ACCOUNT_COLUMNS)
		.eq('account_id', accountId)
		.maybeSingle();

	// RLS-filtered: not-owner (or nonexistent) → no row → 404 (no existence leak).
	if (!row) throw error(404, 'Account not found');

	const account = row;

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

	// Cashflow-domain Sub-Cat options for the per-transaction category pickers
	// (entry/edit/split) — RLS-scoped. (No asset-domain account picker: the
	// account-level Sub-Cat surface is removed.)
	const cashflowSubCats = await loadCashflowSubCats(locals.supabase);

	// SELF-203 stock-split entry — the account's current live positions (quantity ≠ 0) for the
	// security picker: fn_holdings_as_of(today) filtered to this account + pfin.asset labels.
	// RLS-scoped, fail-soft ([] on error → cash-only accounts have nothing to split). The
	// OWD-2 source-of-truth UI gate reads account.linked_source_id directly (the same column
	// the fn_create_stock_split DB guard keys on — UI + DB gate on one source, no derived drift).
	const heldSecurities = await loadHeldSecurities(locals.supabase, accountId, todayIso());

	// SELF-204 manual↔provider dedup DETECTION (migration 040 / ADR-034 D2) — candidate pairs
	// for this account (a manual row that looks like a synced provider row). Detection-only:
	// the user reconciles explicitly (SELF-205 interprets). RLS-scoped, fail-soft ([] on error).
	const dupCandidates = await loadDupCandidates(locals.supabase, accountId);

	// SELF-204 sync history (ADR-034 D3) — THIS account's linked-connection sync activity, filtered
	// by the account's linked_source_id (per-account per F/CTO ratify; owner-scoped scalar projection,
	// raw `detail` blob unreachable). A manual/non-linked account → []. Fail-soft ([] on error).
	const syncHistory = await loadSyncHistory(locals.supabase, account.linked_source_id ?? null);

	// Connections-redesign Aggregation section: THIS account's connection state (provider +
	// health + last-sync), resolved via its linked_source_id from the 043 view (RLS-scoped).
	// A manual / non-linked account → null (the section renders "manual, no connection").
	// Fail-soft: loadConnectionState returns null on a read error too. Project the 3 fields the
	// Aggregation section needs (the full ConnectionState is not surfaced here).
	const connState =
		account.linked_source_id == null
			? null
			: await loadConnectionState(locals.supabase, String(account.linked_source_id));
	const connection = connState
		? {
				provider: connState.provider,
				connection_status: connState.connection_status,
				last_successful_sync_at: connState.last_successful_sync_at
			}
		: null;

	return {
		account,
		transactions,
		cashflowSubCats,
		heldSecurities,
		dupCandidates,
		syncHistory,
		connection
	};
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

	// Edit the account's user attributes: name / account_type / scope / tax_treatment. RLS-scoped
	// single-row UPDATE (account_update = users_id = auth.uid()). Deliberately does NOT touch the
	// aggregator / connection binding (deferred) nor is_active (that's toggleActive). `.strict()` +
	// the shared enums are the mass-assignment + type-confusion fences (Lock 14 mods #1/#2).
	updateAttributes: async ({ request, locals, params }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const accountId = parseAccountId(params.account_id);
		if (accountId === null) return fail(400, { errors: { _form: ['Invalid account.'] } });

		const raw = Object.fromEntries(await request.formData());
		const parsed = updateAttributesSchema.safeParse(raw);
		if (!parsed.success) return fail(400, { errors: fieldErrors(parsed.error), values: raw });

		const { error: updErr } = await locals.supabase
			.schema('pfin')
			.from('account')
			.update({
				name: parsed.data.name,
				account_type: parsed.data.account_type,
				scope: parsed.data.scope,
				tax_treatment: parsed.data.tax_treatment
			})
			.eq('account_id', accountId);

		if (updErr) {
			console.error('[accounts/[account_id]] updateAttributes failed:', updErr.message);
			return fail(422, { errors: { _form: ['Could not update the account.'] }, values: raw });
		}
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

		// SELF-204 (ADR-034 D4): compute the canonical content hash in shared TS (the SAME module
		// the provider-sync mapper uses) and pass it as p_import_hash — the RPC STORES it (computes
		// nothing), feeding manual↔provider dedup detection. NULL was the pre-040 behavior.
		const importHash = computeImportHash({
			accountId,
			date: v.transaction_date,
			amount: v.amount,
			vendor: v.vendor,
			description: v.description
		});

		const { data: newId, error: rpcErr } = await locals.supabase
			.schema('pfin')
			.rpc('fn_create_manual_trans', {
				p_account_id: accountId,
				p_transaction_date: v.transaction_date,
				p_amount: v.amount,
				p_vendor: v.vendor,
				p_description: v.description,
				p_sub_cat_id: v.sub_cat_id,
				p_note: v.note,
				p_import_hash: importHash
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
	},

	// ── SELF-203 stock-split entry (039 / fn_create_stock_split; ADR-033) ──────────────────
	// (4) Record a POSITION-LEVEL book-neutral corp_action via the atomic INVOKER RPC. Posted
	// fields: security_id, ratio_num, ratio_den, ex_date (account_id is the route param; there
	// is NO amount — a split is book-neutral, quantity-only). The RPC's guards are the boundary
	// (cross-tenant fails closed; provider-linked / empty-position / no-op rejected) — the helper
	// maps each RAISE to a friendly, field-scoped error.
	createStockSplit: async ({ request, locals, params }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });
		const accountId = parseAccountId(params.account_id);
		if (accountId === null) return fail(400, { errors: { _form: ['Invalid account.'] } });

		const raw = Object.fromEntries(await request.formData());
		const parsed = stockSplitCreateSchema.safeParse(raw);
		if (!parsed.success) return fail(400, { errors: fieldErrors(parsed.error), values: raw });

		return toActionResult(await createStockSplit(locals.supabase, accountId, parsed.data));
	}
};
