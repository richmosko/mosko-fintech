---
name: feedback-rediff-source-before-reverify
description: When asked to re-confirm a test result against "current" code, diff your local copy against the authoring teammate's live worktree BEFORE re-running — don't just re-run and assume your copy is current. Confirmed by architect as the step that made a re-verification worth anything.
metadata:
  type: feedback
---

Architect asked for a fresh re-verification of 34 pytest tests because two
concurrent changes had landed in Backend's `run_nav_backfill.py` since my
last confirmed green run. Before re-running, I re-diffed my QA-worktree
copies of both `run_nav_backfill.py` and `nav_backfill.py` against Backend's
worktree — zero delta — THEN ran the suite.

Architect's framing, unprompted praise for a step I did on my own judgment
(not because it was asked for): *"Without it, 'I tested Architect's copy'
and 'I tested the current code' are two different claims that happen to
coincide most of the time. You closed that gap unprompted."* Separately,
architect verified the same equivalence one hop further downstream — after
committing, confirmed the committed bytes matched what I'd executed via
`git diff HEAD` being empty in their own worktree — closing the full chain
from "what QA ran" to "what's on disk in every worktree" to "what's
committed."

**Why this matters structurally:** in a three-way loop (QA tests, Backend
edits, architect commits), a stale local copy passing tests is
indistinguishable from a current one passing tests — pytest can't tell you
which file it read. The only way to make "I re-verified" mean "I verified
the CURRENT thing" instead of "I verified A thing" is an explicit diff
against the authoring party's live source, taken in the same turn as the
run, not assumed from a prior sync.

**How to apply:** whenever a re-verification is requested specifically
*because* the artifact under test may have moved since the last green run,
diff against the authoring teammate's current worktree first and report
that the diff was empty (or note what changed) as part of the confirmation
— not just the fresh pass count. This is the same discipline as
[[feedback_which_ref_the_probe_was_aimed_at]] and
[[feedback_relay_from_the_tree_not_the_report]] applied to test inputs
rather than git refs: name what you diffed against, not just that you
re-ran.
