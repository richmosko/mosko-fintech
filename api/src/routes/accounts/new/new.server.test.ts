// new.server.test.ts — manual-account creation server surface (SELF-201 §2.4.2).
//
// SELF-267 AC 2/2a/3 create-then-update coverage: fn_create_manual_account's signature is
// UNCHANGED (087) — tax_jurisdiction is realized as a SECOND statement, an ordinary UPDATE,
// AFTER the RPC has committed. These legs lock: the RPC call carries no tax_jurisdiction arg;
// a null (absent/'') tax_jurisdiction skips the UPDATE entirely; a non-null value issues it;
// a post-create 23505 does NOT roll the account back and reports a field error WITH the
// created account's id; the create RPC's own failure path is untouched.

import { describe, it, expect, vi } from 'vitest';
import { actions } from './+page.server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const NEW_ACCOUNT_ID = 42;

const VALID = {
	name: 'Brokerage',
	account_type: 'investment',
	scope: 'personal',
	tax_treatment: 'taxable',
	initial_value: '100.00',
	as_of_date: '2026-01-01'
};

function makeEvent(
	fields: Record<string, string>,
	user: { id: string } | null,
	rpcErr: { message: string } | null = null,
	taxUpdateErr: { message: string; code?: string } | null = null
) {
	const rpc = vi.fn(async () => ({ data: rpcErr ? null : NEW_ACCOUNT_ID, error: rpcErr }));
	const eq = vi.fn(async () => ({ error: taxUpdateErr }));
	const update = vi.fn(() => ({ eq }));
	const from = vi.fn(() => ({ update }));
	const schema = vi.fn(() => ({ rpc, from }));
	const request = new Request('http://localhost/accounts/new', {
		method: 'POST',
		body: new URLSearchParams(fields)
	});
	const locals = {
		safeGetSession: async () => ({ session: user ? {} : null, user }),
		supabase: { schema }
	};
	const event = {
		request,
		locals
	} as unknown as Parameters<typeof actions.default>[0];
	return { event, rpc, update, eq };
}

describe('POST /accounts/new', () => {
	it('unauthenticated → 401, RPC never issued', async () => {
		const { event, rpc } = makeEvent(VALID, null);
		const res = (await actions.default(event)) as { status: number };
		expect(res.status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('no tax_jurisdiction posted → RPC called WITHOUT any tax_jurisdiction arg, no follow-up UPDATE, redirects', async () => {
		const { event, rpc, update } = makeEvent(VALID, { id: SESSION_UID });
		await expect(actions.default(event)).rejects.toMatchObject({ status: 303 });
		expect(rpc).toHaveBeenCalledWith(
			'fn_create_manual_account',
			expect.not.objectContaining({ p_tax_jurisdiction: expect.anything() })
		);
		expect(update).not.toHaveBeenCalled();
	});

	it("tax_jurisdiction posted '' → treated as null, no follow-up UPDATE", async () => {
		const { event, update } = makeEvent({ ...VALID, tax_jurisdiction: '' }, { id: SESSION_UID });
		await expect(actions.default(event)).rejects.toMatchObject({ status: 303 });
		expect(update).not.toHaveBeenCalled();
	});

	it("tax_jurisdiction posted 'ftb' → RPC creates unchanged, THEN a follow-up UPDATE sets it, redirects", async () => {
		const { event, rpc, update, eq } = makeEvent(
			{ ...VALID, tax_jurisdiction: 'ftb' },
			{ id: SESSION_UID }
		);
		await expect(actions.default(event)).rejects.toMatchObject({ status: 303 });
		expect(rpc).toHaveBeenCalledWith(
			'fn_create_manual_account',
			expect.objectContaining({
				p_name: 'Brokerage',
				p_account_type: 'investment',
				p_scope: 'personal',
				p_tax_treatment: 'taxable',
				p_initial_value: 100,
				p_as_of_date: '2026-01-01'
			})
		);
		expect(rpc).toHaveBeenCalledWith(
			'fn_create_manual_account',
			expect.not.objectContaining({ p_tax_jurisdiction: expect.anything() })
		);
		expect(update).toHaveBeenCalledWith({ tax_jurisdiction: 'ftb' });
		expect(eq).toHaveBeenCalledWith('account_id', NEW_ACCOUNT_ID);
	});

	it('bad tax_jurisdiction value → 400, RPC never issued', async () => {
		const { event, rpc } = makeEvent(
			{ ...VALID, tax_jurisdiction: 'not_an_authority' },
			{ id: SESSION_UID }
		);
		const res = (await actions.default(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('create RPC fails → 422, no follow-up UPDATE attempted (unaffected by SELF-267)', async () => {
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { event, update } = makeEvent({ ...VALID, tax_jurisdiction: 'irs' }, { id: SESSION_UID }, {
			message: 'boom'
		});
		const res = (await actions.default(event)) as { status: number };
		expect(res.status).toBe(422);
		expect(update).not.toHaveBeenCalled();
		spy.mockRestore();
	});

	it('post-create 23505 on account_tax_jurisdiction_uniq → 409, account NOT rolled back, accountId returned', async () => {
		const { event } = makeEvent({ ...VALID, tax_jurisdiction: 'irs' }, { id: SESSION_UID }, null, {
			message: 'duplicate key value violates unique constraint "account_tax_jurisdiction_uniq"',
			code: '23505'
		});
		const res = (await actions.default(event)) as {
			status: number;
			data: { errors: Record<string, string[]>; accountId: number };
		};
		expect(res.status).toBe(409);
		expect(res.data.errors.tax_jurisdiction[0]).not.toMatch(/irs|ftb/i);
		expect(res.data.accountId).toBe(NEW_ACCOUNT_ID);
	});

	it('post-create non-23505 UPDATE failure → 422, account NOT rolled back, accountId returned', async () => {
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { event } = makeEvent({ ...VALID, tax_jurisdiction: 'irs' }, { id: SESSION_UID }, null, {
			message: 'db broke'
		});
		const res = (await actions.default(event)) as {
			status: number;
			data: { errors: Record<string, string[]>; accountId: number };
		};
		expect(res.status).toBe(422);
		expect(res.data.accountId).toBe(NEW_ACCOUNT_ID);
		spy.mockRestore();
	});

	it('mass-assignment: sub_cat_id posted → rejected by .strict() → 400', async () => {
		const { event, rpc } = makeEvent({ ...VALID, sub_cat_id: '5' }, { id: SESSION_UID });
		const res = (await actions.default(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(rpc).not.toHaveBeenCalled();
	});
});
