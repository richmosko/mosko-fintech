// POST /api/simplefin/connect — OQ-2 relay leg-S (credential-less SimpleFIN setup-token claim).
//
// Browser-facing shape (Frontend contract): POST { setup_token, institutionName? } →
// { success: true, accounts }. This handler:
//   1. Requires a validated session and derives ownerUserId from it (SC3-C1 / C6-3).
//   2. Validates the body with Zod `.strict()` — the mass-assignment fence: any extra key
//      (least of all a client-supplied ownerUserId / tenant id) is REJECTED (400).
//   3. Relays { setup_token, ownerUserId=session, institutionName? } to the worker's internal
//      /admission/simplefin/claim and maps 2xx → { success, accounts } (sourceId dropped — it's
//      an internal pfin id the browser never needs).
//
// This route holds NO SimpleFIN credential and NO service_role key → stays OFF the RT-26
// allowlist. C6-4 analogue: a burned setup token is never retried — failure is surfaced so the
// browser obtains a fresh setup token from the SimpleFIN Bridge. SimpleFIN is ONE leg (no
// link-token pre-mint, no /item/remove recovery — a read-only Access URL needs none).

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { z } from 'zod';
import { admitSimplefin } from '$lib/server/simplefin/admissionClient';

// `.strict()` mass-assignment fence (Lock 14 Sec mod #1/#2 · SC3-C1/C6-3): these are the ONLY
// keys the browser may send. A body carrying `ownerUserId` (or any extra field) is rejected here —
// it can NEVER influence the tenant the worker admits. `setup_token` (snake) mirrors the shipped
// Plaid `public_token` convention.
const connectBodySchema = z
	.object({
		setup_token: z.string().min(1),
		institutionName: z.string().min(1).optional()
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

	const parsed = connectBodySchema.safeParse(raw);
	if (!parsed.success) {
		// Includes the attacker-supplied-ownerUserId case — `.strict()` rejects the extra key.
		return json({ error: 'invalid_request' }, { status: 400 });
	}

	// ownerUserId = user.id (session). The body's fields cannot reach this argument.
	const outcome = await admitSimplefin(user.id, parsed.data);
	if (!outcome.ok) {
		return json({ error: 'connect_failed' }, { status: outcome.status });
	}

	return json({ success: true, accounts: outcome.data.accounts });
};
