---
name: feedback_verify_db_fn_signature_against_migration
description: A teammate's brief describing a DB function's parameter list is a claim, not a fact — read the applied migration file before designing the mount contract around it.
metadata:
  type: feedback
---

On SELF-229, team-lead's brief described `pfin.fn_aggregation_has_stale_constituent()` as
taking `(p_users_id, p_scope_filter)`. The applied migration (`046_fn_aggregation_has_stale_constituent.sql`)
takes ZERO parameters — it's a whole-user aggregate, not scoped per surface/account. Reading
the migration directly (not the brief, not the component's own header comments, which can
also drift) was the only way to catch this before designing four components around a
per-surface scope filter that doesn't exist.

**Why:** this team's culture (see the shared MEMORY.md verification-discipline entries)
treats a brief's description of a contract as a claim to verify, not a fact to build from —
"brief-drift-catch" is a load-bearing habit here, not paranoia. In this case the drift would
have produced a plausible-looking but wrong mount contract (per-surface scoped staleness
reads that don't exist) if I'd trusted the brief.

**How to apply:** before wiring any Frontend surface to a Backend/Architect-owned RPC, grep
the applied `supabase/migrations/*.sql` file for the function signature and its own CONTRACT
comment block — that's the source of truth, not a teammate's paraphrase of it, and not even
the frontend `.ts` mirror's own header (which can also predate a later-reconciled migration —
see `feedback_stale_component_header_vs_migration.md`-class drift).
