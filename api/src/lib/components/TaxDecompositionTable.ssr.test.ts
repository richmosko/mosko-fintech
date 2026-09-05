// TaxDecompositionTable.ssr.test.ts — SELF-361 / P9 render-footprint battery: the D1
// stale-data-marker on the §2.5.1 decomposition page. Dep-free: server-side render via
// `svelte/server` (no jsdom / no @testing-library), mirroring NavCompositionTable.ssr.test.ts's
// own convention. Full AC1-11 coverage for this table lives in TaxDecompositionTable.dom.test.ts
// (SELF-264); this file covers ONLY what SELF-361 added — badge present/absent, and that it never
// merges with the Capital Gains capability-unavailable register (AC3).
//
// @vitest-environment node
import { describe, it, expect } from 'vitest';
import { render } from 'svelte/server';
import TaxDecompositionTable from './TaxDecompositionTable.svelte';
import type { TaxLiabilitySlice } from '$lib/tax-decomposition';
import { EMPTY_STALENESS, type StaleConstituentItem } from '$lib/staleness/stale-constituent';

const SEED_DELTA = '100_tax_value_inventory_seed_delta.sql';

const LIABILITY: TaxLiabilitySlice = {
	tax_year: 2026,
	decomposition: {
		ordinary_income: { rows: [], total: 0 },
		capital_gains: { status: 'unavailable', reason: 'no_sale_recording_capability' },
		unclassified: { count_ytd: 0 }
	}
};

const STALE_ITEM: StaleConstituentItem = {
	linked_source_id: '42',
	institution_name: 'Test Bank',
	provider: 'plaid',
	connection_status: 'login_required',
	status_class: null
};

describe('TaxDecompositionTable — SELF-361 / P9: D1 stale-data-marker', () => {
	it('staleness confirmed healthy (EMPTY_STALENESS) → zero-footprint, no badge markup', () => {
		const { body } = render(TaxDecompositionTable, {
			props: {
				liability: LIABILITY,
				taxCharacters: [],
				seedDeltaMigration: SEED_DELTA,
				staleness: EMPTY_STALENESS
			}
		});
		expect(body).not.toContain('stale-connection-marker');
		expect(body).not.toContain('May be stale');
	});

	it('is_stale true → the shared StaleConstituentBadge renders beside the section heading', () => {
		const { body } = render(TaxDecompositionTable, {
			props: {
				liability: LIABILITY,
				taxCharacters: [],
				seedDeltaMigration: SEED_DELTA,
				staleness: { is_stale: true, stale_items: [STALE_ITEM] }
			}
		});
		expect(body).toContain('May be stale');
	});

	it('AC3 separation: the badge and the Capital Gains capability-unavailable notice render TOGETHER, neither substituting for the other', () => {
		const { body } = render(TaxDecompositionTable, {
			props: {
				liability: LIABILITY,
				taxCharacters: [],
				seedDeltaMigration: SEED_DELTA,
				staleness: { is_stale: true, stale_items: [STALE_ITEM] }
			}
		});
		expect(body).toContain('May be stale');
		// The full sentence wraps across the template's own source lines, so SSR's raw HTML carries
		// a literal newline mid-sentence — match a phrase that stays on one source line, same
		// posture the DOM test takes with a regex instead.
		expect(body).toContain("Capital gains aren't shown here yet");
	});

	it('staleness unknown (RPC-read failure) → the muted "Staleness unknown" register, never a confirmed-stale tag', () => {
		const { body } = render(TaxDecompositionTable, {
			props: {
				liability: LIABILITY,
				taxCharacters: [],
				seedDeltaMigration: SEED_DELTA,
				staleness: { is_stale: null, stale_items: [] }
			}
		});
		expect(body).toContain('Staleness unknown');
		expect(body).not.toContain('May be stale');
	});
});
