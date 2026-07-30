// POST /api/reauth/start — SELF-207 §2.4.4.b reauth Phase 1 (credential-less relay).
//
// Browser-facing (connect-flow-shaped, NOT a form action — the Plaid path drives the Link SDK):
// POST { linked_source_id } → { kind: 'link_update', link_token } (Plaid) | { kind: 'recollect' }
// (SimpleFIN). This handler:
//   1. Requires a validated session and derives ownerUserId from it (SC3-C1).
//   2. Validates the body with Zod `.strict()` (mass-assignment fence).
//   3. Resolves the provider SERVER-SIDE from the caller's own linked_source (never trusts a
//      client-supplied provider); a non-owned/nonexistent source → 404.
//   4. Relays { provider, linked_source_id, ownerUserId=session } to the worker's internal
//      /admission/reauth/start and returns the handoff.
//
// Holds NO provider secret and NO service_role key → stays OFF the RT-26 allowlist.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { z } from 'zod';
import { resolveConnectionProvider } from '$lib/server/queries/connectionState';
import { reauthStart, type Provider } from '$lib/server/reauth/admissionClient';

const bodySchema = z.object({ linked_source_id: z.string().regex(/^\d+$/) }).strict();

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

	// Provider is authoritative from the caller's own connection (owner-scoped RLS) — a foreign
	// or nonexistent source_id resolves to null → 404 (never reaches the worker).
	const provider = await resolveConnectionProvider(locals.supabase, parsed.data.linked_source_id);
	if (provider !== 'plaid' && provider !== 'simplefin') {
		return json({ error: 'not_found' }, { status: 404 });
	}

	const outcome = await reauthStart(user.id, provider as Provider, parsed.data.linked_source_id);
	if (!outcome.ok) return json({ error: 'reauth_failed' }, { status: outcome.status });

	// Handoff: { kind: 'link_update', linkToken } | { kind: 'recollect_credential' }. Rename
	// linkToken → link_token for the browser (snake convention; mirrors the connect legs).
	if (outcome.data.kind === 'link_update') {
		return json({ kind: 'link_update', link_token: outcome.data.linkToken });
	}
	return json({ kind: 'recollect_credential' });
};
