// plaidLinkFlow.ts — pure, dependency-injected orchestration for the two relay calls.
//
// The DOM/SDK-touching parts (script load, Plaid.create, modal) live in loadPlaidLink.ts
// and the component. THIS module is the framework-free, unit-testable core: two async
// functions that call the relay and validate the response against the SELF-197 contract.
// `fetchFn` is injectable so tests drive it with a mocked relay (no network, no DOM).
//
// AC #5 guard: exchangePublicToken() runs the outgoing body through
// `exchangeRequestSchema.strict()` before sending — a belt-and-suspenders proof that the
// browser transmits ONLY `{ public_token, metadata? }` and never a tenant id / token /
// secret. There is no `access_token` symbol anywhere in this file by construction.

import {
	PLAID_LINK_TOKEN_ROUTE,
	PLAID_EXCHANGE_ROUTE,
	linkTokenResponseSchema,
	exchangeRequestSchema,
	exchangeResponseSchema,
	type LinkTokenResponse,
	type ExchangeResponse
} from './contract';

export type FetchLike = typeof fetch;

/** Which relay leg failed — drives the component's retry affordance (AC #4). */
export type PlaidRelayLeg = 'link-token' | 'exchange';

/** Typed relay failure: HTTP non-2xx, malformed body, or network throw. */
export class PlaidRelayError extends Error {
	readonly leg: PlaidRelayLeg;
	readonly status: number | null;
	readonly kind: 'http' | 'malformed' | 'network';
	constructor(leg: PlaidRelayLeg, kind: 'http' | 'malformed' | 'network', status: number | null = null) {
		super(`Plaid relay ${leg} failed (${kind}${status != null ? ` ${status}` : ''})`);
		this.name = 'PlaidRelayError';
		this.leg = leg;
		this.status = status;
		this.kind = kind;
	}
}

/**
 * Leg 1 — fetch a short-TTL `link_token` from the relay. The client holds only this
 * token; it never sees a Plaid secret or access_token.
 */
export async function fetchLinkToken(fetchFn: FetchLike = fetch): Promise<LinkTokenResponse> {
	let res: Response;
	try {
		res = await fetchFn(PLAID_LINK_TOKEN_ROUTE, {
			method: 'GET',
			headers: { accept: 'application/json' }
		});
	} catch {
		throw new PlaidRelayError('link-token', 'network');
	}
	if (!res.ok) throw new PlaidRelayError('link-token', 'http', res.status);

	let json: unknown;
	try {
		json = await res.json();
	} catch {
		throw new PlaidRelayError('link-token', 'malformed', res.status);
	}
	const parsed = linkTokenResponseSchema.safeParse(json);
	if (!parsed.success) throw new PlaidRelayError('link-token', 'malformed', res.status);
	return parsed.data;
}

/**
 * Leg 2 — hand Plaid's `public_token` (+ non-secret Link metadata) to the relay for the
 * server-side exchange. Returns `{ success, accounts }` on 200. `ownerUserId` is derived
 * server-side from the session (SC3-C1) — deliberately NOT in the body.
 */
export async function exchangePublicToken(
	publicToken: string,
	metadata?: unknown,
	fetchFn: FetchLike = fetch
): Promise<ExchangeResponse> {
	// Mass-assignment fence (AC #5): only these keys may leave the browser.
	const body = exchangeRequestSchema.parse({ public_token: publicToken, metadata });

	let res: Response;
	try {
		res = await fetchFn(PLAID_EXCHANGE_ROUTE, {
			method: 'POST',
			headers: { 'content-type': 'application/json', accept: 'application/json' },
			body: JSON.stringify(body)
		});
	} catch {
		throw new PlaidRelayError('exchange', 'network');
	}
	if (!res.ok) throw new PlaidRelayError('exchange', 'http', res.status);

	let json: unknown;
	try {
		json = await res.json();
	} catch {
		throw new PlaidRelayError('exchange', 'malformed', res.status);
	}
	const parsed = exchangeResponseSchema.safeParse(json);
	if (!parsed.success) throw new PlaidRelayError('exchange', 'malformed', res.status);
	return parsed.data;
}
