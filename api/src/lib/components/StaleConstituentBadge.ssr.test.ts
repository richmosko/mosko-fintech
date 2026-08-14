// StaleConstituentBadge.ssr.test.ts — QA render/remove FOOTPRINT battery for the D1 staleness
// marker (SELF-208 · §2.4.4.c AC#5 · ADR-013 Decision 1). Dep-free: server-side render via
// `svelte/server` (already-installed `svelte` 5) — NO jsdom / NO @testing-library.
//
// WHAT THIS COVERS (the zero-footprint render/remove discipline — AC#5 marks-never-suppresses):
//   • stale-injected  → the marker RENDERS (a visible ".stale-connection-marker" group + the "May
//                        be stale" tag + the accessible standing-condition summary naming the
//                        stale count). Renamed from ".stale-marker" (SELF-229, QA finding) — that
//                        shorter name collides with NavChartLines.svelte's UNRELATED per-point
//                        checkpoint-carry marker (<g class="stale-marker" role="img">), which
//                        renders inside the SAME NavHistoryChart tree this badge also mounts in.
//   • un-stale         → the badge renders NOTHING (zero-footprint) — proves it REMOVES on the next
//                        render cycle after re-auth (mirrors CountBadge zero-footprint discipline).
//   • flag/list disagree (isStale=true but empty list) → NOTHING (the component's defensive
//                        `show = isStale && staleItems.length > 0` gate).
//
// KNOWN COVERAGE BOUNDARY (flagged to team-lead — see the report): the account NAME + the
// per-status affordance (a "Re-authenticate" link vs "temporarily unavailable" text) live inside
// the component's keyboard DISCLOSURE panel (`{#if open}`, `open` starts false). SSR renders the
// collapsed state, so those are NOT in this output. The affordance DECISION they encode is proven
// dep-free by ../staleness/stale-constituent.test.ts; asserting the EXPANDED panel DOM (click to
// open → account name + Re-authenticate link) requires a DOM env (jsdom + @testing-library/svelte
// + @testing-library/user-event) — a gated dep-add per vitest.config.ts. That is the residual
// AC#5 assertion pending the dep-add decision.

// @vitest-environment node
import { describe, it, expect } from 'vitest';
import { render } from 'svelte/server';
import StaleConstituentBadge from './StaleConstituentBadge.svelte';
import type { StaleConstituentItem } from '$lib/staleness/stale-constituent';

const item = (status: string, id = 1): StaleConstituentItem => ({
	linked_source_id: id,
	institution_name: `Bank ${id}`,
	provider: 'plaid',
	connection_status: status,
	status_class: null
});

// Svelte 5 SSR emits structural hydration anchors (`<!--[-->…<!--]-->`) for every {#if} boundary,
// even when the block renders nothing. Zero-footprint = NO rendered DOM element, so strip HTML
// comments + whitespace and assert the remainder is empty (the honest "renders nothing" check).
const visible = (body: string): string => body.replace(/<!--[\s\S]*?-->/g, '').trim();

describe('StaleConstituentBadge — render/remove footprint (SSR)', () => {
	it('stale-injected → the marker RENDERS (visible marker + "May be stale" tag)', () => {
		const { body } = render(StaleConstituentBadge, {
			props: { isStale: true, staleItems: [item('login_required', 1)] }
		});
		expect(body).toContain('stale-connection-marker');
		expect(body).toContain('May be stale');
		// The accessible standing-condition summary names the stale count on the control.
		expect(body).toContain('1 account is contributing possibly-stale data to this total.');
		expect(body).toContain('role="group"');
	});

	it('stale with multiple constituents → summary names the plural count', () => {
		const { body } = render(StaleConstituentBadge, {
			props: {
				isStale: true,
				staleItems: [item('login_required', 1), item('institution_down', 2)]
			}
		});
		expect(body).toContain('2 accounts are contributing possibly-stale data to this total.');
	});

	it('un-stale ({is_stale:false, stale_items:[]}) → renders NOTHING (zero-footprint remove)', () => {
		const { body } = render(StaleConstituentBadge, {
			props: { isStale: false, staleItems: [] }
		});
		expect(visible(body)).toBe('');
		expect(body).not.toContain('stale-connection-marker');
		expect(body).not.toContain('May be stale');
	});

	it('defensive: isStale=true but EMPTY list → renders NOTHING (show gate honours BOTH)', () => {
		const { body } = render(StaleConstituentBadge, {
			props: { isStale: true, staleItems: [] }
		});
		expect(visible(body)).toBe('');
	});

	it('default props (no staleness data) → renders NOTHING (loader-absent safe default)', () => {
		const { body } = render(StaleConstituentBadge, { props: {} });
		expect(visible(body)).toBe('');
	});
});
