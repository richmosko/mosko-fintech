// TenantBoundClient.ts — the SOLE sanctioned Postgres entry point for provider-sync.
//
// ┌─ SANCTIONED-TRANSPORT CONTRACT (scripts/ci/fence-tbc-node.sh) ───────────────┐
// │ This file is the ONE place in workers/provider-sync/src/ that constructs a    │
// │ raw Postgres client (`postgres(...)`). The fence discovers this class by      │
// │ grepping `class TenantBoundClient` and treats every OTHER raw-client          │
// │ construction as a V1-SHIP-BLOCK violation (Lock 13 mod #3 / Decision 1        │
// │ clause d / ADR-011 Decision 17).                                              │
// │                                                                               │
// │ TRANSPORT: DIRECT Postgres (postgres.js) + PFIN_DB_PASSWORD. This worker      │
// │ NEVER uses @supabase/supabase-js / createClient(), and NEVER references the   │
// │ Supabase admin service-role credential — that keeps provider-sync OFF the     │
// │ RT-26 allowlist (which SECURITY §4.1 confines to api/src/). The rationale for  │
// │ that omission lives in the un-scanned .env.example / Dockerfile; the fence's   │
// │ LEG 2 is a STRICT zero-hit (comments included) for the key literal in src/, so │
// │ the literal name never appears here.                                          │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ── THE DUAL-NATURE RECONCILIATION (the load-bearing design decision) ──────────
// The worker lands data through TWO access modes on the SAME connection, and this
// class is where they are reconciled cleanly:
//
//   (1) INVOKER / caller-RLS path  → `withTenant(fn)`.
//       fn_ingest_transactions (017) is SECURITY INVOKER + RLS-ENFORCED + granted
//       to `authenticated`. For its RLS (account_trans_insert wr_access-JOIN, 006)
//       to actually FENCE — not silently pass because service_role is BYPASSRLS —
//       the statement must run as the `authenticated` role WITH auth.uid() resolving
//       to the bound tenant. So withTenant() opens a transaction and, per the Python
//       TenantBoundConnection analogue (workers/etl/.../connection.py) generalized to
//       the RLS-context model, binds the tenant for the duration:
//         SET LOCAL ROLE authenticated;
//         set_config('request.jwt.claims', '{"sub":<uid>,"role":"authenticated"}', true);
//         set_config('request.jwt.claim.sub', <uid>, true);   -- auth.uid() variants
//       Everything in fn() then executes as that tenant under RLS. LOCAL scope resets
//       at COMMIT/ROLLBACK — no leakage across transactions.
//
//   (2) Privileged service_role path → `withServiceRole(fn)`.
//       The provider snapshot + valuation writes (holdings_checkpoint / 018,
//       account_balance_checkpoint / 018, eod_price provider_implied / 019, and the
//       GLOBAL pfin.asset auto-register / 020) are DELIBERATELY privileged: they land
//       shared reference / append-only snapshot rows that authenticated may not write.
//       withServiceRole() runs them under `SET LOCAL ROLE service_role` (BYPASSRLS,
//       Decision 1 privileged-context-write). The DB-side novel #7/#11 fences + the
//       NaN/qty CHECKs still fire under service_role (triggers/CHECKs are role-agnostic)
//       — so the resolved security_id is validated global-OR-owned regardless of RLS
//       bypass (Sec guard #2, satisfied by the shipped fences; no new mechanism here).
//
// Tenant binding is at CONSTRUCTION (forTenant(config, usersId)); BOTH paths are
// scoped to that one users_id. account_id resolution (providerAccountId → account_id)
// is done under withTenant() so RLS scopes it to the bound tenant's accounts — the
// service_role writes then reference only those tenant-owned account_ids.
//
// LOGIN ROLE (RATIFIED — F/CTO 2026-07-17, resolution (b) authenticator):
//   Both `SET LOCAL ROLE authenticated` (tenant path) and `SET LOCAL ROLE service_role`
//   (privileged path) require the DB LOGIN role to be a member of the target roles. The
//   worker therefore connects as `authenticator` — the Supabase NOINHERIT broker role
//   that is a member of anon/authenticated/service_role and holds no privilege of its own
//   until it SET-ROLEs into one. This is FAIL-CLOSED: authenticator inherits nothing, so
//   a statement that never switches role can touch no tenant OR privileged surface.
//   Capability smoke-verified GREEN under the real login role (temp/provider-sync-login-
//   role-capability.md, checks T1–T5; ADR-019 login-role note in DECISIONS.md).
//   NOTE: the worker does NOT log in as `service_role` and MUST NOT be reconfigured to —
//   granting `authenticated` membership TO `service_role` (so a service_role login could
//   SET ROLE authenticated) was the REJECTED alternative: service_role is BYPASSRLS +
//   INHERIT, so that path is fail-OPEN. authenticator (NOINHERIT) is the ratified posture.

import postgres from 'postgres';
import type { Sql } from 'postgres';
import type { WorkerConfig } from '../config/env.js';

/** A postgres.js transaction handle (tagged-template SQL bound to one tx connection). */
export type Tx = Sql;

export class TenantBoundClient {
	/** The SOLE raw Postgres client in provider-sync/src (fence anchor). */
	readonly #sql: Sql;
	readonly #usersId: string;

	private constructor(sql: Sql, usersId: string) {
		this.#sql = sql;
		this.#usersId = usersId;
	}

	/**
	 * Construct a tenant-bound client. `usersId` is bound for the lifetime of the
	 * instance; every withTenant()/withServiceRole() transaction is scoped to it.
	 */
	static forTenant(config: WorkerConfig, usersId: string): TenantBoundClient {
		if (!usersId || !/^[0-9a-f-]{36}$/i.test(usersId)) {
			throw new Error('TenantBoundClient.forTenant requires a real users_id (uuid).');
		}
		const sql = postgres({
			host: config.db.host,
			port: config.db.port,
			database: config.db.database,
			username: config.db.user,
			password: config.db.password,
			max: 1, // single short-lived worker connection (NullPool-equivalent posture)
			prepare: true,
			onnotice: () => {} // suppress NOTICE noise; failures still throw
		});
		return new TenantBoundClient(sql, usersId);
	}

	/** The bound tenant (read-only; the binding is immutable per instance). */
	get usersId(): string {
		return this.#usersId;
	}

	/**
	 * INVOKER / caller-RLS path. Runs `fn` inside a transaction bound to the tenant's
	 * RLS context (role authenticated + jwt sub = usersId). Use for fn_ingest_transactions
	 * and any authenticated-tier RLS-enforced read/write (e.g. account_id resolution).
	 */
	async withTenant<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
		return this.#sql.begin(async (tx) => {
			await tx.unsafe('set local role authenticated');
			// Bind auth.uid() → the tenant. Both GUCs set to cover the auth.uid()
			// implementation variants (jsonb `request.jwt.claims` and the flat
			// `request.jwt.claim.sub`). set_config(..., true) = LOCAL (tx-scoped).
			const claims = JSON.stringify({ sub: this.#usersId, role: 'authenticated' });
			await tx`select set_config('request.jwt.claims', ${claims}, true)`;
			await tx`select set_config('request.jwt.claim.sub', ${this.#usersId}, true)`;
			return fn(tx as unknown as Tx);
		}) as Promise<T>;
	}

	/**
	 * Privileged service_role path. Runs `fn` inside a transaction as service_role
	 * (BYPASSRLS, Decision 1 privileged-context-write). Use for the provider snapshot /
	 * valuation / global-asset writes that authenticated may not perform. The DB-side
	 * #7/#11 security_id fences + NaN/qty CHECKs still fire (role-agnostic).
	 */
	async withServiceRole<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
		return this.#sql.begin(async (tx) => {
			await tx.unsafe('set local role service_role');
			return fn(tx as unknown as Tx);
		}) as Promise<T>;
	}

	/** Close the underlying connection (call once at worker shutdown). */
	async end(): Promise<void> {
		await this.#sql.end();
	}
}
