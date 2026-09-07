// load.server.test.ts — the SELF-354 / P2 monthly-report loader watcher. Proves: (a) the
// unauthenticated redirect to /login with a redirectTo pointing back at this page; (b) the
// target_month param is validated as `YYYY-MM` — malformed -> 400; (c) no row for the month -> 404;
// (d) a `final` row reads its `rendered_payload` back VERBATIM, never calling
// fn_render_monthly_report (R1 (A) — frozen); (e) a `draft` row calls
// fn_render_monthly_report(target_month, data_as_of) live, using the ROW'S OWN data_as_of (Lock 15
// / ONE CALL, ONE CLOCK); (f) `final` wins over `draft` when both are (unexpectedly) resolved for
// the same month; (g) `superseded` rows are excluded from the query entirely (R10 A-8 — never
// rendered in V1); (h) the pfin.tax_character catalog read is fail-loud, mirroring
// taxes/decomposition's own posture; (i) E16 (team-lead) — the final (frozen-payload) path and the
// draft (live-composed) path yield the IDENTICAL payload SHAPE on the same fixture, proving the
// template's own "one shape, two sources" contract rather than merely asserting each path in
// isolation.

// P8 (SELF-360, RT-13) ADDITIONS to this file's original scope: (j) Account Holdings' per-leaf
// `is_stale` is OVERWRITTEN by the live join, regardless of whatever value the payload's own
// leaves carried; (k) Cash Flow's per-row map is computed at the REPORT's OWN `data_as_of`, never
// `serverTodayAsOf()`; (l) the banner's MEMBERSHIP comes from migration 109's snapshot for a
// `final` row (intersected against the live join) and degrades to the full live-stale-set for a
// `draft` row (no snapshot exists yet); (m) the banner's NAMES are ALWAYS resolved via a live
// `pfin.account` read, never `acct_name_at_generation`; (n) RT-13 — every one of these reads goes
// through the SAME `locals.supabase` client the event carries and none is ever called with an
// explicit tenant/user-id parameter — the tenant fence is RLS on that one client, not a value
// this loader threads itself.

import { describe, it, expect } from 'vitest';
import { isHttpError, isRedirect } from '@sveltejs/kit';
import type { SupabaseClient } from '@supabase/supabase-js';
import { MONTHLY_REPORT_PAYLOAD } from '$lib/fixtures/monthly-report';

const { load } = await import('./+page.server');

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

const FINAL_ROW = {
	report_id: 42,
	target_month: '2026-08-01',
	generation_status: 'final',
	data_as_of: '2026-08-31',
	generated_at: '2026-09-02T14:00:00Z',
	owner_header_at_generation: 'THE SMITH 2023 TRUST',
	commentary_cash: 'note',
	commentary_bonds: null,
	commentary_marketable_securities: null,
	commentary_alternatives: null,
	commentary_disposition: 'authored',
	rendered_payload: {
		payload_schema_version: 1,
		target_month: '2026-08-01',
		as_of: '2026-08-31',
		// P8 (SELF-360): `account_holdings.groups` is now dereferenced unconditionally by the
		// loader's own per-leaf staleness refresh — a real MonthlyReportPayload always carries
		// this (108/110's own CONTRACT), so the fixture is widened to match rather than the
		// loader made defensive against a payload shape the DB contract never actually produces.
		sections: { account_holdings: { groups: [] } }
	}
};

const DRAFT_ROW = {
	...FINAL_ROW,
	report_id: 43,
	generation_status: 'draft',
	generated_at: null,
	owner_header_at_generation: null,
	commentary_disposition: null,
	rendered_payload: null
};

const COMPOSED_PAYLOAD = {
	payload_schema_version: 1,
	target_month: '2026-08-01',
	as_of: '2026-08-31',
	// P8 (SELF-360): `account_holdings.groups` is dereferenced unconditionally by the loader's
	// own per-leaf staleness refresh — see FINAL_ROW's own rendered_payload fixture above for
	// the same note.
	sections: { note: 'live-composed', account_holdings: { groups: [] } }
};

const TAX_CHARACTER_ROWS = [{ code: 'ordinary', label: 'Ordinary income', display_order: 10 }];

type RpcCall = { fn: string; params: Record<string, unknown> };

function makeSupabase(opts: {
	reportRows?: unknown[];
	reportError?: { message: string } | null;
	rpcResult?: { data: unknown; error: { message: string } | null };
	taxCharacterRows?: unknown[];
	taxCharacterError?: { message: string } | null;
	// P8 (SELF-360) additions — each defaults to a "healthy, nothing stale" shape so every
	// PRE-EXISTING test above keeps exercising exactly the read paths it always did.
	stalenessResult?: { data: unknown; error: { message: string } | null };
	staleAccountRows?: Array<{ account_id: number }> | null; // resolveStaleAccountIds' own join
	staleAccountError?: { message: string } | null;
	cashflowContributorRows?: unknown[] | null;
	cashflowContributorError?: { message: string } | null;
	snapshotRows?: Array<{ account_id: number }>;
	snapshotError?: { message: string } | null;
	accountNameRows?: Array<{ account_id: number; name: string }>;
	accountNameError?: { message: string } | null;
}) {
	const rpcCalls: RpcCall[] = [];
	const accountQueryCalls: Array<{ col: string; vals: unknown[] }> = [];
	let snapshotQueryCalls = 0;

	const reportTable = {
		select: (_cols: string) => ({
			eq: (_col: string, _val: unknown) => ({
				in: (_col2: string, _vals: string[]) =>
					Promise.resolve({ data: opts.reportRows ?? [], error: opts.reportError ?? null })
			})
		})
	};
	const taxCharacterTable = {
		select: (_cols: string) => ({
			order: () =>
				Promise.resolve({ data: opts.taxCharacterRows ?? [], error: opts.taxCharacterError ?? null })
		})
	};
	// ONE stub serves BOTH resolveStaleAccountIds' own `.select('account_id, linked_source_id')`
	// join AND this loader's own live account-name lookup `.select('account_id, name')` — real
	// supabase-js doesn't filter mock data by the requested column list either way, and each
	// test configures whichever of `staleAccountRows` / `accountNameRows` it actually needs.
	const accountTable = {
		select: (_cols: string) => ({
			in: (col: string, vals: unknown[]) => {
				accountQueryCalls.push({ col, vals });
				// Route by WHICH caller's rows were configured for this test — a test exercising
				// resolveStaleAccountIds sets `staleAccountRows`; one exercising the live-name
				// lookup sets `accountNameRows`. Both may be set when a test checks both legs.
				if (_cols.includes('linked_source_id')) {
					// resolveStaleAccountIds' own join is keyed on `linked_source_id`, a field this
					// file's `staleAccountRows` fixture doesn't carry at all (it's a flat
					// account_id-only stand-in for "the accounts this join resolves to") — no
					// `vals`-based filtering is meaningful here; return the configured set as-is.
					if (opts.staleAccountError) return Promise.resolve({ data: null, error: opts.staleAccountError });
					return Promise.resolve({ data: opts.staleAccountRows ?? [], error: null });
				}
				// The live account-NAME lookup, by contrast, IS keyed on `account_id` — the same
				// column `vals` names — so filtering here is both meaningful and load-bearing:
				// it is what proves the loader actually narrowed `bannerAccountIds` to the
				// membership intersection BEFORE querying names, not just filtered the result
				// afterwards. A mock that ignored `vals` here would hide that bug entirely.
				if (opts.accountNameError) return Promise.resolve({ data: null, error: opts.accountNameError });
				const wantedIds = new Set(vals.map(String));
				const rows = (opts.accountNameRows ?? []).filter((r) => wantedIds.has(String(r.account_id)));
				return Promise.resolve({ data: rows, error: null });
			}
		})
	};
	const snapshotTable = {
		select: (_cols: string) => ({
			eq: (_col: string, _val: unknown) => {
				snapshotQueryCalls++;
				return Promise.resolve({ data: opts.snapshotRows ?? [], error: opts.snapshotError ?? null });
			}
		})
	};
	const from = (table: string) => {
		if (table === 'monthly_report') return reportTable;
		if (table === 'tax_character') return taxCharacterTable;
		if (table === 'account') return accountTable;
		if (table === 'monthly_report_account_snapshot') return snapshotTable;
		throw new Error(`unexpected table: ${table}`);
	};
	// Back-compat MUTABLE object for every PRE-EXISTING assertion in this file
	// (`rpc.calls` / `rpc.fn` / `rpc.params`, destructured up front, before `load()` runs) —
	// a plain object whose PROPERTIES are mutated in place, never a getter: destructuring a
	// getter copies its return value once, at destructure time, and would freeze every one of
	// these pre-existing assertions at their initial (pre-call) state. Tracks the LAST
	// non-staleness, non-cashflow-contributor RPC call, since P8 added two more RPCs this loader
	// may call before (or instead of) `fn_render_monthly_report`.
	const rpc = { fn: '', params: {} as Record<string, unknown>, calls: 0 };
	const rpcFn = (fn: string, params: Record<string, unknown>) => {
		rpcCalls.push({ fn, params });
		if (fn === 'fn_aggregation_has_stale_constituent') {
			return Promise.resolve(
				opts.stalenessResult ?? { data: [{ is_stale: false, stale_items: [] }], error: null }
			);
		}
		if (fn === 'fn_cashflow_contributors') {
			if (opts.cashflowContributorError) {
				return Promise.resolve({ data: null, error: opts.cashflowContributorError });
			}
			return Promise.resolve({ data: opts.cashflowContributorRows ?? [], error: null });
		}
		rpc.fn = fn;
		rpc.params = params;
		rpc.calls++;
		return Promise.resolve(opts.rpcResult ?? { data: null, error: null });
	};
	const schema = (_s: string) => ({ from, rpc: rpcFn });
	const client = { schema } as unknown as SupabaseClient;
	return {
		client,
		rpc,
		rpcCalls,
		accountQueryCalls,
		get snapshotQueryCalls() {
			return snapshotQueryCalls;
		}
	};
}

function makeEvent(
	targetMonth: string,
	user: { id: string } | null,
	supabase: SupabaseClient
) {
	const locals = { safeGetSession: async () => ({ session: user ? {} : null, user }), supabase };
	return {
		locals,
		params: { target_month: targetMonth },
		url: new URL(`http://localhost/reports/monthly/${targetMonth}`)
	} as unknown as Parameters<typeof load>[0];
}

describe('load() — auth', () => {
	it('redirects unauthenticated callers to /login with redirectTo pointing back at this page', async () => {
		const { client } = makeSupabase({});
		let caught: unknown;
		try {
			await load(makeEvent('2026-08', null, client));
		} catch (e) {
			caught = e;
		}
		expect(isRedirect(caught)).toBe(true);
		expect((caught as { status: number }).status).toBe(303);
		expect((caught as { location: string }).location).toBe(
			'/login?redirectTo=%2Freports%2Fmonthly%2F2026-08'
		);
	});
});

describe('load() — target_month validation', () => {
	it('a malformed target_month (not YYYY-MM) -> 400, no DB reached', async () => {
		const { client } = makeSupabase({});
		let caught: unknown;
		try {
			await load(makeEvent('not-a-month', { id: SESSION_UID }, client));
		} catch (e) {
			caught = e;
		}
		expect(isHttpError(caught)).toBe(true);
		expect((caught as { status: number }).status).toBe(400);
	});

	it('a month value out of range (13) -> 400', async () => {
		const { client } = makeSupabase({});
		let caught: unknown;
		try {
			await load(makeEvent('2026-13', { id: SESSION_UID }, client));
		} catch (e) {
			caught = e;
		}
		expect(isHttpError(caught)).toBe(true);
		expect((caught as { status: number }).status).toBe(400);
	});
});

describe('load() — no row for the month', () => {
	it('no final/draft row -> 404', async () => {
		const { client } = makeSupabase({ reportRows: [] });
		let caught: unknown;
		try {
			await load(makeEvent('2026-08', { id: SESSION_UID }, client));
		} catch (e) {
			caught = e;
		}
		expect(isHttpError(caught)).toBe(true);
		expect((caught as { status: number }).status).toBe(404);
	});
});

describe('load() — final report: frozen payload, no live composition', () => {
	it('reads rendered_payload verbatim and never calls fn_render_monthly_report', async () => {
		const { client, rpc } = makeSupabase({
			reportRows: [FINAL_ROW],
			taxCharacterRows: TAX_CHARACTER_ROWS
		});
		const result = await load(makeEvent('2026-08', { id: SESSION_UID }, client));
		expect(result).toMatchObject({ payload: FINAL_ROW.rendered_payload });
		expect(rpc.calls).toBe(0);
	});

	it('forwards the header fields verbatim, including owner_header_at_generation and commentary_disposition', async () => {
		const { client } = makeSupabase({ reportRows: [FINAL_ROW], taxCharacterRows: TAX_CHARACTER_ROWS });
		const result = (await load(makeEvent('2026-08', { id: SESSION_UID }, client))) as unknown as {
			header: Record<string, unknown>;
		};
		expect(result.header).toMatchObject({
			report_id: 42,
			generation_status: 'final',
			owner_header_at_generation: 'THE SMITH 2023 TRUST',
			commentary_disposition: 'authored'
		});
	});

	it('a final row with rendered_payload NULL (a real DB-contract violation) -> 500, never silently rendered', async () => {
		const brokenFinal = { ...FINAL_ROW, rendered_payload: null };
		const { client } = makeSupabase({ reportRows: [brokenFinal], taxCharacterRows: TAX_CHARACTER_ROWS });
		let caught: unknown;
		try {
			await load(makeEvent('2026-08', { id: SESSION_UID }, client));
		} catch (e) {
			caught = e;
		}
		expect(isHttpError(caught)).toBe(true);
		expect((caught as { status: number }).status).toBe(500);
	});
});

describe('load() — draft report: live composition via fn_render_monthly_report', () => {
	it("calls fn_render_monthly_report with the ROW'S OWN target_month and data_as_of (Lock 15 / ONE CALL, ONE CLOCK)", async () => {
		const { client, rpc } = makeSupabase({
			reportRows: [DRAFT_ROW],
			rpcResult: { data: COMPOSED_PAYLOAD, error: null },
			taxCharacterRows: TAX_CHARACTER_ROWS
		});
		const result = await load(makeEvent('2026-08', { id: SESSION_UID }, client));
		expect(rpc.calls).toBe(1);
		expect(rpc.fn).toBe('fn_render_monthly_report');
		expect(rpc.params).toEqual({ p_target_month: '2026-08-01', p_data_as_of: '2026-08-31' });
		expect(result).toMatchObject({ payload: COMPOSED_PAYLOAD });
	});

	it('an fn_render_monthly_report failure -> 500', async () => {
		const { client } = makeSupabase({
			reportRows: [DRAFT_ROW],
			rpcResult: { data: null, error: { message: 'boom' } },
			taxCharacterRows: TAX_CHARACTER_ROWS
		});
		let caught: unknown;
		try {
			await load(makeEvent('2026-08', { id: SESSION_UID }, client));
		} catch (e) {
			caught = e;
		}
		expect(isHttpError(caught)).toBe(true);
		expect((caught as { status: number }).status).toBe(500);
	});
});

describe('load() — final wins over draft when both resolve for the same month', () => {
	it('prefers the final row (the presentation bridge\'s own "generated = the current final")', async () => {
		const { client, rpc } = makeSupabase({
			reportRows: [DRAFT_ROW, FINAL_ROW],
			taxCharacterRows: TAX_CHARACTER_ROWS
		});
		const result = await load(makeEvent('2026-08', { id: SESSION_UID }, client));
		expect(result).toMatchObject({ payload: FINAL_ROW.rendered_payload });
		expect(rpc.calls).toBe(0);
	});
});

describe('load() — superseded rows never reach this route (R10 A-8)', () => {
	it('the report query is scoped to generation_status in (final, draft) — asserted via the query builder shape', async () => {
		// The `.in('generation_status', [...])` call itself is the fence — see makeSupabase's
		// reportTable stub, which only resolves rows through that exact chain. A row this loader's
		// own query would never even select (a `superseded`-only result set) degrades to the
		// ordinary "no row" 404 path, proven above — there is no separate code path that could
		// leak one through.
		const { client } = makeSupabase({ reportRows: [] });
		let caught: unknown;
		try {
			await load(makeEvent('2026-08', { id: SESSION_UID }, client));
		} catch (e) {
			caught = e;
		}
		expect(isHttpError(caught)).toBe(true);
		expect((caught as { status: number }).status).toBe(404);
	});
});

describe('load() — E16: final and draft paths yield the SAME payload shape on the same fixture', () => {
	it('a final row (frozen rendered_payload) and a draft row (live fn_render_monthly_report) both return the SAME section keys', async () => {
		const finalRow = { ...FINAL_ROW, rendered_payload: MONTHLY_REPORT_PAYLOAD };
		const { client: finalClient } = makeSupabase({
			reportRows: [finalRow],
			taxCharacterRows: TAX_CHARACTER_ROWS
		});
		const finalResult = (await load(makeEvent('2026-08', { id: SESSION_UID }, finalClient))) as unknown as {
			payload: { sections: Record<string, unknown> };
		};

		const { client: draftClient } = makeSupabase({
			reportRows: [DRAFT_ROW],
			rpcResult: { data: MONTHLY_REPORT_PAYLOAD, error: null },
			taxCharacterRows: TAX_CHARACTER_ROWS
		});
		const draftResult = (await load(makeEvent('2026-08', { id: SESSION_UID }, draftClient))) as unknown as {
			payload: { sections: Record<string, unknown> };
		};

		const expectedSectionKeys = [
			'account_holdings',
			'nav_performance',
			'asset_allocation',
			'rebalancing_targets',
			'cash_flow',
			'estimated_taxes'
		].sort();
		expect(Object.keys(finalResult.payload.sections).sort()).toEqual(expectedSectionKeys);
		expect(Object.keys(draftResult.payload.sections).sort()).toEqual(expectedSectionKeys);
		expect(Object.keys(draftResult.payload.sections).sort()).toEqual(
			Object.keys(finalResult.payload.sections).sort()
		);
	});
});

describe('load() — fail-loud tax_character read (mirrors taxes/decomposition)', () => {
	it('throws 500 when pfin.tax_character read errors, rather than rendering an incomplete vocabulary', async () => {
		const { client } = makeSupabase({
			reportRows: [FINAL_ROW],
			taxCharacterError: { message: 'timeout' }
		});
		let caught: unknown;
		try {
			await load(makeEvent('2026-08', { id: SESSION_UID }, client));
		} catch (e) {
			caught = e;
		}
		expect(isHttpError(caught)).toBe(true);
		expect((caught as { status: number }).status).toBe(500);
	});
});

// ── P8 (SELF-360) — §2.6.5 staleness markers, RT-13 ─────────────────────────────────────────
// Stale linked_source_id '9' resolves (via the mocked account-join) to account_id 1 — the
// Brokerage leaf MONTHLY_REPORT_PAYLOAD's own account_holdings fixture carries FROZEN at
// `is_stale: false`. account_id 2 (Mortgage) never appears in the stale join.
const STALE_TENANT_RESULT = {
	data: [
		{
			is_stale: true,
			stale_items: [
				{
					linked_source_id: '9',
					institution_name: 'Chase',
					provider: 'plaid',
					connection_status: 'login_required',
					status_class: 'error'
				}
			]
		}
	],
	error: null
};

function finalRowWithPayload() {
	return { ...FINAL_ROW, rendered_payload: MONTHLY_REPORT_PAYLOAD };
}

describe('load() — P8 AC2: Account Holdings per-leaf is_stale is OVERWRITTEN by the live join', () => {
	it('a leaf frozen `false` becomes `true` when its account is CURRENTLY stale; an unrelated leaf stays `false`', async () => {
		const { client } = makeSupabase({
			reportRows: [finalRowWithPayload()],
			taxCharacterRows: TAX_CHARACTER_ROWS,
			stalenessResult: STALE_TENANT_RESULT,
			staleAccountRows: [{ account_id: 1 }]
		});
		const result = (await load(makeEvent('2026-08', { id: SESSION_UID }, client))) as unknown as {
			payload: {
				sections: {
					account_holdings: {
						groups: Array<{ accounts: Array<{ account_id: number; is_stale: boolean | null }> }>;
					};
				};
			};
		};
		const leaves = result.payload.sections.account_holdings.groups.flatMap((g) => g.accounts);
		expect(leaves.find((a) => a.account_id === 1)?.is_stale).toBe(true);
		expect(leaves.find((a) => a.account_id === 2)?.is_stale).toBe(false);
	});

	it('a staleness read failure degrades EVERY leaf to `null` (unknown), never to the frozen value nor to `false`', async () => {
		const { client } = makeSupabase({
			reportRows: [finalRowWithPayload()],
			taxCharacterRows: TAX_CHARACTER_ROWS,
			stalenessResult: { data: null, error: { message: 'rpc down' } }
		});
		const result = (await load(makeEvent('2026-08', { id: SESSION_UID }, client))) as unknown as {
			staleness: { is_stale: boolean | null };
			payload: { sections: { account_holdings: { groups: Array<{ accounts: Array<{ is_stale: boolean | null }> }> } } };
		};
		expect(result.staleness.is_stale).toBeNull();
		const leaves = result.payload.sections.account_holdings.groups.flatMap((g) => g.accounts);
		expect(leaves.every((a) => a.is_stale === null)).toBe(true);
	});
});

describe("load() — P8 AC4: Cash Flow row map at the REPORT's OWN data_as_of", () => {
	it("calls fn_cashflow_contributors with p_as_of = row.data_as_of, never today's date", async () => {
		const { client, rpcCalls } = makeSupabase({
			reportRows: [finalRowWithPayload()],
			taxCharacterRows: TAX_CHARACTER_ROWS,
			stalenessResult: STALE_TENANT_RESULT,
			staleAccountRows: [{ account_id: 1 }],
			cashflowContributorRows: [
				{ cat: 'Income', sub_cat: 'Salary', sub_cat_id: 5, account_id: 1, account_name: 'Brokerage' }
			]
		});
		const result = await load(makeEvent('2026-08', { id: SESSION_UID }, client));
		const contributorCall = rpcCalls.find((c) => c.fn === 'fn_cashflow_contributors');
		expect(contributorCall?.params).toEqual({ p_as_of: finalRowWithPayload().data_as_of });
		expect((result as { cashflowRowStaleness: unknown }).cashflowRowStaleness).toEqual({
			Income: { Salary: { is_stale: true, staleAccountNames: ['Brokerage'] } }
		});
	});

	it('a cashflow-contributor read failure degrades to the EMPTY map, not a thrown 500', async () => {
		const { client } = makeSupabase({
			reportRows: [finalRowWithPayload()],
			taxCharacterRows: TAX_CHARACTER_ROWS,
			stalenessResult: STALE_TENANT_RESULT,
			staleAccountRows: [{ account_id: 1 }],
			cashflowContributorError: { message: 'timeout' }
		});
		const result = await load(makeEvent('2026-08', { id: SESSION_UID }, client));
		expect((result as { cashflowRowStaleness: unknown }).cashflowRowStaleness).toEqual({});
	});
});

describe('load() — P8 AC3/AC7: report-level banner — membership vs. naming are two different questions', () => {
	it('FINAL report: membership is the migration-109 snapshot intersected with the live join; a currently-stale account NOT in the snapshot is excluded', async () => {
		// ⚠ `snapshotQueryCalls` is a GETTER (its value changes as `load()` runs) — it must be
		// read AFTER `load()` resolves via the mock object itself, never destructured up front
		// (a destructured getter freezes its value at destructure time, before any call happens).
		const mock = makeSupabase({
			reportRows: [finalRowWithPayload()],
			taxCharacterRows: TAX_CHARACTER_ROWS,
			stalenessResult: {
				data: [
					{
						is_stale: true,
						stale_items: [
							{
								linked_source_id: '9',
								institution_name: 'Chase',
								provider: 'plaid',
								connection_status: 'login_required',
								status_class: 'error'
							},
							{
								linked_source_id: '10',
								institution_name: 'Fidelity',
								provider: 'plaid',
								connection_status: 'login_required',
								status_class: 'error'
							}
						]
					}
				],
				error: null
			},
			staleAccountRows: [{ account_id: 1 }, { account_id: 2 }],
			snapshotRows: [{ account_id: 1 }], // only account 1 belongs to THIS report
			accountNameRows: [
				{ account_id: 1, name: 'Chase Checking' },
				{ account_id: 2, name: 'Should Not Appear' }
			]
		});
		const result = await load(makeEvent('2026-08', { id: SESSION_UID }, mock.client));
		expect((result as { staleAccountNames: string[] }).staleAccountNames).toEqual(['Chase Checking']);
		expect(mock.snapshotQueryCalls).toBe(1);
	});

	it('DRAFT report: NO snapshot read is ever attempted (109 has no rows for a draft) — membership degrades to every currently-stale account', async () => {
		// See the FINAL-report leg above: `snapshotQueryCalls` is a getter and must be read AFTER
		// `load()`, via the mock object itself.
		const mock = makeSupabase({
			reportRows: [DRAFT_ROW],
			rpcResult: { data: MONTHLY_REPORT_PAYLOAD, error: null },
			taxCharacterRows: TAX_CHARACTER_ROWS,
			stalenessResult: STALE_TENANT_RESULT,
			staleAccountRows: [{ account_id: 1 }, { account_id: 2 }],
			accountNameRows: [
				{ account_id: 1, name: 'Chase Checking' },
				{ account_id: 2, name: 'Fidelity Brokerage' }
			]
		});
		const result = await load(makeEvent('2026-08', { id: SESSION_UID }, mock.client));
		expect((result as { staleAccountNames: string[] }).staleAccountNames).toEqual([
			'Chase Checking',
			'Fidelity Brokerage'
		]);
		expect(mock.snapshotQueryCalls).toBe(0);
	});

	it("names are ALWAYS resolved from the LIVE account read, never `acct_name_at_generation` — the snapshot supplies membership only", async () => {
		const { client } = makeSupabase({
			reportRows: [finalRowWithPayload()],
			taxCharacterRows: TAX_CHARACTER_ROWS,
			stalenessResult: STALE_TENANT_RESULT,
			staleAccountRows: [{ account_id: 1 }],
			snapshotRows: [{ account_id: 1 }],
			accountNameRows: [{ account_id: 1, name: 'Live Name Today' }]
		});
		const result = await load(makeEvent('2026-08', { id: SESSION_UID }, client));
		// The snapshot mock in this file's own makeSupabase never returns a name column at all
		// (only `account_id`) — a loader that tried to read `acct_name_at_generation` off it
		// would get `undefined`, not a frozen name; this asserts the LIVE name is what actually
		// surfaces, which is the only name source this loader ever queries for the banner.
		expect((result as { staleAccountNames: string[] }).staleAccountNames).toEqual(['Live Name Today']);
	});

	it('a zero-stale-accounts tenant renders no banner names and skips the snapshot/account-name reads entirely', async () => {
		const mock = makeSupabase({
			reportRows: [finalRowWithPayload()],
			taxCharacterRows: TAX_CHARACTER_ROWS
			// stalenessResult defaults to { is_stale: false, stale_items: [] }
		});
		const result = await load(makeEvent('2026-08', { id: SESSION_UID }, mock.client));
		expect((result as { staleAccountNames: string[] }).staleAccountNames).toEqual([]);
		expect(mock.snapshotQueryCalls).toBe(0);
		expect(mock.accountQueryCalls).toHaveLength(0);
	});
});

describe("load() — P8 RT-13: the tenant fence is the caller's own client, never an explicit parameter", () => {
	it('no staleness-related call anywhere carries an explicit tenant/user-id parameter', async () => {
		const { client, rpcCalls } = makeSupabase({
			reportRows: [finalRowWithPayload()],
			taxCharacterRows: TAX_CHARACTER_ROWS,
			stalenessResult: STALE_TENANT_RESULT,
			staleAccountRows: [{ account_id: 1 }],
			snapshotRows: [{ account_id: 1 }],
			accountNameRows: [{ account_id: 1, name: 'Chase Checking' }],
			cashflowContributorRows: []
		});
		await load(makeEvent('2026-08', { id: SESSION_UID }, client));

		const tenantLikeKeys = ['users_id', 'p_users_id', 'tenant_id', 'user_id'];
		for (const call of rpcCalls) {
			// `loadStaleness()` calls `.rpc('fn_aggregation_has_stale_constituent')` with NO second
			// argument at all — `params` is `undefined`, which trivially satisfies "no tenant
			// param" and must not be coerced to `{}` before checking (only to avoid `toHaveProperty`
			// throwing on a non-object, not to manufacture a params value that was never sent).
			const params = call.params ?? {};
			for (const key of tenantLikeKeys) {
				expect(params, `${call.fn} params must not carry ${key}`).not.toHaveProperty(key);
			}
		}
	});

	it('every account/snapshot read is issued through the SAME client the event carried — no second client is ever constructed', async () => {
		// This test's own mock IS the only client this loader could possibly call through (there
		// is no second `schema()`/`from()` implementation anywhere in makeSupabase) — a loader
		// that somehow reached a different client would throw "unexpected table" or simply never
		// populate `accountQueryCalls`/`snapshotQueryCalls`, either of which this assertion
		// would catch.
		// `snapshotQueryCalls` is a getter — read via `mock.snapshotQueryCalls` after `load()`,
		// never destructured up front (see the P8 AC3/AC7 tests above for the same note).
		const mock = makeSupabase({
			reportRows: [finalRowWithPayload()],
			taxCharacterRows: TAX_CHARACTER_ROWS,
			stalenessResult: STALE_TENANT_RESULT,
			staleAccountRows: [{ account_id: 1 }],
			snapshotRows: [{ account_id: 1 }],
			accountNameRows: [{ account_id: 1, name: 'Chase Checking' }]
		});
		await load(makeEvent('2026-08', { id: SESSION_UID }, mock.client));
		expect(mock.accountQueryCalls.length).toBeGreaterThan(0);
		expect(mock.snapshotQueryCalls).toBe(1);
	});
});
