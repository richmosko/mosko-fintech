// SubCatPicker.dom.test.ts — SELF-249 per-row Sub-Cat picker (AC2/AC4/AC6). DOM battery:
// three render states (solid / suggested / hint), the disabled gate, submit success/failure, and
// two inversion checks — the disabled gate is a REAL block (not decoration chained to a disabled
// attribute) and the provider-category hint is NEVER a write (mounting never fires the relay).
//
// ENV: jsdom (per-file pragma, mirrors NavCompositionTable.dom.test.ts) + @testing-library/svelte.
//
// @vitest-environment jsdom

import { describe, it, expect, vi } from 'vitest';
import { render, fireEvent, within } from '@testing-library/svelte';
import SubCatPicker from './SubCatPicker.svelte';
import { ClassifyError } from '$lib/transactions/classifyFlow';
import type { SubCatGroup, TransactionView } from '$lib/transaction-util';

const GROUPS: SubCatGroup[] = [
	{
		label: 'Expense',
		options: [
			{ value: '10', label: 'Groceries' },
			{ value: '11', label: 'Dining' }
		]
	},
	{ label: 'Income', options: [{ value: '20', label: 'Paycheck' }] }
];

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

describe('SubCatPicker — three render states (AC2)', () => {
	it('solid: an already-classified row preselects the current value, not muted, no hint text', () => {
		const { getByRole, queryByText } = render(SubCatPicker, {
			props: {
				transaction: trans({ category: { cat: 'Expense', sub_cat: 'Groceries' }, sub_cat_id: 10 }),
				subCatGroups: GROUPS
			}
		});
		const select = getByRole('combobox') as HTMLSelectElement;
		expect(select.value).toBe('10');
		expect(queryByText(/Suggested from your vendor history/)).toBeNull();
		expect(queryByText(/Provider category:/)).toBeNull();
	});

	it('Sec FLAG-D: a note-only annotation (category non-null, sub_cat_id null) is NOT solid — falls through to suggested/hint', () => {
		// subCatLabel (taxonomy.ts) never returns null, so a note-only annotation still produces a
		// non-null `category: { cat: null, sub_cat: 'Unsorted' }`. `classified` must key on
		// `sub_cat_id`, not `category`, or this row wrongly renders solid with no hint/suggestion.
		const { getByRole, getByText } = render(SubCatPicker, {
			props: {
				transaction: trans({ category: { cat: null, sub_cat: 'Unsorted' }, sub_cat_id: null, suggested_sub_cat_id: 11 }),
				subCatGroups: GROUPS
			}
		});
		const select = getByRole('combobox') as HTMLSelectElement;
		expect(select.value).toBe('11');
		expect(getByText(/Suggested from your vendor history — not saved until confirmed\./)).toBeTruthy();
	});

	it('Sec FLAG-D: same note-only annotation, no suggestion either → falls through to the hint state, not solid', () => {
		const { getByRole, getByText } = render(SubCatPicker, {
			props: {
				transaction: trans({
					category: { cat: null, sub_cat: 'Unsorted' },
					sub_cat_id: null,
					provider_category: 'Groceries'
				}),
				subCatGroups: GROUPS
			}
		});
		const select = getByRole('combobox') as HTMLSelectElement;
		expect(select.value).toBe('');
		expect(getByText('Provider category: Groceries')).toBeTruthy();
	});

	it('suggested: no override but a vendor suggestion pre-fills the value with an unconfirmed hint', () => {
		const { getByRole, getByText } = render(SubCatPicker, {
			props: { transaction: trans({ suggested_sub_cat_id: 11 }), subCatGroups: GROUPS }
		});
		const select = getByRole('combobox') as HTMLSelectElement;
		expect(select.value).toBe('11');
		expect(getByText(/Suggested from your vendor history — not saved until confirmed\./)).toBeTruthy();
	});

	it('hint: no override and no suggestion → stays Unsorted; provider_category renders as a ghost hint, never the value', () => {
		const { getByRole, getByText } = render(SubCatPicker, {
			props: { transaction: trans({ provider_category: 'Groceries' }), subCatGroups: GROUPS }
		});
		const select = getByRole('combobox') as HTMLSelectElement;
		expect(select.value).toBe('');
		expect(getByText('Provider category: Groceries')).toBeTruthy();
	});

	it('no override, no suggestion, no provider_category → Unsorted, no hint text at all', () => {
		const { getByRole, queryByText } = render(SubCatPicker, {
			props: { transaction: trans(), subCatGroups: GROUPS }
		});
		expect((getByRole('combobox') as HTMLSelectElement).value).toBe('');
		expect(queryByText(/Provider category:/)).toBeNull();
		expect(queryByText(/Suggested from/)).toBeNull();
	});
});

describe('SubCatPicker — Sec FLAG-B: Trade is never offered', () => {
	it('filters a Trade group out of the rendered options even when subCatGroups carries one', () => {
		const groupsWithTrade: SubCatGroup[] = [
			...GROUPS,
			{ label: 'Trade', options: [{ value: '99', label: 'Buy' }] }
		];
		const { getByRole, queryByText } = render(SubCatPicker, {
			props: { transaction: trans(), subCatGroups: groupsWithTrade }
		});
		const select = getByRole('combobox') as HTMLSelectElement;
		expect(within(select).queryByText('Buy')).toBeNull();
		expect(queryByText('Trade')).toBeNull();
		// The sibling group is untouched — this is a targeted exclusion, not an empty picker.
		expect(within(select).getByText('Groceries')).toBeTruthy();
	});
});

describe('SubCatPicker — disabled gate (AC6)', () => {
	it('QA walk regression (tip 691f7cb, trans 5556/5557): an already-classified Trade row (has_security) renders its label, not blank', () => {
		// The FLAG-B Trade filter must NOT apply here: this row's own value IS a Trade sub_cat
		// (legitimate per 084's biconditional — security_id present <=> cat='Trade' — which is
		// exactly why has_security makes it non-classifiable). Filtering unconditionally removed
		// the option the bound value needed, so the disabled select rendered blank.
		const tradeGroups: SubCatGroup[] = [...GROUPS, { label: 'Trade', options: [{ value: '470', label: 'BTO' }] }];
		const { getByRole } = render(SubCatPicker, {
			props: {
				transaction: trans({
					category: { cat: 'Trade', sub_cat: 'BTO' },
					sub_cat_id: 470,
					classifiable: false,
					classifiableReason: 'has_security'
				}),
				subCatGroups: tradeGroups
			}
		});
		const select = getByRole('combobox') as HTMLSelectElement;
		expect(select.value).toBe('470');
		expect(select.disabled).toBe(true);
		expect(within(select).getByText('BTO')).toBeTruthy();
	});

	it('classifiable:false disables the select, hides the submit control, and shows the mapped affordance text', () => {
		const { getByRole, queryByRole, getByText } = render(SubCatPicker, {
			props: {
				transaction: trans({ classifiable: false, classifiableReason: 'is_reversal' }),
				subCatGroups: GROUPS
			}
		});
		expect((getByRole('combobox') as HTMLSelectElement).disabled).toBe(true);
		expect(queryByRole('button')).toBeNull();
		expect(getByText('A reversal row can’t be classified here. Classify the original transaction it replaces.')).toBeTruthy();
	});

	it('an unrecognized/absent reason still renders a safe generic affordance note, never a blank one', () => {
		const { getByText } = render(SubCatPicker, {
			props: { transaction: trans({ classifiable: false, classifiableReason: null }), subCatGroups: GROUPS }
		});
		expect(getByText('Could not save the category. Please try again.')).toBeTruthy();
	});

	it('an unwired transaction (classifiable undefined) defaults to classifiable — control is live, not disabled', () => {
		const { getByRole } = render(SubCatPicker, { props: { transaction: trans(), subCatGroups: GROUPS } });
		expect((getByRole('combobox') as HTMLSelectElement).disabled).toBe(false);
		expect(getByRole('button')).toBeTruthy();
	});
});

describe('SubCatPicker — submit (AC4)', () => {
	it('success: posts the picked sub_cat_id via classifyFn and calls onSuccess to re-validate', async () => {
		const classifyFn = vi.fn().mockResolvedValue({ trans_id: 501, sub_cat_id: 11 });
		const onSuccess = vi.fn();
		const { getByRole } = render(SubCatPicker, {
			props: { transaction: trans(), subCatGroups: GROUPS, classifyFn, onSuccess }
		});
		await fireEvent.change(getByRole('combobox'), { target: { value: '11' } });
		await fireEvent.click(getByRole('button'));
		expect(classifyFn).toHaveBeenCalledWith(501, 11, undefined);
		expect(onSuccess).toHaveBeenCalledOnce();
	});

	it('a suggested value can be CONFIRMED without changing the select first (native change never fires on an untouched value)', async () => {
		const classifyFn = vi.fn().mockResolvedValue({ trans_id: 501, sub_cat_id: 11 });
		const onSuccess = vi.fn();
		const { getByRole } = render(SubCatPicker, {
			props: { transaction: trans({ suggested_sub_cat_id: 11 }), subCatGroups: GROUPS, classifyFn, onSuccess }
		});
		await fireEvent.click(getByRole('button', { name: 'Confirm' }));
		expect(classifyFn).toHaveBeenCalledWith(501, 11, undefined);
		expect(onSuccess).toHaveBeenCalledOnce();
	});

	it('failure: renders the code-mapped copy inline via the SelectField error slot; onSuccess is not called', async () => {
		const classifyFn = vi.fn().mockRejectedValue(new ClassifyError('journaled', 409));
		const onSuccess = vi.fn();
		const { getByRole, findByRole } = render(SubCatPicker, {
			props: { transaction: trans({ suggested_sub_cat_id: 11 }), subCatGroups: GROUPS, classifyFn, onSuccess }
		});
		await fireEvent.click(getByRole('button', { name: 'Confirm' }));
		const alert = await findByRole('alert');
		expect(alert.textContent).toBe('This transaction is posted to a journal. Detach it from the journal, then reclassify.');
		expect(onSuccess).not.toHaveBeenCalled();
	});
});

describe('SubCatPicker — inversion checks', () => {
	it('the disabled gate is a REAL block, not decoration: forcing a submit event while classifiable:false never calls classifyFn', async () => {
		const classifyFn = vi.fn();
		const { container } = render(SubCatPicker, {
			props: {
				transaction: trans({ classifiable: false, classifiableReason: 'journaled', category: { cat: 'Expense', sub_cat: 'Groceries' } }),
				subCatGroups: GROUPS,
				classifyFn
			}
		});
		const form = within(container).getByRole('combobox').closest('form')!;
		await fireEvent.submit(form);
		expect(classifyFn).not.toHaveBeenCalled();

		// The SAME fixture, only `classifiable: true` — proves the branch above can also PASS,
		// so the guard is a live predicate rather than one that can never fire either way.
		const { getByRole } = render(SubCatPicker, {
			props: {
				transaction: trans({ category: { cat: 'Expense', sub_cat: 'Groceries' }, sub_cat_id: 10 }),
				subCatGroups: GROUPS,
				classifyFn
			}
		});
		await fireEvent.click(getByRole('button'));
		expect(classifyFn).toHaveBeenCalledTimes(1);
	});

	it('the provider_category hint is NEVER a write: mounting a hint-state row alone calls classifyFn zero times', () => {
		const classifyFn = vi.fn();
		render(SubCatPicker, {
			props: { transaction: trans({ provider_category: 'Groceries' }), subCatGroups: GROUPS, classifyFn }
		});
		expect(classifyFn).not.toHaveBeenCalled();
	});
});
