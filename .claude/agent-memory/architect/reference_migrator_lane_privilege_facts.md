---
name: migrator-lane-privilege-facts
description: Four measured Postgres/Supabase-CLI facts that decided ADR-072 Amendment 5 — CREATE-time view checks ignore security_invoker, name-resolution needs schema USAGE, the CLI records a ledger row for a file that did nothing, and role-graph statements are unreachable for any bounded applier
metadata:
  type: reference
---

Measured 2026-09-16 on `public.ecr.aws/supabase/postgres:17.6.1.132` (PG 17.6) with
`supabase db push` v2.105.0, disposable cluster. Each of these changed a ruled decision.

**1. `security_invoker = true` does NOT move the CREATE-time permission check.** A view body
is permission-checked **when the view is created**, regardless of the option; `security_invoker`
moves only the RUNTIME identity. So `create view … with (security_invoker = true) as select …
from vault.decrypted_secrets` **fails for a creator with no vault privilege**. ⚠ This falsified
a ratified basis clause ("the owner's vault dependency is removed — wall 2 deleted"): the wall
is **narrowed to CREATE time**, not deleted. The option is still load-bearing as a **component** —
`ALTER VIEW … OWNER TO` succeeds without re-validating the body, but under the default the view
then executes as its vault-less owner and is **broken**.

**2. `has_table_privilege(role,'schema.table',…)` and `to_regclass('schema.table')` need USAGE on
the schema just to RESOLVE THE NAME.** Both raise `permission denied for schema …` for exactly the
role you are trying to test. **Probe by OID through `pg_class`/`pg_namespace`** (world-readable)
and the same call answers for any role. A name-based privilege probe inside a guard makes the
guard fail instead of skipping.

**3. A migration whose guard skips still gets a `schema_migrations` row.** The CLI records any
file that applied **without error**; it never inspects what the file did. A guard that
`RAISE WARNING`s and returns normally is a success. ⚠ So "the file is on the pre-step list" does
not by itself prevent the "applies, records a row, does nothing, forever" failure — the skip
branch must **assert** the thing the pre-step was supposed to land (read the catalog, raise on
absent AND on stale). ⚠ **Assert EQUALITY only where the file is the LAST WRITER of that object's
comment; assert EXISTENCE where a later migration deliberately supersedes it** — `117` supersedes
`055`'s role comment, so an equality check in `055` RED-fails a *correct* bootstrap.

**4. Role-graph statements are unreachable for every bounded applier, and no grant fixes it.**
`comment on role X` and `grant <app_role> to X` need superuser or **ADMIN OPTION** on the target.
Postgres **refuses self-admin** (`grant migrator to migrator` → *"role is a member of role"*), and
the image owns `service_role`/`authenticated`, so ADMIN OPTION on those is a posture veto (it is
self-grantable). ⚠ **PG 16+ auto-grants a CREATEROLE creator ADMIN OPTION on what it creates** — so
"let the applier create the worker roles instead" is a *transitive* path into `service_role`, not a
repair. These statements belong to a supervised lane, permanently.

**Corollary that decided the design:** ownership is fixed by a group role every applier enters
(`set role pfin_owner; … reset role;`), never by the applying identity — with a **deny-CREATE
engine backstop** as the primary control, because the convention is a line a human can forget.
Related: [[a-role-cannot-comment-on-itself]], [[set-local-outside-a-transaction-is-a-noop]].
