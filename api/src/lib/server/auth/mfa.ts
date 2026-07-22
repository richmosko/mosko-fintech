// mfa.ts — server-side MFA (TOTP) reconciliation + step-up decision helpers.
// Backend-owned server surface (ARCH §4.1 allowlist). SELF-291 / Auth-3b Slice 1.
//
// Two records of "does this user use MFA" exist after Auth-3 (design-spec §4):
//   1. GoTrue's enrolled/verified FACTORS — the source of truth for "a factor is
//      verified" (it drives the session's AAL). Reachable via supabase.auth.mfa.*.
//   2. pfin.user_settings.mfa_policy — the user's DECLARED posture + the 025 DB
//      backstop's control variable. Reachable via userSettings.ts.
//
// N2 RECONCILIATION RULE (design-spec §4): GoTrue's verified-factor state (AAL) is
// the SOURCE OF TRUTH for enforcement; mfa_policy mirrors it via two transition
// points (enroll → 'totp'; remove → 'none'). The step-up GUARD keys off AAL, NOT the
// stored policy — so a self-enrolled-via-API factor with a stale mfa_policy='none'
// (N2a) still steps up, and mfa_policy='totp' is only ever written AFTER a factor is
// verified (N2b lockout prevented at the write ordering; see security/+page.server.ts).
//
// N3 (design-spec §4): the guard read here is FAIL-CLOSED — distinct from the
// fail-SOFT getMfaPolicy() reporter in userSettings.ts. Any error / indeterminate /
// missing AAL state ⇒ requires-step-up (block). This is defense-in-depth OVER the DB
// backstop (025, the real enforcer on the direct PostgREST data API), never a
// replacement for it.
//
// Anon+RLS client only — NEVER service_role (RT-26 / Lock 11). No DB writes here; the
// mfa_policy transition writes live in userSettings.setMfaPolicy (N1 separate update).

import type { SupabaseClient } from '@supabase/supabase-js';
import { getMfaPolicy, type MfaPolicy } from '$lib/server/queries/userSettings';

/** GoTrue assurance levels as reported by getAuthenticatorAssuranceLevel(). */
export type AalLevel = 'aal1' | 'aal2' | null;

/** The step-up guard's verdict. */
export type StepUpDecision = 'step-up-required' | 'allow';

/**
 * FAIL-CLOSED step-up decision (N3). Keyed off GoTrue's AAL — the reconciled source
 * of truth for "a verified factor exists" (N2). Returns 'step-up-required' when:
 *   - getAuthenticatorAssuranceLevel() errors or returns no data (indeterminate);
 *   - either level is null (indeterminate);
 *   - a verified factor exists (nextLevel === 'aal2') but the session has not stepped
 *     up (currentLevel !== 'aal2') — this covers N2a (factor present even if
 *     mfa_policy is a stale 'none').
 * Otherwise 'allow' (no verified factor, or already aal2). A thrown transport error is
 * also treated as requires-step-up. NEVER falls through to allow on an unknown state.
 */
export async function requireStepUp(supabase: SupabaseClient): Promise<StepUpDecision> {
	try {
		const { data, error } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
		if (error || !data) return 'step-up-required'; // indeterminate ⇒ fail CLOSED
		const currentLevel = data.currentLevel as AalLevel;
		const nextLevel = data.nextLevel as AalLevel;
		if (currentLevel == null || nextLevel == null) return 'step-up-required'; // fail CLOSED
		// A verified factor exists but the session is not stepped up.
		if (nextLevel === 'aal2' && currentLevel !== 'aal2') return 'step-up-required';
		return 'allow';
	} catch {
		return 'step-up-required'; // any throw ⇒ fail CLOSED
	}
}

/** A user's TOTP factors partitioned by verification status. */
export interface TotpFactors {
	verifiedIds: string[];
	unverifiedIds: string[];
}

/**
 * List the caller's TOTP factor ids, partitioned verified vs unverified. Reads
 * GoTrue's own factor list (the AAL source of truth). Returns empty arrays on error —
 * callers treat "can't list" conservatively (enrollStart refuses to assume no verified
 * factor; the display just shows MFA-off, which the guard/DB backstop still enforce).
 */
export async function getTotpFactors(supabase: SupabaseClient): Promise<TotpFactors> {
	const { data, error } = await supabase.auth.mfa.listFactors();
	if (error || !data) {
		return { verifiedIds: [], unverifiedIds: [] };
	}
	const totp = data.totp ?? [];
	return {
		verifiedIds: totp.filter((f) => f.status === 'verified').map((f) => f.id),
		unverifiedIds: totp.filter((f) => f.status !== 'verified').map((f) => f.id)
	};
}

/** Derived MFA status for the security-settings page load (display-only, fail-soft). */
export interface MfaStatus {
	/** A verified TOTP factor exists (GoTrue AAL truth) — MFA is really ON. */
	hasVerifiedTotp: boolean;
	verifiedTotpFactorIds: string[];
	currentLevel: AalLevel;
	nextLevel: AalLevel;
	/** The DECLARED posture (display only — never the gate; the guard uses AAL). */
	mfaPolicy: MfaPolicy;
}

/**
 * Resolve the caller's MFA status for the security page. Display-only ⇒ fail-soft:
 * a read hiccup collapses to the safe "MFA off" shape (the DB backstop + the guard
 * remain the real enforcers regardless of what this render shows).
 */
export async function getMfaStatus(supabase: SupabaseClient): Promise<MfaStatus> {
	const [factors, aal, mfaPolicy] = await Promise.all([
		getTotpFactors(supabase),
		supabase.auth.mfa.getAuthenticatorAssuranceLevel(),
		getMfaPolicy(supabase)
	]);
	return {
		hasVerifiedTotp: factors.verifiedIds.length > 0,
		verifiedTotpFactorIds: factors.verifiedIds,
		currentLevel: (aal.data?.currentLevel ?? null) as AalLevel,
		nextLevel: (aal.data?.nextLevel ?? null) as AalLevel,
		mfaPolicy
	};
}
