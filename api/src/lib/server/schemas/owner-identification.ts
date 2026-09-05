// owner-identification.ts — server-side Zod schema for the SELF-359 (P7) owner-identification
// header write path (Settings /settings/owner-id; migration 106 / ADR-011 Decision 18 Lock 14;
// RT-12-shaped). Reconciled against migration 106
// (supabase/migrations/106_owner_identification.sql, landed at 30ac2cc on main via PR #629) —
// read live before trusting any fact below; this file cites, not restates, its `comment on` text.
//
// ⚠ AUTHORSHIP NOTE, stated rather than silently taken: this file lives under $lib/server/ —
// Backend's ARCH §4.1 allowlist surface — and was authored by Frontend under the SELF-359
// dispatch, which named this file explicitly and directed the whole write path be built here,
// because no paired Backend issue existed for this table's write path at dispatch time (only
// A8 / migration 106 itself is Backend/Architect-owned and already landed). Flagged to team-lead
// as a role-boundary exception, not a silent scope grab — a Backend/Sec re-read of this file is
// owed at the AC8 Sec joint review (Lock 14 MANDATORY joint-review).
//
// SOURCE OF TRUTH: Frontend's editor (OwnerIdentificationEditor.svelte) mirrors this client-side
// via $lib/schemas/owner-identification.ts (shape parity) and $lib/validation/ownerIdHeader.ts
// (the live per-field UX check the component actually calls — same "Zod object for parity, plain
// sanitizer for live UX" split as tax-bracket-schedule.ts / scheduleLabel.ts) and must never ship
// either mirror looser than this file. `.strict()` is the mass-assignment fence (Lock 14 mod #1)
// — `users_id` is deliberately NOT a field here: it is never read from the client, always derived
// from the session (auth.uid() via hooks.server.ts).
//
// SHAPE — ONE field, `owner_id_header_text: string | null`, always present. This is a
// single-field replace (the editor has exactly one input), not a multi-field partial UPSERT —
// there is no "leave alone" state to distinguish, unlike cashflow-target.ts's two-scalar
// null-vs-omitted crux.
//
// EMPTY-INPUT-IS-NULL (106's TEXT FENCE (3) / the SELF-352 PR #629 rider this issue's own AC item
// 3 restates): 106's not-blank CHECK refuses '' with 23514, so an emptied editor field MUST be
// written as NULL, never as ''. This schema does that normalization itself — blank (empty or
// whitespace-only) input parses to `null` — so every caller gets the correct write value without
// re-deriving the rule.
//
// LENGTH — 106's CHECK counts CODE POINTS (`length()`); a Zod `.max` on JS `.length` counts
// UTF-16 CODE UNITS, which is equal-or-STRICTER (an astral character counts 2 here, 1 there) —
// the safe direction, per 106's own column comment. Applied to the TRIMMED value (see below), so
// the bound a user hits is the bound the stored value is measured against, not a bound inflated
// by throwaway leading/trailing whitespace.
//
// SINGLE LINE — 106's CHECK rejects the Unicode line-boundary class, not LF alone: LF, VT, FF,
// CR, NEL (U+0085), LINE SEPARATOR (U+2028), PARAGRAPH SEPARATOR (U+2029) — copied here as the
// SAME seven code points, in the SAME class, mirroring that CHECK's own regex byte-for-byte.
//
// TRIM-TO-CANONICAL-FORM is THIS SCHEMA'S OWN judgment call, not a 106 mirror: 106 carries no trim
// CHECK (unlike tax-bracket-schedule.ts's `schedule_label`, which the DB itself canonicalizes via
// `btrim`), so a value with leading/trailing whitespace is DB-legal as stored. Trimming here is a
// UX/consistency choice — flagged at hand-off — to keep a report header from silently carrying
// accidental surrounding whitespace and to keep the 120-character bound meaningful against what is
// actually stored. Reversible without a migration if this call is wrong.
//
// WHAT THIS SCHEMA DOES NOT FENCE (RT-12's own scope note, 106's column comment, verbatim): "THESE
// CHECKS ARE THE DB HALF AND ARE NECESSARY RATHER THAN SUFFICIENT" — a `<script>` payload, a
// SQL-injection string, an RTL override, or a homoglyph are all PROSE to this field and are
// accepted; rejecting them here would be the wrong fence at the wrong layer. Escaping at the
// render surface (P2/P6, Svelte's default `{...}` interpolation, never `{@html}`) is the actual
// control for those classes — same posture tax-bracket-schedule.ts states for `schedule_label`. A
// non-line-boundary Unicode control character (e.g. BEL, ESC) is likewise accepted — this schema
// mirrors ONLY 106's two CHECKs it is scoped to (length, single-line), never a broader
// control-character fence. See owner-id.server.test.ts's RT-12 battery for the reject-vs-store-
// inert table this produces.

import { z } from 'zod';

/** The Unicode line-boundary class 106's `owner_identification_header_single_line_check` fences,
 *  copied byte-for-byte from that CHECK's own comment: LF VT FF CR NEL LINE-SEP PARA-SEP. */
const LINE_BOUNDARY_RE = /[\u000A\u000B\u000C\u000D\u0085\u2028\u2029]/;

const MAX_HEADER_LENGTH = 120;

/** `null` | string → `string | null`, normalizing blank input to NULL (see file header) and
 *  bounding the trimmed value against 106's length + single-line CHECKs. */
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
 * stray posted field (e.g. `users_id`) — the same mass-assignment fence as every other Lock 14
 * settings write path (cashflow-target.ts / tax-bracket-schedule.ts).
 */
export const ownerIdentificationUpsertSchema = z
	.object({
		owner_id_header_text: ownerIdHeaderText()
	})
	.strict();

export type OwnerIdentificationUpsert = z.infer<typeof ownerIdentificationUpsertSchema>;
