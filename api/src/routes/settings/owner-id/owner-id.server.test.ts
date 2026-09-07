// owner-id.server.test.ts — SELF-359 orchestration coverage for /settings/owner-id's loader +
// `save` form action, on top of migration 106 (pfin.owner_identification, SELF-352 / A8).
//
// SCOPE: this file locks the ORCHESTRATION +page.server.ts itself owns — auth gates, FormData ->
// schema translation, the null-vs-blank-vs-value write semantics, mass-assignment prevention, and
// DB-error-code mapping (23514/23505/42501/other). The schema's own OWN rule logic (length bound,
// line-boundary rejection, blank-to-null normalization) is covered directly against
// $lib/server/schemas/owner-identification.ts's exported schema, not re-derived here.
//
// RT-12 ADVERSARIAL BATTERY (SELF-359 AC5's write-endpoint half; the render-escaping half is
// P2/P6's, explicitly NOT claimed here). Reject-vs-store-inert table, stated once so the intent
// behind each leg below is legible without re-deriving it per case:
//
//   payload class                          outcome            why
//   ------------------------------------   ----------------   --------------------------------
//   XSS <script>/onerror payload           STORED, inert      prose to this schema; no charset
//                                                              or tag fence exists at this layer
//                                                              (schedule_label's own precedent);
//                                                              escaping is the RENDER side's job
//                                                              (P2/P6), never claimed here.
//   SQL-injection string                   STORED, inert      PostgREST/postgrest-js never
//                                                              interpolates raw SQL; this is a
//                                                              plain text value to the column.
//   oversize: 121 chars                    REJECTED (400)     106's length CHECK / this schema's
//                                                              matching <=120 UTF-16 bound.
//   oversize: 10 KB                        REJECTED (400)     same length bound, far over it.
//   Unicode line-boundary char (each of     REJECTED (400)     106's single-line CHECK / this
//   the seven LF/VT/FF/CR/NEL/LS/PS)                          schema's matching regex.
//   Unicode control char, NON-line-        STORED, inert      RT-12's own scope note (106's
//   boundary (e.g. BEL, ESC)                                  column comment, verbatim): this
//                                                              schema mirrors ONLY the length +
//                                                              single-line CHECKs, not a broader
//                                                              control-character fence.
//   RTL override (U+202E)                  STORED, inert      no charset fence at this layer;
//                                                              same posture as the XSS leg.
//   homoglyph substitution                 STORED, inert      no charset fence; this field has
//                                                              no identity-spoofing exposure at
//                                                              the write layer to defend against.
//
// DB-error mapping (AC4): 23514/23505 -> generic 400, NEVER the constraint name; 42501 -> 403
// step-up copy; anything else -> logged 500. Since the schema's own length/single-line checks
// already reject the length + line-boundary legs above the DB, the 23514 mapping test below
// exercises it directly against a MOCKED DB error (defense-in-depth), not by finding a payload
// that reaches the DB with a CHECK violation live.

import { describe, it, expect } from 'vitest';
import { load, actions } from './+page.server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

type EqResult = { data: unknown; error: { code: string; message: string } | null };
type UpsertResult = { error: { code: string; message: string } | null };

type Captured = {
	selectCalls: number;
	upsertCalls: Array<{ row: Record<string, unknown>; opts: unknown }>;
};

function makeSupabase(
	opts: { loadResult?: EqResult; upsertResult?: UpsertResult },
	captured: Captured
) {
	const table = {
		select: (_cols: string) => {
			captured.selectCalls++;
			return { maybeSingle: () => Promise.resolve(opts.loadResult ?? { data: null, error: null }) };
		},
		upsert: (row: Record<string, unknown>, upsertOpts: unknown) => {
			captured.upsertCalls.push({ row, opts: upsertOpts });
			return Promise.resolve(opts.upsertResult ?? { error: null });
		}
	};
	const from = (name: string) => {
		if (name === 'owner_identification') return table;
		throw new Error(`unexpected table ${name}`);
	};
	return { schema: (_s: string) => ({ from }) };
}

function newCaptured(): Captured {
	return { selectCalls: 0, upsertCalls: [] };
}

type OwnerIdActionEvent = Parameters<typeof actions.save>[0];

function makeEvent(
	fields: Record<string, string>,
	user: { id: string } | null,
	supabaseOpts: Parameters<typeof makeSupabase>[0] = {}
) {
	const captured = newCaptured();
	const request = new Request('http://localhost/settings/owner-id', {
		method: 'POST',
		body: new URLSearchParams(fields)
	});
	const locals = {
		safeGetSession: async () => ({ session: user ? {} : null, user }),
		supabase: makeSupabase(supabaseOpts, captured)
	};
	return { event: { request, locals } as unknown as OwnerIdActionEvent, captured };
}

// ── load ───────────────────────────────────────────────────────────────────────────────────────

describe('load', () => {
	it('unauthenticated -> redirect to /login', async () => {
		const locals = { safeGetSession: async () => ({ session: null, user: null }) };
		const url = new URL('http://localhost/settings/owner-id');
		await expect(load({ locals, url } as unknown as Parameters<typeof load>[0])).rejects.toMatchObject({
			status: 303
		});
	});

	it('row-absent (never provisioned) -> ownerIdHeaderText: null', async () => {
		const captured = newCaptured();
		const locals = {
			safeGetSession: async () => ({ session: {}, user: { id: SESSION_UID } }),
			supabase: makeSupabase({ loadResult: { data: null, error: null } }, captured)
		};
		const url = new URL('http://localhost/settings/owner-id');
		const result = await load({ locals, url } as unknown as Parameters<typeof load>[0]);
		expect(result).toEqual({ ownerIdHeaderText: null });
		expect(captured.selectCalls).toBe(1);
	});

	it('row present with NULL column -> ownerIdHeaderText: null (106: row-absent and NULL read identically)', async () => {
		const locals = {
			safeGetSession: async () => ({ session: {}, user: { id: SESSION_UID } }),
			supabase: makeSupabase(
				{ loadResult: { data: { owner_id_header_text: null }, error: null } },
				newCaptured()
			)
		};
		const url = new URL('http://localhost/settings/owner-id');
		const result = await load({ locals, url } as unknown as Parameters<typeof load>[0]);
		expect(result).toEqual({ ownerIdHeaderText: null });
	});

	it('row present with a value -> that value threaded through verbatim', async () => {
		const locals = {
			safeGetSession: async () => ({ session: {}, user: { id: SESSION_UID } }),
			supabase: makeSupabase(
				{ loadResult: { data: { owner_id_header_text: 'THE SMITH 2023 TRUST' }, error: null } },
				newCaptured()
			)
		};
		const url = new URL('http://localhost/settings/owner-id');
		const result = await load({ locals, url } as unknown as Parameters<typeof load>[0]);
		expect(result).toEqual({ ownerIdHeaderText: 'THE SMITH 2023 TRUST' });
	});

	it('read error -> fail-soft to null, never throws', async () => {
		const locals = {
			safeGetSession: async () => ({ session: {}, user: { id: SESSION_UID } }),
			supabase: makeSupabase(
				{ loadResult: { data: null, error: { code: 'XXYYY', message: 'boom' } } },
				newCaptured()
			)
		};
		const url = new URL('http://localhost/settings/owner-id');
		const result = await load({ locals, url } as unknown as Parameters<typeof load>[0]);
		expect(result).toEqual({ ownerIdHeaderText: null });
	});
});

// ── actions.save — orchestration ──────────────────────────────────────────────────────────────

describe('actions.save', () => {
	it('unauthenticated -> 401, no DB reached', async () => {
		const { event, captured } = makeEvent({ owner_id_header_text: 'x' }, null);
		const res = (await actions.save(event)) as { status: number };
		expect(res.status).toBe(401);
		expect(captured.upsertCalls).toHaveLength(0);
	});

	it('happy path: a valid value -> upsert row carries session users_id + trimmed value, onConflict users_id', async () => {
		const { event, captured } = makeEvent(
			{ owner_id_header_text: '  THE SMITH 2023 TRUST  ' },
			{ id: SESSION_UID }
		);
		const res = await actions.save(event);
		expect(res).toEqual({ ok: true, ownerIdHeaderText: 'THE SMITH 2023 TRUST' });
		expect(captured.upsertCalls).toHaveLength(1);
		expect(captured.upsertCalls[0].row).toEqual({
			users_id: SESSION_UID,
			owner_id_header_text: 'THE SMITH 2023 TRUST'
		});
		expect(captured.upsertCalls[0].opts).toEqual({ onConflict: 'users_id' });
	});

	it("emptied input ('') -> written as NULL, never '' (106's not-blank CHECK would 23514 on '')", async () => {
		const { event, captured } = makeEvent({ owner_id_header_text: '' }, { id: SESSION_UID });
		const res = await actions.save(event);
		expect(res).toEqual({ ok: true, ownerIdHeaderText: null });
		expect(captured.upsertCalls[0].row.owner_id_header_text).toBeNull();
	});

	it('whitespace-only input -> also written as NULL, not the whitespace string', async () => {
		const { event, captured } = makeEvent({ owner_id_header_text: '   \t  ' }, { id: SESSION_UID });
		const res = await actions.save(event);
		expect(res).toEqual({ ok: true, ownerIdHeaderText: null });
		expect(captured.upsertCalls[0].row.owner_id_header_text).toBeNull();
	});

	it('mass-assignment: a stray users_id field in the FormData never reaches the write row', async () => {
		const { event, captured } = makeEvent(
			{ owner_id_header_text: 'THE SMITH 2023 TRUST', users_id: 'attacker-controlled-uuid' },
			{ id: SESSION_UID }
		);
		await actions.save(event);
		expect(captured.upsertCalls[0].row.users_id).toBe(SESSION_UID);
	});

	it('missing owner_id_header_text field -> treated as null (a schema-level string|null, not a 400)', async () => {
		const { event, captured } = makeEvent({}, { id: SESSION_UID });
		const res = await actions.save(event);
		expect(res).toEqual({ ok: true, ownerIdHeaderText: null });
		expect(captured.upsertCalls[0].row.owner_id_header_text).toBeNull();
	});

	// ── schema-boundary rejections (never reach the DB) ─────────────────────────────────────────

	it('oversize: 121 characters -> 400 field error on owner_id_header_text, no DB reached', async () => {
		const { event, captured } = makeEvent(
			{ owner_id_header_text: 'A'.repeat(121) },
			{ id: SESSION_UID }
		);
		const res = (await actions.save(event)) as { status: number; data: { errors: Record<string, string[]> } };
		expect(res.status).toBe(400);
		expect(res.data.errors).toHaveProperty('owner_id_header_text');
		expect(captured.upsertCalls).toHaveLength(0);
	});

	it('oversize: 10 KB -> 400, no DB reached', async () => {
		const { event, captured } = makeEvent(
			{ owner_id_header_text: 'A'.repeat(10 * 1024) },
			{ id: SESSION_UID }
		);
		const res = (await actions.save(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(captured.upsertCalls).toHaveLength(0);
	});

	it('exactly 120 characters -> accepted (boundary, not off-by-one rejected)', async () => {
		const { event, captured } = makeEvent(
			{ owner_id_header_text: 'A'.repeat(120) },
			{ id: SESSION_UID }
		);
		const res = await actions.save(event);
		expect(res).toEqual({ ok: true, ownerIdHeaderText: 'A'.repeat(120) });
		expect(captured.upsertCalls).toHaveLength(1);
	});

	// One leg per Unicode line-boundary code point 106's single-line CHECK fences — each ALONE,
	// per that CHECK's own comment: "A battery leg asserting a specific constraint name must
	// therefore violate that rule ALONE."
	const LINE_BOUNDARY_CASES: Array<[string, number]> = [
		['LF', 0x0a],
		['VT', 0x0b],
		['FF', 0x0c],
		['CR', 0x0d],
		['NEL', 0x85],
		['LINE SEPARATOR', 0x2028],
		['PARAGRAPH SEPARATOR', 0x2029]
	];
	for (const [name, codepoint] of LINE_BOUNDARY_CASES) {
		it(`Unicode line-boundary char ${name} (U+${codepoint.toString(16).padStart(4, '0').toUpperCase()}) embedded -> 400, no DB reached`, async () => {
			const value = `line one${String.fromCharCode(codepoint)}line two`;
			const { event, captured } = makeEvent({ owner_id_header_text: value }, { id: SESSION_UID });
			const res = (await actions.save(event)) as {
				status: number;
				data: { errors: Record<string, string[]> };
			};
			expect(res.status).toBe(400);
			expect(res.data.errors).toHaveProperty('owner_id_header_text');
			expect(captured.upsertCalls).toHaveLength(0);
		});
	}

	// ── RT-12 adversarial battery (write-endpoint half; see file header table) ─────────────────

	it('RT-12: XSS <script> payload -> STORED inert (prose to this schema; escaping is the render side\'s job)', async () => {
		const payload = '<script>alert(1)</script>';
		const { event, captured } = makeEvent({ owner_id_header_text: payload }, { id: SESSION_UID });
		const res = await actions.save(event);
		expect(res).toEqual({ ok: true, ownerIdHeaderText: payload });
		expect(captured.upsertCalls[0].row.owner_id_header_text).toBe(payload);
	});

	it('RT-12: XSS attribute-breakout payload -> STORED inert', async () => {
		const payload = '"><img src=x onerror=alert(1)>';
		const { event, captured } = makeEvent({ owner_id_header_text: payload }, { id: SESSION_UID });
		const res = await actions.save(event);
		expect(res).toEqual({ ok: true, ownerIdHeaderText: payload });
		expect(captured.upsertCalls[0].row.owner_id_header_text).toBe(payload);
	});

	it('RT-12: SQL-injection string -> STORED inert (PostgREST never interpolates raw SQL)', async () => {
		const payload = "'; DROP TABLE pfin.owner_identification; --";
		const { event, captured } = makeEvent({ owner_id_header_text: payload }, { id: SESSION_UID });
		const res = await actions.save(event);
		expect(res).toEqual({ ok: true, ownerIdHeaderText: payload });
		expect(captured.upsertCalls[0].row.owner_id_header_text).toBe(payload);
	});

	it('RT-12: non-line-boundary Unicode control chars (BEL, ESC) -> STORED inert (this schema mirrors ONLY length + single-line)', async () => {
		const payload = `BEL${String.fromCharCode(0x07)}ESC${String.fromCharCode(0x1b)}end`;
		const { event, captured } = makeEvent({ owner_id_header_text: payload }, { id: SESSION_UID });
		const res = await actions.save(event);
		expect(res).toEqual({ ok: true, ownerIdHeaderText: payload });
		expect(captured.upsertCalls[0].row.owner_id_header_text).toBe(payload);
	});

	it('RT-12: RTL override (U+202E) -> STORED inert', async () => {
		const payload = `good${String.fromCharCode(0x202e)}evil`;
		const { event, captured } = makeEvent({ owner_id_header_text: payload }, { id: SESSION_UID });
		const res = await actions.save(event);
		expect(res).toEqual({ ok: true, ownerIdHeaderText: payload });
		expect(captured.upsertCalls[0].row.owner_id_header_text).toBe(payload);
	});

	it('RT-12: homoglyph substitution (Cyrillic Т U+0422 for Latin T) -> STORED inert (no charset fence at this layer)', async () => {
		const payload = 'ТHE TRUST'; // Cyrillic Те (U+0422) standing in for Latin "T"
		const { event, captured } = makeEvent({ owner_id_header_text: payload }, { id: SESSION_UID });
		const res = await actions.save(event);
		expect(res).toEqual({ ok: true, ownerIdHeaderText: payload });
		expect(captured.upsertCalls[0].row.owner_id_header_text).toBe(payload);
	});

	// ── DB-error mapping (AC4): 23514/23505 -> generic 400, 42501 -> 403, never a constraint name ─

	it('DB 23514 (a CHECK slips past the app schema, e.g. a future stricter DB CHECK) -> generic 400, no constraint name leaked', async () => {
		const { event } = makeEvent(
			{ owner_id_header_text: 'THE SMITH 2023 TRUST' },
			{ id: SESSION_UID },
			{ upsertResult: { error: { code: '23514', message: 'owner_identification_header_not_blank_check violated' } } }
		);
		const res = (await actions.save(event)) as { status: number; data: { errors: Record<string, string[]> } };
		expect(res.status).toBe(400);
		const message = res.data.errors._form.join(' ');
		expect(message).not.toMatch(/owner_identification_header/i);
		expect(message).not.toMatch(/_check/i);
	});

	it('DB 23505 (unique (users_id) conflict, defense-in-depth) -> generic 400, no constraint name leaked', async () => {
		const { event } = makeEvent(
			{ owner_id_header_text: 'THE SMITH 2023 TRUST' },
			{ id: SESSION_UID },
			{ upsertResult: { error: { code: '23505', message: 'duplicate key value violates unique constraint "owner_identification_users_id_key"' } } }
		);
		const res = (await actions.save(event)) as { status: number; data: { errors: Record<string, string[]> } };
		expect(res.status).toBe(400);
		const message = res.data.errors._form.join(' ');
		expect(message).not.toMatch(/owner_identification/i);
		expect(message).not.toMatch(/constraint/i);
	});

	it('DB 42501 (aal2 step-up backstop) -> 403 step-up copy', async () => {
		const { event } = makeEvent(
			{ owner_id_header_text: 'THE SMITH 2023 TRUST' },
			{ id: SESSION_UID },
			{ upsertResult: { error: { code: '42501', message: 'permission denied' } } }
		);
		const res = (await actions.save(event)) as { status: number };
		expect(res.status).toBe(403);
	});

	it('unexpected DB error -> 500', async () => {
		const { event } = makeEvent(
			{ owner_id_header_text: 'THE SMITH 2023 TRUST' },
			{ id: SESSION_UID },
			{ upsertResult: { error: { code: 'XXYYY', message: 'boom' } } }
		);
		const res = (await actions.save(event)) as { status: number };
		expect(res.status).toBe(500);
	});
});
