// cash-flow-loader.server.test.ts — SELF-251 load()-integration coverage for
// cash-flow/+page.server.ts. Fills a gap the component/page dom tests can't reach: those files
// prove the UI renders correctly GIVEN a payload, never that the payload itself was fetched
// exactly once. AC9's own module header states the hazard directly — "two requests each
// defaulting p_as_of independently can straddle midnight and disagree" — so this file's whole
// job is the loader-boundary half of the one-source discipline: ONE `loadCashflowCrossAccountRollup`
// call per load(), fed the SAME `asOf` the route's own header says it threads once.
//
// `loadCashflowCrossAccountRollup` (Backend-owned, cashflowCrossAccountRollup.ts) is mocked here
// — its own internal RLS-scoping / normalize() behavior is proven by that file's own
// cashflowCrossAccountRollup.test.ts; this file's only honest claim is about +page.server.ts's
// WIRING: does it call the wrapper once, with a real as-of, and does it fail soft to `null`
// (never throw through to the route) exactly like every other §2.1/§2.2 loader.
//
// Mirrors nav-series.server.test.ts's convention: import the real `load`, drive it with a
// minimal locals/url double, assert on the mock's call count/args rather than on network state.
//
// SELF-256 EXTENSION (loader leg): `loadHistoricalExpendituresPanel` is mocked ALONGSIDE the
// rollup wrapper — its own internal RLS-scoping / normalize() / fail-soft behavior is proven by
// historicalExpendituresPanel.test.ts; this file's added coverage is again about WIRING: same
// `asOf` threaded to both calls, and each side's fail-soft degrade is independent of the other's
// (a thrown panel read must not touch `data.rollup`, and vice versa).

import { describe, it, expect, vi } from 'vitest';
import { isRedirect } from '@sveltejs/kit';

const loadCashflowCrossAccountRollupMock = vi.fn();
vi.mock('$lib/server/queries/cashflowCrossAccountRollup', () => ({
	loadCashflowCrossAccountRollup: loadCashflowCrossAccountRollupMock
}));

const loadHistoricalExpendituresPanelMock = vi.fn();
vi.mock('$lib/server/queries/historicalExpendituresPanel', () => ({
	loadHistoricalExpendituresPanel: loadHistoricalExpendituresPanelMock
}));

const { load } = await import('./+page.server');

const SESSION_USER = { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' };
const HAPPY_ROLLUP = {
	as_of: '2026-08-27',
	sections: [],
	targets: { income_target_annual: null, expense_target_monthly: null },
	unclassified: { count_ytd: 0 }
};
const HAPPY_PANEL = { points: [], unclassifiedCount: 0 };

function stubHappyPanel() {
	loadHistoricalExpendituresPanelMock.mockReset();
	loadHistoricalExpendituresPanelMock.mockResolvedValue(HAPPY_PANEL);
}

function makeEvent(user: { id: string } | null = SESSION_USER) {
	const locals = {
		safeGetSession: async () => ({ session: user ? {} : null, user }),
		supabase: {} // never touched directly by this route — only by the mocked wrapper
	};
	const url = new URL('http://localhost/cash-flow');
	return { locals, url } as unknown as Parameters<typeof load>[0];
}

// load()'s inferred return type unions in `void` (the redirect() early-throw path), which TS
// can't rule out statically even though the redirect leg's own test never reads `data` — same
// narrowing precedent as accounts/[account_id]/load.server.test.ts's `LoadResult`/`loadData`.
type LoadResult = {
	rollup: unknown;
	historicalExpenditures: unknown;
	historicalExpendituresUnclassifiedCount: unknown;
};
async function loadData(event: Parameters<typeof load>[0]): Promise<LoadResult> {
	return (await load(event)) as unknown as LoadResult;
}

describe('load() — SELF-251 unauthenticated redirect', () => {
	it('redirects to /login with a redirectTo, and attempts NO rollup or panel read', async () => {
		loadCashflowCrossAccountRollupMock.mockClear();
		loadHistoricalExpendituresPanelMock.mockClear();
		let caught: unknown;
		try {
			await load(makeEvent(null));
		} catch (e) {
			caught = e;
		}
		expect(isRedirect(caught)).toBe(true);
		expect((caught as { status: number }).status).toBe(303);
		expect((caught as { location: string }).location).toBe('/login?redirectTo=%2Fcash-flow');
		expect(loadCashflowCrossAccountRollupMock).not.toHaveBeenCalled();
		expect(loadHistoricalExpendituresPanelMock).not.toHaveBeenCalled();
	});
});

describe('load() — SELF-251 AC9/ADR-044 D2 one-source: exactly one rollup read per load(), asOf resolved once', () => {
	it('calls loadCashflowCrossAccountRollup EXACTLY ONCE — a second call would reintroduce the straddle-midnight hazard this loader\'s own header names', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		stubHappyPanel();
		await load(makeEvent());
		expect(loadCashflowCrossAccountRollupMock).toHaveBeenCalledTimes(1);
	});

	it('passes a real YYYY-MM-DD asOf (serverTodayAsOf\'s own shape) as the second argument', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		stubHappyPanel();
		await load(makeEvent());
		const [, asOfArg] = loadCashflowCrossAccountRollupMock.mock.calls[0];
		expect(asOfArg).toMatch(/^\d{4}-\d{2}-\d{2}$/);
	});

	it('threads the resolved rollup straight through to data.rollup, unmodified', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		stubHappyPanel();
		const data = await loadData(makeEvent());
		expect(data.rollup).toBe(HAPPY_ROLLUP);
	});
});

describe('load() — SELF-251 fail-soft: a thrown read degrades to null, never throws through the route', () => {
	it('an unexpected throw from loadCashflowCrossAccountRollup degrades to data.rollup === null', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockRejectedValueOnce(new Error('network blip'));
		stubHappyPanel();
		const data = await loadData(makeEvent());
		expect(data.rollup).toBeNull();
	});

	it('a resolved null (the wrapper\'s own internal fail-soft path) passes through as null, not fabricated into an empty rollup', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(null);
		stubHappyPanel();
		const data = await loadData(makeEvent());
		expect(data.rollup).toBeNull();
	});
});

describe('load() — SELF-256 §2.3.4 panel: one call site, same asOf, independent fail-soft', () => {
	it('calls loadHistoricalExpendituresPanel EXACTLY ONCE, with the SAME asOf value passed to the rollup call', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		loadHistoricalExpendituresPanelMock.mockReset();
		loadHistoricalExpendituresPanelMock.mockResolvedValueOnce(HAPPY_PANEL);
		await load(makeEvent());

		expect(loadHistoricalExpendituresPanelMock).toHaveBeenCalledTimes(1);
		const [, rollupAsOf] = loadCashflowCrossAccountRollupMock.mock.calls[0];
		const [, panelAsOf] = loadHistoricalExpendituresPanelMock.mock.calls[0];
		expect(panelAsOf).toBe(rollupAsOf);
	});

	it('threads points/unclassifiedCount straight through to data, unmodified', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		loadHistoricalExpendituresPanelMock.mockReset();
		const panel = { points: [{ month_end: '2026-06-30' }], unclassifiedCount: 3 };
		loadHistoricalExpendituresPanelMock.mockResolvedValueOnce(panel);
		const data = await loadData(makeEvent());

		expect(data.historicalExpenditures).toBe(panel.points);
		expect(data.historicalExpendituresUnclassifiedCount).toBe(3);
	});

	it('a real 0 unclassifiedCount survives to data, NOT coalesced to null (inversion check)', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		loadHistoricalExpendituresPanelMock.mockReset();
		loadHistoricalExpendituresPanelMock.mockResolvedValueOnce({ points: [], unclassifiedCount: 0 });
		const data = await loadData(makeEvent());

		expect(data.historicalExpendituresUnclassifiedCount).toBe(0);
		expect(data.historicalExpendituresUnclassifiedCount).not.toBeNull();
	});

	it('a NULL unclassifiedCount survives to data, NOT coalesced to 0 (inversion check)', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		loadHistoricalExpendituresPanelMock.mockReset();
		loadHistoricalExpendituresPanelMock.mockResolvedValueOnce({ points: [], unclassifiedCount: null });
		const data = await loadData(makeEvent());

		expect(data.historicalExpendituresUnclassifiedCount).toBeNull();
	});

	it('an unexpected throw from loadHistoricalExpendituresPanel degrades both panel fields to null WITHOUT touching data.rollup', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		loadHistoricalExpendituresPanelMock.mockReset();
		loadHistoricalExpendituresPanelMock.mockRejectedValueOnce(new Error('network blip'));
		const data = await loadData(makeEvent());

		expect(data.historicalExpenditures).toBeNull();
		expect(data.historicalExpendituresUnclassifiedCount).toBeNull();
		expect(data.rollup).toBe(HAPPY_ROLLUP);
	});

	it('an unexpected throw from loadCashflowCrossAccountRollup does NOT touch the panel fields', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockRejectedValueOnce(new Error('network blip'));
		loadHistoricalExpendituresPanelMock.mockReset();
		const panel = { points: [{ month_end: '2026-06-30' }], unclassifiedCount: 5 };
		loadHistoricalExpendituresPanelMock.mockResolvedValueOnce(panel);
		const data = await loadData(makeEvent());

		expect(data.rollup).toBeNull();
		expect(data.historicalExpenditures).toBe(panel.points);
		expect(data.historicalExpendituresUnclassifiedCount).toBe(5);
	});
});
