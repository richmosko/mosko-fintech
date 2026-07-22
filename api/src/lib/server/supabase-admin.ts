// supabase-admin.ts — THE sole SUPABASE_SERVICE_ROLE_KEY reference in api/src.
// Backend-owned server surface (ARCH §4.1 allowlist). SELF-291 / Auth-3b Slice 2b.
//
// ── RT-26: THE 4TH ALLOWLIST SURFACE (ADR-016 Decision 3) ────────────────────────
// This factory is the 4th (and first *actual*) RT-26 service_role surface in api/src —
// the anticipated `supabase-admin.ts` factory the allowlist registry pre-registered at
// its "Phase 5 factory-file question" note. It is the ONE audited key-home: every
// service_role call-site (MFA recovery — issuance/redemption/regenerate) imports
// `supabaseAdmin()` from HERE and references NO key itself, so the RT-26 grep fence
// (scripts/ci/fence-rt26-service-role-allowlist.sh) sees exactly ONE hit — this file —
// which matches the single new allowlist entry `api/src/lib/server/supabase-admin.ts`.
// Any other api/src file referencing the key trips the fence (fail-closed). Do NOT add a
// second key reference anywhere; add a call-site that imports this factory instead.
//
// ── Why service_role here (recovery is privileged BY CONSTRUCTION — ADR-030) ─────────
// The MB-1 guard (025) blocks an authenticated aal1 session from lowering mfa_policy out
// of the aal2-capable set; a recovering user IS authenticated + aal1 (lost authenticator)
// → only service_role/postgres are guard-exempt. CV-R1 = BLOCKED (aal1 self-unenroll of a
// verified factor 422s), so only the service_role admin API can remove the dead factor;
// and the 026/027 recovery tables are service_role-only. Tenant correctness for callers is
// bound IN CODE (an explicit users_id filter on every query — service_role is BYPASSRLS,
// so the WHERE is the tenant fence; Decision-1 code-side binding). users_id comes ONLY
// from the validated session, NEVER the request body.
//
// server-only: this module lives under src/lib/server/** — Vite refuses a browser import,
// and $env/dynamic/private never ships to the browser.

import { createClient, type SupabaseClient } from '@supabase/supabase-js';
// Server-only private env (never bundled to the browser) — the service_role key home.
import { env } from '$env/dynamic/private';
// Public config (URL) — same value the anon client uses.
import { env as pub } from '$env/dynamic/public';

// Memoized fail-loud env guard: validated at FIRST call (runtime, where the env is
// populated), not at module load (build time, where it is empty) — mirrors the
// hooks.server.ts supabaseEnv() pattern. Cached so the guard stays off the hot path.
let cached: SupabaseClient | null = null;

/**
 * The service_role Supabase client (BYPASSRLS + the 026/027 grants). Persisted sessions
 * are disabled — this client authenticates by the service_role key, not a user session.
 * NEVER expose its results without an explicit users_id filter (the WHERE is the tenant
 * fence under BYPASSRLS).
 */
export function supabaseAdmin(): SupabaseClient {
	if (cached) return cached;
	const url = pub.PUBLIC_SUPABASE_URL;
	const key = env.SUPABASE_SERVICE_ROLE_KEY;
	if (!url || !key) {
		throw new Error(
			'Missing PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY — set them in the container runtime env (see .env.example).'
		);
	}
	cached = createClient(url, key, {
		auth: { persistSession: false, autoRefreshToken: false }
	});
	return cached;
}
