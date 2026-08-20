// taxonomy.ts — shared server-side reads for the per-user storage-classification taxonomy
// (pfin.user_taxonomy, 009) and the per-user cashflow posting-prototype vocabulary
// (pfin.posting_prototype, 084 / ADR-058 Decision 1's asymmetric split). Backend-owned server
// surface. Factored so the accounts/new create picker and the accounts/[account_id]
// reassignment picker (SELF-236) use the SAME RLS-scoped query + label-flatten — the two
// pickers can never drift on ordering/shape.
//
// POST-084 SHAPE (ADR-058 Decision 1): `user_taxonomy` keeps its name/ids/asset rows and drops
// `domain` — it IS the storage-classification table now, unique (users_id, cat, sub_cat). The
// cashflow rows live in the new `posting_prototype`, same unique shape, own table entirely.
// There is no more "asset domain" / "cashflow domain" read of ONE table — asset reads stay on
// `user_taxonomy`, cashflow reads move to `posting_prototype`.

import type { SupabaseClient } from '@supabase/supabase-js';

// ── SELF-311 default-taxonomy first-access lazy provisioning (migration 041 / ADR-036 B1),
//    reworked at 084 (ADR-058 Decision 1) to provision BOTH the storage-classification table
//    (pfin.user_taxonomy, from pfin.taxonomy_default) and the posting-prototype table
//    (pfin.posting_prototype, from pfin.posting_prototype_default) — Sec F3, VETO-if-unpaired,
//    the named no-bundling exception riding the split migration's PR. ──

/** The column set `084` leaves on `taxonomy_default` / `posting_prototype_default` — both
 *  dropped `domain` in the same (symmetric) split (084 §4.4): cat/sub_cat/tax_relevant/
 *  tax_character/display_order/notes. `users_id` is NOT here — neither global default table has
 *  a tenant column; it is stamped app-side from the SESSION on both branches below.
 *  `is_active`/`created_at`/`updated_at`/`id` are all DB-defaulted on both per-user tables, so
 *  they are deliberately omitted from the insert, same as pre-084. */
type DefaultProvisionRow = {
	cat: string;
	sub_cat: string;
	tax_relevant: boolean;
	tax_character: string | null;
	display_order: number | null;
	notes: string | null;
};

const DEFAULT_PROVISION_COLUMNS =
	'cat, sub_cat, tax_relevant, tax_character, display_order, notes';

// ── ADR-058 Decision 3 (element PR) ── `element` lands on `pfin.user_taxonomy` AND
// `pfin.taxonomy_default` ONLY — NOT NULL, CHECK (element in ('asset','liability')) — and
// explicitly NEVER on `pfin.posting_prototype` / `pfin.posting_prototype_default` ("prototypes
// carry no element, not even a derived one"). That asymmetry is exactly the F3-class hazard the
// pre-existing shared `DefaultProvisionRow` / `DEFAULT_PROVISION_COLUMNS` would silently mis-cover
// if reused for both branches after this migration: `provisionAssetTaxonomy`'s column-listed
// INSERT would either omit the new NOT NULL column (blocks provisioning for every fresh signup —
// Decision 3's F4 finding) or, if a shared constant were widened to include `element`, the
// cashflow branch would ask `posting_prototype_default` for a column it does not have. The two
// branches therefore get their OWN column set from here on — this one for the asset/storage side.
type AssetDefaultProvisionRow = DefaultProvisionRow & { element: string };

const ASSET_DEFAULT_PROVISION_COLUMNS = `${DEFAULT_PROVISION_COLUMNS}, element`;

/**
 * Provision the caller's STORAGE-classification defaults: `pfin.user_taxonomy` from
 * `pfin.taxonomy_default`. One of the two INDEPENDENT branches `provisionDefaultTaxonomy` runs —
 * fail-soft entirely on its own, and its guard/read/upsert failing must never prevent the sibling
 * `provisionCashflowPrototypes` branch from running (Sec F3 condition (b): the existence guard
 * SPLITS PER TABLE, so a row on ONE table must never suppress provisioning on the OTHER — the
 * pre-084 single-table guard would otherwise mark a user who has storage rows but zero prototypes
 * as "already provisioned" and they would never get them).
 */
async function provisionAssetTaxonomy(supabase: SupabaseClient, userId: string): Promise<void> {
	try {
		// (1) Existence guard — RLS-scoped to the caller's own rows.
		const { data: existing, error: exErr } = await supabase
			.schema('pfin')
			.from('user_taxonomy')
			.select('id')
			.limit(1)
			.maybeSingle();
		if (exErr) {
			console.error(
				'[taxonomy] provisionAssetTaxonomy guard read failed (fail-soft):',
				exErr.message
			);
			return;
		}
		if (existing) return; // already provisioned — nothing to do.

		// (2) Read the global storage-side default set. ADR-058 Decision 3: `element` is selected
		// here (and ONLY here — the cashflow branch's `posting_prototype_default` never gains this
		// column) because it is now NOT NULL + CHECK-constrained on `taxonomy_default` itself, so
		// every row this read returns already carries a valid value — the app does no defaulting.
		const { data: defaults, error: dErr } = await supabase
			.schema('pfin')
			.from('taxonomy_default')
			.select(ASSET_DEFAULT_PROVISION_COLUMNS);
		if (dErr) {
			console.error(
				'[taxonomy] provisionAssetTaxonomy default read failed (fail-soft):',
				dErr.message
			);
			return;
		}
		if (!defaults || defaults.length === 0) return;

		// (3) UPSERT (DO NOTHING) with a session-derived users_id. `domain` is gone from the
		// unique key post-084 — the conflict target is (users_id, cat, sub_cat). `element` rides
		// along as an ordinary copied column (ADR-058 Decision 3) — it is not part of the conflict
		// target, which stays (users_id, cat, sub_cat) unchanged.
		const rows = (defaults as AssetDefaultProvisionRow[]).map((d) => ({ users_id: userId, ...d }));
		const { error: insErr } = await supabase
			.schema('pfin')
			.from('user_taxonomy')
			.upsert(rows, { onConflict: 'users_id,cat,sub_cat', ignoreDuplicates: true });
		if (insErr) {
			console.error(
				'[taxonomy] provisionAssetTaxonomy upsert failed (fail-soft):',
				insErr.message
			);
		}
	} catch (e) {
		// Defensive: even a thrown transport/client error must not break the page load, and must
		// not prevent the sibling branch from running (it isn't in this try/catch's scope).
		console.error(
			'[taxonomy] provisionAssetTaxonomy threw (fail-soft):',
			e instanceof Error ? e.message : String(e)
		);
	}
}

/**
 * Provision the caller's CASHFLOW posting-prototype defaults: `pfin.posting_prototype` from
 * `pfin.posting_prototype_default`. Sibling of `provisionAssetTaxonomy` — see its header for the
 * independence contract this mirrors verbatim (same guard/read/upsert shape, different table
 * pair, same fail-soft-per-branch discipline).
 */
async function provisionCashflowPrototypes(supabase: SupabaseClient, userId: string): Promise<void> {
	try {
		// (1) Existence guard — RLS-scoped to the caller's own rows. Deliberately a SEPARATE guard
		// read against `posting_prototype`, not a reuse of the asset-side guard's result — that is
		// the whole point of Sec F3 condition (b).
		const { data: existing, error: exErr } = await supabase
			.schema('pfin')
			.from('posting_prototype')
			.select('id')
			.limit(1)
			.maybeSingle();
		if (exErr) {
			console.error(
				'[taxonomy] provisionCashflowPrototypes guard read failed (fail-soft):',
				exErr.message
			);
			return;
		}
		if (existing) return; // already provisioned — nothing to do.

		// (2) Read the global cashflow-side default set.
		const { data: defaults, error: dErr } = await supabase
			.schema('pfin')
			.from('posting_prototype_default')
			.select(DEFAULT_PROVISION_COLUMNS);
		if (dErr) {
			console.error(
				'[taxonomy] provisionCashflowPrototypes default read failed (fail-soft):',
				dErr.message
			);
			return;
		}
		if (!defaults || defaults.length === 0) return;

		// (3) UPSERT (DO NOTHING) with a session-derived users_id. Conflict target (users_id, cat,
		// sub_cat) — `posting_prototype`'s unique shape per 084 §4.5.
		const rows = (defaults as DefaultProvisionRow[]).map((d) => ({ users_id: userId, ...d }));
		const { error: insErr } = await supabase
			.schema('pfin')
			.from('posting_prototype')
			.upsert(rows, { onConflict: 'users_id,cat,sub_cat', ignoreDuplicates: true });
		if (insErr) {
			console.error(
				'[taxonomy] provisionCashflowPrototypes upsert failed (fail-soft):',
				insErr.message
			);
		}
	} catch (e) {
		console.error(
			'[taxonomy] provisionCashflowPrototypes threw (fail-soft):',
			e instanceof Error ? e.message : String(e)
		);
	}
}

/**
 * Idempotently provision the caller's defaults on first access — BOTH the storage-classification
 * table AND the posting-prototype table (084 / ADR-058 Decision 1's asymmetric split; Sec F3,
 * VETO-if-unpaired, the named no-bundling exception). Runs the two independent branches above
 * SEQUENTIALLY, each with its OWN try/catch scope: neither branch's guard, read, upsert, or thrown
 * error can suppress or abort the other. This is the direct app-side answer to F3 condition (b) —
 * the pre-084 function had exactly ONE existence guard against `user_taxonomy` alone, which after
 * the split would silently stop a user who already has storage rows from ever receiving
 * posting-prototype rows.
 *
 * FAIL-SOFT by contract (like ensureUserSettings): a provisioning hiccup on EITHER branch must
 * NEVER throw or block the page load. On any error the caller sees an empty (or half-provisioned)
 * taxonomy that session — the SELF-200 no-taxonomy guard renders that gracefully — and each branch
 * self-heals independently on the next request (its own guard re-checks its own table). Errors are
 * logged per branch, never raised. The aal2-claused 041-shape INSERT policies still fully fence
 * both writes server-side.
 */
export async function provisionDefaultTaxonomy(
	supabase: SupabaseClient,
	userId: string
): Promise<void> {
	await provisionAssetTaxonomy(supabase, userId);
	await provisionCashflowPrototypes(supabase, userId);
}

export type SubCatOption = {
	id: number;
	cat: string;
	sub_cat: string;
	display_order: number | null;
	/** NOT NULL, CHECK-constrained ('asset' | 'liability') since migration 085 (ADR-058
	 *  Decision 3) — every row genuinely carries one, so this is a plain widening of an
	 *  already-shared read, not a per-consumer special case. Added for SELF-242/N7 (F/CTO
	 *  ruling, option A): the allocation editor filters to asset-element Sub-Cats client-side
	 *  (see PlanningTargetEditor.svelte) rather than this query gaining a second, driftable
	 *  copy. The `portfolio/classify` picker (the other consumer) ignores the extra field —
	 *  it spreads this array straight through to its own picker UI without exhaustive typing,
	 *  so widening here is inert there, not risky. */
	element: 'asset' | 'liability';
};

/**
 * Asset-domain (§2.2.1) Sub-Cat options for the caller, RLS-scoped via the per-request anon
 * client (user_taxonomy_select = auth.uid()). is_active hides retired rows. Returns [] on error
 * (logged) — the picker degrades, never throws.
 *
 * POST-084: `user_taxonomy` IS the storage-classification table now (no more `domain` column to
 * filter on) — every row here is asset-domain by construction, so the read is unconditional
 * beyond `is_active`. POST-085: also selects `element` — see SubCatOption's own comment for why.
 */
export async function loadAssetSubCats(supabase: SupabaseClient): Promise<SubCatOption[]> {
	const { data, error } = await supabase
		.schema('pfin')
		.from('user_taxonomy')
		.select('id, cat, sub_cat, display_order, element')
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
 * Cashflow (§2.4 / ADR-031 D3 class enum) Sub-Cat options for the caller, RLS-scoped. The
 * category picker for the manual cash-entry / edit / split surfaces (SELF-202). Same shape +
 * ordering as loadAssetSubCats.
 *
 * POST-084: reads `pfin.posting_prototype`, NOT `pfin.user_taxonomy` — the cashflow rows moved
 * tables at the split (ADR-058 Decision 1), so this is a different table, not a different filter
 * on the same one. `posting_prototype` carries its own `is_active` column (084 §4.5), so the
 * shape stays identical to loadAssetSubCats beyond the table name.
 */
export async function loadCashflowSubCats(supabase: SupabaseClient): Promise<SubCatOption[]> {
	const { data, error } = await supabase
		.schema('pfin')
		.from('posting_prototype')
		.select('id, cat, sub_cat, display_order')
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
 * ADR-013 H1 app-layer pre-validation for the SELF-235 classify/reassign write path: does
 * `subCatId` exist and belong to the CALLER? RLS-scoped (user_taxonomy_select = auth.uid()), so a
 * forged or cross-tenant id resolves to zero rows — existence and ownership collapse into one
 * check, same shape H1 asks for the §2.2 `%Target` keyed-array write ("the Sub-Cat key must be
 * validated against the seeded taxonomy — no forged/cross-tenant key"). is_active mirrors
 * loadAssetSubCats so a submitted id is only ever one the picker itself could have offered.
 *
 * POST-084: no `domain` filter — `user_taxonomy` is asset-only by construction now, so a
 * `posting_prototype` id (a DIFFERENT table's id-space per Decision 2) simply cannot resolve a
 * row here, which is a strictly STRONGER guarantee than the pre-084 `.eq('domain','asset')`
 * filter (that filter policed a column value on a shared table; table identity now does the same
 * job by construction and cannot be dropped by accident the way a `.eq()` clause can).
 *
 * DEFENSE-IN-DEPTH ONLY: this is checked BEFORE the write, never instead of the 022 DB fences
 * (fn_user_asset_category_matched_sub_cat / fn_user_asset_category_asset), which remain the
 * authoritative tenant boundary. Fail-closed on an unverifiable read (returns false) — an error
 * here must never be treated as "valid".
 */
export async function isAssignableAssetSubCat(
	supabase: SupabaseClient,
	subCatId: number
): Promise<boolean> {
	const { data, error } = await supabase
		.schema('pfin')
		.from('user_taxonomy')
		.select('id')
		.eq('id', subCatId)
		.eq('is_active', true)
		.maybeSingle();
	if (error) {
		console.error('[taxonomy] isAssignableAssetSubCat read failed (fail-closed):', error.message);
		return false;
	}
	return data !== null;
}

/**
 * Flatten an embedded `( cat, sub_cat )` join result to a label. Table-agnostic — used against
 * BOTH the `user_taxonomy` embed (asset-side callers, e.g. pendingSymbols.ts / SELF-235 pickers)
 * and the `posting_prototype` embed (cashflow-side callers, e.g. the account-detail transaction
 * list post-084 — 023/029's `sub_cat_id` FK re-targets there). supabase-js may type the FK embed
 * as a to-many array though this many-to-one FK returns a single object at runtime — normalize
 * both. NULL (untagged sub_cat_id) → { cat: null, sub_cat: 'Unsorted' } (mirrors the create
 * dropdown's Unsorted option).
 */
export function subCatLabel(embedded: unknown): { cat: string | null; sub_cat: string } {
	const one = Array.isArray(embedded) ? (embedded[0] ?? null) : (embedded ?? null);
	const label = one as { cat: string; sub_cat: string } | null;
	return { cat: label?.cat ?? null, sub_cat: label?.sub_cat ?? 'Unsorted' };
}
