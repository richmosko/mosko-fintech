// load.server.test.ts — SELF-355 / P3 orchestration coverage for the §2.6.2.b commentary
// route's loader + `save` form action, against migration 108 (pfin.monthly_report) + migration
// 112 (pfin.fn_save_monthly_commentary). RT-11 canonical test label. EXTENDED under P4 (SELF-356)
// for the `noLedgerDesignated` loader derivation (AC4) and the new `finalize` action (AC5, 115).
//
// SCOPE: this file locks the ORCHESTRATION this route file itself owns — auth gates, target-
// month parsing, final-vs-draft row selection, prior-month reference reads degrading soft, the
// $ ReAlloc live-read fail-soft posture, FormData → Zod translation, and the RPC error → 4xx
// mapping (mapSaveError's own no-leaked-names contract). `loadStaleness` / `loadNonReAllocation`
// are Backend's own query modules and are MOCKED here (their own contracts are those modules'
// own unit tests' job — this file only proves the wiring, mirroring
// taxes/decomposition/load.server.test.ts's own stated convention). `noLedgerDesignated`'s own
// pure-logic coverage (which reason strings/statuses flip it) lives in monthly-report.test.ts —
// this file only proves the loader composes the draft payload and threads the result through.

import { describe, it, expect, vi } from 'vitest';

const loadStalenessMock = vi.fn();
const loadNonReAllocationMock = vi.fn();
const serverTodayAsOfMock = vi.fn(() => ({ asOf: '2026-09-04', tz: 'America/Los_Angeles' }));

vi.mock('$lib/server/queries/staleness', () => ({ loadStaleness: loadStalenessMock }));
vi.mock('$lib/server/queries/nonReAllocation', () => ({ loadNonReAllocation: loadNonReAllocationMock }));
vi.mock('$lib/server/time/asOf', () => ({ serverTodayAsOf: serverTodayAsOfMock }));

const { load, actions } = await import('./+page.server');

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

type CommentaryRow = {
	report_id: number;
	target_month: string;
	generation_status: 'draft' | 'final' | 'superseded';
	data_as_of: string;
	commentary_cash: string | null;
	commentary_bonds: string | null;
	commentary_marketable_securities: string | null;
	commentary_alternatives: string | null;
};

const EMPTY_STALENESS = { is_stale: false, stale_items: [] };
const UNKNOWN_STALENESS = { is_stale: null, stale_items: [] };

function draftRow(overrides: Partial<CommentaryRow> = {}): CommentaryRow {
	return {
		report_id: 7,
		target_month: '2026-09-01',
		generation_status: 'draft',
		data_as_of: '2026-09-04',
		commentary_cash: '',
		commentary_bonds: '',
		commentary_marketable_securities: '',
		commentary_alternatives: '',
		...overrides
	};
}

function finalRow(overrides: Partial<CommentaryRow> = {}): CommentaryRow {
	return { ...draftRow(overrides), report_id: 6, generation_status: 'final' };
}

type RpcCall = { fn: string; params: Record<string, unknown> };

function makeSupabase(opts: {
	rows?: CommentaryRow[] | null;
	reportErr?: { message: string } | null;
	priorRow?: Partial<CommentaryRow> | null;
	rpcResult?: { data: unknown; error: { code: string; message: string } | null };
}) {
	const rpcCalls: RpcCall[] = [];
	const from = (table: string) => {
		if (table !== 'monthly_report') throw new Error(`unexpected table: ${table}`);
		return {
			select: (_cols: string) => ({
				eq: (_col: string, _val: unknown) => ({
					in: (_col2: string, _vals: string[]) =>
						Promise.resolve({ data: opts.rows ?? [], error: opts.reportErr ?? null }),
					order: (_col2: string, _o: unknown) => ({
						limit: (_n: number) => ({
							maybeSingle: () => Promise.resolve({ data: opts.priorRow ?? null, error: null })
						})
					})
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

function makeLoadEvent(
	targetMonthParam: string,
	user: { id: string } | null,
	supabase: ReturnType<typeof makeSupabase>['client']
) {
	const locals = { safeGetSession: async () => ({ session: user ? {} : null, user }), supabase };
	return {
		locals,
		params: { target_month: targetMonthParam },
		url: new URL(`http://localhost/reports/monthly/${targetMonthParam}/commentary`)
	} as unknown as Parameters<typeof load>[0];
}

function makeActionEvent(
	targetMonthParam: string,
	fields: Record<string, string>,
	user: { id: string } | null,
	supabase: ReturnType<typeof makeSupabase>['client']
) {
	const locals = { safeGetSession: async () => ({ session: user ? {} : null, user }), supabase };
	const request = new Request(`http://localhost/reports/monthly/${targetMonthParam}/commentary?/save`, {
		method: 'POST',
		body: new URLSearchParams(fields)
	});
	return {
		request,
		locals,
		params: { target_month: targetMonthParam }
	} as unknown as Parameters<typeof actions.save>[0];
}

type LoadResult = {
	targetMonth: string;
	targetMonthLabel: string;
	isDraft: boolean;
	commentary: { cash: string; bonds: string; marketable_securities: string; alternatives: string };
	priorMonthLabel: string;
	priorCommentary: { cash: string; bonds: string; marketable_securities: string; alternatives: string };
	allocation: unknown;
	staleness: unknown;
	noLedgerDesignated: boolean;
};

const ALLOCATION_STUB = { groups: [], unsorted: null, total_non_re: 0 };

function stubLiveReadsHealthy() {
	loadStalenessMock.mockReset().mockResolvedValue(EMPTY_STALENESS);
	loadNonReAllocationMock.mockReset().mockResolvedValue({ ok: true, data: ALLOCATION_STUB });
}

// P4 (SELF-356 AC4) — a minimal composed-payload fixture. Only `sections.estimated_taxes
// .jurisdictions.{federal,california}.ytd_paid` is load-bearing for `noLedgerDesignated`
// (monthly-report.test.ts owns that function's own pure-logic coverage); everything else is cast
// past rather than filled out.
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
		const event = makeLoadEvent('2026-09', null, client);
		await expect(load(event)).rejects.toMatchObject({ status: 303 });
	});

	it('invalid target_month param → 400', async () => {
		stubLiveReadsHealthy();
		const { client } = makeSupabase({});
		const event = makeLoadEvent('not-a-month', { id: SESSION_UID }, client);
		await expect(load(event)).rejects.toMatchObject({ status: 400 });
	});

	it('report read error → 500', async () => {
		stubLiveReadsHealthy();
		const { client } = makeSupabase({ reportErr: { message: 'boom' } });
		const event = makeLoadEvent('2026-09', { id: SESSION_UID }, client);
		await expect(load(event)).rejects.toMatchObject({ status: 500 });
	});

	it('no report for this month → 404', async () => {
		stubLiveReadsHealthy();
		const { client } = makeSupabase({ rows: [] });
		const event = makeLoadEvent('2026-09', { id: SESSION_UID }, client);
		await expect(load(event)).rejects.toMatchObject({ status: 404 });
	});

	it('draft-only → isDraft true, commentary from the draft row', async () => {
		stubLiveReadsHealthy();
		const { client } = makeSupabase({ rows: [draftRow({ commentary_cash: 'draft cash text' })] });
		const event = makeLoadEvent('2026-09', { id: SESSION_UID }, client);
		const result = (await load(event)) as unknown as LoadResult;
		expect(result.isDraft).toBe(true);
		expect(result.commentary.cash).toBe('draft cash text');
	});

	it('final wins over draft when both exist for the month (tiebreak)', async () => {
		stubLiveReadsHealthy();
		const { client } = makeSupabase({
			rows: [
				draftRow({ commentary_cash: 'draft text' }),
				finalRow({ commentary_cash: 'final text' })
			]
		});
		const event = makeLoadEvent('2026-09', { id: SESSION_UID }, client);
		const result = (await load(event)) as unknown as LoadResult;
		expect(result.isDraft).toBe(false);
		expect(result.commentary.cash).toBe('final text');
	});

	it('a NULL commentary column renders as an empty string, never "null"', async () => {
		stubLiveReadsHealthy();
		const { client } = makeSupabase({ rows: [draftRow({ commentary_bonds: null })] });
		const event = makeLoadEvent('2026-09', { id: SESSION_UID }, client);
		const result = (await load(event)) as unknown as LoadResult;
		expect(result.commentary.bonds).toBe('');
	});

	it('prior-month reference row present → priorCommentary populated', async () => {
		stubLiveReadsHealthy();
		const { client } = makeSupabase({
			rows: [draftRow()],
			priorRow: { commentary_cash: 'prior cash', commentary_alternatives: 'prior alts' }
		});
		const event = makeLoadEvent('2026-09', { id: SESSION_UID }, client);
		const result = (await load(event)) as unknown as LoadResult;
		expect(result.priorCommentary.cash).toBe('prior cash');
		expect(result.priorCommentary.alternatives).toBe('prior alts');
	});

	it('no prior-month row → priorCommentary degrades to all-blank, not a 404', async () => {
		stubLiveReadsHealthy();
		const { client } = makeSupabase({ rows: [draftRow()], priorRow: null });
		const event = makeLoadEvent('2026-09', { id: SESSION_UID }, client);
		const result = (await load(event)) as unknown as LoadResult;
		expect(result.priorCommentary).toEqual({
			cash: '',
			bonds: '',
			marketable_securities: '',
			alternatives: ''
		});
	});

	it('staleness read throws → degrades to UNKNOWN_STALENESS, page still renders', async () => {
		loadStalenessMock.mockReset().mockRejectedValue(new Error('rpc down'));
		loadNonReAllocationMock.mockReset().mockResolvedValue({ ok: true, data: ALLOCATION_STUB });
		const { client } = makeSupabase({ rows: [draftRow()] });
		const event = makeLoadEvent('2026-09', { id: SESSION_UID }, client);
		const result = (await load(event)) as unknown as LoadResult;
		expect(result.staleness).toEqual(UNKNOWN_STALENESS);
	});

	it('allocation read throws → degrades to null, page still renders (not a 500)', async () => {
		loadStalenessMock.mockReset().mockResolvedValue(EMPTY_STALENESS);
		loadNonReAllocationMock.mockReset().mockRejectedValue(new Error('rpc down'));
		const { client } = makeSupabase({ rows: [draftRow()] });
		const event = makeLoadEvent('2026-09', { id: SESSION_UID }, client);
		const result = (await load(event)) as unknown as LoadResult;
		expect(result.allocation).toBeNull();
	});

	it('allocation read resolves .ok=false → degrades to null (fail-soft, never a fabricated table)', async () => {
		loadStalenessMock.mockReset().mockResolvedValue(EMPTY_STALENESS);
		loadNonReAllocationMock.mockReset().mockResolvedValue({ ok: false, reason: 'x' });
		const { client } = makeSupabase({ rows: [draftRow()] });
		const event = makeLoadEvent('2026-09', { id: SESSION_UID }, client);
		const result = (await load(event)) as unknown as LoadResult;
		expect(result.allocation).toBeNull();
	});
});

describe('load — noLedgerDesignated (P4 / SELF-356 AC4)', () => {
	it('draft with a designated ledger on both jurisdictions → false', async () => {
		stubLiveReadsHealthy();
		const { client, rpcCalls } = makeSupabase({
			rows: [draftRow()],
			rpcResult: { data: composedPayload(true, true), error: null }
		});
		const event = makeLoadEvent('2026-09', { id: SESSION_UID }, client);
		const result = (await load(event)) as unknown as LoadResult;
		expect(result.noLedgerDesignated).toBe(false);
		expect(rpcCalls).toEqual([
			{
				fn: 'fn_render_monthly_report',
				params: { p_target_month: '2026-09-01', p_data_as_of: draftRow().data_as_of }
			}
		]);
	});

	it('draft with no ledger designated on either jurisdiction → true', async () => {
		stubLiveReadsHealthy();
		const { client } = makeSupabase({
			rows: [draftRow()],
			rpcResult: { data: composedPayload(false, false), error: null }
		});
		const event = makeLoadEvent('2026-09', { id: SESSION_UID }, client);
		const result = (await load(event)) as unknown as LoadResult;
		expect(result.noLedgerDesignated).toBe(true);
	});

	it('final row → always false, and the composition RPC is never called (nothing left to finalize)', async () => {
		stubLiveReadsHealthy();
		const { client, rpcCalls } = makeSupabase({ rows: [finalRow()] });
		const event = makeLoadEvent('2026-09', { id: SESSION_UID }, client);
		const result = (await load(event)) as unknown as LoadResult;
		expect(result.noLedgerDesignated).toBe(false);
		expect(rpcCalls).toHaveLength(0);
	});

	it('composition RPC error → fail-soft false, page still renders (a prompt, not a block, extends to its own read failing)', async () => {
		stubLiveReadsHealthy();
		const { client } = makeSupabase({
			rows: [draftRow()],
			rpcResult: { data: null, error: { code: '55555', message: 'boom' } }
		});
		const event = makeLoadEvent('2026-09', { id: SESSION_UID }, client);
		const result = (await load(event)) as unknown as LoadResult;
		expect(result.noLedgerDesignated).toBe(false);
	});
});

describe('actions.save', () => {
	function validFields(overrides: Record<string, string> = {}): Record<string, string> {
		return {
			cash: 'cash text',
			bonds: 'bonds text',
			marketable_securities: 'ms text',
			alternatives: 'alt text',
			...overrides
		};
	}

	it('unauthenticated → 401, no RPC reached', async () => {
		const { client, rpcCalls } = makeSupabase({});
		const event = makeActionEvent('2026-09', validFields(), null, client);
		const res = (await actions.save(event)) as { status: number };
		expect(res.status).toBe(401);
		expect(rpcCalls).toHaveLength(0);
	});

	it('invalid target_month param → 400, no RPC reached', async () => {
		const { client, rpcCalls } = makeSupabase({});
		const event = makeActionEvent('bogus', validFields(), { id: SESSION_UID }, client);
		const res = (await actions.save(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(rpcCalls).toHaveLength(0);
	});

	it('a 4000-code-point body is accepted and reaches the RPC verbatim', async () => {
		const body = 'a'.repeat(4000);
		const { client, rpcCalls } = makeSupabase({ rpcResult: { data: 7, error: null } });
		const event = makeActionEvent('2026-09', validFields({ cash: body }), { id: SESSION_UID }, client);
		const res = (await actions.save(event)) as { ok: boolean };
		expect(res).toEqual({ ok: true, commentary: expect.objectContaining({ cash: body }) });
		expect(rpcCalls[0].params.p_cash).toBe(body);
	});

	it('a 4001-code-point body is refused 400, no RPC reached', async () => {
		const body = 'a'.repeat(4001);
		const { client, rpcCalls } = makeSupabase({});
		const event = makeActionEvent('2026-09', validFields({ cash: body }), { id: SESSION_UID }, client);
		const res = (await actions.save(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(rpcCalls).toHaveLength(0);
	});

	// 6b (migration 112's own QA list): 3,996 ASCII + 4 astral characters = 4,000 CODE POINTS but
	// 4,004 UTF-16 units — the unit leg that fails if anyone reverts to `.length`.
	it('3,996 ASCII + 4 astral characters (4,000 code points / 4,004 UTF-16 units) is accepted', async () => {
		const body = 'a'.repeat(3996) + '𝄞𝄞𝄞𝄞'; // 4 astral (surrogate-pair) characters
		expect(body.length).toBe(4004); // sanity: UTF-16 units
		expect(Array.from(body).length).toBe(4000); // sanity: code points
		const { client, rpcCalls } = makeSupabase({ rpcResult: { data: 7, error: null } });
		const event = makeActionEvent('2026-09', validFields({ cash: body }), { id: SESSION_UID }, client);
		const res = (await actions.save(event)) as { ok: boolean };
		expect(res).toEqual({ ok: true, commentary: expect.objectContaining({ cash: body }) });
	});

	it('mass-assignment: only the four named RPC params are ever sent — no users_id/tenant param', async () => {
		const { client, rpcCalls } = makeSupabase({ rpcResult: { data: 7, error: null } });
		const event = makeActionEvent(
			'2026-09',
			{ ...validFields(), users_id: 'evil', tenant_id: 'evil', target_month: '1999-01-01' },
			{ id: SESSION_UID },
			client
		);
		await actions.save(event);
		const params = rpcCalls[0].params;
		expect(Object.keys(params).sort()).toEqual([
			'p_alternatives',
			'p_bonds',
			'p_cash',
			'p_marketable_securities',
			'p_target_month'
		]);
		expect(params.p_target_month).toBe('2026-09-01'); // from the ROUTE PARAM, never the body
	});

	it('P0001 (no report / not-a-draft) → generic 4xx with NO function name or reasoning leaked', async () => {
		const rawMessage =
			'pfin.fn_save_monthly_commentary refused: the report for 2026-09-01 is `final` and commentary is writable only inside the DRAFT window (PM D-6, ratified at R4).';
		const { client, rpcCalls } = makeSupabase({
			rpcResult: { data: null, error: { code: 'P0001', message: rawMessage } }
		});
		const event = makeActionEvent('2026-09', validFields(), { id: SESSION_UID }, client);
		const res = (await actions.save(event)) as { status: number; data: { errors: { _form: string[] } } };
		expect(res.status).toBe(400);
		const shown = res.data.errors._form.join(' ');
		expect(shown).not.toContain('fn_save_monthly_commentary');
		expect(shown).not.toContain('DRAFT window');
		expect(shown).not.toContain('PM D-6');
		expect(rpcCalls).toHaveLength(1); // the RPC WAS called (RLS/precondition refusal, not a client-side block)
	});

	it('cross-tenant call (RLS resolves zero rows, same P0001 "no report" text as an absent month) → the SAME generic message, no disclosure', async () => {
		const rawMessage =
			'pfin.fn_save_monthly_commentary: no monthly report exists for 2026-09-01 that you can write. Either the month has no report yet, or it is not yours, or your session does not meet the step-up your settings require.';
		const { client } = makeSupabase({
			rpcResult: { data: null, error: { code: 'P0001', message: rawMessage } }
		});
		const event = makeActionEvent('2026-09', validFields(), { id: SESSION_UID }, client);
		const res = (await actions.save(event)) as { status: number; data: { errors: { _form: string[] } } };
		expect(res.status).toBe(400);
		const shown = res.data.errors._form.join(' ');
		expect(shown).not.toContain('fn_save_monthly_commentary');
		expect(shown).not.toContain('it is not yours');
	});

	it('23514 (DB length CHECK, belt-and-suspenders) → 400 generic length message', async () => {
		const { client } = makeSupabase({
			rpcResult: { data: null, error: { code: '23514', message: 'value too long for type character varying' } }
		});
		const event = makeActionEvent('2026-09', validFields(), { id: SESSION_UID }, client);
		const res = (await actions.save(event)) as { status: number; data: { errors: { _form: string[] } } };
		expect(res.status).toBe(400);
		expect(res.data.errors._form.join(' ')).not.toContain('character varying');
	});

	it('an unexpected error code → 500 generic message', async () => {
		const { client } = makeSupabase({
			rpcResult: { data: null, error: { code: '55555', message: 'weird' } }
		});
		const event = makeActionEvent('2026-09', validFields(), { id: SESSION_UID }, client);
		const res = (await actions.save(event)) as { status: number };
		expect(res.status).toBe(500);
	});
});

// P4 (SELF-356 AC5) — the editor's own "Finalize {Month YYYY}" action, wired to migration 115
// (pfin.fn_finalize_monthly_report) with the `'authored'` disposition literal.
describe('actions.finalize', () => {
	function makeFinalizeActionEvent(
		targetMonthParam: string,
		fields: Record<string, string>,
		user: { id: string } | null,
		supabase: ReturnType<typeof makeSupabase>['client']
	) {
		const locals = { safeGetSession: async () => ({ session: user ? {} : null, user }), supabase };
		const request = new Request(
			`http://localhost/reports/monthly/${targetMonthParam}/commentary?/finalize`,
			{ method: 'POST', body: new URLSearchParams(fields) }
		);
		return {
			request,
			locals,
			params: { target_month: targetMonthParam }
		} as unknown as Parameters<typeof actions.finalize>[0];
	}

	it('unauthenticated → 401, no RPC reached', async () => {
		const { client, rpcCalls } = makeSupabase({});
		const event = makeFinalizeActionEvent('2026-09', {}, null, client);
		const res = (await actions.finalize(event)) as { status: number };
		expect(res.status).toBe(401);
		expect(rpcCalls).toHaveLength(0);
	});

	it('invalid target_month param → 400, no RPC reached', async () => {
		const { client, rpcCalls } = makeSupabase({});
		const event = makeFinalizeActionEvent('bogus', {}, { id: SESSION_UID }, client);
		const res = (await actions.finalize(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(rpcCalls).toHaveLength(0);
	});

	it('mass-assignment: a stray posted field is refused (`.strict()`), no RPC reached', async () => {
		const { client, rpcCalls } = makeSupabase({});
		const event = makeFinalizeActionEvent(
			'2026-09',
			{ p_commentary_disposition: 'skipped', users_id: 'evil' },
			{ id: SESSION_UID },
			client
		);
		const res = (await actions.finalize(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(rpcCalls).toHaveLength(0);
	});

	it("a clean submit calls 115 with the 'authored' disposition — never a posted value", async () => {
		const { client, rpcCalls } = makeSupabase({ rpcResult: { data: 7, error: null } });
		const event = makeFinalizeActionEvent('2026-09', {}, { id: SESSION_UID }, client);
		await expect(actions.finalize(event)).rejects.toMatchObject({
			status: 303,
			location: '/reports/monthly/2026-09'
		});
		expect(rpcCalls).toEqual([
			{
				fn: 'fn_finalize_monthly_report',
				params: { p_target_month: '2026-09-01', p_commentary_disposition: 'authored' }
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
		const event = makeFinalizeActionEvent('2026-09', {}, { id: SESSION_UID }, client);
		const res = (await actions.finalize(event)) as { status: number; data: { errors: { _form: string[] } } };
		expect(res.status).toBe(400);
		expect(res.data.errors._form.join(' ')).not.toContain('fn_finalize_monthly_report');
	});

	it('42501 (step-up required) → 403', async () => {
		const { client } = makeSupabase({
			rpcResult: { data: null, error: { code: '42501', message: 'insufficient_privilege' } }
		});
		const event = makeFinalizeActionEvent('2026-09', {}, { id: SESSION_UID }, client);
		const res = (await actions.finalize(event)) as { status: number };
		expect(res.status).toBe(403);
	});

	it('an unexpected error code → 500 generic message', async () => {
		const { client } = makeSupabase({
			rpcResult: { data: null, error: { code: '55555', message: 'weird' } }
		});
		const event = makeFinalizeActionEvent('2026-09', {}, { id: SESSION_UID }, client);
		const res = (await actions.finalize(event)) as { status: number };
		expect(res.status).toBe(500);
	});
});
