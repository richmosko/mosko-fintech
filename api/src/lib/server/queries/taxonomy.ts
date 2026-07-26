// taxonomy.ts — shared server-side reads for the per-user Sub-Cat taxonomy (009).
// Backend-owned server surface. Factored so the accounts/new create picker and the
// accounts/[account_id] reassignment picker (SELF-236) use the SAME RLS-scoped query
// + label-flatten — the two pickers can never drift on domain/ordering/shape.

import type { SupabaseClient } from '@supabase/supabase-js';

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
