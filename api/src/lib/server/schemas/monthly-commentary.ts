// monthly-commentary.ts — server-side Zod schema for the §2.6.2 commentary write path (SELF-355 /
// P3; migration 108's four commentary CHECKs; migration 112's fn_save_monthly_commentary;
// RT-11-shaped). Reconciled against migration 112
// (supabase/migrations/112_fn_save_monthly_commentary.sql, landed on feature/self-355-db @
// 5789c2d) — read live before trusting any fact below; this file cites, not restates, its own
// CONTRACT block.
//
// SOURCE OF TRUTH: Frontend's editor (MonthlyCommentaryEditor.svelte) mirrors this client-side via
// $lib/schemas/monthly-commentary.ts (shape parity) and $lib/validation/monthlyCommentary.ts (the
// live per-field UX check the component actually calls, incl. the code-point counter — same "Zod
// object for parity, plain checker for live UX" split as tax-bracket-schedule.ts / scheduleLabel.ts
// and owner-identification.ts / ownerIdHeader.ts). `.strict()` is the mass-assignment fence (Lock
// 14 mod #1) — neither `target_month` (a route param here, not a body field) nor `users_id` is a
// schema field; `users_id` is never read from the client (112's own SELECT ... FOR UPDATE resolves
// it via RLS, and this route's own RPC call never passes one).
//
// LENGTH (E15 item 10/11, Sec N-5): 108's four CHECKs each count CODE POINTS
// (`length(commentary_cash) <= 4000`), and 112 ADDS NO SECOND BOUND OF ITS OWN — "a second bound
// here would be a third fact that can disagree with the other two" (112's own header). This
// schema's bound is therefore the ONE app-layer participant in Sec N-5's two-layer equality (app
// vs DB) and MUST count code points the same way: `Array.from(s).length`, NEVER `s.length` (a bare
// `.length` counts UTF-16 code units, so a body of 3,996 ASCII + 4 astral characters is 4,000 code
// points — DB-legal — but 4,004 UTF-16 units, which a `.length`-bound schema would wrongly refuse —
// E15 item 11's own named falsifying case).
//
// NEWLINE NORMALIZATION IS NOT THIS SCHEMA'S JOB. E15 item 11 / 112's own FINDING: the CLIENT
// normalizes `\r\n` -> `\n` before both counting and submitting, and 112 deliberately does NOT
// normalize server-side ("would silently rewrite the author's stored text"). The SAME reasoning
// applies at this layer — this schema counts code points on WHATEVER TEXT ARRIVES, without
// rewriting it, which is both the correct security posture (never silently mutate stored content)
// and sufficient defense: a body that arrives un-normalized (client bypassed, or a non-editor
// caller) is counted on its ACTUAL code points as received, so an over-bound un-normalized body is
// still correctly refused — it does not need this schema's help to already have more code points
// than a normalized version of the same visual content would.
//
// BLANK IS A LEGITIMATE VALUE, NOT UNSET (unlike owner-identification.ts's crux): 108 carries NO
// not-blank CHECK on any of the four commentary columns (unlike 106's
// `owner_identification_header_not_blank_check`) — only a length bound. '' is DB-legal and is
// exactly what "the author cleared this sub-section" looks like (112's own header: "A sub-section
// the author cleared comes back as NULL or ''"). This schema therefore does NOT normalize blank to
// null the way owner-identification.ts's schema does — every field is a plain, always-required
// `string` (a `<textarea>`'s native value is always a string, never actually absent), and an empty
// string round-trips as an empty string all the way to the DB.
//
// REPLACE-ALL, LITERAL (AC5 / 112's own header): all four fields are REQUIRED on every submission
// — there is no "leave this one alone" semantics, because the editor always submits the whole
// form and 112's own body assigns all four columns from its four arguments on every call.

import { z } from 'zod';

const MAX_CODE_POINTS = 4000;

/** One commentary sub-section: a plain string, bounded at 4000 CODE POINTS (not UTF-16 units —
 *  see file header). `catLabel` is folded into the message so a `.strict()` object built from
 *  four of these produces a field-attributable error per sub-section. */
const commentaryField = (catLabel: string) =>
	z.string().refine((s) => Array.from(s).length <= MAX_CODE_POINTS, {
		message: `Over the ${MAX_CODE_POINTS}-character limit for ${catLabel}.`
	});

/**
 * POST body for pfin.fn_save_monthly_commentary (SELF-355 AC5/AC6). `.strict()` rejects any stray
 * posted field — in particular `target_month` (a route param, never a body field, mirroring
 * tax-bracket-schedule.ts's `schedule_id` convention) and `users_id` (never read from the client;
 * 112's own SELECT ... FOR UPDATE resolves the tenant via RLS).
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
