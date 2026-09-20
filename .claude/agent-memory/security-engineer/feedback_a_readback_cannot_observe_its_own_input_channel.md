---
name: a-readback-cannot-observe-its-own-input-channel
description: A byte-exact read-back is vacuous when the written value and the expected value reach the comparison through the SAME mangling path — trace both legs back to their source
metadata:
  type: feedback
---

"Reads it back and compares byte-exact" sounds like a total control. It is only a
control over what happens **after** the fork point of the two legs. If the value
written and the value compared against are the same variable, any corruption
**upstream of that variable** corrupts both sides identically and the comparison
passes.

**Why:** PR #825's `migrator-scheduled-task.sh` exists to stop the task's `command`
literal being hand-copied a sixth time — it reads it from `provision-vps.sh`'s
`MIGRATOR_TASK_COMMAND` and byte-compares the Coolify read-back (`:273`). But
`$TASK_COMMAND` is interpolated into an **unquoted** `<<REMOTE` heredoc (`:202,:253`),
so local shell expansion mangles it before it ever leaves the machine. The mangled
value is what gets POSTed AND what the read-back is compared to. A `$`, a backtick or
a `"` in that literal would silently create a Coolify task differing from the repo
source of truth, and the whole single-source mechanism would report success.
(Today's literal `sh /workspace/pfin-task.sh` has no metacharacters — latent, not
live. That distinction is the mechanism/reachability split, graded separately.)

**How to apply:** for any read-back / round-trip / byte-exact assertion, draw the two
legs back to where they diverge. The assertion covers only the segment downstream of
the divergence. Then ask what the segment *upstream* can do: shell expansion,
heredoc interpolation, encoding, normalization, truncation, case-folding. If both
legs share it, the assertion is blind to it and you must name a second instrument
(compare against the file on disk, or hash at the source) or move the fork earlier.

Same family as the golden-fixture question "what varies between the two sides?" —
invariance is blindness.

Related: [[seed-delta-battery-watches-itself]],
[[probe-that-only-asserts-failure-goes-vacuous]],
[[unquoted-heredoc-deletes-text-from-the-remote-body]],
[[hazard-mechanism-vs-reachability]].
