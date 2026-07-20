// reachabilityProbe.test.ts — SELF-279 CA-2 recurring reachability probe QA battery.
//
// SCOPE: the probe module (src/http/reachabilityProbe.ts) — the PURE decision core
// (parseProbeTarget / classifyProbeResponse) + the injectable-fetch effectful seam
// (probeOne / runReachabilityProbe / runAdmissionReachabilityProbe). ALL tests are
// NETWORK-FREE: every effectful path is driven through an injected `fetchImpl` /
// `postAlert` stub — no real socket, no real Discord, no DB (the probe touches none).
//
// Maps design §9 / team-lead brief tests: #1 positive-detection · #2 correctly-private ·
// #3 F1 subset-match robustness (additive-safe + no-false-positive) · #4 confirm-route ·
// #8 N1 URL hygiene (+ no credential echo in the reject reason) · #9 enable/disable (RF-2)
// + the DISCORD_WEBHOOK_URL-unset positive path (design §9 spec #9). The C1 scrub (#6) and
// the C3 webhook-non-fatal (#5) live in discord.test.ts; the C3 exit-code guard (#7) in
// poll.test.ts.

import { describe, it, expect, vi } from 'vitest';
import {
	parseProbeTarget,
	classifyProbeResponse,
	probeOne,
	runReachabilityProbe,
	runAdmissionReachabilityProbe,
	HEALTHZ_PATH,
	CONFIRM_PATH,
	HEALTHZ_FINGERPRINT,
	CONFIRM_FINGERPRINT,
	MAX_PROBE_BODY_BYTES,
	type ProbeFetch,
	type ProbeResponseLike,
	type DiscordPayload
} from '../src/http/reachabilityProbe.js';
import type { WorkerConfig } from '../src/config/env.js';

// ── Deterministic fixtures (no clock, no network) ──────────────────────────────────
const NOW = (): Date => new Date('2026-07-19T00:00:00.000Z');
const NOW_ISO = '2026-07-19T00:00:00.000Z';

/** A ProbeResponseLike whose body is served via text() (no ReadableStream ⇒ the text()
 *  path in readCappedJson). `rawText` overrides the JSON serialization (non-JSON / oversize). */
function resp(status: number, body?: unknown, rawText?: string): ProbeResponseLike {
	const text = rawText ?? (body === undefined ? '' : JSON.stringify(body));
	return { status, text: async () => text };
}

/** A fetch stub that routes by URL substring; unmatched URLs throw (⇒ unreachable/private). */
function routeFetch(routes: Array<[needle: string, make: () => Promise<ProbeResponseLike>]>): ProbeFetch {
	return async (url: string): Promise<ProbeResponseLike> => {
		for (const [needle, make] of routes) if (url.includes(needle)) return make();
		throw new Error(`ECONNREFUSED ${url}`);
	};
}

const HOST = 'https://provider-sync-ab12cd.example.com';

function cfg(over: Partial<WorkerConfig> = {}): WorkerConfig {
	return {
		db: { host: 'h', port: 5432, database: 'd', user: 'u', password: 'p' },
		plaid: { clientId: 'c', secret: 's', env: 'sandbox' },
		simplefinToken: undefined,
		discordWebhookUrl: 'https://discord.example.test/api/webhooks/abc/xyz',
		probe: { publicUrls: [], confirmRoute: false, timeoutMs: 5000 },
		...over
	} as WorkerConfig;
}

// ═══════════════════════════════════════════════════════════════════════════════════
// #1 — POSITIVE DETECTION
// ═══════════════════════════════════════════════════════════════════════════════════
describe('#1 positive detection — healthz 200 {status:ok} fingerprints as our admission app', () => {
	it('classifyProbeResponse (pure): healthz 200 {status:ok} ⇒ reachable-admission-app', () => {
		expect(classifyProbeResponse('healthz', 200, { status: 'ok' })).toBe('reachable-admission-app');
	});

	it('probeOne: a 200 {status:ok} healthz ⇒ reachable, url is base+/healthz, fingerprint is the FIXED literal', async () => {
		const fetchImpl = routeFetch([[HEALTHZ_PATH, () => Promise.resolve(resp(200, { status: 'ok' }))]]);
		const outcome = await probeOne(HOST, { fetchImpl, timeoutMs: 5000, confirmRoute: false });
		expect(outcome.classification).toBe('reachable-admission-app');
		expect(outcome.url).toBe(`${HOST}${HEALTHZ_PATH}`);
		expect(outcome.fingerprint).toBe(HEALTHZ_FINGERPRINT); // NEVER the raw body
	});

	it('runReachabilityProbe: any tripped target ⇒ report.positive true + tripped names the URL', async () => {
		const fetchImpl = routeFetch([[HEALTHZ_PATH, () => Promise.resolve(resp(200, { status: 'ok' }))]]);
		const report = await runReachabilityProbe([HOST], {
			fetchImpl,
			timeoutMs: 5000,
			confirmRoute: false,
			now: NOW,
			log: vi.fn()
		});
		expect(report.positive).toBe(true);
		expect(report.targetCount).toBe(1);
		expect(report.checkedAt).toBe(NOW_ISO);
		expect(report.tripped).toEqual([{ url: `${HOST}${HEALTHZ_PATH}`, fingerprint: HEALTHZ_FINGERPRINT }]);
	});

	it('runAdmissionReachabilityProbe: a positive detection BUILDS + DELIVERS the alert (postAlert spy) naming the URL', async () => {
		const fetchImpl = routeFetch([[HEALTHZ_PATH, () => Promise.resolve(resp(200, { status: 'ok' }))]]);
		const postAlert = vi.fn<(url: string, p: DiscordPayload) => Promise<void>>().mockResolvedValue(undefined);
		const log = vi.fn();
		await runAdmissionReachabilityProbe(cfg({ probe: { publicUrls: [HOST], confirmRoute: false, timeoutMs: 5000 } }), log, {
			fetchImpl,
			now: NOW,
			postAlert
		});
		expect(postAlert).toHaveBeenCalledTimes(1);
		const [webhookUrl, payload] = postAlert.mock.calls[0]!;
		expect(webhookUrl).toContain('discord.example.test');
		const probedField = payload.embeds[0]!.fields.find((f) => f.name === 'probed_url')!;
		expect(probedField.value).toContain(`${HOST}${HEALTHZ_PATH}`);
		// Durable structured log emitted FIRST (finding of record).
		expect(log).toHaveBeenCalledWith(expect.stringContaining('POSITIVE DETECTION'));
	});

	it('positive detection with DISCORD_WEBHOOK_URL UNSET ⇒ finding LOGGED, no alert delivered, no throw (§9 spec #9)', async () => {
		const fetchImpl = routeFetch([[HEALTHZ_PATH, () => Promise.resolve(resp(200, { status: 'ok' }))]]);
		const postAlert = vi.fn<(url: string, p: DiscordPayload) => Promise<void>>();
		const log = vi.fn();
		await expect(
			runAdmissionReachabilityProbe(
				cfg({ discordWebhookUrl: undefined, probe: { publicUrls: [HOST], confirmRoute: false, timeoutMs: 5000 } }),
				log,
				{ fetchImpl, now: NOW, postAlert }
			)
		).resolves.toBeUndefined();
		expect(postAlert).not.toHaveBeenCalled(); // webhook unset ⇒ no delivery attempt
		expect(log).toHaveBeenCalledWith(expect.stringContaining('POSITIVE DETECTION'));
		expect(log).toHaveBeenCalledWith(expect.stringContaining('DISCORD_WEBHOOK_URL unset'));
	});
});

// ═══════════════════════════════════════════════════════════════════════════════════
// #2 — CORRECTLY-PRIVATE (refused / timeout / non-2xx) ⇒ NO alert
// ═══════════════════════════════════════════════════════════════════════════════════
describe('#2 correctly-private — unreachable / non-fingerprint ⇒ no positive, no alert', () => {
	it('classifyProbeResponse (pure): a non-2xx healthz ⇒ correctly-private', () => {
		expect(classifyProbeResponse('healthz', 404, { status: 'ok' })).toBe('correctly-private');
		expect(classifyProbeResponse('healthz', 503, { status: 'ok' })).toBe('correctly-private');
	});

	it('probeOne: a fetch that REJECTS (ECONNREFUSED/DNS/TLS/AbortError) ⇒ correctly-private, fingerprint null', async () => {
		for (const err of [new Error('ECONNREFUSED'), new Error('ENOTFOUND'), Object.assign(new Error('The operation was aborted'), { name: 'AbortError' })]) {
			const fetchImpl: ProbeFetch = async () => {
				throw err;
			};
			const outcome = await probeOne(HOST, { fetchImpl, timeoutMs: 5000, confirmRoute: false });
			expect(outcome.classification).toBe('correctly-private');
			expect(outcome.fingerprint).toBeNull();
		}
	});

	it('runAdmissionReachabilityProbe: all-private ⇒ postAlert NOT called + "all correctly private" logged', async () => {
		const fetchImpl: ProbeFetch = async () => {
			throw new Error('ECONNREFUSED');
		};
		const postAlert = vi.fn<(url: string, p: DiscordPayload) => Promise<void>>();
		const log = vi.fn();
		await runAdmissionReachabilityProbe(cfg({ probe: { publicUrls: [HOST], confirmRoute: false, timeoutMs: 5000 } }), log, {
			fetchImpl,
			now: NOW,
			postAlert
		});
		expect(postAlert).not.toHaveBeenCalled();
		expect(log).toHaveBeenCalledWith(expect.stringContaining('all correctly private'));
	});
});

// ═══════════════════════════════════════════════════════════════════════════════════
// #3 — F1 subset-match robustness: additive-safe (no false-NEGATIVE) + proxy-page guard (no false-POSITIVE)
// ═══════════════════════════════════════════════════════════════════════════════════
describe('#3 F1 subset-match robustness', () => {
	it('ADDITIVE /healthz field still fingerprints (no false-negative — the whole point of F1)', () => {
		expect(classifyProbeResponse('healthz', 200, { status: 'ok', version: '1.2', build: 42 })).toBe('reachable-admission-app');
	});

	it('a generic proxy 200 page does NOT trip (no false-positive): non-JSON / {} / array / oversize ⇒ correctly-private', async () => {
		const cases: Array<{ label: string; make: () => ProbeResponseLike }> = [
			{ label: 'non-JSON HTML', make: () => resp(200, undefined, '<!doctype html><title>Parking</title>') },
			{ label: 'empty object', make: () => resp(200, {}) },
			{ label: 'JSON array', make: () => resp(200, [{ status: 'ok' }]) },
			{ label: 'unrelated JSON', make: () => resp(200, { foo: 1 }) },
			// oversize: a body that WOULD fingerprint but exceeds the 8 KB cap ⇒ read yields undefined ⇒ private.
			{ label: 'oversize-but-fingerprinting', make: () => resp(200, undefined, JSON.stringify({ status: 'ok', pad: 'x'.repeat(MAX_PROBE_BODY_BYTES + 100) })) }
		];
		for (const c of cases) {
			const fetchImpl = routeFetch([[HEALTHZ_PATH, () => Promise.resolve(c.make())]]);
			const outcome = await probeOne(HOST, { fetchImpl, timeoutMs: 5000, confirmRoute: false });
			expect(outcome.classification, c.label).toBe('correctly-private');
		}
	});
});

// ═══════════════════════════════════════════════════════════════════════════════════
// #4 — Confirm-route (guarded; off by default, but the classifier must be correct if enabled)
// ═══════════════════════════════════════════════════════════════════════════════════
describe('#4 confirm-route 401 envelope', () => {
	it('classifyProbeResponse (pure): confirm 401 {error:unauthorized} ⇒ reachable; other 401 bodies / 200 ⇒ private', () => {
		expect(classifyProbeResponse('confirm', 401, { error: 'unauthorized' })).toBe('reachable-admission-app');
		expect(classifyProbeResponse('confirm', 401, { error: 'nope' })).toBe('correctly-private');
		expect(classifyProbeResponse('confirm', 401, 'unauthorized')).toBe('correctly-private'); // non-JSON
		expect(classifyProbeResponse('confirm', 200, { error: 'unauthorized' })).toBe('correctly-private'); // wrong status
	});

	it('probeOne with confirmRoute=true: healthz non-fingerprint + confirm 401 envelope ⇒ reachable via CONFIRM_PATH', async () => {
		const fetchImpl = routeFetch([
			[HEALTHZ_PATH, () => Promise.resolve(resp(404, undefined, 'not found'))],
			[CONFIRM_PATH, () => Promise.resolve(resp(401, { error: 'unauthorized' }))]
		]);
		const outcome = await probeOne(HOST, { fetchImpl, timeoutMs: 5000, confirmRoute: true });
		expect(outcome.classification).toBe('reachable-admission-app');
		expect(outcome.url).toBe(`${HOST}${CONFIRM_PATH}`);
		expect(outcome.fingerprint).toBe(CONFIRM_FINGERPRINT);
	});

	it('confirmRoute=false: the confirm route is NEVER probed even when healthz misses (default posture)', async () => {
		const confirmCalled = vi.fn();
		const fetchImpl = routeFetch([
			[HEALTHZ_PATH, () => Promise.resolve(resp(404, undefined, 'nf'))],
			[
				CONFIRM_PATH,
				() => {
					confirmCalled();
					return Promise.resolve(resp(401, { error: 'unauthorized' }));
				}
			]
		]);
		const outcome = await probeOne(HOST, { fetchImpl, timeoutMs: 5000, confirmRoute: false });
		expect(confirmCalled).not.toHaveBeenCalled();
		expect(outcome.classification).toBe('correctly-private');
	});
});

// ═══════════════════════════════════════════════════════════════════════════════════
// #8 — N1 URL hygiene: parseProbeTarget accepts bare https FQDN, rejects the rest; reason leaks nothing
// ═══════════════════════════════════════════════════════════════════════════════════
describe('#8 N1 URL hygiene — parseProbeTarget', () => {
	it('accepts a bare https FQDN and returns the normalized origin (no trailing slash)', () => {
		expect(parseProbeTarget('https://provider-sync-ab12cd.example.com')).toEqual({ ok: true, base: HOST });
		expect(parseProbeTarget('  https://apex.example.com/  ')).toEqual({ ok: true, base: 'https://apex.example.com' });
	});

	it('rejects non-https, embedded userinfo, query-string, fragment, and path-beyond-/ with a CATEGORY reason', () => {
		const table: Array<[string, string]> = [
			['http://provider-sync.example.com', 'not-https'],
			['https://user:hunter2@provider-sync.example.com', 'embedded-userinfo'],
			['https://provider-sync.example.com/?token=abc', 'has-query-string'],
			['https://provider-sync.example.com/#frag', 'has-fragment'],
			['https://provider-sync.example.com/admin/secrets', 'has-path'],
			['not a url at all', 'unparseable-url']
		];
		for (const [raw, reason] of table) {
			expect(parseProbeTarget(raw)).toEqual({ ok: false, reason });
		}
	});

	it('the reject reason is a category label ONLY — it NEVER echoes the raw bad entry (no credential leak)', () => {
		const r = parseProbeTarget('https://user:hunter2@provider-sync.example.com/?token=SECRETTOKEN#frag');
		expect(r.ok).toBe(false);
		if (!r.ok) {
			expect(r.reason).not.toContain('hunter2'); // password never echoed
			expect(r.reason).not.toContain('SECRETTOKEN'); // query never echoed
			expect(r.reason).not.toContain('provider-sync'); // not even the host
			expect(r.reason).toBe('embedded-userinfo'); // first-failing category
		}
	});

	it('runReachabilityProbe SKIPS invalid targets (logs a category, does not probe them) and probes the valid ones', async () => {
		const fetchImpl = routeFetch([[HEALTHZ_PATH, () => Promise.resolve(resp(200, { status: 'ok' }))]]);
		const log = vi.fn();
		const report = await runReachabilityProbe(
			['http://insecure.example.com', 'https://user:pw@evil.example.com', HOST],
			{ fetchImpl, timeoutMs: 5000, confirmRoute: false, now: NOW, log }
		);
		expect(report.targetCount).toBe(1); // only the one VALID target was probed/counted
		expect(report.positive).toBe(true);
		expect(log).toHaveBeenCalledWith(expect.stringContaining('skipping invalid target (not-https)'));
		expect(log).toHaveBeenCalledWith(expect.stringContaining('skipping invalid target (embedded-userinfo)'));
		// the skip logs never echo the raw bad entry.
		for (const call of log.mock.calls) expect(String(call[0])).not.toContain('pw@evil');
	});
});

// ═══════════════════════════════════════════════════════════════════════════════════
// #9 — Enable/disable (RF-2): presence of ADMISSION_PROBE_PUBLIC_URLS is the switch
// ═══════════════════════════════════════════════════════════════════════════════════
describe('#9 enable/disable (RF-2) — presence of ADMISSION_PROBE_PUBLIC_URLS gates the probe', () => {
	it('EMPTY list ⇒ a logged no-op: NO fetch, NO alert', async () => {
		const fetchImpl = vi.fn<ProbeFetch>();
		const postAlert = vi.fn<(url: string, p: DiscordPayload) => Promise<void>>();
		const log = vi.fn();
		await runAdmissionReachabilityProbe(cfg({ probe: { publicUrls: [], confirmRoute: false, timeoutMs: 5000 } }), log, {
			fetchImpl,
			now: NOW,
			postAlert
		});
		expect(fetchImpl).not.toHaveBeenCalled();
		expect(postAlert).not.toHaveBeenCalled();
		expect(log).toHaveBeenCalledWith(expect.stringContaining('no ADMISSION_PROBE_PUBLIC_URLS configured — skipping'));
	});

	it('≥1 entry ⇒ ENABLED: the injected fetch IS invoked', async () => {
		const fetchImpl = vi.fn<ProbeFetch>().mockResolvedValue(resp(404, undefined, 'nf'));
		const postAlert = vi.fn<(url: string, p: DiscordPayload) => Promise<void>>();
		const log = vi.fn();
		await runAdmissionReachabilityProbe(cfg({ probe: { publicUrls: [HOST], confirmRoute: false, timeoutMs: 5000 } }), log, {
			fetchImpl,
			now: NOW,
			postAlert
		});
		expect(fetchImpl).toHaveBeenCalledTimes(1);
		expect(fetchImpl.mock.calls[0]![0]).toBe(`${HOST}${HEALTHZ_PATH}`);
		expect(postAlert).not.toHaveBeenCalled(); // 404 ⇒ private ⇒ no alert
	});
});
