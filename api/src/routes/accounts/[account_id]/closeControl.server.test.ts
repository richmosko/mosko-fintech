// closeControl.server.test.ts — the account CLOSE / REOPEN control
// (ADR-042 Decision 1; the INVOKER RPC pair per Amendment 2).
//
// TWO ACTIONS as of 059 (§7.9 application-layer landing). `toggleActive`, which posted an
// `is_active` boolean, is SPLIT into `closeAccount` + `reopenAccount` rather than RENAMED — a
// toggle models closure as a flag with two values, and ADR-042 ruled it a dated TRANSITION whose
// two directions carry different payloads. The split is what lets `reason_code` be plainly
// REQUIRED on close and ABSENT on reopen instead of a cross-field `.refine()` over the flag, so
// `.strict()` alone is the fence. Renaming would have carried the wrong model forward.
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
const CLOSE = { reason_code: 'no_longer_used' };
const REOPEN = {};
// 058 §(7): fn_close_account RETURNS the closed_at it actually applied, SERVER-derived from
// now(). Nothing the client sent can produce this value — that is the point of asserting it.
const APPLIED_CLOSED_AT = '2026-08-04T11:22:33.456Z';

function makeEvent(
	fields: Record<string, string>,
	user: { id: string } | null,
	accountId = '7',
	rpcErr: { message: string; code?: string } | null = null,
	rpcData: string | null = APPLIED_CLOSED_AT
) {
	// Typed params: without them `rpc.mock.calls[0]` is the empty tuple and the call-shape
	// assertions below cannot index it.
	const rpc = vi.fn(async (_fn: string, _args: Record<string, unknown>) => ({
		data: rpcData,
		error: rpcErr
	}));
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
	} as unknown as Parameters<typeof actions.closeAccount>[0];
	return { event, rpc, update };
}

describe('POST /accounts/[account_id]?/closeAccount|reopenAccount — the close control', () => {
	it('unauthenticated → 401, nothing written', async () => {
		const { event, rpc, update } = makeEvent(CLOSE, null);
		const res = (await actions.closeAccount(event)) as { status: number };
		expect(res.status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
		expect(update).not.toHaveBeenCalled();
	});

	it('no-direct-patch: closing goes through fn_close_account, NEVER a PATCH', async () => {
		const { event, rpc, update } = makeEvent(CLOSE, { id: SESSION_UID }, '7');
		await actions.closeAccount(event);

		expect(update).not.toHaveBeenCalled();
		expect(rpc).toHaveBeenCalledTimes(1);
		expect(rpc.mock.calls[0][0]).toBe('fn_close_account');
	});

	it('close call-shape: account id + reason only — no client clock is sent', async () => {
		const { event, rpc } = makeEvent(CLOSE, { id: SESSION_UID }, '7');
		await actions.closeAccount(event);

		const args = rpc.mock.calls[0][1];
		expect(args).toEqual({ p_account_id: 7, p_reason_code: 'no_longer_used' });
		// p_closed_at is deliberately ABSENT so the RPC defaults it to server now(). Sending a
		// client clock lets a machine a minute fast trip the gate's own future-date bound.
		expect(args).not.toHaveProperty('p_closed_at');
	});

	it('reopen goes through fn_reopen_account and carries no reason', async () => {
		const { event, rpc, update } = makeEvent(REOPEN, { id: SESSION_UID }, '7');
		await actions.reopenAccount(event);

		expect(update).not.toHaveBeenCalled();
		expect(rpc).toHaveBeenCalledWith('fn_reopen_account', { p_account_id: 7 });
		// No p_effective_date: the reopen schema is empty-and-strict and the GUC is OPTIONAL by
		// design, so 058's writer records NULL = "not recorded" rather than a guessed current_date.
	});

	it('closing without a reason is rejected before any DB call', async () => {
		// reason_code is MANDATORY on the into-closed transition and has no other carrier.
		// Catching it here keeps the gate's raise as a backstop rather than the primary UX.
		// Post-split this is plain schema requiredness on closeAccountSchema, not a cross-field
		// refinement over a boolean — the empty post has nothing to satisfy it.
		const { event, rpc } = makeEvent({}, { id: SESSION_UID }, '7');
		const res = (await actions.closeAccount(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('an out-of-vocabulary reason is rejected before any DB call', async () => {
		const { event, rpc } = makeEvent(
			{ reason_code: 'not-a-reason' },
			{ id: SESSION_UID },
			'7'
		);
		const res = (await actions.closeAccount(event)) as { status: number };
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
			// Asserts the REMEDY, not the restatement. The old copy said "Close it as of a later
			// date" and this asserted "activity dated after" — a phrase that merely echoed the
			// raise back, so it would have passed against copy instructing a control the UI does
			// not have (which is exactly what it was passing against). The user-actionable half is
			// what the leg has to name.
			'dated in the future'
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
			const res = (await actions.closeAccount(event)) as {
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
		const res = (await actions.closeAccount(event)) as {
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
		const res = (await actions.closeAccount(event)) as {
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
		const res = (await actions.reopenAccount(event)) as {
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
		const res = (await actions.closeAccount(event)) as {
			data: { errors: { _form: string[] } };
		};
		expect(res.data.errors._form[0]).not.toMatch(/\b7\b/);
	});

	// ── Sec joint-review (PR #318, F8): the OPERATOR LOG must not carry the raise text ────────
	// 058's leg-2 raise interpolates a real account cash balance and every leg interpolates the
	// closing date. Logs are operator-only, so this is a redaction rather than a veto — but log
	// shipping/retention is an unscoped Phase-7 surface and this project redacts concrete money
	// even from committed artifacts. The operator keeps the SQLSTATE and the leg; not the amount.
	it('a blocked close logs the code and the leg — never the raise, never the amount', async () => {
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		try {
			const { event } = makeEvent(CLOSE, { id: SESSION_UID }, '7', {
				message:
					'account closure blocked: account 7 holds a non-zero cash balance (500 native) as of 2026-06-30 (leg 2 of 3: cash)',
				code: 'P0001'
			});
			await actions.closeAccount(event);

			expect(spy).toHaveBeenCalledTimes(1);
			const logged = spy.mock.calls[0].join(' ');
			expect(logged).toContain('code=P0001');
			expect(logged).toContain('gate:cash');
			// The three things that must never reach the log stream: the amount, the date, and the
			// raise verbatim. The account id is asserted too — it rides in the same string.
			expect(logged).not.toContain('500');
			expect(logged).not.toContain('2026-06-30');
			expect(logged).not.toContain('non-zero cash balance');
		} finally {
			spy.mockRestore();
		}
	});

	// 058's leg-2 CONTRACT-BREACH raise ("got no usable cash balance") also carries the
	// `leg 2 of 3: cash` marker, so a naive classifier folds it into the ordinary cash refusal and
	// the operator cannot tell "the user holds cash" (act on the account) from "056's contract is
	// broken" (act on 056). It gets its own LOG key — and deliberately the SAME user-facing copy,
	// because Sec ruled that mapping GREEN and this change alters no byte the user sees.
	it('the leg-2 contract breach logs distinctly but reads identically to the user', async () => {
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		try {
			const { event } = makeEvent(CLOSE, { id: SESSION_UID }, '7', {
				message:
					'account closure blocked: account 7 got no usable cash balance from fn_account_cash_as_of (row MISSING, value NULL) — that function is TOTAL over pfin.account and double-coalesces to non-NULL, so either result means its contract is broken (leg 2 of 3: cash)',
				code: 'P0001'
			});
			const res = (await actions.closeAccount(event)) as {
				status: number;
				data: { errors: { _form: string[] } };
			};
			expect(spy.mock.calls[0].join(' ')).toContain('gate:cash-contract');
			expect(res.status).toBe(422);
			expect(res.data.errors._form[0]).toBe(
				'This account still holds a cash balance. Move the funds out, then close it.'
			);
		} finally {
			spy.mockRestore();
		}
	});

	it('an RPC refusal logs its own key, not the interpolated account id', async () => {
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		try {
			const { event } = makeEvent(CLOSE, { id: SESSION_UID }, '7', {
				message:
					'close refused: no OPEN account 7 is reachable in this session — it does not exist, is not yours, or is already closed.',
				code: 'P0002'
			});
			await actions.closeAccount(event);
			const logged = spy.mock.calls[0].join(' ');
			expect(logged).toContain('code=P0002');
			expect(logged).toContain('rpc:already-closed');
			expect(logged).not.toContain('no OPEN account');
		} finally {
			spy.mockRestore();
		}
	});

	// ── Sec joint-review (PR #318, F8 note): return SERVER state, not the client's input ──────
	// 058 §(7) gives fn_close_account a return type for exactly one value: the applied closed_at,
	// derived from server now() because p_closed_at is deliberately not sent. Echoing the posted
	// is_active back reported what the client ASKED FOR and discarded that value.
	it('a successful close returns the SERVER-applied closed_at', async () => {
		const { event } = makeEvent(CLOSE, { id: SESSION_UID }, '7');
		const res = (await actions.closeAccount(event)) as Record<string, unknown>;

		expect(res).toEqual({ success: true, closed_at: APPLIED_CLOSED_AT });
		// The posted value is not echoed back — that was the defect, and it is the assertion that
		// would fail if someone re-added a client-echoed field alongside. `is_active` is named
		// explicitly because it is what USED to be here and is the thing a revert would restore.
		expect(res).not.toHaveProperty('is_active');
	});

	it('a successful reopen returns closed_at: null — the applied state, not a missing one', async () => {
		// fn_reopen_account RETURNS void (a reopen applies NULL); the asymmetry is the contract.
		const { event } = makeEvent(REOPEN, { id: SESSION_UID }, '7', null, null);
		const res = (await actions.reopenAccount(event)) as Record<string, unknown>;

		expect(res).toEqual({ success: true, closed_at: null });
	});

	it('a non-gate DB error falls back to the generic envelope', async () => {
		const { event } = makeEvent(CLOSE, { id: SESSION_UID }, '7', {
			message: 'could not serialize access due to concurrent update'
		});
		const res = (await actions.closeAccount(event)) as {
			status: number;
			data: { errors: { _form: string[] } };
		};
		expect(res.status).toBe(422);
		expect(res.data.errors._form[0]).toBe('Could not update the account.');
	});
});
