---
name: state-check-lstats-the-repair-dereferences
description: A check-then-chown/chmod repair in a world-writable dir is a root symlink-follow primitive — stat reports the link, chown/chmod act on the target
metadata:
  type: feedback
---

When provisioning code checks a file's owner/mode and then **repairs** it, grade the check and the repair as **two different syscall families**. `stat -c` without `-L` reports the **symlink itself**; `chown` and `chmod` **dereference**. So in a world-writable directory a local user pre-creates the path as a symlink, the state check mismatches (it sees a 0777 link), and root's repair branch hands the caller ownership/mode of the **target**.

**Why:** PR #800 provisioned `/var/lock/pfin-migrator-orchestrate.lock` (dir is `1777`) with `stat -c '%U:%G %a'` then, on mismatch, root `chown ci-migrate:ci-migrate && chmod 0600`. Measured in `/tmp` this session: `chmod 0600 lnk` left the link `lrwxr-xr-x` and changed the target to `-rw-------`; `stat` reported `Symbolic Link` without `-L` and `Regular File` with it. **`fs.protected_symlinks` does NOT save you** — it covers `open()`, so a `touch X && chown … && chmod …` *create* branch short-circuits safely, but a *repair* branch that skips the `touch` is unprotected.

**How to apply:** two questions on any check-then-repair over a path an unprivileged user can influence — (1) does the check use lstat semantics while the repair uses stat semantics; (2) is the repair running as root. If both, require a type gate (`stat -c '%F'` must be a regular file, else `die`) and `chown -h`. Grade reachability separately from mechanism per [[feedback_hazard_mechanism_vs_reachability]] — a foothold that does not exist today makes this a flag, not a veto. Pairs with [[feedback_lock_file_is_owned_by_its_first_creator]].
