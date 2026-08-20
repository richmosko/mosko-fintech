// numeric.ts — CLIENT-SIDE mirror of the shared numeric-sanitization battery.
//
// MIRROR of src/lib/server/validation/numeric.ts (Lock 14 V1-SHIP-BLOCK Sec mod #1/#2).
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
