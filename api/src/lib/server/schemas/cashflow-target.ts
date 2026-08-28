// cashflow-target.ts — server-side Zod schema for the SELF-252 / Lock 14 cash-flow-target write
// path (POST /api/settings/cashflow-target; migration 090 / ADR-011 Decision 18; RT-23-shaped).
//
// SOURCE OF TRUTH: Frontend's editor (SELF-252) mirrors this client-side (Lock 14) and must
// never ship a looser schema. `.strict()` is the mass-assignment fence (Lock 14 mod #1) —
// `users_id` is deliberately NOT a field here: it is never read from the client, always derived
// from the session (auth.uid() via hooks.server.ts). Both amounts run through the shared
// numeric battery (Lock 14 mod #2) — see $lib/server/validation/numeric.ts — shaped to 090's
// own DDL (numeric(20,4), CHECK col is null or (col >= 0 and col <> 'NaN')).
//
// NULL-VS-OMITTED IS THE CRUX (AC3/AC6, sitting items 19/19a): a key OMITTED from the payload
// means "leave that column alone"; an explicit JSON `null` means "SET that column to NULL".
// Zod's `.optional()` distinguishes these at the parsed-output level without any extra
// bookkeeping: an omitted key parses to `undefined`, an explicit `null` parses to `null` (having
// passed through the `z.null()` arm below, never through the numeric battery), and a real value
// parses to a validated `number`. The route handler (+server.ts) builds its write object only
// from keys whose parsed value is NOT `undefined` — see that file for why this must never
// collapse into a row DELETE (090's own UNSET SEMANTICS: this table carries two independent
// scalars in one row, and this schema's job is only to make "the key is present with `null`"
// and "the key is absent" distinguishable all the way to that decision).
//
// NEGATIVE VALUES: sanitizeCurrencyAmount (numeric.ts) carries no `min`/`max` for this shape —
// it has no stance on sign, unlike sanitizePercent's [0,100]. A negative cash-flow target has no
// product meaning (090's own CHECK already refuses it at the DB: `col >= 0`), so this schema
// refuses it explicitly at the app layer too — mirrors transaction.ts's
// `positiveRatioComponent()` pattern (a `.refine` layered on the shared adapter, not folded into
// the shared battery itself, since the battery is reused by fields with different sign rules).
// Refusing here gives a clean field-level 400 instead of falling through to the DB CHECK's
// generic constraint-violation error.

import { z } from 'zod';
import { sanitizeCurrencyAmount } from '$lib/server/validation/numeric';

/** Zod adapter over the shared numeric-sanitization battery → a validated `number`. */
const currencyAmount = () =>
	z.any().transform((val, ctx) => {
		const r = sanitizeCurrencyAmount(val);
		if (!r.ok) {
			ctx.addIssue({ code: z.ZodIssueCode.custom, message: r.reason });
			return z.NEVER;
		}
		return r.value;
	});

/** A cash-flow target has no product meaning below zero (090's own DB CHECK agrees); refused
 *  here for a clean field-level error rather than the DB CHECK's generic 23514. */
const nonNegativeCurrencyAmount = () =>
	currencyAmount().refine((n) => n >= 0, 'Enter a non-negative amount.');

/** Present + valid number → set; present + explicit `null` → clear (SET NULL); absent →
 *  leave the column alone. See the module header for why `.optional()` alone is sufficient to
 *  keep "absent" and "explicit null" distinguishable in the parsed output. */
const clearableCurrencyAmount = () => z.union([z.null(), nonNegativeCurrencyAmount()]).optional();

/**
 * POST body for the pfin.cashflow_target UPSERT (AC3). Field names (`income_annual`,
 * `expense_monthly`) are the app-facing names; the route handler maps them onto the DB's own
 * column names (`income_target_annual`, `expense_target_monthly`) when it builds the write
 * object. `.strict()` rejects any stray posted field (e.g. `users_id`) — the same mass-
 * assignment fence as planning-target.ts.
 */
export const cashflowTargetUpsertSchema = z
	.object({
		income_annual: clearableCurrencyAmount(),
		expense_monthly: clearableCurrencyAmount()
	})
	.strict();

export type CashflowTargetUpsert = z.infer<typeof cashflowTargetUpsertSchema>;
