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
#     REVOKEs -> the migrator credential handoff, FOUR legs (A/B/C/E --
#     no leg D; see PATH A below), same B/C shape as db-role-handoff.sh's
#     own (that script's header has the full derivation; not re-derived
#     here):
#       A) READ, DON'T MINT (Sec VETO-1 r2 ruling, PR #849 review --
#          PATH A, team-lead's call). db-bootstrap no longer generates
#          its own credential. `provision-migrator-app.sh` (step 3,
#          BEFORE this script runs) already mint-if-absent's
#          MIGRATOR_DB_PASSWORD into the `pfin-migrator` Coolify
#          resource's OWN env store, AND deploys the migrator container
#          with that value compose-interpolated into PROD_DB_URL at
#          deploy time (`infra/supabase/migrator/docker-compose.yaml`).
#          That deploy already happened by the time db-bootstrap runs --
#          the RUNNING CONTAINER's own PROD_DB_URL is therefore already
#          correct, by construction, for whatever value is in the store
#          right now. This leg reads that SAME value (box-side, via the
#          coolify tinker mechanism leg E already used for E -- Coolify's
#          public API never returns a secret's real value, so this is
#          NOT a `GET /envs` call) and sets the Postgres role's password
#          to it via `\password migrator` + `ALTER ROLE migrator LOGIN`,
#          -v ON_ERROR_STOP=1. REFUSES (exit 2, precondition) if the
#          store holds no MIGRATOR_DB_PASSWORD -- run
#          provision-migrator-app.sh first. The value never leaves the
#          box, never touches this script's own local process, never
#          touches argv on either side -- same seed-file discipline as
#          before, just sourced box-side instead of generated laptop-
#          side. What r1's mint-then-push (leg D) got backwards: minting
#          a SECOND value and pushing it to reconcile the store is
#          strictly redundant with just reading the ONE value that
#          already exists and is already what the running container
#          uses -- one authoritative source, not two reconciled after
#          the fact. Tradeoff, stated: db-bootstrap no longer controls
#          credential FRESHNESS -- rotation is db-role-handoff.sh's job
#          (`--rotate`, which already pushes a new value then requires a
#          redeploy) unchanged by this script.
#       B) catalog verify -- rolcanlogin + pg_authid.rolpassword IS NOT
#          NULL, re-read fresh.
#       C) connect AS migrator over -h db (never -h localhost -- the
#          container-internal loopback trust-path hazard db-role-
#          handoff.sh's own header documents) with the credential read
#          in leg A, asserting a password prompt WAS observed, no
#          cleartext leak, and current_user echoes back EXACTLY
#          'migrator' as its own output ROW (Sec F-1b, PR #849 r2 review
#          -- a substring `grep -qF "migrator"` over the WHOLE capture is
#          satisfied by the prompt line itself, `Password for user
#          migrator: `, and can never fail independently of the prompt
#          check; fixed to match the psql output row exactly).
#       E) Sanity re-read, box-side, both computed box-side (Sec VETO-1
#          r2: the r1 form -- "does the store match what we just read
#          from the store" -- was a tautology). Re-queries the store's
#          CURRENT MIGRATOR_DB_PASSWORD (a fresh tinker read, not the
#          leg-A value held in memory) and compares its hash against the
#          hash of the value the ROLE was actually just set to (leg A's
#          own PW). A mismatch means the store changed between leg A's
#          read and this point -- e.g. a concurrent rotation -- and the
#          role was just set to a value that is no longer what
#          `PROD_DB_URL` will read on the NEXT deploy; refuses rather
#          than reporting a false VERIFIED.
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
# = true) and reports success as a no-op; it detects "partially bootstrapped"
# (some but not all of Phase 1/2/3 landed) and REFUSES rather than
# guessing which repair path applies.
#
# MEASURED BLAST RADIUS OF THE bootstrap_complete PREDICATE BUG
# (team-lead's live --from standup run, main d44a19b0, 2026-09-21) -- the
# `t` vs `true` mismatch (see BOOTSTRAP_COMPLETE below) plus the
# `|| echo 'f'` fail-open meant a database bootstrapped since 2026-09-19
# read as "not bootstrapped" on BOTH the preflight AND the --apply call,
# and the --apply call proceeded to actually re-run against it. What
# that one live run actually did, recorded here so a future incident
# doesn't have to re-derive it from scratch: Phase 1 re-ran roles.sql,
# auth-grants.sql, the engine-backstop REVOKEs, and the 055/116/117/
# 118/119 role-comment files -- every one an idempotent NOTICE-skip
# against the pre-existing objects, no schema change. The migrator
# credential handoff's leg A (`\password migrator`) reset the role's
# password to the SAME value already in the Coolify store (leg A always
# runs unconditionally by design -- PATH A, Sec VETO-1 r2 ruling -- so
# this part is not new exposure, just an unnecessary repeat). What
# actually happened at leg B onward and at Phase 2 is a SEPARATE,
# independently-found defect (Sec VETO-1, PR #854 review), corrected in
# the same PR as this predicate fix: a `docker compose exec -T` call
# inside a heredoc-fed remote `bash -s` block without a stdin redirect
# DRAINS the rest of that heredoc's own bytes, so leg B's own catalog-
# verify comparison, ALL of leg C (the trust-path detection), and leg E
# (the store-drift readback) never actually ran that day -- the log shows
# neither leg B's own OK/FATAL line nor leg C's/E's banners anywhere,
# even though the outer script still printed its "sanity re-read confirms
# no drift" success line (false: no re-read happened). Phase 2's own
# `supabase db push` call has the identical defect -- its completion-line
# check never ran either, so "reported a no-op" could not actually be
# confirmed from that log; only that the outer script printed "migration
# sweep applied" regardless of what the push itself did. No data is known
# to have been lost or corrupted, but this MEASURED BLAST RADIUS note
# should be read as "what the outer script printed", not "what was
# verified" for everything from leg B onward in that run. The run then
# genuinely FAILED at Phase 2 verify, because bootstrap_complete was
# STILL misread as false even after Phase 1/2 ran -- which is what
# surfaced the ORIGINAL predicate bug, independent of the stdin-drain
# defect. The fix below addresses both: not doing unnecessary re-apply
# work on every re-run, refusing cleanly instead of guessing on a failed
# read, AND (see legs B/Phase-2-push below) not silently skipping the
# checks that would have caught either problem.
#
# USAGE
#   scripts/db-bootstrap.sh              # preflight: read-only, prints the plan
#   scripts/db-bootstrap.sh --apply      # runs Phase 1 -> 2 -> 3
#
#   BOX_IP is read from .env (script-written by provision-vps.sh --apply).
#
# EXIT CODES
#   0  VERIFIED -- bootstrap_complete = true, the ownership census shows
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
  # `</dev/null` (Sec VETO-1 / team-lead's tree-wide follow-up, PR #854) --
  # this exec is the LAST line of its own heredoc today, so nothing
  # currently gets drained by it, but that is a position-dependent
  # accident, not a guarantee -- a future line added after it inside this
  # same heredoc would silently reacquire the exact defect this PR fixes
  # elsewhere. Redirect defensively, unconditionally.
  sshx "env STACK_UUID=\"$STACK_UUID\" bash -s" <<REMOTE
set -e
docker compose --project-name "\$STACK_UUID" exec -T db psql -U supabase_admin -d postgres -tAc "$1" </dev/null
REMOTE
}

# read_gate <description-for-errors> <sql> -- team-lead's live --from
# standup finding, 2026-09-21: the OLD bootstrap_complete read used
# `2>/dev/null | tr -d ' \n' || echo 'f'` -- a FAILED read (psql/ssh/
# docker error) was silently converted into the specific answer "not
# bootstrapped", which this script then trusted and proceeded to a full
# Phase 1->3 re-apply against an already-bootstrapped, live database. A
# failed read is UNKNOWN, never a specific value -- this helper refuses
# immediately (exit 2) rather than ever falling through to a caller with
# a guessed answer. Every gating read in this script goes through this,
# not just the one team-lead's brief named -- a fail-open here is the
# SAME defect class regardless of which read it sits on.
read_gate() {
  # Sec N-1 (PR #854 review), two fixes:
  # (a) stderr is captured SEPARATELY from stdout via a temp file, not
  #     folded into $out with `2>&1` -- benign stderr on a SUCCESSFUL
  #     read (ssh's own "Warning: Permanently added ... to the list of
  #     known hosts" on a first connect under
  #     StrictHostKeyChecking=accept-new, or a docker compose WARN line)
  #     would otherwise become part of the parsed VALUE and trip this
  #     function's own caller-side parse guards -- a new refusal path on
  #     the success case the fix did not require. Diagnostic text stays
  #     available for the die2 message on the failure path either way.
  # (b) `if out=$(cmd); then rc=0; else rc=$?; fi`, never `set +e; ...;
  #     set -e` -- the exact pattern flagged as this PR's own defect #4
  #     in provision.sh (an unconditional `set -e` at a helper's end
  #     flips errexit back ON if the CALLER had it off). No live call
  #     site of read_gate is currently inside such a bracket, so this was
  #     latent, not exploitable -- fixed anyway since the cost is zero
  #     and it is the exact trap already found and fixed once this PR.
  local desc="$1" sql="$2" out err_file err rc
  err_file="$(mktemp)"
  if out="$(psql_admin "$sql" 2>"$err_file")"; then
    rc=0
  else
    rc=$?
  fi
  err="$(cat "$err_file")"
  rm -f "$err_file"
  if [[ "$rc" -ne 0 ]]; then
    die2 "could not read $desc (rc=$rc): $err -- refusing to guess; this state is UNKNOWN, never treated as a specific value."
  fi
  printf '%s' "$out" | tr -d ' \n'
}

step "Preflight: migrator credential state (query per archive §6.3 -- the branch-gate, not a guess)"
# Sec measurement, 2026-09-21 (reproduced locally against a throwaway
# initdb instance before shipping this fix, not just trusted): an
# explicit `::text` cast on a boolean value or expression -- as EVERY
# query in this file uses, for concatenation -- prints the LITERAL
# WORDS "true"/"false", never the abbreviated "t"/"f" a bare boolean
# COLUMN's own psql rendering would show. The comparisons below used to
# read "t"/"f"/"t|t" and so never matched a real "true"/"false" answer,
# on EVERY query in this file that casts a boolean, not just the one
# team-lead's brief measured -- fixed uniformly here.
MIGRATOR_STATE="$(read_gate "migrator credential state" "select r.rolcanlogin::text || '|' || (a.rolpassword is not null)::text from pg_catalog.pg_roles r join pg_catalog.pg_authid a on a.rolname = r.rolname where r.rolname = 'migrator';")"
if [[ -n "$MIGRATOR_STATE" && ! "$MIGRATOR_STATE" =~ ^(true|false)\|(true|false)$ ]]; then
  die2 "migrator credential state read returned unparseable output ('$MIGRATOR_STATE') -- refusing to guess; expected empty (role absent) or a 'true|false'-shaped pair."
fi
info "migrator rolcanlogin|password_set = '${MIGRATOR_STATE:-<role absent>}'"

step "Preflight: bootstrap_complete (a row exists for migration 118 -- never a bare row count)"
BOOTSTRAP_COMPLETE="$(read_gate "bootstrap_complete" "select exists(select 1 from supabase_migrations.schema_migrations where version = '118')::text;")"
if [[ "$BOOTSTRAP_COMPLETE" != "true" && "$BOOTSTRAP_COMPLETE" != "false" ]]; then
  die2 "bootstrap_complete read returned unparseable output ('$BOOTSTRAP_COMPLETE') -- refusing to guess; expected exactly 'true' or 'false'."
fi
info "bootstrap_complete = $BOOTSTRAP_COMPLETE"

if [[ "$BOOTSTRAP_COMPLETE" == "true" ]]; then
  step "Already bootstrapped -- verifying the ownership census before reporting VERIFIED"
  CENSUS_BAD="$(read_gate "ownership census" "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'pfin' and pg_get_userbyid(c.relowner) not in ('pfin_owner');")"
  [[ "$CENSUS_BAD" =~ ^[0-9]+$ ]] || die2 "ownership census read returned unparseable output ('$CENSUS_BAD') -- refusing to guess; expected a non-negative integer."
  [[ "$CENSUS_BAD" == "0" ]] || die "bootstrap_complete=true but the ownership census shows $CENSUS_BAD non-pfin_owner-owned pfin object(s) -- the pfin_owner sweep broke somewhere. Investigate by hand; this script does not auto-repair an ownership mismatch."
  ok "ownership census clean (zero non-pfin_owner-owned pfin objects)"

  # Sec's PR #854 finding, remedied here (team-lead, run-4 follow-up,
  # 2026-09-21): the ownership census ALONE was a falsified verification
  # record on THIS path -- it says nothing about the migrator credential
  # actually working end to end. Legs C (connect AS migrator over -h db)
  # and E (store-hash still matches what was just used) from the Phase 1
  # credential-handoff block below are re-run here READ-ONLY (no \password,
  # no ALTER ROLE -- the credential is read from the store, never minted
  # or rewritten) before this path is allowed to report VERIFIED.
  step "Already bootstrapped -- read-only legs C+E against the live migrator credential"
  sshx "env STACK_UUID=\"$STACK_UUID\" MIGRATOR_UUID=\"$MIGRATOR_UUID\" bash -s" <<'REMOTE'
set -e
umask 077

echo "== A (read-only). Reading the CURRENT MIGRATOR_DB_PASSWORD from pfin-migrator's own env store =="
PW="$(docker exec coolify php artisan tinker --execute="
\$app = \App\Models\Application::where('uuid','$MIGRATOR_UUID')->firstOrFail();
\$row = \$app->environment_variables()->where('key', 'MIGRATOR_DB_PASSWORD')->where('is_preview', false)->first();
echo \$row ? (string) \$row->value : '';
" 2>/dev/null | tail -1 | tr -d ' \n')"
if [ -z "$PW" ]; then
  echo "FATAL: pfin-migrator's env store holds no MIGRATOR_DB_PASSWORD (is_preview=false), but bootstrap_complete=true -- credential/store drift. Investigate by hand (see docs/archive/deployment-runbook-rationale-2026-09-20.md sec6.3); do not re-run this script with --apply against an already-bootstrapped box." >&2
  exit 2
fi

echo "== C (read-only). Connect AS migrator over -h db with the store's current credential =="
set +e
CONNECT_OUT="$(docker compose --project-name "$STACK_UUID" exec -T db psql -v ON_ERROR_STOP=1 -h db -p 5432 -U migrator -d postgres <<< "$(printf '%s\nselect current_user;\n' "$PW")" 2>&1)"
CONNECT_RC=$?
set -e
if printf '%s' "$CONNECT_OUT" | grep -qF -- "$PW"; then
  echo "FATAL: the credential's cleartext value appeared in the connect-as-migrator step's own captured output -- refusing to proceed or print it." >&2
  exit 1
fi
if ! printf '%s' "$CONNECT_OUT" | grep -qF "Password for user"; then
  echo "FATAL: no password prompt was observed connecting AS migrator with the store's current credential -- this means the connection took a NON-password-authenticated path (a trust rule), or the credential no longer authenticates at all. Investigate by hand." >&2
  exit 1
fi
if [ $CONNECT_RC -ne 0 ]; then
  echo "FATAL: could not connect AS migrator with the store's current credential (exit $CONNECT_RC) -- the store and the live role have drifted apart. Investigate by hand (see docs/archive/deployment-runbook-rationale-2026-09-20.md sec6.3); this script does not auto-repair a migrator credential mismatch on an already-bootstrapped box." >&2
  exit 1
fi
if ! printf '%s' "$CONNECT_OUT" | grep -qE '^[[:space:]]*migrator[[:space:]]*$'; then
  echo "FATAL: connected but current_user did not echo back 'migrator' as its own output row." >&2
  exit 1
fi
echo "OK: connected AS migrator over a non-loopback, password-prompted path with the store's current credential; current_user confirmed."

echo "== E (read-only). Re-read the store immediately after connecting -- the value used to connect must still hash-match the store's CURRENT value (guards a concurrent rotation racing this very check) =="
EXPECTED_HASH="$(printf '%s' "$PW" | sha256sum | cut -c1-16)"
READBACK_OUT="$(docker exec coolify php artisan tinker --execute="
\$app = \App\Models\Application::where('uuid','$MIGRATOR_UUID')->firstOrFail();
\$rows = \$app->environment_variables()->where('key', 'MIGRATOR_DB_PASSWORD')->where('is_preview', false)->get();
if (\$rows->count() !== 1) { echo \$rows->count(); } else { echo '1|' . substr(hash('sha256', (string) \$rows->first()->value), 0, 16); }
" 2>/dev/null | tail -1 | tr -d ' \n')"
READBACK_COUNT="${READBACK_OUT%%|*}"
READBACK_HASH="${READBACK_OUT#*|}"
if [ "$READBACK_COUNT" != "1" ]; then
  echo "FATAL: MIGRATOR_DB_PASSWORD (is_preview=false) re-read found $READBACK_COUNT matching row(s) on pfin-migrator, expected exactly 1 -- refusing to trust the store." >&2
  exit 1
fi
if [ "$READBACK_HASH" != "$EXPECTED_HASH" ]; then
  echo "FATAL: the store's MIGRATOR_DB_PASSWORD changed between leg A's read and leg C's connect attempt (concurrent rotation) -- refusing to report VERIFIED against a value that may no longer be current." >&2
  exit 1
fi
echo "OK: the store's current MIGRATOR_DB_PASSWORD still hash-matches the value just used to connect -- no drift (value never printed)."
REMOTE
  ok "already-bootstrapped: migrator credential's live connect path (leg C) and store-hash match (leg E) both verified read-only -- VERIFIED, nothing to do"
  exit 0
fi

if [[ "$MIGRATOR_STATE" == "true|true" ]]; then
  die "migrator already has LOGIN + a password set, but bootstrap_complete=false -- a PARTIAL bootstrap state (Phase 1's credential step ran, but migration 118 never landed). This script refuses to guess whether Phase 2 needs a re-run or something else broke; investigate by hand (see docs/archive/deployment-runbook-rationale-2026-09-20.md §6.3's own recovery guidance) before re-running."
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

step "Phase 1: migrator credential handoff -- legs A/B/C/E (no leg D; PATH A, Sec VETO-1 r2 ruling -- read the existing credential from pfin-migrator's own env store, never mint a second one). See this script's own header for the full derivation."
sshx "env STACK_UUID=\"$STACK_UUID\" MIGRATOR_UUID=\"$MIGRATOR_UUID\" bash -s" <<'REMOTE'
set -e
umask 077

echo "== A. Reading the existing MIGRATOR_DB_PASSWORD from pfin-migrator's own env store (box-side; Coolify's public API never returns a secret's real value, so this uses the same tinker mechanism leg E's readback already relies on -- never a GET /envs call) =="
PW="$(docker exec coolify php artisan tinker --execute="
\$app = \App\Models\Application::where('uuid','$MIGRATOR_UUID')->firstOrFail();
\$row = \$app->environment_variables()->where('key', 'MIGRATOR_DB_PASSWORD')->where('is_preview', false)->first();
echo \$row ? (string) \$row->value : '';
" 2>/dev/null | tail -1 | tr -d ' \n')"
if [ -z "$PW" ]; then
  echo "FATAL: pfin-migrator's env store holds no MIGRATOR_DB_PASSWORD (is_preview=false) -- run scripts/provision-migrator-app.sh first (it mint-if-absent's this value, and deploys the container with it already compose-interpolated into PROD_DB_URL)." >&2
  exit 2
fi
if [ "${#PW}" -ne 64 ]; then
  echo "FATAL: the store's MIGRATOR_DB_PASSWORD is ${#PW} chars, expected 64 (provision-migrator-app.sh mints via token_hex(32)) -- refusing to use a malformed value." >&2
  exit 2
fi

echo "== A. \\password migrator + ALTER ROLE ... LOGIN, using the value just read (never generated here) =="
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
# Sec F-2b (PR #849 r3 review): the cleartext scrub MUST run before OUT is
# ever printed, on every branch -- not just the exit-0 happy path. The old
# order (RC check first, printing $OUT raw, THEN the scrub) meant that on
# any non-zero exit the scrub never ran at all: if \password's two piped PW
# lines are not consumed (the trust-path shift leg C exists to detect),
# they get parsed as SQL -> `ERROR: syntax error at or near "<pw>"`, and
# -v ON_ERROR_STOP=1 (Sec F-1) turns that into RC!=0 -- so the F-1 fix
# moved this exact case from the scrubbed branch to the unscrubbed one,
# disclosing the 64-char credential on stderr over ssh to the operator's
# terminal. Leg C already had the right order (cleartext check before its
# own RC check); this mirrors it: scrub first, and only once OUT is proven
# NOT to contain $PW is it safe to print raw in the RC-failure diagnostic
# below. `--` guards the scrub itself (Sec N-1): without it, a stored
# value starting with `-` would be parsed by grep as an option instead of
# matched, failing the scrub OPEN.
if printf '%s' "$OUT" | grep -qF -- "$PW"; then
  echo "FATAL: the credential's cleartext value appeared in psql's own captured output (handoff exited $RC) -- refusing to print it." >&2
  exit 1
fi
if [ $RC -ne 0 ]; then echo "FATAL: psql handoff script exited $RC: $OUT" >&2; exit 1; fi
if printf '%s' "$OUT" | grep -qi "didn't match"; then echo "FATAL: password confirmation mismatch inside \\password." >&2; exit 1; fi
echo "OK: migrator credential handoff completed (exit 0, no mismatch, no cleartext echo)."

echo "== B. Catalog verify (rolcanlogin + pg_authid.rolpassword IS NOT NULL, re-read fresh) =="
# ⚠ `</dev/null` is load-bearing, not cosmetic (Sec VETO-1, PR #854
# review, live-confirmed against team-lead's own 2026-09-21 run). This
# remote script is fed to `bash -s` on ssh's OWN stdin, and `docker
# compose exec -T` ATTACHES and DRAINS stdin -- without the redirect,
# THIS call eats the rest of this heredoc's bytes before bash ever reads
# them, bash hits EOF and exits 0, and everything after it (leg B's own
# comparison below, ALL of leg C's trust-path detection, and leg E's
# store-drift readback) silently never runs, while the OUTER script still
# prints its own "ok" success line. Measured live: realrun3.log prints
# the "== B." banner below, then NEITHER this leg's own OK/FATAL line NOR
# leg C's "== C." banner NOR leg E's readback line appear anywhere, yet
# the outer script's "migrator: LOGIN + password set ... sanity re-read
# confirms no drift" line still printed -- a false OK, not a caught
# failure. Same defect class as mint-supabase-jwt-keys.sh's 2026-09-11
# item (2a). Every `docker compose exec -T` inside a heredoc-fed remote
# block needs this, whether or not the command itself reads stdin --
# docker drains it regardless (measured).
VERIFY="$(docker compose --project-name "$STACK_UUID" exec -T db psql -U supabase_admin -d postgres -tAc \
  "select rolcanlogin::text || '|' || (select (rolpassword is not null)::text from pg_authid where rolname='migrator') from pg_roles where rolname='migrator';" </dev/null)"
VERIFY_TRIMMED="$(printf '%s' "$VERIFY" | tr -d ' \n')"
if [ "$VERIFY_TRIMMED" != "true|true" ]; then
  echo "FATAL: post-handoff catalog verify expected 'true|true' (rolcanlogin|has_password), got '$VERIFY_TRIMMED'." >&2
  exit 1
fi
echo "OK: catalog confirms rolcanlogin=true and a password is set."

echo "== C. Connect AS migrator over a non-loopback path with the generated credential (-h db, never -h localhost -- see db-role-handoff.sh's own header for the container-internal trust-path hazard this avoids; UNMEASURED on the production target, same bound as that script states) =="
set +e
CONNECT_OUT="$(docker compose --project-name "$STACK_UUID" exec -T db psql -v ON_ERROR_STOP=1 -h db -p 5432 -U migrator -d postgres <<< "$(printf '%s\nselect current_user;\n' "$PW")" 2>&1)"
CONNECT_RC=$?
set -e
if ! printf '%s' "$CONNECT_OUT" | grep -qF "Password for user"; then
  echo "FATAL: no password prompt was observed connecting AS migrator -- this means the connection took a NON-password-authenticated path (e.g. a trust rule), which is the exact hazard this step exists to detect. Refusing regardless of exit code." >&2
  exit 1
fi
if printf '%s' "$CONNECT_OUT" | grep -qF -- "$PW"; then
  echo "FATAL: the credential's cleartext value appeared in the connect-as-migrator step's own captured output -- refusing to proceed or print it." >&2
  exit 1
fi
if [ $CONNECT_RC -ne 0 ]; then
  echo "FATAL: could not connect AS migrator with the generated credential (exit $CONNECT_RC) -- the handoff did not take effect end to end." >&2
  exit 1
fi
# Sec F-1b (PR #849 r2 review): match the psql output ROW exactly, not a
# substring of the WHOLE capture -- a bare `grep -qF "migrator"` is
# already satisfied by the prompt line itself ("Password for user
# migrator: "), so it could never fail independently of the prompt
# check above. Anchored to a whitespace-tolerant EXACT row match instead
# (psql's own column output pads with leading/trailing spaces).
if ! printf '%s' "$CONNECT_OUT" | grep -qE '^[[:space:]]*migrator[[:space:]]*$'; then
  echo "FATAL: connected but current_user did not echo back 'migrator' as its own output row." >&2
  exit 1
fi
echo "OK: connected AS migrator over a non-loopback, password-prompted path with the generated credential; current_user confirmed."

echo "== E. Sanity re-read (Sec VETO-1 r2 review) -- the store's CURRENT MIGRATOR_DB_PASSWORD must still hash-match the value the role was just set to; a mismatch means the store changed between leg A's read and now (e.g. a concurrent rotation), and the role would be set to a value that will NOT be what the next deploy's PROD_DB_URL reads =="
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
  echo "FATAL: the store's CURRENT MIGRATOR_DB_PASSWORD no longer hash-matches the value the migrator role was just set to (leg A's own read) -- it changed between the initial read and now. Refusing rather than reporting a false VERIFIED against a value the next deploy will not actually use." >&2
  exit 1
fi
echo "OK: the store's current MIGRATOR_DB_PASSWORD still hash-matches what the role was set to -- no drift between read and set (value never printed)."
REMOTE
ok "migrator: LOGIN + password set from pfin-migrator's own existing MIGRATOR_DB_PASSWORD (read, not minted); sanity re-read confirms no drift"

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
# ⚠ `</dev/null` is load-bearing, not cosmetic (Sec VETO-1, PR #854
# review, live-confirmed against team-lead's own 2026-09-21 run). This
# remote script is fed to `bash -s` on ssh's OWN stdin, and `docker
# compose exec -T` ATTACHES and DRAINS stdin -- without the redirect,
# THIS call eats the rest of this heredoc's bytes, bash hits EOF and
# exits 0, and the RC check + completion-line grep below silently never
# run. Measured live: realrun3.log never contains "Finished supabase db
# push" anywhere, yet the outer script's "ok migration sweep applied"
# line still printed -- the check that would have told a no-op apart
# from a genuinely failed push never executed at all.
set +e
OUT="$(docker compose --project-name "$MIGRATOR_UUID" exec -T migrator sh -c 'supabase db push --yes --db-url "$PROD_DB_URL" --workdir /workspace' </dev/null 2>&1)"
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
CENSUS_BAD="$(read_gate "ownership census" "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'pfin' and pg_get_userbyid(c.relowner) not in ('pfin_owner');")"
[[ "$CENSUS_BAD" =~ ^[0-9]+$ ]] || die2 "ownership census read returned unparseable output ('$CENSUS_BAD') -- refusing to guess; expected a non-negative integer."
[[ "$CENSUS_BAD" == "0" ]] || die "ownership census shows $CENSUS_BAD non-pfin_owner-owned pfin object(s) after Phase 2 -- the pair broke somewhere in the apply. Do NOT proceed to Phase 3/§7; do not paper over it with a manual ALTER ... OWNER TO."
ok "ownership census clean"
BOOTSTRAP_COMPLETE="$(read_gate "bootstrap_complete" "select exists(select 1 from supabase_migrations.schema_migrations where version = '118')::text;")"
[[ "$BOOTSTRAP_COMPLETE" == "true" || "$BOOTSTRAP_COMPLETE" == "false" ]] || die2 "bootstrap_complete read returned unparseable output ('$BOOTSTRAP_COMPLETE') -- refusing to guess; expected exactly 'true' or 'false'."
[[ "$BOOTSTRAP_COMPLETE" == "true" ]] || die "bootstrap_complete=false after Phase 2 (no ledger row for migration 118) -- the apply did not actually land 118. Investigate before Phase 3."
ok "bootstrap_complete = true"

step "Phase 3 (post-step, supabase_admin): post-step-vault-view.sql -- creates pfin.decrypted_source_credential, transfers to pfin_owner, asserts exactly one decrypt view (its own assertion IS the pass/fail signal, not re-implemented here)"
psql_admin_file "$REPO_ROOT/supabase/post-step-vault-view.sql" || die "supabase/post-step-vault-view.sql failed (its own assertion block is the failure signal -- see the output above for which leg)"
ok "post-step-vault-view.sql applied and self-asserted"

step "Done"
info "Phase 1 -> 2 -> 3 complete: bootstrap_complete=true, ownership census clean, decrypt view asserted by its own file. §6.1/§6.2 worker-role handoffs (scripts/db-role-handoff.sh) are the next step, unchanged."
exit 0
