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
import { EMPTY_STALENESS } from '$lib/staleness/stale-constituent';
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
				{ account_id: 1, account_name: 'Brokerage', current_market_value: 500_000, unrealized_gl: 42_000, is_stale: false },
				{ account_id: 7, account_name: 'Old IRA', current_market_value: 90_000, unrealized_gl: -3_500, is_stale: false }
			]
		},
		{
			category: 'liability',
			subtotal: -150_000,
			accounts: [
				{ account_id: 2, account_name: 'Mortgage', current_market_value: -150_000, unrealized_gl: null, is_stale: false }
			]
		}
	],
	buildups: { total_non_re: 500_000, gross_total: 500_000, debt: 150_000, realized_tax_liab: { status: 'computed', amount: 0 }, unrealized_tax_liab: { status: 'computed', amount: 0 } },
	nav: 350_000
};

describe('NavCompositionTable — expanded-leaf interaction (AC#2/AC#3)', () => {
	it('collapsed default: leaf rows absent, every toggle aria-expanded="false"', () => {
		const { queryByText, getAllByRole } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(queryByText('Brokerage')).toBeNull();
		for (const btn of getAllByRole('button')) {
			expect(btn.getAttribute('aria-expanded')).toBe('false');
		}
	});

	it('click a category → leaf rows appear; aria-expanded flips to "true"', async () => {
		const { getByRole, findByText } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		const toggle = getByRole('button', { name: /Investment/i });
		await fireEvent.click(toggle);
		expect(toggle.getAttribute('aria-expanded')).toBe('true');
		await findByText('Brokerage');
		await findByText('Old IRA');
	});

	it('leaf account-name links to /accounts/[account_id]', async () => {
		const { getByRole, findByRole } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		await fireEvent.click(getByRole('button', { name: /Investment/i }));
		const link = await findByRole('link', { name: 'Brokerage' });
		expect(link.getAttribute('href')).toBe('/accounts/1');
	});

	it('NULL unrealized_gl renders as "—" (em dash), never $0/blank', async () => {
		const { getByRole, findByText } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		await fireEvent.click(getByRole('button', { name: /Liability/i }));
		const mortgage = await findByText('Mortgage');
		const row = mortgage.closest('tr')!;
		expect(within(row).getByText('—')).toBeTruthy();
	});
});

describe('NavCompositionTable — value-color FENCE (§5 fence 1: G/L column ONLY)', () => {
	it('positive G/L → .pos on the G/L cell; current-value cell stays NEUTRAL', async () => {
		const { getByRole, findByText } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
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
		const { getByRole, findByText } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		await fireEvent.click(getByRole('button', { name: /Investment/i }));
		const row = (await findByText('Old IRA')).closest('tr')!;
		const glCell = within(row).getAllByRole('cell').slice(-1)[0];
		expect(glCell.classList.contains('neg')).toBe(true);
		expect(glCell.classList.contains('pos')).toBe(false);
	});

	it('NULL G/L cell carries NEITHER pos NOR neg (— is not a performance value)', async () => {
		const { getByRole, findByText } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		await fireEvent.click(getByRole('button', { name: /Liability/i }));
		const row = (await findByText('Mortgage')).closest('tr')!;
		const glCell = within(row).getAllByRole('cell').slice(-1)[0];
		expect(glCell.classList.contains('pos')).toBe(false);
		expect(glCell.classList.contains('neg')).toBe(false);
	});
});

describe('NavCompositionTable — keyboard / disclosure a11y', () => {
	it('re-clicking collapses (aria-expanded back to "false", leaf rows removed)', async () => {
		const { getByRole, queryByText, findByText } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		const toggle = getByRole('button', { name: /Investment/i });
		await fireEvent.click(toggle);
		await findByText('Brokerage');
		await fireEvent.click(toggle);
		expect(toggle.getAttribute('aria-expanded')).toBe('false');
		expect(queryByText('Brokerage')).toBeNull();
	});

	it('toggle is keyboard-operable: a native <button> (Enter/Space fire onclick) w/ aria-controls', () => {
		const { getByRole } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		const toggle = getByRole('button', { name: /Investment/i });
		expect(toggle.tagName).toBe('BUTTON');
		expect(toggle.getAttribute('type')).toBe('button');
		// aria-controls points at the group tbody so AT announces the controlled region.
		expect(toggle.getAttribute('aria-controls')).toBe('comp-grp-investment');
	});
});

describe('NavCompositionTable — SELF-229 AC#2 per-leaf staleness (TRI-STATE, never merged)', () => {
	function triStateFixture(is_stale: boolean | null): NavComposition {
		return {
			groups: [
				{
					category: 'investment',
					subtotal: 500_000,
					accounts: [
						{ account_id: 1, account_name: 'Brokerage', current_market_value: 500_000, unrealized_gl: 42_000, is_stale }
					]
				}
			],
			buildups: { total_non_re: 500_000, gross_total: 500_000, debt: 0, realized_tax_liab: { status: 'computed', amount: 0 }, unrealized_tax_liab: { status: 'computed', amount: 0 } },
			nav: 500_000
		};
	}

	it('is_stale === true → "May be stale" tag renders beside the leaf link, no "unknown" text', async () => {
		const { getByRole, findByText, queryByText } = render(NavCompositionTable, {
			props: { staleness: EMPTY_STALENESS, composition: triStateFixture(true) }
		});
		await fireEvent.click(getByRole('button', { name: /Investment/i }));
		await findByText('Brokerage');
		expect(await findByText('May be stale')).toBeTruthy();
		expect(queryByText('Staleness unknown')).toBeNull();
	});

	it('is_stale === null (UNKNOWN — join failed) → "Staleness unknown" renders, DISTINCT from "May be stale"', async () => {
		const { getByRole, findByText, queryByText } = render(NavCompositionTable, {
			props: { staleness: EMPTY_STALENESS, composition: triStateFixture(null) }
		});
		await fireEvent.click(getByRole('button', { name: /Investment/i }));
		await findByText('Brokerage');
		expect(await findByText('Staleness unknown')).toBeTruthy();
		// UNKNOWN must never render as, or alongside, the confirmed-stale tag.
		expect(queryByText('May be stale')).toBeNull();
	});

	it('is_stale === false (confirmed not stale) → neither marker renders', async () => {
		const { getByRole, findByText, queryByText } = render(NavCompositionTable, {
			props: { staleness: EMPTY_STALENESS, composition: triStateFixture(false) }
		});
		await fireEvent.click(getByRole('button', { name: /Investment/i }));
		await findByText('Brokerage');
		expect(queryByText('May be stale')).toBeNull();
		expect(queryByText('Staleness unknown')).toBeNull();
	});
});

// ============================================================================
// SELF-229-QA — brief AC4: "a stale leaf shows BOTH the per-row indicator AND the
// aggregation-level badge — assert both, and assert a non-stale leaf next to a stale one shows
// neither per-row marking." The tri-state block above proves each per-row state in isolation
// (single-leaf fixtures, aggregation `staleness` confirmed healthy / EMPTY_STALENESS); this block
// proves the TWO-LEVEL signal — per-row AND aggregation — together, and proves a MIXED group
// (one stale leaf beside a confirmed-not-stale one) marks only the actually-stale row.
// ============================================================================

describe('NavCompositionTable — SELF-229 AC4: per-row marker AND aggregation badge coexist; a mixed group marks only the stale leaf', () => {
	const MIXED: NavComposition = {
		groups: [
			{
				category: 'investment',
				subtotal: 590_000,
				accounts: [
					{ account_id: 1, account_name: 'Brokerage', current_market_value: 500_000, unrealized_gl: 42_000, is_stale: true },
					{ account_id: 7, account_name: 'Old IRA', current_market_value: 90_000, unrealized_gl: -3_500, is_stale: false }
				]
			}
		],
		buildups: { total_non_re: 590_000, gross_total: 590_000, debt: 0, realized_tax_liab: { status: 'computed', amount: 0 }, unrealized_tax_liab: { status: 'computed', amount: 0 } },
		nav: 590_000
	};

	it('a stale leaf shows the per-row tag AND the aggregation badge is present at the same time', async () => {
		const { container, getByRole, findByText } = render(NavCompositionTable, {
			props: {
				composition: MIXED,
				staleness: {
					is_stale: true,
					stale_items: [
						{ linked_source_id: '1', institution_name: 'Bank 1', provider: 'plaid', connection_status: 'login_required', status_class: null }
					]
				}
			}
		});
		// Aggregation-level badge (section heading).
		expect(container.querySelector('.stale-connection-marker')).not.toBeNull();
		// Per-row leaf marker.
		await fireEvent.click(getByRole('button', { name: /Investment/i }));
		const staleRow = (await findByText('Brokerage')).closest('tr')!;
		expect(within(staleRow).getByText('May be stale')).toBeTruthy();
	});

	it('in the SAME mixed group, the non-stale leaf beside the stale one shows NEITHER per-row marker', async () => {
		const { getByRole, findByText, getAllByText } = render(NavCompositionTable, {
			props: {
				composition: MIXED,
				staleness: {
					is_stale: true,
					stale_items: [
						{ linked_source_id: '1', institution_name: 'Bank 1', provider: 'plaid', connection_status: 'login_required', status_class: null }
					]
				}
			}
		});
		await fireEvent.click(getByRole('button', { name: /Investment/i }));
		const healthyRow = (await findByText('Old IRA')).closest('tr')!;
		expect(within(healthyRow).queryByText('May be stale')).toBeNull();
		expect(within(healthyRow).queryByText('Staleness unknown')).toBeNull();
		// The stale sibling's own tag is unaffected — this isn't just an "always absent" bug. TWO
		// "May be stale" occurrences are expected on this fixture (the aggregation badge's tag +
		// Brokerage's own leaf flag), so this asserts the COUNT rather than using a single-match
		// query, which would throw AmbiguousElementError on this exact page.
		expect(getAllByText('May be stale')).toHaveLength(2);
	});
});

// ============================================================================
// SELF-229-QA — wiring fidelity + signal-distinctness. Disclosure CONTENT for the aggregation
// badge (account names, Re-authenticate link) is proven once, generically, in
// StaleConstituentBadge.dom.test.ts since all four ramp surfaces pass the identical props
// through unchanged. This block covers what's specific to THIS surface: the actual staleItems
// array reaching the aggregation badge, and the aggregation badge staying structurally distinct
// from the Unrealized-G/L value-color fence (`.gl.pos` / `.gl.neg`) proven above — two unrelated
// signal families (connection health vs. investment performance) that must never share a
// selector or a hue.
// ============================================================================

describe('NavCompositionTable — SELF-229 wiring fidelity: the ACTUAL staleItems array reaches the aggregation badge', () => {
	it('a two-item staleItems array yields the PLURAL summary, not a single-item count', () => {
		const { getByRole } = render(NavCompositionTable, {
			props: {
				composition: fixture,
				staleness: {
					is_stale: true,
					stale_items: [
						{ linked_source_id: '1', institution_name: 'Bank 1', provider: 'plaid', connection_status: 'login_required', status_class: null },
						{ linked_source_id: '2', institution_name: 'Bank 2', provider: 'plaid', connection_status: 'login_required', status_class: null }
					]
				}
			}
		});
		expect(getByRole('group', { name: '2 accounts are contributing possibly-stale data to this total.' })).toBeTruthy();
	});
});

describe('NavCompositionTable — aggregation badge (canary, connection health) never shares a selector with the Unrealized-G/L value-color fence (investment performance)', () => {
	it('aggregation badge stale + a positive G/L leaf BOTH present: the badge carries no .pos/.neg, the G/L cell carries no D1 classes', async () => {
		const { container, getByRole, findByText } = render(NavCompositionTable, {
			props: {
				composition: fixture,
				staleness: {
					is_stale: true,
					stale_items: [
						{ linked_source_id: '1', institution_name: 'Bank 1', provider: 'plaid', connection_status: 'login_required', status_class: null }
					]
				}
			}
		});
		const badge = container.querySelector('.stale-connection-marker')!;
		expect(badge).not.toBeNull();
		expect(badge.classList.contains('pos')).toBe(false);
		expect(badge.classList.contains('neg')).toBe(false);

		await fireEvent.click(getByRole('button', { name: /Investment/i }));
		const row = (await findByText('Brokerage')).closest('tr')!;
		const glCell = within(row).getAllByRole('cell').slice(-1)[0];
		expect(glCell.classList.contains('stale-connection-marker')).toBe(false);
	});

	it('aggregation badge healthy (staleness omitted): no badge renders at all, the G/L fence is unaffected', async () => {
		const { container, getByRole, findByText } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(container.querySelector('.stale-connection-marker')).toBeNull();
		await fireEvent.click(getByRole('button', { name: /Investment/i }));
		const row = (await findByText('Brokerage')).closest('tr')!;
		const glCell = within(row).getAllByRole('cell').slice(-1)[0];
		expect(glCell.classList.contains('pos')).toBe(true);
	});
});

// ============================================================================
// F/CTO ruling (a), FINAL BATTERY PASS (team-lead, post-442dac8): the badge's own tri-state
// distinguishability is proven exhaustively at the shared-component level
// (StaleConstituentBadge.ssr.test.ts), and the PER-LEAF tri-state is proven by the "SELF-229
// AC#2 per-leaf staleness (TRI-STATE, never merged)" describe block above. What was NOT proven
// anywhere: that the AGGREGATION-level `staleness.is_stale === null` (a DIFFERENT signal from any
// per-leaf null — this is the rollup badge fed by `data.staleness` directly, not a leaf's own
// `is_stale`) actually reaches this surface's mount and renders. Closing that gap.
// ============================================================================

describe('NavCompositionTable — SELF-229 tri-state wiring: the AGGREGATION badge\'s staleness.is_stale === null reaches this surface', () => {
	it('aggregation is_stale === null renders "Staleness unknown" beside the heading, distinct from "May be stale"', () => {
		const { getByText, queryByText } = render(NavCompositionTable, {
			props: { composition: fixture, staleness: { is_stale: null, stale_items: [] } }
		});
		expect(getByText('Staleness unknown')).toBeTruthy();
		expect(queryByText('May be stale')).toBeNull();
	});

	it('aggregation is_stale === false (confirmed healthy) stays zero-footprint — never confused with the unknown case above', () => {
		const { queryByText } = render(NavCompositionTable, {
			props: { composition: fixture, staleness: { is_stale: false, stale_items: [] } }
		});
		expect(queryByText('Staleness unknown')).toBeNull();
		expect(queryByText('May be stale')).toBeNull();
	});

	it('aggregation is_stale === null does NOT imply any leaf\'s own per-leaf is_stale is null — the two are independent signals, unaffected by each other', async () => {
		// fixture's leaves are all is_stale: false (confirmed not stale per-leaf), while the
		// AGGREGATION badge is unknown — proves the rollup and the per-row detail are fed by
		// genuinely separate values, not one derived from the other.
		const { getByRole, getByText, findByText, queryByText } = render(NavCompositionTable, {
			props: { composition: fixture, staleness: { is_stale: null, stale_items: [] } }
		});
		expect(getByText('Staleness unknown')).toBeTruthy();
		await fireEvent.click(getByRole('button', { name: /Investment/i }));
		const row = (await findByText('Brokerage')).closest('tr')!;
		// The leaf itself is confirmed false (fixture's own value) — no per-row marker of any kind.
		expect(within(row).queryByText('May be stale')).toBeNull();
		expect(within(row).queryByText('Staleness unknown')).toBeNull();
	});
});
