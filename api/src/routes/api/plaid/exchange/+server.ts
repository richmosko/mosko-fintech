// POST /api/plaid/exchange — SELF-197 relay leg 2 (credential-less public_token exchange).
//
// Browser-facing shape (Frontend contract.ts): POST { public_token, metadata? } →
// { success: true, accounts }. This handler:
//   1. Requires a validated session and derives ownerUserId from it (SC3-C1 / C6-3).
//   2. Validates the body with Zod `.strict()` — the mass-assignment fence: any extra
//      key (least of all a client-supplied ownerUserId / tenant id) is REJECTED (400).
//   3. Relays { public_token, ownerUserId=session, institution... } to the worker's
//      internal /admission/exchange and maps 2xx → { success, accounts } (sourceId
//      dropped — it's an internal pfin id the browser never needs).
//
// This route holds NO Plaid secret and NO service_role key → stays OFF the RT-26
// allowlist. C6-4: a burned public_token is never retried — failure is surfaced so the
// browser re-runs Link for a fresh token.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { z } from 'zod';
import { exchangePublicToken } from '$lib/server/plaid/admissionClient';

// `.strict()` mass-assignment fence (Lock 14 Sec mod #1/#2 · SC3-C1/C6-3): these are the
// ONLY keys the browser may send. A body carrying `ownerUserId` (or any extra field) is
// rejected here — it can NEVER influence the tenant the worker admits.
const exchangeBodySchema = z
	.object({
		public_token: z.string().min(1),
		metadata: z.unknown().optional()
	})
	.strict();

export const POST: RequestHandler = async ({ request, locals }) => {
	// SC3-C1: session-derived tenant is the SOLE primary tenant control.
	const { user } = await locals.safeGetSession();
	if (!user) {
		return json({ error: 'unauthenticated' }, { status: 401 });
	}

	let raw: unknown;
	try {
		raw = await request.json();
	} catch {
		return json({ error: 'invalid_request' }, { status: 400 });
	}

	const parsed = exchangeBodySchema.safeParse(raw);
	if (!parsed.success) {
		// Includes the attacker-supplied-ownerUserId case — `.strict()` rejects the extra key.
		return json({ error: 'invalid_request' }, { status: 400 });
	}

	// ownerUserId = user.id (session). The body's fields cannot reach this argument.
	const outcome = await exchangePublicToken(user.id, parsed.data);
	if (!outcome.ok) {
		return json({ error: 'exchange_failed' }, { status: outcome.status });
	}

	return json({ success: true, accounts: outcome.data.accounts });
};
