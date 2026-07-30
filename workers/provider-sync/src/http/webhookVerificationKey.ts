// webhookVerificationKey.ts — SELF-206 Option-1 credentialed JWK fetch (worker side).
//
// WHY THIS LIVES WORKER-SIDE (the load-bearing posture point):
//   Plaid webhook verification is asymmetric-JWT (Plaid-Verification header, ES256), verified
//   against a PUBLIC key from Plaid's `/webhook_verification_key/get`. That endpoint is a
//   CREDENTIALED Plaid call (PLAID_CLIENT_ID / PLAID_SECRET) — and those creds live ONLY in the
//   worker (api/src is credential-less BY DESIGN, ADR-027 (t) / RT-26 posture). So the credentialed
//   *fetch* happens here; api/src does the actual JWT/body-hash verification locally with the
//   returned PUBLIC key (jose). This keeps PLAID_SECRET off the internet-facing surface and keeps
//   api/src off the RT-26 credential list.
//
//   The key returned is a PUBLIC EC/P-256 JWK — it is NOT secret material. Returning it over the
//   private-bind, shared-secret-gated admission hop leaks nothing. NEVER return / log anything
//   beyond the public JWK coordinates (C6-5).

/** The PUBLIC EC/P-256 JWK subset api/src needs to verify an ES256 JWT (jose importJWK). The
 *  Plaid response's `key` carries more (created_at/expired_at/use) — we forward only the public
 *  verification material. `kty`/`crv`/`x`/`y` are the EC public point; `kid`/`alg`/`use` are
 *  routing/metadata. NO private field exists on a public JWK — there is no `d` to leak. */
export interface PublicJwk {
	kty: string;
	crv: string;
	x: string;
	y: string;
	kid: string;
	alg: string;
	use: string;
}

/** The minimal structural Plaid client this module needs — just the one method (keeps the unit
 *  test free of a full PlaidApi). buildPlaidClient() (cli/admit.ts) satisfies it in production. */
export interface WebhookKeyClient {
	webhookVerificationKeyGet(req: { key_id: string }): Promise<{
		data: { key: { kty: string; crv: string; x: string; y: string; kid: string; alg: string; use: string } };
	}>;
}

/**
 * Fetch the PUBLIC JWK for a given `kid` from Plaid (credentialed call — auth is carried by the
 * client's baseOptions headers, exactly as every other worker Plaid call). Returns only the public
 * verification material. Throws (scrubbed by the caller) on any Plaid/transport failure — the
 * caller (admission route) maps that to a generic 502, and api/src fails the webhook CLOSED (no
 * 200 for an unverifiable webhook → Plaid retries).
 */
export async function fetchWebhookVerificationKey(
	client: WebhookKeyClient,
	kid: string
): Promise<PublicJwk> {
	const { data } = await client.webhookVerificationKeyGet({ key_id: kid });
	const k = data.key;
	// Forward ONLY the public coordinates + routing metadata (no created_at/expired_at echoed —
	// api/src does not need them and we keep the surface minimal).
	return { kty: k.kty, crv: k.crv, x: k.x, y: k.y, kid: k.kid, alg: k.alg, use: k.use };
}
