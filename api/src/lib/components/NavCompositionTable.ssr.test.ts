// NavCompositionTable.ssr.test.ts — render FOOTPRINT battery for the §2.1.5 composition table
// (SELF-226 · V1.1). Dep-free: server-side render via `svelte/server` (already-installed svelte 5)
// — NO jsdom / NO @testing-library, per vitest.config.ts (the gated DOM dep is not added).
//
// WHAT THIS COVERS (deterministic in SSR — the collapsed default state):
//   • 3 visual tiers (AC#4): .group-row (category) · tr.subtotal (buildup ladder) · tr.foot (NAV).
//   • Collapse DEFAULT COLLAPSED (AC#2): leaf account rows are ABSENT until expanded → the leaf
//     /accounts/[id] link + G/L cells are not in the initial output; the caret is the ▸ (closed)
//     glyph; every group toggle is a <button aria-expanded="false"> (keyboard-native disclosure).
//   • Buildup ladder EXACT order + labels (AC#4) + the Debt SUBTRACTION render (D5: −magnitude).
//   • Tax placeholders render `$0` + the V1.4 caption (AC#6 / D7).
//   • NAV foot renders whole-dollar, echoing the §2.1.1 headline (D9).
//   • Empty categories are absent upstream → a groups:[] tree still renders the ladder + NAV.
//
// COVERAGE BOUNDARY (flagged): the EXPANDED leaf DOM (click a group → account rows + /accounts/[id]
// links + G/L pos/neg classes) needs a DOM env (jsdom + @testing-library) — the gated dep-add per
// vitest.config.ts. The leaf-render logic (href shape, G/L `—`/color) is otherwise proven by the
// static markup here for the collapsed→open transition being a pure {#if}. buildupRows ordering /
// debt-sign / tax-flagging are proven dep-free in ../nav-composition.test.ts.

// @vitest-environment node
import { describe, it, expect } from 'vitest';
import { render } from 'svelte/server';
import NavCompositionTable from './NavCompositionTable.svelte';
import type { NavComposition } from '$lib/nav-composition';

const fixture: NavComposition = {
	groups: [
		{
			category: 'investment',
			subtotal: 500_000,
			accounts: [
				{ account_id: 1, account_name: 'Brokerage', current_market_value: 500_000, unrealized_gl: 42_000 }
			]
		},
		{
			category: 'liability',
			subtotal: -150_000, // natural-negative (D5)
			accounts: [
				{ account_id: 2, account_name: 'Mortgage', current_market_value: -150_000, unrealized_gl: null }
			]
		}
	],
	buildups: {
		total_non_re: 500_000,
		gross_total: 500_000,
		debt: 150_000, // positive magnitude (051 contract)
		realized_tax_liab: 0,
		unrealized_tax_liab: 0
	},
	nav: 350_000
};

describe('NavCompositionTable — 3 visual tiers (AC#4)', () => {
	it('renders category group-rows, buildup subtotals, and the NAV foot as distinct tiers', () => {
		const { body } = render(NavCompositionTable, { props: { composition: fixture } });
		// Svelte scopes component classes (e.g. `class="subtotal svelte-xxxx"`) → substring match.
		expect(body).toContain('group-head'); // tier 1 — category header
		expect(body).toContain('subtotal'); // tier 2 — buildup ladder
		expect(body).toContain('foot'); // tier 3 — NAV foot
	});
});

describe('NavCompositionTable — collapse default COLLAPSED (AC#2)', () => {
	it('every category is a keyboard-native <button aria-expanded="false"> disclosure', () => {
		const { body } = render(NavCompositionTable, { props: { composition: fixture } });
		expect(body).toContain('aria-expanded="false"');
		expect(body).toContain('▸'); // closed caret
		expect(body).not.toContain('▾'); // no open caret in the collapsed default
	});

	it('leaf account rows are ABSENT until expanded (no /accounts/[id] link in the initial render)', () => {
		const { body } = render(NavCompositionTable, { props: { composition: fixture } });
		expect(body).not.toContain('/accounts/1');
		expect(body).not.toContain('Brokerage');
	});

	it('renders the category display labels on the (collapsed) group headers', () => {
		const { body } = render(NavCompositionTable, { props: { composition: fixture } });
		expect(body).toContain('Investment');
		expect(body).toContain('Liability');
	});
});

describe('NavCompositionTable — buildup ladder (AC#4) + signs (D5) + tax placeholders (AC#6/D7)', () => {
	it('renders the ladder labels in the exact ratified order', () => {
		const { body } = render(NavCompositionTable, { props: { composition: fixture } });
		const order = ['Total Non-RE', 'Gross Total', 'Debt', 'Realized Tax Liab', 'Unrealized Tax Liab'];
		let cursor = -1;
		for (const label of order) {
			const at = body.indexOf(label);
			expect(at, `"${label}" present and after the previous label`).toBeGreaterThan(cursor);
			cursor = at;
		}
	});

	it('renders Debt as a SUBTRACTION (−$150,000) — the positive magnitude negated (D5)', () => {
		const { body } = render(NavCompositionTable, { props: { composition: fixture } });
		expect(body).toContain('-$150,000');
	});

	it('renders the two tax placeholders as $0 + the V1.4 caption (AC#6 / D7)', () => {
		const { body } = render(NavCompositionTable, { props: { composition: fixture } });
		expect(body).toContain('$0');
		expect(body).toContain('(from §2.5) · full estimate arrives in V1.4');
	});

	it('renders the NAV foot whole-dollar (echoes the §2.1.1 headline, D9)', () => {
		const { body } = render(NavCompositionTable, { props: { composition: fixture } });
		expect(body).toContain('Net Assets Value (NAV)');
		expect(body).toContain('$350,000');
	});
});

describe('NavCompositionTable — empty-groups tree (D3 empty categories omitted upstream)', () => {
	it('still renders the ladder + NAV when groups is empty (zero-account well-formed tree)', () => {
		const empty: NavComposition = {
			groups: [],
			buildups: { total_non_re: 0, gross_total: 0, debt: 0, realized_tax_liab: 0, unrealized_tax_liab: 0 },
			nav: 0
		};
		const { body } = render(NavCompositionTable, { props: { composition: empty } });
		expect(body).toContain('Net Assets Value (NAV)');
		expect(body).toContain('Total Non-RE');
		expect(body).not.toContain('group-head'); // no category headers
	});
});
