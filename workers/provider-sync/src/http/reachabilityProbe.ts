// reachabilityProbe.ts — SELF-279 recurring CA-2 external reachability probe.
//
// WHAT: an ACTIVE external HTTP probe (F/CTO-ratified Option B) that catches the RT-27 residual
// the boot env-tripwire (CA-1) CANNOT see — a Coolify Domain assigned AFTER deploy + the stale-env
// bug (coollabsio/coolify #8912/#6124): env does not reflect the new Domain, yet the admission
// endpoint IS publicly reachable through the proxy. Only actual external reachability testing
// catches it. This complements CA-2's one-shot deploy-time smoke with a RECURRING runtime drift
// detector, folded into the @daily poll as an isolated pre-loop step (RF-1).
//
// POSTURE — HARDENING / ALERTING, NOT a ship-gate. A positive detection is a Discord-alerted
// security FINDING + a durable structured log; it NEVER exits 1, NEVER flips the poll fleet-fatal
// (C3). The residual it targets is already reduced-severity (even under a tripwire fail-open the
// endpoint stays shared-secret-authed — authenticated-reachable, not an unauth breach), which is
// why the failure posture is fail-SAFE (log-and-continue), not fail-closed.
//
// STRUCTURE mirrors poll.ts: PURE decision core (classifyProbeResponse / parseProbeTarget) ⟂ a
// thin network seam behind an injectable `fetchImpl` — the whole module unit-tests with NO real
// network. It touches NO DB and holds NO credential by construction (a plain outbound GET to a
// public URL), so there is nothing tenant-scoped to leak (§10 / Decision-3 UNTOUCHED).
//
// ── FINGERPRINT (F1, F/CTO-ratified) ─────────────────────────────────────────────────────
//   Positive = a 2xx that FINGERPRINTS as OUR admission app — a SUBSET match `body.status === 'ok'`
//   (NOT a strict whole-body deep-equal). Un-forgeable by a generic proxy/CDN 200 page (must be
//   structured JSON carrying that field), yet survives additive `/healthz` changes so it can never
//   silently false-negative. Bare reachability is NOT enough — a proxy 404 / Cloudflare challenge /
//   generic 200 HTML / a different service does NOT trip it.
//
// ── N1 SSRF HYGIENE ──────────────────────────────────────────────────────────────────────
//   Each configured URL must be a BARE public https FQDN (reject query-string / embedded userinfo /
//   fragment / path — the URL is echoed into the alert). `redirect: 'manual'` (no 30x-to-internal
//   chase), a per-URL AbortSignal.timeout, an 8 KB response-size cap, and a defensive JSON parse.
//   The probe sends NO auth header — it holds no credential, and stays that way.

import type { WorkerConfig } from '../config/env.js';
import { buildCa2Alert, postDiscord, type DiscordPayload } from '../notify/discord.js';

/** Primary fingerprint target — the unauthenticated liveness route (admissionServer.ts). */
export const HEALTHZ_PATH = '/healthz';
/** Optional confirmation target — an admission route probed with NO secret header ⇒ only ever a
 *  401 (no auth side-effect, admits nothing). Gated behind ADMISSION_PROBE_CONFIRM_ROUTE (Sec A). */
export const CONFIRM_PATH = '/admission/link-token';

/** FIXED fingerprint DESCRIPTOR LITERALS (C1) — the value echoed into the alert is one of THESE
 *  constants, NEVER the raw response body. */
export const HEALTHZ_FINGERPRINT = 'healthz 200 {status:ok}';
export const CONFIRM_FINGERPRINT = 'link-token 401 {error:unauthorized}';

/** 8 KB body-read cap — our admission app answers a tiny JSON body; anything larger is not us. */
export const MAX_PROBE_BODY_BYTES = 8 * 1024;

export type ProbeClassification = 'reachable-admission-app' | 'correctly-private';
export type ProbeCheck = 'healthz' | 'confirm';

/** One URL's probe outcome. `fingerprint` is a FIXED literal when reachable, else null. */
export interface ProbeOutcome {
	/** The fully-probed URL (base + path) — a validated bare public FQDN + our constant path. */
	readonly url: string;
	readonly classification: ProbeClassification;
	readonly fingerprint: string | null;
}

/** The report over the whole configured URL list. */
export interface ProbeReport {
	readonly positive: boolean;
	readonly tripped: { readonly url: string; readonly fingerprint: string }[];
	readonly checkedAt: string;
	/** Count of VALID targets actually probed (invalid entries are skipped, not counted). */
	readonly targetCount: number;
}

const errMessage = (err: unknown): string => (err instanceof Error ? err.message : String(err));

const isRecord = (v: unknown): v is Record<string, unknown> =>
	typeof v === 'object' && v !== null && !Array.isArray(v);

// ── PURE decision core ───────────────────────────────────────────────────────────────────

export type ParsedTarget = { ok: true; base: string } | { ok: false; reason: string };

/**
 * PURE — validate + normalize a configured probe URL (N1 SSRF hygiene). Accepts ONLY a bare public
 * https FQDN; rejects a non-https scheme, embedded userinfo/credentials, a query string, a fragment,
 * or a path beyond '/'. Returns the normalized origin (no trailing slash) on success. The rejection
 * `reason` is a CATEGORY LABEL ONLY — it NEVER echoes the raw string (a rejected entry could carry
 * userinfo credentials; logging it back would leak them).
 */
export function parseProbeTarget(raw: string): ParsedTarget {
	let u: URL;
	try {
		u = new URL(raw.trim());
	} catch {
		return { ok: false, reason: 'unparseable-url' };
	}
	if (u.protocol !== 'https:') return { ok: false, reason: 'not-https' };
	if (u.username !== '' || u.password !== '') return { ok: false, reason: 'embedded-userinfo' };
	if (u.search !== '') return { ok: false, reason: 'has-query-string' };
	if (u.hash !== '') return { ok: false, reason: 'has-fragment' };
	if (u.pathname !== '/' && u.pathname !== '') return { ok: false, reason: 'has-path' };
	// origin = scheme + host [+ :port], no trailing slash, no query/hash/userinfo — a clean base.
	return { ok: true, base: u.origin };
}

/**
 * PURE — the fingerprint decision (the false-positive guard lives here; 100% literal-testable).
 *   healthz : 200 AND a JSON object with `status === 'ok'` (SUBSET match F1 — additive-change-safe).
 *   confirm : 401 AND a JSON object with `error === 'unauthorized'` (the admission 401 envelope).
 * Anything else (wrong status, non-JSON/array/oversize body ⇒ passed as undefined, a foreign body)
 * ⇒ 'correctly-private'. A generic proxy/CDN 200 page cannot forge the structured field.
 */
export function classifyProbeResponse(check: ProbeCheck, status: number, body: unknown): ProbeClassification {
	if (check === 'healthz') {
		if (status === 200 && isRecord(body) && body['status'] === 'ok') return 'reachable-admission-app';
		return 'correctly-private';
	}
	// confirm
	if (status === 401 && isRecord(body) && body['error'] === 'unauthorized') return 'reachable-admission-app';
	return 'correctly-private';
}

// ── Thin network seam (injectable — no live network in tests) ─────────────────────────────
// A minimal structural fetch type (mirrors SimpleFINAdapter.FetchLike) so a test stub is a plain
// object. `redirect`/`signal` are carried so probeOne can enforce manual-redirect + timeout.

export interface ProbeRequestInit {
	method?: string;
	redirect?: 'manual' | 'follow' | 'error';
	signal?: AbortSignal;
	headers?: Record<string, string>;
}
export interface ProbeResponseLike {
	status: number;
	body?: ReadableStream<Uint8Array> | null;
	text(): Promise<string>;
}
export type ProbeFetch = (url: string, init?: ProbeRequestInit) => Promise<ProbeResponseLike>;

export interface ProbeOneDeps {
	fetchImpl: ProbeFetch;
	timeoutMs: number;
	confirmRoute: boolean;
	maxBytes?: number;
}

/** Read the response body with a HARD byte cap, then JSON-parse DEFENSIVELY. A read error, an
 *  oversize body, or a non-JSON body ⇒ undefined (⇒ classify → correctly-private; it is not our
 *  tiny admission app). Streams when a body stream is present (real fetch); falls back to a
 *  length-capped text() for a simple test stub. */
async function readCappedJson(res: ProbeResponseLike, maxBytes: number): Promise<unknown> {
	let text: string;
	try {
		const stream = res.body ?? null;
		if (stream) {
			const reader = stream.getReader();
			const chunks: Uint8Array[] = [];
			let total = 0;
			try {
				for (;;) {
					const { done, value } = await reader.read();
					if (done) break;
					if (value) {
						total += value.byteLength;
						if (total > maxBytes) {
							try {
								await reader.cancel();
							} catch {
								/* ignore */
							}
							return undefined; // oversize ⇒ not our tiny admission app.
						}
						chunks.push(value);
					}
				}
			} finally {
				try {
					reader.releaseLock();
				} catch {
					/* ignore */
				}
			}
			text = Buffer.concat(chunks.map((c) => Buffer.from(c))).toString('utf8');
		} else {
			const raw = await res.text();
			if (raw.length > maxBytes) return undefined; // oversize ⇒ not our tiny admission app.
			text = raw;
		}
	} catch {
		return undefined; // body read failed ⇒ treat as not-our-app (fail-safe).
	}
	try {
		return JSON.parse(text) as unknown;
	} catch {
		return undefined; // non-JSON body ⇒ not our admission app.
	}
}

/** Thin: do ONE probe request (manual-redirect + timeout + NO auth header), read the capped body,
 *  and delegate the decision to the pure classifier. A thrown fetch (connection refused / DNS /
 *  TLS / timeout AbortError) ⇒ 'correctly-private' (unreachable). */
async function fetchAndClassify(
	url: string,
	method: 'GET' | 'POST',
	check: ProbeCheck,
	deps: ProbeOneDeps
): Promise<ProbeClassification> {
	let res: ProbeResponseLike;
	try {
		res = await deps.fetchImpl(url, {
			method,
			redirect: 'manual', // a proxy 30x to a login/marketing page is NOT followed (N1).
			signal: AbortSignal.timeout(deps.timeoutMs), // a hang ⇒ AbortError ⇒ correctly-private (N2).
			headers: { accept: 'application/json' } // NO auth header — the probe holds no credential (N1).
		});
	} catch {
		return 'correctly-private';
	}
	const body = await readCappedJson(res, deps.maxBytes ?? MAX_PROBE_BODY_BYTES);
	return classifyProbeResponse(check, res.status, body);
}

/**
 * Probe ONE base origin: GET /healthz (primary). If it does not fingerprint AND the confirm route
 * is enabled, POST /admission/link-token with NO secret header (only ever elicits a 401 — no auth
 * side-effect). Returns the fully-probed URL + the FIXED fingerprint literal on a positive, else
 * 'correctly-private'. Self-isolating — never throws (fetch throws map to correctly-private).
 */
export async function probeOne(base: string, deps: ProbeOneDeps): Promise<ProbeOutcome> {
	const healthzUrl = `${base}${HEALTHZ_PATH}`;
	const healthz = await fetchAndClassify(healthzUrl, 'GET', 'healthz', deps);
	if (healthz === 'reachable-admission-app') {
		return { url: healthzUrl, classification: 'reachable-admission-app', fingerprint: HEALTHZ_FINGERPRINT };
	}
	if (deps.confirmRoute) {
		const confirmUrl = `${base}${CONFIRM_PATH}`;
		const confirm = await fetchAndClassify(confirmUrl, 'POST', 'confirm', deps);
		if (confirm === 'reachable-admission-app') {
			return { url: confirmUrl, classification: 'reachable-admission-app', fingerprint: CONFIRM_FINGERPRINT };
		}
	}
	return { url: healthzUrl, classification: 'correctly-private', fingerprint: null };
}

export interface RunProbeDeps {
	fetchImpl: ProbeFetch;
	timeoutMs: number;
	confirmRoute: boolean;
	/** Injected clock (a `() => Date`) so checkedAt is deterministic in tests. */
	now: () => Date;
	log: (message: string) => void;
	maxBytes?: number;
}

/**
 * Orchestrate the probe over the configured URL list. Validates each entry (N1), probes the valid
 * ones sequentially (N2: total wall-time ≤ valid-url-count × timeout — bounded), and collects the
 * tripped targets. NEVER throws — each URL runs under its own try/catch; an unexpected error is
 * logged (scrubbed) and treated as private. ANY tripped target ⇒ positive.
 */
export async function runReachabilityProbe(rawUrls: readonly string[], deps: RunProbeDeps): Promise<ProbeReport> {
	const checkedAt = deps.now().toISOString();
	const tripped: { url: string; fingerprint: string }[] = [];
	let targetCount = 0;

	for (const raw of rawUrls) {
		const parsed = parseProbeTarget(raw);
		if (!parsed.ok) {
			// reason is a category label ONLY — never echo the raw entry (it may carry userinfo).
			deps.log(`CA-2 probe: skipping invalid target (${parsed.reason})`);
			continue;
		}
		targetCount += 1;
		try {
			const outcome = await probeOne(parsed.base, {
				fetchImpl: deps.fetchImpl,
				timeoutMs: deps.timeoutMs,
				confirmRoute: deps.confirmRoute,
				maxBytes: deps.maxBytes ?? MAX_PROBE_BODY_BYTES
			});
			if (outcome.classification === 'reachable-admission-app' && outcome.fingerprint !== null) {
				tripped.push({ url: outcome.url, fingerprint: outcome.fingerprint });
			}
		} catch (err) {
			// Defense-in-depth: probeOne is already self-isolating, but never let one URL throw out.
			deps.log(`CA-2 probe: target errored (treated as private, non-fatal): ${errMessage(err)}`);
		}
	}

	return { positive: tripped.length > 0, tripped, checkedAt, targetCount };
}

// ── Top-level step (what poll.ts invokes) ─────────────────────────────────────────────────

export interface AdmissionProbeDeps {
	fetchImpl?: ProbeFetch;
	now?: () => Date;
	/** Override the alert delivery (tests spy this). Defaults to postDiscord over global fetch. */
	postAlert?: (webhookUrl: string, payload: DiscordPayload) => Promise<void>;
}

/**
 * The isolated pre-loop step runPoll calls. Reads config.probe (+ config.discordWebhookUrl), runs
 * the probe, and on a POSITIVE detection emits a DURABLE structured log FIRST (the finding of
 * record) then a best-effort Discord alert on top. FAIL-SAFE end-to-end (C3): it NEVER throws, adds
 * NO new non-zero-exit path, and cannot delay the poll meaningfully (bounded per-URL timeout, N2).
 *
 * Presence of ADMISSION_PROBE_PUBLIC_URLS gates it: an empty/unset list ⇒ a single skip log line,
 * then return (fail-SAFE no-op, NOT fail-closed — this is hardening, not a boot gate).
 */
export async function runAdmissionReachabilityProbe(
	config: WorkerConfig,
	log: (message: string) => void,
	deps: AdmissionProbeDeps = {}
): Promise<void> {
	const urls = config.probe.publicUrls;
	if (urls.length === 0) {
		log('CA-2 probe: no ADMISSION_PROBE_PUBLIC_URLS configured — skipping');
		return;
	}

	const fetchImpl = deps.fetchImpl ?? (globalThis.fetch as unknown as ProbeFetch);
	const now = deps.now ?? ((): Date => new Date());

	const report = await runReachabilityProbe(urls, {
		fetchImpl,
		timeoutMs: config.probe.timeoutMs,
		confirmRoute: config.probe.confirmRoute,
		now,
		log
	});

	if (!report.positive) {
		log(`CA-2 probe: ${report.targetCount} target(s), all correctly private`);
		return;
	}

	// POSITIVE DETECTION. Durable structured log FIRST (Coolify-log-routable finding of record);
	// the Discord POST is best-effort delivery on top (§4). The log carries ONLY the tripped
	// public URL(s) (public by definition) — no secret, no body, no tenant data (C1).
	const trippedList = report.tripped.map((t) => t.url).join(', ');
	log(`CA-2 probe: POSITIVE DETECTION — admission endpoint PUBLICLY REACHABLE: ${trippedList}`);

	if (config.discordWebhookUrl === undefined) {
		log('CA-2 probe: DISCORD_WEBHOOK_URL unset — finding logged only (no Discord alert)');
		return;
	}

	const payload = buildCa2Alert(report, report.checkedAt);
	const postAlert =
		deps.postAlert ?? ((url: string, p: DiscordPayload): Promise<void> => postDiscord(url, p, { fetchImpl: undefined, log }));
	// postDiscord is itself fail-safe; guard anyway so nothing can escape this step.
	try {
		await postAlert(config.discordWebhookUrl, payload);
	} catch (err) {
		log(`CA-2 probe: alert delivery errored (non-fatal, finding already logged): ${errMessage(err)}`);
	}
}
