// numeric.ts — shared numeric-sanitization battery (Lock 14 V1-SHIP-BLOCK Sec mod #1).
//
// The security discipline is REJECT, not coerce-by-stripping: a value that is not
// already a clean decimal is refused, never silently "cleaned" into one. This is the
// mass-assignment / type-confusion fence for every server-side numeric boundary
// (initial account value here; tax brackets, cash-flow amounts, etc. later).
//
// Rejects, each with a targeted reason for field-error mapping:
//   - NaN / Infinity / -Infinity (literal or parsed)
//   - currency strings ($, €, £, ¥, and any non-digit symbol)
//   - thousands separators (comma)
//   - scientific / exponential notation (1e5, 1E-3)
//   - embedded whitespace, empty, non-string/non-number
//   - > 4 decimal places or > 16 integer digits (out of numeric(20,4) range)
//
// SELF-201 is the first consumer (per Lock 14). Kept framework-agnostic (no Zod
// import) so it is unit-testable in isolation; the Zod adapter lives in schemas/.

/** Max integer digits for a Postgres numeric(20,4): 20 precision − 4 scale = 16. */
const MAX_INT_DIGITS = 16;
const MAX_DECIMAL_PLACES = 4;

/** Strict decimal: optional sign, 1–16 integer digits, optional .1–4 fractional digits. */
const STRICT_DECIMAL = /^-?\d{1,16}(\.\d{1,4})?$/;

export type SanitizeResult =
	| { ok: true; value: number }
	| { ok: false; reason: string };

/**
 * Validate a user-supplied monetary/numeric input against the battery.
 * Accepts a raw form value (string) or a number (client-mirror path). Returns a
 * clean finite `number` fit for numeric(20,4), or a rejection with a reason.
 */
export function sanitizeCurrencyAmount(raw: unknown): SanitizeResult {
	// Normalize to the string we will strictly validate. Numbers are re-stringified
	// so exponential-format values (1e21 → "1e+21") are caught by the same fence.
	let s: string;
	if (typeof raw === 'number') {
		if (!Number.isFinite(raw)) return { ok: false, reason: 'Enter a finite number.' };
		s = String(raw);
	} else if (typeof raw === 'string') {
		s = raw.trim();
	} else {
		return { ok: false, reason: 'Invalid amount.' };
	}

	if (s === '') return { ok: false, reason: 'Enter an amount.' };

	// Targeted diagnostics first (better UX than a single generic message).
	if (/[eE]/.test(s)) return { ok: false, reason: 'Scientific notation is not allowed.' };
	if (/[,]/.test(s)) return { ok: false, reason: 'Remove thousands separators (e.g. enter 1500.00).' };
	if (/[^\d.\-]/.test(s))
		return { ok: false, reason: 'Remove currency symbols and spaces (digits only, e.g. 1500.00).' };
	if (/Infinity|NaN/i.test(s)) return { ok: false, reason: 'Enter a finite number.' };

	if (!STRICT_DECIMAL.test(s)) {
		// Distinguish scale-vs-range for a clearer message where possible.
		const dot = s.indexOf('.');
		if (dot !== -1 && s.length - dot - 1 > MAX_DECIMAL_PLACES)
			return { ok: false, reason: `At most ${MAX_DECIMAL_PLACES} decimal places.` };
		return { ok: false, reason: 'Enter a valid number (e.g. 1500.00).' };
	}

	// Range fence: integer-digit count must fit numeric(20,4).
	const intDigits = s.replace('-', '').split('.')[0];
	if (intDigits.length > MAX_INT_DIGITS)
		return { ok: false, reason: 'Amount is out of range.' };

	const value = Number(s);
	if (!Number.isFinite(value)) return { ok: false, reason: 'Enter a finite number.' };

	return { ok: true, value };
}
