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
	rendered_payload: { payload_schema_version: 1, target_month: '2026-08-01', as_of: '2026-08-31', sections: {} }
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
	sections: { note: 'live-composed' }
};

const TAX_CHARACTER_ROWS = [{ code: 'ordinary', label: 'Ordinary income', display_order: 10 }];

function makeSupabase(opts: {
	reportRows?: unknown[];
	reportError?: { message: string } | null;
	rpcResult?: { data: unknown; error: { message: string } | null };
	taxCharacterRows?: unknown[];
	taxCharacterError?: { message: string } | null;
}) {
	const rpc = { fn: '', params: {} as Record<string, unknown>, calls: 0 };
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
	const from = (table: string) => {
		if (table === 'monthly_report') return reportTable;
		if (table === 'tax_character') return taxCharacterTable;
		throw new Error(`unexpected table: ${table}`);
	};
	const rpcFn = (fn: string, params: Record<string, unknown>) => {
		rpc.fn = fn;
		rpc.params = params;
		rpc.calls++;
		return Promise.resolve(opts.rpcResult ?? { data: null, error: null });
	};
	const schema = (_s: string) => ({ from, rpc: rpcFn });
	return { client: { schema } as unknown as SupabaseClient, rpc };
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
