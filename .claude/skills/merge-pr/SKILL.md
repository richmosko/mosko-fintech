---
name: merge-pr
description: Merges an open PR to main on F/CTO sign-off, then syncs local main over SSH (HTTPS is a last-resort fallback for a blocked port 22 only). Handles doc-update PRs (phase/*, meta/* — the live flow) and feature PRs (feature/* — Phase 6+, Linear/QA-gated). Uses merge-commit style (--merge), not squash. Optional argument: PR number (defaults to the current branch's PR). Per ADR-009 Decision 9.
user-invocable: true
allowed-tools:
  - Bash
  - Read
---

# merge-pr — Merge an approved PR to main

Executes the merge of an open PR, then syncs local `main` and cleans up the branch. **Decision rights on merging stay with the F/CTO** — this skill runs the merge *after* explicit sign-off; it does not decide to merge. The companion to `/finish-doc-update` (doc PRs) and `/finish-feature` (feature PRs), both of which open a PR but deliberately stop short of merging.

mosko-fintech adaptation of `richmosko/project_template`'s `/merge-pr` per [ADR-009](../../../DECISIONS.md#adr-009) Decision 9 (selective-adoption framework, Decision 8). Differences from template:

1. **Merge style is `--merge` (merge commit), NOT `--squash`.** `main` preserves `Merge pull request #N from …` history (see #58 / #59 / #60). The template defaults to squash; mosko overrides to merge-commit to match its history and the explicit note in `/finish-doc-update` ("Do not propose `--squash` or `--rebase` unless explicitly asked").
2. **Documents the SSH deploy-key path** for the post-merge `git pull --ff-only` + local-branch sync, with a narrow HTTPS last resort (blocked port 22 only, per-use authorization) — same pattern as `/finish-doc-update`. The repo deploy key makes SSH the working path; HTTPS is no longer the expected route.
3. **Two-flow branch detection.** `phase/*` and `meta/*` branches are doc-update PRs — **the live flow** (no Linear, no QA handshake, no team teardown). `feature/*` branches are feature PRs — the fuller flow (QA sign-off gate + Linear "Done" + MILESTONES Active-Feature clearing + team teardown + release tagging). **The feature path is dormant until Linear activates at Phase 4** per [ADR-009](../../../DECISIONS.md#adr-009) Decision 7; in Phases 2–3 every PR is a doc update.
4. **F/CTO is the merge gate**, not qa-engineer sign-off (the template assumes the Implement/Validate loop). QA still gates feature PRs in Phase 6+, but doc PRs gate on the team-lead's diff read + the F/CTO's call only (there is no QA/Validate phase for doc-only PRs).

## Inputs

- `$ARGUMENTS` — optional PR number. If omitted, detect via `gh pr view --json number -q .number` on the current branch.

## Pre-flight

- **Confirm explicit F/CTO sign-off to merge.** Silence is not approval. If the F/CTO hasn't clearly said to merge this PR, ask before proceeding.
- **Detect the PR + branch type.** `gh pr view <pr?> --json number,headRefName,baseRefName`. Classify the head branch: `phase/*` or `meta/*` → doc-update flow; `feature/*` → feature flow.
- **Feature PRs only (Phase 6+):** confirm qa-engineer sign-off is explicit ("validate green" or equivalent) and, if the diff touched the security-controls catalog, that `/security-review` passed this loop. These gates do **not** apply to doc PRs.

## Steps

### 1. Verify merge readiness

```bash
gh pr view <pr-num> --json mergeable,mergeStateStatus,reviewDecision,statusCheckRollup
```

Abort with a clear message (don't pretend success) if:
- `mergeable != "MERGEABLE"` (conflicts — advise rebasing the branch on `main`),
- CI checks aren't green (`statusCheckRollup`),
- required reviews are missing (branch-protection `reviewDecision`).

### 2. Merge (merge-commit style)

```bash
gh pr merge <pr-num> --merge --delete-branch
```

`--merge` preserves the `Merge pull request #N from …` history `main` uses. `--delete-branch` removes the remote branch. **Do not** use `--squash` or `--rebase` unless the F/CTO explicitly asks.

### 3. Sync local main (over SSH)

**SSH is the working path — pull plainly.**

```bash
git checkout main
git pull --ff-only
```

A repo-scoped **deploy key** is configured for mosko-fintech in the shared git config (`core.sshCommand`, inherited by every worktree), so this works without a TTY. The passphrase-key problem the old HTTPS-first guidance existed for was solved on 2026-05-14.

⚠ **`Permission denied (publickey)` is NOT expected, and is NOT a cue to switch to HTTPS.** Verify the premise first — both checks are read-only and take seconds:

```bash
ssh -i ~/.ssh/id_ed25519_claude_mosko-fintech -o IdentitiesOnly=yes -T git@github.com
#   expect: Hi richmosko/mosko-fintech! You've successfully authenticated
git config --get core.sshCommand
#   expect: ssh -i ~/.ssh/id_ed25519_claude_mosko-fintech -o IdentitiesOnly=yes
```

If those succeed, the failure is something else — read the actual error. If `core.sshCommand` is absent (fresh machine, rotated key), run `/setup-claude-deploy-key`; that is the fix, not HTTPS.

#### HTTPS temp-switch — LAST RESORT, one failure mode only

**The deploy key cannot fix a blocked or timing-out port 22** — deploy keys still use port 22. On a hostile network or behind a corporate firewall SSH will **time out or be refused at the connection level** (distinct from being *rejected on authentication*), and HTTPS over 443 is the genuine answer. **That case is why this fallback is demoted rather than deleted.**

⚠ Note for the push-side sibling (`/finish-doc-update`): **HTTPS silently refuses pushes touching `.github/workflows/`**, because the `gh` OAuth token lacks `workflow` scope. A read-only `git pull` is unaffected, but do not carry the HTTPS habit back to a push.

With per-use authorization (each use gets its own approval):

```bash
git remote set-url origin https://github.com/richmosko/mosko-fintech.git
git pull --ff-only
git remote set-url origin git@github.com:richmosko/mosko-fintech.git
git remote -v   # confirm SSH restored
```

Always restore origin to SSH afterward, even on failure. The HTTPS form uses the gh CLI's stored credentials (system keyring), which Claude's bash can reach.

Then delete the local branch (it's merged + the remote is gone):

```bash
git branch -d <head-branch>
```

Use `-d` (safe; refuses if unmerged), not `-D`.

### 4. Feature-PR follow-up (feature/* only — Phase 6+; dormant until Linear activates at Phase 4)

Skip this entire step for `phase/*` and `meta/*` PRs.

- **Linear:** set the issue status to "Done"; add a final comment ("Merged in `<sha>`. Closing."). Parent cycle (sprint) + project (milestone) auto-track as constituent issues close.
- **MILESTONES.md:** move the feature from `### In Flight` to `### Completed` (Features) with merge date + PR link; clear `## Active Feature`; if the feature completed a sprint or milestone, update the matching `## Sprints` / `## Roadmap` row.
- **Release tagging (only if the PR completes a release milestone):** prompt "Tag this as a release? (recommended `vX.Y.Z`)". On yes: `git tag -a vX.Y.Z -m "…"` + `git push origin vX.Y.Z`, then `gh release create vX.Y.Z --generate-notes --draft --title "…"`, and hand off to the F/CTO to curate + **publish** (the lead does not publish on the F/CTO's behalf — release notes are a Principal decision). Add a `## Releases` row. **Process milestones (M0/M1) are internal phase gates and typically are NOT tagged.**
- **Team teardown:** once the lead has decided the next move, tear down the Implement team (the shared task list disappears with it — durable state must already be in MILESTONES.md / Linear).

### 5. Doc-PR / phase-transition follow-up (phase/*, meta/*)

This skill does **not** auto-edit state files. If the merged PR materially changed project state (new phase entry, a locked decision, a new artifact), the **team-lead** lands the companion updates via a subsequent `/start-doc-update meta/<slug>` cycle — mirroring the "After-merge follow-up" section of `/finish-doc-update`:

- `MILESTONES.md` → Current Phase / Recent activity,
- `DECISIONS.md` → a phase-gate-approval ADR if applicable (consolidation vs terse per ADR-009 Decision 8).

Merging *this* PR does not trigger those automatically — they are deliberate, separate edits.

### 6. Hand off

Report the merge SHA + confirm `main` is synced and the branch is cleaned up. Then ask the team-lead (the main session) for the next move. For doc PRs the lead reads MILESTONES.md and picks the next deliverable; for feature PRs the lead picks the next feature, plans the next sprint, or escalates a phase transition.

## What this skill does NOT do

- **Decide to merge.** The F/CTO authorizes each merge; this skill executes it.
- **Auto-merge on CI-green.** Would cross the "don't merge unilaterally" line.
- **Watch CI.** Out of scope — verify once in step 1; if checks are pending, wait and re-run or abort.
- **Publish releases.** Drafts only; the F/CTO curates + publishes.
- **Bump WORKFLOW.md version or write ADRs.** Those are separate, deliberate edits (flag them as follow-ups).

## Failure modes

- **No explicit F/CTO sign-off:** stop; confirm before merging.
- **`mergeable != MERGEABLE`:** surface the conflict; advise rebasing the head branch on `main` (the branch owner does this, not `merge-pr`).
- **CI not green / required reviews missing:** surface verbatim; do not merge.
- **`git pull` fails (`Permission denied (publickey)`):** NOT expected and NOT a cue to switch to HTTPS. Verify the deploy key first (`ssh -T` + `git config --get core.sshCommand`, step 3); if it checks out, read the actual error. Reach for HTTPS only on a connection-level timeout/refusal (port 22 blocked).
- **`git branch -d` refuses (unmerged):** investigate before forcing — do not jump to `-D`. Usually means the local branch has commits the merge didn't include (e.g., the PR merged a different head); reconcile first.

## Notes

- Closes the dangling `/merge-pr` reference that `/finish-doc-update` and `/start-doc-update` pointed at before this skill existed — the merge step is now a real skill rather than a bare `gh pr merge` instruction.
- Merge-commit (`--merge --delete-branch`) is mosko's house style on `main`; the template's squash default is the deliberate divergence.
- The HTTPS temp-switch needs per-use authorization every time — the credential/network environment can differ between sessions. It is a last resort for a blocked port 22, not the expected path; `/setup-claude-deploy-key` is what fixes an actual key problem.
- This skill is mosko-fintech-specific. Repo URLs, branch conventions, the merge style, and the push/pull guidance live with this repo. A different repo running the template would have its own version.
