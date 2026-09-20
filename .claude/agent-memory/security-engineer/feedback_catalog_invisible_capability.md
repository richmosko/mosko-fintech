---
name: catalog-invisible-capability
description: A capability granted by an image extension keyed to a role membership the catalog does not expose is invisible to every `pg_roles` / `has_*_privilege` assertion we write — verify it behaviourally or not at all.
metadata:
  type: feedback
---

**`rolsuper = f` and `has_parameter_privilege = f` do NOT mean a role cannot set a superuser-context GUC.**
On this Supabase image, `postgres` sets `session_replication_role` through a privileged-settings extension keyed
to `supabase_privileged_role` membership — **invisible to catalog checks and absent from this repository
entirely.** Measured 2026-09-16.

**Why this bites hard here:** I authored and graded the §4.2 correction that reasoned *"setting
`session_replication_role` requires actual superuser, so `postgres` cannot set it — enforced by CONSTRUCTION."*
It was a sound inference from a correct `rolsuper` measurement and it was **wrong**. The consequence is not
small: `session_replication_role = 'replica'` makes **every immutability trigger and the entire Decision-3
matched-tenant family inert** (ADR-011 D4's own amendment: an RLS-exempt writer's applicable-layer count goes to
**zero, not one**), so the identity behind the Studio console can write to audit-class tables with no
trigger-layer fence at all. **The prohibition survives; it reverts from construction to operator discipline.**

**How to apply:**
- **Never conclude "cannot" from a role-attribute read.** `rolsuper`/`rolbypassrls`/`has_parameter_privilege`
  answer *"does the catalog grant it"*, not *"can this role do it"*. An image or extension can add a path none
  of them models.
- **Any acceptance criterion of the form "role X cannot do Y" needs a BEHAVIOURAL probe** — attempt Y as X and
  assert the failure. A catalog assertion is not evidence for that claim. This is now a standing condition on
  the least-privilege `meta` role remediation.
- When writing a posture claim, prefer **"measured: attempting Y as X fails with <error>"** over
  **"X lacks attribute A, therefore cannot Y."** The second form is an inference wearing a measurement's
  clothes — see [[hazard-mechanism-vs-reachability]] and [[capability-verify-adr-db-primitives]].
