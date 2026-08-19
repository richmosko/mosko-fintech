// classify.server.test.ts — QA app-layer coverage for the SELF-200 (§2.4.1.e) classify action
// error-surface mapping, extended at SELF-235 (§2.2.1.b) for the ADR-013 H1 pre-validation gate.
// Pure-TS server test (node env per vitest.config). No DB / no Plaid — mocks the supabase-js
// upsert chain + the session, exactly the netWorth.test.ts pattern.
//
// SCOPE (distinct from the pgTAP battery + Backend's pure-logic test):
//   - supabase/tests/rls/self200_pending_symbol_classification_rls.sql proves the DB fences
//     (#8/#9) + derived-read isolation end-to-end under RLS — the SECURITY teeth.
//   - pendingSymbols.test.ts proves the derived-set anti-join (computePendingIds).
//   - THIS locks the app-layer contract the DB battery can't see: that a 022 fence RAISE
//     (which arrives as an upsert error MESSAGE) is mapped to the correct FIELD-scoped
//     fail() — cross-tenant Sub-Cat → `sub_cat_id`, cross-tenant asset → `asset_id`, and
//     an unrecognized DB error degrades SAFELY to the generic `_form` 422 (fails closed, no
//     leak). The mapping is a string→field coupling to Architect's migration raise prefixes;
//     this is its regression fence. Teeth: cases 1/2 assert the OTHER field is absent, so a
//     swapped/broken mapping flips the test RED.
//   - ALSO locks the ADR-013 H1 pre-validation gate (isAssignableAssetSubCat): a sub_cat_id the
//     pre-check can't confirm (domain-mismatched, cross-tenant, or an unverifiable read) is
//     rejected 403 BEFORE the upsert is ever attempted — this is the ONLY app-side enforcement
//     of domain='asset' (022's comment: "Matched-DOMAIN is app-layer in V1"; the DB fence #8
//     checks tenant match only, not domain).

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { actions } from './+page.server';

const SESSION_A = '00000000-0000-0000-0000-00000000000a';

type UpsertResult = { data: unknown; error: { message: string } | null };
/** The ADR-013 H1 pre-validation read: .schema('pfin').from('user_taxonomy').select('id')
 *  .eq('id',…).eq('is_active',true).maybeSingle(). POST-084 (ADR-058 Decision 1's split):
 *  `user_taxonomy` has no `domain` column any more — table identity IS the domain fence now, so
 *  the chain is two `.eq()` calls, not three. `found:true` means the row resolved (assignable);
 *  `found:false` mimics RLS / cross-table exclusion (zero rows, no error). */
type PreValidateResult = { found: boolean; error?: { message: string } };

/** Minimal supabase-js stub covering BOTH chains the classify action touches: the
 *  isAssignableAssetSubCat pre-check read (user_taxonomy) and the upsert write
 *  (user_asset_category). `.from()` branches on the table name so one stub serves both. */
function makeSupabase(upsertResult: UpsertResult, preValidate: PreValidateResult = { found: true }) {
	const maybeSingle = vi.fn(async () => upsertResult);
	const select = vi.fn(() => ({ maybeSingle }));
	const upsert = vi.fn(() => ({ select }));

	const preMaybeSingle = vi.fn(async () =>
		preValidate.error
			? { data: null, error: preValidate.error }
			: { data: preValidate.found ? { id: 1 } : null, error: null }
	);
	const preEq2 = vi.fn(() => ({ maybeSingle: preMaybeSingle }));
	const preEq1 = vi.fn(() => ({ eq: preEq2 }));
	const preSelect = vi.fn(() => ({ eq: preEq1 }));

	const from = vi.fn((table: string) =>
		table === 'user_taxonomy' ? { select: preSelect } : { upsert }
	);
	const schema = vi.fn(() => ({ from }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, schema, from, upsert, select, maybeSingle, preSelect, preMaybeSingle };
}

/** Build the RequestEvent slice the classify action reads: form body + session + supabase. */
function makeEvent(opts: {
	form: Record<string, string>;
	user?: { id: string } | null;
	upsert?: UpsertResult;
	preValidate?: PreValidateResult;
}) {
	const fd = new FormData();
	for (const [k, v] of Object.entries(opts.form)) fd.set(k, v);
	const { client, upsert, maybeSingle } = makeSupabase(
		opts.upsert ?? { data: { asset_id: Number(opts.form.asset_id) }, error: null },
		opts.preValidate
	);
	const event = {
		request: { formData: async () => fd },
		locals: {
			supabase: client,
			safeGetSession: async () => ({ user: opts.user === undefined ? { id: SESSION_A } : opts.user })
		}
	};
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	return { event: event as any, upsert, maybeSingle };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const run = (event: any) => (actions.classify as any)(event);

describe('classify action — error-surface mapping (SELF-200)', () => {
	it('cross-tenant Sub-Cat RAISE (#8) → 422 scoped to sub_cat_id (NOT asset_id)', async () => {
		const { event } = makeEvent({
			form: { asset_id: '10', sub_cat_id: '20' },
			upsert: {
				data: null,
				error: {
					message:
						'cross-tenant Sub-Cat rejected: sub_cat_id 20 is not a taxonomy row owned by users_id … (#8)'
				}
			}
		});
		const res = await run(event);
		expect(res.status).toBe(422);
		expect(res.data.errors.sub_cat_id).toBeDefined();
		// TEETH: must NOT be mislabeled as an asset error (the #9 message also contains
		// "matched-tenant"; a loose/ swapped match would set asset_id here).
		expect(res.data.errors.asset_id).toBeUndefined();
	});

	it('cross-tenant asset RAISE (#9) → 422 scoped to asset_id (NOT sub_cat_id)', async () => {
		const { event } = makeEvent({
			form: { asset_id: '99', sub_cat_id: '20' },
			upsert: {
				data: null,
				error: {
					message:
						'cross-tenant asset rejected: asset_id 99 is not a global or tenant-owned asset for users_id … (#9)'
				}
			}
		});
		const res = await run(event);
		expect(res.status).toBe(422);
		expect(res.data.errors.asset_id).toBeDefined();
		expect(res.data.errors.sub_cat_id).toBeUndefined();
	});

	it('unrecognized DB error → degrades safely to generic _form 422 (fails closed, no field leak)', async () => {
		const { event } = makeEvent({
			form: { asset_id: '10', sub_cat_id: '20' },
			upsert: { data: null, error: { message: 'some unexpected postgres error 42P01' } }
		});
		const res = await run(event);
		expect(res.status).toBe(422);
		expect(res.data.errors._form).toBeDefined();
		expect(res.data.errors.sub_cat_id).toBeUndefined();
		expect(res.data.errors.asset_id).toBeUndefined();
	});

	it('happy path → { success, asset_id }; users_id is session-derived, never from the body', async () => {
		const { event, upsert } = makeEvent({
			form: { asset_id: '10', sub_cat_id: '20' },
			upsert: { data: { asset_id: 10 }, error: null }
		});
		const res = await run(event);
		expect(res).toEqual({ success: true, asset_id: 10 });
		// The upsert payload carries the SESSION user id (mass-assignment fence), not a body value.
		expect(upsert).toHaveBeenCalledWith(
			expect.objectContaining({ users_id: SESSION_A, asset_id: 10, sub_cat_id: 20 }),
			{ onConflict: 'users_id,asset_id' }
		);
	});

	it('not signed in → 401 (no DB write attempted)', async () => {
		const { event, upsert } = makeEvent({ form: { asset_id: '10', sub_cat_id: '20' }, user: null });
		const res = await run(event);
		expect(res.status).toBe(401);
		expect(upsert).not.toHaveBeenCalled();
	});

	it('invalid input (missing sub_cat_id) → 400 before any DB write', async () => {
		const { event, upsert } = makeEvent({ form: { asset_id: '10' } });
		const res = await run(event);
		expect(res.status).toBe(400);
		expect(upsert).not.toHaveBeenCalled();
	});

	it('RLS-filtered non-owner write (null row, no error) → 404 defensive backstop', async () => {
		const { event } = makeEvent({
			form: { asset_id: '10', sub_cat_id: '20' },
			upsert: { data: null, error: null }
		});
		const res = await run(event);
		expect(res.status).toBe(404);
	});
});

describe('classify action — ADR-013 H1 pre-validation gate (SELF-235 AC6)', () => {
	it('sub_cat_id the pre-check cannot confirm (cross-tenant / wrong-domain / nonexistent) → 403, no write attempted', async () => {
		const { event, upsert } = makeEvent({
			form: { asset_id: '10', sub_cat_id: '20' },
			preValidate: { found: false }
		});
		const res = await run(event);
		expect(res.status).toBe(403);
		expect(res.data.errors.sub_cat_id).toBeDefined();
		expect(upsert).not.toHaveBeenCalled();
	});

	it('pre-check read error → fails CLOSED (403, no write) — an unverifiable check is never "valid"', async () => {
		const { event, upsert } = makeEvent({
			form: { asset_id: '10', sub_cat_id: '20' },
			preValidate: { found: false, error: { message: 'connection reset' } }
		});
		const res = await run(event);
		expect(res.status).toBe(403);
		expect(upsert).not.toHaveBeenCalled();
	});

	it('pre-check passes → falls through to the upsert as before', async () => {
		const { event, upsert } = makeEvent({
			form: { asset_id: '10', sub_cat_id: '20' },
			preValidate: { found: true },
			upsert: { data: { asset_id: 10 }, error: null }
		});
		const res = await run(event);
		expect(res).toEqual({ success: true, asset_id: 10 });
		expect(upsert).toHaveBeenCalled();
	});
});
