// updateAttributes.server.test.ts — account-detail attribute-edit action.
// Locks auth-gate → account-id parse → .strict() body-parse (enums + name/scope rules) →
// single-row RLS-scoped UPDATE → error-envelope. RLS ownership is proven by QA's pgTAP battery;
// here the client is mocked to assert the action's contract (only the 4+1 attributes are written;
// mass-assignment + bad enums rejected).
//
// SELF-267 AC 2/2a/3: tax_jurisdiction extends this action (an ordinary UPDATE, not a new RPC).
// Additional legs below: schema-level '' / absent → null; happy set; the 23505 → 409 field-error
// mapping off pfin.account_tax_jurisdiction_uniq (102); provider-linked refusal (team-lead
// ruling E12 — app-layer only, no DB fence); and that clearing (null) never trips the
// provider-linked check (it only guards a NON-null designation).

import { describe, it, expect, vi } from 'vitest';
import { actions } from './+page.server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

const VALID = {
	name: 'Brokerage',
	account_type: 'investment',
	scope: 'personal',
	tax_treatment: 'taxable'
};

/**
 * `linkedSourceId` seeds the mocked account-detail SELECT the provider-linked check runs
 * (only reached when a NON-null tax_jurisdiction is posted). `undefined` means "no row" —
 * the RLS-scoped cross-tenant/absent-account case, which the check no-ops on.
 */
function makeEvent(
	fields: Record<string, string>,
	user: { id: string } | null,
	accountId = '7',
	updErr: { message: string; code?: string } | null = null,
	linkedSourceId: number | null | undefined = null
) {
	const eq = vi.fn(async () => ({ error: updErr }));
	const update = vi.fn(() => ({ eq }));
	const maybeSingle = vi.fn(async () => ({
		data: linkedSourceId === undefined ? null : { linked_source_id: linkedSourceId }
	}));
	const selectEq = vi.fn(() => ({ maybeSingle }));
	const select = vi.fn(() => ({ eq: selectEq }));
	const from = vi.fn(() => ({ update, select }));
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
	return { event, update, eq, select, maybeSingle };
}

describe('POST /accounts/[account_id]?/updateAttributes', () => {
	it('unauthenticated → 401, UPDATE never issued', async () => {
		const { event, update } = makeEvent(VALID, null);
		const res = (await actions.updateAttributes(event)) as { status: number };
		expect(res.status).toBe(401);
		expect(update).not.toHaveBeenCalled();
	});

	it('valid body, no tax_jurisdiction posted → UPDATE writes the 4 attributes + null (absent → clear)', async () => {
		const { event, update, eq } = makeEvent(VALID, { id: SESSION_UID }, '7');
		const res = (await actions.updateAttributes(event)) as { success: boolean };
		expect(update).toHaveBeenCalledWith({
			name: 'Brokerage',
			account_type: 'investment',
			scope: 'personal',
			tax_treatment: 'taxable',
			tax_jurisdiction: null
		});
		expect(eq).toHaveBeenCalledWith('account_id', 7);
		expect(res).toEqual({ success: true });
	});

	it("tax_jurisdiction posted '' → UPDATE writes null (explicit clear), no provider-linked check run", async () => {
		const { event, update, select } = makeEvent(
			{ ...VALID, tax_jurisdiction: '' },
			{ id: SESSION_UID }
		);
		const res = (await actions.updateAttributes(event)) as { success: boolean };
		expect(select).not.toHaveBeenCalled();
		expect(update).toHaveBeenCalledWith(
			expect.objectContaining({ tax_jurisdiction: null })
		);
		expect(res).toEqual({ success: true });
	});

	it("tax_jurisdiction posted 'irs' on a manual (non-linked) account → UPDATE writes 'irs'", async () => {
		const { event, update, select } = makeEvent(
			{ ...VALID, tax_jurisdiction: 'irs' },
			{ id: SESSION_UID },
			'7',
			null,
			null // linked_source_id null → manual account
		);
		const res = (await actions.updateAttributes(event)) as { success: boolean };
		expect(select).toHaveBeenCalled();
		expect(update).toHaveBeenCalledWith(
			expect.objectContaining({ tax_jurisdiction: 'irs' })
		);
		expect(res).toEqual({ success: true });
	});

	it('bad tax_jurisdiction value → 400, UPDATE never issued', async () => {
		const { event, update } = makeEvent(
			{ ...VALID, tax_jurisdiction: 'not_an_authority' },
			{ id: SESSION_UID }
		);
		const res = (await actions.updateAttributes(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(update).not.toHaveBeenCalled();
	});

	it('23505 on account_tax_jurisdiction_uniq → 409 field error on tax_jurisdiction, generic copy (no enum name)', async () => {
		const { event, update } = makeEvent(
			{ ...VALID, tax_jurisdiction: 'irs' },
			{ id: SESSION_UID },
			'7',
			{
				message: 'duplicate key value violates unique constraint "account_tax_jurisdiction_uniq"',
				code: '23505'
			},
			null
		);
		const res = (await actions.updateAttributes(event)) as {
			status: number;
			data: { errors: Record<string, string[]> };
		};
		expect(update).toHaveBeenCalled();
		expect(res.status).toBe(409);
		expect(res.data.errors.tax_jurisdiction[0]).not.toMatch(/irs|ftb/i);
		expect(res.data.errors.tax_jurisdiction[0]).toMatch(/tax authority/i);
	});

	it('a 23505 on some OTHER constraint is NOT misclassified as the tax_jurisdiction conflict', async () => {
		const { event } = makeEvent(
			{ ...VALID, tax_jurisdiction: 'irs' },
			{ id: SESSION_UID },
			'7',
			{ message: 'duplicate key value violates unique constraint "some_other_uniq"', code: '23505' },
			null
		);
		const res = (await actions.updateAttributes(event)) as { status: number };
		expect(res.status).toBe(422);
	});

	it('provider-linked account + non-null tax_jurisdiction → 422 field error, UPDATE never issued', async () => {
		const { event, update } = makeEvent(
			{ ...VALID, tax_jurisdiction: 'ftb' },
			{ id: SESSION_UID },
			'7',
			null,
			99 // linked_source_id set → provider-linked
		);
		const res = (await actions.updateAttributes(event)) as {
			status: number;
			data: { errors: Record<string, string[]> };
		};
		expect(res.status).toBe(422);
		expect(res.data.errors.tax_jurisdiction).toBeDefined();
		expect(update).not.toHaveBeenCalled();
	});

	it('provider-linked account + tax_jurisdiction cleared (absent) → no check run, UPDATE proceeds', async () => {
		const { event, update, select } = makeEvent(VALID, { id: SESSION_UID }, '7', null, 99);
		const res = (await actions.updateAttributes(event)) as { success: boolean };
		expect(select).not.toHaveBeenCalled();
		expect(update).toHaveBeenCalledWith(
			expect.objectContaining({ tax_jurisdiction: null })
		);
		expect(res).toEqual({ success: true });
	});

	it('cross-tenant/absent account + non-null tax_jurisdiction → link-check no-ops (no row), UPDATE still issued (RLS decides)', async () => {
		const { event, update, select } = makeEvent(
			{ ...VALID, tax_jurisdiction: 'irs' },
			{ id: SESSION_UID },
			'7',
			null,
			undefined // no row returned by the SELECT
		);
		const res = (await actions.updateAttributes(event)) as { success: boolean };
		expect(select).toHaveBeenCalled();
		expect(update).toHaveBeenCalled();
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

	it('mass-assignment: closed_at / linked_source_id posted → rejected by .strict() → 400', async () => {
		// closed_at replaces is_active as the interesting mass-assignment target at 059: it is the
		// column the close gate governs, and 003's TABLE-LEVEL update grant means the DB would
		// accept it from this path if `.strict()` did not reject it first. (058's gate is the real
		// boundary; this is the app-layer fence in front of it.) `is_active` is deliberately NOT
		// asserted here any more — a dropped column is rejected by every layer trivially, so
		// testing it would prove nothing while reading like coverage.
		const { event, update } = makeEvent(
			{ ...VALID, closed_at: '2026-06-03T10:00:00Z', linked_source_id: '99' },
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

	it('UPDATE error (non-23505) → 422', async () => {
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { event } = makeEvent(VALID, { id: SESSION_UID }, '7', { message: 'db broke' });
		const res = (await actions.updateAttributes(event)) as { status: number };
		expect(res.status).toBe(422);
		spy.mockRestore();
	});
});
