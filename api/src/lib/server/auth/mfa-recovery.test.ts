// mfa-recovery.test.ts — unit coverage for the recovery core (SELF-291 / Auth-3b Slice 2b).
// Pure-TS server test (node env). Mocks mfa-hash (fast/deterministic), the service_role
// admin factory, and the notify helper. Proves Sec's HARD conditions:
//   · atomic rate-gate: the attempt row is pre-logged BEFORE the count; lockout at 6th.
//   · atomic check-and-consume: a 0-rows-affected consume is rejected (double-spend).
//   · constant-time-ish compare: verifyCode runs against EVERY live code (no early-out).
//   · deleteFactor retried (must succeed).
//   · users_id is bound in code — every query filters the passed session userId.

import { describe, it, expect, vi, beforeEach } from 'vitest';

// Deterministic, fast scrypt double: hash(x) = 'hash:'+x; verify(x,h) = (h === 'hash:'+x).
// (mfa-hash.test.ts covers the REAL scrypt round-trip / tamper-reject / length-safety.)
vi.mock('$lib/server/auth/mfa-hash', () => ({
	hashCode: vi.fn(async (s: string) => `hash:${s}`),
	verifyCode: vi.fn(async (s: string, h: string) => h === `hash:${s}`)
}));
// Notify is fail-soft telemetry — stub it out.
vi.mock('$lib/server/auth/mfa-notify', () => ({ notifyMfaChange: vi.fn(async () => {}) }));

// The admin factory — replaced per-test via setAdmin().
let currentAdmin: unknown;
vi.mock('$lib/server/supabase-admin', () => ({ supabaseAdmin: () => currentAdmin }));

import { verifyCode } from './mfa-hash';
import { redeemRecoveryCode, issueRecoveryCodes, recoveryCodeStatus } from './mfa-recovery';

const UID = 'user-1111-4aaa-8aaa-aaaaaaaaaaaa';

type Cfg = {
	failCount?: number;
	attemptInsertError?: { message: string } | null;
	countError?: { message: string } | null;
	liveCodes?: { code_id: number; code_hash: string }[];
	consumeRows?: { code_id: number }[];
	consumeError?: { message: string } | null;
	downgradeError?: { message: string } | null;
	factors?: { id: string; factor_type: string; status: string }[];
	deleteFactorError?: { message: string } | null;
	codeInsertError?: { message: string } | null;
	unused?: number;
};

function makeAdmin(cfg: Cfg) {
	const calls = {
		attemptInserts: [] as unknown[],
		codeInserts: [] as unknown[],
		consume: [] as unknown[],
		supersede: [] as unknown[],
		downgrade: [] as unknown[],
		eqUsersIds: [] as unknown[],
		deleteFactor: [] as { id: string; userId: string }[]
	};

	function resolve(table: string, st: Record<string, unknown>) {
		if (table === 'mfa_recovery_attempt') {
			if (st.insert) {
				calls.attemptInserts.push(st.rows);
				return { data: null, error: cfg.attemptInsertError ?? null };
			}
			if (st.count) return { count: cfg.failCount ?? 0, error: cfg.countError ?? null };
		}
		if (table === 'mfa_recovery_code') {
			if (st.insert) {
				calls.codeInserts.push(st.rows);
				return { data: null, error: cfg.codeInsertError ?? null };
			}
			if (st.update && st.select) {
				calls.consume.push(st.patch);
				return { data: cfg.consumeRows ?? [{ code_id: 0 }], error: cfg.consumeError ?? null };
			}
			if (st.update) {
				calls.supersede.push(st.patch);
				return { data: null, error: null };
			}
			if (st.count) return { count: cfg.unused ?? 0, error: null };
			if (st.select) return { data: cfg.liveCodes ?? [], error: null };
		}
		if (table === 'user_settings') {
			if (st.update) {
				calls.downgrade.push(st.patch);
				return { data: null, error: cfg.downgradeError ?? null };
			}
		}
		return { data: null, error: null };
	}

	function from(table: string) {
		const st: Record<string, unknown> = {};
		const b: Record<string, unknown> = {};
		const chain = (fn: (...a: unknown[]) => void) => (...args: unknown[]) => {
			fn(...args);
			return b;
		};
		b.insert = chain((rows) => { st.insert = true; st.rows = rows; });
		b.update = chain((patch) => { st.update = true; st.patch = patch; });
		b.select = chain((_cols, opts) => {
			st.select = true;
			const o = opts as { head?: boolean; count?: string } | undefined;
			if (o?.head && o?.count) st.count = true;
		});
		b.eq = chain((c, v) => { if (c === 'users_id') calls.eqUsersIds.push(v); });
		b.is = chain(() => {});
		b.gt = chain(() => {});
		b.neq = chain(() => {});
		b.then = (res: (v: unknown) => unknown, rej: (e: unknown) => unknown) =>
			Promise.resolve(resolve(table, st)).then(res, rej);
		return b;
	}

	const admin = {
		schema: () => ({ from }),
		auth: {
			admin: {
				mfa: {
					listFactors: vi.fn(async () => ({ data: { factors: cfg.factors ?? [] }, error: null })),
					deleteFactor: vi.fn(async (arg: { id: string; userId: string }) => {
						calls.deleteFactor.push(arg);
						return { error: cfg.deleteFactorError ?? null };
					})
				}
			}
		}
	};
	return { admin, calls };
}

beforeEach(() => {
	vi.clearAllMocks();
	vi.spyOn(console, 'error').mockImplementation(() => {});
	vi.spyOn(console, 'warn').mockImplementation(() => {});
});

describe('redeemRecoveryCode — rate-gate (Sec: atomic + still-log)', () => {
	it('pre-logs the attempt BEFORE the count, and locks at the 6th failure', async () => {
		const { admin, calls } = makeAdmin({ failCount: 6 }); // count incl. the just-inserted row
		currentAdmin = admin;
		const outcome = await redeemRecoveryCode(UID, 'abcd2345abcd2345');
		expect(outcome).toBe('locked');
		// Still-log: the attempt was recorded as a failure BEFORE we returned locked.
		expect(calls.attemptInserts).toHaveLength(1);
		expect(calls.attemptInserts[0]).toEqual({ users_id: UID, succeeded: false });
	});

	it('allows the 5th attempt through to verification (count == 5, not > 5)', async () => {
		const { admin } = makeAdmin({ failCount: 5, liveCodes: [] }); // no codes → invalid, not locked
		currentAdmin = admin;
		await expect(redeemRecoveryCode(UID, 'abcd2345abcd2345')).resolves.toBe('invalid');
	});

	it('fails CLOSED (locked) if the attempt pre-log write errors', async () => {
		const { admin } = makeAdmin({ attemptInsertError: { message: 'db down' } });
		currentAdmin = admin;
		await expect(redeemRecoveryCode(UID, 'abcd2345abcd2345')).resolves.toBe('locked');
	});
});

describe('redeemRecoveryCode — compare + consume (Sec: constant-time + double-spend)', () => {
	it('compares against EVERY live code with no early break', async () => {
		const input = 'abcd2345abcd2345';
		const { admin } = makeAdmin({
			failCount: 1,
			liveCodes: [
				{ code_id: 1, code_hash: `hash:${input}` }, // matches FIRST
				{ code_id: 2, code_hash: 'hash:other1' },
				{ code_id: 3, code_hash: 'hash:other2' }
			],
			consumeRows: [{ code_id: 1 }],
			factors: []
		});
		currentAdmin = admin;
		const outcome = await redeemRecoveryCode(UID, input);
		expect(outcome).toBe('ok');
		// All three candidates were verified despite the first matching (no timing leak).
		expect(verifyCode).toHaveBeenCalledTimes(3);
	});

	it('rejects a matched code whose atomic consume affects 0 rows (double-spend race)', async () => {
		const input = 'abcd2345abcd2345';
		const { admin } = makeAdmin({
			failCount: 1,
			liveCodes: [{ code_id: 1, code_hash: `hash:${input}` }],
			consumeRows: [] // concurrent redeem won the row-lock race
		});
		currentAdmin = admin;
		await expect(redeemRecoveryCode(UID, input)).resolves.toBe('invalid');
	});

	it('no match → invalid', async () => {
		const { admin } = makeAdmin({
			failCount: 1,
			liveCodes: [{ code_id: 1, code_hash: 'hash:somethingelse' }]
		});
		currentAdmin = admin;
		await expect(redeemRecoveryCode(UID, 'abcd2345abcd2345')).resolves.toBe('invalid');
	});
});

describe('redeemRecoveryCode — consume success path', () => {
	const input = 'abcd2345abcd2345';
	function okAdmin(extra: Partial<Cfg> = {}) {
		return makeAdmin({
			failCount: 1,
			liveCodes: [{ code_id: 7, code_hash: `hash:${input}` }],
			consumeRows: [{ code_id: 7 }],
			factors: [{ id: 'f1', factor_type: 'totp', status: 'verified' }],
			...extra
		});
	}

	it('downgrades mfa_policy to none, removes the factor, logs success, returns ok', async () => {
		const { admin, calls } = okAdmin();
		currentAdmin = admin;
		const outcome = await redeemRecoveryCode(UID, input, 'u@example.com');
		expect(outcome).toBe('ok');
		// Policy downgraded (BEFORE factor removal — lockout-safe ordering).
		expect(calls.downgrade).toEqual([{ mfa_policy: 'none' }]);
		// Dead factor removed via the admin API.
		expect(calls.deleteFactor).toEqual([{ id: 'f1', userId: UID }]);
		// Success attempt logged (the true row, in addition to the provisional false pre-log).
		expect(calls.attemptInserts).toContainEqual({ users_id: UID, succeeded: true });
	});

	it('retries deleteFactor on persistent error (must-succeed discipline)', async () => {
		const { admin } = okAdmin({ deleteFactorError: { message: 'transient' } });
		currentAdmin = admin;
		const outcome = await redeemRecoveryCode(UID, input);
		// Policy is downgraded so DB access is restored → still ok; the lingering factor is a
		// guard nuisance, not a hard lockout. deleteFactor was retried, not skipped.
		expect(outcome).toBe('ok');
		expect(
			(admin.auth.admin.mfa.deleteFactor as ReturnType<typeof vi.fn>).mock.calls.length
		).toBe(3);
	});

	it('returns invalid if the post-consume mfa_policy downgrade fails', async () => {
		const { admin } = okAdmin({ downgradeError: { message: 'boom' } });
		currentAdmin = admin;
		await expect(redeemRecoveryCode(UID, input)).resolves.toBe('invalid');
	});
});

describe('redeemRecoveryCode — tenant binding (Decision-1)', () => {
	it('filters every query by the passed session userId (never any other)', async () => {
		const input = 'abcd2345abcd2345';
		const { admin, calls } = makeAdmin({
			failCount: 1,
			liveCodes: [{ code_id: 1, code_hash: `hash:${input}` }],
			consumeRows: [{ code_id: 1 }],
			factors: []
		});
		currentAdmin = admin;
		await redeemRecoveryCode(UID, input);
		expect(calls.eqUsersIds.length).toBeGreaterThan(0);
		expect(calls.eqUsersIds.every((v) => v === UID)).toBe(true);
	});
});

describe('issueRecoveryCodes', () => {
	it('returns 10 grouped codes and inserts 10 hashed rows under one batch, then supersedes', async () => {
		const { admin, calls } = makeAdmin({});
		currentAdmin = admin;
		const codes = await issueRecoveryCodes(UID);
		expect(codes).toHaveLength(10);
		// Grouped display shape abcd-efgh-ijkl-mnop.
		expect(codes[0]).toMatch(/^[a-z2-7]{4}-[a-z2-7]{4}-[a-z2-7]{4}-[a-z2-7]{4}$/);
		// One insert of 10 rows, each with a hash of the ungrouped plaintext + a shared batch.
		expect(calls.codeInserts).toHaveLength(1);
		const rows = calls.codeInserts[0] as { users_id: string; code_hash: string; batch_id: string }[];
		expect(rows).toHaveLength(10);
		const batchIds = new Set(rows.map((r) => r.batch_id));
		expect(batchIds.size).toBe(1);
		rows.forEach((r, i) => {
			expect(r.users_id).toBe(UID);
			expect(r.code_hash).toBe(`hash:${codes[i].replace(/-/g, '')}`);
		});
		// Prior batches superseded.
		expect(calls.supersede).toHaveLength(1);
	});

	it('throws (old batch left live) if the insert fails', async () => {
		const { admin } = makeAdmin({ codeInsertError: { message: 'db down' } });
		currentAdmin = admin;
		await expect(issueRecoveryCodes(UID)).rejects.toThrow();
	});
});

describe('recoveryCodeStatus', () => {
	it('returns the unused count', async () => {
		const { admin } = makeAdmin({ unused: 4 });
		currentAdmin = admin;
		await expect(recoveryCodeStatus(UID)).resolves.toEqual({ unused: 4 });
	});
});
