// NavCompositionTable.dom.test.ts — EXPANDED-leaf interaction battery (SELF-226 · V1.1).
// QA-authored durable closure for the coverage gap the SSR battery leaves open: the SSR
// (svelte/server) tests prove only the COLLAPSED default; this proves the EXPANDED path
// (click a category → leaf rows) + the a11y disclosure toggle + the pos/neg value-color FENCE.
//
// ENV: jsdom (per-file pragma below) + @testing-library/svelte — devDeps approved (team-lead +
// F/CTO, Option A). The per-file `// @vitest-environment jsdom` keeps every other test on the
// default node env (vitest.config.ts) so this is the ONLY DOM-env file; no global config change.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, fireEvent, within } from '@testing-library/svelte';
import NavCompositionTable from './NavCompositionTable.svelte';
import type { NavComposition } from '$lib/nav-composition';

// Fixture deliberately carries what the F/CTO's live local data lacks: an INVESTMENT group with a
// signed-POSITIVE and a signed-NEGATIVE unrealized_gl leaf, plus a liability leaf with NULL G/L
// (→ '—'). That makes the pos/neg color fence + the null path observable deterministically.
const fixture: NavComposition = {
	groups: [
		{
			category: 'investment',
			subtotal: 500_000,
			accounts: [
				{ account_id: 1, account_name: 'Brokerage', current_market_value: 500_000, unrealized_gl: 42_000 },
				{ account_id: 7, account_name: 'Old IRA', current_market_value: 90_000, unrealized_gl: -3_500 }
			]
		},
		{
			category: 'liability',
			subtotal: -150_000,
			accounts: [
				{ account_id: 2, account_name: 'Mortgage', current_market_value: -150_000, unrealized_gl: null }
			]
		}
	],
	buildups: { total_non_re: 500_000, gross_total: 500_000, debt: 150_000, realized_tax_liab: 0, unrealized_tax_liab: 0 },
	nav: 350_000
};

describe('NavCompositionTable — expanded-leaf interaction (AC#2/AC#3)', () => {
	it('collapsed default: leaf rows absent, every toggle aria-expanded="false"', () => {
		const { queryByText, getAllByRole } = render(NavCompositionTable, { props: { composition: fixture } });
		expect(queryByText('Brokerage')).toBeNull();
		for (const btn of getAllByRole('button')) {
			expect(btn.getAttribute('aria-expanded')).toBe('false');
		}
	});

	it('click a category → leaf rows appear; aria-expanded flips to "true"', async () => {
		const { getByRole, findByText } = render(NavCompositionTable, { props: { composition: fixture } });
		const toggle = getByRole('button', { name: /Investment/i });
		await fireEvent.click(toggle);
		expect(toggle.getAttribute('aria-expanded')).toBe('true');
		await findByText('Brokerage');
		await findByText('Old IRA');
	});

	it('leaf account-name links to /accounts/[account_id]', async () => {
		const { getByRole, findByRole } = render(NavCompositionTable, { props: { composition: fixture } });
		await fireEvent.click(getByRole('button', { name: /Investment/i }));
		const link = await findByRole('link', { name: 'Brokerage' });
		expect(link.getAttribute('href')).toBe('/accounts/1');
	});

	it('NULL unrealized_gl renders as "—" (em dash), never $0/blank', async () => {
		const { getByRole, findByText } = render(NavCompositionTable, { props: { composition: fixture } });
		await fireEvent.click(getByRole('button', { name: /Liability/i }));
		const mortgage = await findByText('Mortgage');
		const row = mortgage.closest('tr')!;
		expect(within(row).getByText('—')).toBeTruthy();
	});
});

describe('NavCompositionTable — value-color FENCE (§5 fence 1: G/L column ONLY)', () => {
	it('positive G/L → .pos on the G/L cell; current-value cell stays NEUTRAL', async () => {
		const { getByRole, findByText } = render(NavCompositionTable, { props: { composition: fixture } });
		await fireEvent.click(getByRole('button', { name: /Investment/i }));
		const row = (await findByText('Brokerage')).closest('tr')!;
		const cells = within(row).getAllByRole('cell'); // [current-value, G/L]
		const glCell = cells[cells.length - 1];
		expect(glCell.classList.contains('gl')).toBe(true);
		expect(glCell.classList.contains('pos')).toBe(true);
		expect(glCell.classList.contains('neg')).toBe(false);
		// FENCE: the current-market-value cell must NOT carry pos/neg (position, not performance).
		const valueCell = cells[0];
		expect(valueCell.classList.contains('pos')).toBe(false);
		expect(valueCell.classList.contains('neg')).toBe(false);
	});

	it('negative G/L → .neg on the G/L cell (and not .pos)', async () => {
		const { getByRole, findByText } = render(NavCompositionTable, { props: { composition: fixture } });
		await fireEvent.click(getByRole('button', { name: /Investment/i }));
		const row = (await findByText('Old IRA')).closest('tr')!;
		const glCell = within(row).getAllByRole('cell').slice(-1)[0];
		expect(glCell.classList.contains('neg')).toBe(true);
		expect(glCell.classList.contains('pos')).toBe(false);
	});

	it('NULL G/L cell carries NEITHER pos NOR neg (— is not a performance value)', async () => {
		const { getByRole, findByText } = render(NavCompositionTable, { props: { composition: fixture } });
		await fireEvent.click(getByRole('button', { name: /Liability/i }));
		const row = (await findByText('Mortgage')).closest('tr')!;
		const glCell = within(row).getAllByRole('cell').slice(-1)[0];
		expect(glCell.classList.contains('pos')).toBe(false);
		expect(glCell.classList.contains('neg')).toBe(false);
	});
});

describe('NavCompositionTable — keyboard / disclosure a11y', () => {
	it('re-clicking collapses (aria-expanded back to "false", leaf rows removed)', async () => {
		const { getByRole, queryByText, findByText } = render(NavCompositionTable, { props: { composition: fixture } });
		const toggle = getByRole('button', { name: /Investment/i });
		await fireEvent.click(toggle);
		await findByText('Brokerage');
		await fireEvent.click(toggle);
		expect(toggle.getAttribute('aria-expanded')).toBe('false');
		expect(queryByText('Brokerage')).toBeNull();
	});

	it('toggle is keyboard-operable: a native <button> (Enter/Space fire onclick) w/ aria-controls', () => {
		const { getByRole } = render(NavCompositionTable, { props: { composition: fixture } });
		const toggle = getByRole('button', { name: /Investment/i });
		expect(toggle.tagName).toBe('BUTTON');
		expect(toggle.getAttribute('type')).toBe('button');
		// aria-controls points at the group tbody so AT announces the controlled region.
		expect(toggle.getAttribute('aria-controls')).toBe('comp-grp-investment');
	});
});
