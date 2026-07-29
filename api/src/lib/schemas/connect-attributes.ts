// connect-attributes.ts — CLIENT-SIDE Zod mirror of the SELF-199 per-account attribute
// capture submit (§2.4.1.d). PROPOSED contract — settled WITH Backend (they own the
// server-side `.strict()` schema + the `fn_land_linked_accounts` RPC that consumes it;
// api/CLAUDE.md: "API contracts are Backend's source of truth"). Field names / shape track
// whatever Backend's server schema locks; update this mirror in lockstep when it lands.
//
// DISCIPLINE (Lock 14 / api/CLAUDE.md): this is the browser-side UX fast-feedback layer,
// NOT the security boundary. The SERVER schema is the `.strict()` mass-assignment fence and
// the real validation. This mirror must never be LOOSER than the server's: same `.strict()`
// posture (envelope AND each account object), same value-sets (imported from the shared
// browser-safe `account-constants` — the single anti-drift point the manual-account form
// also uses), same min/max.
//
// SHAPE: the attributes step captures four USER attributes per selected account —
//   • name          free-text label            (1..200)
//   • scope         free-text ownership label   (1..200)  ← ADR-004 Dec B: user-defined
//                    ownership label ("Rich personal" / "RichMoskoTrust" / "Retirement-IRA"),
//                    NOT an isolation boundary. Same 1..200 shape as manual-account scope.
//   • tax_treatment TAX_TREATMENTS enum
//   • account_type  ACCOUNT_TYPES enum          ← seeded from the adapter subtype as a
//                    confirm/override recommendation; absent → user sets (ADR-037 SELF-199).
// plus the carried join key:
//   • account_id    the provider AccountRef id  (opaque; identifies which account these
//                    attributes belong to). NOT user-editable.
// The balance/valuation is NOT captured here — the connection supplies it. (Contrast the
// manual-account form, which captures initial_value + as_of_date.)

import { z } from 'zod';
import { ACCOUNT_TYPES, TAX_TREATMENTS } from '$lib/schemas/account-constants';

/** One account's attribute set. `.strict()` — no extra key rides along (mass-assignment
 *  fence mirror). Enum messages are friendlier than the raw enum error — a UX nicety, NOT a
 *  loosening (same value-set, same `.strict()`). */
export const connectAccountAttributesSchema = z
	.object({
		/** Provider AccountRef id — the join key; opaque, carried from the connect step.
		 *  `.trim()` mirrors the server (`linkedAccountAttrSchema.account_id`). */
		account_id: z.string().trim().min(1, 'Missing account reference.'),
		name: z.string().trim().min(1, 'Name is required.').max(200, 'Name is too long.'),
		scope: z.string().trim().min(1, 'Scope is required.').max(200, 'Scope is too long.'),
		tax_treatment: z.enum(TAX_TREATMENTS, { message: 'Choose a tax treatment.' }),
		account_type: z.enum(ACCOUNT_TYPES, { message: 'Choose an account type.' })
	})
	.strict();

export type ConnectAccountAttributes = z.infer<typeof connectAccountAttributesSchema>;

/**
 * The full submit envelope: the linked_source this batch belongs to + one attribute set per
 * selected account. `.strict()`; `linked_source_id` is `pfin.linked_source.source_id` — a
 * **bigint serialized as a decimal string** (e.g. "42"), NOT a UUID — so a numeric-string
 * regex mirrors Backend's server envelope exactly. `.min(1)` on the array so an empty submit
 * (the "unselected accounts are never persisted" no-op) is rejected client-side before the
 * round trip. All shape only — the server schema is the security boundary.
 */
export const connectAttributesSubmitSchema = z
	.object({
		linked_source_id: z.string().trim().regex(/^\d+$/, 'Missing connection reference.'),
		// .min(1): the client only includes SELECTED accounts; an empty submit is a
		// client-prevented no-op. .max(100): mirrors the server cap (`landLinkedAccountsSchema`)
		// so the client is never LOOSER than the security boundary.
		accounts: z
			.array(connectAccountAttributesSchema)
			.min(1, 'No accounts to save.')
			.max(100, 'Too many accounts in one submission.')
	})
	.strict();

export type ConnectAttributesSubmit = z.infer<typeof connectAttributesSubmitSchema>;

/**
 * Flatten a ZodError from a per-account parse into `{ field: [messages] }` keyed by the
 * top-level field. Mirrors the account.ts helper so client + server errors render through one
 * code path. Root-level issues bucket under `_form`. (Used per-row: the attributes page
 * validates each account object independently so errors attach to the right row.)
 */
export function fieldErrors(error: z.ZodError): Record<string, string[]> {
	const out: Record<string, string[]> = {};
	for (const issue of error.issues) {
		const key = issue.path.length ? String(issue.path[0]) : '_form';
		(out[key] ??= []).push(issue.message);
	}
	return out;
}
