---
name: feedback-build-ahead-of-migration-default-nullable
description: When building a client type against a ratified-but-unmigrated DB contract, default every field the AC text is silent on to nullable; only narrow to non-null where the AC text (or the merged migration) explicitly guarantees it.
metadata:
  type: feedback
---

When team-lead routes a UI task with "don't block on the migration — build against the ratified contract," type the shared client-side row shape defensively: any field the AC/contract text doesn't explicitly call non-null gets `T | null`. Narrow to non-null only for fields the text states outright (e.g. "cpi_basis_period is non-NULL on all three rows even when cpi_unavailable is true").

**Why:** Validated twice in one session (SELF-222's NavDeltaPanel: 071→072 added `delta_inflation_adjusted_percent`; SELF-223's NavReferenceDatesPanel: authored pre-073, reconciled post-merge). Both times, Backend independently drafted the same type from the same ratified text and it matched my defensive draft field-for-field except where the real migration later corrected ONE field backend had also gotten conservatively nullable and then had to narrow post-merge-verification (SELF-223's `cpi_any_carried`/`cpi_unavailable`, corrected to plain `boolean` after Backend read the applied 073 body). A defensive nullable default costs nothing when later narrowed (predicates using `=== true` degrade gracefully to a plain truthy check); assuming non-null and being wrong would have crashed or silently mis-rendered.

**How to apply:** At the next "build ahead of the migration" task, write the interface nullable-by-default, add a one-line comment naming it a "contract-text inference, reconcile against the live migration," and expect a small doc-only (not structural) reconciliation commit once the real DDL lands — that's the expected, cheap outcome, not a sign the original typing was wrong.
