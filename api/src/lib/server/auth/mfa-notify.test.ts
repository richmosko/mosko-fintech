// mfa-notify.test.ts — unit coverage for the MFA-change notifier (SELF-291 / Auth-3b
// Slice 2b). Pure-TS server test (node env). Mocks nodemailer. Proves the deploy-gated +
// fail-soft contract: no SMTP → no-op-with-log; a send throw is swallowed; a null email
// is a no-op; and a configured send emits a plain-text (INV-1) message.
//
// `$env/dynamic/private` resolves to the process.env-backed stub via the vitest alias.

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import nodemailer from 'nodemailer';
import { notifyMfaChange } from './mfa-notify';

vi.mock('nodemailer', () => {
	const sendMail = vi.fn(async () => ({ messageId: 'x' }));
	return { default: { createTransport: vi.fn(() => ({ sendMail })), __sendMail: sendMail } };
});

const sendMail = (nodemailer as unknown as { __sendMail: ReturnType<typeof vi.fn> }).__sendMail;
const createTransport = nodemailer.createTransport as unknown as ReturnType<typeof vi.fn>;

const SMTP_KEYS = ['SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS', 'SMTP_ADMIN_EMAIL'];
function clearSmtp() {
	for (const k of SMTP_KEYS) delete process.env[k];
}

beforeEach(() => {
	vi.clearAllMocks();
	clearSmtp();
	vi.spyOn(console, 'warn').mockImplementation(() => {});
	vi.spyOn(console, 'error').mockImplementation(() => {});
});
afterEach(clearSmtp);

describe('notifyMfaChange — deploy-gated + fail-soft', () => {
	it('is a no-op-with-log when SMTP is not configured (never throws, no transport)', async () => {
		await expect(notifyMfaChange({ email: 'u@example.com', event: 'enrolled' })).resolves.toBeUndefined();
		expect(createTransport).not.toHaveBeenCalled();
		expect(console.warn).toHaveBeenCalled();
	});

	it('is a no-op when the email is null', async () => {
		process.env.SMTP_HOST = 'localhost';
		process.env.SMTP_ADMIN_EMAIL = 'noreply@example.com';
		await expect(notifyMfaChange({ email: null, event: 'disabled' })).resolves.toBeUndefined();
		expect(createTransport).not.toHaveBeenCalled();
	});

	it('sends a PLAIN-TEXT message when configured (INV-1: no html field)', async () => {
		process.env.SMTP_HOST = 'localhost';
		process.env.SMTP_PORT = '54325';
		process.env.SMTP_ADMIN_EMAIL = 'noreply@example.com';
		await notifyMfaChange({ email: 'u@example.com', event: 'recovered' });
		expect(createTransport).toHaveBeenCalledOnce();
		expect(sendMail).toHaveBeenCalledOnce();
		const msg = sendMail.mock.calls[0][0];
		expect(msg.to).toBe('u@example.com');
		expect(msg.from).toBe('noreply@example.com');
		expect(typeof msg.text).toBe('string');
		expect('html' in msg).toBe(false); // INV-1 plain-text only
	});

	it('swallows a send error (fail-soft — never blocks the security op)', async () => {
		process.env.SMTP_HOST = 'localhost';
		process.env.SMTP_ADMIN_EMAIL = 'noreply@example.com';
		sendMail.mockRejectedValueOnce(new Error('smtp exploded'));
		await expect(notifyMfaChange({ email: 'u@example.com', event: 'regenerated' })).resolves.toBeUndefined();
		expect(console.error).toHaveBeenCalled();
	});
});
