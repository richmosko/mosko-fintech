#!/usr/bin/env bash
#
# db-bootstrap.sh -- docs/deployment-runbook.md Part 3 row 3 (§6.3):
# database bootstrap -- create pfin_owner/migrator, activate the migrator
# credential, apply migrations 001-118(+), create the vault decrypt
# view. BACKLOG.md §7.36 item 75 (W-5). DevOps-owned.
#
# 🔒 SECURITY-SENSITIVE -- Sec joint-review mandatory. This is a NEW
# privileged-automation surface: every statement in Phase 1/Phase 3 runs
# AS `supabase_admin`, the box's true superuser (measured 2026-09-14 --
# `postgres` is NOT a superuser on this image, holds only
# rolcreaterole/rolcreatedb, and fails Phase 3's `ALTER DATABASE … OWNER`
# with "must be able to SET ROLE"). No prior script in this repo has run
# ANY statement as `supabase_admin` -- every sibling script (db-role-
# handoff.sh, push-production-secrets.sh, ...) operates at a narrower
# privilege level. Read this script's own statements before trusting it.
#
# SOURCE OF TRUTH -- every statement below is transcribed from the
# reconstructed, MEASURED §6.3 procedure at
# docs/archive/deployment-runbook-rationale-2026-09-20.md (search
# "PHASE 1 (pre-step)" / "PHASE 2 (main pass)" / "PHASE 3 (post-step)"),
# not re-derived. That text is itself the record of a real re-bootstrap
# run (2026-09-17) that found and fixed defects in an earlier draft of
# this exact procedure (a duplicate `create schema pfin` statement, the
# `PGSSLMODE=disable` requirement, the `--yes --db-url` flag). Deviating
# from that transcription without re-reading the archive risks
# reproducing an already-fixed defect.
#
# REFUSES TO RUN OUTSIDE AN OPERATOR SSH SESSION, STRUCTURALLY, NOT BY A
# RUNTIME CHECK -- this script establishes its OWN SSH connection to the
# box (via `sshx`, the operator's own `$AUTOMATION_KEY`), exactly like
# every sibling operator-side script. A Coolify Scheduled Task executes
# `docker exec` commands INSIDE a container -- it has no code path that
# could invoke this script at all, on the operator's own machine or
# anywhere else. This is the enforcement mechanism BACKLOG item 75's own
# AC names ("must never own this bootstrap"): the script's own topology,
# not a flag this script checks and could be bypassed by unsetting.
#
# THREE PHASES
#   Phase 1 (pre-step, supabase_admin, THIS script, scripted): roles.sql
#     -> auth-grants.sql -> CREATE SCHEMA pfin + the engine-backstop
#     REVOKEs -> the migrator credential handoff, FIVE legs (A-E), same
#     shape as db-role-handoff.sh's own (that script's header has the full
#     derivation; not re-derived here):
#       A) \password migrator + ALTER ROLE migrator LOGIN (generate
#          locally, deliver as a 0600 seed, never argv, never an env
#          dump), -v ON_ERROR_STOP=1 on the psql invocation.
#       B) catalog verify -- rolcanlogin + pg_authid.rolpassword IS NOT
#          NULL, re-read fresh.
#       C) connect AS migrator over -h db (never -h localhost -- the
#          container-internal loopback trust-path hazard db-role-
#          handoff.sh's own header documents) with the generated
#          credential, asserting a password prompt WAS observed, no
#          cleartext leak, and current_user echoes back 'migrator'.
#       D) 🔒 push the SAME credential onto the `pfin-migrator` Coolify
#          resource's own env store as MIGRATOR_DB_PASSWORD (Sec VETO-1,
#          PR #849 review). WITHOUT this leg, the Postgres role's actual
#          password (this leg's PW) and the migrator container's own
#          PROD_DB_URL (built from provision-migrator-app.sh's
#          INDEPENDENTLY minted MIGRATOR_DB_PASSWORD -- a different random
#          value, minted when that resource was first created) diverge:
#          Phase 2 auth-fails, and the re-run then hits the partial-state
#          guard below permanently (no scripted repair exists). This leg
#          is the reconciliation -- the two values must be the SAME one,
#          and leg A's freshly-generated PW is the one already proven live
#          (by legs B/C) against the actual Postgres role, so it is what
#          gets pushed, overwriting whatever provision-migrator-app.sh
#          minted.
#       E) hash-bound readback -- production row only (is_preview=false),
#          exactly one match, a truncated SHA-256 of the stored value must
#          match the same truncated hash of the credential this run
#          generated (never the plaintext value, on either side).
#     Then the 055/116/117/118/119 role-comment files, run directly
#     (idempotent -- each file's own guard degrades to a WARNING and
#     reports the pre-step already ran, never a silent skip).
#   Phase 2 (main pass, the migrator container, THIS script, scripted):
#     `supabase db push --yes --db-url "$PROD_DB_URL" --workdir
#     /workspace` inside the migrator container. PGSSLMODE=disable is
#     REQUIRED in that container's own environment (measured --
#     provision-migrator-app.sh already sets it; this script does not
#     duplicate that, only depends on it).
#   Phase 3 (post-step, supabase_admin, THIS script, scripted):
#     `psql -f supabase/post-step-vault-view.sql` -- creates the vault
#     decrypt view, transfers it to pfin_owner, and asserts (inside the
#     file itself) exactly one pfin decrypt view exists,
#     security_invoker=true. This script does not re-implement that
#     assertion -- a non-zero exit from the file IS the failure signal.
#
# WHAT THIS SCRIPT DELIBERATELY DOES NOT DO -- the archive's own
# procedure names a "wipe first" recovery path (drop schema pfin cascade;
# drop schema supabase_migrations cascade;) for a box that already has a
# PARTIAL prior apply, gated behind three measured-by-hand conditions
# (zero non-seed pfin rows, auth.users = 0, the outside-pfin enumeration
# empty). That path is NOT built here -- it is a rare, destructive,
# judgment-laden recovery action, not a first-bootstrap step. This
# script's own preflight detects "already bootstrapped" (bootstrap_complete
# = t) and reports success as a no-op; it detects "partially bootstrapped"
# (some but not all of Phase 1/2/3 landed) and REFUSES rather than
# guessing which repair path applies.
#
# USAGE
#   scripts/db-bootstrap.sh              # preflight: read-only, prints the plan
#   scripts/db-bootstrap.sh --apply      # runs Phase 1 -> 2 -> 3
#
#   BOX_IP is read from .env (script-written by provision-vps.sh --apply).
#
# EXIT CODES
#   0  VERIFIED -- bootstrap_complete = t, the ownership census shows
#      every pfin object owned by pfin_owner (zero postgres/migrator-
#      owned), and Phase 3's own assertion (the decrypt-view file itself)
#      exited 0.
#   1  REFUSED -- a real finding: the ownership census shows a
#      postgres/migrator-owned pfin object (the pfin_owner sweep broke
#      somewhere), a partial-bootstrap state this script refuses to
#      guess a repair for, or any phase's own script/statement failed.
#   2  FAILED -- a precondition this script could not even attempt under
#      (box unreachable, migrator container/resource not found).
#
# ORCHESTRATOR CONTRACT (BACKLOG.md §7.36 item 76's provision.sh calls
# this directly): non-interactive, no prompts, no `read`. Idempotent by
# construction on the ALREADY-BOOTSTRAPPED case (reports VERIFIED,
# touches nothing) -- NOT idempotent on a genuinely partial state, which
# it refuses rather than repairs (see above). Every fact used (role
# state, ledger state, ownership census) is resolved LIVE each run.

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
MIGRATOR_APP_NAME="${MIGRATOR_APP_NAME:-pfin-migrator}"

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
die2() { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 2; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    *) echo "unknown flag: $arg" >&2; echo "usage: $0 [--apply]" >&2; exit 2 ;;
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

step "Resolving the Supabase-stack project uuid and the migrator app uuid"
UUID_RE='^[a-z0-9]{20,32}$'
RESOLVED="$(sshx "env stack_name=$(printf '%q' "$STACK_APP_NAME") migrator_name=$(printf '%q' "$MIGRATOR_APP_NAME") bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "\$stack_name" "\$migrator_name" <<'PYEOF'
$PY_API_HELPER
import sys
token, stack_name, migrator_name = sys.argv[1], sys.argv[2], sys.argv[3]
apps = api(token, "GET", "/applications")
stack_matches = [a for a in apps if a.get("name") == stack_name]
migrator_matches = [a for a in apps if a.get("name") == migrator_name]
if len(stack_matches) != 1:
    die(f"expected exactly one application named '{stack_name}', found {len(stack_matches)}")
if len(migrator_matches) != 1:
    die(f"expected exactly one application named '{migrator_name}', found {len(migrator_matches)}")
print(stack_matches[0]["uuid"])
print(migrator_matches[0]["uuid"])
PYEOF
REMOTE
)"
STACK_UUID="$(sed -n '1p' <<<"$RESOLVED")"
MIGRATOR_UUID="$(sed -n '2p' <<<"$RESOLVED")"
[[ "$STACK_UUID" =~ $UUID_RE ]] || die2 "could not resolve '$STACK_APP_NAME' to a uuid-shaped application id"
[[ "$MIGRATOR_UUID" =~ $UUID_RE ]] || die2 "could not resolve '$MIGRATOR_APP_NAME' to a uuid-shaped application id"
ok "stack: $STACK_APP_NAME -> $STACK_UUID; migrator: $MIGRATOR_APP_NAME -> $MIGRATOR_UUID"

psql_admin() {
  # psql_admin <sql> -- runs one statement/script as supabase_admin inside the db service, -tAc form for scalar reads.
  sshx "env STACK_UUID=\"$STACK_UUID\" bash -s" <<REMOTE
set -e
docker compose --project-name "\$STACK_UUID" exec -T db psql -U supabase_admin -d postgres -tAc "$1"
REMOTE
}

step "Preflight: migrator credential state (query per archive §6.3 -- the branch-gate, not a guess)"
MIGRATOR_STATE="$(psql_admin "select r.rolcanlogin::text || '|' || (a.rolpassword is not null)::text from pg_catalog.pg_roles r join pg_catalog.pg_authid a on a.rolname = r.rolname where r.rolname = 'migrator';" | tr -d ' \n')"
info "migrator rolcanlogin|password_set = '${MIGRATOR_STATE:-<role absent>}'"

step "Preflight: bootstrap_complete (a row exists for migration 118 -- never a bare row count)"
BOOTSTRAP_COMPLETE="$(psql_admin "select exists(select 1 from supabase_migrations.schema_migrations where version = '118')::text;" 2>/dev/null | tr -d ' \n' || echo 'f')"
info "bootstrap_complete = ${BOOTSTRAP_COMPLETE:-f}"

if [[ "$BOOTSTRAP_COMPLETE" == "t" ]]; then
  step "Already bootstrapped -- verifying the ownership census before reporting VERIFIED"
  CENSUS_BAD="$(psql_admin "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'pfin' and pg_get_userbyid(c.relowner) not in ('pfin_owner');" | tr -d ' \n')"
  [[ "$CENSUS_BAD" == "0" ]] || die "bootstrap_complete=t but the ownership census shows $CENSUS_BAD non-pfin_owner-owned pfin object(s) -- the pfin_owner sweep broke somewhere. Investigate by hand; this script does not auto-repair an ownership mismatch."
  ok "ownership census clean (zero non-pfin_owner-owned pfin objects) -- VERIFIED, nothing to do"
  exit 0
fi

if [[ "$MIGRATOR_STATE" == "t|t" ]]; then
  die "migrator already has LOGIN + a password set, but bootstrap_complete=f -- a PARTIAL bootstrap state (Phase 1's credential step ran, but migration 118 never landed). This script refuses to guess whether Phase 2 needs a re-run or something else broke; investigate by hand (see docs/archive/deployment-runbook-rationale-2026-09-20.md §6.3's own recovery guidance) before re-running."
fi

if [[ "$APPLY" -eq 0 ]]; then
  step "Done (preflight)"
  info "fresh box for this bootstrap -- re-run with --apply to run Phase 1 -> 2 -> 3."
  exit 0
fi

# psql_admin_file <local-sql-file> -- pipes a LOCAL (this repo checkout's
# own, never the box's) SQL file's content over the SSH connection's own
# stdin into `docker compose exec -T db psql`. Deliberately NOT wrapped
# in an intermediate `bash -s` remote script (every other helper in this
# file is) -- `bash -s` itself needs the SSH stdin channel to receive ITS
# OWN script body, which would collide with using that same channel to
# carry the SQL file's content to the psql process bash -s eventually
# spawns. Passing the remote command as a plain ssh argument instead
# means ssh's own stdin (the local file, via `<`) forwards directly to
# THAT command's stdin, no intermediate consumer in the way. STACK_UUID
# is interpolated directly (safe: validated against UUID_RE above, never
# operator/API-controlled free text). The `db` service container is bare
# Supabase Postgres -- it does NOT have this repo's supabase/ tree
# mounted, so the file's content must cross the wire; it is never
# written to the box's own filesystem.
psql_admin_file() {
  sshx "docker compose --project-name $STACK_UUID exec -T db psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres" < "$1"
}

step "Phase 1 (pre-step, supabase_admin): roles.sql"
psql_admin_file "$REPO_ROOT/supabase/roles.sql" || die "supabase/roles.sql failed"
ok "roles.sql applied"

step "Phase 1: auth-grants.sql"
psql_admin_file "$REPO_ROOT/supabase/auth-grants.sql" || die "supabase/auth-grants.sql failed"
ok "auth-grants.sql applied"

step "Phase 1: engine-backstop REVOKEs (schema pfin already created by roles.sql's own guarded DO block -- never repeat CREATE SCHEMA here, the archive's own 2026-09-17 correction)"
sshx "env STACK_UUID=\"$STACK_UUID\" bash -s" <<'REMOTE'
set -e
docker compose --project-name "$STACK_UUID" exec -T db psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres <<'SQL'
revoke create on schema pfin from migrator;
revoke create on schema pfin from public;
SQL
REMOTE
ok "engine-backstop REVOKEs applied"

step "Phase 1: migrator credential handoff -- legs A-E, same shape as scripts/db-role-handoff.sh's own (generate locally, deliver as a 0600 seed, never argv, never an env dump; see this script's own header for what each leg proves and why leg D is Sec-mandatory)"
PW="$(openssl rand -hex 32)"
[[ ${#PW} -eq 64 ]] || die "generated credential is ${#PW} chars, expected 64 -- refusing to proceed with a malformed value."
SEED_FILE="/root/.pfin/_dbbootstrap_migrator_seed.$$.env"
printf '%s' "$PW" | sshx "umask 077; mkdir -p /root/.pfin; cat > $SEED_FILE"
unset PW
sshx "env STACK_UUID=\"$STACK_UUID\" MIGRATOR_UUID=\"$MIGRATOR_UUID\" SEED_FILE=\"$SEED_FILE\" bash -s" <<'REMOTE'
set -e
umask 077
trap 'shred -u "$SEED_FILE" 2>/dev/null || rm -f "$SEED_FILE"' EXIT
PW="$(cat "$SEED_FILE")"
[ -n "$PW" ] || { echo "FATAL: seed file read as empty -- refusing to proceed." >&2; exit 1; }
[ "${#PW}" -eq 64 ] || { echo "FATAL: seed file credential is ${#PW} chars, expected 64." >&2; exit 1; }

echo "== A. \\password migrator + ALTER ROLE ... LOGIN =="
PSQL_SCRIPT="$(printf '\\password migrator\n%s\n%s\nALTER ROLE migrator LOGIN;\n' "$PW" "$PW")"
# set +e / set -e bracket the assignment deliberately -- under the
# outer `set -e`, a plain `OUT="$(cmd)"` where cmd exits non-zero kills
# this remote script AT THE ASSIGNMENT, before RC=$? is ever reached, so
# the FATAL diagnostic below would be dead code and the operator would
# see a bare, unexplained exit 1 with $OUT (the actual psql error text)
# never printed. Same bracket as scripts/db-role-handoff.sh's own
# identical mechanism (missing here in an earlier draft of this file --
# caught while building this script's own strike-proof fence, never
# exercised against a live box).
# Sec F-1 (PR #849 review) -- -v ON_ERROR_STOP=1 added: without it, an
# `ALTER ROLE migrator LOGIN` failure (any reason) left psql exit 0, and
# nothing downstream distinguished that from success -- a false VERIFIED.
set +e
OUT="$(docker compose --project-name "$STACK_UUID" exec -T db psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres <<< "$PSQL_SCRIPT" 2>&1)"
RC=$?
set -e
if [ $RC -ne 0 ]; then echo "FATAL: psql handoff script exited $RC: $OUT" >&2; exit 1; fi
if printf '%s' "$OUT" | grep -qi "didn't match"; then echo "FATAL: password confirmation mismatch inside \\password." >&2; exit 1; fi
if printf '%s' "$OUT" | grep -qF "$PW"; then echo "FATAL: the credential's cleartext value appeared in psql's own captured output." >&2; exit 1; fi
echo "OK: migrator credential handoff completed (exit 0, no mismatch, no cleartext echo)."

echo "== B. Catalog verify (rolcanlogin + pg_authid.rolpassword IS NOT NULL, re-read fresh) =="
VERIFY="$(docker compose --project-name "$STACK_UUID" exec -T db psql -U supabase_admin -d postgres -tAc \
  "select rolcanlogin::text || '|' || (select (rolpassword is not null)::text from pg_authid where rolname='migrator') from pg_roles where rolname='migrator';")"
VERIFY_TRIMMED="$(printf '%s' "$VERIFY" | tr -d ' \n')"
if [ "$VERIFY_TRIMMED" != "t|t" ]; then
  echo "FATAL: post-handoff catalog verify expected 't|t' (rolcanlogin|has_password), got '$VERIFY_TRIMMED'." >&2
  exit 1
fi
echo "OK: catalog confirms rolcanlogin=t and a password is set."

echo "== C. Connect AS migrator over a non-loopback path with the generated credential (-h db, never -h localhost -- see db-role-handoff.sh's own header for the container-internal trust-path hazard this avoids; UNMEASURED on the production target, same bound as that script states) =="
set +e
CONNECT_OUT="$(docker compose --project-name "$STACK_UUID" exec -T db psql -v ON_ERROR_STOP=1 -h db -p 5432 -U migrator -d postgres <<< "$(printf '%s\nselect current_user;\n' "$PW")" 2>&1)"
CONNECT_RC=$?
set -e
if ! printf '%s' "$CONNECT_OUT" | grep -qF "Password for user"; then
  echo "FATAL: no password prompt was observed connecting AS migrator -- this means the connection took a NON-password-authenticated path (e.g. a trust rule), which is the exact hazard this step exists to detect. Refusing regardless of exit code." >&2
  exit 1
fi
if printf '%s' "$CONNECT_OUT" | grep -qF "$PW"; then
  echo "FATAL: the credential's cleartext value appeared in the connect-as-migrator step's own captured output -- refusing to proceed or print it." >&2
  exit 1
fi
if [ $CONNECT_RC -ne 0 ]; then
  echo "FATAL: could not connect AS migrator with the generated credential (exit $CONNECT_RC) -- the handoff did not take effect end to end." >&2
  exit 1
fi
if ! printf '%s' "$CONNECT_OUT" | grep -qF "migrator"; then
  echo "FATAL: connected but current_user did not echo back 'migrator'." >&2
  exit 1
fi
echo "OK: connected AS migrator over a non-loopback, password-prompted path with the generated credential; current_user confirmed."

echo "== D. Pushing the SAME credential onto pfin-migrator's env store as MIGRATOR_DB_PASSWORD (Sec VETO-1, PR #849 review -- see this script's own header) =="
TOKEN="$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "$TOKEN" "$MIGRATOR_UUID" "$SEED_FILE" <<'PYEOF'
import json, subprocess, sys, tempfile, os

token, resource_uuid, seed_file = sys.argv[1], sys.argv[2], sys.argv[3]

def die(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)

def api(method, path, body=None):
    if '"' in token or "\n" in token:
        die("Coolify API token contains an unexpected character -- refusing")
    config = 'header = "Authorization: Bearer ' + token + '"\n'
    tmppath = None
    cmd = ["curl", "-sS", "-K", "-", "-X", method, "-w", "\n%{http_code}"]
    if body is not None:
        fd, tmppath = tempfile.mkstemp(prefix="pfin-dbbootstrap-body-")
        os.write(fd, body.encode())
        os.close(fd)
        cmd += ["-H", "Content-Type: application/json", "--data-binary", f"@{tmppath}"]
    cmd += [f"http://localhost:8000/api/v1{path}"]
    try:
        result = subprocess.run(cmd, input=config.encode(), capture_output=True)
    finally:
        if tmppath:
            os.unlink(tmppath)
    if result.returncode != 0:
        die(f"Coolify API {method} {path} failed: curl exit {result.returncode} ({result.stderr.decode(errors='replace').strip()[:200]})")
    raw = result.stdout.decode()
    out, _, code = raw.rpartition("\n")
    if not code.isdigit():
        die("could not parse an HTTP status code off curl's own -w output")
    status = int(code)
    if not (200 <= status < 300):
        die(f"Coolify API {method} {path} -> HTTP {status}: {out.strip()[:500]}")
    return json.loads(out) if out.strip() else None

# Same shape as db-role-handoff.sh's own leg D -- the value is read from
# the seed file's PATH (a non-secret argument), never from this process's
# own argv.
with open(seed_file) as f:
    pw = f.read()
if len(pw) != 64:
    die(f"seed file credential is {len(pw)} chars, expected 64 -- refusing to push a malformed value")

api("PATCH", f"/applications/{resource_uuid}/envs/bulk", json.dumps({"data": [
    {"key": "MIGRATOR_DB_PASSWORD", "value": pw},
]}))
print("PATCHED MIGRATOR_DB_PASSWORD onto pfin-migrator (value never printed).")
PYEOF

echo "== E. Hash-bound readback -- production row only, exactly one match, bound to the ACTUAL generated credential (never the value itself) =="
EXPECTED_HASH="$(printf '%s' "$PW" | sha256sum | cut -c1-16)"
READBACK_OUT="$(docker exec coolify php artisan tinker --execute="
\$app = \App\Models\Application::where('uuid','$MIGRATOR_UUID')->firstOrFail();
\$rows = \$app->environment_variables()->where('key', 'MIGRATOR_DB_PASSWORD')->where('is_preview', false)->get();
if (\$rows->count() !== 1) { echo \$rows->count(); } else { echo '1|' . substr(hash('sha256', (string) \$rows->first()->value), 0, 16); }
" 2>/dev/null | tail -1 | tr -d ' \n')"
READBACK_COUNT="${READBACK_OUT%%|*}"
READBACK_HASH="${READBACK_OUT#*|}"
if [ "$READBACK_COUNT" != "1" ]; then
  echo "FATAL: MIGRATOR_DB_PASSWORD (is_preview=false) readback found $READBACK_COUNT matching row(s) on pfin-migrator, expected exactly 1 -- refusing to trust the store." >&2
  exit 1
fi
if [ "$READBACK_HASH" != "$EXPECTED_HASH" ]; then
  echo "FATAL: MIGRATOR_DB_PASSWORD is present (one production row) but its truncated hash does not match the credential this run generated -- the store holds a DIFFERENT value than what was pushed. Refusing. (Hash only -- neither value is ever read back or printed.)" >&2
  exit 1
fi
echo "OK: MIGRATOR_DB_PASSWORD present on pfin-migrator (production row, exactly one match), hash-bound to the generated credential confirmed (value never printed)."
REMOTE
ok "migrator: LOGIN + password set; MIGRATOR_DB_PASSWORD pushed to pfin-migrator and hash-verified"

step "Phase 1: role-comment files (055/116/117/118/119, run directly -- idempotent, each file's own guard degrades to a WARNING on a pre-existing role, never a silent skip)"
for f in 055_pfin_etl_role 116_pfin_provider_sync_role 117_pfin_etl_role_comment_c1_reattribution 118_migrator_role 119_migrator_role_comment_amendment3_recitation; do
  MIGFILE="$REPO_ROOT/supabase/migrations/${f}.sql"
  if [[ ! -f "$MIGFILE" ]]; then
    info "$f.sql not present in supabase/migrations/ -- skipping (matches the archive's own note: 119 rows only once PR #775's file is merged into the tree)."
    continue
  fi
  psql_admin_file "$MIGFILE" || die "supabase/migrations/${f}.sql failed"
  ok "$f.sql applied"
done

step "Phase 2 (main pass, migrator container): supabase db push --yes --db-url \"\$PROD_DB_URL\" --workdir /workspace"
sshx "env MIGRATOR_UUID=\"$MIGRATOR_UUID\" bash -s" <<'REMOTE'
set -e
# set +e / set -e bracket this assignment deliberately -- see the
# identical comment on the Phase 1 credential-handoff step above; a bare
# `OUT="$(cmd)"` under `set -e` would kill this script at the assignment
# on a genuine push failure, before RC=$? and echo "$OUT" (the actual
# supabase/docker error text) are ever reached.
set +e
OUT="$(docker compose --project-name "$MIGRATOR_UUID" exec -T migrator sh -c 'supabase db push --yes --db-url "$PROD_DB_URL" --workdir /workspace' 2>&1)"
RC=$?
set -e
echo "$OUT"
if [ $RC -ne 0 ]; then echo "FATAL: supabase db push exited $RC" >&2; exit 1; fi
if ! printf '%s' "$OUT" | grep -qF "Finished supabase db push"; then
  echo "FATAL: exit 0 but the CLI's own completion line ('Finished supabase db push') is absent -- treating this as an incomplete run, not a pass." >&2
  exit 1
fi
REMOTE
ok "migration sweep applied"

step "Phase 2 verify: ownership census + bootstrap_complete (never a bare ledger row count -- the archive's own stated trap)"
CENSUS_BAD="$(psql_admin "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'pfin' and pg_get_userbyid(c.relowner) not in ('pfin_owner');" | tr -d ' \n')"
[[ "$CENSUS_BAD" == "0" ]] || die "ownership census shows $CENSUS_BAD non-pfin_owner-owned pfin object(s) after Phase 2 -- the pair broke somewhere in the apply. Do NOT proceed to Phase 3/§7; do not paper over it with a manual ALTER ... OWNER TO."
ok "ownership census clean"
BOOTSTRAP_COMPLETE="$(psql_admin "select exists(select 1 from supabase_migrations.schema_migrations where version = '118')::text;" | tr -d ' \n')"
[[ "$BOOTSTRAP_COMPLETE" == "t" ]] || die "bootstrap_complete=f after Phase 2 (no ledger row for migration 118) -- the apply did not actually land 118. Investigate before Phase 3."
ok "bootstrap_complete = t"

step "Phase 3 (post-step, supabase_admin): post-step-vault-view.sql -- creates pfin.decrypted_source_credential, transfers to pfin_owner, asserts exactly one decrypt view (its own assertion IS the pass/fail signal, not re-implemented here)"
psql_admin_file "$REPO_ROOT/supabase/post-step-vault-view.sql" || die "supabase/post-step-vault-view.sql failed (its own assertion block is the failure signal -- see the output above for which leg)"
ok "post-step-vault-view.sql applied and self-asserted"

step "Done"
info "Phase 1 -> 2 -> 3 complete: bootstrap_complete=t, ownership census clean, decrypt view asserted by its own file. §6.1/§6.2 worker-role handoffs (scripts/db-role-handoff.sh) are the next step, unchanged."
exit 0
