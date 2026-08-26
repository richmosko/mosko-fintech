// TransactionRow.ssr.test.ts — SELF-249 integration point: the Category cell's three-way branch
// (split parent / frozen / live picker) that decides whether SubCatPicker mounts at all. Dep-free
// via `svelte/server` (mirrors NavCompositionTable.ssr.test.ts); SubCatPicker's OWN render states
// are covered exhaustively in SubCatPicker.ssr.test.ts / .dom.test.ts — this file only proves
// TransactionRow routes to the right one of the three per AC7 / the frozen convention.

// @vitest-environment node
import { describe, it, expect } from 'vitest';
import { render } from 'svelte/server';
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

describe('TransactionRow — Category cell routing (SELF-249)', () => {
	it('a normal, non-frozen, non-split row mounts SubCatPicker (a per-row #subcat-<id> select)', () => {
		const { body } = render(TransactionRow, {
			props: { transaction: trans(), subCatGroups: GROUPS, columns: 6, frozen: false }
		});
		expect(body).toContain('id="subcat-501"');
	});

	it('AC7 — a split-parent row (split_count>0) mounts NO picker at all, only the split tag', () => {
		const { body } = render(TransactionRow, {
			props: {
				transaction: trans({
					split_count: 2,
					splits: [
						{ id: 1, amount: -20, cat: 'Expense', sub_cat: 'Groceries', note: null, display_order: 0 },
						{ id: 2, amount: -22, cat: 'Expense', sub_cat: 'Dining', note: null, display_order: 1 }
					]
				}),
				subCatGroups: GROUPS,
				columns: 6,
				frozen: false
			}
		});
		expect(body).toContain('Split · 2');
		expect(body).not.toContain('id="subcat-501"');
	});

	it('a frozen (closed-account) row falls back to the plain read-only label, not the picker', () => {
		const { body } = render(TransactionRow, {
			props: { transaction: trans({ category: { cat: 'Expense', sub_cat: 'Groceries' } }), subCatGroups: GROUPS, columns: 6, frozen: true }
		});
		expect(body).not.toContain('id="subcat-501"');
		expect(body).toContain('Groceries');
	});

	it('a reversal row (is_reverse) STILL mounts the picker — disabled-render, not a hide (AC6 general rule)', () => {
		const { body } = render(TransactionRow, {
			props: {
				transaction: trans({ is_reverse: true, classifiable: false, classifiableReason: 'is_reversal' }),
				subCatGroups: GROUPS,
				columns: 6,
				frozen: false
			}
		});
		expect(body).toContain('id="subcat-501"');
		expect(body).toContain('A reversal row can’t be classified here.');
	});
});
