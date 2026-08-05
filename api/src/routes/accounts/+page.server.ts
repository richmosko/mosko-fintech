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
// Shows BOTH open and closed accounts (partitioned client-side into the grouped list + the
// collapsed Closed group per the wireframe) — this is a MANAGEMENT + RENDER surface, so it
// applies NO closure filter at all, and the partition is a CURRENT-STATE question:
// `closed_at !== null`, which is correct AND complete here. The as-of form of the ADR-042
// closure contract (api/CLAUDE.md) belongs to the VALUATION surfaces (NAV / aggregation /
// counts) and would be WRONG here rather than merely heavier — it needs an `as_of` this page
// has no business choosing. Stated affirmatively, not as "the filter does not apply": saying
// only what does NOT apply leaves the next reader to guess what does.
// This page renders NO gross total / NAV (PM-2 value-semantics pin); the number lives on
// the Net Worth dashboard.

import { redirect } from '@sveltejs/kit';
import { loadConnectionStates } from '$lib/server/queries/connectionState';
import type { PageServerLoad } from './$types';

// RLS-scoped read. acct_number intentionally NOT selected — masked-only render posture (SD-15).
const ACCOUNT_COLUMNS =
	'account_id, name, account_type, scope, tax_treatment, closed_at, linked_source_id';

/** The account-row shape the Hub renders — chip inputs resolved server-side (anti-drift). */
export type HubAccount = {
	account_id: number;
	name: string;
	account_type: string;
	scope: string;
	tax_treatment: string;
	/** Closure timestamp (ISO) or null when open — ADR-042 / 059. NULL = open, never absent.
	 *  Replaces `is_active: boolean`: this is a SHAPE change across the Backend↔Frontend
	 *  boundary, not a rename, and the date is what lets the list say WHEN rather than merely
	 *  THAT. Partition on `closed_at !== null`; do not collapse it back to a boolean here. */
	closed_at: string | null;
	/** connectionChipState() inputs — `provider: 'manual'` + `connection_status: 'healthy'`
	 *  for a non-linked (manual) account → the neutral "Manual" chip. */
	provider: string;
	connection_status: string;
	/**
	 * The CONNECTION's lifecycle flag (`linked_source.is_active`), for the chip's inactive-first
	 * precedence — NOT the account's closure state (F/CTO ruling).
	 *
	 * ⚠ NAMED `connection_is_active`, NOT `is_active`, DELIBERATELY. The hub previously fed the
	 * chip the ACCOUNT's `is_active` while the chip's documented precedence — "inactive
	 * (is_active=false) → sync is paused regardless of connection health" — describes the
	 * LINKED_SOURCE lifecycle. Two different columns, the same spelling, so no text search could
	 * ever surface the mismatch: it typechecked, it rendered, and it was wrong. The prefix is the
	 * fix — a bare `is_active` on an account-row type is the ambiguity itself.
	 *
	 * `?? true` IS LOAD-BEARING, not a tidy default: a manual account HAS no connection, and
	 * `false` there would render every manual account as sync-paused. There is no sync to pause.
	 * A linked account whose connection-state read degraded also lands here, and `true` is right
	 * for the same reason the neutral 'manual' chip is — degrade to "nothing to report", never to
	 * a false alarm.
	 */
	connection_is_active: boolean;
};

type AccountRow = {
	account_id: number;
	name: string;
	account_type: string;
	scope: string;
	tax_treatment: string;
	closed_at: string | null;
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
			closed_at: a.closed_at,
			provider: conn?.provider ?? 'manual',
			connection_status: conn?.connection_status ?? 'healthy',
			connection_is_active: conn?.is_active ?? true
		};
	});

	return { accounts, error: false };
};
