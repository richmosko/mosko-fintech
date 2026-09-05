// render-env.test.js — SELF-348 (A4) Sec F-13 follow-up (PR #634): the PR
// body's claim that "the signing key is absent from every Chromium child
// environment" had no committed watcher — `_childEnvWithoutSecrets()` was
// exercised only manually. This suite asserts it directly. No Chromium
// binary needed — `_childEnvWithoutSecrets` is a pure function of
// `process.env`, never launched.

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { _childEnvWithoutSecrets } = require("../src/render");

test("the Chromium child env omits PDF_WORKER_SIGNING_KEY even when it IS set on the worker process", () => {
  const original = process.env.PDF_WORKER_SIGNING_KEY;
  process.env.PDF_WORKER_SIGNING_KEY = "must-never-reach-chromium";
  try {
    const childEnv = _childEnvWithoutSecrets();
    assert.equal("PDF_WORKER_SIGNING_KEY" in childEnv, false);
  } finally {
    if (original === undefined) {
      delete process.env.PDF_WORKER_SIGNING_KEY;
    } else {
      process.env.PDF_WORKER_SIGNING_KEY = original;
    }
  }
});

test("the Chromium child env is otherwise a COPY of process.env, not an empty object — other vars (e.g. PATH) survive", () => {
  const childEnv = _childEnvWithoutSecrets();
  assert.equal(childEnv.PATH, process.env.PATH);
});

test("mutating the returned env object does NOT mutate process.env — a fresh copy every call", () => {
  const childEnv = _childEnvWithoutSecrets();
  childEnv.SOME_TEST_MARKER = "leaked-if-shared-reference";
  assert.equal(process.env.SOME_TEST_MARKER, undefined);
});
