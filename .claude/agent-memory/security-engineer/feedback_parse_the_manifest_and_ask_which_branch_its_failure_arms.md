---
name: parse-the-manifest-and-ask-which-branch-its-failure-arms
description: A committed config can be schema-INVALID while every fence over it passes — fences read regexes, not parsers. Worse, when a runbook makes that file's deploy outcome the MEASUREMENT of an open question, a syntax bug manufactures a false negative that arms the documented WIDER fallback.
metadata:
  type: feedback
---

**Run the artifact's own parser before grading its content, and then ask which BRANCH of the
procedure its failure arms.**

**Why (PR #819, ADR-072 Amendment 4 / item 29, 2026-09-18).** The new committed
`infra/supabase/migrator/docker-compose.yaml` declared the external-network attachment as

```yaml
services:
  migrator:
    networks:
      default:
        name: ${...}
        external: true      # <- name:/external: are TOP-LEVEL network keys
```

`name:` and `external:` are top-level `networks:` keys; under a **service's** own `networks:`
mapping the Compose schema refuses them. Measured: `docker compose config` ->
`services.migrator.networks.default additional properties 'name', 'external' not allowed`, with a
positive control (same block at column 0) rendering correctly. **Every fence over the file passed
anyway** — `fence-migrator-private-bind.sh` exits 0, because it greps for `ports:`/`expose:`/
Domain/`network_mode`, and a file that cannot deploy trivially publishes nothing. A fence's clean
pass is evidence about the fence's predicate, never about the manifest's validity.

**The half that makes this security-relevant rather than a build nit.** The runbook made *this
file's deploy outcome* the measurement of an UNMEASURED question ("does Coolify permit an
`external:` network at all?"), and its failure branch routed the operator to **mechanism (a), the
network-WIDENING fallback**, instructing them to record (b) as measured-unavailable. So a YAML
nesting bug does not merely fail — **it manufactures a false measurement that steers a live
cutover onto the wider posture**, against the ADR's own "prefer (b); fall back to (a) only with an
explicit written statement of what it widens." Cf.
[[feedback_walk_the_unset_path_of_a_reversible_flag]] — a named fallback is a live branch, and
anything that can trip the primary is a way of *selecting* it.

**How to apply:**
1. **Any new committed manifest — compose, workflow, systemd unit, JSON/YAML config — gets run
   through its real validator in the review**, not read. `docker compose config`, `actionlint`,
   `systemd-analyze verify`, `yq`/`jq`. Always with a POSITIVE CONTROL (the shape you believe is
   correct) so a validator that is silently not running cannot look like a pass.
2. **When a lock names a primary mechanism and a fallback, enumerate what can trip the primary**,
   and grade each against "does this failure get correctly diagnosed, or misattributed to the
   open question?" A failure mode indistinguishable from the answer is a broken measurement.
3. **When handing back a fix, verify it passes BOTH gates** — the parser *and* the fence. I
   confirmed the corrected top-level block renders under `docker compose config` and still exits 0
   under the fence before sending it.
4. **Operator-time-only pointers, same review, same class.** The cutover procedure was §6.8 while
   EIGHT carriers cited §6.6 (a different, destructive "re-bootstrap" section) — including inside a
   compose `${VAR:?message}` **interpolation error message**, i.e. the loudest failure path. A
   section-number pointer is a claim; verify it against the live heading list
   (`grep -n '^### 6\.' file`), and expect headings to be out of numeric order, which is what lets
   "see §6.6 below" read as plausible. Related:
   [[feedback_verify_the_cited_source_subsection_not_the_headline]].
