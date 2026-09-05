// healthz.test.js — SELF-348 (A4) Sec F-13 follow-up (PR #634): the PR body's
// "/healthz" claim had no committed watcher either. This starts the REAL
// exported `server` (server.js) on an ephemeral port and hits the route with
// a real HTTP request — no Chromium involved (the health route never touches
// render.js), so this suite runs unconditionally.

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");

const { server } = require("../src/server");

function get(port, path) {
  return new Promise((resolve, reject) => {
    http
      .get({ host: "127.0.0.1", port, path }, (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () =>
          resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString("utf8") })
        );
      })
      .on("error", reject);
  });
}

test("GET /healthz returns 200 ok without requiring auth or a browser", async () => {
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const { port } = server.address();
    const res = await get(port, "/healthz");
    assert.equal(res.status, 200);
    assert.equal(res.body, "ok");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("GET /unknown-route returns 404", async () => {
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const { port } = server.address();
    const res = await get(port, "/unknown-route");
    assert.equal(res.status, 404);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
