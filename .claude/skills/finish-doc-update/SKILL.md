---
name: finish-doc-update
description: Closes a doc-only update — commits the doc edits, pushes the `phase/*` or `meta/*` branch over SSH (HTTPS is a last-resort fallback for a blocked port 22 only), and opens a PR with mosko's elaborate body shape (Summary / Motivation / Files / Test plan / Follow-ups). Mirrors `/finish-feature` but lighter (no Linear issue update, no QA handshake) and replaces the retired `/ship-branch` skill. Per ADR-009 Decision 9.
user-invocable: true
allowed-tools:
  - Bash
  - Read
---

# finish-doc-update — Wrap a doc-update branch into a PR

Wraps a doc-update branch into a PR. Does not auto-merge — that's `/merge-pr`'s job (or human merge via GitHub UI). Decision rights on merging stay with F/CTO.

mosko-fintech adaptation of `richmosko/project_template`'s `/finish-doc-update` per [ADR-009](../../../DECISIONS.md#adr-009) Decision 9. Differences from template:

1. **Documents the SSH deploy-key path plus a narrow HTTPS last resort.** Template's version does plain `git push` and surfaces errors — which is now also mosko's behaviour, because the repo deploy key makes SSH work. The HTTPS temp-switch is retained ONLY for a blocked/timing-out port 22, with per-use authorization, and carries an explicit warning that it silently refuses workflow-file pushes.
2. **Commit message format** uses `docs(<outer>): <subject>` matching the R/P/I+V outer-category prefix from `/start-doc-update` (`docs(research):` / `docs(plan):` / `docs(iv):` / `docs(meta):`).
3. **PR body shape** uses mosko's elaborate shape (Summary / Motivation / Files changed / Test plan / Follow-ups) replacing template's lean Summary+Type-line shape. F/CTO consistently finds the richer shape useful for PR review.

## Pre-flight

Run in parallel:
- `git rev-parse --abbrev-ref HEAD` — confirm we're on a `phase/*` or `meta/*` branch. **Bail** if on `main` or a `feature/*` branch (those are `/finish-feature` territory).
- `git diff --quiet HEAD` + `git status --porcelain` — confirm there are uncommitted changes to wrap. If clean and nothing to commit since branch creation, **bail** with a clear message ("nothing to commit on this branch — abandon it via `git checkout main && git branch -D <branch>` or make edits first").
- `git log main..HEAD --oneline` — note commits already on this branch.
- `git remote -v` — note current origin URL (will usually be SSH).

## Steps

### 1. Stage and commit

- Run `git status` and `git diff` to see what's changing.
- Group changes into logical commits if there are multiple. One commit per logical change (e.g. "PRD: add Non-Goals" and "PRD: refine success metrics" are separate commits, not one).
- **Commit message format:** `docs(<outer>): <subject>` matching the branch prefix:
  - On `phase/research-prd-add-section`: `docs(research): add §3.4 success metric`
  - On `phase/plan-arch-clarify-dataflow`: `docs(plan): clarify data-flow diagram in ARCH`
  - On `meta/workflow-fix-mermaid`: `docs(meta): fix Mermaid arrow in WORKFLOW`
  - On `meta/adr-010-tailwind-choice`: `docs(meta): land ADR-010 — Tailwind for styling`
- HEREDOC body for non-trivial changes; one-liner subject is fine for simple edits.
- **No raw `self-NNN` in the commit subject or body** (the integration scans commit messages — see the Issue-ID hygiene callout in step 3). Reference the documented feature by PR number + merge SHA, not its issue ID. The committed *file content* (CHANGELOG/MILESTONES/DECISIONS) keeps the IDs — that's exempt.

Add the standard Claude trailer per global git instructions:

```
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

### 2. Push over SSH

**SSH is the working path — push plainly.**

```bash
git push -u origin HEAD
```

A repo-scoped **deploy key** is configured for mosko-fintech in the shared git config (`core.sshCommand`, which every worktree inherits), so pushes work without a TTY. The passphrase-key problem that the old HTTPS-first guidance existed for was solved on 2026-05-14.

⚠ **`Permission denied (publickey)` is NOT expected here, and is NOT a cue to reach for HTTPS.** Verify the premise before concluding SSH is unavailable — both checks are read-only and take seconds:

```bash
ssh -i ~/.ssh/id_ed25519_claude_mosko-fintech -o IdentitiesOnly=yes -T git@github.com
#   expect: Hi richmosko/mosko-fintech! You've successfully authenticated
git config --get core.sshCommand
#   expect: ssh -i ~/.ssh/id_ed25519_claude_mosko-fintech -o IdentitiesOnly=yes
```

If those succeed, the push failed for some *other* reason — read the actual error rather than assuming it is the key. If `core.sshCommand` is missing (fresh machine, rotated key), run `/setup-claude-deploy-key`; that is the fix, not HTTPS.

#### HTTPS temp-switch — LAST RESORT, and only for one failure mode

**The deploy key cannot fix a blocked or timing-out port 22** — deploy keys still use port 22. On a hostile network or behind a corporate firewall, SSH will **time out or be refused at the connection level** (as distinct from being *rejected on authentication*), and HTTPS over 443 is then the genuine answer. **That case is why this fallback still exists.**

⚠ **HTTPS SILENTLY REFUSES WORKFLOW-FILE PUSHES.** It authenticates with the `gh` OAuth token, which lacks `workflow` scope, so any push touching `.github/workflows/` is rejected:

```
! [remote rejected] refusing to allow an OAuth App to create or update workflow
  `.github/workflows/<file>.yml` without `workflow` scope
```

This arrives as a *mysterious permissions error* and reads like a repo/branch problem rather than a transport one. **If the branch touches a workflow file, HTTPS is not an option at all** — fix the SSH path instead.

With per-use authorization (each push gets its own approval):

```bash
git remote set-url origin https://github.com/richmosko/mosko-fintech.git
git push -u origin HEAD
git remote set-url origin git@github.com:richmosko/mosko-fintech.git
git remote -v   # confirm SSH restored
```

Always restore origin to SSH afterward, even on failure. The HTTPS form uses the gh CLI's stored credentials (system keyring), which Claude's bash can reach.

> **Why this is a demotion and not a deletion.** The port-22 case is real and HTTPS is the only answer to it. What was wrong was the *ordering*: the fallback was documented as the expected path, so agents matched `Permission denied (publickey)` to a familiar story and switched transport without ever testing whether SSH worked. On 2026-08-06 that cost six unnecessary HTTPS pushes and a spurious credential escalation to the F/CTO, on a repo where SSH had worked for nearly three months. **A documented workaround is a claim about the world with a timestamp on it, and it decays.**

### 3. Open the PR

Use `gh pr create` with mosko's **elaborate PR body shape** per ADR-009 Decision 9.

> **⚠️ Issue-ID hygiene (load-bearing — the Linear↔GitHub auto-close gate).** A doc/meta PR is *about* issues but does NOT complete them. The integration fires its issue automation on any `self-NNN` token in the **branch name, PR title, PR body, or commit messages** (NOT file diffs). So a doc PR that names a live `self-NNN` in its metadata will spuriously transition that issue on open/merge (this is why the F/CTO disabled the merged→Done auto-close; re-enabling is gated on doc PRs staying clean). **Rules for this skill's title / body / commits:**
> - **Never write a raw `SELF-NNN` / `self-NNN` token** in the doc-PR title, body, or commit message. Reference the feature it documents by **PR number + merge SHA** instead (e.g. "the accounts-hub bundle, PR #269, merge `255af7d`") — never by its issue ID.
> - The branch name already excludes IDs (`meta/<slug>` / `phase/<outer>-<slug>` per `/start-doc-update`) — keep it that way.
> - **File CONTENT is exempt** — `CHANGELOG.md` / `MILESTONES.md` / `DECISIONS.md` may (and should) keep `SELF-NNN` in the committed text as the historical record; the integration scans PR/commit *metadata*, not diffs. The rule is about the PR title/body/commit-message ONLY.
> - Neutralize any *incidental* mention of an unrelated live issue that would otherwise land in the body — do not name it. (See `feedback_branch_name_issue_id_autocloses_linear`.)

**Title:** matches the most recent commit subject (or ask user if multiple commits with mixed scopes). **Must contain no `self-NNN` token** (per the hygiene rule above) — so the commit subject it mirrors must also be ID-free.

**Body skeleton:**

```markdown
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

- **Files list:** pull from `git diff --stat main..HEAD`. Include only what's actually in the diff.
- **ADR references:** scan `git log main..HEAD` and the diff for `ADR-NNN` mentions; include only what's present, don't invent.
- **Test plan:** derive checks from what changed. Examples:
  - Hook change → "open a new session; verify hook fires; confirm MILESTONES.md head loads".
  - `DECISIONS.md` change → "read ADR end-to-end; confirm format matches hybrid policy from ADR-009 Decision 8; verify cross-refs resolve".
  - HTML doc change → "open in browser; verify renders + Mermaid diagrams + anchors resolve; no console errors".
  - `WORKFLOW.md` change → "read header line; verify Current phase is still accurate; verify CHANGELOG link works".
- **Follow-ups:** queued companion PRs or downstream work; if none, drop the section.

Include the Claude Code attribution footer:

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

Use a HEREDOC for the body to preserve formatting.

### 4. Hand off the PR URL

`gh pr create` prints the PR URL on success. Surface it to the user. **Do not auto-merge.** Decision rights on merging stay with F/CTO.

If running in agent-team mode, also `SendMessage` to the team-lead (the main session): "Doc update opened as PR <url>. Ready for review and `/merge-pr` (or human merge via GitHub UI)."

The team-lead reviews the diff, confirms it reads correctly, and either:
- Runs `/merge-pr` to merge on F/CTO's behalf (after F/CTO approval)
- Tells the user to review and merge via the GitHub UI

**There's no QA / Validate phase for doc-only PRs.** The lead's read of the diff is the only gate beyond GitHub's own branch-protection rules.

## After-merge follow-up

If the merged change was tied to a phase transition (e.g. "PRD v1 approved → move to Plan"), the team-lead should still:
- Update `MILESTONES.md` → Current Phase
- Add an entry to `DECISIONS.md` for the phase-gate approval (consolidation pattern if synthesis work; terse pattern if isolated decision — per ADR-009 Decision 8)

These updates may need their own subsequent `/start-doc-update meta/<slug>` cycle since the merge of *this* PR doesn't automatically trigger them.

## What this skill does NOT do

- **Auto-merge after CI passes** — would cross the "don't merge unilaterally" line. The follow-up `gh pr merge --merge --delete-branch` is a separate operation triggered by F/CTO sign-off.
- **Watch CI status** — out of scope.
- **Pull `main` and clean up the local branch after merge** — sibling operation; `/merge-pr` handles that when it merges.
- **Bump `WORKFLOW.md` version or write ADRs automatically** — those are separate, deliberate edits. If the PR's content materially changes project state (new phase entry, new locked decision, new artifact), call out the missing companion under "Follow-ups" in the PR body.

## Failure modes

- **Not on a `phase/*` or `meta/*` branch**: bail; suggest `/start-doc-update` first to create the branch.
- **No uncommitted changes**: bail; nothing to commit. Either make edits or abandon the branch.
- **SSH push fails (`Permission denied (publickey)`)**: this is NOT the expected outcome and NOT a cue to switch to HTTPS. Verify the deploy key first (`ssh -T` + `git config --get core.sshCommand`, step 2). If the key checks out, the failure is something else — read the actual error. If `core.sshCommand` is absent, run `/setup-claude-deploy-key`. Reach for HTTPS only on a connection-level timeout/refusal (port 22 blocked), and never when the branch touches `.github/workflows/`.
- **`gh pr create` fails**: surface the error verbatim (auth, branch-protection mismatch, etc.). Don't pretend success.
- **Branch protection rejects the push** (rare on initial push; common if main was force-changed): surface the error and advise the user to rebase or pull.

## Notes

- `gh pr merge --merge --delete-branch` is the merge style used on `main` (preserves `Merge pull request #N from …` history). Do not propose `--squash` or `--rebase` unless explicitly asked.
- The HTTPS temp-switch needs per-use authorization every time — the user's network and credential environment can differ between sessions. It is a last resort for a blocked port 22, not the expected path.
- After merge, the post-merge sync (`git checkout main && git pull`) uses the same SSH path. It would only need the HTTPS temp-switch in the same narrow port-22 case, which is a separate authorization moment handled outside this skill (or absorbed by `/merge-pr`).
- Per ADR-009 Decision 9, this skill **replaces `/ship-branch`** (which was the single-step push+PR skill from mosko's pre-template-adoption convention). Branch creation is now handled by the sibling `/start-doc-update`. The two-step flow matches template's convention while preserving mosko's push guidance + elaborate PR body shape.
- This skill is mosko-fintech-specific. The repo URLs, branch conventions, PR body shape, and push guidance live with this repo. A different repo running the template would have its own version of this skill.
