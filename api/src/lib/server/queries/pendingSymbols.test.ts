// pendingSymbols.test.ts — unit coverage for the SELF-200 derived-set core (computePendingIds).
// Pure-TS server test (node env per vitest.config). No DB / no mocks — this exercises ONLY the
// extracted anti-join logic (DISTINCT dedup + NULL-security_id drop + set-difference). The RLS
// wiring in pendingAssetIds / loadPendingSymbols / countPendingSymbols is covered end-to-end by
// QA's two-tenant battery; this locks the deterministic derivation semantics.

import { describe, it, expect } from 'vitest';
import { computePendingIds } from './pendingSymbols';

describe('computePendingIds', () => {
	it('returns transacted assets that have no classification', () => {
		const transacted = [{ security_id: 1 }, { security_id: 2 }, { security_id: 3 }];
		const classified = [{ asset_id: 2 }];
		expect(computePendingIds(transacted, classified).sort()).toEqual([1, 3]);
	});

	it('dedupes multiple transactions of the same security (DISTINCT)', () => {
		const transacted = [{ security_id: 5 }, { security_id: 5 }, { security_id: 5 }];
		expect(computePendingIds(transacted, [])).toEqual([5]);
	});

	it('drops NULL security_id rows (cash / non-security transactions)', () => {
		const transacted = [{ security_id: null }, { security_id: 7 }, { security_id: null }];
		expect(computePendingIds(transacted, [])).toEqual([7]);
	});

	it('is ever-transacted, not net-position: a sold-to-zero security still surfaces', () => {
		// The caller has txns for security 9 (bought then fully sold — still 2 rows here) and
		// has never classified it → it is pending regardless of current quantity.
		const transacted = [{ security_id: 9 }, { security_id: 9 }];
		expect(computePendingIds(transacted, [])).toEqual([9]);
	});

	it('returns [] when every transacted security is already classified', () => {
		const transacted = [{ security_id: 1 }, { security_id: 2 }];
		const classified = [{ asset_id: 1 }, { asset_id: 2 }];
		expect(computePendingIds(transacted, classified)).toEqual([]);
	});

	it('returns [] with no transactions', () => {
		expect(computePendingIds([], [{ asset_id: 1 }])).toEqual([]);
	});

	it('ignores classifications for assets never transacted', () => {
		const transacted = [{ security_id: 1 }];
		const classified = [{ asset_id: 99 }]; // stray classification, not in transacted set
		expect(computePendingIds(transacted, classified)).toEqual([1]);
	});
});
