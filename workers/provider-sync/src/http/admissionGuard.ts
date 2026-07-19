// admissionGuard.ts — CA-1 (Sec SELF-212) fail-closed private-only startup assertion.
//
// LIMB (a) of C6-1 (DevOps spike §Limb-a, Sec CO-REVIEW ADDENDUM #1): the admission HTTP
// server refuses to boot unless BOTH hold:
//   (1) an affirmative private-only opt-in (`ADMISSION_PRIVATE_ONLY=true`), AND
//   (2) the ABSENCE of any Coolify public-route env signal for this service.
// Either an unset opt-in OR any public-route signal → fail closed (refuse to serve). There
// is no config state that silently yields a public admission endpoint.
//
// CAVEAT-2 (Sec-accepted correction): this does NOT check the socket bind address —
// in-container `0.0.0.0` is REQUIRED for sibling reach over the internal Docker network.
// The exposure control is the Coolify proxy-Domain / published-port, surfaced to the worker
// as the injected public-route env family — NOT the bind address.
//
// CA-1 (env-name-drift must fail closed, not open): the tripwire keys on PATTERN/PREFIX
// matches, NOT a hardcoded exact-name allowlist. A Coolify upgrade that renames/adds an FQDN
// var must not silently slip a Domain past an exact-name check. The pattern set below is a
// COORDINATED CONTRACT with DevOps (spike §Limb-a); DevOps verifies it against the running
// Coolify version's actually-injected var names at deploy (that live-version cross-check is
// the deploy-gate half of CA-1; this file is the code half). CA-2's deploy-time external-
// reachability negative smoke test is the empirical backstop and lives at the deploy gate,
// not in the worker.

/** A single public-route env-name matcher. `test(NAME_UPPERCASED)` → true means "this env
 *  var name is a Coolify public-route signal" → the worker must fail closed. */
export interface PublicRouteMatcher {
	readonly label: string;
	test(upperName: string): boolean;
}

/**
 * The public-route env-name PATTERN set (CA-1). Prefix/substring matches over the UPPERCASED
 * env-var name — deliberately broad so a renamed/added Coolify FQDN var is caught by pattern,
 * not missed by an exact-name gap. Sourced from the DevOps C6-1 spike §Limb-a; treat this as
 * the coordinated contract surface — DevOps confirms/extends it against the live Coolify
 * version at deploy. Add patterns here (never narrow to exact names).
 */
export const PUBLIC_ROUTE_ENV_MATCHERS: readonly PublicRouteMatcher[] = [
	// Coolify injects `SERVICE_FQDN_<NAME>` when a Domain is assigned to a service.
	{ label: 'SERVICE_FQDN_*', test: (n) => n.startsWith('SERVICE_FQDN_') },
	// `SERVICE_URL_<ID>` is a DISTINCT family (Compose deploys with an assigned domain) that
	// does NOT reliably co-appear with SERVICE_FQDN_ — Coolify bugs #8912/#6124 show FQDN/URL
	// generics update inconsistently, so keying only on FQDN is an env-name-drift fail-open
	// (CA-1). DevOps live-Coolify cross-check: temp/self212-devops-ca1-coolify-route-envvars.md.
	{ label: 'SERVICE_URL_*', test: (n) => n.startsWith('SERVICE_URL_') },
	// Coolify URL/FQDN families (`COOLIFY_URL`, `COOLIFY_FQDN`, and version variants).
	{ label: 'COOLIFY_*URL*', test: (n) => n.startsWith('COOLIFY_') && n.includes('URL') },
	{ label: 'COOLIFY_*FQDN*', test: (n) => n.startsWith('COOLIFY_') && n.includes('FQDN') },
	// Explicit opt-in public-URL signal (belt-and-suspenders; if anything sets this, refuse).
	{ label: 'ADMISSION_PUBLIC_URL', test: (n) => n === 'ADMISSION_PUBLIC_URL' }
];

/** The first public-route signal present in `env`, or null. Case-insensitive on the name. */
export function detectPublicRouteSignal(
	env: Record<string, string | undefined>,
	matchers: readonly PublicRouteMatcher[] = PUBLIC_ROUTE_ENV_MATCHERS
): string | null {
	for (const name of Object.keys(env)) {
		// Only a set (non-empty) value counts as a live signal — an empty string is not a route.
		if (env[name] === undefined || env[name] === '') continue;
		const upper = name.toUpperCase();
		for (const m of matchers) {
			if (m.test(upper)) return name;
		}
	}
	return null;
}

/**
 * CA-1 fail-closed assertion. Throws (refuse to serve) unless `ADMISSION_PRIVATE_ONLY==='true'`
 * AND no public-route env signal is present. Pure + side-effect-free (reads only the passed
 * record) so it is unit-testable without process.env. The thrown message names WHY (opt-in vs
 * which signal matched) — the matched env NAME only, never a value.
 */
export function assertPrivateOnly(
	env: Record<string, string | undefined>,
	matchers: readonly PublicRouteMatcher[] = PUBLIC_ROUTE_ENV_MATCHERS
): void {
	if (env.ADMISSION_PRIVATE_ONLY !== 'true') {
		throw new Error(
			'admission server refuses to serve: ADMISSION_PRIVATE_ONLY must be exactly "true" ' +
				'(fail-closed private-only opt-in, CA-1). This endpoint is internal-Docker-network ' +
				'only and MUST NOT be publicly routed.'
		);
	}
	const signal = detectPublicRouteSignal(env, matchers);
	if (signal !== null) {
		throw new Error(
			`admission server refuses to serve: a Coolify public-route signal is present ` +
				`(env "${signal}", CA-1). The admission endpoint must never be assigned a public ` +
				`Domain / published port. Remove the public route, then restart.`
		);
	}
}
