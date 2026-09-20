#!/usr/bin/env bash
#
# db-role-handoff.sh — scripts the §6.1/§6.2 deploy-time DB-role credential
# handoff (docs/deployment-runbook.md §6.1 `pfin_etl` / §6.2
# `pfin_provider_sync`; migrations 055/116, canonical if this runbook text
# ever disagrees) — the two-statement `\password <role>` THEN
# `ALTER ROLE <role> LOGIN;` sequence, plus pushing the SAME generated
# credential onto the worker's own Coolify resource as `PFIN_DB_PASSWORD`.
# DevOps-owned. BACKLOG.md §7.36 item 68, W-2. Sec joint-review mandatory
# (secrets + DB roles).
#
# WHY THE TWO STATEMENTS, IN THIS ORDER (mirrors §6.1/§6.2 exactly — see
# their own headers for the full derivation; not re-derived here):
#   `\password <role>` sets ONLY the password while the role is still
#   NOLOGIN (inert); `ALTER ROLE <role> LOGIN` then flips onto an
#   ALREADY-credentialed role. LOGIN-with-no-password never exists at any
#   instant. The single-statement `ALTER ROLE … WITH LOGIN PASSWORD '…'`
#   form is PROHIBITED — wherever statement logging is on, it writes the
#   credential to the server log in cleartext; `\password` computes the
#   SCRAM verifier CLIENT-SIDE and only the verifier (not the plaintext)
#   ever becomes logged statement text.
#
# MECHANISM CHOICE — `\password` DRIVEN VIA PIPED STDIN, not a hand-rolled
# SCRAM hash. Verified locally (throwaway `initdb` instance, this PR):
# `psql <<EOF\n\password <role>\n<pw>\n<pw>\nEOF` — with stdin NOT a tty —
# actually sets the password (confirmed: subsequent login with that exact
# value succeeds) and the statement `log_statement=all` then captures is
# `ALTER USER <role> PASSWORD 'SCRAM-SHA-256$...'` — the verifier, never
# the cleartext (grepped the log for the plaintext value: zero hits).
# `simple_prompt()` (what `\password` calls) only disables terminal ECHO
# when stdin IS a tty; on a pipe there is no tty to echo on, so it just
# reads a line — this is not a special "non-interactive mode," it is the
# same code path `\password` always uses, exercised over a redirect
# instead of a keyboard. This is `psql`'s OWN tested, ratified mechanism —
# reusing it is strictly less risk than re-implementing RFC 5802
# SCRAM-SHA-256 verifier generation by hand to feed `ALTER ROLE … PASSWORD
# '<hash>'` (the brief's named alternative). If Sec prefers the hand-rolled
# form, say so — happy to redo it, but the piped-stdin form is what's
# built here, exactly matching §6.1/§6.2's own prescribed two statements
# verbatim, not a materially different substitute.
#
# CONNECTING IDENTITY — `supabase_admin`, NOT `postgres`. §6.1/§6.2's own
# text says run as `postgres` (which the runbook's §6.0 confirms holds
# CREATEROLE, sufficient for `\password`/`ALTER ROLE`). This script instead
# connects as `supabase_admin` (the box's TRUE superuser, per §6.0)
# throughout, because the brief's own preflight ask — confirm "no password
# set" via `pg_authid` — needs it: verified locally, a non-superuser
# CREATEROLE role gets `permission denied for table pg_authid`, while
# `pg_roles.rolpassword` is the constant `'********'` for every role
# regardless of state (the runbook's own documented reason not to use it —
# "always true and proves nothing"). `supabase_admin` is a strict
# superset of what `postgres` can do here (superuser implies CREATEROLE),
# so using it does not weaken anything §6.1/§6.2 require — it only adds
# the read access this script's own preflight check needs. Flagged as a
# judgment call, not silently assumed: if Sec wants this run as `postgres`
# instead (dropping the pre-state password-set check to what `rolcanlogin`
# alone can prove), say so in review.
#
# WHAT NEVER CROSSES ARGV OR ENV DUMP
#   - The generated credential: `openssl rand -hex 32` LOCALLY, delivered
#     to the box as a 0600 seed file over SSH STDIN (same shape as
#     provision-supabase-stack.sh's own SMTP_SEED_FILE — piped, never a
#     command-line arg on either side, never heredoc-embedded literal
#     text), read back ON THE BOX by PATH only. A single `trap ... EXIT`
#     registered at the top of the one remote script that uses it shreds
#     the file on ANY exit — success, a `set -e` abort, or a signal.
#   - The psql `\password` script (role name + the two password lines +
#     the LOGIN statement): built into a bash VARIABLE on the box and fed
#     to `docker compose exec -T db psql` via a HERE-STRING (`<<<`), never
#     `-c '<sql>'` (would be argv), never a second on-disk file. A
#     here-string is a pipe/small-tmpfile libc hands the child process as
#     its stdin — it never appears in that child's own argv or in `ps`.
#   - The connect-AS-the-role verification: psql's OWN connection-time
#     password prompt, ALSO driven via piped stdin (verified locally, same
#     mechanism as `\password` — no tty, no echo, just a line read) — NOT
#     `PGPASSWORD=` (which would be either an argv element or an
#     environment variable visible via `/proc/<pid>/environ`, a materially
#     worse exposure class for a live production DB credential than for
#     the API token this repo already accepts that residual for at item
#     60 — deliberately not extended here).
#   - The Coolify API token: `curl -K -` (stdin config directive), same
#     shape as every other provision-*.sh / push-production-secrets.sh /
#     coolify-env.sh in this repo.
#   - The PATCH body carrying `PFIN_DB_PASSWORD`'s new value: a 0600
#     tempfile under /root/.pfin/, `--data-binary @<path>`, unlinked in a
#     `finally` immediately after the call — same shape provision-app.sh /
#     provision-worker.sh already use for their own (non-secret) env-var
#     PATCH bodies, extended here to a secret body.
#   - The readback: Coolify's public `GET .../envs` never returns a
#     secret's real VALUE (confirmed by mint-supabase-jwt-keys.sh's own
#     header — "v1 /envs listing never carries a value field" for a
#     genuinely secret entry). Readback here uses the SAME on-box Eloquent
#     `tinker --execute` decrypt-and-measure-LENGTH-ONLY pattern
#     provision-supabase-stack.sh's own assert-non-empty step and
#     mint-supabase-jwt-keys.sh's own JWT-shape check both already use —
#     the printed length (an integer, e.g. "64") is not a secret; the
#     VALUE is never echoed by this script at any point, locally or on
#     the box.
#
# NOT REUSING push-production-secrets.sh's push helper (brief item (3)) —
# stated, not silently decided: that script's OWN header excludes
# PFIN_DB_PASSWORD by name (`EXCLUDED_DEFERRED` — "§6.1/§6.2's role
# handoff, never this script"), and its value-provenance model is
# "operator's local .env is authoritative, unconditional overwrite" —
# structurally different from this script's "mint a fresh value THIS RUN,
# tie its lifecycle to the DB-side handoff succeeding first" model. This
# repo's own stated convention (provision-app.sh's header: "provision-vps.sh
# / provision-supabase-stack.sh / provision-migrator-app.sh don't share
# code with each other either") is to copy the proven SHAPE (the `curl -K
# -` / tempfile-body `api()` helper), not to extract a shared library —
# followed here, not duplicated verbatim from any one sibling.
#
# IDEMPOTENCY
#   Preflight always reads live role state (`pg_roles.rolcanlogin` +
#   `pg_authid.rolpassword IS NOT NULL`) before doing anything else, in
#   BOTH preflight-only and --apply runs. A role that already has LOGIN
#   AND a password set refuses UNLESS `--rotate` is passed — this script
#   must never silently re-run an initial handoff over a live credential.
#   `--rotate` skips the `ALTER ROLE … LOGIN` statement (already set) and
#   refuses if the role is NOT already LOGIN (that is an initial handoff,
#   not a rotation — omit `--rotate`).
#
# WHAT THIS SCRIPT DOES NOT DO
#   Redeploy/restart the worker's Coolify container. Per §6.1/§6.2: "+
#   restart the ETL container ONLY" / "+ restart the provider-sync
#   container ONLY" — no coordinated PostgREST redeploy for either role
#   (the whole point of the dedicated-role design). Coolify only injects
#   an env-store change into a container at deploy/recreate time (same
#   caveat mint-supabase-jwt-keys.sh's own header states) — this script
#   prints that reminder but does not trigger the restart itself, so a
#   redeploy decision stays a deliberate, separate operator step (W-3).
#
# USAGE
#   BOX_IP=<box-ip> scripts/db-role-handoff.sh <pfin_etl|pfin_provider_sync>            # preflight
#   BOX_IP=<box-ip> scripts/db-role-handoff.sh <pfin_etl|pfin_provider_sync> --apply     # initial handoff
#   BOX_IP=<box-ip> scripts/db-role-handoff.sh <pfin_etl|pfin_provider_sync> --apply --rotate
#                                                                             # rotate an existing credential
#
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

ROLE="${1:-}"
if [[ $# -ge 1 ]]; then shift; fi
APPLY=0
ROTATE=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --rotate) ROTATE=1 ;;
    *) echo "unknown flag: $arg" >&2; echo "usage: $0 <pfin_etl|pfin_provider_sync> [--apply] [--rotate]" >&2; exit 2 ;;
  esac
done

# --- Table: role -> its own Coolify resource name --------------------------
# Same F/CTO-ruled names push-production-secrets.sh's RESOURCE_IDENTITY_MAP
# and provision-worker.sh's table already use.
case "$ROLE" in
  pfin_etl)
    RESOURCE_NAME="pfin-back-etl"
    ;;
  pfin_provider_sync)
    RESOURCE_NAME="pfin-provider-sync"
    ;;
  "")
    echo "FATAL: missing <role> argument." >&2
    echo "usage: $0 <pfin_etl|pfin_provider_sync> [--apply] [--rotate]" >&2
    exit 2
    ;;
  *)
    echo "FATAL: unrecognised role '$ROLE' -- refusing." >&2
    echo "  <role> is one of: pfin_etl, pfin_provider_sync" >&2
    exit 2
    ;;
esac

BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
PROJECT_NAME="${PROJECT_NAME:-pfin-supabase}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-production}"
SUPABASE_STACK_APP_NAME="${SUPABASE_STACK_APP_NAME:-pfin-supabase-stack}"

UUID_RE='^[a-z0-9]{20,32}$'

APPLY_ROTATE_INCOMPATIBLE=0
if [[ $ROTATE -eq 1 && $APPLY -eq 0 ]]; then
  APPLY_ROTATE_INCOMPATIBLE=1
fi

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

if [[ $APPLY_ROTATE_INCOMPATIBLE -eq 1 ]]; then
  die "--rotate has no effect without --apply -- this is preflight-only either way; pass --apply --rotate together, or drop --rotate for a plain preflight read."
fi

[[ -n "$BOX_IP" ]] || die "BOX_IP is required, not defaulted -- set it explicitly (same discipline as every other scripts/provision-*.sh / scripts/db-role-handoff.sh)."

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }

sshx true >/dev/null 2>&1 || die "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

# Same api()/jqp() shape as scripts/provision-worker.sh (token on `curl -K
# -`, request body via a 0600 tempfile unlinked in `finally`, HTTP status
# parsed off curl's own `-w '\n%{http_code}'` trailer so a non-2xx body is
# actually visible instead of a generic curl exit code).
read -r -d '' PY_API_HELPER <<'PY' || true
import json, sys, subprocess, tempfile, os

def die(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)

def api(token, method, path, body=None):
    if '"' in token or "\n" in token:
        die("Coolify API token contains an unexpected character -- refusing to build a curl config for it")
    config = 'header = "Authorization: Bearer ' + token + '"\n'
    tmppath = None
    cmd = ["curl", "-sS", "-K", "-", "-X", method, "-w", "\n%{http_code}"]
    if body is not None:
        fd, tmppath = tempfile.mkstemp(prefix="pfin-dbrole-body-")
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
        die(f"Coolify API {method} {path}: could not parse an HTTP status code off curl's own -w output -- refusing to guess success or failure. Raw tail: {raw[-200:]!r}")
    status = int(code)
    if not (200 <= status < 300):
        die(f"Coolify API {method} {path} -> HTTP {status}: {out.strip()[:500]}")
    return json.loads(out) if out.strip() else None
PY

api() {
  local method="$1" path="$2" body="${3:-}"
  local env_assign="method=$(printf '%q' "$method") path=$(printf '%q' "$path") body=$(printf '%q' "$body")"
  sshx "env $env_assign bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "\$method" "\$path" "\$body" <<'PYEOF'
$PY_API_HELPER
import sys
token, method, path = sys.argv[1], sys.argv[2], sys.argv[3]
body = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else None
result = api(token, method, path, body)
print(json.dumps(result) if result is not None else '')
PYEOF
REMOTE
}
jqp() {
  local input
  input="$(cat)"
  [[ -n "$input" ]] || exit 1
  printf '%s' "$input" | python3 -c "import json,sys;$1"
}

step "Resolving the Supabase-stack application ('$SUPABASE_STACK_APP_NAME')"
STACK_APP_JSON="$(api GET /applications | jqp "
d=json.load(sys.stdin)
m=[a for a in d if a['name']=='$SUPABASE_STACK_APP_NAME']
if len(m) > 1:
    raise SystemExit('FATAL: %d applications named %r (%r) -- refusing to pick one.' % (len(m), '$SUPABASE_STACK_APP_NAME', [x['uuid'] for x in m]))
print(json.dumps(m[0]) if m else '')")"
[[ -n "$STACK_APP_JSON" ]] || die "no application named '$SUPABASE_STACK_APP_NAME' -- run scripts/provision-supabase-stack.sh --apply first."
STACK_UUID="$(echo "$STACK_APP_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
[[ "$STACK_UUID" =~ $UUID_RE ]] || die "resolved stack application uuid '$STACK_UUID' does not match the expected uuid shape -- refusing to use it in a remote command."
ok "Supabase-stack application exists — $STACK_UUID"

step "Resolving target Coolify resource '$RESOURCE_NAME' — REQUIRED, refusing if absent"
RESOURCE_JSON="$(api GET /applications | jqp "
d=json.load(sys.stdin)
m=[a for a in d if a['name']=='$RESOURCE_NAME']
if len(m) > 1:
    raise SystemExit('FATAL: %d applications named %r (%r) -- refusing to pick one.' % (len(m), '$RESOURCE_NAME', [x['uuid'] for x in m]))
print(json.dumps(m[0]) if m else '')")"
[[ -n "$RESOURCE_JSON" ]] || die "no Coolify application named '$RESOURCE_NAME' -- this is a REQUIRED precondition, not skippable: run scripts/provision-worker.sh $RESOURCE_NAME --apply first (docs/deployment-runbook.md §7.2 step (i))."
RESOURCE_UUID="$(echo "$RESOURCE_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
[[ "$RESOURCE_UUID" =~ $UUID_RE ]] || die "resolved resource uuid '$RESOURCE_UUID' does not match the expected uuid shape -- refusing to use it in a remote command."
ok "'$RESOURCE_NAME' exists — $RESOURCE_UUID"

step "Preflight — live role state (read-only; pg_roles + pg_authid, via 'supabase_admin')"
# supabase_admin is the box's TRUE superuser (docs/deployment-runbook.md
# §6.0) -- needed to read pg_authid.rolpassword at all (measured locally:
# a CREATEROLE-only, non-superuser role gets "permission denied for table
# pg_authid"; pg_roles.rolpassword is the constant '********' regardless
# of state, per §6.1's own documented reason not to use it). See this
# script's own header for the full judgment-call statement.
ROLE_STATE="$(sshx "env STACK_UUID=\"$STACK_UUID\" ROLE=\"$ROLE\" bash -s" <<'REMOTE'
set -e
docker compose --project-name "$STACK_UUID" exec -T db psql -U supabase_admin -d postgres -tAc \
  "select coalesce((select rolcanlogin::text from pg_roles where rolname='$ROLE'), 'ABSENT'), coalesce((select (rolpassword is not null)::text from pg_authid where rolname='$ROLE'), 'ABSENT');"
REMOTE
)"
ROLE_EXISTS_FIELD="$(echo "$ROLE_STATE" | cut -d'|' -f1)"
HAS_PASSWORD_FIELD="$(echo "$ROLE_STATE" | cut -d'|' -f2)"
info "raw state: rolcanlogin=$ROLE_EXISTS_FIELD has_password=$HAS_PASSWORD_FIELD"

[[ "$ROLE_EXISTS_FIELD" != "ABSENT" ]] || die "role '$ROLE' does not exist in pg_roles -- the migration that creates it (055 for pfin_etl, 116 for pfin_provider_sync) has not been applied yet. Run supabase migrations first."

ROLCANLOGIN="$ROLE_EXISTS_FIELD"
HAS_PASSWORD="$HAS_PASSWORD_FIELD"

if [[ $ROTATE -eq 1 ]]; then
  [[ "$ROLCANLOGIN" == "t" ]] || die "role '$ROLE' is not yet LOGIN -- this is an INITIAL handoff, not a rotation. Omit --rotate."
else
  if [[ "$ROLCANLOGIN" == "t" && "$HAS_PASSWORD" == "t" ]]; then
    die "role '$ROLE' already has LOGIN and a password set -- refusing to silently re-run the initial handoff over a live credential. Pass --apply --rotate if you intend to rotate it."
  fi
fi

step "Plan"
cat <<PLAN
      role            $ROLE
      target resource $RESOURCE_NAME  ($RESOURCE_UUID)
      mode            $([[ $ROTATE -eq 1 ]] && echo "ROTATE (role already LOGIN; \\password only, no LOGIN flip)" || echo "INITIAL HANDOFF (\\password then ALTER ROLE ... LOGIN)")
      current state   rolcanlogin=$ROLCANLOGIN has_password=$HAS_PASSWORD
PLAN

if [[ $APPLY -eq 0 ]]; then
  printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing generated, set, or pushed. Re-run with --apply to execute.\n'
  exit 0
fi

step "Generating the credential locally (openssl rand -hex 32)"
PW="$(openssl rand -hex 32)"
[[ ${#PW} -eq 64 ]] || die "generated credential is ${#PW} chars, expected 64 -- refusing to proceed with a malformed value."
ok "generated (64 hex chars; value never printed)"

step "Delivering the credential to the box as a 0600 seed (piped over SSH stdin, never argv, never an env dump)"
SEED_FILE="/root/.pfin/_dbrole_seed.${ROLE}.$$.env"
printf '%s' "$PW" | sshx "umask 077; mkdir -p /root/.pfin; cat > $SEED_FILE"
unset PW
ok "seed delivered to $SEED_FILE (0600, root-only) — local copy of the value discarded from this process's own variables"

step "Running the handoff + verification + Coolify push inside one remote session"
sshx "env STACK_UUID=\"$STACK_UUID\" ROLE=\"$ROLE\" ROTATE=\"$ROTATE\" RESOURCE_UUID=\"$RESOURCE_UUID\" SEED_FILE=\"$SEED_FILE\" bash -s" <<'REMOTE'
set -e
umask 077
# Registered FIRST, fires on ANY exit -- success, a set -e abort, or a
# signal. Same discipline as provision-supabase-stack.sh's own
# SMTP_SEED_FILE trap.
trap 'shred -u "$SEED_FILE" 2>/dev/null || rm -f "$SEED_FILE"' EXIT

PW="$(cat "$SEED_FILE")"
[ -n "$PW" ] || { echo "FATAL: seed file read as empty -- refusing to proceed." >&2; exit 1; }
[ "${#PW}" -eq 64 ] || { echo "FATAL: seed file credential is ${#PW} chars, expected 64 -- refusing to proceed with a malformed value." >&2; exit 1; }

step_r() { printf '\n== %s ==\n' "$1"; }

step_r "A. Two-statement handoff (\\password then ALTER ROLE ... LOGIN, unless --rotate)"
if [ "$ROTATE" = "1" ]; then
  PSQL_SCRIPT="$(printf '\\password %s\n%s\n%s\n' "$ROLE" "$PW" "$PW")"
else
  PSQL_SCRIPT="$(printf '\\password %s\n%s\n%s\nALTER ROLE %s LOGIN;\n' "$ROLE" "$PW" "$PW" "$ROLE")"
fi
set +e
OUT="$(docker compose --project-name "$STACK_UUID" exec -T db psql -U supabase_admin -d postgres <<< "$PSQL_SCRIPT" 2>&1)"
RC=$?
set -e
if [ $RC -ne 0 ]; then
  echo "FATAL: psql handoff script exited $RC" >&2
  exit 1
fi
if printf '%s' "$OUT" | grep -qi "didn't match"; then
  echo "FATAL: password confirmation mismatch inside \\password -- this should never happen (both lines are generated identically); the value was NOT set. Investigate the seed pipeline before retrying." >&2
  exit 1
fi
if printf '%s' "$OUT" | grep -qF "$PW"; then
  echo "FATAL: the credential's cleartext value appeared in psql's own captured output -- refusing to proceed or print it. Investigate before retrying (this should be structurally impossible: \\password's prompt-and-hash path never echoes the typed value)." >&2
  exit 1
fi
echo "OK: two-statement handoff script completed (exit 0, no mismatch, no cleartext echo)."

step_r "B. Catalog verify (rolcanlogin + pg_authid.rolpassword IS NOT NULL, as supabase_admin)"
VERIFY="$(docker compose --project-name "$STACK_UUID" exec -T db psql -U supabase_admin -d postgres -tAc \
  "select rolcanlogin::text || '|' || (select (rolpassword is not null)::text from pg_authid where rolname='$ROLE') from pg_roles where rolname='$ROLE';")"
VERIFY_TRIMMED="$(printf '%s' "$VERIFY" | tr -d ' \n')"
if [ "$VERIFY_TRIMMED" != "t|t" ]; then
  echo "FATAL: post-handoff catalog verify expected 't|t' (rolcanlogin|has_password), got '$VERIFY_TRIMMED'." >&2
  exit 1
fi
echo "OK: catalog confirms rolcanlogin=t and a password is set."

step_r "C. Connect AS $ROLE over TCP with the generated credential (forces password auth, not local trust)"
# -h localhost forces the TCP host-connection path -- the SAME pg_hba.conf
# rule class a remote docker-network peer (the actual worker container)
# needs, unlike the local Unix-socket connection supabase_admin used above.
# The password crosses via psql's OWN connection-time prompt, piped over
# stdin (verified locally this PR, same mechanism as \password's own
# prompt) -- never PGPASSWORD (env or argv).
set +e
CONNECT_OUT="$(docker compose --project-name "$STACK_UUID" exec -T db psql -h localhost -p 5432 -U "$ROLE" -d postgres <<< "$(printf '%s\nselect current_user;\n' "$PW")" 2>&1)"
CONNECT_RC=$?
set -e
if [ $CONNECT_RC -ne 0 ]; then
  echo "FATAL: could not connect AS $ROLE with the generated credential over TCP (exit $CONNECT_RC) -- the handoff did not take effect end to end." >&2
  exit 1
fi
if ! printf '%s' "$CONNECT_OUT" | grep -qF "$ROLE"; then
  echo "FATAL: connected but current_user did not echo back '$ROLE'." >&2
  exit 1
fi
echo "OK: connected AS $ROLE over TCP with the generated credential; current_user confirmed."

step_r "D. Pushing the SAME credential onto the target Coolify resource's env store as PFIN_DB_PASSWORD"
TOKEN="$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "$TOKEN" "$RESOURCE_UUID" "$SEED_FILE" <<'PYEOF'
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
        fd, tmppath = tempfile.mkstemp(prefix="pfin-dbrole-body-")
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

# Same shape as provision-supabase-stack.sh's own SMTP_SEED_FILE read --
# the value is read from the PATH (a non-secret argument), never from this
# process's own argv.
with open(seed_file) as f:
    pw = f.read()
if len(pw) != 64:
    die(f"seed file credential is {len(pw)} chars, expected 64 -- refusing to push a malformed value")

api("PATCH", f"/applications/{resource_uuid}/envs/bulk", json.dumps({"data": [
    {"key": "PFIN_DB_PASSWORD", "value": pw},
]}))
print("PATCHED PFIN_DB_PASSWORD onto the target resource (value never printed).")
PYEOF

step_r "E. Byte-exact readback — presence + length only, never the value"
# Coolify's public GET .../envs never returns a secret's real value (same
# fact mint-supabase-jwt-keys.sh's own header states) -- readback goes
# through the on-box Eloquent decrypt path, same as that script's own
# JWT-shape check, but asserting LENGTH ONLY here, never a shape/content
# check that would need to touch the value itself.
LEN_OUT="$(docker exec coolify php artisan tinker --execute="
\$app = \App\Models\Application::where('uuid','$RESOURCE_UUID')->firstOrFail();
\$env = \$app->environment_variables()->where('key', 'PFIN_DB_PASSWORD')->first();
echo \$env ? strlen((string) \$env->value) : 0;
" 2>/dev/null | tail -1 | tr -d ' \n')"
if [ "$LEN_OUT" != "64" ]; then
  echo "FATAL: PFIN_DB_PASSWORD readback length is '$LEN_OUT', expected 64 -- refusing to trust the store. (Length only -- the value itself is never read back or printed.)" >&2
  exit 1
fi
echo "OK: PFIN_DB_PASSWORD present on the target resource, length 64 confirmed (value never printed)."

step_r "Done (remote)"
echo "Seed file will be shredded now by this script's own EXIT trap."
REMOTE

step "Done"
info "Role '$ROLE' now has LOGIN + a generated credential; the SAME credential is set as PFIN_DB_PASSWORD on '$RESOURCE_NAME'."
info "⚠ A REDEPLOY/RESTART IS STILL REQUIRED — Coolify only injects an env-store change into a container at deploy/recreate time. Per docs/deployment-runbook.md §6.1/§6.2: restart ONLY '$RESOURCE_NAME' — no coordinated PostgREST redeploy, no other worker restart. This script does not trigger it (a deliberate, separate operator step)."
info "Record this resource's uuid with scripts/record-coolify-uuids.sh --apply if not already recorded."
