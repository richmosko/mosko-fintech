// importHash.test.ts — the drift regression guard for the canonical manual↔provider content
// hash (SELF-204 / ADR-034 D4). The pinned known-input→known-hex vectors are the load-bearing
// assertion: if the canonicalization or digest EVER changes, these fail loudly. Because the same
// module is the single source imported by BOTH the SvelteKit manual-entry action (via the
// generated copy) AND this worker's ingest mapper, a green run here proves both tiers hash
// identically (no invisible dedup drift). The hashes were computed from this exact spec
// (F/CTO-ratified 2026-07-27) — do NOT edit them to make a changed implementation pass; a changed
// hash is a one-way door (historical rows can't be re-hashed).

import { describe, it, expect } from 'vitest';
import { computeImportHash } from '../src/shared/importHash.js';

const SEP = String.fromCharCode(0x1f);

describe('computeImportHash — pinned known vectors (drift guard)', () => {
	it('V1 canonical vector', () => {
		expect(
			computeImportHash({
				accountId: 42,
				date: '2026-07-20',
				amount: -54.3,
				vendor: 'Costco',
				description: 'weekly groceries'
			})
		).toBe('0fd6f01cede4eba8f305fe7a527fd7f5c662eeddf7572a56ed9519424a561112');
	});

	it('V2 null-descriptor vector', () => {
		expect(
			computeImportHash({ accountId: 1, date: '2026-01-02', amount: 100, vendor: null, description: null })
		).toBe('5462e7917b511f16d8e773f0ecbc5653b033a0b06b8a1b3c365e2e02be165340');
	});
});

describe('computeImportHash — canonicalization equivalences (same hash)', () => {
	const v1 = {
		accountId: 42,
		date: '2026-07-20',
		amount: -54.3,
		vendor: 'Costco',
		description: 'weekly groceries'
	};
	const base = computeImportHash(v1);

	it('amount scale-insensitive (54.3 ≡ 54.30 ≡ 54.3000)', () => {
		expect(computeImportHash({ ...v1, amount: -54.3 })).toBe(base);
		expect(computeImportHash({ ...v1, amount: Number('-54.3000') })).toBe(base);
	});

	it('descriptor case- and whitespace-insensitive', () => {
		expect(computeImportHash({ ...v1, vendor: '  COSTCO ', description: 'Weekly   Groceries' })).toBe(base);
	});

	it('control chars in the descriptor cannot inject the join delimiter', () => {
		expect(computeImportHash({ ...v1, vendor: `Costco${SEP}weekly`, description: 'groceries' })).toBe(
			computeImportHash({ ...v1, vendor: 'Costco weekly', description: 'groceries' })
		);
	});
});

describe('computeImportHash — field sensitivity (different hash)', () => {
	const v1 = {
		accountId: 42,
		date: '2026-07-20',
		amount: -54.3,
		vendor: 'Costco',
		description: 'weekly groceries'
	};
	const base = computeImportHash(v1);

	it('account, amount, date, and sign each change the hash', () => {
		expect(computeImportHash({ ...v1, accountId: 43 })).not.toBe(base);
		expect(computeImportHash({ ...v1, amount: -54.31 })).not.toBe(base);
		expect(computeImportHash({ ...v1, date: '2026-07-21' })).not.toBe(base);
		expect(computeImportHash({ ...v1, amount: 54.3 })).not.toBe(base); // +inflow vs −outflow
	});

	it('is a 64-char lowercase-hex SHA-256 digest', () => {
		expect(base).toMatch(/^[0-9a-f]{64}$/);
	});
});
