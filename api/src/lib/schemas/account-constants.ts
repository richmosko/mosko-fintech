// account-constants.ts — browser-safe shared value-sets for the account surfaces.
//
// NON-server module (imports nothing server-only) so BOTH sides import the SAME
// canonical value-sets: the server schema (src/lib/server/schemas/account.ts, the
// .strict() + numeric-battery security boundary) AND Frontend's client-side UX
// mirror. This is the single anti-drift point — the schemas stay per-role (Backend
// owns the source of truth; Frontend mirrors independently per api/CLAUDE.md), but
// the enum value-sets can never diverge because there is only one definition.
//
// Value-sets are copied VERBATIM from the DB CHECK constraints on pfin.account (003)
// — the DB CHECK is the authoritative backstop. If 003's CHECK changes, update here
// (Backend-sourced; the values track the migration, not UI preference).

/** account_type — VERBATIM from 003 pfin.account CHECK. */
export const ACCOUNT_TYPES = [
	'depository',
	'investment',
	'retirement',
	'crypto',
	'manual_other',
	'real_estate',
	'liability'
] as const;
export type AccountType = (typeof ACCOUNT_TYPES)[number];

/** tax_treatment — VERBATIM from 003 pfin.account CHECK. */
export const TAX_TREATMENTS = ['taxable', 'tax_deferred', 'tax_free'] as const;
export type TaxTreatment = (typeof TAX_TREATMENTS)[number];

/**
 * tax_jurisdiction — VERBATIM from 102 pfin.tax_jurisdiction_enum ('irs', 'ftb').
 * SELF-267 AC 1/2. Marks an account as a tax authority's ledger; NULL (absent from this
 * set at the app layer — see account.ts's taxJurisdictionField) means "not a tax-authority
 * ledger", never "unknown". One account per value per user (102's partial unique index
 * account_tax_jurisdiction_uniq) — the app-layer schemas do not re-enforce that count; the
 * DB constraint is the fence and the write path maps its 23505 to a field error.
 */
export const TAX_JURISDICTIONS = ['irs', 'ftb'] as const;
export type TaxJurisdiction = (typeof TAX_JURISDICTIONS)[number];

/**
 * closure reason_code — VERBATIM from 057 pfin.account_event CHECK.
 *
 * MANDATORY on the into-closed transition (058's audit writer refuses without it and
 * deliberately will not invent one). This is a THIRD representation of the vocabulary
 * (DB CHECK -> here -> the picker); per Architect it is NOT re-validated inside
 * fn_close_account, which would make a fourth. Drift is caught by a QA assertion against
 * pg_constraint rather than by a comment — the §7.6 S1 shape.
 *
 * Labels are placeholders pending PM + UX copy; the VALUES are Backend-sourced and track
 * the migration, never UI preference.
 */
export const CLOSURE_REASONS = [
	'no_longer_used',
	'sold',
	'transferred_out',
	'duplicate',
	'institution_closed',
	'other'
] as const;
export type ClosureReason = (typeof CLOSURE_REASONS)[number];

/**
 * PM copy ruling, 2026-08-04 — no longer placeholders. Four of six kept verbatim; two changed.
 *
 * THE GOVERNING CONSTRAINT IS NOT READABILITY, IT IS DISTINGUISHABILITY. What the user picks is
 * written to `pfin.account_event`, which is IMMUTABLE audit-class (ADR-011 Decision 2) with no
 * correction path. So the failure mode is not an ugly label — it is TWO LABELS A USER CANNOT
 * CHOOSE BETWEEN, because then the picked value is noise and the audit trail records a fact
 * nobody asserted. Every label must let the user answer "is this the true one?" without guessing.
 *
 * CHANGED:
 *  - `duplicate`: "Duplicate" -> "Duplicate of another account". Bare "Duplicate" left the object
 *    unnamed — duplicate transaction? duplicate connection? It is also the only value in the set
 *    that is about the RECORD rather than the real-world account, so it is the one most worth
 *    disambiguating.
 *  - `transferred_out`: "Transferred out" -> "Transferred to another account". "Out" names a
 *    direction with no destination, and it was the value most confusable with "Sold" — both mean
 *    "the assets left". Naming the destination-shape separates them at a glance: sold = converted,
 *    transferred = moved.
 *
 * KEPT: "No longer used" (dormant-but-real, distinct from every other value), "Sold" (correct for
 * both a brokerage position and a §2.4.2 manual asset like a house or vehicle), "Closed by the
 * institution" (names the actor, which is the whole distinction from "No longer used"), "Other".
 *
 * PM FLAG, out of scope here and NOT fixed by relabelling: "Other" writes a value that records
 * nothing, into the one table that cannot be corrected. There is no free-text companion field. A
 * reason-note is a schema + form change, not copy — routed to team-lead as a BACKLOG §7 candidate.
 *
 * The VALUES above remain Backend-sourced and track `057`'s CHECK; nothing here may reorder or
 * rename them.
 */
export const CLOSURE_REASON_LABELS: Record<ClosureReason, string> = {
	no_longer_used: 'No longer used',
	sold: 'Sold',
	transferred_out: 'Transferred to another account',
	duplicate: 'Duplicate of another account',
	institution_closed: 'Closed by the institution',
	other: 'Other'
};
