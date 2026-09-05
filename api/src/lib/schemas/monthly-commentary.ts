// monthly-commentary.ts — CLIENT-SIDE Zod mirror of the §2.6.2 commentary write path
// ($lib/server/schemas/monthly-commentary.ts; migration 108/112; SELF-355 / P3; RT-11-shaped).
//
// MIRROR of $lib/server/schemas/monthly-commentary.ts. The SERVER schema is the security boundary
// (`.strict()` mass-assignment fence, Lock 14 mod #1); THIS object exists for SHAPE PARITY — same
// role cashflow-target.ts / owner-identification.ts play for their own surfaces.
// MonthlyCommentaryEditor.svelte's actual per-keystroke UX (the live "{n} / 4000" counter, the
// Save-disabled gate) calls the plain helpers at $lib/validation/monthlyCommentary.ts instead —
// the same "Zod object for parity, plain checker for live UX" split this codebase already
// established for scheduleLabel.ts / ownerIdHeader.ts.
//
// Discipline: never ship a client schema LOOSER than the server's. Same `.strict()` posture, same
// four-required-fields shape, same 4000-CODE-POINT bound (`Array.from(s).length`, never
// `s.length` — see the server schema's own header for the astral-character falsifying case).

import { z } from 'zod';

const MAX_CODE_POINTS = 4000;

const commentaryField = (catLabel: string) =>
	z.string().refine((s) => Array.from(s).length <= MAX_CODE_POINTS, {
		message: `Over the ${MAX_CODE_POINTS}-character limit for ${catLabel}.`
	});

/**
 * POST body for pfin.fn_save_monthly_commentary (SELF-355 AC5/AC6). `.strict()` rejects any stray
 * posted field — the same mass-assignment fence as the server schema.
 */
export const monthlyCommentaryUpsertSchema = z
	.object({
		cash: commentaryField('Cash'),
		bonds: commentaryField('Bonds'),
		marketable_securities: commentaryField('Marketable Securities'),
		alternatives: commentaryField('Alternatives')
	})
	.strict();

export type MonthlyCommentaryUpsert = z.infer<typeof monthlyCommentaryUpsertSchema>;
