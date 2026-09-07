// ownerIdHeader.ts — CLIENT-SIDE mirror of the server's owner-identification header posture
// ($lib/server/schemas/owner-identification.ts), for SELF-359's /settings/owner-id editor
// (migration 106 / Lock 14 / RT-12-shaped). Used by OwnerIdentificationEditor.svelte for live
// per-keystroke UX feedback — the object-shape Zod mirror at
// $lib/schemas/owner-identification.ts carries the same two rules for shape parity and is not
// itself wired into the live field (same split as scheduleLabel.ts / TaxBracketScheduleEditor.svelte's
// own established convention: a plain sanitize function for per-field UX, a Zod object for
// shape-level parity/tests).
//
// MIRROR, NOT PARITY: 106's CHECK counts CODE POINTS; JS `.length` counts UTF-16 code units,
// which is equal-or-STRICTER (the safe direction — 106's own column comment). Trimming before
// storage is this codebase's own UX judgment call (106 carries no trim CHECK) — see the server
// schema's header for why.
//
// This file is NOT numeric, so it does not live in numeric.ts's shared `sanitizeDecimal` core --
// same "one file per validated shape" convention that file's own header describes.

export type HeaderSanitizeResult = { ok: true; value: string | null } | { ok: false; reason: string };

const MAX_HEADER_LENGTH = 120;

/** Copied byte-for-byte from the server schema's `LINE_BOUNDARY_RE` — LF VT FF CR NEL LINE-SEP
 *  PARA-SEP, migration 106's `owner_identification_header_single_line_check`. Built from
 *  `String.fromCharCode` code points rather than a literal control byte embedded in source,
 *  mirroring scheduleLabel.ts's own convention for the same reason (no literal control byte in
 *  a source file). */
const LINE_BOUNDARY_CODEPOINTS = [0x0a, 0x0b, 0x0c, 0x0d, 0x85, 0x2028, 0x2029];

function hasLineBoundary(s: string): boolean {
	for (let i = 0; i < s.length; i++) {
		if (LINE_BOUNDARY_CODEPOINTS.includes(s.charCodeAt(i))) return true;
	}
	return false;
}

/**
 * Validate + normalize an owner-identification header field. Blank (empty or whitespace-only)
 * input is a valid CLEAR, normalized to `null` (106's TEXT FENCE (3): a write path clearing the
 * field MUST send NULL, never ''). Non-blank input is trimmed, then bounded to <=120 UTF-16 code
 * units and no Unicode line-boundary code point — the same two CHECKs the server schema mirrors,
 * no more (see that file's header for what is deliberately NOT fenced here: XSS/SQLi/RTL-
 * override/homoglyph payloads are all prose to this field and pass this check — escaping at the
 * render surface is the actual control for those classes, per RT-12's own scope note).
 */
export function sanitizeOwnerIdHeader(raw: unknown): HeaderSanitizeResult {
	if (raw === null) return { ok: true, value: null };
	if (typeof raw !== 'string') return { ok: false, reason: 'Enter a valid header.' };
	const trimmed = raw.trim();
	if (trimmed.length === 0) return { ok: true, value: null };
	if (trimmed.length > MAX_HEADER_LENGTH) {
		return { ok: false, reason: `Header is limited to ${MAX_HEADER_LENGTH} characters.` };
	}
	if (hasLineBoundary(trimmed)) {
		return { ok: false, reason: 'Header must be a single line.' };
	}
	return { ok: true, value: trimmed };
}
