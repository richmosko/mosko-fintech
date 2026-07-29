// attributes.server.test.ts — SELF-199 §2.4.1.d persist-action integration tests.
//
// Locks the body-parse → RPC-arg mapping → error-envelope behavior of the default form
// action: the hidden `payload` JSON is parsed + .strict()-validated; each carried AccountRef
// `account_id` is renamed to `provider_account_id` for the 042 p_accounts element;
// linked_source_id is coerced to a number for the bigint param; unauth/malformed/invalid
// fail closed; the cross-tenant #6-fence error maps to 403. The DB behavior of
// fn_land_linked_accounts itself is proven by the capability smoke + QA's pgTAP battery;
// here we mock the RPC to assert the action's contract with it.

import { describe, it, expect, vi, type Mock } from 'vitest';

// Mock the step-up helper: default 'allow' (aal2 session) so the persist-path tests exercise
// the RPC boundary; the dedicated step-up test overrides it to 'step-up-required' per-call.
vi.mock('$lib/server/auth/mfa', () => ({ requireStepUp: vi.fn(async () => 'allow') }));

import { actions } from './+page.server';
import { requireStepUp } from '$lib/server/auth/mfa';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

const VALID_ENVELOPE = {
	linked_source_id: '42',
	accounts: [
		{ account_id: 'acct_A', name: 'Checking', scope: 'personal', tax_treatment: 'taxable', account_type: 'depository' },
		{ account_id: 'acct_B', name: 'Roth', scope: 'personal', tax_treatment: 'tax_free', account_type: 'retirement' }
	]
};

/** Build an action event whose form carries a single `payload` field (= raw string). */
function makeEvent(
	payload: string,
	user: { id: string } | null,
	// Loose `Mock` type so both the success default ({ error: null }) and the error-case
	// mocks ({ error: { message } }) conform (vitest's Mock<T> is invariant on T).
	rpc: Mock = vi.fn(async () => ({ error: null }))
) {
	const request = new Request('http://localhost/accounts/connect/attributes', {
		method: 'POST',
		body: new URLSearchParams({ payload })
	});
	const locals = {
		safeGetSession: async () => ({ session: user ? {} : null, user }),
		supabase: { schema: () => ({ rpc }) }
	};
	const url = new URL('http://localhost/accounts/connect/attributes');
	const event = { request, locals, url } as unknown as Parameters<typeof actions.default>[0];
	return { event, rpc };
}

/** Run the action; normalize a thrown redirect into an inspectable object. */
async function run(event: Parameters<typeof actions.default>[0]) {
	try {
		return { kind: 'return' as const, value: await actions.default(event) };
	} catch (e) {
		return { kind: 'throw' as const, value: e as { status?: number; location?: string } };
	}
}

describe('POST /accounts/connect/attributes (persist action)', () => {
	it('unauthenticated → 401, RPC never called', async () => {
		const { event, rpc } = makeEvent(JSON.stringify(VALID_ENVELOPE), null);
		const res = await run(event);
		expect(res.kind).toBe('return');
		expect((res.value as { status: number }).status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('step-up-required session → redirects to /mfa/step-up, RPC never called', async () => {
		vi.mocked(requireStepUp).mockResolvedValueOnce('step-up-required');
		const { event, rpc } = makeEvent(JSON.stringify(VALID_ENVELOPE), { id: SESSION_UID });
		const res = await run(event);
		expect(res.kind).toBe('throw'); // redirect throws
		if (res.kind !== 'throw') throw new Error('expected a redirect');
		expect(res.value.status).toBe(303);
		expect(res.value.location).toBe('/mfa/step-up?redirectTo=%2Faccounts%2Fconnect%2Fattributes');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('valid payload → RPC gets numeric linked_source_id + account_id→provider_account_id mapping; success redirects to /accounts', async () => {
		const { event, rpc } = makeEvent(JSON.stringify(VALID_ENVELOPE), { id: SESSION_UID });
		const res = await run(event);

		expect(rpc).toHaveBeenCalledTimes(1);
		const [fn, args] = rpc.mock.calls[0] as unknown as [string, Record<string, unknown>];
		expect(fn).toBe('fn_land_linked_accounts');
		expect(args.p_linked_source_id).toBe(42); // numeric, not the "42" string
		expect(args.p_accounts).toEqual([
			{ provider_account_id: 'acct_A', name: 'Checking', scope: 'personal', tax_treatment: 'taxable', account_type: 'depository' },
			{ provider_account_id: 'acct_B', name: 'Roth', scope: 'personal', tax_treatment: 'tax_free', account_type: 'retirement' }
		]);

		expect(res.kind).toBe('throw'); // redirect throws
		if (res.kind !== 'throw') throw new Error('expected a redirect');
		expect(res.value.status).toBe(303);
		expect(res.value.location).toBe('/accounts');
	});

	it('malformed payload JSON → 400, RPC never called', async () => {
		const { event, rpc } = makeEvent('{not json', { id: SESSION_UID });
		const res = await run(event);
		expect((res.value as { status: number }).status).toBe(400);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('schema-invalid (empty accounts) → 400, RPC never called', async () => {
		const { event, rpc } = makeEvent(JSON.stringify({ linked_source_id: '42', accounts: [] }), { id: SESSION_UID });
		const res = await run(event);
		expect((res.value as { status: number }).status).toBe(400);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('mass-assignment: extra per-account key rejected by .strict() → 400', async () => {
		const tampered = {
			linked_source_id: '42',
			accounts: [{ ...VALID_ENVELOPE.accounts[0], users_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' }]
		};
		const { event, rpc } = makeEvent(JSON.stringify(tampered), { id: SESSION_UID });
		const res = await run(event);
		expect((res.value as { status: number }).status).toBe(400);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('cross-tenant #6-fence RPC error → 403 (distinct message)', async () => {
		const rpc = vi.fn(async () => ({
			error: { message: 'cross-tenant linked_source rejected … matched-tenant fence' }
		}));
		const { event } = makeEvent(JSON.stringify(VALID_ENVELOPE), { id: SESSION_UID }, rpc);
		const res = await run(event);
		expect((res.value as { status: number }).status).toBe(403);
	});

	it('generic RPC error → 422', async () => {
		const rpc = vi.fn(async () => ({ error: { message: 'something else broke' } }));
		const { event } = makeEvent(JSON.stringify(VALID_ENVELOPE), { id: SESSION_UID }, rpc);
		const res = await run(event);
		expect((res.value as { status: number }).status).toBe(422);
	});
});
