// monthlyCommentary.ts — CLIENT-SIDE mirror of the §2.6.2 commentary length posture
// ($lib/server/schemas/monthly-commentary.ts; migration 108's four commentary CHECKs +
// migration 112's fn_save_monthly_commentary; SELF-355 / P3; E15 riders 10-12, Sec N-5). Used by
// MonthlyCommentaryEditor.svelte for the live "{n} / 4000" counter and the Save-disabled gate.
//
// THE MIRROR RULE (E15 item 11, Sec N-5's own catch criterion): 108's CHECK counts CODE POINTS
// (Postgres `length()`); a bare JS `.length` counts UTF-16 CODE UNITS, so a body of 3,996 ASCII +
// 4 astral characters is 4,000 code points (DB-legal) but 4,004 UTF-16 units — a naive `.length`
// bound would refuse what the DB accepts, the WRONG direction for a mirror (a looser client would
// be the dangerous direction; a client that is merely INCORRECT in the strict direction is still a
// broken counter, not a security hole, but E15's own QA list names this as the leg that fails if
// anyone reverts to `.length`). `codePointLength` below uses `Array.from(s).length`, matching
// Postgres `length()` exactly.
//
// NEWLINE NORMALIZATION (E15 item 11 / migration 112's own FINDING): the client normalizes
// `\r\n` -> `\n` BEFORE both counting and submitting — this is the ONLY reason the client's count
// and the DB's count agree on a multi-line body. `112` deliberately does NOT normalize server-side
// (doing so would silently rewrite the author's stored text), and NEITHER does this codebase's own
// server-side Zod schema (same reasoning applies at that layer) — normalization is a CLIENT-ONLY
// step. `normalizeLineEndings` below is applied by MonthlyCommentaryEditor.svelte to the value
// BEFORE it reaches either the live counter or the hidden field that actually gets submitted; the
// visible <textarea> keeps whatever the browser gives it, unmutated, so a user's cursor position
// / undo history is never disturbed by this codebase's own normalization pass.

export const MONTHLY_COMMENTARY_MAX_CODE_POINTS = 4000;

/** Postgres `length()`-equivalent: counts CODE POINTS, not UTF-16 code units. `Array.from` splits
 *  a string on Unicode code points (surrogate-pair-aware), unlike `.length`. */
export function codePointLength(s: string): number {
	return Array.from(s).length;
}

/** `\r\n` -> `\n` — the ONLY normalization this surface performs, and it happens ONLY on the
 *  client (E15 item 11 / 112's own FINDING). Never `\r` alone -> `\n` (a bare `\r` is not part of
 *  this AC's stated normalization and this file does not invent a wider rule than the one ruled). */
export function normalizeLineEndings(s: string): string {
	return s.replace(/\r\n/g, '\n');
}

export type CommentaryFieldCheck =
	| { ok: true; codePoints: number }
	| { ok: false; codePoints: number; reason: string };

/** Validate one already-normalized commentary sub-section against the 4000-code-point bound
 *  (E15 item 10). The caller is responsible for normalizing first — this function does not
 *  normalize on the caller's behalf, so a caller that skips normalization gets a count that
 *  disagrees with what would be submitted, which is exactly the failure mode E15 exists to name,
 *  not silently paper over. */
export function checkCommentaryField(normalized: string, catLabel: string): CommentaryFieldCheck {
	const codePoints = codePointLength(normalized);
	if (codePoints > MONTHLY_COMMENTARY_MAX_CODE_POINTS) {
		return { ok: false, codePoints, reason: `Over the ${MONTHLY_COMMENTARY_MAX_CODE_POINTS}-character limit for ${catLabel}.` };
	}
	return { ok: true, codePoints };
}
