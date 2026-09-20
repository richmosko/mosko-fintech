---
name: role-creator-gets-admin-option
description: PG16+ auto-grants ADMIN OPTION to a CREATEROLE role on every role it creates — so WHICH IDENTITY APPLIES a migration silently decides role-administration edges, and a bounded-credential condition can be defeated transitively.
metadata:
  type: feedback
---

**Changing WHO applies a migration set changes the role graph, not just object ownership. In PG16+, a
non-superuser `CREATEROLE` role that creates a role is auto-granted ADMIN OPTION on it** — self-grantable,
so it can `GRANT <role> TO itself` and `SET ROLE` into it.

**Why:** ADR-072 C8 accepts the migrator's standing `CREATEROLE` as moot *because* `CREATEROLE` is
"confined to roles the migrator itself created" — a bound over an **empty set** only while `postgres`
created the worker roles. Reordering the bootstrap so `migrator` runs `055`/`116` makes that set
`{pfin_etl, pfin_provider_sync}`. Both are `grant service_role to …` recipients, so the chain
**migrator → self-grant worker role → SET ROLE → service_role** defeats C8's own second sentence
("must NOT be a member of `service_role`/`authenticated`/any app role") **transitively**, without any
statement that looks like a membership grant. A superuser creator does NOT auto-grant, so the same
migration set produces different privilege graphs under different appliers.

**How to apply:**
- On any proposal that changes the applying identity: ask **"which roles does the new applier CREATE?"**
  before asking about object ownership. Grep the set for `create role`.
- **Role creation belongs in the supervised superuser pre-step under every shape** — never inside the
  bounded-applier or group-owner pass. This kills the tempting repair to "`comment on role` is refused,
  so drop the roles and let the applier re-create them": that repair BUYS the ADMIN OPTION.
- A group-owner role (`pfin_owner`-shaped) must **not** hold `CREATEROLE` — members reach whatever it holds.
- **`set local role X` is a convenience boundary, not a privilege boundary**: any member with SET enters
  at will, so whatever the group role holds, the standing credential reaches. Say that out loud when
  accepting a group-owner design, or the residual gets assumed away.
- An ownership census over `pg_class`/`pg_proc`/`pg_type`/`pg_namespace` **cannot see any of this**. Roles
  and memberships live outside every schema — see [[enumeration-frame-misses-cluster-level-objects]].
- Related walls under a non-superuser applier: `comment on role` needs superuser **or** ADMIN OPTION and
  is **unfixable for the applier itself**; `pg_authid` reads take `insufficient_privilege` and can make a
  guard stop guarding silently. ⚠ Never remediate that by granting `pg_authid`/`pg_read_all_data` — that
  hands every SCRAM verifier in the cluster to a standing credential.

## ⚠ `pg_has_role` privilege mode: GUARD → `USAGE`, WATCHER → `MEMBER`. Do not unify them.
Under NOINHERIT the two diverge, and **which one is correct depends on what the leg is for**:
- A **WATCHER** asserting "this role does not hold X" must use **`MEMBER`** — `USAGE` (and
  `has_table_privilege`) **stay false through the violation**, because a NOINHERIT membership confers nothing
  by inheritance. It **under**-reports, so a watcher built on it is green while the grant sits latent, one
  `SET ROLE` from live. That is how `781`'s `(g1)`–`(g3)` were falsified.
- A **GUARD** that gates a privileged statement should use **`USAGE`**. The same under-reporting is now
  **fail-closed**: the guard raises in a case where a `SET ROLE` might have let the statement through. Refusing
  when you might have succeeded is the right error direction for a gate.
**How to apply:** when reviewing a `pg_has_role` leg, ask *"is this observing or deciding?"* first, then check
the mode matches. And when a reviewer is tempted to "make them consistent," say which is which and why — a
guard changed to `MEMBER` starts permitting statements that then fail anyway, and a watcher changed to `USAGE`
stops watching.
