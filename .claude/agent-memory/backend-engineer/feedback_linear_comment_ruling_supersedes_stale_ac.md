---
name: feedback-linear-comment-ruling-supersedes-stale-ac
description: A Sec/Architect ruling posted as a Linear COMMENT on a later issue can supersede that issue's own AC text without the AC text ever being edited — always pull comments, not just the description, when an AC looks schema-impossible or duplicative of already-shipped work.
metadata:
  type: feedback
---

On SELF-242 (2026-08-20), the team-lead's task brief handed me Linear ACs verbatim: AC #3 described the write as a "keyed array of {user_taxonomy_id, pct_target} pairs" and AC #7 named the route `POST /api/settings/allocation`. Neither matched the codebase: SELF-233 had already shipped a SINGULAR `POST /api/settings/planning-target` endpoint, and its own code comment said SELF-242 "does not re-implement" it.

Routing the ambiguity through `linear-liaison` to pull SELF-242's full comment thread (not just its description) surfaced the resolution: a 2026-08-17 comment on SELF-242 itself, quoting Sec's binding ruling from the SELF-233 joint review, stated explicitly "242's share is the editor consuming SELF-233's hardened endpoint + this DELETE, not re-implementing validation." The issue's AC #3/#7 text was never edited to match — the ruling lives only in a comment, dated AFTER the AC text was drafted.

**Why:** Linear ACs are written once (often by PM, early) and issues get ratified/re-scoped later via comments rather than by editing the AC list in place — the AC text is not automatically kept in sync with later binding rulings. A brief that hands you "verbatim ACs" is handing you the ORIGINAL draft, not necessarily the current scope.

**How to apply:** When an AC looks schema-impossible, duplicative of something already shipped, or otherwise surprising given the current tree state — before implementing to the letter, pull the ISSUE'S OWN COMMENTS (and comments on directly-related issues, e.g. the sibling ticket the current one "consumes") via `linear-liaison`, not just the description/AC block. A later comment carrying a role-authoritative ruling (Sec veto, Architect flag) wins over older AC prose. Report the reconciliation to team-lead as a bubble-up finding rather than silently building to either the stale AC or the comment alone — the AC text itself is not mine to edit (Linear scope-change is F/CTO/PM territory), so the discrepancy stays on the record.

See also the user's global memory `feedback_pm_draft_ac_vs_schema.md` (schema-infeasible ACs generally) — this is the comment-thread-specific corollary: the AC can be stale even when it IS schema-feasible, because a later ruling narrowed scope after the AC was written.
