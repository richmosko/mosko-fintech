// nav-series-params.test.ts — unit battery for the client-side NAV-chart URL-param mirror
// (SELF-220). Proves the schema stays as strict as its posture claims: unknown keys rejected
// (.strict()), bad enum/date values rejected, inverted ranges rejected, and a malformed URL
// degrades to {} (the surface's default) rather than throwing.

import { describe, it, expect } from 'vitest';
import { navSeriesParamsSchema, parseNavSeriesParams } from './nav-series-params';

describe('navSeriesParamsSchema — well-formed input', () => {
	it('accepts all-absent (the default-window case)', () => {
		expect(navSeriesParamsSchema.safeParse({}).success).toBe(true);
	});

	it('accepts a well-formed granularity + non-inverted range', () => {
		const r = navSeriesParamsSchema.safeParse({
			granularity: 'weekly',
			start: '2026-01-01',
			end: '2026-06-30'
		});
		expect(r.success).toBe(true);
	});

	it('accepts start === end (a single-day zoom)', () => {
		expect(
			navSeriesParamsSchema.safeParse({ start: '2026-01-01', end: '2026-01-01' }).success
		).toBe(true);
	});
});

describe('navSeriesParamsSchema — rejects, mirroring 062s posture', () => {
	it('rejects a granularity outside {monthly,weekly,daily}', () => {
		expect(navSeriesParamsSchema.safeParse({ granularity: 'yearly' }).success).toBe(false);
	});

	it('rejects a non-calendar date (2026-02-31)', () => {
		expect(navSeriesParamsSchema.safeParse({ start: '2026-02-31' }).success).toBe(false);
	});

	it('rejects a malformed date string', () => {
		expect(navSeriesParamsSchema.safeParse({ start: '01/01/2026' }).success).toBe(false);
	});

	it('rejects an inverted range (start after end)', () => {
		expect(
			navSeriesParamsSchema.safeParse({ start: '2026-06-30', end: '2026-01-01' }).success
		).toBe(false);
	});

	it('rejects an unknown key (.strict() — the mass-assignment fence)', () => {
		expect(navSeriesParamsSchema.safeParse({ granularity: 'monthly', extra: 'x' }).success).toBe(
			false
		);
	});
});

describe('parseNavSeriesParams — degrades a malformed URL to the default, never throws', () => {
	it('parses a well-formed query string', () => {
		const search = new URLSearchParams('granularity=daily&start=2026-01-01&end=2026-03-31');
		expect(parseNavSeriesParams(search)).toEqual({
			granularity: 'daily',
			start: '2026-01-01',
			end: '2026-03-31'
		});
	});

	it('degrades an invalid granularity to {} rather than dropping only that field', () => {
		const search = new URLSearchParams('granularity=yearly&start=2026-01-01&end=2026-03-31');
		expect(parseNavSeriesParams(search)).toEqual({});
	});

	it('degrades an inverted range to {} rather than swapping/clamping it', () => {
		const search = new URLSearchParams('start=2026-06-30&end=2026-01-01');
		expect(parseNavSeriesParams(search)).toEqual({});
	});

	it('degrades a hand-edited garbage query string to {} without throwing', () => {
		const search = new URLSearchParams('granularity=<script>&start=nope');
		expect(() => parseNavSeriesParams(search)).not.toThrow();
		expect(parseNavSeriesParams(search)).toEqual({});
	});

	it('returns {} for an empty query string', () => {
		expect(parseNavSeriesParams(new URLSearchParams(''))).toEqual({});
	});
});
