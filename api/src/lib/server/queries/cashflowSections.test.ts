// cashflowSections.test.ts — unit coverage for the §2.3 shared section-vocabulary module
// (SELF-250 AC5). Proves the ratified A-10 mapping (Income<-Revenue, Expenses<-Expense,
// Other Cash Flows<-Transfer,Equity), Trade's EXPLICIT exclusion (not merely an omission that
// could be mistaken for an oversight), and the fallback-to-undefined (never a thrown error, never
// a raw-value label) posture for any value outside the ratified vocabulary.

import { describe, it, expect } from 'vitest';
import {
	CASHFLOW_CLASS_TO_SECTION,
	CASHFLOW_OTHER_CASH_FLOWS_NOTE,
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

describe('cashflowSections — SELF-253 AC8 honest-transfer-note', () => {
	it('is a non-empty string and never claims a transfer cancels out on its own', () => {
		expect(typeof CASHFLOW_OTHER_CASH_FLOWS_NOTE).toBe('string');
		expect(CASHFLOW_OTHER_CASH_FLOWS_NOTE.length).toBeGreaterThan(0);
		// The one thing this copy must never say, stated as an inversion check: a future edit that
		// drops the caveat and leaves only "cancels out" flips this red.
		expect(CASHFLOW_OTHER_CASH_FLOWS_NOTE).toMatch(/does not.*cancel out/i);
		expect(CASHFLOW_OTHER_CASH_FLOWS_NOTE).toMatch(/suspense/i);
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

describe('cashflowSections — SELF-253 drift watcher: this module vs 094 `cats` output', () => {
	// `094` (pfin.fn_cashflow_per_account) emits a `cats` array per section — the class set it
	// partitioned on, computed DB-side from its own `section_cats` VALUES rows, alphabetized within
	// a section (`jsonb_agg(sc.cat order by sc.cat)`). That literal shape is pinned in the RLS
	// battery (STRUCT-CATS leg, supabase/tests/rls/094_fn_cashflow_per_account_rls.sql). THIS test
	// is the other half of the watcher Architect's header describes: it derives the SAME partition
	// from CASHFLOW_CLASS_TO_SECTION (the app-side single source of truth) by inverting it, and
	// asserts the two agree — so a future edit to EITHER the SQL VALUES rows or this TS table, made
	// without touching the other, reds one side of the watcher instead of drifting silently.
	it('CASHFLOW_CLASS_TO_SECTION, inverted and alphabetized, equals 094s emitted `cats` partition', () => {
		const inverted: Record<string, string[]> = {};
		for (const [cls, section] of Object.entries(CASHFLOW_CLASS_TO_SECTION)) {
			if (!section) continue;
			(inverted[section] ??= []).push(cls);
		}
		for (const key of Object.keys(inverted)) inverted[key].sort();

		// Expected shape mirrors 094's `section_cats` VALUES rows verbatim (migration header:
		// "the class sets ... expressed as data the join consumes directly"). A change to either
		// side without the other is exactly the drift this leg exists to catch.
		expect(inverted).toEqual({
			income: ['Revenue'],
			other_cash_flows: ['Equity', 'Transfer'],
			expenses: ['Expense']
		});
	});

	it('Trade contributes to NO section in the inverted partition either (mirrors 094s exclusion)', () => {
		const allPartitioned = Object.values(CASHFLOW_CLASS_TO_SECTION).length;
		// 5 ratified classes, 4 with a section (Revenue/Expense/Transfer/Equity) — Trade excluded.
		expect(Object.keys(CASHFLOW_CLASS_TO_SECTION)).toHaveLength(4);
		expect(allPartitioned).toBe(4);
	});
});
