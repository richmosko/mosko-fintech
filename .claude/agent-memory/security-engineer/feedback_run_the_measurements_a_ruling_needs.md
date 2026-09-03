---
name: run-the-measurements-a-ruling-needs
description: Read-only measurements needed to REACH a verdict are review work — run them, don't route them back; the line to route across is builds/fixes and expensive reproductions the builder can run cheaper
metadata:
  type: feedback
---

**Run the read-only measurements your own ruling depends on. Do not route them back to the builder.**
Confirmed by team-lead 2026-09-03 as the **standing preference for reviews**, after I flagged it as a
judgment call they might have made differently.

**Why:** on the loop-mechanics snapshot advisory, DevOps's parity evidence compared two artifacts
built from the same recipe, so it could not reach the booking's actual claim. I ran three `psql`
reads against the live bootstrapped database to get the missing baseline and ruled on that.
Team-lead's reasoning: **routing back costs a round-trip to produce evidence only I knew I needed** —
the builder cannot anticipate the probe, because identifying it *is* the review. Both that and the
APPLIED-vs-DISCHARGED distinction it enabled were called out as making the ruling better.

**Where the line actually is** — this does NOT loosen [[do-not-do-teammates-work]], it locates it:

- **Mine (do it):** read-only measurement — catalog queries, `git show`/`grep`, hashing a blob,
  diffing two artifacts, counting legs. Anything whose output is evidence and whose side effects
  are none.
- **Never mine (route it):** **builds and fixes — changing the artifact under review.** That
  boundary is absolute and is the one my role brief already fences.
- **Route it (offer accepted, not work avoided):** **expensive reproductions the builder can run
  cheaper** — e.g. taking Architect's 2-minute scratch-chain recipe rather than rebuilding a chain
  myself. Judged on cost and who already has the harness warm, not on whose "side" it is.

**How to apply:** when a verdict hinges on a fact I do not have, ask *is this a read?* If yes, take
the measurement in the same turn as the ruling and cite the command. Only surface it as a gap when
it needs a build, a fix, or a harness someone else already has standing. And a blocked or missing
measurement is still a scheduling fact to surface — the change here is that a *cheap read* was never
that fact.

Related: [[applied-vs-demonstrated-discharge]] ·
[[my-review-measurements-become-quoted-sources]] ·
[[measure-the-fence-regex-not-its-comment]]
