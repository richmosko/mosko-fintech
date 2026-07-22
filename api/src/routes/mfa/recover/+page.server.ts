// mfa/recover/+page.server.ts — MFA recovery via a one-time backup code (SELF-291 /
// Auth-3b Slice 2b, AC#4). Backend-owned server source (ARCH §4.1 allowlist).
//
// Reachable at aal1 (the hooks guard exempts the '/mfa' prefix) — a user who lost their
// authenticator is authenticated (password) but aal1 and cannot step up; this is their
// escape hatch. They redeem a backup code → the dead factor is removed + mfa_policy
// downgraded to 'none' (NO aal2 minted, ADR-030) → they re-enroll a fresh factor.
//
//  - load(): resolve the validated user (else /login). If they have no verified factor
//    (nothing to recover) or are already aal2, bounce to /settings/security.
//  - actions.redeem: Zod .strict() { code }; users_id is taken from the SESSION, never the
//    body. redeemRecoveryCode does the rate-gate + verify + atomic-consume + factor-removal
//    + downgrade + notify. 'ok' → re-enroll prompt; 'invalid' → 400; 'locked' → 429.
//
// The service_role work lives in mfa-recovery.ts (via the admin factory); this route holds
// NO service_role key (RT-26). Enumeration-safe: 'invalid' is generic.

import { fail, redirect } from '@sveltejs/kit';
import { fieldErrors } from '$lib/server/schemas/auth';
import { recoveryCodeSchema } from '$lib/server/schemas/mfa';
import { redeemRecoveryCode } from '$lib/server/auth/mfa-recovery';
import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const { data } = await locals.supabase.auth.mfa.getAuthenticatorAssuranceLevel();
	// Already stepped up, or no verified factor to recover from → nothing to do here.
	if (data?.currentLevel === 'aal2' || data?.nextLevel !== 'aal2') {
		throw redirect(303, '/settings/security');
	}
	return { mode: 'ready' as const };
};

export const actions: Actions = {
	redeem: async ({ request, locals }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const parsed = recoveryCodeSchema.safeParse(Object.fromEntries(await request.formData()));
		if (!parsed.success) {
			return fail(400, { errors: fieldErrors(parsed.error) });
		}

		// users_id is the VALIDATED-SESSION id — never the request body (Decision-1).
		const outcome = await redeemRecoveryCode(user.id, parsed.data.code, user.email);
		if (outcome === 'locked') {
			return fail(429, {
				errors: { _form: ['Too many attempts. Please wait an hour and try again.'] }
			});
		}
		if (outcome === 'invalid') {
			return fail(400, { errors: { _form: ['That recovery code is not valid.'] } });
		}

		// Recovered: no factor + mfa_policy='none' → /settings/security is reachable (guard
		// allows a no-factor user). Prompt a fresh enrollment.
		throw redirect(303, '/settings/security?recovered=1');
	}
};
