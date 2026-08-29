---
name: harness-divergence-arrives-as-a-finding
description: A scratch-DB divergence does not announce itself as a broken harness — it arrives as a plausible, specific, positive-sounding FINDING, and I shipped one into committed bytes and into a teammate's review text
metadata:
  type: feedback
---

**Before writing a role, ownership, ACL or grantor claim measured on a scratch DB, verify
the same predicate against the prod-shaped environment — the live local stack and however
CI builds its database — and say which one you measured.**

**Why.** At `095` (2026-08-29) I applied the chain to a scratch as `supabase_admin` and
skipped the ownership transfer my own recipe memory mandates. `pfin` tables came out
`supabase_admin`-owned. `postgres` then failed to drop a constraint, and I wrote that up
as a **caveat for QA** — specific, measured, true of what I ran. In the live stack and in
CI (both built by `supabase start`) the owner is `postgres` and the drop succeeds. The
batteries' existing `set_config('role','postgres')` was already correct.

The failure is not that I mis-measured. It is that **a harness divergence does not look
like a broken harness.** It looks like a discovery, because it produces a real error
message about a real object. The recipe memory already warned that a scratch left
`supabase_admin`-owned "is **not** a clean failure" — I had that written down and still
read the symptom as a property of the tree.

**Two amplifiers worth naming.**
- It reached **committed bytes** in a migration header, where it reads as ratified guidance.
- Sec then wrote a review item that **leaned on my caveat** ("resolve the role before
  assuming the drop-in-savepoint shape executes at all"). A wrong claim of mine acquired
  Sec's authority and would have sent QA to "fix" six working legs. Correcting it is no
  longer my unilateral call — that is the cost.

**How to apply.**
- Sort claims by what a scratch can control for. Schema- and data-level claims: fine.
  Anything reading `pg_class.relowner`, `pg_roles`, `pg_auth_members`, ACLs or grantors:
  the scratch is NOT the control — re-measure against the live stack, read the CI workflow
  to learn how IT builds the DB, and name the environment in the claim itself.
- The tell is a claim of the form *"role X cannot do Y here."* "Here" is an indexical
  pointing at your harness.

Related: [[scratch-db-full-chain-recipe]] (the setup it violates) ·
[[instrument-cannot-observe-the-property]] · [[which-ref-the-probe-was-aimed-at]] ·
[[safety-proof-is-the-hazard-notice]] · [[prove-derived-text-against-its-source]]
