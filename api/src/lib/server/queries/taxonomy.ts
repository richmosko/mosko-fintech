// taxonomy.ts — shared server-side reads for the per-user Sub-Cat taxonomy (009).
// Backend-owned server surface. Factored so the accounts/new create picker and the
// accounts/[account_id] reassignment picker (SELF-236) use the SAME RLS-scoped query
// + label-flatten — the two pickers can never drift on domain/ordering/shape.

import type { SupabaseClient } from '@supabase/supabase-js';

// ── SELF-311 default-taxonomy first-access lazy provisioning (migration 041 / ADR-036 B1) ──

/** The exact column set the canonical 041 provision statement selects from pfin.taxonomy_default
 *  (the migration-header source of truth): domain/cat/sub_cat/tax_relevant/tax_character/
 *  display_order/notes. `users_id` is NOT here — the global default table has no tenant column;
 *  it is stamped app-side from the SESSION. `is_active`/`created_at`/`updated_at`/`id` are all
 *  DB-defaulted on user_taxonomy (009), so they are deliberately omitted from the insert. */
type TaxonomyDefaultRow = {
	domain: string;
	cat: string;
	sub_cat: string;
	tax_relevant: boolean;
	tax_character: string | null;
	display_order: number | null;
	notes: string | null;
};

const TAXONOMY_DEFAULT_COLUMNS =
	'domain, cat, sub_cat, tax_relevant, tax_character, display_order, notes';

/**
 * Idempotently provision the caller's default user_taxonomy on first access (migration 041 /
 * ADR-036 B1 — both domains in ONE pass). App-side implementation of the canonical 041
 * INSERT…SELECT (041 authors NO function, so the app runs it as authenticated SQL under the
 * user's OWN JWT via the per-request anon client — caller-RLS, no service_role, no DEFINER):
 *   1. Cheap EXISTENCE GUARD — `select id … limit 1`. If the caller already has ANY taxonomy
 *      row, skip (avoids a 63-row insert-attempt on every navigation). RLS scopes the read to
 *      auth.uid() (user_taxonomy_select), so no explicit users_id filter is needed.
 *   2. Read the 63-row global default set (pfin.taxonomy_default — authenticated `using(true)`).
 *   3. UPSERT the mapped rows with `users_id` from the SESSION (mass-assignment safe — NEVER the
 *      client) and `ignoreDuplicates: true` → INSERT … ON CONFLICT (users_id, domain, cat,
 *      sub_cat) DO NOTHING. Idempotent regardless of the guard (race-safe); the guard just
 *      avoids the per-nav insert-attempt cost.
 *
 * FAIL-SOFT by contract (like ensureUserSettings): a provisioning hiccup must NEVER throw or block
 * the page load. On any error the caller sees an empty taxonomy that session — the SELF-200
 * no-taxonomy guard renders that gracefully — and it self-heals on the next request. Errors are
 * logged, not raised. The aal2-claused 041 INSERT policy still fully fences the write server-side.
 */
export async function provisionDefaultTaxonomy(
	supabase: SupabaseClient,
	userId: string
): Promise<void> {
	try {
		// (1) Existence guard — RLS-scoped to the caller's own rows.
		const { data: existing, error: exErr } = await supabase
			.schema('pfin')
			.from('user_taxonomy')
			.select('id')
			.limit(1)
			.maybeSingle();
		if (exErr) {
			console.error('[taxonomy] provisionDefaultTaxonomy guard read failed (fail-soft):', exErr.message);
			return;
		}
		if (existing) return; // already provisioned — nothing to do.

		// (2) Read the global default set.
		const { data: defaults, error: dErr } = await supabase
			.schema('pfin')
			.from('taxonomy_default')
			.select(TAXONOMY_DEFAULT_COLUMNS);
		if (dErr) {
			console.error('[taxonomy] provisionDefaultTaxonomy default read failed (fail-soft):', dErr.message);
			return;
		}
		if (!defaults || defaults.length === 0) return;

		// (3) UPSERT (DO NOTHING) with a session-derived users_id.
		const rows = (defaults as TaxonomyDefaultRow[]).map((d) => ({ users_id: userId, ...d }));
		const { error: insErr } = await supabase
			.schema('pfin')
			.from('user_taxonomy')
			.upsert(rows, { onConflict: 'users_id,domain,cat,sub_cat', ignoreDuplicates: true });
		if (insErr) {
			console.error('[taxonomy] provisionDefaultTaxonomy upsert failed (fail-soft):', insErr.message);
		}
	} catch (e) {
		// Defensive: even a thrown transport/client error must not break the page load.
		console.error(
			'[taxonomy] provisionDefaultTaxonomy threw (fail-soft):',
			e instanceof Error ? e.message : String(e)
		);
	}
}

export type SubCatOption = {
	id: number;
	cat: string;
	sub_cat: string;
	display_order: number | null;
};

/**
 * Asset-domain (§2.2.1) Sub-Cat options for the caller, RLS-scoped via the
 * per-request anon client (user_taxonomy_select = auth.uid()). is_active hides
 * retired rows. Returns [] on error (logged) — the picker degrades, never throws.
 */
export async function loadAssetSubCats(supabase: SupabaseClient): Promise<SubCatOption[]> {
	const { data, error } = await supabase
		.schema('pfin')
		.from('user_taxonomy')
		.select('id, cat, sub_cat, display_order')
		.eq('domain', 'asset')
		.eq('is_active', true)
		.order('display_order', { ascending: true, nullsFirst: false })
		.order('cat', { ascending: true })
		.order('sub_cat', { ascending: true });

	if (error) {
		console.error('[taxonomy] loadAssetSubCats failed:', error.message);
		return [];
	}
	return (data ?? []) as SubCatOption[];
}

/**
 * Cashflow-domain (§2.4 / ADR-031 D3 class enum) Sub-Cat options for the caller, RLS-scoped.
 * The category picker for the manual cash-entry / edit / split surfaces (SELF-202). Same shape
 * + ordering as loadAssetSubCats; domain='cashflow' is the only difference. Returns [] on error.
 */
export async function loadCashflowSubCats(supabase: SupabaseClient): Promise<SubCatOption[]> {
	const { data, error } = await supabase
		.schema('pfin')
		.from('user_taxonomy')
		.select('id, cat, sub_cat, display_order')
		.eq('domain', 'cashflow')
		.eq('is_active', true)
		.order('display_order', { ascending: true, nullsFirst: false })
		.order('cat', { ascending: true })
		.order('sub_cat', { ascending: true });

	if (error) {
		console.error('[taxonomy] loadCashflowSubCats failed:', error.message);
		return [];
	}
	return (data ?? []) as SubCatOption[];
}

/**
 * Flatten an embedded `user_taxonomy ( cat, sub_cat )` join result to a label.
 * supabase-js may type the FK embed as a to-many array though this many-to-one FK
 * returns a single object at runtime — normalize both. NULL (untagged sub_cat_id) →
 * { cat: null, sub_cat: 'Unsorted' } (mirrors the create dropdown's Unsorted option).
 */
export function subCatLabel(embedded: unknown): { cat: string | null; sub_cat: string } {
	const one = Array.isArray(embedded) ? (embedded[0] ?? null) : (embedded ?? null);
	const label = one as { cat: string; sub_cat: string } | null;
	return { cat: label?.cat ?? null, sub_cat: label?.sub_cat ?? 'Unsorted' };
}
