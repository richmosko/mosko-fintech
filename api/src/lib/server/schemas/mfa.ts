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
