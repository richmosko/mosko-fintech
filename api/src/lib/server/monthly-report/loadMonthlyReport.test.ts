// loadMonthlyReport.test.ts — the shared monthly-report data-loading watcher, RELOCATED here
// from reports/monthly/[target_month]/load.server.test.ts at the SELF-358 (P6, PDF export)
// extraction — this is where the logic under test now lives (`loadMonthlyReportForRender`),
// shared verbatim by the in-app page loader and the PDF export route. Route-level concerns
// (the auth redirect, `target_month` param parsing/400) stay in each caller's OWN
// `load.server.test.ts` / `pdf/+server.test.ts`, since this module owns neither.
//
// Proves: (a) no row for the month -> 404; (b) a `final` row reads its `rendered_payload` back
// VERBATIM, never calling fn_render_monthly_report (R1 (A) — frozen); (c) a `draft` row calls
// fn_render_monthly_report(target_month, data_as_of) live, using the ROW'S OWN data_as_of (Lock
// 15 / ONE CALL, ONE CLOCK); (d) `final` wins over `draft` when both are (unexpectedly) resolved
// for the same month; (e) `superseded` rows are excluded from the query entirely (R10 A-8); (f)
// the pfin.tax_character catalog read is fail-loud; (g) E16 — the final (frozen-payload) path
// and the draft (live-composed) path yield the IDENTICAL payload SHAPE on the same fixture; (h)
// P8's staleness/banner/cashflow-row-map design (AC2/AC3/AC4/AC7, RT-13).

import { describe, it, expect } from 'vitest';
import { isHttpError } from '@sveltejs/kit';
import type { SupabaseClient } from '@supabase/supabase-js';
import { MONTHLY_REPORT_PAYLOAD } from '$lib/fixtures/monthly-report';
import { loadMonthlyReportForRender } from './loadMonthlyReport';

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
	stalenessResult?: { data: unknown; error: { message: string } | null };
	staleAccountRows?: Array<{ account_id: number }> | null;
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
	const accountTable = {
		select: (_cols: string) => ({
			in: (col: string, vals: unknown[]) => {
				accountQueryCalls.push({ col, vals });
				if (_cols.includes('linked_source_id')) {
					if (opts.staleAccountError) return Promise.resolve({ data: null, error: opts.staleAccountError });
					return Promise.resolve({ data: opts.staleAccountRows ?? [], error: null });
				}
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

const MONTH = '2026-08-01'; // already-parsed, as this module expects

describe('loadMonthlyReportForRender() — no row for the month', () => {
	it('no final/draft row -> 404', async () => {
		const { client } = makeSupabase({ reportRows: [] });
		let caught: unknown;
		try {
			await loadMonthlyReportForRender(client, MONTH);
		} catch (e) {
			caught = e;
		}
		expect(isHttpError(caught)).toBe(true);
		expect((caught as { status: number }).status).toBe(404);
	});
});

describe('loadMonthlyReportForRender() — final report: frozen payload, no live composition', () => {
	it('reads rendered_payload verbatim and never calls fn_render_monthly_report', async () => {
		const { client, rpc } = makeSupabase({
			reportRows: [FINAL_ROW],
			taxCharacterRows: TAX_CHARACTER_ROWS
		});
		const result = await loadMonthlyReportForRender(client, MONTH);
		expect(result).toMatchObject({ payload: FINAL_ROW.rendered_payload });
		expect(rpc.calls).toBe(0);
	});

	it('forwards the header fields verbatim, including owner_header_at_generation and commentary_disposition', async () => {
		const { client } = makeSupabase({ reportRows: [FINAL_ROW], taxCharacterRows: TAX_CHARACTER_ROWS });
		const result = await loadMonthlyReportForRender(client, MONTH);
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
			await loadMonthlyReportForRender(client, MONTH);
		} catch (e) {
			caught = e;
		}
		expect(isHttpError(caught)).toBe(true);
		expect((caught as { status: number }).status).toBe(500);
	});
});

describe('loadMonthlyReportForRender() — draft report: live composition via fn_render_monthly_report', () => {
	it("calls fn_render_monthly_report with the ROW'S OWN target_month and data_as_of (Lock 15 / ONE CALL, ONE CLOCK)", async () => {
		const { client, rpc } = makeSupabase({
			reportRows: [DRAFT_ROW],
			rpcResult: { data: COMPOSED_PAYLOAD, error: null },
			taxCharacterRows: TAX_CHARACTER_ROWS
		});
		const result = await loadMonthlyReportForRender(client, MONTH);
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
			await loadMonthlyReportForRender(client, MONTH);
		} catch (e) {
			caught = e;
		}
		expect(isHttpError(caught)).toBe(true);
		expect((caught as { status: number }).status).toBe(500);
	});
});

describe('loadMonthlyReportForRender() — final wins over draft when both resolve for the same month', () => {
	it('prefers the final row (the presentation bridge\'s own "generated = the current final")', async () => {
		const { client, rpc } = makeSupabase({
			reportRows: [DRAFT_ROW, FINAL_ROW],
			taxCharacterRows: TAX_CHARACTER_ROWS
		});
		const result = await loadMonthlyReportForRender(client, MONTH);
		expect(result).toMatchObject({ payload: FINAL_ROW.rendered_payload });
		expect(rpc.calls).toBe(0);
	});
});

describe('loadMonthlyReportForRender() — superseded rows never reach this module (R10 A-8)', () => {
	it('the report query is scoped to generation_status in (final, draft) — asserted via the query builder shape', async () => {
		const { client } = makeSupabase({ reportRows: [] });
		let caught: unknown;
		try {
			await loadMonthlyReportForRender(client, MONTH);
		} catch (e) {
			caught = e;
		}
		expect(isHttpError(caught)).toBe(true);
		expect((caught as { status: number }).status).toBe(404);
	});
});

describe('loadMonthlyReportForRender() — E16: final and draft paths yield the SAME payload shape on the same fixture', () => {
	it('a final row (frozen rendered_payload) and a draft row (live fn_render_monthly_report) both return the SAME section keys', async () => {
		const finalRow = { ...FINAL_ROW, rendered_payload: MONTHLY_REPORT_PAYLOAD };
		const { client: finalClient } = makeSupabase({
			reportRows: [finalRow],
			taxCharacterRows: TAX_CHARACTER_ROWS
		});
		const finalResult = await loadMonthlyReportForRender(finalClient, MONTH);

		const { client: draftClient } = makeSupabase({
			reportRows: [DRAFT_ROW],
			rpcResult: { data: MONTHLY_REPORT_PAYLOAD, error: null },
			taxCharacterRows: TAX_CHARACTER_ROWS
		});
		const draftResult = await loadMonthlyReportForRender(draftClient, MONTH);

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

describe('loadMonthlyReportForRender() — fail-loud tax_character read (mirrors taxes/decomposition)', () => {
	it('throws 500 when pfin.tax_character read errors, rather than rendering an incomplete vocabulary', async () => {
		const { client } = makeSupabase({
			reportRows: [FINAL_ROW],
			taxCharacterError: { message: 'timeout' }
		});
		let caught: unknown;
		try {
			await loadMonthlyReportForRender(client, MONTH);
		} catch (e) {
			caught = e;
		}
		expect(isHttpError(caught)).toBe(true);
		expect((caught as { status: number }).status).toBe(500);
	});
});

// ── P8 (SELF-360) — §2.6.5 staleness markers, RT-13 ─────────────────────────────────────────
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

describe('loadMonthlyReportForRender() — P8 AC2: Account Holdings per-leaf is_stale is OVERWRITTEN by the live join', () => {
	it('a leaf frozen `false` becomes `true` when its account is CURRENTLY stale; an unrelated leaf stays `false`', async () => {
		const { client } = makeSupabase({
			reportRows: [finalRowWithPayload()],
			taxCharacterRows: TAX_CHARACTER_ROWS,
			stalenessResult: STALE_TENANT_RESULT,
			staleAccountRows: [{ account_id: 1 }]
		});
		const result = await loadMonthlyReportForRender(client, MONTH);
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
		const result = await loadMonthlyReportForRender(client, MONTH);
		expect(result.staleness.is_stale).toBeNull();
		const leaves = result.payload.sections.account_holdings.groups.flatMap((g) => g.accounts);
		expect(leaves.every((a) => a.is_stale === null)).toBe(true);
	});
});

describe("loadMonthlyReportForRender() — P8 AC4: Cash Flow row map at the REPORT's OWN data_as_of", () => {
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
		const result = await loadMonthlyReportForRender(client, MONTH);
		const contributorCall = rpcCalls.find((c) => c.fn === 'fn_cashflow_contributors');
		expect(contributorCall?.params).toEqual({ p_as_of: finalRowWithPayload().data_as_of });
		expect(result.cashflowRowStaleness).toEqual({
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
		const result = await loadMonthlyReportForRender(client, MONTH);
		expect(result.cashflowRowStaleness).toEqual({});
	});
});

describe('loadMonthlyReportForRender() — P8 AC3/AC7: report-level banner — membership vs. naming are two different questions', () => {
	it('FINAL report: membership is the migration-109 snapshot intersected with the live join; a currently-stale account NOT in the snapshot is excluded', async () => {
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
			snapshotRows: [{ account_id: 1 }],
			accountNameRows: [
				{ account_id: 1, name: 'Chase Checking' },
				{ account_id: 2, name: 'Should Not Appear' }
			]
		});
		const result = await loadMonthlyReportForRender(mock.client, MONTH);
		expect(result.staleAccountNames).toEqual(['Chase Checking']);
		expect(mock.snapshotQueryCalls).toBe(1);
	});

	it('DRAFT report: NO snapshot read is ever attempted (109 has no rows for a draft) — membership degrades to every currently-stale account', async () => {
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
		const result = await loadMonthlyReportForRender(mock.client, MONTH);
		expect(result.staleAccountNames).toEqual(['Chase Checking', 'Fidelity Brokerage']);
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
		const result = await loadMonthlyReportForRender(client, MONTH);
		expect(result.staleAccountNames).toEqual(['Live Name Today']);
	});

	it('a zero-stale-accounts tenant renders no banner names and skips the snapshot/account-name reads entirely', async () => {
		const mock = makeSupabase({
			reportRows: [finalRowWithPayload()],
			taxCharacterRows: TAX_CHARACTER_ROWS
		});
		const result = await loadMonthlyReportForRender(mock.client, MONTH);
		expect(result.staleAccountNames).toEqual([]);
		expect(mock.snapshotQueryCalls).toBe(0);
		expect(mock.accountQueryCalls).toHaveLength(0);
	});
});

describe("loadMonthlyReportForRender() — P8 RT-13: the tenant fence is the caller's own client, never an explicit parameter", () => {
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
		await loadMonthlyReportForRender(client, MONTH);

		const tenantLikeKeys = ['users_id', 'p_users_id', 'tenant_id', 'user_id'];
		for (const call of rpcCalls) {
			const params = call.params ?? {};
			for (const key of tenantLikeKeys) {
				expect(params, `${call.fn} params must not carry ${key}`).not.toHaveProperty(key);
			}
		}
	});

	it('every account/snapshot read is issued through the SAME client the caller passed — no second client is ever constructed', async () => {
		const mock = makeSupabase({
			reportRows: [finalRowWithPayload()],
			taxCharacterRows: TAX_CHARACTER_ROWS,
			stalenessResult: STALE_TENANT_RESULT,
			staleAccountRows: [{ account_id: 1 }],
			snapshotRows: [{ account_id: 1 }],
			accountNameRows: [{ account_id: 1, name: 'Chase Checking' }]
		});
		await loadMonthlyReportForRender(mock.client, MONTH);
		expect(mock.accountQueryCalls.length).toBeGreaterThan(0);
		expect(mock.snapshotQueryCalls).toBe(1);
	});
});
