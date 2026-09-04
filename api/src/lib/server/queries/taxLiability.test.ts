// taxLiability.test.ts — unit coverage for loadTaxLiability and loadPriorYearQ4 (SELF-262/264/266,
// E39). Mocks the supabase-js chain: .schema('pfin').rpc('fn_compute_tax_liability') → { data,
// error }. Proves (a) a well-formed payload passes through VERBATIM, no reshaping; (b) an RPC
// error throws TaxLiabilityPayloadError rather than degrading; (c) a non-object / array payload
// throws; (d) a payload missing any of the six ADR-067 Decision 5 top-level keys throws, naming
// the missing key; (e) loadPriorYearQ4 calls the SAME function a SECOND time with p_data_as_of
// pinned to exactly Dec 31 of the given window's tax_year, and forwards each jurisdiction's last
// installment / annual_liability / funds_due envelope verbatim — unavailable stays unavailable,
// never coerced to 0.
//
// loadTaxLiability's own RPC is called with NO p_data_as_of argument (AC 8a — server-derived
// today); this file also proves that call-shape directly, since a stray as-of argument threading
// in would be a silent SELF-264/266 AC 8a regression nothing else here would catch.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import {
	loadTaxLiability,
	loadPriorYearQ4,
	TaxLiabilityPayloadError,
	type TaxLiabilityPayload,
	type TaxJurisdictionPayload
} from './taxLiability';

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

/** A COMPUTED jurisdiction, standing in for a resolved prior-year-Q4 payload's federal/california block. */
function computedJurisdiction(overrides: Partial<TaxJurisdictionPayload> = {}): TaxJurisdictionPayload {
	return {
		status: 'computed',
		basis_year: 2025,
		schedules: {},
		inputs: { ordinary_input: 1000, lt_cg_input: 0, standard_deduction: 500 },
		taxable_income: { ordinary: 500, lt_cg: 0 },
		annual_liability: 400,
		tax_balance_prior_year: null,
		installments: [
			{ quarter: 1, due_date: '2025-04-15', amount: 100 },
			{ quarter: 2, due_date: '2025-06-15', amount: 100 },
			{ quarter: 3, due_date: '2025-09-15', amount: 100 },
			{ quarter: 4, due_date: '2026-01-15', amount: 100 }
		],
		installments_due_through_next: 4,
		next_due_date: '2026-01-15',
		ytd_paid: { status: 'designated', amount: 300 },
		funds_due: { status: 'computed', amount: 100 },
		...overrides
	};
}

const UNAVAILABLE_JURISDICTION: TaxJurisdictionPayload = {
	status: 'unavailable',
	reason: 'no_schedule_any_year',
	basis_year: null,
	schedules: {},
	inputs: { ordinary_input: null, lt_cg_input: null, standard_deduction: null },
	taxable_income: { ordinary: null, lt_cg: null },
	annual_liability: null,
	tax_balance_prior_year: null,
	installments: null,
	installments_due_through_next: 1,
	next_due_date: '2026-04-15',
	ytd_paid: { status: 'unavailable', reason: 'no_ledger_designated' },
	funds_due: { status: 'unavailable', reason: 'no_schedule_any_year' }
};

describe('loadPriorYearQ4 (E39 / R8 (B))', () => {
	const WINDOW = { open: true, tax_year: 2025, due_date: '2026-01-15' };

	it('calls fn_compute_tax_liability a SECOND time with p_data_as_of pinned to Dec 31 of window.tax_year', async () => {
		const { client, rpc } = makeSupabase({
			data: { ...WELL_FORMED, jurisdictions: { federal: computedJurisdiction(), california: computedJurisdiction() } },
			error: null
		});
		await loadPriorYearQ4(client, WINDOW);
		expect(rpc).toHaveBeenCalledTimes(1);
		expect(rpc).toHaveBeenCalledWith('fn_compute_tax_liability', { p_data_as_of: '2025-12-31' });
	});

	it('forwards tax_year, due_date and the exact as_of it queried with', async () => {
		const { client } = makeSupabase({
			data: { ...WELL_FORMED, jurisdictions: { federal: computedJurisdiction(), california: computedJurisdiction() } },
			error: null
		});
		const result = await loadPriorYearQ4(client, WINDOW);
		expect(result.tax_year).toBe(2025);
		expect(result.due_date).toBe('2026-01-15');
		expect(result.as_of).toBe('2025-12-31');
	});

	it('takes q4_installment as the LAST element of installments[], and forwards annual_liability + funds_due verbatim when computed', async () => {
		const { client } = makeSupabase({
			data: {
				...WELL_FORMED,
				jurisdictions: {
					federal: computedJurisdiction({ funds_due: { status: 'computed', amount: 42 } }),
					california: computedJurisdiction()
				}
			},
			error: null
		});
		const result = await loadPriorYearQ4(client, WINDOW);
		expect(result.federal).toEqual({
			q4_installment: 100,
			annual_liability: 400,
			funds_due_envelope: { status: 'computed', amount: 42 }
		});
	});

	it('an UNAVAILABLE jurisdiction forwards null q4_installment/annual_liability and an unavailable envelope — NEVER coerced to 0', async () => {
		const { client } = makeSupabase({
			data: { ...WELL_FORMED, jurisdictions: { federal: UNAVAILABLE_JURISDICTION, california: computedJurisdiction() } },
			error: null
		});
		const result = await loadPriorYearQ4(client, WINDOW);
		expect(result.federal).toEqual({
			q4_installment: null,
			annual_liability: null,
			funds_due_envelope: { status: 'unavailable', reason: 'no_schedule_any_year' }
		});
	});

	it('propagates TaxLiabilityPayloadError from the second call rather than degrading', async () => {
		const { client } = makeSupabase({ error: { message: 'timeout' } });
		await expect(loadPriorYearQ4(client, WINDOW)).rejects.toBeInstanceOf(TaxLiabilityPayloadError);
	});
});

describe('loadPriorYearQ4 — N-4: the function\'s own range fence (Lock 15 / ADR-011 Decision 19)', () => {
	// serverTodayAsOf() is not mockable without touching production code (house convention —
	// see nav-series.test.ts), so these legs derive an offset from the WALL CLOCK's own current
	// year rather than hardcoding "today" — each leg still asserts a fixed, unambiguous relation
	// to today (always-past / always-future / floor-year) that holds on any day the suite runs.
	const CURRENT_YEAR = new Date().getUTCFullYear();

	it('an in-range tax_year passes through to the RPC call', async () => {
		const { client, rpc } = makeSupabase({
			data: {
				...WELL_FORMED,
				jurisdictions: { federal: computedJurisdiction(), california: computedJurisdiction() }
			},
			error: null
		});
		const result = await loadPriorYearQ4(client, { open: true, tax_year: 2020, due_date: '2021-01-15' });
		expect(rpc).toHaveBeenCalledWith('fn_compute_tax_liability', { p_data_as_of: '2020-12-31' });
		expect(result.as_of).toBe('2020-12-31');
	});

	it('a pre-2015 tax_year throws TaxLiabilityPayloadError naming the out-of-range date, never reaching the RPC', async () => {
		const { client, rpc } = makeSupabase({ data: WELL_FORMED, error: null });
		await expect(
			loadPriorYearQ4(client, { open: true, tax_year: 2014, due_date: '2015-01-15' })
		).rejects.toThrow(/2014-12-31 is out of range/);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('a future tax_year (CURRENT_YEAR + 1, always after today) throws, never reaching the RPC', async () => {
		const { client, rpc } = makeSupabase({ data: WELL_FORMED, error: null });
		await expect(
			loadPriorYearQ4(client, { open: true, tax_year: CURRENT_YEAR + 1, due_date: `${CURRENT_YEAR + 2}-01-15` })
		).rejects.toBeInstanceOf(TaxLiabilityPayloadError);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('boundary: tax_year 2015 (2015-12-31, the earliest value >= AS_OF_FLOOR 2015-12-01) passes — the floor is inclusive, not off-by-one', async () => {
		const { client, rpc } = makeSupabase({
			data: {
				...WELL_FORMED,
				jurisdictions: { federal: computedJurisdiction(), california: computedJurisdiction() }
			},
			error: null
		});
		await loadPriorYearQ4(client, { open: true, tax_year: 2015, due_date: '2016-01-15' });
		expect(rpc).toHaveBeenCalledWith('fn_compute_tax_liability', { p_data_as_of: '2015-12-31' });
	});

	it('boundary: tax_year CURRENT_YEAR - 1 (last calendar year\'s Dec 31, always <= today) passes — the ceiling is inclusive, not off-by-one', async () => {
		const { client, rpc } = makeSupabase({
			data: {
				...WELL_FORMED,
				jurisdictions: { federal: computedJurisdiction(), california: computedJurisdiction() }
			},
			error: null
		});
		await loadPriorYearQ4(client, {
			open: true,
			tax_year: CURRENT_YEAR - 1,
			due_date: `${CURRENT_YEAR}-01-15`
		});
		expect(rpc).toHaveBeenCalledWith('fn_compute_tax_liability', {
			p_data_as_of: `${CURRENT_YEAR - 1}-12-31`
		});
	});

	it('a non-integer window.tax_year throws before ever building an as-of string, never reaching the RPC', async () => {
		const { client, rpc } = makeSupabase({ data: WELL_FORMED, error: null });
		await expect(
			loadPriorYearQ4(client, { open: true, tax_year: 2020.5, due_date: '2021-01-15' })
		).rejects.toThrow(/not an integer/);
		expect(rpc).not.toHaveBeenCalled();
	});
});
