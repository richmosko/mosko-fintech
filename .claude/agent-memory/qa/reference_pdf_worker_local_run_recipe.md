---
name: pdf-worker-local-run-recipe
description: How to actually stand up workers/pdf-render/ locally for a P6/SELF-358 walk — no runbook doc covers it; this is the derived recipe (puppeteer-core needs a real Chrome path, .env isn't auto-loaded, api/ needs matching signing key + URL override).
metadata:
  type: reference
---

`docs/local-dev.md` covers `workers/provider-sync/` in detail but says NOTHING about
`workers/pdf-render/` (the Node PDF worker, Lock 13). There is no dedicated local-run doc for
it as of the SELF-358/P6 walk (2026-09-07) — "the admission-hop runbook" a brief may reference
turns out to mean the SD-20 signed-JWT handshake concept documented in
`api/src/lib/server/pdf/renderClient.ts`'s own comments, not a separate runbook file. Derived
recipe, confirmed working:

1. **Worker deps**: `cd workers/pdf-render && npm install` (pulls `puppeteer-core` +
   `jsonwebtoken` — small, no bundled Chromium download since it's `-core`).
2. **Chrome binary**: `puppeteer-core` needs `PUPPETEER_EXECUTABLE_PATH` pointed at a REAL
   Chrome/Chromium. A puppeteer-cache Chrome-for-Testing binary already existed at
   `~/.cache/puppeteer/chrome/<version>/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing`
   — reuse it (or `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome` if present).
   Quote the path in `.env` (it has spaces) — `source .env` on an unquoted path with spaces
   fails with `command not found: Chrome`.
3. **`workers/pdf-render/.env`** (gitignored): `PDF_WORKER_SIGNING_KEY=<32+ chars>` +
   `PUPPETEER_EXECUTABLE_PATH="<quoted path>"`.
4. **`api/.env`**: add the SAME `PDF_WORKER_SIGNING_KEY` value (SD-20 shared-secret pair) plus
   `PDF_RENDER_WORKER_URL=http://localhost:8080` (the app's own default,
   `http://pdf-render:8080`, is the Coolify-network service name — unreachable outside Docker).
5. **Start order**: `.env` is NOT auto-loaded by `npm start` (no dotenv in `server.js`) — must
   `set -a; source .env; set +a` in the SAME shell invocation before `npm start`, or the app
   throws `PUPPETEER_EXECUTABLE_PATH is not set` on boot. Restart the SvelteKit dev server too
   after editing `api/.env` (Vite only reads `.env` at startup, per
   `docs/local-dev.md`'s own troubleshooting table).
6. **Verify**: worker logs `[pdf-render] listening on :8080` on clean boot.

**Downloading + inspecting the actual PDF** (not just trusting a 200): `curl` the report's
`/reports/monthly/{month}/pdf` route with a real session cookie
([[reference_magic_link_cookie_login_for_live_walks]]), then `pdftotext` (extract text — proves
escaping/inertness of adversarial content) and `pdftoppm -png` (render a page to inspect styling
visually) — both are Homebrew `poppler` tools, already installed on this machine at
`/opt/homebrew/bin/`.
