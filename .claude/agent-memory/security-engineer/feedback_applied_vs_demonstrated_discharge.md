---
name: applied-vs-demonstrated-discharge
description: Before recording a booked fix as discharged, ask whether the evidence compares against a DIFFERENT baseline and whether the discriminating instance even exists — a same-recipe diff proves no-drift, not parity, and a flag can be currently inert
metadata:
  type: feedback
---

**Discharging a booked fix has two independent halves — APPLIED and DEMONSTRATED — and evidence
usually establishes only the first.** Say which one you are signing.

**Why:** the loop-mechanics template-DB tooling (2026-09-03) was offered against the BACKLOG §7.14
*scratch-harness ACL parity* booking, whose fix half reads *"mirror the bootstrap in both directions
(grants present AND revokes present) in any scratch-verification harness."* DevOps's evidence was a
full GRANT/REVOKE diff, **byte-identical 177/177**, between a template-clone and a hand-built
sequential control.

Two things were wrong with treating that as discharge, and both generalize:

1. **Same-recipe baseline.** Both sides of that diff come from the same script. It proves the
   template/clone step introduces no drift; it is **structurally incapable** of detecting
   harness-vs-BOOTSTRAP divergence, which is the only thing the booking is about. *Name the
   baseline* — a diff whose two sides share the suspected error is invariance, not agreement. The
   useful probe compares against a **differently-produced** artifact: I diffed the template against
   the live Supabase-bootstrapped `postgres` DB — `pfin` `relacl` identical across 39 relations,
   schema USAGE `anon/authenticated/service_role` = false/true/true on both, `auth`/`vault`/`storage`
   function `proacl` non-NULL and matching (the 2026-08-12 NULL-proacl symptom does not reproduce).
   *That* is parity evidence.

2. **The discriminating instance may not exist.** Measured across `auth`/`vault`/`extensions`/
   `storage`/`graphql`: **zero** functions with PUBLIC EXECUTE revoked, in either database. So the
   REVOKE axis — precisely what `--no-privileges` destroys — has nothing to preserve on this cluster
   today. The `--no-privileges` omission is correct and unfalsified, but **not load-bearing that
   anyone can currently show.** Recording that as "demonstrated" would leave a flag whose proof
   nobody can reproduce, which is how a control gets removed later as decoration.
   **Discharge condition to hand back instead of a verdict:** build once WITH the bad flag and diff
   the ACL census. A delta ⇒ demonstrated, and it becomes the regression fixture. No delta ⇒ *that
   is the finding* — record the protection as prospective so nobody "cleans it up" believing it was
   proven.

**How to apply:**
- Ask of any parity evidence: *what produced each side?* If the answer is the same recipe, downgrade
  the claim to no-drift and go find a differently-produced baseline yourself — it is usually one
  `psql` away.
- Before signing a hazard as fixed, **grep for a live instance of the hazard's own precondition.**
  A hazard with zero current instances is still worth fencing, but the fence's status is
  *prospective*, and that word belongs in the record.
- Raw parity numbers mislead in both directions: a 55-vs-52 function-count gap in `extensions`
  looked like a real divergence and resolved to `pg_stat_statements` alone — observability, absent
  from the template, fails LOUD if ever needed. **Identify the delta before grading it**; an
  unidentified count is not a finding.

Related: [[verify-the-stated-correctness-mechanism]] ·
[[clearance-conditions-must-absorb-my-own-recommendations]] ·
[[corrupt-the-control-canary-boundary-tie]]
