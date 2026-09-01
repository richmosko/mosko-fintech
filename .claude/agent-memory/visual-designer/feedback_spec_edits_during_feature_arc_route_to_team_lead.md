---
name: feedback_spec_edits_during_feature_arc_route_to_team_lead
description: Visual Designer has no dedicated worktree — design-system-spec.md edits during an active feature arc land in the read-anchor main tree and must be transplanted onto the owning feature branch, not made directly.
metadata:
  type: feedback
---

When I write a docs/DESIGN/ spec edit (e.g. a new component-inventory row) while a feature branch is mid-flight, the edit lands in the main repo's working tree — which is the shared read anchor, not a branch of its own (unlike Architect/Backend/Frontend/etc., who each have a worktree at `~/Projects/mosko-fintech-worktrees/<agent>`). That main-tree edit has to be manually transplanted onto the feature branch so it ships with the PR that sets the precedent it documents, and the main tree restored clean afterward.

**Why:** confirmed by team-lead (2026-08-31, SELF-256 arc): "your edit landed in the main repo's working tree ... I transplanted the 2-line diff onto feature/self-256 ... main tree is restored clean." This was framed as expected mechanics, not an error — but it's manual work on team-lead's side every time.

**How to apply:** during an active feature arc, don't silently Write/Edit docs/DESIGN/design-system-spec.md (or other DESIGN files) expecting it to land with the feature — instead tell team-lead the rows/content to add and which branch they belong on, and let team-lead route the edit onto the owning branch. Outside a feature arc (e.g. a standalone design-system update with no in-flight branch), editing the main tree directly is fine as before.
