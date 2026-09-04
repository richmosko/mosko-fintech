// taxBracketRows.ts -- CLIENT-SIDE mirror of the write endpoint's `precheckRowOrdering`
// (api/src/routes/api/settings/tax-brackets/[schedule_id]/+server.ts), for SELF-265's
// /settings/tax-brackets editor.
//
// COURTESY ONLY -- never the guarantee. Migration 101's own comment states it directly: "the row
// lock is not a substitute for either [set-property] leg, and neither is a substitute for it."
// The actual guarantee is 101's deferred CONSTRAINT TRIGGER
// (fn_tax_bracket_row_schedule_invariants), which evaluates once the whole set exists at COMMIT
// -- a property a client-side per-keystroke check structurally cannot observe (this file has no
// transaction, no commit, no view of what the DB will actually see). This function exists only
// so a user gets the SAME rejection message before a round trip that the server's own courtesy
// pre-check would give it, one layer earlier.
//
// SAME TWO LEGS, SAME MESSAGES, SAME STRICTER-THAN-THE-DB posture as the server file:
//   Leg A (zero floor): the first row's bracket_floor must be exactly 0.
//   Leg B (rate monotonicity): each subsequent row's bracket_rate must be >= the previous row's,
//     reading rows in SUBMISSION order (never re-sorted) -- stricter than the DB, which sorts by
//     bracket_floor internally and doesn't care what order the caller submitted rows in. A batch
//     that passes this check is therefore guaranteed to also pass the DB fence; the reverse is
//     not claimed.
//   `<=` (not `<`) on the floor comparison subsumes duplicate-floor detection, same as the server
//   file's own comment explains: two rows sharing one bracket_floor can never pass
//   "each subsequent floor > previous".

export type BracketRowInput = { bracket_floor: number; bracket_rate: number };

export type RowOrderingResult = { ok: true } | { ok: false; reason: string };

export function precheckRowOrdering(rows: readonly BracketRowInput[]): RowOrderingResult {
	if (rows.length === 0) return { ok: false, reason: 'At least one bracket row is required.' };

	if (rows[0].bracket_floor !== 0) {
		return { ok: false, reason: 'The lowest bracket must start at 0.' };
	}
	for (let i = 1; i < rows.length; i++) {
		if (rows[i].bracket_floor <= rows[i - 1].bracket_floor) {
			return { ok: false, reason: 'Bracket thresholds must strictly increase, in order.' };
		}
		if (rows[i].bracket_rate < rows[i - 1].bracket_rate) {
			return { ok: false, reason: 'Bracket rates must not decrease as thresholds rise.' };
		}
	}
	return { ok: true };
}
