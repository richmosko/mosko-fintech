// numeric.ts — CLIENT-SIDE mirror of the shared numeric-sanitization battery.
//
// MIRROR of src/lib/server/validation/numeric.ts (Lock 14 V1-SHIP-BLOCK Sec mod #2 — the
// numeric-input sanitization battery; mod #1 is the Zod `.strict()` mass-assignment fence at
// the endpoint, per SECURITY §4.5 RT-23).
// This is browser-shipped code, so it CANNOT import from src/lib/server/** (that
// surface never reaches the browser; Vite refuses the build). It is therefore a
// hand-kept parallel copy — the client check is UX fast-feedback ONLY; the SERVER
// battery is the security boundary. This mirror must never be LOOSER than the server
// one: same rejects, same thresholds, same message text. Backend owns the source of
// truth — when the server battery changes, update this copy in lockstep (api/CLAUDE.md
// Frontend conv).
//
// Rejects (identical to server, both consumers): NaN/Infinity, currency symbols,
// thousands commas, scientific/exponential notation, embedded whitespace/empty/
// non-string-non-number, unbounded input length, over-scale decimals, out-of-range
// integer-digit count, and (sanitizePercent only) the two-sided [0,100] range mirroring
// pfin.planning_target.target_percent's CHECK (074).
//
// REFACTORED (SELF-242) to the server's shared-core shape: SELF-233 added the server's
// second consumer, sanitizePercent, alongside the pre-existing sanitizeCurrencyAmount,
// via one parameterized `sanitizeDecimal` core + two thin DDL-shaped wrappers. This file
// now tracks that STRUCTURE, not just its output, so a future third numeric field adds a
// wrapper here too, never a new copy of the battery (mirrors server validation/README.md).
// sanitizeCurrencyAmount's behavior and messages are unchanged by this refactor.

/** Max integer digits for a Postgres numeric(20,4): 20 precision − 4 scale = 16. */
const MAX_INT_DIGITS = 16;
const MAX_DECIMAL_PLACES = 4;

/** Max integer digits for a Postgres numeric(5,2): 5 precision − 2 scale = 3. */
const PERCENT_MAX_INT_DIGITS = 3;
const PERCENT_MAX_DECIMAL_PLACES = 2;
/** Mirrors 074's two-sided `CHECK (target_percent >= 0 and target_percent <= 100)`. */
const PERCENT_MIN = 0;
const PERCENT_MAX = 100;

/** Max integer digits for a Postgres numeric(28,8): 28 precision − 8 scale = 20. Mirrors
 *  `017`'s `pfin.account_trans.quantity numeric(28,8)` — the SELF-325 purchase-path
 *  `p_quantity` argument (088) is written straight into this column. SHARE-COUNT SHAPE,
 *  not money: 8 decimal places (fractional-share / crypto grain) vs money's 4, and 20
 *  integer digits vs money's 16. Kept as its OWN wrapper rather than reusing
 *  `sanitizeCurrencyAmount` — collapsing the two would silently truncate a legitimate
 *  8-decimal quantity to 4 decimal places client-side while the server/DB accept it,
 *  producing a false "too many decimal places" rejection the server would not raise.
 *  ⚠ PROVISIONAL pending Backend's SELF-325 RPC-arg schema confirming the server-side
 *  shape — see purchase.ts EXPECTED CONTRACT note. */
const QUANTITY_MAX_INT_DIGITS = 20;
const QUANTITY_MAX_DECIMAL_PLACES = 8;

/**
 * Generous, shared, EXPLICIT input-length bound — well above any legitimate numeric
 * literal either wrapper accepts (numeric(20,4) tops out at a 22-character string: sign
 * + 16 int digits + '.' + 4 decimal digits). Checked first, before any regex touches the
 * string, so "the input is unbounded" is its own named rejection rather than a fact a
 * reader has to infer from the regexes happening to be linear.
 */
const MAX_INPUT_LENGTH = 64;

export type SanitizeResult = { ok: true; value: number } | { ok: false; reason: string };

type DecimalShape = {
	maxIntDigits: number;
	maxDecimalPlaces: number;
	/** Two-sided numeric range, mirroring a DB CHECK — independent of the digit-shape bound
	 *  above (a value can be digit-shape-valid and still be out of range, e.g. "500.00"
	 *  against a percent field: 3 digits fits the shape, 500 fails the range). */
	min?: number;
	max?: number;
};

/** Shared core — mirrors the server's `sanitizeDecimal`. Every named wrapper below calls
 *  this with an explicit, DDL-shaped `DecimalShape` rather than exposing raw options at the
 *  call site, so a call site can't accidentally invent a new shape inline. */
function sanitizeDecimal(raw: unknown, shape: DecimalShape): SanitizeResult {
	// Normalize to the string we will strictly validate. Numbers are re-stringified so
	// exponential-format values (1e21 → "1e+21") are caught by the same fence.
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

	// LENGTH CAP FIRST — before any regex below runs. See MAX_INPUT_LENGTH.
	if (s.length > MAX_INPUT_LENGTH) return { ok: false, reason: 'Input is too long.' };

	// Targeted diagnostics first (better UX than a single generic message).
	if (/[eE]/.test(s)) return { ok: false, reason: 'Scientific notation is not allowed.' };
	if (/[,]/.test(s)) return { ok: false, reason: 'Remove thousands separators (e.g. enter 1500.00).' };
	if (/[^\d.\-]/.test(s))
		return { ok: false, reason: 'Remove currency symbols and spaces (digits only, e.g. 1500.00).' };
	// INTENTIONAL BACKSTOP, unreachable under the current check order (mirrors the server's
	// own Sec-confirmed note): every spelling of "Infinity"/"NaN" contains a letter outside
	// `[\d.\-]` and is already caught by the character-class check one line above. Preserved
	// rather than removed — unreachability is a property of today's composition, not a
	// guaranteed invariant of this function's contract.
	if (/Infinity|NaN/i.test(s)) return { ok: false, reason: 'Enter a finite number.' };

	const strictDecimal = new RegExp(`^-?\\d{1,${shape.maxIntDigits}}(\\.\\d{1,${shape.maxDecimalPlaces}})?$`);
	if (!strictDecimal.test(s)) {
		const dot = s.indexOf('.');
		if (dot !== -1 && s.length - dot - 1 > shape.maxDecimalPlaces)
			return { ok: false, reason: `At most ${shape.maxDecimalPlaces} decimal places.` };
		return { ok: false, reason: 'Enter a valid number (e.g. 1500.00).' };
	}

	const intDigits = s.replace('-', '').split('.')[0];
	if (intDigits.length > shape.maxIntDigits) return { ok: false, reason: 'Amount is out of range.' };

	const value = Number(s);
	if (!Number.isFinite(value)) return { ok: false, reason: 'Enter a finite number.' };

	if (shape.min !== undefined && value < shape.min)
		return { ok: false, reason: `Enter a value of at least ${shape.min}.` };
	if (shape.max !== undefined && value > shape.max)
		return { ok: false, reason: `Enter a value of at most ${shape.max}.` };

	return { ok: true, value };
}

/**
 * Validate a user-supplied monetary/numeric input against the battery.
 * Accepts a raw form value (string) or a number. Returns a clean finite `number` fit for
 * numeric(20,4), or a rejection with a reason. Logic-identical to the server.
 */
export function sanitizeCurrencyAmount(raw: unknown): SanitizeResult {
	return sanitizeDecimal(raw, { maxIntDigits: MAX_INT_DIGITS, maxDecimalPlaces: MAX_DECIMAL_PLACES });
}

/**
 * Validate a user-supplied percent input against the battery, shaped to
 * pfin.planning_target.target_percent's own DDL (074): numeric(5,2), CHECK (>= 0 AND <=
 * 100). SELF-233 / RT-23 (Lock 14 mod #2) second consumer, mirrored here for SELF-242's
 * planning-target-editor. Same six adversarial categories as `sanitizeCurrencyAmount`
 * (NaN, Infinity, currency-string, regex-overflow, scientific-notation, locale-formatted),
 * plus the two-sided [0, 100] range the DB CHECK also enforces (defense-in-depth — this is
 * UX fast-feedback, never a replacement for the server battery or the DB CHECK).
 */
export function sanitizePercent(raw: unknown): SanitizeResult {
	return sanitizeDecimal(raw, {
		maxIntDigits: PERCENT_MAX_INT_DIGITS,
		maxDecimalPlaces: PERCENT_MAX_DECIMAL_PLACES,
		min: PERCENT_MIN,
		max: PERCENT_MAX
	});
}

/**
 * Validate a user-supplied share-quantity input, shaped to
 * `pfin.account_trans.quantity`'s own DDL (`017`): numeric(28,8). SELF-325 / 088
 * third consumer — the manual-purchase form's `quantity` field. Same adversarial
 * categories as the other two wrappers (NaN, Infinity, currency-string, regex-overflow,
 * scientific-notation, locale-formatted); 088 additionally requires quantity > 0 (a
 * purchase adds a positive quantity) — that positivity + the "derives to a 0.0000
 * per-unit price" ratio check are NOT part of this shape-only battery and are enforced
 * by the purchase schema's own `.refine()`s (purchase.ts), mirroring how
 * `positiveRatioComponent` layers a `> 0` refine on top of `currencyAmount()` in
 * schemas/transaction.ts.
 */
export function sanitizeQuantity(raw: unknown): SanitizeResult {
	return sanitizeDecimal(raw, {
		maxIntDigits: QUANTITY_MAX_INT_DIGITS,
		maxDecimalPlaces: QUANTITY_MAX_DECIMAL_PLACES
	});
}

/** Mirrors the SERVER's `FRACTION_RATE_*` constants (`src/lib/server/validation/numeric.ts`),
 *  shaped to `pfin.tax_bracket_row.bracket_rate` (migration 101): `numeric(12,8)`,
 *  `CHECK (bracket_rate >= 0 and bracket_rate <= 1 and bracket_rate <> 'NaN'::numeric)`. FRACTION
 *  unit (0.22, never 22) — SELF-259's ruling, cited at the migration: a fraction multiplies
 *  directly into the estimated-tax arithmetic, a percent needs a /100 at every call site. */
const FRACTION_RATE_MAX_INT_DIGITS = 4;
const FRACTION_RATE_MAX_DECIMAL_PLACES = 8;
const FRACTION_RATE_MIN = 0;
const FRACTION_RATE_MAX = 1;

/**
 * Validate a FRACTION-unit bracket rate (0.22, not 22) — SELF-265's client mirror of the
 * server's `sanitizeFractionRate` (tax-bracket-schedule.ts / bracketRowSchema). Same six
 * adversarial categories as every other wrapper in this file, plus the DB's own [0, 1] range.
 * This is the value the write endpoint actually stores and validates; `sanitizeBracketRatePercent`
 * below is the PRESENTATION-layer wrapper the editor's percent-typed input actually calls, and it
 * re-validates through this function so the client can never accept a converted value the server
 * would reject.
 */
export function sanitizeFractionRate(raw: unknown): SanitizeResult {
	return sanitizeDecimal(raw, {
		maxIntDigits: FRACTION_RATE_MAX_INT_DIGITS,
		maxDecimalPlaces: FRACTION_RATE_MAX_DECIMAL_PLACES,
		min: FRACTION_RATE_MIN,
		max: FRACTION_RATE_MAX
	});
}

/** Percent-shape bound for `sanitizeBracketRatePercent`'s FIRST pass: 3 integer digits (0-100)
 *  and 6 decimal places — the fraction column's 8 decimal places, shifted 2 places by the ×100
 *  presentation conversion (0.13300000 fraction <-> 13.3 percent). This is NOT a DB-mirrored
 *  shape (no column stores a percent) — it exists only so a shape-invalid percent string fails
 *  with a percent-flavored message before ever being divided by 100. */
const BRACKET_RATE_PERCENT_MAX_INT_DIGITS = 3;
const BRACKET_RATE_PERCENT_MAX_DECIMAL_PLACES = 6;
const BRACKET_RATE_PERCENT_MIN = 0;
const BRACKET_RATE_PERCENT_MAX = 100;

/**
 * PRESENTATION-LAYER wrapper for SELF-265's bracket-rate editor: `pfin.tax_bracket_row
 * .bracket_rate` is stored and validated as a FRACTION (101's ruling — see
 * `sanitizeFractionRate` above), but a settings editor asking a human to type "0.22" instead of
 * "22" is the wrong UX for a value published everywhere as a percent. This function accepts the
 * PERCENT string the field actually displays, validates its own shape (percent digit bounds),
 * converts to a fraction, and — never trusting the conversion alone — re-validates the result
 * through `sanitizeFractionRate`, the same check the payload's own field-level validation uses.
 * A percent input can therefore never produce a fraction this file would accept but the server's
 * mirror would reject: the fraction check is the one both paths share.
 * Returns the FRACTION `number` (never the percent) on success — the shape the `rows[]` payload
 * fields expect.
 */
export function sanitizeBracketRatePercent(raw: unknown): SanitizeResult {
	const shapeCheck = sanitizeDecimal(raw, {
		maxIntDigits: BRACKET_RATE_PERCENT_MAX_INT_DIGITS,
		maxDecimalPlaces: BRACKET_RATE_PERCENT_MAX_DECIMAL_PLACES,
		min: BRACKET_RATE_PERCENT_MIN,
		max: BRACKET_RATE_PERCENT_MAX
	});
	if (!shapeCheck.ok) return shapeCheck;
	// Round-trip through a fixed decimal string, not raw float division, so e.g. "13.3" / 100
	// never leaves float dust (0.13299999999999998) that a later exact-value comparison (the
	// zero-floor / monotonicity courtesy check) could trip on.
	const fraction = Number((shapeCheck.value / 100).toFixed(FRACTION_RATE_MAX_DECIMAL_PLACES));
	return sanitizeFractionRate(fraction);
}

/** Converts a stored FRACTION rate to the percent string the editor displays (0.133 -> "13.3").
 *  Inverse of `sanitizeBracketRatePercent`'s conversion half. Trims float noise the same way
 *  (fixed-decimal round-trip, not raw multiplication display) and drops trailing zeros / a
 *  trailing decimal point so "0.10" reads as "10", not "10.000000". */
export function fractionRateToPercentDisplay(fraction: number): string {
	const pct = Number((fraction * 100).toFixed(BRACKET_RATE_PERCENT_MAX_DECIMAL_PLACES));
	return String(pct);
}
