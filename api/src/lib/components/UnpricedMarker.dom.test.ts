// UnpricedMarker.dom.test.ts — SELF-325 / 088 UNPRICED-BUT-LOUD posture (F/CTO + Architect
// HARD CONDITION: "if the loud state is descoped this becomes F3 shipped as a feature").
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/svelte';
import UnpricedMarker from './UnpricedMarker.svelte';

describe('UnpricedMarker — zero-footprint discipline (mirrors StaleConstituentBadge/InformationalMarkerBadge)', () => {
	it('renders nothing when priced is true', () => {
		const { container } = render(UnpricedMarker, { props: { priced: true } });
		expect(container.textContent?.trim()).toBe('');
	});

	it('renders nothing when priced is null (unknown is NOT the same as confirmed-unpriced)', () => {
		const { container } = render(UnpricedMarker, { props: { priced: null } });
		expect(container.textContent?.trim()).toBe('');
	});

	it('renders nothing when priced is undefined (a caller that forgot to pass it degrades to silent, not to a false alarm)', () => {
		const { container } = render(UnpricedMarker, { props: { priced: undefined } });
		expect(container.textContent?.trim()).toBe('');
	});
});

describe('UnpricedMarker — priced: false, context="confirmation" (purchase-result render)', () => {
	it('renders the full sentence, naming exclusion from net worth', () => {
		const { getByText, getByRole } = render(UnpricedMarker, {
			props: { priced: false, context: 'confirmation' }
		});
		expect(getByRole('status')).toBeTruthy();
		expect(getByText('No price available')).toBeTruthy();
		expect(getByText(/excluded from your net worth/)).toBeTruthy();
		// Architect's constraint: this is a rendering indicator, not a valuation primitive —
		// the marker must never assert the purchase itself failed.
		expect(getByText(/The purchase itself was recorded/)).toBeTruthy();
	});
});

describe('UnpricedMarker — priced: false, context="inline" (default; for a value-adjacent render)', () => {
	it('renders a compact tag with an accessible label, no long sentence', () => {
		const { getByRole, queryByText } = render(UnpricedMarker, { props: { priced: false } });
		const el = getByRole('status');
		expect(el.getAttribute('aria-label')).toMatch(/No price available/);
		expect(queryByText(/The purchase itself was recorded/)).toBeNull();
	});

	it('"inline" is the default context (no context prop passed)', () => {
		const { getByText } = render(UnpricedMarker, { props: { priced: false } });
		expect(getByText('No price available')).toBeTruthy();
	});
});
