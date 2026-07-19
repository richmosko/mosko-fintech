// admissionConfig.ts — env wiring for the admission HTTP server ONLY.
//
// Kept SEPARATE from config/env.ts loadConfig() so the cron `poll` / dev `admit` paths do NOT
// require the admission shared secret. Loading admission config runs the CA-1 fail-closed guard
// FIRST (refuse to serve unless private-only + no public-route signal), THEN requires the
// shared secret + resolves the internal port.
//
// New env contract keys (flagged to DevOps for .env.example + secrets-manifest, spike C6-2):
//   ADMISSION_PRIVATE_ONLY          — must be exactly "true" (CA-1 opt-in; fail-closed).
//   WORKER_ADMISSION_SHARED_SECRET  — production-only secret, both tiers (C6-2). Never in repo.
//   ADMISSION_PORT                  — internal listen port (default 8081). expose:-only, never
//                                     published (DevOps limb-b committed-compose fence).
//   ADMISSION_HOST                  — internal bind host; default 0.0.0.0 (REQUIRED for sibling
//                                     reach — CAVEAT-2; the bind address is NOT the exposure
//                                     control, the Coolify public-route is).

import { assertPrivateOnly } from './admissionGuard.js';

export interface AdmissionConfig {
	readonly host: string;
	readonly port: number;
	readonly sharedSecret: string;
}

/** Minimum shared-secret length we accept at boot (a 256-bit `openssl rand -hex 32` is 64 hex
 *  chars; guard against an obviously-too-short/misconfigured secret). Fail-closed below this. */
const MIN_SECRET_LEN = 32;

/**
 * Load + validate admission config from an env-like record (defaults to process.env). Order is
 * load-bearing: the CA-1 private-only guard runs BEFORE the secret is read, so a public-route
 * misconfig fails closed even if the secret is present. Throws a readable error on any failure.
 */
export function loadAdmissionConfig(env: NodeJS.ProcessEnv = process.env): AdmissionConfig {
	// (1) CA-1 fail-closed private-only assertion FIRST.
	assertPrivateOnly(env as Record<string, string | undefined>);

	// (2) Shared secret (C6-2) — required, non-trivial length, fail-closed on absence.
	const sharedSecret = env.WORKER_ADMISSION_SHARED_SECRET;
	if (!sharedSecret || sharedSecret.length < MIN_SECRET_LEN) {
		throw new Error(
			'admission config invalid: WORKER_ADMISSION_SHARED_SECRET is required and must be a ' +
				`high-entropy secret (>= ${MIN_SECRET_LEN} chars). Provisioned by DevOps on both tiers.`
		);
	}

	// (3) Internal port + host.
	const portRaw = env.ADMISSION_PORT ?? '8081';
	const port = Number.parseInt(portRaw, 10);
	if (!Number.isInteger(port) || port <= 0 || port > 65535) {
		throw new Error(`admission config invalid: ADMISSION_PORT='${portRaw}' is not a valid port.`);
	}
	const host = env.ADMISSION_HOST ?? '0.0.0.0'; // CAVEAT-2: internal Docker-network reach.

	return { host, port, sharedSecret };
}
