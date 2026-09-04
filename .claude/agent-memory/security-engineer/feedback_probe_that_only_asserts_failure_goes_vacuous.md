---
name: probe-that-only-asserts-failure-goes-vacuous
description: An inversion probe asserting only "the command exited non-zero" cannot tell "detected the defect" from "could not reach the service" — and it goes vacuous under exactly the outage the fix under review is about; also, find the sibling fences by RUNTIME VERSION, not by name
metadata:
  type: feedback
---

**A probe that asserts `rc != 0` is not an inversion probe. It is a liveness check wearing one.**

Found at the npm-audit fence review (PR #608, 2026-09-04). `scheduled-dep-audit.yml` builds a throwaway
tree pinning a package with a real published advisory and asserts the audit command exits non-zero. Its
own comment states the property it means to establish: *"proves this job CAN go red on a real advisory."*
It does not establish that. **A registry timeout, a 503, a retired endpoint, a malformed request, a
DNS failure — every one of them satisfies `rc != 0` identically to a genuine finding.**

**Why it is worse than a merely weak probe: it goes vacuous under precisely the condition the PR exists
to fix.** The whole PR was about an audit client erroring against the registry. Under that error the
probe *passes* — for the wrong reason — and the fence's one watcher stops watching at exactly the moment
it is needed. A control that fails open under its own subject matter is worse than no control, because
the green is read as evidence.

**Then the wrong-defect RED compounds it.** The same job annotates any non-zero rc as
`::error title=Dependency advisory in $d::`. So a registry outage is reported to a human as a dependency
advisory. The repairs that message invites — triage a nonexistent CVE, lower the threshold, add
`|| true` — all disable the watcher. See [[a-red-whose-message-names-the-wrong-defect]].

**The fix shape, and it generalises past npm:** make the probe assert **the specific thing was detected**,
not that the command failed. Parse the machine-readable output and require the known identifier
(`npm audit --json` must contain `GHSA-2v37-7h3g-55p8`), not merely a bad exit code. **Ask of every
inversion probe: name three ways the command could fail that are NOT the defect. If the probe cannot
distinguish them, it is not testing what its comment says.**

⚠ **Distinguish this from a genuine fail-closed leg.** The *production* leg of such a job SHOULD fail on
any non-zero rc — a registry error must not yield a green audit. The asymmetry is the point: **fail-closed
in production mode, discriminating in inversion mode.** I explicitly ruled *against* adding a
5xx-vs-finding discriminator to the production path (npm exits 1 for both, so the discriminator would be
a stderr grep on an unstable string, and a retry loop is a new place for the fence to be softened; the
re-run button already supplies the retry). **What I required instead was ATTRIBUTABILITY** — the job may
fail on anything, but it must not *assert a cause it did not establish.*

---

**Companion, same review — find the sibling instances of a defect class by RUNTIME VERSION, not by name.**

The fix pinned the audit client in one workflow. Greping for the job name or for `audit` finds the obvious
neighbours; what actually located the exposure was greping for the **thing that carries the defect**:
`node-version:` across `.github/workflows/`, then resolving what npm each Node line bundles
(`nodejs.org/dist/index.json` → v20.20.2 ships npm 10.8.2, v22.x ships npm 10.9.8 — both pre-fix). That
turned up **three** npm-audit fences in the tree and **one** pinned client. A defect class fixed at one of
N instances gets re-diagnosed from scratch when the other N−1 trip, months later, by someone without the
context.

**How to apply:** when reviewing a fix for an environment/toolchain defect, ask *what property of the
environment carries this defect*, grep for **that** across all workflows/Dockerfiles, and resolve the
version chain rather than trusting a version label. Report the sibling instances as their own tracked
finding with an owner — not folded into the PR under review, whose scope is legitimately narrow.
Related: [[enumeration-and-watcher-stop-one-short]] and
[[grep-the-existing-battery-before-scoping-a-remediation]].

**THE INVERSE FAILURE MODE, and it nearly shipped as a catastrophic finding (SELF-269).** A probe
can also fail by reporting **everything as broken**. I swept a close-gate battery's ~50 cited leg
labels against the five files they were cited from, using a shell function with a nested command
substitution. Under `zsh` the substitution failed, printing `bad substitution` per iteration **while
still emitting the failure branch** — so the output was 47 uniform `*** MISSING ***` lines: *every*
citation dangling across five green batteries. I caught it only because the shell's error text
landed on the same lines. **A quieter shell and I would have forwarded a uniform false positive as
the finding of the review.**

**Two reusable rules from it:**
- **Make a sweep print ONLY misses.** Then a broken sweep prints **nothing** — which reads as
  "clean" and is checked by the next thing you do — instead of printing everything, which reads as a
  five-alarm result and is very hard to disbelieve because it is exactly what a real catastrophe
  looks like. Failing silent is the safe direction *for an enumerating probe*, the opposite of the
  rule for a fence.
- **A uniform result is a tell about the instrument, not about the tree.** When every item in a
  heterogeneous set answers identically, suspect the harness before writing the finding. The re-run
  with a plain loop returned **two** real results out of ~50 — which is what a genuine measurement
  over a mostly-correct artifact looks like.

**And the finding the working sweep actually produced is worth the method:** one dangling label
(`L3a`, cited for content that is really carried by `L3b` + `L3h`) on a battery whose whole method is
**composition by citation**. When the citation IS the evidence, a wrong pointer is that gate's
equivalent of a missing leg — the pointer-vs-content split from [[a-citation-has-four-falsifiable-axes]],
at the one place it costs most. Sweep every cited label mechanically; do not spot-check.

**THE THIRD DIRECTION, and it is the one that ships: a FALSE GREEN from an unvalidated instrument
(SELF-269).** Verifying that no test leg had been re-authored under an unchanged label, my first
script reported **"no verb changed under any label"** — clean, and I was one send from forwarding it.
It was an artifact: the label-capture bound each label to the first `select …(` in its window, which
for every assertion preceded by `select _rls.set_tenant(…)` was the **set_tenant call**, not the
assertion. **It would have reported clean no matter what changed.**

**Three instrument failures in one review, and they are not equally dangerous.** Two produced FALSE
POSITIVES — a sweep printing every citation as dangling, an over-matching regex reporting the
control leg as not-first — and both were caught immediately, because an implausible alarm invites
its own re-check. **The false GREEN invites nothing.** A clean result from an unvalidated instrument
is byte-identical to a clean tree.

**The rule, and it is different from the print-only-misses rule:**

> **A verification needs a POSITIVE CONTROL — an instance KNOWN to have changed, which the
> instrument must detect before its "nothing changed" is believable.** Assert the control first and
> print its result beside the sweep's.

One was available and I had not used it (a leg whose verb change had been declared). The corrected
run prints `POSITIVE CONTROL … WORKS` before the result, which is what makes the result citable.
**This is the [[inversion-test-the-rationale-not-the-presence]] discipline turned on my own review
tooling** — I require teammates to prove a battery leg can go red; a review script asserting absence
owes exactly the same proof. Related: [[a-check-chained-to-its-action-is-decoration]].

**And the honest disposal of a measurement that cannot be trusted:** the operand-level version of
the same check produced a provable artifact, so I reported the verb-level result and stated plainly
that the operand half was **not verified by me**. **An unreliable measurement is not a weaker
result; it is not a result** — do not report it with a hedge, report the scope of what was actually
established.
