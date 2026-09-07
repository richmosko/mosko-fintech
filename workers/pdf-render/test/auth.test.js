// auth.test.js — SELF-348 (A4) follow-up: RT-21 (g) worker-side detection
// signal (ADR-050 Decision 4 minimal form). Pure unit tests against
// verifyRenderAuth's JWT logic + the rejection counter — no Chromium, no
// HTTP server, no network — so this suite runs unconditionally (unlike
// render.test.js, which skips without a local Chromium binary).

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const jwt = require("jsonwebtoken");

const SIGNING_KEY = "test-signing-key-do-not-leak-12345";
const OTHER_KEY = "a-different-key-not-the-real-one";

const {
  verifyRenderAuth,
  AuthError,
  _resetNonceStoreForTests,
  _getRejectionCountsForTests,
  _resetRejectionCountsForTests,
} = require("../src/auth");

function mintToken(overrides = {}, key = SIGNING_KEY) {
  const payload = {
    users_id: "22222222-2222-4222-8222-222222222222",
    nonce: `n-${Math.random()}`,
    ...overrides,
  };
  return jwt.sign(payload, key, {
    algorithm: "HS256",
    // jsonwebtoken adds `iat` automatically unless a caller overrides it —
    // matching the app-side mintRenderToken (renderClient.ts) convention.
  });
}

test.beforeEach(() => {
  _resetNonceStoreForTests();
  _resetRejectionCountsForTests();
});

test("a valid token verifies and increments NO rejection counter", () => {
  const token = mintToken();
  verifyRenderAuth(`Bearer ${token}`, SIGNING_KEY);
  assert.equal(_getRejectionCountsForTests().size, 0);
});

test("a wrong-key signature is rejected and counted under signature_verification_failed", () => {
  const token = mintToken({}, OTHER_KEY);
  assert.throws(() => verifyRenderAuth(`Bearer ${token}`, SIGNING_KEY), AuthError);
  assert.equal(_getRejectionCountsForTests().get("signature_verification_failed"), 1);
});

test("a missing authorization header is rejected and counted under missing_authorization_header", () => {
  assert.throws(() => verifyRenderAuth(undefined, SIGNING_KEY), AuthError);
  assert.equal(_getRejectionCountsForTests().get("missing_authorization_header"), 1);
});

test("a replayed nonce is rejected and counted under nonce_replay — the SAME reason code twice increments to 2", () => {
  const token = mintToken({ nonce: "fixed-nonce-for-replay-test" });
  verifyRenderAuth(`Bearer ${token}`, SIGNING_KEY); // first use succeeds
  assert.throws(() => verifyRenderAuth(`Bearer ${token}`, SIGNING_KEY), AuthError);
  assert.throws(() => verifyRenderAuth(`Bearer ${token}`, SIGNING_KEY), AuthError);
  assert.equal(_getRejectionCountsForTests().get("nonce_replay"), 2);
});

test("distinct reason codes accumulate under DISTINCT keys, never collapsed into one bucket", () => {
  assert.throws(() => verifyRenderAuth(undefined, SIGNING_KEY), AuthError);
  const badToken = mintToken({}, OTHER_KEY);
  assert.throws(() => verifyRenderAuth(`Bearer ${badToken}`, SIGNING_KEY), AuthError);
  const counts = _getRejectionCountsForTests();
  assert.equal(counts.get("missing_authorization_header"), 1);
  assert.equal(counts.get("signature_verification_failed"), 1);
  assert.equal(counts.size, 2);
});

test("the structured log line carries the reason code and count but NEVER the token or key material", () => {
  const originalError = console.error;
  const lines = [];
  console.error = (...args) => lines.push(args.join(" "));
  try {
    const token = mintToken({}, OTHER_KEY);
    assert.throws(() => verifyRenderAuth(`Bearer ${token}`, SIGNING_KEY), AuthError);
  } finally {
    console.error = originalError;
  }
  const joined = lines.join("\n");
  assert.match(joined, /"event":"pdf_render_auth_rejected"/);
  assert.match(joined, /"reason":"signature_verification_failed"/);
  assert.match(joined, /"count_since_start":1/);
  assert.doesNotMatch(joined, new RegExp(SIGNING_KEY));
  assert.doesNotMatch(joined, /users_id/);
});
