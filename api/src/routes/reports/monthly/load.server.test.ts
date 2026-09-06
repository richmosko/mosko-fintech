// load.server.test.ts — SELF-357 / P5 orchestration coverage for the §2.6.3.b listing loader +
// `generate`/`regenerate` form actions, against migration 108 (pfin.monthly_report), migration
// 113 (pfin.fn_open_monthly_report_draft) and migration 114 (pfin.fn_regenerate_monthly_report).
// EXTENDED under P4 (SELF-356) for each pending row's `noLedgerDesignated` derivation (AC4) and
// the new `skip` action (AC1/AC5, migration 115 pfin.fn_finalize_monthly_report).
//
// SCOPE: auth gates, the final/draft listing split (AC1/AC2/AC7 — superseded never listed, one
// entry per month), the two-candidate target-month computation (AC3), the structural
// picker-fence on `?/generate` (only the two freshly-recomputed candidates are legal — see
// +page.server.ts's own header), `?/regenerate`'s looser month-format-only check, and the
// redirect-into-P3-commentary contract on both actions' success path (AC5). 113/114's own DB
// contracts are those migrations' own pgTAP batteries' job — this file only proves the wiring.
// `noLedgerDesignated`'s own pure-logic coverage lives in monthly-report.test.ts; this file only
// proves the loader composes each pending row's own draft payload and threads the result through.

import { describe, it, expect, vi } from 'vitest';

const serverTodayAsOfMock = vi.fn(() => '2026-09-15');
vi.mock('$lib/server/time/asOf', () => ({ serverTodayAsOf: serverTodayAsOfMock }));

const { load, actions } = await import('./+page.server');

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

type ReportRow = {
	report_id: number;
	target_month: string;
	generation_status: 'draft' | 'final';
	generated_at: string | null;
	data_as_of: string;
};

function row(overrides: Partial<ReportRow> = {}): ReportRow {
	return {
		report_id: 1,
		target_month: '2026-08-01',
		generation_status: 'final',
		generated_at: '2026-09-01T00:00:00Z',
		data_as_of: '2026-08-31',
		...overrides
	};
}

type RpcCall = { fn: string; params: Record<string, unknown> };

function makeSupabase(opts: {
	rows?: ReportRow[] | null;
	readErr?: { message: string } | null;
	rpcResult?: { data: unknown; error: { code: string; message: string } | null };
}) {
	const rpcCalls: RpcCall[] = [];
	const from = (table: string) => {
		if (table !== 'monthly_report') throw new Error(`unexpected table: ${table}`);
		return {
			select: (_cols: string) => ({
				in: (_col: string, _vals: string[]) => ({
					order: (_col2: string, _o: unknown) =>
						Promise.resolve({ data: opts.rows ?? [], error: opts.readErr ?? null })
				})
			})
		};
	};
	const rpc = (fn: string, params: Record<string, unknown>) => {
		rpcCalls.push({ fn, params });
		return Promise.resolve(opts.rpcResult ?? { data: null, error: null });
	};
	return { client: { schema: (_s: string) => ({ from, rpc }) }, rpcCalls };
}

function makeLoadEvent(user: { id: string } | null, supabase: ReturnType<typeof makeSupabase>['client']) {
	const locals = { safeGetSession: async () => ({ session: user ? {} : null, user }), supabase };
	return { locals, url: new URL('http://localhost/reports/monthly') } as unknown as Parameters<typeof load>[0];
}

function makeActionEvent(
	fields: Record<string, string>,
	user: { id: string } | null,
	supabase: ReturnType<typeof makeSupabase>['client']
) {
	const locals = { safeGetSession: async () => ({ session: user ? {} : null, user }), supabase };
	const request = new Request('http://localhost/reports/monthly', {
		method: 'POST',
		body: new URLSearchParams(fields)
	});
	return { request, locals } as unknown as Parameters<typeof actions.generate>[0];
}

type LoadResult = {
	generated: Array<{ reportId: number; targetMonth: string; monthLabel: string; generatedAt: string | null }>;
	pending: Array<{ reportId: number; targetMonth: string; monthLabel: string; noLedgerDesignated: boolean }>;
	candidates: Array<{ targetMonth: string; label: string; plainLabel: string; state: string }>;
};

// P4 (SELF-356 AC4) — see the identical fixture in commentary/load.server.test.ts's own header for
// why only `ytd_paid` is filled in.
function composedPayload(federalDesignated: boolean, californiaDesignated: boolean) {
	const ytd = (designated: boolean) =>
		designated ? { status: 'designated', amount: 0 } : { status: 'unavailable', reason: 'no_ledger_designated' };
	return {
		sections: {
			estimated_taxes: {
				jurisdictions: {
					federal: { ytd_paid: ytd(federalDesignated) },
					california: { ytd_paid: ytd(californiaDesignated) }
				}
			}
		}
	};
}

describe('load', () => {
	it('unauthenticated → redirect to /login', async () => {
		const { client } = makeSupabase({});
		await expect(load(makeLoadEvent(null, client))).rejects.toMatchObject({ status: 303 });
	});

	it('read error → 500', async () => {
		const { client } = makeSupabase({ readErr: { message: 'boom' } });
		await expect(load(makeLoadEvent({ id: SESSION_UID }, client))).rejects.toMatchObject({ status: 500 });
	});

	it('final rows populate `generated`, draft rows populate `pending`, superseded never appears (excluded structurally)', async () => {
		const { client } = makeSupabase({
			rows: [
				row({ report_id: 1, target_month: '2026-08-01', generation_status: 'final' }),
				row({ report_id: 2, target_month: '2026-09-01', generation_status: 'draft', generated_at: null })
			]
		});
		const result = (await load(makeLoadEvent({ id: SESSION_UID }, client))) as unknown as LoadResult;
		expect(result.generated).toHaveLength(1);
		expect(result.generated[0]).toMatchObject({ reportId: 1, targetMonth: '2026-08-01' });
		expect(result.pending).toHaveLength(1);
		expect(result.pending[0]).toMatchObject({ reportId: 2, targetMonth: '2026-09-01' });
	});

	it('an empty report set yields empty generated + pending arrays (empty state is a rendering decision, not a load error)', async () => {
		const { client } = makeSupabase({ rows: [] });
		const result = (await load(makeLoadEvent({ id: SESSION_UID }, client))) as unknown as LoadResult;
		expect(result.generated).toEqual([]);
		expect(result.pending).toEqual([]);
	});

	it('computes exactly two candidates — prior month (default) and current month (in-progress label), from serverTodayAsOf', async () => {
		const { client } = makeSupabase({ rows: [] });
		const result = (await load(makeLoadEvent({ id: SESSION_UID }, client))) as unknown as LoadResult;
		expect(result.candidates).toHaveLength(2);
		expect(result.candidates[0]).toMatchObject({ targetMonth: '2026-08-01', label: 'August 2026', state: 'none' });
		expect(result.candidates[1]).toMatchObject({
			targetMonth: '2026-09-01',
			label: 'September 2026 (in progress — as of today)',
			plainLabel: 'September 2026',
			state: 'none'
		});
	});

	it("a candidate month with an existing draft/final row carries that state, not 'none'", async () => {
		const { client } = makeSupabase({
			rows: [row({ target_month: '2026-08-01', generation_status: 'final' })]
		});
		const result = (await load(makeLoadEvent({ id: SESSION_UID }, client))) as unknown as LoadResult;
		expect(result.candidates[0].state).toBe('final');
	});
});

describe('load — pending noLedgerDesignated (P4 / SELF-356 AC4)', () => {
	it('composes the pending draft\'s own payload (fn_render_monthly_report, its OWN data_as_of) — not a second dedicated query', async () => {
		const { client, rpcCalls } = makeSupabase({
			rows: [
				row({ report_id: 2, target_month: '2026-09-01', generation_status: 'draft', data_as_of: '2026-09-14' })
			],
			rpcResult: { data: composedPayload(true, true), error: null }
		});
		const result = (await load(makeLoadEvent({ id: SESSION_UID }, client))) as unknown as LoadResult;
		expect(result.pending[0].noLedgerDesignated).toBe(false);
		expect(rpcCalls).toEqual([
			{ fn: 'fn_render_monthly_report', params: { p_target_month: '2026-09-01', p_data_as_of: '2026-09-14' } }
		]);
	});

	it('flags true when the composed payload shows no ledger designated', async () => {
		const { client } = makeSupabase({
			rows: [row({ report_id: 2, target_month: '2026-09-01', generation_status: 'draft' })],
			rpcResult: { data: composedPayload(false, false), error: null }
		});
		const result = (await load(makeLoadEvent({ id: SESSION_UID }, client))) as unknown as LoadResult;
		expect(result.pending[0].noLedgerDesignated).toBe(true);
	});

	it('a composition RPC error degrades that row to false, the listing still renders (fail-soft)', async () => {
		const { client } = makeSupabase({
			rows: [row({ report_id: 2, target_month: '2026-09-01', generation_status: 'draft' })],
			rpcResult: { data: null, error: { code: '55555', message: 'boom' } }
		});
		const result = (await load(makeLoadEvent({ id: SESSION_UID }, client))) as unknown as LoadResult;
		expect(result.pending[0].noLedgerDesignated).toBe(false);
	});

	it('a final-only row set makes no composition call at all (nothing pending)', async () => {
		const { client, rpcCalls } = makeSupabase({
			rows: [row({ report_id: 1, target_month: '2026-08-01', generation_status: 'final' })]
		});
		await load(makeLoadEvent({ id: SESSION_UID }, client));
		expect(rpcCalls).toHaveLength(0);
	});
});

describe('actions.generate — structural picker fence (AC3)', () => {
	function validFields(overrides: Record<string, string> = {}): Record<string, string> {
		return { target_month: '2026-08-01', ...overrides };
	}

	it('unauthenticated → 401, no RPC reached', async () => {
		const { client, rpcCalls } = makeSupabase({});
		const res = (await actions.generate(makeActionEvent(validFields(), null, client))) as { status: number };
		expect(res.status).toBe(401);
		expect(rpcCalls).toHaveLength(0);
	});

	it('malformed target_month → 400, no RPC reached', async () => {
		const { client, rpcCalls } = makeSupabase({});
		const event = makeActionEvent(validFields({ target_month: '2026-08' }), { id: SESSION_UID }, client);
		const res = (await actions.generate(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(rpcCalls).toHaveLength(0);
	});

	it('a real month-start that is NOT one of the two current candidates → refused 400, no RPC reached', async () => {
		const { client, rpcCalls } = makeSupabase({});
		// 2025-01-01 is a real month-start but neither the prior (2026-08-01) nor current
		// (2026-09-01) candidate as of the mocked "today" (2026-09-15) — the structural fence.
		const event = makeActionEvent(validFields({ target_month: '2025-01-01' }), { id: SESSION_UID }, client);
		const res = (await actions.generate(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(rpcCalls).toHaveLength(0);
	});

	it('the prior-month candidate calls fn_open_monthly_report_draft and redirects into P3', async () => {
		const { client, rpcCalls } = makeSupabase({ rpcResult: { data: 42, error: null } });
		const event = makeActionEvent(validFields(), { id: SESSION_UID }, client);
		await expect(actions.generate(event)).rejects.toMatchObject({
			status: 303,
			location: '/reports/monthly/2026-08/commentary'
		});
		expect(rpcCalls).toEqual([
			{ fn: 'fn_open_monthly_report_draft', params: { p_target_month: '2026-08-01' } }
		]);
	});

	it('the current-month candidate is also legal', async () => {
		const { client, rpcCalls } = makeSupabase({ rpcResult: { data: 43, error: null } });
		const event = makeActionEvent(validFields({ target_month: '2026-09-01' }), { id: SESSION_UID }, client);
		await expect(actions.generate(event)).rejects.toMatchObject({ status: 303 });
		expect(rpcCalls[0].params).toEqual({ p_target_month: '2026-09-01' });
	});

	it('an RPC error → 500 generic, no redirect', async () => {
		const { client } = makeSupabase({ rpcResult: { data: null, error: { code: '55555', message: 'weird' } } });
		const event = makeActionEvent(validFields(), { id: SESSION_UID }, client);
		const res = (await actions.generate(event)) as { status: number };
		expect(res.status).toBe(500);
	});
});

describe('actions.regenerate — month-format check only, no candidate restriction (E15 item 10)', () => {
	it('unauthenticated → 401, no RPC reached', async () => {
		const { client, rpcCalls } = makeSupabase({});
		const event = makeActionEvent({ target_month: '2026-01-01' }, null, client);
		const res = (await actions.regenerate(event)) as { status: number };
		expect(res.status).toBe(401);
		expect(rpcCalls).toHaveLength(0);
	});

	it('malformed target_month → 400, no RPC reached', async () => {
		const { client, rpcCalls } = makeSupabase({});
		const event = makeActionEvent({ target_month: 'not-a-month' }, { id: SESSION_UID }, client);
		const res = (await actions.regenerate(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(rpcCalls).toHaveLength(0);
	});

	it('a real month-start OUTSIDE the two generate-candidates is still accepted here (114 handles any month safely)', async () => {
		const { client, rpcCalls } = makeSupabase({ rpcResult: { data: 99, error: null } });
		const event = makeActionEvent({ target_month: '2025-01-01' }, { id: SESSION_UID }, client);
		await expect(actions.regenerate(event)).rejects.toMatchObject({ status: 303 });
		expect(rpcCalls).toEqual([
			{ fn: 'fn_regenerate_monthly_report', params: { p_target_month: '2025-01-01' } }
		]);
	});

	it('a successful regenerate redirects into P3\'s commentary editor for the returned draft\'s month', async () => {
		const { client } = makeSupabase({ rpcResult: { data: 7, error: null } });
		const event = makeActionEvent({ target_month: '2026-08-01' }, { id: SESSION_UID }, client);
		await expect(actions.regenerate(event)).rejects.toMatchObject({
			status: 303,
			location: '/reports/monthly/2026-08/commentary'
		});
	});

	it('an RPC error → 500 generic', async () => {
		const { client } = makeSupabase({ rpcResult: { data: null, error: { code: '55555', message: 'weird' } } });
		const event = makeActionEvent({ target_month: '2026-08-01' }, { id: SESSION_UID }, client);
		const res = (await actions.regenerate(event)) as { status: number };
		expect(res.status).toBe(500);
	});
});

// P4 (SELF-356 AC1/AC5) — "Skip commentary and finalize", the pending list's own secondary CTA.
// Calls migration 115 (pfin.fn_finalize_monthly_report) with the `'skipped'` disposition literal.
describe('actions.skip', () => {
	it('unauthenticated → 401, no RPC reached', async () => {
		const { client, rpcCalls } = makeSupabase({});
		const event = makeActionEvent({ target_month: '2026-08-01' }, null, client);
		const res = (await actions.skip(event)) as { status: number };
		expect(res.status).toBe(401);
		expect(rpcCalls).toHaveLength(0);
	});

	it('malformed target_month → 400 (Zod .strict() mirror), no RPC reached', async () => {
		const { client, rpcCalls } = makeSupabase({});
		const event = makeActionEvent({ target_month: '2026-08' }, { id: SESSION_UID }, client);
		const res = (await actions.skip(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(rpcCalls).toHaveLength(0);
	});

	it('mass-assignment: a stray posted field is refused (`.strict()`), no RPC reached', async () => {
		const { client, rpcCalls } = makeSupabase({});
		const event = makeActionEvent(
			{ target_month: '2026-08-01', p_commentary_disposition: 'authored', users_id: 'evil' },
			{ id: SESSION_UID },
			client
		);
		const res = (await actions.skip(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(rpcCalls).toHaveLength(0);
	});

	it("calls 115 with the 'skipped' disposition — never a posted value — and redirects into P2's final view", async () => {
		const { client, rpcCalls } = makeSupabase({ rpcResult: { data: 2, error: null } });
		const event = makeActionEvent({ target_month: '2026-08-01' }, { id: SESSION_UID }, client);
		await expect(actions.skip(event)).rejects.toMatchObject({ status: 303, location: '/reports/monthly/2026-08' });
		expect(rpcCalls).toEqual([
			{
				fn: 'fn_finalize_monthly_report',
				params: { p_target_month: '2026-08-01', p_commentary_disposition: 'skipped' }
			}
		]);
	});

	it('P0001 (no live draft) → generic 4xx, no function name leaked', async () => {
		const { client } = makeSupabase({
			rpcResult: {
				data: null,
				error: {
					code: 'P0001',
					message: 'pfin.fn_finalize_monthly_report refused: no live draft for that month.'
				}
			}
		});
		const event = makeActionEvent({ target_month: '2026-08-01' }, { id: SESSION_UID }, client);
		const res = (await actions.skip(event)) as { status: number; data: { errors: { _form: string[] } } };
		expect(res.status).toBe(400);
		expect(res.data.errors._form.join(' ')).not.toContain('fn_finalize_monthly_report');
	});

	it('42501 (step-up required) → 403', async () => {
		const { client } = makeSupabase({
			rpcResult: { data: null, error: { code: '42501', message: 'insufficient_privilege' } }
		});
		const event = makeActionEvent({ target_month: '2026-08-01' }, { id: SESSION_UID }, client);
		const res = (await actions.skip(event)) as { status: number };
		expect(res.status).toBe(403);
	});

	it('an unexpected error code → 500 generic', async () => {
		const { client } = makeSupabase({ rpcResult: { data: null, error: { code: '55555', message: 'weird' } } });
		const event = makeActionEvent({ target_month: '2026-08-01' }, { id: SESSION_UID }, client);
		const res = (await actions.skip(event)) as { status: number };
		expect(res.status).toBe(500);
	});
});
