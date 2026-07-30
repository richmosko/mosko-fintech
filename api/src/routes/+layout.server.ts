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
import { provisionDefaultTaxonomy } from '$lib/server/queries/taxonomy';
import { loadConnectionHealth } from '$lib/server/queries/connectionState';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ locals }) => {
	const { user } = await locals.safeGetSession();

	// SELF-311 (§ default-taxonomy-on-signup / migration 041 / ADR-036 B1): first-access lazy
	// provisioning of the caller's default user_taxonomy. Guarded (skips when already present) +
	// fail-soft (never blocks the load) — see provisionDefaultTaxonomy. Awaited BEFORE the page's
	// own taxonomy-consuming loads would ideally see it; note SvelteKit runs layout+page loads
	// concurrently, so the classify picker can be empty on the FIRST navigation and self-heal next
	// (also wired at the login/signup entry points so post-auth first access is never empty).
	if (user) await provisionDefaultTaxonomy(locals.supabase, user.id);

	// SELF-200 (§2.4.1.e): pending-symbol count for the header badge. Computed at read time
	// (derived view — no stored count). Two cheap RLS-scoped selects, bounded by the caller's own
	// data; only for signed-in users (0 otherwise). Runs on every navigation — kept lean (no
	// asset-detail fetch; see pendingSymbols.countPendingSymbols).
	// FAIL-SOFT-TO-0 on a read error (deliberate — a layout load that threw would break every page).
	// The badge does NOT mask a page-level read failure: the classify page (loadPendingSymbols)
	// distinguishes error-vs-empty itself and surfaces a retriable error (SELF-200 Gap 1).
	const pendingClassificationCount = user ? await countPendingSymbols(locals.supabase) : 0;

	// SELF-207 (§2.4.4.b): connection-health summary for the always-on P4 re-auth banner —
	// { reauthCount, institutionDownCount } over the caller's own connections (043 view).
	// Cheap (a handful of owner-scoped rows, like the pending count) + FAIL-SOFT-TO-{0,0}: a
	// layout load that threw would break every page. Only for signed-in users. The banner is a
	// summary; the /accounts/connections page surfaces any read error itself.
	const connectionHealth = user
		? await loadConnectionHealth(locals.supabase)
		: { reauthCount: 0, institutionDownCount: 0 };

	return { userEmail: user?.email ?? null, pendingClassificationCount, connectionHealth };
};
