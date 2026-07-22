// mfa-notify.ts — app-sent "your MFA settings changed" email (SELF-291 / Auth-3b Slice 2b).
// Backend-owned server surface (ARCH §4.1 allowlist).
//
// GoTrue has no native MFA-change email, so these are app-sent via nodemailer over the
// SAME shared SMTP env Auth-1 (SELF-290) wires for GoTrue (SMTP_HOST/PORT/USER/PASS +
// SMTP_ADMIN_EMAIL as the sender). Locally that points at Mailpit (127.0.0.1:54324) —
// view sent mail in the Mailpit UI. Reuses Auth-1's SMTP; no second mail provider.
//
// DEPLOY-GATED + FAIL-SOFT (load-bearing): notify is defense-in-depth telemetry, NEVER a
// gate on the security operation. If SMTP is unconfigured → no-op-with-log (a single
// warn, no throw). If a send throws → swallow + log. `notifyMfaChange` NEVER throws and
// NEVER blocks enroll / disable / recovery / regenerate — those succeed or fail on their
// own merits, independent of whether the notice was delivered.
//
// INV-1 (ADR-013): plain-text only — no HTML/markdown/rich-text body.
// No service_role key reference here (RT-26): the factory is the sole key-home; this file
// only reads SMTP env + sends mail.

import nodemailer from 'nodemailer';
import { env } from '$env/dynamic/private';

/** The MFA-change events that trigger a notice. */
export type MfaChangeEvent = 'enrolled' | 'disabled' | 'recovered' | 'regenerated';

const SUBJECTS: Record<MfaChangeEvent, string> = {
	enrolled: 'Two-factor authentication was enabled',
	disabled: 'Two-factor authentication was disabled',
	recovered: 'Your account was recovered with a backup code',
	regenerated: 'Your recovery codes were regenerated'
};

const BODIES: Record<MfaChangeEvent, string> = {
	enrolled:
		'Two-factor authentication (TOTP) was just enabled on your mosko-fintech account. ' +
		'If this was not you, sign in and review your security settings immediately.',
	disabled:
		'Two-factor authentication was just disabled on your mosko-fintech account. ' +
		'If this was not you, sign in and re-enable it immediately.',
	recovered:
		'A backup recovery code was just used to recover access to your mosko-fintech ' +
		'account. Your authenticator was removed — please set up two-factor authentication ' +
		'again now. If this was not you, sign in and secure your account immediately.',
	regenerated:
		'Your mosko-fintech recovery codes were just regenerated. Your previous codes no ' +
		'longer work. If this was not you, sign in and review your security settings immediately.'
};

/** True when the minimum SMTP env to send is present. Missing → deploy-gated no-op. */
function smtpConfigured(): boolean {
	return Boolean(env.SMTP_HOST && env.SMTP_ADMIN_EMAIL);
}

/**
 * Send an MFA-change notice to `email`. FAIL-SOFT + DEPLOY-GATED: returns silently on any
 * misconfiguration or send error (logs, never throws). Callers MAY await it but MUST NOT
 * depend on its outcome — the security op stands regardless.
 */
export async function notifyMfaChange(opts: {
	email: string | null | undefined;
	event: MfaChangeEvent;
}): Promise<void> {
	const { email, event } = opts;
	try {
		if (!email) return; // nothing to notify
		if (!smtpConfigured()) {
			console.warn(
				`[mfa-notify] SMTP not configured — skipping "${event}" notice (deploy-gated no-op).`
			);
			return;
		}
		const port = Number(env.SMTP_PORT ?? '587');
		const transport = nodemailer.createTransport({
			host: env.SMTP_HOST,
			port,
			secure: port === 465, // implicit TLS on 465; STARTTLS otherwise
			auth: env.SMTP_USER ? { user: env.SMTP_USER, pass: env.SMTP_PASS } : undefined
		});
		await transport.sendMail({
			from: env.SMTP_ADMIN_EMAIL,
			to: email,
			subject: SUBJECTS[event],
			text: BODIES[event] // INV-1: plain text only, no `html` field
		});
	} catch (e) {
		// A mail hiccup must NEVER surface to the security flow.
		console.error(
			`[mfa-notify] failed to send "${event}" notice (fail-soft):`,
			e instanceof Error ? e.message : String(e)
		);
	}
}
