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
//
// Fail loud, no coercion — matches loadTaxLiability's posture (taxLiability.ts module header).
// A failed fn_tax_authority_ledgers() call means AC 8(ii)'s empty-state flag cannot be trusted
// either way (true would wrongly show the CTA-suppressed table, false would wrongly hide the
// CTA), so this loader throws rather than guessing.

import { redirect } from '@sveltejs/kit';
import { loadTaxLiability } from '$lib/server/queries/taxLiability';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const liability = await loadTaxLiability(locals.supabase);

	const { data: designatedLedgers, error: ledgersErr } = await locals.supabase
		.schema('pfin')
		.rpc('fn_tax_authority_ledgers');

	if (ledgersErr) {
		throw new Error(
			`[taxes/quarterly] pfin.fn_tax_authority_ledgers read failed: ${ledgersErr.message}`
		);
	}

	return {
		liability,
		noTaxAuthorityDesignated: (designatedLedgers ?? []).length === 0
	};
};
