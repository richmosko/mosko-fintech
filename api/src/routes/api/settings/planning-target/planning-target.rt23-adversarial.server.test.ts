// planning-target.rt23-adversarial.server.test.ts — SELF-233 RT-23 adversarial battery for
// POST /api/settings/planning-target. V1-SHIP-BLOCK · Sec joint-review-mandatory (AC7).
//
// RT-23 (docs/SECURITY/index.html, read live before drafting — not from memory or from the
// Linear issue text) covers BOTH Lock 14 mods for this ONE write path in ONE RT entry:
//   - mod #1 (app-layer mass-assignment fence): Zod `.strict()`; unknown-field injection
//     rejected; `users_id` NEVER read from the request body.
//   - mod #2 (numeric-input adversarial battery): NaN/Inf rejection, currency-string reject,
//     overflow guard, scientific-notation reject, locale-formatted reject.
// ⚠ RT-24 is a DIFFERENT, not-yet-built surface (pfin.tax_bracket_schedule / _row, §2.5.2,
// V1.4) — NOT this endpoint. The SELF-233 Linear issue's AC5 mislabels its numeric-battery
// test "RT-24"; this file is intentionally named/labeled RT-23 for BOTH halves, matching the
// canonical SECURITY doc row, and that mislabel is flagged back in the PR/report rather than
// silently propagated. Every case below would go RED if the corresponding fence were removed
// (e.g. drop `.strict()` → the mass-assignment cases would reach the upsert; drop
// sanitizePercent → the numeric cases would reach the upsert with a garbage value).

import { describe, it, expect } from 'vitest';
import { POST } from './+server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

function makeEvent(body: unknown, captured: { calls: number }) {
	const request = new Request('http://localhost/api/settings/planning-target', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const upsert = () => {
		captured.calls++;
		return Promise.resolve({ error: null });
	};
	const locals = {
		safeGetSession: async () => ({ session: {}, user: { id: SESSION_UID } }),
		supabase: { schema: () => ({ from: () => ({ upsert }) }) }
	};
	return { request, locals } as unknown as Parameters<typeof POST>[0];
}

describe('RT-23 mass-assignment battery (Lock 14 mod #1)', () => {
	it("the issue's own example — extra users_id, attempting cross-tenant impersonation — rejected before the DB layer", async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ users_id: 999, target_percent: 50 }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('an otherwise-valid body PLUS a stray users_id is still rejected — isolates .strict() as the fence, not a missing-field coincidence', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ sub_cat_id: 7, target_percent: 50, users_id: 999 }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('any unsanctioned extra field is rejected, not just users_id', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ sub_cat_id: 7, target_percent: 50, is_admin: true }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('missing required field (sub_cat_id) is rejected', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ target_percent: 50 }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('non-positive / non-integer sub_cat_id (shape check) is rejected', async () => {
		const captured = { calls: 0 };
		expect((await POST(makeEvent({ sub_cat_id: -1, target_percent: 50 }, captured))).status).toBe(400);
		expect((await POST(makeEvent({ sub_cat_id: 0, target_percent: 50 }, captured))).status).toBe(400);
		expect((await POST(makeEvent({ sub_cat_id: 1.5, target_percent: 50 }, captured))).status).toBe(400);
		expect(captured.calls).toBe(0);
	});
});

describe('RT-23 numeric-input adversarial battery (Lock 14 mod #2, target_percent)', () => {
	it('rejects NaN', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ sub_cat_id: 7, target_percent: NaN }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('rejects Infinity / -Infinity', async () => {
		const captured = { calls: 0 };
		expect((await POST(makeEvent({ sub_cat_id: 7, target_percent: Infinity }, captured))).status).toBe(400);
		expect((await POST(makeEvent({ sub_cat_id: 7, target_percent: -Infinity }, captured))).status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('rejects currency-string input', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ sub_cat_id: 7, target_percent: '$50' }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('rejects regex-overflow (length-bounded) input', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ sub_cat_id: 7, target_percent: '9'.repeat(1000) }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('rejects scientific notation', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ sub_cat_id: 7, target_percent: '5e1' }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('rejects locale-formatted input (non-en-US)', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ sub_cat_id: 7, target_percent: '1.500,00' }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('rejects an in-shape value outside the 074 [0,100] range — the field-specific boundary beyond the shared six categories', async () => {
		const captured = { calls: 0 };
		expect((await POST(makeEvent({ sub_cat_id: 7, target_percent: -1 }, captured))).status).toBe(400);
		expect((await POST(makeEvent({ sub_cat_id: 7, target_percent: 500 }, captured))).status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('a clean in-range value is accepted (positive control — the battery rejects bad input, not all input)', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ sub_cat_id: 7, target_percent: '33.33' }, captured));
		expect(res.status).toBe(200);
		expect(captured.calls).toBe(1);
	});
});
