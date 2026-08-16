// classification.ts — server-side Zod schema for the SELF-200 pending-symbol classify write-path.
//
// SOURCE OF TRUTH: Frontend mirrors this client-side (Lock 14) and must never ship a looser
// schema. `.strict()` is the mass-assignment fence (Lock 14 mod #2): only { asset_id, sub_cat_id }
// are accepted — `users_id` is NEVER read from the client; the action always sets it from the
// session. Both ids are required positive integers: pfin.user_asset_category.sub_cat_id is
// NOT NULL (022), so — unlike account.sub_cat_id — there is NO nullable "Unsorted" option here;
// classifying requires a real Sub-Cat. Matched-tenant (#8) + global-OR-owned (#9) are DB-enforced
// (022 fn_user_asset_category_matched_sub_cat / _asset triggers) regardless — this schema is UX + shape.

import { z } from 'zod';

export const classifySchema = z
	.object({
		asset_id: z.coerce.number().int().positive(),
		sub_cat_id: z.coerce.number().int().positive()
	})
	.strict();

export type Classify = z.infer<typeof classifySchema>;
