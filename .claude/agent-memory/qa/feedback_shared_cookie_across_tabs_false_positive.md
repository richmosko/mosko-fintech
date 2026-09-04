---
name: shared-cookie-across-tabs-false-positive
description: "⚠ Browser cookies are domain-scoped, not per-tab or per-port — two tabs open to different ports of the SAME hostname (e.g. localhost:5174 twice) share ONE cookie jar. Logging in tenant B in tab 2 after tenant A in tab 1 silently overwrites tab 1's session too. Nearly reported a false critical cross-tenant-write finding because of this, SELF-265 re-walk 2026-09-04."
metadata:
  type: feedback
---

Setting up a two-tenant cross-tenant test with TWO browser tabs, each cookie-injected
as a different synthetic user (tenant A in tab 1, tenant B in tab 2, both on
`localhost:<port>`), I ran a cross-tenant probe from "tab 2 as B" against tenant A's
schedule and got a **200 success** — apparently proving Tenant B could overwrite
Tenant A's row. This looked like a severe, confirmed RLS/tenant-isolation bypass.

**It was not real.** `document.cookie` (and the Cookie Store API) scope by DOMAIN
only — never by port, and never by tab. Setting tenant A's session cookie in tab 1
had already overwritten the SAME cookie name tab 2 was relying on (both tabs share
one cookie jar for hostname "localhost", regardless of port). By the time I ran the
"tenant B" probe in tab 2, that tab's fetch() calls were silently authenticated AS
TENANT A — so the "cross-tenant write" was actually A overwriting its own row
(200, correctly), and re-testing under VERIFIED identity (fetch the page first,
regex the rendered email out of the HTML, confirm it matches the tenant you intend)
showed the real, correct behavior: 404 not_found, zero write, DB unchanged in both
directions.

**How to apply — do this EVERY time before trusting a cross-tenant probe result in a
multi-tab setup:**
1. Right before firing the probe, in the SAME script (no other tab's action allowed
   to interleave), explicitly RE-SET the intended tenant's cookie.
2. In that SAME script, fetch a page that renders the signed-in identity (e.g. the
   top-nav email) and assert it matches the tenant you intend to test as, BEFORE
   drawing any conclusion from the probe's result.
3. Never trust "I set this tab's cookie earlier in the session" — a LATER cookie
   write in ANY other tab on the same hostname may have silently clobbered it.

This is a general trap, not specific to this app: any dev-loop with multiple
synthetic tenants open in sibling tabs of the same browser profile is exposed to it.
See [[reference_migration_up_include_all_for_live_walk]] for the companion
cookie-login setup this trap showed up during.
