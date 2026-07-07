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
