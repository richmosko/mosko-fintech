// settings/owner-id/+page.server.ts — loader + save action for the §2.6.4.b owner-identification
// Settings editor (SELF-359 AC1-AC5), on top of migration 106 (pfin.owner_identification,
// SELF-352 / A8, landed at 30ac2cc on main via PR #629).
//
// ⚠ AUTHORSHIP NOTE (see $lib/server/schemas/owner-identification.ts's own header for the full
// statement): this file lives under Backend's ARCH §4.1 allowlist surface and was authored by
// Frontend under the SELF-359 dispatch brief, which named this exact file and directed the whole
// write path be built here — no paired Backend issue existed for this write path at dispatch
// time. Flagged as a role-boundary exception at hand-off, not taken silently.
//
// READ: a single `maybeSingle()` select — row-absent and a row with NULL `owner_id_header_text`
// both mean "unset" (106's own UNSET SEMANTICS: "BOTH unset representations are reachable ...
// every reader MUST treat row-absent and NULL identically"), so this loader collapses both into
// one `ownerIdHeaderText: string | null` field rather than threading `data`/`error` shape through
// to the page. Fail-soft on a read error (mirrors settings/allocation's own fail-soft posture) —
// a transient read failure degrades to "no header set" rather than a 500; the editor still lets
// the user type and save a new value.
//
// WRITE (AC3/AC5, RT-12): single-row UPSERT on `unique (users_id)` via PostgREST — no RPC, no
// lock needed (a single scalar column, replace-all-of-one-field). `users_id` is ALWAYS the
// session's own auth.uid(), never read from the request (Lock 14 mod #1) — included explicitly in
// the write object rather than relied upon via 106's own `DEFAULT auth.uid()`, matching
// cashflow-target.ts's own convention of never depending on a DEFAULT to carry a security
// property implicitly.
//
// ERROR MAPPING (AC4, Sec rider on PR #629): every 23514 (106's three named CHECKs — length,
// single-line, not-blank) and 23505 (the `unique (users_id)` conflict target, which the UPSERT's
// own onConflict target should make unreachable in practice, but is mapped anyway as
// defense-in-depth, same posture createSchedule's INSERT-conflict mapping takes) maps to a
// GENERIC 400 with user copy — the constraint NAME is NEVER passed to the client. 42501 (the 025
// aal2 step-up backstop, copied byte-faithfully onto every 106 policy) maps to 403, same as every
// other Lock 14 settings write path. Anything else stays a logged 500.

import { fail, redirect } from '@sveltejs/kit';
import type { PostgrestError } from '@supabase/supabase-js';
import { ownerIdentificationUpsertSchema } from '$lib/server/schemas/owner-identification';
import { fieldErrors } from '$lib/server/schemas/account';
import type { PageServerLoad, Actions } from './$types';

/** Maps a pfin.owner_identification write failure to a clean 4xx. Never surfaces a constraint
 *  name (AC4) — every message here is fixed, generic, user-facing copy. */
function mapWriteError(error: PostgrestError): { status: number; message: string } {
	switch (error.code) {
		case '42501':
			return {
				status: 403,
				message: 'This action requires a freshly verified session. Please step up and try again.'
			};
		case '23514':
		case '23505':
			return {
				status: 400,
				message: 'Could not save the header — enter up to 120 characters on a single line, then try again.'
			};
		default:
			console.error('[settings/owner-id] unexpected write error:', error.code, error.message);
			return { status: 500, message: 'Something went wrong. Please try again.' };
	}
}

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const { data, error } = await locals.supabase
		.schema('pfin')
		.from('owner_identification')
		.select('owner_id_header_text')
		.maybeSingle();

	if (error) {
		console.error('[settings/owner-id] load failed (fail-soft, unset):', error.code, error.message);
	}

	const row = data as { owner_id_header_text: string | null } | null;
	return { ownerIdHeaderText: row?.owner_id_header_text ?? null };
};

export const actions: Actions = {
	save: async ({ request, locals }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const form = await request.formData();
		const raw = form.get('owner_id_header_text');

		const parsed = ownerIdentificationUpsertSchema.safeParse({
			owner_id_header_text: typeof raw === 'string' ? raw : null
		});
		if (!parsed.success) {
			return fail(400, { errors: fieldErrors(parsed.error) });
		}

		const { error } = await locals.supabase
			.schema('pfin')
			.from('owner_identification')
			.upsert(
				{ users_id: user.id, owner_id_header_text: parsed.data.owner_id_header_text },
				{ onConflict: 'users_id' }
			);

		if (error) {
			const { status, message } = mapWriteError(error);
			return fail(status, { errors: { _form: [message] } });
		}

		return { ok: true as const, ownerIdHeaderText: parsed.data.owner_id_header_text };
	}
};
