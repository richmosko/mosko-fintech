// mfa.ts — server-side Zod schema for MFA (TOTP) inputs (SELF-291 / Auth-3b Slice 1).
// Backend-owned server surface (ARCH §4.1 allowlist).
//
// `.strict()` is the mass-assignment fence (Lock 14 mod #2) — it rejects any extra
// field. The `code` is the ONLY credential field: control fields (factorId, redirectTo)
// are pulled out of the form body BEFORE this parse (they are not credentials — leaving
// them in would trip `.strict()`), mirroring the /login redirectTo pattern (auth.ts).
//
// `safeRedirectPath` + `fieldErrors` are reused from auth.ts (single source of truth) —
// MFA does not re-copy them.

import { z } from 'zod';

/**
 * A TOTP verification code: exactly 6 digits (GoTrue default; config.toml
 * [auth.mfa.totp]). Trimmed first so a stray space around a pasted code is tolerated,
 * then shape-validated. No numeric-battery coercion here — this is an opaque digit
 * string, not a monetary value.
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
 * A one-time MFA **recovery** code (SELF-291 / Auth-3b Slice 2b). Issued as 16 RFC-4648
 * base32 chars (lowercased; from 10 random bytes = 80 bits), DISPLAYED grouped
 * (`abcd-efgh-ijkl-mnop`) for legibility. The input is NORMALIZED first — trimmed,
 * lowercased, and stripped of spaces/dashes — so a user may paste the grouped form or
 * type it loosely; the normalized 16-char value is what the server scrypt-compares
 * (constant-time) against the stored hash (`mfa-hash.ts` hashes the same normalized form).
 * `.strict()`
 * is the mass-assignment fence; the normalized value is exposed as `code`.
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
