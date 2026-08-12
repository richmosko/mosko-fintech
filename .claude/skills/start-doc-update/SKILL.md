---
name: start-doc-update
description: Kicks off a doc-only update on a `phase/<outer>-<slug>` or `meta/<slug>` branch — for changes to PRD/ARCH/SECURITY HTML docs, WORKFLOW.md, DECISIONS.md, MILESTONES.md, BACKLOG.md, CLAUDE.md, etc. that aren't tied to a Linear feature. Replaces the retired `/ship-branch` skill (which only handled the push+PR step); use `/finish-doc-update` for that step. Per ADR-009 Decision 9.
user-invocable: true
allowed-tools:
  - Bash
  - Read
---

# start-doc-update — Bootstrap a phase- or meta-scoped doc-update branch

Use when you need to revise PRD/ARCH/SECURITY/MILESTONES/DECISIONS/WORKFLOW/CLAUDE/BACKLOG/MILESTONE-FRAMING/etc. and the change isn't tied to a Linear feature.

mosko-fintech adaptation of `richmosko/project_template`'s `/start-doc-update` per [ADR-009](../../../DECISIONS.md#adr-009) Decision 9. Differences from template:

- **Phase prefix map** uses R/P/I+V outer category names (sub-option 3 hybrid) — `research`, `plan`, `iv` — rather than template's per-phase names.
- **State-ledger files lumped under `meta/`** (not template's separate `state/` prefix). Single prefix; the slug names the doc.
- **File-path references** reflect mosko's subdirectory shape (`docs/PRD/`, `docs/ARCH/`, `docs/SECURITY/`) rather than flat HTML siblings.

## When to use vs `/start-feature`

| Situation | Use |
|---|---|
| Implementing a user story tied to a Linear issue | `/start-feature` (Phase 6+) |
| Updating PRD/ARCH/SECURITY during Research/Plan | **`/start-doc-update`** |
| Adding a Decision Log entry (ADR) that requires PR review | **`/start-doc-update`** |
| Fixing a typo in `WORKFLOW.md` or `CLAUDE.md` | **`/start-doc-update`** |
| Bumping a dependency in `package.json` | `/start-feature` (it has acceptance tests) |

Simple rule: **if it has acceptance criteria and lives in Linear, use `/start-feature`. If it's purely docs/process and doesn't, use `/start-doc-update`.**

## Inputs

- `$ARGUMENTS` — short kebab-slug describing the change (e.g. `prd-rename-section-2-archetype`, `arch-clarify-data-flow`, `workflow-fix-mermaid`, `adr-010-tailwind-choice`). Required. The skill will offer to refine if the slug is overly generic (e.g. `update`, `fix`, `change`).

## Steps

### 1. Pre-flight

Run in parallel:
- `git rev-parse --show-toplevel` — confirm we're in a repo. Bail if not.
- `git status --porcelain` — if uncommitted changes exist on the current branch, **stop** and ask the user to commit or stash first. Never auto-stash.
- `git rev-parse --abbrev-ref HEAD` — note current branch. If already on a `phase/*` or `meta/*` or `feature/*` branch, ask the user whether to (a) finish that branch first via `/finish-doc-update` or `/finish-feature`, or (b) stash + checkout main + start fresh.

### 2. Determine the prefix

Match the doc being edited to the prefix per ADR-009 Decision 9 sub-option 3:

| Doc edited | Branch prefix |
|---|---|
| `docs/PRD/*` (PRD HTML artifacts) | `phase/research-<slug>` |
| `docs/ARCH/*` (architecture HTML artifacts) | `phase/plan-<slug>` |
| `docs/SECURITY/*` (security HTML artifacts) | `phase/plan-<slug>` |
| (Future) implementation code | `phase/iv-<slug>` |
| `MILESTONES.md`, `DECISIONS.md`, `BACKLOG.md`, `CHANGELOG.md` | `meta/<slug>` |

⚠ **`CHANGELOG.md` is frozen and no longer maintained** (see `WORKFLOW.md` § Artifact list). It is listed above because the routing still applies if it must ever be touched — not as an invitation to add entries. No skill writes to it.
| `docs/MILESTONE-FRAMING.md` | `meta/<slug>` |
| `WORKFLOW.md`, `CLAUDE.md`, `README.md` | `meta/<slug>` |
| `.claude/agents/*.md`, `.claude/skills/*/SKILL.md` | `meta/<slug>` |
| `.claude/settings.json`, hook configs | `meta/<slug>` |
| `docs/handoff-prompts.md`, `docs/discovery-summary.md` | `meta/<slug>` |
| Ambiguous / multi-doc | ask the user which prefix the change belongs to |

State-ledger files (MILESTONES / DECISIONS / BACKLOG / CHANGELOG / MILESTONE-FRAMING) are intentionally lumped under `meta/` rather than a separate `state/` per ADR-009 Decision 9 lock. The doc edited appears in the slug, so the prefix collision doesn't lose information.

### 3. Create the branch

```bash
git checkout main
git pull --ff-only
git checkout -b <prefix>/<slug>
```

Branch length cap: max 60 chars total. Truncate the slug if needed.

### 4. Confirm and hand off

Tell the user:

```
Branch created: <prefix>/<slug>

Make your doc edits. When done:
  /finish-doc-update  →  commit + push over SSH + open PR
  /merge-pr           →  team-lead merges the PR (or merge via GitHub UI)
```

If the user is working with an active agent team (e.g. PM during Research; Architect during Plan), `SendMessage` the relevant agent to let them know the branch is ready for their doc edits.

## Failure modes

- **Branch already exists**: ask the user if they want to switch to it (resume an in-progress doc update) or pick a different slug.
- **Uncommitted changes on current branch**: stop; ask user to commit or stash. Never auto-stash.
- **Not in a git repo**: stop with a clear error.
- **Slug is overly generic** (e.g. `update`, `fix`, `change`): offer the user a more specific alternative before creating the branch.

## Notes

- Per ADR-009 Decision 9, mosko uses outer-category names (`research`/`plan`/`iv`) rather than template's per-phase names (`research`/`plan`/`state`/`meta`). State-ledger files and meta-infrastructure files share the `meta/` prefix.
- Legacy branches using `phase/<N>-<descriptor>` or `workflow/<descriptor>` conventions (pre-ADR-009) are NOT renamed; new branches use the adapted convention.
- This skill is mosko-fintech-specific. The phase-prefix map, file-path references, and convention citation live with this repo. A different repo running the template would have its own version of this skill.
