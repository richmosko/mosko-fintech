---
name: feedback-utc-vs-local-date-drift
description: dated three separate SELF-330 artifacts 2026-08-21 when local (repo-convention) date was 2026-08-20 — a systematic UTC-vs-local clock mismatch, not three independent typos
metadata:
  type: feedback
---

Wrote `2026-08-21` into a DESIGN.md section heading, and it recurred into two more places on the
same branch (a README cross-reference date, this fixture's own header) before Architect diagnosed
the CAUSE rather than just patching the symptom again: `local now: 2026-08-20 20:47 PDT` vs
`UTC now: 2026-08-21 03:47 UTC` — the repo's dating convention is unambiguously LOCAL (every commit
carries `-0700`), and something in my own process was producing/using a UTC-derived date instead.

**Why this matters beyond the one date:** three occurrences read as three independent slips until
someone checked the actual clock skew — at which point it was obviously one mechanism, not three
mistakes. The generalizable lesson (Architect's framing, and correct): a repeated "wrong by the
same amount, in the same direction" error across independent artifacts is a SYSTEMATIC cause, not
independent bad luck, and should be investigated as one the second time it appears, not patched
as a fourth typo.

**How to apply:** when dating anything in this repo (an ADR entry, a DESIGN.md section, a header
comment), do not trust an assumed "today" — cross-check against a REAL local timestamp before
writing it (e.g. `date` in the actual shell, or a recent commit's own `-0700` timestamp via
`git log -1 --format=%cd`), especially late in the day Pacific time when UTC has already rolled
to the next calendar date. If a date error recurs a second time in one session, stop and diagnose
the mechanism before fixing the third instance — grep the whole tree for the wrong date string
rather than waiting for someone else to find each occurrence one at a time.
