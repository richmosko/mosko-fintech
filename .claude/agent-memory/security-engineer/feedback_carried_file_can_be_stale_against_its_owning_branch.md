---
name: carried-file-can-be-stale-against-its-owning-branch
description: A branch carrying another in-flight branch's file must be diffed against THAT branch, not against main — and a brief's factual claim about the tree is a claim to measure, not a premise to confirm
metadata:
  type: feedback
---

When a review branch carries a file **another in-flight branch owns**, diff it against the **owning branch**, not against `main`. Against `main` it looks like a clean addition; against its owner it can be many commits behind — including behind the fixes I myself found and someone ruled.

**Why:** SELF-265 (2026-09-04) carried `104_fn_compute_tax_liability.sql` and an ADR-067 hunk owned by SELF-262. Not on `main` at all, so `git diff origin/main HEAD` showed a clean 725-line ADD. Measured against `origin/feature/self-262` it was **235/43 behind** and `DECISIONS.md` **12/4** behind — missing every E37 disposition of the SELF-262 Sec findings. Merging 265 first would have landed the un-fixed reader on `main`, and any later conflict resolution favouring "already on main" reverts the fixes silently. A correct fix lost to a merge, not to a decision.

**How to apply:**
- After the usual `git diff origin/main HEAD`, list `git branch -r` and, for every file in the diff that another branch also touches, run `git diff --stat origin/<my-branch> origin/<other-branch> -- <path>`. Non-empty = the branch carries a stale copy; say so with the line counts.
- To find the fix quickly across refs: `for r in $(git branch -r --format='%(refname:short)'); do git grep -c '<token>' $r -- <dir>; done`. A token present on one ref and absent on mine localises the delta in one command.
- Corroborating tell inside a stale carried file: a **count in its own prose** that a ruling already corrected (here, "all five callees were measured stable" after N-1 measured three). A stale count inside a carried blob is cheap confirmation the whole blob is stale.
- **Do not rank the merge-ordering options.** State the hazard, offer merge-first / copy-the-blob / drop-the-file, and require that whichever is taken, the result is verified **byte-identical to the owner's reviewed blob by `git diff`, not by inspection.**

**The root cause runs BOTH directions, and I hit both in one review.** Taking a claim about the tree from a *message* instead of from the *tree*:

- **Direction 1 — "this control exists."** The dispatch brief asserted `standard_deduction_ignored` was in `104`. I started to treat it as background to confirm and drafted a note about whether its *visibility* sufficed. One `grep -rn` returned **zero** — the control was on a different ref. Accepting it would have left F-1 unreported.
- **Direction 2 — "nothing moved."** After the branch moved, team-lead sent *"FYI, not a scope change … no file under review changed."* True of `api/`; **false** of `DECISIONS.md` (16 lines) and `104` (278 lines) — which were F-1's entire subject, and whose movement **CLEARED** it. Accepting it would have left me carrying a **cleared blocker** against a clean branch.

**A brief's factual assertion about the tree is a CLAIM, not a given** — and a *reassuring* claim ("nothing changed", "FYI", "not a scope change") is the more dangerous one, because it invites no work. On every branch-move notification: re-read the tip from the ref (it had moved **twice past** the sha the message named), run `git diff --stat <old-sha> <tip> -- <every path my findings cite>`, and re-verdict per finding rather than accepting the delta description. Grep every named identifier a brief asserts exists, in the same turn I first cite it.

**Corollary on my own artifact:** once a findings file is merged into the branch it reports on, it can go stale against that branch. Discharge with an **appended dated clearance block** (ref re-read + per-finding CLEARED/OPEN + the measurement), never by editing the finding — the original is the dated record of the review.

Related: [[feedback_read_the_branch_from_the_ref_not_the_worktree]] · [[feedback_review_the_delivery_note_against_the_ref]] · [[feedback_read_decisions_from_the_pr_branch_when_the_pr_edits_it]] · [[feedback_my_review_measurements_become_quoted_sources]]
