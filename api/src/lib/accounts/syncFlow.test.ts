// syncFlow.test.ts — SELF-317 manual "Sync now" relay leg. DOM-free; drives a mocked relay via
// the injected fetch. Pins the mass-assignment fence (only source_id leaves the browser, omitted
// for sync-all), the 202 disposition parse, the status → failure-kind mapping, and network/malformed.

import { describe, it, expect, vi } from 'vitest';
import { requestSync, SyncError, type FetchLike } from './syncFlow';

function jsonFetch(body: unknown, status = 202): FetchLike {
	return (async () =>
		new Response(JSON.stringify(body), {
			status,
			headers: { 'content-type': 'application/json' }
		})) as unknown as FetchLike;
}

const ACCEPTED = { status: 'accepted', sources: [{ source_id: '42', disposition: 'triggered' }] };

describe('requestSync', () => {
	it('per-source: sends ONLY { source_id } — no provider, no tenant id (mass-assignment fence)', async () => {
		const spy: FetchLike = vi.fn<FetchLike>(async () =>
			new Response(JSON.stringify(ACCEPTED), {
				status: 202,
				headers: { 'content-type': 'application/json' }
			})
		);
		await requestSync('42', spy);
		const init = (spy as ReturnType<typeof vi.fn<FetchLike>>).mock.calls[0]?.[1];
		const sentBody = JSON.parse(String(init?.body ?? ''));
		expect(Object.keys(sentBody)).toEqual(['source_id']);
		expect(sentBody.source_id).toBe('42');
		expect(sentBody).not.toHaveProperty('provider');
		expect(sentBody).not.toHaveProperty('users_id');
		expect(sentBody).not.toHaveProperty('ownerUserId');
	});

	it('sync-all: omits source_id entirely when absent (no empty string on the wire)', async () => {
		const spy: FetchLike = vi.fn<FetchLike>(async () =>
			new Response(JSON.stringify({ status: 'accepted', sources: [] }), {
				status: 202,
				headers: { 'content-type': 'application/json' }
			})
		);
		await requestSync(undefined, spy);
		const init = (spy as ReturnType<typeof vi.fn<FetchLike>>).mock.calls[0]?.[1];
		const sentBody = JSON.parse(String(init?.body ?? ''));
		expect(Object.keys(sentBody)).toEqual([]);
		expect(sentBody).not.toHaveProperty('source_id');
	});

	it('returns the parsed 202 disposition body on accept', async () => {
		const out = await requestSync('42', jsonFetch(ACCEPTED));
		expect(out.status).toBe('accepted');
		expect(out.sources[0]).toEqual({ source_id: '42', disposition: 'triggered' });
	});

	it('parses the debounced disposition', async () => {
		const out = await requestSync(
			'42',
			jsonFetch({ status: 'accepted', sources: [{ source_id: '42', disposition: 'debounced' }] })
		);
		expect(out.sources[0]?.disposition).toBe('debounced');
	});

	it('maps relay statuses → failure kinds', async () => {
		const cases: Array<[number, string]> = [
			[401, 'unauthenticated'],
			[400, 'invalid_request'],
			[404, 'not_found'],
			[502, 'unavailable'],
			[500, 'sync_failed']
		];
		for (const [status, failure] of cases) {
			await expect(requestSync('42', jsonFetch({ error: 'x' }, status))).rejects.toMatchObject({
				failure,
				status
			});
		}
	});

	it('throws malformed on an unparseable / bad-shape 202 body', async () => {
		await expect(
			requestSync('42', jsonFetch({ status: 'accepted', sources: [{ disposition: 'nope' }] }))
		).rejects.toMatchObject({ failure: 'malformed' });
	});

	it('throws network when fetch itself rejects', async () => {
		const dead = (vi.fn(async () => {
			throw new TypeError('offline');
		}) as unknown) as FetchLike;
		await expect(requestSync('42', dead)).rejects.toBeInstanceOf(SyncError);
		await expect(requestSync('42', dead)).rejects.toMatchObject({ failure: 'network' });
	});
});
