// taxes/quarterly/+page.server.ts — loader for the §2.5.3 two parallel quarterly
// estimated-tax tables (SELF-266). Backend-owned server source (ARCH §4.1 allowlist).
// Frontend's +page.svelte is the sole consumer of this loader's `data` shape. NO actions —
// this surface has no inline edit (V2+, ADR-013 P5); the "Edit tax brackets" button routes
// client-side to /settings/tax-brackets (SELF-265) and this file writes nothing.
//
// SHAPE:
//   liability                  : loadTaxLiability(supabase)'s TaxLiabilityPayload, VERBATIM —
//                                 no reshaping. The page reads `liability.jurisdictions.federal`
//                                 / `.california` for the two tables and `liability.prior_year_
//                                 q4_window` for AC 2a's render window (the R8 boundary is
//                                 computed ONCE inside fn_compute_tax_liability and cited here,
//                                 never re-derived — ADR-067 Decision 5(f)).
//   noTaxAuthorityDesignated   : AC 8(ii)'s empty-state flag — true when the caller has marked
//                                 NO account as a tax-authority ledger for EITHER jurisdiction
//                                 (pfin.account.tax_jurisdiction is null on every row). Measured
//                                 via pfin.fn_tax_authority_ledgers() (102) — the SINGLE home of
//                                 the `tax_jurisdiction is not null` predicate (its own `comment
//                                 on function`: "ANY further consumer... MUST call this function
//                                 rather than restate the predicate") — rather than a second
//                                 RLS-scoped select against pfin.account that would be a second
//                                 copy of that predicate. An EMPTY result from that function is
//                                 the ordinary state for a user who has designated nothing, and
//                                 that is exactly this flag's meaning: this loader states what
//                                 empty means for this caller, per that function's own contract.
//                                 The CTA target (the §2.4.2 account form's tax-authority field)
//                                 is the page's concern, not this loader's.
//   priorYearQ4                 : E39 (R8 (B)) — the prior tax year's Q4 row WITH AMOUNTS, or
//                                 `null` when `liability.prior_year_q4_window.open` is false. 104's
//                                 own payload computes that window for the CURRENT as-of only (open
//                                 / tax_year / due_date, no amounts); the amounts need a SECOND
//                                 fn_compute_tax_liability call, as-of Dec 31 of the prior tax year
//                                 (loadPriorYearQ4 — taxLiability.ts). Called ONLY when the window
//                                 is open, and the as-of it builds CITES the current payload's own
//                                 `prior_year_q4_window.tax_year` rather than deriving a second one
//                                 — no client input reaches it, so AC 8a still holds. Kept as its
//                                 OWN typed value, never merged into `liability` (ruled at E39).
//
// Fail loud, no coercion — matches loadTaxLiability's posture (taxLiability.ts module header).
// A failed fn_tax_authority_ledgers() call means AC 8(ii)'s empty-state flag cannot be trusted
// either way (true would wrongly show the CTA-suppressed table, false would wrongly hide the
// CTA), so this loader throws rather than guessing. Same posture for loadPriorYearQ4 — the prior-
// year Q4 row is still primary content while its window is open, not a degradable extra.
//
// STALENESS (SELF-361 / P9 AC1/AC2): `staleness: StalenessData` — the SAME whole-tenant
// `loadStaleness()` read every other V1.1+ NAV/composition surface consumes
// (`fn_aggregation_has_stale_constituent()` takes NO per-surface argument), mirroring root
// `+page.server.ts` / `allocation/+page.server.ts`'s own try/catch + degrade-to-UNKNOWN posture
// byte-for-byte. Belt-and-suspenders try/catch around `loadStaleness` itself (which already
// degrades an RPC error internally) for an unexpected throw — same non-fail-loud posture as
// `taxes/decomposition`'s own staleness read, distinct from this file's OTHER two reads
// (`fn_tax_authority_ledgers` / `loadPriorYearQ4`), which stay fail-loud per this file's own
// header above.

import { redirect } from '@sveltejs/kit';
import { loadTaxLiability, loadPriorYearQ4 } from '$lib/server/queries/taxLiability';
import { loadStaleness } from '$lib/server/queries/staleness';
import { UNKNOWN_STALENESS } from '$lib/staleness/stale-constituent';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const liability = await loadTaxLiability(locals.supabase);

	let staleness = UNKNOWN_STALENESS;
	try {
		staleness = await loadStaleness(locals.supabase);
	} catch (err) {
		console.error('[taxes/quarterly] staleness load threw; degrading to unknown staleness:', err);
		staleness = UNKNOWN_STALENESS;
	}

	const { data: designatedLedgers, error: ledgersErr } = await locals.supabase
		.schema('pfin')
		.rpc('fn_tax_authority_ledgers');

	if (ledgersErr) {
		throw new Error(
			`[taxes/quarterly] pfin.fn_tax_authority_ledgers read failed: ${ledgersErr.message}`
		);
	}

	const priorYearQ4 = liability.prior_year_q4_window.open
		? await loadPriorYearQ4(locals.supabase, liability.prior_year_q4_window)
		: null;

	return {
		liability,
		noTaxAuthorityDesignated: (designatedLedgers ?? []).length === 0,
		priorYearQ4,
		staleness
	};
};
