// stale-constituent.test.ts — QA unit battery for the D1 staleness-marker affordance logic
// (SELF-208 · §2.4.4.c · ADR-013 Decision 1). Browser-safe, dep-free (node env).
//
// This module is the single browser-side definition of the staleness payload shape + the
// per-status affordance DECISION that StaleConstituentBadge.svelte renders. The badge is a thin
// presentational shell over these predicates, so exercising them here proves the AC#5 per-status
// affordance selection (Re-authenticate vs informational) deterministically WITHOUT a DOM env.
// The component's render/remove FOOTPRINT is proven separately by the SSR test
// (StaleConstituentBadge.ssr.test.ts). See that file's header for the disclosure-panel gap note.

import { describe, it, expect } from 'vitest';
import {
	staleAffordance,
	hasReauthActionable,
	EMPTY_STALENESS,
	type StaleConstituentItem
} from './stale-constituent';

const mk = (status: string, id = 1): StaleConstituentItem => ({
	linked_source_id: id,
	institution_name: `Bank ${id}`,
	provider: 'plaid',
	connection_status: status,
	status_class: null
});

describe('staleAffordance — per-status affordance keyed on connection_status (046 contract)', () => {
	// REAUTH set: owner can fix by re-authenticating → the badge shows a "Re-authenticate" link.
	it.each(['login_required', 'revoked', 'disconnected'])(
		'%s → reauth (re-auth link)',
		(status) => {
			expect(staleAffordance(status)).toBe('reauth');
		}
	);

	// institution_down: transient provider outage → informational "temporarily unavailable", NO link
	// (re-auth cannot fix it) — marked-but-not-reauth, per the 046 header.
	it('institution_down → institution-down (informational, no re-auth link)', () => {
		expect(staleAffordance('institution_down')).toBe('institution-down');
	});

	// Forward-compat: any unknown non-healthy value is marked but NOT mis-actioned as re-auth
	// (D1 never-silently-fresh; fail-safe).
	it('unknown status → info (marked, not offered a mis-firing re-auth)', () => {
		expect(staleAffordance('some_future_status')).toBe('info');
	});
});

describe('hasReauthActionable — drives the panel-level "Review connections" CTA presence', () => {
	it('true when >=1 item is re-auth-actionable', () => {
		expect(hasReauthActionable([mk('institution_down', 1), mk('login_required', 2)])).toBe(true);
	});

	it('false when NO item is re-auth-actionable (all institution_down / info)', () => {
		expect(hasReauthActionable([mk('institution_down', 1), mk('some_future_status', 2)])).toBe(
			false
		);
	});

	it('false on the empty list', () => {
		expect(hasReauthActionable([])).toBe(false);
	});
});

describe('EMPTY_STALENESS — the loader-absent / fail-soft zero-value (staleness.ts degrade target)', () => {
	it('is the unambiguous not-stale value: is_stale=false, stale_items=[]', () => {
		expect(EMPTY_STALENESS.is_stale).toBe(false);
		expect(EMPTY_STALENESS.stale_items).toEqual([]);
	});
});
