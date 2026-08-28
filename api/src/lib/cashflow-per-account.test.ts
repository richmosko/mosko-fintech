// cashflow-per-account.test.ts — SELF-254 unit coverage for the browser-safe presentation
// helpers (ordering, empty-gate, year derivation). Pure TS, no DOM.

import { describe, it, expect } from 'vitest';
import {
	sectionsToRender,
	perAccountHasNoRows,
	renderedYear,
	type CashflowPerAccount,
	type CashflowPerAccountSection
} from './cashflow-per-account';

const ZERO_TOTAL = { month: 0, q1: 0, q2: 0, q3: 0, q4: 0, ytd: 0 };

function section(sectionKey: 'income' | 'other_cash_flows' | 'expenses', rows: unknown[] = []): CashflowPerAccountSection {
	return { sectionKey, label: sectionKey, cats: [], rows: rows as never, total: ZERO_TOTAL };
}

describe('sectionsToRender', () => {
	it('orders income, other_cash_flows, expenses regardless of input order', () => {
		const input = [section('expenses'), section('income'), section('other_cash_flows')];
		const ordered = sectionsToRender(input);
		expect(ordered.map((s) => s.sectionKey)).toEqual(['income', 'other_cash_flows', 'expenses']);
	});

	it('appends an unrecognized section rather than dropping it', () => {
		const bogus = { ...section('income'), sectionKey: 'bogus' as never };
		const ordered = sectionsToRender([section('income'), bogus]);
		expect(ordered).toHaveLength(2);
		expect(ordered[1]).toBe(bogus);
	});
});

describe('perAccountHasNoRows', () => {
	const base: CashflowPerAccount = {
		as_of: '2026-08-27',
		account_id: 1,
		sections: [section('income'), section('other_cash_flows'), section('expenses')],
		unclassified: { count_ytd: 0 }
	};

	it('true when every section has zero rows', () => {
		expect(perAccountHasNoRows(base)).toBe(true);
	});

	it('false when any single section has a row', () => {
		const withRow: CashflowPerAccount = {
			...base,
			sections: [section('income', [{ cat: 'Revenue', sub_cat: 'Salary' }]), section('other_cash_flows'), section('expenses')]
		};
		expect(perAccountHasNoRows(withRow)).toBe(false);
	});
});

describe('renderedYear', () => {
	it('derives the calendar year from an as_of date', () => {
		expect(renderedYear('2026-08-27')).toBe(2026);
	});
});
