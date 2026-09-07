---
name: definer-grant-hands-back-the-channel
description: A SECURITY DEFINER helper adopted to remove a table grant can hand the same forge back through its EXECUTE grant — check what the body validates (shape) vs what it must validate (truth), and check the repair path on the append-only target.
metadata:
  type: feedback
---

Adopting SECURITY DEFINER to avoid an "INVOKER + table grant" forge path closes the
TABLE door and opens a FUNCTION door. If the helper is EXECUTE-granted to
`authenticated` and the schema is PostgREST-exposed, `POST /rpc/<fn>` is the same
channel one layer in.

**Why:** SELF-345 / `111_audit_log.sql` (2026-09-05). `fn_emit_audit_log` was ruled
DEFINER on ADR-011 Decision 9's own ground — *"an INVOKER+grant path would let a user
POST forged history rows — defeating the tamper-evidence."* It stamps `users_id` from
`auth.uid()` (so no cross-tenant reach) and validates `p_surface_name` non-blank and
`p_tenant_resolution_chain` non-blank. It validates **shape, never truth**:
`trigger_source` (incl. `'cron'`), the resolution-chain TEXT, `data_as_of` and the
`subject_table`/`subject_id` locator are all caller-chosen. The migration's own
`comment on table` said *"a caller cannot POST a forged audit row through PostgREST"* —
true of the table, false of the function. The PR's own battery demonstrated it: its
cron-path legs run under `_rls.set_tenant`, which sets `role = authenticated`.

**How to apply:** on any new DEFINER function, run three checks in order.
1. **Reachability** — is the schema in `config.toml` `schemas = [...]`? If yes, every
   EXECUTE grantee is an internet-reachable caller, not an internal one.
2. **Shape vs truth** — list the parameters; for each, ask *what makes this ARGUMENT
   true?* A vocabulary CHECK bounds the value set; it does not bind the value to a fact.
   The fix shape is to bind an argument to a row the caller demonstrably wrote
   (ownership + same-transaction `xmin`), or to move the emission to an AFTER trigger on
   the real write (the `031` `fn_reclass_history_insert` shape, which cannot be called
   bare).
3. **Repairability** — if the target is append-only with UPDATE/DELETE/TRUNCATE
   trigger-blocked for ALL roles, an appended forged row is permanent and repair needs
   `DISABLE TRIGGER` / `session_replication_role = replica`, i.e. a superuser runbook.
   No cheap repair path ⇒ the finding BLOCKS rather than flags.

⚠ The tell that this is happening: the ADR argues the DEFINER posture is *forced* by a
caller that runs under the user's own session. That argument is usually right about
*why INVOKER fails* and silent about *what the EXECUTE grant then costs*. Both halves
have to be answered; the second one is the one nobody writes down.

Related: [[feedback_execute_acl_stakes_invert_on_definer]] ·
[[feedback_shared_namespace_write_has_three_axes]] ·
[[feedback_catalog_comments_carry_live_state_tallies]]
