// POST /api/reauth/complete — SELF-207 §2.4.4.b reauth Phase 2 (credential-less relay).
//
// Browser-facing: POST { linked_source_id, setup_token? } → { connection_status, rotated }.
//   - Plaid: NO token (update-mode Link succeeded client-side; access_token unchanged).
//   - SimpleFIN: the fresh Bridge setup_token (rotated on the existing source).
// This handler:
//   1. Requires a validated session and derives ownerUserId from it (SC3-C1).
//   2. Validates the body with Zod `.strict()` (mass-assignment fence).
//   3. Resolves the provider SERVER-SIDE (never client-supplied); non-owned → 404.
//   4. Builds the provider-appropriate worker input (Plaid: link_update_success; SimpleFIN:
//      setup_token — required for SimpleFIN) and relays to /admission/reauth/complete.
//
// Holds NO provider secret and NO service_role key → stays OFF the RT-26 allowlist.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { z } from 'zod';
import { resolveConnectionProvider } from '$lib/server/queries/connectionState';
import { reauthComplete, type Provider, type ReauthWireInput } from '$lib/server/reauth/admissionClient';

const bodySchema = z
	.object({
		linked_source_id: z.string().regex(/^\d+$/),
		setup_token: z.string().min(1).optional()
	})
	.strict();

export const POST: RequestHandler = async ({ request, locals }) => {
	const { user } = await locals.safeGetSession();
	if (!user) return json({ error: 'unauthenticated' }, { status: 401 });

	let raw: unknown;
	try {
		raw = await request.json();
	} catch {
		return json({ error: 'invalid_request' }, { status: 400 });
	}
	const parsed = bodySchema.safeParse(raw);
	if (!parsed.success) return json({ error: 'invalid_request' }, { status: 400 });

	const provider = await resolveConnectionProvider(locals.supabase, parsed.data.linked_source_id);
	if (provider !== 'plaid' && provider !== 'simplefin') {
		return json({ error: 'not_found' }, { status: 404 });
	}

	// Provider-derived wire input. Plaid finalizes with no token; SimpleFIN REQUIRES the fresh
	// setup token (a missing one is a client error, not a worker round-trip).
	let input: ReauthWireInput;
	if (provider === 'plaid') {
		input = { kind: 'link_update_success' };
	} else {
		if (!parsed.data.setup_token) return json({ error: 'invalid_request' }, { status: 400 });
		input = { kind: 'setup_token', setup_token: parsed.data.setup_token };
	}

	const outcome = await reauthComplete(user.id, provider as Provider, parsed.data.linked_source_id, input);
	if (!outcome.ok) return json({ error: 'reauth_failed' }, { status: outcome.status });

	return json({ connection_status: outcome.data.connectionStatus, rotated: outcome.data.rotated });
};
