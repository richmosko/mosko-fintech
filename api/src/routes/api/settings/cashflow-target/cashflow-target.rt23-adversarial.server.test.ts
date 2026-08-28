// cashflow-target.rt23-adversarial.server.test.ts — SELF-252 AC4 numeric adversarial battery +
// AC3 mass-assignment fence for POST /api/settings/cashflow-target.
//
// This is the RT-23-SHAPED app-layer half Sec's own note on `074` records as owed and NOT
// inherited ("RT-23 IS NOT SATISFIED BY `074`") — `074` covers pfin.planning_target only; this
// table (090 / pfin.cashflow_target) gets its own instance of the same battery, run against
// BOTH numeric fields (planning-target's RT-23 file only had one field to cover). Every case
// below would go RED if the corresponding fence were removed (drop `.strict()` → the
// mass-assignment cases reach the upsert; drop sanitizeCurrencyAmount / the non-negative refine
// → the numeric cases reach the upsert with a garbage or negative value).

import { describe, it, expect } from 'vitest';
import { POST } from './+server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

function makeEvent(body: unknown, captured: { calls: number }) {
	const request = new Request('http://localhost/api/settings/cashflow-target', {
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

describe('AC3 mass-assignment battery (Lock 14 mod #1)', () => {
	it('extra users_id — attempting cross-tenant impersonation — rejected before the DB layer', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ income_annual: 120000, users_id: 999 }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('any unsanctioned extra field is rejected, not just users_id', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ income_annual: 120000, is_admin: true }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('a stray field alongside an otherwise-valid full body is still rejected — isolates .strict() as the fence', async () => {
		const captured = { calls: 0 };
		const res = await POST(
			makeEvent({ income_annual: 120000, expense_monthly: 4000, sub_cat_id: 7 }, captured)
		);
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});
});

describe('AC4 numeric-input adversarial battery — income_annual', () => {
	// NOTE: a literal JS NaN/Infinity can never reach the wire as such — JSON.stringify
	// collapses both to `null` (JSON has no NaN/Infinity literal), and for THIS schema
	// (nullable, unlike planning-target's required percentValue()) an actual `null` on the
	// wire is a VALID explicit-clear, not a rejection. The real adversarial shape is the
	// STRING form (a client-side coercion bug, a hand-crafted request, "NaN"/"Infinity" typed
	// into a field that then gets sent as text) — string literals below are what the battery's
	// Infinity/NaN backstop and character-class fence actually see.
	it('rejects the string "NaN"', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ income_annual: 'NaN' }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('rejects the string "Infinity" / "-Infinity"', async () => {
		const captured = { calls: 0 };
		expect((await POST(makeEvent({ income_annual: 'Infinity' }, captured))).status).toBe(400);
		expect((await POST(makeEvent({ income_annual: '-Infinity' }, captured))).status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('an explicit JSON null is accepted — it is the clear-the-field state, not a NaN proxy (this schema is nullable, unlike planning-target\'s)', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ income_annual: null }, captured));
		expect(res.status).toBe(200);
		expect(captured.calls).toBe(1);
	});

	it('rejects currency-string input', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ income_annual: '$120,000' }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('rejects regex-overflow (length-bounded) input', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ income_annual: '9'.repeat(1000) }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('rejects scientific notation', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ income_annual: '1.2e5' }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('rejects locale-formatted input (non-en-US)', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ income_annual: '120.000,00' }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('rejects a negative value — the shared battery has no sign stance here, so this endpoint refuses it explicitly (a negative target has no product meaning; mirrors 090\'s own DB CHECK)', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ income_annual: -1 }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('a clean non-negative value is accepted (positive control — the battery rejects bad input, not all input)', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ income_annual: '120000.00' }, captured));
		expect(res.status).toBe(200);
		expect(captured.calls).toBe(1);
	});

	it('zero is accepted — a stored 0 is a valid target ("intend to earn/spend nothing"), never rejected as falsy', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ income_annual: 0 }, captured));
		expect(res.status).toBe(200);
		expect(captured.calls).toBe(1);
	});
});

describe('AC4 numeric-input adversarial battery — expense_monthly (same battery, mirrored per field)', () => {
	it('rejects the string "NaN"', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ expense_monthly: 'NaN' }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('rejects the string "Infinity" / "-Infinity"', async () => {
		const captured = { calls: 0 };
		expect((await POST(makeEvent({ expense_monthly: 'Infinity' }, captured))).status).toBe(400);
		expect((await POST(makeEvent({ expense_monthly: '-Infinity' }, captured))).status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('rejects currency-string input', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ expense_monthly: '$4,000' }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('rejects scientific notation', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ expense_monthly: '4e3' }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('rejects locale-formatted input (non-en-US)', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ expense_monthly: '4.000,00' }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('rejects a negative value', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ expense_monthly: -0.01 }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toBe(0);
	});

	it('a clean non-negative value is accepted', async () => {
		const captured = { calls: 0 };
		const res = await POST(makeEvent({ expense_monthly: 4000 }, captured));
		expect(res.status).toBe(200);
		expect(captured.calls).toBe(1);
	});
});
