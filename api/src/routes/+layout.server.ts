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

import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ locals }) => {
	const { user } = await locals.safeGetSession();
	return { userEmail: user?.email ?? null };
};
