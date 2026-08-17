// numeric.test.ts — SELF-233 coverage for the shared numeric-sanitization battery
// (Lock 14 V1-SHIP-BLOCK mod #2). Covers BOTH exported sanitizers against one shared core:
// `sanitizeCurrencyAmount` (SELF-201, numeric(20,4)) had no prior direct unit coverage — this
// file also establishes that regression baseline — and `sanitizePercent` (SELF-233,
// numeric(5,2) bounded [0,100]). The six adversarial categories (NaN, Infinity,
// currency-string, regex-overflow, scientific-notation, locale-formatted) are asserted
// against BOTH, since both wrap the same core.

import { describe, it, expect } from 'vitest';
import { sanitizeCurrencyAmount, sanitizePercent } from './numeric';

describe('sanitizeCurrencyAmount — SELF-201 regression baseline (numeric(20,4), no range)', () => {
	it('accepts a clean decimal string', () => {
		const r = sanitizeCurrencyAmount('1500.00');
		expect(r).toEqual({ ok: true, value: 1500 });
	});

	it('accepts a negative amount (signed ledger convention)', () => {
		const r = sanitizeCurrencyAmount('-54.32');
		expect(r).toEqual({ ok: true, value: -54.32 });
	});

	it('accepts a finite number (client-mirror path)', () => {
		expect(sanitizeCurrencyAmount(12)).toEqual({ ok: true, value: 12 });
	});

	it('accepts up to 16 integer digits / 4 decimal places (numeric(20,4) fit)', () => {
		expect(sanitizeCurrencyAmount('9999999999999999.9999').ok).toBe(true);
	});

	it('rejects 17 integer digits (out of numeric(20,4) range)', () => {
		// The anchored regex already bounds int digits to {1,16}, so a 17-digit string never
		// matches it — this falls through to the generic "not a valid number" branch rather
		// than the separate intDigits.length check (which is consequently unreachable for
		// EVERY digit-count overflow; pre-existing property, unchanged by SELF-233).
		const r = sanitizeCurrencyAmount('99999999999999999');
		expect(r).toEqual({ ok: false, reason: 'Enter a valid number (e.g. 1500.00).' });
	});

	it('rejects 5 decimal places', () => {
		const r = sanitizeCurrencyAmount('1.23456');
		expect(r).toEqual({ ok: false, reason: 'At most 4 decimal places.' });
	});

	it('rejects empty string', () => {
		expect(sanitizeCurrencyAmount('')).toEqual({ ok: false, reason: 'Enter an amount.' });
	});

	it('rejects non-string/non-number input', () => {
		expect(sanitizeCurrencyAmount(null)).toEqual({ ok: false, reason: 'Invalid amount.' });
		expect(sanitizeCurrencyAmount(undefined)).toEqual({ ok: false, reason: 'Invalid amount.' });
		expect(sanitizeCurrencyAmount({})).toEqual({ ok: false, reason: 'Invalid amount.' });
		expect(sanitizeCurrencyAmount([])).toEqual({ ok: false, reason: 'Invalid amount.' });
	});
});

/** The six adversarial categories, parameterized over both sanitizers. Each `bad` case must
 *  reject; the exact reason string is asserted separately per-sanitizer above/below where the
 *  boundary itself (not just the category) matters. */
describe.each([
	['sanitizeCurrencyAmount', sanitizeCurrencyAmount],
	['sanitizePercent', sanitizePercent]
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
		expect(sanitize('-Infinity').ok).toBe(false);
	});

	it('rejects currency-string input ($, €, £, ¥, symbols)', () => {
		expect(sanitize('$50').ok).toBe(false);
		expect(sanitize('€50').ok).toBe(false);
		expect(sanitize('£50').ok).toBe(false);
		expect(sanitize('¥50').ok).toBe(false);
	});

	it('rejects regex-overflow: input longer than the explicit length cap', () => {
		const overflow = '9'.repeat(1000);
		expect(sanitize(overflow)).toEqual({ ok: false, reason: 'Input is too long.' });
	});

	it('rejects scientific / exponential notation', () => {
		expect(sanitize('1e5').ok).toBe(false);
		expect(sanitize('1E-3').ok).toBe(false);
		expect(sanitize('5e2').ok).toBe(false);
	});

	it('rejects locale-formatted input (thousands-grouped / non-en-US decimal comma)', () => {
		expect(sanitize('1,500.00').ok).toBe(false); // en-US thousands grouping
		expect(sanitize('1.500,00').ok).toBe(false); // de-DE grouping+decimal swap
		expect(sanitize('1 500,00').ok).toBe(false); // fr-FR space grouping + decimal comma
	});

	it('rejects embedded whitespace / non-string-non-number', () => {
		expect(sanitize('12 34').ok).toBe(false);
		expect(sanitize(null).ok).toBe(false);
		expect(sanitize({}).ok).toBe(false);
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
		const r = sanitizePercent('1000.00');
		expect(r.ok).toBe(false);
	});
});
