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

// ── 091 / ADR-062 Decision 6 (is_tax_payment PR) ── `is_tax_payment` lands on
// `pfin.posting_prototype` AND `pfin.posting_prototype_default` ONLY — `boolean not null`, NO
// DEFAULT — and explicitly NEVER on `pfin.user_taxonomy` / `pfin.taxonomy_default` (tax-payment-
// ness is a posting-prototype property; the storage side carries no cash-flow rows to mark).
// Same F3-class hazard as `element` above, mirrored: the shared `DefaultProvisionRow` /
// `DEFAULT_PROVISION_COLUMNS` must NOT be widened in place, because `is_tax_payment` is NOT NULL
// with no DEFAULT — an unwidened cashflow column list means the INSERT below is missing a
// required column and the fail-soft branch silently returns zero cash-flow prototypes for every
// fresh signup (ADR-062 Decision 6's named hazard, the same shape as the 085 `element` incident).
// The cashflow branch therefore gets its OWN column set from here on, mirroring the asset branch's
// pattern exactly; the asset branch's column set above is untouched.
type CashflowDefaultProvisionRow = DefaultProvisionRow & { is_tax_payment: boolean };

const CASHFLOW_DEFAULT_PROVISION_COLUMNS = `${DEFAULT_PROVISION_COLUMNS}, is_tax_payment`;

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

		// (2) Read the global cashflow-side default set. 091 / ADR-062 Decision 6: `is_tax_payment`
		// is selected here (and ONLY here — the asset branch's `taxonomy_default` never gains this
		// column) because it is NOT NULL on `posting_prototype_default` itself with every row
		// carrying a valid value already — the app carries it verbatim, it does not synthesize it.
		const { data: defaults, error: dErr } = await supabase
			.schema('pfin')
			.from('posting_prototype_default')
			.select(CASHFLOW_DEFAULT_PROVISION_COLUMNS);
		if (dErr) {
			console.error(
				'[taxonomy] provisionCashflowPrototypes default read failed (fail-soft):',
				dErr.message
			);
			return;
		}
		if (!defaults || defaults.length === 0) return;

		// (3) UPSERT (DO NOTHING) with a session-derived users_id. Conflict target (users_id, cat,
		// sub_cat) — `posting_prototype`'s unique shape per 084 §4.5. `is_tax_payment` rides along
		// as an ordinary copied column (ADR-062 Decision 6) — not part of the conflict target.
		const rows = (defaults as CashflowDefaultProvisionRow[]).map((d) => ({ users_id: userId, ...d }));
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
 * Provision the caller's SELF-260 tax bracket schedules via `pfin.fn_provision_tax_brackets()`
 * (migration 103) — a THIRD, independent sibling of `provisionAssetTaxonomy` /
 * `provisionCashflowPrototypes`, called after both from `provisionDefaultTaxonomy` below (same
 * fail-soft-per-branch discipline: this branch's failure must never suppress, retry, or be
 * suppressed by, either taxonomy branch).
 *
 * UNLIKE the two siblings, there is NO app-side existence guard and NO default-read/upsert pair
 * here — `fn_provision_tax_brackets()` IS the guard (existence-guarded per schedule KEY inside the
 * function, `on conflict do nothing`, migration 103 comment). Adding an app-side pre-check here
 * would just be a second, driftable copy of that guard for no gain — the function is SECURITY
 * INVOKER, takes NO tenant parameter (users_id comes from `auth.uid()` inside the function, same
 * as the RLS this call already runs under), so a single RPC call is the whole operation.
 *
 * The function returns the number of SCHEDULES it created (3 on a fresh caller, 0 if all three
 * already existed) — logged at debug level (not error) so a support reader can tell "provisioned
 * just now" from "already had them" without a second read, while a genuine RPC error still logs at
 * error level and the branch degrades exactly like its siblings (never throws, never blocks the
 * page load; the caller retries next request via the function's own guard).
 */
async function provisionTaxBrackets(supabase: SupabaseClient): Promise<void> {
	try {
		const { data, error } = await supabase.schema('pfin').rpc('fn_provision_tax_brackets');
		if (error) {
			console.error('[taxonomy] provisionTaxBrackets rpc failed (fail-soft):', error.message);
			return;
		}
		if (data === 0) {
			console.debug('[taxonomy] provisionTaxBrackets: caller already had all schedules');
		} else {
			console.debug(`[taxonomy] provisionTaxBrackets: provisioned ${data} schedule(s) now`);
		}
	} catch (e) {
		console.error(
			'[taxonomy] provisionTaxBrackets threw (fail-soft):',
			e instanceof Error ? e.message : String(e)
		);
	}
}

/**
 * Idempotently provision the caller's defaults on first access — the storage-classification
 * table, the posting-prototype table (084 / ADR-058 Decision 1's asymmetric split; Sec F3,
 * VETO-if-unpaired, the named no-bundling exception), AND the SELF-260 tax bracket schedules
 * (migration 103). Runs the three independent branches above SEQUENTIALLY, in that order —
 * taxonomy → cashflow prototypes → tax brackets — each with its OWN try/catch scope: no branch's
 * guard, read, write, or thrown error can suppress or abort another. This is the direct app-side
 * answer to F3 condition (b) — the pre-084 function had exactly ONE existence guard against
 * `user_taxonomy` alone, which after the split would silently stop a user who already has storage
 * rows from ever receiving posting-prototype rows; the same independence now extends to the tax
 * bracket branch, which has no guard of its own to share in the first place.
 *
 * FAIL-SOFT by contract (like ensureUserSettings): a provisioning hiccup on ANY branch must
 * NEVER throw or block the page load. On any error the caller sees an empty (or partially
 * provisioned) taxonomy/schedule set that session — the SELF-200 no-taxonomy guard renders that
 * gracefully — and each branch self-heals independently on the next request (its own guard
 * re-checks its own table, or — for tax brackets — the DB function's own per-schedule
 * existence guard re-runs). Errors are logged per branch, never raised. The aal2-claused
 * 041-shape INSERT policies still fully fence both taxonomy writes server-side, and the 025
 * aal2 backstop fences the tax-bracket writes the same way, INSIDE the SECURITY INVOKER function.
 */
export async function provisionDefaultTaxonomy(
	supabase: SupabaseClient,
	userId: string
): Promise<void> {
	await provisionAssetTaxonomy(supabase, userId);
	await provisionCashflowPrototypes(supabase, userId);
	await provisionTaxBrackets(supabase);
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
 * SELF-325 (088) — the caller's default 'Trade'/'BTO' posting_prototype id, for the manual
 * purchase-path's `p_sub_cat_id`. 088 deliberately does NOT default this itself ("selecting a
 * per-user taxonomy row is the app layer's to do" — single-authority rule, same reason 016's
 * asset_type vocab stays out of 087's body). RLS-scoped (posting_prototype_select = auth.uid()),
 * so a cross-tenant row can never resolve here. Every user gets a 'Trade'/'BTO' row at
 * first-access provisioning (041 taxonomy_default seed, provisionCashflowPrototypes above) — but
 * this is a best-effort DEFAULT, not a guarantee: a user who has renamed/deactivated it, or whose
 * provisioning hasn't run yet, gets `null` back, and the caller passes that straight through as
 * `p_sub_cat_id` (NULL/Unsorted-pending — 088's own fallback, not an error condition).
 */
export async function findDefaultBtoSubCatId(supabase: SupabaseClient): Promise<number | null> {
	const { data, error } = await supabase
		.schema('pfin')
		.from('posting_prototype')
		.select('id')
		.eq('cat', 'Trade')
		.eq('sub_cat', 'BTO')
		.eq('is_active', true)
		.maybeSingle();
	if (error) {
		console.error('[taxonomy] findDefaultBtoSubCatId read failed (falls back to Unsorted-pending):', error.message);
		return null;
	}
	return (data?.id as number | undefined) ?? null;
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
