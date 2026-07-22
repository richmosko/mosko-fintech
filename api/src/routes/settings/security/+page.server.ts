// settings/security/+page.server.ts — MFA (TOTP) security hub. SELF-291 / Auth-3b Slice 1.
// Backend-owned server source (ARCH §4.1 allowlist). AC#2 (enrollment) + the aal2-gated
// disable path + the derived-status load.
//
// This route is NOT step-up-exempt: the hooks guard governs it too. A user with a
// verified factor at aal1 is bounced to /mfa/step-up first (they must be aal2 to manage
// MFA — the disable action assumes aal2 and the DB MB-1 guard rejects otherwise). A user
// with NO verified factor is ALLOWED through (getAAL nextLevel !== 'aal2') so they can
// enroll — the natural, correct behaviour of the AAL-keyed guard.
//
// Enrollment (AC#2) is a two-step within this page:
//   1. enrollStart  — clean up any stale UNVERIFIED factor, mfa.enroll({totp}),
//                      return { qrCode, secret, uri, factorId } for the UI to render.
//   2. enrollVerify — challenge → verify; on success ensureUserSettings() THEN
//                      setMfaPolicy('totp') (N1 separate write, factor-before-policy).
//
// Disable (aal2-gated): setMfaPolicy('none') FIRST (lockout-safe ordering — never leave
// mfa_policy='totp' without a factor, N2b), THEN unenroll the verified factor(s).
//
// Slice 2b additions: recovery-code issuance is hooked into enrollVerify success
// (display-once), a regenerate action (aal2-gated), the unused-code count in the load,
// and notify-on-change at each MFA transition.
//
// The enroll/disable/step-up flows use the ANON+RLS client (the user's own JWT). The
// recovery-code issuance/regenerate helpers run service_role via the audited admin factory
// (supabase-admin.ts) — this route imports the helpers and holds NO service_role key
// itself (RT-26; the factory is the sole key-home). Zod `.strict()` on the code input.

import { fail, redirect } from '@sveltejs/kit';
import { fieldErrors } from '$lib/server/schemas/auth';
import { totpCodeSchema } from '$lib/server/schemas/mfa';
import { ensureUserSettings, setMfaPolicy } from '$lib/server/queries/userSettings';
import { getMfaStatus, getTotpFactors } from '$lib/server/auth/mfa';
import { issueRecoveryCodes, recoveryCodeStatus } from '$lib/server/auth/mfa-recovery';
import { notifyMfaChange } from '$lib/server/auth/mfa-notify';
import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const status = await getMfaStatus(locals.supabase);
	// Unused recovery-code count (service_role read — the table is not owner-readable).
	const recovery = status.hasVerifiedTotp
		? await recoveryCodeStatus(user.id)
		: { unused: 0 };
	return { status, recovery };
};

export const actions: Actions = {
	// ── AC#2 step 1: begin enrollment ──────────────────────────────────────────
	enrollStart: async ({ locals }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		// If a verified factor already exists, MFA is on — refuse a duplicate enroll
		// (the user should disable first). Guards against wedging a second factor.
		const { verifiedIds, unverifiedIds } = await getTotpFactors(locals.supabase);
		if (verifiedIds.length > 0) {
			return fail(400, {
				action: 'enrollStart',
				errors: { _form: ['Two-factor authentication is already enabled.'] }
			});
		}

		// Clean up stale UNVERIFIED factors from an abandoned enroll so they cannot wedge
		// a fresh enroll (do NOT touch verified factors — there are none here anyway).
		for (const id of unverifiedIds) {
			await locals.supabase.auth.mfa.unenroll({ factorId: id });
		}

		const { data, error } = await locals.supabase.auth.mfa.enroll({ factorType: 'totp' });
		if (error || !data) {
			return fail(400, {
				action: 'enrollStart',
				errors: { _form: ['Could not start enrollment. Please try again.'] }
			});
		}

		// The QR / secret / URI are the user's OWN enrollment material, shown once so they
		// can add the factor to their authenticator app. Returned to the page for render.
		return {
			action: 'enrollStart' as const,
			enroll: {
				factorId: data.id,
				qrCode: data.totp.qr_code,
				secret: data.totp.secret,
				uri: data.totp.uri
			}
		};
	},

	// ── AC#2 step 2: verify the code + flip mfa_policy → 'totp' ─────────────────
	enrollVerify: async ({ request, locals }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const form = await request.formData();
		// factorId is a control field (from enrollStart), not a credential — strip it
		// before .strict() so the mass-assignment fence sees only { code }.
		const factorId = form.get('factorId');
		const raw = Object.fromEntries(form);
		delete raw.factorId;

		const parsed = totpCodeSchema.safeParse(raw);
		if (typeof factorId !== 'string' || !factorId) {
			return fail(400, {
				action: 'enrollVerify',
				errors: { _form: ['Enrollment session expired. Please start again.'] }
			});
		}
		if (!parsed.success) {
			return fail(400, { action: 'enrollVerify', factorId, errors: fieldErrors(parsed.error) });
		}

		const { data: challenge, error: challengeError } =
			await locals.supabase.auth.mfa.challenge({ factorId });
		if (challengeError || !challenge) {
			return fail(400, {
				action: 'enrollVerify',
				factorId,
				errors: { _form: ['Could not verify the code. Please try again.'] }
			});
		}

		const { error: verifyError } = await locals.supabase.auth.mfa.verify({
			factorId,
			challengeId: challenge.id,
			code: parsed.data.code
		});
		if (verifyError) {
			return fail(400, {
				action: 'enrollVerify',
				factorId,
				errors: { _form: ['Invalid or expired code. Please try again.'] }
			});
		}

		// Factor is now VERIFIED and the session is aal2. Only NOW flip the declared
		// policy (N1 separate write; factor-before-policy so mfa_policy='totp' never
		// outlives a real factor). Ensure the row exists first (insert-or-nothing).
		await ensureUserSettings(locals.supabase, user.id);
		const ok = await setMfaPolicy(locals.supabase, user.id, 'totp');
		if (!ok) {
			// The factor IS verified (protection is live: the guard steps up via AAL, and
			// the DB backstop will enforce once the policy write lands). Surface a retry.
			return fail(500, {
				action: 'enrollVerify',
				errors: {
					_form: [
						'Two-factor authentication was verified but the setting could not be saved. Please retry.'
					]
				}
			});
		}

		// Fail-soft notify (never blocks the security op).
		await notifyMfaChange({ email: user.email, event: 'enrolled' });

		// Issue the display-once recovery-code batch. Returned to the page (NOT redirected —
		// a redirect cannot carry the plaintext, and the codes are shown exactly once). On
		// an issuance hiccup the enrollment still stands (protection is live); the user is
		// prompted to regenerate from settings.
		let recoveryCodes: string[] = [];
		let recoveryCodesError = false;
		try {
			recoveryCodes = await issueRecoveryCodes(user.id);
		} catch {
			recoveryCodesError = true;
		}
		return { action: 'enrollVerify' as const, enrolled: true, recoveryCodes, recoveryCodesError };
	},

	// ── aal2-gated disable: policy → 'none' THEN remove the factor(s) ───────────
	disable: async ({ locals }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		// Lockout-safe ordering (N2b): downgrade the declared policy FIRST. If the DB
		// MB-1 guard rejects it (aal1 → 42501), we stop here — the factor is untouched and
		// the user is still fully protected. Only after the policy is 'none' do we remove
		// the factor, so we never reach (no factor + mfa_policy='totp').
		await ensureUserSettings(locals.supabase, user.id);
		const ok = await setMfaPolicy(locals.supabase, user.id, 'none');
		if (!ok) {
			return fail(403, {
				action: 'disable',
				errors: {
					_form: [
						'Disabling two-factor authentication requires a freshly verified session. Please step up and try again.'
					]
				}
			});
		}

		// Remove the verified factor(s) so GoTrue AAL drops to aal1 (else the guard would
		// keep stepping the user up on a stale factor — N2a).
		const { verifiedIds } = await getTotpFactors(locals.supabase);
		for (const id of verifiedIds) {
			await locals.supabase.auth.mfa.unenroll({ factorId: id });
		}

		// Fail-soft notify (never blocks the security op).
		await notifyMfaChange({ email: user.email, event: 'disabled' });

		throw redirect(303, '/settings/security');
	},

	// ── aal2-gated: regenerate the recovery-code batch (supersedes the old) ─────
	regenerateRecoveryCodes: async ({ locals }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		// aal2-gate in code: this is a sensitive self-service op. The GET guard already
		// steps a totp user up before they reach this page, but the POST is not guarded —
		// so re-assert current aal2 here (defense-in-depth; the DB has no backstop on the
		// service_role issuance path).
		const { data: aal } = await locals.supabase.auth.mfa.getAuthenticatorAssuranceLevel();
		if (aal?.currentLevel !== 'aal2') {
			return fail(403, {
				action: 'regenerateRecoveryCodes',
				errors: {
					_form: ['Regenerating recovery codes requires a freshly verified session. Please step up and try again.']
				}
			});
		}

		let recoveryCodes: string[] = [];
		try {
			recoveryCodes = await issueRecoveryCodes(user.id);
		} catch {
			return fail(500, {
				action: 'regenerateRecoveryCodes',
				errors: { _form: ['Could not regenerate recovery codes. Please try again.'] }
			});
		}
		// Fail-soft notify.
		await notifyMfaChange({ email: user.email, event: 'regenerated' });
		return { action: 'regenerateRecoveryCodes' as const, recoveryCodes };
	}
};
