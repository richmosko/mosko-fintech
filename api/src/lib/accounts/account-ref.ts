// account-ref.ts — the CANONICAL browser-side account reference (SELF-199 §2.4.1.d).
//
// SCOPE: this is the single, provider-blind shape that BOTH automated-aggregator connect
// paths converge on — Plaid (`$lib/plaid/contract`) and SimpleFIN (`$lib/simplefin/contract`)
// each map their relay response onto THIS type, and the shared attributes-capture route
// (`/accounts/connect/attributes`) reads `AccountRef[]` without knowing which provider
// produced them (ADR-037 Decision 2 SELF-199 row: "the adapter's returned AccountRef[]" —
// provider-blind). It ships to the browser (non-`server` lib surface): it carries NO
// credential and NO server logic — only the non-secret account descriptors the user needs
// to recognise and classify each selected account.
//
// WHY CANONICAL (was two near-identical per-provider copies): plaid/contract.ts carried
// { account_id, name, mask, type, subtype }; simplefin/contract.ts carried
// { account_id, name, type, subtype, currency }. They differ only in the provider-specific
// optional tail (mask ↔ currency). This module is the superset both satisfy structurally,
// so the attributes route builds against ONE type and both contracts re-export it (single
// anti-drift point — mirrors the account-constants.ts pattern).
//
// CONTRACT OWNERSHIP: the POST body that carries these to the persist action is settled
// WITH Backend (api/CLAUDE.md: "API contracts are Backend's source of truth"). This file
// is the browser's view; the response schemas that produce it are parsed leniently (unknown
// keys stripped, not rejected) so a provider response may grow server-side without breaking
// the client. `.strict()` is reserved for the REQUEST fences (leg-2 exchange / connect /
// the attributes POST), where "no extra key leaves the browser" is the security goal.

import { z } from 'zod';
import { ACCOUNT_TYPES, type AccountType } from '$lib/schemas/account-constants';

/**
 * The canonical account reference. `account_id` is the provider's account identifier —
 * the join key the persist action uses to tie each user-entered attribute set back to the
 * account the adapter returned. Everything else is a best-effort, non-secret descriptor.
 */
export const accountRefSchema = z.object({
	/** Provider account id (Plaid `account_id` / SimpleFIN account id). The join key. */
	account_id: z.string().min(1),
	/** Institution-supplied account name, if any (seeds the editable name field). */
	name: z.string().optional(),
	/** Provider top-level type (Plaid `type`; SimpleFIN sends `'unknown'`). */
	type: z.string().optional(),
	/** Provider subtype — Plaid's account-type signal; seeds the account_type
	 *  recommendation the user confirms/overrides. Absent/unknown ⇒ user sets. */
	subtype: z.string().nullish(),
	/** Last-4 mask — Plaid only; absent for SimpleFIN. Display-only recognition aid. */
	mask: z.string().nullish(),
	/** ISO currency — SimpleFIN only; absent for Plaid. Display-only. */
	currency: z.string().optional()
});

export type AccountRef = z.infer<typeof accountRefSchema>;

/**
 * The payload a connect widget emits on success — the provider-blind result the connect
 * step carries CLIENT-SIDE to the attributes route (SELF-199 seam (b): client-carries-refs,
 * no server-side transient store). `linkedSourceId` is the `pfin.linked_source` row the
 * relay created for this connection (ADR-037 substrate; `account.linked_source_id` FK) —
 * carried so the attributes POST can hand it to the persist RPC. Nullable until Backend
 * confirms the relay always returns it; the attributes route fail-closes if it is absent.
 */
export type ConnectResult = {
	linkedSourceId: string | null;
	accounts: AccountRef[];
};

/**
 * Best-effort map from a provider subtype/type to a recommended ACCOUNT_TYPE, per the
 * ADR-037 SELF-199 reconciliation: "adapter-supplied account metadata seeds the form;
 * absent → user sets." This is a UX CONFIRM/OVERRIDE recommendation, NOT a classification
 * authority — the user always confirms and can change it, and the server schema
 * (.strict() + enum) is the boundary regardless of what we recommend here. Conservative
 * by design: anything we can't map with confidence returns undefined so the field starts
 * unselected rather than mis-seeded. Keyed primarily on Plaid's `subtype` vocabulary,
 * falling back to the coarse `type`. SimpleFIN refs (`type:'unknown'`, no subtype) fall
 * through to undefined — the intended "user sets" path.
 */
export function recommendAccountType(ref: Pick<AccountRef, 'type' | 'subtype'>): AccountType | undefined {
	const subtype = ref.subtype?.trim().toLowerCase() ?? '';
	const type = ref.type?.trim().toLowerCase() ?? '';

	// Subtype is the stronger signal — check it first.
	const bySubtype: Record<string, AccountType> = {
		// depository
		checking: 'depository',
		savings: 'depository',
		cd: 'depository',
		'money market': 'depository',
		'cash management': 'depository',
		'prepaid': 'depository',
		ebt: 'depository',
		// retirement (tax-advantaged wrappers)
		'401k': 'retirement',
		'401a': 'retirement',
		'403b': 'retirement',
		'457b': 'retirement',
		ira: 'retirement',
		roth: 'retirement',
		'roth 401k': 'retirement',
		pension: 'retirement',
		'retirement': 'retirement',
		hsa: 'retirement',
		'thrift savings plan': 'retirement',
		sep: 'retirement',
		simple: 'retirement',
		sarsep: 'retirement',
		// investment (taxable brokerage & fund wrappers)
		brokerage: 'investment',
		'non-taxable brokerage account': 'investment',
		'mutual fund': 'investment',
		'stock plan': 'investment',
		'ugma': 'investment',
		'utma': 'investment',
		'529': 'investment',
		'education savings account': 'investment',
		'trust': 'investment',
		'cash isa': 'investment',
		'stocks and shares isa': 'investment',
		// liability (credit & loans)
		'credit card': 'liability',
		'paypal credit': 'liability',
		'line of credit': 'liability',
		'auto': 'liability',
		'business': 'liability',
		'commercial': 'liability',
		'construction': 'liability',
		'consumer': 'liability',
		'home equity': 'liability',
		'loan': 'liability',
		'mortgage': 'liability',
		'overdraft': 'liability',
		'student': 'liability',
		// crypto
		'crypto exchange': 'crypto',
		'cryptocurrency': 'crypto'
	};
	if (subtype && bySubtype[subtype]) return bySubtype[subtype];

	// Coarse type fallback (Plaid top-level `type`).
	const byType: Record<string, AccountType> = {
		depository: 'depository',
		investment: 'investment',
		brokerage: 'investment',
		credit: 'liability',
		loan: 'liability'
	};
	if (type && byType[type]) return byType[type];

	return undefined;
}

/** Defensive guard used by the attributes route: is this a plausible recommendation
 *  we can preselect? (Belt-and-braces against a future ACCOUNT_TYPES change.) */
export function isKnownAccountType(v: string | undefined): v is AccountType {
	return v !== undefined && (ACCOUNT_TYPES as readonly string[]).includes(v);
}
