---
name: a-fence-exists-is-not-a-fence-blocks
description: A new CI fence defaults to ADVISORY. Grade EXISTENCE and ENFORCEMENT separately, read branch protection live via gh api, and note that a required-context manifest reconciles WORKFLOWS — an unrequired JOB inside a listed workflow is invisible to every check in the repo.
metadata:
  type: feedback
---

**"The fence is built and its goldens are strike-proven" answers EXISTENCE. It does not answer
ENFORCEMENT. Grade both, and measure the second live.**

**Why (PR #819 / ADR-072 Amendment 4 item 29, 2026-09-18).** DevOps built a new
network-exposure fence (`fence-migrator-bind`) and QA strike-proved every leg — a genuinely clean
build. Both of us could have stopped there. Measured live:

```
gh api repos/richmosko/mosko-fintech/branches/main/protection \
  --jq '.required_status_checks.contexts[]'
```

`fence-admission-bind` (RT-27) **is** a required context; **`fence-datastore-bind` (RT-32) is
NOT**, and neither is the new job. A red on either is mergeable. The fence that keeps production
Postgres off the public internet was advisory and nobody had said so out loud.

**The structural half, which is the reusable part.** `.github/required-contexts.tsv` and the
`required-unfiltered` fence over it are **one-way**: they prove every context *listed* in the
manifest is unfiltered. Nothing asks the inverse — *"this job exists and is not listed; why?"* The
manifest's own "NOT listed, and why" paragraph enumerates **workflows**, and its derive-command
(`comm -23 /tmp/wf /tmp/listed`) is workflow-level. So **an unrequired JOB inside a LISTED workflow
is invisible to every check in the repo.** Measured: `security-scan.yml` has 24 jobs; 12 back
required contexts. This is the same "absent from both while every check reports healthy" shape the
manifest itself records for the `etl-ci.yml` miss — the third failure mode alongside
required-but-unmanifested and manifested-but-not-required.

**How to apply:**
1. **At every PR that adds or moves a CI fence, state its enforcement posture explicitly** —
   required or advisory — and get it from `gh api .../branches/main/protection`, never from
   `required-contexts.tsv`, which the file's own header calls "a manifest, not a mirror."
2. **Do not let a "coverage moves without shrinking" claim be graded on the predicate alone.** If
   the old fence was advisory and the new one is advisory, the claim holds on the enforcement
   axis too — say so, with the measurement. If it moves required→advisory, that is a shrink and a
   blocking finding.
3. **Do not gate the feature PR on promoting a context.** Branch protection is an F/CTO field
   change; raise it as its own item. But raise it — an advisory fence is a fence someone can merge
   past, and "it was already like that" is how it stays that way. Cf.
   [[feedback_a_described_control_is_not_a_built_one]] (built vs described) — this is the third
   rung: described → built → **enforced**.
4. **A teammate reporting "X isn't in the manifest either, so this matches precedent" has measured
   the manifest, not the world.** Re-read branch protection yourself before agreeing. QA's read
   was correct here; it was correct by luck of the manifest being in sync, which the file warns is
   not guaranteed.
