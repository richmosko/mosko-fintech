// monthly-report-finalize.ts — server-side Zod `.strict()` mirrors for the P4 finalize/skip write
// paths (SELF-356), both calling pfin.fn_finalize_monthly_report(p_target_month date,
// p_commentary_disposition text) — migration 115 on origin/feature/self-355-db @ 924085d (read
// live before trusting any fact below; this file cites, not restates, its own CONTRACT block).
//
// `.strict()` is the mass-assignment fence (Lock 14 mod #1). `p_commentary_disposition` is NEVER
// a schema field on EITHER shape below: 115 accepts exactly `'authored'` or `'skipped'`, and this
// app never reads that value from a request — each call site passes its OWN literal (the
// commentary editor's finalize action always passes `'authored'`; the pending-list skip action
// always passes `'skipped'`). 115's own vocabulary check (108
// monthly_report_commentary_disposition_vocab) is defense-in-depth against a caller this app never
// is, not a value this schema needs to validate. `users_id` is likewise never a field — 115
// resolves the tenant via its own `FOR UPDATE` read under RLS (Gate A / RT-13).

import { z } from 'zod';

const MONTH_START_RE = /^\d{4}-\d{2}-01$/;

/** POST body for `reports/monthly/+page.server.ts`'s `?/skip` action — that route carries no
 *  `[target_month]` route param (it is the flat listing/pending-queue page), so `target_month`
 *  travels as a body field, mirroring the sibling `generate`/`regenerate` actions' own field name
 *  on the same file (those two predate this ticket's Zod-mirror build rule and stay on their own
 *  plain regex check — not touched here). */
export const skipFinalizeSchema = z
	.object({
		target_month: z.string().regex(MONTH_START_RE, 'Invalid target month.')
	})
	.strict();

export type SkipFinalizeInput = z.infer<typeof skipFinalizeSchema>;

/** POST body for `[target_month]/commentary/+page.server.ts`'s `?/finalize` action — the target
 *  month there is the ROUTE PARAM (parsed the same way `?/save` already is), so this action posts
 *  no body fields of its own. An empty `.strict()` object is still the mirror this ticket's build
 *  rule calls for: it refuses any stray posted field (mass-assignment fence) rather than silently
 *  ignoring one, even though today's form has nothing to smuggle. */
export const authoredFinalizeSchema = z.object({}).strict();

export type AuthoredFinalizeInput = z.infer<typeof authoredFinalizeSchema>;
