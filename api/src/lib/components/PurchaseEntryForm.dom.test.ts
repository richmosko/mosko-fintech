// PurchaseEntryForm.dom.test.ts — SELF-325 manual-purchase entry surface.
//
// Scope: rendering + client-side behavior that does not require an actual network round
// trip (Backend's `?/resolveAsset` / `?/createPurchase` actions were not yet authored as
// of this writing — see the component's own EXPECTED CONTRACT header note). Covers:
//   - the F/CTO-required explicit fork ("market security" vs "personal asset")
//   - the ticker-nudge (nudge, never block)
//   - the live per-unit price preview
//   - the BTO category readout (render-only, per the "Backend supplies it" brief)
//   - the raw DOM form data set for each mode (hidden mode/security_id carriers present)
//   - client-side validation blocking an invalid submit before any network call, using the
//     SAME real-user-interaction + real-<form>-submit pattern SymbolClassifyRow.dom.test.ts
//     established (no mocking of `$app/forms` needed — `use:enhance`'s synchronous callback
//     runs and can `cancel()` before any fetch is issued).
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, fireEvent } from '@testing-library/svelte';
import PurchaseEntryForm from './PurchaseEntryForm.svelte';
import type { SelectableAssetOption } from '$lib/purchase-util';

const ASSETS: SelectableAssetOption[] = [
	{
		asset_id: 10,
		asset_type: 'equity',
		symbol: 'AAPL',
		cusip: null,
		name: 'Apple Inc.',
		currency: 'USD',
		is_global: true
	},
	{
		asset_id: 20,
		asset_type: 'real_estate',
		symbol: null,
		cusip: null,
		name: 'My Rental',
		currency: 'USD',
		is_global: false
	}
];

describe('PurchaseEntryForm — fork toggle (F/CTO requirement: explicit market vs personal)', () => {
	it('defaults to the market-security fork, showing the existing-asset picker', () => {
		const { getByRole } = render(PurchaseEntryForm, { props: { selectableAssets: ASSETS } });
		expect(getByRole('combobox', { name: 'Security' })).toBeTruthy();
	});

	it('switching to "Personal asset" shows the mint fields and hides the security picker', async () => {
		const { getByRole, queryByRole, getByLabelText } = render(PurchaseEntryForm, {
			props: { selectableAssets: ASSETS }
		});
		await fireEvent.click(getByRole('radio', { name: 'Personal asset' }));
		expect(queryByRole('combobox', { name: 'Security' })).toBeNull();
		expect(getByLabelText('Name', { exact: false })).toBeTruthy();
		expect(getByRole('combobox', { name: 'Asset type' })).toBeTruthy();
	});

	it('the purchase form (quantity/cost/date) is visible immediately on the personal fork (no identify step)', async () => {
		const { getByRole, getByLabelText } = render(PurchaseEntryForm, {
			props: { selectableAssets: ASSETS }
		});
		await fireEvent.click(getByRole('radio', { name: 'Personal asset' }));
		expect(getByLabelText('Quantity', { exact: false })).toBeTruthy();
		expect(getByLabelText('Total cost', { exact: false })).toBeTruthy();
	});

	it('the purchase form is HIDDEN on the market fork until a security is bound', () => {
		const { queryByLabelText } = render(PurchaseEntryForm, { props: { selectableAssets: ASSETS } });
		expect(queryByLabelText('Quantity', { exact: false })).toBeNull();
	});

	it('picking an existing security reveals the purchase form and a "Buying: …" confirmation', async () => {
		const { getByRole, getByLabelText, getByText } = render(PurchaseEntryForm, {
			props: { selectableAssets: ASSETS }
		});
		const select = getByRole('combobox', { name: 'Security' }) as HTMLSelectElement;
		await fireEvent.change(select, { target: { value: '10' } });
		await fireEvent.click(getByRole('button', { name: 'Use this security' }));
		expect(getByText('AAPL — Apple Inc.')).toBeTruthy();
		expect(getByLabelText('Quantity', { exact: false })).toBeTruthy();
	});

	it('"Don\'t see it? Look up a ticker or CUSIP" reveals the resolve sub-form', async () => {
		const { getByRole, getByLabelText } = render(PurchaseEntryForm, {
			props: { selectableAssets: ASSETS }
		});
		await fireEvent.click(getByRole('button', { name: "Don't see it? Look up a ticker or CUSIP" }));
		expect(getByLabelText('Ticker symbol')).toBeTruthy();
		expect(getByLabelText('CUSIP')).toBeTruthy();
	});
});

describe('PurchaseEntryForm — ticker nudge (F/CTO ruling: nudge, never block)', () => {
	it('typing a ticker-shaped name into the personal-asset Name field shows the nudge', async () => {
		const { getByRole, getByLabelText, getByText } = render(PurchaseEntryForm, {
			props: { selectableAssets: ASSETS }
		});
		await fireEvent.click(getByRole('radio', { name: 'Personal asset' }));
		const name = getByLabelText('Name', { exact: false }) as HTMLInputElement;
		await fireEvent.input(name, { target: { value: 'AAPL' } });
		expect(getByText(/looks like a ticker symbol/)).toBeTruthy();
	});

	it('does not show the nudge for an ordinary personal-asset name', async () => {
		const { getByRole, getByLabelText, queryByText } = render(PurchaseEntryForm, {
			props: { selectableAssets: ASSETS }
		});
		await fireEvent.click(getByRole('radio', { name: 'Personal asset' }));
		const name = getByLabelText('Name', { exact: false }) as HTMLInputElement;
		await fireEvent.input(name, { target: { value: 'Acme Holdings LLC' } });
		expect(queryByText(/looks like a ticker symbol/)).toBeNull();
	});

	it('the nudge does NOT block submission — the field stays editable and valid', async () => {
		const { getByRole, getByLabelText } = render(PurchaseEntryForm, {
			props: { selectableAssets: ASSETS }
		});
		await fireEvent.click(getByRole('radio', { name: 'Personal asset' }));
		const name = getByLabelText('Name', { exact: false }) as HTMLInputElement;
		await fireEvent.input(name, { target: { value: 'AAPL' } });
		expect(name.disabled).toBe(false);
	});
});

describe('PurchaseEntryForm — live per-unit price preview (shared derivation, purchase-util.ts)', () => {
	it('shows the derived per-unit price once quantity and total cost are both entered', async () => {
		const { getByRole, getByLabelText, getByText } = render(PurchaseEntryForm, {
			props: { selectableAssets: ASSETS }
		});
		await fireEvent.click(getByRole('radio', { name: 'Personal asset' }));
		await fireEvent.input(getByLabelText('Quantity', { exact: false }), { target: { value: '10' } });
		await fireEvent.input(getByLabelText('Total cost', { exact: false }), { target: { value: '1000' } });
		expect(getByText('Per-unit price: 100.0000')).toBeTruthy();
	});

	it('shows nothing until both quantity and cost are present', async () => {
		const { getByRole, getByLabelText, queryByText } = render(PurchaseEntryForm, {
			props: { selectableAssets: ASSETS }
		});
		await fireEvent.click(getByRole('radio', { name: 'Personal asset' }));
		await fireEvent.input(getByLabelText('Quantity', { exact: false }), { target: { value: '10' } });
		expect(queryByText(/Per-unit price:/)).toBeNull();
	});
});

describe('PurchaseEntryForm — BTO category readout (render-only; Backend supplies the default)', () => {
	it('renders the supplied label read-only, no picker', async () => {
		const { getByRole, getByText, queryByRole } = render(PurchaseEntryForm, {
			props: { selectableAssets: ASSETS, defaultSubCatId: 5, defaultSubCatLabel: 'Buy to Open' }
		});
		await fireEvent.click(getByRole('radio', { name: 'Personal asset' }));
		expect(getByText('Buy to Open')).toBeTruthy();
		expect(queryByRole('combobox', { name: 'Category' })).toBeNull();
	});

	it('renders nothing when no default is supplied (null)', async () => {
		const { getByRole, queryByText } = render(PurchaseEntryForm, {
			props: { selectableAssets: ASSETS, defaultSubCatId: null, defaultSubCatLabel: null }
		});
		await fireEvent.click(getByRole('radio', { name: 'Personal asset' }));
		expect(queryByText(/Categorized as:/)).toBeNull();
	});
});

describe('PurchaseEntryForm — submit-level fence: raw DOM form data set carries mode + identity', () => {
	it('personal (mint) fork: the raw form posts mode=mint and no security_id control', async () => {
		const { getByRole, getByLabelText, container } = render(PurchaseEntryForm, {
			props: { selectableAssets: ASSETS }
		});
		await fireEvent.click(getByRole('radio', { name: 'Personal asset' }));
		await fireEvent.change(getByRole('combobox', { name: 'Asset type' }), {
			target: { value: 'real_estate' }
		});
		await fireEvent.input(getByLabelText('Name', { exact: false }), { target: { value: '123 Main St' } });

		const forms = container.querySelectorAll('form');
		const purchaseForm = forms[forms.length - 1] as HTMLFormElement;
		const posted = new FormData(purchaseForm);
		expect(posted.get('mode')).toBe('mint');
		expect(posted.has('security_id')).toBe(false);
		expect(posted.get('asset_name')).toBe('123 Main St');
	});

	it('market (bind) fork: once a security is bound, the raw form posts mode=bind and the bound security_id', async () => {
		const { getByRole, container } = render(PurchaseEntryForm, { props: { selectableAssets: ASSETS } });
		const select = getByRole('combobox', { name: 'Security' }) as HTMLSelectElement;
		await fireEvent.change(select, { target: { value: '10' } });
		await fireEvent.click(getByRole('button', { name: 'Use this security' }));

		const forms = container.querySelectorAll('form');
		const purchaseForm = forms[forms.length - 1] as HTMLFormElement;
		const posted = new FormData(purchaseForm);
		expect(posted.get('mode')).toBe('bind');
		expect(posted.get('security_id')).toBe('10');
	});
});

describe('PurchaseEntryForm — client validation blocks an invalid submit before any network call', () => {
	it('submitting the mint form with no asset_type/asset_name shows inline errors and does not throw', async () => {
		const { getByRole, getByLabelText, findByText } = render(PurchaseEntryForm, {
			props: { selectableAssets: ASSETS }
		});
		await fireEvent.click(getByRole('radio', { name: 'Personal asset' }));
		await fireEvent.input(getByLabelText('Quantity', { exact: false }), { target: { value: '10' } });
		await fireEvent.input(getByLabelText('Total cost', { exact: false }), { target: { value: '1000' } });
		await fireEvent.click(getByRole('button', { name: 'Record purchase' }));
		expect(await findByText('Name this asset.')).toBeTruthy();
	});

	it('submitting with a quantity/cost ratio that derives to 0.0000 is refused client-side with an explanatory message', async () => {
		const { getByRole, getByLabelText, findByText } = render(PurchaseEntryForm, {
			props: { selectableAssets: ASSETS }
		});
		await fireEvent.click(getByRole('radio', { name: 'Personal asset' }));
		await fireEvent.change(getByRole('combobox', { name: 'Asset type' }), {
			target: { value: 'real_estate' }
		});
		await fireEvent.input(getByLabelText('Name', { exact: false }), { target: { value: '123 Main St' } });
		await fireEvent.input(getByLabelText('Quantity', { exact: false }), { target: { value: '1000000' } });
		await fireEvent.input(getByLabelText('Total cost', { exact: false }), { target: { value: '10' } });
		await fireEvent.input(getByLabelText('Trade date', { exact: false }), { target: { value: '2026-08-21' } });
		await fireEvent.click(getByRole('button', { name: 'Record purchase' }));
		expect(await findByText(/per-unit price of 0.0000/)).toBeTruthy();
	});
});
