// PurchaseEntryForm.dom.test.ts — SELF-325 manual-purchase entry surface.
//
// Scope: rendering + client-side behavior, against the CONFIRMED contract (Backend,
// SendMessage 2026-08-21; asset-type vocabulary split per F/CTO+Architect, same date).
// Covers:
//   - the F/CTO-required explicit fork ("market security" vs "personal asset")
//   - the asset-type vocabulary split IS STRUCTURAL: the resolve picker never offers a
//     personal type; the mint picker offers the full superset
//   - the ticker-nudge (nudge, never block)
//   - the live per-unit price preview
//   - the BTO category readout (render-only, per the "Backend supplies it" brief)
//   - the resolve step's fetch call (mocked `fetch`) — success sets boundAssetId, a
//     `{assetId: null}` 200 and a non-ok response both surface a visible error
//   - the raw DOM form data set for the purchase form (hidden mode/security_id carriers
//     present — the resolve step is a plain fetch, not a form action, so it has no
//     equivalent raw-FormData assertion)
//   - client-side validation blocking an invalid submit before any network call, using the
//     SAME real-user-interaction + real-<form>-submit pattern SymbolClassifyRow.dom.test.ts
//     established (no mocking of `$app/forms` needed — `use:enhance`'s synchronous callback
//     runs and can `cancel()` before any fetch is issued).
//
// @vitest-environment jsdom

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
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

describe('PurchaseEntryForm — asset-type vocabulary split is STRUCTURAL (F/CTO+Architect ruling, 2026-08-21)', () => {
	it('the resolve step never offers a personal type (real_estate/vehicle/collectible/private) or currency as an <option>', async () => {
		const { getByRole } = render(PurchaseEntryForm, { props: { selectableAssets: ASSETS } });
		await fireEvent.click(getByRole('button', { name: "Don't see it? Look up a ticker or CUSIP" }));
		const select = getByRole('combobox', { name: 'Asset type' }) as HTMLSelectElement;
		const values = [...select.options].map((o) => o.value);
		expect(values).toEqual(
			expect.arrayContaining(['equity', 'etf', 'fund', 'money_market', 'bond', 'future', 'option', 'crypto', 'metal'])
		);
		for (const forbidden of ['real_estate', 'vehicle', 'collectible', 'private', 'currency']) {
			expect(values).not.toContain(forbidden);
		}
	});

	it('the personal-asset (mint) step DOES offer all 4 personal types (and the 9 resolvable ones), but never currency', async () => {
		const { getByRole } = render(PurchaseEntryForm, { props: { selectableAssets: ASSETS } });
		await fireEvent.click(getByRole('radio', { name: 'Personal asset' }));
		const select = getByRole('combobox', { name: 'Asset type' }) as HTMLSelectElement;
		const values = [...select.options].map((o) => o.value);
		for (const t of ['real_estate', 'vehicle', 'collectible', 'private', 'equity', 'crypto']) {
			expect(values).toContain(t);
		}
		expect(values).not.toContain('currency');
	});
});

describe('PurchaseEntryForm — resolve step calls POST /api/asset/resolve (fetch+JSON, not a form action)', () => {
	const originalFetch = globalThis.fetch;

	beforeEach(() => {
		globalThis.fetch = vi.fn();
	});
	afterEach(() => {
		globalThis.fetch = originalFetch;
		vi.restoreAllMocks();
	});

	it('a successful resolve POSTs the identified fields as JSON and binds the returned assetId', async () => {
		(globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
			ok: true,
			json: async () => ({ assetId: 77 })
		});
		const { getByRole, getByLabelText, getByText, findByText } = render(PurchaseEntryForm, {
			props: { selectableAssets: ASSETS }
		});
		await fireEvent.click(getByRole('button', { name: "Don't see it? Look up a ticker or CUSIP" }));
		await fireEvent.input(getByLabelText('Ticker symbol'), { target: { value: 'MSFT' } });
		await fireEvent.change(getByRole('combobox', { name: 'Asset type' }), { target: { value: 'equity' } });
		await fireEvent.click(getByRole('button', { name: 'Look up' }));

		expect(await findByText(/MSFT/)).toBeTruthy();
		expect(globalThis.fetch).toHaveBeenCalledWith(
			'/api/asset/resolve',
			expect.objectContaining({
				method: 'POST',
				headers: expect.objectContaining({ 'content-type': 'application/json' })
			})
		);
		const call = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0];
		const body = JSON.parse((call[1] as RequestInit).body as string);
		expect(body).toEqual({ symbol: 'MSFT', cusip: null, asset_type: 'equity', name: null });
		// Resolve succeeded -> the purchase form is now visible (identity settled).
		expect(getByText(/Quantity/)).toBeTruthy();
	});

	it('a 200 with assetId: null shows a visible error instead of silently binding nothing', async () => {
		(globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
			ok: true,
			json: async () => ({ assetId: null })
		});
		const { getByRole, getByLabelText, findByText } = render(PurchaseEntryForm, {
			props: { selectableAssets: ASSETS }
		});
		await fireEvent.click(getByRole('button', { name: "Don't see it? Look up a ticker or CUSIP" }));
		await fireEvent.input(getByLabelText('Ticker symbol'), { target: { value: 'ZZZZ' } });
		await fireEvent.change(getByRole('combobox', { name: 'Asset type' }), { target: { value: 'equity' } });
		await fireEvent.click(getByRole('button', { name: 'Look up' }));
		expect(await findByText(/Couldn't find or create a match/)).toBeTruthy();
	});

	it('a non-ok response with a field error surfaces it on the asset_type field', async () => {
		(globalThis.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
			ok: false,
			status: 400,
			json: async () => ({ error: 'invalid_request', errors: { asset_type: ['Choose an asset type.'] } })
		});
		const { getByRole, getByLabelText, findByText } = render(PurchaseEntryForm, {
			props: { selectableAssets: ASSETS }
		});
		await fireEvent.click(getByRole('button', { name: "Don't see it? Look up a ticker or CUSIP" }));
		await fireEvent.input(getByLabelText('Ticker symbol'), { target: { value: 'MSFT' } });
		await fireEvent.change(getByRole('combobox', { name: 'Asset type' }), { target: { value: 'equity' } });
		await fireEvent.click(getByRole('button', { name: 'Look up' }));
		expect(await findByText('Choose an asset type.')).toBeTruthy();
	});

	it('a network failure (fetch rejects) shows a visible error rather than throwing', async () => {
		(globalThis.fetch as ReturnType<typeof vi.fn>).mockRejectedValue(new Error('network down'));
		const { getByRole, getByLabelText, findByText } = render(PurchaseEntryForm, {
			props: { selectableAssets: ASSETS }
		});
		await fireEvent.click(getByRole('button', { name: "Don't see it? Look up a ticker or CUSIP" }));
		await fireEvent.input(getByLabelText('Ticker symbol'), { target: { value: 'MSFT' } });
		await fireEvent.change(getByRole('combobox', { name: 'Asset type' }), { target: { value: 'equity' } });
		await fireEvent.click(getByRole('button', { name: 'Look up' }));
		expect(await findByText(/Couldn't reach the server/)).toBeTruthy();
	});

	it('client-side validation (blank symbol AND cusip, valid asset_type) blocks the call before fetch is ever invoked', async () => {
		const { getByRole, findByText } = render(PurchaseEntryForm, { props: { selectableAssets: ASSETS } });
		await fireEvent.click(getByRole('button', { name: "Don't see it? Look up a ticker or CUSIP" }));
		// Asset type set to a valid value so ONLY the symbol/cusip refine trips — isolates the
		// assertion from the separate (also-real) empty-asset_type rejection.
		await fireEvent.change(getByRole('combobox', { name: 'Asset type' }), { target: { value: 'equity' } });
		await fireEvent.click(getByRole('button', { name: 'Look up' }));
		expect(await findByText('Enter a ticker symbol or a CUSIP.')).toBeTruthy();
		expect(globalThis.fetch).not.toHaveBeenCalled();
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
		expect(await findByText('Name is required.')).toBeTruthy();
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
