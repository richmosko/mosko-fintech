// tax-brackets.rt24-adversarial.server.test.ts — RT-24 adversarial battery for
// POST /api/settings/tax-brackets/:schedule_id (docs/SECURITY/index.html #rt-24, read live —
// "Tax-bracket settings-store write-path RLS + monotonicity trigger", ADR-011 Decision 18 /
// Lock 14). V1-SHIP-BLOCK · Sec joint-review-mandatory (rederived-acs.md SELF-259 AC8).
//
// RT-24's own acceptance text names TWO app-layer fences parallel to RT-23 (mod #1 .strict() +
// mass-assignment prevention, mod #2 numeric adversarial battery) plus the DB-layer monotonicity
// trigger and the SERIALIZABLE replace-all wrapper (mods #3/#4, both DB-side — asserted via
// mapWriteError's DB-error-mapping tests in the orchestration file, not here). Write path is E8's
// single RPC call (pfin.fn_tax_bracket_schedule_replace_all — 7-arg form amended by E27/E29 for
// `schedule_label`, landed migration 101 @ b073641); this file mocks the RPC call as a single
// count, since these adversarial cases are all expected to be rejected BEFORE reaching it.
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

function makeEvent(body: unknown, captured: { writeCalls: number; rpcParams?: Record<string, unknown> }) {
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
				rpc: (_fn: string, params: Record<string, unknown>) => {
					captured.writeCalls++;
					captured.rpcParams = params;
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
		schedule_label: '2026 federal ordinary — married filing jointly',
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

describe('RT-24 schedule_label battery (migration 101 canonical-form CHECK: btrim-stable, length 1..500 — E27/E29/E31)', () => {
	it('rejects a missing schedule_label', async () => {
		const captured = { writeCalls: 0 };
		const body = validBody() as Record<string, unknown>;
		delete body.schedule_label;
		const res = await POST(makeEvent(body, captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects an empty-string schedule_label', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ schedule_label: '' }), captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects a whitespace-only schedule_label — trimmed to empty before the min(1) check, same as an explicit empty string (101\'s CHECK is a canonical-form invariant: blank-only is impossible there too)', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ schedule_label: '   ' }), captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects a 501-character schedule_label — one over the DB CHECK\'s 500 max', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ schedule_label: 'x'.repeat(501) }), captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects a non-string schedule_label', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ schedule_label: 12345 }), captured));
		expect(res.status).toBe(400);
		expect(captured.writeCalls).toBe(0);
	});

	it('accepts a 500-character schedule_label — exactly the DB CHECK\'s max (positive control)', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ schedule_label: 'x'.repeat(500) }), captured));
		expect(res.status).toBe(200);
		expect(captured.writeCalls).toBe(1);
	});
});

// RT-24 STRING arm (Sec's SELF-260 V-4, second joint-review pass on this surface —
// schedule_label is the first user-controlled free-text field on a Lock 14 write path). The
// length/empty/whitespace-only/max-length legs above are this arm's shape boundary; this block
// adds the two legs V-4 required and neither prior battery covered: control-character rejection,
// and the deliberate NON-rejection of markup — this field is prose, not markup, and escaping is
// a render-side control (Svelte's default `{label}` interpolation, never `{@html}`), owned by
// SELF-265, not by this schema. Rejecting angle brackets here would be the wrong fence.
describe('RT-24 string arm (Sec 260 V-4) — schedule_label control characters and markup', () => {
	it('rejects a schedule_label containing a control character (a literal tab, mid-string)', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ schedule_label: 'federal ordinary\t2026' }), captured));
		expect(res.status).toBe(400);
		const body = (await res.json()) as { fieldErrors?: Record<string, string[]> };
		expect(body.fieldErrors?.schedule_label?.length).toBeGreaterThan(0);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects a schedule_label containing a C0 control character (U+0001)', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ schedule_label: 'federal\u0001ordinary' }), captured));
		expect(res.status).toBe(400);
		const body = (await res.json()) as { fieldErrors?: Record<string, string[]> };
		expect(body.fieldErrors?.schedule_label?.length).toBeGreaterThan(0);
		expect(captured.writeCalls).toBe(0);
	});

	it("rejects a schedule_label containing U+0000 (NUL) with a 400 field error, NOT a 500 — Sec's SELF-260 re-look (D-4): z.string() alone lets NUL through (a TYPE check, not a content check), and Postgres text cannot hold a NUL byte, so an unguarded NUL would fall through to mapWriteError's default 500 internal_error instead of a clean 400. The control-character regex is [^\\u0000-\\u001F\\u007F-\\u009F], which already excludes U+0000 — this is the watcher that would catch a future edit narrowing that range to \\u0001-\\u001F and reopening the hole", async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ schedule_label: 'federal\u0000ordinary' }), captured));
		expect(res.status).toBe(400);
		const body = (await res.json()) as { fieldErrors?: Record<string, string[]> };
		expect(body.fieldErrors?.schedule_label?.length).toBeGreaterThan(0);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects a schedule_label containing a C1 control character (U+0085, NEL)', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ schedule_label: 'federal\u0085ordinary' }), captured));
		expect(res.status).toBe(400);
		const body = (await res.json()) as { fieldErrors?: Record<string, string[]> };
		expect(body.fieldErrors?.schedule_label?.length).toBeGreaterThan(0);
		expect(captured.writeCalls).toBe(0);
	});

	it('accepts a `<script>alert(1)</script>` schedule_label — it is prose, not markup, and is forwarded to the RPC UNCHANGED; rejecting angle brackets would be the wrong control at this layer. Escaping happens at render (SvelteKit default `{label}` interpolation; `{@html}` must never be used on this field) — that render-side leg belongs to SELF-265, not to this test', async () => {
		const captured: { writeCalls: number; rpcParams?: Record<string, unknown> } = { writeCalls: 0 };
		const payload = '<script>alert(1)</script>';
		const res = await POST(makeEvent(validBody({ schedule_label: payload }), captured));
		expect(res.status).toBe(200);
		expect(captured.writeCalls).toBe(1);
		expect(captured.rpcParams?.p_schedule_label).toBe(payload);
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

// tax_year (Sec F-4, SELF-259 joint review, 2026-09-03): the one numeric field on this surface
// that previously bypassed the battery via `z.coerce.number()` — measured to accept "2e3",
// "0x7d0", " 2000 ", and [2000] as 2000. Now routed through `sanitizeYear` (numeric.ts) via the
// schema's `taxYear()` adapter, same reject-not-coerce discipline as standard_deduction /
// bracket_floor / bracket_rate above. Reject cases use the DEFAULT makeEvent fixture (schema
// validation fails before the ownership-read mock is ever reached, so its fixed `tax_year: 2026`
// is irrelevant here); accept cases use `makeEventForYear` so the mocked ownership read's
// `tax_year` matches the body's post-sanitization value and the schedule-identity guard (409)
// doesn't mask the 200 this battery is actually checking for.
function makeEventForYear(body: unknown, captured: { writeCalls: number }, ownedTaxYear: number) {
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
								Promise.resolve({
									data: { id: 1, tax_year: ownedTaxYear, schedule_type: 'federal_ordinary' },
									error: null
								})
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

describe('RT-24 numeric-input adversarial battery (Lock 14 mod #2) — tax_year (Sec F-4, reject-not-coerce)', () => {
	it('rejects scientific notation ("2e3") with a tax_year field error', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ tax_year: '2e3' }), captured));
		expect(res.status).toBe(400);
		const body = (await res.json()) as { fieldErrors?: Record<string, string[]> };
		expect(body.fieldErrors?.tax_year?.length).toBeGreaterThan(0);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects hex ("0x7d0") with a tax_year field error', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ tax_year: '0x7d0' }), captured));
		expect(res.status).toBe(400);
		const body = (await res.json()) as { fieldErrors?: Record<string, string[]> };
		expect(body.fieldErrors?.tax_year?.length).toBeGreaterThan(0);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects whitespace-padded input (" 2000 ") with a tax_year field error', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ tax_year: ' 2000 ' }), captured));
		expect(res.status).toBe(400);
		const body = (await res.json()) as { fieldErrors?: Record<string, string[]> };
		expect(body.fieldErrors?.tax_year?.length).toBeGreaterThan(0);
		expect(captured.writeCalls).toBe(0);
	});

	it('rejects array coercion ([2000]) with a tax_year field error', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEvent(validBody({ tax_year: [2000] }), captured));
		expect(res.status).toBe(400);
		const body = (await res.json()) as { fieldErrors?: Record<string, string[]> };
		expect(body.fieldErrors?.tax_year?.length).toBeGreaterThan(0);
		expect(captured.writeCalls).toBe(0);
	});

	it('accepts a clean integer number (2000) — positive control', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEventForYear(validBody({ tax_year: 2000 }), captured, 2000));
		expect(res.status).toBe(200);
		expect(captured.writeCalls).toBe(1);
	});

	it('accepts a clean canonical decimal-integer string ("2000") — positive control', async () => {
		const captured = { writeCalls: 0 };
		const res = await POST(makeEventForYear(validBody({ tax_year: '2000' }), captured, 2000));
		expect(res.status).toBe(200);
		expect(captured.writeCalls).toBe(1);
	});
});
