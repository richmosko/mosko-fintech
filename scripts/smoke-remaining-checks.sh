#!/usr/bin/env bash
#
# smoke-remaining-checks.sh -- scripts the `remaining-checks` step of
# scripts/provision.sh (docs/archive/deployment-runbook-rationale-2026-09-20.md
# §10: CA-7 / TZ-1 / RLS isolation / auth login). BACKLOG.md §7.36 item 81.
# QA-owned (CA-7/TZ-1 mechanics consulted with DevOps per the item's own
# routing). Four legs, each independently verdicted, run against the LIVE
# production box -- never a scratch/CI database. READ-ONLY throughout: no
# leg inserts, updates, or deletes a single row (see each leg's own header
# for how it proves its claim without writing).
#
# WHY THIS EXISTS -- `run_remaining_checks()` in provision.sh used to
# `return 4` unconditionally with a comment naming all four checks as
# "entirely BY-HAND". F/CTO's standing directive: anything manual needs a
# VERY unavoidable reason, stated in the script's own output and header.
# This file scripts three of the four checks completely and the fourth
# (auth login) as far as it honestly can be scripted -- see LEG 4 below for
# exactly what remains by-hand and why.
#
# WHAT EACH LEG PROVES, MECHANISM BY MECHANISM
#
#   LEG 1 -- TZ-1 (database TimeZone pin read-back, §4.1; ship-block).
#     The canonical query is NEVER retyped here -- it is extracted LIVE
#     from docs/deployment-runbook.md §4.1 by re-using
#     scripts/ci/check-tz-sweep-identical.py's OWN extract_runbook()
#     function (imported as a module, not copy-pasted), the same function
#     that fence already uses to prove the runbook and (T3) in
#     supabase/tests/01_session_timezone.sql are token-identical. A third
#     hand-typed copy is exactly the drift class that fence exists to
#     prevent -- this script has zero copies of the SQL text; it borrows
#     the fence's own reader. The extracted query then runs, unmodified,
#     against the box's own `db` container as `supabase_admin` (the same
#     `docker compose ... exec -T db psql -U supabase_admin -d postgres
#     -tAc "..."` shape scripts/pgrst-exposure-gates.sh's psql_scalar()
#     already uses) -- a pure catalog read (pg_db_role_setting), zero
#     writes. Required: zero rows. A non-empty result prints the offending
#     role, same diagnostic intent as (T3)'s own is_empty() failure text.
#
#   LEG 2 -- CA-7 (Supabase datastore external-reachability negative smoke
#     + attached-network positive control, archive §10). Same shape as
#     scripts/smoke-admission-endpoint.sh's CA-2, different subject and
#     different mechanism for the non-HTTP legs:
#       NEGATIVE, from the OPERATOR's own machine (outside the Coolify
#       project network entirely): a raw TCP-connect probe against
#       $BOX_IP on 5432 (supavisor session)/6543 (supavisor
#       transaction)/8000 (api-gw) -- all three must refuse. The archive
#       text names `nmap -Pn -p 5432,6543,8000`; this script uses `nc -z
#       -w 5` instead -- DELIBERATE SUBSTITUTION, not a silent departure:
#       nmap's presence on the operator's own Mac is unmeasured, while BSD
#       netcat ships with macOS by default and is checked as an explicit
#       precondition (`command -v nc`) before any leg trusts a "closed"
#       result -- an absent probe binary must never silently read as "the
#       port is closed". Same connect-refused semantics either way.
#       Also confirms no Coolify Domain is assigned to the Supabase stack
#       app itself (api-gw/supavisor/db are services WITHIN one compose
#       application, not separate Coolify resources each with their own
#       fqdn -- one fqdn check covers all three, same N3 shape as CA-2).
#       POSITIVE, from a sibling container attached to the stack's own
#       Docker network (`pfin-app`, same attachment
#       smoke-pfin-exposure.sh already relies on): a `docker exec ... node
#       -e` one-liner (no `nc` dependency inside the container -- Node's
#       own `http`/`net` modules do the TCP-connect and HTTP-GET work,
#       avoiding an assumption about what's installed in a container this
#       script does not own) issues an HTTP GET to `api-gw:8000` (expects
#       a real numeric status, proving DNS + reachability -- this doubles
#       as the CA-4-style network-attachment assertion, same logic CA-2's
#       own P1 uses) and raw TCP connects to `supavisor:5432` and
#       `supavisor:6543` (expects both OPEN).
#
#   LEG 3 -- RLS isolation (ADR-011 surface; archive §10's "a seeded user
#     sees only their own rows" stub, restated as a PRODUCTION-SAFE,
#     READ-ONLY check). Production may hold zero real tenant rows, or it
#     may already hold real financial data:
#       - Every `pfin.*` table carrying a `users_id` column is discovered
#         LIVE from information_schema.columns (never a hand-maintained
#         list -- the B-1 dynamic-enumeration convention
#         scripts/pgrst-exposure-gates.sh already established).
#       - For each discovered table: `pg_class.relrowsecurity = true`
#         (RLS is ON), at least one `pg_policies` row exists for it (a
#         real policy is attached, not just the flag), and `anon` holds NO
#         SELECT grant on it (re-derived independently of
#         pgrst-exposure-gates.sh's own B-1 -- this step does not assume
#         B-1 already ran successfully earlier in the SAME provision.sh
#         invocation; verify live, never assume). These three hold
#         regardless of row count.
#       - THE BEHAVIORAL PROOF -- Sec F-1 correction (PR #869 review): a
#         bare "authenticated sees 0 rows" read is VACUOUS on a table that
#         holds zero rows to begin with -- it cannot distinguish
#         "correctly isolated" from "RLS switched off entirely on an
#         empty table", and a freshly-provisioned, pre-cutover box is
#         overwhelmingly likely to BE that empty-table state. Fixed by
#         pairing the zero-context read with a PRIVILEGED baseline count
#         (as `supabase_admin`, no `SET ROLE`) for the SAME tables, in the
#         SAME psql invocation (one SSH round trip, still entirely
#         read-only). Per table: connect as `authenticated` (`SET ROLE
#         authenticated` from the `supabase_admin` superuser session --
#         current_user becomes `authenticated`, which is neither the
#         table owner nor a superuser, so RLS enforces normally per
#         ordinary Postgres semantics) WITHOUT ever setting
#         `request.jwt.claims` -- exactly the shape a stolen/absent JWT
#         would produce. Every migration in this repo scopes its policies
#         `users_id = auth.uid()` (001_pfin_foundation.sql's own stated
#         convention), and `auth.uid()` returns NULL with no JWT claims
#         set, so `users_id = NULL` can never be true -- a table with
#         real rows and 0 visible under `authenticated` is PROVEN
#         isolated; a table with 0 real rows to begin with is
#         INCONCLUSIVE (nothing to isolate, says nothing either way); any
#         table where `authenticated` sees >0 rows is a live RLS bypass,
#         FAILED regardless of the others. If NO discovered table is ever
#         PROVEN (i.e. the whole set is empty), this leg reports SKIPPED,
#         not VERIFIED -- isolation is unproven, not proven absent; `reset
#         role` (Sec F-2) at the tail keeps the session's role-scope
#         explicit rather than incidental-because-the-connection-closes-
#         next.
#       - `service_role`'s own BYPASSRLS attribute is confirmed
#         structurally (`pg_roles.rolbypassrls`), matching the by-design
#         contrast every migration comment in this repo already states
#         (008_pfin_service_role_grants.sql: "service_role is BYPASSRLS,
#         ACL is checked independently"). Sec: the absence of a separate
#         `authenticated.rolbypassrls = false` assertion is not a gap --
#         if `authenticated` ever held BYPASSRLS the behavioral read above
#         would already FAIL loudly (it would see every row).
#     A pgTAP two-tenant INSERT-then-rollback battery (this repo's own
#     CI/local pattern) was considered and rejected here: even a rolled-
#     back write against PRODUCTION carries a different risk posture
#     (WAL, lock contention, connection-pool pressure under supavisor)
#     than an ephemeral CI/local database, and the team-lead brief this
#     script implements is explicit that this leg must be READ-ONLY.
#     Sec-reviewed and confirmed correct on this point (PR #869 review).
#
#   LEG 4 -- auth login (archive §10 stub). The app carries no public
#     domain until the `dns`/`cutover` steps run -- this leg detects that
#     and reports SKIPPED (exit 3) rather than pretending to have checked
#     anything. Once a domain exists, it exercises everything that can be
#     exercised without creating a real account or sending a real
#     production email:
#       - GET /login -> expect 200 (the page renders).
#       - POST /signup with a body MISSING the required `password` field,
#         `Origin: https://<domain>` set explicitly (SvelteKit's built-in
#         CSRF guard 403s a cross-origin-looking POST before the route's
#         own Zod validation ever runs -- setting Origin to the app's own
#         domain is what lets this probe reach the real fail(400) path
#         instead of being rejected one layer earlier) -> expect 400. This
#         proves the endpoint is live and its `.strict()` validation
#         fires, WITHOUT ever calling `signUp` with a valid credential
#         pair -- no real auth.users row, no real confirmation email, no
#         Resend quota spent by this leg.
#       - A Resend send-acceptance probe, SEPARATELY: reads
#         `GOTRUE_SMTP_PASS`/`GOTRUE_SMTP_ADMIN_EMAIL` from the Supabase
#         stack's own `auth` (GoTrue) container env -- filtered ON THE BOX
#         inside the remote command string, same hygiene boundary
#         scripts/pgrst-schemas-live-check.sh already documents, never
#         crossing back to the operator's machine -- and, if present,
#         issues one real Resend API send to `delivered@resend.dev`,
#         Resend's own documented test address that accepts a send
#         without actually delivering it or counting against normal
#         quota the way a real recipient would. `SMTP_PASS` is
#         DELIBERATELY unset on a fresh stand-up (infra/supabase/README.md
#         says so explicitly -- "needs a secrets-manifest.yml decision
#         before it's wired up") -- this leg treats that absence as
#         informational, not a failure.
#       - ⚠ THE EMAIL-CONFIRMATION ROUND-TRIP ITSELF -- following the
#         link a real confirmation email carries and confirming the
#         session actually establishes -- IS NOT SCRIPTED, and there is
#         no honest way to script it from here: it requires reading an
#         arbitrary recipient's real inbox, which no credential this repo
#         holds grants access to, and manufacturing one would mean
#         creating a real account against production on every run. This
#         is the ONE genuinely unavoidable manual moment this script
#         reports (MANUAL, exit 4) once a domain exists, EVEN when every
#         automatable sub-check above passes -- see docs/deployment-
#         runbook.md's own unavoidable-manual list, updated in the same
#         PR that added this script.
#
# EXIT CODES (provision.sh's own step vocabulary, NOT the 0/1/2/3 shape
# scripts/smoke-admission-endpoint.sh / scripts/smoke-etl-poll.sh use --
# this script wraps a step that is still PARTLY manual by design, so it
# needs the richer 4-way split provision.sh's registry already speaks):
#   0  VERIFIED -- all four legs fully verified.
#   3  SKIPPED  -- no leg failed, but at least one is not yet attemptable
#      (auth-login before a domain exists is the only case today) --
#      non-fatal, re-run once the precondition clears.
#   4  MANUAL   -- no leg failed and none is merely skipped, but at least
#      one requires a by-hand step to fully close (auth-login's email-
#      confirmation round-trip, once a domain exists) -- this is a CEILING
#      this script can never rise above while that round-trip remains
#      unscriptable, by design, not a bug to chase.
#   else FAILED -- a real finding in any leg (TZ-1 drift, a CA-7 exposure,
#      an RLS gap, a wrong HTTP status), OR a precondition this script
#      could not even attempt under (box/stack/sibling unreachable, the
#      TZ-1 extraction failed, `nc` missing locally). Overall priority
#      when legs disagree: FAILED > MANUAL > SKIPPED > VERIFIED -- any
#      real finding trumps everything; a remaining hand step trumps a
#      mere skip; a skip trumps full success.
#
# USAGE
#   BOX_IP=<box-ip> scripts/smoke-remaining-checks.sh
#
#   Same invocation convention as scripts/smoke-admission-endpoint.sh /
#   scripts/smoke-etl-poll.sh -- BOX_IP is required, never defaulted, read
#   from the caller's environment (provision.sh's require_box_ip(), or the
#   operator's own `BOX_IP=$(grep '^BOX_IP=' .env | cut -d= -f2-)` when run
#   standalone). STACK_APP_NAME (default pfin-supabase-stack) and
#   SIBLING_APP_NAME (default pfin-app) are env-var-overridable, same
#   discipline as every other scripts/smoke-*.sh.
#
# ORCHESTRATOR CONTRACT (provision.sh's `remaining-checks` step calls this
# directly): non-interactive, no prompts, no `read`. Pure read/probe
# outside the two documented exceptions in LEG 4 (the malformed-signup
# POST and the Resend test-address send, neither of which creates state
# this repo's own data model tracks), safe to re-run any number of times.
# Every fact used is resolved LIVE each run -- nothing cached from a prior
# invocation.

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

BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
STACK_APP_NAME="${STACK_APP_NAME:-pfin-supabase-stack}"
SIBLING_APP_NAME="${SIBLING_APP_NAME:-pfin-app}"
COMPOSE_SERVICE="${COMPOSE_SERVICE:-app}"

# RLS_DENY_ALL_EXPECTED -- LEG 3's allowlist for tables where RLS is ON,
# 0 policies exist in pg_policies, and default-deny (Postgres's own
# ordinary RLS semantics -- no policy means no row matches, for any
# non-BYPASSRLS role) is the RATIFIED posture (Sec ruling, real-run 23
# close-out, 2026-09-22), not a coverage gap -- each is service_role-only
# by design, and a users_id policy on any of them would WEAKEN posture:
#   audit_log                 -- 111_audit_log.sql:622/628 (RLS enabled,
#                                 zero policies, zero grants; the only
#                                 write path is fn_emit_audit_log,
#                                 SECURITY DEFINER at :936); adding an
#                                 authenticated read policy ENDS the aal2
#                                 step-up exemption stated at :511-514.
#   mfa_recovery_code          -- 026_mfa_recovery_code.sql:197/204,
#                                 column-scoped grants at :176-178.
#   mfa_recovery_attempt       -- 027_mfa_recovery_attempt.sql:169/175.
#   linked_source_sync_audit   -- 015_linked_source_fold.sql:487/626,
#                                 025_aal2_step_up_backstop.sql:180-182.
# GROWS ONLY BY MIGRATION (mirrors 111_audit_log.sql:505's own
# convention for surface_name) -- a fifth table is never added here
# without a new migration establishing the same service_role-only
# design and a fresh Sec review; a table Sec later rules a real gap on
# is REMOVED so this leg FAILS on it again. A table that later gains a
# real policy moves out of DENY-ALL on its own (reported INFO, not
# removed by hand -- see LEG 3 below). Sec requirement (real-run 23
# close-out): a table with 0 policies NOT on this list is FAILED
# unconditionally -- never a generic "0 policies + authenticated sees 0
# rows => DENY-ALL" rule, which would bless a forgotten policy.
RLS_DENY_ALL_EXPECTED=(audit_log linked_source_sync_audit mfa_recovery_attempt mfa_recovery_code)

is_deny_all_expected() {
  local t="$1" x
  for x in "${RLS_DENY_ALL_EXPECTED[@]}"; do
    [[ "$x" == "$t" ]] && return 0
  done
  return 1
}

die()   { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
ok()    { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info()  { printf '      %s\n' "$*"; }
warn()  { printf '\033[33m WARN\033[0m  %s\n' "$*" >&2; }
step()  { printf '\n\033[1m%s\033[0m\n' "$*"; }

for arg in "$@"; do
  case "$arg" in
    *) echo "unknown flag: $arg" >&2; echo "usage: $0 (read-only, no flags -- BOX_IP env var required)" >&2; exit 1 ;;
  esac
done

[[ -n "$BOX_IP" ]] || die "BOX_IP is required, not defaulted -- set it explicitly (same discipline as every other scripts/smoke-*.sh / provision-*.sh)."

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }

sshx true >/dev/null 2>&1 || die "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

# Same api()/-K- shape as every sibling script -- token on curl's stdin
# config, never argv.
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

resolve_app() {
  # resolve_app <name> -- prints "<uuid>\n<fqdn>". Same shape as every
  # sibling smoke's own resolve_app().
  local query="$1"
  local uuid_re='^[a-z0-9]{20,32}$'
  local mode="name"
  [[ "$query" =~ $uuid_re ]] && mode="uuid"
  local query_env
  query_env="app_query=$(printf '%q' "$query")"
  sshx "env $query_env bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "\$app_query" "$mode" <<'PYEOF'
$PY_API_HELPER
import sys
token, query, mode = sys.argv[1], sys.argv[2], sys.argv[3]
apps = api(token, "GET", "/applications")
field = "uuid" if mode == "uuid" else "name"
matches = [a for a in apps if a.get(field) == query]
if len(matches) != 1:
    die(f"expected exactly one application matching {field}='{query}', found {len(matches)}")
a = matches[0]
print(a["uuid"])
print(a.get("fqdn") or "")
print(a.get("docker_compose_domains") or "")
PYEOF
REMOTE
}

step "Resolving '$STACK_APP_NAME' and '$SIBLING_APP_NAME'"
STACK_RESOLVED="$(resolve_app "$STACK_APP_NAME")" || die "could not resolve '$STACK_APP_NAME'"
STACK_UUID="$(sed -n 1p <<<"$STACK_RESOLVED")"
STACK_FQDN="$(sed -n 2p <<<"$STACK_RESOLVED")"
ok "resolved '$STACK_APP_NAME' -> $STACK_UUID"
SIBLING_RESOLVED="$(resolve_app "$SIBLING_APP_NAME")" || die "could not resolve '$SIBLING_APP_NAME'"
SIBLING_UUID="$(sed -n 1p <<<"$SIBLING_RESOLVED")"
SIBLING_FQDN="$(sed -n 2p <<<"$SIBLING_RESOLVED")"
SIBLING_COMPOSE_DOMAINS="$(sed -n 3p <<<"$SIBLING_RESOLVED")"
ok "resolved '$SIBLING_APP_NAME' -> $SIBLING_UUID (fqdn: ${SIBLING_FQDN:-<none>}, docker_compose_domains: ${SIBLING_COMPOSE_DOMAINS:-<none>})"

find_running_container() {
  # find_running_container <project-uuid> <compose-service> -- prints the
  # container id, refuses on 0 or >1 running matches (Sec F4 discipline,
  # same as every sibling smoke).
  local uuid="$1" svc="$2"
  local list
  list="$(sshx "docker compose --project-name $uuid ps -q $svc | xargs -r -I{} docker inspect --format '{{.State.Running}}{{\"\\t\"}}{{.Id}}{{\"\\t\"}}{{.Created}}' {} | awk -F'\t' '\$1==\"true\"{print \$2\"\t\"\$3}'")"
  [[ -n "$list" ]] || return 1
  local count
  count="$(printf '%s\n' "$list" | grep -c .)"
  if [[ "$count" -ne 1 ]]; then
    echo "AMBIGUOUS: $count running containers match compose service '$svc' under project '$uuid':" >&2
    echo "$list" >&2
    return 2
  fi
  awk -F'\t' '{print $1}' <<<"$list"
}

psql_admin() {
  # psql_admin <query> -- docker compose exec -T db psql -U supabase_admin
  # -d postgres -tAc "<query>" </dev/null against the STACK's own `db`
  # container. Same shape as scripts/pgrst-exposure-gates.sh's own
  # psql_scalar(). `</dev/null` unconditionally (fence-heredoc-stdin-
  # drain.sh discipline).
  sshx "env STACK_UUID=\"$STACK_UUID\" bash -s" <<REMOTE
set -e
docker compose --project-name "\$STACK_UUID" exec -T db psql -U supabase_admin -d postgres -tAc "$1" </dev/null
REMOTE
}

# =====================================================================
# LEG 1 -- TZ-1
# =====================================================================
step "Leg 1/4 -- TZ-1: database TimeZone pin read-back (docs/deployment-runbook.md §4.1)"
TZ1_STATUS="VERIFIED"
TZ1_MSG=""

set +e
TZ1_QUERY="$(python3 - "$REPO_ROOT" <<'PYEOF'
import importlib.util, sys
repo_root = sys.argv[1]
spec = importlib.util.spec_from_file_location(
    "tzsweep", f"{repo_root}/scripts/ci/check-tz-sweep-identical.py"
)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
runbook_path = f"{repo_root}/docs/deployment-runbook.md"
text = mod.read(runbook_path)
query = mod.extract_runbook(text, runbook_path)
sys.stdout.write(query)
PYEOF
)"
TZ1_EXTRACT_RC=$?
set -e

if [[ $TZ1_EXTRACT_RC -ne 0 || -z "$TZ1_QUERY" ]]; then
  TZ1_STATUS="FAILED"
  TZ1_MSG="could not extract the TZ-1 query LIVE from docs/deployment-runbook.md §4.1 via scripts/ci/check-tz-sweep-identical.py's own extract_runbook() (rc=$TZ1_EXTRACT_RC) -- the runbook's psql anchor may have moved. Investigate that fence's RUNBOOK_ANCHOR before treating this as anything else; this leg refuses to retype the query as a fallback."
elif [[ "$TZ1_QUERY" == *'"'* || "$TZ1_QUERY" == *'`'* ]]; then
  TZ1_STATUS="FAILED"
  TZ1_MSG="the extracted TZ-1 query contains a double-quote or backtick -- refusing to interpolate it into a remote psql -tAc double-quoted argument unescaped. The runbook §4.1 block's shape has likely changed in a way this leg's interpolation was never built to handle."
else
  set +e
  TZ1_ROWS="$(psql_admin "$TZ1_QUERY")"
  TZ1_RC=$?
  set -e
  if [[ $TZ1_RC -ne 0 ]]; then
    TZ1_STATUS="FAILED"
    TZ1_MSG="could not run the TZ-1 query against $STACK_APP_NAME's own db container (rc=$TZ1_RC) -- box/stack/db-container precondition, not a TimeZone finding."
  elif [[ -n "$TZ1_ROWS" ]]; then
    TZ1_STATUS="FAILED"
    TZ1_MSG="TZ-1: one or more roles carry a TimeZone override in pg_db_role_setting -- runbook §4.1's own remediation applies ('alter role <role> reset timezone'). Offending row(s):
$TZ1_ROWS"
  fi
fi

if [[ "$TZ1_STATUS" == "VERIFIED" ]]; then
  ok "TZ-1: zero roles carry a TimeZone override -- the 061 database-level UTC pin is unshadowed"
else
  warn "TZ-1: $TZ1_MSG"
fi

# =====================================================================
# LEG 2 -- CA-7
# =====================================================================
step "Leg 2/4 -- CA-7: Supabase datastore (api-gw/supavisor) external-reachability negative smoke + attached-network positive control"
CA7_STATUS="VERIFIED"
CA7_MSGS=()

if ! command -v nc >/dev/null 2>&1; then
  CA7_STATUS="FAILED"
  CA7_MSGS+=("nc (netcat) not found on the operator's own machine -- required for the N1 negative TCP-connect probe on 5432/6543/8000. This repo assumes BSD netcat ships with macOS by default; an absent probe binary must never silently read as 'the port is closed'. Install one before re-running this leg.")
else
  for port in 5432 6543 8000; do
    if nc -z -w 5 "$BOX_IP" "$port" >/dev/null 2>&1; then
      CA7_STATUS="FAILED"
      CA7_MSGS+=("N1: port $port on $BOX_IP is OPEN from the operator's own machine -- a real external-reachability exposure of the Supabase datastore. Escalate immediately, do not re-run and hope.")
    else
      info "N1: $BOX_IP:$port -> closed/refused (as expected)"
    fi
  done
fi

if [[ -n "$STACK_FQDN" ]]; then
  CA7_STATUS="FAILED"
  CA7_MSGS+=("$STACK_APP_NAME carries a live fqdn ('$STACK_FQDN') -- a Domain IS assigned to the Supabase stack app. Escalate, do not re-run and hope.")
else
  info "no Coolify Domain assigned to $STACK_APP_NAME"
fi

CA7_CONTAINER=""
set +e
CA7_CONTAINER="$(find_running_container "$SIBLING_UUID" "$COMPOSE_SERVICE")"
CA7_FIND_RC=$?
set -e
if [[ $CA7_FIND_RC -ne 0 ]]; then
  CA7_STATUS="FAILED"
  CA7_MSGS+=("could not find exactly one running '$COMPOSE_SERVICE' container under '$SIBLING_APP_NAME' for the positive control (rc=$CA7_FIND_RC) -- is the app deployed? remaining-checks runs after deploy-app/deploy-workers in the registry, so this should already be true.")
else
  CA7_NODE_ONE_LINER='
const http = require("http");
const net = require("net");
function httpProbe() {
  return new Promise((resolve) => {
    const r = http.request({ host: "api-gw", port: 8000, path: "/auth/v1/health", method: "GET" }, (res) => {
      res.on("data", () => {});
      res.on("end", () => resolve(String(res.statusCode)));
    });
    r.on("error", () => resolve("000"));
    r.end();
  });
}
function tcpProbe(host, port) {
  return new Promise((resolve) => {
    const s = net.createConnection({ host, port, timeout: 5000 });
    s.on("connect", () => { s.destroy(); resolve("OPEN"); });
    s.on("timeout", () => { s.destroy(); resolve("TIMEOUT"); });
    s.on("error", () => resolve("ERROR"));
  });
}
(async () => {
  const gw = await httpProbe();
  const p1 = await tcpProbe("supavisor", 5432);
  const p2 = await tcpProbe("supavisor", 6543);
  console.log(gw + " " + p1 + " " + p2);
})();
'
  set +e
  CA7_RESULT="$(sshx "docker exec $CA7_CONTAINER node -e $(printf '%q' "$CA7_NODE_ONE_LINER")" </dev/null)"
  CA7_NODE_RC=$?
  set -e
  if [[ $CA7_NODE_RC -ne 0 || -z "$CA7_RESULT" ]]; then
    CA7_STATUS="FAILED"
    CA7_MSGS+=("the positive-control node probe inside '$SIBLING_APP_NAME' ($CA7_CONTAINER) exited $CA7_NODE_RC with no usable output.")
  else
    CA7_GW="$(awk '{print $1}' <<<"$CA7_RESULT")"
    CA7_P1="$(awk '{print $2}' <<<"$CA7_RESULT")"
    CA7_P2="$(awk '{print $3}' <<<"$CA7_RESULT")"
    info "positive control: api-gw:8000=$CA7_GW supavisor:5432=$CA7_P1 supavisor:6543=$CA7_P2"
    if [[ "$CA7_GW" == "000" ]]; then
      CA7_STATUS="FAILED"
      CA7_MSGS+=("P: GET api-gw:8000/auth/v1/health from '$SIBLING_APP_NAME' got no response -- either not attached to the Supabase stack's Docker network (CA-4 shape), or api-gw is down.")
    fi
    if [[ "$CA7_P1" != "OPEN" ]]; then
      CA7_STATUS="FAILED"
      CA7_MSGS+=("P: TCP connect to supavisor:5432 from '$SIBLING_APP_NAME' -> $CA7_P1, expected OPEN.")
    fi
    if [[ "$CA7_P2" != "OPEN" ]]; then
      CA7_STATUS="FAILED"
      CA7_MSGS+=("P: TCP connect to supavisor:6543 from '$SIBLING_APP_NAME' -> $CA7_P2, expected OPEN.")
    fi
  fi
fi

if [[ "$CA7_STATUS" == "VERIFIED" ]]; then
  ok "CA-7: api-gw/supavisor unreachable from outside the private network; reachable, correctly, from a sibling container on the stack's own network"
else
  for m in "${CA7_MSGS[@]}"; do warn "CA-7: $m"; done
fi

# =====================================================================
# LEG 3 -- RLS isolation (ADR-011 surface -- flagged for Sec design review)
# =====================================================================
step "Leg 3/4 -- RLS isolation: anon/authenticated/service_role visibility shape (ADR-011)"
RLS_STATUS="VERIFIED"
RLS_MSGS=()

RLS_ENUM_QUERY="select c.relname, c.relrowsecurity::text, (select count(*) from pg_policies p where p.schemaname = n.nspname and p.tablename = c.relname)::text, has_table_privilege('anon', c.oid, 'SELECT')::text from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'pfin' and c.relkind in ('r','p') and exists (select 1 from information_schema.columns col where col.table_schema = 'pfin' and col.table_name = c.relname and col.column_name = 'users_id') order by c.relname;"

set +e
RLS_ENUM="$(psql_admin "$RLS_ENUM_QUERY")"
RLS_ENUM_RC=$?
set -e

if [[ $RLS_ENUM_RC -ne 0 ]]; then
  RLS_STATUS="FAILED"
  RLS_MSGS+=("could not enumerate users_id-bearing pfin tables (rc=$RLS_ENUM_RC) -- precondition, not an RLS finding.")
elif [[ -z "$RLS_ENUM" ]]; then
  # Invariance-is-blindness: an empty discovered-table set must FAIL
  # closed, never read as "0 tables, vacuously fine" (memory:
  # feedback_not_null_no_default_column_forces_whole_tree_sweep and
  # feedback_count_distinct_silently_drops_null -- same family of trap).
  RLS_STATUS="FAILED"
  RLS_MSGS+=("zero pfin tables with a users_id column were discovered -- this cannot be right for a stack running these migrations. The enumeration query itself is almost certainly broken; treating an empty result as a pass would be exactly the invariance-is-blindness failure this repo's own testing discipline forbids.")
else
  TABLES=()
  ALLOWLIST_CANDIDATES=()
  while IFS='|' read -r tbl rls polcount anonsel; do
    [[ -z "$tbl" ]] && continue
    if [[ ! "$tbl" =~ ^[a-z_][a-z0-9_]*$ ]]; then
      RLS_STATUS="FAILED"
      RLS_MSGS+=("discovered table name '$tbl' does not match the expected identifier shape -- refusing to interpolate it into a dynamic query.")
      continue
    fi
    TABLES+=("$tbl")
    if [[ "$rls" != "true" ]]; then
      RLS_STATUS="FAILED"
      RLS_MSGS+=("pfin.$tbl: relrowsecurity=$rls, expected true -- RLS is not enabled on a table carrying users_id.")
    fi
    if [[ "$anonsel" != "false" ]]; then
      RLS_STATUS="FAILED"
      RLS_MSGS+=("pfin.$tbl: anon holds SELECT (has_table_privilege=$anonsel) -- anon must hold no grant on any pfin relation.")
    fi
    # Sec ruling (real-run 23 close-out, 2026-09-22): 0 policies is
    # FAILED for any table not on RLS_DENY_ALL_EXPECTED, unconditionally
    # -- never a generic "0 policies + authenticated sees 0 rows =>
    # DENY-ALL" rule, which would bless a forgotten policy on a table
    # that was never meant to be service_role-only. This decision does
    # not wait on, and is never rescued by, the behavioral read below.
    if [[ "$polcount" -lt 1 ]]; then
      if is_deny_all_expected "$tbl"; then
        ALLOWLIST_CANDIDATES+=("$tbl")
      else
        RLS_STATUS="FAILED"
        RLS_MSGS+=("pfin.$tbl: 0 policies in pg_policies and NOT in RLS_DENY_ALL_EXPECTED -- either this is a real policy-coverage gap (add a policy), or it is meant to be service_role-only and Sec needs to rule so it can be added to the allowlist by migration. Treating as FAILED until then.")
      fi
    fi
  done <<<"$RLS_ENUM"
  info "discovered ${#TABLES[@]} users_id-bearing pfin table(s): ${TABLES[*]}"

  if [[ "$RLS_STATUS" == "VERIFIED" ]]; then
    # Sec F-1 (PR #869 review): a bare "authenticated sees 0 rows" read is
    # VACUOUS on a table that holds zero rows to begin with -- it cannot
    # distinguish "correctly isolated" from "RLS switched off entirely on
    # an empty table", and a freshly-provisioned, pre-cutover box is
    # overwhelmingly likely to BE that empty-table state, not an edge
    # case. Fixed by pairing the zero-context read with a PRIVILEGED
    # baseline count (as supabase_admin, no SET ROLE) for the SAME
    # tables, in the SAME psql invocation -- one SSH round trip, still
    # entirely read-only. Per table: priv>0 and auth=0 -> PROVEN
    # (isolation actually demonstrated); priv=0 -> INCONCLUSIVE (nothing
    # to isolate, this table says nothing either way); auth>0 -> FAILED
    # regardless of priv (unchanged -- a live bypass is a live bypass).
    # If NO table is ever PROVEN, this leg refuses to report VERIFIED --
    # SKIPPED, naming why, same shape smoke-etl-poll.sh already uses for
    # "zero active tenants, nothing to check yet".
    #
    # Sec F-2: `reset role` at the tail -- the statements between the SET
    # ROLE and the end of THIS session are the thing to control; explicit,
    # not incidental-because-the-connection-happens-to-close-next.
    PRIV_SQL=""
    first=1
    for t in "${TABLES[@]}"; do
      if [[ $first -eq 1 ]]; then PRIV_SQL="select 'PRIV' as ctx, '$t' as t, count(*) as n from pfin.\"$t\""; first=0
      else PRIV_SQL="$PRIV_SQL union all select 'PRIV', '$t', count(*) from pfin.\"$t\""; fi
    done
    # GRANT_SQL -- Sec requirement (real-run 23 close-out): for every
    # DENY-ALL allowlist candidate (0-policy, allowlisted -- non-
    # allowlisted 0-policy tables already FAILED above and never reach
    # here), assert the FULL conjunction, not just anon's table-level
    # grant (already checked above): authenticated must hold NO
    # table-level SELECT either, and NEITHER anon NOR authenticated may
    # hold ANY column-level grant (information_schema.column_privileges
    # -- 026_mfa_recovery_code.sql:222 uses column-scoped grants, so a
    # column-level leak is a real, distinct risk from a table-level one).
    # Runs as supabase_admin (before the role switch below) -- a
    # superuser sees every grant in information_schema regardless of who
    # granted it.
    GRANT_SQL=""
    if [[ "${#ALLOWLIST_CANDIDATES[@]}" -gt 0 ]]; then
      first=1
      for t in "${ALLOWLIST_CANDIDATES[@]}"; do
        seg="select 'COLGRANT' as ctx, '$t' as t, (select count(*) from information_schema.column_privileges cp where cp.table_schema = 'pfin' and cp.table_name = '$t' and cp.grantee in ('anon','authenticated'))::text as n
union all select 'AUTHTBL', '$t', has_table_privilege('authenticated', 'pfin.\"$t\"'::regclass, 'SELECT')::text"
        if [[ $first -eq 1 ]]; then GRANT_SQL="$seg"; first=0
        else GRANT_SQL="$GRANT_SQL
union all $seg"; fi
      done
    fi
    AUTH_SQL=""
    first=1
    for t in "${TABLES[@]}"; do
      if [[ $first -eq 1 ]]; then AUTH_SQL="select 'AUTH' as ctx, '$t' as t, count(*) as n from pfin.\"$t\""; first=0
      else AUTH_SQL="$AUTH_SQL union all select 'AUTH', '$t', count(*) from pfin.\"$t\""; fi
    done
    ZERO_CTX_QUERY="$PRIV_SQL"
    if [[ -n "$GRANT_SQL" ]]; then
      ZERO_CTX_QUERY="$ZERO_CTX_QUERY; $GRANT_SQL"
    fi
    ZERO_CTX_QUERY="$ZERO_CTX_QUERY; set role authenticated; $AUTH_SQL; reset role;"
    set +e
    ZERO_CTX_OUT="$(psql_admin "$ZERO_CTX_QUERY")"
    ZERO_CTX_RC=$?
    set -e
    if [[ $ZERO_CTX_RC -ne 0 ]]; then
      RLS_STATUS="FAILED"
      RLS_MSGS+=("the privileged-baseline / zero-JWT-context 'authenticated' row-count read failed (rc=$ZERO_CTX_RC) -- precondition (e.g. supabase_admin cannot SET ROLE authenticated), not an isolation finding.")
    else
      # bash 3.2 (macOS operator shell): no associative arrays (`declare
      # -A` is a bash 4+ builtin option this repo's own provision.sh
      # header already states as off-limits -- "parallel arrays, no
      # assoc arrays"). Per-table lookup via a plain string match on the
      # "CTX|table|count" output instead of a hash map.
      PROVEN_COUNT=0
      INCONCLUSIVE_COUNT=0
      DENY_ALL_COUNT=0
      for t in "${TABLES[@]}"; do
        p="$(printf '%s\n' "$ZERO_CTX_OUT" | awk -F'|' -v t="$t" '$1=="PRIV" && $2==t {print $3; exit}')"
        a="$(printf '%s\n' "$ZERO_CTX_OUT" | awk -F'|' -v t="$t" '$1=="AUTH" && $2==t {print $3; exit}')"
        polcount="$(printf '%s\n' "$RLS_ENUM" | awk -F'|' -v t="$t" '$1==t {print $3; exit}')"
        if [[ -z "$p" || -z "$a" ]]; then
          RLS_STATUS="FAILED"
          RLS_MSGS+=("pfin.$t: missing a privileged or authenticated row-count reading in the combined query output -- precondition, treat as unverified.")
          continue
        fi
        if [[ "$a" != "0" ]]; then
          RLS_STATUS="FAILED"
          RLS_MSGS+=("pfin.$t: $a row(s) visible to a session with NO tenant identity established (SET ROLE authenticated, no request.jwt.claims) -- expected 0. This is a live RLS bypass, not a fixture artifact.")
          continue
        fi
        if [[ "$polcount" -ge 1 ]]; then
          # POLICY-SCOPED -- at least one real pg_policies row.
          if is_deny_all_expected "$t"; then
            info "pfin.$t: in RLS_DENY_ALL_EXPECTED but carries $polcount polic(ies) now -- POLICY-SCOPED, not DENY-ALL any more (INFO, not a failure; consider removing it from the allowlist once Sec confirms)."
          fi
          if [[ "$p" -gt 0 ]]; then
            PROVEN_COUNT=$((PROVEN_COUNT + 1))
          else
            INCONCLUSIVE_COUNT=$((INCONCLUSIVE_COUNT + 1))
          fi
        else
          # 0-policy table -- the enumeration loop above already FAILED
          # and left this whole block for any table not in
          # RLS_DENY_ALL_EXPECTED, so reaching here means $t IS
          # allowlisted. Defensive re-check anyway (fail closed on a
          # future logic change; never trust "should be unreachable").
          if ! is_deny_all_expected "$t"; then
            RLS_STATUS="FAILED"
            RLS_MSGS+=("pfin.$t: INTERNAL: reached DENY-ALL verification with 0 policies but is NOT in RLS_DENY_ALL_EXPECTED -- this should be unreachable (the enumeration loop should have failed it already). Treating as FAILED, not a pass.")
            continue
          fi
          # Sec requirement (real-run 23 close-out): assert the FULL
          # conjunction before crediting isolation -- RLS on (checked),
          # 0 policies (checked), anon zero table-grant (checked), PLUS
          # authenticated zero table-grant and zero column-level grants
          # for either role (GRANT_SQL above).
          colgrant="$(printf '%s\n' "$ZERO_CTX_OUT" | awk -F'|' -v t="$t" '$1=="COLGRANT" && $2==t {print $3; exit}')"
          authtbl="$(printf '%s\n' "$ZERO_CTX_OUT" | awk -F'|' -v t="$t" '$1=="AUTHTBL" && $2==t {print $3; exit}')"
          if [[ -z "$colgrant" || -z "$authtbl" ]]; then
            RLS_STATUS="FAILED"
            RLS_MSGS+=("pfin.$t: missing a column-grant or authenticated-table-grant reading in the combined query output -- precondition, treat as unverified.")
            continue
          fi
          if [[ "$authtbl" != "false" ]]; then
            RLS_STATUS="FAILED"
            RLS_MSGS+=("pfin.$t: DENY-ALL-allowlisted but authenticated holds table-level SELECT (has_table_privilege=$authtbl) -- the service_role-only design this table's own migration documents requires zero authenticated grant, not just zero anon grant.")
            continue
          fi
          if [[ "$colgrant" != "0" ]]; then
            RLS_STATUS="FAILED"
            RLS_MSGS+=("pfin.$t: DENY-ALL-allowlisted but $colgrant column-level grant(s) to anon/authenticated exist in information_schema.column_privileges -- a column-scoped grant (this table's own migration uses column-scoped grants for service_role) must never extend to anon/authenticated.")
            continue
          fi
          # Structural conjunction holds (RLS on, 0 policies, anon+
          # authenticated zero grant at table AND column level). The
          # behavioral half (authenticated sees 0 of >0 real rows) only
          # PROVES anything when the privileged baseline is non-zero
          # (Sec requirement 4) -- on an empty table the structural
          # conjunction is VERIFIED but the row observation is
          # INCONCLUSIVE, never reported as DENY-ALL fully demonstrated.
          DENY_ALL_COUNT=$((DENY_ALL_COUNT + 1))
          if [[ "$p" -gt 0 ]]; then
            info "DENY-ALL: pfin.$t -- structural conjunction verified (RLS on, 0 policies, anon+authenticated zero grant at table+column level) AND authenticated sees 0 of $p row(s) visible to supabase_admin -- ALLOWLISTED, isolation demonstrated."
            PROVEN_COUNT=$((PROVEN_COUNT + 1))
          else
            info "DENY-ALL: pfin.$t -- structural conjunction verified (RLS on, 0 policies, anon+authenticated zero grant at table+column level); row observation INCONCLUSIVE (privileged count is 0 too -- nothing to isolate, never reported as DENY-ALL fully demonstrated on an empty table)."
            INCONCLUSIVE_COUNT=$((INCONCLUSIVE_COUNT + 1))
          fi
        fi
      done
      if [[ "$RLS_STATUS" == "VERIFIED" ]]; then
        if [[ "$PROVEN_COUNT" -eq 0 ]]; then
          RLS_STATUS="SKIPPED"
          RLS_MSGS+=("every discovered table holds zero rows -- no rows exist to be isolated, so isolation is UNPROVEN, not proven absent. RLS-enabled/anon-zero-grant all checked structurally and hold; the behavioral zero-context read has nothing to demonstrate on an empty table. Re-run once at least one table holds real (or synthetic-but-real) tenant data.")
        else
          ok "RLS: every discovered table -- RLS on, anon zero-grant; $PROVEN_COUNT table(s) PROVEN isolated ($DENY_ALL_COUNT via allowlisted DENY-ALL, $((PROVEN_COUNT - DENY_ALL_COUNT)) via >=1 policy), $INCONCLUSIVE_COUNT table(s) INCONCLUSIVE (empty, nothing to isolate)"
        fi
      fi
    fi
  fi

  set +e
  BYPASS_OUT="$(psql_admin "select rolbypassrls::text from pg_roles where rolname = 'service_role';")"
  BYPASS_RC=$?
  set -e
  if [[ $BYPASS_RC -ne 0 ]]; then
    RLS_STATUS="FAILED"
    RLS_MSGS+=("could not read pg_roles.rolbypassrls for service_role (rc=$BYPASS_RC).")
  elif [[ "$(tr -d ' \n' <<<"$BYPASS_OUT")" != "true" ]]; then
    RLS_STATUS="FAILED"
    RLS_MSGS+=("service_role.rolbypassrls != true (got '$BYPASS_OUT') -- the by-design BYPASSRLS contrast this repo's own migrations document is no longer true.")
  else
    info "service_role.rolbypassrls = true (by design)"
  fi
fi

if [[ "$RLS_STATUS" != "VERIFIED" ]]; then
  for m in "${RLS_MSGS[@]}"; do warn "RLS: $m"; done
fi

# derive_auth_host <docker_compose_domains raw string> <fqdn> <compose
# service> -- LEG 4's own host-derivation step, corrected 2026-09-22 (run
# 23): resolve_app()'s `fqdn` alone is Coolify's own default sslip.io URL
# on this box (COOLIFY-FACT-04) once a real domain is assigned via
# docker_compose_domains instead -- the OLD code built `https://$fqdn`
# against a value that was ALREADY a full `http://...` URL, and never
# looked at docker_compose_domains at all. Prints exactly two lines on
# success ("<host>" then "<source>", source one of
# docker_compose_domains/fqdn), or "REFUSED\n<reason>" / "NONE\n<empty>"
# otherwise. normalize_domains() below is copied VERBATIM from
# scripts/assign-app-domain.sh's own function of the same name
# (COOLIFY-FACT-15 measured shape: the field reads back as a JSON STRING
# whose own content is a JSON OBJECT keyed by compose service name) --
# this repo's own sibling-script convention is a verbatim copy, never a
# shared-library import (assign-app-domain.sh's own header cites its
# api() helper as the precedent for that convention). Keep both copies
# byte-identical if either one changes.
derive_auth_host() {
  local raw="$1" fqdn="$2" service="$3"
  python3 - "$raw" "$fqdn" "$service" <<'PYEOF'
import json, re, sys

raw, fqdn, service = sys.argv[1], sys.argv[2], sys.argv[3]

def normalize_domains(raw):
    if raw in (None, ""):
        return {}
    if isinstance(raw, str):
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            return None
    else:
        parsed = raw
    out = {}
    if isinstance(parsed, dict):
        for svc, entry in parsed.items():
            dom = entry.get("domain", "") if isinstance(entry, dict) else ""
            out[svc] = {d.strip() for d in dom.split(",") if d.strip()}
    elif isinstance(parsed, list):
        for entry in parsed:
            svc = entry.get("name") if isinstance(entry, dict) else None
            dom = entry.get("domain", "") if isinstance(entry, dict) else ""
            if svc:
                out[svc] = {d.strip() for d in dom.split(",") if d.strip()}
    else:
        return None
    return out

HOSTNAME_RE = re.compile(
    r'^(?!-)[A-Za-z0-9-]{1,63}(?<!-)(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))*$'
)

def strip_scheme(url):
    m = re.match(r'^[a-zA-Z][a-zA-Z0-9+.-]*://(.*)$', url)
    return m.group(1) if m else url

services = normalize_domains(raw)
if services is None and raw not in (None, ""):
    print("REFUSED")
    print(f"docker_compose_domains ('{raw[:200]}') could not be parsed (even after accounting for its own string-of-JSON shape, COOLIFY-FACT-06/15) -- refusing to guess a host.")
    sys.exit(0)

candidate = None
source = None
if services and services.get(service):
    candidate = sorted(services[service])[0]
    source = "docker_compose_domains"
elif fqdn:
    candidate = fqdn
    source = "fqdn"

if not candidate:
    print("NONE")
    print("")
    sys.exit(0)

host = strip_scheme(candidate)
if "://" in host:
    print("REFUSED")
    print(f"'{candidate}' (from {source}) still carries a scheme prefix after stripping -- refusing to build a URL against it.")
    sys.exit(0)
if not HOSTNAME_RE.match(host):
    print("REFUSED")
    print(f"derived host '{host}' (from {source}, raw value '{candidate}') is not hostname-shaped -- refusing to build a URL against it.")
    sys.exit(0)

print(host)
print(source)
PYEOF
}

# =====================================================================
# LEG 4 -- auth login
# =====================================================================
step "Leg 4/4 -- auth login"
AUTH_STATUS="VERIFIED"
AUTH_MSG=""

AUTH_DERIVE="$(derive_auth_host "$SIBLING_COMPOSE_DOMAINS" "$SIBLING_FQDN" "$COMPOSE_SERVICE")"
AUTH_DERIVE_1="$(sed -n 1p <<<"$AUTH_DERIVE")"
AUTH_DERIVE_2="$(sed -n 2p <<<"$AUTH_DERIVE")"

if [[ "$AUTH_DERIVE_1" == "NONE" ]]; then
  AUTH_STATUS="SKIPPED"
  AUTH_MSG="no domain on '$SIBLING_APP_NAME' yet -- neither docker_compose_domains nor fqdn yields a usable host (the dns/cutover steps haven't run). Re-run once a domain is assigned."
elif [[ "$AUTH_DERIVE_1" == "REFUSED" ]]; then
  AUTH_STATUS="FAILED"
  AUTH_MSG="host derivation refused: $AUTH_DERIVE_2"
else
  AUTH_HOST="$AUTH_DERIVE_1"
  AUTH_SOURCE="$AUTH_DERIVE_2"
  info "auth login: using host '$AUTH_HOST' (source: $AUTH_SOURCE)"

  LOGIN_STATUS="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$AUTH_HOST/login" 2>/dev/null || true)"
  [[ -n "$LOGIN_STATUS" ]] || { AUTH_STATUS="FAILED"; AUTH_MSG="the GET https://$AUTH_HOST/login probe produced no output at all -- local curl may be missing/broken, or the domain does not resolve/TLS-handshake. A precondition, not a reachability finding either way."; }

  if [[ "$AUTH_STATUS" != "FAILED" ]]; then
    if [[ "$LOGIN_STATUS" == "200" ]]; then
      ok "auth login: GET /login -> 200"
    else
      AUTH_STATUS="FAILED"
      AUTH_MSG="GET https://$AUTH_HOST/login -> HTTP $LOGIN_STATUS, expected 200."
    fi
  fi

  if [[ "$AUTH_STATUS" != "FAILED" ]]; then
    # Origin set explicitly to the app's own domain: SvelteKit's built-in
    # CSRF guard 403s a cross-origin-looking POST before the route's own
    # Zod validation ever runs -- see this file's own header for why.
    SIGNUP_STATUS="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
      -H "Origin: https://$AUTH_HOST" \
      --data-urlencode "email=smoke-remaining-checks-invalid@example.invalid" \
      "https://$AUTH_HOST/signup" 2>/dev/null || true)"
    if [[ -z "$SIGNUP_STATUS" ]]; then
      AUTH_STATUS="FAILED"
      AUTH_MSG="the POST https://$AUTH_HOST/signup probe produced no output at all -- precondition, not a validation finding."
    elif [[ "$SIGNUP_STATUS" == "400" ]]; then
      ok "auth login: POST /signup with a missing 'password' field -> 400 (Zod .strict() validation fires; no real account was created)"
    else
      AUTH_STATUS="FAILED"
      AUTH_MSG="POST https://$AUTH_HOST/signup (missing password) -> HTTP $SIGNUP_STATUS, expected 400."
    fi
  fi

  if [[ "$AUTH_STATUS" != "FAILED" ]]; then
    RESEND_NODE_HELPER='
const http = require("http");
const key = process.env.GOTRUE_SMTP_PASS || "";
const from = process.env.GOTRUE_SMTP_ADMIN_EMAIL || "";
if (!key) { console.log("RESEND_KEY_ABSENT"); process.exit(0); }
const https = require("https");
const body = JSON.stringify({
  from: from || "onboarding@resend.dev",
  to: ["delivered@resend.dev"],
  subject: "smoke-remaining-checks: CA-7/TZ-1/RLS/auth-login synthetic probe",
  text: "synthetic Resend send-acceptance probe (docs/deployment-runbook.md remaining-checks). No real recipient."
});
const req = https.request({
  host: "api.resend.com", path: "/emails", method: "POST",
  headers: { "Authorization": "Bearer " + key, "Content-Type": "application/json", "Content-Length": Buffer.byteLength(body) }
}, (res) => { res.on("data", () => {}); res.on("end", () => console.log("RESEND_STATUS_" + res.statusCode)); });
req.on("error", () => console.log("RESEND_CONN_ERROR"));
req.write(body);
req.end();
'
    set +e
    RESEND_OUT="$(sshx "env STACK_UUID=\"$STACK_UUID\" bash -s" <<REMOTE
set -e
docker compose --project-name "\$STACK_UUID" exec -T auth node -e $(printf '%q' "$RESEND_NODE_HELPER") </dev/null
REMOTE
)"
    RESEND_RC=$?
    set -e
    if [[ $RESEND_RC -ne 0 || -z "$RESEND_OUT" ]]; then
      AUTH_STATUS="FAILED"
      AUTH_MSG="could not run the Resend send-acceptance probe inside $STACK_APP_NAME's auth container (rc=$RESEND_RC)."
    elif [[ "$RESEND_OUT" == "RESEND_KEY_ABSENT" ]]; then
      info "auth login: GOTRUE_SMTP_PASS is absent on the auth container -- Resend not yet configured (infra/supabase/README.md: intentionally left unset pending a secrets-manifest.yml decision). Not a failure; the send-acceptance sub-check is not attempted."
    elif [[ "$RESEND_OUT" == "RESEND_STATUS_200" ]]; then
      ok "auth login: Resend send-acceptance probe (to delivered@resend.dev, Resend's own test address) -> 200"
    else
      AUTH_STATUS="FAILED"
      AUTH_MSG="Resend send-acceptance probe -> $RESEND_OUT, expected RESEND_STATUS_200 or RESEND_KEY_ABSENT."
    fi
  fi

  if [[ "$AUTH_STATUS" == "VERIFIED" ]]; then
    # Every automatable sub-check passed. The email-confirmation
    # round-trip itself remains genuinely unscriptable (see this file's
    # own header) -- this leg CANNOT report fully VERIFIED while a domain
    # exists; MANUAL is the honest ceiling, not a downgrade to chase away.
    AUTH_STATUS="MANUAL"
    AUTH_MSG="login page (200) / signup validation (400) / Resend send-acceptance all checked automatically and passed. The email-confirmation round-trip -- following the real link a confirmation email carries and confirming the session establishes -- requires reading an arbitrary recipient's real inbox, which no credential this repo holds grants; scripting it would mean creating a real account against production on every run. This is the one unavoidable by-hand step. See docs/deployment-runbook.md's unavoidable-manual list."
  fi
fi

# Every leg above sets AUTH_MSG on its own FAILED/SKIPPED/MANUAL branch but
# does not print it inline any more (run 23: a FAILED set deep in the
# if-chain above printed NOTHING -- the rest of the chain's own `if
# AUTH_STATUS != FAILED` guards silently skipped every later warn call
# too). One unconditional print here, same shape LEG 3's own trailing
# "if RLS_STATUS != VERIFIED" block already uses, guarantees the message
# reaches stdout/stderr exactly once regardless of which branch set it.
if [[ "$AUTH_STATUS" != "VERIFIED" && -n "$AUTH_MSG" ]]; then
  warn "auth login: $AUTH_MSG"
fi

# =====================================================================
# Summary + overall verdict
# =====================================================================
step "Summary"
printf '  %-12s %s\n' "TZ-1:" "$TZ1_STATUS"
printf '  %-12s %s\n' "CA-7:" "$CA7_STATUS"
printf '  %-12s %s\n' "RLS:" "$RLS_STATUS"
printf '  %-12s %s\n' "auth-login:" "$AUTH_STATUS"

OVERALL="VERIFIED"
for s in "$TZ1_STATUS" "$CA7_STATUS" "$RLS_STATUS" "$AUTH_STATUS"; do
  case "$s" in
    FAILED) OVERALL="FAILED" ;;
    MANUAL) [[ "$OVERALL" != "FAILED" ]] && OVERALL="MANUAL" ;;
    SKIPPED) [[ "$OVERALL" != "FAILED" && "$OVERALL" != "MANUAL" ]] && OVERALL="SKIPPED" ;;
  esac
done

case "$OVERALL" in
  VERIFIED) ok "overall: VERIFIED"; exit 0 ;;
  SKIPPED)  warn "overall: SKIPPED (non-fatal-but-not-verified -- re-run once the skipped leg's precondition clears)"; exit 3 ;;
  MANUAL)   warn "overall: MANUAL (a genuinely by-hand step remains -- see auth-login above)"; exit 4 ;;
  FAILED)   die "overall: FAILED -- one or more legs found a real issue or hit a precondition it could not attempt under. See the leg output above." ;;
esac
