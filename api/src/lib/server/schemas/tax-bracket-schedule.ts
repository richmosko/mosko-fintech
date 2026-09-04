// tax-bracket-schedule.ts — server-side Zod schema for the SELF-259 AC6 replace-all write path
// (POST /api/settings/tax-brackets/[schedule_id]; migration 101, Architect-owned, IN FLIGHT on
// feature/self-259 as of this file's authorship — every column name/type below is a PROPOSAL
// pending reconciliation against the pushed DDL, not a transcription of ratified DDL).
//
// ⚠ SEE THE ROUTE FILE (`[schedule_id]/+server.ts`) for the full set of DDL assumptions this
// schema is built against (table/column names, the D3 matched-tenant grain, the proposed RPC
// contract) — not restated here to avoid a second, driftable copy.
//
// SOURCE OF TRUTH: Frontend's editor (SELF-265) mirrors this client-side (Lock 14) and must
// never ship a looser schema. `.strict()` at every level (outer object AND each row) is the
// mass-assignment fence (Lock 14 mod #1) — `users_id` and `schedule_id` are deliberately NOT
// fields here: `users_id` is never read from the client (always the session's auth.uid()), and
// `schedule_id` is a ROUTE param (validated separately in the route file as a shape-only guard,
// mirroring accounts/[account_id]'s parseAccountId / transactions/[trans_id]'s parseTransId),
// never a body field — a body field of the same name would be a second, unvalidated path to the
// same object reference IDOR surface R4 rider 4 exists to close.
//
// REPLACE-ALL SEMANTICS (R4 rider 0 / the ADR-011 Decision 18 Sec mod): every scalar field is
// REQUIRED on every POST — this is a full replace of the schedule's row set AND its scalar
// fields, not a partial UPSERT. This is why `tax_balance_prior_year` is `number | null` here
// (present, typed, never omittable) rather than cashflow-target.ts's `.optional()` null-vs-
// omitted pattern — that pattern exists to distinguish "leave this column alone" from "clear
// it," a distinction that has no meaning under replace-all (there is no "leave alone": every
// POST fully determines the post-write state).
//
// NUMERIC FIELDS run through the shared numeric-sanitization battery (Lock 14 mod #2 — see
// $lib/server/validation/numeric.ts): `standard_deduction` / `tax_balance_prior_year` /
// `bracket_floor` reuse `sanitizeCurrencyAmount` (dollar-shaped, numeric(20,4)-proposed);
// `bracket_rate` uses the new `sanitizeFractionRate` export (FRACTION unit per team-lead
// ruling / Sec M-7 — 0.22, never 22 — two-sided [0,1], PROPOSED shape pending migration 101).
//
// ZERO-FLOOR / MONOTONICITY (Sec §10.2 items 3-5, R4 rider 8): this schema enforces neither —
// they are SET properties over `rows[]`, not per-field shape checks, and are enforced as an
// app-layer COURTESY pre-check in the route file (never the guarantee — the DB's deferred
// CONSTRAINT TRIGGER is, per R4 rider 1/2/8, confirmed independent of SERIALIZABLE). Kept out
// of this schema so the courtesy check can run against the VALIDATED, ordered row array the
// route file already has, rather than duplicating row-shape validation inside a `.refine()`.

import { z } from 'zod';
import { sanitizeCurrencyAmount, sanitizeFractionRate } from '$lib/server/validation/numeric';

/** Zod adapter over the shared currency battery → a validated `number`. Mirrors
 *  cashflow-target.ts's `currencyAmount()` / planning-target's pattern — one adapter per
 *  wrapped sanitizer, never inlined at each call site. */
const currencyAmount = () =>
	z.any().transform((val, ctx) => {
		const r = sanitizeCurrencyAmount(val);
		if (!r.ok) {
			ctx.addIssue({ code: z.ZodIssueCode.custom, message: r.reason });
			return z.NEVER;
		}
		return r.value;
	});

/** A standard deduction / bracket floor has no product meaning below zero — refused here for a
 *  clean field-level error rather than falling through to a DB CHECK's generic 23514 (mirrors
 *  cashflow-target.ts's `nonNegativeCurrencyAmount()`). */
const nonNegativeCurrencyAmount = () => currencyAmount().refine((n) => n >= 0, 'Enter a non-negative amount.');

/** `tax_balance_prior_year` is INFORMATIONAL ONLY (rederived-acs.md SELF-266 AC2, μ-2) and its
 *  sign is not constrained by any AC read so far — an overpayment carried forward is plausibly
 *  negative under this repo's established sign-flip convention for overpayment (ν-1, SELF-266
 *  AC5). Finite via the shared battery; no non-negative refine. Required (present, number-or-
 *  null), never omittable — see file header REPLACE-ALL SEMANTICS. */
const priorYearBalance = () => z.union([z.null(), currencyAmount()]);

/** Zod adapter over the new fraction-rate battery → a validated `number` in [0, 1]. */
const fractionRate = () =>
	z.any().transform((val, ctx) => {
		const r = sanitizeFractionRate(val);
		if (!r.ok) {
			ctx.addIssue({ code: z.ZodIssueCode.custom, message: r.reason });
			return z.NEVER;
		}
		return r.value;
	});

/**
 * `schedule_type` — PROPOSED three-value enum (PRD §2.5.2 (λ) Federal ordinary / Federal LT CG,
 * (κ) CA FTB ordinary; rederived-acs.md SELF-259 AC1). Snake_case identifiers are this schema's
 * OWN naming choice, not a transcription of a ratified DB enum — migration 101 has not landed
 * as of this file's authorship. Reconcile against `pfin.tax_bracket_schedule.schedule_type`'s
 * actual enum labels once pushed; a label mismatch here is a 400 on every request, never a
 * silent miscategorization, so this is a fail-closed placeholder rather than a fail-open one.
 */
export const taxBracketScheduleTypeSchema = z.enum(['federal_ordinary', 'federal_ltcg', 'ca_ftb_ordinary']);

/** One bracket row: a lower-bound threshold + its marginal rate (rederived-acs.md SELF-259
 *  AC2). `.strict()` rejects any stray posted field on a row (e.g. a client-supplied `id` or
 *  `users_id` — R4's grain (C) gives `tax_bracket_row` its OWN `users_id` column beside
 *  `schedule_id`, which makes a client-supplied row `users_id` a live mass-assignment /
 *  cross-tenant-planting vector if it were ever accepted as a field; it is not one here — the
 *  route file's RPC call derives it server-side for every row, uniformly, the same way
 *  `users_id` is derived for the parent scalars). */
const bracketRowSchema = z
	.object({
		bracket_floor: nonNegativeCurrencyAmount(),
		bracket_rate: fractionRate()
	})
	.strict();

/** Reasonable, explicit, defensive cap on row count — a full replace-all with an unbounded
 *  array is an unbounded-input-size class of its own (mirrors numeric.ts's MAX_INPUT_LENGTH
 *  reasoning: "unbounded" is its own named rejection, not an incidental side effect of some
 *  other check happening to be linear). No real V1 bracket schedule approaches double digits;
 *  50 is generous headroom, not a tight fit. */
const MAX_ROWS = 50;

/**
 * POST body for the pfin.tax_bracket_schedule + pfin.tax_bracket_row replace-all
 * (rederived-acs.md SELF-259 AC6). `.strict()` rejects any stray posted field — in particular
 * `users_id` and `schedule_id` (see file header). `rows` requires at least one row: the R4
 * rider 8 zero-floor constraint ("the lowest bracket_floor of every schedule is zero") has no
 * meaning over an empty set, and a zero-row schedule is not a schedule.
 */
export const taxBracketScheduleReplaceSchema = z
	.object({
		tax_year: z.coerce.number().int().min(2000).max(2100),
		schedule_type: taxBracketScheduleTypeSchema,
		standard_deduction: nonNegativeCurrencyAmount(),
		tax_balance_prior_year: priorYearBalance(),
		rows: z.array(bracketRowSchema).min(1).max(MAX_ROWS)
	})
	.strict();

export type TaxBracketScheduleReplace = z.infer<typeof taxBracketScheduleReplaceSchema>;
