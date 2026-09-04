// nav-composition-flip.server.test.ts — SELF-268 / ADR-067 Decision 3 (R3 rider 0) load()-
// integration coverage for the root +page.server.ts.
//
// This file IS the watcher R3 rider 0 and AC 1a name — "SELF-226's foot-to-headline
// reconciliation ... stays in the battery" — which Sec's pre-ruling re-read (P-11,
// docs/records/v14-execution/self268-sec-findings.md) measured as NOT EXISTING anywhere on the
// tree: `grep -rn "composition.nav" api/src` found only a render assertion
// (NavCompositionTable.ssr.test.ts), never a comparison against `data.netWorth`. Built here per
// Sec's explicit instruction, refined a second time (P-11 refinement) into the TWO halves a single
// "same rendered number" assertion cannot provide on its own:
//
//   (i)  CALL-SHAPE — on the §2.1.1 headline path, `fn_nav_composition` is called EXACTLY ONCE and
//        `fn_compute_nav` is NEVER called. This is the half that goes RED the moment the headline
//        is re-pointed at `fn_compute_nav`, independent of what any mock happens to return — a
//        fixture that coincidentally agrees cannot pass this leg by accident, because the leg
//        never looks at a returned VALUE at all.
//   (ii) VALUE — both rendered figures (`data.netWorth`, `data.composition.nav`) derive from the
//        SAME payload, proven with a DIFFERING-VALUE mock for `fn_compute_nav` as the inversion
//        fixture: if the headline ever silently started reading `fn_compute_nav` again (whether or
//        not (i) also caught it), the differing mock value would make `data.netWorth` disagree
//        with `data.composition.nav`, and this assertion would fail.
//
// ⚠ INVERSION VERIFIED BY HAND, NOT JUST BY CONSTRUCTION (2026-09-04, Backend). Per Sec's ask —
//   "prove it by temporarily re-pointing (red), then restoring (green)" — the test below
//   (`'differing fn_compute_nav value does not move the headline ...'`) was run against a
//   deliberately-broken copy of netWorth.ts that read `composition.nav` OR the mocked
//   `fn_compute_nav` value (simulating a partial revert), confirmed RED (`data.netWorth` came back
//   as the differing `fn_compute_nav` mock value, failing the `toBe(SAMPLE_COMPOSITION.nav)`
//   assertion), then netWorth.ts was reverted to its committed form and the same test was
//   confirmed GREEN. That edit was never committed — this paragraph is the record of it.
//
// Also proves (per R3 rider 0's own text, and Sec D-5's non-objection):
//   1. ONE call to fn_nav_composition serves BOTH the §2.1.1 headline (`data.netWorth`) and the
//      §2.1.5 foot (`data.composition.nav`) on a single page load — never two RPC round-trips for
//      one request.
//   2. A composed-read failure degrades BOTH surfaces together (shared value, shared failure) —
//      there is no longer a state where the foot fails but the headline stays up on a stale
//      independent read, because there is only one read.
//
// The rest of the route's RPCs (staleness / navSeries / navBoundary / navDeltaPanel /
// navReferenceDates) are mocked to trivial happy-path defaults, mirroring
// nav-series.server.test.ts's own convention — their behavior is proven elsewhere.

import { describe, it, expect, vi } from 'vitest';
import { load } from './+page.server';

const SESSION_USER = { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' };

const TRIVIAL_NAV_DELTA_PANEL: unknown[] = [];
const TRIVIAL_NAV_REFERENCE_DATES: unknown[] = [];

/** `fn_compute_nav`'s configured mock behavior for one test. */
type ComputeNavMock = { mode: 'throw' } | { mode: 'value'; value: unknown };

/**
 * Builds a `locals.supabase` stub whose `.schema('pfin')` chain dispatches by RPC/table name.
 * `navCompositionRpc` is a spy so call COUNT (not just call args) can be asserted — the core
 * property under test is that it is invoked exactly ONCE per load(), no matter how many surfaces
 * on the route consume its value.
 *
 * `computeNavMock` defaults to `{ mode: 'throw' }` — the strongest tripwire for the ordinary
 * "never called" tests (a call surfaces immediately and loudly). The dedicated inversion-fixture
 * test below overrides it to `{ mode: 'value', value: <differing number> }`, because Sec's P-11
 * refinement specifically wants a PLAUSIBLE differing return, not an exception, as the fixture
 * proving the "same number" assertion can fail.
 */
function makeLocals(
	navCompositionData: unknown,
	navCompositionError: { message: string } | null = null,
	computeNavMock: ComputeNavMock = { mode: 'throw' }
) {
	const navCompositionRpc = vi.fn(async () => ({
		data: navCompositionData,
		error: navCompositionError
	}));
	const computeNavRpc = vi.fn(async () => {
		if (computeNavMock.mode === 'throw') {
			// Must never be reached post-SELF-268 — a call here is the exact regression this file
			// exists to catch (the headline reverting to the un-composed reader).
			throw new Error('fn_compute_nav must not be called — the headline reads fn_nav_composition');
		}
		return { data: computeNavMock.value, error: null };
	});

	const rpc = vi.fn(async (fnName: string) => {
		switch (fnName) {
			case 'fn_compute_nav':
				return computeNavRpc();
			case 'fn_nav_composition':
				return navCompositionRpc();
			case 'fn_aggregation_has_stale_constituent':
				return { data: [{ is_stale: false, stale_items: [] }], error: null };
			case 'fn_nav_series_inflation_adjusted':
				return { data: [], error: null };
			case 'fn_first_cron_checkpoint':
				return {
					data: [{ first_cron_checkpoint: null, has_cron_rows: false, has_imported_rows: false }],
					error: null
				};
			case 'fn_nav_delta_panel':
				return { data: TRIVIAL_NAV_DELTA_PANEL, error: null };
			case 'fn_nav_reference_dates':
				return { data: TRIVIAL_NAV_REFERENCE_DATES, error: null };
			default:
				throw new Error(`unexpected rpc: ${fnName}`);
		}
	});
	const from = vi.fn(() => ({
		select: vi.fn(() => ({
			or: vi.fn(async () => ({ count: 3, error: null }))
		}))
	}));
	const supabase = { schema: vi.fn(() => ({ rpc, from })) };
	const locals = {
		safeGetSession: async () => ({ session: {}, user: SESSION_USER }),
		supabase
	};
	return { locals, rpc, navCompositionRpc, computeNavRpc };
}

function makeEvent(
	navCompositionData: unknown,
	navCompositionError: { message: string } | null = null,
	computeNavMock?: ComputeNavMock
) {
	const { locals, rpc, navCompositionRpc, computeNavRpc } = makeLocals(
		navCompositionData,
		navCompositionError,
		computeNavMock
	);
	const url = new URL('http://localhost/');
	const event = { locals, url } as unknown as Parameters<typeof load>[0];
	return { event, rpc, navCompositionRpc, computeNavRpc };
}

const SAMPLE_COMPOSITION = {
	groups: [
		{
			category: 'depository',
			accounts: [
				{ account_id: 1, account_name: 'Checking', current_market_value: 5000, unrealized_gl: null }
			],
			subtotal: 5000
		}
	],
	buildups: {
		total_non_re: 5000,
		gross_total: 5000,
		debt: 0,
		// SELF-268 / E41-E42: envelopes, not plain numbers (see navComposition.ts's
		// TaxLiabilityEnvelope) — arbitrary here since this file never asserts on them.
		realized_tax_liab: { status: 'unavailable', reason: 'no_schedule_any_year' },
		unrealized_tax_liab: { status: 'unavailable', reason: 'no_schedule_any_year' }
	},
	nav: 47_310.5
};

describe('load() — SELF-268 / R3 rider 0: one composed value, one reader', () => {
	it('the headline (netWorth) and the foot (composition.nav) are the LITERAL SAME number', async () => {
		const { event } = makeEvent(SAMPLE_COMPOSITION);
		const data = (await load(event)) as { netWorth: number | null; composition: { nav: number } | null };

		expect(data.netWorth).toBe(SAMPLE_COMPOSITION.nav);
		expect(data.composition?.nav).toBe(SAMPLE_COMPOSITION.nav);
		expect(data.netWorth).toBe(data.composition?.nav);
	});

	// ── (i) CALL-SHAPE — the leg that reds even when a fixture would otherwise agree ──────────
	it('fn_nav_composition is called EXACTLY ONCE — not once per surface', async () => {
		const { event, navCompositionRpc } = makeEvent(SAMPLE_COMPOSITION);
		await load(event);

		expect(navCompositionRpc).toHaveBeenCalledTimes(1);
	});

	it('fn_compute_nav is never called — the headline no longer has its own independent read', async () => {
		const { event, rpc } = makeEvent(SAMPLE_COMPOSITION);
		await load(event);

		expect(rpc).not.toHaveBeenCalledWith('fn_compute_nav', expect.anything());
	});

	// ── (ii) VALUE / INVERSION — Sec P-11 refinement's second half ────────────────────────────
	it('a DIFFERING fn_compute_nav mock value does not move the headline — the inversion fixture proving (i) is not vacuous', async () => {
		// Deliberately far from SAMPLE_COMPOSITION.nav (47_310.5) so any accidental read would be
		// unmistakable rather than a coincidental near-match.
		const DIFFERING_FN_COMPUTE_NAV_VALUE = 999_999;
		const { event, computeNavRpc } = makeEvent(SAMPLE_COMPOSITION, null, {
			mode: 'value',
			value: DIFFERING_FN_COMPUTE_NAV_VALUE
		});
		const data = (await load(event)) as { netWorth: number | null; composition: { nav: number } | null };

		// The headline reads the composed value regardless of what fn_compute_nav is armed to
		// return — proving the "same number" property is not an artifact of both mocks
		// coincidentally agreeing (they deliberately do NOT here).
		expect(data.netWorth).toBe(SAMPLE_COMPOSITION.nav);
		expect(data.netWorth).not.toBe(DIFFERING_FN_COMPUTE_NAV_VALUE);
		expect(data.composition?.nav).toBe(SAMPLE_COMPOSITION.nav);
		// fn_compute_nav was armed with a real, plausible (non-throwing) value and STILL never
		// reached — this is the same call-shape property as the test above, restated under the
		// inversion fixture rather than the throw-based one, so the two tests do not depend on
		// each other's mock configuration to both be meaningful.
		expect(computeNavRpc).not.toHaveBeenCalled();
	});

	it('a composed-read RPC error degrades BOTH the headline and the foot together — one shared failure, not an independent one per surface', async () => {
		const { event } = makeEvent(null, { message: 'permission denied' });
		const data = (await load(event)) as { netWorth: number | null; composition: unknown };

		expect(data.netWorth).toBeNull();
		expect(data.composition).toBeNull();
	});

	it('a well-formed zero-account tree (nav: 0) is a real zero on BOTH surfaces, not a failure', async () => {
		const zeroTree = {
			groups: [],
			buildups: {
				total_non_re: 0,
				gross_total: 0,
				debt: 0,
				realized_tax_liab: { status: 'computed', amount: 0 },
				unrealized_tax_liab: { status: 'computed', amount: 0 }
			},
			nav: 0
		};
		const { event } = makeEvent(zeroTree);
		const data = (await load(event)) as { netWorth: number | null; composition: { nav: number } | null };

		expect(data.netWorth).toBe(0);
		expect(data.composition?.nav).toBe(0);
	});
});
