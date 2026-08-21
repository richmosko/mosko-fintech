// holdings-section.dom.test.ts — SELF-325 P-b Holdings section (UX ruling 2026-08-21).
//
// Scope: the new Holdings section's three states (empty, all-priced, mixed) and its
// always-present Status column header. Renders the full +page.svelte, following the
// us-equity-page.dom.test.ts precedent (the only prior +page.svelte DOM test in this repo) —
// same @testing-library/svelte render() pattern applied to a route component, not a new
// pattern. `data` satisfies the FULL merged PageData (this route's own load() fields + the
// root +layout.server.ts's userEmail/pendingClassificationCount/connectionHealth) — structural
// typing only, no import from $lib/server/**.
//
// ⚠ QUERIES ARE SCOPED TO THE Holdings <section> VIA `within`, not the whole page — with a
// non-provider-linked account (the fixture below), "Record a stock split" ALSO renders off the
// SAME `heldSecurities` array (its own picker `<option>`s), so an unscoped `getByText('AAPL — …')`
// against the full document finds it twice and throws. Scoping to the section under test is the
// correct fix, not renaming/uniquifying the fixture's labels to dodge the collision.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, within } from '@testing-library/svelte';
import AccountPage from './+page.svelte';

const LAYOUT_DEFAULTS = {
	userEmail: null,
	pendingClassificationCount: 0,
	connectionHealth: { reauthCount: 0, institutionDownCount: 0 }
};

const ACCOUNT = {
	account_id: 1,
	name: 'Brokerage',
	account_type: 'investment',
	scope: 'personal',
	tax_treatment: 'taxable',
	closed_at: null,
	linked_source_id: null,
	created_at: '2026-01-01T00:00:00Z'
};

function baseData(heldSecurities: Array<{
	security_id: number;
	symbol: string | null;
	name: string | null;
	quantity: number;
	priced: boolean;
}>) {
	return {
		...LAYOUT_DEFAULTS,
		account: ACCOUNT,
		transactions: [],
		cashflowSubCats: [],
		heldSecurities,
		dupCandidates: [],
		syncHistory: [],
		connection: null,
		selectableAssets: [],
		defaultSubCatId: null,
		defaultSubCatLabel: null
	};
}

function renderHoldings(heldSecurities: Parameters<typeof baseData>[0]) {
	const view = render(AccountPage, { props: { data: baseData(heldSecurities), form: null } });
	const section = view.getByRole('region', { name: 'Holdings' });
	return { ...view, section, within: within(section) };
}

describe('accounts/[account_id] — Holdings section (SELF-325 P-b)', () => {
	it('empty state: "No holdings in this account." — no table rendered', () => {
		const { within: w } = renderHoldings([]);
		expect(w.getByText('No holdings in this account.')).toBeTruthy();
		expect(w.queryByRole('columnheader', { name: 'Security' })).toBeNull();
	});

	it('all-priced: every row renders, Status header present, every Status cell BLANK (no chip)', () => {
		const { within: w } = renderHoldings([
			{ security_id: 10, symbol: 'AAPL', name: 'Apple Inc.', quantity: 5, priced: true },
			{ security_id: 20, symbol: 'MSFT', name: 'Microsoft', quantity: 2, priced: true }
		]);
		expect(w.getByRole('columnheader', { name: 'Status' })).toBeTruthy();
		expect(w.getByText('AAPL — Apple Inc.')).toBeTruthy();
		expect(w.getByText('MSFT — Microsoft')).toBeTruthy();
		// Zero-footprint: UnpricedMarker renders nothing for a priced holding.
		expect(w.queryByText('No price available')).toBeNull();
	});

	it('mixed: the marker renders ONLY on the unpriced row', () => {
		const { within: w } = renderHoldings([
			{ security_id: 10, symbol: 'AAPL', name: 'Apple Inc.', quantity: 5, priced: true },
			{ security_id: 30, symbol: null, name: 'My Rental', quantity: 1, priced: false }
		]);
		expect(w.getByText('AAPL — Apple Inc.')).toBeTruthy();
		expect(w.getByText('My Rental')).toBeTruthy();
		expect(w.getAllByText('No price available')).toHaveLength(1);
	});

	it('the Status column header renders even when every row is priced (empty cell, never a missing one)', () => {
		const { within: w } = renderHoldings([
			{ security_id: 10, symbol: 'AAPL', name: 'Apple Inc.', quantity: 5, priced: true }
		]);
		expect(w.getByRole('columnheader', { name: 'Status' })).toBeTruthy();
	});

	it('quantity renders in its own right-aligned column', () => {
		const { within: w } = renderHoldings([
			{ security_id: 10, symbol: 'AAPL', name: 'Apple Inc.', quantity: 5, priced: true }
		]);
		expect(w.getByRole('columnheader', { name: 'Quantity' })).toBeTruthy();
		expect(w.getByText('5')).toBeTruthy();
	});

	it('a provider-linked account (no stock-split section, so no picker collision) still renders Holdings correctly', () => {
		const view = render(AccountPage, {
			props: {
				data: {
					...baseData([{ security_id: 10, symbol: 'AAPL', name: 'Apple Inc.', quantity: 5, priced: false }]),
					account: { ...ACCOUNT, linked_source_id: 99 }
				},
				form: null
			}
		});
		const section = view.getByRole('region', { name: 'Holdings' });
		const w = within(section);
		expect(w.getByText('AAPL — Apple Inc.')).toBeTruthy();
		expect(w.getByText('No price available')).toBeTruthy();
	});
});
