// asOf.test.ts — SELF-238 coverage for `userSuppliedAsOf`, the second production factory for
// the `ZoneResolvedAsOf` brand. Behavioral coverage; the shape/containment invariants (which
// files may cast to the brand, where `unsafeAsOfForTest` may be imported from) are QA-owned in
// asOfBrand.invariant.test.ts and are not duplicated here.
//
// EXTENDED at the V1.5 aal2/asOf close-out follow-up (Sec self360-sec-review.md shape (a)) with a
// grep-shaped leg asserting `userSuppliedAsOf` has NO production caller outside its own schema
// module (`schemas/asOf.ts`) — the property `asOf.ts`'s own module header now claims, restored by
// routing P8's DB-derived date through the new `storedAsOf` factory instead. Not duplicating
// asOfBrand.invariant.test.ts's own containment checks (those cover CASTS to the brand and
// `unsafeAsOfForTest` imports; a call to `userSuppliedAsOf` needs neither, so it is a genuinely
// different property with no existing instrument).

import { describe, it, expect } from 'vitest';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { userSuppliedAsOf, storedAsOf, serverTodayAsOf } from './asOf';

describe('userSuppliedAsOf', () => {
	it('accepts a well-formed real calendar date and returns it unchanged (structurally a string)', () => {
		expect(userSuppliedAsOf('2026-07-20')).toBe('2026-07-20');
	});

	it('accepts leap-day and month-end boundaries', () => {
		expect(userSuppliedAsOf('2024-02-29')).toBe('2024-02-29'); // 2024 is a leap year
		expect(userSuppliedAsOf('2026-01-31')).toBe('2026-01-31');
	});

	it('rejects a non-existent calendar date (e.g. Feb 31, non-leap Feb 29)', () => {
		expect(() => userSuppliedAsOf('2026-02-31')).toThrow(/real calendar date/);
		expect(() => userSuppliedAsOf('2026-02-29')).toThrow(/real calendar date/); // 2026 is not a leap year
	});

	it('rejects malformed shapes without ever reaching Date parsing', () => {
		expect(() => userSuppliedAsOf('2026/07/20')).toThrow(/YYYY-MM-DD/);
		expect(() => userSuppliedAsOf('07-20-2026')).toThrow(/YYYY-MM-DD/);
		expect(() => userSuppliedAsOf('2026-7-20')).toThrow(/YYYY-MM-DD/);
		expect(() => userSuppliedAsOf('')).toThrow(/YYYY-MM-DD/);
		expect(() => userSuppliedAsOf('not-a-date')).toThrow(/YYYY-MM-DD/);
	});

	it('rejects the adversarial-battery-shaped garbage a Zod bypass could still hand it', () => {
		expect(() => userSuppliedAsOf('NaN')).toThrow();
		expect(() => userSuppliedAsOf('Infinity')).toThrow();
		expect(() => userSuppliedAsOf('2026-07-20T00:00:00Z')).toThrow(); // timestamp, not a bare date
		expect(() => userSuppliedAsOf('9'.repeat(1000))).toThrow();
	});

	it('is a DIFFERENT production path from serverTodayAsOf, both landing on the same branded type', () => {
		// Structural equality is not the point here (they mint different dates); the point is both
		// compile as ZoneResolvedAsOf without a cast at either call site — i.e. this file itself
		// never writes `as ZoneResolvedAsOf` (asOfBrand.invariant.test.ts is the containment proof).
		const today = serverTodayAsOf();
		const chosen = userSuppliedAsOf('2020-01-01');
		expect(typeof today).toBe('string');
		expect(typeof chosen).toBe('string');
	});

	// V1.5 aal2/asOf close-out follow-up (Sec self360-sec-review.md): a grep-shaped leg over `src`,
	// not another behavioral case — this is source-level BY NECESSITY, same reasoning
	// asOfBrand.invariant.test.ts's own header gives for its own checks: there is no runtime
	// observation that distinguishes "the only call is inside schemas/asOf.ts" from "a route calls
	// it too" once both compile.
	it('has NO production caller outside its own schema module (schemas/asOf.ts) and tests', () => {
		const SRC = fileURLToPath(new URL('../../../', import.meta.url)); // -> api/src/

		function sourceFiles(dir: string, acc: string[] = []): string[] {
			for (const entry of readdirSync(dir)) {
				if (entry === 'node_modules' || entry === '.svelte-kit') continue;
				const full = join(dir, entry);
				if (statSync(full).isDirectory()) sourceFiles(full, acc);
				else if (/\.(ts|svelte)$/.test(entry)) acc.push(full);
			}
			return acc;
		}

		const files = sourceFiles(SRC);
		// PRECONDITION (mirrors asOfBrand.invariant.test.ts's own first assertion) — without this,
		// a moved directory or changed extension makes every assertion below pass vacuously.
		expect(files.length).toBeGreaterThan(100);

		const code = (src: string) => src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');

		const EXEMPT = new Set(['lib/server/time/asOf.ts', 'lib/server/schemas/asOf.ts']);
		const callers = files
			.map((f) => relative(SRC, f).replace(/\\/g, '/'))
			.filter((rel) => {
				if (EXEMPT.has(rel)) return false;
				if (/\.test\.ts$/.test(rel)) return false;
				const full = join(SRC, rel);
				return /\buserSuppliedAsOf\s*\(/.test(code(readFileSync(full, 'utf8')));
			});

		expect(
			callers,
			'userSuppliedAsOf is called from a production file outside schemas/asOf.ts. A DB-derived date must route through storedAsOf instead (see asOf.ts\'s own module header) — routing it through userSuppliedAsOf makes the brand stop discriminating provenance by name.'
		).toEqual([]);
	});

	it('storedAsOf accepts a well-formed real calendar date (the P8 DB-derived-date factory)', () => {
		expect(storedAsOf('2026-09-04')).toBe('2026-09-04');
	});

	it('storedAsOf rejects the same malformed/non-existent-date classes userSuppliedAsOf does', () => {
		expect(() => storedAsOf('2026-02-31')).toThrow(/real calendar date/);
		expect(() => storedAsOf('2026/09/04')).toThrow(/YYYY-MM-DD/);
	});
});
