// updateAttributes.server.test.ts — account-detail attribute-edit action.
// Locks auth-gate → account-id parse → .strict() body-parse (enums + name/scope rules) →
// single-row RLS-scoped UPDATE → error-envelope. RLS ownership is proven by QA's pgTAP battery;
// here the client is mocked to assert the action's contract (only the 4 attributes are written;
// mass-assignment + bad enums rejected).

import { describe, it, expect, vi } from 'vitest';
import { actions } from './+page.server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

const VALID = {
	name: 'Brokerage',
	account_type: 'investment',
	scope: 'personal',
	tax_treatment: 'taxable'
};

function makeEvent(
	fields: Record<string, string>,
	user: { id: string } | null,
	accountId = '7',
	updErr: { message: string } | null = null
) {
	const eq = vi.fn(async () => ({ error: updErr }));
	const update = vi.fn(() => ({ eq }));
	const from = vi.fn(() => ({ update }));
	const schema = vi.fn(() => ({ from }));
	const request = new Request(`http://localhost/accounts/${accountId}`, {
		method: 'POST',
		body: new URLSearchParams(fields)
	});
	const locals = {
		safeGetSession: async () => ({ session: user ? {} : null, user }),
		supabase: { schema }
	};
	const event = {
		request,
		locals,
		params: { account_id: accountId }
	} as unknown as Parameters<typeof actions.updateAttributes>[0];
	return { event, update, eq };
}

describe('POST /accounts/[account_id]?/updateAttributes', () => {
	it('unauthenticated → 401, UPDATE never issued', async () => {
		const { event, update } = makeEvent(VALID, null);
		const res = (await actions.updateAttributes(event)) as { status: number };
		expect(res.status).toBe(401);
		expect(update).not.toHaveBeenCalled();
	});

	it('valid body → UPDATE writes ONLY the 4 attributes, keyed on account_id', async () => {
		const { event, update, eq } = makeEvent(VALID, { id: SESSION_UID }, '7');
		const res = (await actions.updateAttributes(event)) as { success: boolean };
		expect(update).toHaveBeenCalledWith({
			name: 'Brokerage',
			account_type: 'investment',
			scope: 'personal',
			tax_treatment: 'taxable'
		});
		expect(eq).toHaveBeenCalledWith('account_id', 7);
		expect(res).toEqual({ success: true });
	});

	it('bad account_type enum → 400, UPDATE never issued', async () => {
		const { event, update } = makeEvent(
			{ ...VALID, account_type: 'not_a_type' },
			{ id: SESSION_UID }
		);
		const res = (await actions.updateAttributes(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(update).not.toHaveBeenCalled();
	});

	it('empty name → 400', async () => {
		const { event } = makeEvent({ ...VALID, name: '' }, { id: SESSION_UID });
		const res = (await actions.updateAttributes(event)) as { status: number };
		expect(res.status).toBe(400);
	});

	it('mass-assignment: is_active / linked_source_id posted → rejected by .strict() → 400', async () => {
		const { event, update } = makeEvent(
			{ ...VALID, is_active: 'false', linked_source_id: '99' },
			{ id: SESSION_UID }
		);
		const res = (await actions.updateAttributes(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(update).not.toHaveBeenCalled();
	});

	it('invalid account_id param → 400', async () => {
		const { event } = makeEvent(VALID, { id: SESSION_UID }, 'abc');
		const res = (await actions.updateAttributes(event)) as { status: number };
		expect(res.status).toBe(400);
	});

	it('UPDATE error → 422', async () => {
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { event } = makeEvent(VALID, { id: SESSION_UID }, '7', { message: 'db broke' });
		const res = (await actions.updateAttributes(event)) as { status: number };
		expect(res.status).toBe(422);
		spy.mockRestore();
	});
});
