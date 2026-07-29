// reauthPollE2E.dbit.test.ts — SELF-207 §2.4.4.b reauth full-loop E2E (QA-owned; the "live-DB G2
// integration test" poll.test.ts reserves for QA). REAL local Postgres + Vault, REAL poll loop,
// REAL SimpleFINAdapter.reauthComplete — nothing mocked but the SimpleFIN HTTP seam (injected
// fetch that returns the auth-failure / claim responses).
//
// THE FULL REAL-POLL-DRIVEN CHAIN (F/CTO-ratified shape — no seeded transition):
//   (1) drive a DEFINITIVE auth failure (HTTP 401) through the SHIPPED poll loop → the detector
//       flips connection_status → 'login_required' + appends a login_required state_history row
//       (provider_error_code http_401).
//   (2) idempotent: a 2nd consecutive 401 poll does NOT append a duplicate state_history row.
//   (3) FALSE-POSITIVE GUARD: a TRANSIENT failure (HTTP 500) on a healthy source does NOT flip
//       (stays healthy, no state_history row) — the "definitive auth-rejection only" contract.
//   (4) real reauthComplete with a fresh setup token → connection_status 'healthy' + a healthy
//       state_history row + IN-PLACE Vault rotation: the SAME credential_secret_id handle now
//       decrypts to the NEW Access URL (via pfin.decrypted_source_credential), external_connection_id
//       tracks the new digest, rotated:true. Proves the credential rotated without a new secret row.
//
// DETECTOR CONTRACT (verified in src, confirmed by team-lead): classifySimplefinUnhealthy reads
//   err.httpStatus (scrubbedSimplefinError attaches it) — 401/403 → login_required; 5xx/429/network/
//   no-status → transient → null → no flip.
//
// POSTURE (SECURITY §4.5): SYNTHETIC ONLY — an ephemeral auth.users tenant + synthetic SimpleFIN
//   Access URLs (throwaway; never real). The Vault secret holds a synthetic URL. Cleaned up in
//   afterAll (DELETE cascades the pfin rows + the fn_linked_source_cleanup_vault_secret trigger
//   removes the vault.secrets row).
//
// SELF-GATING: needs a live local Postgres. Set PFIN_TEST_DB_URL (e.g.
//   postgresql://postgres:postgres@127.0.0.1:54322/postgres) to run; absent → the suite skips (so
//   the DB-less worker unit CI job never reds). Raw seed/verify connection lives in tests/ (outside
//   the fence-tbc-node src/ scope); the CODE UNDER TEST uses the real TenantBoundClient.

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import postgres from 'postgres';
import { randomUUID } from 'node:crypto';
import { createPollHandlers, runPollLoop, resolveCredential, type PollWiring, type SourceRow } from '../src/cli/poll.js';
import { SimpleFINAdapter, accessUrlDigest, type FetchLike } from '../src/adapters/SimpleFINAdapter.js';
import { TenantBoundClient } from '../src/db/TenantBoundClient.js';
import type { WorkerConfig } from '../src/config/env.js';

declare const process: { env: Record<string, string | undefined> };

const DB_URL = process.env.PFIN_TEST_DB_URL;
const RUN = Boolean(DB_URL);

// Per-run unique so re-runs never collide on the linked_source (provider, external_connection_id)
// unique index (the digests are deterministic over the URL), even if a prior cleanup was skipped.
const TENANT = randomUUID();
const SUFFIX = randomUUID().slice(0, 8);
const OLD_URL = `https://svcuser:svcpass@bridge.example/access/OLD-${SUFFIX}`;
const NEW_URL = `https://svcuser:svcpass@bridge.example/access/NEW-${SUFFIX}`;
const B_URL = `https://svcuser:svcpass@bridge.example/access/B-${SUFFIX}`;
const SETUP_TOKEN = Buffer.from(`https://bridge.example/claim/${SUFFIX}`).toString('base64');

function configFrom(dbUrl: string): WorkerConfig {
	const u = new URL(dbUrl);
	return {
		db: {
			host: u.hostname,
			port: Number(u.port || '5432'),
			database: u.pathname.replace(/^\//, ''),
			user: decodeURIComponent(u.username),
			password: decodeURIComponent(u.password)
		},
		plaid: { clientId: 'cid', secret: 'sek', env: 'sandbox' },
		simplefinToken: undefined,
		discordWebhookUrl: undefined,
		probe: { publicUrls: [], confirmRoute: false, timeoutMs: 5000 }
	} as unknown as WorkerConfig;
}

/** A failing SimpleFIN /accounts fetch with a fixed HTTP status (drives the detector classifier). */
const failWith = (status: number): FetchLike => async () => ({ ok: false, status, text: async () => '', json: async () => ({}) });

/** Reauth claim fetch: POST claim → the NEW Access URL (text); GET /accounts → an empty set. */
const claimFetch = (newUrl: string): FetchLike => async (_url, init) =>
	init?.method === 'POST'
		? { ok: true, status: 200, text: async () => newUrl, json: async () => ({}) }
		: { ok: true, status: 200, text: async () => '', json: async () => ({ accounts: [], errors: [], errlist: [] }) };

const NOOP_SYNC = (async () => ({})) as unknown as PollWiring['sync'];

describe.skipIf(!RUN)('SELF-207 reauth full-loop E2E — real poll detector + real Vault rotation', () => {
	let config: WorkerConfig;
	let sql: postgres.Sql;
	let aSrc: number; // the login_required subject
	let bSrc: number; // the false-positive-guard (transient) subject
	let aSecretId: string; // A's Vault handle (must be UNCHANGED across the rotation)

	/** Seed a healthy SimpleFIN source with a REAL Vault credential; return (source_id, secret_id). */
	async function seedSource(accessUrl: string, digest: string): Promise<{ sourceId: number; secretId: string }> {
		const [{ secret_id }] = await sql<{ secret_id: string }[]>`
			select vault.create_secret(${accessUrl}, ${'e2e:' + digest.slice(0, 12)}, 'qa e2e synthetic') as secret_id`;
		const [{ source_id }] = await sql<{ source_id: string }[]>`
			insert into pfin.linked_source
				(users_id, provider, external_connection_id, credential_secret_id, connection_status, institution_name)
			values (${TENANT}, 'simplefin', ${digest}, ${secret_id}, 'healthy', 'QA E2E Bank')
			returning source_id`;
		return { sourceId: Number(source_id), secretId: secret_id };
	}

	const rowFor = (sourceId: number, digest: string): SourceRow => ({
		sourceId: String(sourceId),
		provider: 'simplefin',
		usersId: TENANT,
		externalConnectionId: digest,
		providerMetadata: null
	});

	function wiringWith(fetchLike: FetchLike): PollWiring {
		return {
			clientFor: (usersId) => TenantBoundClient.forTenant(config, usersId),
			buildAdapter: () => new SimpleFINAdapter(undefined, undefined, fetchLike),
			resolveCredential, // REAL — reads pfin.decrypted_source_credential under service_role
			sync: NOOP_SYNC, // never reached on a fetch-fail path
			syncDate: '2026-07-29'
		};
	}

	async function runOnePoll(row: SourceRow, fetchLike: FetchLike): Promise<void> {
		const handlers = createPollHandlers(wiringWith(fetchLike), () => {});
		await runPollLoop([row], handlers, '2026-07-29T00:00:00Z');
	}

	async function status(sourceId: number): Promise<string> {
		const [r] = await sql<{ connection_status: string }[]>`
			select connection_status from pfin.linked_source where source_id = ${sourceId}`;
		return r.connection_status;
	}
	async function historyRows(sourceId: number, statusClass: string): Promise<number> {
		const [r] = await sql<{ n: string }[]>`
			select count(*) as n from pfin.linked_source_state_history
			 where source_id = ${sourceId} and status_class = ${statusClass}`;
		return Number(r.n);
	}

	beforeAll(async () => {
		config = configFrom(DB_URL as string);
		sql = postgres(DB_URL as string, { onnotice: () => {}, max: 4 });
		await sql`insert into auth.users (id) values (${TENANT}) on conflict do nothing`;
		const a = await seedSource(OLD_URL, accessUrlDigest(OLD_URL)); aSrc = a.sourceId; aSecretId = a.secretId;
		const b = await seedSource(B_URL, accessUrlDigest(B_URL)); bSrc = b.sourceId;
	}, 60_000);

	afterAll(async () => {
		if (!sql) return;
		// The poll wrote IMMUTABLE sync_audit + state_history rows for this tenant. auth.users delete
		// cascades ON DELETE SET NULL onto sync_audit.users_id (an UPDATE) → block_mutation would raise.
		// So (test-harness only) transiently disable both immutability triggers, delete in dependency
		// order (state_history before its RESTRICT parent linked_source; sync_audit first so no SET
		// NULL fires), then re-enable. linked_source delete fires the vault-secret cleanup trigger.
		try {
			await sql`alter table pfin.linked_source_sync_audit disable trigger linked_source_sync_audit_block_mutation`;
			await sql`alter table pfin.linked_source_state_history disable trigger linked_source_state_history_block_mutation`;
			await sql`delete from pfin.linked_source_sync_audit where users_id = ${TENANT}`;
			await sql`delete from pfin.linked_source_state_history where source_id in (select source_id from pfin.linked_source where users_id = ${TENANT})`;
			await sql`delete from pfin.linked_source where users_id = ${TENANT}`;
			await sql`delete from auth.users where id = ${TENANT}`;
		} finally {
			await sql`alter table pfin.linked_source_sync_audit enable trigger linked_source_sync_audit_block_mutation`;
			await sql`alter table pfin.linked_source_state_history enable trigger linked_source_state_history_block_mutation`;
			await sql.end();
		}
	}, 30_000);

	it('(1) real poll 401 → detector flips connection_status to login_required + appends a login_required/http_401 state_history row', async () => {
		expect(await status(aSrc)).toBe('healthy'); // baseline
		await runOnePoll(rowFor(aSrc, accessUrlDigest(OLD_URL)), failWith(401));

		expect(await status(aSrc)).toBe('login_required');
		const [h] = await sql<{ status_class: string; provider_error_code: string }[]>`
			select status_class, provider_error_code from pfin.linked_source_state_history
			 where source_id = ${aSrc} order by history_id desc limit 1`;
		expect(h.status_class).toBe('login_required');
		expect(h.provider_error_code).toBe('http_401');
	});

	it('(2) idempotent: a 2nd consecutive 401 poll does NOT append a duplicate state_history row', async () => {
		const before = await historyRows(aSrc, 'login_required');
		await runOnePoll(rowFor(aSrc, accessUrlDigest(OLD_URL)), failWith(401));
		expect(await historyRows(aSrc, 'login_required')).toBe(before); // no flip (already login_required) → no new row
		expect(await status(aSrc)).toBe('login_required');
	});

	it('(3) false-positive guard: a TRANSIENT 500 poll on a healthy source does NOT flip (stays healthy, no state_history row)', async () => {
		expect(await status(bSrc)).toBe('healthy');
		await runOnePoll(rowFor(bSrc, accessUrlDigest(B_URL)), failWith(500));
		expect(await status(bSrc)).toBe('healthy'); // 500 is transient → classifier returns null → no flip
		expect(await historyRows(bSrc, 'login_required')).toBe(0); // and NO login_required transition written
	});

	it('(4) real reauthComplete → healthy + healthy state_history + IN-PLACE Vault rotation (same handle, decrypts to the NEW url)', async () => {
		const adapter = new SimpleFINAdapter((uid) => TenantBoundClient.forTenant(config, uid), undefined, claimFetch(NEW_URL));
		const result = await adapter.reauthComplete(
			{ linkedSourceId: BigInt(aSrc), ownerUserId: TENANT },
			{ kind: 'setup_token', setupToken: SETUP_TOKEN }
		);
		expect(result).toEqual({ connectionStatus: 'healthy', rotated: true });

		// connection flipped back to healthy + a healthy transition row appended.
		expect(await status(aSrc)).toBe('healthy');
		expect(await historyRows(aSrc, 'healthy')).toBeGreaterThanOrEqual(1);

		// IN-PLACE rotation: the SAME credential_secret_id handle (no new secret row) …
		const [{ credential_secret_id, external_connection_id }] = await sql<
			{ credential_secret_id: string; external_connection_id: string }[]
		>`select credential_secret_id, external_connection_id from pfin.linked_source where source_id = ${aSrc}`;
		expect(credential_secret_id).toBe(aSecretId); // handle UNCHANGED
		expect(external_connection_id).toBe(accessUrlDigest(NEW_URL)); // digest tracks the new credential

		// … now decrypts to the NEW Access URL (the Vault secret was rotated in place).
		const [{ decrypted_credential }] = await sql<{ decrypted_credential: string }[]>`
			select decrypted_credential from pfin.decrypted_source_credential
			 where source_id = ${aSrc} and users_id = ${TENANT}`;
		expect(decrypted_credential).toBe(NEW_URL);
	});
});
