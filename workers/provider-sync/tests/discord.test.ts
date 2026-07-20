// discord.test.ts — SELF-279 CA-2 worker→Discord egress QA battery.
//
// Two MERGE-GATE tests clearing Sec AMBER conditions:
//   #6 [C1 scrub]  buildCa2Alert emits ONLY allow-listed non-sensitive values (probed URL +
//                  FIXED fingerprint literal + timestamp) — NEVER a token / shared-secret /
//                  PFIN_DB_* / access_token / public_token / uuid ownerUserId / raw response body.
//   #5 [C3]        postDiscord is FAIL-SAFE — a rejecting/500/timeout webhook NEVER throws;
//                  it logs-and-continues (the finding is already durably logged upstream).
//
// NETWORK-FREE: postDiscord's fetch is injected. buildCa2Alert is pure (no clock, no I/O).

import { describe, it, expect, vi } from 'vitest';
import {
	buildCa2Alert,
	postDiscord,
	type Ca2AlertInput,
	type DiscordPayload,
	type DiscordFetch,
	type DiscordResponseLike
} from '../src/notify/discord.js';
import { HEALTHZ_FINGERPRINT } from '../src/http/reachabilityProbe.js';

const NOW_ISO = '2026-07-19T00:00:00.000Z';
const PROBED_URL = 'https://provider-sync-ab12cd.example.com/healthz';

// ═══════════════════════════════════════════════════════════════════════════════════
// #6 [MERGE-GATE C1] — scrub assertion
// ═══════════════════════════════════════════════════════════════════════════════════
describe('#6 [C1 MERGE-GATE] buildCa2Alert scrub — allow-listed values ONLY, no secret/PII/body leak', () => {
	it('a clean input serializes the probed URL + the FIXED fingerprint literal + the timestamp', () => {
		const payload = buildCa2Alert({ tripped: [{ url: PROBED_URL, fingerprint: HEALTHZ_FINGERPRINT }] }, NOW_ISO);
		const json = JSON.stringify(payload);
		expect(json).toContain(PROBED_URL);
		expect(json).toContain(HEALTHZ_FINGERPRINT); // our OWN constant, not a response-derived value
		expect(json).toContain(NOW_ISO);
	});

	it('a POISONED input (extra rogue fields on the tripped entry) leaks NONE of them — the allow-list is real', () => {
		// The builder must read ONLY t.url + t.fingerprint. We attach secret-shaped rogue props to
		// PROVE they cannot reach the payload — this is the load-bearing scrub guarantee, not a
		// clean-in/clean-out tautology.
		const poisoned = {
			tripped: [
				{
					url: PROBED_URL,
					fingerprint: HEALTHZ_FINGERPRINT,
					// rogue fields the builder MUST ignore:
					rawBody: '{"status":"ok"}',
					access_token: 'access-sandbox-DEADBEEFCAFE',
					public_token: 'public-sandbox-0123456789',
					sharedSecret: 'WORKER_ADMISSION_SHARED_SECRET-supersecretvalue',
					dbPassword: 'PFIN_DB_PASSWORD=hunter2',
					ownerUserId: '11111111-1111-1111-1111-111111111111'
				}
			]
		} as unknown as Ca2AlertInput;

		const json = JSON.stringify(buildCa2Alert(poisoned, NOW_ISO));

		const forbidden = [
			'access-sandbox-DEADBEEFCAFE', // token substring
			'access_token',
			'public-sandbox-0123456789',
			'public_token',
			'WORKER_ADMISSION_SHARED_SECRET',
			'PFIN_DB_',
			'hunter2',
			'11111111-1111-1111-1111-111111111111', // uuid ownerUserId
			'rawBody',
			'"status":"ok"' // the raw response body must never be echoed
		];
		for (const needle of forbidden) expect(json, `must not leak ${needle}`).not.toContain(needle);

		// Allow-listed values that ARE expected:
		expect(json).toContain(PROBED_URL);
		expect(json).toContain(HEALTHZ_FINGERPRINT);
		expect(json).toContain(NOW_ISO);
	});

	it('the payload SHAPE is allow-listed keys only (content/embeds → title/description/fields → 3 fixed field names)', () => {
		const payload = buildCa2Alert({ tripped: [{ url: PROBED_URL, fingerprint: HEALTHZ_FINGERPRINT }] }, NOW_ISO);
		expect(Object.keys(payload).sort()).toEqual(['content', 'embeds']);
		expect(payload.embeds).toHaveLength(1);
		expect(Object.keys(payload.embeds[0]!).sort()).toEqual(['description', 'fields', 'title']);
		expect(payload.embeds[0]!.fields.map((f) => f.name)).toEqual(['probed_url', 'fingerprint', 'detected_at_utc']);
		// each field has exactly {name, value} — no smuggled extra property.
		for (const f of payload.embeds[0]!.fields) expect(Object.keys(f).sort()).toEqual(['name', 'value']);
	});
});

// ═══════════════════════════════════════════════════════════════════════════════════
// #5 [MERGE-GATE C3] — webhook failure is non-fatal
// ═══════════════════════════════════════════════════════════════════════════════════
describe('#5 [C3 MERGE-GATE] postDiscord fail-safe — a broken webhook NEVER throws', () => {
	const PAYLOAD: DiscordPayload = buildCa2Alert({ tripped: [{ url: PROBED_URL, fingerprint: HEALTHZ_FINGERPRINT }] }, NOW_ISO);
	const WEBHOOK = 'https://discord.example.test/api/webhooks/abc/xyz';

	it('a REJECTING fetch (Discord down / DNS / timeout) ⇒ resolves (no throw) + logs-and-continues', async () => {
		const fetchImpl: DiscordFetch = async () => {
			throw new Error('ECONNRESET');
		};
		const log = vi.fn();
		await expect(postDiscord(WEBHOOK, PAYLOAD, { fetchImpl, log })).resolves.toBeUndefined();
		expect(log).toHaveBeenCalledWith(expect.stringContaining('Discord webhook post failed (non-fatal'));
		// the coarse log line never echoes the payload/URL body.
		for (const call of log.mock.calls) expect(String(call[0])).not.toContain(PROBED_URL);
	});

	it('a non-OK (HTTP 500) response ⇒ resolves (no throw) + logs the status, non-fatal', async () => {
		const fetchImpl: DiscordFetch = async (): Promise<DiscordResponseLike> => ({ ok: false, status: 500 });
		const log = vi.fn();
		await expect(postDiscord(WEBHOOK, PAYLOAD, { fetchImpl, log })).resolves.toBeUndefined();
		expect(log).toHaveBeenCalledWith(expect.stringContaining('HTTP 500'));
	});

	it('a healthy (204) response ⇒ resolves quietly, POSTs the serialized payload, no error log', async () => {
		let sentBody = '';
		const fetchImpl: DiscordFetch = async (_url, init): Promise<DiscordResponseLike> => {
			sentBody = init?.body ?? '';
			expect(init?.method).toBe('POST');
			expect(init?.headers?.['content-type']).toBe('application/json');
			return { ok: true, status: 204 };
		};
		const log = vi.fn();
		await expect(postDiscord(WEBHOOK, PAYLOAD, { fetchImpl, log })).resolves.toBeUndefined();
		expect(JSON.parse(sentBody)).toEqual(PAYLOAD);
		expect(log).not.toHaveBeenCalled(); // success path is silent
	});
});
