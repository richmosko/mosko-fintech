// taxBracketRows.test.ts — courtesy row-ordering mirror test (SELF-265). Mirrors the write
// endpoint's own `precheckRowOrdering` legs (Leg A zero-floor, Leg B rate monotonicity — R4
// rider 8 item 5 / AC5). NOTE: TaxBracketScheduleEditor.svelte structurally fixes the first
// row's floor at 0 (a disabled field, never user-editable — see that component's own header),
// so the zero-floor leg can never actually fire through that component's rendered UI; it is
// tested here directly against the shared validation module instead, which is where the
// property is actually encoded and where a future consumer without that structural guard would
// need it to still hold.

import { describe, it, expect } from 'vitest';
import { precheckRowOrdering, type BracketRowInput } from './taxBracketRows';

describe('precheckRowOrdering — Leg A (zero floor)', () => {
	it('accepts a schedule whose lowest floor is exactly 0', () => {
		const rows: BracketRowInput[] = [
			{ bracket_floor: 0, bracket_rate: 0.1 },
			{ bracket_floor: 11000, bracket_rate: 0.22 }
		];
		expect(precheckRowOrdering(rows)).toEqual({ ok: true });
	});

	it('rejects a schedule whose lowest floor is non-zero — monotonicity alone cannot catch this', () => {
		const rows: BracketRowInput[] = [
			{ bracket_floor: 11000, bracket_rate: 0.1 },
			{ bracket_floor: 44000, bracket_rate: 0.22 }
		];
		expect(precheckRowOrdering(rows)).toEqual({
			ok: false,
			reason: 'The lowest bracket must start at 0.'
		});
	});

	it('rejects an empty row set (this app-layer bound; the DB itself treats empty as the cleared/unset intermediate state)', () => {
		expect(precheckRowOrdering([])).toEqual({
			ok: false,
			reason: 'At least one bracket row is required.'
		});
	});
});

describe('precheckRowOrdering — Leg B (rate monotonicity, non-decreasing)', () => {
	it('accepts non-decreasing rates as floors ascend', () => {
		const rows: BracketRowInput[] = [
			{ bracket_floor: 0, bracket_rate: 0.1 },
			{ bracket_floor: 11000, bracket_rate: 0.1 }, // equal rate — allowed (non-decreasing, not strict)
			{ bracket_floor: 44000, bracket_rate: 0.22 }
		];
		expect(precheckRowOrdering(rows)).toEqual({ ok: true });
	});

	it('rejects a rate that decreases as the floor rises', () => {
		const rows: BracketRowInput[] = [
			{ bracket_floor: 0, bracket_rate: 0.22 },
			{ bracket_floor: 11000, bracket_rate: 0.1 }
		];
		expect(precheckRowOrdering(rows)).toEqual({
			ok: false,
			reason: 'Bracket rates must not decrease as thresholds rise.'
		});
	});
});

describe('precheckRowOrdering — floor strictness (subsumes duplicate-floor detection)', () => {
	it('rejects two rows sharing the same floor — `<=` comparison, matching 101’s unique (schedule_id, bracket_floor)', () => {
		const rows: BracketRowInput[] = [
			{ bracket_floor: 0, bracket_rate: 0.1 },
			{ bracket_floor: 0, bracket_rate: 0.22 }
		];
		expect(precheckRowOrdering(rows)).toEqual({
			ok: false,
			reason: 'Bracket thresholds must strictly increase, in order.'
		});
	});

	it('rejects a floor that decreases (out-of-order submission) — stricter than the DB, which sorts internally', () => {
		const rows: BracketRowInput[] = [
			{ bracket_floor: 0, bracket_rate: 0.1 },
			{ bracket_floor: 44000, bracket_rate: 0.22 },
			{ bracket_floor: 11000, bracket_rate: 0.24 }
		];
		expect(precheckRowOrdering(rows)).toEqual({
			ok: false,
			reason: 'Bracket thresholds must strictly increase, in order.'
		});
	});
});
