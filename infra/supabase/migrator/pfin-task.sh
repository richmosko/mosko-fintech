#!/bin/sh
#
# pfin-task.sh — ADR-072 Amendment 8 (2026-09-18, F/CTO-ratified
# option (B), Architect's architect-a7-command-length.md). This IS the
# migrator Coolify Scheduled Task's `command`, baked into the image at
# /workspace/pfin-task.sh instead of living as a 357-byte inline literal
# in Coolify's own `scheduled_tasks.command` column.
#
# WHY THIS FILE EXISTS AT ALL — the column is too narrow for the logic
#   Coolify's `scheduled_tasks.command` is `character varying(255)`
#   (measured, never widened through v4.3.18 — see
#   database/migrations/2023_12_31_173041_create_scheduled_tasks_table.php
#   in Coolify's own tree, and ADR-072 Amendment 8's own record). The tagged
#   3-assertion literal this script replaces is 357 bytes; every rewrite
#   that fits 255 either deletes the `rc` capture below (Architect's
#   measured "dangerous finding": with it gone, a FAILED `supabase db
#   push` reports exit 0, because the shell's own exit status becomes
#   that of the LAST command, which is always the final `echo` -- this is
#   the exact vacuous-green defect class ADR-072 Amendment 6 exists to
#   close) or deletes one of the two ledger-comparison tags (turning the
#   delivery assertion into a one-sided, meaningless comparison). Neither
#   trade is acceptable -- Sec's ruling on this addendum is explicit VETO
#   on both. Baking this logic into the IMAGE instead of the Coolify
#   `command` field removes the length constraint entirely: Coolify's
#   command becomes `sh /workspace/pfin-task.sh` (26 bytes), and this
#   file carries the full logic with no byte budget at all.
#
# ⚠⚠ NAMED PROHIBITION — READ THIS BEFORE TOUCHING `rc=$?` BELOW, EVER.
#   The `rc=$?; …; exit $rc` capture below is LOAD-BEARING FOR ADR-072
#   DECISION 3 — not boilerplate, not a style choice. Measured
#   (Architect, ADR-072 Amendment 8):
#     sh -c 'false; echo TAG=x'                 -> exit 0
#     sh -c 'false; rc=$?; echo TAG=x; exit $rc' -> exit 1
#   Without it, a FAILED `db push` still exits 0 (the shell's own exit
#   status becomes the LAST command's -- always the final `echo`, which
#   always succeeds). ADR-072 Decision 3's entire fail-closed gate reads
#   THIS SCRIPT'S OWN EXIT STATUS via the Scheduled Task's `status`
#   field. **NEVER REMOVE IT TO SAVE BYTES** -- there is no byte-budget
#   reason to anymore (that was the whole point of moving this logic
#   into an image layer with no length limit), and deleting it makes
#   every failed migration report SUCCESS, forever, silently -- the
#   exact vacuous-green defect three real Phase D fires already produced
#   once, which is why Amendment 6 exists. THIS IS A NAMED PROHIBITION,
#   not a style note: do not remove `rc=$?` or `exit $rc` from this file
#   under any refactoring, ever, for any reason. If this script is ever
#   rewritten, the rewrite MUST preserve capturing `db push`'s own exit
#   status and using THAT (not any later command's) as this script's own
#   exit code.
#
# WHAT THE THREE TAGGED LINES ARE FOR (migrator-orchestrate.sh parses
#   these out of the Scheduled Task execution's own `message` field via
#   the Coolify executions API -- ADR-072 Amendment 7, #802/#808; never a
#   direct docker call, ci-migrate has no route to the docker socket):
#     PFIN-BUILD-SHA=<sha>       the image's own baked git sha
#                                (/workspace/.build-sha, Amendment 6),
#                                emitted BEFORE the apply runs, so it
#                                describes the container about to act,
#                                not one that might be replaced mid-run.
#     PFIN-LEDGER-TOP=<version>  the migrations ledger's own top row,
#                                read via `psql` under `migrator`'s own
#                                credential (already in this container's
#                                env; migrator owns
#                                supabase_migrations.schema_migrations
#                                per Amendment 5) -- emitted AFTER the
#                                apply, so it reflects what actually
#                                landed, not what was merely attempted.
#     PFIN-NEWEST-FILE=<version> the newest migration file baked into
#                                THIS image's own /workspace/supabase/
#                                migrations -- `sort -V` (version sort),
#                                never a bare `sort` (lexicographic --
#                                agrees with numeric order only while
#                                every version is the same digit-width;
#                                Sec FLAG A on #802, item 51 AC(5)).
#   A missing, malformed, or duplicated tag; a sha mismatch; or a ledger
#   mismatch each fail closed on the orchestrator's own side, with a
#   distinct exit code per case -- none of that logic lives here. This
#   script's ONLY job is to emit the three lines faithfully and exit with
#   the real apply's own status.
#
# SHAPE — deliberately NOT `set -e`. The `rc=$?` capture above IS the
#   control; `set -e` would abort this script the instant `supabase db
#   push` fails, before the two post-apply tags (which are exactly the
#   diagnostic value of a failed run -- the orchestrator's own delivery
#   assertion needs PFIN-LEDGER-TOP/PFIN-NEWEST-FILE to exist even on a
#   partial/failed apply, to tell "nothing applied" apart from "some
#   migrations applied, then one failed"). `set -u` (unset-variable
#   protection) is kept -- it costs nothing here and catches a typo'd
#   variable name before it silently expands to empty.
set -u

echo "PFIN-BUILD-SHA=$(cat /workspace/.build-sha)"

supabase db push --yes --db-url "$PROD_DB_URL" --workdir /workspace
rc=$?

echo "PFIN-LEDGER-TOP=$(psql "$PROD_DB_URL" -tAc "select max(version) from supabase_migrations.schema_migrations")"
echo "PFIN-NEWEST-FILE=$(ls /workspace/supabase/migrations | sort -V | tail -1 | cut -d_ -f1)"

exit $rc
