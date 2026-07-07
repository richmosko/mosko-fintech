// numeric.ts — CLIENT-SIDE mirror of the shared numeric-sanitization battery.
//
// MIRROR of src/lib/server/validation/numeric.ts (Lock 14 V1-SHIP-BLOCK Sec mod #1).
// This is browser-shipped code, so it CANNOT import from src/lib/server/** (that
// surface never reaches the browser; Vite refuses the build). It is therefore a
// hand-kept parallel copy — the client check is UX fast-feedback ONLY; the SERVER
// battery is the security boundary. This mirror must never be LOOSER than the server
// one: same rejects, same thresholds. Backend owns the source of truth — when the
// server battery changes, update this copy in lockstep (api/CLAUDE.md Frontend conv).
//
// Rejects (identical to server): NaN/Infinity, currency symbols, thousands commas,
// scientific/exponential notation, embedded whitespace/empty/non-string-non-number,
// > 4 decimal places, > 16 integer digits (numeric(20,4) range).

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
 * Accepts a raw form value (string) or a number. Returns a clean finite `number`
 * fit for numeric(20,4), or a rejection with a reason. Logic-identical to the server.
 */
export function sanitizeCurrencyAmount(raw: unknown): SanitizeResult {
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

	if (/[eE]/.test(s)) return { ok: false, reason: 'Scientific notation is not allowed.' };
	if (/[,]/.test(s)) return { ok: false, reason: 'Remove thousands separators (e.g. enter 1500.00).' };
	if (/[^\d.\-]/.test(s))
		return { ok: false, reason: 'Remove currency symbols and spaces (digits only, e.g. 1500.00).' };
	if (/Infinity|NaN/i.test(s)) return { ok: false, reason: 'Enter a finite number.' };

	if (!STRICT_DECIMAL.test(s)) {
		const dot = s.indexOf('.');
		if (dot !== -1 && s.length - dot - 1 > MAX_DECIMAL_PLACES)
			return { ok: false, reason: `At most ${MAX_DECIMAL_PLACES} decimal places.` };
		return { ok: false, reason: 'Enter a valid number (e.g. 1500.00).' };
	}

	const intDigits = s.replace('-', '').split('.')[0];
	if (intDigits.length > MAX_INT_DIGITS)
		return { ok: false, reason: 'Amount is out of range.' };

	const value = Number(s);
	if (!Number.isFinite(value)) return { ok: false, reason: 'Enter a finite number.' };

	return { ok: true, value };
}
