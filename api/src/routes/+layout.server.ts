// +layout.server.ts — root layout server load (SELF-285).
// Backend-owned server source (ARCH §4.1 allowlist).
//
// Exposes ONLY the signed-in user's email to every page (for the header/sign-out
// affordance) — NEVER the full User object, which carries tokens, app_metadata,
// identities, and other fields that must not ship to the browser.
//
// NOTE (deliberate, follow-up flagged): protected page loads still run their OWN
// safeGetSession(), so a protected request performs a second getUser() (once here,
// once in the page load). A dedupe via `await parent()` in page loads is a possible
// optimization, but is intentionally NOT done here — keeping session resolution at
// the hooks chokepoint + each load's explicit guard preserves the ADR-015 posture.
// Left as a follow-up rather than folded in silently.

import { countPendingSymbols } from '$lib/server/queries/pendingSymbols';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ locals }) => {
	const { user } = await locals.safeGetSession();

	// SELF-200 (§2.4.1.e): pending-symbol count for the header badge. Computed at read time
	// (derived view — no stored count). Two cheap RLS-scoped selects, bounded by the caller's own
	// data; only for signed-in users (0 otherwise). Runs on every navigation — kept lean (no
	// asset-detail fetch; see pendingSymbols.countPendingSymbols).
	// FAIL-SOFT-TO-0 on a read error (deliberate — a layout load that threw would break every page).
	// The badge does NOT mask a page-level read failure: the classify page (loadPendingSymbols)
	// distinguishes error-vs-empty itself and surfaces a retriable error (SELF-200 Gap 1).
	const pendingClassificationCount = user ? await countPendingSymbols(locals.supabase) : 0;

	return { userEmail: user?.email ?? null, pendingClassificationCount };
};
