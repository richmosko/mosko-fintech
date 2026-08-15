// page-staleness.test.ts — QA-owned. Named WITHOUT the `+` prefix deliberately: `src/routes/` is
// SvelteKit-reserved for `+page.svelte` / `+page.server.ts` / `+layout.*` etc., and
// `svelte-kit sync` throws ("Files prefixed with + are reserved") on any other `+`-prefixed file
// in that directory — confirmed by hand (a first draft named `+page.staleness.test.ts` broke
// `svelte-kit sync`, and therefore `npm run check`, silently as far as `vitest run` alone was
// concerned, since vitest itself doesn't invoke svelte-kit sync). Follows the SAME topic-named,
// non-mirroring convention this directory's other route tests already use
// (`nav-series.server.test.ts` tests `+page.server.ts`, not `+page.server.test.ts`).
//
// The §2.1.1 headline's OWN <StaleConstituentBadge> mount (SELF-208 AC#4, +page.svelte lines
// ~130-135) had no dedicated render test at all — every other SELF-229 surface (chart / delta
// panel / reference-dates panel / composition) got a wiring-fidelity leg in this battery; the
// headline itself, the FIRST and original mount site, did not. Closes that gap for F/CTO ruling
// (a) item 2 ("unknown-state render legs at the headline + four surfaces") — the four surfaces'
// own SSR files already carry the analogous `is_stale: true` wiring check; this file is the
// headline's counterpart, extended to the tri-state UNKNOWN case now that render-layer work has
// landed (442dac8 — StaleConstituentBadge.svelte's own tri-state distinguishability is already
// proven exhaustively there; this file proves WIRING at the headline mount, not the badge's
// internal behaviour again).
//
// @vitest-environment node
import { describe, it, expect } from 'vitest';
import { render } from 'svelte/server';
import Page from './+page.svelte';
import { EMPTY_STALENESS, UNKNOWN_STALENESS, type StalenessData } from '$lib/staleness/stale-constituent';
import type { StaleConstituentItem } from '$lib/staleness/stale-constituent';
import { unsafeAsOfForTest } from '$lib/server/time/asOf';

// Minimal PageData satisfying every field +page.svelte's template reaches for on the nav-hero
// branch, INCLUDING the parent +layout.server.ts fields SvelteKit merges into `PageData`
// (userEmail / pendingClassificationCount / connectionHealth — svelte-check caught these missing
// on a first draft; +page.svelte doesn't read them directly, but the generated `PageData` type is
// the UNION of every ancestor layout's load() return, not just this route's own). Every
// non-staleness field is a SAFE fail-soft default (null / a harmless params object) so each child
// component below the headline renders its own read-failed notice rather than throwing — this
// file is about the HEADLINE's own badge, not the child surfaces (their own SSR files cover their
// own wiring).
function pageData(staleness: StalenessData, overrides: Partial<Record<string, unknown>> = {}) {
	return {
		userEmail: null,
		pendingClassificationCount: 0,
		connectionHealth: { reauthCount: 0, institutionDownCount: 0 },
		netWorth: 500_000,
		accountPresence: 'some' as const,
		asOf: unsafeAsOfForTest('2026-08-14'),
		staleness,
		navReferenceDates: null,
		navDeltaPanel: null,
		composition: null,
		navSeries: null,
		navSeriesParamsError: null,
		navSeriesParams: { granularity: 'monthly' as const, start: '2021-06-01', end: '2026-06-01' },
		navBoundary: null,
		...overrides
	};
}

const staleItem: StaleConstituentItem = {
	linked_source_id: '42',
	institution_name: 'Test Bank',
	provider: 'plaid',
	connection_status: 'login_required',
	status_class: null
};

describe('+page.svelte — headline §2.1.1 StaleConstituentBadge mount, tri-state wiring', () => {
	it('staleness.is_stale === null (UNKNOWN_STALENESS): the headline renders "Staleness unknown"', () => {
		const { body } = render(Page, { props: { data: pageData(UNKNOWN_STALENESS) } });
		expect(body).toContain('Staleness unknown');
		expect(body).not.toContain('May be stale');
	});

	it('staleness.is_stale === false (EMPTY_STALENESS, confirmed healthy): zero-footprint at the headline', () => {
		const { body } = render(Page, { props: { data: pageData(EMPTY_STALENESS) } });
		expect(body).not.toContain('Staleness unknown');
		expect(body).not.toContain('May be stale');
	});

	it('staleness.is_stale === true: the headline still renders "May be stale" (unaffected by the tri-state widening)', () => {
		const { body } = render(Page, {
			props: { data: pageData({ is_stale: true, stale_items: [staleItem] }) }
		});
		expect(body).toContain('May be stale');
		expect(body).not.toContain('Staleness unknown');
	});

	// ── The headline's own PRE-EXISTING "unknown" (accountPresence==='unknown', the account-COUNT
	// read failing) is a DIFFERENT, ORTHOGONAL unknown from staleness's "couldn't confirm
	// staleness". Both are reachable at once (netWorth===0, accountPresence==='unknown', staleness
	// itself also unknown) — the two must render as separate, non-conflated notices, not merged or
	// mistaken for each other by a future reader who sees "unknown" twice on the same screen.
	describe('the pre-existing accountPresence==="unknown" notice is a DIFFERENT unknown, never conflated with staleness unknown', () => {
		it('both unknowns reachable together (netWorth=0, accountPresence=unknown, staleness=null): TWO distinct notices render, neither substitutes for the other', () => {
			const { body } = render(Page, {
				props: {
					data: pageData(UNKNOWN_STALENESS, { netWorth: 0, accountPresence: 'unknown' })
				}
			});
			// The account-count-unknown notice (pre-existing, +page.svelte's own copy).
			expect(body).toContain("We couldn't load your account list just now");
			// The staleness-unknown notice (the badge's own copy, SELF-229).
			expect(body).toContain('Staleness unknown');
			expect(body).toContain("we couldn't confirm");
		});

		it('staleness unknown alone (netWorth non-zero, accountPresence known): the account-count notice does NOT fire — it is scoped to netWorth===0 only', () => {
			const { body } = render(Page, {
				props: { data: pageData(UNKNOWN_STALENESS, { netWorth: 500_000, accountPresence: 'some' }) }
			});
			expect(body).toContain('Staleness unknown');
			expect(body).not.toContain("We couldn't load your account list just now");
		});
	});
});
