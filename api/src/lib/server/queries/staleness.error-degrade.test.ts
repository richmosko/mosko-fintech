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
