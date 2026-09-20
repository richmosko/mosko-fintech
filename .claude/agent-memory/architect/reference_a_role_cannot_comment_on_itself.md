---
name: a-role-cannot-comment-on-itself
description: A non-superuser CREATEROLE role cannot COMMENT ON ROLE itself, and Postgres refuses the self-admin grant that would fix it — measured PG 17.6; this makes every `comment on role migrator` migration supervised-superuser-only
metadata:
  type: reference
---

**`comment on role X` run as `X` fails, and no grant closes the gap.** Measured 2026-09-16 on
`public.ecr.aws/supabase/postgres:17.6.1.132` (PG 17.6), disposable cluster, with a role carrying
the ADR-072 C8 attribute set (NOINHERIT, CREATEROLE, non-superuser, LOGIN):

- `comment on role migrator` as `migrator` → `ERROR: permission denied` /
  `DETAIL: The current user must have the ADMIN option on role "migrator".`
- `grant migrator to migrator with admin option` → `ERROR: role "migrator" is a member of role
  "migrator"`. Postgres refuses self-admin **by policy**, so there is no supervised step and no
  widening short of superuser that lets the role comment on itself.

⚠ **`pg_has_role(current_user,'migrator','USAGE')` returns `t` for `migrator` itself and is NOT a
usable detector.** The real predicate is `rolsuper(current_user)` OR an `admin_option` row in
`pg_catalog.pg_auth_members` whose grantee is reachable from `current_user` — that detector is
strike-proven in `119`'s applier guard.

**Why it matters beyond the one statement:** it means **every** correction to the `migrator` role
comment is a supervised superuser act (runbook §6.3, as `supabase_admin` — `postgres` measures
`rolsuper = f` on this image). A `comment on role migrator` migration can therefore NEVER be the
ADR-072 Phase D unsupervised-trigger vehicle: it hard-fails, landing nothing and proving neither the
write path nor the §7.36 item-32 ownership transfer. `118`'s header predicted this for a *replay*;
the measurement establishes it for a **first apply** too, which is the case that actually bites.

Related: [[reference_role_comment_is_a_shared_cluster_catalog]] — `118` and `119` write the SAME
`pg_shdescription` key, so re-applying `118` after `119` silently reinstates the withdrawn text with
no error and no diff. That is what the paired pgTAP negative legs exist to observe.
See also [[feedback_execute_acl_stakes_invert_on_definer]], [[feedback_a_check_i_ran_is_not_a_check_that_exists]].
