// scheduleLabel.test.ts — client mirror test (SELF-265) for the schedule_label posture
// ($lib/server/schemas/tax-bracket-schedule.ts's `scheduleLabel()` — migration 101's
// tax_bracket_schedule_schedule_label_check).

import { describe, it, expect } from 'vitest';
import { sanitizeScheduleLabel } from './scheduleLabel';

describe('sanitizeScheduleLabel', () => {
	it('accepts a normal label', () => {
		expect(sanitizeScheduleLabel('Single filer, 2026 IRS Schedule X')).toEqual({
			ok: true,
			value: 'Single filer, 2026 IRS Schedule X'
		});
	});

	it('trims leading/trailing ASCII whitespace before measuring length and storing', () => {
		expect(sanitizeScheduleLabel('  Single filer  ')).toEqual({ ok: true, value: 'Single filer' });
	});

	it('rejects an empty string after trim (the degenerate whitespace-only case included)', () => {
		expect(sanitizeScheduleLabel('').ok).toBe(false);
		expect(sanitizeScheduleLabel('   ').ok).toBe(false);
	});

	it('accepts the seeded 473-character California label at the 500-character bound (E29)', () => {
		const label = 'A'.repeat(473);
		expect(sanitizeScheduleLabel(label)).toEqual({ ok: true, value: label });
	});

	it('accepts exactly 500 characters and rejects 501', () => {
		expect(sanitizeScheduleLabel('A'.repeat(500)).ok).toBe(true);
		expect(sanitizeScheduleLabel('A'.repeat(501))).toEqual({
			ok: false,
			reason: 'Schedule label is too long (500 characters max).'
		});
	});

	it('rejects an interior control character (e.g. an embedded tab)', () => {
		expect(sanitizeScheduleLabel('Single\tfiler').ok).toBe(false);
	});

	it('rejects a non-string value', () => {
		expect(sanitizeScheduleLabel(42).ok).toBe(false);
		expect(sanitizeScheduleLabel(null).ok).toBe(false);
	});
});
