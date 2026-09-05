// fixtures/monthly-report.ts — a well-formed MonthlyReportHeader + MonthlyReportPayload pair for
// the §2.6.1.b monthly report render (SELF-354 / P2), built from migration 110's CONTRACT shape
// verbatim (supabase/migrations/110_fn_render_monthly_report.sql, feature/self-345 @ be7aed6).
//
// SHARED FIXTURE, not a one-off test stub: P6 (PDF export) and A5 (PDF-composition worker call)
// consume the SAME shared template (MonthlyReportView.svelte, R2 (C)) this fixture feeds, so this
// file lives under $lib/fixtures/ rather than colocated with one test file — every consumer of the
// template can build against the SAME payload shape rather than each hand-rolling its own,
// independently-drifting fixture.
//
// Two exports: `MONTHLY_REPORT_HEADER_FINAL` / `MONTHLY_REPORT_HEADER_DRAFT` (the two
// `generation_status` values this route ever renders — R10 A-8, `superseded` is never rendered in
// V1) and `MONTHLY_REPORT_PAYLOAD` (the payload — identical shape regardless of which header it is
// paired with, since R1 (A)'s entire point is ONE render path over ONE payload shape).

import type { MonthlyReportHeader, MonthlyReportPayload } from '../monthly-report';
import type { NavComposition } from '../nav-composition';
import type { CashflowCrossAccountRollup, CashflowSection } from '../cashflow-rollup';
import type { HistoricalExpenditurePoint } from '../historical-expenditures';
import type { TaxJurisdictionPayload } from '../tax-quarterly';

export const MONTHLY_REPORT_HEADER_FINAL: MonthlyReportHeader = {
	report_id: 42,
	target_month: '2026-08-01',
	generation_status: 'final',
	data_as_of: '2026-08-31',
	generated_at: '2026-09-02T14:00:00Z',
	owner_header_at_generation: 'THE SMITH 2023 TRUST',
	commentary_cash: 'Holding steady; no changes planned this quarter.',
	commentary_bonds: '',
	commentary_marketable_securities: 'Rebalanced into international equity per plan.',
	commentary_alternatives: '',
	commentary_disposition: 'authored'
};

export const MONTHLY_REPORT_HEADER_DRAFT: MonthlyReportHeader = {
	...MONTHLY_REPORT_HEADER_FINAL,
	report_id: 43,
	generation_status: 'draft',
	generated_at: null,
	owner_header_at_generation: null,
	commentary_disposition: null
};

const ACCOUNT_HOLDINGS: NavComposition = {
	groups: [
		{
			category: 'investment',
			subtotal: 500_000,
			accounts: [
				{
					account_id: 1,
					account_name: 'Brokerage',
					current_market_value: 500_000,
					unrealized_gl: 42_000,
					is_stale: false
				}
			]
		},
		{
			category: 'liability',
			subtotal: -150_000,
			accounts: [
				{
					account_id: 2,
					account_name: 'Mortgage',
					current_market_value: -150_000,
					unrealized_gl: null,
					is_stale: false
				}
			]
		}
	],
	buildups: {
		total_non_re: 500_000,
		gross_total: 500_000,
		debt: 150_000,
		realized_tax_liab: { status: 'computed', amount: 4_200 },
		unrealized_tax_liab: { status: 'computed', amount: 1_800 }
	},
	nav: 350_000
};

function cashflowSection(
	over: Partial<CashflowSection> & { cat: string; sectionKey: 'income' | 'expenses' }
): CashflowSection {
	return {
		rows: [],
		total: { month: 0, q1: 0, q2: 0, q3: 0, q4: 0, ytd: 0 },
		label: over.sectionKey === 'income' ? 'Income' : 'Expenses',
		...over
	};
}

const CROSS_ACCOUNT_ROLLUP: CashflowCrossAccountRollup = {
	as_of: '2026-08-31',
	sections: [
		cashflowSection({
			cat: 'Revenue',
			sectionKey: 'income',
			rows: [{ sub_cat: 'Salary', month: 5000, q1: 15000, q2: 15000, q3: null, q4: null, ytd: 30000 }],
			total: { month: 5000, q1: 15000, q2: 15000, q3: null, q4: null, ytd: 30000 }
		}),
		cashflowSection({
			cat: 'Expense',
			sectionKey: 'expenses',
			rows: [{ sub_cat: 'Rent', month: -2000, q1: -6000, q2: -6000, q3: null, q4: null, ytd: -12000 }],
			total: { month: -2000, q1: -6000, q2: -6000, q3: null, q4: null, ytd: -12000 }
		})
	],
	targets: { income_target_annual: 60000, expense_target_monthly: 2200 },
	unclassified: { count_ytd: 2 }
};

const HISTORICAL_EXPENDITURES: HistoricalExpenditurePoint[] = [
	{
		month_end: '2026-08-31',
		expense_monthly_nominal: 2000,
		expense_monthly_inflation_adjusted: 1950,
		rolling_12mo_avg_inflation_adjusted: 1900,
		cpi_period: '2026-07',
		cpi_value: 314.2,
		cpi_is_carried: false,
		cpi_carried_from: null,
		cpi_period_was_due: true,
		cpi_nonpublication_on_record: false,
		cpi_coverage_through: '2026-07'
	}
];

const JURISDICTION_COMPUTED: TaxJurisdictionPayload = {
	status: 'computed',
	basis_year: 2026,
	schedules: {
		federal_ordinary: { present: true, basis_year: 2026, current_year_schedule_empty: false }
	},
	inputs: { ordinary_input: 100000, lt_cg_input: 0, standard_deduction: 14600 },
	taxable_income: { ordinary: 85400, lt_cg: null },
	annual_liability: 12000,
	tax_balance_prior_year: 0,
	installments: [
		{ quarter: 1, due_date: '2026-04-15', amount: 3000 },
		{ quarter: 2, due_date: '2026-06-15', amount: 3000 },
		{ quarter: 3, due_date: '2026-09-15', amount: 3000 },
		{ quarter: 4, due_date: '2027-01-15', amount: 3000 }
	],
	installments_due_through_next: 2,
	next_due_date: '2026-09-15',
	ytd_paid: { status: 'designated', amount: 6000 },
	funds_due: { status: 'computed', amount: 3000 },
	applied_marginal_rate: { ordinary: 0.24 }
};

export const MONTHLY_REPORT_PAYLOAD: MonthlyReportPayload = {
	payload_schema_version: 1,
	target_month: '2026-08-01',
	as_of: '2026-08-31',
	sections: {
		account_holdings: ACCOUNT_HOLDINGS,
		nav_performance: {
			series: [
				{ point_date: '2026-08-01', nav_value: 350_000, checkpoint_date: '2026-08-31' }
			],
			series_inflation_adjusted: [
				{
					point_date: '2026-08-01',
					nav_nominal: 350_000,
					checkpoint_date: '2026-08-31',
					nav_inflation_adjusted: 340_000,
					cpi_period: '2026-07',
					cpi_value: 314.2,
					cpi_is_carried: false,
					cpi_carried_from: null,
					cpi_period_was_due: true,
					cpi_nonpublication_on_record: false,
					cpi_coverage_through: '2026-07'
				}
			],
			delta_panel: { status: 'unavailable', reason: 'reader_not_as_of_threadable' },
			reference_dates: { status: 'unavailable', reason: 'reader_not_as_of_threadable' }
		},
		asset_allocation: {
			rows: [
				{ sub_cat_id: 1, cat: 'US Equity', sub_cat: 'US - Sector Diversified', market_value: 300_000, target_percent: 60 },
				{ sub_cat_id: 2, cat: 'US Equity', sub_cat: 'US - Small Cap', market_value: 50_000, target_percent: null },
				{ sub_cat_id: 3, cat: 'Fixed Income', sub_cat: 'Bonds - Aggregate', market_value: 150_000, target_percent: 30 }
			]
		},
		rebalancing_targets: {
			source_report_id: 42,
			cash: 'Holding steady; no changes planned this quarter.',
			bonds: '',
			marketable_securities: 'Rebalanced into international equity per plan.',
			alternatives: '',
			disposition: 'authored'
		},
		cash_flow: {
			cross_account_rollup: CROSS_ACCOUNT_ROLLUP,
			historical_expenditures: HISTORICAL_EXPENDITURES
		},
		estimated_taxes: {
			as_of: '2026-08-31',
			tax_year: 2026,
			decomposition: {
				ordinary_income: {
					rows: [
						{ sub_cat_id: 1, cat: 'Revenue', sub_cat: 'Salary', tax_character: 'ordinary', amount: 30000 }
					],
					total: 30000
				},
				capital_gains: { status: 'unavailable', reason: 'no_sale_recording_capability' },
				unclassified: { count_ytd: 2 }
			},
			jurisdictions: {
				federal: JURISDICTION_COMPUTED,
				california: { ...JURISDICTION_COMPUTED, applied_marginal_rate: { ordinary: 0.093 } }
			},
			nav_components: {
				realized_tax_liab: { status: 'computed', amount: 4_200 },
				unrealized_tax_liab: { status: 'computed', amount: 1_800 }
			},
			prior_year_q4_window: { open: false, tax_year: 2025, due_date: '2026-01-15' }
		}
	}
};
