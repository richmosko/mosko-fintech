// TaxBracketScheduleEditor.dom.test.ts — SELF-265 verification battery. Covers:
//   - percent<->fraction round trip at render (fraction 0.22 displays "22") and at save
//     (edited percent "24" submits as fraction 0.24).
//   - the rate-monotonicity courtesy message (Leg B) — reachable through normal editing, since
//     only the FIRST row's floor is structurally fixed (see below), not its rate.
//   - the first row's floor rendering DISABLED and fixed at "0" (the structural-picker judgment
//     call this component's header names) — the zero-floor courtesy message itself (Leg A) is
//     therefore untestable through this component's UI and is covered instead in
//     $lib/validation/taxBracketRows.test.ts, against the shared validation module directly.
//   - the federal_lt_cg "takes no deduction" stated-fact caption (AC2).
//   - the schedule-label textarea holding the seeded 473-character California label (E29's
//     500-character bound).
//   - the POST payload shape: {schedule_id} in the URL, tax_year/schedule_type passed through
//     unchanged as the identity guard the endpoint enforces, rows in submission order.
//
// @vitest-environment jsdom

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, fireEvent, waitFor } from '@testing-library/svelte';
import TaxBracketScheduleEditor from './TaxBracketScheduleEditor.svelte';

type Schedule = {
	id: number;
	tax_year: number;
	schedule_type: 'federal_ordinary' | 'federal_lt_cg' | 'california_ordinary';
	schedule_label: string;
	standard_deduction: number;
	tax_balance_prior_year: number | null;
	rows: { bracket_floor: number; bracket_rate: number }[];
};

const federalOrdinary: Schedule = {
	id: 1,
	tax_year: 2026,
	schedule_type: 'federal_ordinary',
	schedule_label: 'Single filer, 2026 IRS Schedule X',
	standard_deduction: 15000,
	tax_balance_prior_year: null,
	rows: [
		{ bracket_floor: 0, bracket_rate: 0.1 },
		{ bracket_floor: 11000, bracket_rate: 0.22 }
	]
};

describe('TaxBracketScheduleEditor — percent<->fraction boundary (E1)', () => {
	it('renders stored fraction rates as percent strings', () => {
		const { getByLabelText } = render(TaxBracketScheduleEditor, { props: { schedule: federalOrdinary } });
		expect((getByLabelText('Bracket 2 rate') as HTMLInputElement).value).toBe('22');
	});

	it('the first row’s floor renders DISABLED and fixed at "0" — structurally unreachable for the zero-floor error', () => {
		const { getByLabelText } = render(TaxBracketScheduleEditor, { props: { schedule: federalOrdinary } });
		const fixedFloor = getByLabelText('Bracket 1 floor') as HTMLInputElement;
		expect(fixedFloor.value).toBe('0');
		expect(fixedFloor.disabled).toBe(true);
	});

	it('submits an edited percent as its FRACTION value', async () => {
		globalThis.fetch = vi.fn().mockResolvedValue(new Response(JSON.stringify({ ok: true }), { status: 200 }));
		const { getByLabelText, getByRole } = render(TaxBracketScheduleEditor, {
			props: { schedule: federalOrdinary }
		});
		await fireEvent.input(getByLabelText('Bracket 2 rate'), { target: { value: '24' } });
		await fireEvent.click(getByRole('button', { name: 'Save changes' }));

		await waitFor(() => expect(globalThis.fetch).toHaveBeenCalledTimes(1));
		const call = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0];
		expect(call[0]).toBe('/api/settings/tax-brackets/1');
		const body = JSON.parse(call[1].body);
		expect(body.rows).toEqual([
			{ bracket_floor: 0, bracket_rate: 0.1 },
			{ bracket_floor: 11000, bracket_rate: 0.24 }
		]);
		// Identity passthrough — the endpoint's 409 schedule-identity guard requires these to
		// match the resolved row unchanged; this component never offers to edit them.
		expect(body.tax_year).toBe(2026);
		expect(body.schedule_type).toBe('federal_ordinary');
	});
});

describe('TaxBracketScheduleEditor — Leg B rate-monotonicity courtesy message', () => {
	it('shows the non-decreasing-rate message and disables Save when a later rate drops below an earlier one', async () => {
		const { getByLabelText, getByRole, findByRole } = render(TaxBracketScheduleEditor, {
			props: { schedule: federalOrdinary }
		});
		await fireEvent.input(getByLabelText('Bracket 2 rate'), { target: { value: '5' } }); // below bracket 1's 10%
		const banner = await findByRole('alert');
		expect(banner.textContent).toBe('Bracket rates must not decrease as thresholds rise.');
		expect((getByRole('button', { name: 'Save changes' }) as HTMLButtonElement).disabled).toBe(true);
	});
});

describe('TaxBracketScheduleEditor — federal_lt_cg "takes no deduction" stated fact (AC2)', () => {
	it('renders the no-deduction caption for federal_lt_cg regardless of the entered value', () => {
		const ltcg: Schedule = {
			...federalOrdinary,
			id: 2,
			schedule_type: 'federal_lt_cg',
			schedule_label: 'Single filer — federal long-term capital gains, 2026',
			standard_deduction: 0
		};
		const { getByText } = render(TaxBracketScheduleEditor, { props: { schedule: ltcg } });
		expect(
			getByText(
				'Federal long-term capital gains takes no separate standard deduction — 0 is a stated fact for this schedule, not a blank.'
			)
		).toBeTruthy();
	});

	it('does NOT render the caption for a different schedule_type', () => {
		const { queryByText } = render(TaxBracketScheduleEditor, { props: { schedule: federalOrdinary } });
		expect(queryByText(/takes no separate standard deduction/)).toBeNull();
	});
});

describe('TaxBracketScheduleEditor — schedule_label textarea (E29 500-char bound)', () => {
	it('holds the seeded 473-character California label without truncation', () => {
		const longLabel = 'A'.repeat(473);
		const schedule: Schedule = { ...federalOrdinary, id: 3, schedule_label: longLabel };
		const { getByLabelText } = render(TaxBracketScheduleEditor, { props: { schedule } });
		const textarea = getByLabelText('Schedule label', { exact: false }) as HTMLTextAreaElement;
		expect(textarea.value).toBe(longLabel);
		expect(textarea.value.length).toBe(473);
	});
});

describe('TaxBracketScheduleEditor — save error handling', () => {
	const originalFetch = globalThis.fetch;
	beforeEach(() => {
		globalThis.fetch = vi.fn();
	});
	afterEach(() => {
		globalThis.fetch = originalFetch;
	});

	it('renders the schedule-identity-mismatch (409) copy', async () => {
		(globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue(
			new Response(JSON.stringify({ error: 'schedule_identity_mismatch' }), { status: 409 })
		);
		const { getByRole, findByRole } = render(TaxBracketScheduleEditor, { props: { schedule: federalOrdinary } });
		await fireEvent.click(getByRole('button', { name: 'Save changes' }));
		const banner = await findByRole('alert');
		expect(banner.textContent).toBe('This schedule’s year or type changed elsewhere. Refresh and try again.');
	});

	it('renders a rows-level error from a 400 fieldErrors body keyed "rows"', async () => {
		(globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue(
			new Response(
				JSON.stringify({ error: 'invalid_request', fieldErrors: { rows: ['Enter a value of at most 1.'] } }),
				{ status: 400 }
			)
		);
		const { getByRole, findByText } = render(TaxBracketScheduleEditor, { props: { schedule: federalOrdinary } });
		await fireEvent.click(getByRole('button', { name: 'Save changes' }));
		expect(await findByText('Enter a value of at most 1.')).toBeTruthy();
	});
});
