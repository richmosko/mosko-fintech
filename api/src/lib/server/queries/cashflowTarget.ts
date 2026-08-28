// cashflowTarget.ts — server-side read for pfin.cashflow_target, the SELF-252 settings-editor
// prefill (read side of AC2 + AC9). Backend-owned server surface (ARCH §4.1 allowlist).
//
// RLS-scoped SELECT via the per-request anon/authenticated client (`locals.supabase`) — the
// caller's own session, never service_role (RT-26 / Lock 11). A cross-tenant caller reads zero
// rows and fails closed (AC9).
//
// Row-absent (never provisioned) and a row that exists with both columns NULL MUST read as the
// SAME state — "no targets set" (090's own READER OBLIGATION). This module reuses
// `CashflowTargets` from cashflowCrossAccountRollup.ts rather than defining a second shape for
// the same fact: that type already carries NO row-presence field for exactly this reason (its
// own AC6 note), so the settings editor's prefill and the §2.3.2 rollup's targets agree
// structurally rather than by convention.
//
// Consumed by Frontend's `/settings/cash-flow-targets` loader (AC2): both fields default to the
// existing row's values, BLANK where NULL — an unset field must render empty, never `$0`.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { CashflowTargets } from './cashflowCrossAccountRollup';

const UNSET: CashflowTargets = { income_target_annual: null, expense_target_monthly: null };

/**
 * Load the caller's own pfin.cashflow_target row, or the UNSET shape if no row exists yet.
 * Fail-soft on any read error — mirrors userSettings.ts / cashflowCrossAccountRollup.ts's own
 * posture: a transient read failure degrades to UNSET (the editor renders blank fields) rather
 * than throwing through to the route. This module never writes, so a failed read can never lose
 * a stored target — it can only under-render one until the next successful read.
 */
export async function loadCashflowTarget(supabase: SupabaseClient): Promise<CashflowTargets> {
	try {
		const { data, error } = await supabase
			.schema('pfin')
			.from('cashflow_target')
			.select('income_target_annual, expense_target_monthly')
			.maybeSingle();

		if (error) {
			console.error('[cashflowTarget] read failed → degrading to unset:', error.message);
			return UNSET;
		}

		return (data as CashflowTargets | null) ?? UNSET;
	} catch (e) {
		console.error('[cashflowTarget] threw → degrading to unset:', e instanceof Error ? e.message : String(e));
		return UNSET;
	}
}
