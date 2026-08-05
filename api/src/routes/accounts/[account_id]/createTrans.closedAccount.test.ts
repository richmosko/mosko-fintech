// createTrans.closedAccount.test.ts — 058 §(4)'s closed-account transfer-in fence, at the app
// layer.
//
// WHY THIS FILE EXISTS AT ALL, since the UI now hides the entry form on a closed account:
// GATING THE UI IS NOT A FENCE. The action stays reachable from a stale tab, a second window, or
// any client that posts directly, and a provider sync can land on an account closed a moment ago.
// The DB trigger is the boundary; these assertions cover its RENDERING — that the app tells the
// user the one thing they can act on instead of advising a retry that can never succeed.

import { describe, it, expect, vi } from 'vitest';
import { actions } from './+page.server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

// 058 §(4) verbatim shape: interpolates the account id AND the table name (tg_table_name).
const CLOSED_RAISE =
	'write blocked: account 7 is closed (account_trans). A closed account is frozen — reopen it, ' +
	'make the correction, then re-close (which re-proves the zero invariant).';

const VALID = {
	transaction_date: '2026-07-20',
	amount: '25.00',
	vendor: 'Coffee',
	description: 'flat white',
	sub_cat_id: '3',
	note: ''
};

function makeEvent(rpcErr: { message: string } | null) {
	const rpc = vi.fn(async (_fn: string, _args: Record<string, unknown>) => ({
		data: rpcErr ? null : 99,
		error: rpcErr
	}));
	const schema = vi.fn(() => ({ rpc, from: vi.fn() }));
	const request = new Request('http://localhost/accounts/7', {
		method: 'POST',
		body: new URLSearchParams(VALID)
	});
	const locals = {
		safeGetSession: async () => ({ session: {}, user: { id: SESSION_UID } }),
		supabase: { schema }
	};
	return {
		event: { request, locals, params: { account_id: '7' } } as unknown as Parameters<
			typeof actions.createTrans
		>[0]
	};
}

describe('createTrans — the 058 closed-account fence', () => {
	it('is classified, not swallowed by the generic envelope', async () => {
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		try {
			const { event } = makeEvent({ message: CLOSED_RAISE });
			const res = (await actions.createTrans(event)) as {
				status: number;
				data: { errors: { _form?: string[] } };
			};

			// 409, not 422: the request is well-formed and the account STATE is the conflict.
			expect(res.status).toBe(409);
			expect(res.data.errors._form?.[0]).toContain('closed');
		} finally {
			spy.mockRestore();
		}
	});

	it('carries the REMEDY and never advises a retry', async () => {
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		try {
			const { event } = makeEvent({ message: CLOSED_RAISE });
			const res = (await actions.createTrans(event)) as { data: { errors: { _form?: string[] } } };
			const shown = res.data.errors._form?.[0] ?? '';

			// THE DEFECT THIS FILE EXISTS FOR: "Please try again" is advice for something that can
			// never succeed while the account is closed, and the DB was supplying the real remedy
			// which the app discarded.
			expect(shown).not.toMatch(/try again/i);
			expect(shown).toMatch(/reopen/i);
		} finally {
			spy.mockRestore();
		}
	});

	it('leaks neither the account id nor the table name from the raise', async () => {
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		try {
			const { event } = makeEvent({ message: CLOSED_RAISE });
			const res = (await actions.createTrans(event)) as { data: { errors: { _form?: string[] } } };
			const shown = res.data.errors._form?.[0] ?? '';

			expect(shown).not.toContain('account_trans'); // tg_table_name — names an implementation
			expect(shown).not.toMatch(/\b7\b/);
		} finally {
			spy.mockRestore();
		}
	});

	it('a DIFFERENT raise still falls through to the generic envelope', async () => {
		// Non-vacuity: the assertions above would also pass if every error rendered the closed-account
		// message. The classifier must be narrow.
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		try {
			const { event } = makeEvent({ message: 'could not serialize access due to concurrent update' });
			const res = (await actions.createTrans(event)) as {
				status: number;
				data: { errors: { _form?: string[] } };
			};
			expect(res.status).toBe(422);
			expect(res.data.errors._form?.[0]).toMatch(/try again/i);
		} finally {
			spy.mockRestore();
		}
	});
});
