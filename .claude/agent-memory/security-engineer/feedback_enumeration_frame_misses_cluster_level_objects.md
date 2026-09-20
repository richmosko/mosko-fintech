---
name: enumeration-frame-misses-cluster-level-objects
description: A "what does this create OUTSIDE schema X" enumeration is framed on schemas, so it is structurally blind to roles, role memberships, and other cluster-level objects — and reports a confident EMPTY SET over the very things the change turns on.
metadata:
  type: feedback
---

**Grade an enumeration by the SET ITS METHOD CAN RANGE OVER, not by whether it came back empty.**
"Zero objects created outside `pfin`, static and live" was correct and well-executed — two independent
methods, and my own re-run of the static half agreed — and it was **silent about the objects that
actually mattered**, because both halves are framed on *schemas*.

**Why:** roles, role memberships, `alter default privileges` defaults, database-level `ALTER DATABASE …
SET`, event triggers and publications are **not in any schema**. A static grep for
`create <kind> <schema>.<name>` and a live census over `pg_class`/`pg_proc`/`pg_type`/`pg_namespace`
both range over schema-resident objects only. The migration set created **three roles** and granted
`service_role` to two of them; neither leg reads `pg_authid` or `pg_auth_members`. The reorder the
enumeration was gating turned entirely on those rows, and the confident empty set read as clearance.

**How to apply:** when handed an "everything outside X" enumeration, ask **what catalog each leg reads**
and name the registers it does not touch — `pg_authid`, `pg_auth_members`, `pg_db_role_setting`,
`pg_default_acl`, `pg_event_trigger`, `pg_publication`, `pg_database`. Then say the grade in two parts:
**ESTABLISHED for <the measured set>, NOT MEASURED for <the named remainder>** — never "empty set",
which reads as a property of the world rather than of the instrument. Same shape as
[[a-grep-over-comments-measures-intent-not-data]] and [[state-what-the-count-is-over]]. And note the
downstream cost: the runbook and the standup both restated the flat "empty" — one unqualified
measurement fans out into every artifact that cites it.

**Second instance, 2026-09-18 (ADR-072 BACKLOG item 52).** A booked item stated the blast radius as *"the gate is per-APPLICATION, so the reach is every task on it"* — but its own cited evidence was `api.ability:write` (an **ability**, not a resource scope) plus `authorize('update', …)` described as **resource-ownership**. Ownership is a property of the **team**, so on a solo-operator instance the reach is plausibly every scheduled task on **every** application. **An ability is not a scope, and an ownership check is not a per-resource restriction.** The narrow framing also made a gap read as live when it was an **empty set today** — and an empty set with no watcher is where a future addition silently enters, so the narrow reading needs an explicit **arming condition**. Ask: what is the unit the grant is actually attached to, and does the item's citation establish that unit or merely assume it?

**Third instance, 2026-09-18 — the frame missed the SCHEMA.** A premise inventory for a vendor-API chain swept `routes/api.php`, controllers, models and helpers, and was declared complete. The next premise to be falsified was **`scheduled_tasks.command` is `varchar(255)`** — the third vendor-shape premise to break (after a socket route and a single-task GET route). **It read no migration and no schema. A column width is a premise exactly as much as a route's existence is.** When enumerating premises about an external system, enumerate over its *schema constraints on every field you write or compare*, not only over its route/handler surface.
