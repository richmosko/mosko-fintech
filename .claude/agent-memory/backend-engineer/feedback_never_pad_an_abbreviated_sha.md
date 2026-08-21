---
name: never-pad-an-abbreviated-sha
description: When reporting a "full" commit sha in a handoff, run git rev-parse — don't extend git's 7-char abbreviated output with guessed digits.
metadata:
  type: feedback
---

`git commit` prints only an abbreviated (~7-char) sha in its own output (`[detached HEAD 25caf54] ...`).
When a handoff message calls for the *full* sha (sha-pinned handoffs, cherry-pick targets), that
abbreviation is not the full value — run `git rev-parse HEAD` (or `git log -1 --format=%H`) and
quote exactly what it returns. Padding the abbreviation with characters that "look plausible" is
fabrication, even if unintentional and even if nobody acts on the wrong digits.

**Why:** During SELF-243, I committed a detached delta and reported "sha 25caf5427..." in the
handoff — the digits after the real 7-char prefix were not read from `git rev-parse`, they were an
artifact of glancing at other hex nearby and assuming a plausible continuation. frontend-2 caught it
independently while resolving the sha from their own worktree (shared object store, same commit) —
the actual full sha was `25caf545fcc8103b1d9134749ee14addfd77fd06`. No harm done this time (they
resolved it correctly anyway), but a sha-pinned handoff exists specifically so the *receiver* never
has to re-derive or eyeball-verify the pointer — a wrong full sha defeats that purpose the same way
a stale md5 would.

**How to apply:** Every time a commit is made in this session (detached pin commits, sha-pinned
handoffs to a teammate) and the sha needs to go in a message, run `git rev-parse HEAD` in the SAME
turn and copy its output verbatim — never hand-extend the abbreviated form `git commit` prints, and
never reuse a sha you seem to remember from a prior tool result without re-reading it. Same
discipline as [[feedback_verify_against_commit_not_head_when_disputing_history]] and the "anchor
confirm requests to a sha, never a description" principle: the sha itself must also be read live,
not reconstructed from memory of its shape.
