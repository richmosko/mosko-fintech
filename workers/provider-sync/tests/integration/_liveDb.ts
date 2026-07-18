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
// These require the local Supabase stack (config.toml Postgres @ 127.0.0.1:54322, migrations
// 001–021 applied, vault extension). They are GATED behind RUN_DB_INTEGRATION=1 so the default
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

/** Integration tests run only when explicitly enabled (stack present). */
export const RUN_DB_INTEGRATION = process.env.RUN_DB_INTEGRATION === '1';

if (!RUN_DB_INTEGRATION) {
	// Loud, visible skip signal — these are NOT enforced in this run (no silent green).
	// eslint-disable-next-line no-console
	console.warn(
		'[provider-sync integration] SKIPPED — set RUN_DB_INTEGRATION=1 with the local Supabase ' +
			'stack up (127.0.0.1:54322, migrations 001–021) to run G3/SC-4 live-DB tests.'
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

/** A raw client for test setup/measurement (runs as the connect user; superuser locally). */
export function rawSql(conn: LiveConn = liveConn()): Sql {
	return postgres({ ...conn, max: 1, prepare: false, onnotice: () => {} });
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
