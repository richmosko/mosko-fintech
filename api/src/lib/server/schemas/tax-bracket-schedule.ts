// tax-bracket-schedule.ts — server-side Zod schema for the SELF-259 AC6 replace-all write path
// (POST /api/settings/tax-brackets/[schedule_id]). Reconciled against migration 101
// (supabase/migrations/101_tax_bracket_tables.sql, landed at 5f69249 on feature/self-259 —
// read live before trusting any fact below; this file cites, not restates, its `comment on`
// text) — no field/type here is a proposal any more.
//
// ⚠ SEE THE ROUTE FILE (`[schedule_id]/+server.ts`) for the full write-path design — ONE
// SECURITY INVOKER RPC, `pfin.fn_tax_bracket_schedule_replace_all` (migration 101), CONFIRMED
// by Sec's SELF-259 joint review (`docs/records/v14-execution/self259-sec-review.md` @
// `b53f766`, F-6: the landed signature matches this endpoint's `.rpc()` call name-for-name and
// type-for-type) — plus the schedule-identity-mismatch guard. Not restated here to avoid a
// second, driftable copy.
//
// SOURCE OF TRUTH: Frontend's editor (SELF-265) mirrors this client-side (Lock 14) and must
// never ship a looser schema. `.strict()` at every level (outer object AND each row) is the
// mass-assignment fence (Lock 14 mod #1) — `users_id` and `schedule_id` are deliberately NOT
// fields here: `users_id` is never read from the client (always the session's auth.uid(), and
// 101's own DEFAULT auth.uid() on both tables makes omitting it from every write the load-
// bearing path, not merely a convention), and `schedule_id` is a ROUTE param (validated
// separately in the route file as a shape-only guard, mirroring accounts/[account_id]'s
// parseAccountId / transactions/[trans_id]'s parseTransId), never a body field — a body field
// of the same name would be a second, unvalidated path to the same object-reference IDOR
// surface R4 rider 4 exists to close.
//
// REPLACE-ALL SEMANTICS (R4 rider 0 / the ADR-011 Decision 18 Sec mod; 101's own "the schedule
// and its rows are replaced as ONE unit"): every scalar field is REQUIRED on every POST — this
// is a full replace of the schedule's row set AND its scalar fields, not a partial UPSERT. This
// is why `tax_balance_prior_year` is `number | null` here (present, typed, never omittable)
// rather than cashflow-target.ts's `.optional()` null-vs-omitted pattern — that pattern exists
// to distinguish "leave this column alone" from "clear it," a distinction that has no meaning
// under replace-all (there is no "leave alone": every POST fully determines the post-write
// state). `tax_year` / `schedule_type` ARE required body fields per the original dispatch brief
// (the editor displays which tax_year/type a schedule is for) but the route file treats them as
// READ-ONLY identity once resolved from `{schedule_id}` — see that file for why (a body value
// that disagrees with the resolved row is refused, never silently repointed). `schedule_label`
// (added at Sec's SELF-260 V-2, rulings E27/E29) is likewise required and fully replaced on every
// POST — it is user-owned, user-editable data written by the same call, not an identity field,
// so it carries no schedule-identity-guard equivalent in the route file.
//
// NUMERIC FIELDS run through the shared numeric-sanitization battery (Lock 14 mod #2 — see
// $lib/server/validation/numeric.ts), each shaped to 101's own DDL:
//   - standard_deduction: numeric(20,4) NOT NULL, >= 0, non-NaN, no upper bound.
//   - tax_balance_prior_year: numeric(20,4) NULL, non-NaN, NO SIGN BOUND (101: "a prior-year
//     balance can be an OVERPAYMENT and is then legitimately negative").
//   - bracket_floor: numeric(20,4) NOT NULL, >= 0, non-NaN.
//   - bracket_rate: numeric(12,8) NOT NULL, 0 <= rate <= 1 (FRACTION unit), non-NaN.
// The first three reuse `sanitizeCurrencyAmount`; `bracket_rate` uses `sanitizeFractionRate`.
//
// ZERO-FLOOR / RATE-MONOTONICITY (101's two set-property legs, carried by ONE DEFERRED
// CONSTRAINT TRIGGER — fn_tax_bracket_row_schedule_invariants): this schema enforces NEITHER —
// they are SET properties over `rows[]`, not per-field shape checks, and are enforced as an
// app-layer COURTESY pre-check in the route file (never the guarantee — 101's own comment: "
// SERIALIZABLE is NOT a substitute for this and this is not a substitute for SERIALIZABLE").
// Kept out of this schema so the courtesy check can run against the VALIDATED, submission-order
// row array the route file already has, rather than duplicating row-shape validation inside a
// `.refine()`. `rows` here only enforces per-row SHAPE (non-negative floor, in-range fraction
// rate) and the array-level bound (min 1, max MAX_ROWS) — never ordering or the floor-uniqueness
// `unique (schedule_id, bracket_floor)` carries (the route file's courtesy check catches a
// duplicate floor as a side effect of requiring strictly-ascending submission order; see its
// own comment for why that is stricter than, and does not attempt to replace, the DB's actual
// per-VALUE-not-per-SUBMISSION-ORDER guarantee).

import { z } from 'zod';
import { sanitizeCurrencyAmount, sanitizeFractionRate, sanitizeYear } from '$lib/server/validation/numeric';

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
 *  clean field-level error rather than falling through to 101's DB CHECK's generic 23514
 *  (mirrors cashflow-target.ts's `nonNegativeCurrencyAmount()`). */
const nonNegativeCurrencyAmount = () => currencyAmount().refine((n) => n >= 0, 'Enter a non-negative amount.');

/** `tax_balance_prior_year` is INFORMATIONAL ONLY (101's own column comment: "MUST NOT ENTER
 *  THE ESTIMATED-TAX COMPUTATION") and CARRIES NO SIGN BOUND, confirmed at 101 — a prior-year
 *  balance can be a legitimate negative overpayment. Finite via the shared battery; no
 *  non-negative refine. Required (present, number-or-null), never omittable — see file header
 *  REPLACE-ALL SEMANTICS. */
const priorYearBalance = () => z.union([z.null(), currencyAmount()]);

/** `schedule_label` (migration 101, added at Sec's SELF-260 V-2, rulings E27/E29):
 *  `pfin.tax_bracket_schedule.schedule_label text not null`, CHECK
 *  `length(schedule_label) between 1 and 500` — named
 *  `tax_bracket_schedule_schedule_label_check`. Required on every POST (REPLACE-ALL SEMANTICS
 *  above), trimmed, non-empty after trim (a whitespace-only label is refused the same as an
 *  empty one — 101's own comment: "the empty string is refused rather than admitted as a
 *  blank"), max 500 mirroring the DB CHECK exactly. A non-string is rejected by `z.string()`
 *  itself, same as every other typed field on this schema — no `z.any()` transform needed since
 *  this is a shape/length check, not a numeric-parse. */
const scheduleLabel = () =>
	z
		.string()
		.trim()
		.min(1, 'A schedule label is required.')
		.max(500, 'Schedule label is too long (500 characters max).');

/** Zod adapter over the fraction-rate battery → a validated `number` in [0, 1]. */
const fractionRate = () =>
	z.any().transform((val, ctx) => {
		const r = sanitizeFractionRate(val);
		if (!r.ok) {
			ctx.addIssue({ code: z.ZodIssueCode.custom, message: r.reason });
			return z.NEVER;
		}
		return r.value;
	});

/** Zod adapter over the integer-year battery → a validated `number` in [1913, 2100]. Sec F-4
 *  (SELF-259 joint review, 2026-09-03): `tax_year` was the one numeric field on this surface
 *  still using `z.coerce.number()` — coerce-not-reject, the inverse of every other field's
 *  discipline. Same one-adapter-per-wrapped-sanitizer shape as `currencyAmount()` /
 *  `fractionRate()` above. */
const taxYear = () =>
	z.any().transform((val, ctx) => {
		const r = sanitizeYear(val);
		if (!r.ok) {
			ctx.addIssue({ code: z.ZodIssueCode.custom, message: r.reason });
			return z.NEVER;
		}
		return r.value;
	});

/**
 * `schedule_type` — CONFIRMED against `pfin.tax_schedule_type_enum` (migration 101):
 * `federal_ordinary` | `federal_lt_cg` | `california_ordinary` (PRD §2.5.2 (λ) Federal
 * ordinary / Federal LT CG, (κ) CA FTB ordinary). ⚠ NOTE the exact spelling
 * `federal_lt_cg` (underscored, not `federal_ltcg`) — this file's earlier draft, written
 * before migration 101 landed, had it wrong; a label mismatch here is a 400 on every request,
 * never a silent miscategorization, but it is still worth getting right the first time.
 */
export const taxBracketScheduleTypeSchema = z.enum(['federal_ordinary', 'federal_lt_cg', 'california_ordinary']);

/** One bracket row: a lower-bound threshold + its marginal rate (rederived-acs.md SELF-259
 *  AC2). `.strict()` rejects any stray posted field on a row (e.g. a client-supplied `id` or
 *  `users_id` — R4's grain (C) gives `tax_bracket_row` its OWN `users_id` column beside
 *  `schedule_id`, which makes a client-supplied row `users_id` a live mass-assignment /
 *  cross-tenant-planting vector if it were ever accepted as a field; it is not one here — every
 *  INSERTed row omits `users_id` entirely and relies on 101's `DEFAULT auth.uid()`, uniformly,
 *  the same way `users_id` is never read from the body for the parent scalars). */
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
 * `users_id` and `schedule_id` (see file header). `rows` requires at least one row: 101's own
 * Leg A (the lowest `bracket_floor` of a NON-EMPTY schedule must be zero) has no meaning over
 * an empty set, and — while the DB itself treats an empty row set as the legal "cleared /
 * unset" intermediate state of a replace-all — a settings editor UI has no legitimate reason to
 * submit zero brackets as an INTENDED final state, so this is an app-layer UX bound, not a
 * transcription of a DB requirement.
 *
 * `tax_year` bound `>= 1913` mirrors the DB CHECK migration 101 carries by amendment (the first
 * year of the US federal income tax) — team-lead-confirmed 2026-09-03. The upper bound (2100)
 * is NOT DB-sourced (no upper CHECK is confirmed); it is this schema's own defensive judgment
 * call, purely to reject an obviously-fat-fingered year, and may be loosened or dropped without
 * reconciling against any migration. Routed through `sanitizeYear` (Sec F-4, SELF-259 joint
 * review, 2026-09-03) — REJECT-not-coerce, same battery discipline as the currency/fraction
 * fields, rather than `z.coerce.number()`, which silently accepted scientific notation
 * (`"2e3"`), hex (`"0x7d0"`), whitespace-padded strings (`" 2000 "`), and single-element
 * arrays (`[2000]`).
 */
export const taxBracketScheduleReplaceSchema = z
	.object({
		tax_year: taxYear(),
		schedule_type: taxBracketScheduleTypeSchema,
		schedule_label: scheduleLabel(),
		standard_deduction: nonNegativeCurrencyAmount(),
		tax_balance_prior_year: priorYearBalance(),
		rows: z.array(bracketRowSchema).min(1).max(MAX_ROWS)
	})
	.strict();

export type TaxBracketScheduleReplace = z.infer<typeof taxBracketScheduleReplaceSchema>;
