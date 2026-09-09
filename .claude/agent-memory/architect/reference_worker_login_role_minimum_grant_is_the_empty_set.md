---
name: worker-login-role-minimum-grant-is-the-empty-set
description: For a NOINHERIT worker login role behind a TenantBoundClient/Connection, the minimum object-privilege set is EMPTY — and granting EXECUTE to it is a widening, not a hardening.
metadata:
  type: reference
---

A dedicated `NOINHERIT` login role for a worker (`pfin_etl` @ `055`, `pfin_provider_sync`
@ `116`) gets **role memberships only and zero object privileges** — no schema `USAGE`,
no table privilege, no function `EXECUTE`, no sequence, no default ACL.

**Why:** every statement the worker issues runs inside `TenantBoundClient.withTenant()` /
`.withServiceRole()` (Node) or `TenantBoundConnection` (Python), and both open a
transaction and issue their `set local role` **before** the caller's callback runs. The
sole raw-client construction site is CI-fenced (`scripts/ci/fence-tbc-node.sh`,
`fence-tbc-pfin-back-etl.sh`). So **no statement is ever evaluated with the login role as
the effective role.** Measure this by reading the client class, not by enumerating the
worker's SQL — the SQL inventory tells you what the *assumed* roles need, which is already
decided elsewhere (`008` + per-migration grants).

⚠ **The EXECUTE inversion — the intuition runs backwards.** `EXECUTE` is checked against
the **current effective role**. A SECURITY DEFINER function the worker reaches needs **no
grant to the login role**, and granting one would be a **WIDENING**: it makes the function
reachable *without* a `SET ROLE`, defeating the NOINHERIT property the role exists to
hold. DEFINER functions in a worker's blast radius are typically reached as **triggers**
on tables it writes — a trigger function's privileges are not checked against the
statement's caller.

**How to apply:** when a brief says "grant only the minimum the worker exercises", the
answer for the LOGIN role is *nothing*. Say so explicitly and record the object inventory
as the evidence the decision was measured against, so a reviewer checks the reasoning
rather than the conclusion. Related: [[reference_agent_worktree_location]],
[[feedback_execute_acl_stakes_invert_on_definer]].
