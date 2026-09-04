// scheduleLabel.ts — CLIENT-SIDE mirror of the server's `schedule_label` posture
// ($lib/server/schemas/tax-bracket-schedule.ts's `scheduleLabel()`), for SELF-265's
// /settings/tax-brackets editor (Lock 14 mod #1 shape half; the numeric mirrors live in
// numeric.ts — this is the one free-text field on the surface).
//
// MIRROR, NOT PARITY — same residual the server file states and this file does not try to
// close: JS `.trim()` strips Unicode whitespace, the DB's `btrim` strips only six ASCII kinds.
// A label of pure exotic Unicode whitespace (NBSP, U+2028, and kin) is DB-legal/APP-illegal
// either way -- this client check refuses it same as the server does, it just isn't claiming to
// match the DB CHECK's own boundary byte-for-byte. This is UX fast-feedback only; the DB CHECK
// (tax_bracket_schedule_schedule_label_check) and the server's Zod schema remain the actual
// boundary.
//
// This file is NOT numeric, so it does not live in numeric.ts's shared `sanitizeDecimal` core --
// same "one file per validated shape" convention that file's own header describes.

export type LabelSanitizeResult = { ok: true; value: string } | { ok: false; reason: string };

const MAX_LABEL_LENGTH = 500;

// Any code point in U+0000-U+001F or U+007F-U+009F -- mirrors the server's control-character
// regex verbatim (Sec's SELF-260 V-4 ruling: tab and newline included, this is a single-line
// settings label). NOT an XSS control -- escaping is the render side's job (`{label}`
// interpolation), never this field's. Built via `String.fromCharCode` ranges rather than a
// literal control byte embedded in the source file.
function hasControlChar(s: string): boolean {
	for (let i = 0; i < s.length; i++) {
		const code = s.charCodeAt(i);
		if ((code >= 0x00 && code <= 0x1f) || (code >= 0x7f && code <= 0x9f)) return true;
	}
	return false;
}

/**
 * Validate a schedule label: trim first (the trimmed value is what's measured and what's
 * submitted -- there is no separate "raw" value kept anywhere in this pipeline, same as the
 * server), then require 1-500 characters and no control characters.
 */
export function sanitizeScheduleLabel(raw: unknown): LabelSanitizeResult {
	if (typeof raw !== 'string') return { ok: false, reason: 'A schedule label is required.' };

	const trimmed = raw.trim();

	if (trimmed.length < 1) return { ok: false, reason: 'A schedule label is required.' };
	if (trimmed.length > MAX_LABEL_LENGTH) {
		return { ok: false, reason: `Schedule label is too long (${MAX_LABEL_LENGTH} characters max).` };
	}
	if (hasControlChar(trimmed)) {
		return { ok: false, reason: 'Schedule label may not contain control characters.' };
	}

	return { ok: true, value: trimmed };
}
