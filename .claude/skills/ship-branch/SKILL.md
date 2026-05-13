---
name: ship-branch
description: Open a pull request from the current feature branch to `main`, following mosko-fintech's PR conventions — semantic branch names (`phase/<N>-<descriptor>` or `workflow/<descriptor>`), templated PR body grounded in actual diff, SSH→HTTPS push fallback with per-use authorization, no auto-merge. Use when the user asks to "ship this branch", "open a PR", "push and PR this", or any variant requesting the current branch land on `main` via pull request.
user-invocable: true
allowed-tools:
  - Bash
  - Read
---

# ship-branch — Open a PR from the current branch to main

Encodes mosko-fintech's PR workflow so every merge follows the same shape: semantic branch name, templated PR body anchored in the actual diff, SSH→HTTPS push fallback that asks before applying, and PR-URL hand-off without auto-merge.

## How to run

### 1. Pre-flight checks

Run in parallel:

- `git branch --show-current` — confirm not on `main`.
- `git log main..HEAD --oneline` — confirm at least one commit ahead of `main`.
- `git status` — working tree must be clean. Uncommitted changes block the push.
- `git remote -v` — note the current origin URL (will usually be SSH).

Bail with an explanation if: on `main`, no commits ahead of `main`, or uncommitted changes are present. Surface and ask the user — don't "fix" silently.

### 2. Branch-name sanity check

mosko-fintech's branch convention (verifiable via `git log --oneline -20` on `main`):

- `phase/<N>-<descriptor>` for phase-level work — e.g., `phase/1-step-3-script-audit`.
- `workflow/<descriptor>` for `WORKFLOW.md`, hooks, skills, or operational changes — e.g., `workflow/v1.5-reorient-prompt-fix`, `workflow/ship-branch-skill`.
- Plain descriptor for one-off changes (rare).

If the current branch name matches `claude/*` (auto-generated agent-worktree name) or otherwise doesn't fit the convention, propose a semantic name and ask the user to confirm before renaming:

```
git branch -m <new-name>
```

If already semantic, proceed.

### 3. Push to origin (SSH→HTTPS fallback)

Attempt the SSH push first:

```
git push -u origin <branch>
```

If it fails with `Permission denied (publickey)`, do **not** retry. Surface the failure and propose the HTTPS temp-switch, asking explicitly for per-use authorization (matches the project's SSH-fallback policy — each push gets its own approval). On approval:

```
git remote set-url origin https://github.com/richmosko/mosko-fintech.git
git push -u origin <branch>
git remote set-url origin git@github.com:richmosko/mosko-fintech.git
```

Always restore origin to SSH after the push, even on push failure. Confirm restoration via `git remote -v` before continuing.

### 4. Open the PR

Use `gh pr create` with a templated body. Title from the most recent commit subject; if the branch has multiple commits with mixed scopes, ask the user for a title rather than guessing.

PR body skeleton:

```
## Summary

- (1–3 bullets — what this PR does, not how)

## Motivation

(One paragraph — why this PR exists. Cite the triggering ADR, incident, or session handoff if applicable. Skip this section for trivial PRs.)

## Files changed

- `path/to/file` — (one-line description of what changed)

## Test plan

- [ ] (manual or automated check)
- [ ] (another check)

## Follow-ups

- (queued companion PRs or downstream work, if any)
```

Ground every section in actual diff:

- File list: pull from `git diff --stat main..HEAD`.
- ADR references: scan `git log main..HEAD` and the diff for `ADR-NNN` mentions; include only what's present, don't invent.
- Test plan: derive checks from what changed (e.g., a hook change → "open a new session, verify hook fires"; a `DECISIONS.md` change → "read ADR end-to-end, confirm no embedded architectural decisions in a PRD-scoped ADR").

Include the Claude Code attribution footer that other PRs on this repo use.

### 5. Hand off the PR URL

`gh pr create` prints the PR URL on success. Surface it to the user. **Do not auto-merge.** Decision rights on merging stay with F/CTO.

## What this skill does NOT do

- Auto-merge after CI passes — would cross the "don't merge unilaterally" line. The follow-up `gh pr merge --merge --delete-branch` is a separate operation triggered by F/CTO sign-off.
- Watch CI status — out of scope.
- Pull `main` and clean up the local branch after merge — that's a sibling operation, not part of "ship the branch."
- Bump `WORKFLOW.md` version or write ADRs — those are separate, deliberate edits. If the PR's content materially changes project state (new phase entry, locked decision, new artifact), call out the missing `WORKFLOW.md` companion under "Follow-ups" in the PR body.

## Notes

- `gh pr merge --merge --delete-branch` is the merge style used on `main` (preserves `Merge pull request #N from …` history). Do not propose `--squash` or `--rebase` unless explicitly asked.
- The HTTPS temp-switch needs per-use authorization every time — the user's network and credential environment can differ between sessions, and the SSH-fallback memory is explicit on this point.
- After merge, the post-merge sync (`git checkout main && git pull`) will also need the HTTPS temp-switch if SSH is still blocked. That's a separate authorization moment, handled outside this skill.
- This skill is mosko-fintech-specific. The branch conventions, repo URL, and PR body shape live with this repo. A different repo would have its own version of this skill with its own conventions.
