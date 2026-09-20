---
name: a-gate-measured-against-main-expires-when-main-moves
description: A merge gate phrased as a diff against origin/main is a snapshot, not a verdict — when main moves the same command flips, and a modify/delete conflict can arrive whose tempting resolution is the harm the gate existed to prevent.
metadata:
  type: feedback
---

**The rule.** A gate of the form *"`git diff origin/main <tip> -- <path>` must be empty"* is
**scoped to the `main` sha you ran it at**. Name that sha in the verdict, and re-run the gate in
the same turn as the merge. Never report such a gate as simply "met".

**Why.** Measured across one review of PR #636 / `feature/self-355-db-qa` (2026-09-06).

I ran the gate at `879b03a` and it was **empty** — because `main` did not yet carry
`supabase/tests/rls/111_audit_log_rls.sql`. I reported "M-2 gate met." Then #636 merged
(`e3546ab`) and `main` gained the clearance battery. The identical command against the branch now
reported a **deletion**. Nothing on the branch changed; the baseline moved beneath a verdict I had
already shipped as durable. This is [[the-instrument-cannot-observe-the-property]] arriving in a
gate rather than in a measurement, and [[which-ref-the-probe-was-aimed-at]] is the fix: my claim
was ref-scoped and I did not say so.

**⚠ The second half, which is the part worth carrying: what a moved `main` turns the gate into.**

Once `main` gained the file, the branch's situation became **modify/delete**:

- `git merge-base origin/main 2fe5092` = `49a26f4`, which **contains** the file;
- the branch **deletes** it (`git log --oneline --diff-filter=D <base>..<tip> -- <path>`);
- `main` carries a **different, newer** version.

`git merge-tree --write-tree --name-only origin/main <tip>` returned
`CONFLICT (modify/delete): … deleted in <tip> and modified in origin/main.` **Git halts loudly,
which is the good news.** The bad news is that the branch commit's own subject line read
*"drop stale 111 battery copy"* — i.e. **the conflict resolver is handed an instruction to take
the deletion**, and taking it would have removed the 36-leg VETO-1 clearance battery from `main`.
The exact harm the gate existed to prevent, re-entering as a plausible conflict resolution instead
of as a silent overwrite.

**How to apply.**

- For any "must this file survive the merge" question, the instrument is
  `git merge-tree --write-tree --name-only <main> <tip>`, **not** a two-way `git diff`. A two-way
  diff answers "do these two trees differ", which is not the merge outcome — see
  [[read-the-branch-from-the-ref-not-the-worktree]] on diffs answering the wrong question.
- Check the **merge-base** for the disputed path. A branch deletion is a no-op if the base lacks
  the file and a conflict if the base has it — opposite outcomes from identical branch content.
- **Read the deleting commit's subject line as part of the hazard.** A commit message that sounds
  like a standing instruction ("drop stale X") is what the resolver will act on. When the branch's
  cleanup has been discharged elsewhere, the fix is usually to **drop that commit** on rebase, not
  to resolve its conflict.
- Restate the gate with its baseline and its re-run requirement, e.g. *"empty against the `main`
  sha at merge time, re-run in that turn"* — a gate that can silently expire is a convention with
  no mechanism.

**⚠ IT MOVED THREE TIMES IN ONE SESSION, AND ONCE *BETWEEN TWO COMMANDS IN THE SAME TURN*.** During
the #641 re-confirm, my first command printed `origin/main` at `1afe807`; a later command in the
same turn returned an **empty** `git diff --stat origin/main <head>` where minutes earlier it had
returned 9 files / +3038. The branch had not drifted — the PR **merged** mid-turn, so `main`
absorbed the content. **The only reason I caught it is that the number was implausible and I
re-measured instead of reporting it.** A plausible wrong number would have shipped. *"Re-read the
ref in the same turn as the claim"* is not strong enough during an active merge window: **re-read
it in the same COMMAND as the claim**, or print the sha beside every number.

**⚠ AND A SHA NAMED IN A REQUEST MAY BE A DIFFERENT BRANCH'S TIP.** The same review asked me to
grade `3f65ce0`; `gh pr view <n> --json headRefOid` returned `d5aeacc` on a *differently-named
branch* (`feature/monthly-report-rpcs-112-115` vs `feature/self-355-db-qa`), with `3f65ce0` an
ancestor. Same content lineage, different objects. **Resolve the PR head from `gh`, never from the
sha in the message, and when they disagree grade BOTH rather than pick** — picking is where a
graded-the-wrong-tree finding comes from. Related: [[anchor-confirm-requests-to-a-sha]].

**Companion, same review: name a prediction that failed, not just a measurement that changed.** I
predicted CI would red a dblink leg because the CI lane used the same stack shape as the local one.
CI went green and the battery merged byte-identical. The prediction was wrong; the useful half of
that analysis was the veto boundary I set around `dblink_connect_u` and superuser elevation, which
held. **Environment-shaped failures are local-until-measured** — see
[[dblink-in-a-test-is-a-privilege-boundary]]. State a reading as a reading, and let the CI run
decide.

**⚠ "CI GREEN ON THIS TIP" IS NOT EVIDENCE ABOUT THE MERGE RESULT — run `git merge-tree` as a standing
part of every PR review (PR #833 r2, 2026-09-19).** The branch was reported CI-green and was; it was
also **4 commits behind main** and conflicted on merge. CI runs on the branch tip, which is a different
tree from the one that will land. `git merge-tree $(git merge-base <main> <tip>) <tip> <main>` piped to
`grep -c '<<<<<<<'` is one command and answers it.

**The recurring conflict site in this repo is `MILESTONES.md`'s recent-activity list** — both sides add
a bullet at the top and both delete the 6th, so any two same-day PRs collide there. When reporting it,
say what the resolution must preserve, not just that it conflicts: **the list stays at 5 AND the
`AUTOLOAD-CUTOFF` marker survives** (the SessionStart hook keys on that marker; a
slice-to-the-next-heading resolution eats it and every future session silently loads the wrong thing).

**Also check, same command, same moment:** whether the branch carries the ADRs its own new text cites.
#833 linked `#adr-073` while its own `DECISIONS.md` predated ADR-073 — harmless post-merge, but it
means **any substring test of a quoted ADR clause must be aimed at MAIN, not at the branch.** I aimed
one at the branch first and got a false negative that would have had me tell Architect their ADR text
was missing. See [[feedback_which_ref_the_probe_was_aimed_at]].
