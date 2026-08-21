// numeric.test.ts — client mirror parity test (SELF-242). Asserts this file's
// sanitizeCurrencyAmount/sanitizePercent behave identically to the server battery
// (src/lib/server/validation/numeric.test.ts is the canonical source these mirror; kept
// in lockstep per api/CLAUDE.md Frontend conv — a looser client mirror is the ship-block
// this test exists to catch). The six adversarial categories (NaN, Infinity,
// currency-string, regex-overflow, scientific-notation, locale-formatted) are asserted
// against BOTH wrappers, since both wrap the same core.

import { describe, it, expect } from 'vitest';
import { sanitizeCurrencyAmount, sanitizePercent, sanitizeQuantity } from './numeric';

describe('sanitizeCurrencyAmount — SELF-201 regression baseline (numeric(20,4), no range)', () => {
	it('accepts a clean decimal string', () => {
		expect(sanitizeCurrencyAmount('1500.00')).toEqual({ ok: true, value: 1500 });
	});

	it('accepts a negative amount (signed ledger convention)', () => {
		expect(sanitizeCurrencyAmount('-54.32')).toEqual({ ok: true, value: -54.32 });
	});

	it('accepts a finite number (client-mirror path)', () => {
		expect(sanitizeCurrencyAmount(12)).toEqual({ ok: true, value: 12 });
	});
});

describe.each([
	['sanitizeCurrencyAmount', sanitizeCurrencyAmount],
	['sanitizePercent', sanitizePercent],
	['sanitizeQuantity', sanitizeQuantity]
] as const)('%s — six-category adversarial battery', (_name, sanitize) => {
	it('rejects NaN (literal number)', () => {
		expect(sanitize(NaN).ok).toBe(false);
	});

	it('rejects NaN (string)', () => {
		expect(sanitize('NaN').ok).toBe(false);
	});

	it('rejects Infinity / -Infinity (literal number)', () => {
		expect(sanitize(Infinity).ok).toBe(false);
		expect(sanitize(-Infinity).ok).toBe(false);
	});

	it('rejects Infinity (string)', () => {
		expect(sanitize('Infinity').ok).toBe(false);
	});

	it('rejects a currency-string (symbol + input)', () => {
		expect(sanitize('$1,500.00').ok).toBe(false);
	});

	it('rejects thousands-separator locale formatting', () => {
		expect(sanitize('1,500').ok).toBe(false);
	});

	it('rejects scientific notation', () => {
		expect(sanitize('1e3').ok).toBe(false);
	});

	it('rejects embedded whitespace / empty string', () => {
		expect(sanitize('').ok).toBe(false);
		expect(sanitize('   ').ok).toBe(false);
	});

	it('rejects a non-string non-number', () => {
		expect(sanitize({ amount: 5 }).ok).toBe(false);
		expect(sanitize(null).ok).toBe(false);
		expect(sanitize(undefined).ok).toBe(false);
	});

	it('rejects an over-length input before any regex runs', () => {
		expect(sanitize('1'.repeat(65)).ok).toBe(false);
	});
});

describe('sanitizePercent — numeric(5,2) CHECK (0..100), 074 shape', () => {
	it('accepts an in-range value', () => {
		expect(sanitizePercent('12.5')).toEqual({ ok: true, value: 12.5 });
	});

	it('accepts the boundaries', () => {
		expect(sanitizePercent('0')).toEqual({ ok: true, value: 0 });
		expect(sanitizePercent('0.00')).toEqual({ ok: true, value: 0 });
		expect(sanitizePercent('100')).toEqual({ ok: true, value: 100 });
		expect(sanitizePercent('100.00')).toEqual({ ok: true, value: 100 });
	});

	it('accepts up to 2 decimal places', () => {
		expect(sanitizePercent('33.33')).toEqual({ ok: true, value: 33.33 });
	});

	it('rejects a negative value (digit-shape valid, range invalid)', () => {
		expect(sanitizePercent('-5')).toEqual({ ok: false, reason: 'Enter a value of at least 0.' });
	});

	it('rejects > 100 even when digit-shape-valid (e.g. 3-digit values under 1000)', () => {
		expect(sanitizePercent('500.00')).toEqual({ ok: false, reason: 'Enter a value of at most 100.' });
		expect(sanitizePercent('100.01')).toEqual({ ok: false, reason: 'Enter a value of at most 100.' });
	});

	it('rejects 3 decimal places (numeric(5,2) scale)', () => {
		expect(sanitizePercent('12.345')).toEqual({ ok: false, reason: 'At most 2 decimal places.' });
	});

	it('rejects 4+ integer digits (numeric(5,2) precision, independent of the 0..100 range)', () => {
		expect(sanitizePercent('1000.00').ok).toBe(false);
	});
});

describe('sanitizeQuantity — numeric(28,8) shape (017 pfin.account_trans.quantity; SELF-325 / 088)', () => {
	it('accepts a whole-share quantity', () => {
		expect(sanitizeQuantity('100')).toEqual({ ok: true, value: 100 });
	});

	it('accepts up to 8 decimal places (fractional-share / crypto grain)', () => {
		expect(sanitizeQuantity('0.12345678')).toEqual({ ok: true, value: 0.12345678 });
	});

	it('rejects 9+ decimal places — the property currency/percent do NOT share (their scale is 4/2)', () => {
		expect(sanitizeQuantity('1.123456789')).toEqual({
			ok: false,
			reason: 'At most 8 decimal places.'
		});
	});

	it('a value with 5 decimal places is ACCEPTED here but would be REJECTED by sanitizeCurrencyAmount — proves this is its own shape, not a re-skin', () => {
		expect(sanitizeQuantity('1.12345').ok).toBe(true);
		expect(sanitizeCurrencyAmount('1.12345').ok).toBe(false);
	});

	it('accepts up to 20 integer digits (numeric(28,8): 28-8=20) — beyond currency amount’s 16-digit bound', () => {
		expect(sanitizeQuantity('1'.repeat(20)).ok).toBe(true);
		expect(sanitizeQuantity('1'.repeat(21)).ok).toBe(false);
	});

	it('has no built-in positivity/range floor — 0 and negatives pass the SHAPE battery (088’s own > 0 refine is a separate layer, mirrored in schemas/purchase.ts)', () => {
		expect(sanitizeQuantity('0')).toEqual({ ok: true, value: 0 });
		expect(sanitizeQuantity('-5')).toEqual({ ok: true, value: -5 });
	});
});
