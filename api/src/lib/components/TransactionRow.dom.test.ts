// TransactionRow.dom.test.ts — SELF-340 (F/CTO ruled, A+C-deferred) — the Edit-button UI mirror:
// a security-linked row never OFFERS Edit (reverseAndReplaceTrans's cash-only replacement would
// silently drop the security link); Categorize stays offered (the 023 overlay is unaffected);
// the pre-existing `frozen` gate is unchanged (both actions still hidden entirely when frozen).
//
// This is defense-in-depth, NOT the boundary — Backend's server-side refusal is the real fence;
// these tests only pin what the UI OFFERS, mirroring SubCatPicker.dom.test.ts's house pattern.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/svelte';
import TransactionRow from './TransactionRow.svelte';
import type { SubCatGroup, TransactionView } from '$lib/transaction-util';

const GROUPS: SubCatGroup[] = [{ label: 'Expense', options: [{ value: '10', label: 'Groceries' }] }];

function trans(overrides: Partial<TransactionView> = {}): TransactionView {
	return {
		trans_id: 501,
		transaction_date: '2026-08-01',
		amount: -42,
		vendor: 'AMAZON',
		description: null,
		transaction_type: 'standard',
		is_reverse: false,
		replaces_trans_id: null,
		created_at: '2026-08-01T00:00:00Z',
		category: null,
		note: null,
		splits: [],
		split_count: 0,
		...overrides
	};
}

describe('TransactionRow — Edit-button UI mirror (SELF-340)', () => {
	it('a cash row (security_id: null) offers both Edit and Categorize', () => {
		const { getByRole } = render(TransactionRow, {
			props: { transaction: trans({ security_id: null }), subCatGroups: GROUPS, columns: 6, frozen: false }
		});
		expect(getByRole('button', { name: 'Edit' })).toBeTruthy();
		expect(getByRole('button', { name: 'Categorize' })).toBeTruthy();
	});

	it('a security-linked row (security_id set) offers Categorize but NOT Edit', () => {
		const { getByRole, queryByRole } = render(TransactionRow, {
			props: { transaction: trans({ security_id: 42 }), subCatGroups: GROUPS, columns: 6, frozen: false }
		});
		expect(queryByRole('button', { name: 'Edit' })).toBeNull();
		expect(getByRole('button', { name: 'Categorize' })).toBeTruthy();
	});

	it('an unwired row (security_id undefined) fails CLOSED — no Edit, same as a confirmed security row', () => {
		// Deliberately does not set security_id at all — proves the field's OWN fail-closed
		// default (transaction-util.ts), not a special case coded into this component.
		const { queryByRole, getByRole } = render(TransactionRow, {
			props: { transaction: trans(), subCatGroups: GROUPS, columns: 6, frozen: false }
		});
		expect(queryByRole('button', { name: 'Edit' })).toBeNull();
		expect(getByRole('button', { name: 'Categorize' })).toBeTruthy();
	});

	it('frozen gate is unchanged: neither Edit nor Categorize renders on a frozen cash row', () => {
		const { queryByRole } = render(TransactionRow, {
			props: { transaction: trans({ security_id: null }), subCatGroups: GROUPS, columns: 6, frozen: true }
		});
		expect(queryByRole('button', { name: 'Edit' })).toBeNull();
		expect(queryByRole('button', { name: 'Categorize' })).toBeNull();
	});
});
