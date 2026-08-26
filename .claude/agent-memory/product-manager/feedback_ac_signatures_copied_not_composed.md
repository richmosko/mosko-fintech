---
name: ac-signatures-copied-not-composed
description: Never compose a DB signature in an AC — copy it verbatim from the migration or mark SIGNATURE-PROVISIONAL; a parameter list is a capability claim.
metadata:
  type: feedback
---

An AC that names a database function/column signature must either (a) copy the signature verbatim from the migration file, citing the migration number, at drafting time, or (b) if the object doesn't exist yet, name behavior only ("the whole-user staleness primitive from SELF-208") plus a `SIGNATURE-PROVISIONAL` marker that must be resolved at promotion-to-Linear (milestone-rotation per ADR-017 D2 is the re-check gate).

**Why:** I invented `fn_aggregation_has_stale_constituent(p_users_id, p_scope_filter)` in two consecutive issues (SELF-223 caught by reconciliation, SELF-229 caught by team-lead) — the real 046 function is zero-arg, caller-scoped via INVOKER + auth.uid(). Third instance: SELF-228's drafted ACs cited `p_scope '{}'::pfin.scope[]` — a type that never existed and a param ratified OUT (049-R2/051-A1/052); I ran the reconciliation side (2026-08-15), rule held. A composed parameter list isn't just wrong syntax: it's a **capability claim** (per-scope filtering that doesn't exist) that downstream engineers may build against. Two reconciliation moves that generalize: (1) an intent like "filter by scope" that has no param reconciles to an application-query-layer assertion (join to the attribute column), per SECURITY §4.1 axis-ii; (2) check the SUBSTRATE — a per-scope assertion is only constructible on leaf surfaces, not on functions reading a pre-aggregated store (nav_daily), where "full-household" is by construction. Related: [[scope-ac-invariants]].

**How to apply:** Whenever drafting or promoting an AC that names anything with a signature, grep the migration first. If drafting ahead of schema, write behavioral language and the provisional marker; the promotion step clears the marker against real DDL or the AC doesn't promote.

**4th instance (2026-08-26, SELF-340) — the class extends beyond signatures to PRIMITIVES QUOTED FROM THE PRD.** I built an options-brief lean on "delete-is-implicit-skip" as the V1 remedy path because PRD §2.4.3 describes it (Axis C1, skip_flag, deleted/skipped view). The primitive NEVER SHIPPED — ADR-032 eliminated it; `skip_flag`'s only tree occurrences are prose asserting its absence. Architect's grep caught it; the lean survived only because it was written as a conditional gate. Rule extension: a PRD-quoted mechanism made load-bearing in ANY deliverable (not just ACs) gets grep-verified against migrations/api-src first — the PRD-predates-GL class means PRD prose is a claim about intent, never about the substrate.
