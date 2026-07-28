// classification.ts — CLIENT-SIDE Zod mirror of the SELF-200 pending-symbol classify write-path.
//
// MIRROR of src/lib/server/schemas/classification.ts. The SERVER schema is the security
// boundary (.strict() mass-assignment fence, Lock 14 mod #2 — only { asset_id, sub_cat_id }
// accepted; users_id is ALWAYS session-derived, never read from the client); THIS is the
// browser-side UX mirror — fast field-level feedback before the POST.
//
// Discipline (api/CLAUDE.md): never ship a client schema LOOSER than the server's. Same
// `.strict()` posture, same `z.coerce.number().int().positive()` on BOTH ids. Unlike
// account.sub_cat_id there is NO nullable "Unsorted" option — pfin.user_asset_category.sub_cat_id
// is NOT NULL (022), so classifying REQUIRES a real Sub-Cat. Friendlier messages are a UX nicety,
// NOT a loosening (same value-set, same int().positive() gate). Matched-tenant (#8) +
// global-OR-owned (#9) stay DB-enforced (022 triggers) — this is UX + shape only. Backend owns the
// source of truth; when the server schema changes, this mirror updates in lockstep.

import { z } from 'zod';

export const classifySchema = z
	.object({
		asset_id: z.coerce.number().int().positive(),
		// '' (the non-preselected "Select a category…" placeholder — AC3) coerces to 0, which fails
		// .positive() → the "Choose a category." message. Same gate as the server; friendlier copy.
		sub_cat_id: z.coerce
			.number({ message: 'Choose a category.' })
			.int('Choose a category.')
			.positive('Choose a category.')
	})
	.strict();

export type Classify = z.infer<typeof classifySchema>;
