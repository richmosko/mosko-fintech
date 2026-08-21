---
name: repo-runs-on-local-time-agents-read-utc
description: Datestamps written into repo prose keep coming out one day ahead — agents read a UTC clock while the repo's commits are local (-0700); treat a wrong date as systematic, never as a typo
metadata:
  type: reference
---

**The repo runs on LOCAL time; agents write dates from a UTC clock.** Measured at
SELF-330 close:

```
local now:  2026-08-20 20:47 PDT
UTC now:    2026-08-21 03:47 UTC
```

Every commit carries `-0700` (e.g. `47c1ec2` at `2026-08-20 20:20:12 -0700`), so
**local is the repo's convention** and a UTC datestamp in prose sits a **calendar
day ahead of the commit that introduced it**. Anyone reconciling the two later
reads a document dated after the change it describes.

⚠ **The operational point is not the offset — it is that I mis-diagnosed it three
times in one evening.** Three separate agents wrote `2026-08-21` (a `DESIGN.md`
heading, four datestamps across three frontend files, a fixture header). I
corrected each as an isolated slip. **Three agents do not independently mistype
the same wrong date.** Any evening-hours date that is one day ahead is this, and
it recurs on every branch until agents are told which clock to read.

**How to apply:** when drafting or reviewing prose datestamps, take the date from
`date '+%Y-%m-%d'` (local), never from a UTC source, and never from a CI log
timestamp — GitHub Actions logs are UTC, so an evening run reads as tomorrow.
When you see a wrong date, **check the offset before calling it a typo**; and
after correcting one instance, **re-grep the whole branch** rather than the file
you were looking at — my "all future dates gone" claim was scoped to three files
and one instance shipped at HEAD in `supabase/tests/README.md`.

Related: [[feedback_state_what_the_count_is_over]] (a claim scoped to three files
does not characterise a branch), [[feedback_conditional_rearmed_by_transcription]]
(fan-out as the tell that something is systematic rather than incidental).
