// webhookStatus.test.ts — SELF-206 AC4/AC5 Plaid → provider-agnostic normalization.

import { describe, it, expect } from 'vitest';
import { plaidStatusTransition, isTransactionsEvent } from './webhookStatus';
import { CONNECTION_STATUSES } from '$lib/schemas/connection-status-constants';

describe('plaidStatusTransition — ITEM error_code mapping (AC4)', () => {
	it('ITEM_LOGIN_REQUIRED → login_required (raw code retained)', () => {
		expect(plaidStatusTransition('ITEM', 'ERROR', 'ITEM_LOGIN_REQUIRED')).toEqual({
			statusClass: 'login_required',
			providerErrorCode: 'ITEM_LOGIN_REQUIRED'
		});
	});

	it('institution-outage codes → institution_down (info-only, no re-auth CTA)', () => {
		for (const code of ['INSTITUTION_DOWN', 'INSTITUTION_NOT_RESPONDING', 'INSTITUTION_NO_LONGER_SUPPORTED']) {
			expect(plaidStatusTransition('ITEM', 'ERROR', code)?.statusClass).toBe('institution_down');
		}
	});

	it('ITEM_NO_ERROR → healthy', () => {
		expect(plaidStatusTransition('ITEM', 'ERROR', 'ITEM_NO_ERROR')?.statusClass).toBe('healthy');
	});

	it('M6: an UNRECOGNIZED ITEM error → login_required (never silently dropped; raw code kept)', () => {
		expect(plaidStatusTransition('ITEM', 'ERROR', 'SOME_NEW_PLAID_CODE')).toEqual({
			statusClass: 'login_required',
			providerErrorCode: 'SOME_NEW_PLAID_CODE'
		});
	});

	it('ITEM ERROR with no error_code → login_required with a synthetic raw code', () => {
		expect(plaidStatusTransition('ITEM', 'ERROR', null)).toEqual({
			statusClass: 'login_required',
			providerErrorCode: 'ITEM_ERROR'
		});
	});
});

describe('plaidStatusTransition — ITEM webhook_code mapping (AC4)', () => {
	it('PENDING_EXPIRATION / PENDING_DISCONNECT → login_required', () => {
		expect(plaidStatusTransition('ITEM', 'PENDING_EXPIRATION', null)?.statusClass).toBe('login_required');
		expect(plaidStatusTransition('ITEM', 'PENDING_DISCONNECT', null)?.statusClass).toBe('login_required');
	});

	it('USER_PERMISSION_REVOKED / USER_ACCOUNT_REVOKED → revoked', () => {
		expect(plaidStatusTransition('ITEM', 'USER_PERMISSION_REVOKED', null)?.statusClass).toBe('revoked');
		expect(plaidStatusTransition('ITEM', 'USER_ACCOUNT_REVOKED', null)?.statusClass).toBe('revoked');
	});

	it('LOGIN_REPAIRED → healthy', () => {
		expect(plaidStatusTransition('ITEM', 'LOGIN_REPAIRED', null)?.statusClass).toBe('healthy');
	});

	it('informational ITEM codes → null (no health flip)', () => {
		expect(plaidStatusTransition('ITEM', 'WEBHOOK_UPDATE_ACKNOWLEDGED', null)).toBeNull();
		expect(plaidStatusTransition('ITEM', 'NEW_ACCOUNTS_AVAILABLE', null)).toBeNull();
	});

	it('every emitted statusClass is a member of the canonical 015 set', () => {
		const codes = ['ITEM_LOGIN_REQUIRED', 'INSTITUTION_DOWN', 'ITEM_NO_ERROR', 'WEIRD'];
		for (const c of codes) {
			const t = plaidStatusTransition('ITEM', 'ERROR', c);
			if (t) expect((CONNECTION_STATUSES as readonly string[]).includes(t.statusClass)).toBe(true);
		}
	});
});

describe('plaidStatusTransition — non-ITEM types carry no health change', () => {
	it('TRANSACTIONS / HOLDINGS → null', () => {
		expect(plaidStatusTransition('TRANSACTIONS', 'SYNC_UPDATES_AVAILABLE', null)).toBeNull();
		expect(plaidStatusTransition('HOLDINGS', 'DEFAULT_UPDATE', null)).toBeNull();
	});
});

describe('isTransactionsEvent (AC5 gate)', () => {
	it('true only for the TRANSACTIONS type', () => {
		expect(isTransactionsEvent('TRANSACTIONS')).toBe(true);
		expect(isTransactionsEvent('ITEM')).toBe(false);
		expect(isTransactionsEvent('HOLDINGS')).toBe(false);
	});
});
