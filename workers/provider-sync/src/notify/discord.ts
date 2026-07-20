// discord.ts — provider-sync worker → Discord webhook egress (SELF-279 / CA-2).
//
// This is the worker's FIRST direct outbound POST that is NOT to a provider (Plaid/SimpleFIN)
// or pfin — a new trust-boundary egress (Sec joint-review §8 #1). It reuses the already-plumbed
// `DISCORD_WEBHOOK_URL` (env.ts / config.discordWebhookUrl); no new secret is introduced.
//
// STRUCTURE mirrors the worker's pure-core ⟂ thin-network-seam convention (poll.ts /
// admissionServer.ts): buildCa2Alert() is a PURE payload builder (the C1 scrub guarantee is
// asserted here + unit-testable with literals), postDiscord() is a THIN, FAIL-SAFE poster that
// SWALLOWS every error (never throws, never flips the poll fleet-fatal — C3).
//
// ── C1 SCRUB INVARIANT (BLOCKING) ──────────────────────────────────────────────────────
//   buildCa2Alert serializes ONLY allow-listed, non-sensitive values: the probed public URL
//   (public by definition — a bare https FQDN validated upstream, no query/userinfo), a FIXED
//   fingerprint DESCRIPTOR LITERAL (our own constant, NEVER the raw response body), and a UTC
//   timestamp. It NEVER serializes the raw probe response body, a token, the shared secret,
//   `PFIN_DB_*`, an `access_token`/`public_token`, or an `ownerUserId`. The probe holds NO
//   tenant credential by construction (it is a plain outbound GET to a public URL), so there is
//   structurally nothing tenant-scoped to leak — the scrub is belt on top of that guarantee.

const DISCORD_POST_TIMEOUT_MS = 5_000;

const CA2_ALERT_DESCRIPTION =
	'The provider-sync admission endpoint answered an ADMISSION-APP fingerprint from an external ' +
	'probe. It must be internal-Docker-network-only. Investigate a post-deploy Coolify Domain-assign ' +
	'+ stale-env (coollabsio/coolify #8912/#6124). The endpoint stays shared-secret-authed ' +
	'(authenticated-reachable, not an unauth breach) — reduced-severity, but remediate.';

/** A tripped probe target — the fully-probed URL + the FIXED fingerprint descriptor literal that
 *  matched. BOTH are non-sensitive: the URL is a validated bare public FQDN, the fingerprint is
 *  one of our own compile-time constants (never response-body-derived). */
export interface TrippedTarget {
	readonly url: string;
	readonly fingerprint: string;
}

/** The minimal probe report shape buildCa2Alert consumes (a structural subset of ProbeReport in
 *  reachabilityProbe.ts, re-declared here so notify/ has no dependency back on the probe module). */
export interface Ca2AlertInput {
	readonly tripped: readonly TrippedTarget[];
}

export interface DiscordEmbedField {
	readonly name: string;
	readonly value: string;
}
export interface DiscordEmbed {
	readonly title: string;
	readonly description: string;
	readonly fields: DiscordEmbedField[];
}
export interface DiscordPayload {
	readonly content: string;
	readonly embeds: DiscordEmbed[];
}

/**
 * PURE — build the CA-2 positive-detection Discord payload from the probe report. Reads ONLY the
 * tripped URLs + their fixed fingerprint descriptors + the supplied UTC timestamp (C1). NO raw
 * response body, NO secret, NO token, NO tenant-PII ever enters this object. Deterministic (no
 * clock read — `nowIso` is injected) so it unit-tests against literals.
 */
export function buildCa2Alert(input: Ca2AlertInput, nowIso: string): DiscordPayload {
	// Allow-listed fields ONLY. Each value is either a validated-public URL, one of OUR fingerprint
	// constants, or the injected timestamp — nothing derived from a probe response body.
	const probedUrls = input.tripped.map((t) => t.url).join(', ');
	const fingerprints = input.tripped.map((t) => t.fingerprint).join('; ');
	return {
		content: '🚨 provider-sync CA-2: admission endpoint PUBLICLY REACHABLE',
		embeds: [
			{
				title: 'CA-2 recurring reachability probe — POSITIVE DETECTION',
				description: CA2_ALERT_DESCRIPTION,
				fields: [
					{ name: 'probed_url', value: probedUrls || '(none)' },
					{ name: 'fingerprint', value: fingerprints || '(none)' },
					{ name: 'detected_at_utc', value: nowIso }
				]
			}
		]
	};
}

// ── Network seam (injectable for tests — no live Discord) ────────────────────────────────
// A minimal structural fetch type (mirrors SimpleFINAdapter.FetchLike) so a test stub is a plain
// object and we do not couple to the exact global `fetch` signature.

export interface DiscordFetchInit {
	method?: string;
	headers?: Record<string, string>;
	body?: string;
	signal?: AbortSignal;
}
export interface DiscordResponseLike {
	ok: boolean;
	status: number;
}
export type DiscordFetch = (url: string, init?: DiscordFetchInit) => Promise<DiscordResponseLike>;

export interface PostDiscordDeps {
	/** Injectable fetch (defaults to global fetch). */
	fetchImpl?: DiscordFetch;
	/** Token-free diagnostic logger (best-effort delivery outcome only — never a payload/secret). */
	log?: (message: string) => void;
	/** Per-post timeout (defaults to 5s). */
	timeoutMs?: number;
}

/**
 * THIN + FAIL-SAFE (C3) — POST the alert payload to the Discord webhook. SWALLOWS every failure
 * (webhook down / URL unset / 5xx / timeout / network) → a single non-fatal log line, NEVER a
 * throw. The finding is ALSO always emitted as a durable structured log upstream (the Discord
 * POST is best-effort delivery on top), so a swallowed error here never loses the finding.
 */
export async function postDiscord(
	webhookUrl: string,
	payload: DiscordPayload,
	deps: PostDiscordDeps = {}
): Promise<void> {
	const log = deps.log;
	const fetchImpl = deps.fetchImpl ?? (globalThis.fetch as unknown as DiscordFetch);
	try {
		const res = await fetchImpl(webhookUrl, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(payload),
			signal: AbortSignal.timeout(deps.timeoutMs ?? DISCORD_POST_TIMEOUT_MS)
		});
		if (!res.ok) {
			log?.(`CA-2 alert: Discord webhook returned HTTP ${res.status} (non-fatal, finding already logged)`);
		}
	} catch (err) {
		// Discard the raw error object — keep only a coarse message (never echo the payload/URL body).
		log?.(`CA-2 alert: Discord webhook post failed (non-fatal, finding already logged): ${err instanceof Error ? err.message : 'error'}`);
	}
}
