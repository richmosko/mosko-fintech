// classifyFlow.test.ts — SELF-249 per-row Sub-Cat picker write path. DOM-free; drives a mocked
// relay via the injected fetch. Mirrors accounts/syncFlow.test.ts's shape: mass-assignment fence,
// success parse, status/code → failure-code mapping, and network/malformed.

import { describe, it, expect, vi } from 'vitest';
import { classifyTrans, ClassifyError, type FetchLike } from './classifyFlow';

function jsonFetch(body: unknown, status = 200): FetchLike {
	return (async () =>
		new Response(JSON.stringify(body), {
			status,
			headers: { 'content-type': 'application/json' }
		})) as unknown as FetchLike;
}

describe('classifyTrans', () => {
	it('POSTs ONLY { sub_cat_id } to the trans_id-scoped route (mass-assignment fence)', async () => {
		const spy: FetchLike = vi.fn<FetchLike>(async () =>
			new Response(JSON.stringify({ ok: true, trans_id: 501, sub_cat_id: 7 }), {
				status: 200,
				headers: { 'content-type': 'application/json' }
			})
		);
		await classifyTrans(501, 7, spy);
		const call = (spy as ReturnType<typeof vi.fn<FetchLike>>).mock.calls[0];
		expect(call?.[0]).toBe('/api/transactions/501/classify');
		const sentBody = JSON.parse(String((call?.[1] as RequestInit)?.body ?? ''));
		expect(Object.keys(sentBody)).toEqual(['sub_cat_id']);
		expect(sentBody.sub_cat_id).toBe(7);
		expect(sentBody).not.toHaveProperty('trans_id');
		expect(sentBody).not.toHaveProperty('users_id');
	});

	it('resolves { trans_id, sub_cat_id } on success', async () => {
		const out = await classifyTrans(501, 7, jsonFetch({ ok: true, trans_id: 501, sub_cat_id: 7 }));
		expect(out).toEqual({ trans_id: 501, sub_cat_id: 7 });
	});

	it('rejects a non-positive-integer sub_cat_id before any network call (client mirror)', async () => {
		const spy = vi.fn<FetchLike>();
		await expect(classifyTrans(501, 0, spy as unknown as FetchLike)).rejects.toThrow();
		await expect(classifyTrans(501, -3, spy as unknown as FetchLike)).rejects.toThrow();
		expect(spy).not.toHaveBeenCalled();
	});

	it('maps each server-typed refusal code through verbatim, regardless of HTTP status', async () => {
		const cases: Array<[string, number]> = [
			['not_standard', 409],
			['has_security', 409],
			['split_parent', 409],
			['is_reversal', 409],
			['journaled', 409],
			['journaled_cat_conflict', 409],
			['trade_constraint', 409], // Sec PR #564 FLAG-B follow-up
			['invalid_sub_cat_id', 400]
		];
		for (const [code, status] of cases) {
			await expect(
				classifyTrans(501, 7, jsonFetch({ error: 'x', code }, status))
			).rejects.toMatchObject({ code, status });
		}
	});

	it('maps a 404 with no body code to not_found', async () => {
		await expect(classifyTrans(999, 7, jsonFetch({ error: 'Transaction not found.' }, 404))).rejects.toMatchObject({
			code: 'not_found',
			status: 404
		});
	});

	it('maps a 401 with no body code to unauthenticated', async () => {
		await expect(classifyTrans(501, 7, jsonFetch({ error: 'unauthenticated' }, 401))).rejects.toMatchObject({
			code: 'unauthenticated',
			status: 401
		});
	});

	it('falls back to server_error for an unrecognized code / bare 500', async () => {
		await expect(classifyTrans(501, 7, jsonFetch({ error: 'boom' }, 500))).rejects.toMatchObject({
			code: 'server_error',
			status: 500
		});
		await expect(classifyTrans(501, 7, jsonFetch({ error: 'boom', code: 'not_a_real_code' }, 500))).rejects.toMatchObject(
			{ code: 'server_error', status: 500 }
		);
	});

	it('throws network when fetch itself rejects', async () => {
		const dead = vi.fn(async () => {
			throw new TypeError('offline');
		}) as unknown as FetchLike;
		await expect(classifyTrans(501, 7, dead)).rejects.toBeInstanceOf(ClassifyError);
		await expect(classifyTrans(501, 7, dead)).rejects.toMatchObject({ code: 'network' });
	});

	it('throws malformed on an unparseable success body', async () => {
		const badJson: FetchLike = (async () =>
			new Response('not json', { status: 200, headers: { 'content-type': 'application/json' } })) as unknown as FetchLike;
		await expect(classifyTrans(501, 7, badJson)).rejects.toMatchObject({ code: 'malformed', status: 200 });
	});
});
