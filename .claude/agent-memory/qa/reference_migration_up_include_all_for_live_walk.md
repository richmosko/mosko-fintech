---
name: migration-up-include-all-for-live-walk
description: For a live browser walk needing new migrations, apply them non-destructively to the SHARED local stack's live "postgres" DB via `supabase migration up --local --include-all` — never `supabase db reset`, and a separately-named scratch clone (db-template-clone.sh) is NOT reachable by the running app (PostgREST/GoTrue are fixed to the "postgres" DB). SELF-265, 2026-09-04.
metadata:
  type: reference
---

A live browser walk needs the RUNNING stack's PostgREST/GoTrue containers to serve
the schema being tested — they are fixed at container-start to one database (locally,
`postgres` inside `supabase_db_mosko-fintech`), not swappable per-request. This means
[[reference_db_template_clone_tool]]'s scratch-DB clones (a separately-NAMED database
in the same cluster) are invisible to the live app; they're for pgTAP/psql-driven
verification only, not for a browser session.

**What worked (SELF-265):** from the worktree carrying the new migration files,
`supabase migration up --local` first (safe, no-op if nothing new); if it refuses
with "Found local migration files to be inserted before the last migration on remote
database" (a real, observed state: the shared DB had 099+102 applied with 100/101
missing — 102 happened not to reference 101's tables, so it applied out of order
harmlessly at some earlier point), re-run with `--include-all` after confirming the
skipped files contain no `drop`/`delete`/`truncate` (grep first). This is ADDITIVE
to the shared DB other teammates' worktrees also point at — never `db reset`, which
wipes it.

**Companion:** [[reference_magic_link_cookie_login_for_live_walks]]'s login flow
still applies unchanged on top of this — once the schema is live, log in exactly as
documented there.

**Dev server note:** the running `vite dev` process may be serving a DIFFERENT,
stale worktree (check `lsof -p <pid> | grep cwd` against the port shown by
`lsof -iTCP -sTCP:LISTEN`) — copy `api/.env` from any worktree that already has one
(the local anon key is a well-known Supabase CLI default, not a secret) into your own
worktree and start your OWN `vite dev --port <fresh>` rather than trusting whatever
is already listening on 5173.
