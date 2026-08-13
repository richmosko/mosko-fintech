---
name: feedback-postgres-roles-are-cluster-level-not-per-db
description: An incident, not a near-miss — ran ALTER ROLE pfin_etl LOGIN PASSWORD against my scratch database, on the wrong assumption the role attribute was scoped to the database connected to. Roles are cluster-level; this overwrote the real shared credential's password verifier cluster-wide, unrecoverably. 2026-08-12, SELF-217 write-path integration harness.
metadata:
  type: feedback
---

Built a Python integration-test scratch-DB harness (SELF-217's `NavBackfillWorker`
write-path tests) and armed the login role it needed by running
`ALTER ROLE pfin_etl LOGIN PASSWORD '<scratch-only value>';` against my scratch
database. This ran TWICE across two harness iterations, and neither restored
`NOLOGIN` afterward — the teardown only dropped the scratch *database*.

**Postgres roles live in `pg_authid`, a CLUSTER-WIDE catalog — not a per-database
table.** `ALTER ROLE` has no database scope no matter which database the issuing
connection happens to be on. `pfin_etl` is the SAME role real workers connect as
on the SAME local Postgres cluster my scratch databases live on (they're
different *databases*, not different *clusters*) — so this command silently
overwrote the real role's password verifier (a SCRAM hash) with my scratch
value, cluster-wide, and left `rolcanlogin = true` on a role documented
elsewhere (this repo's own credential-rotation convention) as "should be OFF
between uses." The real password is gone: Postgres stores only the verifier,
never the plaintext, so there is no path back to the original — only reissuing
a new one.

**Why this slipped through despite already knowing the fact:** I had a memory
note about this exact role's LOGIN-arming convention (`ALTER ROLE pfin_etl
LOGIN` / disarm between uses / "the credential is unrecoverable if lost") and
still ran the mutating command against what I believed was an isolated scratch
context. Knowing a fact in the abstract did not surface it at the moment a
DIFFERENT-looking action (arming a role for MY OWN scratch DB) was actually the
same class of action the note was warning about. The database name was scratch;
the role was not.

**How to apply — the general rule, not just this role:** before running any
`ALTER ROLE` / `CREATE ROLE` / `DROP ROLE` / `GRANT <role> TO <role>` while
connected to a scratch or throwaway database, ask explicitly: *is this
statement scoped to the database I'm connected to, or to the cluster?* Roles,
tablespaces, and a handful of other objects (`ALTER SYSTEM`, `pg_hba.conf`) are
cluster-level; nearly everything else (tables, schemas, extensions, functions,
most GRANTs on objects) is database-scoped. When a test harness needs a login
role, CREATE a throwaway one scoped to that harness's own lifecycle (create in
setup, drop in teardown, name it distinctly from anything a real migration
creates) — never reuse or arm a role a real system also depends on, even
"just for a scratch DB," because the role itself is never scratch.
[[feedback_scratch_db_pgtap_harness_gotchas]] is the adjacent lesson about this
same harness class (a scratch DB that under-mirrors the real bootstrap, in the
PERMISSIVE direction); this one is closer to
[[feedback_never_write_into_a_teammates_worktree]] in shape — both are "the
blast radius of this action is wider than the sandbox I thought I was
operating in."
