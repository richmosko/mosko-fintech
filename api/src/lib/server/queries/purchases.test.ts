// purchases.test.ts — SELF-325 createManualPurchase RPC wrapper + 088 raise-message classifiers.
// Mocks the supabase chain (schema→rpc→single), mirroring the sibling query-module tests.

import { describe, it, expect, vi } from 'vitest';
import {
	createManualPurchase,
	PROVIDER_LINKED_PURCHASE_MESSAGE,
	ZERO_ROUNDED_PRICE_MESSAGE,
	CURRENCY_ASSET_TYPE_MESSAGE,
	ASSET_NOT_BINDABLE_MESSAGE,
	STALE_ZERO_VALUATION_MESSAGE
} from './purchases';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { BindPurchaseInput, MintPurchaseInput } from '$lib/server/schemas/purchase';

function makeSupabase(result: { data?: unknown; error?: unknown }) {
	const single = vi.fn(async () => result);
	const rpc = vi.fn(() => ({ single }));
	const schema = vi.fn(() => ({ rpc }));
	return { supabase: { schema } as unknown as SupabaseClient, schema, rpc, single };
}

const BIND: BindPurchaseInput = {
	mode: 'bind',
	security_id: 501,
	trade_date: '2026-08-15',
	quantity: 10,
	cost_basis: 1500,
	sub_cat_id: 7,
	description: null,
	note: null
};

const MINT: MintPurchaseInput = {
	mode: 'mint',
	asset_type: 'real_estate',
	asset_name: 'Rental House',
	symbol: null,
	trade_date: '2026-08-15',
	quantity: 1,
	cost_basis: 250000,
	sub_cat_id: null,
	description: null,
	note: null
};

const HAPPY_ROW = { trans_id: 900, security_id: 501, priced: true, price: 150 };

describe('createManualPurchase — happy path', () => {
	it('BIND: builds p_security_id args and returns the full composite (priced/price forwarded)', async () => {
		const { supabase, schema, rpc, single } = makeSupabase({ data: HAPPY_ROW, error: null });
		const result = await createManualPurchase(supabase, 10, BIND);

		expect(schema).toHaveBeenCalledWith('pfin');
		expect(rpc).toHaveBeenCalledWith('fn_create_manual_purchase', {
			p_account_id: 10,
			p_trade_date: '2026-08-15',
			p_quantity: 10,
			p_cost_basis: 1500,
			p_security_id: 501,
			p_sub_cat_id: 7,
			p_description: null,
			p_note: null
		});
		expect(single).toHaveBeenCalled();
		expect(result).toEqual({ ok: true, transId: 900, securityId: 501, priced: true, price: 150 });
	});

	it('MINT: builds p_asset_type/p_asset_name/p_symbol args, no p_security_id', async () => {
		const { supabase, rpc } = makeSupabase({ data: HAPPY_ROW, error: null });
		await createManualPurchase(supabase, 10, MINT);
		expect(rpc).toHaveBeenCalledWith('fn_create_manual_purchase', {
			p_account_id: 10,
			p_trade_date: '2026-08-15',
			p_quantity: 1,
			p_cost_basis: 250000,
			p_asset_type: 'real_estate',
			p_asset_name: 'Rental House',
			p_symbol: null,
			p_sub_cat_id: null,
			p_description: null,
			p_note: null
		});
	});

	it('forwards priced=false and its price unchanged (the unpriced-but-loud global-asset branch)', async () => {
		const { supabase } = makeSupabase({ data: { trans_id: 1, security_id: 2, priced: false, price: 5 }, error: null });
		const result = await createManualPurchase(supabase, 10, BIND);
		expect(result).toEqual({ ok: true, transId: 1, securityId: 2, priced: false, price: 5 });
	});

	it('coerces a string-typed numeric(20,4) price to a number (PostgREST may serialize as string)', async () => {
		const { supabase } = makeSupabase({
			data: { trans_id: 1, security_id: 2, priced: true, price: '150.0000' },
			error: null
		});
		const result = await createManualPurchase(supabase, 10, BIND);
		expect(result).toEqual({ ok: true, transId: 1, securityId: 2, priced: true, price: 150 });
	});
});

describe('createManualPurchase — 088 raise-message classification', () => {
	it('account not found/visible → 404', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { supabase } = makeSupabase({
			data: null,
			error: { message: 'Account 10 not found or not visible to this caller (SELF-325 / 088).' }
		});
		await expect(createManualPurchase(supabase, 10, BIND)).resolves.toEqual({
			ok: false,
			status: 404,
			message: 'Account not found.'
		});
		errSpy.mockRestore();
	});

	it('provider-linked account → 422 with the source-of-truth remedy', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { supabase } = makeSupabase({
			data: null,
			error: {
				message:
					'Account 10 is provider-linked, so its transactions come from the provider. Recording a purchase manually here would double-count it against the next sync (SELF-325 / 088; the 039 source-of-truth guard).'
			}
		});
		const result = await createManualPurchase(supabase, 10, BIND);
		expect(result).toEqual({ ok: false, status: 422, message: PROVIDER_LINKED_PURCHASE_MESSAGE });
		errSpy.mockRestore();
	});

	it('zero-rounded per-unit price → 422, field quantity', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { supabase } = makeSupabase({
			data: null,
			error: {
				message:
					'This purchase derives a per-unit price of 0.0000 and would record a worthless trade: cost_basis 10.00 over quantity 1000000 is below the numeric(20,4) price grain (SELF-325 / 088).'
			}
		});
		const result = await createManualPurchase(supabase, 10, BIND);
		expect(result).toEqual({ ok: false, status: 422, field: 'quantity', message: ZERO_ROUNDED_PRICE_MESSAGE });
		errSpy.mockRestore();
	});

	it("asset_type='currency' in MINT mode → 422, field asset_type, routes to cash-entry", async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { supabase } = makeSupabase({
			data: null,
			error: { message: "p_asset_type may not be 'currency': cash is amount-carried, not instrument-carried." }
		});
		const result = await createManualPurchase(supabase, 10, MINT);
		expect(result).toEqual({ ok: false, status: 422, field: 'asset_type', message: CURRENCY_ASSET_TYPE_MESSAGE });
		errSpy.mockRestore();
	});

	it('BIND: security_id not global-or-owned → 422, field security_id', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { supabase } = makeSupabase({
			data: null,
			error: { message: 'security_id 999 is not a global or caller-owned asset (SELF-325 / 088).' }
		});
		const result = await createManualPurchase(supabase, 10, BIND);
		expect(result).toEqual({ ok: false, status: 422, field: 'security_id', message: ASSET_NOT_BINDABLE_MESSAGE });
		errSpy.mockRestore();
	});

	it('pre-existing non-positive manual valuation → 422, field trade_date', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { supabase } = makeSupabase({
			data: null,
			error: {
				message:
					'A manual valuation already exists for this asset at 2026-08-15 and its price is 0 — the position would value at zero (SELF-325 / 088).'
			}
		});
		const result = await createManualPurchase(supabase, 10, BIND);
		expect(result).toEqual({ ok: false, status: 422, field: 'trade_date', message: STALE_ZERO_VALUATION_MESSAGE });
		errSpy.mockRestore();
	});

	it('an unrecognized raise falls to the generic envelope (no detail leak)', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { supabase } = makeSupabase({ data: null, error: { message: 'some unrelated internal error' } });
		const result = await createManualPurchase(supabase, 10, BIND);
		expect(result).toEqual({ ok: false, status: 422, message: 'Could not record the purchase. Please try again.' });
		errSpy.mockRestore();
	});

	it('mode-confusion raises (should be unreachable via a schema-correct action) still fall to the generic envelope, double-logged', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { supabase } = makeSupabase({
			data: null,
			error: { message: 'Supply either p_security_id (bind an existing asset) or p_asset_type + p_asset_name.' }
		});
		const result = await createManualPurchase(supabase, 10, BIND);
		expect(result.ok).toBe(false);
		if (!result.ok) expect(result.status).toBe(422);
		errSpy.mockRestore();
	});

	it('a null row on success (should-never-happen) → 502 generic, logged', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { supabase } = makeSupabase({ data: null, error: null });
		const result = await createManualPurchase(supabase, 10, BIND);
		expect(result).toEqual({ ok: false, status: 502, message: 'Could not record the purchase. Please try again.' });
		errSpy.mockRestore();
	});
});
