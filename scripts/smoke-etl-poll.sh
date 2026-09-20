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
#   0  the worker exited 0 AND at least one pfin.nav_daily row exists
#      for today
#   1  a real failure: the worker exited non-zero, OR it exited 0 but no
#      row exists for today (a silent no-op), OR ambiguous (>1) running
#      container match
#   2  a precondition this smoke could not even attempt under (box
#      unreachable, resource/container not found)

set -euo pipefail

BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
ETL_APP_NAME="${ETL_APP_NAME:-pfin-back-etl}"
ETL_SERVICE="pfin-back-etl-monthly-report"

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
die2() { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 2; }
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

step "Running one daily-NAV checkpoint poll"
set +e
WORKER_OUT="$(sshx "docker exec $CONTAINER python run_nav_daily.py" 2>&1)"
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
    cur.execute("select count(*) from pfin.nav_daily where nav_date = current_date")
    print(cur.fetchone()[0])
except Exception as exc:
    print(f"CONN_ERROR {exc}", file=sys.stderr)
    sys.exit(2)
'
set +e
COUNT_OUT="$(sshx "docker exec $CONTAINER python3 -c $(printf '%q' "$PY_COUNT_CHECK")")"
COUNT_RC=$?
set -e
if [[ $COUNT_RC -ne 0 ]]; then
  die2 "could not read pfin.nav_daily's row count (precondition, not a poll failure) -- see: $COUNT_OUT"
fi
[[ "$COUNT_OUT" =~ ^[0-9]+$ ]] || die2 "unexpected output from the row-count read-back: $COUNT_OUT"
if [[ "$COUNT_OUT" -lt 1 ]]; then
  die "run_nav_daily.py exited 0 with a completion log line, but pfin.nav_daily has ZERO rows for today -- a silent no-op (zero active tenants is possible but must be confirmed by hand before treating this as expected, not assumed here)."
fi
ok "pfin.nav_daily has $COUNT_OUT row(s) for today"

step "Done"
info "one real run_nav_daily.py poll completed (exit 0) and pfin.nav_daily carries $COUNT_OUT row(s) for today."
exit 0
