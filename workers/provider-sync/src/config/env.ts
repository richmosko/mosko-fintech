// env.ts — env-var wiring for the provider-sync worker.
//
// Reads the CONTRACT keys enumerated in workers/provider-sync/.env.example (DevOps-
// owned; real values Coolify-injected on the greenfield VPS per ADR-021). This worker
// reaches pfin via DIRECT Postgres + PFIN_DB_PASSWORD only (Lock 13 mod #3). The
// Supabase admin service-role credential is intentionally not part of this worker's
// env surface (fence-tbc-node LEG 2); its rationale lives in the un-scanned .env.example
// / Dockerfile, never in src/.
//
// PLAID_ENV is read here (sandbox default) even though .env.example does not list it
// yet — V1.0 is Plaid SANDBOX tier; production tier is F/CTO-gated behind SELF-212.
// Flagged to DevOps to add PLAID_ENV to the .env.example contract.

import { z } from 'zod';

/** Validated worker configuration (fail-closed: a missing required key throws at boot). */
export interface WorkerConfig {
	readonly db: {
		readonly host: string;
		readonly port: number;
		readonly database: string;
		readonly user: string;
		readonly password: string;
	};
	readonly plaid: {
		readonly clientId: string;
		readonly secret: string;
		readonly env: 'sandbox' | 'production';
	};
	/** SimpleFIN fallback token — OPTIONAL in PR #1 (adapter is DEFERRED to PR #2). */
	readonly simplefinToken: string | undefined;
	/** Coolify→Discord failure/health routing — OPTIONAL (scheduler PR #2). */
	readonly discordWebhookUrl: string | undefined;
}

// `.strict()` is not meaningful for process.env (a wide record); instead we pick +
// validate exactly the keys we consume. Required keys use `.min(1)` so an empty
// Coolify var fails loudly at boot rather than surfacing as a runtime auth error.
const nonEmpty = z.string().min(1);

const envSchema = z.object({
	PFIN_DB_HOST: nonEmpty,
	PFIN_DB_PORT: z.coerce.number().int().positive().default(5432),
	PFIN_DB_NAME: nonEmpty,
	PFIN_DB_USER: nonEmpty,
	PFIN_DB_PASSWORD: nonEmpty,
	PLAID_CLIENT_ID: nonEmpty,
	PLAID_SECRET: nonEmpty,
	PLAID_ENV: z.enum(['sandbox', 'production']).default('sandbox'),
	SIMPLEFIN_TOKEN: z.string().optional(),
	DISCORD_WEBHOOK_URL: z.string().optional()
});

/**
 * Load + validate worker config from an env-like record (defaults to process.env).
 * Throws a readable aggregate error if any required key is missing/empty.
 */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): WorkerConfig {
	const parsed = envSchema.safeParse(env);
	if (!parsed.success) {
		const missing = parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ');
		throw new Error(`provider-sync config invalid: ${missing}`);
	}
	const e = parsed.data;
	return {
		db: {
			host: e.PFIN_DB_HOST,
			port: e.PFIN_DB_PORT,
			database: e.PFIN_DB_NAME,
			user: e.PFIN_DB_USER,
			password: e.PFIN_DB_PASSWORD
		},
		plaid: { clientId: e.PLAID_CLIENT_ID, secret: e.PLAID_SECRET, env: e.PLAID_ENV },
		simplefinToken: e.SIMPLEFIN_TOKEN,
		discordWebhookUrl: e.DISCORD_WEBHOOK_URL
	};
}
