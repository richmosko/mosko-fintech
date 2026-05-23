---
name: finish-doc-update
description: Closes a doc-only update — commits the doc edits, pushes the `phase/*` or `meta/*` branch (with SSH→HTTPS fallback per feedback_ssh_push_fallback), and opens a PR with mosko's elaborate body shape (Summary / Motivation / Files / Test plan / Follow-ups). Mirrors `/finish-feature` but lighter (no Linear issue update, no QA handshake) and replaces the retired `/ship-branch` skill. Per ADR-009 Decision 9.
user-invocable: true
allowed-tools:
  - Bash
  - Read
---

# finish-doc-update — Wrap a doc-update branch into a PR

Wraps a doc-update branch into a PR. Does not auto-merge — that's `/merge-pr`'s job (or human merge via GitHub UI). Decision rights on merging stay with F/CTO.

mosko-fintech adaptation of `richmosko/project_template`'s `/finish-doc-update` per [ADR-009](../../../DECISIONS.md#adr-009) Decision 9. Differences from template:

1. **Adds SSH→HTTPS fallback** with per-use authorization — ported from the retired `/ship-branch` skill per `feedback_ssh_push_fallback` memory. Template's version did plain `git push` and surfaced errors; mosko's adaptation surfaces the fallback path on `Permission denied (publickey)`.
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

Add the standard Claude trailer per global git instructions:

```
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

### 2. Push with SSH→HTTPS fallback

Attempt the SSH push first:

```bash
git push -u origin HEAD
```

If it fails with `Permission denied (publickey)`, do **not** retry. Surface the failure and propose the HTTPS temp-switch, asking explicitly for per-use authorization (matches `feedback_ssh_push_fallback` — each push gets its own approval). On approval:

```bash
git remote set-url origin https://github.com/richmosko/mosko-fintech.git
git push -u origin HEAD
git remote set-url origin git@github.com:richmosko/mosko-fintech.git
git remote -v   # confirm SSH restored
```

Always restore origin to SSH after the push, even on push failure. The HTTPS form uses the gh CLI's stored credentials (system keyring) which Claude's bash can reach.

This SSH→HTTPS fallback is the mosko-specific extension to template's `/finish-doc-update`. It exists because the F/CTO's main SSH key is passphrase-protected and Claude Code's bash has no TTY to unlock it. See `feedback_ssh_push_fallback` for the full root-cause analysis; the primary fix (`/setup-claude-deploy-key`) eliminates the friction per-repo, with HTTPS temp-switch as the secondary fallback.

### 3. Open the PR

Use `gh pr create` with mosko's **elaborate PR body shape** per ADR-009 Decision 9.

**Title:** matches the most recent commit subject (or ask user if multiple commits with mixed scopes).

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
- **SSH push fails (`Permission denied (publickey)`)**: surface and propose the HTTPS temp-switch with per-use authorization. Do not retry SSH automatically.
- **`gh pr create` fails**: surface the error verbatim (auth, branch-protection mismatch, etc.). Don't pretend success.
- **Branch protection rejects the push** (rare on initial push; common if main was force-changed): surface the error and advise the user to rebase or pull.

## Notes

- `gh pr merge --merge --delete-branch` is the merge style used on `main` (preserves `Merge pull request #N from …` history). Do not propose `--squash` or `--rebase` unless explicitly asked.
- The HTTPS temp-switch needs per-use authorization every time — the user's network and credential environment can differ between sessions, and the `feedback_ssh_push_fallback` memory is explicit on this point.
- After merge, the post-merge sync (`git checkout main && git pull`) will also need the HTTPS temp-switch if SSH is still blocked. That's a separate authorization moment, handled outside this skill (or absorbed by `/merge-pr`).
- Per ADR-009 Decision 9, this skill **replaces `/ship-branch`** (which was the single-step push+PR skill from mosko's pre-template-adoption convention). Branch creation is now handled by the sibling `/start-doc-update`. The two-step flow matches template's convention while preserving mosko's SSH fallback + elaborate PR body shape.
- This skill is mosko-fintech-specific. The repo URLs, branch conventions, PR body shape, and SSH fallback live with this repo. A different repo running the template would have its own version of this skill.
