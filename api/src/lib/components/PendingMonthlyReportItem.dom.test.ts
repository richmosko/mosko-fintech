// PendingMonthlyReportItem.dom.test.ts — SELF-356 / P4 AC1-AC4. Covers:
//   - AC3's verbatim item copy;
//   - the "Write commentary" CTA links into P3's editor (unchanged target);
//   - the no-ledger-designated prompt renders/does not render per the `noLedgerDesignated` prop
//     (AC4) — the prompt's own copy is NoLedgerDesignatedPrompt.dom.test.ts's job, this file only
//     proves the conditional wiring;
//   - the skip control (SkipFinalizeControl.svelte) is present, own coverage in its own test file.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/svelte';
import PendingMonthlyReportItem from './PendingMonthlyReportItem.svelte';

const PROPS = { targetMonth: '2026-08-01', monthLabel: 'August 2026', noLedgerDesignated: false };

describe('PendingMonthlyReportItem — AC3 verbatim copy + CTAs', () => {
	it('renders the verbatim pending-item copy', () => {
		const { getByText } = render(PendingMonthlyReportItem, { props: PROPS });
		expect(getByText('August 2026 — awaiting your Rebalancing Targets commentary.')).toBeTruthy();
	});

	it('"Write commentary" links into P3\'s editor for this month', () => {
		const { getByRole } = render(PendingMonthlyReportItem, { props: PROPS });
		const link = getByRole('link', { name: 'Write commentary' }) as HTMLAnchorElement;
		expect(link.getAttribute('href')).toBe('/reports/monthly/2026-08/commentary');
	});

	it('the "Skip commentary and finalize" control is present', () => {
		const { getByRole } = render(PendingMonthlyReportItem, { props: PROPS });
		expect(getByRole('button', { name: 'Skip commentary and finalize August 2026' })).toBeTruthy();
	});
});

describe('PendingMonthlyReportItem — no-ledger-designated prompt wiring (AC4)', () => {
	it('renders the prompt when noLedgerDesignated is true', () => {
		const { getByText } = render(PendingMonthlyReportItem, {
			props: { ...PROPS, noLedgerDesignated: true }
		});
		expect(
			getByText('No IRS/FTB ledger designated — NAV on this report will exclude tax liabilities.')
		).toBeTruthy();
	});

	it('is absent when noLedgerDesignated is false', () => {
		const { queryByText } = render(PendingMonthlyReportItem, { props: PROPS });
		expect(queryByText(/No IRS\/FTB ledger designated/)).toBeNull();
	});
});
