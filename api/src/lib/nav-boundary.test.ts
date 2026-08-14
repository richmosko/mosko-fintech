// nav-boundary.test.ts — unit battery for the §12.1/§12.6 cron/imported boundary
// disposition helpers (SELF-220). Browser-safe, dep-free (node env). Exercises all
// four states of 069's contract plus the mixed-view edge cases the flow-doc addendum
// calls out explicitly (§12.1 the whole reason the return is a row, §12.6 point 2).

import { describe, it, expect } from 'vitest';
import {
	isPreBoundaryPoint,
	isImportedEraPoint,
	shouldSuppressCarryStaleness,
	resolutionDisclosureFires,
	EMPTY_NAV_BOUNDARY,
	type NavBoundary
} from './nav-boundary';

const NO_ROWS: NavBoundary = { first_cron_checkpoint: null, has_cron_rows: false, has_imported_rows: false };
const IMPORTED_ONLY: NavBoundary = { first_cron_checkpoint: null, has_cron_rows: false, has_imported_rows: true };
const CRON_ONLY: NavBoundary = { first_cron_checkpoint: '2026-06-01', has_cron_rows: true, has_imported_rows: false };
const MIXED: NavBoundary = { first_cron_checkpoint: '2026-06-01', has_cron_rows: true, has_imported_rows: true };

describe('EMPTY_NAV_BOUNDARY', () => {
	it('is the no-rows state (069 state (a))', () => {
		expect(EMPTY_NAV_BOUNDARY).toEqual(NO_ROWS);
	});
});

describe('isPreBoundaryPoint', () => {
	it('false when there is no boundary at all (no-rows state)', () => {
		expect(isPreBoundaryPoint('2020-01-01', NO_ROWS)).toBe(false);
	});

	it('false when there is no boundary at all (imported-only state — nothing to be "before")', () => {
		expect(isPreBoundaryPoint('2020-01-01', IMPORTED_ONLY)).toBe(false);
	});

	it('true for a point strictly before the boundary (mixed state)', () => {
		expect(isPreBoundaryPoint('2026-05-31', MIXED)).toBe(true);
	});

	it('false for a point ON the boundary date (the boundary itself is cron-era)', () => {
		expect(isPreBoundaryPoint('2026-06-01', MIXED)).toBe(false);
	});

	it('false for a point after the boundary', () => {
		expect(isPreBoundaryPoint('2026-07-01', MIXED)).toBe(false);
	});
});

describe('isImportedEraPoint — the corrected predicate (Architect contract-conformance flag, 2026-08-13)', () => {
	it('imported-only state (has_cron_rows === false): TRUE for every point, regardless of date — the state IS the imported era, with no boundary date to compare against', () => {
		expect(isImportedEraPoint('2020-01-01', IMPORTED_ONLY)).toBe(true);
		expect(isImportedEraPoint('2026-08-13', IMPORTED_ONLY)).toBe(true);
	});

	it('mixed state: reduces to isPreBoundaryPoint exactly (a real boundary date exists to compare against)', () => {
		expect(isImportedEraPoint('2026-05-31', MIXED)).toBe(true);
		expect(isImportedEraPoint('2026-07-01', MIXED)).toBe(false);
	});

	it('cron-only state: false for every point — has_cron_rows is true and no real cron row precedes the min cron date', () => {
		expect(isImportedEraPoint('2026-06-15', CRON_ONLY)).toBe(false);
	});
});

describe('shouldSuppressCarryStaleness — §12.1/§12.2', () => {
	it('suppresses pre-boundary (mixed state)', () => {
		expect(shouldSuppressCarryStaleness('2026-05-31', MIXED)).toBe(true);
	});

	it('does NOT suppress post-boundary — a real cron gap keeps full diagnostic meaning', () => {
		expect(shouldSuppressCarryStaleness('2026-07-01', MIXED)).toBe(false);
	});

	it('does NOT suppress in a pure cron-only store — nothing pre-boundary exists', () => {
		expect(shouldSuppressCarryStaleness('2026-06-15', CRON_ONLY)).toBe(false);
	});

	it('⭐ REGRESSION (Architect, 2026-08-13): suppresses EVERY point in the imported-only state — the bug this leg exists to catch had this returning false for every point, because isPreBoundaryPoint alone answers false when first_cron_checkpoint is null', () => {
		expect(shouldSuppressCarryStaleness('2018-01-31', IMPORTED_ONLY)).toBe(true);
		expect(shouldSuppressCarryStaleness('2026-08-01', IMPORTED_ONLY)).toBe(true);
	});
});

describe('resolutionDisclosureFires — §12.1/§12.6', () => {
	it('never fires with no imported rows at all (no-rows state)', () => {
		expect(resolutionDisclosureFires(NO_ROWS, [])).toBe(false);
	});

	it('never fires in a pure cron-only store', () => {
		expect(resolutionDisclosureFires(CRON_ONLY, [{ point_date: '2026-06-15' }])).toBe(false);
	});

	it('fires for the WHOLE series in the imported-only state, unconditionally — no boundary to compare', () => {
		expect(resolutionDisclosureFires(IMPORTED_ONLY, [{ point_date: '2020-01-31' }])).toBe(true);
	});

	it('imported-only fires even with an EMPTY points array — a sparse/zero-row view must not be read as "no imported history" (069 state (a))', () => {
		expect(resolutionDisclosureFires(IMPORTED_ONLY, [])).toBe(true);
	});

	it('mixed state: fires when the current view includes at least one pre-boundary point', () => {
		const points = [{ point_date: '2026-05-01' }, { point_date: '2026-06-15' }];
		expect(resolutionDisclosureFires(MIXED, points)).toBe(true);
	});

	it('mixed state: does NOT fire when the current view is entirely post-boundary (e.g. a recent zoom)', () => {
		const points = [{ point_date: '2026-07-01' }, { point_date: '2026-07-15' }];
		expect(resolutionDisclosureFires(MIXED, points)).toBe(false);
	});

	it('mixed state with an empty points array does not fire — no view content to be pre-boundary', () => {
		expect(resolutionDisclosureFires(MIXED, [])).toBe(false);
	});
});
