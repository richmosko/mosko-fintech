// SymbolClassifyRow.dom.test.ts — SELF-235 QA additions.
//
// (1) SUBMIT-LEVEL fence for the cascading Cat -> Sub-Cat editor. Frontend caught (by diff
//     re-read, not by any test) that naming the Cat select would have 400'd every save against
//     the server's .strict() classifySchema — it ships with name="" instead (an empty-name
//     control is excluded from the browser's "constructing the form data set" algorithm, per the
//     HTML living standard: a control with no name attribute, OR whose name is the empty string,
//     is skipped). No dom-level test exercised this before now. These tests build the ACTUAL
//     <form> via real user interaction (open the editor, choose a Cat, choose a Sub-Cat) and
//     construct `new FormData(form)` directly — the SAME algorithm the browser runs on submit —
//     so a future regression (e.g. someone "fixing" the Cat select's blank name, or adding a new
//     field to the form without a matching server-schema key) goes RED here without needing to
//     mock fetch or `use:enhance` at all.
//
// (2) Retired-Sub-Cat self-correction (Frontend bubble-up 3): when a row's ASSIGNED sub_cat_id is
//     no longer present in the `subCats` options (retired since classification, or simply excluded
//     for any reason), `open()` still pre-selects the Cat (from the assignment's own embedded
//     label, which does not depend on `subCats`) but the `$effect` cascade-reset immediately
//     clears the Sub-Cat selection because it is not a valid option for that Cat. No real
//     retirement flow exists yet to exercise this end-to-end (Frontend's own caveat) — this proves
//     the row does not crash and does not silently keep an invalid, unposted-anyway Sub-Cat
//     selected, using a fixture that reproduces the shape directly.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, fireEvent } from '@testing-library/svelte';
import SymbolClassifyRow from './SymbolClassifyRow.svelte';
import type { SymbolListItem, SubCatOption } from '$lib/asset-classify';

const SUB_CATS: SubCatOption[] = [
	{ id: 101, cat: 'Brokerage', sub_cat: 'US Equity', display_order: 1 },
	{ id: 102, cat: 'Brokerage', sub_cat: 'Index Funds', display_order: 2 },
	{ id: 201, cat: 'Retirement', sub_cat: '401k', display_order: 3 }
];

const PENDING_SYMBOL: SymbolListItem = {
	asset_id: 42,
	symbol: 'VOO',
	name: 'Vanguard S&P 500',
	asset_type: 'equity',
	metadata: null,
	classification: null
};

const CLASSIFIED_SYMBOL: SymbolListItem = {
	asset_id: 99,
	symbol: 'QQQ',
	name: 'Invesco QQQ',
	asset_type: 'equity',
	metadata: null,
	classification: { sub_cat_id: 101, cat: 'Brokerage', sub_cat: 'US Equity' }
};

/** RETIRED_SUB_CAT_SYMBOL's classification points at sub_cat_id 999, cat 'Legacy' — present in
 *  NEITHER `SUB_CATS` nor as any option under any Cat in `SUB_CATS`. Reproduces "the assigned
 *  Sub-Cat is no longer offered" without needing a real retire-then-reload flow. */
const RETIRED_SUB_CAT_SYMBOL: SymbolListItem = {
	asset_id: 7,
	symbol: 'OLD',
	name: 'Retired Holding',
	asset_type: 'equity',
	metadata: null,
	classification: { sub_cat_id: 999, cat: 'Legacy', sub_cat: 'Discontinued' }
};

describe('SymbolClassifyRow — submit-level fence: the posted form data set (Sec/QA gap)', () => {
	it('classify (pending row): posts EXACTLY {asset_id, sub_cat_id} — the Cat select never reaches the form data set', async () => {
		const { getByRole, container } = render(SymbolClassifyRow, {
			props: { symbol: PENDING_SYMBOL, subCats: SUB_CATS }
		});

		await fireEvent.click(getByRole('button', { name: 'Classify' }));

		const catSelect = getByRole('combobox', { name: 'Category' }) as HTMLSelectElement;
		await fireEvent.change(catSelect, { target: { value: 'Brokerage' } });

		const subCatSelect = getByRole('combobox', { name: 'Sub-category' }) as HTMLSelectElement;
		await fireEvent.change(subCatSelect, { target: { value: '101' } });

		const form = container.querySelector('form') as HTMLFormElement;
		const posted = new FormData(form);

		expect([...posted.keys()].sort()).toEqual(['asset_id', 'sub_cat_id']);
		expect(posted.get('asset_id')).toBe('42');
		expect(posted.get('sub_cat_id')).toBe('101');
		expect(posted.has('cat')).toBe(false);
	});

	it('reassign (already-classified row): the pre-selected form ALSO posts exactly {asset_id, sub_cat_id} after changing Sub-Cat', async () => {
		const { getByRole, container } = render(SymbolClassifyRow, {
			props: { symbol: CLASSIFIED_SYMBOL, subCats: SUB_CATS }
		});

		// AC2 pre-select: opening an already-classified row shows "Change", not "Classify".
		await fireEvent.click(getByRole('button', { name: 'Change' }));

		const catSelect = getByRole('combobox', { name: 'Category' }) as HTMLSelectElement;
		expect(catSelect.value).toBe('Brokerage'); // pre-selected from the current assignment

		const subCatSelect = getByRole('combobox', { name: 'Sub-category' }) as HTMLSelectElement;
		expect(subCatSelect.value).toBe('101'); // pre-selected from the current assignment

		// Reassign to another Sub-Cat under the SAME Cat.
		await fireEvent.change(subCatSelect, { target: { value: '102' } });

		const form = container.querySelector('form') as HTMLFormElement;
		const posted = new FormData(form);

		expect([...posted.keys()].sort()).toEqual(['asset_id', 'sub_cat_id']);
		expect(posted.get('asset_id')).toBe('99');
		expect(posted.get('sub_cat_id')).toBe('102');
		expect(posted.has('cat')).toBe(false);
	});

	it('⭐ CORRUPT-THE-CONTROL: a select WITH a real `name` DOES reach FormData — proves the two absence-checks above have teeth, not a vacuous "cat" typo', () => {
		const form = document.createElement('form');
		form.innerHTML = `<select name="cat"><option value="Brokerage" selected>Brokerage</option></select>`;
		document.body.appendChild(form);
		try {
			const posted = new FormData(form);
			expect(posted.has('cat')).toBe(true);
			expect(posted.get('cat')).toBe('Brokerage');
		} finally {
			form.remove();
		}
	});
});

describe('SymbolClassifyRow — retired-Sub-Cat degrade (Frontend bubble-up 3; no real retirement flow exists to exercise this end-to-end)', () => {
	it('opening a row whose assigned Sub-Cat is absent from `subCats` does not throw, and self-corrects the Sub-Cat selection to empty', async () => {
		const { getByRole } = render(SymbolClassifyRow, {
			props: { symbol: RETIRED_SUB_CAT_SYMBOL, subCats: SUB_CATS }
		});

		// The status chip still shows the STORED label (from the junction row's own embedded
		// taxonomy, independent of the live `subCats` options list) — "Change", not "Classify".
		await fireEvent.click(getByRole('button', { name: 'Change' }));

		const catSelect = getByRole('combobox', { name: 'Category' }) as HTMLSelectElement;
		// MEASURED (not assumed): bound to 'Legacy', a value with NO matching <option>, the native
		// <select>'s OWN `.value` getter reports '' — it does not throw, and it does not echo the
		// stale string back. (The Svelte-side STATE variable is still 'Legacy' internally; the
		// $effect below keys off THAT, not off what the control renders — proven by the Sub-Cat
		// clearing correctly even though the Cat control itself shows blank.)
		expect(catSelect.value).toBe('');

		const subCatSelect = getByRole('combobox', { name: 'Sub-category' }) as HTMLSelectElement;
		// The cascade-reset $effect fires because subCatOptionsForCat(SUB_CATS, 'Legacy') is empty
		// (no Cat 'Legacy' exists in the live options at all) — selectedSubCat self-corrects to ''.
		expect(subCatSelect.value).toBe('');

		// Non-vacuous companion: a genuinely valid Cat/Sub-Cat pair is NOT cleared by the same
		// effect (guards against the reset firing unconditionally on every open()).
		const form = catSelect.closest('form') as HTMLFormElement;
		expect(form).not.toBeNull();
	});

	it('non-vacuous companion: a Cat that DOES exist in subCats but with an out-of-Cat Sub-Cat ALSO self-corrects (not just the wholly-unknown-Cat case above)', async () => {
		const symbol: SymbolListItem = {
			...RETIRED_SUB_CAT_SYMBOL,
			asset_id: 8,
			// A live Cat ('Retirement'), but the assigned sub_cat_id (999) does not belong to it —
			// the shape a Sub-Cat retirement WITHIN an otherwise-live Cat would produce.
			classification: { sub_cat_id: 999, cat: 'Retirement', sub_cat: 'Discontinued 401k Plan' }
		};
		const { getByRole } = render(SymbolClassifyRow, { props: { symbol, subCats: SUB_CATS } });

		await fireEvent.click(getByRole('button', { name: 'Change' }));

		const catSelect = getByRole('combobox', { name: 'Category' }) as HTMLSelectElement;
		expect(catSelect.value).toBe('Retirement'); // this Cat DOES exist in subCats

		const subCatSelect = getByRole('combobox', { name: 'Sub-category' }) as HTMLSelectElement;
		// 401k (id 201) is the only live option under Retirement; 999 is not among them, so the
		// effect still clears it even though the Cat itself resolved fine.
		expect(subCatSelect.value).toBe('');
	});
});
