// nav-composition-flip.server.test.ts — SELF-268 / ADR-067 Decision 3 (R3 rider 0) load()-
// integration coverage for the root +page.server.ts.
//
// Proves the property riders 0 and 4 actually require at the ORCHESTRATION layer (unit tests on
// netWorth.ts / navComposition.ts alone cannot see this — each is tested in isolation there):
//
//   1. ONE call to fn_nav_composition serves BOTH the §2.1.1 headline (`data.netWorth`) and the
//      §2.1.5 foot (`data.composition.nav`) on a single page load — never two RPC round-trips for
//      one request. `fn_compute_nav` is never called at all.
//   2. The headline's `netWorth` and the foot's `composition.nav` are the LITERAL SAME number,
//      because they are the same fetched value, not two calls to the same definition that could
//      independently drift.
//   3. A composed-read failure degrades BOTH surfaces together (shared value, shared failure) —
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

/**
 * Builds a `locals.supabase` stub whose `.schema('pfin')` chain dispatches by RPC/table name.
 * `navCompositionRpc` is a spy so call COUNT (not just call args) can be asserted — the core
 * property under test is that it is invoked exactly ONCE per load(), no matter how many surfaces
 * on the route consume its value.
 */
function makeLocals(navCompositionData: unknown, navCompositionError: { message: string } | null = null) {
	const navCompositionRpc = vi.fn(async () => ({
		data: navCompositionData,
		error: navCompositionError
	}));

	const rpc = vi.fn(async (fnName: string) => {
		switch (fnName) {
			case 'fn_compute_nav':
				// Must never be reached post-SELF-268 — a call here is the exact regression this
				// file exists to catch (the headline reverting to the un-composed reader).
				throw new Error('fn_compute_nav must not be called — the headline reads fn_nav_composition');
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
	return { locals, rpc, navCompositionRpc };
}

function makeEvent(navCompositionData: unknown, navCompositionError: { message: string } | null = null) {
	const { locals, rpc, navCompositionRpc } = makeLocals(navCompositionData, navCompositionError);
	const url = new URL('http://localhost/');
	const event = { locals, url } as unknown as Parameters<typeof load>[0];
	return { event, rpc, navCompositionRpc };
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
		realized_tax_liab: 0,
		unrealized_tax_liab: 0
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

	it('a composed-read RPC error degrades BOTH the headline and the foot together — one shared failure, not an independent one per surface', async () => {
		const { event } = makeEvent(null, { message: 'permission denied' });
		const data = (await load(event)) as { netWorth: number | null; composition: unknown };

		expect(data.netWorth).toBeNull();
		expect(data.composition).toBeNull();
	});

	it('a well-formed zero-account tree (nav: 0) is a real zero on BOTH surfaces, not a failure', async () => {
		const zeroTree = {
			groups: [],
			buildups: { total_non_re: 0, gross_total: 0, debt: 0, realized_tax_liab: 0, unrealized_tax_liab: 0 },
			nav: 0
		};
		const { event } = makeEvent(zeroTree);
		const data = (await load(event)) as { netWorth: number | null; composition: { nav: number } | null };

		expect(data.netWorth).toBe(0);
		expect(data.composition?.nav).toBe(0);
	});
});
