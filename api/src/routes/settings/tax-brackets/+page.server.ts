// settings/tax-brackets/+page.server.ts — loader + form actions for the §2.5.2.a tax-brackets
// settings editor (SELF-265; rederived-acs.md § SELF-265 AC1-AC9). Backend-owned server source
// (ARCH §4.1 allowlist). Frontend's `+page.svelte` (built in parallel against this contract) is
// the sole consumer.
//
// THREE JURISDICTIONS, FIXED (AC1): federal_ordinary / federal_lt_cg / california_ordinary —
// `loadTaxBracketSchedules` (queries/taxBracketSchedules.ts) always returns all three groups,
// even when a jurisdiction holds no schedule yet, so the page can render all three editors
// unconditionally. Each jurisdiction carries `current_year_present` + `basis_year`, computed
// server-side so the editor can render the AC7a/E22 CTA ("FTB 2026 unpublished — figures run on
// the 2025 schedule; add 2026 when published") without re-deriving the fallback logic
// client-side. ⚠ AC8(ii) — the SEPARATE empty state for "no account carries a tax_jurisdiction
// value" — is NOT built here: it is a §2.5.3 YTD-Paid / account-attribute concern (SELF-267's
// surface, not this migration range's), and this issue's dispatch brief scoped this loader to
// bracket-schedule state only. Flagged in the hand-off rather than silently assumed either way.
//
// NO AS-OF TOGGLE (AC8a) — every §2.5 surface reads server-derived today; nothing here accepts a
// client-supplied as-of. `currentTaxYear` is resolved ONCE per request from `serverTodayAsOf()`
// (ADR-044 Decision 2 / the DB-clock discipline `time/asOf.ts` states), never `new Date()`
// inline, matching every other §2.x reader in this tree.
//
// WRITES (AC3/AC4): three actions, ONE schedule per request (execution-log E20) — never a
// multi-schedule batch. All three go through `queries/taxBracketScheduleWrite.ts`'s
// `replaceTaxBracketSchedule`, which REUSES the SELF-259 AC6 RPC contract
// (`pfin.fn_tax_bracket_schedule_replace_all`) name-for-name and the sibling endpoint's
// ownership-read-before-RPC / schedule-identity-guard / courtesy-precheck design — see that
// module's own header for why it is a separate implementation rather than a shared import.
//
// TRANSPORT: SvelteKit form actions (api/CLAUDE.md: "forms go through SvelteKit form actions"),
// so `rows` (a dynamic-length array the editor builds client-side) travels as a JSON-stringified
// hidden field, parsed here before validation — there is no existing JSON-array-in-FormData
// precedent in this codebase to follow, so this is a fresh, narrow judgment call, flagged in the
// hand-off. `tax_balance_prior_year` similarly needs an explicit '' → null translation before
// the shared schema sees it: `taxBracketScheduleReplaceSchema` expects `number | null` (matching
// the JSON endpoint's body), never an empty string, and FormData has no `null`.
//
// Lock 14 fences, same three owners as the sibling endpoint: `.strict()` at every level
// (schemas/tax-bracket-schedule.ts, REUSED unmodified — no field was added to it, this editor
// needs none it does not already have) is the mass-assignment fence; the shared numeric-
// sanitization battery is the adversarial-input fence; the DB's matched-tenant fence + deferred
// set-property trigger + `025` aal2 backstop are the actual guarantees, and every action's job is
// to map a rejection to a clean 4xx, never to re-derive the semantics itself.
//
// AUDIT-LOG: not applicable — ADR-011 Decision 18 classifies the whole Lock-14 settings family
// (tax_bracket_schedule / tax_bracket_row included) as NOT audit-class (same ruling
// cashflowTarget.ts / planning-target.ts / the sibling endpoint record).
//
// INVOKER + anon-key + RLS only, throughout: every call goes through `locals.supabase`, the
// session-bound client wired at the hooks.server.ts chokepoint. service_role is FORBIDDEN here.

import { fail, redirect } from '@sveltejs/kit';
import { loadTaxBracketSchedules } from '$lib/server/queries/taxBracketSchedules';
import { replaceTaxBracketSchedule } from '$lib/server/queries/taxBracketScheduleWrite';
import { taxBracketScheduleReplaceSchema } from '$lib/server/schemas/tax-bracket-schedule';
import { fieldErrors } from '$lib/server/schemas/account';
import { serverTodayAsOf } from '$lib/server/time/asOf';
import type { PageServerLoad, Actions } from './$types';

/** Shape-only guard on a posted `schedule_id` field — RLS (via `replaceTaxBracketSchedule`'s own
 *  ownership read, or the DELETE's own RLS-scoped predicate) is the actual tenant/visibility
 *  boundary. Mirrors the sibling endpoint's `parseScheduleId` / accounts/[account_id]'s
 *  `parseAccountId`: `Number.isSafeInteger`, not a smaller bound, because the PK is
 *  `bigint generated always as identity` (migration 101). */
function parseScheduleId(raw: FormDataEntryValue | null): number | null {
	if (typeof raw !== 'string') return null;
	const n = Number(raw);
	return Number.isSafeInteger(n) && n > 0 ? n : null;
}

/**
 * Turn a posted FormData into the shape `taxBracketScheduleReplaceSchema` validates, then
 * validate it. `schedule_id` is a CONTROL field, read separately by each action (never a member
 * of this schema — the schema is REUSED unmodified from the sibling endpoint, where `schedule_id`
 * is a route param, not a body field; here it is a sibling form field instead, but the mass-
 * assignment discipline is the same: it never reaches `.strict()`). `rows` arrives as a JSON
 * string (see file header); a parse failure is left as the raw string rather than special-cased —
 * `z.array(...)` then rejects it with its own clear "expected array" issue on `rows`, same
 * generic-but-correct shape as every other schema-boundary type mismatch on this surface.
 */
function parseReplaceFormData(form: FormData) {
	const priorYearRaw = form.get('tax_balance_prior_year');
	const rowsRaw = form.get('rows');
	let rows: unknown = rowsRaw;
	if (typeof rowsRaw === 'string') {
		try {
			rows = JSON.parse(rowsRaw);
		} catch {
			rows = rowsRaw;
		}
	}

	return taxBracketScheduleReplaceSchema.safeParse({
		tax_year: form.get('tax_year'),
		schedule_type: form.get('schedule_type'),
		schedule_label: form.get('schedule_label'),
		standard_deduction: form.get('standard_deduction'),
		tax_balance_prior_year: priorYearRaw === null || priorYearRaw === '' ? null : priorYearRaw,
		rows
	});
}

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const currentTaxYear = Number(serverTodayAsOf().slice(0, 4));
	const jurisdictions = await loadTaxBracketSchedules(locals.supabase, currentTaxYear);

	return { jurisdictions, currentTaxYear };
};

export const actions: Actions = {
	// ── AC3/AC4: replace-all write for ONE EXISTING schedule ────────────────────────────────────
	saveSchedule: async ({ request, locals }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { action: 'saveSchedule', errors: { _form: ['You must be signed in.'] } });

		const form = await request.formData();
		const scheduleId = parseScheduleId(form.get('schedule_id'));
		if (scheduleId === null) {
			return fail(400, { action: 'saveSchedule', errors: { _form: ['Invalid schedule.'] } });
		}

		const parsed = parseReplaceFormData(form);
		if (!parsed.success) {
			return fail(400, { action: 'saveSchedule', scheduleId, errors: fieldErrors(parsed.error) });
		}

		const result = await replaceTaxBracketSchedule(locals.supabase, scheduleId, parsed.data);
		if (!result.ok) {
			return fail(result.status, { action: 'saveSchedule', scheduleId, errors: result.errors });
		}

		return { action: 'saveSchedule' as const, ok: true, scheduleId };
	},

	// ── AC3: create a NEW schedule (a new tax_year, or a jurisdiction's first schedule) ─────────
	// The replace-all RPC never creates a schedule (execution-log E8) — the parent row is an
	// ordinary INSERT under RLS (users_id DEFAULT auth.uid()), and only THEN is the same
	// replace-all path called for its rows, on the schedule this INSERT just minted. This is how
	// e.g. a CA 2026 schedule gets entered once the FTB publishes it (AC7a/E22's CTA target).
	createSchedule: async ({ request, locals }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { action: 'createSchedule', errors: { _form: ['You must be signed in.'] } });

		const form = await request.formData();
		const parsed = parseReplaceFormData(form);
		if (!parsed.success) {
			return fail(400, { action: 'createSchedule', errors: fieldErrors(parsed.error) });
		}

		const { data: inserted, error: insertError } = await locals.supabase
			.schema('pfin')
			.from('tax_bracket_schedule')
			.insert({
				tax_year: parsed.data.tax_year,
				schedule_type: parsed.data.schedule_type,
				schedule_label: parsed.data.schedule_label,
				standard_deduction: parsed.data.standard_deduction,
				tax_balance_prior_year: parsed.data.tax_balance_prior_year
			})
			.select('id')
			.single();

		if (insertError) {
			// unique (users_id, tax_year, schedule_type) — a schedule for this year+type already
			// exists. Attributed to `tax_year`: it is the dimension a user creating a new schedule is
			// actually choosing (schedule_type is fixed per editor panel).
			if (insertError.code === '23505') {
				return fail(409, {
					action: 'createSchedule',
					errors: { tax_year: ['A schedule already exists for this year and type.'] }
				});
			}
			if (insertError.code === '42501') {
				return fail(403, {
					action: 'createSchedule',
					errors: { _form: ['This action requires a freshly verified session. Please step up and try again.'] }
				});
			}
			console.error('[tax-brackets] createSchedule insert failed:', insertError.code, insertError.message);
			return fail(500, { action: 'createSchedule', errors: { _form: ['Could not create the schedule. Please try again.'] } });
		}

		const scheduleId = (inserted as { id: number }).id;

		// Same one-schedule-per-request replace-all path saveSchedule uses — the ownership read
		// inside it simply re-finds the row the INSERT above just created, and the identity guard
		// passes trivially since tax_year/schedule_type were just written from this same input.
		const result = await replaceTaxBracketSchedule(locals.supabase, scheduleId, parsed.data);
		if (!result.ok) {
			return fail(result.status, { action: 'createSchedule', scheduleId, errors: result.errors });
		}

		return { action: 'createSchedule' as const, ok: true, scheduleId };
	},

	// ── AC3: delete a schedule (cascade removes its rows) ────────────────────────────────────────
	// Deliberately UNGUARDED against deleting the only schedule of a type for the current year —
	// there is no "last one" special case. A jurisdiction with no current-or-prior schedule left
	// renders AC8(i)'s UNAVAILABLE state on the reader surfaces; that is the reader's job to
	// render, not this action's to prevent by refusing an otherwise-valid delete.
	//
	// Idempotent-DELETE convention (planning-target.ts's precedent on this same Lock-14 family):
	// always succeeds at the HTTP level, `deleted` discloses the caller's OWN outcome. The
	// explicit `.eq('users_id', ...)` predicate (beside `.eq('id', ...)`) is what makes `deleted`
	// safe to disclose — it pins the query to the caller's own rows BY CONSTRUCTION, so a
	// cross-tenant row is unobservable through this response rather than merely RLS-filtered.
	// `deleted: false` covers two causes this flag does not separate (the row never existed, or it
	// exists but the caller is below aal2 so the DELETE policy's USING clause hides it) — both
	// read identically, a deliberate bounded non-disclosure WITHIN one account, same as
	// planning-target.ts's own DELETE.
	deleteSchedule: async ({ request, locals }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { action: 'deleteSchedule', errors: { _form: ['You must be signed in.'] } });

		const form = await request.formData();
		const scheduleId = parseScheduleId(form.get('schedule_id'));
		if (scheduleId === null) {
			return fail(400, { action: 'deleteSchedule', errors: { _form: ['Invalid schedule.'] } });
		}

		const { error, count } = await locals.supabase
			.schema('pfin')
			.from('tax_bracket_schedule')
			.delete({ count: 'exact' })
			.eq('id', scheduleId)
			.eq('users_id', user.id);

		if (error) {
			console.error('[tax-brackets] deleteSchedule failed:', error.code, error.message);
			return fail(500, { action: 'deleteSchedule', errors: { _form: ['Could not delete the schedule. Please try again.'] } });
		}

		return { action: 'deleteSchedule' as const, scheduleId, deleted: (count ?? 0) > 0 };
	}
};
