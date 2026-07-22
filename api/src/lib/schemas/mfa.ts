// mfa.ts — CLIENT-SIDE Zod mirror of the TOTP code input (SELF-291 / Auth-3b Slice 1).
//
// MIRROR of src/lib/server/schemas/mfa.ts. The SERVER schema is the security boundary
// (.strict() mass-assignment fence, Lock 14 mod #2); THIS is the browser-side UX mirror
// — a shape-of-record for the 6-digit code the step-up + enroll-verify forms submit.
// Discipline (api/CLAUDE.md): never ship a client schema LOOSER than the server's. Same
// `.strict()` posture, same `/^\d{6}$/` shape, same trim, IDENTICAL message string
// (single anti-drift point). Backend owns the source of truth; when the server schema
// changes, this mirror updates in lockstep.
//
// The forms are plain progressive-enhancement `<form method="POST">` (mirroring
// /login + /signup) — native input attributes (pattern/maxlength/inputmode) carry the
// in-browser fast-feedback; this schema is the tested shape-of-record + is available for
// any future use:enhance client pre-validation.

import { z } from 'zod';

/**
 * A TOTP verification code: exactly 6 digits. Trimmed first so a stray space around a
 * pasted code is tolerated, then shape-validated. Message string is byte-identical to the
 * server's (schemas/mfa.ts) so client + server surface the same copy.
 */
export const totpCodeSchema = z
	.object({
		code: z
			.string()
			.trim()
			.regex(/^\d{6}$/, 'Enter the 6-digit code from your authenticator app.')
	})
	.strict();

export type TotpCodeInput = z.infer<typeof totpCodeSchema>;

/**
 * CLIENT MIRROR of the server `recoveryCodeSchema` (src/lib/server/schemas/mfa.ts) — the
 * MFA one-time backup code redeemed on /mfa/recover (SELF-291 / Auth-3b Slice 2b, AC#4).
 * The SERVER schema is the security boundary (`.strict()` mass-assignment fence + the
 * constant-time scrypt compare); THIS is the browser-side UX shape-of-record.
 *
 * Codes are DISPLAYED grouped (`abcd-efgh-ijkl-mnop`) but stored/compared as 16 RFC-4648
 * base32 chars. Normalize identically to the server — trim, lowercase, strip spaces/dashes
 * — so a user may paste the grouped form or type it loosely; the normalized 16-char value
 * is validated against `/^[a-z2-7]{16}$/`. Byte-identical `.strict()` posture, transform,
 * regex, and message string to the server (single anti-drift point). Never looser than the
 * server; when the server schema changes, this mirror updates in lockstep.
 */
export const recoveryCodeSchema = z
	.object({
		code: z
			.string()
			.trim()
			.transform((s) => s.toLowerCase().replace(/[\s-]/g, ''))
			.pipe(z.string().regex(/^[a-z2-7]{16}$/, 'Enter a valid recovery code.'))
	})
	.strict();

export type RecoveryCodeInput = z.infer<typeof recoveryCodeSchema>;

/**
 * Flatten a ZodError into `{ field: [messages] }` keyed by the top-level field — mirrors
 * the server `fieldErrors` (auth.ts) + the client account.ts copy so all validation
 * errors render through one `{ field: string[] }` code path. Root-level issues bucket
 * under `_form`.
 */
export function fieldErrors(error: z.ZodError): Record<string, string[]> {
	const out: Record<string, string[]> = {};
	for (const issue of error.issues) {
		const key = issue.path.length ? String(issue.path[0]) : '_form';
		(out[key] ??= []).push(issue.message);
	}
	return out;
}
