---
name: gl-taxonomy-split-ratified
description: The 2026-08-18 F/CTO-ratified asymmetric split of user_taxonomy into a storage spine + posting_prototype — SHIPPED 2026-08-20 as migration 084 (PR #507, Sec GREEN): posting_prototype live, ids preserved, ADR-058 Accepted + Amendment 1. Read ADR-058 live; this memory is the pointer.
metadata:
  type: project
---

**ADR-058 authored into `DECISIONS.md` at PR #499 (2026-08-19) and the DDL SHIPPED at PR #507 (2026-08-20, migration `084`): `pfin.posting_prototype` + `posting_prototype_default` are LIVE on main, ids preserved via the offset+maxvalue pair, D3 #10/#13 re-targeted labels-kept, ADR-058 Status = Accepted with Amendment 1 (3 items). Read the ADR and the migration live — do not reason from this file.** [Supersession note 2026-08-20: this file's prior 'NO DDL exists yet' claim went stale at PR #507; the departing split-arc Architect corrected it pre-shutdown, team-lead's cleanup accidentally discarded that edit, and this is the reinstatement.]

**One-line shape, only so you recognise the ADR when you find it:** `pfin.user_taxonomy` keeps its name / ids / asset rows and drops `domain`; cashflow rows move to a new `pfin.posting_prototype` with **original ids preserved**. Ratified order is **rename → split → `element`**, three separate PRs.

**How to apply.** Read ADR-058 for every detail (the id mechanism, the `element` value set, the write posture, Sec F1–F11). The follow-ups have tracked homes now: **BACKLOG §7.24** (five items) + **§5.3** (GL-native P&L, V2) + **§7.13 / §5.7** closure annotations. ⚠ **Before authoring any DDL:** Sec F2's four row counts against production-shaped data, recorded in the migration header, non-zero disposed by F/CTO first — a precondition on AUTHORING, not on landing.

⚠ **ADR-011 Decision 3's `#10` / `#13` / `#17` amendments ride the DDL PR, not a doc-PR** — the Sec pin (transcribed verbatim inside ADR-058 Decision 5) says so. Landing them early or late both break the read-Decision-3-live discipline.

⚠ **Two things that will read as bugs and are not:** `Securities Sold Short` is ratified (ADR-031 Amendment 1 item 7) and appears **nowhere in the tree** — shorts route to Suspense; and after the split **two `element` vocabularies exist** (reporting bucket vs ledger account), **not required to agree** — a short is `asset` on one and `liability` on the other. Never "reconcile" them by joining.

⚠ **`api/src/lib/server/queries/taxonomy.ts` rides the split migration's PR** (Sec F3, a named exception to no-bundling): its `onConflict` names `domain` and every failure path is fail-soft, so the migration alone silently provisions new users with nothing.

Related: [[ratified-name-is-not-a-built-table]] · [[no-concept-exists-check-deferred-decisions]] · [[join-key-decides-failure-direction]]
