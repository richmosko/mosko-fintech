---
name: the-fence-scans-the-prose-about-the-fence
description: A grep-shaped ban blocks your own commit message, header or ADR text that DESCRIBES the banned thing — describe the pattern, never quote the literal, and remember the blocking tool also scans the command you use to fix it
metadata:
  type: feedback
---

**Never write a banned literal into prose — a commit message, a migration
header, an ADR, a runbook — even to say you avoided it.** Describe the pattern
instead.

**Why:** measured at `101` (SELF-259, 2026-09-03). The pre-commit hook banning
the local DB-reset command matched the phrase inside my own **commit message**,
which said which path I had *not* used. The commit was blocked twice:

1. First on the message file itself.
2. **Then on the `python3` one-liner written to FIX it** — because the fix
   quoted the offending string as its search term.

The second block is the reusable half. **The tool that blocks you also scans
the command you reach for to unblock yourself**, so the obvious repair
reproduces the failure and looks like the hook is broken.

**How to apply:**
- In prose, name the fence by its effect: *"the banned local-reset path was not
  used"*, not the command. `git commit -F <file>` does not exempt the file.
- To edit an offending string out, **match around it** — a `sed` pattern with a
  character class or a wildcard over the banned token — or **regenerate the
  whole file** from scratch without it. Do not grep for it.
- Generalizes past hooks: **any check that scans a corpus will eventually scan
  the prose written about the check**, because that prose is the densest
  concentration of the tokens it hunts. Applies to CI grep fences (DevOps) and
  battery-level invariant greps (QA) as much as to commit hooks.
- ⚠ Do not "fix" this by loosening the fence. The fence is right; the prose is
  what moves.

Related: [[bare-numeric-admits-infinity]] ·
[[watcher-not-fence-for-by-construction-properties]]
