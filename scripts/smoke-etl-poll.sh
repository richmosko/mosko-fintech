#!/usr/bin/env bash
#
# smoke-etl-poll.sh -- docs/deployment-runbook.md §10 "ETL container runs
# one poll": trigger ONE real run of the daily NAV-checkpoint worker
# (`run_nav_daily.py`) and assert a `pfin.nav_daily` row exists for
# today. BACKLOG.md §7.36 item 68 (W-3). DevOps-owned.
#
# WHICH CONTAINER, AND WHY -- A FLAGGED GAP, NOT A SILENT WORKAROUND.
#   §7's own text names a real, committed gap: `pfin-back-etl`'s NIGHTLY
#   (resident) compose service -- the one `run_nav_daily.py`'s own
#   docstring calls "the worker entry point the scheduler will eventually
#   invoke" -- carries NO `PFIN_DB_*` environment wiring in
#   workers/etl/docker-compose.yaml today (only `PYTHONUNBUFFERED=1`);
#   only the SIBLING `pfin-back-etl-monthly-report` service (SAME image,
#   SAME build, confirmed by that compose file's own header) has
#   `PFIN_DB_*` wired. Wiring the nightly service is explicitly routed to
#   F/CTO (cadence ratify) + Backend (which entrypoint(s), the missing
#   `environment:` block) in that same runbook section -- NOT decided or
#   silently fixed here. Until that lands, this smoke runs
#   `run_nav_daily.py` INSIDE the monthly-report container instead --
#   same image, same DB role (`pfin_etl`), same script, a real and
#   idempotent write against the same table the nightly cron will
#   eventually target. This is the mechanism until the wiring gap closes,
#   named as such, not assumed to be the permanent shape.
#
# WHY "A ROW EXISTS FOR TODAY", NOT "THE COUNT INCREASED"
#   `nav_daily.py`'s own INSERT is `on conflict (users_id, nav_date) do
#   nothing` (workers/etl/src/pfin_back_etl/nav_daily.py) -- the worker is
#   DESIGNED to be idempotent within a day. A strict before/after count-
#   delta assertion would FALSE-NEGATIVE on any legitimate same-day
#   re-run (including the real nightly cron having already run today) --
#   exactly the kind of smoke that trains operators to ignore it. The
#   correct, idempotency-safe assertion is presence: at least one
#   `pfin.nav_daily` row with `nav_date = current_date` exists AFTER the
#   run, regardless of whether THIS invocation or an earlier one today
#   inserted it.
#
# TWO SIGNALS, NOT ONE
#   1. The worker's own exit code -- `run_nav_daily.py` propagates
#      `NavDailyWorker().run()`'s own failure signal; a non-zero exit is
#      load-bearing on its own.
#   2. The row-presence read-back -- catches the shape exit-code-alone
#      would miss: a worker that exits 0 but whose write silently no-op'd
#      for a reason exit code doesn't surface (e.g. zero active tenants
#      today, a permission grant regression that produced zero rows
#      without raising). Read via a plain `psycopg2` connection using the
#      SAME env credentials already present in the container (never this
#      script's own, never printed) -- a read-only COUNT, not a route
#      through TenantBoundConnection, which this DevOps-owned smoke has
#      no business importing (it is not repo `workers/etl/` source; it
#      never touches per-tenant rows, only an aggregate count).
#
# USAGE
#   BOX_IP=<box-ip> scripts/smoke-etl-poll.sh
#
#   ETL_APP_NAME (default pfin-back-etl) is env-var-overridable.
#
# EXIT CODES
#   0  VERIFIED -- the worker exited 0 AND at least one pfin.nav_daily
#      row exists for today
#   1  REFUSED -- the worker exited non-zero, OR it exited 0 but no row
#      exists for today (a silent no-op), OR ambiguous (>1) running
#      container match
#   2  FAILED -- a precondition this smoke could not even attempt under
#      (box unreachable, resource/container not found)
#   3  SKIPPED -- zero active (account-owning) tenants exist yet; the
#      worker was NOT run and NO checkpoint was written. Neither a pass
#      nor a real finding -- distinct from 0/1/2 so an orchestrator
#      (provision.sh) can treat it as non-fatal-but-not-verified rather
#      than silently reading it as either. See "Pre-check" below.
#
# WHY A PRE-CHECK, NOT A POST-HOC EXCUSE (Sec F-3, PR #848 review;
# F/CTO ruling 2026-09-20, option 1/B) -- run_nav_daily.py's own
# checkpoint INSERT is APPEND-ONLY and irreversible in normal operation
# (054's triggers make it un-bypassable even to `service_role`; see
# nav_daily.py's own module docstring). Running this smoke before any
# tenant has connected an account would write a PERMANENT, real
# pfin.nav_daily row the moment the first tenant does connect one --
# not a throwaway test artifact. The pre-check below counts active
# tenants BEFORE the worker ever runs, using the EXACT SAME selection
# query run_nav_daily.py's own NavDailyWorker.account_user_ids() uses
# (`select distinct users_id from pfin.account`, AS service_role --
# nav_daily.py's own module docstring: "account-owning tenants", not a
# guessed or narrower definition) -- so "active" here means precisely
# what the worker itself means by it, never a smoke-script guess. Zero
# -> SKIPPED (exit 3), worker never invoked. One or more -> proceeds
# exactly as before this fix, and DOES write a real checkpoint row --
# operators must run this only once accounts are actually connected
# (docs/deployment-runbook.md §7.2 / §10 state this explicitly next to
# the row that calls this script).
#
# ORCHESTRATOR CONTRACT (BACKLOG.md §7.36 item 68 W-5's provision.sh will
# call this directly): non-interactive, no prompts, no `read`. Idempotent
# by construction -- `run_nav_daily.py`'s own INSERT is `on conflict
# (users_id, nav_date) do nothing` (see below), so re-running this smoke
# any number of times in one day is safe: a repeat run still exits 0 as
# long as the row-presence check holds, never fails on "already ran
# today." Every fact used (container id, row count) is resolved LIVE
# each run, never cached.

set -euo pipefail

# WHICH PYTHON, AND WHY THIS MATTERS -- run-12 stop fix, 2026-09-21.
# workers/etl/Dockerfile's own convention: `WORKDIR /app` + `uv sync
# --frozen --no-dev` (uv's own default venv location is
# <project-root>/.venv, never overridden here) -- so the project's own
# dependencies (psycopg2-binary, per pyproject.toml) live ONLY at
# /app/.venv/bin/python. MEASURED live in the running etl container
# (23ca4985..., run 12): `which python3` -> /usr/local/bin/python3 (the
# python:3.14-slim BASE image's own system interpreter) has NO
# psycopg2/psycopg/sqlalchemy at all; /app/.venv/bin/python imports
# psycopg2 2.9.11 fine. Every `docker exec ... python3` call in this
# script's own prior revision used the wrong interpreter and failed at
# the very first import, misreported as "could not read pfin.account's
# active-tenant count" (a NO_PSYCOPG2 precondition, not a poll failure).
# Fixed by naming the interpreter ONCE, here, and never spelling out
# `python3`/`python` bare against this container again -- see the new
# preflight step below, which asserts this path exists and actually
# imports psycopg2 BEFORE either read depends on it, rather than letting
# a wrong-interpreter failure surface three steps later as an opaque
# CONN_ERROR-shaped message.
ETL_PYTHON="/app/.venv/bin/python"

BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
ETL_APP_NAME="${ETL_APP_NAME:-pfin-back-etl}"
ETL_SERVICE="pfin-back-etl-monthly-report"

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
die2() { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 2; }
skip3(){ printf '\n\033[33mSKIPPED\033[0m  %s\n' "$*"; exit 3; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

[[ -n "$BOX_IP" ]] || die2 "BOX_IP is required, not defaulted -- set it explicitly (same discipline as every other scripts/provision-*.sh / deploy-app.sh / coolify-env.sh)."

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }

sshx true >/dev/null 2>&1 || die2 "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die2 "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

read -r -d '' PY_API_HELPER <<'PY' || true
import json, sys, subprocess

def die(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)

def api(token, method, path):
    if '"' in token or "\n" in token:
        die("Coolify API token contains an unexpected character -- refusing to build a curl config for it")
    config = 'header = "Authorization: Bearer ' + token + '"\n'
    cmd = ["curl", "-fsS", "-K", "-", "-X", method, f"http://localhost:8000/api/v1{path}"]
    try:
        result = subprocess.run(cmd, input=config.encode(), capture_output=True, check=True)
    except subprocess.CalledProcessError as exc:
        die(f"Coolify API {method} {path} failed: exit {exc.returncode} ({exc.stderr.decode(errors='replace').strip()[:200]})")
    out = result.stdout.decode()
    return json.loads(out) if out.strip() else None
PY

step "Resolving '$ETL_APP_NAME'"
UUID_RE='^[a-z0-9]{20,32}$'
MATCH_MODE="name"
[[ "$ETL_APP_NAME" =~ $UUID_RE ]] && MATCH_MODE="uuid"
APP_QUERY_ENV="app_query=$(printf '%q' "$ETL_APP_NAME")"
APP_UUID="$(sshx "env $APP_QUERY_ENV bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "\$app_query" "$MATCH_MODE" <<'PYEOF'
$PY_API_HELPER
import sys
token, query, mode = sys.argv[1], sys.argv[2], sys.argv[3]
apps = api(token, "GET", "/applications")
field = "uuid" if mode == "uuid" else "name"
matches = [a for a in apps if a.get(field) == query]
if len(matches) != 1:
    die(f"expected exactly one application matching {field}='{query}', found {len(matches)}")
print(matches[0]["uuid"])
PYEOF
REMOTE
)"
[[ "$APP_UUID" =~ $UUID_RE ]] || die2 "could not resolve '$ETL_APP_NAME' to a uuid-shaped application id"
ok "resolved '$ETL_APP_NAME' -> $APP_UUID"

step "Finding the running '$ETL_SERVICE' container"
RUNNING_LIST="$(sshx "docker compose --project-name $APP_UUID ps -q $ETL_SERVICE | xargs -r -I{} docker inspect --format '{{.State.Running}}{{\"\\t\"}}{{.Id}}{{\"\\t\"}}{{.Created}}' {} | awk -F'\t' '\$1==\"true\"{print \$2\"\t\"\$3}'")"
[[ -n "$RUNNING_LIST" ]] || die2 "no running container found for compose service '$ETL_SERVICE' under project '$APP_UUID' -- is '$ETL_APP_NAME' deployed and healthy? (scripts/deploy-app.sh)"
RUNNING_COUNT="$(printf '%s\n' "$RUNNING_LIST" | grep -c .)"
[[ "$RUNNING_COUNT" -eq 1 ]] \
  || die "AMBIGUOUS: $RUNNING_COUNT running containers match compose service '$ETL_SERVICE' under project '$APP_UUID' -- refusing to silently pick one. Matches:
$RUNNING_LIST
Investigate on the box (docker compose --project-name $APP_UUID ps -a) before trusting which one this smoke should target."
CONTAINER="$(awk -F'\t' '{print $1}' <<<"$RUNNING_LIST")"
ok "running container: $CONTAINER"

step "Preflight: confirming the container's own project interpreter"
sshx "docker exec $CONTAINER test -x $ETL_PYTHON" </dev/null >/dev/null 2>&1 \
  || die2 "$ETL_PYTHON does not exist or is not executable in container $CONTAINER -- either the image build changed (uv's venv location, or the base image path) or this container predates that convention. Investigate before assuming the interpreter path above still holds; do not fall back to a bare 'python3' (the system interpreter has no psycopg2 -- see this script's own header)."
PSYCOPG2_PROBE_OUT="$(sshx "docker exec $CONTAINER $ETL_PYTHON -c 'import psycopg2'" </dev/null 2>&1)" \
  || die2 "$ETL_PYTHON exists but 'import psycopg2' failed in container $CONTAINER: $PSYCOPG2_PROBE_OUT -- the venv itself may be stale or incomplete (uv sync did not run, or ran against a different lockfile). This is a precondition failure, not a poll failure -- investigate the image build before re-running."
ok "$ETL_PYTHON exists and imports psycopg2 -- proceeding with the real reads below"

step "Pre-check: active (account-owning) tenant count"
PY_TENANT_CHECK='
import os, sys
try:
    import psycopg2
except ImportError:
    print("NO_PSYCOPG2", file=sys.stderr)
    sys.exit(2)
try:
    conn = psycopg2.connect(
        host=os.environ["PFIN_DB_HOST"],
        port=os.environ["PFIN_DB_PORT"],
        dbname=os.environ["PFIN_DB_NAME"],
        user=os.environ["PFIN_DB_USER"],
        password=os.environ["PFIN_DB_PASSWORD"],
        sslmode=os.environ.get("PFIN_DB_SSLMODE", "require"),
        connect_timeout=10,
    )
    cur = conn.cursor()
    # Sec F-3 / F/CTO ruling 2026-09-20 -- SAME selection query and SAME
    # role assumption as the NavDailyWorker.account_user_ids() method in
    # nav_daily.py -- active means exactly what the worker itself means
    # by it: distinct account-owning tenants, open or closed accounts
    # alike (that filtering happens inside fn_compute_nav, not here --
    # restating it here would let the two definitions drift).
    cur.execute("set local role service_role")
    cur.execute("select count(distinct users_id) from pfin.account")
    print(cur.fetchone()[0])
except Exception as exc:
    print(f"CONN_ERROR {exc}", file=sys.stderr)
    sys.exit(2)
'
set +e
TENANT_COUNT_OUT="$(sshx "docker exec $CONTAINER $ETL_PYTHON -c $(printf '%q' "$PY_TENANT_CHECK")")"
TENANT_COUNT_RC=$?
set -e
if [[ $TENANT_COUNT_RC -ne 0 ]]; then
  die2 "could not read pfin.account's active-tenant count (precondition, not a poll failure) -- see: $TENANT_COUNT_OUT"
fi
[[ "$TENANT_COUNT_OUT" =~ ^[0-9]+$ ]] || die2 "unexpected output from the active-tenant count read-back: $TENANT_COUNT_OUT"
if [[ "$TENANT_COUNT_OUT" -eq 0 ]]; then
  skip3 "zero active tenants -- nav_daily checkpoint not written. Re-run once at least one tenant has connected an account."
fi
ok "$TENANT_COUNT_OUT active (account-owning) tenant(s) -- proceeding to a real, permanent checkpoint write"

step "Running one daily-NAV checkpoint poll"
set +e
WORKER_OUT="$(sshx "docker exec $CONTAINER $ETL_PYTHON run_nav_daily.py" 2>&1)"
WORKER_RC=$?
set -e
info "$(tail -5 <<<"$WORKER_OUT")"
if [[ $WORKER_RC -ne 0 ]]; then
  echo "$WORKER_OUT" >&2
  die "run_nav_daily.py exited $WORKER_RC (see full output above) -- the poll itself failed."
fi
if ! grep -qF "Finished at" <<<"$WORKER_OUT"; then
  die "run_nav_daily.py exited 0 but its own completion log line ('Finished at ...') is absent -- treating this as an incomplete run, not a pass."
fi
ok "worker exited 0 with a completion log line"

step "Asserting a pfin.nav_daily row exists for today"
PY_COUNT_CHECK='
import os, sys
try:
    import psycopg2
except ImportError:
    print("NO_PSYCOPG2", file=sys.stderr)
    sys.exit(2)
try:
    conn = psycopg2.connect(
        host=os.environ["PFIN_DB_HOST"],
        port=os.environ["PFIN_DB_PORT"],
        dbname=os.environ["PFIN_DB_NAME"],
        user=os.environ["PFIN_DB_USER"],
        password=os.environ["PFIN_DB_PASSWORD"],
        sslmode=os.environ.get("PFIN_DB_SSLMODE", "require"),
        connect_timeout=10,
    )
    cur = conn.cursor()
    # Sec V-2 (PR #848 round-2 review) -- PFIN_DB_USER (pfin_etl) is
    # NOINHERIT and holds NO direct table privileges by design (055:190);
    # an unqualified SELECT here fails 42501, same as every other pfin_etl
    # statement this repo runs. service_role holds
    # select (users_id, nav_date) on pfin.nav_daily (054:615) -- assume it
    # explicitly, exactly as the pre-check above already does. No grant
    # change; do not add privileges to pfin_etl to work around this.
    cur.execute("set local role service_role")
    cur.execute("select count(*) from pfin.nav_daily where nav_date = current_date")
    print(cur.fetchone()[0])
except Exception as exc:
    print(f"CONN_ERROR {exc}", file=sys.stderr)
    sys.exit(2)
'
set +e
COUNT_OUT="$(sshx "docker exec $CONTAINER $ETL_PYTHON -c $(printf '%q' "$PY_COUNT_CHECK")")"
COUNT_RC=$?
set -e
if [[ $COUNT_RC -ne 0 ]]; then
  die2 "could not read pfin.nav_daily's row count (precondition, not a poll failure) -- see: $COUNT_OUT"
fi
[[ "$COUNT_OUT" =~ ^[0-9]+$ ]] || die2 "unexpected output from the row-count read-back: $COUNT_OUT"
if [[ "$COUNT_OUT" -lt 1 ]]; then
  die "run_nav_daily.py exited 0 with a completion log line, but pfin.nav_daily has ZERO rows for today -- a silent no-op. The pre-check above already confirmed >=1 active tenant exists, so 'zero active tenants' is NOT an available explanation here -- this is a real finding (grant/constraint drift, or the worker silently skipping a tenant it should have written)."
fi
ok "pfin.nav_daily has $COUNT_OUT row(s) for today"

step "Done"
info "one real run_nav_daily.py poll completed (exit 0) and pfin.nav_daily carries $COUNT_OUT row(s) for today."
exit 0
