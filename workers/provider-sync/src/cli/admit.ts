// admit.ts — provider-sync dev CLI: drive PlaidAdapter.connect() for a SANDBOX Item.
//
// SC3-C2 (SANDBOX-GATED — load-bearing): this CLI refuses to run unless PLAID_ENV=sandbox
// (assertSandboxGate throws at startup otherwise). It is NEVER the production admission
// path — production onboarding goes through the future api/src server-session relay (the
// worker-owns-exchange split, ADR-027 amendment), which derives ownerUserId from the
// server-validated session, NOT from an operator-supplied flag. This CLI supplies the
// tenant explicitly (a known dev/test user) — acceptable for sandbox only (design §4).
//
// USAGE (sandbox only):
//   PLAID_ENV=sandbox PLAID_CLIENT_ID=... PLAID_SECRET=... PFIN_DB_*=... \
//     node dist/cli/admit.js --owner <ownerUserId-uuid> [--public-token <token>]
//   With no --public-token, a sandbox public_token is minted via
//   /sandbox/public_token/create (mirrors temp/plaid-test.mjs).

import { fileURLToPath } from 'node:url';
import { Configuration, PlaidApi, PlaidEnvironments } from 'plaid';
import { loadConfig, type WorkerConfig } from '../config/env.js';
import { TenantBoundClient } from '../db/TenantBoundClient.js';
import { PlaidAdapter, type PlaidClientLike } from '../adapters/PlaidAdapter.js';

/**
 * SC3-C2 sandbox gate. Refuse any non-sandbox env. Kept pure + side-effect-free so it is
 * unit-testable without constructing a Plaid client or reading process.env.
 */
export function assertSandboxGate(plaidEnv: string): void {
	if (plaidEnv !== 'sandbox') {
		throw new Error(
			`admit CLI refuses to run: PLAID_ENV='${plaidEnv}' (must be 'sandbox'). ` +
				'This dev CLI is sandbox-only (SC3-C2); production admission goes through the ' +
				'api/src server-session relay, never this CLI.'
		);
	}
}

export interface AdmitArgs {
	ownerUserId: string;
	publicToken: string | undefined;
}

/** Parse `--owner <uuid> [--public-token <token>]`. ownerUserId is REQUIRED (§4). */
export function parseAdmitArgs(argv: readonly string[]): AdmitArgs {
	let ownerUserId: string | undefined;
	let publicToken: string | undefined;
	for (let i = 0; i < argv.length; i++) {
		if (argv[i] === '--owner') ownerUserId = argv[++i];
		else if (argv[i] === '--public-token') publicToken = argv[++i];
	}
	if (!ownerUserId) {
		throw new Error('admit CLI requires --owner <ownerUserId uuid> (the resolved tenant; §4).');
	}
	return { ownerUserId, publicToken };
}

/** Build the real Plaid SDK client for the configured (sandbox) env. */
export function buildPlaidClient(config: WorkerConfig): PlaidApi {
	const configuration = new Configuration({
		basePath: PlaidEnvironments[config.plaid.env],
		baseOptions: {
			headers: { 'PLAID-CLIENT-ID': config.plaid.clientId, 'PLAID-SECRET': config.plaid.secret }
		}
	});
	return new PlaidApi(configuration);
}

/** Drive connect() for a sandbox Item. C2 gate first; mints a sandbox public_token if none. */
export async function runAdmit(config: WorkerConfig, argv: readonly string[]): Promise<void> {
	assertSandboxGate(config.plaid.env); // SC3-C2 — before any provider/DB touch.
	const args = parseAdmitArgs(argv);
	const plaid = buildPlaidClient(config) as unknown as PlaidClientLike;

	let publicToken = args.publicToken;
	if (!publicToken) {
		const { data } = await plaid.sandboxPublicTokenCreate({
			institution_id: 'ins_109508',
			initial_products: ['transactions', 'investments']
		});
		publicToken = data.public_token;
	}

	// The factory (NOT this file) constructs the raw Postgres client → TBC-node fence stays
	// satisfied; the KEY literal never appears here (LEG 2 zero-hit).
	const dbFor = (usersId: string): TenantBoundClient => TenantBoundClient.forTenant(config, usersId);
	const adapter = new PlaidAdapter(plaid, dbFor, (m) => console.log(`[admit] ${m}`));

	const result = await adapter.connect({ provider: 'plaid', publicToken, ownerUserId: args.ownerUserId });
	// SC3-C4: NEVER print the access_token — only the source id + non-credential account refs.
	console.log(`admitted source_id=${result.sourceId} accounts=${result.accounts.length}`);
	for (const a of result.accounts) {
		console.log(`  • ${a.name} [${a.type}/${a.subtype ?? '-'}] ${a.currency}`);
	}
}

async function main(): Promise<void> {
	await runAdmit(loadConfig(), process.argv.slice(2));
}

// Entrypoint guard: run main() only when invoked directly (node dist/cli/admit.js), NOT
// when imported by the unit test (under vitest, argv[1] is the test runner).
const invokedPath = process.argv[1];
const isMain = invokedPath !== undefined && fileURLToPath(import.meta.url) === invokedPath;
if (isMain) {
	main().catch((err: unknown) => {
		// SC3-C4: surface only a scrubbed message (adapter errors are already scrubbed).
		console.error(err instanceof Error ? err.message : String(err));
		process.exitCode = 1;
	});
}
