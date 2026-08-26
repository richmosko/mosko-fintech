// SubCatPicker.ssr.test.ts — SELF-249 render-footprint battery, dep-free via `svelte/server`
// (mirrors NavCompositionTable.ssr.test.ts). Covers what's deterministic without a DOM env: the
// three AC2 render states as static markup, the AC6 disabled attribute + affordance text, and
// that the provider_category hint NEVER appears as the selected option's value.

// @vitest-environment node
import { describe, it, expect } from 'vitest';
import { render } from 'svelte/server';
import SubCatPicker from './SubCatPicker.svelte';
import type { SubCatGroup, TransactionView } from '$lib/transaction-util';

const GROUPS: SubCatGroup[] = [
	{
		label: 'Expense',
		options: [
			{ value: '10', label: 'Groceries' },
			{ value: '11', label: 'Dining' }
		]
	}
];

// The component's OWN scoped CSS literally contains the word "disabled" (`.select-input:disabled`,
// `--c-disabled-bg`), so a whole-body `toContain('disabled')` would pass even with no `disabled`
// attribute rendered. Scope the check to just the <select ...> opening tag to avoid that collision.
function selectTag(body: string): string {
	return body.match(/<select[^>]*>/)?.[0] ?? '';
}

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

describe('SubCatPicker SSR — solid state', () => {
	it('an already-classified row selects the matching option and is not muted', () => {
		const { body } = render(SubCatPicker, {
			props: { transaction: trans({ category: { cat: 'Expense', sub_cat: 'Groceries' } }), subCatGroups: GROUPS }
		});
		expect(body).toContain('<option value="10" selected="">');
		expect(body).not.toContain('is-muted');
		expect(body).not.toContain('Suggested from');
		expect(body).not.toContain('Provider category:');
	});
});

describe('SubCatPicker SSR — suggested state', () => {
	it('a vendor suggestion pre-selects the option and renders muted + the unconfirmed hint', () => {
		const { body } = render(SubCatPicker, {
			props: { transaction: trans({ suggested_sub_cat_id: 11 }), subCatGroups: GROUPS }
		});
		expect(body).toContain('<option value="11" selected="">');
		expect(body).toContain('is-muted');
		expect(body).toContain('Suggested from your vendor history');
	});
});

describe('SubCatPicker SSR — hint state', () => {
	it('the provider_category hint renders as text only — never as the selected option', () => {
		const { body } = render(SubCatPicker, {
			props: { transaction: trans({ provider_category: 'Groceries' }), subCatGroups: GROUPS }
		});
		expect(body).toContain('Provider category: Groceries');
		// The placeholder ("Unsorted") stays selected — no option carrying the Groceries id/label
		// is marked `selected` merely because the hint mentions "Groceries".
		expect(body).not.toContain('<option value="10" selected="">');
		expect(body).toContain('is-muted'); // hint state is also un-confirmed, so still muted
	});
});

describe('SubCatPicker SSR — disabled gate (AC6)', () => {
	it('classifiable:false renders a disabled select and the mapped affordance note, no submit button', () => {
		const { body } = render(SubCatPicker, {
			props: {
				transaction: trans({ classifiable: false, classifiableReason: 'journaled' }),
				subCatGroups: GROUPS
			}
		});
		expect(selectTag(body)).toContain('disabled');
		expect(body).toContain('This transaction is posted to a journal. Detach it from the journal, then reclassify.');
		expect(body).not.toContain('type="submit"');
	});

	it('an unwired transaction (classifiable undefined) renders enabled with a submit button', () => {
		const { body } = render(SubCatPicker, { props: { transaction: trans(), subCatGroups: GROUPS } });
		expect(selectTag(body)).not.toContain('disabled');
		expect(body).toContain('type="submit"');
	});
});
