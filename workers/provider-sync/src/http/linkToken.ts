// linkToken.ts — leg-1: Plaid /link/token/create (SELF-212 Option C).
//
// A STATELESS synchronous mint: no DB write, no service_role, no persistence. It lives in the
// worker (not api/src) because /link/token/create needs the Plaid CLIENT SECRET, which per
// ADR-027 (s) is confined to the worker tier — the same secret does both link_token mint AND
// public_token exchange, so putting it in api/src would re-open app-owns-exchange.
//
// `ownerUserId` is the session-derived tenant relayed by api/src over the shared-secret-authed
// channel (C6-6: leg-1 tenant scoping is also session-derived, never browser-sourced). It maps
// to Plaid's `user.client_user_id`. Errors are scrubbed (C6-5) — reuse scrubbedPlaidError so no
// Plaid secret / token fragment surfaces.

import { scrubbedPlaidError, type PlaidClientLike } from '../adapters/PlaidAdapter.js';

/** Defaults for the V1 Plaid Link session. Products match the sandbox mint in cli/admit.ts
 *  (transactions + investments); country/language are the V1 single-region posture. */
export interface LinkTokenOptions {
	readonly clientName?: string;
	readonly products?: readonly string[];
	readonly countryCodes?: readonly string[];
	readonly language?: string;
	/** Optional Plaid OAuth redirect URI (V1 sandbox does not require it). */
	readonly redirectUri?: string;
}

const DEFAULTS = {
	clientName: 'mosko-fintech',
	products: ['transactions', 'investments'] as const,
	countryCodes: ['US'] as const,
	language: 'en'
};

/**
 * Mint a short-lived Plaid link_token for `ownerUserId`. Pure w.r.t. our data layer (no DB);
 * the only side effect is the Plaid API call. Returns exactly the fields the browser needs to
 * open Plaid Link. Throws a SCRUBBED error on Plaid failure (C6-5).
 */
export async function mintLinkToken(
	client: PlaidClientLike,
	ownerUserId: string,
	opts: LinkTokenOptions = {}
): Promise<{ link_token: string; expiration: string }> {
	try {
		const { data } = await client.linkTokenCreate({
			user: { client_user_id: ownerUserId },
			client_name: opts.clientName ?? DEFAULTS.clientName,
			products: [...(opts.products ?? DEFAULTS.products)],
			country_codes: [...(opts.countryCodes ?? DEFAULTS.countryCodes)],
			language: opts.language ?? DEFAULTS.language,
			...(opts.redirectUri ? { redirect_uri: opts.redirectUri } : {})
		});
		return { link_token: data.link_token, expiration: data.expiration };
	} catch (err) {
		throw scrubbedPlaidError(err, 'link/token/create');
	}
}

/**
 * Mint an UPDATE-MODE Plaid link_token for an EXISTING Item (SELF-207 re-auth). Passes the
 * Item's existing `access_token` and OMITS `products` (Plaid's update-mode rule — products are
 * fixed on the existing Item). Update mode does NOT change the access_token (no re-exchange;
 * plaid.com/docs/link/update-mode) — so re-auth needs no credential rotation. `accessToken` is
 * resolved server-side from Vault by the caller (reauthShared.resolveAccessToken); it is NEVER
 * logged and stays in worker memory only. Update-mode link_tokens expire after 30 min. Throws a
 * SCRUBBED error on Plaid failure (C6-5) — the message carries no token/secret fragment.
 */
export async function mintUpdateModeLinkToken(
	client: PlaidClientLike,
	ownerUserId: string,
	accessToken: string,
	opts: LinkTokenOptions = {}
): Promise<{ link_token: string; expiration: string }> {
	try {
		const { data } = await client.linkTokenCreate({
			user: { client_user_id: ownerUserId },
			client_name: opts.clientName ?? DEFAULTS.clientName,
			// products OMITTED — update mode operates on the existing Item's product set.
			country_codes: [...(opts.countryCodes ?? DEFAULTS.countryCodes)],
			language: opts.language ?? DEFAULTS.language,
			access_token: accessToken,
			...(opts.redirectUri ? { redirect_uri: opts.redirectUri } : {})
		});
		return { link_token: data.link_token, expiration: data.expiration };
	} catch (err) {
		throw scrubbedPlaidError(err, 'link/token/create (update mode)');
	}
}
