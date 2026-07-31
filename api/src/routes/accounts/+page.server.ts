// accounts/+page.server.ts — the Accounts Hub landing (sidebar destination #1 per the
// §2.4 wireframe §1). Backend-owned server source (ARCH §4.1 allowlist).
//
// Fixes the /accounts 404: five breadcrumbs (accounts/{new,connect,connect/attributes,
// connections,[account_id]}) and TWO redirects — most notably accounts/connect/attributes
// redirect(303, '/accounts') on a successful institution connect — all target /accounts,
// which had no index route.
//
// load(): auth-gate, then read the caller's accounts (RLS-scoped anon client — NEVER
// service_role) and their connection states, and shape each account row with the chip
// inputs (provider + connection_status) SERVER-SIDE. The connection SEMANTIC is Backend's
// (Frontend renders it), matching the SELF-207 connection-state discipline. Both reads fail
// SOFT — a connection-read failure degrades linked accounts to a neutral chip; it never
// blocks the account list.
//
// Shows BOTH active and inactive accounts (partitioned client-side into the grouped list +
// the collapsed Inactive group per the wireframe) — this is a management surface, so the
// NAV/current-state `WHERE is_active = TRUE` CONTRACT (api/CLAUDE.md) does NOT apply here.
// This page renders NO gross total / NAV (PM-2 value-semantics pin); the number lives on
// the Net Worth dashboard.

import { redirect } from '@sveltejs/kit';
import { loadConnectionStates } from '$lib/server/queries/connectionState';
import type { PageServerLoad } from './$types';

// RLS-scoped read. acct_number intentionally NOT selected — masked-only render posture (SD-15).
const ACCOUNT_COLUMNS =
	'account_id, name, account_type, scope, tax_treatment, is_active, linked_source_id';

/** The account-row shape the Hub renders — chip inputs resolved server-side (anti-drift). */
export type HubAccount = {
	account_id: number;
	name: string;
	account_type: string;
	scope: string;
	tax_treatment: string;
	is_active: boolean;
	/** connectionChipState() inputs — `provider: 'manual'` + `connection_status: 'healthy'`
	 *  for a non-linked (manual) account → the neutral "Manual" chip. */
	provider: string;
	connection_status: string;
};

type AccountRow = {
	account_id: number;
	name: string;
	account_type: string;
	scope: string;
	tax_treatment: string;
	is_active: boolean;
	linked_source_id: number | string | null;
};

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	// Preserve where the user was headed so /login can bounce them back (SELF-285).
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	// ── the account list (primary data; RLS-scoped to auth.uid()) ─────────────────
	const { data, error: acctErr } = await locals.supabase
		.schema('pfin')
		.from('account')
		.select(ACCOUNT_COLUMNS)
		.order('name', { ascending: true });

	if (acctErr) {
		console.error('[accounts] account list read failed:', acctErr.message);
		// error:true → the Hub shows a retriable message, distinct from a true-empty (no accounts).
		return { accounts: [] as HubAccount[], error: true };
	}

	// ── connection states (secondary; fail SOFT → linked rows degrade to a neutral chip) ──
	// source_id === account.linked_source_id (same bigint, renamed at the 043-view boundary).
	const { connections } = await loadConnectionStates(locals.supabase);
	const bySource = new Map(connections.map((c) => [c.source_id, c]));

	const accounts: HubAccount[] = ((data ?? []) as AccountRow[]).map((a) => {
		// A linked account resolves its provider + status from its connection state; a manual
		// (non-linked) account — or a linked one whose state read degraded — gets the neutral
		// 'manual' chip (provider 'manual' → connectionChipState returns 'manual').
		const conn = a.linked_source_id == null ? undefined : bySource.get(String(a.linked_source_id));
		return {
			account_id: a.account_id,
			name: a.name,
			account_type: a.account_type,
			scope: a.scope,
			tax_treatment: a.tax_treatment,
			is_active: a.is_active,
			provider: conn?.provider ?? 'manual',
			connection_status: conn?.connection_status ?? 'healthy'
		};
	});

	return { accounts, error: false };
};
