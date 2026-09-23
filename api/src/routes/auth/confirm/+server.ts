// auth/confirm/+server.ts — SSR token_hash auth-email verification (ADR-074).
// Backend-owned server source (ARCH §4.1 allowlist). NO service_role (RT-26).
//
// Replaces GoTrue's own `/auth/v1/verify` as the link target in our five custom
// mailer templates (`api/static/email-templates/**`): the email links here with
// `?token_hash=&type=`, and this route verifies the token itself via the app's
// anon+RLS Supabase client over the private stack network — GoTrue's HTTP API gets
// no public route (Sec ruling 2026-09-23). `/auth/v1/verify` (and the stock
// `{{ .ConfirmationURL }}` bodies it powers) is UNREACHABLE from outside the stack by
// design; this route is the only thing a mail client can successfully click.
//
// VERIFY-THEN-REDIRECT: this handler renders nothing. On success it 303s to a FIXED
// per-type destination — never a `next`/`redirect_to` the caller supplies — so an
// open-redirect parameter is structurally impossible here (unlike /auth/callback,
// which at least requires a PKCE code-verifier cookie set on the same browser). The
// redirect Location carries NO query string: the token is single-use and consumed
// server-side exactly once here, and must never reappear in a Referer header or get
// bookmarked/forwarded in a later URL.
//
// ACCESS-LOG RESIDUAL (decided, not inherited — team-lead or Sec, if this changes):
// grepped this repo for any request-URL logger (morgan/pino-http/access-log) — none
// exists, and @sveltejs/adapter-node's own server has no built-in request logger, so
// the APP layer never logs `token_hash`. The one residual this doesn't close is an
// upstream reverse-proxy (Traefik/Coolify) that may log request paths including query
// strings — that surface is outside the `/api` allowlist (DevOps/infra-owned) and is
// accepted here as a single-use, short-TTL-bounded residual rather than mitigated in
// this handler (team-lead has flagged it to DevOps).
//
// ERROR HANDLING: one generic arm for every failure — missing/invalid params, an
// unlisted `type`, an expired/already-consumed/replayed token, or a verifyOtp error —
// all land on the SAME /login?error=confirmation the login page already renders
// (`api/src/routes/login/+page.svelte`). Never echo GoTrue's error message: as with
// the signup/login/forgot-password enumeration fences, distinguishing failure reasons
// here is itself a signal an attacker can probe.

import { redirect } from '@sveltejs/kit';
import { emailOtpTypeSchema, type EmailOtpType } from '$lib/server/schemas/auth';
import type { RequestHandler } from './$types';

// Fixed post-verification destinations, keyed by the validated `type`. NOT
// user-configurable and not derived from any request input.
const DEST: Record<EmailOtpType, string> = {
	signup: '/',
	invite: '/',
	magiclink: '/',
	recovery: '/reset-password',
	email_change: '/' // ADR-074 open question 5 — no email-change UI exists in V1 yet.
};

export const GET: RequestHandler = async ({ url, locals }) => {
	const tokenHash = url.searchParams.get('token_hash');
	const parsedType = emailOtpTypeSchema.safeParse(url.searchParams.get('type'));

	if (tokenHash && parsedType.success) {
		const { error } = await locals.supabase.auth.verifyOtp({
			token_hash: tokenHash,
			type: parsedType.data
		});
		if (!error) throw redirect(303, DEST[parsedType.data]);
	}

	// Missing/invalid params, unlisted type, or a verifyOtp failure (expired/replayed/
	// unknown token) → one generic arm. Reveals nothing about which case occurred.
	throw redirect(303, '/login?error=confirmation');
};
