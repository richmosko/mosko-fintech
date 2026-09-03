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
//
// SELF-258 EXTENSION (staleness-ramp loader leg): `loadStaleness` is mocked the same way — its
// own internal RPC-normalize / fail-soft behavior is proven by staleness.test.ts /
// staleness.error-degrade.test.ts; this file's added coverage is again pure WIRING: exactly one
// call, the result threaded straight through to `data.staleness`, degrading to UNKNOWN_STALENESS
// (never EMPTY_STALENESS) on a throw, independent of the rollup/panel legs in both directions.
//
// SELF-258 EXTENSION (per-row Sub-Cat staleness, contributor-map loader leg): `loadCashflowContributors`
// (the `099` RPC read) and `resolveStaleAccountIds` (navComposition.ts's SELF-330 bridge) are
// mocked as the I/O boundary; `computeCashflowRowStaleness` — the pure fold — is the REAL
// implementation, imported via `importOriginal`, so this file's added coverage proves actual
// end-to-end WIRING (contributors + resolved stale ids -> a real `data.cashflowRowStaleness`
// shape), not just call counts. `computeCashflowRowStaleness`'s own fold semantics (dominance
// order, account_name-null UNKNOWN branch, key exclusions) are separately unit-tested in
// cashflowContributors.test.ts and are NOT re-proven here.

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

const loadStalenessMock = vi.fn();
vi.mock('$lib/server/queries/staleness', () => ({
	loadStaleness: loadStalenessMock
}));

const loadCashflowContributorsMock = vi.fn();
vi.mock('$lib/server/queries/cashflowContributors', async (importOriginal) => {
	const actual =
		await importOriginal<typeof import('$lib/server/queries/cashflowContributors')>();
	return {
		...actual,
		loadCashflowContributors: loadCashflowContributorsMock
	};
});

const resolveStaleAccountIdsMock = vi.fn();
vi.mock('$lib/server/queries/navComposition', () => ({
	resolveStaleAccountIds: resolveStaleAccountIdsMock
}));

const { load } = await import('./+page.server');
const { UNKNOWN_STALENESS } = await import('$lib/staleness/stale-constituent');

const SESSION_USER = { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' };
const HAPPY_ROLLUP = {
	as_of: '2026-08-27',
	sections: [],
	targets: { income_target_annual: null, expense_target_monthly: null },
	unclassified: { count_ytd: 0 }
};
const HAPPY_PANEL = { points: [], unclassifiedCount: 0 };

const HAPPY_STALENESS = { is_stale: false, stale_items: [] };

function stubHappyPanel() {
	loadHistoricalExpendituresPanelMock.mockReset();
	loadHistoricalExpendituresPanelMock.mockResolvedValue(HAPPY_PANEL);
}

function stubHappyStaleness() {
	loadStalenessMock.mockReset();
	loadStalenessMock.mockResolvedValue(HAPPY_STALENESS);
	// HAPPY_STALENESS.is_stale is false (KNOWN, not null), so staleLinkedSourceIds resolves to a
	// known (empty) Set, not null — every test using this helper therefore DOES enter the
	// contributor-map leg's `staleLinkedSourceIds !== null` branch. Stub its two I/O calls to a
	// quiet, deterministic happy path so tests that aren't exercising THIS leg specifically don't
	// incidentally depend on the unstubbed-mock throw/catch fail-soft path.
	loadCashflowContributorsMock.mockReset();
	loadCashflowContributorsMock.mockResolvedValue([]);
	resolveStaleAccountIdsMock.mockReset();
	resolveStaleAccountIdsMock.mockResolvedValue(new Set());
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
	staleness: unknown;
	cashflowRowStaleness: unknown;
};
async function loadData(event: Parameters<typeof load>[0]): Promise<LoadResult> {
	return (await load(event)) as unknown as LoadResult;
}

describe('load() — SELF-251 unauthenticated redirect', () => {
	it('redirects to /login with a redirectTo, and attempts NO rollup, panel, staleness, or contributor-map read', async () => {
		loadCashflowCrossAccountRollupMock.mockClear();
		loadHistoricalExpendituresPanelMock.mockClear();
		loadStalenessMock.mockClear();
		loadCashflowContributorsMock.mockClear();
		resolveStaleAccountIdsMock.mockClear();
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
		expect(loadStalenessMock).not.toHaveBeenCalled();
		expect(loadCashflowContributorsMock).not.toHaveBeenCalled();
		expect(resolveStaleAccountIdsMock).not.toHaveBeenCalled();
	});
});

describe('load() — SELF-251 AC9/ADR-044 D2 one-source: exactly one rollup read per load(), asOf resolved once', () => {
	it('calls loadCashflowCrossAccountRollup EXACTLY ONCE — a second call would reintroduce the straddle-midnight hazard this loader\'s own header names', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		stubHappyPanel();
		stubHappyStaleness();
		await load(makeEvent());
		expect(loadCashflowCrossAccountRollupMock).toHaveBeenCalledTimes(1);
	});

	it('passes a real YYYY-MM-DD asOf (serverTodayAsOf\'s own shape) as the second argument', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		stubHappyPanel();
		stubHappyStaleness();
		await load(makeEvent());
		const [, asOfArg] = loadCashflowCrossAccountRollupMock.mock.calls[0];
		expect(asOfArg).toMatch(/^\d{4}-\d{2}-\d{2}$/);
	});

	it('threads the resolved rollup straight through to data.rollup, unmodified', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		stubHappyPanel();
		stubHappyStaleness();
		const data = await loadData(makeEvent());
		expect(data.rollup).toBe(HAPPY_ROLLUP);
	});
});

describe('load() — SELF-251 fail-soft: a thrown read degrades to null, never throws through the route', () => {
	it('an unexpected throw from loadCashflowCrossAccountRollup degrades to data.rollup === null', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockRejectedValueOnce(new Error('network blip'));
		stubHappyPanel();
		stubHappyStaleness();
		const data = await loadData(makeEvent());
		expect(data.rollup).toBeNull();
	});

	it('a resolved null (the wrapper\'s own internal fail-soft path) passes through as null, not fabricated into an empty rollup', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(null);
		stubHappyPanel();
		stubHappyStaleness();
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
		stubHappyStaleness();
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
		stubHappyStaleness();
		const data = await loadData(makeEvent());

		expect(data.historicalExpenditures).toBe(panel.points);
		expect(data.historicalExpendituresUnclassifiedCount).toBe(3);
	});

	it('a real 0 unclassifiedCount survives to data, NOT coalesced to null (inversion check)', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		loadHistoricalExpendituresPanelMock.mockReset();
		loadHistoricalExpendituresPanelMock.mockResolvedValueOnce({ points: [], unclassifiedCount: 0 });
		stubHappyStaleness();
		const data = await loadData(makeEvent());

		expect(data.historicalExpendituresUnclassifiedCount).toBe(0);
		expect(data.historicalExpendituresUnclassifiedCount).not.toBeNull();
	});

	it('a NULL unclassifiedCount survives to data, NOT coalesced to 0 (inversion check)', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		loadHistoricalExpendituresPanelMock.mockReset();
		loadHistoricalExpendituresPanelMock.mockResolvedValueOnce({ points: [], unclassifiedCount: null });
		stubHappyStaleness();
		const data = await loadData(makeEvent());

		expect(data.historicalExpendituresUnclassifiedCount).toBeNull();
	});

	it('an unexpected throw from loadHistoricalExpendituresPanel degrades both panel fields to null WITHOUT touching data.rollup', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		loadHistoricalExpendituresPanelMock.mockReset();
		loadHistoricalExpendituresPanelMock.mockRejectedValueOnce(new Error('network blip'));
		stubHappyStaleness();
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
		stubHappyStaleness();
		const data = await loadData(makeEvent());

		expect(data.rollup).toBeNull();
		expect(data.historicalExpenditures).toBe(panel.points);
		expect(data.historicalExpendituresUnclassifiedCount).toBe(5);
	});
});

describe('load() — SELF-258 staleness ramp: one whole-tenant read, independent fail-soft', () => {
	it('calls loadStaleness EXACTLY ONCE and threads the result straight through to data.staleness, unmodified', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		stubHappyPanel();
		loadStalenessMock.mockReset();
		loadStalenessMock.mockResolvedValueOnce(HAPPY_STALENESS);
		const data = await loadData(makeEvent());

		expect(loadStalenessMock).toHaveBeenCalledTimes(1);
		expect(data.staleness).toBe(HAPPY_STALENESS);
	});

	it('a real stale result (is_stale: true, non-empty stale_items) survives to data unmodified', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		stubHappyPanel();
		const staleResult = {
			is_stale: true,
			stale_items: [
				{
					linked_source_id: '7',
					institution_name: 'Test Bank',
					provider: 'plaid',
					connection_status: 'error',
					status_class: 'error'
				}
			]
		};
		loadStalenessMock.mockReset();
		loadStalenessMock.mockResolvedValueOnce(staleResult);
		const data = await loadData(makeEvent());

		expect(data.staleness).toBe(staleResult);
	});

	it('an unexpected throw from loadStaleness degrades data.staleness to UNKNOWN_STALENESS, WITHOUT touching rollup or panel fields', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		stubHappyPanel();
		loadStalenessMock.mockReset();
		loadStalenessMock.mockRejectedValueOnce(new Error('network blip'));
		const data = await loadData(makeEvent());

		expect(data.staleness).toEqual(UNKNOWN_STALENESS);
		expect(data.rollup).toBe(HAPPY_ROLLUP);
		expect(data.historicalExpenditures).toEqual(HAPPY_PANEL.points);
	});

	it('a rollup-read throw does NOT touch data.staleness', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockRejectedValueOnce(new Error('network blip'));
		stubHappyPanel();
		stubHappyStaleness(); // arms loadStalenessMock AND the contributor-map mocks quietly —
		// HAPPY_STALENESS.is_stale is false (known), so the contributor-map leg below DOES run.
		const data = await loadData(makeEvent());

		expect(data.staleness).toBe(HAPPY_STALENESS);
		expect(data.rollup).toBeNull();
	});
});

describe('load() — SELF-258 §2.3.2 per-row Sub-Cat staleness: contributor-map leg', () => {
	it('skips BOTH loadCashflowContributors and resolveStaleAccountIds when the root staleness read is unknown, degrading to the empty map', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		stubHappyPanel();
		loadStalenessMock.mockReset();
		loadStalenessMock.mockResolvedValueOnce(UNKNOWN_STALENESS);
		loadCashflowContributorsMock.mockReset();
		resolveStaleAccountIdsMock.mockReset();
		const data = await loadData(makeEvent());

		expect(loadCashflowContributorsMock).not.toHaveBeenCalled();
		expect(resolveStaleAccountIdsMock).not.toHaveBeenCalled();
		expect(data.cashflowRowStaleness).toEqual({});
	});

	it('calls loadCashflowContributors with the SAME asOf as the rollup, and resolveStaleAccountIds with the derived stale linked-source-id set', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		stubHappyPanel();
		loadStalenessMock.mockReset();
		loadStalenessMock.mockResolvedValueOnce({
			is_stale: true,
			stale_items: [
				{
					linked_source_id: '7',
					institution_name: 'Test Bank',
					provider: 'plaid',
					connection_status: 'error',
					status_class: 'error'
				}
			]
		});
		loadCashflowContributorsMock.mockReset();
		loadCashflowContributorsMock.mockResolvedValueOnce([]);
		resolveStaleAccountIdsMock.mockReset();
		resolveStaleAccountIdsMock.mockResolvedValueOnce(new Set());
		await load(makeEvent());

		expect(loadCashflowContributorsMock).toHaveBeenCalledTimes(1);
		const [, rollupAsOf] = loadCashflowCrossAccountRollupMock.mock.calls[0];
		const [, contributorsAsOf] = loadCashflowContributorsMock.mock.calls[0];
		expect(contributorsAsOf).toBe(rollupAsOf);

		expect(resolveStaleAccountIdsMock).toHaveBeenCalledTimes(1);
		const [, staleLinkedSourceIdsArg] = resolveStaleAccountIdsMock.mock.calls[0];
		expect(staleLinkedSourceIdsArg).toEqual(new Set(['7']));
	});

	it('a real contributor set with a confirmed-stale account threads through to data.cashflowRowStaleness, naming it', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		stubHappyPanel();
		loadStalenessMock.mockReset();
		loadStalenessMock.mockResolvedValueOnce({ is_stale: false, stale_items: [] });
		loadCashflowContributorsMock.mockReset();
		loadCashflowContributorsMock.mockResolvedValueOnce([
			{ cat: 'Revenue', sub_cat: 'Salary', sub_cat_id: 1, account_id: 100, account_name: 'Checking' }
		]);
		resolveStaleAccountIdsMock.mockReset();
		resolveStaleAccountIdsMock.mockResolvedValueOnce(new Set(['100']));
		const data = await loadData(makeEvent());

		expect(data.cashflowRowStaleness).toEqual({
			Revenue: { Salary: { is_stale: true, staleAccountNames: ['Checking'] } }
		});
	});

	it('an unexpected throw from loadCashflowContributors degrades data.cashflowRowStaleness to {} WITHOUT touching rollup/panel/staleness', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		stubHappyPanel();
		loadStalenessMock.mockReset();
		loadStalenessMock.mockResolvedValueOnce(HAPPY_STALENESS);
		loadCashflowContributorsMock.mockReset();
		loadCashflowContributorsMock.mockRejectedValueOnce(new Error('network blip'));
		resolveStaleAccountIdsMock.mockReset();
		const data = await loadData(makeEvent());

		expect(data.cashflowRowStaleness).toEqual({});
		expect(data.rollup).toBe(HAPPY_ROLLUP);
		expect(data.historicalExpenditures).toEqual(HAPPY_PANEL.points);
		expect(data.staleness).toBe(HAPPY_STALENESS);
	});

	it('a resolved null from loadCashflowContributors (its own internal fail-soft) also degrades to {} without calling resolveStaleAccountIds', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		stubHappyPanel();
		loadStalenessMock.mockReset();
		loadStalenessMock.mockResolvedValueOnce(HAPPY_STALENESS);
		loadCashflowContributorsMock.mockReset();
		loadCashflowContributorsMock.mockResolvedValueOnce(null);
		resolveStaleAccountIdsMock.mockReset();
		const data = await loadData(makeEvent());

		expect(resolveStaleAccountIdsMock).not.toHaveBeenCalled();
		expect(data.cashflowRowStaleness).toEqual({});
	});

	it('an unexpected throw from resolveStaleAccountIds degrades data.cashflowRowStaleness to {} WITHOUT touching data.staleness', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		stubHappyPanel();
		loadStalenessMock.mockReset();
		loadStalenessMock.mockResolvedValueOnce(HAPPY_STALENESS);
		loadCashflowContributorsMock.mockReset();
		loadCashflowContributorsMock.mockResolvedValueOnce([
			{ cat: 'Revenue', sub_cat: 'Salary', sub_cat_id: 1, account_id: 100, account_name: 'Checking' }
		]);
		resolveStaleAccountIdsMock.mockReset();
		resolveStaleAccountIdsMock.mockRejectedValueOnce(new Error('network blip'));
		const data = await loadData(makeEvent());

		expect(data.cashflowRowStaleness).toEqual({});
		expect(data.staleness).toBe(HAPPY_STALENESS);
	});

	it('a rollup-read throw does NOT prevent the contributor-map leg from resolving normally', async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockRejectedValueOnce(new Error('network blip'));
		stubHappyPanel();
		loadStalenessMock.mockReset();
		loadStalenessMock.mockResolvedValueOnce(HAPPY_STALENESS);
		loadCashflowContributorsMock.mockReset();
		loadCashflowContributorsMock.mockResolvedValueOnce([
			{ cat: 'Expense', sub_cat: 'Rent', sub_cat_id: 2, account_id: 200, account_name: 'Savings' }
		]);
		resolveStaleAccountIdsMock.mockReset();
		resolveStaleAccountIdsMock.mockResolvedValueOnce(new Set());
		const data = await loadData(makeEvent());

		expect(data.rollup).toBeNull();
		expect(data.cashflowRowStaleness).toEqual({
			Expense: { Rent: { is_stale: false, staleAccountNames: [] } }
		});
	});

	// Sec mid-flight condition on this leg (verbatim binding, relayed by team-lead): the SELF-330
	// fold this module is pointed at resolves an unrecognised account_id to FALSE
	// (nonReAllocation.ts's own subCatIsStale/resolveStaleAccountIds), which is correct THERE only
	// because resolveStaleAccountIds's RLS-scoped read means an invisible account can never be a
	// Set member in the first place — copied by analogy onto 099's account_name-null signal, that
	// same "not a member" absence would turn UNKNOWN back into FRESH one layer down, the exact
	// three-into-two collapse 099's SHAPE 3 ruling exists to prevent. This is the loader-level,
	// end-to-end version of that requirement (the pure-core version lives in
	// cashflowContributors.test.ts, "an otherwise ALL-FRESH row with ONE unresolvable contributor").
	it("SEC CONDITION: a NULL-account_name contributor on an otherwise all-fresh Sub-Cat row yields UNKNOWN, never FALSE", async () => {
		loadCashflowCrossAccountRollupMock.mockReset();
		loadCashflowCrossAccountRollupMock.mockResolvedValueOnce(HAPPY_ROLLUP);
		stubHappyPanel();
		loadStalenessMock.mockReset();
		loadStalenessMock.mockResolvedValueOnce(HAPPY_STALENESS);
		loadCashflowContributorsMock.mockReset();
		loadCashflowContributorsMock.mockResolvedValueOnce([
			{ cat: 'Revenue', sub_cat: 'Salary', sub_cat_id: 1, account_id: 100, account_name: 'Checking' },
			{ cat: 'Revenue', sub_cat: 'Salary', sub_cat_id: 1, account_id: 999, account_name: null }
		]);
		resolveStaleAccountIdsMock.mockReset();
		// Empty: 100 is confirmed NOT stale (a known, visible member-check miss); 999 is absent for a
		// DIFFERENT reason — the RLS-scoped bridge's own read cannot see it either, mirroring exactly
		// what resolveStaleAccountIds would really return for an account invisible to the caller.
		resolveStaleAccountIdsMock.mockResolvedValueOnce(new Set<string>());
		const data = await loadData(makeEvent());

		expect(data.cashflowRowStaleness).toEqual({
			Revenue: { Salary: { is_stale: null, staleAccountNames: [] } }
		});
	});
});
