// reset-password/+page.server.ts — set a new password on the recovery session
// (SELF-288 / Auth-5, AC #1; F/CTO Option A). Backend-owned server source (ARCH §4.1
// allowlist). NO service_role (RT-26), NO migration, NO DEFINER.
//
// REACHED VIA the recovery link: the email's ConfirmationURL → GoTrue verifies the
// recovery token → redirects to /auth/callback?next=/reset-password&code=… → the callback
// exchangeCodeForSession() mints a recovery SESSION (aal1) → bounces here.
//
// MFA STEP-UP COMPOSITION (F/CTO Option A — the security crux, flagged for Sec):
//   THE ENFORCER IS THE APP LAYER — the aal2 requirement for an MFA user's password reset is
//   enforced by OUR guard, in two positions, independent of any GoTrue behavior:
//     (1) mfaHandle guards the GET navigation. This route is DELIBERATELY NOT in the hooks
//         STEP_UP_EXEMPT_PREFIXES, so:
//           - NON-MFA user → requireStepUp 'allow'          → load renders the form directly.
//           - MFA user     → requireStepUp 'step-up-required' → mfaHandle redirects aal1 →
//             /mfa/step-up?redirectTo=/reset-password → verify authenticator → aal2 → return
//             here → load renders the form.
//     (2) the ACTION re-runs the SAME requireStepUp decision (mfaHandle only guards GET, not
//         this POST), so a scripted / aal2-lapsed aal1 MFA POST is funnelled to /mfa/step-up
//         too — never reaching updateUser at aal1. Non-MFA → 'allow' → proceeds.
//   So a password reset for an MFA user requires BOTH email control (the link) AND the 2nd
//   factor (step-up) — enforced by (1)+(2). This is NOT an MFA bypass; it ADDS the factor
//   requirement.
//   THIRD LINE (belt-and-suspenders, NOT relied upon): GoTrue is OBSERVED to also refuse
//   updateUser({password}) at aal1 for an MFA-enrolled user and permit it at aal2 (its
//   sensitive-op gate; observed on the pinned GoTrue in supabase/config.toml). That is a
//   correctly-positioned extra layer behind our guard — if it ever changed across a GoTrue
//   version, our (1)+(2) app-layer gate still holds the property. It is NOT the guarantee.
//   (The prior design exempted this route and let an aal1 MFA user reach the form, where that
//   GoTrue refusal surfaced as a silent generic-400 dead-end — the bug QA found. Removing the
//   exemption + the app-layer step-up gate is the fix; it no longer leans on GoTrue's refusal.)
//   · Lost-authenticator: an MFA user who also lost their authenticator is routed to
//     /mfa/step-up, which carries the /mfa/recover recovery-code escape (SELF-291). They
//     redeem a code (removing MFA), then complete the reset MFA-free.
//
// POST-RESET: signOut() the recovery session + redirect to /login?reset=success — forces a
// fresh sign-in with the new password (which, for MFA users, re-runs step-up on the next
// protected navigation). Identity is always the SESSION's, never the body (Decision-1);
// `.strict()` blocks a smuggled email/id.

import { fail, redirect } from '@sveltejs/kit';
import { resetPasswordSchema, fieldErrors } from '$lib/server/schemas/auth';
import { requireStepUp } from '$lib/server/auth/mfa';
import type { PageServerLoad, Actions } from './$types';

/** The step-up target for an MFA user (return here at aal2). Shared by hook + action shape. */
const STEP_UP_REDIRECT = `/mfa/step-up?redirectTo=${encodeURIComponent('/reset-password')}`;

export const load: PageServerLoad = async ({ locals }) => {
	const { user } = await locals.safeGetSession();
	// No recovery session (link expired, already consumed, or arrived here directly) → send
	// them back to request a fresh link. Generic; reveals nothing.
	if (!user) throw redirect(303, '/forgot-password?expired=1');
	// NOTE: an MFA user's aal1 GET was already redirected to /mfa/step-up by mfaHandle before
	// this load ran (route is non-exempt), so by here they are aal2-or-non-MFA. No AAL branch
	// needed in load — the hook owns the GET-path step-up decision.
	return { ready: true as const };
};

export const actions: Actions = {
	default: async ({ request, locals }) => {
		// Re-assert the recovery session at action time (defense-in-depth; the session could
		// have expired between load and submit). No user → cannot set a password.
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['Your reset link has expired. Please request a new one.'] } });

		// Input-shape fence FIRST (outermost): `.strict()` rejects a smuggled identity key
		// (id / users_id / email / user_metadata) with a 400 — the mass-assignment fence
		// (Lock 14 #2) — regardless of AAL. This ordering means a tampered body is rejected on
		// its own terms and never depends on the step-up branch below.
		const parsed = resetPasswordSchema.safeParse(Object.fromEntries(await request.formData()));
		if (!parsed.success) {
			return fail(400, { errors: fieldErrors(parsed.error) });
		}

		// aal2-for-MFA gate (Option A defense-in-depth). mfaHandle guards the GET render but
		// NOT this POST; re-run the SAME requireStepUp decision so an MFA user who is still
		// aal1 (scripted POST, or an aal2 that lapsed mid-flow) is funnelled to /mfa/step-up —
		// which carries the /mfa/recover lost-authenticator escape — instead of hitting
		// GoTrue's bare aal1 refusal. Fail-closed on indeterminate AAL. Non-MFA → 'allow'.
		if ((await requireStepUp(locals.supabase)) === 'step-up-required') {
			throw redirect(303, STEP_UP_REDIRECT);
		}

		// updateUser at aal2 (MFA users, stepped up above) or aal1 (non-MFA, no sensitive-op
		// gate). Sets the password ONLY — mints no aal2, changes no factor. Identity is the
		// SESSION's, never the body.
		const { error } = await locals.supabase.auth.updateUser({ password: parsed.data.password });
		if (error) {
			// Generic — do not echo GoTrue's message (may hint at policy/history internals). A
			// residual MFA-gate refusal (e.g. AAL raced) also lands here as a safe generic 400.
			return fail(400, { errors: { _form: ['Could not update your password. Please try again.'] } });
		}

		// Invalidate the one-purpose recovery session; force a fresh sign-in with the new
		// password (which, for MFA users, re-runs the aal2 step-up — the non-bypass proof).
		await locals.supabase.auth.signOut();
		throw redirect(303, '/login?reset=success');
	}
};
