// syncFlow.ts — pure, dependency-injected core for the SELF-317 manual "Sync now" relay.
//
// Framework-free + unit-testable (like reauthFlow / plaidLinkFlow): one async function that
// POSTs to /api/sync and validates the 202 body against sync-contract.ts. `fetchFn` is injectable
// so tests drive a mocked relay (no network, no DOM). The DOM/timer parts (60s disable, freshness
// poll) live in the SyncNowControl component.
//
// FENCE: the outgoing body runs through the `.strict()` request schema before send — a
// belt-and-braces proof the browser transmits ONLY `source_id` (no provider, no tenant id, no
// secret). `users_id` is derived server-side from the session and never exists in this module.

import {
	SYNC_ROUTE,
	syncRequestSchema,
	syncResponseSchema,
	type SyncResponse
} from './sync-contract';

export type FetchLike = typeof fetch;

/** Actionable failure category, mapped from the relay HTTP status (Backend's error envelope):
 *  401 unauthenticated · 400 invalid_request · 404 not_found · 502 unavailable ·
 *  other-non-2xx sync_failed · fetch-threw network · unparseable body malformed. */
export type SyncFailureKind =
	| 'unauthenticated'
	| 'invalid_request'
	| 'not_found'
	| 'unavailable'
	| 'sync_failed'
	| 'network'
	| 'malformed';

export class SyncError extends Error {
	readonly failure: SyncFailureKind;
	readonly status: number | null;
	constructor(failure: SyncFailureKind, status: number | null = null) {
		super(`Sync failed (${failure}${status != null ? ` ${status}` : ''})`);
		this.name = 'SyncError';
		this.failure = failure;
		this.status = status;
	}
}

/** Map a relay HTTP status → an actionable failure category. */
function classify(status: number): SyncFailureKind {
	if (status === 401) return 'unauthenticated';
	if (status === 400) return 'invalid_request';
	if (status === 404) return 'not_found';
	if (status === 502) return 'unavailable'; // worker unreachable / worker 5xx
	return 'sync_failed';
}

/**
 * Trigger a manual sync. `sourceId` PRESENT ⇒ sync that one connection; ABSENT ⇒ "sync all my
 * active sources". Resolves to the 202 body (`{ status:'accepted', sources:[{source_id,
 * disposition}] }`) or throws `SyncError`. "accepted" ≠ "succeeded" — the caller then polls the
 * 040/043 sync-state views (via loader invalidation) for the real, post-sync freshness.
 */
export async function requestSync(
	sourceId?: string,
	fetchFn: FetchLike = fetch
): Promise<SyncResponse> {
	// Mass-assignment fence: only `source_id` may leave the browser, and only when present —
	// omit it entirely for the sync-all case so the optional mirror is satisfied (no empty string).
	const body = syncRequestSchema.parse(sourceId !== undefined ? { source_id: sourceId } : {});

	let res: Response;
	try {
		res = await fetchFn(SYNC_ROUTE, {
			method: 'POST',
			headers: { 'content-type': 'application/json', accept: 'application/json' },
			body: JSON.stringify(body)
		});
	} catch {
		throw new SyncError('network');
	}
	if (!res.ok) throw new SyncError(classify(res.status), res.status);

	let json: unknown;
	try {
		json = await res.json();
	} catch {
		throw new SyncError('malformed', res.status);
	}
	const parsed = syncResponseSchema.safeParse(json);
	if (!parsed.success) throw new SyncError('malformed', res.status);
	return parsed.data;
}
