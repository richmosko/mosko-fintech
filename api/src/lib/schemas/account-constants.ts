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

/** Placeholder copy — PM + UX own the final strings. */
export const CLOSURE_REASON_LABELS: Record<ClosureReason, string> = {
	no_longer_used: 'No longer used',
	sold: 'Sold',
	transferred_out: 'Transferred out',
	duplicate: 'Duplicate',
	institution_closed: 'Closed by the institution',
	other: 'Other'
};
