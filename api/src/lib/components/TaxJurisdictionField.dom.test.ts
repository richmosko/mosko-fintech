// TaxJurisdictionField.dom.test.ts — SELF-267 AC 2 / AC 2b DOM battery.
//
// Covers: the three explicit states render (none / IRS / FTB — not two-plus-a-blank), the
// "Not a tax authority ledger" default is a real selectable option (not a placeholder reading as
// "unanswered"), a selection round-trips through the bound value the way the form action reads
// it, the inline field-error slot renders on a server-side conflict (AC 3, the partial-unique-
// index rejection), and the control is hidden entirely (no combobox in the DOM at all) for a
// provider-linked account.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, fireEvent } from '@testing-library/svelte';
import TaxJurisdictionField from './TaxJurisdictionField.svelte';

describe('TaxJurisdictionField — three explicit states (AC 2 / AC 2b)', () => {
	it('renders exactly three options, in order: unset default, IRS, FTB', () => {
		const { getByRole } = render(TaxJurisdictionField);
		const select = getByRole('combobox') as HTMLSelectElement;
		const opts = Array.from(select.options).map((o) => ({ value: o.value, text: o.textContent }));
		expect(opts).toEqual([
			{ value: '', text: 'Not a tax authority ledger' },
			{ value: 'irs', text: 'IRS (Federal)' },
			{ value: 'ftb', text: 'FTB (California)' }
		]);
	});

	it('the default (no `value` prop) selects "Not a tax authority ledger" explicitly — never a blank/placeholder read', () => {
		const { getByRole } = render(TaxJurisdictionField);
		const select = getByRole('combobox') as HTMLSelectElement;
		expect(select.value).toBe('');
		expect(select.selectedOptions[0].textContent).toBe('Not a tax authority ledger');
	});

	it('an already-designated account (value="irs") preselects IRS', () => {
		const { getByRole } = render(TaxJurisdictionField, { props: { value: 'irs' } });
		const select = getByRole('combobox') as HTMLSelectElement;
		expect(select.value).toBe('irs');
	});
});

describe('TaxJurisdictionField — selection round-trips into the form payload', () => {
	it('choosing FTB updates the native <select> value — what a real submit reads under `name`', async () => {
		const { getByRole } = render(TaxJurisdictionField, { props: { value: 'irs' } });
		const select = getByRole('combobox') as HTMLSelectElement;
		expect(select.value).toBe('irs');
		await fireEvent.change(select, { target: { value: 'ftb' } });
		expect(select.value).toBe('ftb');
	});

	it('choosing "Not a tax authority ledger" from a designated state clears back to `""` — the unmark path (AC 2b)', async () => {
		const { getByRole } = render(TaxJurisdictionField, { props: { value: 'irs' } });
		const select = getByRole('combobox') as HTMLSelectElement;
		await fireEvent.change(select, { target: { value: '' } });
		expect(select.value).toBe('');
	});

	it('the field posts under the DEFAULT name `tax_jurisdiction` — the FormData key both actions read', () => {
		const { getByRole } = render(TaxJurisdictionField);
		expect((getByRole('combobox') as HTMLSelectElement).name).toBe('tax_jurisdiction');
	});
});

describe('TaxJurisdictionField — inline field error (AC 3, the one-per-authority conflict)', () => {
	it('renders the server-mapped conflict message via the SelectField error slot', () => {
		const { getByRole, getByText } = render(TaxJurisdictionField, {
			props: { value: 'irs', errors: ['You already have an IRS account.'] }
		});
		const alert = getByRole('alert');
		expect(alert.textContent).toBe('You already have an IRS account.');
		expect(getByText('You already have an IRS account.')).toBeTruthy();
	});

	it('no errors prop → no alert rendered', () => {
		const { queryByRole } = render(TaxJurisdictionField);
		expect(queryByRole('alert')).toBeNull();
	});
});

describe('TaxJurisdictionField — hidden for a provider-linked account', () => {
	it('`hidden` renders no combobox at all, not merely a styled-off one', () => {
		const { queryByRole, container } = render(TaxJurisdictionField, { props: { hidden: true } });
		expect(queryByRole('combobox')).toBeNull();
		expect(container.querySelector('select')).toBeNull();
	});

	it('the same fixture with `hidden` false renders it — proves the branch can go either way', () => {
		const { queryByRole } = render(TaxJurisdictionField, { props: { hidden: false } });
		expect(queryByRole('combobox')).toBeTruthy();
	});
});
