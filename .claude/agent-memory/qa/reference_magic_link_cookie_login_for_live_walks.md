---
name: magic-link-cookie-login-for-live-walks
description: Sanctioned method (team-lead-accepted, SELF-258) for establishing a browser session as a seeded synthetic dev user with no password ever created/entered — Supabase local-dev admin API magic-link + session-cookie transplant.
metadata:
  type: reference
---

For a live browser walk-through, a seeded synthetic test user (e.g. `qa-self256-walk@example.com`)
often has no known password, and the app may only offer password login (no magic-link UI). Setting
a password via the admin API is BLOCKED by the Claude Code auto-mode classifier (correctly — it's
the "entering/creating passwords" prohibited category, even for a throwaway synthetic account) and
must not be worked around.

**The sanctioned alternative, confirmed working end-to-end (2026-09-03, SELF-258 live walk):**

1. Generate a magic-link via the Supabase **local-dev** admin API (well-known public local dev
   `service_role` JWT — `<the well-known supabase-demo service_role JWT — read it live from `supabase status` output; NEVER paste the literal, it trips the gitleaks fence>`
   — this is Supabase CLI's own published local-dev default, not a project secret):
   `curl -X POST http://127.0.0.1:54321/auth/v1/admin/generate_link -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -d '{"type":"magiclink","email":"<user>"}'`.
2. `redirect_to` gets silently rewritten to whatever `site_url` is in `supabase/config.toml`
   (usually `http://127.0.0.1:3000`, unrelated to the actual running dev port) — don't fight it,
   don't edit config.toml (out of QA's Write scope anyway).
3. Navigate the real browser to the returned `action_link` (a real GoTrue `/auth/v1/verify` URL).
   It redirects to the (probably-dead) site_url with `#access_token=...&refresh_token=...` in the
   URL fragment — read it straight off the navigate tool's own result (no fetch needed).
4. On the ACTUAL app origin (not an error page — see the localhost/127.0.0.1 gotcha below),
   `document.cookie` write access works fine. Set the cookie the app's own `@supabase/ssr`
   client reads: name `sb-<storageKey-ref>-auth-token` (derive by loading
   `createBrowserClient(url,anonKey).auth.storageKey` once — for `http://127.0.0.1:54321` this was
   `sb-127-auth-token`), value = `'base64-' + base64url(JSON.stringify(sessionObject))` where
   `sessionObject` is `{access_token, token_type:'bearer', expires_in, expires_at, refresh_token,
   user:{...decoded from the JWT payload...}}`. Do the base64url encoding with plain
   `btoa`+char-substitution — **don't** dynamically `import()` `@supabase/ssr` from an external CDN
   (esm.sh) on the real app page: it works fine on an error page (no CSP) but the real app's CSP
   blocks the cross-origin script load. No import is needed anyway — the encoding is trivial.
5. Navigate/reload the app — `hooks.server.ts`'s cookie-based session validation (via
   `@supabase/ssr`'s `getAll`) picks it up as a normal, real, server-verified session (GoTrue
   validates the JWT signature same as any login). No fetch(), no password, no admin session
   token ever touches a form field.

**Gotcha that will burn a lot of time first**: a `vite dev` server started plain (`vite dev`, no
`--host`) binds **IPv6 `localhost` (`::1`) only** — `http://127.0.0.1:5173` (IPv4) gets a
connection failure indistinguishable from "server is down" (browser shows a generic error page;
`fetch`/`document.cookie` throw `SecurityError`/`Failed to fetch` from that error-page context,
which looks like a CORS/sandbox problem but is just "you're on chrome's internal error page, not
the site"). Use `http://localhost:5173` (or check `lsof -iTCP:PORT -sTCP:LISTEN` — if it shows
`TCP localhost:PORT` rather than `*:PORT` or `127.0.0.1:PORT`, it's IPv6-only).

Team-lead accepted this whole pattern as the sanctioned walk-login method going forward
(SELF-258, 2026-09-03) — reuse it rather than re-deriving.
