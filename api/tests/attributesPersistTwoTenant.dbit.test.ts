// attributesPersistTwoTenant.dbit.test.ts — SELF-199 / ADR-037 APP-PATH two-tenant + step-up
// integration test (QA-owned). The action-layer complement to the 042 DB-layer pgTAP battery
// (supabase/tests/rls/042_fn_land_linked_accounts_rls.sql).
//
// ┌─ WHAT THIS PROVES THAT THE OTHER TESTS DON'T ────────────────────────────────────────────┐
// │ • The 042 pgTAP battery proves the 015 #6 matched-tenant fence FIRES in the DB under real  │
// │   RLS when a caller passes another tenant's p_linked_source_id.                            │
// │ • Backend's attributes.server.test.ts proves the action's guard + error→HTTP mapping with  │
// │   a MOCKED requireStepUp / rpc (asserts the branches, not that a real id/session PRODUCES   │
// │   them).                                                                                    │
// │ • THIS test drives the REAL persist action against the REAL local Supabase with REAL        │
// │   password sessions (and, for the step-up case, a REAL enrolled+verified TOTP factor), so   │
// │   the whole chain runs unmocked: requireStepUp(getAuthenticatorAssuranceLevel) → RPC →      │
// │   PostgREST → RLS → the #6 fence → the action envelope. End-to-end.                         │
// └──────────────────────────────────────────────────────────────────────────────────────────┘
//
// FOUR REAL BEHAVIORS (reconciled to Backend's pre-RPC requireStepUp guard, F/CTO-approved):
//   (1) cross-tenant: A (no verified factor → guard ALLOWs) posts tenant B's linked_source_id →
//       the real #6 fence raises → the action maps it to fail-closed 403. End-to-end, no mock.
//   (2) owner control: A posts A's OWN linked_source_id → lands atomically → 303 → /accounts.
//   (3) LAYER-DIVERGENCE edge (the residual of the fence-order finding — surfaced to Sec/Backend):
//       the app guard keys off GoTrue AAL (a *verified factor*), while the 025 DB clause keys off
//       the pfin.user_settings.mfa_policy COLUMN. A user whose pfin mfa_policy='totp' but who has
//       NO verified GoTrue factor (a reachable divergent state — e.g. a factor was removed but the
//       MB-1 guard kept mfa_policy from being lowered) is NOT step-up-intercepted (guard sees no
//       factor → ALLOW), yet is still blocked at the DB #6 fence (its aal2-gated linked_source is
//       RLS-invisible at aal1) → the misleading 403. Fail-closed (no hole) — but the app guard does
//       NOT resolve the finding for this divergent-state user. Worth a Sec/Backend note.
//   (4) step-up (the finding's FIX, proven directly): a user WITH a real verified TOTP factor at
//       aal1 posts → requireStepUp fires (nextLevel='aal2', currentLevel='aal1') → 303 →
//       /mfa/step-up BEFORE the RPC. This is the intended resolution: a legit step-up user is sent
//       to step-up, never the misleading cross-tenant 403.
//
// POSTURE (SECURITY §4.5): SYNTHETIC ONLY. Tenants are ephemeral auth.users (admin API, per-run
// unique); NO PII / NO real account numbers / NO real credentials (linked_source rows are
// credential-less: credential_secret_id NULL). Passwords + TOTP secrets are throwaway synthetic
// values that never leave the runner. Every created user is deleted in afterAll (ON DELETE CASCADE
// reaps the pfin rows + the enrolled factor).
//
// SELF-GATING (⚠ CI/boundary — flagged to team-lead/DevOps/Sec): DB-BACKED integration test.
// Requires a live local Supabase (`supabase start`) AND API_URL / ANON_KEY / SERVICE_ROLE_KEY
// (as emitted by `supabase status -o env`). When any is absent (the pure-unit `npm test` CI job)
// the suite `describe.skipIf`-skips, so it NEVER reds a DB-less runner. Two open decisions for
// ratify: (1) it uses the service_role key IN THE TEST RUNNER for privileged seeding (linked_source
// has no authenticated write path — Decision 1; the RT-26 grep fence scans api/src only, so a
// tests/ reference does not trip it — Sec should bless the pattern); (2) whether DevOps stands up a
// DB-backed CI job so this runs in CI (else it stays a locally-run gate). NOTE (no silent cap): the
// step-up FIX is ALSO covered by Backend's attributes.server.test.ts (mocked requireStepUp); this
// test now proves it end-to-end with a real factor too.

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { createHmac } from 'node:crypto';
import { actions } from '../src/routes/accounts/connect/attributes/+page.server';

const URL_ = process.env.SUPABASE_URL ?? process.env.API_URL;
const ANON = process.env.SUPABASE_ANON_KEY ?? process.env.ANON_KEY;
const SR = process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.SERVICE_ROLE_KEY;
const RUN = Boolean(URL_ && ANON && SR);

// ── RFC 6238 TOTP (Node crypto — no otplib dep) — to complete a real GoTrue factor enrollment ──
function base32Decode(s: string): Buffer {
	const A = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
	let bits = '';
	const out: number[] = [];
	for (const c of s.replace(/=+$/, '').toUpperCase()) {
		const v = A.indexOf(c);
		if (v < 0) continue;
		bits += v.toString(2).padStart(5, '0');
	}
	for (let i = 0; i + 8 <= bits.length; i += 8) out.push(parseInt(bits.slice(i, i + 8), 2));
	return Buffer.from(out);
}
function totp(secretB32: string): string {
	const key = base32Decode(secretB32);
	const counter = Math.floor(Date.now() / 1000 / 30);
	const buf = Buffer.alloc(8);
	buf.writeBigInt64BE(BigInt(counter));
	const hmac = createHmac('sha1', key).update(buf).digest();
	const off = hmac[hmac.length - 1] & 0xf;
	const bin = ((hmac[off] & 0x7f) << 24) | ((hmac[off + 1] & 0xff) << 16) | ((hmac[off + 2] & 0xff) << 8) | (hmac[off + 3] & 0xff);
	return String(bin % 1_000_000).padStart(6, '0');
}

/** Build the persist-action event: one hidden `payload` field, a session for `user`, and `url`
 *  (the requireStepUp guard reads url.pathname for the step-up redirectTo). */
function makeEvent(payloadObj: unknown, supabase: SupabaseClient, user: { id: string }) {
	const request = new Request('http://localhost/accounts/connect/attributes', {
		method: 'POST',
		body: new URLSearchParams({ payload: JSON.stringify(payloadObj) })
	});
	const locals = { safeGetSession: async () => ({ session: {}, user }), supabase };
	const url = new URL('http://localhost/accounts/connect/attributes');
	return { request, locals, url } as unknown as Parameters<typeof actions.default>[0];
}

/** Run the action; normalize a thrown redirect into an inspectable object. */
async function run(event: Parameters<typeof actions.default>[0]) {
	try {
		return { kind: 'return' as const, value: (await actions.default(event)) as { status: number; data?: unknown } };
	} catch (e) {
		return { kind: 'throw' as const, value: e as { status?: number; location?: string } };
	}
}

const acct = (rid: number) => ({
	account_id: `ext-${rid}-1`,
	name: 'Checking',
	scope: 'personal',
	tax_treatment: 'taxable',
	account_type: 'depository'
});
const formMsg = (v: { status: number; data?: unknown }) =>
	(v.data as { errors?: { _form?: string[] } })?.errors?._form?.[0];

describe.skipIf(!RUN)('APP-PATH persist action — two-tenant isolation + step-up (real DB)', () => {
	const RID = Date.now();
	let admin: SupabaseClient;
	const createdUserIds: string[] = [];

	// per-tenant real password sessions (persistSession so mfa/getAAL find the session)
	let cA: SupabaseClient, cD: SupabaseClient, cE: SupabaseClient;
	let aId: string, dId: string, eId: string;
	let aSrc: number, bSrc: number, dSrc: number, eSrc: number;

	async function makeUser(tag: string): Promise<{ id: string; client: SupabaseClient }> {
		const email = `qa-self199-${tag}-${RID}@synthetic.test`;
		const password = `Pw-${RID}-${tag}-xyz`;
		const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
		if (error || !data.user) throw new Error(`createUser(${tag}) failed: ${error?.message}`);
		createdUserIds.push(data.user.id);
		const client = createClient(URL_ as string, ANON as string, { auth: { persistSession: true, autoRefreshToken: false } });
		const si = await client.auth.signInWithPassword({ email, password });
		if (si.error) throw new Error(`signIn(${tag}) failed: ${si.error.message}`);
		return { id: data.user.id, client };
	}

	async function makeSource(users_id: string, tag: string): Promise<number> {
		const { data, error } = await admin
			.schema('pfin')
			.from('linked_source')
			.insert({ users_id, provider: 'plaid', external_connection_id: `conn-${tag}-${RID}`, institution_name: `Synthetic ${tag}` })
			.select('source_id')
			.single();
		if (error || !data) throw new Error(`insert linked_source(${tag}) failed: ${error?.message}`);
		return data.source_id as number;
	}

	beforeAll(async () => {
		admin = createClient(URL_ as string, SR as string, { auth: { persistSession: false, autoRefreshToken: false } });

		const A = await makeUser('a'); aId = A.id; cA = A.client;
		const B = await makeUser('b');
		const D = await makeUser('d'); dId = D.id; cD = D.client;
		const E = await makeUser('e'); eId = E.id;

		aSrc = await makeSource(aId, 'a');
		bSrc = await makeSource(B.id, 'b');
		dSrc = await makeSource(dId, 'd');
		eSrc = await makeSource(eId, 'e');

		// D declares pfin mfa_policy='totp' (a pfin COLUMN — GoTrue never sees it) but enrolls NO
		// factor: the divergent state case (3). Seed via D's OWN authed session (authenticated has
		// the INSERT grant; user_settings has no service_role grant + no aal gate; WITH CHECK
		// users_id=auth.uid()=D). MB-1 downgrade guard is UPDATE-only, so INSERT is clean.
		const us = await cD.schema('pfin').from('user_settings').insert({ users_id: dId, mfa_policy: 'totp' });
		if (us.error) throw new Error(`insert user_settings(d) failed: ${us.error.message}`);

		// E enrolls + verifies a REAL GoTrue TOTP factor (case 4). Enroll requires a real session
		// (GoTrue rejects hand-minted JWTs), which the password sign-in provides.
		const en = await E.client.auth.mfa.enroll({ factorType: 'totp', friendlyName: `qa-${RID}` });
		if (en.error || !en.data?.totp?.secret) throw new Error(`enroll(e) failed: ${en.error?.message}`);
		const ch = await E.client.auth.mfa.challenge({ factorId: en.data.id });
		if (ch.error) throw new Error(`challenge(e) failed: ${ch.error.message}`);
		const vf = await E.client.auth.mfa.verify({ factorId: en.data.id, challengeId: ch.data.id, code: totp(en.data.totp.secret) });
		if (vf.error) throw new Error(`verify(e) failed: ${vf.error.message}`);
		// FRESH sign-in → an aal1 session that now has a verified factor (currentLevel aal1 /
		// nextLevel aal2 → requireStepUp fires). The verify() above left an aal2 session; re-signing
		// in returns to aal1-with-a-verified-factor, the exact step-up-required condition.
		cE = createClient(URL_ as string, ANON as string, { auth: { persistSession: true, autoRefreshToken: false } });
		const siE = await cE.auth.signInWithPassword({ email: `qa-self199-e-${RID}@synthetic.test`, password: `Pw-${RID}-e-xyz` });
		if (siE.error) throw new Error(`re-signIn(e) failed: ${siE.error.message}`);
	}, 60_000);

	afterAll(async () => {
		if (!admin) return;
		for (const id of createdUserIds) await admin.auth.admin.deleteUser(id); // cascade reaps pfin rows + factors
	}, 30_000);

	it('(1) cross-tenant: session A supplying tenant B’s linked_source_id → fail-closed 403 (real #6 fence, no mock)', async () => {
		// A has no verified factor → requireStepUp ALLOWs → the request reaches the RPC, where the
		// real fn_account_matched_linked_source (015 #6) raises on B’s source → action → 403.
		const res = await run(makeEvent({ linked_source_id: String(bSrc), accounts: [acct(RID)] }, cA, { id: aId }));
		if (res.kind !== 'return') throw new Error('expected a fail() return, not a redirect');
		expect(res.value.status).toBe(403);
		expect(formMsg(res.value)).toMatch(/could not be linked/i);

		// Isolation held: NO account landed under B’s source (read as A, RLS-scoped).
		const { data } = await cA.schema('pfin').from('account').select('account_id').eq('linked_source_id', bSrc);
		expect(data ?? []).toHaveLength(0);
	});

	it('(2) owner control: session A supplying A’s OWN linked_source_id → 303 → /accounts, account lands', async () => {
		const res = await run(makeEvent({ linked_source_id: String(aSrc), accounts: [acct(RID)] }, cA, { id: aId }));
		if (res.kind !== 'throw') throw new Error('expected a redirect');
		expect(res.value.status).toBe(303);
		expect(res.value.location).toBe('/accounts');

		const { data } = await cA
			.schema('pfin')
			.from('account')
			.select('provider_account_id, is_active')
			.eq('linked_source_id', aSrc)
			.eq('provider_account_id', `ext-${RID}-1`);
		expect(data).toHaveLength(1);
		expect(data?.[0]?.is_active).toBe(true);
	});

	it('(3) LAYER-DIVERGENCE edge (Sec/Backend note): pfin mfa_policy=totp but NO GoTrue factor → guard ALLOWs, DB #6 still blocks → 403 (the guard does not resolve this residual)', async () => {
		// D has pfin mfa_policy='totp' (025 DB clause gates) but no verified GoTrue factor (guard
		// keys off GoTrue AAL → nextLevel='aal1' → ALLOW). So D reaches the RPC and is blocked at the
		// DB #6 fence (D’s aal2-gated linked_source is RLS-invisible at aal1) with the misleading
		// cross-tenant message. Fail-closed (no hole) — but the app guard does NOT intercept this
		// divergent-state user, so the fence-order finding’s residual persists for it.
		const res = await run(makeEvent({ linked_source_id: String(dSrc), accounts: [acct(RID)] }, cD, { id: dId }));
		if (res.kind !== 'return') throw new Error('expected a fail() return, not a redirect');
		expect(res.value.status).toBe(403);
		expect(formMsg(res.value)).toMatch(/could not be linked/i);
	});

	it('(4) step-up (finding’s FIX, end-to-end): a user WITH a real verified TOTP factor at aal1 → 303 → /mfa/step-up BEFORE the RPC', async () => {
		// E has a REAL enrolled+verified factor and a fresh aal1 session → getAuthenticatorAssuranceLevel
		// returns {currentLevel:'aal1', nextLevel:'aal2'} → requireStepUp fires → redirect to step-up
		// BEFORE the #6 fence. This is the intended resolution: a legit step-up user is sent to step-up,
		// NOT the misleading cross-tenant 403 (contrast case 3’s divergent-state user).
		const res = await run(makeEvent({ linked_source_id: String(eSrc), accounts: [acct(RID)] }, cE, { id: eId }));
		if (res.kind !== 'throw') throw new Error('expected a redirect');
		expect(res.value.status).toBe(303);
		expect(res.value.location).toMatch(/^\/mfa\/step-up\?redirectTo=/);

		// And nothing landed under E’s source — the guard intercepted before the RPC.
		const { data } = await admin.schema('pfin').from('account').select('account_id').eq('linked_source_id', eSrc);
		expect(data ?? []).toHaveLength(0);
	});
});
