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
import { landAccounts, type TaxTreatment } from '../ingest/accountMapper.js';

/** The 003 tax_treatment CHECK domain — validated at parse time so a bad flag fails fast
 *  (before any provider/DB touch) rather than as a DB CHECK violation mid-map. */
const TAX_TREATMENTS: readonly TaxTreatment[] = ['taxable', 'tax_deferred', 'tax_free'];

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
	/** When true, after connect() the SAME returned refs are mapped to pfin.account rows
	 *  (one connect→map sandbox run; ADR-027 amendment §6-(a)). */
	map: boolean;
	/** Provisional slice-wide scope for the mapped accounts (§4.2). Default 'personal'. */
	scope: string;
	/** Provisional slice-wide tax_treatment (§4.2), retirement-nudged per account. Default 'taxable'. */
	taxTreatment: TaxTreatment;
}

/**
 * Parse `--owner <uuid> [--public-token <token>] [--map] [--scope <s>] [--tax-treatment <t>]`.
 * ownerUserId is REQUIRED (§4). --scope/--tax-treatment are provisional mapping defaults
 * (§4.2), only consulted when --map is passed; --tax-treatment is validated against the 003
 * CHECK domain (fail-fast).
 */
export function parseAdmitArgs(argv: readonly string[]): AdmitArgs {
	let ownerUserId: string | undefined;
	let publicToken: string | undefined;
	let map = false;
	let scope = 'personal';
	let taxTreatment: string = 'taxable';
	for (let i = 0; i < argv.length; i++) {
		if (argv[i] === '--owner') ownerUserId = argv[++i];
		else if (argv[i] === '--public-token') publicToken = argv[++i];
		else if (argv[i] === '--map') map = true;
		else if (argv[i] === '--scope') scope = argv[++i] ?? scope;
		else if (argv[i] === '--tax-treatment') taxTreatment = argv[++i] ?? taxTreatment;
	}
	if (!ownerUserId) {
		throw new Error('admit CLI requires --owner <ownerUserId uuid> (the resolved tenant; §4).');
	}
	if (!(TAX_TREATMENTS as readonly string[]).includes(taxTreatment)) {
		throw new Error(
			`admit CLI --tax-treatment='${taxTreatment}' is invalid; must be one of ${TAX_TREATMENTS.join(' | ')} (003 CHECK).`
		);
	}
	return { ownerUserId, publicToken, map, scope, taxTreatment: taxTreatment as TaxTreatment };
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

	// --map: map the SAME refs connect() returned into pfin.account rows (no re-fetch; one
	// connect→map run, §6-(a)). Writes under the TENANT context (withTenant / INVOKER, Q1) —
	// a FRESH TenantBoundClient (connect() already ended its own admission client). The
	// factory (not this file) constructs the raw client → TBC-node fence stays satisfied.
	if (args.map) {
		const client = TenantBoundClient.forTenant(config, args.ownerUserId);
		try {
			const accountIdByProvider = await landAccounts(
				client,
				result.sourceId,
				args.ownerUserId,
				result.accounts,
				{ scope: args.scope, taxTreatment: args.taxTreatment },
				PlaidAdapter.mapAccountType
			);
			console.log(
				`mapped ${accountIdByProvider.size}/${result.accounts.length} account(s) ` +
					`[scope=${args.scope} tax_treatment=${args.taxTreatment} (provisional; SELF-212-corrected)]`
			);
			for (const a of result.accounts) {
				const accountId = accountIdByProvider.get(a.providerAccountId);
				const acctType = PlaidAdapter.mapAccountType(a.type, a.subtype);
				console.log(`  • ${a.name} [${a.type}/${a.subtype ?? '-'} → ${acctType}] account_id=${accountId ?? '?'}`);
			}
		} finally {
			await client.end();
		}
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
