// GET /api/plaid/link-token — SELF-197 relay leg 1 (credential-less link_token mint).
//
// Browser-facing shape (Frontend contract.ts): GET → { link_token, expiration }.
// This handler derives ownerUserId from the validated session and POSTs it to the
// worker's internal /admission/link-token (ownerUserId rides the JSON body, never a
// query string — C6-5 log hygiene). The Plaid secret lives worker-side; this route
// holds only WORKER_ADMISSION_SHARED_SECRET → stays OFF the RT-26 allowlist.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { mintLinkToken } from '$lib/server/plaid/admissionClient';

export const GET: RequestHandler = async ({ locals }) => {
	// SC3-C1: tenant identity comes EXCLUSIVELY from the validated session (auth.uid()
	// via the hooks.server.ts chokepoint), never from the request.
	const { user } = await locals.safeGetSession();
	if (!user) {
		return json({ error: 'unauthenticated' }, { status: 401 });
	}

	const outcome = await mintLinkToken(user.id);
	if (!outcome.ok) {
		// Generic envelope — no token fragment, no upstream detail (C6-5).
		return json({ error: 'link_token_unavailable' }, { status: outcome.status });
	}

	return json({ link_token: outcome.data.link_token, expiration: outcome.data.expiration });
};
