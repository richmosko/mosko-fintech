---
name: a-mode-selected-fixture-is-blind-to-which-credential-crossed
description: A two-mode probe whose fixture returns a canned answer keyed on a MODE NAME cannot observe which credential actually crossed — strike the credential-delivery clause, not the classification branch, and make the fixture assert the argv
metadata:
  type: feedback
---

When a probe has **two modes with different expected outcomes** (anon → refuse, authenticated →
allow), the fence usually proves the **classification** (same status, two verdicts) and silently
fails to prove the **delivery** (that the privileged mode actually used the privileged credential).
The gap appears whenever the offline fixture picks its canned response from a **mode-name variable**
the harness sets, rather than from what the script actually passed it.

**Why:** PR #833's `scripts/smoke-pfin-exposure.sh` has exactly this shape — default mode uses the
container's own anon key and treats `200` as a **security anomaly FAILURE**; `--jwt` overrides the
`Authorization` header via `docker exec -e SMOKE_JWT_OVERRIDE=` and expects `200`. Its fence ran six
scenarios and was green. I deleted the `-e SMOKE_JWT_OVERRIDE=` clause on a copy — so `--jwt` mode
silently ran with the **anon** key — and **all six scenarios stayed GREEN**. Post-strike, a `200` in
`--jwt` mode is reported PASS while being precisely the anon-200 anomaly the default mode exists to
catch: the one-direction vacuity the script's own header claims it never has. `fake-docker` chose its
output from `$FAKE_DOCKER_MODE`, which the harness sets; it never looked at `$*`.

**How to apply:**
- **Enumerate the strike targets per mode, not per branch.** For a two-credential probe there are at
  least three: the classification branch for mode A, the one for mode B, and the **credential-delivery
  clause** that makes B different from A. Fences reliably cover the first two and reliably miss the third.
- **The fix lives in the fixture, not the script.** Make the shim assert the argv it was handed:
  a `jwt-*` mode arriving with no `SMOKE_JWT_OVERRIDE=` in `$*` must emit a status **no branch
  passes**; an `anon-*` mode arriving **with** one must do the same. No new scenario, no change to the
  reviewed script. Measured on a copy: green unstruck, RED under the strike — always verify the fix
  you hand over, per [[feedback_supplied_verbatim_text_ships_unfiltered]].
- **Ask of any mode-selected shim: could the script under test have sent something else and still got
  this answer?** If yes, the shim is a stub, not a witness.
- Severity: **flag**, not veto, when the privileged mode is off the live procedure (here `--jwt` is
  post-invite and §7.1 only runs the anon mode). Say that explicitly so the flag is not read as a block.
- Related: [[feedback_a_fixture_written_to_match_the_premise_cannot_falsify_it]],
  [[feedback_probe_that_only_asserts_failure_goes_vacuous]],
  [[feedback_corrupt_the_control_canary_boundary_tie]] point 10 (a green strike may be a missed strike).

**Second, smaller catch in the same review, same root:** the operator-side credential surface. The
`--jwt` value is built into the **local `ssh` argv** as well as the box-side `docker` argv, while the
header's named residual covered only the box. **Two hosts, one named** — see
[[feedback_credential_in_host_argv_and_the_named_vehicle]] and
[[feedback_filter_side_of_the_ssh_boundary]]. The ratified remedy in this repo is the seed-file hop
(`push-production-secrets.sh`): write the value to a 0600 file on the box over SSH **stdin**, then
`--env-file` it, so neither argv carries the value.
