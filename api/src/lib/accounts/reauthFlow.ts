// reauthFlow.ts — pure, dependency-injected core for the two SELF-207 re-auth relay legs.
//
// Framework-free + unit-testable (like plaidLinkFlow / simplefinConnectFlow): two async
// functions that POST to the relay and validate the response against reauth-contract.ts.
// `fetchFn` is injectable so tests drive a mocked relay (no network, no DOM). The DOM/SDK
// parts (Plaid Link update-mode modal, the SimpleFIN paste field) live in the component.
//
// FENCES: each outgoing body runs through its `.strict()` request schema before send — a
// belt-and-braces proof the browser transmits ONLY the allowed keys (no provider, no tenant
// id, no secret beyond the setup token the user pasted). No access_token / Access URL / Plaid
// secret exists in this module by construction.

import {
	REAUTH_START_ROUTE,
	REAUTH_COMPLETE_ROUTE,
	reauthStartRequestSchema,
	reauthStartResponseSchema,
	reauthCompleteRequestSchema,
	reauthCompleteResponseSchema,
	type ReauthStartResponse,
	type ReauthCompleteResponse
} from './reauth-contract';

export type FetchLike = typeof fetch;

/** Which relay leg failed — drives the component's retry affordance. */
export type ReauthLeg = 'start' | 'complete';

/** Actionable failure category, mapped from the relay HTTP status (Backend's error envelope):
 *  401 unauthenticated · 400 invalid_request · 404 not_found · 500/other reauth_failed · network. */
export type ReauthFailureKind =
	| 'unauthenticated'
	| 'invalid_request'
	| 'not_found'
	| 'reauth_failed'
	| 'network'
	| 'malformed';

export class ReauthError extends Error {
	readonly leg: ReauthLeg;
	readonly failure: ReauthFailureKind;
	readonly status: number | null;
	constructor(leg: ReauthLeg, failure: ReauthFailureKind, status: number | null = null) {
		super(`Re-auth ${leg} failed (${failure}${status != null ? ` ${status}` : ''})`);
		this.name = 'ReauthError';
		this.leg = leg;
		this.failure = failure;
		this.status = status;
	}
}

/** Map a relay HTTP status → an actionable failure category. */
function classify(status: number): ReauthFailureKind {
	if (status === 401) return 'unauthenticated';
	if (status === 400) return 'invalid_request';
	if (status === 404) return 'not_found';
	return 'reauth_failed'; // 500 reauth_failed / anything else non-2xx
}

/**
 * Leg 1 — start re-auth for one connection. Returns the discriminated handoff telling the
 * component how to re-collect: `link_update` (open Plaid Link with `link_token`) or
 * `recollect_credential` (show the SimpleFIN paste field). Provider is server-resolved.
 */
export async function startReauth(
	linkedSourceId: string,
	fetchFn: FetchLike = fetch
): Promise<ReauthStartResponse> {
	const body = reauthStartRequestSchema.parse({ linked_source_id: linkedSourceId });

	let res: Response;
	try {
		res = await fetchFn(REAUTH_START_ROUTE, {
			method: 'POST',
			headers: { 'content-type': 'application/json', accept: 'application/json' },
			body: JSON.stringify(body)
		});
	} catch {
		throw new ReauthError('start', 'network');
	}
	if (!res.ok) throw new ReauthError('start', classify(res.status), res.status);

	let json: unknown;
	try {
		json = await res.json();
	} catch {
		throw new ReauthError('start', 'malformed', res.status);
	}
	const parsed = reauthStartResponseSchema.safeParse(json);
	if (!parsed.success) throw new ReauthError('start', 'malformed', res.status);
	return parsed.data;
}

/**
 * Leg 2 — complete re-auth. Plaid: omit `setupToken` (update-mode success carries no
 * public_token). SimpleFIN: pass the freshly-pasted setup token (required). Returns
 * `{ connection_status, rotated }` on success — the caller then invalidates the loaders so
 * the banner + connection-state view refresh (the connection flips to healthy).
 */
export async function completeReauth(
	linkedSourceId: string,
	setupToken?: string,
	fetchFn: FetchLike = fetch
): Promise<ReauthCompleteResponse> {
	// Mass-assignment fence: only these keys leave the browser. Omit setup_token entirely when
	// absent (Plaid) so the optional mirror is satisfied (no empty string on the wire).
	const body = reauthCompleteRequestSchema.parse({
		linked_source_id: linkedSourceId,
		...(setupToken ? { setup_token: setupToken } : {})
	});

	let res: Response;
	try {
		res = await fetchFn(REAUTH_COMPLETE_ROUTE, {
			method: 'POST',
			headers: { 'content-type': 'application/json', accept: 'application/json' },
			body: JSON.stringify(body)
		});
	} catch {
		throw new ReauthError('complete', 'network');
	}
	if (!res.ok) throw new ReauthError('complete', classify(res.status), res.status);

	let json: unknown;
	try {
		json = await res.json();
	} catch {
		throw new ReauthError('complete', 'malformed', res.status);
	}
	const parsed = reauthCompleteResponseSchema.safeParse(json);
	if (!parsed.success) throw new ReauthError('complete', 'malformed', res.status);
	return parsed.data;
}
