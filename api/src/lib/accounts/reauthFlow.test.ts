// reauthFlow.test.ts — SELF-207 Phase-2 re-auth relay legs. DOM-free; drives a mocked relay
// via the injected fetch. Pins the mass-assignment fences (only allowed keys leave the browser),
// the discriminated start handoff, the setup_token present/absent rule on complete, and the
// status → failure-kind mapping.

import { describe, it, expect, vi } from 'vitest';
import { startReauth, completeReauth, ReauthError, type FetchLike } from './reauthFlow';

function jsonFetch(body: unknown, status = 200): FetchLike {
	return (async () =>
		new Response(JSON.stringify(body), {
			status,
			headers: { 'content-type': 'application/json' }
		})) as unknown as FetchLike;
}

describe('startReauth', () => {
	it('sends ONLY { linked_source_id } — no provider, no tenant id (mass-assignment fence)', async () => {
		const spy: FetchLike = vi.fn<FetchLike>(async () =>
			new Response(JSON.stringify({ kind: 'link_update', link_token: 'lt-1' }), {
				status: 200,
				headers: { 'content-type': 'application/json' }
			})
		);
		await startReauth('42', spy);
		const init = (spy as ReturnType<typeof vi.fn<FetchLike>>).mock.calls[0]?.[1];
		const sentBody = JSON.parse(String(init?.body ?? ''));
		expect(Object.keys(sentBody)).toEqual(['linked_source_id']);
		expect(sentBody.linked_source_id).toBe('42');
		expect(sentBody).not.toHaveProperty('provider');
		expect(sentBody).not.toHaveProperty('users_id');
	});

	it('returns the Plaid link_update handoff on 200', async () => {
		const out = await startReauth('42', jsonFetch({ kind: 'link_update', link_token: 'lt-xyz' }));
		expect(out.kind).toBe('link_update');
		if (out.kind === 'link_update') expect(out.link_token).toBe('lt-xyz');
	});

	it('returns the SimpleFIN recollect_credential handoff on 200', async () => {
		const out = await startReauth('42', jsonFetch({ kind: 'recollect_credential' }));
		expect(out.kind).toBe('recollect_credential');
	});

	it('maps relay statuses → failure kinds', async () => {
		const cases: Array<[number, string]> = [
			[401, 'unauthenticated'],
			[400, 'invalid_request'],
			[404, 'not_found'],
			[500, 'reauth_failed']
		];
		for (const [status, failure] of cases) {
			await expect(startReauth('42', jsonFetch({ error: 'x' }, status))).rejects.toMatchObject({
				leg: 'start',
				failure,
				status
			});
		}
	});

	it('throws malformed on an unknown discriminant / bad body', async () => {
		await expect(startReauth('42', jsonFetch({ kind: 'nope' }))).rejects.toMatchObject({
			leg: 'start',
			failure: 'malformed'
		});
	});

	it('throws network when fetch itself rejects', async () => {
		const dead = (vi.fn(async () => {
			throw new TypeError('offline');
		}) as unknown) as FetchLike;
		await expect(startReauth('42', dead)).rejects.toBeInstanceOf(ReauthError);
		await expect(startReauth('42', dead)).rejects.toMatchObject({ leg: 'start', failure: 'network' });
	});
});

describe('completeReauth', () => {
	it('Plaid path: sends { linked_source_id } only — setup_token omitted when absent', async () => {
		const spy: FetchLike = vi.fn<FetchLike>(async () =>
			new Response(JSON.stringify({ connection_status: 'healthy', rotated: false }), {
				status: 200,
				headers: { 'content-type': 'application/json' }
			})
		);
		await completeReauth('42', undefined, spy);
		const init = (spy as ReturnType<typeof vi.fn<FetchLike>>).mock.calls[0]?.[1];
		const sentBody = JSON.parse(String(init?.body ?? ''));
		expect(Object.keys(sentBody)).toEqual(['linked_source_id']);
		expect(sentBody).not.toHaveProperty('setup_token');
	});

	it('SimpleFIN path: includes setup_token when provided', async () => {
		const spy: FetchLike = vi.fn<FetchLike>(async () =>
			new Response(JSON.stringify({ connection_status: 'healthy', rotated: true }), {
				status: 200,
				headers: { 'content-type': 'application/json' }
			})
		);
		await completeReauth('42', 'fresh-setup-token', spy);
		const init = (spy as ReturnType<typeof vi.fn<FetchLike>>).mock.calls[0]?.[1];
		const sentBody = JSON.parse(String(init?.body ?? ''));
		expect(Object.keys(sentBody).sort()).toEqual(['linked_source_id', 'setup_token']);
		expect(sentBody.setup_token).toBe('fresh-setup-token');
	});

	it('returns { connection_status, rotated } on 200', async () => {
		const out = await completeReauth('42', undefined, jsonFetch({ connection_status: 'healthy', rotated: false }));
		expect(out.connection_status).toBe('healthy');
		expect(out.rotated).toBe(false);
	});

	it('maps the SimpleFIN ②-held 500 → reauth_failed on the complete leg', async () => {
		await expect(
			completeReauth('42', 'tok', jsonFetch({ error: 'reauth_failed' }, 500))
		).rejects.toMatchObject({ leg: 'complete', failure: 'reauth_failed', status: 500 });
	});

	it('maps 400 (e.g. missing setup_token server-side) → invalid_request', async () => {
		await expect(
			completeReauth('42', undefined, jsonFetch({ error: 'invalid_request' }, 400))
		).rejects.toMatchObject({ leg: 'complete', failure: 'invalid_request' });
	});
});
