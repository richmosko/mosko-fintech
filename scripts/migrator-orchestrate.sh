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
# WHAT IT DOES (ADR-072 Decision 2 + Decision 3 + Amendment 7 draft)
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
#   ⚠ DRAFT — NOT TO MERGE BEFORE ADR-072 AMENDMENT 7 IS RATIFIED. The sha
#   and delivery checks below no longer gate BEFORE the Scheduled Task
#   fires (they can't — nothing here can read the container's state
#   without docker access) — they are asserted AFTER a successful run,
#   against that same run's own self-reported output. If the assertions
#   ever fail, the `db push` this run fired has ALREADY executed against
#   whatever image/state existed at fire time; the app deploy is withheld,
#   but the migration apply itself is not undone. This is a deliberate,
#   named tradeoff of Amendment 7's design (the alternative being no
#   outcome assertion at all, since ci-migrate cannot reach the socket to
#   check anything beforehand) — Architect/Sec/F/CTO's call, not mine to
#   soften or work around here.
#
#   The calling GitHub Actions workflow gates on THIS script's own SSH exit
#   code — GHA's native step-sequencing is the fail-closed gate (ADR-072
#   Consequences / this ADR's GitHub Actions item): a non-zero exit here
#   fails the SSH step, which fails the job, which stops the workflow before
#   anything downstream runs. There is no separate "poll Coolify" step in the
#   workflow — polling happens HERE, inside the one orchestrated unit whose
#   exit code the SSH channel carries.
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

api() { # api <METHOD> <PATH>
  curl -fsS -X "$1" -H "Authorization: Bearer $COOLIFY_API_TOKEN" "$COOLIFY_BASE$2"
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
# is application-attached).
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
TASK_LIST_JSON="$(api GET "/applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks" || true)"
if [[ -z "$TASK_LIST_JSON" ]]; then
  log "FAIL (exit 10): could not GET the Scheduled Task list to verify the migrator task's command before firing. Refusing to fire against an unverifiable task. See the task list directly at GET /applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks. NOT executing the Scheduled Task."
  exit 10
fi
TASK_MATCH_COUNT="$(printf '%s' "$TASK_LIST_JSON" | jqp "
d=json.load(sys.stdin)
rows=d if isinstance(d, list) else d.get('data', d)
print(sum(1 for r in (rows or []) if (r or {}).get('uuid') == '$MIGRATOR_TASK_UUID'))
")"
if [[ "$TASK_MATCH_COUNT" != "1" ]]; then
  log "FAIL (exit 10): the Scheduled Task list returned $TASK_MATCH_COUNT entries matching MIGRATOR_TASK_UUID ($MIGRATOR_TASK_UUID) -- expected exactly one (zero means the task was deleted or the UUID is wrong; two-or-more should be impossible for a UUID but is refused rather than resolved by position, same discipline as the tagged-line extraction below). See the task list directly at GET /applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks. NOT executing the Scheduled Task."
  exit 10
fi
LIVE_TASK_COMMAND="$(printf '%s' "$TASK_LIST_JSON" | jqp "
d=json.load(sys.stdin)
rows=d if isinstance(d, list) else d.get('data', d)
matches=[r for r in (rows or []) if (r or {}).get('uuid') == '$MIGRATOR_TASK_UUID']
print((matches[0] or {}).get('command','') if matches else '')
")"
LIVE_TASK_COMMAND="$(strip_ws "$LIVE_TASK_COMMAND")"
EXPECTED_TASK_COMMAND="$(strip_ws "$MIGRATOR_TASK_COMMAND")"
if [[ -z "$LIVE_TASK_COMMAND" || "$LIVE_TASK_COMMAND" != "$EXPECTED_TASK_COMMAND" ]]; then
  log "FAIL (exit 10): the Scheduled Task's command in Coolify differs from MIGRATOR_TASK_COMMAND in /etc/pfin/migrator-trigger.conf -- change it in ONE place per docs/deployment-runbook.md §6.5 (byte-exact comparison; leading/trailing space, tab, CR, LF stripped from both sides, nothing else). NOT executing the Scheduled Task. Re-run provision-vps.sh --apply after confirming which side is stale, or investigate an unauthorized edit -- do not just re-fire. (Live and expected command text withheld from this log line by design -- Sec's own instruction is that this script logs only extracted PFIN-* tag values, never a raw command/message blob. See the live task list directly at GET /applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks and compare the matching entry's \`command\` against \$CONF_FILE's MIGRATOR_TASK_COMMAND by hand.)"
  exit 10
fi
log "task command integrity check OK: live Scheduled Task command matches MIGRATOR_TASK_COMMAND in $CONF_FILE"

log "executing migrator Scheduled Task ($MIGRATOR_TASK_UUID) on application $MIGRATOR_SERVICE_UUID"
# Item 15 fix (Sec-gated, booked BACKLOG.md §7.36 #15): the migrator
# Scheduled Task is attached to an APPLICATION resource (the Supabase-stack
# Coolify app, standup-log.md Phase A.2 — created via
# `POST /applications/{uuid}/scheduled-tasks`, i.e.
# ScheduledTasksController::create_scheduled_task_by_application_uuid), not
# a Service resource. Coolify 4.3.18's routes/api.php defines TWO separate
# route families for scheduled tasks, each bound to its own controller
# method and resource table: `/applications/{uuid}/scheduled-tasks/...`
# (execute -> execute_scheduled_task_by_application_uuid, executions ->
# executions_by_application_uuid) and `/services/{uuid}/scheduled-tasks/...`
# (its own distinct by_service_uuid methods). Addressing an
# application-attached task under `/services/` 404s — confirmed by reading
# routes/api.php directly (github.com/coollabsio/coolify, tag v4.3.18),
# not assumed. Corrected to the `/applications/` family below.
api POST "/applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks/$MIGRATOR_TASK_UUID/execute" >/dev/null \
  || fail "could not start the Scheduled Task (execute call itself failed — check the token's write ability and the UUIDs in $CONF_FILE)"

log "polling execution status (never Coolify's deployment status — ADR-072 Decision 3)"
STATUS=""
EXEC_ROW_JSON=""
for _ in $(seq 1 "$POLL_MAX_ATTEMPTS"); do
  EXEC_ROW_JSON="$(api GET "/applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks/$MIGRATOR_TASK_UUID/executions")"
  STATUS="$(printf '%s' "$EXEC_ROW_JSON" | jqp "
d=json.load(sys.stdin)
rows=d if isinstance(d, list) else d.get('data', d)
print((rows[0] or {}).get('status','') if rows else '')
")"
  [[ "$STATUS" != "running" && -n "$STATUS" ]] && break
  sleep "$POLL_INTERVAL_S"
done
# The execution's own `message` field -- captured on EVERY terminal
# status, not just success. Fetched once, from the SAME row the poll
# loop's last iteration already read -- no second API call needed.
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
print((rows[0] or {}).get('message','') if rows else '')
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
      api GET "/deploy?uuid=$APP_UUID" >/dev/null \
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
