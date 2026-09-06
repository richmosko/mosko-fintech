---
name: pass-if-absent-substitutes-a-path-convention
description: A pass-if-absent fence designs out a SEQUENCING convention and quietly substitutes a PATH convention — same rot class, one level down; discover the target, don't pin it.
metadata:
  type: feedback
---

A fence ruled **pass-if-absent** so that an ordering constraint "disappears rather than
being remembered" still hardcodes WHERE the target will appear. That is a **path
convention with no mechanism** — the exact failure class the pass-if-absent shape was
adopted to avoid. If the builder of the future target picks any other path, the fence
reports "target absent — pass" forever, green, with nothing observing it.

**Why:** SELF-350 A6 (PR #630). R6 rider 2 designed out the A4 sequencing edge on the
stated ground that *"a sequencing constraint stated in an AC is a convention with no
mechanism, and conventions with no mechanism rot silently."* The job then invoked the
fence on a single hardcoded `workers/pdf-render/package.json`. Measured: fence exits 0
on the absent path; `workers/pdf-render/` exists with no manifest. A4 shipping
`workers/pdf-render/app/package.json` voids the whole production leg silently.

**How to apply:** whenever a fence is pass-if-absent, ask *what names the target?*
Require **discovery** (`find <dir> -name <file> -not -path '*/node_modules/*'`, loop),
not a pinned path — discovery preserves pass-if-absent (zero found ⇒ pass) and makes the
fence bite on whatever path the future issue chooses. Pair with [[probe-that-only-asserts-failure-goes-vacuous]]:
a pass-if-absent leg and an `rc != 0`-only inversion leg are the same vacuity from
opposite ends — one can never fire, the other can never distinguish why it fired.
Also: the inversion step must assert the OUTPUT TOKEN, because a fail-closed fence
returns the same non-zero rc for "caught the violation", "fixture JSON is malformed",
and "the interpreter is missing" (all three measured at rc=1 here).
