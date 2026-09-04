// numeric.ts — shared numeric-sanitization battery (Lock 14 V1-SHIP-BLOCK Sec mod #2).
//
// The security discipline is REJECT, not coerce-by-stripping: a value that is not
// already a clean decimal is refused, never silently "cleaned" into one. This is the
// mass-assignment / type-confusion fence for every server-side numeric boundary.
//
// Rejects, each with a targeted reason for field-error mapping:
//   - NaN / Infinity / -Infinity (literal or parsed)
//   - currency strings ($, €, £, ¥, and any non-digit symbol) — "locale-formatted"
//     input (thousands-grouped, non-en-US decimal comma, etc.) is refused the same way:
//     anything that is not already a plain `-?digits(.digits)?` string is rejected, never
//     locale-parsed.
//   - thousands separators (comma)
//   - scientific / exponential notation (1e5, 1E-3)
//   - embedded whitespace, empty, non-string/non-number
//   - input longer than MAX_INPUT_LENGTH (explicit, testable bound — checked BEFORE any
//     regex runs against the string; the regexes below are already linear/anchored and
//     not ReDoS-able, but the cap makes "unbounded input" a rejected category in its own
//     right rather than an incidental side-effect of the shape check)
//   - out-of-range for the target's own DDL shape (integer-digit count / decimal places,
//     and — where the caller supplies one — a two-sided numeric range, mirroring a DB CHECK)
//
// SELF-201 is the first consumer (`sanitizeCurrencyAmount`, numeric(20,4) — account /
// transaction amounts). SELF-233 (Lock 14 / RT-23) is the second: `sanitizePercent`,
// numeric(5,2) bounded [0,100] — pfin.planning_target.target_percent (074). Both are thin,
// message-preserving wrappers over one parameterized core (`sanitizeDecimal`) so the same
// adversarial battery (NaN, Infinity, currency-string, regex-overflow, scientific-notation,
// locale-formatted) is enforced identically at every numeric boundary. A future numeric
// field (e.g. V1.4 tax-bracket amounts, RT-24) adds a new thin wrapper — see README.md in
// this directory — never a new copy of the battery.
//
// Kept framework-agnostic (no Zod import) so it is unit-testable in isolation; the Zod
// adapter lives in schemas/ (one per surface — see e.g. schemas/account.ts, schemas/
// planning-target.ts).

/** Max integer digits for a Postgres numeric(20,4): 20 precision − 4 scale = 16. */
const MAX_INT_DIGITS = 16;
const MAX_DECIMAL_PLACES = 4;

/** Max integer digits for a Postgres numeric(5,2): 5 precision − 2 scale = 3. */
const PERCENT_MAX_INT_DIGITS = 3;
const PERCENT_MAX_DECIMAL_PLACES = 2;
/** Mirrors 074's two-sided `CHECK (target_percent >= 0 and target_percent <= 100)`. */
const PERCENT_MIN = 0;
const PERCENT_MAX = 100;

/** Max integer digits/decimal places for the PROPOSED `pfin.tax_bracket_row.bracket_rate`
 *  shape (SELF-259 / R4 rider 4 / Sec M-7) — a FRACTION unit (0.22, never 22), two-sided
 *  CHECK [0, 1] per R4 rider 8 item (ii). ⚠ `102`/migration-101's DDL has not landed as of this
 *  file's authorship (Architect owns it in parallel, feature/self-259) — this shape is a
 *  Backend PROPOSAL to reconcile against the pushed precision/scale once known, not a
 *  transcription of ratified DDL. Re-read the migration before trusting these constants. */
const FRACTION_RATE_MAX_INT_DIGITS = 1;
const FRACTION_RATE_MAX_DECIMAL_PLACES = 4;
const FRACTION_RATE_MIN = 0;
const FRACTION_RATE_MAX = 1;

/** Max integer digits for a Postgres numeric(28,8): 28 precision − 8 scale = 20. Shapes
 *  `pfin.account_trans.quantity` (017). No `min`/`max` here — the column itself carries no DB
 *  CHECK range, so there is no inclusive bound to mirror (unlike `sanitizePercent`'s 074 CHECK).
 *  The strict positivity `fn_create_manual_purchase` (088) requires is layered on top by the Zod
 *  adapter's own `.refine((n) => n > 0, ...)` — the same shape as `transaction.ts`'s
 *  `positiveRatioComponent()` — never folded into this shape's `min`, because `sanitizeDecimal`'s
 *  `min` is inclusive (`value < min` rejects) and would wrongly admit exactly `0`. */
const QUANTITY_MAX_INT_DIGITS = 20;
const QUANTITY_MAX_DECIMAL_PLACES = 8;

/**
 * Generous, shared, EXPLICIT input-length bound — well above any legitimate numeric
 * literal this module accepts (numeric(20,4) tops out at a 22-character string: sign +
 * 16 int digits + '.' + 4 decimal digits). Checked first, before any regex touches the
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

/**
 * The one parameterized core every exported sanitizer wraps. Not exported — callers get a
 * named, DDL-shaped function (`sanitizeCurrencyAmount`, `sanitizePercent`, ...) rather than
 * a bag of options, so a call site can't accidentally invent a new shape inline.
 */
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
	// INTENTIONAL BACKSTOP, unreachable under the current check order (Sec-confirmed
	// 2026-08-17): every spelling of "Infinity"/"NaN" (any case) contains a letter outside
	// `[\d.\-]` and is therefore already caught by the character-class check one line above.
	// Preserved rather than removed — unreachability is a property of today's composition,
	// not a guaranteed invariant of this function's contract.
	if (/Infinity|NaN/i.test(s)) return { ok: false, reason: 'Enter a finite number.' };

	const strictDecimal = new RegExp(`^-?\\d{1,${shape.maxIntDigits}}(\\.\\d{1,${shape.maxDecimalPlaces}})?$`);
	if (!strictDecimal.test(s)) {
		// Distinguish scale-vs-range for a clearer message where possible.
		const dot = s.indexOf('.');
		if (dot !== -1 && s.length - dot - 1 > shape.maxDecimalPlaces)
			return { ok: false, reason: `At most ${shape.maxDecimalPlaces} decimal places.` };
		return { ok: false, reason: 'Enter a valid number (e.g. 1500.00).' };
	}

	// Digit-shape range fence: integer-digit count must fit the target typmod.
	// INTENTIONAL BACKSTOP, unreachable under the current check order (Sec-confirmed
	// 2026-08-17): `strictDecimal` above is anchored (`^...$`) and already bounds the
	// integer-digit run to `{1,shape.maxIntDigits}`, so no string can pass that regex while
	// exceeding this length. Shape-dependent (unlike the other two backstops in this
	// function, this one's unreachability follows from `shape` at every call site, not from
	// a fixed prior line) — preserved rather than removed for the same reason: it is a
	// property of the current composition, not an invariant this function guarantees.
	const intDigits = s.replace('-', '').split('.')[0];
	if (intDigits.length > shape.maxIntDigits) return { ok: false, reason: 'Amount is out of range.' };

	// INTENTIONAL BACKSTOP, unreachable under the current check order (Sec-confirmed
	// 2026-08-17): `strictDecimal` above only matches an already-well-formed
	// `-?digits(.digits)?` string, and `Number()` on such a string is always finite —
	// there is no input shape that reaches this line as a non-finite value. Preserved
	// rather than removed for the same reason as the two backstops above.
	const value = Number(s);
	if (!Number.isFinite(value)) return { ok: false, reason: 'Enter a finite number.' };

	// Value range fence (mirrors a DB CHECK) — independent of, and in addition to, the
	// digit-shape fence above.
	if (shape.min !== undefined && value < shape.min)
		return { ok: false, reason: `Enter a value of at least ${shape.min}.` };
	if (shape.max !== undefined && value > shape.max)
		return { ok: false, reason: `Enter a value of at most ${shape.max}.` };

	return { ok: true, value };
}

/**
 * Validate a user-supplied monetary/numeric input against the battery. Accepts a raw form
 * value (string) or a number (client-mirror path). Returns a clean finite `number` fit for
 * numeric(20,4), or a rejection with a reason.
 *
 * Behavior- and message-identical to the pre-SELF-233 implementation for every existing
 * consumer (account.ts / transaction.ts `currencyAmount()`): same rejects, same messages,
 * same ordering. The only new code path is the length cap, which no legitimate
 * numeric(20,4) input (≤22 chars) can ever reach.
 */
export function sanitizeCurrencyAmount(raw: unknown): SanitizeResult {
	return sanitizeDecimal(raw, { maxIntDigits: MAX_INT_DIGITS, maxDecimalPlaces: MAX_DECIMAL_PLACES });
}

/**
 * Validate a user-supplied percent input against the battery, shaped to
 * pfin.planning_target.target_percent's own DDL (074): numeric(5,2), CHECK (>= 0 AND <=
 * 100). SELF-233 / RT-23 (Lock 14 mod #2) second consumer. Same six adversarial categories
 * as `sanitizeCurrencyAmount` (NaN, Infinity, currency-string, regex-overflow,
 * scientific-notation, locale-formatted), plus the two-sided [0, 100] range the DB CHECK
 * also enforces (defense-in-depth — this is the first line, not a replacement for it).
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
 * Validate a user-supplied share/unit-quantity input against the battery, shaped to
 * `pfin.account_trans.quantity`'s own DDL (017): `numeric(28,8)`, no CHECK range. SELF-325
 * (`fn_create_manual_purchase`, 088) first consumer. Same six adversarial categories as the other
 * exports; strict positivity is NOT enforced here (see the shape constants' comment) — the Zod
 * adapter in `schemas/purchase.ts` layers a `.refine((n) => n > 0, ...)` on top, mirroring
 * `transaction.ts`'s `positiveRatioComponent()`.
 */
export function sanitizeQuantity(raw: unknown): SanitizeResult {
	return sanitizeDecimal(raw, { maxIntDigits: QUANTITY_MAX_INT_DIGITS, maxDecimalPlaces: QUANTITY_MAX_DECIMAL_PLACES });
}

/**
 * Validate a user-supplied tax-bracket marginal-rate input against the battery, PROPOSED shape
 * for `pfin.tax_bracket_row.bracket_rate` (SELF-259; not yet DDL-confirmed — see the shape
 * constants' comment above). FRACTION unit per team-lead ruling / Sec M-7 (0.22, never 22):
 * two-sided [0, 1] range, same six adversarial categories as the other exports.
 */
export function sanitizeFractionRate(raw: unknown): SanitizeResult {
	return sanitizeDecimal(raw, {
		maxIntDigits: FRACTION_RATE_MAX_INT_DIGITS,
		maxDecimalPlaces: FRACTION_RATE_MAX_DECIMAL_PLACES,
		min: FRACTION_RATE_MIN,
		max: FRACTION_RATE_MAX
	});
}
