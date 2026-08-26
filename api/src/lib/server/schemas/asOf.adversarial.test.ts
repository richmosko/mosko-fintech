// asOf.adversarial.test.ts — QA-owned. SELF-247 AC7's adversarial battery + the sitting-item-12
// §2.2 merged-surface watcher (deferred to the schema boundary per team-lead ruling,
// default-and-notify / ADR-063, F/CTO reversal window open until PR ratify) + the two-clock
// no-embedded-clock determinism guard (12a: "any `new Date()` inside the validator is a defect").
//
// COMPLEMENTS asOf.test.ts (Backend's own AC1-4 module-contract coverage: absent/malformed/
// mass-assignment, basic NaN/Infinity/overlong, both inclusive boundaries, per-call ceiling
// injection) rather than duplicating it. This file's distinct value:
//   1. the WIDER adversarial input-class battery AC7 names — injection-shaped, type-coerced,
//      locale-formatted, non-date garbage — asserting the SELF-233 structured field-level error
//      SHAPE via `fieldErrors()` (schemas/account.ts's shared flattener), not just success:false;
//   2. the sitting item 12 §2.2 watcher, explicitly labeled schema-boundary-only — see the
//      describe block below for what it does and does not prove, and
//      temp/self247-tension-route-leg.md for the full writeup this deferral is drawn from;
//   3. the no-internal-clock-read determinism guard under a shifted system clock.

import { describe, it, expect, vi, afterEach } from 'vitest';
import { asOfSchema, AS_OF_FLOOR } from './asOf';
import { fieldErrors } from './account';
import { unsafeAsOfForTest } from '$lib/server/time/asOf';

// Fixed injected ceiling for every test that isn't specifically exercising the ceiling boundary
// or the two-clock guard. Never `new Date()` here — see asOf.ts's own header on why.
const D = unsafeAsOfForTest('2026-08-25');

describe('asOfSchema — AC7 adversarial battery (structured field-level error SHAPE, not just rejection)', () => {
	const rejected: Array<[string, unknown]> = [
		['negative-shaped date string', '-2026-08-25'],
		['one day beyond D (future)', '2026-08-26'],
		['far future', '2099-01-01'],
		['one day before the floor (out-of-range past)', '2015-11-30'],
		['far out-of-range past', '1900-01-01'],
		['non-date garbage', 'not-a-date'],
		['SQL-injection-shaped, statement-terminating', "2026-08-25'; DROP TABLE pfin.account_trans; --"],
		['SQL-injection-shaped, tautology', "' OR '1'='1"],
		['type-coerced: number', 20260825],
		['type-coerced: array', ['2026-08-25']],
		['type-coerced: object', { as_of: '2026-08-25' }],
		['type-coerced: boolean', true],
		['type-coerced: null', null],
		['locale-formatted: US slash (MM/DD/YYYY)', '08/25/2026'],
		['locale-formatted: EU dot (DD.MM.YYYY)', '25.08.2026'],
		['locale-formatted: EU slash (DD/MM/YYYY)', '25/08/2026'],
		['timestamp, not a bare date', '2026-08-25T00:00:00Z'],
		['literal NaN text', 'NaN'],
		['literal Infinity text', 'Infinity'],
		['empty string', '']
	];

	for (const [label, input] of rejected) {
		it(`rejects ${label}, with a field-level error attached to as_of`, () => {
			const r = asOfSchema(D).safeParse({ as_of: input });
			expect(r.success).toBe(false);
			if (r.success) return;
			const errs = fieldErrors(r.error);
			// SHAPE, not just rejection: a field-level key, a non-empty array, string messages.
			expect(errs.as_of).toBeDefined();
			expect(Array.isArray(errs.as_of)).toBe(true);
			expect(errs.as_of.length).toBeGreaterThan(0);
			expect(typeof errs.as_of[0]).toBe('string');
			expect(errs.as_of[0].length).toBeGreaterThan(0);
		});
	}
});

// ── §2.2 route watcher leg — sitting item 12's ruled clause ("...one QA watcher leg on the
//    merged §2.2 route (reject pre-floor + future)"), DELIBERATELY BUILT AT THE SCHEMA BOUNDARY
//    INSTEAD, per team-lead ruling (default-and-notify, ADR-063 — F/CTO reversal window open
//    until PR ratify; this deviation from item 12's letter is not a silent resolution).
//
//    WHY: no route in SELF-247's scope wires a client-supplied `as_of` — all four route loaders
//    call `serverTodayAsOf()` unconditionally, and `allocation/+page.server.ts` states in-file
//    that no as_of query-param is supported yet (confirmed in Backend's a08b2d1 commit message:
//    "No route wires client-supplied as_of in this PR"). A literal route-level HTTP leg is not
//    buildable against what ships in this PR without either (a) faking a route call around the
//    schema — not a real route observation — or (b) actually wiring the query param, which is
//    out of THIS PR's scope fence and would set the BACKLOG §7.25 item 3 route-coverage
//    precedent BY ACCIDENT — the two things sitting item 12a's decoupling ruling exists to
//    prevent.
//
//    WHAT THIS LEG PROVES: the SHARED schema — the one §2.2's loaders will consume once the
//    param is wired — enforces the D-6 bound NOW, pre-emptively (Architect's corrected framing:
//    "harmless while unreachable; a fence gap the moment the query param is wired").
//    WHAT IT DOES NOT PROVE: that `/allocation` rejects anything today. It cannot — the route
//    does not call this schema. Do not read this leg as route-level coverage.
//    Route-level coverage, when it is deliberately built, is BACKLOG §7.25 item 3's job — see
//    temp/self247-tension-route-leg.md (QA, this worktree) for the full writeup.
describe('asOfSchema — §2.2 merged-surface watcher (schema-boundary only — route-level coverage deferred to §7.25 item 3)', () => {
	it('rejects one day before AS_OF_FLOOR (pre-floor)', () => {
		const r = asOfSchema(D).safeParse({ as_of: '2015-11-30' });
		expect(r.success).toBe(false);
	});

	it('rejects one day after D (future)', () => {
		const r = asOfSchema(D).safeParse({ as_of: '2026-08-26' });
		expect(r.success).toBe(false);
	});

	it('accepts exactly AS_OF_FLOOR (inclusive lower bound — an off-by-one here silently refuses the earliest legitimate as-of)', () => {
		const r = asOfSchema(D).safeParse({ as_of: AS_OF_FLOOR });
		expect(r.success).toBe(true);
	});

	it("accepts exactly D (inclusive upper bound — an off-by-one here silently refuses today's own as-of)", () => {
		const r = asOfSchema(D).safeParse({ as_of: D });
		expect(r.success).toBe(true);
	});
});

// ── Two-clock guard: the factory must perform NO clock read of its own. Determinism under a
//    shifted system clock proves the ceiling is INJECTED, not embedded (12a's named hazard: a
//    `.max(new Date())`-shaped implementation would reopen ADR-044's two-clock hazard with up to
//    ~26h of boundary-day disagreement). A future edit that sneaks a system-clock read into the
//    factory's own ceiling logic must go RED here.
//
//    NOTE: `asOf.ts`'s `isoDate()` legitimately contains one argument-carrying
//    `new Date(`${s}T00:00:00Z`)` for shape/round-trip parsing of the CANDIDATE string — that use
//    never derives "today" and is not what this guard targets. The guard asserts determinism
//    under a shifted clock, not the absence of every `new Date()` token.
describe('asOfSchema — two-clock guard (no internal system-clock read)', () => {
	// Belt-and-suspenders: every `it` below restores real timers itself before returning, but a
	// thrown assertion mid-test would leave fake timers active for the next test in this file.
	// vitest's `afterEach` runs even when the preceding test throws.
	afterEach(() => {
		vi.useRealTimers();
	});

	it('validation of a fixed injected D is unchanged whether the system clock reads 26h earlier or later', () => {
		const fixedInput = { as_of: '2026-08-25' };

		vi.useFakeTimers();
		vi.setSystemTime(new Date('2026-08-24T00:00:00Z')); // system clock 26h behind D's "today"
		const before = asOfSchema(D).safeParse(fixedInput).success;

		vi.setSystemTime(new Date('2026-08-26T02:00:00Z')); // system clock ~26h ahead
		const after = asOfSchema(D).safeParse(fixedInput).success;

		vi.useRealTimers();

		expect(before).toBe(true);
		expect(after).toBe(true);
	});

	it('the strong discriminator: a date between D and a shifted-ahead system clock is still ACCEPTED — a `new Date()`-based ceiling would wrongly reject it', () => {
		const nearCeilingD = unsafeAsOfForTest('2026-08-20');

		vi.useFakeTimers();
		vi.setSystemTime(new Date('2026-08-25T00:00:00Z')); // system clock 5 days ahead of D
		// 2026-08-22 is > D (2026-08-20) but < the shifted "now" (2026-08-25). A validator that
		// (incorrectly) bounds against `new Date()` would ACCEPT this; the injected-D contract
		// requires it be REJECTED, because it is future-relative to D.
		const r = asOfSchema(nearCeilingD).safeParse({ as_of: '2026-08-22' });
		vi.useRealTimers();

		expect(r.success).toBe(false);
	});
});
