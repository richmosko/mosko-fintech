// cashflowSections.test.ts — unit coverage for the §2.3 shared section-vocabulary module
// (SELF-250 AC5). Proves the ratified A-10 mapping (Income<-Revenue, Expenses<-Expense,
// Other Cash Flows<-Transfer,Equity), Trade's EXPLICIT exclusion (not merely an omission that
// could be mistaken for an oversight), and the fallback-to-undefined (never a thrown error, never
// a raw-value label) posture for any value outside the ratified vocabulary.

import { describe, it, expect } from 'vitest';
import {
	CASHFLOW_CLASS_TO_SECTION,
	cashflowSectionKey,
	cashflowSectionLabel
} from './cashflowSections';

describe('cashflowSections — the ratified A-10 mapping', () => {
	it('Revenue -> income / "Income"', () => {
		expect(cashflowSectionKey('Revenue')).toBe('income');
		expect(cashflowSectionLabel('Revenue')).toBe('Income');
	});

	it('Expense -> expenses / "Expenses"', () => {
		expect(cashflowSectionKey('Expense')).toBe('expenses');
		expect(cashflowSectionLabel('Expense')).toBe('Expenses');
	});

	it('Transfer -> other_cash_flows / "Other Cash Flows"', () => {
		expect(cashflowSectionKey('Transfer')).toBe('other_cash_flows');
		expect(cashflowSectionLabel('Transfer')).toBe('Other Cash Flows');
	});

	it('Equity -> other_cash_flows / "Other Cash Flows" — SAME section as Transfer (D-2 (B) union)', () => {
		expect(cashflowSectionKey('Equity')).toBe('other_cash_flows');
		expect(cashflowSectionLabel('Equity')).toBe('Other Cash Flows');
	});
});

describe('cashflowSections — Trade is EXCLUDED, not merely unmapped', () => {
	it('Trade has no membership in the class->section table (inversion check)', () => {
		// A future edit that re-adds Trade to CASHFLOW_CLASS_TO_SECTION (e.g. "just default it to
		// some section") flips this assertion RED — proving the exclusion is actually encoded,
		// not just an accident of the current table's contents.
		expect(Object.prototype.hasOwnProperty.call(CASHFLOW_CLASS_TO_SECTION, 'Trade')).toBe(false);
	});

	it('Trade resolves to undefined, not a fabricated section', () => {
		expect(cashflowSectionKey('Trade')).toBeUndefined();
		expect(cashflowSectionLabel('Trade')).toBeUndefined();
	});
});

describe('cashflowSections — values outside the ratified vocabulary degrade to undefined', () => {
	it('an unrecognized cat value never throws and never returns a raw-value label', () => {
		expect(() => cashflowSectionKey('SomeFutureClass')).not.toThrow();
		expect(cashflowSectionKey('SomeFutureClass')).toBeUndefined();
		expect(cashflowSectionLabel('SomeFutureClass')).toBeUndefined();
	});
});

describe('cashflowSections — exactly three sections, exactly five classes considered', () => {
	it('every ratified class maps to at most one section, and only these five are considered', () => {
		const classes = ['Revenue', 'Expense', 'Transfer', 'Equity', 'Trade'] as const;
		const resolved = classes.map((c) => [c, cashflowSectionKey(c)] as const);
		expect(resolved).toEqual([
			['Revenue', 'income'],
			['Expense', 'expenses'],
			['Transfer', 'other_cash_flows'],
			['Equity', 'other_cash_flows'],
			['Trade', undefined]
		]);
	});
});
