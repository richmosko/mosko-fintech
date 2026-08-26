// accounts/[account_id]/+page.server.ts — account-detail server surface.
// SELF-201 §2.4.2 (AC #3/#4).
// Backend-owned server source (ARCH §4.1 allowlist).
//
//  - load(): account row + transaction history — all RLS-scoped. Non-owner → 404.
//  - actions.closeAccount / actions.reopenAccount: the account CLOSE / REOPEN control
//    (ADR-042 Decision 1). Each maps 1:1 onto its INVOKER RPC, which performs a single-row
//    RLS-scoped UPDATE of closed_at. Gated by the 058 BEFORE UPDATE close gate; refusals name
//    which leg fired. is_active is GONE (dropped at 059) — there is no boolean here to flip.
//
// The account-level asset Sub-Cat surface (reassignSubCat action + the asset-domain
// picker + the account.sub_cat_id label embed) is REMOVED — allocation classifies
// per-asset (user_asset_category) / per-transaction (annotations), never per-account.
// The DB column pfin.account.sub_cat_id + its 012 fn_account_matched_sub_cat trigger
// stay dormant (a full column drop is a separate future Architect ADR). The
// per-TRANSACTION cashflow category (account_trans_annotation.sub_cat_id) is unaffected.
//
// SUPERSEDED BY ADR-042, and DISCHARGED at 059: the AC #3 is_active polarity note described a
// boolean that no longer exists. Closure is as-of dated (closed_at); a boolean cannot answer an
// as-of question, which is the defect the three-concept model removes.
//
// THIS PAGE IS A RENDER SURFACE, AND THAT DETERMINES ITS PREDICATE (api/CLAUDE.md, closure
// contract). It asks "is this account closed RIGHT NOW", so `closed_at !== null` — which the
// consuming +page.svelte does — is CORRECT AND COMPLETE. The as-of form belongs to the
// VALUATION surfaces (NAV / aggregation / counts); using it here would be WRONG, not merely
// heavier, because it needs an `as_of` this page has no business choosing in order to answer a
// question nobody asked. This load() therefore selects closed_at and applies NO closure
// predicate at all.
//   ⚠ An earlier version of this very comment said "the predicate is AS-OF … never the naive
//   `closed_at is null`", unconditionally. That was the pre-bfc2fd8 root contract, which was
//   written from the NAV path and over-generalised from it — so this header told the reader
//   that what the page's own consumer correctly does is the naive mistake. Recorded rather than
//   silently replaced, because the failure mode is the one §7.9 AC 5 names ARRIVING FROM THE
//   OPPOSITE DIRECTION: not a stale root re-seeding its leaves, but a root CORRECTED while its
//   leaves kept the superseded reading. A contract sharpened in one place and not the others
//   has two answers, and the weaker one is the copy sitting next to the code.
// AC #4: closed accounts retain account_trans history (schema-guaranteed).
// acct_number intentionally NOT selected — masked-only render posture (SD-15).

import { error, fail, redirect } from '@sveltejs/kit';
import {
	closeAccountSchema,
	reopenAccountSchema,
	updateAttributesSchema,
	fieldErrors
} from '$lib/server/schemas/account';
import { loadConnectionState } from '$lib/server/queries/connectionState';
import { serverTodayAsOf } from '$lib/server/time/asOf';
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
	isClosedAccountWrite,
	CLOSED_ACCOUNT_WRITE_MESSAGE,
	classifiabilityOf,
	loadVendorSuggestions,
	vendorKey,
	type WriteResult
} from '$lib/server/queries/transactions';
import { loadCashflowSubCats, subCatLabel, findDefaultBtoSubCatId } from '$lib/server/queries/taxonomy';
import { loadDupCandidates, loadSyncHistory } from '$lib/server/queries/reconciliation';
import { computeImportHash } from '$lib/server/dedup/importHash';
import { createPurchaseSchema } from '$lib/server/schemas/purchase';
import { createManualPurchase } from '$lib/server/queries/purchases';
import { loadSelectableAssets } from '$lib/server/queries/selectableAssets';
import type { PageServerLoad, Actions } from './$types';

// Category label + note (023) and split children (029) embedded per transaction so the
// detail UI can render the current state (category, is-split, breakdown). Both embeds are
// RLS-scoped; the nested posting_prototype carries the human label.
//
// POST-084 (ADR-058 Decision 1/5): both 023's `account_trans_annotation.sub_cat_id` and 029's
// `account_trans_split.sub_cat_id` RE-TARGET from `user_taxonomy` to `posting_prototype` — the
// cashflow-side referents the split moves. PostgREST embeds key on the FK's TARGET TABLE NAME,
// so the embed key changes with the FK; this is the same "consumer breaks the instant the FK
// re-targets" hazard Sec named F3 for taxonomy.ts's provisioning path, extended by team-lead to
// this file (ruling: rides the split PR, pending Sec confirm-or-narrow at joint-review — this is
// a READ path, so a missed re-target here breaks the account-detail transaction history for every
// existing user on the very first post-migration page load, not just new signups).
//
// SELF-249 loader extension (TransactionView's EXPECTED-CONTRACT fields — transaction-util.ts):
// `security_id` and `provider_category` are added at top level; `journal_id` is added to the
// EXISTING annotation embed (no new join — E3's LEFT-JOIN-not-inner rule is satisfied by
// construction here, same as the pre-existing `sub_cat_id`/`note`: this embed carries no filter,
// so PostgREST returns it as null rather than excluding the row when no annotation exists). All
// three feed `classifiabilityOf` (transactions.ts) + the `provider_category` display hint below.
const TRANSACTION_COLUMNS = `
	trans_id, transaction_date, amount, vendor, description, transaction_type, security_id, is_reverse, replaces_trans_id, created_at, provider_category,
	account_trans_annotation ( sub_cat_id, note, journal_id, posting_prototype ( cat, sub_cat ) ),
	account_trans_split ( id, amount, sub_cat_id, note, display_order, posting_prototype ( cat, sub_cat ) )
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
	'account_id, name, account_type, scope, tax_treatment, closed_at, linked_source_id, created_at';

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
	//
	// SELF-249 AC6: `classifiable`/`classifiableReason` are computed HERE, in-process, by feeding
	// this SAME query's already-loaded fields (transaction_type, security_id, is_reverse,
	// split_count, journal_id) to `classifiabilityOf` — the identical pure predicate
	// `checkClassifiable` (transactions.ts) uses at write time. No second implementation of the
	// five rules, and no extra per-row round trip: everything the predicate needs is already in
	// this one bulk query.
	const transactions = ((transRows ?? []) as Array<Record<string, unknown>>).map((r) => {
		const annRaw = r.account_trans_annotation as
			| { sub_cat_id?: number | null; note?: string | null; journal_id?: number | null; posting_prototype?: unknown }
			| Array<{ sub_cat_id?: number | null; note?: string | null; journal_id?: number | null; posting_prototype?: unknown }>
			| null;
		const ann = Array.isArray(annRaw) ? (annRaw[0] ?? null) : annRaw;
		const splits = ((r.account_trans_split as Array<Record<string, unknown>>) ?? [])
			.map((s) => ({
				id: s.id as number,
				amount: s.amount as number,
				note: (s.note as string | null) ?? null,
				display_order: (s.display_order as number | null) ?? null,
				...subCatLabel(s.posting_prototype)
			}))
			.sort((a, b) => (a.display_order ?? 0) - (b.display_order ?? 0));
		// Sec FLAG-D (PR #564 AMBER, backend half): `subCatLabel` NEVER returns null (its miss case
		// is the {cat:null, sub_cat:'Unsorted'} OBJECT, a truthy value), so `category` alone cannot
		// distinguish "no annotation" from "a NOTE-ONLY annotation" (sub_cat_id null, reachable via
		// recategorize's nullable subCatIdField) — both read as a non-null `category`. `category`'s
		// own computation is UNCHANGED here (Frontend's parallel FLAG-D fix does not key off it
		// either way, and other category consumers keep their existing behavior). Instead, the raw
		// `sub_cat_id` is surfaced as its OWN field below (Frontend's SubCatPicker now keys
		// `classified` on `transaction.sub_cat_id != null` directly — transaction-util.ts's
		// EXPECTED-CONTRACT note), and this loader's own unclassified-vendor-suggestion filter
		// (below) is keyed on the SAME raw field, not on `category`.
		const category = ann ? subCatLabel(ann.posting_prototype) : null;
		const subCatId = (ann?.sub_cat_id as number | null | undefined) ?? null;
		const securityId = (r.security_id as number | null) ?? null;
		const check = classifiabilityOf({
			transaction_type: r.transaction_type as string,
			security_id: securityId,
			is_reverse: r.is_reverse as boolean,
			split_count: splits.length,
			journal_id: (ann?.journal_id as number | null) ?? null
		});
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
			category,
			sub_cat_id: subCatId,
			// SELF-340 (ADR-064 D1 UI mirror, TransactionView's EXPECTED-CONTRACT `security_id`
			// field — Frontend's default fails CLOSED, hiding Edit on every row, until this lands):
			// was already computed above for `classifiabilityOf` but dropped before the return —
			// surfaced here so Frontend's row-level Edit-hiding mirror has real data instead of the
			// unwired-default fail-closed state (which hides Edit on cash rows too, safe but wrong).
			security_id: securityId,
			note: (ann?.note as string | null) ?? null,
			splits,
			split_count: splits.length,
			provider_category: (r.provider_category as string | null) ?? null,
			classifiable: check.classifiable,
			classifiableReason: check.classifiable ? null : check.reason
		};
	});

	// SELF-249 AC7/AC8: vendor suggestions, ONLY for unclassified rows (an existing override
	// always wins — transaction-util.ts's own contract note) and batched by DISTINCT vendor
	// (loadVendorSuggestions) rather than one `fn_suggest_subcat_for_vendor` RPC call per row —
	// see that function's header for why a per-row call doesn't scale with page size.
	//
	// Sec FLAG-D: keyed on `sub_cat_id == null`, NOT `category === null` — a note-only annotation
	// (sub_cat_id null) has a non-null `category` (subCatLabel's Unsorted-label object) but is
	// still unclassified and should still get a suggestion/hint.
	const unclassifiedVendors = transactions.filter((t) => t.sub_cat_id == null).map((t) => t.vendor);
	const vendorSuggestions = await loadVendorSuggestions(locals.supabase, unclassifiedVendors);
	const transactionsWithSuggestions = transactions.map((t) => {
		if (t.sub_cat_id != null) return { ...t, suggested_sub_cat_id: null };
		const key = vendorKey(t.vendor);
		return { ...t, suggested_sub_cat_id: key !== null ? (vendorSuggestions.get(key) ?? null) : null };
	});

	// Cashflow-domain Sub-Cat options for the per-transaction category pickers
	// (entry/edit/split) — RLS-scoped. (No asset-domain account picker: the
	// account-level Sub-Cat surface is removed.)
	const cashflowSubCats = await loadCashflowSubCats(locals.supabase);

	// SELF-325 purchase-path DISPLAY data (the createPurchase action re-reads both, independently
	// and authoritatively, at submit time — this is for rendering the form, not the write path):
	//   - selectableAssets: the caller's pickable universe (own + global pfin.asset, RLS-scoped)
	//     for the BIND-mode "pick an existing asset" affordance, distinct from a fresh /asset/
	//     resolve ticker lookup.
	//   - defaultSubCat: derived from the ALREADY-LOADED cashflowSubCats (no extra round trip) —
	//     the caller's 'Trade'/'BTO' row, so the form can show the category the purchase will
	//     default to before the user ever touches the sub_cat_id field. Absent (not provisioned /
	//     renamed / deactivated) → null; the form renders "Unsorted-pending", same fallback the
	//     action itself uses via findDefaultBtoSubCatId.
	// Fail-soft: mirrors heldSecurities/dupCandidates — a read error degrades to an empty picker
	// (the resolve+RPC write path stays the authoritative check either way) rather than breaking
	// the page load.
	const { assets: selectableAssets } = await loadSelectableAssets(locals.supabase);
	const defaultBto = cashflowSubCats.find((s) => s.cat === 'Trade' && s.sub_cat === 'BTO') ?? null;
	const defaultSubCatId = defaultBto?.id ?? null;
	const defaultSubCatLabel = defaultBto ? `${defaultBto.cat} — ${defaultBto.sub_cat}` : null;

	// SELF-203 stock-split entry — the account's current live positions (quantity ≠ 0) for the
	// security picker: fn_holdings_as_of(today) filtered to this account + pfin.asset labels.
	// RLS-scoped, fail-soft ([] on error → cash-only accounts have nothing to split). The
	// OWD-2 source-of-truth UI gate reads account.linked_source_id directly (the same column
	// the fn_create_stock_split DB guard keys on — UI + DB gate on one source, no derived drift).
	const heldSecurities = await loadHeldSecurities(locals.supabase, accountId, serverTodayAsOf());

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
		transactions: transactionsWithSuggestions,
		cashflowSubCats,
		heldSecurities,
		dupCandidates,
		syncHistory,
		connection,
		selectableAssets,
		defaultSubCatId,
		defaultSubCatLabel
	};
};

/**
 * ONE classification of a close-control refusal, consumed by BOTH the user-facing copy and the
 * operator log. Deliberately single: a second classifier for the log would drift away from the
 * one the user sees, and then the log would name a leg the user was never told about.
 *
 * The raw raises are never surfaced and are never logged — see the `console.error` below.
 */
type GateLeg = 'holdings' | 'cash' | 'cash-contract' | 'post-closure' | 'future-dated' | 'other';
type RpcRefusal = 'already-closed' | 'already-open';
type CloseFailure =
	| { kind: 'gate'; leg: GateLeg }
	| { kind: 'rpc'; refusal: RpcRefusal }
	| { kind: 'unclassified' };

function classifyCloseFailure(raw: string): CloseFailure {
	// The gate is checked FIRST so a gate raise always wins over an RPC refusal — the prior
	// if/else order, preserved.
	if (raw.includes('account closure blocked')) {
		// `cash-contract` is 058's leg-2 CONTRACT-BREACH raise ("got no usable cash balance"),
		// which also carries the `leg 2 of 3: cash` marker and so must be tested BEFORE it. It
		// gets its own key only so the operator log can distinguish "the user holds cash" (act on
		// the account) from "fn_account_cash_as_of's contract is broken" (act on 056). Its
		// USER-FACING copy is deliberately identical to `cash` — Sec ruled that mapping GREEN and
		// this change must not alter a single byte the user sees.
		if (raw.includes('leg 1 of 3: holdings')) return { kind: 'gate', leg: 'holdings' };
		if (raw.includes('got no usable cash balance')) return { kind: 'gate', leg: 'cash-contract' };
		if (raw.includes('leg 2 of 3: cash')) return { kind: 'gate', leg: 'cash' };
		if (raw.includes('leg 3 of 3: post-closure activity'))
			return { kind: 'gate', leg: 'post-closure' };
		if (raw.includes('future closed_at')) return { kind: 'gate', leg: 'future-dated' };
		return { kind: 'gate', leg: 'other' };
	}
	// The RPCs' own narrow-by-construction refusals, which are NOT gate refusals.
	//
	// `fn_close_account` matches `… and closed_at is null`, `fn_reopen_account` the inverse, so a
	// zero-row match means the account is already in the requested state (or is not the caller's).
	// Architect made these prefixes deliberately distinct from the gate's so the two stay separable.
	// The common cause is a double-submit — benign, and it must not read as a failure to close, and
	// certainly not as "it still holds value", which is what it fell through to before.
	if (raw.includes('close refused:')) return { kind: 'rpc', refusal: 'already-closed' };
	if (raw.includes('reopen refused:')) return { kind: 'rpc', refusal: 'already-open' };
	return { kind: 'unclassified' };
}

/**
 * User-facing copy that NAMES the leg that fired.
 *
 * The gate's raises are operator-precise (they interpolate account ids, dates and native
 * amounts) and are not shown verbatim — but which of the four legs refused IS the useful
 * part, per ADR-042 Decision 1. A generic "could not update" would tell the user nothing
 * and is the failure this mapping exists to avoid.
 */
const GATE_LEG_MESSAGE: Record<GateLeg, string> = {
	holdings: 'This account still holds positions. Sell or transfer them out, then close it.',
	cash: 'This account still holds a cash balance. Move the funds out, then close it.',
	'cash-contract': 'This account still holds a cash balance. Move the funds out, then close it.',
	// ⚠ REWRITTEN: this said "Close it as of a later date", which INSTRUCTS THE USER TO USE A
	//   CONTROL THAT DOES NOT EXIST. GATE_LEG_MESSAGE was written against a close flow that took a
	//   closing date; the flow that shipped does not — closeAccount sends no p_closed_at, so the
	//   closure is always server-now(). Same defect class as the `use or ignore` clause #319
	//   removed: copy describing an affordance the UI never gained. (pm-copy / ux-copy.)
	//   Because closed_at is always today, the blocking activity is always FUTURE-dated, so the
	//   remedy is about those entries rather than about the closing date.
	'post-closure':
		'This account has entries dated in the future. Remove or re-date them, or wait until those dates have passed, then close it.',
	// ⚠ UNREACHABLE FROM THIS APP PATH TODAY, AND DELIBERATELY KEPT. closeAccount never sends
	//   p_closed_at, so closed_at = now() and the gate's `new.closed_at > now()` cannot fire.
	//   KEPT rather than deleted for two reasons, in order of weight:
	//     1. Deleting it does not remove the case, it RE-ROUTES it — the raise would fall through
	//        to `other`, whose copy is "it still holds value", which is FALSE for a future-date
	//        refusal. A wrong message is worse than an unused correct one.
	//     2. p_closed_at is a DEFAULTED PARAMETER on a PostgREST-exposed signature (058 §(7)),
	//        so it is reachable by construction to any future caller that supplies a date —
	//        including a backfill or an admin path — without touching this file.
	//   Recorded so nobody exercises the UI, fails to reach it, and concludes it is dead.
	'future-dated': 'An account cannot be closed as of a future date.',
	other: 'This account cannot be closed yet — it still holds value.'
};

/**
 * ⚠ THIS COPY IS A DELIBERATE BEST-GUESS OVER AN INTENTIONALLY-AMBIGUOUS SIGNAL. NOTHING MAY
 *   BRANCH ON IT (Sec joint-review, PR #318 F8 note).
 *
 *   058 §(7)'s DDL states it outright: the `close refused:` raise "does NOT discriminate absent /
 *   not-yours / already-closed: under RLS those are one condition, and separating them would leak
 *   existence." The same holds for `reopen refused:`. So the server genuinely cannot tell which of
 *   the three occurred, and this mapping ASSERTS one of them.
 *
 *   It leaks nothing — the response is byte-identical across all three causes, which is the
 *   property that must be preserved — and "already closed" is by far the likeliest cause (a
 *   double-submit) and the only one the user can act on. But it is a claim the server cannot
 *   substantiate, so it is UX copy and nothing more. The moment any UI branches on it (hides the
 *   close button, routes to a reopen affordance, reports "closed" in a toast the user trusts) it
 *   becomes a bug: a user who mistyped an id, or hit someone else's account, would be told their
 *   own account is closed. If a caller ever needs the distinction, the answer is that there isn't
 *   one to be had — not a vaguer message here, and certainly not a discriminating raise in 058.
 *
 *   The raises interpolate the account id; that is operator detail and is not surfaced.
 */
const RPC_REFUSAL_MESSAGE: Record<RpcRefusal, string> = {
	'already-closed': 'This account is already closed.',
	'already-open': 'This account is already open.'
};

/** A leg identifier for the operator log — the classification, never the raise text. */
function failureLabel(f: CloseFailure): string {
	if (f.kind === 'gate') return `gate:${f.leg}`;
	if (f.kind === 'rpc') return `rpc:${f.refusal}`;
	return 'unclassified';
}

/**
 * The close-control error path, SHARED by closeAccount and reopenAccount.
 *
 * Shared deliberately rather than duplicated per action: both directions can trip 058's two
 * already-closed immutability conjuncts, both get an RPC refusal, and the F8 redaction below is a
 * property of the RAISES, not of the direction. Two copies would let one drift back to logging
 * `updErr.message` while the other stayed correct — and the drifted one would look fine in review.
 */
function closeControlFailure(updErr: { message?: string | null; code?: string }) {
	const failure = classifyCloseFailure(updErr.message ?? '');
	// ⚠ NEVER LOG `updErr.message` ON THIS PATH (Sec joint-review, PR #318 F8).
	//   058's gate raises are operator-precise BY VALUE: leg 2 interpolates a real account CASH
	//   BALANCE (`% native`), legs 1/2/3 interpolate the closing DATE, and the two already-closed
	//   immutability conjuncts interpolate both closure dates. Logs are operator-only, which is
	//   why this is a redaction and not a veto — but this project redacts concrete money even from
	//   committed artifacts, and log shipping/retention is a Phase-7 surface nobody has scoped for
	//   financial values. Shipping the amount into the log stream on every blocked close
	//   pre-commits that decision.
	//   The operator still gets what they need to act: the SQLSTATE and WHICH LEG FIRED, derived
	//   from the SAME classification the user-facing copy uses — one classifier, so the log and
	//   the message cannot drift apart. What they do not get is the amount.
	console.error(
		`[accounts/[account_id]] close-control RPC failed: code=${updErr.code ?? 'none'} ${failureLabel(failure)}`
	);
	// The close gate refuses with a named leg (holdings / cash / post-closure activity /
	// future-dated). ADR-042 Decision 1 requires the refusal to NAME why, so the user knows the
	// account holds value rather than that "something went wrong" — a guided close-with-funds
	// walkthrough is future work and the message stands in for it.
	if (failure.kind === 'gate')
		return fail(422, { errors: { _form: [GATE_LEG_MESSAGE[failure.leg]] } });
	// The RPCs' own refusals carry a distinct prefix and mean "already in that state", not
	// "blocked". Classified after the gate so a gate raise always wins.
	if (failure.kind === 'rpc')
		return fail(409, { errors: { _form: [RPC_REFUSAL_MESSAGE[failure.refusal]] } });
	return fail(422, { errors: { _form: ['Could not update the account.'] } });
}

export const actions: Actions = {
	// ── The account CLOSE / REOPEN control (ADR-042 Decision 1; the RPC pair per Amendment 2) ──
	//
	// TWO ACTIONS, NOT A TOGGLE. `toggleActive` (which posted an `is_active` boolean) is retired
	// with the column at 059, and it is SPLIT rather than renamed. A toggle models closure as a
	// flag with two values; ADR-042 ruled it a dated TRANSITION with two directions that carry
	// different payloads — a close needs a reason_code, a reopen has no reason vocabulary at all.
	// Keeping one action meant a boolean plus a cross-field `.refine()` making reason_code
	// conditionally required, i.e. a state machine wearing a boolean. That is the same shape at
	// the app layer that 059 removed at the schema layer, and renaming it would have carried it
	// forward under a better name. Each action now maps 1:1 onto its INVOKER RPC.
	//
	// WHY AN RPC AND NOT A PATCH (both directions): 058's audit writer requires `pfin.reason_code`
	// to be set in the SAME TRANSACTION as the close, and it deliberately will not invent one. A
	// PostgREST PATCH is its own transaction with no way to carry a GUC alongside it, so a direct
	// .update() CANNOT close an account — it fails every time. The INVOKER RPC sets the GUC and
	// performs the UPDATE in one request, so the two share a transaction BY CONSTRUCTION rather
	// than by convention. RLS, the aal2 conjunct, the close gate, the biconditional and the audit
	// writer all still evaluate as the caller.
	closeAccount: async ({ request, locals, params }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const accountId = parseAccountId(params.account_id);
		if (accountId === null) return fail(400, { errors: { _form: ['Invalid account.'] } });

		const parsed = closeAccountSchema.safeParse(Object.fromEntries(await request.formData()));
		if (!parsed.success) return fail(400, { errors: fieldErrors(parsed.error) });

		// closed_at is NOT sent: p_closed_at defaults to server now(). Sending a client clock
		// would let a machine a minute fast trip the gate's own future-date bound.
		const { data: applied, error: updErr } = await locals.supabase
			.schema('pfin')
			.rpc('fn_close_account', {
				p_account_id: accountId,
				p_reason_code: parsed.data.reason_code
			});

		if (updErr) return closeControlFailure(updErr);

		// SERVER-APPLIED STATE, not the posted value (Sec joint-review, PR #318 F8 note).
		// 058 §(7)'s CONTRACT block: fn_close_account RETURNS the closed_at actually applied, and
		// that value is SERVER-derived — p_closed_at is deliberately not sent so it defaults to
		// server now(), which means the caller CANNOT otherwise know it.
		const closedAt = (applied as string | null) ?? null;
		if (closedAt === null) {
			// Contract breach, not a user condition: fn_close_account raises P0002 when it matches
			// no open row, so a no-error result with no timestamp means its RETURNING is broken.
			// Named in the log rather than reported to the user as an open account.
			console.error(
				'[accounts/[account_id]] fn_close_account returned no closed_at despite no error — RETURNING contract broken'
			);
		}
		return { success: true, closed_at: closedAt };
	},

	reopenAccount: async ({ request, locals, params }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const accountId = parseAccountId(params.account_id);
		if (accountId === null) return fail(400, { errors: { _form: ['Invalid account.'] } });

		// The schema is EMPTY-and-`.strict()`, so this is a real fence and not a formality: a
		// posted reason_code or closed_at is REJECTED rather than silently dropped.
		const parsed = reopenAccountSchema.safeParse(Object.fromEntries(await request.formData()));
		if (!parsed.success) return fail(400, { errors: fieldErrors(parsed.error) });

		const { error: updErr } = await locals.supabase
			.schema('pfin')
			.rpc('fn_reopen_account', { p_account_id: accountId });

		if (updErr) return closeControlFailure(updErr);

		// fn_reopen_account RETURNS void because a reopen applies NULL; that asymmetry IS the
		// contract (058 §(7)), so null here is the applied state, not a missing one.
		return { success: true, closed_at: null };
	},

	// Edit the account's user attributes: name / account_type / scope / tax_treatment. RLS-scoped
	// single-row UPDATE (account_update = users_id = auth.uid()). Deliberately does NOT touch the
	// aggregator / connection binding (deferred) nor closed_at (that's the close/reopen pair, and
	// 058 fences it at the DB regardless). `.strict()` +
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
			// 058 §(4)'s closed-account fence, classified FIRST and separately from the generic
			// envelope. fn_create_manual_trans INSERTs into pfin.account_trans, which 058 freezes on
			// a closed account — so this write CANNOT succeed while the account is closed, and the
			// old fallback ("Please try again") was retry advice for something that never will.
			// ⚠ THE UI GATING IS NOT WHAT MAKES THIS SAFE. The write stays reachable from a stale
			//   tab, a second window, or a provider sync landing on a freshly-closed account —
			//   hiding the form reduces how often this is seen and changes nothing about whether it
			//   can happen. The DB trigger is the fence; this is only its rendering.
			if (isClosedAccountWrite(rpcErr.message))
				return fail(409, { errors: { _form: [CLOSED_ACCOUNT_WRITE_MESSAGE] }, values: raw });
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
	//
	// SELF-249 binding option-B item 1 (F/CTO-ruled at PR #561 Sec joint review, 2026-08-25): a
	// reversal row (is_reverse=true) refuses this write. The E1 check lives in `upsertAnnotation`
	// itself (see its own header) — this action's only write, so no separate call is needed here.
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
	},

	// ── SELF-325 manual purchase-path (088 / fn_create_manual_purchase) ────────────────────
	// Posted `mode` selects BIND (`security_id`, resolved beforehand via /asset/resolve or a
	// selectableAssets.ts picker) or MINT (`asset_type`/`asset_name`[/`symbol`], a new
	// caller-owned asset). account_id is the route param, not a form field. `priced`/`price`/
	// `security_id` come back from the RPC's composite and are forwarded to the caller
	// UNCHANGED — see purchases.ts's module header for why projecting them away is the failure
	// ADR-049 Decision 4 exists to prevent. `priced` is a rendering indicator only.
	createPurchase: async ({ request, locals, params }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });
		const accountId = parseAccountId(params.account_id);
		if (accountId === null) return fail(400, { errors: { _form: ['Invalid account.'] } });

		const raw = Object.fromEntries(await request.formData());
		const parsed = createPurchaseSchema.safeParse(raw);
		if (!parsed.success) return fail(400, { errors: fieldErrors(parsed.error), values: raw });
		let v = parsed.data;

		// 088 deliberately does NOT default p_sub_cat_id (single-authority rule: selecting a
		// per-user taxonomy row is app-layer work). When the form omitted one, look up the
		// caller's default 'Trade'/'BTO' row; a miss (not provisioned / renamed / deactivated)
		// falls through as NULL — 088's own Unsorted-pending fallback, not an error.
		if (v.sub_cat_id === null) {
			const btoId = await findDefaultBtoSubCatId(locals.supabase);
			v = { ...v, sub_cat_id: btoId };
		}

		const result = await createManualPurchase(locals.supabase, accountId, v);
		if (!result.ok) {
			const key = result.field ?? '_form';
			return fail(result.status, { errors: { [key]: [result.message] }, values: raw });
		}
		return {
			success: true,
			transId: result.transId,
			securityId: result.securityId,
			priced: result.priced,
			price: result.price
		};
	}
};
