// render.js — headless-Chromium HTML->PDF rendering. Constructs NO HTML,
// interpolates NO field, has NO template (AC #5's negative assertion) — the
// only input this module accepts is a complete HTML document string, and the
// only output is PDF bytes. Escaping of user-controlled free text is
// discharged upstream (the app's Svelte template, Svelte's default escaping —
// R2 consequences); this file has nothing to escape because it builds no
// markup.
//
// RESOURCE-LOADING FENCE (AC #4b — REQUIRED, an ADDITION to Lock 13 mod #7's
// hardening list, Sec R2.2 condition 1, adopted with the R2 ruling). This
// worker renders NETWORK-SUPPLIED HTML in a real browser engine; without this
// fence, `<iframe src="file:///proc/self/environ">` inside that HTML would
// exfiltrate PDF_WORKER_SIGNING_KEY (this container's ONLY secret, therefore
// its entire compromise) straight into the rendered PDF, and
// `<img src="http://169.254.169.254/">` would fetch cloud-metadata content
// into it. `page.setContent()` PLUS request interception that ABORTS every
// request whose scheme is not `data:` — no `file:`, no `http:`, no `https:` —
// closes both: `data:` URIs (inline base64 images/fonts the HTML already
// carries) are the only resource class this worker will ever fetch on the
// page's behalf. The interception handler's abort COUNT is returned to the
// caller precisely so a test can assert "the fence fired N times," not merely
// "the PDF looks fine" — a failed fetch and a blocked fetch render
// identically, so the visual alone is not evidence (Sec's own framing at the
// ruling; see test/render.test.js).
//
// Lock 13 mod #7 hardening, each implemented below:
//   - browser-context-per-render: ONE browser process is launched at worker
//     startup and reused (avoids a full Chromium relaunch per request); EVERY
//     render gets its OWN incognito browser context (createBrowserContext()),
//     closed immediately after — no cookies, cache, storage or state survives
//     from one render to the next, and a render cannot see anything a prior
//     render's page may have touched.
//   - system-fonts-only: a side effect of the resource-loading fence above,
//     not a separate mechanism — a remote @font-face `url(https://...)` is
//     aborted like any other non-`data:` request, so only fonts already
//     installed in the container's OS (or embedded as `data:` URIs in the
//     HTML itself) can ever render.
//   - `--disable-features=BackgroundFetch,ServiceWorker,BackgroundSync` —
//     launch flag, verbatim.
//   - cache disabled — `page.setCacheEnabled(false)` per render page.
//   - per-render PDF metadata cleared — see `_stripPdfInfoMetadata` below;
//     documented there as BEST-EFFORT, not a cryptographic guarantee.

"use strict";

const puppeteer = require("puppeteer-core");

const HARDENING_ARGS = [
  "--disable-features=BackgroundFetch,ServiceWorker,BackgroundSync",
  // Standard Docker/CI Chromium flags — NOT part of Lock 13 mod #7's named
  // list, needed for Chromium to run at all in a container. Documented
  // separately from the mod #7 flag above so a reader can tell which lines
  // are the ratified hardening list and which are container-runtime
  // necessity. --no-sandbox trades Chromium's OWN process-level sandbox for
  // the container's namespace isolation as the compensating control — flagged
  // explicitly for Sec review, not slipped in silently.
  "--no-sandbox",
  "--disable-setuid-sandbox",
  "--disable-dev-shm-usage",
];

let _browserPromise = null;

// Defense-in-depth BESIDE the resource-loading fence, not instead of it: the
// Chromium child process would otherwise inherit this Node process's FULL
// environment by default (Puppeteer's `env` launch option defaults to
// `process.env`), which would put PDF_WORKER_SIGNING_KEY — this container's
// ONLY secret — inside Chromium's OWN /proc/self/environ. The resource-
// loading fence already stops an `<iframe src="file:///proc/self/environ">`
// from ever being FETCHED; this stops the key from being THERE to read even
// if some other Chromium-internal path reached it. Named explicitly because
// "the fence already covers this" is the reasoning that would make someone
// skip it, and the two controls fail independently.
function _childEnvWithoutSecrets() {
  const env = { ...process.env };
  delete env.PDF_WORKER_SIGNING_KEY;
  return env;
}

function _launchBrowser() {
  const executablePath = process.env.PUPPETEER_EXECUTABLE_PATH;
  if (!executablePath) {
    throw new Error(
      "PUPPETEER_EXECUTABLE_PATH is not set — this worker uses puppeteer-core " +
        "against the container's system Chromium, never a bundled download."
    );
  }
  return puppeteer.launch({
    executablePath,
    headless: true,
    args: HARDENING_ARGS,
    env: _childEnvWithoutSecrets(),
  });
}

/** Lazily launches ONE shared browser process for the worker's lifetime.
 *  Exported so server.js can warm it at startup and close it on shutdown. */
function getBrowser() {
  if (!_browserPromise) {
    _browserPromise = _launchBrowser();
  }
  return _browserPromise;
}

async function closeBrowser() {
  if (_browserPromise) {
    const browser = await _browserPromise;
    _browserPromise = null;
    await browser.close();
  }
}

const ALLOWED_SCHEME = "data:";

/**
 * Render `html` (a COMPLETE document string) to PDF bytes.
 *
 * Returns { pdfBuffer, abortedRequests } — `abortedRequests` is the list of
 * { url } entries the resource-loading fence blocked, so a caller (test or
 * otherwise) can assert on the COUNT and CONTENT of what was refused, not
 * just infer it from the rendered output.
 *
 * @param {string} html
 */
async function renderHtmlToPdf(html) {
  const browser = await getBrowser();
  const context = await browser.createBrowserContext();
  const abortedRequests = [];
  try {
    const page = await context.newPage();
    await page.setCacheEnabled(false);

    await page.setRequestInterception(true);
    page.on("request", (request) => {
      const url = request.url();
      if (url.startsWith(ALLOWED_SCHEME)) {
        request.continue();
      } else {
        abortedRequests.push({ url });
        request.abort("blockedbyclient");
      }
    });

    // setContent, not goto() against a URL this worker does not control — the
    // page's initial document IS the HTML the caller posted, injected
    // directly. No initial navigation request is made at all (setContent
    // does not fetch anything for the top-level document itself), so the
    // FIRST request interception can fire is a resource the posted HTML
    // itself references.
    await page.setContent(html, { waitUntil: "networkidle0" });

    const pdfBuffer = await page.pdf({ printBackground: true });
    return { pdfBuffer: _stripPdfInfoMetadata(pdfBuffer), abortedRequests };
  } finally {
    await context.close();
  }
}

// PDF metadata clearing (Lock 13 mod #7's fourth item) — BEST EFFORT,
// documented as such rather than claimed as a guarantee. Chromium's
// print-to-PDF pipeline sets the document Info dictionary's /Title from the
// rendered HTML's <title> element and /Producer to its own Skia/PDF string;
// since this worker renders arbitrary caller-supplied HTML, an uncleared
// /Title could carry content the caller did not intend to leak via metadata
// (a viewer's "Document Properties" pane, distinct from the visible page).
//
// This function does a byte-level scrub of the classic uncompressed Info
// dictionary shape (`/Title (...)`, `/Author (...)`, etc. as literal or
// hex-string PDF objects) directly in the object stream. ⚠ IT DOES NOT COVER
// every PDF-metadata storage shape — a PDF using COMPRESSED object streams
// (PDF 1.5+ /ObjStm) or an XMP metadata stream (/Metadata) would carry the
// same fields in a form this regex cannot see, and this function does not
// attempt to decompress or rewrite those. Measured against this worker's
// ACTUAL Puppeteer/Chromium output (test/render.test.js's metadata assertion)
// rather than assumed: covers what THIS pipeline emits today. Flagged as a
// judgment call, not a silent gap — a stronger guarantee needs a real PDF
// library (pdf-lib or equivalent), which is a 3rd runtime dependency this
// issue's dependency budget did not plan for; routed to team-lead/Sec rather
// than added unilaterally.
function _stripPdfInfoMetadata(pdfBuffer) {
  // LENGTH-PRESERVING, load-bearing: a PDF's xref table stores exact BYTE
  // OFFSETS to every object, and stream objects carry an exact /Length. If
  // this scrub changed the file's total byte length anywhere before the
  // trailer, every offset after that point would go stale and the PDF would
  // corrupt — a "security" fix that breaks the deliverable is worse than no
  // fix. Every substitution below replaces a captured span with a
  // SAME-LENGTH span (spaces for a literal string's interior, '0' digits for
  // a hex string's interior) so the file's total length and every existing
  // offset are unchanged. Operates on a Buffer (not a decoded string) so a
  // non-UTF8 byte inside a string object is never re-encoded into a
  // different byte length.
  const buf = Buffer.from(pdfBuffer); // copy — do not mutate the caller's buffer in place via indexOf loops below acting on a shared reference
  const fields = ["Title", "Author", "Subject", "Keywords", "Creator", "Producer", "CreationDate", "ModDate"];
  for (const field of fields) {
    _blankLiteralStringField(buf, field);
    _blankHexStringField(buf, field);
  }
  return buf;
}

// /Field (...) — literal string. PDF escapes an interior unbalanced paren as
// `\(` / `\)`, so an escaped paren must not be counted as the closer; this
// walks byte-by-byte rather than using a regex so the "count of a preceding
// backslash is odd" rule for PDF's own `\\` escape is applied correctly
// (`\\)` closes the string; `\)` does not).
function _blankLiteralStringField(buf, field) {
  const needle = Buffer.from(`/${field}`, "latin1");
  let searchFrom = 0;
  for (;;) {
    const keyIdx = buf.indexOf(needle, searchFrom);
    if (keyIdx === -1) return;
    let i = keyIdx + needle.length;
    while (i < buf.length && (buf[i] === 0x20 || buf[i] === 0x0a || buf[i] === 0x0d || buf[i] === 0x09)) i++;
    if (buf[i] !== 0x28 /* ( */) {
      searchFrom = keyIdx + needle.length;
      continue;
    }
    const contentStart = i + 1;
    let j = contentStart;
    let backslashRun = 0;
    let depth = 1; // PDF literal strings may nest BALANCED unescaped parens
    while (j < buf.length && depth > 0) {
      const b = buf[j];
      if (b === 0x5c /* \ */) {
        backslashRun++;
      } else {
        const escaped = backslashRun % 2 === 1;
        if (b === 0x28 && !escaped) depth++;
        else if (b === 0x29 && !escaped) depth--;
        backslashRun = 0;
      }
      j++;
    }
    const contentEnd = j - 1; // position of the closing, now-unmatched paren
    buf.fill(0x20, contentStart, contentEnd); // same-length blank (spaces)
    searchFrom = j;
  }
}

// /Field <48656C6C6F> — hex string form.
function _blankHexStringField(buf, field) {
  const needle = Buffer.from(`/${field}`, "latin1");
  let searchFrom = 0;
  for (;;) {
    const keyIdx = buf.indexOf(needle, searchFrom);
    if (keyIdx === -1) return;
    let i = keyIdx + needle.length;
    while (i < buf.length && (buf[i] === 0x20 || buf[i] === 0x0a || buf[i] === 0x0d || buf[i] === 0x09)) i++;
    if (buf[i] !== 0x3c /* < */) {
      searchFrom = keyIdx + needle.length;
      continue;
    }
    const contentStart = i + 1;
    const closeIdx = buf.indexOf(0x3e /* > */, contentStart);
    if (closeIdx === -1) {
      searchFrom = i + 1;
      continue;
    }
    buf.fill(0x30 /* '0' */, contentStart, closeIdx); // same-length blank hex
    searchFrom = closeIdx + 1;
  }
}

module.exports = {
  renderHtmlToPdf,
  getBrowser,
  closeBrowser,
  _stripPdfInfoMetadata,
};
