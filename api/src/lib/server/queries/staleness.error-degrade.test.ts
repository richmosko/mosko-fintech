// staleness.error-degrade.test.ts — QA-owned, INDEPENDENT of backend's own new `staleness.test.ts`
// (both exist now — same `netWorth.test.ts`/`netWorth.boundary.test.ts` split convention this
// codebase already uses: backend owns primary module coverage, QA owns an adjacent file proving
// the same property from the outside, so a shared blind spot in one doesn't survive in the other).
// RENAMED from `staleness.test.ts` (2026-08-14) purely to avoid a PATH COLLISION once backend
// authored their own file at that exact name mid-session — no content dropped, this is the same
// file, just not competing for the same filename. No prior test file existed for this module
// before either of us wrote one (verified: the SELF-208 root staleness primitive shipped without
// one — a gap in itself, closed here and in backend's file both).
//
// F/CTO ruling (a), routed via team-lead, SELF-229: loadStaleness() — the SINGLE consumption
// site every V1.1 NW surface reads (§2.1.1 headline / §2.1.2 chart / §2.1.3 delta panel / §2.1.4
// reference-dates panel, plus §2.1.5 composition's additional per-row join — see this module's
// own AC5 D1 annotation) — gets the SAME tri-state fix SELF-229 AC#2 already gave the
// composition per-leaf join (e7b8da9): an RPC failure must degrade to an EXPLICIT unknown state,
// never to `EMPTY_STALENESS` (`{is_stale: false, stale_items: []}`), because that shape is
// INDISTINGUISHABLE from "confirmed healthy" at every consuming surface — the exact
// silent-fresh-on-failure defect class SELF-220 Sec round 2 rejected on the chart, one level up
// the call graph from where it was first found and fixed.
//
// ⭐ LEG (1) BELOW WAS RUN AS A LITERAL, MEASURED RED RUN — not a predicted one — against the
// pre-rework `loadStaleness()` (returned `EMPTY_STALENESS` on `error`/no-row). 3 of 5 legs failed
// at that point; confirmed by running it (reported to team-lead). Backend's rework has since
// landed (temp/self229-staleness-rework.diff, applied to staleness.ts) — CONFIRMED against their
// actual diff, not just the relay: `is_stale: boolean | null`, a distinct `UNKNOWN_STALENESS`
// constant (`{is_stale: null, stale_items: []}`), separate from `EMPTY_STALENESS`. Shape matches
// what legs (2)+ already predicted — no reconciliation needed.
//
// MOCK IDIOM: same `makeSupabase` pattern as netWorth.boundary.test.ts / navComposition.staleness.test.ts
// — a minimal stub SupabaseClient built with vi.fn() chains, `as unknown as SupabaseClient`.
//
// @vitest-environment node

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadStaleness } from './staleness';
import { EMPTY_STALENESS } from '$lib/staleness/stale-constituent';

function makeSupabase(rpcResult: { data: unknown; error: { message: string } | null }) {
	const rpc = vi.fn(async () => rpcResult);
	const schema = vi.fn(() => ({ rpc }));
	return { schema } as unknown as SupabaseClient;
}

describe('loadStaleness — root RPC failure must degrade to UNKNOWN, never to confirmed-not-stale', () => {
	it('⭐ was RED against pre-rework code (fn_aggregation_has_stale_constituent errors): is_stale must be null (unknown), NEVER false — and the result must not equal EMPTY_STALENESS', async () => {
		const client = makeSupabase({ data: null, error: { message: 'connection reset' } });
		const result: unknown = await loadStaleness(client);

		// Stated both ways so a future fixture/shape change can't accidentally satisfy one form
		// without the other: EMPTY_STALENESS is the literal WRONG ANSWER this leg exists to rule
		// out, and `is_stale === null` is the literal RIGHT ANSWER per the composition precedent.
		expect(result).not.toEqual(EMPTY_STALENESS);
		expect((result as { is_stale: unknown }).is_stale).toBe(null);
		expect((result as { is_stale: unknown }).is_stale).not.toBe(false);
	});

	it('the RPC returning NO aggregate row (fn contract violation, not an error) gets the SAME unknown treatment — an anomaly is not evidence of health either', async () => {
		const client = makeSupabase({ data: [], error: null });
		const result: unknown = await loadStaleness(client);
		expect((result as { is_stale: unknown }).is_stale).toBe(null);
		expect((result as { is_stale: unknown }).is_stale).not.toBe(false);
	});

	it('a genuinely-healthy successful read (is_stale: false, confirmed by a real query result) is UNCHANGED and stays false — distinct from the unknown/null case above', async () => {
		const client = makeSupabase({ data: [{ is_stale: false, stale_items: [] }], error: null });
		const result: unknown = await loadStaleness(client);
		expect((result as { is_stale: unknown }).is_stale).toBe(false);
		expect((result as { is_stale: unknown }).is_stale).not.toBe(null);
	});

	it('a genuinely-stale successful read (is_stale: true) is unaffected by the tri-state fix', async () => {
		const client = makeSupabase({
			data: [
				{
					is_stale: true,
					stale_items: [
						{
							linked_source_id: 42,
							institution_name: 'Test Bank',
							provider: 'plaid',
							connection_status: 'login_required',
							status_class: null
						}
					]
				}
			],
			error: null
		});
		const result: unknown = await loadStaleness(client);
		expect((result as { is_stale: unknown }).is_stale).toBe(true);
		expect((result as { stale_items: unknown[] }).stale_items).toHaveLength(1);
	});
});

// ============================================================================
// DATA-LAYER distinction leg (F/CTO ruling item 3's prerequisite): a genuinely-healthy read and
// an errored read must be DISTINGUISHABLE at the data layer BEFORE any render-layer distinction
// is even possible. This is the leg I can verify today; the render-layer half (does the badge
// component actually render the two states differently) is BLOCKED on Frontend landing the
// tri-state UI treatment mirroring their composition-leaf work (`.leaf-stale-flag` /
// `.leaf-stale-unknown`) — StaleConstituentBadge.svelte's `isStale` prop is still typed as a
// plain `boolean` today, which would reject `null` at the type level even before the runtime
// `show = isStale && staleItems.length > 0` gate treats `null` the same (falsy) as `false`. Both
// need Frontend's rework; tracked as items (2)/(3) of the ruling, not duplicated here.
// ============================================================================

describe('loadStaleness — data-layer prerequisite: healthy vs unknown are two DIFFERENT values, not two spellings of the same one', () => {
	it('healthy (false) and unknown (null) are NOT the same value under strict equality', async () => {
		const healthyClient = makeSupabase({ data: [{ is_stale: false, stale_items: [] }], error: null });
		const erroredClient = makeSupabase({ data: null, error: { message: 'boom' } });
		const healthy: unknown = await loadStaleness(healthyClient);
		const unknown_: unknown = await loadStaleness(erroredClient);
		expect((healthy as { is_stale: unknown }).is_stale).not.toBe((unknown_ as { is_stale: unknown }).is_stale);
	});
});

// ============================================================================
// Sec R1 (post-GREEN re-verdict, cebe96d, dispatched to backend): the F1 guard above only catches
// TYPE mismatches (non-boolean is_stale / non-array stale_items) — it does not catch a
// well-TYPED but logically INCONSISTENT pair, e.g. `is_stale: false` alongside a NON-EMPTY
// `stale_items` array. Backend's fold-in adds a pair-consistency guard —
// `is_stale !== (stale_items.length > 0)` → degrade to UNKNOWN — mirroring F1's own
// `is_stale:true, stale_items:[]` case (already guarded at the RENDER layer via showUnknown, but
// this is the LOADER-layer mirror of that same inconsistency, the other direction).
//
// ⭐ RAN AS A LITERAL, MEASURED RED RUN against the pre-R1 loader (2026-08-15): this leg FAILED —
// `is_stale` came back `false` (the row's own field, passed through unmodified — the F1 type
// guard passed it as well-typed and the function had no cross-field check). RE-VERIFIED GREEN
// (2026-08-15) against backend's landed fold-in (334a043) — confirmed against the real committed
// diff, not the relay.
// ============================================================================

describe('loadStaleness — Sec R1: a well-typed but INCONSISTENT (is_stale, stale_items) pair degrades to UNKNOWN', () => {
	it('⭐ is_stale: false paired with a NON-EMPTY stale_items array → UNKNOWN, NOT the raw false passed through', async () => {
		const client = makeSupabase({
			data: [
				{
					is_stale: false,
					stale_items: [
						{
							linked_source_id: 7,
							institution_name: 'Test Bank',
							provider: 'plaid',
							connection_status: 'login_required',
							status_class: null
						}
					]
				}
			],
			error: null
		});
		const result: unknown = await loadStaleness(client);
		expect((result as { is_stale: unknown }).is_stale).toBe(null);
		// The wrong answer this leg rules out: passing `is_stale: false` straight through despite a
		// non-empty stale_items list — a "confirmed not stale" claim contradicted by its own list.
		expect((result as { is_stale: unknown }).is_stale).not.toBe(false);
	});

	it('a well-formed CONSISTENT pair (is_stale: true with a non-empty list) is UNAFFECTED by the R1 guard (regression check on the guard itself)', async () => {
		const client = makeSupabase({
			data: [
				{
					is_stale: true,
					stale_items: [
						{
							linked_source_id: 7,
							institution_name: 'Test Bank',
							provider: 'plaid',
							connection_status: 'login_required',
							status_class: null
						}
					]
				}
			],
			error: null
		});
		const result: unknown = await loadStaleness(client);
		expect((result as { is_stale: unknown }).is_stale).toBe(true);
		expect((result as { stale_items: unknown[] }).stale_items).toHaveLength(1);
	});
});

// ============================================================================
// Sec R2 (GREEN round, non-blocking; both F1's original log site AND R1's new one were extended
// to the same shape-only principle): a malformed/inconsistent row can carry REAL tenant data
// (institution_name / provider / linked_source_id) — the log call must never emit the row
// content, only its shape (types, array-ness, lengths). Proven here by VALUE, not by asserting a
// specific logged object shape (which would drift the moment backend renames a metadata key) —
// this leg plants a distinctive institution name / linked_source_id in the malformed input and
// asserts neither ever appears in ANY console.error call's serialized output, across BOTH guard
// branches (F1's type mismatch, R1's pair inconsistency).
// ============================================================================

describe("loadStaleness — Sec R2: neither malformed-row log call ever emits the row's own tenant data", () => {
	const PLANTED_NAME = 'Canary National Bank';
	const PLANTED_SOURCE_ID = 'ls_98765_canary';

	function assertNoLeak(errorSpy: ReturnType<typeof vi.spyOn>) {
		expect(errorSpy).toHaveBeenCalled();
		const serialized = errorSpy.mock.calls.map((call: unknown[]) => JSON.stringify(call)).join('\n');
		expect(serialized).not.toContain(PLANTED_NAME);
		expect(serialized).not.toContain(PLANTED_SOURCE_ID);
	}

	it('⭐ F1 branch (type mismatch: stale_items not an array): the planted institution name/linked_source_id never reach console.error', async () => {
		const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		try {
			const client = makeSupabase({
				data: [
					{
						is_stale: true,
						// Malformed on purpose (not an array) — the planted values ride along inside the
						// non-array payload, exactly the shape a real malformed 046 response could carry.
						stale_items: {
							linked_source_id: PLANTED_SOURCE_ID,
							institution_name: PLANTED_NAME,
							provider: 'plaid'
						}
					}
				],
				error: null
			});
			await loadStaleness(client);
			assertNoLeak(errorSpy);
		} finally {
			errorSpy.mockRestore();
		}
	});

	it('⭐ R1 branch (pair inconsistency: is_stale disagrees with stale_items.length): the planted institution name/linked_source_id never reach console.error', async () => {
		const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		try {
			const client = makeSupabase({
				data: [
					{
						is_stale: false, // inconsistent with a non-empty list below
						stale_items: [
							{
								linked_source_id: PLANTED_SOURCE_ID,
								institution_name: PLANTED_NAME,
								provider: 'plaid',
								connection_status: 'login_required',
								status_class: null
							}
						]
					}
				],
				error: null
			});
			await loadStaleness(client);
			assertNoLeak(errorSpy);
		} finally {
			errorSpy.mockRestore();
		}
	});
});
