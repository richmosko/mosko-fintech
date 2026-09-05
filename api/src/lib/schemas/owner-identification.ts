// owner-identification.ts — CLIENT-SIDE Zod mirror of the SELF-359 owner-identification header
// write path ($lib/server/schemas/owner-identification.ts; migration 106 / ADR-011 Decision 18;
// RT-12-shaped).
//
// MIRROR of $lib/server/schemas/owner-identification.ts. The SERVER schema is the security
// boundary (.strict() mass-assignment fence, Lock 14 mod #1 — only { owner_id_header_text }
// accepted; users_id is ALWAYS session-derived, never read from the client); THIS object exists
// for SHAPE PARITY / tests, same role cashflow-target.ts / planning-target.ts play for their own
// surfaces. OwnerIdentificationEditor.svelte's actual per-keystroke UX feedback calls the plain
// sanitize function at $lib/validation/ownerIdHeader.ts instead — the same "Zod object for
// parity, plain sanitizer for live UX" split scheduleLabel.ts / TaxBracketScheduleEditor.svelte
// already established for the newer form-action generation of settings editors; both mirrors
// enforce the identical two rules (length, single-line) and neither may ever be looser than the
// server schema.
//
// Discipline (api/CLAUDE.md / this role's own client-Zod-mirror obligation): never ship a client
// schema LOOSER than the server's. Same `.strict()` posture, same blank-input-is-NULL
// normalization, same trimmed-value length + line-boundary bound. Backend owns the source of
// truth; when the server schema changes, this mirror updates in lockstep.

import { z } from 'zod';

/** Copied byte-for-byte from the server schema's `LINE_BOUNDARY_RE` — LF VT FF CR NEL LINE-SEP
 *  PARA-SEP, migration 106's `owner_identification_header_single_line_check`. */
const LINE_BOUNDARY_RE = /[\u000A\u000B\u000C\u000D\u0085\u2028\u2029]/;

const MAX_HEADER_LENGTH = 120;

/** `null` | string → `string | null`, normalizing blank input to NULL and bounding the trimmed
 *  value against 106's length + single-line CHECKs. Mirrors the server's `ownerIdHeaderText()`
 *  exactly. */
const ownerIdHeaderText = () =>
	z.union([z.null(), z.string()]).transform((val, ctx) => {
		if (val === null) return null;
		const trimmed = val.trim();
		if (trimmed.length === 0) return null;
		if (trimmed.length > MAX_HEADER_LENGTH) {
			ctx.addIssue({
				code: z.ZodIssueCode.custom,
				message: `Header is limited to ${MAX_HEADER_LENGTH} characters.`
			});
			return z.NEVER;
		}
		if (LINE_BOUNDARY_RE.test(trimmed)) {
			ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'Header must be a single line.' });
			return z.NEVER;
		}
		return trimmed;
	});

/**
 * POST body for the pfin.owner_identification UPSERT (SELF-359 AC3). `.strict()` rejects any
 * stray posted field (e.g. `users_id`) — the same mass-assignment fence as the server schema.
 */
export const ownerIdentificationUpsertSchema = z
	.object({
		owner_id_header_text: ownerIdHeaderText()
	})
	.strict();

export type OwnerIdentificationUpsert = z.infer<typeof ownerIdentificationUpsertSchema>;
