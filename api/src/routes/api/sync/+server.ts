// POST /api/sync — SELF-317 manual "Sync now" trigger (credential-less relay; ADR-037 amendment).
//
// Browser-facing. POST { source_id? } → 202 { status:'accepted', sources:[{source_id, disposition}] }.
// `source_id` ABSENT ⇒ "sync all my active sources"; PRESENT ⇒ per-source. This handler:
//   1. Requires a validated session and derives ownerUserId from it (SC3-C1) — NEVER from the body.
//   2. Validates the body with Zod `.strict()` (mass-assignment fence, Lock 14 mod #1). `source_id`
//      is the ONLY body field; `users_id`/`ownerUserId` are NEVER accepted from the browser.
//   3. Per-source ONLY: resolves the provider SERVER-SIDE from the caller's own linked_source under
//      the anon client + linked_source_select RLS — a foreign/nonexistent source_id → null → 404
//      BEFORE any worker call (Sec C2 layer 2, the spoof gate). Sync-all skips this: the worker-side
//      RLS-scoped enumeration (Sec C1) is the isolation boundary — there is no client-supplied id to
//      spoof in the all-case.
//   4. Relays { ownerUserId=session, source_id? } to the worker's internal /admission/manual-sync and
//      returns the per-source dispositions (A2 return-fast 202).
//
// Holds NO provider secret and NO service_role key → stays OFF the RT-26 allowlist.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { z } from 'zod';
import { resolveConnectionProvider } from '$lib/server/queries/connectionState';
import { requestManualSync } from '$lib/server/sync/syncClient';

const bodySchema = z.object({ source_id: z.string().regex(/^\d+$/).optional() }).strict();

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

	// Per-source spoof gate (Sec C2 layer 2): the source must resolve under the caller's own RLS —
	// a foreign or nonexistent source_id resolves to null → 404, never reaching the worker. Sync-all
	// (source_id absent) skips this: the worker enumerates ONLY the caller's sources under RLS (C1).
	if (parsed.data.source_id !== undefined) {
		const provider = await resolveConnectionProvider(locals.supabase, parsed.data.source_id);
		if (provider !== 'plaid' && provider !== 'simplefin') {
			return json({ error: 'not_found' }, { status: 404 });
		}
	}

	const outcome = await requestManualSync(user.id, parsed.data.source_id);
	if (!outcome.ok) return json({ error: 'sync_failed' }, { status: outcome.status });

	return json({ status: 'accepted', sources: outcome.data.sources }, { status: 202 });
};
