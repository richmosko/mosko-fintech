// simplefinConnectFlow.ts — pure, dependency-injected core for the single SimpleFIN
// connect relay call (leg-S). Framework-free and unit-testable: one async function that
// posts the setup token to the relay and validates the response against the OQ-2 contract.
// `fetchFn` is injectable so tests drive it with a mocked relay (no network, no DOM).
//
// CREDENTIAL HYGIENE (OQ-2 §4): the setup token rides the JSON BODY once (never a URL
// query — mirror the Plaid C6-5 "never a query string" discipline), and this module never
// logs it. `connectRequestSchema.strict()` runs on the outgoing body — a belt-and-braces
// proof the browser transmits ONLY { setup_token, institutionName? } and never a tenant id.
//
// The typed error carries the browser-facing HTTP status so the component can distinguish
// the three actionable outcomes (OQ-2 §3a error mapping):
//   • 400 → burned/invalid setup token → prompt the user to get a fresh one from the Bridge.
//   • 401 → session lapsed → re-auth.
//   • 5xx / network / malformed → service unavailable → retry later.

import {
	SIMPLEFIN_CONNECT_ROUTE,
	connectRequestSchema,
	connectResponseSchema,
	type ConnectResponse
} from './contract';

export type FetchLike = typeof fetch;

/** How the relay call failed — drives the component's error copy + recovery affordance. */
export type SimplefinFailureKind = 'invalid-token' | 'unauthenticated' | 'unavailable';

/** Typed relay failure: HTTP non-2xx, malformed body, or network throw. Carries NO token. */
export class SimplefinRelayError extends Error {
	readonly failure: SimplefinFailureKind;
	readonly status: number | null;
	constructor(failure: SimplefinFailureKind, status: number | null = null) {
		super(`SimpleFIN connect failed (${failure}${status != null ? ` ${status}` : ''})`);
		this.name = 'SimplefinRelayError';
		this.failure = failure;
		this.status = status;
	}
}

/** Map a relay HTTP status → an actionable failure category (OQ-2 §3a). */
function classifyStatus(status: number): SimplefinFailureKind {
	if (status === 401) return 'unauthenticated';
	if (status === 400) return 'invalid-token'; // relay `connect_failed` (burned token) / `invalid_request`
	return 'unavailable'; // 500 / 502 (worker unreachable) / anything else non-2xx
}

/**
 * Leg-S — hand the user's pasted SimpleFIN setup token (+ optional institution name) to
 * the relay for the server-side claim + Vault admission. Returns { success, accounts } on
 * 200. `ownerUserId` is derived server-side from the session (SC3-C1) — deliberately NOT
 * in the body.
 *
 * @param setupToken   the base64 claim string the user pasted (credential-class).
 * @param institutionName optional user-supplied label (non-secret).
 */
export async function submitSetupToken(
	setupToken: string,
	institutionName: string | undefined,
	fetchFn: FetchLike = fetch
): Promise<ConnectResponse> {
	// Mass-assignment fence: only these keys may leave the browser. Omit institutionName
	// entirely when blank so the `.min(1)` optional mirror is satisfied (no empty string).
	const body = connectRequestSchema.parse({
		setup_token: setupToken,
		...(institutionName ? { institutionName } : {})
	});

	let res: Response;
	try {
		res = await fetchFn(SIMPLEFIN_CONNECT_ROUTE, {
			method: 'POST',
			headers: { 'content-type': 'application/json', accept: 'application/json' },
			body: JSON.stringify(body)
		});
	} catch {
		throw new SimplefinRelayError('unavailable'); // network / offline — worker not reached
	}

	if (!res.ok) throw new SimplefinRelayError(classifyStatus(res.status), res.status);

	let json: unknown;
	try {
		json = await res.json();
	} catch {
		throw new SimplefinRelayError('unavailable', res.status); // malformed success body
	}
	const parsed = connectResponseSchema.safeParse(json);
	if (!parsed.success) throw new SimplefinRelayError('unavailable', res.status);
	return parsed.data;
}
