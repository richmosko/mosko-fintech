#!/usr/bin/env bash
#
# migrator-orchestrate.sh — ADR-072 (Option E) chunk 2: the forced-command
# script that IS the `ci-migrate` SSH trigger (Decision 2 C2/C4/C5). Runs AS
# `ci-migrate` on the production box, invoked ONLY via that user's
# authorized_keys forced command — never run directly, never run as any
# other user. DevOps-owned; materialized onto the box (root-owned, mode 0755,
# NOT writable by ci-migrate) by scripts/provision-vps.sh, which is the
# versioned source of truth for what's on the box (ADR-072 Decision 5,
# box-side update channel).
#
# WHAT THIS SCRIPT REFUSES TO DO (Sec C2 — load-bearing, read before editing)
#   It NEVER reads, evals, or dispatches on $SSH_ORIGINAL_COMMAND. A forced
#   command already ignores it in the sense that sshd runs THIS script
#   regardless of what the client asked for — C2 goes further: this script's
#   OWN body must not even reference the variable, because a future edit that
#   starts reading it for "convenience" (e.g. a --dry-run flag from the
#   client) reopens exactly the client-controlled-dispatch hole the forced
#   command exists to close. If you are about to add
#   `case "$SSH_ORIGINAL_COMMAND" in ...` to this file, stop — that is the
#   change C2 forbids, not a refinement of it. Every input this script acts
#   on comes from the box-resident config file below, never from the
#   invoking SSH session.
#
# WHAT IT DOES (ADR-072 Decision 2 + Decision 3 + Amendment 6/7/8 + BACKLOG
# §7.36 item 59)
#   0. DEPLOY (rebuild) the migrator resource FIRST and assert the finished
#      deployment's own `commit` field equals MIGRATOR_EXPECT_SHA — ADR-072
#      Decision 5(1)'s "rebuild -> run task -> deploy app" sequencing,
#      built by item 59 (see that section's own header comment, below the
#      pre-fire task-command integrity check, for the full design).
#   1. Execute the migrator Coolify Scheduled Task (the `supabase db push`
#      apply, scripts/migrator-scheduled-task.md).
#   2. Poll that task's own execution status to a terminal state — NEVER
#      Coolify's deployment status (that swallows a post-deploy-command
#      failure; this is the exact D-shaped trap ADR-072 Decision 3 records).
#   3. On SUCCESS: assert OUTCOME, not just status (ADR-072 Amendment 6/7) —
#      but via the EXECUTION'S OWN REPORTED OUTPUT (Coolify's
#      `.../executions` API `message` field), NEVER a direct `docker`
#      call. ⚠ CHANGED 2026-09-17 (Amendment 7 draft): this script used to
#      run `docker compose exec` directly against the box for both the
#      pre-fire sha-check and the post-run delivery assertion. Sec's C-1
#      finding + F/CTO's box measurement: `ci-migrate` has NO route to
#      `/var/run/docker.sock` (no group, no ACL, no sudo) — a direct
#      `docker compose exec` as `ci-migrate` cannot succeed (permission
#      denied, exit 1, measured live). ⚠ CORRECTED (Sec, carried from
#      #800's review): "has always failed closed" overstated this as
#      EVENT HISTORY -- Amendment 7 §(F) is that these assertions never
#      actually executed on the box at all; "cannot succeed" is the
#      accurate form, a capability claim, not a record of past runs. The
#      three earlier "successful" fires only ever worked through the
#      Coolify API alone. Every docker call is REMOVED from
#      this script. The migrator Scheduled Task's own `command`
#      (scripts/migrator-scheduled-task.md) now emits three tagged lines
#      on its own stdout — `PFIN-BUILD-SHA=`, `PFIN-LEDGER-TOP=`,
#      `PFIN-NEWEST-FILE=` — which Coolify captures into the execution's
#      `message` field (ScheduledTaskJob's own success path -- measured
#      from Coolify v4.3.18 source for ADR-072 Amendment 7's design; see
#      that amendment's own record for the full source-cited measurement
#      of that field). This script parses those
#      three tags out of `message` and asserts: PFIN-BUILD-SHA equals
#      MIGRATOR_EXPECT_SHA (byte-exact), and PFIN-LEDGER-TOP equals
#      PFIN-NEWEST-FILE. A missing/malformed tag, a sha mismatch, or a
#      ledger mismatch each exits non-zero on a DISTINCT code and does
#      NOT deploy, even though the Scheduled Task itself reported success.
#      Only once both assertions pass: trigger the app deploy. On FAILURE,
#      a poll timeout, or any assertion failure: exit non-zero and do NOT
#      deploy — the existing Coolify->Discord Scheduled-Task-failure
#      routing fires on its own for a `failed` status; this script's own
#      log line (including a tail of the execution's raw `message`, for a
#      `failed` status) is the record otherwise.
#   ⚠ STATUS: Amendment 7 is RATIFIED (F/CTO, 2026-09-18) and its design is
#   BUILT (this file, #801/#802/#808/#814) — this paragraph previously read
#   "DRAFT — NOT TO MERGE BEFORE ADR-072 AMENDMENT 7 IS RATIFIED"; that line
#   is corrected here rather than left to mislead a future reader into
#   thinking the sha/delivery checks below are still provisional. The sha
#   and delivery checks below do NOT gate BEFORE the Scheduled Task fires
#   (they can't — nothing here can read the container's state without
#   docker access) — they are asserted AFTER a successful run, against
#   that same run's own self-reported output. If the assertions ever fail,
#   the `db push` this run fired has ALREADY executed against whatever
#   image/state existed at fire time; the app deploy is withheld, but the
#   migration apply itself is not undone. This is a deliberate, named
#   tradeoff of Amendment 7's design (the alternative being no outcome
#   assertion at all, since ci-migrate cannot reach the socket to check
#   anything beforehand) — Architect/Sec/F/CTO's call, not mine to soften
#   or work around here. ⚠ Item 59's new deploy-then-execute step (below)
#   narrows how OFTEN this tradeoff can bite — a fresh image at fire time
#   is now the common case, not an accident of timing — but does not
#   remove it: the deploy's own commit assertion happens before execute,
#   the tag-based assertions here still happen after it, by necessity.
#
#   The calling GitHub Actions workflow gates on THIS script's own SSH exit
#   code — GHA's native step-sequencing is the fail-closed gate (ADR-072
#   Consequences / this ADR's GitHub Actions item): a non-zero exit here
#   fails the SSH step, which fails the job, which stops the workflow before
#   anything downstream runs. There is no separate "poll Coolify" step in the
#   workflow — polling happens HERE, inside the one orchestrated unit whose
#   exit code the SSH channel carries.
#
#   ⚠ EXECUTION BINDING BY UUID SET DIFFERENCE (added after the first real
#   fire, 2026-09-18) — the poll loop and the tag-extraction read do NOT
#   trust `rows[0]` ("the latest execution") from Coolify's
#   `.../executions` API. Measured from Coolify v4.3.18 source
#   (app/Http/Controllers/Api/ScheduledTasksController.php's execute
#   endpoint, app/Jobs/ScheduledTaskJob.php): `POST .../execute` returns
#   only `{"message": "..."}`, no execution identifier, and the execution
#   row itself is created inside the QUEUED job's `handle()` — i.e. only
#   once a queue worker actually starts processing the dispatch, never at
#   `POST /execute`'s response. There is therefore a real window, after
#   this script's execute call returns, during which the execution this
#   fire caused does not exist yet — and `rows[0]` during that window is
#   necessarily a PREVIOUS execution, not this one. The first real fire
#   landed in exactly that window: it read a 2026-09-17 pre-Amendment-8
#   row (status=success, no PFIN-* tags) and exited 8 — fail-closed that
#   time only because the stale row happened to carry no tags. From this
#   fire onward the newest prior row DOES carry valid tags, so a stale
#   `rows[0]` read on a re-fire against the SAME image would pass every
#   assertion below on evidence a DIFFERENT run produced — a latent
#   fail-open, not a fail-closed near-miss.
#
#   Fix: before firing, snapshot the set of execution UUIDs already
#   present ($PRE_FIRE_UUIDS). After firing, each poll iteration computes
#   the CURRENT uuid set minus that snapshot and requires EXACTLY ONE
#   member before proceeding — zero new uuids keeps polling within the
#   existing ceiling (exit 13 if the ceiling expires with none seen); two
#   or more new uuids fails closed immediately (exit 14, a concurrent
#   fire — e.g. another operator firing from the Coolify UI; this
#   script's own `flock` only bars a second copy of itself). Once exactly
#   one new uuid is identified, every subsequent poll and the final
#   status/message read are keyed to THAT uuid specifically, never to
#   position. uuid-set-difference was chosen over a `created_at`-ordering
#   inference (the other candidate) because it is an IDENTITY binding —
#   immune to timestamp-column precision and to any TOCTOU window between
#   the pre-fire snapshot and the fire itself, both of which a
#   timestamp-inference binding would depend on.
#
#   ⚠ Sec joint review on this binding (PR #814, 2026-09-18): every
#   API-sourced uuid interpolated into a `jqp` Python literal is now
#   shape-guarded first (`^[a-z0-9]{24}$`, exit 15 -- a DISTINCT code from
#   the parse-failure family, since a malformed-shape uuid still parses
#   as valid JSON). And the Coolify API token is no longer passed as an
#   argv-visible `curl -H` (readable via `ps`) -- `api()` now uses a
#   `--config` file, mode 0600 by this script's own `umask 077`, removed
#   by an EXIT trap (BACKLOG.md item 52 AC(3)'s constraint on the
#   machine path, matching the standard already required of the
#   runbook's human-operator path).
#
# CONFIGURATION — box-resident only, never client-supplied
#   /etc/pfin/migrator-trigger.conf   Non-secret: MIGRATOR_SERVICE_UUID,
#                                     MIGRATOR_TASK_UUID, APP_UUID. Written by
#                                     provision-vps.sh from the operator's
#                                     local .env (these UUIDs come from the
#                                     Coolify resources chunk 1 documents
#                                     creating — see
#                                     scripts/migrator-scheduled-task.md).
#   /etc/pfin/migrator-coolify-token.env
#                                     `COOLIFY_API_TOKEN=...` — the SCOPED
#                                     token this box mints for exactly this
#                                     script (ADR-072 C4/C5; see
#                                     provision-vps.sh's "migrator trigger
#                                     token" step for how it's minted and why
#                                     its abilities are `read,write,deploy`,
#                                     NOT `root`). Owned ci-migrate:ci-migrate,
#                                     mode 0600 — root mints it, chowns it to
#                                     ci-migrate, and this script (running AS
#                                     ci-migrate) is the only reader.
#
# WHY THE COOLIFY API IS REACHED ON localhost:8000 FROM HERE
#   Coolify's API/dashboard is not publicly reachable at all (ADR-072
#   Decision 2, measured) — :8000 has no Traefik route and is excluded from
#   the box firewall. This script runs ON the box (as the SSH session's
#   remote command), so `localhost:8000` is reachable from inside it exactly
#   the way an operator's own SSH-tunneled `curl` reaches it today
#   (docs/deployment-runbook.md §3's explicit-deploy pattern) — this script
#   is that same curl, invoked by CI instead of by a human.
set -euo pipefail

# ⚠ ADR-072 Amendment 6 -- SINGLE-INVOCATION LOCK (Sec finding on PR #796,
# 2026-09-17): this script previously held no lock at all. GitHub Actions'
# own concurrency group (migrator-trigger.yml's `concurrency:` block)
# serializes push vs `workflow_dispatch` triggers -- but the manual `ssh
# ci-migrate@box` emergency-fire path (§6.7's own recipe; an operator
# during an incident) is OUTSIDE Actions entirely and that group does not
# reach it. Two concurrent `supabase db push` runs against the SAME
# production database is a schema-integrity risk this script must refuse
# by construction, not rely on every caller to avoid.
# FAIL-FAST, never wait: a second invocation that BLOCKED on the lock
# would, once it finally acquired it, assert its own MIGRATOR_EXPECT_SHA
# against a container state that may have changed while it waited (the
# first run may have triggered a rebuild/redeploy) -- waiting produces a
# stale check, not a safe queue. Refuse immediately instead, with a
# distinct exit code the caller can tell apart from every other failure
# mode this script has. This also bounds BACKLOG §7.36 item 49's blocked-
# exec window: a second fire while one is stuck is refused immediately,
# not queued behind it.
# ⚠ LOCK_FILE here MUST match LOCK_FILE_PATH in scripts/provision-vps.sh --
# one path, asserted in both files, not two copies that can drift (Sec
# FLAG 3 on PR #800: this cross-reference was missing the first time and
# nothing tied the two literals together; matches the existing
# TOKEN_VAR_NAME / MIGRATOR_TOKEN_VAR_NAME convention above).
#
# ⚠ MOVED off /var/lock, 2026-09-18 (Sec FLAG 2 on PR #800, confirmed live
# by F/CTO's box measurement: `readlink -f /var/lock` -> `/run/lock`,
# `findmnt -no FSTYPE /run/lock` -> `tmpfs`). /var/lock's target is
# tmpfs -- cleared on every reboot -- so a file provisioned there does
# NOT survive a reboot; the ownership wedge (whoever creates it first
# owns it) reopens on every boot until provision-vps.sh's --apply is
# re-run by hand. LOCK_FILE now lives under /run/lock/pfin/, a directory
# provision-vps.sh provisions via a systemd-tmpfiles drop-in (`d
# /run/lock/pfin 0750 ci-migrate ci-migrate -`) so it is RECREATED
# correctly-owned by systemd-tmpfiles-setup.service on every boot, before
# anything else can race to create it first. The file-level type gate
# (regular-file-only) and `chown -h` in provision-vps.sh's lock-file step
# are KEPT as defense-in-depth even though a 0750 directory (vs. the old
# 1777 /var/lock) already closes the unprivileged-attacker symlink vector
# -- an operator running a debug command AS ROOT bypasses directory
# permissions entirely and could still leave the file wrong-owned or
# symlinked, which is the same failure class Sec's C-2/FLAG-1 findings
# were about in the first place.
LOCK_FILE="/run/lock/pfin/pfin-migrator-orchestrate.lock"
# ⚠ Sec FLAG on PR #804 (2026-09-18): this script set no umask, so
# `exec 200>"$LOCK_FILE"` created a first-acquire lock file under
# whatever umask it inherited -- typically 022, i.e. mode 0644, not the
# 0600 provision-vps.sh's DESIRED_LOCK_STATE compares for exact equality
# against. That mismatch is ROUTINE, not an edge case: reboot -> tmpfiles
# recreates the directory empty -> the next fire creates the lock file
# 0644 -> the next --apply preflight sees "644 != 600" and `die`s with a
# message claiming every future run will exit 7 (lock unopenable) --
# FALSE, since a 0644 file owned by ci-migrate opens for write by
# ci-migrate perfectly well. The failure direction was safe but the
# message misdescribed a healthy box as broken. Sec's preferred fix (of
# three offered): make the 0600 invariant true BY CONSTRUCTION rather
# than by after-the-fact correction, so provision-vps.sh's strict
# exact-mode compare stays strict AND stays honest.
umask 077
exec 200>"$LOCK_FILE" || { printf '[migrator-orchestrate] FAIL (exit 7): could not open %s for locking\n' "$LOCK_FILE" >&2; exit 7; }
if ! flock -n 200; then
  printf '[migrator-orchestrate] FAIL (exit 7): another migrator-orchestrate.sh invocation already holds the lock (%s) -- refusing to run concurrently against production. Fail-fast by design (Sec, ADR-072 Amendment 6): a queued second run would assert against a container state that can change while it waits, not a safe serialization. Wait for the other invocation to finish (or fail) and re-fire.\n' "$LOCK_FILE" >&2
  exit 7
fi

CONF_FILE="/etc/pfin/migrator-trigger.conf"
TOKEN_FILE="/etc/pfin/migrator-coolify-token.env"
# TOKEN_VAR_NAME must match MIGRATOR_TOKEN_VAR_NAME in scripts/provision-vps.sh
# -- one name, asserted in both files, not two copies that can drift.
TOKEN_VAR_NAME="COOLIFY_API_TOKEN"
COOLIFY_BASE="http://localhost:8000/api/v1"
POLL_INTERVAL_S=5
POLL_MAX_ATTEMPTS=120   # 120 * 5s = 10 minutes ceiling on the migration apply

log() { printf '[migrator-orchestrate] %s\n' "$*" >&2; }
fail() { log "FAIL: $*"; exit 1; }

[[ -r "$CONF_FILE" ]] || fail "missing or unreadable $CONF_FILE — provision-vps.sh must materialize this before the trigger is usable"
[[ -r "$TOKEN_FILE" ]] || fail "missing or unreadable $TOKEN_FILE — provision-vps.sh must mint the scoped migrator-trigger Coolify token before the trigger is usable"

# 2026-09-16 incident: this used to `source` both files under `set -a`.
# $TOKEN_FILE on the box held the bare token VALUE with no `NAME=` prefix
# (a stale write from before the writer's current format) -- `source`
# executed that value as a shell command, printing it to F/CTO's terminal.
# Never execute box-resident file content as commands, even root-authored,
# never-client-input content: read each expected NAME by grep, not by
# sourcing. A malformed file (missing prefix, garbage, anything) then
# yields an EMPTY variable, not an executed line -- caught by the `:?`
# guards below, never by bash's command dispatcher.
read_kv() { # read_kv <file> <name>
  grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2- || true
}
MIGRATOR_SERVICE_UUID="$(read_kv "$CONF_FILE" MIGRATOR_SERVICE_UUID)"
MIGRATOR_TASK_UUID="$(read_kv "$CONF_FILE" MIGRATOR_TASK_UUID)"
APP_UUID="$(read_kv "$CONF_FILE" APP_UUID)"
DEPLOY_ON_SUCCESS="$(read_kv "$CONF_FILE" DEPLOY_ON_SUCCESS)"
# ⚠ BACKLOG.md §7.36 item 59 (ADR-072 Amendment 6 consequence (i)) — the
# name guard in the new "deploy the migrator resource" section below.
# Defaulted, not required-or-die: a box provisioned before this variable
# existed in provision-vps.sh's conf writer still gets the correct value
# (matching scripts/provision-migrator-app.sh's own MIGRATOR_APP_NAME
# default), so this guard activates immediately on every existing box
# without a re-provision being a precondition for it to fail closed.
MIGRATOR_APP_NAME="$(read_kv "$CONF_FILE" MIGRATOR_APP_NAME)"
: "${MIGRATOR_APP_NAME:=pfin-migrator}"
# ⚠ Sec FLAG on Amendment 7 (2026-09-17), measured against Coolify v4.3.18
# source for this amendment's design (see that amendment's own record):
# `PATCH /applications/{uuid}/scheduled-tasks/{task_uuid}` is gated ONLY by
# `api.ability:write` (routes/api.php:413 -> ScheduledTasksController::
# update_scheduled_task_by_application_uuid -> updateTask(), which allowlists
# `command` as a plain unrestricted string field, :134/:138 -- measured for
# ADR-072 Amendment 7's design; see that amendment's own record for the
# full route/controller citation). The trigger
# token this script holds ([read,write,deploy], ADR-072 Amendment 2) can
# reach that route -- so can anyone else who obtains the token, or an
# operator editing the task by hand in the Coolify UI. Either way: nothing
# stops the Scheduled Task's `command` from silently drifting away from what
# provision-vps.sh most recently wrote and what this script's tag-parsing
# below assumes it's reading. MIGRATOR_TASK_COMMAND is the byte-exact literal
# provision-vps.sh wrote into $CONF_FILE from scripts/migrator-scheduled-
# task.md (the runbook's own source of truth) -- compared against a live GET
# of the task, below, BEFORE this script ever fires it.
MIGRATOR_TASK_COMMAND="$(read_kv "$CONF_FILE" MIGRATOR_TASK_COMMAND)"
COOLIFY_API_TOKEN="$(read_kv "$TOKEN_FILE" "$TOKEN_VAR_NAME")"

: "${MIGRATOR_SERVICE_UUID:?$CONF_FILE must set MIGRATOR_SERVICE_UUID}"
: "${MIGRATOR_TASK_UUID:?$CONF_FILE must set MIGRATOR_TASK_UUID}"
: "${APP_UUID:?$CONF_FILE must set APP_UUID}"
: "${MIGRATOR_TASK_COMMAND:?$CONF_FILE must set MIGRATOR_TASK_COMMAND}"
: "${COOLIFY_API_TOKEN:?$TOKEN_FILE must set $TOKEN_VAR_NAME}"
# ⚠ Sec FLAG 1 on PR #808's GREEN pin (2026-09-18): $MIGRATOR_TASK_UUID gets
# interpolated directly into a Python string literal inside the jqp
# heredoc below (`... == '$MIGRATOR_TASK_UUID'`) -- same shape validation
# discipline MIGRATOR_EXPECT_SHA already gets (its own exit-4/exit-5
# pair, above) is owed here too, and BEFORE that interpolation, not
# after. Coolify's own uuid generator (`new_public_id()`,
# bootstrap/helpers/shared.php:119-124: `Str::lower(Str::random(24))`)
# is exactly 24 lowercase alphanumeric characters -- measured against
# the pinned source, not guessed; every real UUID already read on this
# box or cited anywhere in this repo (MIGRATOR_SERVICE_UUID, APP_UUID,
# the fail-probe UUID) is 24 chars, matching. A malformed value here is
# a $CONF_FILE defect (a bad hand-edit, a truncated write, a wrong key
# pasted in) -- NOT the same diagnosis as a well-formed UUID that simply
# doesn't match any live task (the tampering-or-drift branch, below) --
# so it gets its OWN exit code and a message naming $CONF_FILE, not the
# list-response branch's wording.
if [[ ! "$MIGRATOR_TASK_UUID" =~ ^[a-z0-9]{24}$ ]]; then
  log "FAIL (exit 11): MIGRATOR_TASK_UUID ('$MIGRATOR_TASK_UUID') in $CONF_FILE is not a well-formed 24-character lowercase-alphanumeric Coolify UUID. This is a config defect in $CONF_FILE, not a tampering-or-drift finding about the live task -- fix the value there (re-run provision-vps.sh --apply with the correct MIGRATOR_TASK_UUID in .env) before firing. NOT executing the Scheduled Task."
  exit 11
fi
# ⚠ Sec NOTE 1 on PR #808's f802ce20 pin (2026-09-18): the companion guard
# to the MIGRATOR_TASK_UUID check above. $MIGRATOR_SERVICE_UUID gets
# interpolated directly into the URL path below (`/applications/
# $MIGRATOR_SERVICE_UUID/scheduled-tasks`) rather than into a Python
# literal, but the same diagnosis problem applies either way: WITHOUT
# this guard, a malformed $CONF_FILE value here (a bad hand-edit, a
# truncated write) reaches the list call, 404s exactly like a genuine
# access/team-scope failure would, and gets reported by the "list call
# itself failed" branch below as an ACCESS-FAILURE diagnosis -- when the
# real cause is a config defect in $CONF_FILE, not anything about the
# token's identity or team scope. Same 24-char lowercase-alphanumeric
# Coolify uuid shape (new_public_id(), measured above) checked BEFORE
# any API call, with its own exit code and a message naming $CONF_FILE
# directly, exactly the same discipline as MIGRATOR_TASK_UUID's guard.
if [[ ! "$MIGRATOR_SERVICE_UUID" =~ ^[a-z0-9]{24}$ ]]; then
  log "FAIL (exit 12): MIGRATOR_SERVICE_UUID ('$MIGRATOR_SERVICE_UUID') in $CONF_FILE is not a well-formed 24-character lowercase-alphanumeric Coolify UUID. This is a config defect in $CONF_FILE -- fix the value there (re-run provision-vps.sh --apply with the correct MIGRATOR_SERVICE_UUID in .env) before firing. Without this check, a malformed value here would reach the Scheduled Task list call, 404, and be misdiagnosed as an access/team-scope failure rather than the config defect it actually is. NOT executing the Scheduled Task."
  exit 12
fi

# ⚠ Sec FLAG 2 on PR #814's GREEN pin (2026-09-18): `api()` used to pass
# the token via an argv-visible `curl -H "Authorization: Bearer ..."` --
# readable via `ps` by any local user for the duration of every call.
# Pre-existing, not introduced by #814, but Sec required the runbook's
# operator block (BACKLOG.md item 52 AC(3): "hand it to curl via a
# header file, --config file (mode 0600), or stdin -- never an
# argv-visible -H") to meet exactly this standard, so the machine path
# must not fall short of the human one. A single `--config` file is
# written once per run (mode 0600 by construction -- this script's own
# `umask 077`, set above, applies to every `mktemp` after it, same as
# every other temp file here) and removed by an EXIT trap, so it does
# not persist past this invocation, does not get rewritten per call, and
# is cleaned up on every exit path (success, any `exit N`, or a signal).
CURL_CONFIG_FILE="$(mktemp)"
trap 'rm -f "$CURL_CONFIG_FILE"' EXIT
printf 'header = "Authorization: Bearer %s"\n' "$COOLIFY_API_TOKEN" > "$CURL_CONFIG_FILE"
api() { # api <METHOD> <PATH>
  curl -fsS -X "$1" --config "$CURL_CONFIG_FILE" "$COOLIFY_BASE$2"
}
jqp() { python3 -c "import json,sys;$1"; }
# extract_one_tag <message> <TAG-NAME> -- Sec condition on Amendment 7
# (2026-09-17): `supabase db push` echoes migration FILENAMES to stdout as
# it applies them, so a naive grep for a tag prefix can match more than
# once if a filename or diff line happens to start with the same text, or
# can silently take a stale earlier occurrence via `tail -1` if the task
# was ever re-run mid-message. EXACTLY ONE anchored match is required --
# zero or two-or-more both fail closed, they are never averaged, deduped,
# or resolved by position.
extract_one_tag() {
  local msg="$1" tag="$2" matches count
  matches="$(printf '%s\n' "$msg" | grep -E "^${tag}=")"
  count="$(printf '%s\n' "$matches" | grep -c "^${tag}=" || true)"
  if [[ -z "$matches" ]]; then
    printf ''
    return 1
  fi
  if [[ "$count" -ne 1 ]]; then
    printf ''
    return 2
  fi
  printf '%s' "$matches" | cut -d= -f2-
  return 0
}

# ⚠ ADR-072 Amendment 6/7 (draft) — Sec's "assert the OUTCOME, not the
# STATUS" ruling on the 119 fire (2026-09-17). Three Phase D fires ran
# `db push` against a STALE migrator container — the image was never
# rebuilt/redeployed after the sha that added new migrations merged — and
# reported clean success, because an empty diff is a valid `db push`
# outcome. Every hop this script controls (execute -> poll -> deploy) was
# working correctly; nothing here could have caught it, because nothing
# here asked "does the container about to run this actually carry the
# migration set I was triggered for." This check asks exactly that.
#
# ⚠ THIS READS MIGRATOR_EXPECT_SHA, A NEW NAMED ENVIRONMENT VARIABLE -- NOT
# $SSH_ORIGINAL_COMMAND, AND THIS IS NOT AN EXCEPTION TO C2 SWALLOWED
# QUIETLY. C2 (this script's own header, above) forbids reading
# $SSH_ORIGINAL_COMMAND or case-dispatching on client input -- that
# invariant is UNCHANGED and this code does not touch that variable.
# MIGRATOR_EXPECT_SHA arrives over a DIFFERENT, narrower channel (OpenSSH's
# `SetEnv`/`AcceptEnv`, sshd_config-gated to this ONE variable name, added
# by scripts/provision-vps.sh -- see that script's own comment at the
# `AcceptEnv` line) and this script treats it PURELY AS A COMPARISON VALUE:
# it is never eval'd, never used to construct a command, never branched on
# beyond the single equality check below. It is data, not dispatch.
if [[ -z "${MIGRATOR_EXPECT_SHA:-}" ]]; then
  log "FAIL (exit 4): MIGRATOR_EXPECT_SHA is not set. Every fire, workflow-triggered or a manual \`ssh ci-migrate@box\`, must supply it. Manual fire: \`ssh -o SetEnv=\"MIGRATOR_EXPECT_SHA=<40-hex-sha>\" ci-migrate@<box>\` (requires provision-vps.sh's AcceptEnv change to have landed). NOT executing the Scheduled Task."
  exit 4
fi
# 40-hex format validation on the INPUT (defence-in-depth, unchanged from
# Amendment 6 -- distinct from the exit-8 tag-shape checks below, which
# validate the Scheduled Task's OWN reported values, not this one).
if [[ ! "$MIGRATOR_EXPECT_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  log "FAIL (exit 5): MIGRATOR_EXPECT_SHA ('$MIGRATOR_EXPECT_SHA') is not a well-formed 40-character hex git sha. Refusing rather than comparing against a malformed value. NOT executing the Scheduled Task."
  exit 5
fi

# ⚠ Sec, Amendment 7 (2026-09-17) -- pre-fire task-command integrity check.
# A [read,write,deploy] token (this script's own token) CAN PATCH this
# task's `command` (measured for this amendment's design against Coolify
# v4.3.18 source -- see that amendment's own record) -- so can a hand-edit
# in the Coolify UI. If the command ever
# drifts from what provision-vps.sh last wrote, every tag this script
# parses after firing describes whatever the DRIFTED command chose to
# print, not the documented apply -- a rewritten task would otherwise
# produce evidence this script trusts blindly. Fetch the task definition
# and compare byte-exact against MIGRATOR_TASK_COMMAND BEFORE firing.
#
# ⚠ Sec NOTE 1 (2026-09-17, #801 review; FLAG B fix, #802 review): this
# command string is now a FOURTH hand-maintained copy of the same literal
# -- Coolify's own stored task, scripts/migrator-scheduled-task.md's
# Command row (the literal's HOME), infra/supabase/docker-compose.yml's
# migrator-service comment, and $CONF_FILE's MIGRATOR_TASK_COMMAND
# (provision-vps.sh's literal). Divergence between any two of these fails
# closed here. To change the command: edit the Command row in
# scripts/migrator-scheduled-task.md first, then follow
# docs/deployment-runbook.md §6.5's propagation procedure to the other
# three sites -- §6.5 documents HOW to propagate the change, it does not
# hold the literal itself (the two previously each pointed at the other
# as "edit here first," a loop; fixed).
#
# ⚠ Sec NOTE 2 (2026-09-17, #801 review; item (1) fix, #802 GREEN pin):
# read_kv() (this script's own helper, above) does NO quote-stripping and
# NO whitespace normalisation -- it returns the raw remainder of the
# `NAME=` line, verbatim. The ONLY normalisation applied to either side
# of this comparison is stripping LEADING AND TRAILING space / tab / CR /
# LF on BOTH the live Coolify API value and the $CONF_FILE literal --
# nothing else: no internal-whitespace collapse, no quote handling.
# ⚠ CORRECTED (Sec, #802 GREEN pin item 1): the prior version stripped
# TRAILING CR/space only -- missed trailing TABS entirely, and missed
# LEADING whitespace on both sides (e.g. a hand-edited conf line
# `MIGRATOR_TASK_COMMAND= sh -c …` with a stray space after `=`, or a
# Coolify-side value with incidental leading whitespace, would each trip
# a false exit-10 mismatch). $MIGRATOR_TASK_COMMAND (read via read_kv
# from $CONF_FILE) is stored with the SAME quoting the Coolify API
# returns in `command` (single/double quotes are literal characters
# inside the value, not stripped by provision-vps.sh's writer or by
# read_kv) -- so a genuine quoting mismatch is a REAL mismatch, not
# noise, and must not be stripped away either.
strip_ws() { printf '%s' "$1" | sed -E $'s/^[ \t\r]+//; s/[ \t\r]+$//'; }
# ⚠ CORRECTED 2026-09-18 (F/CTO's real Phase D fire, first execution of
# this check as ci-migrate on the box): the route this used to call --
# `GET /applications/{uuid}/scheduled-tasks/{task_uuid}` -- DOES NOT
# EXIST in Coolify 4.3.18. Measured against the pinned tag's own
# routes/api.php (:406-417): the only routes under
# `/applications/{uuid}/scheduled-tasks/...` are the bare LIST
# (`:411`, GET, no task_uuid segment), POST create (`:412`), PATCH
# `{task_uuid}` (`:413`), DELETE `{task_uuid}` (`:414`), GET
# `{task_uuid}/executions` (`:415`), and POST `{task_uuid}/execute`
# (`:416`) -- there is NO bare `GET {task_uuid}`. The prior version of
# this check inferred that route from the PATCH route's shape; it was
# never independently measured, and the real fire correctly refused
# (exit 10, "could not GET") against the resulting 404 -- the CONTROL
# failed closed on a route defect, not on the task. Same absence on the
# `/services/{uuid}/scheduled-tasks/...` family (`:418-423`), which this
# script does not use (Item 15 fix, below, already established this task
# is application-attached) -- noted here, not built here, because it is
# relevant to BACKLOG.md item 52's audit arm (any future audit of every
# scheduled task the trigger token's team owns, including SERVICE-
# attached ones, will hit the identical no-single-task-GET absence and
# needs the same list-and-filter shape, not a route this script has no
# reason to call itself).
#
# Fixed: use the LIST route (`ScheduledTasksController::
# scheduled_tasks_by_application_uuid`, `:294-307`, which calls
# `listTasks()` at `:38-47`) and select the ONE element whose `uuid`
# equals $MIGRATOR_TASK_UUID -- EXACTLY one match required, zero or two-
# or-more both fail closed (same "exactly one, never resolved by
# position" discipline as extract_one_tag() above). `listTasks()` returns
# a BARE JSON ARRAY (`response()->json($tasks)` where `$tasks` is a
# Collection -- Laravel serializes that directly to a top-level `[...]`,
# never a `{"data": [...]}` envelope) of each task's fields after
# `removeSensitiveData()` (`:16-26`) hides only `id`/`team_id`/
# `application_id`/`service_id` -- `uuid` and `command` are untouched,
# confirmed by reading `serializeApiResponse()`
# (bootstrap/helpers/api.php:38+), which only reorders keys, strips
# nothing. Still defends the bare-array-vs-`data`-envelope ambiguity the
# same way the executions-poll jqp calls already do (`rows=d if
# isinstance(d, list) else d.get('data', d)`) -- no jq on the box, this
# script has never used it; reusing the same `jqp()`/python3 pattern
# already established for the executions parsing above, not introducing
# a new dependency.
#
# ⚠ Sec's four "same evidence, not weaker" conditions (2026-09-18,
# pre-position on this fix) -- all four measured against Coolify 4.3.18
# source, not assumed, before this route swap was trusted:
#   (1) SAME COLUMN. `updateTask()`'s actual write
#       (`ScheduledTasksController.php:172`, `$task->update($request->
#       only($allowedFields))`) persists to the SAME Eloquent `command`
#       attribute this list route reads back via
#       `$resource->scheduled_tasks->map(...)` -- one column, one store,
#       read through a different envelope, not a different value.
#   (2) NO TRANSFORM, checked in the direction that matters. `command`
#       carries NO Eloquent accessor/mutator/cast of any kind
#       (`app/Models/ScheduledTask.php`: `casts()` touches only
#       `enabled`/`timeout`; `HasSafeStringAttribute`
#       (`app/Traits/HasSafeStringAttribute.php`) defines mutators for
#       `name`/`description` ONLY -- `command` is untouched by either).
#       `serializeApiResponse()` (`bootstrap/helpers/api.php:38-95`,
#       read in full) only reorders keys (`sortKeys()`, then prepends
#       `name`/`description`/`uuid`/`id` and re-appends
#       `created_at`/`updated_at`) -- no truncation (which would fail
#       CLOSED, loud) and no whitespace normalisation (which would NOT
#       fail closed -- it would make this byte-exact compare pass
#       against a stored command that actually differs, compounding
#       with `strip_ws`'s own leading/trailing strip rather than being
#       caught by it). Confirmed absent, not merely unmentioned.
#   (3) NO PAGINATION. `Application::scheduled_tasks()`
#       (`app/Models/Application.php:1090-1092`) is a bare
#       `hasMany(ScheduledTask::class)->orderBy('name','asc')` -- no
#       `->paginate()`, `->take()`, or `->limit()` anywhere in this
#       relation or in `listTasks()`
#       (`ScheduledTasksController.php:38-47`), which accesses it as a
#       plain Eloquent collection property (always the FULL related set,
#       never a paginator) and `->map()`s over the whole thing. A
#       page-one-only read with the migrator task off page one would be
#       a permanent exit-10 wedge indistinguishable from tampering --
#       ruled out by construction, not by assumption.
#   (4) FIELD MATCH, NOT SUBSTRING. The uuid selection below is
#       `(r or {}).get('uuid') == '$MIGRATOR_TASK_UUID'` on PARSED JSON
#       -- a field-equality test against each element's own `uuid` key,
#       never a substring search over the raw response body (which
#       would be an injection surface of the same shape as the tagged-
#       line parse this script already guards against with
#       extract_one_tag()'s anchored, exactly-one-match discipline).
# All four hold: this route change is the same evidence the (never-
# existent) single-task GET would have offered, not weaker evidence
# through a different envelope.
# ⚠ Sec build criterion, #807 pin: "the list call itself failed" (an
# HTTP-level failure -- curl error, or a 404 that could mean the ROUTE
# isn't registered on this Coolify version, or the APP UUID doesn't
# resolve for this token's TEAM, or a generic not-found -- Coolify
# returns the same bare 404 for all three) is a DIFFERENT diagnosis than
# "the list call SUCCEEDED and returned a 200 with zero (or duplicate)
# matches for MIGRATOR_TASK_UUID" (the task itself was deleted, its UUID
# drifted, or -- for a duplicate, which should be impossible for a real
# UUID -- something is actively wrong). The first says "something about
# THIS SCRIPT'S OWN ACCESS to the API is broken" (team-scope, route
# registration, token, network); the second says "the API answered fine,
# but the TASK ISN'T WHERE EXPECTED" (tampering-or-drift on the resource
# itself). Those demand opposite operator responses -- re-provision or
# re-check the token/route in the first case, investigate the task/UUID
# in the second -- so they get TWO DISTINCT MESSAGES below, split at
# exactly the same boundary `curl -fsS`'s own empty-output-on-failure
# behavior already draws (a 4xx/5xx with `-f` exits non-zero and prints
# no body, which is why the `|| true` above yields an EMPTY
# `$TASK_LIST_JSON` for every HTTP-level failure and a real JSON body
# for every successful-but-wrong-content response).
#
# ⚠ EXIT CODE KEPT AS 10 FOR BOTH, DELIBERATELY, NOT SPLIT -- both are
# still "the pre-fire task-command integrity check refused to fire," the
# same severity and the same caller-facing action (do not deploy, do not
# retry blindly); splitting the exit code would only duplicate
# information the MESSAGE TEXT already carries more precisely (which
# exact branch fired, and why) without changing what the caller (GitHub
# Actions' own step-red / a human reading stderr) needs to do next. The
# distinction Sec's criterion requires is diagnostic, not dispatch --
# exactly the same reasoning that already gives exit 8's two sub-causes
# (absent vs. ambiguous tag match) one shared code with two distinct
# messages, below.
TASK_LIST_JSON="$(api GET "/applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks" || true)"
if [[ -z "$TASK_LIST_JSON" ]]; then
  log "FAIL (exit 10): the Scheduled Task LIST CALL ITSELF FAILED (empty response from an HTTP-level failure, not a successful-but-empty list) -- could not verify the migrator task's command before firing. This means something about THIS SCRIPT'S OWN ACCESS is broken, not the task: Coolify returns an identical bare 404 whether the route isn't registered on this Coolify version, MIGRATOR_SERVICE_UUID doesn't resolve for this token's team, or (less likely, already measured stable) a genuine not-found -- check the token's abilities/team scope and MIGRATOR_SERVICE_UUID in $CONF_FILE before assuming a route regression. See GET /applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks directly. Refusing to fire against an unverifiable task. NOT executing the Scheduled Task."
  exit 10
fi
# ⚠ Sec FLAG 2 on PR #808's GREEN pin (2026-09-18): under this script's
# own `set -euo pipefail` (top of file), a jqp/python3 failure (a
# traceback -- e.g. TASK_LIST_JSON is present but not valid JSON, an
# HTTP error page that slipped past the `-z` check above, or any other
# parse exception) would otherwise either (a) abort the WHOLE SCRIPT
# silently via `-e`/`pipefail` with no exit-10-family message at all, or
# (b) if caught, leave `$TASK_MATCH_COUNT` empty -- which then falls
# into the `!= "1"` branch below and gets reported as "zero matches,"
# a TAMPERING-OR-DRIFT diagnosis. Neither is correct: a parse failure
# means the response couldn't be READ at all, which is closer to the
# access-failure branch above than to a real zero-match result. Guard
# the assignment with `if !` (the standard bash idiom that does NOT
# trigger `-e` on a failing command substitution used as a condition)
# and give it a THIRD, distinct message -- kept at exit 10, same
# reasoning as the two messages above: same severity and caller action,
# distinguished by text, not by code.
JQP_ERR_FILE="$(mktemp)"
if ! TASK_MATCH_COUNT="$(printf '%s' "$TASK_LIST_JSON" | jqp "
d=json.load(sys.stdin)
rows=d if isinstance(d, list) else d.get('data', d)
print(sum(1 for r in (rows or []) if (r or {}).get('uuid') == '$MIGRATOR_TASK_UUID'))
" 2>"$JQP_ERR_FILE")"; then
  JQP_ERR="$(tail -1 "$JQP_ERR_FILE" 2>/dev/null || true)"
  rm -f "$JQP_ERR_FILE"
  log "FAIL (exit 10): could not PARSE the Scheduled Task list response -- the list call itself succeeded (non-empty response) but the JSON parser failed ('${JQP_ERR:-<no error captured>}'). This is neither an access failure nor a tampering-or-drift finding -- the response body itself is not valid/parseable JSON. Investigate what Coolify actually returned before re-firing. NOT executing the Scheduled Task."
  exit 10
fi
rm -f "$JQP_ERR_FILE"
if [[ "$TASK_MATCH_COUNT" != "1" ]]; then
  log "FAIL (exit 10): the Scheduled Task LIST CALL SUCCEEDED but returned $TASK_MATCH_COUNT entries matching MIGRATOR_TASK_UUID ($MIGRATOR_TASK_UUID), not exactly one -- this is a TAMPERING-OR-DRIFT diagnosis, distinct from an access failure: the API answered fine, the task itself is not where expected (zero means the task was deleted or the UUID drifted; two-or-more should be impossible for a UUID but is refused rather than resolved by position, same discipline as the tagged-line extraction below). See the task list directly at GET /applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks. NOT executing the Scheduled Task."
  exit 10
fi
# Same jqp-failure guard as above -- a parse failure here must not be
# read as "command is empty" (which would otherwise fall into the
# mismatch branch below and be misreported as a differing command).
JQP_ERR_FILE="$(mktemp)"
if ! LIVE_TASK_COMMAND="$(printf '%s' "$TASK_LIST_JSON" | jqp "
d=json.load(sys.stdin)
rows=d if isinstance(d, list) else d.get('data', d)
matches=[r for r in (rows or []) if (r or {}).get('uuid') == '$MIGRATOR_TASK_UUID']
print((matches[0] or {}).get('command','') if matches else '')
" 2>"$JQP_ERR_FILE")"; then
  JQP_ERR="$(tail -1 "$JQP_ERR_FILE" 2>/dev/null || true)"
  rm -f "$JQP_ERR_FILE"
  log "FAIL (exit 10): could not PARSE the Scheduled Task list response while extracting the matched task's command ('${JQP_ERR:-<no error captured>}'). This is a parse failure, not a command mismatch -- do not treat an empty read as evidence the command differs. Investigate before re-firing. NOT executing the Scheduled Task."
  exit 10
fi
rm -f "$JQP_ERR_FILE"
LIVE_TASK_COMMAND="$(strip_ws "$LIVE_TASK_COMMAND")"
EXPECTED_TASK_COMMAND="$(strip_ws "$MIGRATOR_TASK_COMMAND")"
if [[ -z "$LIVE_TASK_COMMAND" || "$LIVE_TASK_COMMAND" != "$EXPECTED_TASK_COMMAND" ]]; then
  log "FAIL (exit 10): the Scheduled Task's command in Coolify differs from MIGRATOR_TASK_COMMAND in /etc/pfin/migrator-trigger.conf -- change it in ONE place per docs/deployment-runbook.md §6.5 (byte-exact comparison; leading/trailing space, tab, CR, LF stripped from both sides, nothing else). NOT executing the Scheduled Task. Re-run provision-vps.sh --apply after confirming which side is stale, or investigate an unauthorized edit -- do not just re-fire. (Live and expected command text withheld from this log line by design -- Sec's own instruction is that this script logs only extracted PFIN-* tag values, never a raw command/message blob. See the live task list directly at GET /applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks and compare the matching entry's \`command\` against \$CONF_FILE's MIGRATOR_TASK_COMMAND by hand.)"
  exit 10
fi
log "task command integrity check OK: live Scheduled Task command matches MIGRATOR_TASK_COMMAND in $CONF_FILE"

# ═════════════════════════════════════════════════════════════════════
# BACKLOG.md §7.36 item 59 — DEPLOY-THEN-EXECUTE: deploy (rebuild) the
# migrator RESOURCE before ever executing the Scheduled Task. This
# discharges ADR-072 Decision 5(1)'s load-bearing sequencing ("rebuild
# the migrator image -> run the Scheduled Task -> then deploy the app"),
# which Amendment 6 (A) found the build had never implemented -- every
# fire before this PR executed the Scheduled Task against whatever image
# happened to already be running, with nothing here ever causing a
# rebuild. Runs AFTER the task-command integrity check above (a drifted
# command is caught before spending a build on it) and BEFORE the
# execution-binding snapshot below (nothing here executes the task).
#
# ⚠ PRECONDITION THIS SECTION ASSUMES, PER AMENDMENT 6 (B)(i): the
# migrator is its OWN Coolify resource (ADR-072 Amendment 4), so
# redeploying it does NOT restart the Supabase-stack resource (and does
# not bounce production Postgres). That precondition is discharged
# (migrator moved to its own application, `pfin-migrator`,
# scripts/provision-migrator-app.sh, 2026-09-19) -- but nothing besides
# $MIGRATOR_SERVICE_UUID's OWN IDENTITY stands between this section's
# deploy call and the stack resource if $CONF_FILE's MIGRATOR_SERVICE_UUID
# ever drifts onto the wrong uuid. The name guard immediately below is
# that fence, not decoration: the trigger token's `deploy` ability is
# NOT scoped to this one resource -- it reaches every application/service
# the team owns (ADR-072 Amendment 2's C4 widening, measured against
# Coolify v4.3.18's team-scoped-only resolution) -- so the uuid's
# identity is the only thing standing between a conf drift and a deploy
# call landing on the stack application instead.
#
# ⚠⚠ THE POLL BELOW IS A PRECONDITION-WAIT, NEVER A SUCCESS CRITERION --
# ADR-072 Amendment 6 consequence 3, verbatim: "If a deployment-status
# poll is ALSO kept, it is a PRECONDITION -- it waits for the rebuild to
# finish and its success is NEVER evidence that the migration applied."
# Three separate claims get made across this script, in order, and none
# substitutes for another: (1) this poll only proves Coolify's own
# deployment-status machine reached a terminal state -- Decision 3
# already ruled that machine unreliable as a SUCCESS signal (it marks
# FINISHED before a post-deploy command and swallows that command's
# failure); (2) the pre-execute commit assertion right after it proves
# the image THIS FIRE JUST BUILT carries the sha this fire was triggered
# for; (3) the existing tagged-line assertions further below (UNCHANGED
# by this section) prove the migration actually landed in the database.
# Losing sight of which claim is which is exactly the failure class that
# produced the false "Phase D transport proven end-to-end" claim
# Amendment 6 (A) found and corrected -- named again here so it is not
# reintroduced one section over.
DEPLOY_POLL_INTERVAL_S=5
DEPLOY_POLL_MAX_ATTEMPTS=180   # 180 * 5s = 15 minutes -- a Docker image
                                # rebuild now runs ahead of every apply
                                # (Amendment 6 (B)(i) named this wall-clock
                                # cost and accepted it explicitly).

log "verifying MIGRATOR_SERVICE_UUID ($MIGRATOR_SERVICE_UUID) names the expected application before deploying anything at it"
APP_RECORD_JSON="$(api GET "/applications/$MIGRATOR_SERVICE_UUID" || true)"
if [[ -z "$APP_RECORD_JSON" ]]; then
  log "FAIL (exit 16): could not GET /applications/$MIGRATOR_SERVICE_UUID to verify its name before deploying -- an HTTP-level failure (bad uuid, team-scope mismatch, or a route/token problem), not a name mismatch. NOT deploying the migrator resource, NOT executing the Scheduled Task. Check the token's abilities/team scope and MIGRATOR_SERVICE_UUID in $CONF_FILE."
  exit 16
fi
JQP_ERR_FILE="$(mktemp)"
if ! LIVE_APP_NAME="$(printf '%s' "$APP_RECORD_JSON" | jqp "
d=json.load(sys.stdin)
print(d.get('name','') if isinstance(d, dict) else '')
" 2>"$JQP_ERR_FILE")"; then
  JQP_ERR="$(tail -1 "$JQP_ERR_FILE" 2>/dev/null || true)"
  rm -f "$JQP_ERR_FILE"
  log "FAIL (exit 16): could not PARSE the application record while verifying its name ('${JQP_ERR:-<no error captured>}'). NOT deploying the migrator resource, NOT executing the Scheduled Task."
  exit 16
fi
rm -f "$JQP_ERR_FILE"
if [[ -z "$LIVE_APP_NAME" || "$LIVE_APP_NAME" != "$MIGRATOR_APP_NAME" ]]; then
  log "FAIL (exit 16): the application at MIGRATOR_SERVICE_UUID ($MIGRATOR_SERVICE_UUID) is named '$LIVE_APP_NAME', not the expected '$MIGRATOR_APP_NAME' -- refusing to deploy. \$CONF_FILE's MIGRATOR_SERVICE_UUID may have drifted onto a DIFFERENT resource -- the Supabase-stack application is the specific hazard this guard exists for: the trigger token's deploy ability reaches it too (ADR-072 Amendment 2), and redeploying it restarts production Postgres. NOT deploying, NOT executing the Scheduled Task. Investigate MIGRATOR_SERVICE_UUID in $CONF_FILE before re-firing -- do not just retry."
  exit 16
fi
# Defence-in-depth (Sec, PR #831 joint review): the name guard above is one
# field deep -- a two-field conf edit (uuid AND name) defeats it, though
# $CONF_FILE is root-only-writable so that already requires box-root. This
# second field costs nothing extra to check (same $APP_RECORD_JSON already
# fetched, no new API call) and turns a two-field coordinated drift into a
# three-field one. ⚠ MEASURED by Sec, 2026-09-19, `GET /api/v1/applications/<uuid>`
# on Coolify 4.3.18 (the DETAIL route this call itself uses, not
# provision-migrator-app.sh's LIST route at `:184` -- a first measurement
# of this route in this repo, not an inference carried from that list-route
# precedent): the detail route serialises `base_directory` as
# `/infra/supabase/migrator` for `pfin-migrator` and `/infra/supabase` for
# `pfin-supabase-stack` -- the two values differ, and the guard below
# checks the one that names the resource this section is about to deploy.
if ! LIVE_BASE_DIR="$(printf '%s' "$APP_RECORD_JSON" | jqp "
d=json.load(sys.stdin)
print(d.get('base_directory','') if isinstance(d, dict) else '')
" 2>/dev/null)"; then
  log "FAIL (exit 16): could not PARSE the application record while verifying its base_directory. NOT deploying the migrator resource, NOT executing the Scheduled Task."
  exit 16
fi
if [[ "$LIVE_BASE_DIR" != "/infra/supabase/migrator" ]]; then
  log "FAIL (exit 16): the application at MIGRATOR_SERVICE_UUID ($MIGRATOR_SERVICE_UUID) is named '$LIVE_APP_NAME' (matches) but its base_directory is '$LIVE_BASE_DIR', not the expected '/infra/supabase/migrator' -- refusing to deploy. NOT deploying, NOT executing the Scheduled Task. Investigate MIGRATOR_SERVICE_UUID in $CONF_FILE before re-firing -- do not just retry."
  exit 16
fi
log "name guard OK: MIGRATOR_SERVICE_UUID ($MIGRATOR_SERVICE_UUID) resolves to application '$LIVE_APP_NAME' (base_directory $LIVE_BASE_DIR)"

log "deploying the migrator resource (rebuild -> run task -> deploy app, ADR-072 Decision 5(1))"
# POST, not GET -- measured against Coolify v4.3.18's routes/api.php:144-145:
# `Route::get('/deploy', [OtherController::class, 'post_required'])` returns
# HTTP 405 ("This endpoint has changed to a POST request."); only
# `Route::post('/deploy', [DeployController::class, 'deploy'])` is wired to
# the real handler. ⚠ The APP-deploy call in this script's own `success)`
# branch below has called `api GET "/deploy?uuid=$APP_UUID"` since this
# script existed -- the SAME defect, pre-existing, fixed in this PR at
# that call site too (see its own comment there), not introduced here.
#
# `force` (rebuild without cache) is deliberately NOT passed, and is not
# needed for correctness here -- measured against
# bootstrap/helpers/applications.php's queue_application_deployment(): the
# API's by_uuids()/deploy_resource() call site never passes an explicit
# `commit`, so `$commit` there resolves to `$application->git_commit_sha`,
# which is EMPTY on this application (measured:
# scripts/provision-migrator-app.sh's CREATE_BODY never sets
# git_commit_sha, and nothing in ApplicationDeploymentJob ever writes it
# back afterward -- only the deployment QUEUE ROW's own `commit` column is
# updated, never the application's). An empty/'HEAD' commit makes
# ApplicationDeploymentJob::shouldResolveBranchHeadCommit() true, which
# runs `git ls-remote` against the configured branch and rebuilds from
# WHATEVER IS CURRENTLY AT ITS TIP on every single deploy call,
# unconditionally -- `force` only controls Docker build-cache reuse, and
# the migrations directory's content is identical either way when the sha
# is unchanged.
#
# ⚠ CONSEQUENCE OF THAT MEASUREMENT, per this PR's own AC (2): because
# every deploy call rebuilds branch HEAD rather than a pinned commit, a
# `main` advance BETWEEN this fire's trigger and this deploy call builds a
# NEWER commit than $MIGRATOR_EXPECT_SHA. The pre-execute commit assertion
# below WILL then RED on that outcome -- correctly. See that assertion's
# own comment for why this is accepted, not a defect to route around.
DEPLOY_RESPONSE_JSON="$(api POST "/deploy?uuid=$MIGRATOR_SERVICE_UUID")" \
  || fail "could not deploy the migrator resource (deploy call itself failed -- check the token's deploy ability and MIGRATOR_SERVICE_UUID in $CONF_FILE). NOT executing the Scheduled Task."
JQP_ERR_FILE="$(mktemp)"
if ! DEPLOY_MATCH_INFO="$(printf '%s' "$DEPLOY_RESPONSE_JSON" | jqp "
d=json.load(sys.stdin)
rows=(d.get('deployments') or []) if isinstance(d, dict) else []
uuids=[r.get('deployment_uuid','') for r in rows if isinstance(r, dict) and r.get('deployment_uuid')]
print(len(uuids))
print(uuids[0] if len(uuids) == 1 else '')
" 2>"$JQP_ERR_FILE")"; then
  JQP_ERR="$(tail -1 "$JQP_ERR_FILE" 2>/dev/null || true)"
  rm -f "$JQP_ERR_FILE"
  log "FAIL (exit 17): could not PARSE the deploy call's response ('${JQP_ERR:-<no error captured>}'). NOT executing the Scheduled Task."
  exit 17
fi
rm -f "$JQP_ERR_FILE"
DEPLOY_MATCH_COUNT="$(printf '%s' "$DEPLOY_MATCH_INFO" | sed -n '1p')"
DEPLOY_UUID="$(printf '%s' "$DEPLOY_MATCH_INFO" | sed -n '2p')"
if [[ "$DEPLOY_MATCH_COUNT" != "1" ]]; then
  log "FAIL (exit 17): the deploy call's response carried $DEPLOY_MATCH_COUNT deployment_uuid values, not exactly one -- refusing to guess which one is this fire's. NOT executing the Scheduled Task. See POST /deploy?uuid=$MIGRATOR_SERVICE_UUID directly to investigate (a Coolify 'Deployment already queued for this commit' skip -- an existing in-flight deploy for the same resolved commit -- returns a deployment_uuid that resolves to NO real deployment record; that shape surfaces below as exit 17's 'GET itself failed' branch, not this one)."
  exit 17
fi
if [[ ! "$DEPLOY_UUID" =~ ^[a-z0-9]{24}$ ]]; then
  log "FAIL (exit 17): the deploy call returned a deployment_uuid ('$DEPLOY_UUID') that is not a well-formed 24-character lowercase-alphanumeric Coolify uuid. NOT executing the Scheduled Task."
  exit 17
fi
log "migrator deploy queued -- deployment $DEPLOY_UUID"

DEPLOY_STATUS=""
DEPLOY_RECORD_JSON=""
for _ in $(seq 1 "$DEPLOY_POLL_MAX_ATTEMPTS"); do
  DEPLOY_RECORD_JSON="$(api GET "/deployments/$DEPLOY_UUID" || true)"
  if [[ -z "$DEPLOY_RECORD_JSON" ]]; then
    log "FAIL (exit 17): GET /deployments/$DEPLOY_UUID itself failed -- this uuid does not resolve to a real deployment record. The likeliest cause is Coolify's own 'skip' shape (bootstrap/helpers/applications.php's queue_application_deployment(): an existing queued/in_progress deployment for the same resolved commit returns a FRESH, NEVER-PERSISTED deployment_uuid rather than the real in-flight one's) -- investigate via the Coolify dashboard for what is actually running before re-firing. NOT executing the Scheduled Task."
    exit 17
  fi
  JQP_ERR_FILE="$(mktemp)"
  if ! DEPLOY_STATUS="$(printf '%s' "$DEPLOY_RECORD_JSON" | jqp "
d=json.load(sys.stdin)
print(d.get('status','') if isinstance(d, dict) else '')
" 2>"$JQP_ERR_FILE")"; then
    JQP_ERR="$(tail -1 "$JQP_ERR_FILE" 2>/dev/null || true)"
    rm -f "$JQP_ERR_FILE"
    log "FAIL (exit 17): could not PARSE the deployment record while polling status ('${JQP_ERR:-<no error captured>}'). NOT executing the Scheduled Task."
    exit 17
  fi
  rm -f "$JQP_ERR_FILE"
  # Terminal states measured from Coolify v4.3.18's own
  # app/Enums/ApplicationDeploymentStatus.php -- NOT guessed, and NOT the
  # same two-value set ("finished"/"failed") this repo's own
  # provision-supabase-stack.sh / provision-migrator-app.sh already
  # (incorrectly) treat as exhaustive: QUEUED / IN_PROGRESS are the only
  # non-terminal values; FINISHED / FAILED / CANCELLED_BY_USER
  # ('cancelled-by-user') are terminal. A cancelled deployment (an
  # operator hitting Cancel in the Coolify UI mid-build) must fall out of
  # this loop immediately, not be misdiagnosed as a hang by the timeout
  # branch below.
  case "$DEPLOY_STATUS" in
    queued|in_progress) ;;
    *) break ;;
  esac
  sleep "$DEPLOY_POLL_INTERVAL_S"
done

case "$DEPLOY_STATUS" in
  finished)
    log "migrator deploy finished (deployment $DEPLOY_UUID)"
    ;;
  failed|cancelled-by-user)
    fail "migrator deploy reached a non-finished TERMINAL state (status=$DEPLOY_STATUS, deployment $DEPLOY_UUID) -- NOT executing the Scheduled Task. See the deployment log in the Coolify dashboard."
    ;;
  *)
    fail "gave up after $((DEPLOY_POLL_MAX_ATTEMPTS * DEPLOY_POLL_INTERVAL_S))s waiting for the migrator deploy to reach a terminal state (last seen: '${DEPLOY_STATUS:-<empty>}', deployment $DEPLOY_UUID) -- this is a poll timeout, not a confirmed deploy failure (if that value is non-empty and not one of queued/in_progress, this is NOT a timeout -- Coolify returned a status this script does not know, and re-firing will not help). NOT executing the Scheduled Task. Check the Coolify dashboard directly before retriggering."
    ;;
esac

# ⚠⚠ PRE-EXECUTE COMMIT ASSERTION -- THE ACTUAL GATE, per Amendment 6
# consequence 2: "assert the property we actually need, which is directly
# observable and fails closed... the container about to run carries the
# migration set from the merged sha." The poll above only proves Coolify's
# deployment-status machine said "finished"; this proves the image that
# status describes is the one this fire was triggered for. Read the field
# Coolify's own model uses as the deployed-commit authority
# (docs/deployment-runbook.md's own citation of "Coolify's own API/UI
# record of the deployed commit") -- `commit` on the deployment record
# (ApplicationDeploymentQueue's own OA schema field, populated by
# bootstrap/helpers/applications.php's ls-remote-and-save-to-`commit`
# logic during the build) -- never `git_commit_sha` on the application
# itself, which this application never has set (see the deploy-call
# comment above for why that is what keeps every deploy resolving branch
# HEAD rather than replaying a stale pinned value).
JQP_ERR_FILE="$(mktemp)"
if ! DEPLOYED_COMMIT="$(printf '%s' "$DEPLOY_RECORD_JSON" | jqp "
d=json.load(sys.stdin)
print(d.get('commit','') if isinstance(d, dict) else '')
" 2>"$JQP_ERR_FILE")"; then
  JQP_ERR="$(tail -1 "$JQP_ERR_FILE" 2>/dev/null || true)"
  rm -f "$JQP_ERR_FILE"
  log "FAIL (exit 18): could not PARSE the finished deployment record while reading its commit field ('${JQP_ERR:-<no error captured>}'). NOT executing the Scheduled Task."
  exit 18
fi
rm -f "$JQP_ERR_FILE"
if [[ ! "$DEPLOYED_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  log "FAIL (exit 18): the finished deployment's own 'commit' field ('$DEPLOYED_COMMIT') is not a well-formed 40-character hex sha -- refusing to compare against a malformed value. NOT executing the Scheduled Task. See GET /deployments/$DEPLOY_UUID directly."
  exit 18
fi
if [[ "$DEPLOYED_COMMIT" != "$MIGRATOR_EXPECT_SHA" ]]; then
  log "FAIL (exit 18): the migrator deploy that JUST FINISHED built sha $DEPLOYED_COMMIT, not the sha this fire was triggered for ($MIGRATOR_EXPECT_SHA). This is EXPECTED and CORRECT when \`main\` advanced between this fire's trigger and this deploy call (Coolify's git-based deploy always rebuilds from the CURRENT branch HEAD, never a pinned commit -- see the deploy-call comment above) -- a newer commit means a new fire is already coming (or queued) under this workflow's own concurrency group, and the ledger is unaffected because this apply would only ever have run against a SUPERSET image. NOT executing the Scheduled Task; let the newer fire behind this one run (or re-fire deliberately) rather than retrying blindly. Deployment $DEPLOY_UUID."
  exit 18
fi
log "pre-execute commit assertion OK: the migrator deploy that just finished built the expected sha ($DEPLOYED_COMMIT)"
# ═════════════════════════════════════════════════════════════════════

# ⚠ EXECUTION-BINDING SNAPSHOT — taken BEFORE the execute call, per the
# header comment above. This is the pre-fire half of the uuid set
# difference: record every execution uuid that already exists so that,
# after firing, "new" can be defined as "not in this set" rather than
# "rows[0]". A read/parse failure here is treated with the SAME
# discipline as the task-list access/parse failures above (exit 10,
# distinguished by message text only) -- this script must not fire
# against a task whose pre-fire state it could not establish.
EXECUTIONS_PATH="/applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks/$MIGRATOR_TASK_UUID/executions"
PRE_FIRE_EXEC_JSON="$(api GET "$EXECUTIONS_PATH" || true)"
if [[ -z "$PRE_FIRE_EXEC_JSON" ]]; then
  log "FAIL (exit 10): the executions LIST CALL ITSELF FAILED (empty response) while taking the pre-fire uuid snapshot -- cannot establish which executions already exist, so a post-fire 'new uuid' comparison would be meaningless. Same access-failure class as the task-list check above. See GET $EXECUTIONS_PATH directly. NOT executing the Scheduled Task."
  exit 10
fi
JQP_ERR_FILE="$(mktemp)"
if ! PRE_FIRE_UUIDS="$(printf '%s' "$PRE_FIRE_EXEC_JSON" | jqp "
d=json.load(sys.stdin)
rows=d if isinstance(d, list) else d.get('data', d)
print('\n'.join(sorted(set((r or {}).get('uuid','') for r in (rows or []) if (r or {}).get('uuid')))))
" 2>"$JQP_ERR_FILE")"; then
  JQP_ERR="$(tail -1 "$JQP_ERR_FILE" 2>/dev/null || true)"
  rm -f "$JQP_ERR_FILE"
  log "FAIL (exit 10): could not PARSE the executions list response while taking the pre-fire uuid snapshot ('${JQP_ERR:-<no error captured>}'). NOT executing the Scheduled Task."
  exit 10
fi
rm -f "$JQP_ERR_FILE"
# ⚠ Sec FLAG 1 on PR #814's GREEN pin (2026-09-18): every uuid in
# $PRE_FIRE_UUIDS is about to be interpolated into a Python string
# literal inside the jqp heredoc below (`set('''$PRE_FIRE_UUIDS'''.split())`)
# -- and unlike $MIGRATOR_TASK_UUID (root-owned, box-resident,
# ci-migrate-unwritable), these values arrive OVER THE NETWORK from
# Coolify's own executions API. Not a privilege-escalation concern (Sec:
# crafting a malicious value here requires already compromising Coolify
# or the path to localhost:8000, both already root-equivalent) but a
# DIAGNOSIS concern -- an unguarded malformed value would surface as an
# opaque Python traceback (misreported as a parse failure) rather than
# as what it actually is. Same 24-char lowercase-alphanumeric Coolify
# uuid shape as MIGRATOR_TASK_UUID's own guard (new_public_id(),
# bootstrap/helpers/shared.php:119-124, measured above) -- but this is
# its OWN exit code and message, not a reuse of the parse-failure branch
# above: a well-formed-but-malformed-shape uuid parsed the JSON fine, it
# just isn't the shape this script can safely reason about downstream.
while IFS= read -r pre_fire_uuid; do
  [[ -z "$pre_fire_uuid" ]] && continue
  if [[ ! "$pre_fire_uuid" =~ ^[a-z0-9]{24}$ ]]; then
    log "FAIL (exit 15): the executions API returned a malformed execution uuid ('$pre_fire_uuid') in the pre-fire snapshot -- not a well-formed 24-character lowercase-alphanumeric Coolify uuid. Refusing to interpolate an unvalidated, network-sourced value into this script's own comparison logic. NOT executing the Scheduled Task. See GET $EXECUTIONS_PATH directly to investigate what Coolify actually returned."
    exit 15
  fi
done <<< "$PRE_FIRE_UUIDS"
log "pre-fire execution uuid snapshot recorded"

log "executing migrator Scheduled Task ($MIGRATOR_TASK_UUID) on application $MIGRATOR_SERVICE_UUID"
# Item 15 fix (Sec-gated, booked BACKLOG.md §7.36 #15): the migrator
# Scheduled Task is attached to an APPLICATION resource — ⚠ CHANGED,
# ADR-072 Amendment 4 / BACKLOG.md §7.36 item 29 (2026-09-18): that
# application is now migrator's OWN standalone Coolify application
# (infra/supabase/migrator/docker-compose.yaml), NOT the Supabase-stack
# application this comment originally named (standup-log.md Phase A.2's
# "created via" citation below describes how the task was FIRST created,
# under the old topology; the route/controller-method distinction it
# documents is unchanged by the move — only WHICH application UUID
# $MIGRATOR_SERVICE_UUID now resolves to changed, and this script needed
# no code change for that, since it already treats
# $MIGRATOR_SERVICE_UUID as an opaque config value read from
# $CONF_FILE). The task itself is (re-)created via
# `POST /applications/{uuid}/scheduled-tasks`, i.e.
# ScheduledTasksController::create_scheduled_task_by_application_uuid, not
# a Service resource. Coolify 4.3.18's routes/api.php defines TWO separate
# route families for scheduled tasks, each bound to its own controller
# method and resource table: `/applications/{uuid}/scheduled-tasks/...`
# (execute -> execute_scheduled_task_by_application_uuid, executions ->
# executions_by_application_uuid) and `/services/{uuid}/scheduled-tasks/...`
# (its own distinct by_service_uuid methods). Addressing an
# application-attached task under `/services/` 404s — confirmed by reading
# routes/api.php directly (github.com/coollabsio/coolify, tag v4.3.18),
# not assumed. Corrected to the `/applications/` family below.
#
# The response is now CAPTURED, not discarded -- Sec's site sweep (this
# PR): if the controller ever starts returning an execution identifier,
# the orchestrator should not be throwing it away. Measured (this PR,
# Coolify v4.3.18 ScheduledTasksController::executeTask()): it does not
# today -- the body is exactly {"message": "..."}. Only the response's
# KEY SHAPE is logged (never an arbitrary value) so this stays true to
# the PFIN-*-tags-only logging discipline elsewhere in this script --
# except a candidate uuid, which this script already logs elsewhere
# ($BOUND_EXEC_UUID below), so surfacing one here too is not a new class
# of disclosure.
#
# ⚠ THE UUID SET DIFFERENCE BELOW IS THE SELECTOR, NOT A FALLBACK BEHIND
# A uuid-FROM-POST PRIMARY (F/CTO/Sec directive, this PR): a "primary +
# described fallback" shape is exactly the class that has shipped
# unexercised three times on this chain already (see the header
# comment's evidence-independence note). There is only ONE arm here. If
# this response ever does carry a uuid-shaped identifier, it is used
# only as an EXTRA integrity check against what the set difference
# independently bound to below -- never as an alternate selection path.
EXECUTE_RESPONSE_JSON="$(api POST "/applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks/$MIGRATOR_TASK_UUID/execute")" \
  || fail "could not start the Scheduled Task (execute call itself failed — check the token's write ability and the UUIDs in $CONF_FILE)"
EXECUTE_RESPONSE_KEYS="$(printf '%s' "$EXECUTE_RESPONSE_JSON" | jqp "
d=json.load(sys.stdin)
print(','.join(sorted(d.keys())) if isinstance(d, dict) else type(d).__name__)
" 2>/dev/null || true)"
log "execute call returned (response KEYS only, never an arbitrary value): ${EXECUTE_RESPONSE_KEYS:-<unparseable or empty>}"
# Best-effort candidate under the handful of plausible key names -- empty
# if none of them are present (the measured, current shape). Never
# treated as required or as a selector.
EXECUTE_RESPONSE_UUID_CANDIDATE="$(printf '%s' "$EXECUTE_RESPONSE_JSON" | jqp "
d=json.load(sys.stdin)
v = None
if isinstance(d, dict):
    for k in ('uuid', 'execution_uuid', 'execution', 'id'):
        if isinstance(d.get(k), str) and d.get(k):
            v = d.get(k)
            break
print(v or '')
" 2>/dev/null || true)"
if [[ -n "$EXECUTE_RESPONSE_UUID_CANDIDATE" ]]; then
  log "execute call response also carried a candidate execution identifier ($EXECUTE_RESPONSE_UUID_CANDIDATE) -- will be checked against the set-difference binding below as an integrity assertion, not used to select it"
fi

log "polling for THIS fire's execution -- binds by uuid set difference (pre-fire snapshot vs. current), never by rows[0] position (see header comment)"
STATUS=""
EXEC_ROW_JSON=""
BOUND_EXEC_UUID=""
for _ in $(seq 1 "$POLL_MAX_ATTEMPTS"); do
  EXEC_ROW_JSON="$(api GET "$EXECUTIONS_PATH")"

  if [[ -z "$BOUND_EXEC_UUID" ]]; then
    # Not yet bound to a specific execution: compute (current uuids) minus
    # (pre-fire uuids) and require EXACTLY ONE member before proceeding --
    # same exactly-one discipline as extract_one_tag() and the task-match
    # check above, never resolved by position or by "first seen".
    JQP_ERR_FILE="$(mktemp)"
    if ! NEW_UUID_INFO="$(printf '%s' "$EXEC_ROW_JSON" | jqp "
d=json.load(sys.stdin)
rows=d if isinstance(d, list) else d.get('data', d)
pre=set('''$PRE_FIRE_UUIDS'''.split())
newu=sorted(set((r or {}).get('uuid','') for r in (rows or []) if (r or {}).get('uuid') and r.get('uuid') not in pre))
print(len(newu))
print(newu[0] if len(newu) == 1 else '')
" 2>"$JQP_ERR_FILE")"; then
      JQP_ERR="$(tail -1 "$JQP_ERR_FILE" 2>/dev/null || true)"
      rm -f "$JQP_ERR_FILE"
      log "FAIL (exit 10): could not PARSE the executions list response while computing the new-uuid set ('${JQP_ERR:-<no error captured>}'). Deploy NOT triggered."
      exit 10
    fi
    rm -f "$JQP_ERR_FILE"
    NEW_UUID_COUNT="$(printf '%s' "$NEW_UUID_INFO" | sed -n '1p')"
    NEW_UUID_CANDIDATE="$(printf '%s' "$NEW_UUID_INFO" | sed -n '2p')"

    if [[ "$NEW_UUID_COUNT" -gt 1 ]]; then
      log "FAIL (exit 14): $NEW_UUID_COUNT execution uuids are present that were absent from the pre-fire snapshot -- this fire's execution is AMBIGUOUS among them. This is a concurrent-fire diagnosis, not a transient glitch: something else (another operator firing from the Coolify UI is the likely source -- this script's own flock only bars a second copy of itself) started a Scheduled Task execution for this same task in the same window. Refusing to guess which uuid is THIS fire's rather than resolving by position. Deploy NOT triggered. See $EXECUTIONS_PATH directly to investigate before re-firing."
      exit 14
    elif [[ "$NEW_UUID_COUNT" -eq 1 ]]; then
      # ⚠ Sec FLAG 1 (same as the pre-fire snapshot guard above): this
      # candidate is about to become $BOUND_EXEC_UUID and get
      # interpolated into a Python string literal in every subsequent
      # status/message read below (`... == '$BOUND_EXEC_UUID'`) -- guard
      # it BEFORE binding, not after, with its own exit code, not a
      # reuse of the parse-failure or ambiguous-fire branches.
      if [[ ! "$NEW_UUID_CANDIDATE" =~ ^[a-z0-9]{24}$ ]]; then
        log "FAIL (exit 15): the executions API returned a malformed execution uuid ('$NEW_UUID_CANDIDATE') as the sole new execution since the pre-fire snapshot -- not a well-formed 24-character lowercase-alphanumeric Coolify uuid. Refusing to bind to (and interpolate) an unvalidated, network-sourced value. Deploy NOT triggered. See $EXECUTIONS_PATH directly to investigate what Coolify actually returned."
        exit 15
      fi
      BOUND_EXEC_UUID="$NEW_UUID_CANDIDATE"
      log "bound to execution uuid $BOUND_EXEC_UUID (the one execution present now that was absent from the pre-fire snapshot)"
    fi
    # NEW_UUID_COUNT == 0: this fire's execution has not appeared yet
    # (the dispatch-to-job-start queue lag the header comment measures) --
    # fall through to sleep/retry within the existing poll ceiling.
  fi

  if [[ -n "$BOUND_EXEC_UUID" ]]; then
    JQP_ERR_FILE="$(mktemp)"
    if ! STATUS="$(printf '%s' "$EXEC_ROW_JSON" | jqp "
d=json.load(sys.stdin)
rows=d if isinstance(d, list) else d.get('data', d)
matches=[r for r in (rows or []) if (r or {}).get('uuid') == '$BOUND_EXEC_UUID']
print((matches[0] or {}).get('status','') if matches else '')
" 2>"$JQP_ERR_FILE")"; then
      JQP_ERR="$(tail -1 "$JQP_ERR_FILE" 2>/dev/null || true)"
      rm -f "$JQP_ERR_FILE"
      log "FAIL (exit 10): could not PARSE the executions list response while reading bound execution $BOUND_EXEC_UUID's status ('${JQP_ERR:-<no error captured>}'). Deploy NOT triggered."
      exit 10
    fi
    rm -f "$JQP_ERR_FILE"
    [[ "$STATUS" != "running" && -n "$STATUS" ]] && break
  fi

  sleep "$POLL_INTERVAL_S"
done

if [[ -z "$BOUND_EXEC_UUID" ]]; then
  log "FAIL (exit 13): no execution uuid absent from the pre-fire snapshot ever appeared within the $((POLL_MAX_ATTEMPTS * POLL_INTERVAL_S))s poll ceiling -- THIS FIRE'S EXECUTION NEVER SHOWED UP, distinct from a confirmed migration failure (the Scheduled Task never even started, from this script's vantage point). Coolify's ScheduledTaskJob creates the execution row only once a queue worker actually begins processing the dispatched job, never at the execute call's response (see header comment) -- check the Coolify queue worker's health/backlog and the dashboard directly before re-firing. Deploy NOT triggered."
  exit 13
fi
# INTEGRITY CHECK ONLY, never a selector: if the execute response carried
# a candidate identifier, it must agree with what the set difference
# independently bound to. A disagreement means either this script's own
# candidate-extraction guessed the wrong key (a bug, not a security
# event) or something has gone genuinely wrong with the binding --
# either way, refuse to proceed on an execution whose own evidence
# disagrees with itself.
if [[ -n "$EXECUTE_RESPONSE_UUID_CANDIDATE" && "$EXECUTE_RESPONSE_UUID_CANDIDATE" != "$BOUND_EXEC_UUID" ]]; then
  log "FAIL (exit 14): the execute call's response carried a candidate execution identifier ($EXECUTE_RESPONSE_UUID_CANDIDATE) that does NOT match the execution uuid ($BOUND_EXEC_UUID) the set-difference binding independently selected. The set difference remains the selector (not this candidate) -- refusing to proceed while the two disagree rather than trusting either silently. Deploy NOT triggered. Investigate before re-firing."
  exit 14
fi
# The execution's own `message` field -- captured on EVERY terminal
# status, not just success. Fetched once, from the SAME row the poll
# loop's last iteration already read -- no second API call needed. Keyed
# to $BOUND_EXEC_UUID, NEVER to rows[0] position -- see the header
# comment: rows[0] can be a PREVIOUS execution's row during the
# dispatch-to-job-start queue lag, and reading `message` from it would
# parse tags from a run this fire did not cause.
# ⚠ CORRECTED from this PR's own earlier draft intent: C-4's original
# "include a tail of stderr on failure" carried over as "include a tail
# of message on failure" -- but Sec's later condition on Amendment 7
# (2026-09-17) is that this script logs ONLY the extracted PFIN-* tag
# values, NEVER the raw message blob, on any path, success or failure.
# The `failed)` branch below therefore does NOT log any part of
# $EXEC_MESSAGE, and tag-parsing is never attempted on a `failed` status
# either (strike requirement: parse only on `success`) -- operators use
# the Coolify dashboard's own execution log for failure diagnosis, not
# this script's stdout. Measured for this amendment's design against
# Coolify v4.3.18 source (see that amendment's own record): `message` on
# a successful execution holds the FULL merged stdout+stderr of the
# `docker exec`
# Coolify's own backend ran, capped at exactly 5MB with an explicit
# truncation marker appended only if that cap is hit.
EXEC_MESSAGE="$(printf '%s' "$EXEC_ROW_JSON" | jqp "
d=json.load(sys.stdin)
rows=d if isinstance(d, list) else d.get('data', d)
matches=[r for r in (rows or []) if (r or {}).get('uuid') == '$BOUND_EXEC_UUID']
print((matches[0] or {}).get('message','') if matches else '')
")"

case "$STATUS" in
  success)
    # ⚠ ADR-072 Amendment 7 (draft) -- ASSERT VIA THE EXECUTIONS API,
    # NEVER DOCKER (2026-09-17). This used to run `docker compose exec`
    # directly against the box for both a pre-fire sha-check and this
    # post-run delivery assertion. Sec's C-1 finding + F/CTO's box
    # measurement: `ci-migrate` has NO route to `/var/run/docker.sock` --
    # no group, no ACL, no sudo (`sudo -u ci-migrate docker compose ...`
    # -> permission denied, exit 1, measured live). Every docker call in
    # this script COULD NOT succeed (Sec's correction, carried from #800:
    # "always failing closed" overstates this as event history when
    # Amendment 7 §(F) is that these assertions never actually executed
    # on the box); the three earlier "working" fires only ever went
    # through the Coolify API. Removed entirely.
    #
    # scripts/migrator-scheduled-task.md's Command now emits three tagged
    # lines on its own stdout: `PFIN-BUILD-SHA=`, `PFIN-LEDGER-TOP=`,
    # `PFIN-NEWEST-FILE=`. Coolify's ScheduledTaskJob captures that
    # combined stdout+stderr into `message` on success (source-cited
    # measurement above) -- this script parses the three tags out of
    # `EXEC_MESSAGE` (already fetched above) instead of exec'ing anything
    # itself. No new host privilege, no docker socket, ever.
    #
    # ⚠ SELF-REPORTED EVIDENCE, NAMED AS SUCH (Sec's preliminary framing
    # on Amendment 7, PR #800 review): the task's own stdout is the same
    # evidentiary CLASS as the deployment-status poll ADR-072 Decision 3
    # already forbids -- a `db push` that silently applied nothing and
    # still echoed a clean-looking `PFIN-LEDGER-TOP=`/`PFIN-NEWEST-FILE=`
    # pair would pass this check. Sec has not yet graded the ratified
    # amendment; this Draft ships exactly what was briefed, not a
    # strengthened version of it -- do not soften or extend this parsing
    # unilaterally if that concern needs a different mechanism later.
    #
    # ⚠ THE APPLY ALREADY HAPPENED BY THE TIME ANY OF THIS RUNS. Unlike
    # Amendment 6's pre-fire sha-check, nothing here can gate the
    # Scheduled Task BEFORE it fires -- there is no docker-free way to
    # read the container's state in advance. If the assertions below
    # fail, the `db push` already executed against whatever image/state
    # existed at fire time; withholding the deploy does not undo the
    # apply. Named, not softened -- Architect/Sec/F/CTO's tradeoff, not
    # mine to work around here.
    #
    # Truncation check FIRST, before any tag extraction: a message cut at
    # the 5MB cap could have lost a tag entirely (if the cut landed
    # before `psql`/`ls` ever ran) or cut one mid-line -- either way,
    # nothing extracted from a truncated message can be trusted.
    if printf '%s' "$EXEC_MESSAGE" | grep -qF '[... Output truncated at 5MB limit ...]'; then
      log "FAIL (exit 9): the execution's own message was truncated at Coolify's 5MB cap -- cannot trust any PFIN-* tag extracted from a truncated capture (a tag may be cut mid-line, or lost entirely if the cut landed before it was ever printed). Deploy NOT triggered. This should not happen for this task's expected output size. See the execution record for this run at GET /applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks/$MIGRATOR_TASK_UUID/executions to investigate what the command actually printed before re-firing (raw message withheld from this log line by design -- Sec's own instruction is that this script logs only extracted PFIN-* tag values, never a raw message blob)."
      exit 9
    fi

    # Sec condition on Amendment 7 (2026-09-17): `db push` echoes migration
    # filenames into its own stdout as it applies -- a naive prefix grep can
    # match more than once. extract_one_tag() (defined above) requires
    # EXACTLY ONE anchored match per tag; zero or >=2 both fail closed via
    # its return code, never silently resolved by `tail -1` or any other
    # positional pick. Rc 1 = absent, rc 2 = ambiguous (>=2 matches) -- both
    # collapse to exit 8 below; the distinction is diagnostic only, logged,
    # never load-bearing for which code is returned.
    PFIN_BUILD_SHA_TAG="" ; PFIN_BUILD_SHA_RC=0
    PFIN_BUILD_SHA_TAG="$(extract_one_tag "$EXEC_MESSAGE" "PFIN-BUILD-SHA")" || PFIN_BUILD_SHA_RC=$?
    PFIN_LEDGER_TOP_TAG="" ; PFIN_LEDGER_TOP_RC=0
    PFIN_LEDGER_TOP_TAG="$(extract_one_tag "$EXEC_MESSAGE" "PFIN-LEDGER-TOP")" || PFIN_LEDGER_TOP_RC=$?
    PFIN_NEWEST_FILE_TAG="" ; PFIN_NEWEST_FILE_RC=0
    PFIN_NEWEST_FILE_TAG="$(extract_one_tag "$EXEC_MESSAGE" "PFIN-NEWEST-FILE")" || PFIN_NEWEST_FILE_RC=$?

    if [[ "$PFIN_BUILD_SHA_RC" -ne 0 || "$PFIN_LEDGER_TOP_RC" -ne 0 || "$PFIN_NEWEST_FILE_RC" -ne 0 ]]; then
      describe_rc() { case "$1" in 0) echo "ok";; 1) echo "absent";; 2) echo "ambiguous (>=2 matches)";; esac; }
      log "FAIL (exit 8): tagged-line extraction did not yield exactly one match for every tag (PFIN-BUILD-SHA: $(describe_rc "$PFIN_BUILD_SHA_RC"); PFIN-LEDGER-TOP: $(describe_rc "$PFIN_LEDGER_TOP_RC"); PFIN-NEWEST-FILE: $(describe_rc "$PFIN_NEWEST_FILE_RC")). Either the Scheduled Task's command changed / failed partway through before emitting all three lines, or the apply's own output echoed a duplicate-looking line (Sec's exactly-one-match condition, Amendment 7). Deploy NOT triggered. See the execution record for this run at GET /applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks/$MIGRATOR_TASK_UUID/executions to investigate (raw message withheld from this log line by design -- see the header comment on logging only extracted tags)."
      exit 8
    fi
    if [[ ! "$PFIN_BUILD_SHA_TAG" =~ ^[0-9a-f]{40}$ ]]; then
      log "FAIL (exit 8): PFIN-BUILD-SHA ('$PFIN_BUILD_SHA_TAG') is not a well-formed 40-character hex sha -- the task's own /workspace/.build-sha read is malformed or empty. Deploy NOT triggered. See the execution record for this run at GET /applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks/$MIGRATOR_TASK_UUID/executions for the full context."
      exit 8
    fi
    # Architect's Amendment-7 catch: STRING comparison of ledger/file
    # version prefixes breaks the moment either side changes digit-width
    # ('99' > '100' as strings). Both must be all-digits (fail closed
    # otherwise) and are then compared with forced base-10 arithmetic
    # (`10#...`), never `[[ = ]]`, so a width difference (e.g. a legacy
    # 3-digit migration vs a future 14-digit-timestamp one) still
    # compares correctly as numbers.
    if [[ ! "$PFIN_LEDGER_TOP_TAG" =~ ^[0-9]+$ || ! "$PFIN_NEWEST_FILE_TAG" =~ ^[0-9]+$ ]]; then
      log "FAIL (exit 8): PFIN-LEDGER-TOP ('$PFIN_LEDGER_TOP_TAG') or PFIN-NEWEST-FILE ('$PFIN_NEWEST_FILE_TAG') is not all-digits -- refusing a non-numeric comparison. Deploy NOT triggered. See the execution record for this run at GET /applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks/$MIGRATOR_TASK_UUID/executions for the full context."
      exit 8
    fi

    if [[ "$PFIN_BUILD_SHA_TAG" != "$MIGRATOR_EXPECT_SHA" ]]; then
      log "FAIL (exit 3): the migrator container's baked sha, as reported by this execution's own output ($PFIN_BUILD_SHA_TAG), does NOT match the sha this run was triggered for ($MIGRATOR_EXPECT_SHA). The container had NOT been rebuilt from the expected sha at fire time -- this is exactly the defect class the 2026-09-17 119 fire surfaced. The apply already ran against the wrong image; investigate before re-firing, and rebuild/redeploy the migrator image (Amendment 4 / this amendment's own consequence) first. Deploy NOT triggered."
      exit 3
    fi
    if (( 10#$PFIN_LEDGER_TOP_TAG != 10#$PFIN_NEWEST_FILE_TAG )); then
      log "FAIL (exit 6): the Scheduled Task reported success, but the ledger's top row ($PFIN_LEDGER_TOP_TAG, reported by this execution's own output) does not match the newest migration file present in the container at execution time ($PFIN_NEWEST_FILE_TAG). The apply did not actually deliver what the image says it should have -- this is the outcome-vs-status gap ADR-072 Amendment 6/7 exists to close. Deploy NOT triggered. Investigate before re-firing -- do not assume this is transient."
      exit 6
    fi
    log "outcome verified via the execution's own message: build-sha ($PFIN_BUILD_SHA_TAG) matches the triggering commit, ledger top row ($PFIN_LEDGER_TOP_TAG) matches the newest migration file ($PFIN_NEWEST_FILE_TAG)"

    # DEPLOY_ON_SUCCESS gate (Sec-ruled, Phase D deploy-gate consult): the
    # first live exercise of this externally-reachable path (ci-migrate's
    # forced command, reachable from GitHub Actions, holding a
    # [read,write,deploy] token) should do the smallest thing it is capable
    # of — apply the migration and stop, not also fire a real production
    # deploy the first time this trigger is ever pulled for real. Read from
    # $CONF_FILE ONLY, never from $SSH_ORIGINAL_COMMAND or any argument (C2
    # — this key sits on the trusted side of that line: $CONF_FILE is
    # already root:ci-migrate 0640, ci-migrate-unwritable, sourced wholesale
    # as fully-trusted box-resident input; this is one more key in that same
    # file, not a new control, and needs no fence or watcher of its own.
    # Fail-closed by POSITIVE test (deliberately NOT the ":?" abort pattern
    # the other keys above use) — unset, unreadable, "0", or any other value
    # withholds the deploy rather than aborting a migration that already
    # succeeded.
    if [[ "${DEPLOY_ON_SUCCESS:-0}" == "1" ]]; then
      log "migration apply SUCCEEDED — triggering app deploy (uuid $APP_UUID)"
      # ⚠ FIXED to POST, BACKLOG.md §7.36 item 59 PR (pre-existing defect,
      # not introduced by that PR): this call used to be `api GET
      # "/deploy?uuid=$APP_UUID"`. Measured against Coolify v4.3.18's
      # routes/api.php:144-145: GET /deploy is bound to
      # OtherController::post_required, which returns HTTP 405 ("This
      # endpoint has changed to a POST request.") unconditionally — this
      # call has never been able to succeed. Undetected until now because
      # DEPLOY_ON_SUCCESS defaults to 0 (the branch above), so this line
      # has never actually executed against production.
      api POST "/deploy?uuid=$APP_UUID" >/dev/null \
        || fail "migration succeeded but the app-deploy call itself failed — check the token's deploy ability. THE DB IS MIGRATED; the app was NOT redeployed. Investigate and redeploy manually before assuming this is a full failure."
      log "app deploy triggered"
    else
      # A suppressed deploy is a SUCCESS, not a failure — exit 0 so the
      # GitHub Actions job is green. Exiting non-zero here would invert
      # ADR-072 Decision 3's meaning: a red job would then mean "worked as
      # configured", exactly the signal-degradation D3 exists to prevent.
      log "migration apply SUCCEEDED — app deploy SUPPRESSED (DEPLOY_ON_SUCCESS!=1)"
    fi
    ;;
  failed)
    fail "migration apply FAILED (Scheduled Task execution status=failed) — app deploy NOT triggered. Coolify->Discord Scheduled-Task-failure routing already fired; check the execution log in the Coolify dashboard for the migration error."
    ;;
  *)
    fail "gave up after $((POLL_MAX_ATTEMPTS * POLL_INTERVAL_S))s waiting for a terminal execution status (last seen: '${STATUS:-<empty>}') — app deploy NOT triggered. This is a poll-timeout, not a confirmed migration failure; check the Coolify dashboard directly before retriggering."
    ;;
esac
