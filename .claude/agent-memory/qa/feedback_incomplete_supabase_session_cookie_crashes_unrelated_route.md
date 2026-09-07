---
name: incomplete-supabase-session-cookie-crashes-unrelated-route
description: A hand-built sb-127-auth-token cookie with only access_token/refresh_token/expires_at (no token_type/expires_in/user) causes a real 500 in unrelated server code, not the auth check itself — verify against a full session before reporting a defect.
metadata:
  type: feedback
---

During the SELF-354/355/357/360/356/358 V1.5 browser walk (2026-09-06/07), authenticating a
brand-new synthetic user via `cookieStore.set()` with a minimal session object
(`{access_token, refresh_token, expires_at}`) produced a real, reproducible 500:
`GET /mfa/step-up` → `TypeError: Cannot read properties of undefined (reading 'factors')` inside
`SupabaseAuthClient._getAuthenticatorAssuranceLevel`. This looked like a genuine product defect
(a brand-new user hitting a crash on first navigation) and I almost reported it as one.

**Root cause, confirmed empirically**: the crash was MINE, not the product's. Supabase-js's
server client expects the FULL session shape it itself would produce
(`access_token, token_type, expires_in, expires_at, refresh_token, user`) — the `user` object is
what `_getAuthenticatorAssuranceLevel` reads `.factors` off of. Omitting it left `user`
`undefined` inside the library, which threw from otherwise-unrelated code three call-frames away
from anything resembling an auth check. Rebuilding the cookie with the complete shape (fetch
`/auth/v1/user` with the access token, splice the result in as `user`) made the exact same route
load cleanly on the exact same fresh account.

**How to apply**: whenever hand-constructing a `sb-127-auth-token` cookie via `cookieStore.set()`
for a walk/test session (see [[reference_magic_link_cookie_login_for_live_walks]]), always build
the FULL session object — never just the three token fields. If a walk hits a crash right after
setting a hand-built cookie, suspect the cookie's own shape FIRST (rebuild it complete and retry)
before writing up a product defect. This is the same discipline as
[[feedback_pattern_match_to_past_incident_verify_current_state]] — a crash that pattern-matches
"bug" needs the mechanism traced (here: read the actual server log stack trace) before it's
reported as one.
