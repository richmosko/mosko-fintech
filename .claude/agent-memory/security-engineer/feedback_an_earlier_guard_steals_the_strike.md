---
name: an-earlier-guard-steals-the-strike
description: A fence scenario labelled for control B often exercises control A, because A's die() fires first — to strike control N you must disarm controls 1..N-1
metadata:
  type: feedback
---

When a script has layered refusals (allowlist, then manifest, then read-back), a test
input crafted for the LAST one is refused by the FIRST one. The test goes green, its
label says the last control works, and the last control has no watcher at all.

**Why:** PR #825's `fence-coolify-env-strikes.sh:135` ran
`set <uuid> SUPABASE_SERVICE_ROLE_KEY=x`, expected exit 1, and called it *"set
refuses manifest secret name."* But that name isn't on `SET_ALLOWLIST`, so the
allowlist `die()` fired first and the `secrets-manifest.yml` block was never reached.
Measured: **deleting the entire manifest-refusal block left the fence green on all
three scenarios.** The manifest check was the header's advertised belt-and-braces —
*"even a careless future SET_ALLOWLIST edit cannot turn this into a secret pusher"* —
and it was the one claim with nothing behind it.

The correct strike **widens the earlier guard on a copy** so control flow reaches the
later one: `sed` `SET_ALLOWLIST=(…)` to admit the manifest name, then assert it is
STILL refused. Confirmed both directions — widened alone → still refused (manifest
holds); widened AND manifest disarmed → green (so the leg is real).

**How to apply:** for every layered-refusal script, enumerate the guards **in
execution order** and ask, for each test input, *which guard actually fires*. Cheapest
check: disarm the control the test claims to prove (`if X:` → `if False:`) on a copy
and re-run — if the suite stays green, the label is wrong. Watch for the paired
vacuity: when the early `die()` fires, no downstream side-effect log exists, so any
"and X never appeared in the log" assertion in that same scenario is also vacuous
(here: "token absent from every logged curl argv" over an empty log).

Related: [[a-red-whose-message-names-the-wrong-defect]],
[[a-described-control-is-not-a-built-one]],
[[probe-that-only-asserts-failure-goes-vacuous]],
[[inversion-test-the-rationale-not-the-presence]].

## Second instance (PR #825 `de2ad749`) — the FIX for one finding made another's guard vacuous

The 4th scenario I asked for widens `SET_ALLOWLIST` on a copy via `sed`, then guards itself with
`grep -q 'SUPABASE_SERVICE_ROLE_KEY' "$WIDENED"` — "did the widening apply?". But the F2 fix I
asked for in the SAME round added a `grep -qx SUPABASE_SERVICE_ROLE_KEY` manifest-anchor line to
`coolify-env.sh`. The guard now matches that anchor whether or not the `sed` did anything.
Measured: reformat `SET_ALLOWLIST` to a multi-line array (benign style edit) AND disarm the
manifest refusal → **fence green on all four scenarios**, scenario 4 silently back to testing the
allowlist. Fix: anchor the guard to the ARRAY LINE (`grep -qE '^SET_ALLOWLIST=\(.*NAME'`), never
to a bare name.

**The generalisation: a positive-control TOKEN is only a control while it is UNIQUE in the file.**
When you require a new anchor/sentinel, grep the file for that literal first and check no other
guard keys on it. Two of my own requirements collided here — review a round's fixes as a SET, not
one at a time.

## Instrument positive control — a strike that does not apply is a FALSE GREEN

Twice in one session I ran a "disarming" mutation that silently matched nothing (wrong indent;
then a harness `sed` on `^COOLIFY_ENV_SH=` that also rewrote the fence's own
`COOLIFY_ENV_SH="$WIDENED"` line). Both would have let me report a correct control as
"not load-bearing". **Always assert the mutation landed** (`diff -q orig copy && echo INSTRUMENT
FAILED`), and prefer copying the whole tree and running the fence UNMODIFIED over sed-ing the
fence. When a strike says green, read the actual refusal MESSAGE — it names which guard fired.
