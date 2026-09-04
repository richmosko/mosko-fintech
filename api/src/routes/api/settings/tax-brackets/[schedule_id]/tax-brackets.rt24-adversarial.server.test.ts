// tax-brackets.rt24-adversarial.server.test.ts — RT-24 adversarial battery for
// POST /api/settings/tax-brackets/:schedule_id (docs/SECURITY/index.html #rt-24, read live —
// "Tax-bracket settings-store write-path RLS + monotonicity trigger", ADR-011 Decision 18 /
// Lock 14). V1-SHIP-BLOCK · Sec joint-review-mandatory (rederived-acs.md SELF-259 AC8).
//
// RT-24's own acceptance text names TWO app-layer fences parallel to RT-23 (mod #1 .strict() +
// mass-assignment prevention, mod #2 numeric adversarial battery) plus the DB-layer monotonicity
// trigger and the SERIALIZABLE replace-all wrapper (mods #3/#4, both DB-side — asserted via
// mapReplaceError's DB-error-mapping tests in the orchestration file, not here).
//
// ⚠ FLAGGED, NOT FIXED HERE (Sec/Architect territory — docs/SECURITY/index.html is Sec-owned):
// RT-24's OWN row text, read live for this file, says the monotonicity fence is a "BEFORE
// INSERT/UPDATE trigger" checking "lower_bound" — BOTH of which R4 (docs/records/v14-preflight/
// sitting-log.md, 2026-09-03, the LATER and controlling ruling) supersedes: rider 1 replaces
// the BEFORE ROW form with a deferred CONSTRAINT TRIGGER (a BEFORE ROW trigger cannot see later
// rows in the same multi-row INSERT and passes a non-monotone batch), and rederived-acs.md's
// AC2 carries `bracket_floor` forward as the column-name RECOMMENDATION, not `lower_bound`. This
// file's schema (schemas/tax-bracket-schedule.ts) is built against R4 + rederived-acs.md as the
// most-recent authority; RT-24's doc text is stale against both and due a Sec update at the
// SELF-259 joint review — recorded here rather than silently reconciled.

import { describe, it, expect } from 'vitest';
import { POST } from './+server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

function makeEvent(body: unknown, captured: { rpcCalls: number }) {
	const request = new Request('http://localhost/api/settings/tax-brackets/1', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const locals = {
		safeGetSession: async () => ({ session: {}, user: { id: SESSION_UID } }),
		supabase: {
			schema: () => ({
				from: () => ({
					select: () => ({ eq: () => ({ maybeSingle: () => Promise.resolve({ data: { id: 1 }, error: null }) }) })
				}),
				rpc: () => {
					captured.rpcCalls++;
					return Promise.resolve({ data: null, error: null });
				}
			})
		}
	};
	return { request, locals, params: { schedule_id: '1' } } as unknown as Parameters<typeof POST>[0];
}

function validBody(overrides: Record<string, unknown> = {}) {
	return {
		tax_year: 2026,
		schedule_type: 'federal_ordinary',
		standard_deduction: '14600.00',
		tax_balance_prior_year: null,
		rows: [
			{ bracket_floor: 0, bracket_rate: '0.10' },
			{ bracket_floor: 11600, bracket_rate: '0.12' }
		],
		...overrides
	};
}

describe('RT-24 mass-assignment battery (Lock 14 mod #1)', () => {
	it("a forged users_id — attempted cross-tenant impersonation — rejected before the DB layer", async () => {
		const captured = { rpcCalls: 0 };
		const res = await POST(makeEvent(validBody({ users_id: 'not-my-session' }), captured));
		expect(res.status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('any unsanctioned extra top-level field is rejected', async () => {
		const captured = { rpcCalls: 0 };
		const res = await POST(makeEvent(validBody({ is_admin: true }), captured));
		expect(res.status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('missing a required scalar field (schedule_type) is rejected', async () => {
		const captured = { rpcCalls: 0 };
		const body = validBody() as Record<string, unknown>;
		delete body.schedule_type;
		const res = await POST(makeEvent(body, captured));
		expect(res.status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('an out-of-enum schedule_type is rejected', async () => {
		const captured = { rpcCalls: 0 };
		const res = await POST(makeEvent(validBody({ schedule_type: 'nevada_ordinary' }), captured));
		expect(res.status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('an empty rows array is rejected (zero-row "schedule" is not a schedule)', async () => {
		const captured = { rpcCalls: 0 };
		const res = await POST(makeEvent(validBody({ rows: [] }), captured));
		expect(res.status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});
});

describe('RT-24 numeric-input adversarial battery (Lock 14 mod #2) — standard_deduction', () => {
	it('rejects NaN', async () => {
		const captured = { rpcCalls: 0 };
		const res = await POST(makeEvent(validBody({ standard_deduction: NaN }), captured));
		expect(res.status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('rejects Infinity / -Infinity', async () => {
		const captured = { rpcCalls: 0 };
		expect((await POST(makeEvent(validBody({ standard_deduction: Infinity }), captured))).status).toBe(400);
		expect((await POST(makeEvent(validBody({ standard_deduction: -Infinity }), captured))).status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('rejects a currency-string', async () => {
		const captured = { rpcCalls: 0 };
		const res = await POST(makeEvent(validBody({ standard_deduction: '$14,600' }), captured));
		expect(res.status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('rejects scientific notation', async () => {
		const captured = { rpcCalls: 0 };
		const res = await POST(makeEvent(validBody({ standard_deduction: '1.46e4' }), captured));
		expect(res.status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('rejects locale-formatted input (non-en-US)', async () => {
		const captured = { rpcCalls: 0 };
		const res = await POST(makeEvent(validBody({ standard_deduction: '14.600,00' }), captured));
		expect(res.status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('rejects a negative deduction', async () => {
		const captured = { rpcCalls: 0 };
		const res = await POST(makeEvent(validBody({ standard_deduction: -100 }), captured));
		expect(res.status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('rejects regex-overflow (length-bounded) input', async () => {
		const captured = { rpcCalls: 0 };
		const res = await POST(makeEvent(validBody({ standard_deduction: '9'.repeat(1000) }), captured));
		expect(res.status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});
});

describe('RT-24 numeric-input adversarial battery (Lock 14 mod #2) — bracket_floor (row field)', () => {
	const badRow = (bracket_floor: unknown) => validBody({ rows: [{ bracket_floor, bracket_rate: '0.10' }] });

	it('rejects NaN', async () => {
		const captured = { rpcCalls: 0 };
		expect((await POST(makeEvent(badRow(NaN), captured))).status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('rejects Infinity', async () => {
		const captured = { rpcCalls: 0 };
		expect((await POST(makeEvent(badRow(Infinity), captured))).status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('rejects a currency-string', async () => {
		const captured = { rpcCalls: 0 };
		expect((await POST(makeEvent(badRow('€0'), captured))).status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('rejects scientific notation', async () => {
		const captured = { rpcCalls: 0 };
		expect((await POST(makeEvent(badRow('0e0'), captured))).status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('rejects locale-formatted input', async () => {
		const captured = { rpcCalls: 0 };
		expect((await POST(makeEvent(badRow('11.600,00'), captured))).status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('rejects a negative floor', async () => {
		const captured = { rpcCalls: 0 };
		expect((await POST(makeEvent(badRow(-1), captured))).status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});
});

describe('RT-24 numeric-input adversarial battery (Lock 14 mod #2) — bracket_rate (row field, FRACTION unit)', () => {
	const badRow = (bracket_rate: unknown) => validBody({ rows: [{ bracket_floor: 0, bracket_rate }] });

	it('rejects NaN', async () => {
		const captured = { rpcCalls: 0 };
		expect((await POST(makeEvent(badRow(NaN), captured))).status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('rejects Infinity', async () => {
		const captured = { rpcCalls: 0 };
		expect((await POST(makeEvent(badRow(Infinity), captured))).status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('rejects a currency-string', async () => {
		const captured = { rpcCalls: 0 };
		expect((await POST(makeEvent(badRow('$0.10'), captured))).status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('rejects scientific notation', async () => {
		const captured = { rpcCalls: 0 };
		expect((await POST(makeEvent(badRow('1e-1'), captured))).status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('rejects locale-formatted input', async () => {
		const captured = { rpcCalls: 0 };
		expect((await POST(makeEvent(badRow('0,10'), captured))).status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('rejects a percent-unit value (22 instead of 0.22) — the unit fence, not just a range fence', async () => {
		const captured = { rpcCalls: 0 };
		expect((await POST(makeEvent(badRow(22), captured))).status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('rejects a negative rate', async () => {
		const captured = { rpcCalls: 0 };
		expect((await POST(makeEvent(badRow(-0.1), captured))).status).toBe(400);
		expect(captured.rpcCalls).toBe(0);
	});

	it('a clean in-range fraction is accepted (positive control)', async () => {
		const captured = { rpcCalls: 0 };
		const res = await POST(makeEvent(validBody(), captured));
		expect(res.status).toBe(200);
		expect(captured.rpcCalls).toBe(1);
	});
});
