---
name: page-svelte-ahead-of-backend-loader
description: Established precedent — author +page.svelte against a proposed contract before Backend's +page.server.ts loader lands, rather than blocking on it.
metadata:
  type: feedback
---

Writing a route's `+page.svelte` before Backend's paired `+page.server.ts` loader exists is a
validated pattern in this codebase, not a boundary violation to avoid. `+page.server.ts` stays
strictly Backend-owned (tool-boundary rule, unchanged) — this is about sequencing, not authorship.

**Why:** confirmed twice now — `settings/allocation/+page.svelte` (SELF-242) was authored and
merged with its own header stating "Backend-owned, NOT YET LANDED as of this file's authoring,"
and I repeated the same move for `allocation/us-equity/+page.svelte` (SELF-241) when Backend's
loader for that route didn't exist yet, even though the underlying query layer
(`loadUsEquityAllocation`, SELF-240) was already fully built and tested server-side. Blocking on
the loader would have stalled UI work that had everything else it needed.

**How to apply:**
- Only do this when the underlying server *query/read layer* the loader would call already
  exists (verify live — don't assume). If the read path itself doesn't exist, that's the real
  Step-0 STOP condition, not the thin loader-wiring file.
- Import `PageData` from `./$types` as normal (not a hand-typed prop shape) — `npm run check`
  will surface real, expected `Property 'X' does not exist on PageData` errors until Backend
  lands the file. That's the correct, visible signal — don't work around it with `any` or a
  parallel type.
- Document an "EXPECTED CONTRACT" block in the file's own header: exact field names/types, which
  existing loader read they should reuse (don't let Backend duplicate a query that already
  exists), and null-on-failure semantics matching this repo's fail-soft convention.
- Report the missing loader as a **bubble-up blocking gap** at hand-off, not as "Broken" —
  it's expected, not a regression; state exactly what file Backend needs to add and give the
  contract shape so it's fast to land. See [[project_self229_composition_leaf_staleness_blocker]]
  for the sibling pattern of "loader join, not a migration."
