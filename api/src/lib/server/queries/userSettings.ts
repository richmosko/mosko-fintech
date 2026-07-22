// userSettings.ts — server-side helpers for pfin.user_settings (SELF-286 / Auth-3 substrate).
// Backend-owned server surface (ARCH §4.1 allowlist).
//
// pfin.user_settings (migration 024): ONE row per user, PK = users_id (the tenant
// anchor itself, DEFAULT auth.uid()); `mfa_policy text NOT NULL DEFAULT 'none' CHECK
// IN ('none','totp','passkey')`. Owner-only RLS (users_id = auth.uid()); authenticated
// holds SELECT/INSERT/UPDATE (a LIVE write path); NO DELETE, NO service_role. The app
// writes under the user's OWN JWT via the per-request anon client — NEVER service_role
// (RT-26 / Lock 11). Provisioning is LAZY app-upsert (ratified D3), NOT an on-signup
// SECURITY DEFINER trigger — which is why the DEFINER allowlist stays at 3.

import type { SupabaseClient } from '@supabase/supabase-js';

/** The ratified per-user MFA choice domain (024 CHECK). email-2FA was dropped. */
export type MfaPolicy = 'none' | 'totp' | 'passkey';

/**
 * Idempotently ensure the caller's own user_settings row exists. Lazy provisioning
 * (ratified D3): an RLS-scoped upsert under the user's own JWT — `users_id` also
 * DEFAULTs to auth.uid() in the DDL, but we pass it explicitly for a stable onConflict
 * target. `ignoreDuplicates: true` makes a re-run a no-op (INSERT ... ON CONFLICT DO
 * NOTHING), so calling this on every successful auth is cheap + self-healing.
 *
 * FAIL-SOFT by contract: a provisioning hiccup must NEVER throw or block login — the
 * row self-heals on the next request, and a missing row reads as 'none' anyway (the
 * universal tenant RLS still fully fences the user). Errors are logged, not raised.
 */
export async function ensureUserSettings(supabase: SupabaseClient, userId: string): Promise<void> {
	try {
		const { error } = await supabase
			.schema('pfin')
			.from('user_settings')
			.upsert({ users_id: userId }, { onConflict: 'users_id', ignoreDuplicates: true });
		if (error) {
			console.error('[userSettings] ensureUserSettings upsert failed (fail-soft):', error.message);
		}
	} catch (e) {
		// Defensive: even a thrown transport/client error must not block the auth flow.
		console.error(
			'[userSettings] ensureUserSettings threw (fail-soft):',
			e instanceof Error ? e.message : String(e)
		);
	}
}

/**
 * Read the caller's own mfa_policy, RLS-scoped to auth.uid(). A MISSING row (never
 * provisioned) or ANY read error resolves to the DEFAULT 'none' — a user who has not
 * chosen a factor is not force-stepped-up here.
 *
 * NOTE: this substrate helper only REPORTS the policy. The fail-CLOSED
 * "missing ⇒ requires-step-up" GUARD semantics belong to Auth-3b (SELF-291) — do not
 * bake a step-up decision into this read.
 */
export async function getMfaPolicy(supabase: SupabaseClient): Promise<MfaPolicy> {
	try {
		const { data, error } = await supabase
			.schema('pfin')
			.from('user_settings')
			.select('mfa_policy')
			.maybeSingle();
		if (error) {
			console.error('[userSettings] getMfaPolicy read failed → default none:', error.message);
			return 'none';
		}
		return (data?.mfa_policy as MfaPolicy | undefined) ?? 'none';
	} catch (e) {
		console.error(
			'[userSettings] getMfaPolicy threw → default none:',
			e instanceof Error ? e.message : String(e)
		);
		return 'none';
	}
}

/**
 * N1 SEPARATE-WRITE (Auth-3b / SELF-291): explicitly UPDATE **only** the mfa_policy
 * column, RLS-scoped to the caller's own row (users_id = auth.uid()). This is the
 * enrollment/removal policy transition — deliberately NOT an upsert: ensureUserSettings
 * owns row creation (insert-or-nothing, no-clobber), and this owns the policy value.
 * Merging the two writes would risk clobbering other columns / resetting the policy —
 * so callers MUST `ensureUserSettings()` first (row exists), then call this.
 *
 * Write-ordering invariant (N2b lockout prevention): mfa_policy is set to 'totp' ONLY
 * AFTER a factor is verified, and set to 'none' BEFORE a verified factor is removed —
 * so `mfa_policy = 'totp'` never outlives a real factor. Callers enforce the ordering.
 *
 * NOT fail-soft: returns `false` (and logs) on any error so the caller can react (tell
 * the user to retry). In particular the MB-1 DB guard (025) REJECTS a 'totp'->'none'
 * downgrade at aal1 with SQLSTATE 42501 — that surfaces here as `false` (disable
 * requires an aal2 session).
 */
export async function setMfaPolicy(
	supabase: SupabaseClient,
	userId: string,
	policy: MfaPolicy
): Promise<boolean> {
	try {
		const { error } = await supabase
			.schema('pfin')
			.from('user_settings')
			.update({ mfa_policy: policy })
			.eq('users_id', userId);
		if (error) {
			console.error('[userSettings] setMfaPolicy update failed:', error.message);
			return false;
		}
		return true;
	} catch (e) {
		console.error(
			'[userSettings] setMfaPolicy threw:',
			e instanceof Error ? e.message : String(e)
		);
		return false;
	}
}
