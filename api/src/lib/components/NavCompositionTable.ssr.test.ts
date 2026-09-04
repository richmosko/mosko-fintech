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
//   • SELF-268 V1.4 flip: the two tax rows render their REAL, UNFLIPPED positive values (AC 7 /
//     M-3 / AC 10) — the V1.1 `isTaxPlaceholder` `$0` + "V1.4 ramp" caption shape is GONE.
//   • SELF-268 AC 9a: the §2.5.4 disclaimer renders as a visible footnote (no hover-only).
//   • SELF-268 AC 6 / AC 10a (EXPECTED CONTRACT, provisional — see $lib/nav-composition.ts):
//     `tax_components` unavailable rendering and `excluded_tax_ledgers` rendering, each proven
//     present AND absent (graceful no-op when 105 hasn't landed the field yet).
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
import { EMPTY_STALENESS } from '$lib/staleness/stale-constituent';
import type { StaleConstituentItem } from '$lib/staleness/stale-constituent';

const fixture: NavComposition = {
	groups: [
		{
			category: 'investment',
			subtotal: 500_000,
			accounts: [
				{ account_id: 1, account_name: 'Brokerage', current_market_value: 500_000, unrealized_gl: 42_000, is_stale: false }
			]
		},
		{
			category: 'liability',
			subtotal: -150_000, // natural-negative (D5)
			accounts: [
				{ account_id: 2, account_name: 'Mortgage', current_market_value: -150_000, unrealized_gl: null, is_stale: false }
			]
		}
	],
	buildups: {
		total_non_re: 500_000,
		gross_total: 500_000,
		debt: 150_000, // positive magnitude (051 contract)
		realized_tax_liab: 4_200, // SELF-268: real value, positive magnitude (AC 7 / M-3)
		unrealized_tax_liab: 1_800 // SELF-268: real value, positive magnitude (AC 7 / M-3)
	},
	nav: 350_000
};

describe('NavCompositionTable — 3 visual tiers (AC#4)', () => {
	it('renders category group-rows, buildup subtotals, and the NAV foot as distinct tiers', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		// Svelte scopes component classes (e.g. `class="subtotal svelte-xxxx"`) → substring match.
		expect(body).toContain('group-head'); // tier 1 — category header
		expect(body).toContain('subtotal'); // tier 2 — buildup ladder
		expect(body).toContain('foot'); // tier 3 — NAV foot
	});
});

describe('NavCompositionTable — collapse default COLLAPSED (AC#2)', () => {
	it('every category is a keyboard-native <button aria-expanded="false"> disclosure', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).toContain('aria-expanded="false"');
		expect(body).toContain('▸'); // closed caret
		expect(body).not.toContain('▾'); // no open caret in the collapsed default
	});

	it('leaf account rows are ABSENT until expanded (no /accounts/[id] link in the initial render)', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).not.toContain('/accounts/1');
		expect(body).not.toContain('Brokerage');
	});

	it('renders the category display labels on the (collapsed) group headers', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).toContain('Investment');
		expect(body).toContain('Liability');
	});
});

describe('NavCompositionTable — buildup ladder (AC#4) + signs (D5) + SELF-268 real tax values (AC 7 / AC 10)', () => {
	it('renders the ladder labels in the exact ratified order', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		const order = ['Total Non-RE', 'Gross Total', 'Debt', 'Realized Tax Liab', 'Unrealized Tax Liab'];
		let cursor = -1;
		for (const label of order) {
			const at = body.indexOf(label);
			expect(at, `"${label}" present and after the previous label`).toBeGreaterThan(cursor);
			cursor = at;
		}
	});

	it('renders Debt as a SUBTRACTION (−$150,000) — the positive magnitude negated (D5)', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).toContain('-$150,000');
	});

	it('AC 10 — a NON-ZERO helper value reaches the rendered cell (asserts the number, not the absence of "$0")', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).toContain('$4,200');
		expect(body).toContain('$1,800');
	});

	it('AC 7 / M-3 — the tax rows render UNFLIPPED (no leading minus sign; debt stays the only negation)', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).not.toContain('-$4,200');
		expect(body).not.toContain('-$1,800');
	});

	it('the V1.1 tax-placeholder shape is GONE: no "$0" tax rows, no V1.4-ramp caption text', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).not.toContain('(from §2.5) · full estimate arrives in V1.4');
	});

	it('renders the NAV foot whole-dollar (echoes the §2.1.1 headline, D9)', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).toContain('Net Assets Value (NAV)');
		expect(body).toContain('$350,000');
	});
});

describe('NavCompositionTable — SELF-268 AC 9a: the §2.5.4 disclaimer is a visible footnote (never hover-only)', () => {
	it('renders the PRD-verbatim disclaimer text in the page body itself (not a title attribute)', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).toContain('Treat this as an LT-aware floor estimate, not a precise tax forecast.');
		// A title attribute would put the text INSIDE a `title="..."`, invisible to SSR body text
		// unless it's real rendered content — assert it's not merely present as an attribute value.
		expect(body).not.toContain('title="Treat this as an LT-aware floor estimate');
	});
});

describe('NavCompositionTable — SELF-268 AC 6 (EXPECTED CONTRACT, provisional): tax_components availability', () => {
	it('absent `tax_components` → no "Unavailable" notice renders (graceful no-op, not a crash)', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).not.toContain('Unavailable');
	});

	it('an unavailable realized scalar renders "Unavailable" instead of its $0 buildups value — never a silent zero', () => {
		const unavailable: NavComposition = {
			...fixture,
			buildups: { ...fixture.buildups, realized_tax_liab: 0 },
			tax_components: {
				realized_tax_liab: { status: 'unavailable', reason: 'no_ledger_designated' },
				unrealized_tax_liab: { status: 'computed' }
			}
		};
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: unavailable } });
		expect(body).toContain('Unavailable');
		expect(body).toContain('no tax-authority ledger designated');
	});

	it('a computed status renders the real dollar figure, no "Unavailable" text', () => {
		const computed: NavComposition = {
			...fixture,
			tax_components: {
				realized_tax_liab: { status: 'computed' },
				unrealized_tax_liab: { status: 'computed' }
			}
		};
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: computed } });
		expect(body).not.toContain('Unavailable');
		expect(body).toContain('$4,200');
	});
});

describe('NavCompositionTable — SELF-268 AC 10a / R3 rider 0b+6 (EXPECTED CONTRACT, provisional): excluded_tax_ledgers', () => {
	it('field absent → no exclusion note renders at all (a real payload gap, never a fabricated claim)', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).not.toContain('tax-authority ledgers');
	});

	it('field present but EMPTY → renders the "none excluded" line — the unmarked-ledger visibility rider 0b requires', () => {
		const noneExcluded: NavComposition = { ...fixture, excluded_tax_ledgers: [] };
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: noneExcluded } });
		expect(body).toContain('No accounts are currently designated as tax-authority ledgers');
	});

	it('field present with entries → names each excluded account, linked to its /accounts/[id] page', () => {
		const withExclusion: NavComposition = {
			...fixture,
			excluded_tax_ledgers: [{ account_id: 99, account_name: 'IRS Escrow' }]
		};
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: withExclusion } });
		expect(body).toContain('Excluded from Net Worth above as tax-authority ledgers');
		expect(body).toContain('IRS Escrow');
		expect(body).toContain('/accounts/99');
	});
});

describe('NavCompositionTable — empty-groups tree (D3 empty categories omitted upstream)', () => {
	it('still renders the ladder + NAV when groups is empty (zero-account well-formed tree)', () => {
		const empty: NavComposition = {
			groups: [],
			buildups: { total_non_re: 0, gross_total: 0, debt: 0, realized_tax_liab: 0, unrealized_tax_liab: 0 },
			nav: 0
		};
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: empty } });
		expect(body).toContain('Net Assets Value (NAV)');
		expect(body).toContain('Total Non-RE');
		expect(body).not.toContain('group-head'); // no category headers
	});
});

describe('NavCompositionTable — SELF-229 section shell + D1 stale-data-marker', () => {
	it('owns its own "Composition" section heading (moved in from +page.svelte)', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).toContain('>Composition<');
	});

	// Sec F3(B) (F/CTO-ruled): `staleness` is now a REQUIRED prop — there is no more implicit
	// "omitted" case (a caller that forgets it fails at TYPECHECK). This asserts the explicit
	// EMPTY_STALENESS (confirmed-healthy) value stays zero-footprint, same as before.
	it('staleness confirmed healthy (EMPTY_STALENESS) → zero-footprint, no badge markup', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).not.toContain('stale-connection-marker');
		expect(body).not.toContain('May be stale');
	});

	it('is_stale true → the shared StaleConstituentBadge renders beside the heading (AGGREGATION level; per-leaf marking is a separate, currently-blocked AC)', () => {
		const staleItem: StaleConstituentItem = {
			linked_source_id: '42',
			institution_name: 'Test Bank',
			provider: 'plaid',
			connection_status: 'login_required',
			status_class: null
		};
		const { body } = render(NavCompositionTable, {
			props: { composition: fixture, staleness: { is_stale: true, stale_items: [staleItem] } }
		});
		expect(body).toContain('May be stale');
		// Institution name only renders inside the collapsed disclosure panel (StaleConstituentBadge's own {#if open} — closed by default); the tag + its accessible summary are what SSR proves here.
		expect(body).toContain('possibly-stale');
	});
});
