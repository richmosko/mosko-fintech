---
name: a-piped-count-guard-mints-a-zero-when-the-producer-fails
description: "`producer | grep -c X || true` returns \"0\" when the PRODUCER fails, so a zero-means-safe guard on a destructive path fails OPEN; grade the asymmetry against sibling legs that already fail closed"
metadata:
  type: feedback
---

A guard of the shape `COUNT="$(producer | grep -c "$NEEDLE" || true)"` followed by
`[[ "$COUNT" != "0" ]] && refuse` is **fail-OPEN on producer failure**, not fail-closed.

**Why:** no `pipefail` in the (often remote, `sh -c`) shell, so a failed `producer`
still lets the pipeline run — `grep -c` reads empty stdin, prints `0`, exits 1, and
`|| true` launders that into exit 0. stdout is a clean `0`. The producer's stderr goes
somewhere nobody inspects. The operator sees `measured: containers=0` and cannot tell a
true empty set from a dead producer. First caught PR #836 `scripts/provision-app.sh:299-300`
(2026-09-20): `docker ps -a | grep -c "$uuid" || true` guarding whether the script may
DELETE a production Coolify application. Veto.

**How to apply:**
- Any `|| true` (or `2>/dev/null`) between a measurement and a **zero-means-proceed**
  decision is the thing to grade, especially on delete/destroy/overwrite paths.
- **Look for the asymmetric sibling.** In #836 the env leg in the SAME block already did
  `|| echo "unknown"` — a non-numeric sentinel that the `!= "0"` test refuses. The correct
  shape was three lines away. A guard block whose legs disagree about failure direction is
  the tell; name the asymmetry, it makes the fix obvious and un-arguable.
- Prove it, don't infer it: `bash -c 'p(){ return 1; }; echo "[$(p | grep -c x || true)]"'`
  → `[0]`. Same with the producer absent from PATH. Costs one command.
- Fix shape: separate the producer's exit status from `grep -c`'s legitimate no-match
  exit 1 — `if RAW="$(producer)"; then COUNT=$(grep -c ...); else COUNT=unknown; fi`.
  `if VAR="$(...)"` is a condition context, so `set -e` does not abort.
- **Demand the paired strike.** A fence can strike every leg's non-zero case and still be
  green over this: the missing scenario is "the producer itself fails". See
  [[inversion-test-the-rationale-not-the-presence]] and
  [[probe-that-only-asserts-failure-goes-vacuous]].

Related: [[an-earlier-guard-steals-the-strike]], [[a-fence-exists-is-not-a-fence-blocks]],
[[mint-if-absent-default-is-blind-to-the-live-store]].

## Verifying the FIX: strike the CHANNEL, not just the predicate

When the fix relies on a boundary's exit status reaching the caller (here: ssh's status →
the operator-side `if`), the fence's shim for the far side often sits on the NEAR side's
PATH. Then a green "read-fails" scenario is ambiguous: did it refuse because the boundary
propagated a failure, or because a local call failed?

Two strikes, both cheap, both on copies (PR #836 re-review, d0ff3826):
- **Strike the fix** — revert it, confirm exactly the new scenarios go red and the old ones
  stay green. Reproduce this yourself; do not accept the builder's report of it.
- **Strike the CHANNEL** — make the shimmed boundary swallow the inner exit status
  (append `|| true` to the fake `ssh`'s final `bash -c`). If the read-fails scenarios
  still pass, they never rode on the boundary at all.
- Corroborate structurally: grep every call site of the shimmed binary in the real script
  and confirm none is local. Topology argument + behavioural strike together.

Also re-run the ORIGINAL construction against the NEW shape as a **boundary pair**:
failed read → `unknown` → refuse, AND successful-but-empty read → `0` → proceed. A fix
that refuses both ways is not a fix, it is a wedge.

**Stale-rationale residue:** the fix can leave a fence comment justifying a control with a
premise the fix just deleted (here, "provision-app.sh's reads end in `|| true`"). The
control stays correct; its reason expired. Note-severity — it does not instruct a failure
— but say it, because an expired reason is how a good control gets "simplified" away.
See [[a-rework-leaves-residue-that-names-what-it-dropped]].
