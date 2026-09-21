#!/usr/bin/env bash
#
# pgrst-exposure-gates.sh -- docs/deployment-runbook.md Part 3's pre-flip
# gates (§6.9 steps 1-3, Sec's B-1/B-2/B-3 conditions). BACKLOG.md §7.36
# item 66 (W-5). DevOps-owned. Three read-only psql checks, run against
# the LIVE production database, that must all pass before
# PGRST_DB_SCHEMAS is flipped to expose the `pfin` schema to the Data
# API -- a CI-green two-tenant battery observes CI's own scratch DB, not
# this box, and is not evidence here (see B-1's own text,
# docs/archive/deployment-runbook-rationale-2026-09-20.md §6.9).
#
# SOURCE OF TRUTH -- every query below is transcribed verbatim from that
# archive section ("B-1 -- VETO trigger" / "B-2 -- applied migration
# count" / "B-3 -- 025 present"), not re-derived.
#
# B-1 (VETO): anon must hold NEITHER schema-level USAGE on `pfin` NOR any
#   table-level SELECT/INSERT/UPDATE/DELETE on any `pfin` relation,
#   enumerated dynamically (never a hand-maintained list, which silently
#   stops covering a relation added after the list was written).
# B-2: the applied-migration ledger count must equal the LIVE count of
#   supabase/migrations/*.sql files in THIS repo checkout, re-counted
#   every run -- never a baseline pinned in the script (the archive's own
#   stated trap: a fixed number RED's a correct box the moment new
#   migrations land).
# B-3: exactly one ledger row for migration 025 (025_aal2_step_up_backstop.sql).
#
# Sec N-5 (PR #849 review, noted, not asked for): the B-1 relation
# enumeration uses `has_table_privilege`, which does not see column-level
# grants, and `relkind in ('r','v','m','p')` omits foreign tables ('f')
# and sequences ('S'); neither leg sees a role-level `ALTER DEFAULT
# PRIVILEGES` grant that would apply to a FUTURE relation. All three are
# subsumed by the schema-level `has_schema_privilege('anon','pfin',
# 'USAGE') = f` leg above, which is the actually-binding fence for this
# gate -- stated so this known scope limit of the enumeration leg is
# never read as a gap in the control itself.
#
# USAGE
#   scripts/pgrst-exposure-gates.sh              # preflight: read-only (this script is ENTIRELY read-only -- no --apply flag exists)
#
#   BOX_IP is read from .env (script-written by provision-vps.sh --apply).
#
# EXIT CODES
#   0  VERIFIED -- all three gates pass.
#   1  REFUSED -- a real finding: B-1's VETO trigger fired (anon holds a
#      grant it must not), B-2's count mismatches, or B-3 found zero or
#      more than one row for migration 025.
#   2  FAILED -- a precondition this script could not even attempt under
#      (box unreachable, stack resource not found).
#
# ORCHESTRATOR CONTRACT (BACKLOG.md §7.36 item 76's provision.sh calls
# this directly): non-interactive, no prompts, no `read`. Every fact used
# is resolved LIVE each run -- this script has no state of its own to be
# idempotent ABOUT; it is a pure read-only gate, safe to re-run any
# number of times.

set -euo pipefail

if [[ -n "${REPO_ROOT:-}" ]]; then
  :
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ "$SCRIPT_DIR" == *"/.claude/worktrees/"* ]]; then
    printf '\n\033[31mFAIL\033[0m  running from an agent worktree (%s) -- set REPO_ROOT=<main checkout path> to override, or run this script from the main checkout.\n' "$SCRIPT_DIR" >&2
    exit 1
  fi
  GIT_COMMON_DIR="$(git -C "$SCRIPT_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || GIT_COMMON_DIR=""
  if [[ -z "$GIT_COMMON_DIR" ]]; then
    printf '\n\033[31mFAIL\033[0m  could not resolve the repo root via git rev-parse --git-common-dir from %s (not inside a git checkout?). Set REPO_ROOT explicitly.\n' "$SCRIPT_DIR" >&2
    exit 1
  fi
  REPO_ROOT="$(cd "$(dirname "$GIT_COMMON_DIR")" && pwd)"
fi

AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
STACK_APP_NAME="${STACK_APP_NAME:-pfin-supabase-stack}"

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
die2() { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 2; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

for arg in "$@"; do
  case "$arg" in
    *) echo "unknown flag: $arg" >&2; echo "usage: $0 (read-only, no flags)" >&2; exit 2 ;;
  esac
done

BOX_IP="$(grep -m1 '^BOX_IP=' "$REPO_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d '\r\n' || true)"
[[ -n "$BOX_IP" ]] || die2 "BOX_IP absent/blank in $REPO_ROOT/.env -- run scripts/provision-vps.sh --apply first"

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

step "Resolving '$STACK_APP_NAME'"
UUID_RE='^[a-z0-9]{20,32}$'
STACK_UUID="$(sshx "env stack_name=$(printf '%q' "$STACK_APP_NAME") bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "\$stack_name" <<'PYEOF'
$PY_API_HELPER
import sys
token, stack_name = sys.argv[1], sys.argv[2]
apps = api(token, "GET", "/applications")
matches = [a for a in apps if a.get("name") == stack_name]
if len(matches) != 1:
    die(f"expected exactly one application named '{stack_name}', found {len(matches)}")
print(matches[0]["uuid"])
PYEOF
REMOTE
)"
[[ "$STACK_UUID" =~ $UUID_RE ]] || die2 "could not resolve '$STACK_APP_NAME' to a uuid-shaped application id"
ok "resolved '$STACK_APP_NAME' -> $STACK_UUID"

psql_scalar() {
  # `</dev/null` (Sec VETO-1 / team-lead's tree-wide follow-up, PR #854) --
  # this exec is the LAST line of its own heredoc today, so nothing
  # currently gets drained by it, but that is a position-dependent
  # accident, not a guarantee -- redirect defensively, unconditionally.
  sshx "env STACK_UUID=\"$STACK_UUID\" bash -s" <<REMOTE
set -e
docker compose --project-name "\$STACK_UUID" exec -T db psql -U supabase_admin -d postgres -tAc "$1" </dev/null
REMOTE
}

step "B-1 -- VETO trigger: anon zero-grant fence (schema USAGE + every pfin relation, enumerated dynamically)"
ANON_USAGE="$(psql_scalar "select has_schema_privilege('anon', 'pfin', 'USAGE')::text;" | tr -d ' \n')"
info "anon_schema_usage = $ANON_USAGE (expect f)"
GRANTED_RELATIONS="$(psql_scalar "select n.nspname || '.' || c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'pfin' and c.relkind in ('r','v','m','p') and (has_table_privilege('anon', c.oid, 'SELECT') or has_table_privilege('anon', c.oid, 'INSERT') or has_table_privilege('anon', c.oid, 'UPDATE') or has_table_privilege('anon', c.oid, 'DELETE'));")"
GRANTED_COUNT="$(printf '%s' "$GRANTED_RELATIONS" | grep -c . || true)"
info "pfin relations anon holds a grant on: $GRANTED_COUNT (expect 0)"
if [[ "$ANON_USAGE" == "t" || "$GRANTED_COUNT" -ne 0 ]]; then
  die "B-1 VETO: anon_schema_usage=$ANON_USAGE, granted relation count=$GRANTED_COUNT -- anon must hold NEITHER before pfin is exposed. STOP -- do not proceed to the PGRST_DB_SCHEMAS flip. Offending relations:
$GRANTED_RELATIONS"
fi
ok "B-1 clean: anon holds no pfin grant of any kind"

step "B-2 -- applied migration count vs. this checkout's supabase/migrations/*.sql (re-counted live, never a pinned baseline)"
EXPECTED_COUNT="$(find "$REPO_ROOT/supabase/migrations" -maxdepth 1 -name '*.sql' -type f | wc -l | tr -d ' ')"
LIVE_COUNT="$(psql_scalar "select count(*) from supabase_migrations.schema_migrations;" | tr -d ' \n')"
info "supabase/migrations/*.sql in this checkout: $EXPECTED_COUNT; ledger count: $LIVE_COUNT"
[[ "$LIVE_COUNT" == "$EXPECTED_COUNT" ]] || die "B-2: ledger count ($LIVE_COUNT) does not equal this checkout's migration-file count ($EXPECTED_COUNT). Either the apply is incomplete, or this checkout is not the sha that was deployed -- investigate before proceeding."
ok "B-2 clean: ledger count matches"

step "B-3 -- migration 025 present (exactly one row)"
ROWS_025="$(psql_scalar "select version from supabase_migrations.schema_migrations where version like '025%';")"
COUNT_025="$(printf '%s' "$ROWS_025" | grep -c . || true)"
info "025%% rows: $COUNT_025 ($ROWS_025)"
[[ "$COUNT_025" -eq 1 ]] || die "B-3: expected exactly one ledger row matching '025%', found $COUNT_025."
ok "B-3 clean: exactly one 025 row"

step "Done"
info "All three pre-flip gates (B-1/B-2/B-3) pass -- safe to proceed to the PGRST_DB_SCHEMAS flip."
exit 0
