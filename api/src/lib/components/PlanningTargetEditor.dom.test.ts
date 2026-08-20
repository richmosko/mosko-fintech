// PlanningTargetEditor.dom.test.ts — N7-A verification battery (SELF-242), closing two
// catch-criteria PM's AC delta named explicitly (relayed by team-lead, 2026-08-20):
//
// (1) element === 'asset' ALONE would newly ADMIT Real Estate Sub-Cats (Real Estate is
//     itself element = 'asset', 085's backfill) — the existing cat !== 'Real Estate'
//     filter must remain a SEPARATE, additional predicate. NOT independently testable
//     behaviorally today, and this file says so rather than faking a test that would pass
//     either way: CAT_GROUP_ORDER (allocation-taxonomy.ts) never includes 'Real Estate' as
//     a group key, so catGroups' per-cat lookup and usEquityRows' cat==='Marketable
//     Securities' lookup structurally cannot surface a Real Estate row regardless of
//     whether the name filter exists — a DOM test asserting "Residential" never renders
//     would pass with or without that filter, which is the "assertion with no behavioural
//     observer" shape 074's own migration header already names for a different clause. The
//     correct verification for THIS predicate is structural (read the source — both
//     predicates ARE present, `element === 'asset' && cat !== 'Real Estate'`, see the
//     PlanningTargetEditor.svelte header + nonReCatalog derivation), belt-and-suspenders
//     against a FUTURE change (e.g. SELF-239 making the grouping data-driven off every
//     distinct Cat present) rather than a live bug this test suite can catch today.
//
// (2) The grand total must count each stored target EXACTLY ONCE — the twelve US-equity
//     Sub-Cats render individually in the US Equity sub-section, and their combined value
//     is folded into the Marketable Securities Cat-group sum (catSums) EXACTLY ONCE (only
//     inside the `g.cat === US_EQUITY_PARENT_CAT` branch); the separately-displayed
//     usEquitySum caption is informational only and is never added into grandTotal a
//     second time. THIS predicate IS independently observable — a regression here changes
//     the rendered grand-total number — so it gets a real DOM assertion below, worked
//     through a fixture designed so a double-count would produce a DIFFERENT total than a
//     correct one (21.00% correct vs. 31.00% if the US-equity twelve were summed twice).
//
// Also covers: a Liabilities-element row (N7-A's live, behaviorally-observable predicate —
// 'Liabilities' IS a CAT_GROUP_ORDER member, unlike Real Estate) is excluded from both the
// rendered groups and the grand total, and its whole Cat-group card is DROPPED rather than
// rendered empty.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/svelte';
import PlanningTargetEditor from './PlanningTargetEditor.svelte';

type Row = {
	id: number;
	cat: string;
	sub_cat: string;
	display_order: number | null;
	element: 'asset' | 'liability';
};

const catalog: Row[] = [
	{ id: 1, cat: 'Cash', sub_cat: 'FDIC', display_order: 10, element: 'asset' },
	{ id: 2, cat: 'Marketable Securities', sub_cat: 'UNKNOWN', display_order: 90, element: 'asset' },
	{
		id: 3,
		cat: 'Marketable Securities',
		sub_cat: 'ExUS-Developed_Market',
		display_order: 220,
		element: 'asset'
	},
	{
		id: 4,
		cat: 'Marketable Securities',
		sub_cat: 'US-01-Basic_Materials',
		display_order: 100,
		element: 'asset'
	},
	{
		id: 5,
		cat: 'Marketable Securities',
		sub_cat: 'US-02-Telecom',
		display_order: 110,
		element: 'asset'
	},
	{ id: 6, cat: 'Alternatives', sub_cat: 'REIT', display_order: 240, element: 'asset' },
	{ id: 7, cat: 'Liabilities', sub_cat: 'Credit-Balance', display_order: 290, element: 'liability' },
	{ id: 8, cat: 'Real Estate', sub_cat: 'Residential', display_order: 320, element: 'asset' }
];

// Cash=5, Marketable Securities direct(UNKNOWN=3, ExUS-Developed=2)=5, US Equity(US-01=4,
// US-02=6)=10 folded into Marketable Securities' own sum -> Marketable Securities total=15,
// Alternatives=1. Liabilities=100 and Real Estate=50 are POISON VALUES: either leaking into
// the total would be immediately visible (100 alone dwarfs every legitimate value here).
// Correct grand total = 5 + 15 + 1 = 21.00. A double-count of the US-equity ten would read
// 31.00 instead (21 + the 10 counted again).
const initialTargets = { 1: 5, 2: 3, 3: 2, 4: 4, 5: 6, 6: 1, 7: 100, 8: 50 };

describe('PlanningTargetEditor — N7-A element filter + grand-total exactness', () => {
	it('excludes a Liabilities-element row and drops its Cat-group card entirely', () => {
		const { queryByRole, queryByText } = render(PlanningTargetEditor, {
			props: { catalog, initialTargets }
		});
		expect(queryByRole('heading', { name: 'Liabilities' })).toBeNull();
		expect(queryByText('Credit-Balance')).toBeNull();
	});

	it('renders Cash, Marketable Securities, and Alternatives groups (non-empty after the element filter)', () => {
		const { getByRole } = render(PlanningTargetEditor, { props: { catalog, initialTargets } });
		expect(getByRole('heading', { name: 'Cash' })).toBeTruthy();
		expect(getByRole('heading', { name: 'Marketable Securities' })).toBeTruthy();
		expect(getByRole('heading', { name: 'Alternatives' })).toBeTruthy();
	});

	it('renders the US Equity sub-section rows individually, each with its own field', () => {
		const { getByLabelText } = render(PlanningTargetEditor, { props: { catalog, initialTargets } });
		expect((getByLabelText('US-01-Basic_Materials') as HTMLInputElement).value).toBe('4');
		expect((getByLabelText('US-02-Telecom') as HTMLInputElement).value).toBe('6');
	});

	it('the Marketable Securities Cat-group sum folds the US-equity contribution in exactly once (15.00%, not 5.00% or 25.00%)', () => {
		const { getByText } = render(PlanningTargetEditor, { props: { catalog, initialTargets } });
		expect(getByText('15.00%')).toBeTruthy();
	});

	it('the US Equity sub-section shows its own subtotal (10.00%) as an informational readout, separate from the Cat-group sum', () => {
		const { getByText } = render(PlanningTargetEditor, { props: { catalog, initialTargets } });
		expect(getByText('10.00%')).toBeTruthy();
	});

	it('the grand total counts every stored target exactly once: 21.00% — not 31.00% (US-equity double-counted) and not including Liabilities(100) or Real Estate(50)', () => {
		const { getByText, queryByText } = render(PlanningTargetEditor, {
			props: { catalog, initialTargets }
		});
		expect(getByText('21.00%')).toBeTruthy();
		expect(queryByText('31.00%')).toBeNull();
		expect(queryByText('121.00%')).toBeNull(); // would appear if Liabilities' 100 leaked in
		expect(queryByText('71.00%')).toBeNull(); // would appear if Real Estate's 50 leaked in
	});
});
