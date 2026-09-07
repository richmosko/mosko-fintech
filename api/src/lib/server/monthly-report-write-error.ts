// monthly-report-write-error.ts — the shared RPC-failure mapper for the FOUR aal2-guarded
// monthly-report write actions: `?/generate` (113, pfin.fn_open_monthly_report_draft),
// `?/regenerate` (114, pfin.fn_regenerate_monthly_report), and BOTH `?/skip` and `?/finalize`
// (115, pfin.fn_finalize_monthly_report — two call sites, two files). EXTRACTED at the SELF-356
// close-out follow-up (Sec self356-sec-review.md's completed per-action table) from what had been
// two near-identical `mapFinalizeError` copies (one per file) plus two actions (`generate`,
// `regenerate`) that had NO mapper at all — see self357-sec-review.md's own finding: every RPC
// failure on those two, including a LIVE 42501, was collapsing to an undifferentiated 500.
//
// P3's `?/save` (112, pfin.fn_save_monthly_commentary) is DELIBERATELY NOT folded in here — 112
// raises an extra `23514` (DB length CHECK) case these four don't, so `mapSaveError` stays local
// to `commentary/+page.server.ts`.
//
// ── THE AAL2 BACKSTOP (why every one of these four needs the SAME two live branches) ──────────
// Migration 108's `authenticated` RLS policies on `pfin.monthly_report` carry the 025 aal2
// backstop clause. Sec's per-action table (self356-sec-review.md) measured each RPC's own
// statement order against it:
//
//   route · action | RPC | refusal shape                        | 42501 reachable?
//   P5 · generate   | 113 | empty lock -> INSERT's own WITH CHECK | YES — LIVE, the only one
//   P5 · regenerate | 114 | zero rows to lock -> P0001            | no (dead)
//   P4 · skip       | 115 | zero rows to lock -> P0001            | no (dead)
//   P4 · finalize   | 115 | zero rows to lock -> P0001            | no (dead)
//
// 113 is unique: its refusal reaches an INSERT whose own `WITH CHECK` can raise a genuine 42501.
// 114 and 115 both refuse by finding ZERO ROWS to lock in a `SELECT ... FOR UPDATE` that runs
// BEFORE any write statement, so the below-aal2 caller never reaches an INSERT/UPDATE that could
// itself raise 42501 — the refusal surfaces as P0001 instead. The `42501` branch below is
// therefore dead on three of these four callers today; it stays in the shared mapper (rather than
// being trimmed to only `?/generate`) because (a) `?/generate`'s own live case needs it and this
// IS the shared mapper, and (b) a future RPC change that adds a direct write to 114/115 would need
// this branch already in place — removing it would silently reopen the exact gap self357 found.
//
// Every message is uniform across ALL of its trigger conditions (missing report / wrong
// generation_status / below-aal2 session) — non-disclosure by construction, the same posture
// `mapSaveError` and the Lock-14 direct-write mappers (`settings/owner-id`, `settings/tax-
// brackets`) already take: a cross-tenant caller, an owner whose report is gone, and an
// MFA-enrolled owner on a stale session all see the identical copy.

import type { PostgrestError } from '@supabase/supabase-js';

/**
 * Maps a failure from 113/114/115 to a clean 4xx/5xx. `logContext` is a short per-call-site tag
 * (e.g. `'reports/monthly generate'`) so the default-branch `console.error` still names which
 * action failed, now that the mapping logic itself is shared.
 */
export function mapMonthlyReportWriteError(
	error: PostgrestError,
	logContext: string
): { status: number; message: string } {
	switch (error.code) {
		case '42501':
			// LIVE on `?/generate` (113's empty-lock path reaches an INSERT's own WITH CHECK) —
			// MUST stay live there. Dead on `?/regenerate`/`?/skip`/`?/finalize` (114/115 refuse by
			// finding zero rows to lock, never reaching a write statement that could raise this) —
			// kept for shape per this file's own header, not redundant.
			return {
				status: 403,
				message: 'This action requires a freshly verified session. Please step up and try again.'
			};
		case 'P0001':
			return {
				status: 400,
				message:
					'This report may already be finalized, no longer exist, or your session may need re-verification — try signing in again.'
			};
		default:
			console.error(`[${logContext}] unexpected write error:`, error.code, error.message);
			return { status: 500, message: 'Something went wrong. Please try again.' };
	}
}
