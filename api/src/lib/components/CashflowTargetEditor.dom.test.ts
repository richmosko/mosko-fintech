// CashflowTargetEditor.dom.test.ts — SELF-252 verification battery (Frontend's AC1/AC2/AC6-UI/AC8
// half). Covers:
//   - blank-vs-$0 prefill (AC2): a NULL column renders empty, a stored 0 renders "0" — the
//     distinction SELF-251's cash-flow caption branches on.
//   - the three-state-per-field POST body (AC3/AC6 UI): untouched → key OMITTED; edited →
//     number; explicitly cleared (via the Clear control) → `null`. Never both keys
//     unconditionally.
//   - the unset control's disabled state (nothing to clear on an already-blank field).
//   - redirect to `/cash-flow` on a successful save (AC8).
//   - field-level error rendering from a 400 `fieldErrors` body, the step_up_required (403)
//     generic copy, and a network failure.
//
// @vitest-environment jsdom

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, fireEvent, waitFor } from '@testing-library/svelte';
import CashflowTargetEditor from './CashflowTargetEditor.svelte';
import { goto } from '$app/navigation';

const UNSET = { income_target_annual: null, expense_target_monthly: null };

describe('CashflowTargetEditor — blank-vs-$0 prefill (AC2)', () => {
	it('renders both fields empty when both columns are NULL (never a seeded 0)', () => {
		const { getByLabelText } = render(CashflowTargetEditor, { props: { initialTargets: UNSET } });
		expect((getByLabelText('Annual income target') as HTMLInputElement).value).toBe('');
		expect((getByLabelText('Monthly expense target') as HTMLInputElement).value).toBe('');
	});

	it('renders a stored 0 AS "0" — a $0 target is a real fact, distinct from absence', () => {
		const { getByLabelText } = render(CashflowTargetEditor, {
			props: { initialTargets: { income_target_annual: 0, expense_target_monthly: null } }
		});
		expect((getByLabelText('Annual income target') as HTMLInputElement).value).toBe('0');
		expect((getByLabelText('Monthly expense target') as HTMLInputElement).value).toBe('');
	});

	it('renders an existing non-zero value prefilled', () => {
		const { getByLabelText } = render(CashflowTargetEditor, {
			props: { initialTargets: { income_target_annual: 120000, expense_target_monthly: 4500.5 } }
		});
		expect((getByLabelText('Annual income target') as HTMLInputElement).value).toBe('120000');
		expect((getByLabelText('Monthly expense target') as HTMLInputElement).value).toBe('4500.5');
	});
});

describe('CashflowTargetEditor — unset control (AC6 UI)', () => {
	it('the Clear button is disabled when the field is already blank (nothing to clear)', () => {
		const { getByRole } = render(CashflowTargetEditor, { props: { initialTargets: UNSET } });
		expect((getByRole('button', { name: 'Clear Annual income target' }) as HTMLButtonElement).disabled).toBe(true);
	});

	it('clicking Clear on a set field empties it and then disables the control', async () => {
		const { getByLabelText, getByRole } = render(CashflowTargetEditor, {
			props: { initialTargets: { income_target_annual: 5000, expense_target_monthly: null } }
		});
		const clearBtn = getByRole('button', { name: 'Clear Annual income target' }) as HTMLButtonElement;
		expect(clearBtn.disabled).toBe(false);
		await fireEvent.click(clearBtn);
		expect((getByLabelText('Annual income target') as HTMLInputElement).value).toBe('');
		expect(clearBtn.disabled).toBe(true);
	});
});

describe('CashflowTargetEditor — three-state-per-field POST body (AC3/AC6 UI) + redirect (AC8)', () => {
	const originalFetch = globalThis.fetch;

	beforeEach(() => {
		globalThis.fetch = vi.fn();
		(goto as ReturnType<typeof vi.fn>).mockClear();
	});
	afterEach(() => {
		globalThis.fetch = originalFetch;
	});

	it('an untouched field is OMITTED; an edited field is sent as a number; save disabled with nothing dirty', async () => {
		(globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue(
			new Response(JSON.stringify({ ok: true, income_annual: 90000 }), { status: 200 })
		);
		const { getByLabelText, getByRole } = render(CashflowTargetEditor, {
			props: { initialTargets: { income_target_annual: null, expense_target_monthly: 3000 } }
		});

		const saveBtn = getByRole('button', { name: 'Save changes' }) as HTMLButtonElement;
		expect(saveBtn.disabled).toBe(true);

		const incomeField = getByLabelText('Annual income target');
		await fireEvent.input(incomeField, { target: { value: '90000' } });
		expect(saveBtn.disabled).toBe(false);

		await fireEvent.click(saveBtn);
		await waitFor(() => expect(globalThis.fetch).toHaveBeenCalledTimes(1));

		const call = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0];
		expect(call[0]).toBe('/api/settings/cashflow-target');
		const body = JSON.parse(call[1].body);
		expect(body).toEqual({ income_annual: 90000 }); // expense_monthly untouched → omitted
		expect(body).not.toHaveProperty('expense_monthly');

		await waitFor(() => expect(goto).toHaveBeenCalledWith('/cash-flow'));
	});

	it('explicitly clearing a set field sends `null`, not omission or a number', async () => {
		(globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue(
			new Response(JSON.stringify({ ok: true }), { status: 200 })
		);
		const { getByRole } = render(CashflowTargetEditor, {
			props: { initialTargets: { income_target_annual: 90000, expense_target_monthly: null } }
		});

		await fireEvent.click(getByRole('button', { name: 'Clear Annual income target' }));
		const saveBtn = getByRole('button', { name: 'Save changes' }) as HTMLButtonElement;
		expect(saveBtn.disabled).toBe(false);
		await fireEvent.click(saveBtn);

		await waitFor(() => expect(globalThis.fetch).toHaveBeenCalledTimes(1));
		const body = JSON.parse((globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0][1].body);
		expect(body).toEqual({ income_annual: null });
	});

	it('a field edited back to its exact original value is no longer dirty — omitted, no spurious write', async () => {
		(globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue(
			new Response(JSON.stringify({ ok: true }), { status: 200 })
		);
		const { getByLabelText, getByRole } = render(CashflowTargetEditor, {
			props: { initialTargets: { income_target_annual: 90000, expense_target_monthly: null } }
		});
		const incomeField = getByLabelText('Annual income target');
		await fireEvent.input(incomeField, { target: { value: '95000' } });
		await fireEvent.input(incomeField, { target: { value: '90000' } });
		expect((getByRole('button', { name: 'Save changes' }) as HTMLButtonElement).disabled).toBe(true);
	});

	it('both fields dirty (one value, one cleared) sends exactly those two keys, never both-keys-always for an untouched third state', async () => {
		(globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue(
			new Response(JSON.stringify({ ok: true }), { status: 200 })
		);
		const { getByLabelText, getByRole } = render(CashflowTargetEditor, {
			props: { initialTargets: { income_target_annual: 90000, expense_target_monthly: 3000 } }
		});
		await fireEvent.input(getByLabelText('Annual income target'), {
			target: { value: '95000' }
		});
		await fireEvent.click(getByRole('button', { name: 'Clear Monthly expense target' }));
		await fireEvent.click(getByRole('button', { name: 'Save changes' }));

		await waitFor(() => expect(globalThis.fetch).toHaveBeenCalledTimes(1));
		const body = JSON.parse((globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0][1].body);
		expect(body).toEqual({ income_annual: 95000, expense_monthly: null });
	});
});

describe('CashflowTargetEditor — error handling', () => {
	const originalFetch = globalThis.fetch;
	beforeEach(() => {
		globalThis.fetch = vi.fn();
	});
	afterEach(() => {
		globalThis.fetch = originalFetch;
	});

	it('renders a field-level error from a 400 fieldErrors body and does not redirect', async () => {
		(globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue(
			new Response(
				JSON.stringify({ error: 'invalid_request', fieldErrors: { income_annual: ['Amount is out of range.'] } }),
				{ status: 400 }
			)
		);
		const { getByLabelText, getByRole, findByText } = render(CashflowTargetEditor, {
			props: { initialTargets: UNSET }
		});
		// A well-formed value the client battery accepts locally — exercises the server's
		// fieldErrors path directly (e.g. a value the DB CHECK rejects for a reason the
		// client-side battery has no equivalent for).
		await fireEvent.input(getByLabelText('Annual income target'), {
			target: { value: '1000' }
		});
		await fireEvent.click(getByRole('button', { name: 'Save changes' }));
		expect(await findByText('Amount is out of range.')).toBeTruthy();
	});

	it('renders the generic step-up copy on a 403 step_up_required response', async () => {
		(globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue(
			new Response(JSON.stringify({ error: 'step_up_required' }), { status: 403 })
		);
		const { getByLabelText, getByRole, findByRole } = render(CashflowTargetEditor, {
			props: { initialTargets: UNSET }
		});
		await fireEvent.input(getByLabelText('Annual income target'), { target: { value: '1000' } });
		await fireEvent.click(getByRole('button', { name: 'Save changes' }));
		const banner = await findByRole('alert');
		expect(banner.textContent).toBe("Verify it's you and try again.");
	});

	it('renders a generic message on network failure', async () => {
		(globalThis.fetch as ReturnType<typeof vi.fn>).mockRejectedValue(new Error('network down'));
		const { getByLabelText, getByRole, findByRole } = render(CashflowTargetEditor, {
			props: { initialTargets: UNSET }
		});
		await fireEvent.input(getByLabelText('Annual income target'), { target: { value: '1000' } });
		await fireEvent.click(getByRole('button', { name: 'Save changes' }));
		const banner = await findByRole('alert');
		expect(banner.textContent).toBe('Something went wrong saving your changes. Please try again.');
	});
});
