// serve-admission.ts — SELF-212 Option C admission-server entrypoint.
//
// Boots the inbound admission HTTP server (leg-1 link_token mint + leg-2 exchange/admit). This
// is the PRODUCTION onboarding path the sandbox-only cli/admit.ts always deferred to. DevOps
// owns the Dockerfile CMD / Coolify service (`node dist/cli/serve-admission.js`); this file wires
// config + the Plaid client + the tenant-bound service_role DB factory into the server.
//
// Boot order is fail-closed: loadAdmissionConfig() runs the CA-1 private-only guard + requires
// the shared secret BEFORE the listener binds. Any misconfig throws → non-zero exit → Coolify→
// Discord alert. NOTE: unlike cli/admit.ts there is NO sandbox gate — this IS the production
// path (Plaid tier is governed by PLAID_ENV / the SELF-212 F/CTO production-tier call).

import { fileURLToPath } from 'node:url';
import { loadConfig } from '../config/env.js';
import { TenantBoundClient } from '../db/TenantBoundClient.js';
import { PlaidAdapter, type PlaidClientLike } from '../adapters/PlaidAdapter.js';
import { SimpleFINAdapter } from '../adapters/SimpleFINAdapter.js';
import { buildPlaidClient } from './admit.js';
import { mintLinkToken } from '../http/linkToken.js';
import { loadAdmissionConfig } from '../http/admissionConfig.js';
import { createAdmissionServer, type ExchangeInput, type SimplefinClaimInput } from '../http/admissionServer.js';

export async function main(): Promise<void> {
	const config = loadConfig();
	const admission = loadAdmissionConfig(); // CA-1 guard + shared secret (fail-closed).

	const plaid = buildPlaidClient(config) as unknown as PlaidClientLike;

	// The dbFor FACTORY (not this file, not the adapter) constructs the raw Postgres client via
	// TenantBoundClient.forTenant → the fence-tbc-node LEG-1 anchor stays the sole construction
	// site; the service_role key literal never appears here (LEG-2 zero-hit).
	const dbFor = (usersId: string): TenantBoundClient => TenantBoundClient.forTenant(config, usersId);
	// Token-free logger (C6-5): the adapter/server only ever hand it non-credential diagnostics.
	const adapter = new PlaidAdapter(plaid, dbFor, (m) => console.log(`[admission] ${m}`));
	// leg-S: SimpleFINAdapter shares the SAME dbFor factory (TBC-node fence stays satisfied — the
	// factory, not this file, builds the raw client). No provider SDK: SimpleFIN is claim-over-HTTP,
	// so the adapter's default global fetch is used (no client construction here).
	const sfAdapter = new SimpleFINAdapter(dbFor, (m) => console.log(`[admission] ${m}`));

	const server = createAdmissionServer({
		sharedSecret: admission.sharedSecret,
		mintLinkToken: (ownerUserId) => mintLinkToken(plaid, ownerUserId),
		admit: (input: ExchangeInput) =>
			adapter.connect({
				provider: 'plaid',
				publicToken: input.publicToken,
				ownerUserId: input.ownerUserId,
				institutionId: input.institutionId,
				institutionName: input.institutionName
			}),
		admitSimplefin: (input: SimplefinClaimInput) =>
			sfAdapter.connect({
				provider: 'simplefin',
				setupToken: input.setupToken,
				ownerUserId: input.ownerUserId,
				institutionName: input.institutionName
			}),
		logger: (m) => console.log(`[admission] ${m}`)
	});

	await new Promise<void>((resolve) => {
		server.listen(admission.port, admission.host, () => {
			// Never log the shared secret. Host/port are non-sensitive internal coordinates.
			console.log(`[admission] listening on ${admission.host}:${admission.port} (private-only)`);
			resolve();
		});
	});
}

// Entrypoint guard: run only when invoked directly (node dist/cli/serve-admission.js), NOT when
// imported by a unit test.
const invokedPath = process.argv[1];
const isMain = invokedPath !== undefined && fileURLToPath(import.meta.url) === invokedPath;
if (isMain) {
	main().catch((err: unknown) => {
		console.error(err instanceof Error ? err.message : String(err));
		process.exitCode = 1;
	});
}
