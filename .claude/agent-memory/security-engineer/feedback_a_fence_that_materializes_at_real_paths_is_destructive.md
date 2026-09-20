---
name: a-fence-that-materializes-at-real-paths-is-destructive
description: A CI fence that runs the REAL script against its REAL hard-coded production paths is a destructive tool on any host that has those paths — grade the CLEANUP TRAP, not just the writes.
metadata:
  type: feedback
---

When a fence refuses an env-var path override **on purpose** (C2-class: "no caller-steerable
config path"), its only remaining way to test the real script is to **materialize fixtures AT
the real, hard-coded production paths**. That is the right call for the override question and
it silently creates a second one: **the fence is now a destructive tool on any host that has
those paths.**

Grade three things, in this order:

1. **The cleanup trap, before the writes.** `trap cleanup EXIT` doing `sudo rm -f "$CONF_FILE"
   "$TOKEN_FILE"` is worse than the overwrite — the overwrite is repairable by re-provisioning,
   the DELETE of a **credential file** needs a re-mint. Ask what the trap removes, not what the
   body writes.
2. **What ENFORCES "CI only".** A header paragraph saying "there is no production box inside a
   GitHub Actions runner" is a *disposition*, not a mechanism. `command -v sudo` is not a host
   guard — every Linux dev box and the production box both pass it. Demand **two** guards:
   `[[ "${GITHUB_ACTIONS:-}" == "true" ]]` (cheap) and, load-bearing, **`[[ ! -e "$CONF_FILE" &&
   ! -e "$TOKEN_FILE" ]]`** — host-independent, holds even if the env var is spoofed, and is the
   one that actually encodes "this host is not a real box."
3. **The realistic trigger is not an attacker.** It is an operator debugging on the box thinking
   *"let me just run the fence locally."* The author will say it is Linux+sudo only as if that
   were the fence; the production box is Linux with sudo.

**Why:** PR #831 (2026-09-19, item 59) added `fence-migrator-orchestrate-strikes.sh`, which
sudo-writes and then EXIT-trap-deletes `/etc/pfin/migrator-trigger.conf` and
`/etc/pfin/migrator-coolify-token.env`. Correct CI design, one missing guard away from wiping
the production migrate lane's credential. I made it the merge condition.

**How to apply:** any new `scripts/ci/fence-*.sh` that (a) invokes the REAL script rather than a
copy, and (b) needs `sudo`. Both together are the tell. See also
[[feedback_a_disposition_without_a_mechanism]], [[feedback_a_described_control_is_not_a_built_one]],
[[feedback_a_fence_exists_is_not_a_fence_blocks]].

⚠ Second thing this review surfaced, same file: the strike's message anchor must be **unique in
the script**. `"gave up after"` matched TWO poll-timeout sites — the leg would pass on the wrong
branch. `grep -cF "<anchor>" <script>` every anchor; a count of 2 is a false green waiting.
See [[feedback_fence_sentinel_asserts_subject_not_layer]].

## How to STRIKE such a guard without being destructive (worked, 2026-09-19, b7dd2fb9)

Bash is read-only for me, and the script's whole hazard is that it sudo-writes. Both constraints
are satisfied by **shadowing `sudo` with a refuser**:

- temp bin with a `sudo` stub: `echo "SUDO-REACHED: $*" >> "$SUDO_WITNESS"; exit 99`
- **Strike A** — the guard's condition UNMET: assert exit 2 **and `wc -l $SUDO_WITNESS` == 0.**
  The witness count is the real assertion; the exit code alone does not prove nothing was written.
- **Strike B, the positive control that matters most** — condition MET: assert the witness is
  NON-empty and its first line is the write you feared. This proves the guard is the ONLY thing
  standing in the way, i.e. load-bearing rather than incidentally redundant with some other
  refusal. Without B, a guard that never had to fire looks identical to one that works.

It also satisfies `command -v sudo`-style preflights for free, and the EXIT trap's own
`sudo rm -f` shows up in the witness — which is how I confirmed the trap was the real hazard.
