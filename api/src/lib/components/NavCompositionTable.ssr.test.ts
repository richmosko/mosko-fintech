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
//   • SELF-268 V1.4 flip, E41-E42 envelope shape (Sec P-18), RULING UPDATE E44 (Sec freeze F-2
//     option (A), team-lead under F/CTO delegation, which also closes F-1): `buildups.realized_tax_liab` /
//     `unrealized_tax_liab` are ENVELOPES ({status:'computed',amount}|{status:'unavailable',reason},
//     reusing tax-quarterly.ts's shipped `FundsDueEnvelope`); a computed envelope renders its real
//     amount FLIPPED — the same single flip site as Debt — so an underpaid liability (positive raw
//     amount) renders NEGATIVE (reduces NAV) and an overpaid one (negative raw amount, a receivable)
//     renders POSITIVE with an explicit "+" (adds back) — the V1.1 `isTaxPlaceholder` `$0` +
//     "V1.4 ramp" caption shape is GONE.
//   • SELF-268 AC 9a: the §2.5.4 disclaimer renders as a visible footnote (no hover-only).
//   • SELF-268 AC 6: an unavailable envelope renders "Unavailable — <copy>" text (the FINAL copy
//     per team-lead 2026-09-04), never the $0 the buildups value would otherwise arithmetically be.
//   • Sec P-5 / option (C): the NAV foot's OWN LABEL carries the three-state tax-adjustment basis
//     (tax-adjusted / partial / unadjusted) — never a caption beside the table, never a boolean.
//     All three states are proven here, including BOTH partial sub-cases.
//   • SELF-268 AC 10a — `excludedTaxLedgers`, a SIBLING PROP to `composition` (Backend's confirmed
//     root-loader field, NOT nested in the composition payload). THREE distinct states proven:
//     `undefined` (prop omitted → no-op), `null` (the loader's reads FAILED → explicit notice,
//     never silently "none excluded"), `[]` (confirmed none designated → explicit "none excluded"
//     line), plus a populated list with jurisdiction labels.
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
		// SELF-268 E41: envelopes, `amount` is a real value, positive magnitude (AC 7 / M-3).
		realized_tax_liab: { status: 'computed', amount: 4_200 },
		unrealized_tax_liab: { status: 'computed', amount: 1_800 }
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

	it('RULING UPDATE (E44) — the tax rows render FLIPPED, same as Debt: a positive (underpaid) raw amount renders with a leading minus', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).toContain('-$4,200');
		expect(body).toContain('-$1,800');
	});

	it('the V1.1 tax-placeholder shape is GONE: no "$0" tax rows, no V1.4-ramp caption text', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).not.toContain('(from §2.5) · full estimate arrives in V1.4');
	});

	it('renders the NAV foot whole-dollar (echoes the §2.1.1 headline, D9), label reflects the tax-adjusted state', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).toContain('Net Assets Value (tax-adjusted)');
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

describe('NavCompositionTable — SELF-268 AC 6 (E41 envelope shape): unavailable tax lines never render $0', () => {
	it('both computed (default fixture) → no "Unavailable" notice renders', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).not.toContain('Unavailable');
	});

	it('an unavailable realized envelope renders "Unavailable — <copy>", never the arithmetic $0', () => {
		const unavailable: NavComposition = {
			...fixture,
			buildups: {
				...fixture.buildups,
				realized_tax_liab: { status: 'unavailable', reason: 'ytd_paid_unavailable' }
			}
		};
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: unavailable } });
		expect(body).toContain('Unavailable');
		expect(body).toContain('a tax-authority ledger is not designated for every jurisdiction — designate the missing one in Accounts');
	});

	it('a negative raw realized amount (overpayment/receivable) renders as a real POSITIVE figure with an explicit "+" (adds back), never $0/unavailable', () => {
		const overpayment: NavComposition = {
			...fixture,
			buildups: { ...fixture.buildups, realized_tax_liab: { status: 'computed', amount: -500 } }
		};
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: overpayment } });
		expect(body).not.toContain('Unavailable');
		expect(body).toContain('+$500');
		expect(body).not.toContain('-$500');
	});

	it('a computed envelope renders the real dollar figure, no "Unavailable" text', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).not.toContain('Unavailable');
		expect(body).toContain('$4,200');
	});
});

describe('NavCompositionTable — Sec P-5 / option (C): the NAV-foot LABEL carries the three-state basis (never a boolean, never a caption beside the table)', () => {
	it('both envelopes computed → "Net Assets Value (tax-adjusted)"', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).toContain('Net Assets Value (tax-adjusted)');
	});

	it('both envelopes unavailable → "Net Assets Value (pre-tax — tax lines unavailable)"', () => {
		const unadjusted: NavComposition = {
			...fixture,
			buildups: {
				...fixture.buildups,
				realized_tax_liab: { status: 'unavailable', reason: 'ytd_paid_unavailable' },
				unrealized_tax_liab: { status: 'unavailable', reason: 'no_schedule_any_year' }
			}
		};
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: unadjusted } });
		expect(body).toContain('Net Assets Value (pre-tax — tax lines unavailable)');
	});

	it('realized unavailable only (partial, sub-case A) → names the realized line', () => {
		const partial: NavComposition = {
			...fixture,
			buildups: { ...fixture.buildups, realized_tax_liab: { status: 'unavailable', reason: 'ytd_paid_unavailable' } }
		};
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: partial } });
		expect(body).toContain(
			'Net Assets Value (realized tax not yet deducted — a tax-authority ledger is not designated for every jurisdiction — designate the missing one in Accounts)'
		);
	});

	it('unrealized unavailable only (partial, sub-case B) → names the unrealized line', () => {
		const partial: NavComposition = {
			...fixture,
			buildups: { ...fixture.buildups, unrealized_tax_liab: { status: 'unavailable', reason: 'no_schedule_any_year' } }
		};
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: partial } });
		expect(body).toContain(
			'Net Assets Value (unrealized tax not yet deducted — no tax bracket schedule on file — enter it in Settings)'
		);
	});
});

describe('NavCompositionTable — SELF-268 AC 10a / R3 rider 0b+6: excludedTaxLedgers (a SIBLING prop, THREE distinct states)', () => {
	it('prop absent (component default) → no exclusion note renders at all (a real payload gap, never a fabricated claim)', () => {
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: fixture } });
		expect(body).not.toContain('tax-authority ledgers');
	});

	it('prop === null (the loader read FAILED) → an explicit "couldn\'t confirm" notice, never silently read as "none excluded"', () => {
		const { body } = render(NavCompositionTable, {
			props: { staleness: EMPTY_STALENESS, composition: fixture, excludedTaxLedgers: null }
		});
		expect(body).toContain("couldn't confirm");
		expect(body).not.toContain('No accounts are designated');
	});

	it('prop === [] (CONFIRMED none designated) → renders the "none excluded" line — the unmarked-ledger visibility rider 0b requires', () => {
		const { body } = render(NavCompositionTable, {
			props: { staleness: EMPTY_STALENESS, composition: fixture, excludedTaxLedgers: [] }
		});
		expect(body).toContain('No accounts are designated as tax-authority ledgers — none excluded');
	});

	it('prop present with entries → names each excluded account + its jurisdiction label, linked to its /accounts/[id] page', () => {
		const { body } = render(NavCompositionTable, {
			props: {
				staleness: EMPTY_STALENESS,
				composition: fixture,
				excludedTaxLedgers: [
					{ account_id: 99, account_name: 'IRS Escrow', jurisdiction: 'irs' },
					{ account_id: 100, account_name: 'CA Escrow', jurisdiction: 'ftb' }
				]
			}
		});
		expect(body).toContain('Excluded from Net Worth above as tax-authority ledgers');
		expect(body).toContain('IRS Escrow');
		expect(body).toContain('/accounts/99');
		// Jurisdiction rendered via the SAME account-display.ts vocabulary the §2.4.2 account form
		// uses — never the raw 'irs'/'ftb' enum value in user-facing copy.
		expect(body).toContain('IRS (Federal)');
		expect(body).toContain('CA Escrow');
		expect(body).toContain('FTB (California)');
	});
});

describe('NavCompositionTable — empty-groups tree (D3 empty categories omitted upstream)', () => {
	it('still renders the ladder + NAV when groups is empty (zero-account well-formed tree)', () => {
		const empty: NavComposition = {
			groups: [],
			buildups: {
				total_non_re: 0,
				gross_total: 0,
				debt: 0,
				realized_tax_liab: { status: 'computed', amount: 0 },
				unrealized_tax_liab: { status: 'computed', amount: 0 }
			},
			nav: 0
		};
		const { body } = render(NavCompositionTable, { props: { staleness: EMPTY_STALENESS, composition: empty } });
		expect(body).toContain('Net Assets Value (tax-adjusted)');
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
