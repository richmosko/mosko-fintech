// load.server.test.ts — the SELF-354 / P2 route-level watcher. The data-loading behavior this
// file used to test IN FULL now lives in `$lib/server/monthly-report/loadMonthlyReport.test.ts`
// (extracted at the SELF-358 / P6 PDF-export rebase-integration, alongside the load path itself
// — see loadMonthlyReport.ts's own header for why this is structural under R2 (C), not a
// discipline). This file keeps only what is actually THIS ROUTE's own concern: (a) the
// unauthenticated redirect to /login with a redirectTo pointing back at this page; (b) the
// `target_month` param is validated as `YYYY-MM` — malformed -> 400, before the shared loader is
// ever called; (c) one thin wiring smoke test proving `load()` actually calls the shared module
// and returns its fields PLUS `seedDeltaMigration` (the one field that was never part of the
// extraction — a static citation constant, not a read).

import { describe, it, expect } from 'vitest';
import { isHttpError, isRedirect } from '@sveltejs/kit';
import type { SupabaseClient } from '@supabase/supabase-js';

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
		sections: { account_holdings: { groups: [] } }
	}
};

const TAX_CHARACTER_ROWS = [{ code: 'ordinary', label: 'Ordinary income', display_order: 10 }];

function makeSupabase(opts: { reportRows?: unknown[]; taxCharacterRows?: unknown[] }) {
	const reportTable = {
		select: (_cols: string) => ({
			eq: (_col: string, _val: unknown) => ({
				in: (_col2: string, _vals: string[]) => Promise.resolve({ data: opts.reportRows ?? [], error: null })
			})
		})
	};
	const taxCharacterTable = {
		select: (_cols: string) => ({
			order: () => Promise.resolve({ data: opts.taxCharacterRows ?? [], error: null })
		})
	};
	// The smoke test below exercises a healthy-tenant, zero-stale-accounts path — no
	// staleness/cashflow/snapshot/account read is ever reached (see
	// loadMonthlyReport.test.ts's own "zero-stale-accounts tenant... skips the
	// snapshot/account-name reads entirely" leg for why), so only these two tables need a stub
	// here.
	const from = (table: string) => {
		if (table === 'monthly_report') return reportTable;
		if (table === 'tax_character') return taxCharacterTable;
		throw new Error(`unexpected table in load.server.test.ts's own smoke test: ${table}`);
	};
	const rpcFn = (fn: string) => {
		if (fn === 'fn_aggregation_has_stale_constituent') {
			return Promise.resolve({ data: [{ is_stale: false, stale_items: [] }], error: null });
		}
		throw new Error(`unexpected rpc in load.server.test.ts's own smoke test: ${fn}`);
	};
	const schema = (_s: string) => ({ from, rpc: rpcFn });
	return { client: { schema } as unknown as SupabaseClient };
}

function makeEvent(targetMonth: string, user: { id: string } | null, supabase: SupabaseClient) {
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

describe('load() — wiring smoke test (the exhaustive data-loading battery lives in loadMonthlyReport.test.ts)', () => {
	it('calls the shared loader and returns its fields plus seedDeltaMigration', async () => {
		const { client } = makeSupabase({ reportRows: [FINAL_ROW], taxCharacterRows: TAX_CHARACTER_ROWS });
		const result = (await load(makeEvent('2026-08', { id: SESSION_UID }, client))) as unknown as {
			header: Record<string, unknown>;
			payload: unknown;
			taxCharacters: unknown;
			seedDeltaMigration: string;
			staleness: unknown;
			cashflowRowStaleness: unknown;
			staleAccountNames: unknown;
		};
		expect(result.payload).toMatchObject({ target_month: '2026-08-01' });
		expect(result.header).toMatchObject({ report_id: 42, generation_status: 'final' });
		expect(typeof result.seedDeltaMigration).toBe('string');
		expect(result.seedDeltaMigration.length).toBeGreaterThan(0);
	});
});
