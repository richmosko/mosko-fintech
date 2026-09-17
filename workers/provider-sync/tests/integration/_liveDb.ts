// _liveDb.ts — SHARED live-DB harness for the provider-sync integration tests (QA-authored;
// the suite's FIRST live-Postgres tests — every other worker test is mocked/fakeTx).
//
// ── WHY LIVE DB (not a mock) ───────────────────────────────────────────────────────────
// G3 (admission atomicity) and SC-4 (duplicate-global-asset) are properties of the REAL
// database + real transactions that a mock cannot prove:
//   • G3 asserts vault.create_secret + INSERT linked_source share ONE transaction, so a
//     failed INSERT rolls back the created secret (no orphaned credential). Whether
//     vault.create_secret is transactional is a fact of the pinned Supabase stack — it MUST
//     be verified against the real vault, not assumed (per the "capability-verify ADR-locked
//     DB primitives against the pinned stack" lesson / SELF-196).
//   • SC-4 asserts the resolution.ts cusip-first / symbol / ON CONFLICT dedup behaves against
//     the REAL 016 (symbol) + 020 (cusip) partial-unique indexes on pfin.asset.
//
// ── DETERMINISM + CI POSTURE (QA discipline: no silent green, no flaky CI) ──────────────
// These require the local Supabase stack (config.toml Postgres @ 127.0.0.1:54322, ALL migrations
// applied — not a fixed range, vault extension). They are GATED behind RUN_DB_INTEGRATION=1 so the default
// `vitest run` (which must stay hermetic until DevOps provisions a DB in CI) SKIPS them
// LOUDLY (a visible skip, never a false pass). Locally: `RUN_DB_INTEGRATION=1 npx vitest run
// tests/integration`. Wiring them into a blocking CI lane (provision the stack + set the flag)
// is a DevOps follow-up — flagged, not silently assumed to be enforced.
//
// ── FIDELITY NOTE ──────────────────────────────────────────────────────────────────────
// The harness connects as `postgres` and does `SET LOCAL ROLE service_role` inside
// `sql.begin` — the SAME service_role execution context (BYPASSRLS, role-agnostic CHECKs/
// triggers still fire) that TenantBoundClient.withServiceRole runs under. It does NOT log in
// as `authenticator` (the ratified production login role) only because the local authenticator
// password is not a fixed test constant; the login-role identity is immaterial to what G3/SC-4
// assert (both exercise the service_role tx, not the tenant-RLS path). withServiceRole's
// `sql.begin` rollback semantics are IDENTICAL to production — that IS the property under test.

import postgres from 'postgres';
import type { Sql } from 'postgres';
import type { AdmissionDb, AdmissionDbFactory } from '../../src/adapters/SimpleFINAdapter.js';
import type { Tx } from '../../src/db/TenantBoundClient.js';

/** Integration tests run only when explicitly enabled (stack present). */
export const RUN_DB_INTEGRATION = process.env.RUN_DB_INTEGRATION === '1';

if (!RUN_DB_INTEGRATION) {
	// Loud, visible skip signal — these are NOT enforced in this run (no silent green).
	// eslint-disable-next-line no-console
	console.warn(
		'[provider-sync integration] SKIPPED — set RUN_DB_INTEGRATION=1 with the local Supabase ' +
			'stack up (127.0.0.1:54322, ALL migrations applied) to run the live-DB tests.'
	);
}

export interface LiveConn {
	host: string;
	port: number;
	database: string;
	username: string;
	password: string;
}

/** Local Supabase defaults; overridable via PFIN_DB_* for a CI lane. */
export function liveConn(): LiveConn {
	return {
		host: process.env.PFIN_DB_HOST ?? '127.0.0.1',
		port: Number(process.env.PFIN_DB_PORT ?? 54322),
		database: process.env.PFIN_DB_NAME ?? 'postgres',
		username: process.env.PFIN_DB_USER ?? 'postgres',
		password: process.env.PFIN_DB_PASSWORD ?? 'postgres'
	};
}

/**
 * A raw client for test setup/measurement (runs as the connect user — `postgres` locally).
 * ⚠ NOT superuser: measured `rolsuper = f`. Its reach into `session_replication_role` (a
 * `superuser`-context GUC per pg_settings.context) comes from the Supabase image's
 * privileged-settings extension, keyed to membership in `supabase_privileged_role` — a
 * capability `has_parameter_privilege()` reports `f` for even though it demonstrably works,
 * and which appears nowhere in this repository. `pfin_owner` holds no such membership and
 * cannot be given one from here; that is why `cleanupG2` below sets the GUC as THIS
 * connection's identity before it `set local role pfin_owner`s into table-owner reach —
 * reversing the order is refused (measured, ADR-072 Amendment 5 harness-identity ruling).
 */
export function rawSql(conn: LiveConn = liveConn()): Sql {
	return postgres({ ...conn, max: 1, prepare: false, onnotice: () => {} });
}

/**
 * Sec C-1 fixture-level assertion (ADR-072 Amendment 5 harness-identity ruling): every test
 * body that shares a pooled connection with a `session_replication_role = 'replica'` cleanup
 * MUST prove that GUC did not leak past its owning transaction. `set local` dies at commit —
 * but a future edit that drops the `local` (or reorders it outside `tx.begin`) would make it
 * persist for the rest of the connection, silently running every later test body with the
 * ENTIRE trigger layer inert (immutability fences AND the Decision-3 matched-tenant family)
 * while the suite stays green. Call this as the FIRST statement of every `it()` that runs
 * against a `db` connection `cleanupG2` has touched.
 */
export async function assertReplicationOrigin(db: Sql): Promise<void> {
	const r = await db<{ v: string }[]>`select current_setting('session_replication_role') as v`;
	const got = r[0]?.v;
	if (got !== 'origin') {
		throw new Error(
			`Sec C-1 FENCE: session_replication_role = '${got}' at test-body start, expected ` +
				`'origin'. A prior cleanup's 'set local session_replication_role' leaked past its ` +
				`transaction (missing 'local', or set outside tx.begin) — the trigger layer ` +
				`(immutability fences + Decision-3 matched-tenant family) is INERT for the rest ` +
				`of this connection and every later assertion in this suite is running against ` +
				`an unfenced database while reporting green.`
		);
	}
}

/**
 * A live AdmissionDbFactory mirroring TenantBoundClient production shape: a fresh short-lived
 * (max:1) connection per connect(), withServiceRole runs `SET LOCAL ROLE service_role` inside
 * `sql.begin` (auto-ROLLBACK on throw), end() closes it (the adapter calls it in `finally`).
 *
 * @param wrapTx optional fault-injection wrapper around the tx tagged-template (G3 uses it to
 *               force the INSERT to fail AFTER a real vault.create_secret — proving rollback).
 */
export function makeLiveDbFor(
	conn: LiveConn = liveConn(),
	wrapTx?: (tx: unknown) => unknown
): AdmissionDbFactory {
	return (_usersId: string): AdmissionDb => {
		const sql = postgres({ ...conn, max: 1, prepare: false, onnotice: () => {} });
		const withServiceRole = (<T>(fn: (t: unknown) => Promise<T>): Promise<T> =>
			sql.begin(async (tx) => {
				await tx.unsafe('set local role service_role');
				return fn(wrapTx ? wrapTx(tx) : tx);
			}) as Promise<T>) as AdmissionDb['withServiceRole'];
		return { withServiceRole, end: () => sql.end() };
	};
}

/**
 * A live TenantBoundClient-shaped double for the G2 land-path integration test — the ONLY
 * harness that exercises BOTH access modes on one connection (syncProviderData needs
 * withTenant AND withServiceRole). It connects as the superuser test role (postgres) and
 * SET-LOCAL-ROLEs into the SAME two execution contexts production's TenantBoundClient
 * establishes:
 *   • withTenant  → `set local role authenticated` + the two request.jwt claim GUCs, so
 *     fn_ingest_transactions runs under RLS as the bound tenant (the account_trans_insert
 *     wr_access-JOIN actually FENCES — it is not silently bypassed).
 *   • withServiceRole → `set local role service_role` (BYPASSRLS) for the append-only
 *     snapshot writes + the global-asset register + the guard-#3 eod_price upsert.
 * The login identity differs (postgres vs the ratified `authenticator`) ONLY because the
 * local authenticator password is not a fixed test constant; a superuser can SET ROLE into
 * either target, and every property G2 asserts is a fact of what runs UNDER each role
 * (RLS-enforced ingest under authenticated; idempotency under service_role), NOT of the
 * login handshake. `begin`'s per-transaction LOCAL-role reset is IDENTICAL to production.
 *
 * The returned object is structurally a TenantBoundClient but not nominally one (its private
 * #fields brand it) — the G2 test casts it `as unknown as TenantBoundClient` at the
 * syncProviderData call site, exactly as poll.ts casts its structural PollClient.
 */
export interface LiveTenantClient {
	withTenant<T>(fn: (tx: Tx) => Promise<T>): Promise<T>;
	withServiceRole<T>(fn: (tx: Tx) => Promise<T>): Promise<T>;
	end(): Promise<void>;
}

export function makeLiveTenantClient(usersId: string, conn: LiveConn = liveConn()): LiveTenantClient {
	const sql = postgres({ ...conn, max: 1, prepare: false, onnotice: () => {} });
	return {
		withTenant: (<T>(fn: (tx: Tx) => Promise<T>): Promise<T> =>
			sql.begin(async (tx) => {
				await tx.unsafe('set local role authenticated');
				const claims = JSON.stringify({ sub: usersId, role: 'authenticated' });
				await tx`select set_config('request.jwt.claims', ${claims}, true)`;
				await tx`select set_config('request.jwt.claim.sub', ${usersId}, true)`;
				return fn(tx as unknown as Tx);
			}) as Promise<T>) as LiveTenantClient['withTenant'],
		withServiceRole: (<T>(fn: (tx: Tx) => Promise<T>): Promise<T> =>
			sql.begin(async (tx) => {
				await tx.unsafe('set local role service_role');
				return fn(tx as unknown as Tx);
			}) as Promise<T>) as LiveTenantClient['withServiceRole'],
		end: () => sql.end()
	};
}

/**
 * Bulldoze all G2 test rows for a tenant + the ZZTG2 test asset. Append-only tables
 * (account_trans / holdings_checkpoint / account_balance_checkpoint) carry immutability
 * triggers that block DELETE for ALL roles incl. service_role — so the deletes run under
 * `session_replication_role = 'replica'`, which suppresses user + FK/cascade triggers for
 * THIS transaction only. Everything is deleted explicitly in dependency order, so cascade is
 * not relied on. Idempotent: safe to run as both pre-clean (a prior aborted run may have left
 * committed rows) and teardown. Keyed on stable identifiers (users_id + the global ZZTG2
 * symbol), so it never touches another tenant's data.
 *
 * ⚠ IDENTITY, POST ADR-072 AMENDMENT 5 (G3 pfin_owner ownership sweep). `postgres` no longer
 * owns `pfin.account_trans` et al. — it needs an explicit `set local role pfin_owner` to reach
 * DELETE (the grant, per `roles.sql`'s `grant pfin_owner to postgres with inherit false, set
 * true` — deliberately non-ambient). ⚠⚠ ORDER IS LOAD-BEARING AND MEASURED, NOT A STYLE
 * CHOICE: `session_replication_role` is set FIRST, while still `postgres` (the GUC is
 * superuser-context and reachable only through the Supabase image's privileged-settings
 * extension, keyed to `postgres`'s `supabase_privileged_role` membership — `pfin_owner` holds
 * no such membership); `set local role pfin_owner` runs SECOND. Reversing the order is
 * REFUSED — `pfin_owner` cannot set the GUC at all, so a hoisted role-switch fails at the GUC
 * line with an error naming the wrong thing. `reset role` at the end is defense-in-depth
 * (same discipline as the migration lane): `set local role` already dies at commit/rollback,
 * but an explicit reset makes the identity-scoping visible at the site rather than implicit
 * in the transaction boundary.
 */
export async function cleanupG2(db: Sql, usersId: string, assetSymbols: readonly string[]): Promise<void> {
	await db.begin(async (tx) => {
		await tx.unsafe("set local session_replication_role = 'replica'");
		await tx.unsafe('set local role pfin_owner');
		await tx`delete from pfin.account_trans where account_id in (select account_id from pfin.account where users_id = ${usersId})`;
		await tx`delete from pfin.holdings_checkpoint where account_id in (select account_id from pfin.account where users_id = ${usersId})`;
		await tx`delete from pfin.account_balance_checkpoint where account_id in (select account_id from pfin.account where users_id = ${usersId})`;
		await tx`delete from pfin.eod_price where asset_id in (select asset_id from pfin.asset where users_id is null and symbol in ${tx(assetSymbols as string[])})`;
		await tx`delete from pfin.asset where users_id is null and symbol in ${tx(assetSymbols as string[])}`;
		await tx`delete from pfin.account_users where users_id = ${usersId}`;
		await tx`delete from pfin.account where users_id = ${usersId}`;
		await tx`delete from pfin.linked_source where users_id = ${usersId}`;
		await tx`delete from auth.users where id = ${usersId}`;
		await tx.unsafe('reset role');
	});
}
