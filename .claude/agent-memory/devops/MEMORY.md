# Memory index

## Working with the team
- [Verify relayed reviewer text before applying](feedback_verify_relayed_reviewer_text_before_applying.md) — a reviewer's relay isn't privileged; test it against its own stated cases before swapping in.

## Fence design
- [Fences must fail closed on their own dependency](feedback_fence_must_fail_closed_on_own_dependency.md) — a hook that shells to a parser (e.g. `jq`) must deny if that parser is missing, not just when the pattern doesn't match.
- [.claude/settings.json activation semantics](reference_claude_settings_activation_semantics.md) — permission rules AND hooks both load at SessionStart only; neither binds mid-session after an edit. "Mergeable" ≠ "active."

## Git / worktree mechanics
- [Worktree HEAD can be detached by a coordinator checkout, not by main moving](reference_worktree_head_detach_on_main_advance.md) — re-check `git status --short --branch` right before committing, not just after `git checkout -b`; a commit's "detached HEAD" line is the tell.
