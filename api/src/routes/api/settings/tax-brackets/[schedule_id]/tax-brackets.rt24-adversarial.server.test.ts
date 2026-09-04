// tax-brackets.rt24-adversarial.server.test.ts — RT-24 adversarial battery for
// POST /api/settings/tax-brackets/:schedule_id (docs/SECURITY/index.html #rt-24, read live —
// "Tax-bracket settings-store write-path RLS + monotonicity trigger", ADR-011 Decision 18 /
// Lock 14). V1-SHIP-BLOCK · Sec joint-review-mandatory (rederived-acs.md SELF-259 AC8).
//
// RT-24's own acceptance text names TWO app-layer fences parallel to RT-23 (mod #1 .strict() +
// mass-assignment prevention, mod #2 numeric adversarial battery) plus the DB-layer monotonicity
// trigger and the SERIALIZABLE replace-all wrapper (mods #3/#4, both DB-side — asserted via
// mapWriteError's DB-error-mapping tests in the orchestration file, not here). Write path is E8's
// single RPC call (pfin.fn_tax_bracket_schedule_replace_all); this file mocks the RPC call as a
// single count, since these adversarial cases are all expected to be rejected BEFORE reaching it.
//
// ⚠ FLAGGED, NOT FIXED HERE (Sec/Architect territory — docs/SECURITY/index.html is Sec-owned):
// RT-24's OWN row text, read live for this file, says the monotonicity fence is a "BEFORE
// INSERT/UPDATE trigger" checking "lower_bound" — BOTH superseded by the landed migration 101
// (supabase/migrations/101_tax_bracket_tables.sql @ 5f69249, SELF-259): the fence is a DEFERRED
// CONSTRAINT TRIGGER (a BEFORE ROW trigger cannot see later rows in the same multi-row INSERT,
// per 101's own header), and the column is `bracket_floor`, not `lower_bound`. This file's
// schema (schemas/tax-bracket-schedule.ts) is built against the landed DDL as the current
// authority; RT-24's doc text is stale against it and due a Sec update at the SELF-259 joint
// review — recorded here rather than silently reconciled.

import { describe, it, expect } from 'vitest';
import { POST } from './+server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

function makeEvent(body: unknown, captured: { writeCalls: number }) {
	const request = new Request('http://localhost/api/settings/tax-brackets/1', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const locals = {
		safeGetSession: async () => ({ session: {}, user: { id: SESSION_UID } }),
		supabase: {
			schema: () => ({
				from: (_table: string) => ({
					select: () => ({
						eq: () => ({
							maybeSingle: () =>
								Promise.resolve({ data: { id: 1, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null })
						})
					})
				}),
				rpc: (_fn: string, _params: Record<string, unknown>) => {
					captured.writeCalls++;
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
	it('a forged users_id — attempted cross-tenant impersonation — rejected before the DB layer', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ users_id: 'not-my-session' }), captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('any unsanctioned extra top-level field is rejected', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ is_admin: true }), captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('missing a required scalar field (schedule_type) is rejected', async () => {
		const captured = { writeCalls: 0 };
		const body = validBody() as Record<string, unknown>;
		delete body.schedule_type;
		const res = await POST(makeEvent(body, captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('an out-of-enum schedule_type is rejected', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ schedule_type: 'nevada_ordinary' }), captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('a plausible-but-wrong enum spelling ("federal_ltcg", missing the underscore) is rejected — the exact label is federal_lt_cg', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ schedule_type: 'federal_ltcg' }), captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('an empty rows array is rejected (an app-layer UX bound — the DB itself treats empty as legal, but a settings editor has no reason to submit zero brackets as an intended final state)', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ rows: [] }), captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});
});

describe('RT-24 numeric-input adversarial battery (Lock 14 mod #2) — standard_deduction', () => {
	it('rejects NaN', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ standard_deduction: NaN }), captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects Infinity / -Infinity', async () => {
		const captured = { writeCalls: 0 };
		expect((await POST(makeEvent(validBody({ standard_deduction: Infinity }), captured))).status).toBe(400);
		expect((await POST(makeEvent(validBody({ standard_deduction: -Infinity }), captured))).status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects a currency-string', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ standard_deduction: '$14,600' }), captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects scientific notation', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ standard_deduction: '1.46e4' }), captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects locale-formatted input (non-en-US)', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ standard_deduction: '14.600,00' }), captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects a negative deduction', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ standard_deduction: -100 }), captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects regex-overflow (length-bounded) input', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ standard_deduction: '9'.repeat(1000) }), captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});
});

describe('RT-24 numeric-input adversarial battery (Lock 14 mod #2) — tax_balance_prior_year (nullable, no sign bound)', () => {
	it('rejects NaN (string — a literal JS `NaN` number serializes to JSON `null`, which is this field\'s VALID unset value, so the adversarial input must be the string "NaN" to actually exercise the sanitizer\'s NaN-text rejection rather than the nullable type-check path)', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ tax_balance_prior_year: 'NaN' }), captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects a currency-string', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ tax_balance_prior_year: '$500' }), captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('accepts a negative value — CONFIRMED at migration 101: "a prior-year balance can be an OVERPAYMENT and is then legitimately negative"', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ tax_balance_prior_year: -500.25 }), captured));
		expect(res.status).toBe(200);
		expect(captured.writeCalls).toBe(1);
	});

	it('accepts null (the unset representation)', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ tax_balance_prior_year: null }), captured));
		expect(res.status).toBe(200);
	});
});

describe('RT-24 numeric-input adversarial battery (Lock 14 mod #2) — bracket_floor (row field)', () => {
	const badRow = (bracket_floor: unknown) => validBody({ rows: [{ bracket_floor, bracket_rate: '0.10' }] });

	it('rejects NaN', async () => {
		const captured = { writeCalls: 0 };
		expect((await POST(makeEvent(badRow(NaN), captured))).status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects Infinity', async () => {
		const captured = { writeCalls: 0 };
		expect((await POST(makeEvent(badRow(Infinity), captured))).status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects a currency-string', async () => {
		const captured = { writeCalls: 0 };
		expect((await POST(makeEvent(badRow('€0'), captured))).status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects scientific notation', async () => {
		const captured = { writeCalls: 0 };
		expect((await POST(makeEvent(badRow('0e0'), captured))).status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects locale-formatted input', async () => {
		const captured = { writeCalls: 0 };
		expect((await POST(makeEvent(badRow('11.600,00'), captured))).status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects a negative floor', async () => {
		const captured = { writeCalls: 0 };
		expect((await POST(makeEvent(badRow(-1), captured))).status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});
});

describe('RT-24 numeric-input adversarial battery (Lock 14 mod #2) — bracket_rate (row field, FRACTION unit, numeric(12,8) CHECK [0,1])', () => {
	const badRow = (bracket_rate: unknown) => validBody({ rows: [{ bracket_floor: 0, bracket_rate }] });

	it('rejects NaN', async () => {
		const captured = { writeCalls: 0 };
		expect((await POST(makeEvent(badRow(NaN), captured))).status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects Infinity', async () => {
		const captured = { writeCalls: 0 };
		expect((await POST(makeEvent(badRow(Infinity), captured))).status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects a currency-string', async () => {
		const captured = { writeCalls: 0 };
		expect((await POST(makeEvent(badRow('$0.10'), captured))).status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects scientific notation', async () => {
		const captured = { writeCalls: 0 };
		expect((await POST(makeEvent(badRow('1e-1'), captured))).status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects locale-formatted input', async () => {
		const captured = { writeCalls: 0 };
		expect((await POST(makeEvent(badRow('0,10'), captured))).status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects a percent-unit value (22 instead of 0.22) via the range check — the typmod (numeric(12,8), 4 int digits) is deliberately loose enough to let "22" coerce, per migration 101\'s own design, so the >1 CHECK is what fires', async () => {
		const captured = { writeCalls: 0 };
		expect((await POST(makeEvent(badRow(22), captured))).status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects a negative rate', async () => {
		const captured = { writeCalls: 0 };
		expect((await POST(makeEvent(badRow(-0.1), captured))).status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('accepts up to 8 decimal places (the typmod scale) — a clean in-range fraction is accepted (positive control)', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ rows: [{ bracket_floor: 0, bracket_rate: '0.12345678' }] }), captured));
		expect(res.status).toBe(200);
		expect(captured.writeCalls).toBe(1);
	});
});
