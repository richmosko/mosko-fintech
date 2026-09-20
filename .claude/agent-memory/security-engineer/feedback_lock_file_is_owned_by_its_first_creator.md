---
name: lock-file-is-owned-by-its-first-creator
description: A lock path in a 1777 dir with no provisioning is owned by whoever runs first — one root run wedges the unprivileged service account permanently
metadata:
  type: feedback
---

When grading a `flock` control, do not stop at the lock **semantics** (`-n` vs blocking, exit code, fd scope). Grade **who creates the lock file and with what ownership**. `exec 200>"$LOCK_FILE"` requires write permission on an *existing* file; the first process to run creates it with that user's ownership and umask.

**Why:** PR #798 put the orchestrator's lock at `/var/lock/pfin-migrator-orchestrate.lock` with nothing provisioning it. `/var/lock` is `1777`, so the script runs as `ci-migrate` normally — but **one root run by an operator debugging on the box leaves the file `root:root 0644`, and every subsequent `ci-migrate` run then exits 7 permanently.** A control added to protect a path wedges that path. The `1777` directory also lets any local unprivileged user pre-create and hold the file (DoS only, refuse-to-run direction).

**How to apply:** ask three questions of any lock path — (1) is it pre-created by provisioning, owned by the service account, with a preflight leg asserting that; (2) is the "could not open" message distinguishable from the "already held" message so the wedge is diagnosable; (3) who else can write that directory. A `1777` or shared path with no provisioning is a flag, not a note. Related: [[feedback_a_disposition_without_a_mechanism]], [[feedback_which_lane_does_the_watcher_observe]].
