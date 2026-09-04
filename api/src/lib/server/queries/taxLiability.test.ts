// taxLiability.test.ts — unit coverage for loadTaxLiability (SELF-262/264/266). Mocks the
// supabase-js chain: .schema('pfin').rpc('fn_compute_tax_liability') → { data, error }. Proves
// (a) a well-formed payload passes through VERBATIM, no reshaping; (b) an RPC error throws
// TaxLiabilityPayloadError rather than degrading; (c) a non-object / array payload throws; (d) a
// payload missing any of the six ADR-067 Decision 5 top-level keys throws, naming the missing key.
//
// The RPC is called with NO p_data_as_of argument (AC 8a — server-derived today); this file also
// proves that call-shape directly, since a stray as-of argument threading in would be a silent
// SELF-264/266 AC 8a regression nothing else here would catch.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadTaxLiability, TaxLiabilityPayloadError, type TaxLiabilityPayload } from './taxLiability';

type MockOpts = {
	data?: unknown;
	error?: { message: string } | null;
};

function makeSupabase(opts: MockOpts) {
	const rpc = vi.fn(async () => ({ data: opts.data ?? null, error: opts.error ?? null }));
	const schema = vi.fn(() => ({ rpc }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, rpc, schema };
}

/** A minimal well-formed payload carrying all six ADR-067 Decision 5 top-level keys. */
const WELL_FORMED: TaxLiabilityPayload = {
	as_of: '2026-09-04',
	tax_year: 2026,
	decomposition: {
		ordinary_income: { rows: [], total: 0 },
		capital_gains: { status: 'unavailable', reason: 'no_sale_recording_capability' },
		unclassified: { count_ytd: 0 }
	},
	jurisdictions: {
		federal: {
			status: 'unavailable',
			reason: 'no_schedule_any_year',
			basis_year: null,
			schedules: {},
			inputs: { ordinary_input: 0, lt_cg_input: 0, standard_deduction: null },
			taxable_income: { ordinary: null, lt_cg: null },
			annual_liability: null,
			tax_balance_prior_year: null,
			installments: null,
			installments_due_through_next: 1,
			next_due_date: '2026-04-15',
			ytd_paid: { status: 'unavailable', reason: 'no_ledger_designated' },
			funds_due: { status: 'unavailable', reason: 'no_schedule_any_year' }
		},
		california: {
			status: 'unavailable',
			reason: 'no_schedule_any_year',
			basis_year: null,
			schedules: {},
			inputs: { ordinary_input: 0, lt_cg_input: 0, standard_deduction: null },
			taxable_income: { ordinary: null, lt_cg: null },
			annual_liability: null,
			tax_balance_prior_year: null,
			installments: null,
			installments_due_through_next: 1,
			next_due_date: '2026-04-15',
			ytd_paid: { status: 'unavailable', reason: 'no_ledger_designated' },
			funds_due: { status: 'unavailable', reason: 'no_schedule_any_year' }
		}
	},
	nav_components: {
		realized_tax_liab: { status: 'unavailable', reason: 'no_schedule_any_year' },
		unrealized_tax_liab: { status: 'unavailable', reason: 'no_schedule_any_year' }
	},
	prior_year_q4_window: { open: false, tax_year: 2025, due_date: '2026-01-15' }
};

describe('loadTaxLiability', () => {
	it('passes a well-formed payload through VERBATIM — no reshaping', async () => {
		const { client } = makeSupabase({ data: WELL_FORMED, error: null });
		const result = await loadTaxLiability(client);
		expect(result).toEqual(WELL_FORMED);
	});

	it('calls fn_compute_tax_liability with NO p_data_as_of argument (AC 8a: server-derived today)', async () => {
		const { client, rpc } = makeSupabase({ data: WELL_FORMED, error: null });
		await loadTaxLiability(client);
		expect(rpc).toHaveBeenCalledTimes(1);
		expect(rpc).toHaveBeenCalledWith('fn_compute_tax_liability');
	});

	it('throws TaxLiabilityPayloadError on an RPC error — never degrades', async () => {
		const { client } = makeSupabase({ error: { message: 'connection reset' } });
		await expect(loadTaxLiability(client)).rejects.toBeInstanceOf(TaxLiabilityPayloadError);
		await expect(loadTaxLiability(client)).rejects.toThrow(/connection reset/);
	});

	it('throws on a null payload rather than coercing to an empty shape', async () => {
		const { client } = makeSupabase({ data: null, error: null });
		await expect(loadTaxLiability(client)).rejects.toBeInstanceOf(TaxLiabilityPayloadError);
	});

	it('throws on an array payload (fn_compute_tax_liability is a scalar jsonb return, never set-returning)', async () => {
		const { client } = makeSupabase({ data: [WELL_FORMED], error: null });
		await expect(loadTaxLiability(client)).rejects.toThrow(/non-object payload/);
	});

	it.each([
		'as_of',
		'tax_year',
		'decomposition',
		'jurisdictions',
		'nav_components',
		'prior_year_q4_window'
	] as const)('throws naming the missing key when top-level key `%s` is absent', async (key) => {
		const malformed = { ...WELL_FORMED };
		delete (malformed as Record<string, unknown>)[key];
		const { client } = makeSupabase({ data: malformed, error: null });
		await expect(loadTaxLiability(client)).rejects.toThrow(new RegExp(key));
	});
});
