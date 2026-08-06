// account-display.test.ts — QA-owned. ADR-043's invariant, converted from prose into
// instruments. Specified by Architect at `temp/closedatlabel-test-spec.md`; authored here.
//
// ┌─ WHY THIS EXISTS ─────────────────────────────────────────────────────────────────────┐
// │ MEASURED 2026-08-05: `closedAtLabel` had ZERO test coverage. Three surfaces render      │
// │ through it and no test file referenced it — the api/ test count was 551 on BOTH sides   │
// │ of the ADR-043 split, so removing the behaviour change moved the count by exactly zero. │
// │                                                                                          │
// │ Sec's ruling is why this is not follow-up: ADR-043's invariant — **UTC, unlabelled,      │
// │ all three surfaces or none** — was enforced by a doc-comment, and *the ADR's             │
// │ justification and the test that would catch its violation are the same claim.*           │
// └──────────────────────────────────────────────────────────────────────────────────────────┘
//
// ┌─ ⚠⚠ THE TRAP THIS FILE IS BUILT AROUND — read before editing any assertion below ──────┐
// │ **A `closedAtLabel` test that passes under every process TZ is blind to the variable at │
// │ issue, not robust to it.** `closedAtLabel` pins its render with `timeZone: 'UTC'`. Under │
// │ a process zone of UTC — which is what the dev stack and CI both measure — the output is  │
// │ IDENTICAL with and without that pin. An assertion written on such a stack reports green  │
// │ over the exact defect it claims to guard.                                                 │
// │                                                                                          │
// │ THIS IS NOT HYPOTHETICAL. It is the mechanism by which `059`'s false clause survived     │
// │ review, and `060` says so verbatim: *"IT HELD LOCALLY BY ACCIDENT, WHICH IS WHY IT        │
// │ SURVIVED REVIEW."* So every date assertion here pins the process zone OFF UTC, and both  │
// │ SIDES of UTC are covered — see (T2) for why one side is not enough.                       │
// │                                                                                          │
// │ >> FAIL-ONCE, PERFORMED 2026-08-05 (CP7 adversarial probe, not a claim): with            │
// │    `timeZone: 'UTC'` deleted from account-display.ts:98, (T1a)(T1b)(T2a)(T2b) all went    │
// │    RED — e.g. `expected 4 to be 5`, the literal off-by-one-day ADR-043 exists to prevent. │
// │    Restored -> 5 passed. If you change these assertions, REDO THAT PROBE. An assertion    │
// │    nobody has seen fail is an assertion nobody has shown reaches its subject.              │
// └──────────────────────────────────────────────────────────────────────────────────────────┘
//
// ┌─ ⚠ SCOPE FENCES — three claims, three instruments; do not let this file annex the others ┐
// │ • `formatTimestamp` in transaction-util.ts is NOT asserted here. ADR-043 leaves it open   │
// │   **on purpose** ("Left open on purpose") — its single consumer is SyncHistoryTable,      │
// │   which no gate compares against and which no second surface must agree with. A test      │
// │   pinning UTC there would silently extend a ruling that was explicitly WITHHELD, and the  │
// │   next reader would find a settled test where they expected an open question.             │
// │   `formatSyncTime` in the two route files is the same class and is likewise not asserted. │
// │ • The DATABASE session zone is NOT asserted here. That is                                  │
// │   `supabase/tests/01_session_timezone.sql`'s claim (CI stack only) and the runbook §10     │
// │   TZ-1 deploy gate's claim (production). A green here is evidence about NEITHER.           │
// │ • Assertions are on the DAY NUMBER and on the ABSENCE of a zone marker — never on a        │
// │   byte-exact locale string. An ICU/Node upgrade reds a byte-exact assertion, and whoever   │
// │   hits that red will delete (T1) along with it. The decision is carried by the day, not    │
// │   by the comma.                                                                            │
// └──────────────────────────────────────────────────────────────────────────────────────────┘

import { describe, it, expect, afterEach } from 'vitest';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { closedAtLabel } from './account-display';

// ── process-zone control ────────────────────────────────────────────────────────────────
// Node applies a `process.env.TZ` mutation to subsequent Date formatting (it notifies V8 of
// the configuration change), so the zone can be varied WITHIN one file rather than needing a
// per-file vitest `env:` and therefore a separate file per zone. VERIFIED under this runner
// rather than assumed — (T0) below is that verification, and it is an assertion rather than a
// comment precisely because the whole battery is vacuous if it silently stops working.
const ORIGINAL_TZ = process.env.TZ;
afterEach(() => {
	if (ORIGINAL_TZ === undefined) delete process.env.TZ;
	else process.env.TZ = ORIGINAL_TZ;
});

function withTZ<T>(zone: string, fn: () => T): T {
	process.env.TZ = zone;
	return fn();
}

/**
 * The day-of-month carried by a rendered label, or NaN.
 *
 * Deliberately NOT a byte-exact string comparison: the ruling is about WHICH DAY is shown,
 * and coupling to `'Aug 5, 2026'` would make an ICU version bump look like an ADR violation.
 * Takes the first 1–2 digit run that is not part of a 4-digit year.
 */
function dayOfMonth(label: string): number {
	const m = label.replace(/\d{4}/g, '').match(/\d{1,2}/);
	return m ? Number(m[0]) : NaN;
}

/** The UTC day-of-month named by the input itself — the expected value, read from the source. */
const utcDay = (iso: string) => Number(iso.slice(8, 10));

describe('closedAtLabel — ADR-043: UTC, unlabelled', () => {
	// (T0) PRECONDITION, asserted rather than assumed (the DESIGN.md rule that a source- or
	// environment-dependent battery must prove its input reaches it). If TZ mutation stops
	// taking effect — a Node change, a runner change, a pool that forks differently — then
	// EVERY assertion below passes under an effective UTC and reports a clean pin over a
	// broken one. That is this battery's silent-vacuity mode, and it is the same failure the
	// file's header box describes. This makes it LOUD.
	it('(T0) the process zone actually moves — without this the whole file is vacuous', () => {
		const probe = new Date('2026-08-05T01:00:00Z');
		const la = withTZ('America/Los_Angeles', () =>
			probe.toLocaleString('en-US', { dateStyle: 'medium' })
		);
		const tyo = withTZ('Asia/Tokyo', () => probe.toLocaleString('en-US', { dateStyle: 'medium' }));
		// Same instant, two zones, two different calendar days. If these are equal the runner is
		// not honouring the mutation and nothing below can be believed.
		expect(dayOfMonth(la)).not.toBe(dayOfMonth(tyo));
		expect(dayOfMonth(la)).toBe(4);
		expect(dayOfMonth(tyo)).toBe(5);
	});

	// (T1) THE UTC PIN IS LOAD-BEARING — west of UTC.
	//   `2026-08-05T01:00:00Z` is 4 Aug 18:00 in Los Angeles: the instant the prose reasons in.
	//   Without the pin this renders 4; the ledger's `closed_at::date` (UTC) says 5. That is the
	//   off-by-one-day ADR-043's accepted cost is predicated on NOT happening.
	//   Second row crosses a MONTH boundary as well as a day boundary — same defect, louder
	//   symptom, and it catches a "fix" that special-cases the day arithmetic.
	it.each([
		{ iso: '2026-08-05T01:00:00Z', localDay: 4, note: 'day boundary — 4 Aug 18:00 in LA' },
		{ iso: '2026-09-01T01:00:00Z', localDay: 31, note: 'month boundary — 31 Aug 18:00 in LA' }
	])('(T1) west of UTC renders the UTC day, not the local day [$note]', ({ iso, localDay }) => {
		const label = withTZ('America/Los_Angeles', () => closedAtLabel(iso));
		expect(dayOfMonth(label)).toBe(utcDay(iso));
		// Stated positively AND negatively: the negative names the actual wrong answer, so a
		// future red reads as "it rendered the LOCAL day" rather than "a number was not another".
		expect(dayOfMonth(label)).not.toBe(localDay);
	});

	// (T2) SYMMETRY EAST OF UTC — and this is not redundancy.
	//   West-of-UTC divergence is the one a US-based reviewer reproduces by accident. East of UTC
	//   is the direction the wider TZ analysis repeatedly found fails in the DANGEROUS direction,
	//   and a battery that only ever tests one side of UTC has re-created the hemisphere-dependence
	//   this whole slice exists to remove. Note the local day here is AHEAD, so the arithmetic sign
	//   is opposite to (T1) — a naive off-by-one "correction" passes one and fails the other.
	it.each([
		{ iso: '2026-08-04T23:00:00Z', localDay: 5, note: 'day boundary — 5 Aug 08:00 in Tokyo' },
		{ iso: '2026-08-31T23:00:00Z', localDay: 1, note: 'month boundary — 1 Sep 08:00 in Tokyo' }
	])('(T2) east of UTC renders the UTC day, not the local day [$note]', ({ iso, localDay }) => {
		const label = withTZ('Asia/Tokyo', () => closedAtLabel(iso));
		expect(dayOfMonth(label)).toBe(utcDay(iso));
		expect(dayOfMonth(label)).not.toBe(localDay);
	});

	// (T3) UNLABELLED — asserted on ABSENCE, because "unlabelled" is a ratified half of the
	//   decision and not a formatting accident. ADR-043 accepts that the reader is not told the
	//   zone; a future contributor "helpfully" appending `(UTC)` is changing the ruling, not
	//   improving the copy, and should go red here rather than pass review as a nicety.
	it('(T3) carries no zone marker of any kind', () => {
		for (const zone of ['America/Los_Angeles', 'Asia/Tokyo', 'UTC']) {
			const label = withTZ(zone, () => closedAtLabel('2026-08-05T01:00:00Z'));
			expect(label).not.toContain('(UTC)');
			// Any all-caps zone abbreviation (UTC/GMT/PDT/JST), a trailing Z, or a numeric offset.
			// `Aug` does not match: the class requires 3+ CONSECUTIVE capitals.
			expect(label).not.toMatch(/\b[A-Z]{3,4}\b|\bZ\b|[+-]\d{2}:?\d{2}/);
		}
	});

	// (T5) THE EXISTING CONTRACT — unchanged by ADR-043 and pinned so it stays that way.
	//   The passthrough leg matters more than it looks: returning the raw string rather than
	//   'Invalid Date' is what keeps a malformed value diagnosable on screen instead of
	//   replaced by a uniform lie.
	it('(T5) null renders empty, and an unparseable value passes through unchanged', () => {
		expect(closedAtLabel(null)).toBe('');
		expect(closedAtLabel('')).toBe('');
		expect(closedAtLabel('not-a-date')).toBe('not-a-date');
		// And the passthrough is NOT the JS default for a bad date.
		expect(closedAtLabel('not-a-date')).not.toBe('Invalid Date');
	});
});

// ─────────────────────────────────────────────────────────────────────────────────────────
// (T4) THE THREE-SURFACE INVARIANT — source-shaped, and it lives in this file on purpose.
//
// ⚑ THIS IS THE ASSERTION THAT GUARDS WHAT ADR-043 ACTUALLY RULED, and no amount of unit
//   testing above provides it. The ruling is *"all three surfaces or none."* The regression it
//   forbids is someone formatting `closed_at` inline on ONE screen — at which point
//   `closedAtLabel` is still perfectly correct and simply UNUSED there. Every assertion above
//   stays green through that. The property is CONTAINMENT of the formatting, not the
//   correctness of the formatter.
//
// ⚑ WHY NOT A SEPARATE `.invariant.test.ts` (the asOfBrand precedent's shape): ADR-043 is one
//   ruling with three clauses — UTC, unlabelled, all-three-or-none. Splitting the third clause
//   into its own file makes it look detachable from the other two, and detachable is exactly
//   what a future cleanup does to the clause it does not understand. One ruling, one battery.
//
// SOURCE-LEVEL BY NECESSITY: there is no runtime observation that distinguishes "this screen
// renders via closedAtLabel" from "this screen renders its own inline format" — both produce a
// string into HTML. `058`'s raise-site count and asOfBrand's cast-containment are the same class.
// ─────────────────────────────────────────────────────────────────────────────────────────

const SRC = fileURLToPath(new URL('../', import.meta.url)); // -> api/src/

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
 * Blank out comments, preserving line numbering so reported hits point at real lines.
 *
 * ⚑ NOT OPTIONAL, AND MEASURED: `closed_at` occurs in these files OVERWHELMINGLY IN PROSE —
 * the three surfaces carry long comment blocks explaining the closure model, and this very file
 * names both `closed_at` and `toLocaleDateString` in its own header. Without stripping, the
 * check matches the documentation written about it and reds on its own explanation. That is the
 * same self-match the asOfBrand battery hit on its first run; it is now the third occurrence of
 * the pattern in this suite, so it is treated as the default rather than as a surprise.
 */
function stripComments(src: string): string {
	const blank = (m: string) => m.replace(/[^\n]/g, ' ');
	return src
		.replace(/\/\*[\s\S]*?\*\//g, blank) // /* */
		.replace(/<!--[\s\S]*?-->/g, blank) // svelte markup comments
		.replace(/\/\/[^\n]*/g, blank); // //
}

/** Date-RENDERING APIs. `toISOString` is deliberately excluded — see the test body. */
const FORMAT_CALL = /toLocaleString|toLocaleDateString|toLocaleTimeString|Intl\.DateTimeFormat/;
const CLOSED_AT = /closed_?[aA]t/;

/** Files allowed to format a closure date. Exactly one, and that is the invariant. */
const FORMATTER = 'lib/account-display.ts';

describe('(T4) closure dates are formatted in exactly one place — ADR-043 all-three-or-none', () => {
	// PRECONDITION (same rule as T0): if the walk returns nothing — a moved directory, a changed
	// extension, a bad URL base — every assertion below passes over an empty set and reports a
	// clean invariant. Silent vacuity is what a source-scanning check has instead of a fixture.
	it('the source walk found the files it is scanning', () => {
		expect(FILES.length).toBeGreaterThan(100);
		expect(FILES.map(rel)).toContain(FORMATTER);
		// The three ADR-043 surfaces exist under the names the ruling names them by. If a route is
		// renamed this reds, which is correct: the ruling enumerates surfaces and must be re-read.
		for (const surface of [
			'routes/accounts/+page.svelte',
			'routes/accounts/[account_id]/+page.svelte',
			'routes/accounts/connections/[source_id]/+page.svelte'
		]) {
			expect(FILES.map(rel)).toContain(surface);
		}
	});

	// The three surfaces must actually route through the shared formatter. This is the POSITIVE
	// half — the negative half below cannot tell "renders via closedAtLabel" from "renders no
	// closure date at all", and a surface that silently stopped showing the date would satisfy
	// the negative while breaking the ruling.
	it('all three surfaces render through closedAtLabel', () => {
		for (const surface of [
			'routes/accounts/+page.svelte',
			'routes/accounts/[account_id]/+page.svelte',
			'routes/accounts/connections/[source_id]/+page.svelte'
		]) {
			const src = stripComments(readFileSync(join(SRC, surface), 'utf8'));
			expect({ surface, usesLabel: /closedAtLabel\s*\(/.test(src) }).toEqual({
				surface,
				usesLabel: true
			});
		}
	});

	// THE NEGATIVE HALF: nothing outside the formatter formats a closure date.
	//
	// PROXIMITY-SCOPED, and the window is the honest part of the design. A FILE-scoped check
	// (file mentions closed_at AND file formats a date) reds today on four legitimate files —
	// the two account schemas validate ISO strings, netWorth.ts derives the as-of, and
	// [account_id]/+page.svelte formats SYNC times via formatSyncTime — none of which touch a
	// closure date. A LINE-scoped check misses the variable hop. ±2 lines covers the inline
	// template expression and the immediate `const d = new Date(a.closed_at)` hop, which are the
	// two shapes the regression actually takes.
	//
	// `toISOString` is NOT in FORMAT_CALL: it is zone-invariant by definition, so it cannot
	// produce this defect, and including it would red on the schema validators for no gain.
	// A check that reds on correct code gets deleted, and it takes the real assertion with it.
	it('no closure date is formatted outside account-display.ts', () => {
		const WINDOW = 2;
		const offenders: string[] = [];

		for (const file of FILES) {
			const name = rel(file);
			if (name === FORMATTER || /\.(test|spec)\.ts$/.test(name)) continue;
			const lines = stripComments(readFileSync(file, 'utf8')).split('\n');
			lines.forEach((line, i) => {
				if (!FORMAT_CALL.test(line)) return;
				const from = Math.max(0, i - WINDOW);
				const near = lines.slice(from, i + WINDOW + 1).join('\n');
				if (CLOSED_AT.test(near)) offenders.push(`${name}:${i + 1}`);
			});
		}

		// Listed, not counted: a count says "zero" and tells the next reader nothing about WHERE.
		expect(offenders).toEqual([]);
	});
});
