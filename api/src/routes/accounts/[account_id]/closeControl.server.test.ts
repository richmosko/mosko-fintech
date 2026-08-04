// closeControl.server.test.ts — the account CLOSE / REOPEN control
// (ADR-042 Decision 1; the INVOKER RPC pair per Amendment 2).
//
// The action is still named `toggleActive` and still posts `is_active` (the rename rides with
// the §7.9 application-layer landing), but the MECHANISM is now an RPC. These assertions exist
// because this path had NO coverage at all while it wrote is_active.
//
// THE LOAD-BEARING ONE IS `no-direct-patch`. 058's audit writer requires pfin.reason_code in
// the SAME TRANSACTION as the close and will not invent one; a PostgREST PATCH is its own
// transaction and cannot carry a GUC, so a regression to `.from('account').update(...)` CANNOT
// close an account — it fails 100% of the time. That regression is invisible in review (the
// column being written is still correct) and is caught here at unit speed rather than as an
// opaque failure in the pgTAP battery or, worse, in production.
//
// RLS ownership + the gate's own legs are proven by QA's pgTAP battery
// (058_account_closure_fences.sql); the client is mocked here to lock the action's contract.

import { describe, it, expect, vi } from 'vitest';
import { actions } from './+page.server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const CLOSE = { is_active: 'false', reason_code: 'no_longer_used' };
const REOPEN = { is_active: 'true' };

function makeEvent(
	fields: Record<string, string>,
	user: { id: string } | null,
	accountId = '7',
	rpcErr: { message: string } | null = null
) {
	// Typed params: without them `rpc.mock.calls[0]` is the empty tuple and the call-shape
	// assertions below cannot index it.
	const rpc = vi.fn(async (_fn: string, _args: Record<string, unknown>) => ({ error: rpcErr }));
	// `update` is mocked purely so a regression to the PATCH path is OBSERVABLE rather than a
	// TypeError. Nothing here should ever call it.
	const update = vi.fn((_payload: Record<string, unknown>) => ({ eq: vi.fn() }));
	const from = vi.fn(() => ({ update }));
	const schema = vi.fn(() => ({ from, rpc }));
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
	} as unknown as Parameters<typeof actions.toggleActive>[0];
	return { event, rpc, update };
}

describe('POST /accounts/[account_id]?/toggleActive — the close control', () => {
	it('unauthenticated → 401, nothing written', async () => {
		const { event, rpc, update } = makeEvent(CLOSE, null);
		const res = (await actions.toggleActive(event)) as { status: number };
		expect(res.status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
		expect(update).not.toHaveBeenCalled();
	});

	it('no-direct-patch: closing goes through fn_close_account, NEVER a PATCH', async () => {
		const { event, rpc, update } = makeEvent(CLOSE, { id: SESSION_UID }, '7');
		await actions.toggleActive(event);

		expect(update).not.toHaveBeenCalled();
		expect(rpc).toHaveBeenCalledTimes(1);
		expect(rpc.mock.calls[0][0]).toBe('fn_close_account');
	});

	it('close call-shape: account id + reason only — no client clock is sent', async () => {
		const { event, rpc } = makeEvent(CLOSE, { id: SESSION_UID }, '7');
		await actions.toggleActive(event);

		const args = rpc.mock.calls[0][1];
		expect(args).toEqual({ p_account_id: 7, p_reason_code: 'no_longer_used' });
		// p_closed_at is deliberately ABSENT so the RPC defaults it to server now(). Sending a
		// client clock lets a machine a minute fast trip the gate's own future-date bound.
		expect(args).not.toHaveProperty('p_closed_at');
	});

	it('reopen goes through fn_reopen_account and carries no reason', async () => {
		const { event, rpc, update } = makeEvent(REOPEN, { id: SESSION_UID }, '7');
		await actions.toggleActive(event);

		expect(update).not.toHaveBeenCalled();
		expect(rpc).toHaveBeenCalledWith('fn_reopen_account', { p_account_id: 7 });
	});

	it('closing without a reason is rejected before any DB call', async () => {
		// reason_code is MANDATORY on the into-closed transition and has no other carrier.
		// Catching it here keeps the gate's raise as a backstop rather than the primary UX.
		const { event, rpc } = makeEvent({ is_active: 'false' }, { id: SESSION_UID }, '7');
		const res = (await actions.toggleActive(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('an out-of-vocabulary reason is rejected before any DB call', async () => {
		const { event, rpc } = makeEvent(
			{ is_active: 'false', reason_code: 'not-a-reason' },
			{ id: SESSION_UID },
			'7'
		);
		const res = (await actions.toggleActive(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(rpc).not.toHaveBeenCalled();
	});

	// ADR-042 Decision 1: the refusal must NAME why, so the user learns the account holds
	// value rather than that "something went wrong". Each leg maps to distinct copy — a single
	// generic message would make the four legs indistinguishable to the person who has to act.
	const legs: Array<[string, string, string]> = [
		[
			'holdings',
			'account closure blocked: account 7 holds non-zero positions as of 2026-06-30 (leg 1 of 3: holdings)',
			'still holds positions'
		],
		[
			'cash',
			'account closure blocked: account 7 holds a non-zero cash balance (500 native) as of 2026-06-30 (leg 2 of 3: cash)',
			'still holds a cash balance'
		],
		[
			'post-activity',
			'account closure blocked: account 7 has activity dated after 2026-06-30 (leg 3 of 3: post-closure activity)',
			'activity dated after'
		],
		[
			'future-dated',
			'account closure blocked: account 7 has a future closed_at (2027-01-01) — the bound is one-sided, not-in-the-future',
			'future date'
		]
	];

	for (const [name, raw, expected] of legs) {
		it(`gate refusal names the leg that fired: ${name}`, async () => {
			const { event } = makeEvent(CLOSE, { id: SESSION_UID }, '7', { message: raw });
			const res = (await actions.toggleActive(event)) as {
				status: number;
				data: { errors: { _form: string[] } };
			};
			expect(res.status).toBe(422);
			expect(res.data.errors._form[0]).toContain(expected);
		});
	}

	it('gate messages are not leaked verbatim — no account ids or raw amounts reach the user', async () => {
		const { event } = makeEvent(CLOSE, { id: SESSION_UID }, '7', {
			message:
				'account closure blocked: account 7 holds a non-zero cash balance (500 native) as of 2026-06-30 (leg 2 of 3: cash)'
		});
		const res = (await actions.toggleActive(event)) as {
			data: { errors: { _form: string[] } };
		};
		const shown = res.data.errors._form[0];
		expect(shown).not.toContain('leg 2 of 3');
		expect(shown).not.toContain('500 native');
	});

	// Architect's catch: the RPCs refuse with their OWN prefix, not the gate's, so before this
	// mapping a double-submit fell through to "This account cannot be closed yet — it still
	// holds value." Telling someone their already-closed account still holds value is worse
	// than saying nothing, and it is the case a user is most likely to actually hit.
	it('an already-closed account reads as already-closed, not as blocked', async () => {
		const { event } = makeEvent(CLOSE, { id: SESSION_UID }, '7', {
			message:
				'close refused: no OPEN account 7 is reachable in this session — it does not exist, is not yours, or is already closed. Reopen it first if you meant to re-date it.'
		});
		const res = (await actions.toggleActive(event)) as {
			status: number;
			data: { errors: { _form: string[] } };
		};
		expect(res.status).toBe(409);
		expect(res.data.errors._form[0]).toBe('This account is already closed.');
		expect(res.data.errors._form[0]).not.toContain('holds value');
	});

	it('an already-open account reads as already-open on reopen', async () => {
		const { event } = makeEvent(REOPEN, { id: SESSION_UID }, '7', {
			message:
				'reopen refused: no CLOSED account 7 is reachable in this session — it does not exist, is not yours, or is already open.'
		});
		const res = (await actions.toggleActive(event)) as {
			status: number;
			data: { errors: { _form: string[] } };
		};
		expect(res.status).toBe(409);
		expect(res.data.errors._form[0]).toBe('This account is already open.');
	});

	it('the RPC refusal does not leak the interpolated account id', async () => {
		const { event } = makeEvent(CLOSE, { id: SESSION_UID }, '7', {
			message: 'close refused: no OPEN account 7 is reachable in this session — it is already closed.'
		});
		const res = (await actions.toggleActive(event)) as {
			data: { errors: { _form: string[] } };
		};
		expect(res.data.errors._form[0]).not.toMatch(/\b7\b/);
	});

	it('a non-gate DB error falls back to the generic envelope', async () => {
		const { event } = makeEvent(CLOSE, { id: SESSION_UID }, '7', {
			message: 'could not serialize access due to concurrent update'
		});
		const res = (await actions.toggleActive(event)) as {
			status: number;
			data: { errors: { _form: string[] } };
		};
		expect(res.status).toBe(422);
		expect(res.data.errors._form[0]).toBe('Could not update the account.');
	});
});
