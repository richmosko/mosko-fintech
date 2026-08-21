// purchases.ts — server-side write helper for the SELF-325 manual purchase-path
// (`pfin.fn_create_manual_purchase`, migration 088). Backend-owned server source.
//
// SECURITY INVOKER read-composition: the RPC runs under the caller's RLS (Lock 11) — this module
// never touches service_role. The DB raises are the authoritative guard; this file only
// classifies its raise-message text into friendly, field-scoped errors for the form action (the
// same shape transactions.ts's isClosedAccountWrite / createStockSplit classifiers use — see that
// file's own note on why a private-per-call-site copy is the drift pattern NOT to follow: these
// classifiers are exported so a second purchase-path call site reuses them rather than
// re-deriving the same regex).
//
// `priced` / `price` / `security_id` are read from the RPC's composite return and threaded
// through to the caller UNCHANGED — projecting them away is the failure ADR-049 Decision 4's
// composite-return shape exists to prevent (Architect, SELF-325 088 handoff). `priced` is a
// RENDERING indicator only; nothing here (or downstream) may compute money from it.
//
// NOT AN A2 AUDIT-DEFERRAL SITE (Architect's refined ruling, SELF-325 round-3 handoff): this
// module makes exactly ONE RPC call inside `createManualPurchase`, so there is no in-app
// transaction for a same-transaction audit row to belong to or be deferred from — this file is
// not on the A2 deferral list, and must not be added to it later. The audit row, when the A2
// infra lands, belongs INSIDE `pfin.fn_create_manual_purchase` (088) itself, at its own named
// "AUDIT FORWARD-HOOK" comment — not here.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { CreatePurchaseInput } from '$lib/server/schemas/purchase';

export type PurchaseResult =
	| { ok: true; transId: number; securityId: number; priced: boolean; price: number }
	| { ok: false; status: number; field?: string; message: string };

// ── 088 raise-message classifiers, most-specific-first at the call site ─────────────────────────
// Each matches on a distinctive substring of the ACTUAL raise text (088_manual_purchase_path.sql),
// not a paraphrase — verified against the migration source at authoring time.

/** account not owned / not visible under RLS → 404 (no existence leak). */
function isAccountNotVisible(message: string): boolean {
	return /not found or not visible/i.test(message);
}

/** the 039 source-of-truth guard: a provider-linked account rejects manual purchases (the same
 *  provider will report this buy on its next sync). */
function isProviderLinkedPurchase(message: string): boolean {
	return /provider-linked/i.test(message);
}
export const PROVIDER_LINKED_PURCHASE_MESSAGE =
	'This account is linked to a provider — its purchases are recorded automatically during the next sync, not entered manually.';

/** the unconditional zero-rounded-price fence (§4 of 088): the ratio, not either operand alone. */
function isZeroRoundedPrice(message: string): boolean {
	return /would record a worthless trade/i.test(message);
}
export const ZERO_ROUNDED_PRICE_MESSAGE =
	'This quantity and cost basis derive a per-unit price of $0.0000, which would record a worthless trade. Enter a smaller quantity or a larger cost basis.';

/** MINT mode's one explicit vocabulary rejection — cash is not an instrument. */
function isCurrencyAssetType(message: string): boolean {
	return /may not be 'currency'/i.test(message);
}
export const CURRENCY_ASSET_TYPE_MESSAGE =
	'Cash is not a purchasable instrument — record a currency movement from the account’s cash-entry form instead.';

/** BIND mode: the supplied security_id is neither global nor an asset the caller owns. */
function isAssetNotBindable(message: string): boolean {
	return /is not a global or caller-owned asset/i.test(message);
}
export const ASSET_NOT_BINDABLE_MESSAGE =
	'That security could not be found or is not available to purchase. Try resolving it again.';

/** an existing (non-positive) manual valuation at the trade date blocks the purchase — F3-b. */
function isStaleZeroValuation(message: string): boolean {
	return /manual valuation already exists/i.test(message);
}
export const STALE_ZERO_VALUATION_MESSAGE =
	'This asset already has a $0 (or negative) valuation on this date. Correct that valuation before recording a purchase against it.';

/** the mode-fork raises (both-or-neither p_security_id / p_asset_type+p_asset_name) — a
 *  programming-error class, unreachable through a schema-correct form action (the
 *  z.discriminatedUnion('mode', ...) shape makes the fork explicit before the RPC ever runs). */
function isModeConfusion(message: string): boolean {
	return /Supply either p_security_id|must name what was bought/i.test(message);
}

/** the Lock 14 numeric fences 088 also carries at the DB layer (quantity/cost_basis <= 0 / NaN /
 *  Infinity) — defensive only; the Zod battery (schemas/purchase.ts) rejects these first. */
function isQuantityInvalid(message: string): boolean {
	return /p_quantity must be a finite number/i.test(message);
}
function isCostBasisInvalid(message: string): boolean {
	return /p_cost_basis must be a finite number/i.test(message);
}

/** MINT mode's empty-name guard — defensive; the Zod `.min(1, ...)` rejects this first. */
function isAssetNameEmpty(message: string): boolean {
	return /p_asset_name must not be empty/i.test(message);
}

/**
 * Build the RPC args for either mode and call `pfin.fn_create_manual_purchase`. Returns the full
 * composite (trans_id, security_id, priced, price) on success — the caller MUST forward `priced`
 * to the UI (see module header); nothing here decides to drop it.
 */
export async function createManualPurchase(
	supabase: SupabaseClient,
	accountId: number,
	v: CreatePurchaseInput
): Promise<PurchaseResult> {
	const args =
		v.mode === 'bind'
			? {
					p_account_id: accountId,
					p_trade_date: v.trade_date,
					p_quantity: v.quantity,
					p_cost_basis: v.cost_basis,
					p_security_id: v.security_id,
					p_sub_cat_id: v.sub_cat_id,
					p_description: v.description,
					p_note: v.note
				}
			: {
					p_account_id: accountId,
					p_trade_date: v.trade_date,
					p_quantity: v.quantity,
					p_cost_basis: v.cost_basis,
					p_asset_type: v.asset_type,
					p_asset_name: v.asset_name,
					p_symbol: v.symbol,
					p_sub_cat_id: v.sub_cat_id,
					p_description: v.description,
					p_note: v.note
				};

	const { data, error: rpcErr } = await supabase.schema('pfin').rpc('fn_create_manual_purchase', args).single();

	if (rpcErr) {
		const msg = rpcErr.message;
		console.error('[purchases] createManualPurchase RPC failed:', msg);

		// 058 §(4) closed-account fence is NOT reachable here: 088's own source-of-truth guard
		// only refuses provider-linked accounts (checked below), and a closed manual account's
		// account_trans INSERT hits 058 with the SAME "write blocked: ... is closed" text every
		// other write path uses — defensive belt-and-suspenders, same import as transactions.ts.
		if (isAccountNotVisible(msg)) return { ok: false, status: 404, message: 'Account not found.' };
		if (isProviderLinkedPurchase(msg)) return { ok: false, status: 422, message: PROVIDER_LINKED_PURCHASE_MESSAGE };
		if (isZeroRoundedPrice(msg))
			return { ok: false, status: 422, field: 'quantity', message: ZERO_ROUNDED_PRICE_MESSAGE };
		if (isCurrencyAssetType(msg))
			return { ok: false, status: 422, field: 'asset_type', message: CURRENCY_ASSET_TYPE_MESSAGE };
		if (isAssetNotBindable(msg))
			return { ok: false, status: 422, field: 'security_id', message: ASSET_NOT_BINDABLE_MESSAGE };
		if (isStaleZeroValuation(msg))
			return { ok: false, status: 422, field: 'trade_date', message: STALE_ZERO_VALUATION_MESSAGE };
		if (isQuantityInvalid(msg))
			return { ok: false, status: 400, field: 'quantity', message: 'Enter a quantity greater than zero.' };
		if (isCostBasisInvalid(msg))
			return { ok: false, status: 400, field: 'cost_basis', message: 'Enter a cost basis greater than zero.' };
		if (isAssetNameEmpty(msg))
			return { ok: false, status: 400, field: 'asset_name', message: 'Name is required.' };
		if (isModeConfusion(msg)) {
			// Should be unreachable via a schema-correct action — a real hit here is a bug in this
			// module, not a user mistake, so it gets the generic envelope rather than a fabricated
			// field-specific remedy.
			console.error('[purchases] mode-confusion raise reached the app layer (schema bug?):', msg);
		}
		return { ok: false, status: 422, message: 'Could not record the purchase. Please try again.' };
	}

	const row = data as { trans_id: number; security_id: number; priced: boolean; price: number | string } | null;
	if (!row) {
		console.error('[purchases] createManualPurchase RPC returned no row');
		return { ok: false, status: 502, message: 'Could not record the purchase. Please try again.' };
	}

	return {
		ok: true,
		transId: row.trans_id,
		securityId: row.security_id,
		priced: row.priced,
		price: Number(row.price) // numeric(20,4) may arrive as a string over PostgREST
	};
}
