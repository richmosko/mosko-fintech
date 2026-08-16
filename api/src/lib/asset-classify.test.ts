// asset-classify.test.ts — unit tests for the browser-side classify view helpers (SELF-200).
// pendingLabel + displayName (label composition incl. description promotion) + labelForHintKey
// (known map + humanizer) + hintEntries (defensive jsonb-blob → labelled scalar hint rows).

import { describe, it, expect } from 'vitest';
import {
	pendingLabel,
	displayName,
	labelForHintKey,
	hintEntries,
	classificationLabel,
	catOptionsOf,
	subCatOptionsForCat,
	type PendingSymbol
} from './asset-classify';

const base: PendingSymbol = {
	asset_id: 5,
	symbol: null,
	name: null,
	asset_type: 'equity',
	metadata: null
};

describe('displayName', () => {
	it('prefers first-class name', () => {
		expect(displayName({ ...base, name: 'Apple Inc.' })).toBe('Apple Inc.');
	});
	it('promotes a metadata description when name is null', () => {
		expect(displayName({ ...base, metadata: { description: 'Apple Inc. Common Stock' } })).toBe(
			'Apple Inc. Common Stock'
		);
	});
	it('ignores a blank/absent description', () => {
		expect(displayName({ ...base, metadata: { description: '   ' } })).toBeNull();
		expect(displayName(base)).toBeNull();
	});
});

describe('pendingLabel', () => {
	it('renders "SYMBOL — Name" when both present', () => {
		expect(pendingLabel({ ...base, symbol: 'AAPL', name: 'Apple Inc.' })).toBe('AAPL — Apple Inc.');
	});
	it('falls back to symbol, then name/description, then id', () => {
		expect(pendingLabel({ ...base, symbol: 'AAPL' })).toBe('AAPL');
		expect(pendingLabel({ ...base, name: 'Apple Inc.' })).toBe('Apple Inc.');
		expect(pendingLabel({ ...base, metadata: { description: 'Some Bond' } })).toBe('Some Bond');
		expect(pendingLabel(base)).toBe('Asset #5');
	});
});

describe('labelForHintKey', () => {
	it('maps known keys (incl. Provider type disambiguation)', () => {
		expect(labelForHintKey('security_type')).toBe('Provider type');
		expect(labelForHintKey('type')).toBe('Provider type');
		expect(labelForHintKey('close_price_as_of')).toBe('Price as of');
		expect(labelForHintKey('market_identifier_code')).toBe('Market (MIC)');
		expect(labelForHintKey('cusip')).toBe('CUSIP');
	});
	it('humanizes unknown snake_case/camelCase keys, upper-casing acronyms', () => {
		expect(labelForHintKey('option_style')).toBe('Option Style');
		expect(labelForHintKey('underlyingTicker')).toBe('Underlying Ticker');
		expect(labelForHintKey('iso_currency')).toBe('ISO Currency');
	});
});

describe('hintEntries', () => {
	it('labels known keys and formats booleans as Yes/No', () => {
		const rows = hintEntries({
			security_type: 'equity',
			close_price: 123.45,
			is_cash_equivalent: false
		});
		expect(rows).toEqual([
			{ label: 'Provider type', value: 'equity' },
			{ label: 'Close price', value: '123.45' },
			{ label: 'Cash equivalent', value: 'No' }
		]);
	});

	it('suppresses first-class, plumbing, id and timestamp keys', () => {
		const rows = hintEntries({
			symbol: 'AAPL', // first-class
			name: 'Apple', // first-class
			asset_type: 'equity', // first-class
			description: 'dup', // first-class (promoted elsewhere)
			institution_id: 'ins_1', // plumbing
			security_id: 'sec_1', // id
			update_datetime: '2026-01-01T00:00:00Z', // *_datetime suffix
			created_at: '2026-01-01', // timestamp
			sector: 'Technology' // <- the only one that should show
		});
		expect(rows).toEqual([{ label: 'Sector', value: 'Technology' }]);
	});

	it('shows unknown keys (density-first) with humanized labels', () => {
		expect(hintEntries({ option_style: 'american' })).toEqual([
			{ label: 'Option Style', value: 'american' }
		]);
	});

	it('skips null, nested objects, and arrays', () => {
		const rows = hintEntries({ sector: 'Tech', b: null, c: { nested: 1 }, d: [1, 2], exchange: 'NASDAQ' });
		expect(rows).toEqual([
			{ label: 'Sector', value: 'Tech' },
			{ label: 'Exchange', value: 'NASDAQ' }
		]);
	});

	it('caps the number of entries', () => {
		const blob = Object.fromEntries(Array.from({ length: 20 }, (_, i) => [`attr_${i}`, i]));
		expect(hintEntries(blob, 6)).toHaveLength(6);
	});

	it.each([[null], [undefined], ['a string'], [42], [[1, 2, 3]]])(
		'returns [] for non-object metadata %p',
		(meta) => {
			expect(hintEntries(meta)).toEqual([]);
		}
	);
});

describe('classificationLabel', () => {
	it('renders "Cat › Sub-Cat" when both are present', () => {
		expect(classificationLabel({ sub_cat_id: 1, cat: 'Equities', sub_cat: 'US Large Cap' })).toBe(
			'Equities › US Large Cap'
		);
	});
	it('falls back to bare sub_cat when cat is empty (subCatLabel Unsorted convention)', () => {
		expect(classificationLabel({ sub_cat_id: 1, cat: '', sub_cat: 'Unsorted' })).toBe('Unsorted');
	});
	it('returns null when unclassified', () => {
		expect(classificationLabel(null)).toBeNull();
	});
});

describe('catOptionsOf', () => {
	it('dedupes to distinct Cats, first-occurrence order, value === label', () => {
		expect(
			catOptionsOf([{ cat: 'Equities' }, { cat: 'Bonds' }, { cat: 'Equities' }, { cat: 'Cash' }])
		).toEqual([
			{ value: 'Equities', label: 'Equities' },
			{ value: 'Bonds', label: 'Bonds' },
			{ value: 'Cash', label: 'Cash' }
		]);
	});
	it('returns [] for an empty list', () => {
		expect(catOptionsOf([])).toEqual([]);
	});
});

describe('subCatOptionsForCat', () => {
	const subCats = [
		{ id: 1, cat: 'Equities', sub_cat: 'US Large Cap' },
		{ id: 2, cat: 'Equities', sub_cat: 'Intl' },
		{ id: 3, cat: 'Bonds', sub_cat: 'Treasuries' }
	];
	it('filters to the chosen Cat, id-valued options', () => {
		expect(subCatOptionsForCat(subCats, 'Equities')).toEqual([
			{ value: '1', label: 'US Large Cap' },
			{ value: '2', label: 'Intl' }
		]);
	});
	it('returns [] for an unmatched Cat', () => {
		expect(subCatOptionsForCat(subCats, 'Real Estate')).toEqual([]);
	});
	it('returns [] for an empty Cat (nothing chosen yet)', () => {
		expect(subCatOptionsForCat(subCats, '')).toEqual([]);
	});
});
