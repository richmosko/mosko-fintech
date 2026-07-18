// SimpleFINAdapterAdmission.integration.test.ts — QA G3: admission-atomicity LIVE-DB test
// (slice 3a; consumes Backend's SimpleFINAdapter). Design ref: temp/provider-sync-scheduler-
// simplefin-design.md §6 (QA G3) + §8 #1 (the Access URL lands ONLY in vault.secrets).
//
// ── THE PROPERTY UNDER TEST (load-bearing) ─────────────────────────────────────────────
// SimpleFINAdapter.connect() performs an inline `vault.create_secret(<Access URL>)` followed
// by `INSERT pfin.linked_source (credential_secret_id, …)` inside ONE withServiceRole
// transaction. ATOMICITY REQUIREMENT: if the INSERT fails, the create_secret MUST roll back —
// otherwise a Vault secret is orphaned (a live credential with no owning row, un-revocable via
// the app). This test proves that end-to-end against the REAL vault + linked_source: whether
// vault.create_secret participates in the surrounding transaction is a fact of the pinned
// Supabase stack that must be VERIFIED, not assumed (SELF-196 capability-verify lesson).
//
// ── FAULT INJECTION (deterministic, faithful) ──────────────────────────────────────────
// The credential claim + /accounts fetch are MOCKED (we are testing the DB atomicity, not the
// SimpleFIN network). The DB is LIVE. G3-A wraps the live tx so the `INSERT into pfin.linked_
// source` rejects AFTER the real vault.create_secret has run in the same tx → `sql.begin`
// ROLLBACKs → we assert NO orphaned vault.secrets row. Only the FAILURE TRIGGER is injected;
// the create_secret, the transaction, the rollback, and the post-condition query are all real.
// G3-B is the non-vacuous positive control: an un-faulted connect COMMITs exactly one secret +
// one row — proving the "no orphan" assertion is not vacuous (the path really does mint a secret
// when it commits).
//
// GATED behind RUN_DB_INTEGRATION=1 (see _liveDb.ts) — a visible skip when the stack is absent,
// never a false pass. Local run: `RUN_DB_INTEGRATION=1 npx vitest run tests/integration`.

import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { Sql } from 'postgres';
import { SimpleFINAdapter, accessUrlDigest, type FetchLike } from '../../src/adapters/SimpleFINAdapter.js';
import * as fx from '../fixtures/simplefin-payloads.js';
import { makeLiveDbFor, rawSql, RUN_DB_INTEGRATION } from './_liveDb.js';

// A synthetic tenant (seeded into auth.users; NOT a real user). SD §4.5 posture: no PII.
const TENANT = 'a3a3a3a3-3a3a-4a3a-8a3a-a3a3a3a3a3a3';
const LABEL_PREFIX = 'simplefin:conn:%'; // vault.secrets label the adapter mints (never client-readable).

/** Mock fetch: POST <claim URL> → the Access URL (text); GET .../accounts → the accounts set.
 *  Identical shape to the unit test; the credential surface is mocked, the DB is live. */
function admissionFetch(accessUrl = fx.ACCESS_URL, accountsSet: unknown = fx.accountsSetClean): FetchLike {
	return async (_url, init) => {
		if (init?.method === 'POST') {
			return { ok: true, status: 200, text: async () => accessUrl, json: async () => ({}) };
		}
		return { ok: true, status: 200, text: async () => JSON.stringify(accountsSet), json: async () => accountsSet };
	};
}

/** Wrap the tx tagged-template so the linked_source INSERT rejects (create_secret already ran). */
function injectInsertFailure(tx: unknown): unknown {
	const raw = tx as (s: TemplateStringsArray, ...p: unknown[]) => Promise<unknown[]>;
	const wrapped = (strings: TemplateStringsArray, ...params: unknown[]): Promise<unknown[]> => {
		const text = Array.from(strings).join('?');
		if (/insert\s+into\s+pfin\.linked_source/i.test(text)) {
			return Promise.reject(new Error('INJECTED_INSERT_FAILURE (G3 atomicity)'));
		}
		return raw(strings, ...params);
	};
	return wrapped;
}

const setup = (fn: () => void | Promise<void>) => (RUN_DB_INTEGRATION ? fn() : undefined);
const d = RUN_DB_INTEGRATION ? describe : describe.skip;

let db: Sql;

async function simplefinSecretCount(): Promise<number> {
	const r = await db<{ n: string }[]>`select count(*)::text as n from vault.secrets where name like ${LABEL_PREFIX}`;
	return Number(r[0]!.n);
}
async function tenantSourceCount(): Promise<number> {
	const r = await db<{ n: string }[]>`select count(*)::text as n from pfin.linked_source where users_id = ${TENANT}`;
	return Number(r[0]!.n);
}

beforeAll(async () => {
	await setup(async () => {
		db = rawSql();
		// Seed the synthetic tenant (only `id` is NOT-NULL-without-default on auth.users — login-less stub).
		await db`insert into auth.users (id) values (${TENANT}) on conflict do nothing`;
	});
});

afterAll(async () => {
	if (!RUN_DB_INTEGRATION) return;
	// Cascade-cleans linked_source (fires fn_linked_source_cleanup_vault_secret → deletes the secret).
	await db`delete from auth.users where id = ${TENANT}`;
	await db.end();
});

beforeEach(async () => {
	if (!RUN_DB_INTEGRATION) return;
	// Each test starts from a CLEAN credential state so connect() takes the NEW-connection INSERT
	// branch (not the re-admission UPDATE branch). DELETE fires the Vault-secret cleanup trigger.
	await db`delete from pfin.linked_source where users_id = ${TENANT}`;
});

d('G3 — SimpleFINAdapter.connect admission atomicity (live DB)', () => {
	it('G3-A: a failed INSERT rolls back vault.create_secret — NO orphaned secret (load-bearing)', async () => {
		const before = await simplefinSecretCount();

		const adapter = new SimpleFINAdapter(
			makeLiveDbFor(undefined, injectInsertFailure),
			undefined,
			admissionFetch()
		);

		// The injected INSERT failure must surface (fail-closed), not be swallowed.
		await expect(
			adapter.connect({ provider: 'simplefin', setupToken: fx.SETUP_TOKEN, ownerUserId: TENANT, institutionName: 'Capital One' })
		).rejects.toThrow(/INJECTED_INSERT_FAILURE/);

		// ATOMICITY: the real vault.create_secret ran inside the same tx as the failed INSERT →
		// the whole tx rolled back → the secret count is UNCHANGED (no orphan).
		expect(await simplefinSecretCount()).toBe(before);
		// …and no linked_source row landed either (the INSERT was rolled back).
		expect(await tenantSourceCount()).toBe(0);
	});

	it('G3-B: non-vacuous control — a committed connect DOES persist exactly one secret + one row', async () => {
		const before = await simplefinSecretCount();

		const adapter = new SimpleFINAdapter(makeLiveDbFor(), undefined, admissionFetch());
		const result = await adapter.connect({
			provider: 'simplefin',
			setupToken: fx.SETUP_TOKEN,
			ownerUserId: TENANT,
			institutionName: 'Capital One'
		});

		expect(result.sourceId).toBeTypeOf('bigint');
		expect(result.accounts).toHaveLength(3); // checking + card + investment (accountsSetClean)

		// Exactly one linked_source row for the tenant, carrying a REAL vault.secrets handle:
		// proves create_secret genuinely persists a secret on the committed path (so G3-A's
		// "no orphan" is a real delta, not a path that never creates a secret).
		expect(await tenantSourceCount()).toBe(1);
		expect(await simplefinSecretCount()).toBe(before + 1);
		const linked = await db<{ secret_present: boolean; ecid: string }[]>`
			select (s.id is not null) as secret_present, ls.external_connection_id as ecid
			  from pfin.linked_source ls
			  join vault.secrets s on s.id = ls.credential_secret_id
			 where ls.users_id = ${TENANT}`;
		expect(linked).toHaveLength(1);
		expect(linked[0]!.secret_present).toBe(true);
		// external_connection_id is the SHA-256 digest of the Access URL (SC-3 C4) — the row
		// stores the DIGEST, never the raw Access URL.
		expect(linked[0]!.ecid).toBe(accessUrlDigest(fx.ACCESS_URL));
		// beforeEach/afterAll clean up the committed row + secret.
	});

	it('G3-C: re-admission (same digest) UPDATEs in place + REUSES the secret handle — no 2nd row, no orphaned rotated secret', async () => {
		const before = await simplefinSecretCount();
		const adapter = new SimpleFINAdapter(makeLiveDbFor(), undefined, admissionFetch());

		// First admission — commits a new connection (create_secret + INSERT).
		const first = await adapter.connect({ provider: 'simplefin', setupToken: fx.SETUP_TOKEN, ownerUserId: TENANT, institutionName: 'Capital One' });
		const row1 = await db<{ sid: string; csid: string }[]>`
			select source_id::text as sid, credential_secret_id::text as csid
			  from pfin.linked_source where users_id = ${TENANT}`;
		expect(row1).toHaveLength(1);
		expect(await simplefinSecretCount()).toBe(before + 1);

		// Re-admit the SAME Access URL (same SHA-256 digest → same external_connection_id) →
		// the dedup SELECT matches → UPDATE-in-place + vault.update_secret on the EXISTING handle
		// (NOT a fresh create_secret that would orphan the old vault row on the same connection).
		const second = await adapter.connect({ provider: 'simplefin', setupToken: fx.SETUP_TOKEN, ownerUserId: TENANT, institutionName: 'Capital One (re-auth)' });
		const row2 = await db<{ sid: string; csid: string }[]>`
			select source_id::text as sid, credential_secret_id::text as csid
			  from pfin.linked_source where users_id = ${TENANT}`;

		expect(second.sourceId).toBe(first.sourceId); // same row returned, not a new source
		expect(row2).toHaveLength(1); // NO 2nd linked_source row (re-admission is UPDATE, not INSERT)
		expect(row2[0]!.sid).toBe(row1[0]!.sid); // same source_id
		expect(row2[0]!.csid).toBe(row1[0]!.csid); // SAME secret handle reused (update_secret, not a new secret)
		expect(await simplefinSecretCount()).toBe(before + 1); // still exactly 1 — no orphaned rotated secret
	});
});
