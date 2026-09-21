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
#     `-c '<sql>'` (would be argv), never a second on-disk file. Sec N-8
#     (PR #846 review; restored verbatim at N-11 after an earlier edit here
#     dropped Sec's own qualifier) -- precisely: a here-string is bash's
#     OWN construct, not libc's or the child's -- on bash before 5.1, bash
#     writes the expanded word to a temporary file and immediately unlinks
#     it (no directory entry survives) before dup2'ing the open fd onto the
#     child's stdin; bash 5.1+ uses a pipe outright for a here-string that
#     fits the pipe buffer. Neither form ever appears in that child's own
#     argv or in `ps`, and the pre-5.1 unlinked-tmpfile form additionally
#     closes the window where a sibling process could read it by path (a
#     pipe never had a path to read in the first place).
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
#   `pg_authid.rolpassword IS NOT NULL`) AND the worker resource's own
#   Coolify store state (does it already carry a production
#   `PFIN_DB_PASSWORD` row) before doing anything else, in BOTH
#   preflight-only and --apply runs. Three-way (team-lead follow-up, live
#   --dry-run, provision.sh sweep, 2026-09-20 -- the OLD version refused
#   unconditionally whenever LOGIN+password were both already set,
#   breaking provision.sh's own "re-run = no-op" contract on the very
#   next pass over an already-successfully-handed-off role, the same
#   class of defect provision-supabase-stack.sh's db-data-volume guard
#   had):
#     - ALL THREE false (NOLOGIN, no password, store empty) — genuinely
#       fresh, proceeds with the initial handoff.
#     - ALL THREE true (LOGIN, password set, store carries
#       PFIN_DB_PASSWORD) — already handed off, `VERIFIED`, exit 0,
#       no-op, even with `--apply` and without `--rotate`.
#       ⚠ EXISTENCE-ONLY (Sec F-1, PR #852 AMBER review, option (a)+(c) —
#       option (b), hash-binding this no-op path the way leg E binds a
#       FRESH push, was considered and rejected as not cheap: leg E's own
#       hash proof only works because that run's own plaintext $PW is
#       still in scope; on a LATER no-op run there is no live plaintext to
#       hash against (Postgres exposes no reversible form of its live
#       password), and a hash persisted box-side from a past run would
#       only prove the store is unchanged since we last pushed it, never
#       that Postgres's LIVE password still equals it — that would need an
#       actual authentication attempt, materially more machinery). This
#       branch does NOT re-verify the store's current value still matches
#       Postgres's actual live password — a stale value left over from a
#       half-completed `--rotate` (Postgres and the store fell out of
#       sync mid-run) reads true|true|t and is reported VERIFIED here exactly
#       the same as a genuinely consistent state. Printed loudly on every
#       no-op run (not just here); the repair for suspected drift is
#       `--apply --rotate`, which regenerates and re-pushes a coherent
#       value from scratch rather than trusting the existing one.
#     - Any OTHER combination — a genuine mismatch (e.g. LOGIN with no
#       store value, or a store value with the role still NOLOGIN) —
#       refuses, naming the specific state, same as before. This is a
#       Sec-reviewed CONTROL, not a loosening: the refusal remains for
#       every state that is not cleanly one of the two consistent ones.
#   `--rotate` is unaffected by the above (it has its own, unchanged gate
#   — the role must already be LOGIN, or `--rotate` refuses "not yet
#   LOGIN"): skips the `ALTER ROLE … LOGIN` statement (already set) and
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
# BOOLEAN-CAST PREDICATE BUG (found 2026-09-21 while building provision.sh's
# own adopt-by-rotation wrapper around this script's preflight -- same
# defect class as scripts/db-bootstrap.sh's own fix this same PR, reproduced
# locally against a throwaway initdb instance before shipping, not just
# reasoned about: `select <boolexpr>::text` prints the LITERAL WORDS
# "true"/"false", never the abbreviated "t"/"f" a bare boolean COLUMN's own
# psql rendering shows -- true of a raw column cast via `::text` exactly as
# much as a literal, confirmed by measurement, not assumed). THREE sites in
# this file compared a `::text`-cast read against literal "t"/"f"/"t|t" and
# so could NEVER match a real answer: the --rotate LOGIN gate (would refuse
# "not yet LOGIN" against an ALREADY-LOGIN role), the preflight fresh/
# already-handed-off classification (would misreport BOTH consistent states
# as INCONSISTENT), and the post-handoff catalog verify (would refuse EVERY
# successful --apply run, initial or rotate, with "expected 't|t'"). Fixed
# uniformly here to compare against "true"/"false"/"true|true" -- STORE_HAS_PW
# is unaffected (it is assigned "t"/"f" literally by this script's OWN case
# statement below, never read via ::text from psql, so its comparisons are
# correct as written).
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
# `</dev/null` (Sec VETO-1 / team-lead's tree-wide follow-up, PR #854) --
# this exec is the LAST line of its own heredoc today, so nothing
# currently gets drained by it, but that is a position-dependent
# accident, not a guarantee -- redirect defensively, unconditionally.
ROLE_STATE="$(sshx "env STACK_UUID=\"$STACK_UUID\" ROLE=\"$ROLE\" bash -s" <<'REMOTE'
set -e
docker compose --project-name "$STACK_UUID" exec -T db psql -U supabase_admin -d postgres -tAc \
  "select coalesce((select rolcanlogin::text from pg_roles where rolname='$ROLE'), 'ABSENT'), coalesce((select (rolpassword is not null)::text from pg_authid where rolname='$ROLE'), 'ABSENT');" </dev/null
REMOTE
)"
ROLE_EXISTS_FIELD="$(echo "$ROLE_STATE" | cut -d'|' -f1)"
HAS_PASSWORD_FIELD="$(echo "$ROLE_STATE" | cut -d'|' -f2)"
info "raw state: rolcanlogin=$ROLE_EXISTS_FIELD has_password=$HAS_PASSWORD_FIELD"

[[ "$ROLE_EXISTS_FIELD" != "ABSENT" ]] || die "role '$ROLE' does not exist in pg_roles -- the migration that creates it (055 for pfin_etl, 116 for pfin_provider_sync) has not been applied yet. Run supabase migrations first."

ROLCANLOGIN="$ROLE_EXISTS_FIELD"
HAS_PASSWORD="$HAS_PASSWORD_FIELD"

step "Preflight — Coolify store state (PFIN_DB_PASSWORD on '$RESOURCE_NAME')"
# team-lead follow-up (live --dry-run, provision.sh sweep, 2026-09-20):
# the OLD non-rotate refusal fired on ROLCANLOGIN+HAS_PASSWORD alone,
# BEFORE this script's own APPLY=0 preflight-exit gate below -- meaning
# a plain re-run of an ALREADY-SUCCESSFULLY-HANDED-OFF role (the normal,
# expected state on provision.sh's second pass, or a bare `--from
# etl-role`) refused instead of reporting VERIFIED, breaking provision.sh's
# own "re-run = no-op" contract the exact same way provision-supabase-
# stack.sh's db-data-volume guard did. Fix: a THIRD signal -- does the
# worker resource's OWN Coolify env store already carry a production
# PFIN_DB_PASSWORD row -- distinguishes "already fully handed off,
# nothing to do" from "genuinely fresh, proceed" from "a mismatched,
# partial state that needs a human, not a script, to resolve". Same
# on-box Eloquent tinker --execute count-only read this script's own
# leg E readback already uses (never a GET /envs call, which never
# returns a secret's real value) -- never the value, never a new
# mechanism.
STORE_READ="$(sshx "env RESOURCE_UUID=\"$RESOURCE_UUID\" bash -s" <<'REMOTE'
set -e
docker exec coolify php artisan tinker --execute="
/* probe:store-presence */
\$app = \App\Models\Application::where('uuid','$RESOURCE_UUID')->firstOrFail();
\$rows = \$app->environment_variables()->where('key', 'PFIN_DB_PASSWORD')->where('is_preview', false)->get();
\$count = \$rows->count();
\$nonEmpty = (\$count === 1 && (string) \$rows[0]->value !== '') ? '1' : '0';
echo \$count . '|' . \$nonEmpty;
" 2>/dev/null | tail -1 | tr -d ' \n'
REMOTE
)"
# Sec F-2 (PR #859 review) -- shape-guard the read BEFORE splitting it:
# without this, a truncated/malformed read with no '|' at all (e.g. a
# bare "1") has `${STORE_READ%%|*}` and `${STORE_READ#*|}` BOTH return
# the WHOLE string unchanged -- STORE_COUNT="1" AND STORE_NONEMPTY="1",
# silently reading a read that never reported non-emptiness as if it
# had. A truly empty read ("" -- the tinker call itself failed) already
# fails this regex too, refusing here rather than falling through to the
# case statement's own (still-kept) ambiguous-count catch-all below.
[[ "$STORE_READ" =~ ^[0-9]+\|[01]$ ]] || die "PFIN_DB_PASSWORD (is_preview=false) store-presence read on '$RESOURCE_NAME' returned unparseable output ('$STORE_READ') -- refusing to guess; expected '<count>|<0|1>'."
STORE_COUNT="${STORE_READ%%|*}"
STORE_NONEMPTY="${STORE_READ#*|}"
info "store: PFIN_DB_PASSWORD (is_preview=false) row count on '$RESOURCE_NAME' = ${STORE_COUNT:-<none>}, non-empty=${STORE_NONEMPTY:-<none>}"
# Sec F-2 (PR #854 review): STORE_HAS_PW normalized to "true"/"false" --
# same vocabulary as ROLCANLOGIN/HAS_PASSWORD below, even though this
# value is bash-assigned by this `case`, never psql-cast, so it was
# never subject to the t/true predicate bug itself. One die() message
# mixing two boolean vocabularies (this one still "t"/"f" while the
# other two read "true"/"false") is exactly the shape a FUTURE t->true
# sweep "fixes" by editing the die() text alone, silently breaking
# provision.sh's own handoff_adopt_check() byte-match against it (that
# grep, and the ONE OTHER site below, are this value's only two
# consumers -- normalizing here is safe).
#
# team-lead's run-6 stop (realrun6.clean.log, 2026-09-21) -- MEASURED on
# the box: pfin-back-etl and pfin-provider-sync BOTH already carry
# exactly one PFIN_DB_PASSWORD row (is_preview=false), but with
# value_len=0 -- an EMPTY PLACEHOLDER row Coolify's compose parser
# creates from the workers' PLAIN `${PFIN_DB_PASSWORD}` interpolation
# (workers/etl/docker-compose.yaml:97, workers/provider-sync/docker-
# compose.yaml:124 -- NOT the `:?` form; Sec's own compose measurement,
# PR #859 review, corrected an earlier wrong attribution here), never a
# value this script or push-production-secrets.sh (which excludes this
# key by design) ever wrote. A row-COUNT-only check
# read this placeholder as "store has a value" (STORE_HAS_PW=true),
# sending an otherwise-fresh role (LOGIN+password not yet set, or
# already set with nothing to bind against) into the wrong branch below.
# Fix: STORE_HAS_PW is true only when the row exists AND its value is
# non-empty; an empty placeholder is treated as "no value" -- the exact
# same shape as a genuinely fresh store, which is what it is.
case "$STORE_COUNT" in
  0) STORE_HAS_PW=false ;;
  1)
    if [[ "$STORE_NONEMPTY" == "1" ]]; then
      STORE_HAS_PW=true
    else
      STORE_HAS_PW=false
      info "store row exists but is an empty compose-parse placeholder -- treated as no value"
    fi
    ;;
  *) die "PFIN_DB_PASSWORD (is_preview=false) readback on '$RESOURCE_NAME' found '$STORE_COUNT' matching row(s), expected 0 or 1 -- refusing to trust an ambiguous store state." ;;
esac

if [[ $ROTATE -eq 1 ]]; then
  [[ "$ROLCANLOGIN" == "true" ]] || die "role '$ROLE' is not yet LOGIN -- this is an INITIAL handoff, not a rotation. Omit --rotate."
else
  # Sec-reviewed CONTROL, not a loosening: the refusal below still fires
  # on any state that is neither "fully fresh" nor "fully handed off" --
  # only the two CONSISTENT states are treated as non-refusals now.
  if [[ "$ROLCANLOGIN" == "true" && "$HAS_PASSWORD" == "true" && "$STORE_HAS_PW" == "true" ]]; then
    ok "role '$ROLE' already has LOGIN + a password set, and '$RESOURCE_NAME' already carries a production PFIN_DB_PASSWORD -- checking whether the store's value actually binds to Postgres's live password before reporting VERIFIED."
    # Sec F-1 (PR #852 AMBER review) remedied here (team-lead, run-4
    # follow-up, 2026-09-21): this no-op path used to be EXISTENCE-only --
    # it never proved the store's CURRENT value was the SAME credential
    # Postgres is actually authenticating with. The residual named at F-1
    # (a stale value from a half-completed --rotate, where Postgres and the
    # store fell out of sync mid-run, would read true|true|true and report
    # VERIFIED with no further check) is now closed by an actual live
    # authentication attempt using the store's own current value -- read
    # via the same box-side tinker mechanism leg A of a fresh handoff
    # would use to READ (never PATCH) the credential, then a real connect
    # AS $ROLE over -h db with it (the same leg-C-shaped check the fresh
    # handoff flow already runs further below, applied here read-only,
    # never generating or pushing anything).
    step "Preflight -- already-handed-off bind-check: does the store's current PFIN_DB_PASSWORD actually authenticate as '$ROLE'?"
    # ⚠ Written to a real temp file, then fed via `< "$file"`, NEVER a
    # heredoc nested inside this `$(...)` assignment -- bash 3.2 (the
    # operator's own shell) has a parser bug on exactly that nesting shape
    # (a heredoc inside a command substitution assigned inside/near an
    # `if`): confirmed live while building this fix (`bad substitution` /
    # `unexpected token` at an unrelated downstream line, the same class
    # already documented for the `python3 - <<'PYEOF'` case elsewhere in
    # this repo's own scripts). CI runs bash 5, where the nested form would
    # have passed silently -- this would have shipped a script that only
    # breaks under the operator's own bash 3.2, never caught here.
    BIND_CHECK_SCRIPT="$(mktemp)"
    cat > "$BIND_CHECK_SCRIPT" <<'REMOTE'
set -e
echo "== Reading the store's CURRENT PFIN_DB_PASSWORD (read-only -- no rotation, no PATCH) =="
PW="$(docker exec coolify php artisan tinker --execute="
/* probe:bind-check-value */
\$app = \App\Models\Application::where('uuid','$RESOURCE_UUID')->firstOrFail();
\$row = \$app->environment_variables()->where('key', 'PFIN_DB_PASSWORD')->where('is_preview', false)->first();
echo \$row ? (string) \$row->value : '';
" 2>/dev/null | tail -1 | tr -d ' \n')"
if [ -z "$PW" ]; then
  # team-lead's run-6 stop, item 3 -- this branch is now unreachable in the
  # normal case (the preflight's own STORE_HAS_PW check above already
  # treats an empty/placeholder row as "no value" and never reaches this
  # bind-check at all), but kept as a fail-closed guard against a race: the
  # store changing between the preflight's read and this one, moments
  # later. A distinct sentinel line lets the caller give an honest message
  # here instead of the misleading "does NOT authenticate" one below (this
  # was never actually tried against a value).
  echo "FATAL: PFIN_DB_PASSWORD (is_preview=false) resolved to empty on the bind-check read, despite the earlier preflight read reporting a non-empty value -- the store changed between the two reads (a race), or the preflight check was bypassed. Refusing to trust an inconsistent store." >&2
  echo "BIND_CHECK_EMPTY_VALUE_RACE"
  exit 1
fi

echo "== Connect AS $ROLE over -h db with the store's current credential (read-only proof; never rotates anything) =="
# team-lead's own live measurement, run-5 (realrun5.clean.log), 2026-09-21,
# MEASURED on the production target: psql 17.6 over -h db, non-tty, inside
# `docker compose exec -T`, prints NO "Password for user" text at all
# without -W -- it silently consumes the first piped stdin line as the
# password. `-W` forces a prompt regardless of tty/pipe state; its exact
# text is `Password: `, not `Password for user "<role>":` -- accepted as
# either form below, since the exact wording is a psql-version fact, not a
# security property this check should be brittle against.
#
# POSITIVE CONTROL, same measurement: a deliberately WRONG password over
# this SAME path (-h db, -W) must fail with "password authentication
# failed" -- that failure IS the trust-path detection this leg exists to
# provide. Without it, a wrong password succeeding (a trust rule) or
# failing some OTHER way (DNS, compose, protocol) would both be
# indistinguishable from the real credential simply not being tried yet.
WRONG_PW="control-$RANDOM-$RANDOM-$RANDOM"
set +e
CONTROL_OUT="$(docker compose --project-name "$STACK_UUID" exec -T db psql -v ON_ERROR_STOP=1 -h db -p 5432 -W -U "$ROLE" -d postgres <<< "$(printf '%s\nselect current_user;\n' "$WRONG_PW")" 2>&1)"
CONTROL_RC=$?
set -e
if printf '%s' "$CONTROL_OUT" | grep -qF -- "$PW"; then
  echo "FATAL: the real credential's cleartext value appeared in the trust-path control's own captured output (a control run using a DIFFERENT, deliberately-wrong password) -- refusing to proceed or print it." >&2
  exit 1
fi
if [ "$CONTROL_RC" -eq 0 ] || ! printf '%s' "$CONTROL_OUT" | grep -qF "password authentication failed for user \"$ROLE\""; then
  echo "FATAL: connecting AS $ROLE with a deliberately WRONG password did not fail with the exact text 'password authentication failed for user \"$ROLE\"' (exit $CONTROL_RC) -- this means the connection may have taken a NON-password-authenticated path (a trust rule), or something else unexpected happened. Observed output: $CONTROL_OUT" >&2
  exit 1
fi
echo "OK: trust-path control: a deliberately WRONG password was refused with 'password authentication failed for user \"$ROLE\"' -- this path genuinely verifies passwords (not a trust rule). Wrong value never printed."

set +e
CONNECT_OUT="$(docker compose --project-name "$STACK_UUID" exec -T db psql -v ON_ERROR_STOP=1 -h db -p 5432 -W -U "$ROLE" -d postgres <<< "$(printf '%s\nselect current_user;\n' "$PW")" 2>&1)"
CONNECT_RC=$?
set -e
if printf '%s' "$CONNECT_OUT" | grep -qF -- "$PW"; then
  echo "FATAL: the credential's cleartext value appeared in the bind-check connect step's own captured output -- refusing to proceed or print it." >&2
  exit 1
fi
if ! printf '%s' "$CONNECT_OUT" | grep -qE "Password:|Password for user"; then
  echo "FATAL: no password prompt (\"Password:\") was observed connecting AS $ROLE with the store's current credential -- a non-password-authenticated path, or -W stopped forcing one. Observed output: $CONNECT_OUT" >&2
  exit 1
fi
if [ $CONNECT_RC -ne 0 ]; then
  echo "FATAL: could not connect AS $ROLE with the store's current credential (exit $CONNECT_RC) -- the store and the live role have drifted apart. Observed output: $CONNECT_OUT" >&2
  exit 1
fi
if ! printf '%s' "$CONNECT_OUT" | grep -qE "^[[:space:]]*${ROLE}[[:space:]]*\$"; then
  echo "FATAL: connected but current_user did not echo back '$ROLE' as its own output row. Observed output: $CONNECT_OUT" >&2
  exit 1
fi
echo "OK: connected AS $ROLE over a non-loopback, password-prompted path with the store's current credential; current_user confirmed."
REMOTE
    if BIND_CHECK_OUT="$(sshx "env STACK_UUID=\"$STACK_UUID\" RESOURCE_UUID=\"$RESOURCE_UUID\" ROLE=\"$ROLE\" bash -s" < "$BIND_CHECK_SCRIPT")"; then
      BIND_CHECK_RC=0
    else
      BIND_CHECK_RC=$?
    fi
    rm -f "$BIND_CHECK_SCRIPT"
    if [[ "$BIND_CHECK_RC" -ne 0 ]]; then
      # team-lead's run-6 stop, item 3 -- distinguish the bind-check's own
      # defensive "resolved to empty" trip (a race against the preflight
      # read a moment earlier, or the preflight check bypassed) from a
      # genuine credential mismatch. The former is NOT "does NOT
      # authenticate" -- it was never tried against a value at all.
      if printf '%s' "$BIND_CHECK_OUT" | grep -qF "BIND_CHECK_EMPTY_VALUE_RACE"; then
        die "role '$ROLE' / '$RESOURCE_NAME' preflight reported a non-empty store value, but the bind-check's own read a moment later found it empty -- a race between the two reads, or the store changed mid-run. Refusing to guess which is authoritative; re-run. (bind-check output: $BIND_CHECK_OUT)"
      fi
      die "role '$ROLE' / '$RESOURCE_NAME' state is INCONSISTENT(store≠role) -- rolcanlogin=$ROLCANLOGIN has_password=$HAS_PASSWORD store_has_PFIN_DB_PASSWORD=$STORE_HAS_PW, but the store's current PFIN_DB_PASSWORD does NOT authenticate as '$ROLE' against the live database (bind-check output: $BIND_CHECK_OUT). This is the exact half-completed-rotation residual Sec named at PR #852's F-1 review -- the existence-only check would have silently reported VERIFIED here. Run --apply --rotate to re-establish a coherent value from scratch."
    fi
    # team-lead's run-6 stop, item 5b -- surface the bind-check's own
    # observed-fact lines (including the trust-path control's OK line)
    # to this script's own stdout on success too, not only inside a
    # die() on failure -- otherwise the control's own proof that this
    # path genuinely verifies passwords is invisible in a clean run log.
    # Safe to print unconditionally here: the remote script's own
    # cleartext-scrub guards already would have exited non-zero (caught
    # above) before ever reaching its own final success echo if $PW had
    # leaked into this capture.
    printf '%s\n' "$BIND_CHECK_OUT"
    ok "bind-check confirmed: the store's current PFIN_DB_PASSWORD authenticates as '$ROLE' against the live database."
    printf '\n\033[32mVERIFIED\033[0m  already handed off -- store and live role bind-checked, no-op whether or not --apply was passed. Pass --apply --rotate to rotate the established credential.\n'
    exit 0
  elif [[ "$ROLCANLOGIN" == "false" && "$HAS_PASSWORD" == "false" && "$STORE_HAS_PW" == "false" ]]; then
    : # genuinely fresh -- fall through to the existing Plan/Apply flow, unchanged.
  else
    die "role '$ROLE' / '$RESOURCE_NAME' state is INCONSISTENT -- rolcanlogin=$ROLCANLOGIN has_password=$HAS_PASSWORD store_has_PFIN_DB_PASSWORD=$STORE_HAS_PW. Expected either ALL THREE false (fresh -- safe to run --apply) or ALL THREE true (already handed off -- nothing to do); a partial/mismatched combination needs investigation by hand before this script can safely proceed either way. This is NOT the --rotate case -- pass --apply --rotate only when you are intentionally rotating an already-established credential (rolcanlogin=true, has_password=true)."
  fi
fi

step "Plan"
cat <<PLAN
      role            $ROLE
      target resource $RESOURCE_NAME  ($RESOURCE_UUID)
      mode            $([[ $ROTATE -eq 1 ]] && echo "ROTATE (role already LOGIN; \\password only, no LOGIN flip)" || echo "INITIAL HANDOFF (\\password then ALTER ROLE ... LOGIN)")
      current state   rolcanlogin=$ROLCANLOGIN has_password=$HAS_PASSWORD store_has_PFIN_DB_PASSWORD=$STORE_HAS_PW
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
# ⚠ `</dev/null` is load-bearing, not cosmetic (Sec VETO-1, PR #854
# review, found while reviewing db-bootstrap.sh's identical shape --
# live-confirmed there against team-lead's own 2026-09-21 run). This
# remote script is fed to `bash -s` on ssh's OWN stdin, and `docker
# compose exec -T` ATTACHES and DRAINS stdin -- without the redirect,
# THIS call eats the rest of this heredoc's bytes, bash hits EOF and
# exits 0, and everything after it silently never runs: this leg's own
# comparison below, ALL of leg C's trust-path detection (Sec VETO V-1,
# PR #846 -- the `-h localhost` -> `-h db` fix), and leg D/E's Coolify
# push + hash-bound readback. Same defect class as mint-supabase-jwt-
# keys.sh's 2026-09-11 item (2a). Every `docker compose exec -T` inside a
# heredoc-fed remote block needs this, whether or not the command itself
# reads stdin -- docker drains it regardless (measured).
VERIFY="$(docker compose --project-name "$STACK_UUID" exec -T db psql -U supabase_admin -d postgres -tAc \
  "select rolcanlogin::text || '|' || (select (rolpassword is not null)::text from pg_authid where rolname='$ROLE') from pg_roles where rolname='$ROLE';" </dev/null)"
VERIFY_TRIMMED="$(printf '%s' "$VERIFY" | tr -d ' \n')"
if [ "$VERIFY_TRIMMED" != "true|true" ]; then
  echo "FATAL: post-handoff catalog verify expected 'true|true' (rolcanlogin|has_password), got '$VERIFY_TRIMMED'." >&2
  exit 1
fi
echo "OK: catalog confirms rolcanlogin=true and a password is set."

step_r "C. Connect AS $ROLE over a non-loopback path with the generated credential (forces password auth)"
# Sec VETO V-1 (PR #846 review) -- CORRECTED IN PLACE, not merely amended:
# this leg previously used `-h localhost`, which -- run FROM INSIDE the db
# container itself, as this leg does -- is the container-internal LOOPBACK
# path. supabase/migrations/055_pfin_etl_role.sql:277-282's own measured
# local-stack pg_hba.conf records `host all all 127.0.0.1/32 trust`: NO
# password prompt on that path at all. Under trust, the first piped stdin
# line (the CLEARTEXT credential) is consumed as a SQL STATEMENT instead of
# a password answer -- a syntax error, whose statement text (the cleartext)
# is then written to the server log via log_min_error_statement (default
# `error`), independent of log_statement. This is the exact hazard class
# the §6.1/§6.2 single-statement-form PROHIBITION exists to prevent,
# re-entering through this verification step. The prior version's own
# claim here ("forces the TCP host-connection path...not local trust") was
# measured FALSE against 055's own recorded pg_hba.
#
# Fix: `-h db` instead of `-h localhost` -- resolving the stack's OWN
# service name from inside its own container routes the connection through
# the container's real network interface (Docker's embedded DNS + the
# bridge network), landing on the CIDR-scoped rule
# (`host all all 10/8, 172.16/12, 192.168/16, 0.0.0.0/0 scram-sha-256`,
# same 055 citation) rather than the 127.0.0.1/32-specific trust rule --
# the SAME rule class a remote docker-network peer (the actual worker
# container) needs. ⚠ UNMEASURED ON THE PRODUCTION TARGET, stated rather
# than assumed (055:296's own "production pg_hba is NOT measured" bound
# applies identically here) -- this is why the three structural guards
# below do not TRUST the hostname choice alone; they detect a trust-path
# connection even if this reasoning turns out wrong on some future image.
#
# 1. `-v ON_ERROR_STOP=1` -- forces a non-zero psql exit on ANY SQL error
#    inside the piped script, including the exact "credential consumed as
#    a statement" failure mode above. The prior version had no such guard,
#    so psql exited 0 after a syntax error and the next line
#    (`select current_user;`) ran anyway, appearing to succeed.
# 2. Assert the password PROMPT was actually issued. 055:297-299 names
#    this exact discriminator: "Under trust no password is requested at
#    all -- so THE PROMPT ITSELF proves the connection did not traverse
#    the trust line." Absence of "Password for user" in the captured
#    output is now FATAL on its own, independent of the exit code.
# 3. The cleartext-in-output guard (Sec VETO V-1 item 4, PR #846 review --
#    corrected at N-12 after an earlier edit here mislabeled it F-5-class;
#    F-5 was Sec's UNRELATED SET_ALLOWLIST value-shape finding on
#    coolify-env.sh) is the SAME mechanism applied to step A above, now
#    ALSO covering this channel -- CONNECT_OUT is grepped for `$PW` the
#    same way step A's $OUT already is. The password crosses via psql's
#    OWN connection-time prompt, piped over stdin (verified locally this
#    PR, same mechanism as \password's own prompt) -- never PGPASSWORD
#    (env or argv).
# 4. Sec C-1 (PR #856 round 1) -- BACKPORTED from the already-handed-off
#    bind-check below (Item 4, run-4 follow-up) into this ORIGINAL leg C,
#    which must never diverge from its own copy: the scrub (2) now runs
#    BEFORE the prompt check (Sec F-2b's actual requirement -- "scrub
#    before OUT is ever printed, on every branch"), the scrub uses `--`
#    (Sec N-1's option-injection guard), and the current_user match below
#    is the F-1b-corrected exact-row form, not a bare substring (a bare
#    `grep -qF "$ROLE"` is ALREADY satisfied by the "Password for user
#    $ROLE:" prompt line itself, so it could never fail independently of
#    the prompt check -- this was the actual defect: this original leg C
#    still carried the PRE-F-1b form even though db-bootstrap.sh's own
#    copy of this same mechanism already had the fix, and the new
#    bind-check copied THIS site rather than db-bootstrap's corrected
#    one). Both sites now match byte-for-byte in shape; keep them that
#    way on any future edit.
# team-lead's own live measurement, run-5 (realrun5.clean.log), 2026-09-21,
# MEASURED on the production target: psql 17.6 over -h db, non-tty, inside
# `docker compose exec -T`, prints NO "Password for user" text at all
# without -W -- it silently consumes the first piped stdin line as the
# password. `-W` forces a prompt regardless of tty/pipe state; its exact
# text is `Password: `, not `Password for user "<role>":` -- accepted as
# either form below.
#
# POSITIVE CONTROL, same measurement: a deliberately WRONG password over
# this SAME path (-h db, -W) must fail with "password authentication
# failed" -- the actual trust-path proof, run BEFORE the real credential.
WRONG_PW="control-$RANDOM-$RANDOM-$RANDOM"
set +e
CONTROL_OUT="$(docker compose --project-name "$STACK_UUID" exec -T db psql -v ON_ERROR_STOP=1 -h db -p 5432 -W -U "$ROLE" -d postgres <<< "$(printf '%s\nselect current_user;\n' "$WRONG_PW")" 2>&1)"
CONTROL_RC=$?
set -e
if printf '%s' "$CONTROL_OUT" | grep -qF -- "$PW"; then
  echo "FATAL: the real credential's cleartext value appeared in the trust-path control's own captured output (a control run using a DIFFERENT, deliberately-wrong password) -- refusing to proceed or print it." >&2
  exit 1
fi
if [ "$CONTROL_RC" -eq 0 ] || ! printf '%s' "$CONTROL_OUT" | grep -qF "password authentication failed for user \"$ROLE\""; then
  echo "FATAL: connecting AS $ROLE with a deliberately WRONG password did not fail with the exact text 'password authentication failed for user \"$ROLE\"' (exit $CONTROL_RC) -- this means the connection may have taken a NON-password-authenticated path (a trust rule), or something else unexpected happened. Observed output: $CONTROL_OUT" >&2
  exit 1
fi
echo "OK: trust-path control: a deliberately WRONG password was refused with 'password authentication failed for user \"$ROLE\"' -- this path genuinely verifies passwords (not a trust rule). Wrong value never printed."

set +e
CONNECT_OUT="$(docker compose --project-name "$STACK_UUID" exec -T db psql -v ON_ERROR_STOP=1 -h db -p 5432 -W -U "$ROLE" -d postgres <<< "$(printf '%s\nselect current_user;\n' "$PW")" 2>&1)"
CONNECT_RC=$?
set -e
if printf '%s' "$CONNECT_OUT" | grep -qF -- "$PW"; then
  echo "FATAL: the credential's cleartext value appeared in the connect-as-role step's own captured output -- refusing to proceed or print it. Investigate before retrying." >&2
  exit 1
fi
if ! printf '%s' "$CONNECT_OUT" | grep -qE "Password:|Password for user"; then
  echo "FATAL: no password prompt (\"Password:\") was observed connecting AS $ROLE -- this means the connection took a NON-password-authenticated path (e.g. a trust rule), or -W stopped forcing one, which is the exact hazard this step exists to detect. Refusing regardless of exit code (this check does not trust ON_ERROR_STOP or the exit status alone). Observed output: $CONNECT_OUT" >&2
  exit 1
fi
if [ $CONNECT_RC -ne 0 ]; then
  echo "FATAL: could not connect AS $ROLE with the generated credential (exit $CONNECT_RC) -- the handoff did not take effect end to end. Observed output: $CONNECT_OUT" >&2
  exit 1
fi
if ! printf '%s' "$CONNECT_OUT" | grep -qE "^[[:space:]]*${ROLE}[[:space:]]*\$"; then
  echo "FATAL: connected but current_user did not echo back '$ROLE' as its own output row. Observed output: $CONNECT_OUT" >&2
  exit 1
fi
echo "OK: connected AS $ROLE over a non-loopback, password-prompted path with the generated credential; current_user confirmed."

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

step_r "E. Hash-bound readback — production row only, exactly one match, bound to the ACTUAL generated credential (never the value itself)"
# Sec F-2 (PR #846 review). The prior length-only check ('== 64') passed
# for ANY 64-char value on the resource -- it could not distinguish "our
# push landed" from "a stale/different 64-char secret was already there,
# and step D's own PATCH silently no-op'd or hit the wrong row". Two
# tightenings, both still never reading the plaintext value back to this
# shell or printing it:
#   1. is_preview=false -- scope to the PRODUCTION env row specifically;
#      Coolify's env store carries separate rows for a PR-preview deploy
#      (is_preview=true) and the production deploy of the SAME app, and a
#      bare `where('key', ...)` could silently bind to the wrong one.
#   2. exactly one matching row (`count`, not `->first()`) -- `->first()`
#      degrades silently to "whichever row Eloquent's default ordering
#      picks first" if duplicates exist; this refuses instead.
#   3. a TRUNCATED (16 hex char) SHA-256 of the stored value must match
#      the same truncated hash of $PW, computed locally from the shell
#      variable (still in scope; never re-reads the shredded seed file).
#      16 hex chars (64 bits) is not a meaningful preimage/collision
#      target for a value this short-lived and never exposed elsewhere,
#      and it is the ONLY thing that proves the stored value is the SAME
#      credential this run generated, not merely 64 characters long.
# team-lead's run-6 stop, item 8 -- same hardening as db-bootstrap.sh's
# own two leg-E sites: hash-bound, so structurally already immune to an
# empty/placeholder value, but given the SAME explicit non-empty
# predicate for a clearer diagnostic.
EXPECTED_HASH="$(printf '%s' "$PW" | sha256sum | cut -c1-16)"
READBACK_OUT="$(docker exec coolify php artisan tinker --execute="
/* probe:readback-hash */
\$app = \App\Models\Application::where('uuid','$RESOURCE_UUID')->firstOrFail();
\$rows = \$app->environment_variables()->where('key', 'PFIN_DB_PASSWORD')->where('is_preview', false)->get();
\$userRow = \$app->environment_variables()->where('key', 'PFIN_DB_USER')->where('is_preview', false)->first();
\$userVal = \$userRow ? (string) \$userRow->value : '';
if (\$rows->count() !== 1) { echo \$rows->count() . '||' . \$userVal; } else { \$v = (string) \$rows[0]->value; echo '1|' . (\$v === '' ? 'EMPTY' : substr(hash('sha256', \$v), 0, 16)) . '|' . \$userVal; }
" 2>/dev/null | tail -1 | tr -d ' \n')"
READBACK_COUNT="${READBACK_OUT%%|*}"
READBACK_REST="${READBACK_OUT#*|}"
READBACK_HASH="${READBACK_REST%%|*}"
READBACK_USER="${READBACK_REST#*|}"
if [ "$READBACK_COUNT" != "1" ]; then
  echo "FATAL: PFIN_DB_PASSWORD (is_preview=false) readback found $READBACK_COUNT matching row(s) on the target resource, expected exactly 1 -- refusing to trust the store." >&2
  exit 1
fi
if [ "$READBACK_HASH" = "EMPTY" ]; then
  echo "FATAL: PFIN_DB_PASSWORD (is_preview=false) readback resolved to an empty value on the target resource, despite the row existing -- refusing to trust the store." >&2
  exit 1
fi
if [ "$READBACK_HASH" != "$EXPECTED_HASH" ]; then
  echo "FATAL: PFIN_DB_PASSWORD is present (one production row) but its truncated hash does not match the credential this run generated -- the store holds a DIFFERENT value than what was pushed. Refusing. (Hash only -- neither value is ever read back or printed.)" >&2
  exit 1
fi
echo "OK: PFIN_DB_PASSWORD present on the target resource (production row, exactly one match), hash-bound to the generated credential confirmed (value never printed)."

# Sec F-4 (PR #846 review) -- PFIN_DB_USER ordering hazard. docs/deployment-
# runbook.md §7.2's own values table names it explicitly for provider-sync:
# PFIN_DB_USER reads 'authenticator' PRE-cutover and 'pfin_provider_sync'
# POST-cutover (§6.2). A DIFFERING value is therefore the EXPECTED state
# for a normal --apply-without---rotate handoff run ahead of the cutover
# (staging the new role's credential before the operator flips the var and
# redeploys) -- hard-refusing on any mismatch here would break that
# legitimate, documented flow. --rotate is different: it only ever applies
# to a role the resource is ALREADY configured to use (§6.1/§6.2's own
# idempotency gate above requires the role to already be LOGIN), so
# PFIN_DB_USER should ALREADY equal $ROLE by the time --rotate runs; a
# mismatch there means a credential is being rotated for a role the
# resource isn't even wired to yet -- refuse hard.
if [ "$READBACK_USER" != "$ROLE" ]; then
  if [ "$ROTATE" = "1" ]; then
    echo "FATAL: PFIN_DB_USER on the target resource is '$READBACK_USER', not '$ROLE' -- refusing to rotate a credential for a role the resource is not configured to use. --rotate implies the handoff already completed and PFIN_DB_USER should already match." >&2
    exit 1
  fi
  echo "⚠ WARNING: PFIN_DB_USER on the target resource is still '$READBACK_USER', not '$ROLE'. This is the EXPECTED mid-cutover staging state (docs/deployment-runbook.md §7.2) but the credential just pushed will NOT take effect until an operator flips PFIN_DB_USER to '$ROLE' and redeploys. If this mismatch is unexpected for this resource, stop and investigate before redeploying."
else
  echo "OK: PFIN_DB_USER on the target resource already reads '$ROLE' -- the pushed credential will take effect on redeploy with no further env-var change needed."
fi

step_r "Done (remote)"
echo "Seed file will be shredded now by this script's own EXIT trap."
REMOTE

step "Done"
info "Role '$ROLE' now has LOGIN + a generated credential; the SAME credential is set as PFIN_DB_PASSWORD on '$RESOURCE_NAME'."
info "⚠ A REDEPLOY/RESTART IS STILL REQUIRED — Coolify only injects an env-store change into a container at deploy/recreate time. Per docs/deployment-runbook.md §6.1/§6.2: restart ONLY '$RESOURCE_NAME' — no coordinated PostgREST redeploy, no other worker restart. This script does not trigger it (a deliberate, separate operator step)."
info "Record this resource's uuid with scripts/record-coolify-uuids.sh --apply if not already recorded."
