// asOfBrand.invariant.test.ts — QA-owned. The two invariants that keep the ZoneResolvedAsOf
// brand meaningful, converted from documented greps into failing instruments.
//
// ┌─ WHY THIS EXISTS ────────────────────────────────────────────────────────────────────┐
// │ `asOf.ts` records two invariants and names `grep` as the check for one of them:       │
// │   (1) casts able to produce the brand are enumerable at TWO, both in `asOf.ts`         │
// │       — "`grep -rn 'as ZoneResolvedAsOf' src/` should only ever return this file"      │
// │   (2) `unsafeAsOfForTest` imported from a non-test file is a review stop               │
// │                                                                                        │
// │ Both are correct and neither had an instrument. **A documented invariant with no       │
// │ failing instrument is a comment with better formatting** — it holds exactly as long as │
// │ every future reader runs the grep they were told about, which is not a control.        │
// │ Backend named the escape hatch as a real hole rather than a solution; this is the      │
// │ half of it that can be mechanised.                                                     │
// │                                                                                        │
// │ ⚠ WHAT THIS CANNOT DO, stated so the green is not over-read: it does not make the      │
// │   hatch safe. A cast INSIDE `asOf.ts` and a test file that fabricates a nonsense date   │
// │   both remain possible and both stay invisible here. It fences the hatch's BLAST        │
// │   RADIUS — how far the ability to mint a brand can spread — not its existence.          │
// └────────────────────────────────────────────────────────────────────────────────────────┘
//
// SOURCE-LEVEL BY NECESSITY. These are properties of the code's shape, not of its behaviour:
// there is no runtime observation that distinguishes a brand minted in `asOf.ts` from one
// minted in a route handler — that is what a phantom type means. `058`'s (B5) raise-site count
// and (C7) are the same class, for the same reason.

import { describe, it, expect } from 'vitest';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const SRC = fileURLToPath(new URL('../../../', import.meta.url)); // -> api/src/

/** Every .ts/.svelte file under api/src, as repo-relative paths. */
function sourceFiles(dir: string, acc: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		if (entry === 'node_modules' || entry === '.svelte-kit') continue;
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) sourceFiles(full, acc);
		else if (/\.(ts|svelte)$/.test(entry)) acc.push(full);
	}
	return acc;
}

const FILES = sourceFiles(SRC);
const rel = (f: string) => relative(SRC, f).replace(/\\/g, '/');

/**
 * Strip `//` and block comments before matching.
 *
 * ⚑ ADDED AFTER THIS FILE'S FIRST RUN CAUGHT ITSELF. The cast assertion went RED naming TWO
 * files — and the second was THIS ONE, matched on the header comment that QUOTES the grep it
 * replaces. `asOf.ts:53` quotes it too. **A source-scanning check matches the prose written
 * about it**, which is the third time this pattern has appeared in this suite (see DESIGN.md
 * §10: a check matched the warning label written to prevent its own defect). Match executable
 * text only — the anchoring rule, applied to the instrument rather than to the subject.
 */
const code = (src: string) => src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');

describe('ZoneResolvedAsOf brand — shape invariants, not behaviour', () => {
	// PRECONDITION, asserted separately from the results below (DESIGN.md rule 3). If the walk
	// returns nothing — a moved directory, a changed extension, a bad URL base — then EVERY
	// assertion in this file passes over an empty set and reports a clean brand. That is the
	// failure mode a source-scanning test has instead of a fixture, and it is silent.
	it('the source walk actually found files — without this the rest is vacuous', () => {
		expect(FILES.length).toBeGreaterThan(100);
		expect(FILES.some((f) => rel(f) === 'lib/server/time/asOf.ts')).toBe(true);
	});

	it('every cast to the brand lives in asOf.ts — the mint is one file', () => {
		const casters = FILES.filter((f) =>
			/as\s+ZoneResolvedAsOf/.test(code(readFileSync(f, 'utf8')))
		).map(rel);
		// Not a count: a count says "two" and tells the next reader nothing about WHERE, and it
		// goes red on a legitimate third cast inside asOf.ts itself. The property is CONTAINMENT.
		expect(casters).toEqual(['lib/server/time/asOf.ts']);
	});

	it('unsafeAsOfForTest is imported ONLY by test files — the hatch does not reach production', () => {
		const importers = FILES.filter((f) => {
			// The declaration site is not an import of itself.
			if (rel(f) === 'lib/server/time/asOf.ts') return false;
			return /\bunsafeAsOfForTest\b/.test(code(readFileSync(f, 'utf8')));
		}).map(rel);

		const nonTest = importers.filter((f) => !/\.test\.ts$/.test(f));
		// THIS is the assertion Backend's comment described and could not enforce: "imported from
		// any non-.test.ts file is a review stop". A review stop depends on a reviewer noticing;
		// this depends on nobody.
		expect(
			nonTest,
			`unsafeAsOfForTest leaked into non-test file(s). The brand exists to prove an as-of came from a zone-resolved server clock; a production file that can mint one has removed that proof while every type still checks. Derive the date from the server clock, or state why this file is exempt and move the exemption into asOf.ts where it is reviewable.`
		).toEqual([]);

		// Non-vacuity: the hatch IS used somewhere, so the assertion above is a containment
		// result rather than a report that nothing imports it (which would also produce []).
		expect(importers.length).toBeGreaterThan(0);
	});
});
