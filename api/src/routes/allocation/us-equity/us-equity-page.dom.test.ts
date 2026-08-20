// us-equity-page.dom.test.ts — SELF-241 AC6 (return leg): the /allocation/us-equity drill-down
// page always offers a way back to /allocation, independent of load success/failure. The
// "into" leg (§2.2.2's "US - Sector Diversified" row → /allocation/us-equity) is already
// covered by NonReAllocationTable.dom.test.ts's own SELF-241 AC6 block; this file is the
// missing other half — no test anywhere exercised +page.svelte itself before this file.
//
// NOVEL PRECEDENT: no +page.svelte DOM test exists elsewhere in this repo (every existing
// route test is a +page.server.ts load()-integration test, e.g. nav-series.server.test.ts).
// This is the same @testing-library/svelte render() pattern already used for every
// $lib/components/*.svelte test, just applied to a route component instead — not a new
// pattern, so it doesn't carry the burden novelty would. Flagged at hand-off per QA's charter
// (starting +page.svelte coverage precedent is team-lead/F/CTO's call, not QA's to make
// unprompted) — this file is offered as commit-ready content, not committed by QA.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/svelte';
import UsEquityPage from './+page.svelte';
import { EMPTY_STALENESS, UNKNOWN_STALENESS } from '$lib/staleness/stale-constituent';
import type { UsEquityAllocation } from '$lib/us-equity-allocation';
import { US_EQUITY_SUB_CATS } from '$lib/allocation-taxonomy';

// The root +layout.server.ts (SELF-285/200/207) contributes userEmail/pendingClassificationCount/
// connectionHealth to every route's merged PageData — this route's own +page.server.ts only adds
// usEquityAllocation/staleness on top. `data` here must satisfy the FULL merged PageData type
// (svelte-check enforces this even though the component itself never reads the layout fields), so
// every fixture below carries neutral layout-default values alongside the two fields this page
// actually consumes. Structural typing only — no import from $lib/server/** needed.
const LAYOUT_DEFAULTS = {
	userEmail: null,
	pendingClassificationCount: 0,
	connectionHealth: { reauthCount: 0, institutionDownCount: 0 }
};

const POPULATED: UsEquityAllocation = {
	rows: US_EQUITY_SUB_CATS.map((sub_cat, i) => ({
		sub_cat_id: i + 1,
		cat: 'Marketable Securities',
		sub_cat,
		pct_target: 5,
		pct_alloc: 8.33,
		dollar_target: 500,
		dollar_alloc: 833,
		dollar_realloc: -333
	})),
	total: { dollar_alloc: 9996, pct_alloc: 100, pct_target: 100, dollar_target: 6000, dollar_realloc: 0 }
};

describe('allocation/us-equity +page.svelte — AC6 return leg: back-link to /allocation', () => {
	it('renders a back-link to /allocation when the loader succeeds', () => {
		const { getByRole } = render(UsEquityPage, {
			props: { data: { ...LAYOUT_DEFAULTS, usEquityAllocation: POPULATED, staleness: EMPTY_STALENESS } }
		});
		const back = getByRole('link', { name: /Back to Allocation/i });
		expect(back.tagName).toBe('A');
		expect(back.getAttribute('href')).toBe('/allocation');
	});

	it('still renders the back-link when usEquityAllocation is null (loader failure) — never stranded', () => {
		const { getByRole, queryByRole } = render(UsEquityPage, {
			props: { data: { ...LAYOUT_DEFAULTS, usEquityAllocation: null, staleness: UNKNOWN_STALENESS } }
		});
		const back = getByRole('link', { name: /Back to Allocation/i });
		expect(back.getAttribute('href')).toBe('/allocation');
		// The failure state renders instead of the table — no table role present.
		expect(queryByRole('table')).toBeNull();
	});

	it('renders the twelve-row table when the loader succeeds (delegates to UsEquityAllocationTable)', () => {
		const { getByRole } = render(UsEquityPage, {
			props: { data: { ...LAYOUT_DEFAULTS, usEquityAllocation: POPULATED, staleness: EMPTY_STALENESS } }
		});
		expect(getByRole('table')).toBeTruthy();
	});
});
