// closeControl.server.test.ts — the account CLOSE control (ADR-042 Decision 1).
//
// The action is still named `toggleActive` and still posts `is_active` (the rename rides with
// the §7.9 application-layer landing), but what it WRITES is closed_at. These assertions exist
// because that write had NO test coverage at all while it wrote is_active, and the conversion
// added branching refusal logic on top of it.
//
// THE LOAD-BEARING ONE IS `write-shape`: a regression to `{ is_active: ... }` would leave
// closed_at untouched, and 058's ONE-DIRECTIONAL sync (closed_at -> is_active, never the
// reverse) means the account_closure_biconditional CHECK rejects it at the database. Asserting
// the payload here catches that at unit speed instead of as an opaque 400 from PostgREST.
//
// RLS ownership + the gate's own legs are proven by QA's pgTAP battery
// (058_account_closure_fences.sql); the client is mocked here to lock the action's contract.

import { describe, it, expect, vi } from 'vitest';
import { actions } from './+page.server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

function makeEvent(
	fields: Record<string, string>,
	user: { id: string } | null,
	accountId = '7',
	updErr: { message: string } | null = null
) {
	const eq = vi.fn(async () => ({ error: updErr }));
	// Typed payload param: without it `update.mock.calls[0]` is the empty tuple and the
	// write-shape assertion below cannot index it.
	const update = vi.fn((_payload: Record<string, unknown>) => ({ eq }));
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
	} as unknown as Parameters<typeof actions.toggleActive>[0];
	return { event, update, eq };
}

describe('POST /accounts/[account_id]?/toggleActive — the close control', () => {
	it('unauthenticated → 401, UPDATE never issued', async () => {
		const { event, update } = makeEvent({ is_active: 'false' }, null);
		const res = (await actions.toggleActive(event)) as { status: number };
		expect(res.status).toBe(401);
		expect(update).not.toHaveBeenCalled();
	});

	it('write-shape: closing writes closed_at, and NEVER is_active', async () => {
		const { event, update, eq } = makeEvent({ is_active: 'false' }, { id: SESSION_UID }, '7');
		await actions.toggleActive(event);

		expect(update).toHaveBeenCalledTimes(1);
		const payload = update.mock.calls[0][0] as Record<string, unknown>;
		expect(Object.keys(payload)).toEqual(['closed_at']);
		expect(typeof payload.closed_at).toBe('string');
		expect(Number.isNaN(Date.parse(payload.closed_at as string))).toBe(false);
		expect(eq).toHaveBeenCalledWith('account_id', 7);
	});

	it('write-shape: reopening clears closed_at to null, and NEVER is_active', async () => {
		const { event, update } = makeEvent({ is_active: 'true' }, { id: SESSION_UID }, '7');
		await actions.toggleActive(event);
		expect(update).toHaveBeenCalledWith({ closed_at: null });
	});

	// ADR-042 Decision 1: the refusal must NAME why, so the user learns the account holds
	// value rather than that "something went wrong". Each leg maps to distinct copy — a single
	// generic message would make the four legs indistinguishable to the person who has to act.
	const legs: Array<[string, string, string]> = [
		['holdings', 'account closure blocked: account 7 holds non-zero positions as of 2026-06-30 (leg 1 of 3: holdings)', 'still holds positions'],
		['cash', 'account closure blocked: account 7 holds a non-zero cash balance (500 native) as of 2026-06-30 (leg 2 of 3: cash)', 'still holds a cash balance'],
		['post-activity', 'account closure blocked: account 7 has activity dated after 2026-06-30 (leg 3 of 3: post-closure activity)', 'activity dated after'],
		['future-dated', 'account closure blocked: account 7 has a future closed_at (2027-01-01) — the bound is one-sided, not-in-the-future', 'future date']
	];

	for (const [name, raw, expected] of legs) {
		it(`gate refusal names the leg that fired: ${name}`, async () => {
			const { event } = makeEvent({ is_active: 'false' }, { id: SESSION_UID }, '7', {
				message: raw
			});
			const res = (await actions.toggleActive(event)) as {
				status: number;
				data: { errors: { _form: string[] } };
			};
			expect(res.status).toBe(422);
			expect(res.data.errors._form[0]).toContain(expected);
		});
	}

	it('gate messages are not leaked verbatim — no account ids or raw amounts reach the user', async () => {
		const { event } = makeEvent({ is_active: 'false' }, { id: SESSION_UID }, '7', {
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

	it('a non-gate DB error falls back to the generic envelope', async () => {
		const { event } = makeEvent({ is_active: 'false' }, { id: SESSION_UID }, '7', {
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
