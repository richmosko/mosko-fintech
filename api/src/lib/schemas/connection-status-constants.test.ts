// connection-status-constants.test.ts — SELF-207. Pins the provider-blind connection-state
// value-set + the two load-bearing behaviours: the re-auth-actionable predicate (AC #2 gate —
// institution_down MUST be excluded) and the chip-state derivation precedence.

import { describe, it, expect } from 'vitest';
import {
	CONNECTION_STATUSES,
	needsReauth,
	isUnhealthy,
	isInstitutionDown,
	connectionChipState
} from './connection-status-constants';

describe('CONNECTION_STATUSES', () => {
	it('is the 5-value provider-blind set (VERBATIM from the 015 CHECK)', () => {
		expect([...CONNECTION_STATUSES]).toEqual([
			'healthy',
			'login_required',
			'institution_down',
			'revoked',
			'disconnected'
		]);
	});
});

describe('needsReauth (AC #2 CTA gate)', () => {
	it('is true only for the user-fixable states', () => {
		expect(needsReauth('login_required')).toBe(true);
		expect(needsReauth('revoked')).toBe(true);
		expect(needsReauth('disconnected')).toBe(true);
	});
	it('EXCLUDES institution_down (transient outage, re-auth cannot fix it) and healthy', () => {
		expect(needsReauth('institution_down')).toBe(false);
		expect(needsReauth('healthy')).toBe(false);
	});
});

describe('isUnhealthy / isInstitutionDown', () => {
	it('isUnhealthy is every non-healthy state', () => {
		expect(isUnhealthy('healthy')).toBe(false);
		for (const s of ['login_required', 'institution_down', 'revoked', 'disconnected']) {
			expect(isUnhealthy(s)).toBe(true);
		}
	});
	it('isInstitutionDown pins the info-only state', () => {
		expect(isInstitutionDown('institution_down')).toBe(true);
		expect(isInstitutionDown('login_required')).toBe(false);
	});
});

describe('connectionChipState (precedence: inactive → manual → status)', () => {
	it('inactive wins over everything (sync paused regardless of status/provider)', () => {
		expect(
			connectionChipState({ connection_status: 'login_required', provider: 'plaid', is_active: false })
		).toBe('inactive');
		expect(
			connectionChipState({ connection_status: 'healthy', provider: 'manual', is_active: false })
		).toBe('inactive');
	});

	it('manual/import provider (active) → manual, regardless of connection_status', () => {
		expect(
			connectionChipState({ connection_status: 'healthy', provider: 'manual', is_active: true })
		).toBe('manual');
		expect(
			connectionChipState({ connection_status: 'healthy', provider: 'import', is_active: true })
		).toBe('manual');
	});

	it('active automated provider → maps its connection_status (healthy → fresh)', () => {
		const base = { provider: 'plaid', is_active: true };
		expect(connectionChipState({ ...base, connection_status: 'healthy' })).toBe('fresh');
		expect(connectionChipState({ ...base, connection_status: 'login_required' })).toBe('login_required');
		expect(connectionChipState({ ...base, connection_status: 'institution_down' })).toBe('institution_down');
		expect(connectionChipState({ ...base, connection_status: 'revoked' })).toBe('revoked');
		expect(connectionChipState({ ...base, connection_status: 'disconnected' })).toBe('disconnected');
	});

	it('fails safe to a neutral non-actionable chip for an unknown status', () => {
		expect(
			connectionChipState({ connection_status: 'some_future_state', provider: 'plaid', is_active: true })
		).toBe('inactive');
	});
});
