// toggleAccount.server.test.ts — connections-redesign per-connection use/ignore action.
// Locks the auth-gate → .strict() body-parse → single-row RLS-scoped UPDATE → error-envelope
// behavior. The RLS ownership fence is proven by QA's pgTAP battery; here we mock the client to
// assert the action's contract (keyed on account_id; is_active coerced; mass-assignment rejected).

import { describe, it, expect, vi } from 'vitest';
import { actions } from './+page.server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

/** Build an action event whose form carries the given fields; captures the UPDATE payload + filter. */
function makeEvent(fields: Record<string, string>, user: { id: string } | null) {
	const update = vi.fn(() => ({ eq }));
	const eq = vi.fn(async () => ({ error: null }));
	const from = vi.fn(() => ({ update }));
	const schema = vi.fn(() => ({ from }));
	const request = new Request('http://localhost/accounts/connections/42', {
		method: 'POST',
		body: new URLSearchParams(fields)
	});
	const locals = {
		safeGetSession: async () => ({ session: user ? {} : null, user }),
		supabase: { schema }
	};
	const event = { request, locals } as unknown as Parameters<typeof actions.toggleAccount>[0];
	return { event, update, eq };
}

/** Failing-UPDATE variant (RLS/db error). */
function makeFailingEvent(fields: Record<string, string>) {
	const eq = vi.fn(async () => ({ error: { message: 'db broke' } }));
	const update = vi.fn(() => ({ eq }));
	const from = vi.fn(() => ({ update }));
	const schema = vi.fn(() => ({ from }));
	const request = new Request('http://localhost/accounts/connections/42', {
		method: 'POST',
		body: new URLSearchParams(fields)
	});
	const locals = {
		safeGetSession: async () => ({ session: {}, user: { id: SESSION_UID } }),
		supabase: { schema }
	};
	return { event: { request, locals } as unknown as Parameters<typeof actions.toggleAccount>[0] };
}

describe('POST /accounts/connections/[source_id]?/toggleAccount', () => {
	it('unauthenticated → 401, UPDATE never issued', async () => {
		const { event, update } = makeEvent({ account_id: '5', is_active: 'false' }, null);
		const res = (await actions.toggleAccount(event)) as { status: number };
		expect(res.status).toBe(401);
		expect(update).not.toHaveBeenCalled();
	});

	it('valid body → single-row UPDATE keyed on account_id; is_active coerced from form string', async () => {
		const { event, update, eq } = makeEvent(
			{ account_id: '5', is_active: 'false' },
			{ id: SESSION_UID }
		);
		const res = (await actions.toggleAccount(event)) as {
			success: boolean;
			account_id: number;
			is_active: boolean;
		};
		expect(update).toHaveBeenCalledWith({ is_active: false });
		expect(eq).toHaveBeenCalledWith('account_id', 5);
		expect(res).toEqual({ success: true, account_id: 5, is_active: false });
	});

	it('is_active "on"/"true"/"1" coerce to true', async () => {
		for (const v of ['on', 'true', '1']) {
			const { event, update } = makeEvent({ account_id: '5', is_active: v }, { id: SESSION_UID });
			await actions.toggleAccount(event);
			expect(update).toHaveBeenCalledWith({ is_active: true });
		}
	});

	it('missing account_id → 400, UPDATE never issued', async () => {
		const { event, update } = makeEvent({ is_active: 'false' }, { id: SESSION_UID });
		const res = (await actions.toggleAccount(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(update).not.toHaveBeenCalled();
	});

	it('mass-assignment: extra posted column rejected by .strict() → 400', async () => {
		const { event, update } = makeEvent(
			{ account_id: '5', is_active: 'false', users_id: 'bbbb' },
			{ id: SESSION_UID }
		);
		const res = (await actions.toggleAccount(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(update).not.toHaveBeenCalled();
	});

	it('UPDATE error → 422', async () => {
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { event } = makeFailingEvent({ account_id: '5', is_active: 'false' });
		const res = (await actions.toggleAccount(event)) as { status: number };
		expect(res.status).toBe(422);
		spy.mockRestore();
	});
});
