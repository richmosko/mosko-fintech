// StaleConstituentBadge.dom.test.ts — QA disclosure-CONTENT battery (SELF-229 ramp).
//
// Closes the coverage boundary StaleConstituentBadge.ssr.test.ts's own header documents: SSR
// only ever renders the COLLAPSED state (`open` starts false via $state, and svelte/server has
// no click), so the account name + per-status affordance living inside the `{#if open}` panel
// were untested. That gap is exactly AC3's "tooltip lists stale account names + Re-authenticate
// link routes to the SELF-207 connection-state view" requirement for EVERY one of the four
// SELF-229 ramp surfaces (NavHistoryChart / NavDeltaPanel / NavReferenceDatesPanel /
// NavCompositionTable) — all four thread `staleness` straight through to THIS component
// unchanged (see f103586), so the disclosure content is proven ONCE here rather than duplicated
// 4x. Each surface's own SSR test already proves the wiring (isStale/staleItems reach the
// badge) — that division of labor is the judgment call flagged to Frontend.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, fireEvent, within } from '@testing-library/svelte';
import StaleConstituentBadge from './StaleConstituentBadge.svelte';
import type { StaleConstituentItem } from '$lib/staleness/stale-constituent';

const item = (overrides: Partial<StaleConstituentItem> & { linked_source_id: number }): StaleConstituentItem => ({
	institution_name: `Bank ${overrides.linked_source_id}`,
	provider: 'plaid',
	connection_status: 'login_required',
	status_class: null,
	...overrides
});

describe('StaleConstituentBadge — disclosure open reveals account names + per-status affordance (AC3)', () => {
	it('a REAUTH-set item (login_required): institution name + "Re-authenticate" link to /accounts/connections', async () => {
		const { getByRole, findByText, findByRole } = render(StaleConstituentBadge, {
			props: { isStale: true, staleItems: [item({ linked_source_id: 1, connection_status: 'login_required' })] }
		});
		await fireEvent.click(getByRole('button', { name: /May be stale/ }));
		await findByText('Bank 1');
		const link = await findByRole('link', { name: 'Re-authenticate' });
		expect(link.getAttribute('href')).toBe('/accounts/connections');
	});

	it('every REAUTH status (login_required / revoked / disconnected) gets the Re-authenticate link', async () => {
		const items = [
			item({ linked_source_id: 1, connection_status: 'login_required' }),
			item({ linked_source_id: 2, connection_status: 'revoked' }),
			item({ linked_source_id: 3, connection_status: 'disconnected' })
		];
		const { getByRole, findAllByRole } = render(StaleConstituentBadge, {
			props: { isStale: true, staleItems: items }
		});
		await fireEvent.click(getByRole('button', { name: /May be stale/ }));
		const links = await findAllByRole('link', { name: 'Re-authenticate' });
		expect(links).toHaveLength(3);
	});

	it('an institution_down item: institution name + informational text, NO Re-authenticate link on its row (re-auth cannot fix a provider outage)', async () => {
		const { getByRole, findByText } = render(StaleConstituentBadge, {
			props: { isStale: true, staleItems: [item({ linked_source_id: 2, connection_status: 'institution_down' })] }
		});
		await fireEvent.click(getByRole('button', { name: /May be stale/ }));
		const name = await findByText('Bank 2');
		const row = name.closest('li')!;
		expect(within(row).getByText('temporarily unavailable')).toBeTruthy();
		expect(within(row).queryByRole('link', { name: 'Re-authenticate' })).toBeNull();
	});

	it('"Review connections" summary link is present when ANY item is reauth-actionable', async () => {
		const { getByRole, findByRole } = render(StaleConstituentBadge, {
			props: {
				isStale: true,
				staleItems: [
					item({ linked_source_id: 1, connection_status: 'institution_down' }),
					item({ linked_source_id: 2, connection_status: 'login_required' })
				]
			}
		});
		await fireEvent.click(getByRole('button', { name: /May be stale/ }));
		const reviewLink = await findByRole('link', { name: 'Review connections' });
		expect(reviewLink.getAttribute('href')).toBe('/accounts/connections');
	});

	it('"Review connections" summary link is ABSENT when every item is institution_down (nothing re-auth-actionable)', async () => {
		const { getByRole, findByText, queryByRole } = render(StaleConstituentBadge, {
			props: { isStale: true, staleItems: [item({ linked_source_id: 1, connection_status: 'institution_down' })] }
		});
		await fireEvent.click(getByRole('button', { name: /May be stale/ }));
		await findByText('Bank 1');
		expect(queryByRole('link', { name: 'Review connections' })).toBeNull();
	});

	it('a custom reviewHref propagates to BOTH the per-item Re-authenticate link and the summary Review-connections link', async () => {
		const { getByRole, findAllByRole, findByRole } = render(StaleConstituentBadge, {
			props: {
				isStale: true,
				staleItems: [item({ linked_source_id: 1, connection_status: 'login_required' })],
				reviewHref: '/custom/connections'
			}
		});
		await fireEvent.click(getByRole('button', { name: /May be stale/ }));
		const [itemLink] = await findAllByRole('link', { name: 'Re-authenticate' });
		expect(itemLink.getAttribute('href')).toBe('/custom/connections');
		const summaryLink = await findByRole('link', { name: 'Review connections' });
		expect(summaryLink.getAttribute('href')).toBe('/custom/connections');
	});
});

describe('StaleConstituentBadge — keyboard disclosure a11y + re-collapse', () => {
	it('starts collapsed (aria-expanded="false"); toggling flips it and back', async () => {
		const { getByRole, queryByText, findByText } = render(StaleConstituentBadge, {
			props: { isStale: true, staleItems: [item({ linked_source_id: 1 })] }
		});
		const toggle = getByRole('button', { name: /May be stale/ });
		expect(toggle.getAttribute('aria-expanded')).toBe('false');
		expect(queryByText('Bank 1')).toBeNull();

		await fireEvent.click(toggle);
		expect(toggle.getAttribute('aria-expanded')).toBe('true');
		await findByText('Bank 1');

		await fireEvent.click(toggle);
		expect(toggle.getAttribute('aria-expanded')).toBe('false');
		expect(queryByText('Bank 1')).toBeNull();
	});

	it('the toggle is a native <button> with aria-controls pointing at the disclosed region', () => {
		const { getByRole } = render(StaleConstituentBadge, {
			props: { isStale: true, staleItems: [item({ linked_source_id: 1 })] }
		});
		const toggle = getByRole('button', { name: /May be stale/ });
		expect(toggle.tagName).toBe('BUTTON');
		expect(toggle.getAttribute('aria-controls')).toBe('stale-constituent-list');
	});
});
