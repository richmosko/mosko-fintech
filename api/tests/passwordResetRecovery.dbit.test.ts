// passwordResetRecovery.dbit.test.ts — SELF-288 / Auth-5 LIVE password-reset E2E (QA-owned).
//
// The real-stack complement to the mock composition specs (passwordResetFlow.qa /
// passwordResetHardening.qa). Drives resetPasswordForEmail against the REAL local GoTrue, reads the
// recovery email out of the REAL Mailpit, mints the recovery session via the REAL verifyOtp, and
// inspects the resulting AAL — the seams the mocks cannot exercise.
//
// SCOPE + THE HONEST E2E GAP: the vitest harness has no Playwright and does not boot the built app on
// :3000, so the *browser* leg (click the email link → SvelteKit /auth/callback route → rendered
// /reset-password form POST) is NOT driven here. What IS driven end-to-end is the security-substantive
// backbone: GoTrue email delivery → Mailpit → recovery-link shape → the LIVE verify-link round-trip
// (followed over HTTP) hopping through /auth/callback with `next=/reset-password` preserved (Sec #3) →
// verifyOtp recovery session → AAL. The callback handler's next→set-password-form routing is covered
// against the REAL handler in the mock composition spec (Leg B). Full browser E2E on the built app
// (the PKCE ?code= exchange on :3000) remains an explicit gap — needs a Playwright + built-app target,
// flagged to team-lead/DevOps, not silently skipped.
//
// SELF-GATING: identical posture to reauthTwoTenant.dbit — skips unless a live local Supabase is
// reachable via the env keys (`supabase status -o env`). Never runs in a stackless CI leg → never flaky.
//
// SYNTHETIC ONLY: throwaway @synthetic.test users, created + deleted in the fixture. No PII, no real
// account numbers (SECURITY §4.5). TOTP codes are generated in-process from the enroll secret via a
// pure node:crypto RFC-6238 helper — NO new dependency (supply-chain minimalism).

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { createHmac } from 'node:crypto';
import { requireStepUp } from '../src/lib/server/auth/mfa';

declare const process: { env: Record<string, string | undefined> };

const URL_ = process.env.SUPABASE_URL ?? process.env.API_URL;
const ANON = process.env.SUPABASE_ANON_KEY ?? process.env.ANON_KEY;
const SR = process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.SERVICE_ROLE_KEY;
const MAILPIT = process.env.MAILPIT_URL ?? 'http://127.0.0.1:54324';
const RUN = Boolean(URL_ && ANON && SR);

const REDIRECT_TO = () => `${URL_}/auth/callback?next=${encodeURIComponent('/reset-password')}`;

// ── RFC-6238 TOTP (node:crypto only; base32 secret → 6-digit code) ───────────────────────────
function base32Decode(s: string): Buffer {
	const A = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
	let bits = '';
	for (const c of s.replace(/=+$/, '').toUpperCase().replace(/\s/g, '')) {
		const i = A.indexOf(c);
		if (i >= 0) bits += i.toString(2).padStart(5, '0');
	}
	const out: number[] = [];
	for (let i = 0; i + 8 <= bits.length; i += 8) out.push(parseInt(bits.slice(i, i + 8), 2));
	return Buffer.from(out);
}
function totp(secret: string, atMs: number): string {
	const key = base32Decode(secret);
	const counter = Math.floor(atMs / 1000 / 30);
	const buf = Buffer.alloc(8);
	buf.writeUInt32BE(Math.floor(counter / 2 ** 32), 0);
	buf.writeUInt32BE(counter >>> 0, 4);
	const h = createHmac('sha1', key).update(buf).digest();
	const o = h[h.length - 1] & 0xf;
	const n = ((h[o] & 0x7f) << 24) | ((h[o + 1] & 0xff) << 16) | ((h[o + 2] & 0xff) << 8) | (h[o + 3] & 0xff);
	return (n % 1_000_000).toString().padStart(6, '0');
}

// ── Mailpit: poll for the newest message to `address`, return its extracted recovery token ───
async function fetchRecoveryToken(address: string): Promise<{ token: string; rawBody: string }> {
	for (let attempt = 0; attempt < 20; attempt++) {
		const box = (await fetch(`${MAILPIT}/api/v1/messages?limit=25`).then((r) => r.json())) as {
			messages?: { ID: string; To?: { Address: string }[] }[];
		};
		const msg = box.messages?.find((m) => (m.To ?? []).some((t) => t.Address === address));
		if (msg) {
			const full = (await fetch(`${MAILPIT}/api/v1/message/${msg.ID}`).then((r) => r.json())) as {
				Text?: string;
				HTML?: string;
			};
			const body = `${full.Text ?? ''}\n${full.HTML ?? ''}`;
			const token = body.match(/[?&]token=([a-z0-9]+)/i)?.[1];
			if (token) return { token, rawBody: body };
		}
		await new Promise((r) => setTimeout(r, 300));
	}
	throw new Error(`no recovery email with an extractable token arrived for ${address}`);
}

function anonClient(persist = false): SupabaseClient {
	return createClient(URL_ as string, ANON as string, {
		auth: { persistSession: persist, autoRefreshToken: false }
	});
}

/** Challenge + verify a TOTP factor on `client` (one retry across a 30s window boundary). Elevates
 *  the client's session to aal2. Used both to enroll-verify and to STEP UP a recovery session. */
async function verifyTotp(client: SupabaseClient, factorId: string, secret: string): Promise<void> {
	const ch = await client.auth.mfa.challenge({ factorId });
	expect(ch.error).toBeNull();
	let vf = await client.auth.mfa.verify({ factorId, challengeId: ch.data!.id, code: totp(secret, Date.now()) });
	if (vf.error) {
		const ch2 = await client.auth.mfa.challenge({ factorId });
		vf = await client.auth.mfa.verify({ factorId, challengeId: ch2.data!.id, code: totp(secret, Date.now()) });
	}
	expect(vf.error, 'TOTP verify must succeed (session reaches aal2)').toBeNull();
}

describe.skipIf(!RUN)('password-reset LIVE E2E — GoTrue + Mailpit + recovery-session AAL', () => {
	const RID = Date.now();
	let admin: SupabaseClient;
	const createdUserIds: string[] = [];

	async function makeUser(tag: string, password: string): Promise<{ id: string; email: string }> {
		const email = `qa-self288-${tag}-${RID}@synthetic.test`;
		const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
		if (error || !data.user) throw new Error(`createUser(${tag}): ${error?.message}`);
		createdUserIds.push(data.user.id);
		return { id: data.user.id, email };
	}

	beforeAll(() => {
		admin = createClient(URL_ as string, SR as string, { auth: { persistSession: false, autoRefreshToken: false } });
	}, 60_000);

	afterAll(async () => {
		if (admin) for (const id of createdUserIds) await admin.auth.admin.deleteUser(id);
	}, 30_000);

	// ── Target #3 (LIVE): the recovery email really lands, with the right link, and completes ──

	it('(1) recovery link ROUND-TRIPS through /auth/callback?next=/reset-password (live, Sec #3)', async () => {
		const { email } = await makeUser('deliver', 'Old-pass-abc-123');
		const res = await anonClient().auth.resetPasswordForEmail(email, { redirectTo: REDIRECT_TO() });
		expect(res.error).toBeNull();

		const { rawBody } = await fetchRecoveryToken(email);
		expect(rawBody).toMatch(/type=recovery/i); // it is a RECOVERY link, not a magic-link/signup
		// The redirect_to embedded in the GoTrue verify link is URL-encoded (%2Fauth%2Fcallback...);
		// decode twice (the `next` path is itself percent-encoded inside redirect_to) then assert the
		// link is aimed at our callback + next=/reset-password.
		const decoded = decodeURIComponent(decodeURIComponent(rawBody));
		expect(decoded).toMatch(/\/auth\/callback/);
		expect(decoded).toMatch(/next=\/reset-password/);

		// SEC #3 — prove the ROUND-TRIP, not just that an email arrived: follow the actual GoTrue verify
		// link over HTTP (no auto-redirect) and assert it hops to OUR /auth/callback with `next`
		// PRESERVED end-to-end and a real recovery credential attached. This is the live leg; the
		// callback handler then TAKING that `next` and landing the set-password form is asserted against
		// the REAL /auth/callback/+server + reset load() in passwordResetFlow.qa (Leg B).
		const verifyUrl = rawBody.match(/(https?:\/\/[^\s"<>)]+\/auth\/v1\/verify[^\s"<>)]*)/i)?.[1];
		expect(verifyUrl, 'recovery email must carry a GoTrue verify link').toBeTruthy();
		const hop = await fetch(verifyUrl!.replace(/&amp;/g, '&'), { redirect: 'manual' });
		expect(hop.status).toBe(303);
		const loc = hop.headers.get('location') ?? '';
		expect(loc).toMatch(/\/auth\/callback/); // routes THROUGH our callback route
		expect(decodeURIComponent(loc)).toMatch(/next=\/reset-password/); // next survives the hop
		expect(loc).toMatch(/access_token=|[?&]code=/); // carries a genuine recovery credential
		// COVERAGE-LEVEL (honest): the browser-driven PKCE `?code=` exchange inside the built SvelteKit
		// app on :3000 is still NOT driven here (no Playwright/built-app target). Live leg proves
		// GoTrue→/auth/callback next-preservation; Leg B proves the handler's next→set-password routing.
	});

	it('(2) NON-MFA control: the recovery session is aal1/aal1 and updateUser COMPLETES the reset', async () => {
		const { email } = await makeUser('nomfa', 'Old-pass-abc-123');
		await anonClient().auth.resetPasswordForEmail(email, { redirectTo: REDIRECT_TO() });
		const { token } = await fetchRecoveryToken(email);

		const rc = anonClient(true);
		const vo = await rc.auth.verifyOtp({ type: 'recovery', token_hash: token });
		expect(vo.error).toBeNull();

		const aal = await rc.auth.mfa.getAuthenticatorAssuranceLevel();
		expect(aal.data?.currentLevel).toBe('aal1');
		expect(aal.data?.nextLevel).toBe('aal1'); // no factor ⇒ no step-up owed
		expect(await requireStepUp(rc)).toBe('allow');

		const up = await rc.auth.updateUser({ password: 'New-pass-xyz-789' });
		expect(up.error).toBeNull(); // the happy path for the common (non-MFA) user completes
	});

	// ── Target #4 (LIVE, crown jewel): the reset can NEVER substitute for the 2nd factor ───────

	it('(3) MFA user: NO bypass without step-up; reset COMPLETES after step-up (Option A, live)', async () => {
		const password = 'Old-pass-abc-123';
		const { email } = await makeUser('mfa', password);

		// Enroll + verify a real TOTP factor (in-process RFC-6238 code) so the user genuinely has aal2.
		const c = anonClient(true);
		await c.auth.signInWithPassword({ email, password });
		const en = await c.auth.mfa.enroll({ factorType: 'totp' });
		expect(en.error).toBeNull();
		const secret = en.data!.totp.secret;
		await verifyTotp(c, en.data!.id, secret);
		expect((await c.auth.mfa.getAuthenticatorAssuranceLevel()).data?.currentLevel).toBe('aal2'); // precondition
		await c.auth.signOut();

		// Recovery flow: request → Mailpit → mint the aal1 recovery session on a FRESH client.
		await anonClient().auth.resetPasswordForEmail(email, { redirectTo: REDIRECT_TO() });
		const { token } = await fetchRecoveryToken(email);
		const rc = anonClient(true);
		expect((await rc.auth.verifyOtp({ type: 'recovery', token_hash: token })).error).toBeNull();

		// ── LEG (a) — NON-BYPASS: without the 2nd factor the password CANNOT change ──────────────
		// The recovery session is aal1 with a factor owed. requireStepUp (the EXACT decision the reset
		// action gates on before updateUser) demands step-up → the action 303s to /mfa/step-up and never
		// calls updateUser. Belt-and-suspenders, GoTrue itself also refuses the aal1 password change.
		const preAal = await rc.auth.mfa.getAuthenticatorAssuranceLevel();
		expect(preAal.data?.currentLevel).toBe('aal1');
		expect(preAal.data?.nextLevel).toBe('aal2');
		expect(await requireStepUp(rc)).toBe('step-up-required'); // action → 303 /mfa/step-up, updateUser skipped
		const refused = await rc.auth.updateUser({ password: 'New-pass-xyz-789' });
		expect(refused.error).not.toBeNull();
		expect(refused.error?.message).toMatch(/aal2/i);

		// ── LEG (b) — COMPLETENESS: the user STEPS UP on the recovery session → the reset COMPLETES ──
		// This is the /mfa/step-up leg Option A funnels them through (verify the authenticator on the
		// recovery session → aal2). The dead-end QA originally found is now a real path to recovery.
		const factors = await rc.auth.mfa.listFactors();
		const rFactorId = factors.data?.totp?.[0]?.id;
		expect(rFactorId, 'the verified factor is visible on the recovery session').toBeTruthy();
		await verifyTotp(rc, rFactorId!, secret); // step up the recovery session to aal2
		expect((await rc.auth.mfa.getAuthenticatorAssuranceLevel()).data?.currentLevel).toBe('aal2');
		expect(await requireStepUp(rc)).toBe('allow'); // the reset action would now proceed
		const done = await rc.auth.updateUser({ password: 'New-pass-xyz-789' });
		expect(done.error).toBeNull(); // MFA user CAN recover — with email control AND the 2nd factor

		// NON-VACUITY: Leg (a) RED-lines if a regression let an aal1 MFA recovery session change the
		// password (requireStepUp='allow' or GoTrue permitting it) = a real aal2 bypass. Leg (b)
		// RED-lines if step-up failed to elevate the recovery session or updateUser stayed refused at
		// aal2 = the dead-end returns (MFA users locked out of recovery). Both the SECURITY property (no
		// bypass without step-up) AND the COMPLETENESS (MFA user can recover via step-up) are proven live.
	}, 60_000);
});
