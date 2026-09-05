// auth.js — PDF_WORKER_SIGNING_KEY JWT verification (SD-20 / RT-21, re-derived
// under R2 (C) at docs/records/v15-preflight/rederived-acs.md § SELF-349).
//
// SCHEME (SD-20 verbatim, R2 (C) direction): the V1 app signs a short-lived
// (60s freshness) JWT containing a `users_id` claim ONLY, HS256, using
// PDF_WORKER_SIGNING_KEY as the shared secret — this worker VERIFIES it. Under
// (C) the app is the caller and this worker's render endpoint is the ONLY
// verifier (RT-21 letter (f) — "the referent moves" to the worker). The JWT's
// purpose is "prove the caller is our app," not "prove who is asking" (R2
// consequences) — the worker has no tenant or money knowledge to prove
// anything ABOUT, per AC #0/#2, and does not persist or act on `users_id` at
// all; this module never reads that claim's value, only that the token as a
// whole verifies.
//
// RT-21 canonical letters, re-derived under (C), each implemented below:
//   (a) tier restriction -> key restriction. A Supabase-issued JWT has no
//       referent under (C) (there is no "tier" to check) — what survives is
//       (b): only PDF_WORKER_SIGNING_KEY signatures verify at all, so a
//       Supabase JWT (signed with a different secret, under `RS256`/`ES256`
//       typically, never this HS256 shared secret) fails signature
//       verification and is rejected on that ground alone.
//   (b) dedicated signing key — `jsonwebtoken.verify` is called with an
//       EXPLICIT `algorithms: ['HS256']` allowlist (never trusting the
//       token's own `alg` header — the classic "alg: none" / algorithm-
//       confusion bypass) and PDF_WORKER_SIGNING_KEY as the only key.
//   (c) 60-second freshness window — checked on `iat`, NOT `exp` (a
//       freshness window is an assertion about when the token was minted,
//       not when it stops being valid; asserting `exp` instead would pin the
//       wrong claim and could pass a token minted long ago with a generous
//       expiry).
//   (d) nonce replay protection — an in-memory, per-worker-container store
//       (Phase 3 mechanism note in RT-21: "in-memory or Redis-backed nonce
//       store"; in-memory is what ships here). ⚠ STATED, not discovered: a
//       container restart clears the store and admits a replay of a token
//       still inside its 60s window — bounded (60s) and named, per RT-21's
//       own instruction to state what happens on restart rather than assume
//       it away.
//   (e) no service_role escalation — CONVERTS to a structural assertion
//       under (C) (RT-21 letter (e) re-derivation): this worker holds no
//       Supabase credential of any kind, so there is no path here that could
//       escalate to one. Nothing in this module reaches for one.
//   (f) dedicated endpoint — this verification logic is called from exactly
//       one place, the render endpoint (server.js) — not exposed elsewhere.
//   (g) rejected payloads dropped with a detection signal — explicitly
//       ROUTED TO SEC AT BUILD per RT-21 (its storage-surface question is
//       unresolved on the tree); this module logs a rejection reason to
//       stderr (bounded, no attacker-controlled content beyond a fixed enum
//       of reason codes) as the interim signal and does NOT invent a storage
//       surface — that is Sec's call, not this file's.

"use strict";

const jwt = require("jsonwebtoken");

const FRESHNESS_WINDOW_SECONDS = 60;

// Per-worker-container, in-memory (RT-21 (d) — Phase 3 mechanism note).
// Keyed by nonce; value is the epoch-seconds it was first seen, so stale
// entries can be swept without ever growing unbounded across the process
// lifetime (a replay window this small does not need every nonce ever seen).
const _seenNonces = new Map();

function _sweepExpiredNonces(nowSeconds) {
  for (const [nonce, seenAt] of _seenNonces) {
    if (nowSeconds - seenAt > FRESHNESS_WINDOW_SECONDS) {
      _seenNonces.delete(nonce);
    }
  }
}

/** Test-only escape hatch — never called from server.js. Lets each test start
 *  from a known-empty nonce store instead of depending on execution order. */
function _resetNonceStoreForTests() {
  _seenNonces.clear();
}

class AuthError extends Error {
  constructor(reason) {
    super(reason);
    this.name = "AuthError";
    this.reason = reason;
  }
}

/**
 * Verify a render request's bearer token against PDF_WORKER_SIGNING_KEY.
 * Throws AuthError (never returns a falsy "invalid" value) on ANY failure —
 * missing header, malformed token, wrong/absent signature, stale `iat`,
 * replayed nonce, or a payload missing required claims. The caller (server.js)
 * maps every AuthError to 401 with no further detail leaked to the response
 * body (RT-21 (g) — a rejection is a fixed reason CODE server-side, never
 * echoed to the caller with enough detail to help iterate an attack).
 *
 * @param {string|undefined} authorizationHeader e.g. "Bearer <jwt>"
 * @param {string} signingKey PDF_WORKER_SIGNING_KEY
 */
function verifyRenderAuth(authorizationHeader, signingKey) {
  if (!signingKey) {
    // A worker with no configured key can verify nothing — fail closed rather
    // than silently accepting every token (which is what an unset secret
    // passed to jsonwebtoken as `undefined` would otherwise risk depending on
    // library version). This is a startup misconfiguration, not a client
    // error, but the caller still gets a 401 — the worker never runs
    // unauthenticated as a fallback.
    throw new AuthError("signing_key_not_configured");
  }

  if (typeof authorizationHeader !== "string") {
    throw new AuthError("missing_authorization_header");
  }
  const match = /^Bearer\s+(\S+)$/.exec(authorizationHeader);
  if (!match) {
    throw new AuthError("malformed_authorization_header");
  }
  const token = match[1];

  let decoded;
  try {
    // (a)+(b): explicit algorithm allowlist — a Supabase-signed token (a
    // different secret, and in practice a different algorithm entirely)
    // fails here on signature mismatch, never on a downstream claim check.
    decoded = jwt.verify(token, signingKey, { algorithms: ["HS256"] });
  } catch (err) {
    throw new AuthError("signature_verification_failed");
  }

  if (typeof decoded !== "object" || decoded === null) {
    throw new AuthError("malformed_payload");
  }
  if (typeof decoded.users_id !== "string" || decoded.users_id.length === 0) {
    // Per SD-20: "JWT containing users_id claim ONLY". The claim's PRESENCE
    // is checked (a token missing it is malformed against the ratified
    // shape); its VALUE is never read again anywhere in this worker — see
    // the module header on why (AC #0/#2: no tenant knowledge here).
    throw new AuthError("missing_users_id_claim");
  }
  if (typeof decoded.iat !== "number") {
    throw new AuthError("missing_iat_claim");
  }
  if (typeof decoded.nonce !== "string" || decoded.nonce.length === 0) {
    throw new AuthError("missing_nonce_claim");
  }

  const nowSeconds = Math.floor(Date.now() / 1000);

  // (c) 60-second freshness window on `iat`. Also rejects an `iat` in the
  // future beyond the window — a clock-skew allowance is not the same thing
  // as accepting an arbitrarily-future-dated token.
  const age = nowSeconds - decoded.iat;
  if (age > FRESHNESS_WINDOW_SECONDS || age < -FRESHNESS_WINDOW_SECONDS) {
    throw new AuthError("stale_token");
  }

  // (d) nonce replay protection.
  _sweepExpiredNonces(nowSeconds);
  if (_seenNonces.has(decoded.nonce)) {
    throw new AuthError("nonce_replay");
  }
  _seenNonces.set(decoded.nonce, nowSeconds);

  return { usersId: decoded.users_id };
}

module.exports = {
  verifyRenderAuth,
  AuthError,
  FRESHNESS_WINDOW_SECONDS,
  _resetNonceStoreForTests,
};
