// server.js — the PDF worker's HTTP surface. "A PDF printer, nothing else"
// (F/CTO's framing at the R2 ruling, docs/records/v15-preflight/sitting-log.md
// § R2): ONE route, no database reach, no template, no tenant or money
// knowledge. Built on Node's built-in `http` module — no framework dependency
// — so this worker's dependency footprint stays at exactly the two packages
// this surface actually needs (puppeteer-core to render, jsonwebtoken to
// verify the caller), per Lock 13 mod #2's zero-DB-isolation ethos of keeping
// this container's footprint minimal, not just its DB reach.
//
// Zero `SUPABASE_*` anywhere in this file or anything it imports (Sec D-1, a
// VETO — no exception, not even a read-only URL). The single permitted
// credential is PDF_WORKER_SIGNING_KEY (SD-20).

"use strict";

const http = require("node:http");

const { verifyRenderAuth, AuthError } = require("./auth");
const { renderHtmlToPdf, getBrowser, closeBrowser } = require("./render");

const PORT = Number(process.env.PORT || 8080);
const MAX_BODY_BYTES = 25 * 1024 * 1024; // 25MB — a rendered report's HTML has no legitimate reason to approach this; a defensive bound against an unbounded-body DoS, not a product requirement.

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;
    req.on("data", (chunk) => {
      total += chunk.length;
      if (total > MAX_BODY_BYTES) {
        reject(Object.assign(new Error("payload_too_large"), { statusCode: 413 }));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

async function handleRender(req, res) {
  let auth;
  try {
    auth = verifyRenderAuth(req.headers["authorization"], process.env.PDF_WORKER_SIGNING_KEY);
  } catch (err) {
    if (err instanceof AuthError) {
      // RT-21 (g): the structured detection-signal log line (reason code +
      // bounded counter, ADR-050 D4 minimal form) is already emitted by
      // `_rejected()` inside auth.js at throw time — not duplicated here.
      // The response body carries NOTHING beyond the generic 401 — never the
      // reason, which would help an attacker iterate toward a valid forgery.
      res.writeHead(401, { "content-type": "text/plain" });
      res.end("unauthorized");
      return;
    }
    throw err;
  }
  // `auth.usersId` is intentionally UNUSED beyond this point — see auth.js's
  // module header (AC #0/#2: this worker holds no tenant knowledge). Its
  // only role was to be present and verifiable; nothing here acts on its
  // value, logs it, or threads it into the render.
  void auth;

  let bodyBuffer;
  try {
    bodyBuffer = await readBody(req);
  } catch (err) {
    const status = err.statusCode || 400;
    res.writeHead(status, { "content-type": "text/plain" });
    res.end(status === 413 ? "payload too large" : "bad request");
    return;
  }

  const html = bodyBuffer.toString("utf8");
  if (html.length === 0) {
    res.writeHead(400, { "content-type": "text/plain" });
    res.end("empty body");
    return;
  }

  let result;
  try {
    result = await renderHtmlToPdf(html);
  } catch (err) {
    console.error("[pdf-render] render failed:", err && err.message);
    res.writeHead(500, { "content-type": "text/plain" });
    res.end("render failed");
    return;
  }

  if (result.abortedRequests.length > 0) {
    console.log(`[pdf-render] resource-loading fence aborted ${result.abortedRequests.length} request(s)`);
  }

  res.writeHead(200, {
    "content-type": "application/pdf",
    "content-length": result.pdfBuffer.length,
    // Observability for the resource-loading fence (AC #4b's catch criterion
    // is explicitly about the ABORT COUNT, not just PDF appearance — "a
    // failed fetch and a blocked fetch render identically"). A COUNT only,
    // never the aborted URLs themselves, which could carry caller-supplied
    // content this response has no business echoing back.
    "x-pdf-render-aborted-count": String(result.abortedRequests.length),
  });
  res.end(result.pdfBuffer);
}

const server = http.createServer((req, res) => {
  if (req.method === "GET" && req.url === "/healthz") {
    res.writeHead(200, { "content-type": "text/plain" });
    res.end("ok");
    return;
  }
  if (req.method === "POST" && req.url === "/render") {
    handleRender(req, res).catch((err) => {
      console.error("[pdf-render] unhandled error:", err);
      if (!res.headersSent) {
        res.writeHead(500, { "content-type": "text/plain" });
        res.end("internal error");
      }
    });
    return;
  }
  res.writeHead(404, { "content-type": "text/plain" });
  res.end("not found");
});

function start() {
  // Warm the shared browser at startup rather than on the first request, so
  // the first real render isn't the one paying Chromium's launch latency.
  getBrowser()
    .then(() => {
      server.listen(PORT, () => {
        console.log(`[pdf-render] listening on :${PORT}`);
      });
    })
    .catch((err) => {
      console.error("[pdf-render] failed to launch browser at startup:", err);
      process.exit(1);
    });
}

async function shutdown(signal) {
  console.log(`[pdf-render] received ${signal}, shutting down`);
  server.close();
  await closeBrowser();
  process.exit(0);
}

if (require.main === module) {
  process.on("SIGTERM", () => shutdown("SIGTERM"));
  process.on("SIGINT", () => shutdown("SIGINT"));
  start();
}

module.exports = { server, handleRender };
