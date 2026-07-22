// mfa-recovery.ts — MFA one-time recovery-code issuance + redemption (SELF-291 / Auth-3b
// Slice 2b). Backend-owned server surface (ARCH §4.1 allowlist).
//
// Runs under the service_role admin factory (supabase-admin.ts) — recovery is a
// privileged surface BY CONSTRUCTION (ADR-030): the recovering user is authenticated but
// aal1 (lost authenticator), the MB-1 guard (025) blocks their own aal1 mfa_policy
// downgrade, only service_role admin deleteFactor can remove the verified factor, and the
// 026/027 tables are service_role-only. This file imports the factory; it references NO
// service_role key itself (RT-26 — the factory is the sole key-home).
//
// TENANT BINDING (Decision-1, load-bearing): service_role is BYPASSRLS, so RLS does NOT
// fence these queries — the explicit `.eq('users_id', userId)` on EVERY query is the
// tenant fence. `userId` is ALWAYS the validated-session id passed by the caller
// (safeGetSession().user.id) — NEVER taken from the request body.
//
// Sec's HARD conditions, implemented below:
//   (a) atomic rate-gate (TOCTOU): the attempt row is INSERTed BEFORE the count is read
//       (and the count includes it), so concurrent redeems cannot both slip past a stale
//       low count. Log-while-locked preserves the abuse signal; the trailing-1h window
//       (append-log, not a persistent locked_until) self-heals, so spam cannot create a
//       PERMANENT lockout — it only holds while attempts continue within the hour.
//   (b) constant-time-ish compare: verifyCode (scrypt + timingSafeEqual) runs against EVERY
//       live candidate with NO early break, so total time does not leak which code matched.
//   (c) atomic check-and-consume (double-spend): the consume UPDATE keys on
//       `used_at IS NULL` and rejects on 0 rows-affected — a concurrent redeem of the same
//       code loses the row-lock race and is rejected.
//   (d) the dead factor MUST be removed (admin.deleteFactor, retried) or GoTrue keeps
//       nextLevel=aal2 and the Slice-1 guard still blocks the user.

import { randomBytes, randomUUID } from 'node:crypto';
import { supabaseAdmin } from '$lib/server/supabase-admin';
import { hashCode, verifyCode } from '$lib/server/auth/mfa-hash';
import { notifyMfaChange } from '$lib/server/auth/mfa-notify';

// ── Tunables (documented for Sec review) ────────────────────────────────────────────
/** Codes issued per batch. */
const CODE_COUNT = 10;
/**
 * Random bytes per code → base32 = 16 chars = 80 bits of entropy per code. From a CSPRNG
 * (crypto.randomBytes). 80-bit + scrypt-hashing + the 5/hr rate-limit clears the bar by
 * orders of magnitude (Sec-ratified 2026-07-22; NIST SP 800-63B compliant).
 */
const CODE_BYTES = 10;
// Hashing is scrypt (algo-of-record) — see mfa-hash.ts (hashCode/verifyCode). Issuance
// hashes CODE_COUNT codes once (rare); redemption verifies up to the live-code count (≤10)
// per attempt (also the constant-time-compare requirement + a natural brute-force throttle).
/** Rate-limit: max failed redemption attempts per user per trailing hour before lockout. */
const MAX_FAILURES_PER_HOUR = 5;
const WINDOW_MS = 60 * 60 * 1000;
/** admin.deleteFactor retry budget (CV-R2 confirms it works; retries cover a transient). */
const DELETE_FACTOR_RETRIES = 3;

const BASE32 = 'abcdefghijklmnopqrstuvwxyz234567'; // RFC 4648 lowercased

/** Encode bytes as lowercase RFC-4648 base32 (no padding). */
function base32(bytes: Buffer): string {
	let bits = 0;
	let value = 0;
	let out = '';
	for (const b of bytes) {
		value = (value << 8) | b;
		bits += 8;
		while (bits >= 5) {
			out += BASE32[(value >>> (bits - 5)) & 31];
			bits -= 5;
		}
	}
	if (bits > 0) out += BASE32[(value << (5 - bits)) & 31];
	return out;
}

/** A fresh normalized (storage/compare) code: 16 base32 chars from 10 random bytes. */
function generateCode(): string {
	return base32(randomBytes(CODE_BYTES)).slice(0, 16);
}

/** Group a 16-char code into `abcd-efgh-ijkl-mnop` for display (never stored grouped). */
function groupForDisplay(code: string): string {
	return (code.match(/.{1,4}/g) ?? [code]).join('-');
}

export type RedeemOutcome = 'ok' | 'invalid' | 'locked';

/**
 * Issue a fresh batch of CODE_COUNT recovery codes for `userId`. Generates high-entropy
 * plaintext codes, scrypt-hashes each app-side (plaintext NEVER stored/logged), INSERTs
 * the hashes under a new batch_id, then SUPERSEDES any prior live codes (marks them used)
 * — insert-new-first so a mid-op failure never leaves the user with zero live codes.
 * Returns the CODE_COUNT plaintext codes (grouped for display) ONCE — the caller renders
 * them display-once; they are never returned again. Throws on the INSERT failure so the
 * caller can surface a retry (the old batch, if any, is still live and untouched).
 */
export async function issueRecoveryCodes(userId: string): Promise<string[]> {
	const admin = supabaseAdmin();
	const batchId = randomUUID();
	const plaintext: string[] = [];
	const rows: { users_id: string; code_hash: string; batch_id: string }[] = [];
	for (let i = 0; i < CODE_COUNT; i++) {
		const code = generateCode();
		plaintext.push(groupForDisplay(code));
		rows.push({ users_id: userId, code_hash: await hashCode(code), batch_id: batchId });
	}

	// Insert the NEW batch first (old codes stay live until this commits).
	const { error: insErr } = await admin.schema('pfin').from('mfa_recovery_code').insert(rows);
	if (insErr) {
		console.error('[mfa-recovery] issue insert failed:', insErr.message);
		throw new Error('recovery-code issuance failed');
	}

	// Supersede any OTHER live codes (prior batches) — regenerate replaces.
	const { error: supErr } = await admin
		.schema('pfin')
		.from('mfa_recovery_code')
		.update({ used_at: new Date().toISOString() })
		.eq('users_id', userId)
		.is('used_at', null)
		.neq('batch_id', batchId);
	if (supErr) {
		// Non-fatal: the new batch is live; a stale prior batch lingering is a minor
		// over-provision, not a security hole. Log for follow-up.
		console.error('[mfa-recovery] supersede prior batch failed (non-fatal):', supErr.message);
	}

	return plaintext;
}

/** Count the user's unused (live) recovery codes — for the settings display. */
export async function recoveryCodeStatus(userId: string): Promise<{ unused: number }> {
	const admin = supabaseAdmin();
	const { count, error } = await admin
		.schema('pfin')
		.from('mfa_recovery_code')
		.select('code_id', { count: 'exact', head: true })
		.eq('users_id', userId)
		.is('used_at', null);
	if (error) {
		console.error('[mfa-recovery] status count failed:', error.message);
		return { unused: 0 };
	}
	return { unused: count ?? 0 };
}

/**
 * Redeem a recovery code for `userId` (bound in code — NEVER from the body). Returns
 * 'locked' | 'invalid' | 'ok'. `normalizedCode` is the schema-normalized 16-char form.
 * `userEmail` (validated-session email) is used for the fail-soft recovery notice.
 */
export async function redeemRecoveryCode(
	userId: string,
	normalizedCode: string,
	userEmail?: string | null
): Promise<RedeemOutcome> {
	const admin = supabaseAdmin();

	// (a) ATOMIC RATE-GATE. Log THIS attempt as a failure FIRST (still-log + closes the
	// TOCTOU: the row is committed before the count, so a concurrent redeem cannot read a
	// stale low count and slip past). Then count failures in the trailing hour INCLUDING
	// this row; if over the limit → locked (already logged). A success later appends a
	// separate succeeded=true row; this provisional failure row is harmless (success ends
	// recovery) and ages out of the window.
	const { error: preErr } = await admin
		.schema('pfin')
		.from('mfa_recovery_attempt')
		.insert({ users_id: userId, succeeded: false });
	if (preErr) {
		// Cannot record the attempt → fail CLOSED (do not let a logging failure open the gate).
		console.error('[mfa-recovery] attempt pre-log failed → treating as locked:', preErr.message);
		return 'locked';
	}
	const sinceIso = new Date(Date.now() - WINDOW_MS).toISOString();
	const { count: failCount, error: cntErr } = await admin
		.schema('pfin')
		.from('mfa_recovery_attempt')
		.select('attempt_id', { count: 'exact', head: true })
		.eq('users_id', userId)
		.eq('succeeded', false)
		.gt('attempted_at', sinceIso);
	if (cntErr) {
		console.error('[mfa-recovery] rate-gate count failed → treating as locked:', cntErr.message);
		return 'locked'; // fail CLOSED
	}
	// The just-inserted row is included; > MAX means the 6th+ failure this hour.
	if ((failCount ?? 0) > MAX_FAILURES_PER_HOUR) return 'locked';

	// (b) Fetch the user's LIVE hashes + constant-time-ish compare across ALL of them.
	const { data: liveCodes, error: liveErr } = await admin
		.schema('pfin')
		.from('mfa_recovery_code')
		.select('code_id, code_hash')
		.eq('users_id', userId)
		.is('used_at', null);
	if (liveErr) {
		console.error('[mfa-recovery] live-code read failed:', liveErr.message);
		return 'invalid';
	}
	let matchedId: number | null = null;
	for (const row of liveCodes ?? []) {
		// NO early break — verify every candidate (accumulate the match) so timing does not
		// leak which code matched or its position (scrypt + timingSafeEqual inside verifyCode).
		const isMatch = await verifyCode(normalizedCode, row.code_hash as string);
		if (isMatch) matchedId = row.code_id as number;
	}
	if (matchedId === null) {
		// The pre-logged failure row (above) already records this miss for the rate-gate.
		return 'invalid';
	}

	// (c) ATOMIC CHECK-AND-CONSUME (double-spend). Key on used_at IS NULL; reject on 0 rows.
	const { data: consumed, error: consumeErr } = await admin
		.schema('pfin')
		.from('mfa_recovery_code')
		.update({ used_at: new Date().toISOString() })
		.eq('code_id', matchedId)
		.eq('users_id', userId)
		.is('used_at', null)
		.select('code_id');
	if (consumeErr) {
		console.error('[mfa-recovery] consume failed:', consumeErr.message);
		return 'invalid';
	}
	if (!consumed || consumed.length === 0) {
		// A concurrent redeem of the same code won the row-lock race → this one is rejected.
		return 'invalid';
	}

	// The code is consumed. Restore access WITHOUT minting aal2 (ADR-030):
	// DOWNGRADE mfa_policy FIRST, then remove the factor. This ordering preserves the
	// invariant "mfa_policy='totp' never coexists with a removed factor": the only
	// intermediate state is (factor present, mfa_policy='none') — DB access is restored
	// and the user can still redeem another of their codes if factor-removal fails — never
	// the hard-lockout state (no factor, mfa_policy='totp'). See report note (deviation
	// from the brief's delete-then-downgrade order, on partial-failure safety grounds).
	const { error: dgErr } = await admin
		.schema('pfin')
		.from('user_settings')
		.update({ mfa_policy: 'none' })
		.eq('users_id', userId);
	if (dgErr) {
		// Code already consumed; policy still 'totp'. DB still demands aal2 (hard) — surface
		// so the user retries with another code (the honest failure state).
		console.error('[mfa-recovery] mfa_policy downgrade failed post-consume:', dgErr.message);
		return 'invalid';
	}

	// (d) Remove EVERY verified TOTP factor (must succeed — else GoTrue keeps nextLevel=aal2
	// and the Slice-1 guard blocks the user). Retried; idempotent (deleting an absent factor
	// is a no-op).
	await removeVerifiedFactors(userId);

	// Log success + fail-soft notify.
	await admin.schema('pfin').from('mfa_recovery_attempt').insert({ users_id: userId, succeeded: true });
	await notifyMfaChange({ email: userEmail, event: 'recovered' });
	return 'ok';
}

/** Delete every verified TOTP factor for the user via the admin API (retried). */
async function removeVerifiedFactors(userId: string): Promise<void> {
	const admin = supabaseAdmin();
	const { data, error } = await admin.auth.admin.mfa.listFactors({ userId });
	if (error) {
		console.error('[mfa-recovery] listFactors failed during removal:', error.message);
		return;
	}
	const factors = (data?.factors ?? []).filter(
		(f) => f.factor_type === 'totp' && f.status === 'verified'
	);
	for (const factor of factors) {
		let removed = false;
		for (let attempt = 0; attempt < DELETE_FACTOR_RETRIES && !removed; attempt++) {
			const { error: delErr } = await admin.auth.admin.mfa.deleteFactor({
				id: factor.id,
				userId
			});
			if (!delErr) removed = true;
			else console.error(`[mfa-recovery] deleteFactor ${factor.id} attempt ${attempt + 1}:`, delErr.message);
		}
		if (!removed) {
			// The factor lingers → the app guard will still step the user up. mfa_policy is
			// already 'none' (DB access restored); this is a nuisance, not a hard lockout.
			console.error(`[mfa-recovery] deleteFactor ${factor.id} FAILED after retries.`);
		}
	}
}
