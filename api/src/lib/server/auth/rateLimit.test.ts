// rateLimit.test.ts — unit coverage for the in-memory sliding-window limiter (SELF-288).
// Pure-TS server test (node env). Proves: under-cap allows + records; at-cap limits WITHOUT
// recording (a limited caller cannot push the window forward); the window slides (old hits
// age out); scopes + keys are independent; emailKey is stable + non-raw.

import { describe, it, expect, beforeEach } from 'vitest';
import { consumeRateLimit, emailKey, __resetRateLimitForTests } from './rateLimit';

const RULE = { max: 3, windowMs: 1000 };

beforeEach(() => __resetRateLimitForTests());

describe('consumeRateLimit', () => {
	it('allows up to max, then limits within the window', () => {
		const t = 10_000;
		expect(consumeRateLimit('s', 'k', RULE, t).limited).toBe(false);
		expect(consumeRateLimit('s', 'k', RULE, t).limited).toBe(false);
		expect(consumeRateLimit('s', 'k', RULE, t).limited).toBe(false);
		const fourth = consumeRateLimit('s', 'k', RULE, t);
		expect(fourth.limited).toBe(true);
		expect(fourth.retryAfterMs).toBe(1000); // oldest hit + window - now
	});

	it('a limited call does NOT record — window cannot be pushed forward indefinitely', () => {
		const t = 10_000;
		for (let i = 0; i < 3; i++) consumeRateLimit('s', 'k', RULE, t);
		// Hammer while limited at t..t+900 (all within window). None should record.
		for (let dt = 0; dt <= 900; dt += 100) {
			expect(consumeRateLimit('s', 'k', RULE, t + dt).limited).toBe(true);
		}
		// At t+1001 the 3 original hits (all at t) have aged out → allowed again.
		expect(consumeRateLimit('s', 'k', RULE, t + 1001).limited).toBe(false);
	});

	it('window slides: an old hit ages out and frees a slot', () => {
		const t = 10_000;
		consumeRateLimit('s', 'k', RULE, t); // hit @ t
		consumeRateLimit('s', 'k', RULE, t + 400); // hit @ t+400
		consumeRateLimit('s', 'k', RULE, t + 800); // hit @ t+800 → now at cap
		expect(consumeRateLimit('s', 'k', RULE, t + 900).limited).toBe(true);
		// At t+1001 the first hit (@t) has expired (>1000ms) → one slot free.
		expect(consumeRateLimit('s', 'k', RULE, t + 1001).limited).toBe(false);
	});

	it('different scopes and different keys are independent', () => {
		const t = 10_000;
		for (let i = 0; i < 3; i++) consumeRateLimit('ip', 'a', RULE, t);
		expect(consumeRateLimit('ip', 'a', RULE, t).limited).toBe(true);
		expect(consumeRateLimit('ip', 'b', RULE, t).limited).toBe(false); // other key
		expect(consumeRateLimit('email', 'a', RULE, t).limited).toBe(false); // other scope
	});
});

describe('emailKey', () => {
	it('is stable for the same normalized email and never the raw address', () => {
		const k = emailKey('user@example.com');
		expect(k).toBe(emailKey('user@example.com'));
		expect(k).not.toContain('user@example.com');
		expect(k).toMatch(/^[0-9a-f]{64}$/); // sha-256 hex
		expect(emailKey('other@example.com')).not.toBe(k);
	});
});
