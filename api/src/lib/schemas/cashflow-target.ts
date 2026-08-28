// cashflow-target.ts — CLIENT-SIDE Zod mirror of the SELF-252 cash-flow-target write path
// (POST /api/settings/cashflow-target; migration 090 / ADR-011 Decision 18; RT-23-shaped).
//
// MIRROR of src/lib/server/schemas/cashflow-target.ts. The SERVER schema is the security
// boundary (.strict() mass-assignment fence, Lock 14 mod #1 — only { income_annual?,
// expense_monthly? } accepted; users_id is ALWAYS session-derived, never read from the
// client); THIS is the browser-side UX mirror consumed by CashflowTargetEditor.svelte —
// fast field-level feedback before the POST round-trip.
//
// Discipline (api/CLAUDE.md): never ship a client schema LOOSER than the server's. Same
// `.strict()` posture, same clearable-per-field shape (key OMITTED → leave alone; key
// `null` → clear; value → set — the AC3/AC6 null-vs-omitted crux, preserved here exactly
// as the server schema states it), same numeric battery via the client
// `sanitizeCurrencyAmount` mirror (validation/numeric.ts) plus the SAME explicit
// non-negative refine the server layers on top of it (the shared battery has no sign
// stance for this shape — mirrors the server's `nonNegativeCurrencyAmount`). Backend owns
// the source of truth; when the server schema changes, this mirror updates in lockstep.

import { z } from 'zod';
import { sanitizeCurrencyAmount } from '$lib/validation/numeric';

/** Zod adapter over the shared client currency-sanitization battery → a validated `number`. */
const currencyAmount = () =>
	z.any().transform((val, ctx) => {
		const r = sanitizeCurrencyAmount(val);
		if (!r.ok) {
			ctx.addIssue({ code: z.ZodIssueCode.custom, message: r.reason });
			return z.NEVER;
		}
		return r.value;
	});

/** A cash-flow target has no product meaning below zero (090's own DB CHECK agrees) —
 *  mirrors the server's `nonNegativeCurrencyAmount` refine exactly. */
const nonNegativeCurrencyAmount = () =>
	currencyAmount().refine((n) => n >= 0, 'Enter a non-negative amount.');

/** Present + valid number → set; present + explicit `null` → clear (SET NULL); absent →
 *  leave the column alone. Mirrors the server's `clearableCurrencyAmount` — `.optional()`
 *  alone keeps "absent" and "explicit null" distinguishable in the parsed output. */
const clearableCurrencyAmount = () => z.union([z.null(), nonNegativeCurrencyAmount()]).optional();

/**
 * POST body for the pfin.cashflow_target UPSERT (AC3/AC6). `.strict()` rejects any stray
 * posted field (e.g. `users_id`) — the same mass-assignment fence as the server schema.
 */
export const cashflowTargetUpsertSchema = z
	.object({
		income_annual: clearableCurrencyAmount(),
		expense_monthly: clearableCurrencyAmount()
	})
	.strict();

export type CashflowTargetUpsert = z.infer<typeof cashflowTargetUpsertSchema>;
