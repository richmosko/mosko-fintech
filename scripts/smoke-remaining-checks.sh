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
#         LIVE from pg_attribute (never information_schema.columns --
#         that view is role-filtered, same premise Sec had removed from
#         the privilege checks below; pg_attribute is catalog-level and
#         does not depend on who is asking. Never a hand-maintained
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
#         (as `supabase_admin`, no `SET ROLE`) for the SAME tables --
#         the privileged baseline is still one batched UNION ALL psql
#         invocation (admin always has access, never errors), but the
#         `authenticated` read is ONE PSQL INVOCATION PER TABLE (real-run
#         25 fix, 2026-09-22 -- see that fix's own note further down for
#         why: a single combined UNION ALL statement aborts EVERY table's
#         read the instant ONE table hits a grant-level refusal). Per
#         table: connect as `authenticated` (`SET ROLE authenticated`
#         from the `supabase_admin` superuser session -- current_user
#         becomes `authenticated`, which is neither the table owner nor a
#         superuser, so RLS enforces normally per ordinary Postgres
#         semantics) WITHOUT ever setting `request.jwt.claims` -- exactly
#         the shape a stolen/absent JWT would produce. Every migration in
#         this repo scopes its policies `users_id = auth.uid()`
#         (001_pfin_foundation.sql's own stated convention), and
#         `auth.uid()` returns NULL with no JWT claims set, so `users_id
#         = NULL` can never be true -- a table with real rows and 0
#         visible under `authenticated` is PROVEN isolated; a table with
#         0 real rows to begin with is INCONCLUSIVE (nothing to isolate,
#         says nothing either way); any table where `authenticated` sees
#         >0 rows is a live RLS bypass, FAILED regardless of the others.
#         Sec ruling 2026-09-22 (amends the original real-run-25 fix): a
#         psql `permission denied for table <t>` (SQLSTATE 42501) must
#         NEVER be classified as isolation PROVEN by itself -- an error
#         that PREVENTS observation is not an observation of denial, and
#         this leg never prints "proven" or "DENIED" from a permission
#         error; REFUSED is the word. For the four RLS_DENY_ALL_EXPECTED
#         tables (which carry NO grant to `authenticated` at all, by
#         design), the verdict rests on the STRUCTURAL conjunction alone
#         (RLS on, 0 policies, zero anon+authenticated grant at table AND
#         column level, already asserted in the enumeration step below)
#         -- a REFUSED-at-grant read is the EXPECTED, stronger result for
#         a zero-grant table and does NOT itself decide the verdict; a
#         real 0-row read (the SELECT actually succeeded) is WORTH A
#         SECOND LOOK instead, flagged with its own WARN, since a truly
#         zero-grant table should have refused the read outright. On a
#         POLICY-SCOPED table (not in the allowlist), a REFUSED-at-grant
#         read has no such structural fallback to rest on -- INCONCLUSIVE,
#         never PROVEN, never FAILED from a permission error alone. Any
#         OTHER error (not SQLSTATE 42501) on a table's read is a
#         precondition failure scoped to THAT TABLE alone -- INCONCLUSIVE,
#         never FAILED, never aborting the leg or a sibling's read. If NO
#         discovered table is ever PROVEN (i.e. the whole set is empty or
#         every table lands in one of these no-observation buckets), this
#         leg reports SKIPPED, not VERIFIED -- isolation is unproven, not
#         proven absent. Sec F-2's original `reset role` concern no longer
#         applies -- each table's `authenticated` read is its own fresh
#         docker-exec/psql connection now, so there is no shared session
#         for a stray SET ROLE to leak across.
#       - HYBRID tables (real-run 27, 2026-09-22 -- Sec-ruled, PR #883
#         review, TWO rounds) -- `pfin.asset` (016_asset_registry.sql:
#         307-309: "HYBRID RLS ... global rows (users_id NULL) readable
#         by all authenticated") is BY DESIGN not a bare-deny table: a
#         session with no tenant identity established is SUPPOSED to see
#         the global rows. Real-run 27's naive read (a bare `count(*)`)
#         saw 7 such rows and misreported a "live RLS bypass" -- the
#         correct assertion for a hybrid table is "0 rows with a
#         NON-NULL users_id are visible", not "0 rows total are
#         visible". Discovered from the policy text ITSELF in
#         `pg_policies.qual` (never a hand list -- a `SELECT`/`ALL`
#         policy whose USING clause matches `users_id\s+is\s+null`,
#         case-insensitive), same B-1 dynamic-enumeration convention as
#         everything else in this leg -- Sec explicitly ROUND-1-CONFIRMED
#         this discovery mechanism over a hardcoded list (the `cmd in
#         ('SELECT','ALL')` scoping is what makes it safe: a miss on a
#         genuinely hybrid table fails closed via the ordinary "expected
#         0" path, and a match can only fire on a policy that really is
#         hybrid in effect), and the discovered set is printed.
#           For each discovered hybrid table, TWO SEPARATE assertions,
#         not one: (1) the LEAK half -- `psql_admin_auth_read_hybrid()`
#         reads the tenant-visible count (`count(*) filter (where
#         users_id is not null)`, must be 0) and the total visible count
#         (informational) in one connection; tenant-visible > 0 ->
#         FAILED, a real bypass, regardless of anything else, even on a
#         table that has never held tenant data before (one just
#         leaked). (2) the PROVEN-vs-INCONCLUSIVE half -- Sec's round-2
#         correction: on tenant-visible == 0, the privileged baseline `p`
#         for a hybrid table is the TENANT-owned row count (PRIV_SQL's
#         own hybrid branch computes `count(*) filter (where users_id is
#         not null)`, NOT the total), because the table's global rows
#         make it look non-empty while the tenant-scoping half of its
#         own policy may never have been exercised -- measured live on
#         this box: 7 global rows, 0 tenant rows; a total-count baseline
#         would have wrongly credited PROVEN on an assertion that could
#         not have failed ("an assertion that cannot fail is not a
#         measurement" -- Sec, noting this is the third time this
#         specific vacuity trap has come up on this leg). p > 0 ->
#         PROVEN, counted toward PROVEN_COUNT/HYBRID_COUNT. p == 0 ->
#         INCONCLUSIVE, worded explicitly as vacuous (global-row
#         visibility verified; tenant isolation UNPROVEN on this data,
#         not proven absent) -- same empty-table bucket every other
#         table's vacuous case already uses. A grant-level refusal
#         (SQLSTATE 42501) on a hybrid table is surprising
#         (016_asset_registry.sql:334 grants `authenticated` an
#         unconditional table-level SELECT) but stays INCONCLUSIVE,
#         never PROVEN/FAILED from the permission error alone, per the
#         same rule every other table follows.
#       - `service_role`'s own BYPASSRLS attribute is confirmed
#         structurally (`pg_roles.rolbypassrls`), matching the by-design
#         contrast every migration comment in this repo already states
#         (008_pfin_service_role_grants.sql: "service_role is BYPASSRLS,
#         ACL is checked independently"). Sec: the absence of a separate
#         `authenticated.rolbypassrls = false` assertion is not a gap --
#         if `authenticated` ever held BYPASSRLS the behavioral read above
#         would already FAIL loudly (it would see every row). Sec's own
#         condition on accepting this (PR #881 review, 2026-09-22): it
#         holds only when PROVEN_COUNT contains at least one table where a
#         real row-read actually happened -- true by construction now
#         that a REFUSED-at-grant read is classified INCONCLUSIVE rather
#         than PROVEN (a zero-grant table would stay `permission denied`
#         under BYPASSRLS too, revealing nothing), and the
#         `PROVEN_COUNT -eq 0 -> SKIPPED` guard below is what keeps this
#         argument honest on a run where every table is empty or refused.
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
#         instead of being rejected one layer earlier). This proves the
#         endpoint is live and its `.strict()` validation fires, WITHOUT
#         ever calling `signUp` with a valid credential pair -- no real
#         auth.users row, no real confirmation email, no Resend quota
#         spent by this leg.
#           real-run 25 fix (2026-09-22) -- the naive check compared only
#         the raw HTTP status against 400 and treated the real box's
#         actual response as a defect. SvelteKit reports a form-action
#         `fail(400, ...)` (api/src/routes/signup/+page.server.ts) as
#         HTTP 200 with a JSON envelope, not a plain HTTP 400. MEASURED
#         live, real-run 25, 2026-09-22 -- HTTP 200, Content-Type:
#         application/json, body:
#           {"type":"failure","status":400,"data":"[{\"errors\":1,\"email\":5},{\"password\":2,...},\"Invalid input: expected string, received undefined\",...]"}
#         This leg now accepts EITHER shape as proof the request was
#         rejected and no account was created: a plain HTTP 400, or an
#         HTTP 200 envelope with `type: "failure"`, `status: 400`, and a
#         `data` field that mentions "password". An envelope with `type:
#         "success"`, or any redirect, means an account WAS created --
#         FAILED. An HTTP 403 means the CSRF guard rejected the request
#         before validation ever ran (Origin header wrong/missing) --
#         FAILED, naming CSRF, since this leg then cannot prove Zod
#         .strict() fired at all.
#       - A Resend send-acceptance probe, SEPARATELY: reads
#         `GOTRUE_SMTP_PASS`/`GOTRUE_SMTP_ADMIN_EMAIL` from the Supabase
#         stack's own `auth` (GoTrue) container env, and, if present,
#         issues one real Resend API send to `delivered@resend.dev`,
#         Resend's own documented test address that accepts a send
#         without actually delivering it or counting against normal
#         quota the way a real recipient would. `SMTP_PASS` is
#         DELIBERATELY unset on a fresh stand-up (infra/supabase/README.md
#         says so explicitly -- "needs a secrets-manifest.yml decision
#         before it's wired up") -- this leg treats that absence as
#         informational, not a failure.
#           real-run 27 fix (2026-09-22) -- the ORIGINAL probe ran
#         `docker compose exec -T auth node -e ...`, executing INSIDE the
#         `auth` (GoTrue) container itself. MEASURED live, real-run 27,
#         2026-09-22: that exec exits rc=127 with no stdout/stderr text at
#         all -- GoTrue's own image is a minimal Go-binary image and ships
#         neither `node` nor `curl` (consistent with a bare `node: not
#         found`/`exec format error` from an image with no such binary on
#         PATH). This leg had never actually attempted a Resend send.
#         Fixed via `resend_probe()`, in two parts, BOTH still entirely ON
#         THE BOX -- the key never crosses back to the operator's machine,
#         same hygiene boundary scripts/pgrst-schemas-live-check.sh already
#         documents, and it is never assigned to a local (operator-side)
#         shell variable, never printed, and never appears in any
#         process's argv on the box:
#           (1) the key is read via `docker inspect --format
#               '{{range .Config.Env}}...{{end}}'` on the `auth`
#               container FROM THE HOST -- this needs NO binary inside the
#               container at all (not even a shell), sidestepping the
#               missing-node/curl problem for the read step entirely.
#           (2) the actual HTTPS POST to Resend runs via `node` INSIDE THE
#               SIBLING APP CONTAINER instead ($SIBLING_APP_NAME /
#               $COMPOSE_SERVICE) -- proven present by THIS SAME LEG'S own
#               CA-7 positive-control probe (Leg 2, the identical `docker
#               exec ... node -e` mechanism, already measured working
#               against a real SvelteKit/Node app image). The key is piped
#               in on STDIN as a JSON payload (`docker exec -i`, built on
#               the box with `python3 -c 'import json...'` -- never with
#               hand-escaped shell string interpolation), never on any
#               command's argv, and the whole read-then-post sequence is
#               ONE remote ssh script/session (one round trip), not two.
#         The sibling container id itself is resolved the ordinary way
#         (`find_running_container()`, the same Sec F4 ambiguity discipline
#         CA-7 already applies) -- it is a container id, not a secret, so
#         it is fine to hold locally and pass in as an env var.
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

# Sec-RATIFIED 2026-09-22 (all four). RLS on + ZERO policies + zero
# authenticated/anon grant is the ratified posture for these tables,
# not a coverage gap: 026:197/204-205, 027:169/175-176,
# 015:487/626 (named a deliberate exclusion at 025:180-182), and
# 111:622/628. Default-deny is STRICTER than any users_id policy, and
# per 111:511 adding an authenticated read policy ENDS that table's
# aal2-clause exemption. ADDING TO THIS ARRAY IS A JOINT-REVIEW ACT
# (ADR-011 D1/D2 surface) -- it must not grow without Sec review.
#
# A table Sec later rules a real gap on is REMOVED so this leg FAILS on
# it again. A table that later gains a real policy moves out of
# DENY-ALL on its own (reported INFO, not removed by hand -- see LEG 3
# below). A table with 0 policies NOT on this list is FAILED
# unconditionally, in the enumeration loop itself -- never a generic
# "0 policies + authenticated sees 0 rows => DENY-ALL" rule, which
# would bless a forgotten policy.
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

psql_admin_auth_read_hybrid() {
  # psql_admin_auth_read_hybrid <table> -- HYBRID-table variant of
  # psql_admin_auth_read() (real-run 27 fix, Sec-ruled 2026-09-22): a
  # HYBRID select policy (016_asset_registry.sql:307-309's own documented
  # posture -- `using (users_id is null or users_id = auth.uid())`) makes
  # "authenticated sees 0 rows" the WRONG assertion for that table --
  # global rows (users_id IS NULL) are meant to be visible to every
  # authenticated caller by design (Sec joint-review merge-block 6). This
  # reads TWO counts in the SAME session/connection instead: rows where
  # users_id IS NOT NULL (must be 0 -- a non-NULL users_id row visible
  # with no tenant identity established IS a bypass, same as any other
  # table) and the total visible row count (informational -- how many
  # global rows exist). Same VERBOSITY/role/-q shape as
  # psql_admin_auth_read() -- see that function's own header for why each
  # flag is there. Output: "<tenant_visible>|<total>" (psql -A's own
  # default field separator). `<table>` is interpolated only after the
  # same identifier-shape validation psql_admin_auth_read() already
  # requires of its caller.
  local t="$1"
  sshx "env STACK_UUID=\"$STACK_UUID\" bash -s" <<REMOTE
set -e
docker compose --project-name "\$STACK_UUID" exec -T db psql -q -t -A -U supabase_admin -d postgres -c '\set VERBOSITY verbose' -c 'set role authenticated' -c 'select count(*) filter (where users_id is not null), count(*) from pfin.$t' </dev/null
REMOTE
}

psql_admin_auth_read() {
  # psql_admin_auth_read <table> -- the RLS leg's per-table `authenticated`
  # row-count read (real-run 25 fix, Sec-ruled 2026-09-22). THREE separate
  # `-c` flags in ONE psql session/connection (not one semicolon-joined
  # -tAc string) -- a `\set` meta-command and SQL statements never mix
  # cleanly inside a single -c string, and this shape sidesteps that
  # entirely: `-c '\set VERBOSITY verbose'` (so a failing SELECT's error
  # line carries its SQLSTATE, e.g. `ERROR:  42501: permission denied for
  # table <t>` -- MEASURED against the local dev stack, 2026-09-22, and
  # locale-independent, unlike matching the message text), `-c 'set role
  # authenticated'`, `-c 'select count(*) from pfin.<t>'`. `-q` suppresses
  # the `SET` command-completion tag that otherwise lands on stdout ahead
  # of the count (MEASURED: without -q, a successful read prints
  # "SET\n0", not "0"). `<table>` is interpolated ONLY after the caller
  # has validated it against `^[a-z_][a-z0-9_]*$` (the enumeration loop,
  # before any table name reaches here) -- never trust an unvalidated
  # identifier into a remote command line.
  #
  # MEASURED verbatim (local dev stack, 2026-09-22), table audit_log --
  # the exact byte shape scripts/ci/fence-smoke-remaining-checks-strikes.sh
  # pins its DENIED fixture output against, never hand-retyped a second
  # time:
  #   ERROR:  42501: permission denied for table audit_log
  #   HINT:  Grant the required privileges to the current role with: GRANT SELECT ON pfin.audit_log TO authenticated;
  #   LOCATION:  aclcheck_error, aclchk.c:2843
  local t="$1"
  sshx "env STACK_UUID=\"$STACK_UUID\" bash -s" <<REMOTE
set -e
docker compose --project-name "\$STACK_UUID" exec -T db psql -q -t -A -U supabase_admin -d postgres -c '\set VERBOSITY verbose' -c 'set role authenticated' -c 'select count(*) from pfin.$t' </dev/null
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

# Sec F-1 (round-2 review, PR #880): the original enumeration asserted
# anon's TABLE-level grant only -- authenticated's table-level grant and
# BOTH roles' COLUMN-level grants (has_any_column_privilege subsumes a
# table-level grant too, per Sec's own note) were invisible to it. A
# grant added later (e.g. `grant select on pfin.mfa_recovery_code to
# authenticated`, or a column-scoped grant per
# 026_mfa_recovery_code.sql:222's own pattern) would still read 0 rows
# under RLS with 0 policies -- the behavioral read can't see the grant,
# only the grant's absence can be asserted directly. Four privilege
# columns, all fetched here in the one enumeration query (no second
# round trip): anon/authenticated at table level, then anon/authenticated
# at column level, in that order.
# Sec (non-gating flag, PR #880 round-3 GREEN): table DISCOVERY used
# information_schema.columns, a view that shows only columns the
# CURRENT ROLE can see -- the same role-visibility premise Sec had
# already made us remove from the privilege checks (has_table_privilege/
# has_any_column_privilege don't have it). It returns the complete set
# only because psql_admin connects as supabase_admin, a superuser; if
# that ever changes, this view returns FEWER tables, the loop checks
# fewer tables, and the leg reports OK -- a fail-open on the leg's
# COVERAGE, not on any single table's verdict (the empty-set guard below
# catches total loss, not partial). pg_attribute is catalog-level, not
# role-filtered -- discovery no longer depends on who is asking.
# 8th column (real-run 27 addition, Sec-ruled 2026-09-22): HYBRID-table
# discovery. Discovered from the policy text ITSELF -- never a hand list
# -- exactly as 016_asset_registry.sql:307-309's own select policy reads:
# `exists (... a SELECT/ALL policy whose USING clause admits users_id IS
# NULL)`. `\s+` is a Postgres ARE advanced-regex whitespace class (NOT
# the same family as `\b`, which this repo's own memory already flags as
# a literal backspace, not a boundary, in this regex engine -- `\s` IS
# supported here). `~*` is case-insensitive.
RLS_ENUM_QUERY="select c.relname, c.relrowsecurity::text, (select count(*) from pg_policies p where p.schemaname = n.nspname and p.tablename = c.relname)::text, has_table_privilege('anon', c.oid, 'SELECT')::text, has_table_privilege('authenticated', c.oid, 'SELECT')::text, has_any_column_privilege('anon', c.oid, 'SELECT')::text, has_any_column_privilege('authenticated', c.oid, 'SELECT')::text, (exists (select 1 from pg_policies p2 where p2.schemaname = n.nspname and p2.tablename = c.relname and p2.cmd in ('SELECT','ALL') and p2.qual ~* 'users_id\s+is\s+null'))::text from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'pfin' and c.relkind in ('r','p') and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'users_id' and a.attnum > 0 and not a.attisdropped) order by c.relname;"

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
  HYBRID_TABLES=()
  while IFS='|' read -r tbl rls polcount anonsel authsel anoncol authcol hybrid; do
    [[ -z "$tbl" ]] && continue
    if [[ ! "$tbl" =~ ^[a-z_][a-z0-9_]*$ ]]; then
      RLS_STATUS="FAILED"
      RLS_MSGS+=("discovered table name '$tbl' does not match the expected identifier shape -- refusing to interpolate it into a dynamic query.")
      continue
    fi
    TABLES+=("$tbl")
    # `hybrid` is `read`-populated (column 8 of RLS_ENUM_QUERY, declared
    # `(exists(...))::text` in the SQL), so "true"/"false" is the correct
    # vocabulary here -- but this is the ONE site left after the item-1
    # cleanup below where that comparison exists at all, and Sec's own
    # note: fence-boolean-cast-pairing.sh's heuristic only traces
    # `VAR=$(...)` assignments, so a `read`-populated variable is
    # invisible to it either way, correct or not.
    if [[ "$hybrid" == "true" ]]; then
      HYBRID_TABLES+=("$tbl")
    fi
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
        # Sec F-1 (round-2 review, PR #880): a DENY-ALL-allowlisted table
        # must hold ZERO grant to anon or authenticated at BOTH table
        # AND column level -- has_any_column_privilege() subsumes a
        # table-level grant too, so all four columns are checked
        # separately so the failure message can name which shape was
        # found (a column-scoped grant is a live idiom in this repo,
        # 026_mfa_recovery_code.sql:222, not a hypothetical).
        if [[ "$authsel" != "false" ]]; then
          RLS_STATUS="FAILED"
          RLS_MSGS+=("pfin.$tbl: DENY-ALL-allowlisted but authenticated holds table-level SELECT (has_table_privilege=$authsel) -- the service_role-only design this table's own migration documents requires zero authenticated grant, not just zero anon grant.")
        fi
        if [[ "$anoncol" != "false" ]]; then
          RLS_STATUS="FAILED"
          RLS_MSGS+=("pfin.$tbl: DENY-ALL-allowlisted but anon holds a column-level SELECT grant (has_any_column_privilege=$anoncol) -- a column-scoped grant (this table's own migration pattern uses column-scoped grants for service_role) must never extend to anon.")
        fi
        if [[ "$authcol" != "false" ]]; then
          RLS_STATUS="FAILED"
          RLS_MSGS+=("pfin.$tbl: DENY-ALL-allowlisted but authenticated holds a column-level SELECT grant (has_any_column_privilege=$authcol) -- a column-scoped grant (this table's own migration pattern uses column-scoped grants for service_role) must never extend to authenticated.")
        fi
      else
        RLS_STATUS="FAILED"
        RLS_MSGS+=("pfin.$tbl: 0 policies in pg_policies and NOT in RLS_DENY_ALL_EXPECTED -- either this is a real policy-coverage gap (add a policy), or it is meant to be service_role-only and Sec needs to rule so it can be added to the allowlist by migration. Treating as FAILED until then.")
      fi
    fi
  done <<<"$RLS_ENUM"
  info "discovered ${#TABLES[@]} users_id-bearing pfin table(s): ${TABLES[*]}"
  if [[ ${#HYBRID_TABLES[@]} -gt 0 ]]; then
    info "discovered ${#HYBRID_TABLES[@]} HYBRID table(s) (a SELECT/ALL policy admits users_id IS NULL to every authenticated caller): ${HYBRID_TABLES[*]}"
  fi

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
    # Sec ruling 2026-09-22 (PR #883 review, round 2): for a HYBRID table
    # the privileged baseline must be the TENANT-owned row count
    # (`count(*) filter (where users_id is not null)`), NOT the total row
    # count -- a hybrid table's global rows make it look non-empty while
    # the tenant-scoping half of its own policy may never have been
    # exercised (measured live on this box: pfin.asset has 7 global rows
    # and 0 tenant rows -- a total-count baseline would wrongly credit
    # PROVEN on an assertion that could not have failed). Every
    # non-hybrid table keeps the ordinary total-count baseline, unchanged.
    PRIV_SQL=""
    first=1
    for t in "${TABLES[@]}"; do
      # Sec ruling 2026-09-22 (PR #883 review): membership in the
      # already-populated HYBRID_TABLES array (built once, during
      # discovery -- see the enumeration loop above), never a second
      # awk re-parse of RLS_ENUM's column 8. An awk re-read here compared
      # against the literal "true" defeats scripts/ci/fence-boolean-
      # cast-pairing.sh's own heuristic: that fence resolves a variable's
      # cast-ness by scanning FORWARD from its nearest psql-shaped
      # assignment for `::text`, but RLS_ENUM_QUERY's `::text` casts are
      # all textually BEFORE the `RLS_ENUM=$(psql_admin "$RLS_ENUM_QUERY")`
      # call, never after it -- the fence resolves this as UNCAST and
      # flags every "== \"true\"" comparison derived from it. Line 780's
      # identifier-shape validation (`continue`s on anything not matching
      # `^[a-z_][a-z0-9_]*$`) guarantees no discovered table name can
      # contain a space, so this space-padded substring match cannot
      # false-positive on a prefix/suffix collision. `${#HYBRID_TABLES[@]}
      # -gt 0 &&` guards a real bash 3.2 gotcha (macOS's own /bin/bash):
      # under `set -u`, `${arr[@]}`/`${arr[*]}` on a ZERO-length array
      # throws "unbound variable" even after `arr=()` -- MEASURED against
      # this fence when no hybrid table exists at all (the ordinary case).
      if [[ ${#HYBRID_TABLES[@]} -gt 0 && " ${HYBRID_TABLES[*]} " == *" $t "* ]]; then
        EXPR="count(*) filter (where users_id is not null)"
      else
        EXPR="count(*)"
      fi
      if [[ $first -eq 1 ]]; then PRIV_SQL="select 'PRIV' as ctx, '$t' as t, $EXPR as n from pfin.\"$t\""; first=0
      else PRIV_SQL="$PRIV_SQL union all select 'PRIV', '$t', $EXPR from pfin.\"$t\""; fi
    done
    # Grant-conjunction checking (table+column level, both roles) now
    # happens upstream in the enumeration loop above, against the SAME
    # RLS_ENUM_QUERY read that already carries all four privilege
    # columns -- no second round trip needed (Sec F-1, round-2 review,
    # PR #880: originally a separate GRANT_SQL query here; folded into
    # the enumeration query instead).
    set +e
    PRIV_OUT="$(psql_admin "$PRIV_SQL")"
    PRIV_RC=$?
    set -e
    if [[ $PRIV_RC -ne 0 ]]; then
      RLS_STATUS="FAILED"
      RLS_MSGS+=("the privileged-baseline row-count read failed (rc=$PRIV_RC) -- precondition, not an isolation finding.")
    else
      # real-run 25 fix (2026-09-22) -- the ORIGINAL authenticated read
      # batched every table's count into ONE UNION ALL statement, sent
      # together with `set role authenticated` as ONE multi-statement -c
      # string -- ONE implicit server-side transaction. On a table with
      # NO grant to `authenticated` at all (the RLS_DENY_ALL_EXPECTED
      # tables -- the strongest possible deny), that UNION ALL statement
      # itself raises "permission denied for table <t>", which aborts
      # the WHOLE implicit transaction: every OTHER table's count is
      # lost too, and the leg reported a blanket precondition failure
      # even though every single table's read behavior was exactly what
      # DENY-ALL requires. Measured live (real-run 25, 2026-09-22):
      #   psql -U supabase_admin -c "set role authenticated; select
      #   count(*) from pfin.audit_log;" -> ERROR:  permission denied
      #   for table audit_log -- the SET itself succeeds.
      #
      # Fixed by reading `authenticated`'s count ONE TABLE PER psql
      # invocation (`psql_admin_auth_read`, above) -- a fresh docker-exec/
      # psql session each time, so a denied table can never abort a
      # sibling table's read. A batched read that aborts the whole batch
      # on the first refusal must not exist, and does not any more.
      #
      # Sec ruling 2026-09-22 (amends the fix above): a
      # `permission denied for table <t>` refusal (SQLSTATE 42501,
      # detected off the verbose error line `psql_admin_auth_read`
      # requests -- locale-independent, unlike matching the message
      # text) is NEVER classified as isolation proven by itself -- see
      # this file's own LEG 3 header for the full ruling (structural
      # conjunction carries the DENY-ALL verdict; REFUSED is the word,
      # never "proven"/"DENIED"; a POLICY-SCOPED table's refusal has no
      # structural fallback and stays INCONCLUSIVE). Any OTHER error
      # (not 42501) stays a precondition failure, scoped to that one
      # table -- INCONCLUSIVE, never FAILED, not the whole leg. `reset
      # role` (Sec F-2's original concern) is no longer needed -- each
      # table's read is its own fresh connection; there is no shared
      # session for a stray SET ROLE to leak across.
      #
      # bash 3.2 (macOS operator shell): no associative arrays (`declare
      # -A` is a bash 4+ builtin option this repo's own provision.sh
      # header already states as off-limits -- "parallel arrays, no
      # assoc arrays"). Per-table lookup via a plain string match on the
      # "PRIV|table|count" output instead of a hash map.
      PROVEN_COUNT=0
      INCONCLUSIVE_COUNT=0
      DENY_ALL_COUNT=0
      HYBRID_COUNT=0
      # Sec ruling 2026-09-22 (PR #881 review, round 2): INCONCLUSIVE has
      # four distinct causes now, and a summary that folds them into one
      # undifferentiated bucket asserts something false ("empty, nothing
      # to isolate" on a table that was actually unreadable, or whose
      # policy was never exercised). Tracked separately so the summary
      # line can name the real breakdown -- "the sentence must say what
      # actually happened, because it outlives the reasoning behind it."
      INCONCLUSIVE_EMPTY_COUNT=0
      INCONCLUSIVE_REFUSED_POLICY_COUNT=0
      INCONCLUSIVE_UNREADABLE_COUNT=0
      INCONCLUSIVE_CONTRADICTION_COUNT=0
      for t in "${TABLES[@]}"; do
        p="$(printf '%s\n' "$PRIV_OUT" | awk -F'|' -v t="$t" '$1=="PRIV" && $2==t {print $3; exit}')"
        if [[ -z "$p" ]]; then
          RLS_STATUS="FAILED"
          RLS_MSGS+=("pfin.$t: missing a privileged row-count reading in the PRIV query output -- precondition, treat as unverified.")
          continue
        fi
        polcount="$(printf '%s\n' "$RLS_ENUM" | awk -F'|' -v t="$t" '$1==t {print $3; exit}')"

        # Sec ruling 2026-09-22 (PR #883 review): same fix as PRIV_SQL's
        # own hybrid branch above -- membership in HYBRID_TABLES, never a
        # second awk re-parse of RLS_ENUM's column 8 compared against the
        # literal "true" (see that branch's own comment for exactly why
        # this defeats fence-boolean-cast-pairing.sh's forward-scan
        # heuristic).
        if [[ ${#HYBRID_TABLES[@]} -gt 0 && " ${HYBRID_TABLES[*]} " == *" $t "* ]]; then
          # HYBRID (real-run 27, Sec-ruled 2026-09-22, PR #883 review --
          # TWO rounds) -- see psql_admin_auth_read_hybrid()'s own header.
          # TWO SEPARATE assertions, not one: (1) the LEAK half -- 0 rows
          # with a NON-NULL users_id visible with no tenant identity
          # established. Uses the LIVE read ($HYBRID_TENANT) and can fail
          # on its own merits regardless of $p -- a real leak is a real
          # leak even on a table with zero pre-existing tenant rows (one
          # just leaked). (2) the PROVEN-vs-INCONCLUSIVE half -- Sec's
          # round-2 correction: `$p` here is the PRIVILEGED TENANT-row
          # count (PRIV_SQL's own hybrid branch, above), NOT the total
          # row count. p>0 means real tenant-owned rows existed and none
          # leaked -- PROVEN. p==0 means the leak assertion was VACUOUS
          # (nothing existed to leak) -- INCONCLUSIVE, explicitly worded
          # as such, never PROVEN on the strength of an assertion that
          # could not have failed (identical principle to the DENY-ALL
          # empty-table ruling; Sec: "it has now come up three times on
          # this leg in different clothing").
          set +e
          HYBRID_OUT="$(psql_admin_auth_read_hybrid "$t" 2>&1)"
          HYBRID_RC=$?
          set -e
          if [[ $HYBRID_RC -eq 0 ]]; then
            HYBRID_TENANT="$(awk -F'|' '{print $1}' <<<"$HYBRID_OUT")"
            HYBRID_TOTAL="$(awk -F'|' '{print $2}' <<<"$HYBRID_OUT")"
            if [[ -z "$HYBRID_TENANT" || -z "$HYBRID_TOTAL" ]]; then
              INCONCLUSIVE_COUNT=$((INCONCLUSIVE_COUNT + 1))
              INCONCLUSIVE_UNREADABLE_COUNT=$((INCONCLUSIVE_UNREADABLE_COUNT + 1))
              info "pfin.$t: HYBRID read returned an unparseable row ('$HYBRID_OUT') -- INCONCLUSIVE for this table only, not an isolation finding."
            elif [[ "$HYBRID_TENANT" != "0" ]]; then
              RLS_STATUS="FAILED"
              RLS_MSGS+=("pfin.$t: HYBRID table -- $HYBRID_TENANT row(s) with a NON-NULL users_id visible to a session with NO tenant identity established (SET ROLE authenticated, no request.jwt.claims) -- expected 0. This is a live RLS bypass, not the by-design global-row exposure this table's own HYBRID policy grants.")
            elif [[ "$p" -gt 0 ]]; then
              info "HYBRID: pfin.$t -- global-row visibility VERIFIED ($HYBRID_TOTAL row(s), users_id NULL); tenant isolation PROVEN -- $p owner-bearing row(s) exist (privileged tenant-row count) and none are visible without tenant identity."
              PROVEN_COUNT=$((PROVEN_COUNT + 1))
              HYBRID_COUNT=$((HYBRID_COUNT + 1))
            else
              info "HYBRID: pfin.$t -- global-row visibility VERIFIED ($HYBRID_TOTAL row(s), users_id NULL); tenant isolation INCONCLUSIVE -- this table holds 0 owner-bearing row(s) (privileged tenant-row count), so the leak assertion (no non-NULL users_id row visible) is vacuously true, not a proven negative. Global-row visibility is verified; tenant isolation is UNPROVEN on this data, not proven absent."
              INCONCLUSIVE_COUNT=$((INCONCLUSIVE_COUNT + 1))
              INCONCLUSIVE_EMPTY_COUNT=$((INCONCLUSIVE_EMPTY_COUNT + 1))
            fi
          elif [[ "$HYBRID_OUT" == *"42501"* ]]; then
            # Surprising for a hybrid table (016_asset_registry.sql:334
            # grants authenticated a table-level SELECT unconditionally),
            # but stays INCONCLUSIVE per the same permission-error rule
            # every other table follows -- never PROVEN, never FAILED,
            # from a refusal alone.
            info "pfin.$t: HYBRID table, row read: REFUSED at grant level -- not an RLS observation; INCONCLUSIVE (a hybrid table is expected to carry an authenticated grant; a refusal here is worth a second look, but never PROVEN/FAILED from a permission error alone)."
            INCONCLUSIVE_COUNT=$((INCONCLUSIVE_COUNT + 1))
            INCONCLUSIVE_REFUSED_POLICY_COUNT=$((INCONCLUSIVE_REFUSED_POLICY_COUNT + 1))
          else
            INCONCLUSIVE_COUNT=$((INCONCLUSIVE_COUNT + 1))
            INCONCLUSIVE_UNREADABLE_COUNT=$((INCONCLUSIVE_UNREADABLE_COUNT + 1))
            info "pfin.$t: the HYBRID authenticated read failed with an unexpected error (rc=$HYBRID_RC, not SQLSTATE 42501) -- precondition, INCONCLUSIVE for this table only, not an isolation finding. $HYBRID_OUT"
          fi
          continue
        fi

        set +e
        AUTH_OUT="$(psql_admin_auth_read "$t" 2>&1)"
        AUTH_RC=$?
        set -e

        # Sec ruling 2026-09-22 (amends the original brief): a psql
        # `permission denied for table <t>` must NEVER be classified as
        # isolation PROVEN by itself -- an error that prevents
        # observation is not an observation of denial. Detected by
        # SQLSTATE 42501 (insufficient_privilege) on the ERROR line,
        # printed because `psql_admin_auth_read` sets `\set VERBOSITY
        # verbose` first -- locale-independent, unlike matching the
        # message text. Word choice matters here too: never print
        # "proven" or "DENIED" from a permission error -- REFUSED is the
        # word Sec ruled on.
        a=""
        REFUSED_AT_GRANT=0
        if [[ $AUTH_RC -eq 0 ]]; then
          a="$AUTH_OUT"
        elif [[ "$AUTH_OUT" == *"42501"* ]]; then
          REFUSED_AT_GRANT=1
        else
          # Any OTHER error is a precondition failure scoped to THIS
          # table alone -- INCONCLUSIVE ("unreadable", its own breakdown
          # bucket -- Sec: this is NOT "empty, nothing to isolate", the
          # table may hold real data this leg simply couldn't read),
          # never FAILED, never aborting the leg or a sibling table's
          # read.
          INCONCLUSIVE_COUNT=$((INCONCLUSIVE_COUNT + 1))
          INCONCLUSIVE_UNREADABLE_COUNT=$((INCONCLUSIVE_UNREADABLE_COUNT + 1))
          info "pfin.$t: the authenticated row-count read failed with an unexpected error (rc=$AUTH_RC, not SQLSTATE 42501) -- precondition, INCONCLUSIVE for this table only, not an isolation finding. $AUTH_OUT"
          continue
        fi

        if [[ "$REFUSED_AT_GRANT" -eq 0 && "$a" != "0" ]]; then
          RLS_STATUS="FAILED"
          RLS_MSGS+=("pfin.$t: $a row(s) visible to a session with NO tenant identity established (SET ROLE authenticated, no request.jwt.claims) -- expected 0. This is a live RLS bypass, not a fixture artifact.")
          continue
        fi
        if [[ "$polcount" -ge 1 ]]; then
          # POLICY-SCOPED -- at least one real pg_policies row.
          if is_deny_all_expected "$t"; then
            info "pfin.$t: in RLS_DENY_ALL_EXPECTED but carries $polcount polic(ies) now -- POLICY-SCOPED, not DENY-ALL any more (INFO, not a failure; consider removing it from the allowlist once Sec confirms)."
          fi
          if [[ "$REFUSED_AT_GRANT" -eq 1 ]]; then
            # Unlike the DENY-ALL allowlist below, a POLICY-SCOPED
            # table's grant absence was never independently verified
            # structurally -- a refusal here has no structural fallback
            # to rest on, so it stays INCONCLUSIVE, never PROVEN, never
            # FAILED from a permission error alone.
            info "pfin.$t: row read: REFUSED at grant level on a POLICY-SCOPED table ($polcount polic(ies)) -- not an RLS observation; INCONCLUSIVE (this table's grant absence was never independently verified structurally, unlike the DENY-ALL allowlist)."
            INCONCLUSIVE_COUNT=$((INCONCLUSIVE_COUNT + 1))
            INCONCLUSIVE_REFUSED_POLICY_COUNT=$((INCONCLUSIVE_REFUSED_POLICY_COUNT + 1))
          elif [[ "$p" -gt 0 ]]; then
            PROVEN_COUNT=$((PROVEN_COUNT + 1))
          else
            INCONCLUSIVE_COUNT=$((INCONCLUSIVE_COUNT + 1))
            INCONCLUSIVE_EMPTY_COUNT=$((INCONCLUSIVE_EMPTY_COUNT + 1))
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
          # The FULL grant conjunction (RLS on, 0 policies, anon+
          # authenticated zero grant at table AND column level) was
          # already asserted in the enumeration loop above, against this
          # same table's row from RLS_ENUM -- reaching here with
          # RLS_STATUS still VERIFIED means it held. Sec ruling
          # 2026-09-22 (round 2, PR #881 review): a REFUSED-at-grant read
          # is the EXPECTED, stronger result for a zero-grant table (the
          # grant layer refuses before RLS is even consulted) and the
          # verdict then rests on the STRUCTURAL conjunction alone. But a
          # SUCCESSFUL read on that SAME table is not merely surprising --
          # Postgres checks table ACL BEFORE RLS, so a genuinely
          # zero-grant table CANNOT return a row count. A success there
          # means one of the two measurements (the structural grant check,
          # or this row read) is WRONG, and we don't know which --
          # crediting PROVEN would rest a proof on evidence just shown to
          # be self-inconsistent. So: REFUSED -> PROVEN/INCONCLUSIVE
          # decided by the privileged baseline (p>0 vs p==0), same as
          # every other table; SUCCEEDED -> CONTRADICTION, INCONCLUSIVE
          # regardless of p, never PROVEN, until the discrepancy is
          # resolved by hand.
          # DENY_ALL_COUNT is a SUBSET of PROVEN_COUNT (the summary line
          # computes "via >=1 policy" as PROVEN_COUNT - DENY_ALL_COUNT),
          # so it increments ONLY on the branch that actually credits
          # PROVEN via this path -- never unconditionally for every
          # allowlisted table reached here, or the arithmetic would lie.
          CONJUNCTION_TERMS="RLS on, 0 policies, and all four privilege terms false (anon table-level, authenticated table-level, anon column-level, authenticated column-level)"
          if [[ "$REFUSED_AT_GRANT" -eq 1 ]]; then
            info "pfin.$t: row read: REFUSED at grant level (expected for a zero-grant table; stronger than a 0-row read; not itself what proves isolation -- the structural conjunction does)."
            if [[ "$p" -gt 0 ]]; then
              info "DENY-ALL: pfin.$t -- structural conjunction verified ($CONJUNCTION_TERMS) -- ALLOWLISTED, isolation demonstrated."
              PROVEN_COUNT=$((PROVEN_COUNT + 1))
              DENY_ALL_COUNT=$((DENY_ALL_COUNT + 1))
            else
              info "DENY-ALL: pfin.$t -- structural conjunction verified ($CONJUNCTION_TERMS); row observation INCONCLUSIVE (privileged count is 0 too -- nothing to isolate, never reported as DENY-ALL fully demonstrated on an empty table)."
              INCONCLUSIVE_COUNT=$((INCONCLUSIVE_COUNT + 1))
              INCONCLUSIVE_EMPTY_COUNT=$((INCONCLUSIVE_EMPTY_COUNT + 1))
            fi
          else
            warn "RLS: pfin.$t: CONTRADICTION -- the structural conjunction says authenticated holds no SELECT at table or column level, yet authenticated's read SUCCEEDED (returned 0 rows). Postgres checks table ACL BEFORE RLS, so a zero-grant table cannot return a row count. One of these two measurements is wrong; this table is INCONCLUSIVE and is NOT counted as proven until that is resolved."
            INCONCLUSIVE_COUNT=$((INCONCLUSIVE_COUNT + 1))
            INCONCLUSIVE_CONTRADICTION_COUNT=$((INCONCLUSIVE_CONTRADICTION_COUNT + 1))
          fi
        fi
      done
      if [[ "$RLS_STATUS" == "VERIFIED" ]]; then
        if [[ "$PROVEN_COUNT" -eq 0 ]]; then
          RLS_STATUS="SKIPPED"
          RLS_MSGS+=("every discovered table holds zero rows -- no rows exist to be isolated, so isolation is UNPROVEN, not proven absent. RLS-enabled/anon-zero-grant all checked structurally and hold; the behavioral zero-context read has nothing to demonstrate on an empty table. Re-run once at least one table holds real (or synthetic-but-real) tenant data.")
        else
          ok "RLS: every discovered table -- RLS on, anon zero-grant; $PROVEN_COUNT table(s) PROVEN isolated ($DENY_ALL_COUNT via allowlisted DENY-ALL, $HYBRID_COUNT via HYBRID tenant-isolation proof, $((PROVEN_COUNT - DENY_ALL_COUNT - HYBRID_COUNT)) via >=1 policy), $INCONCLUSIVE_COUNT table(s) INCONCLUSIVE ($INCONCLUSIVE_EMPTY_COUNT empty -- nothing to isolate, $INCONCLUSIVE_REFUSED_POLICY_COUNT refused-at-grant on a policy-scoped table -- policy never exercised, $INCONCLUSIVE_UNREADABLE_COUNT unreadable -- an unexpected error, $INCONCLUSIVE_CONTRADICTION_COUNT contradiction -- a zero-grant table's read unexpectedly succeeded)"
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

# Verbatim copy of scripts/assign-app-domain.sh's own normalize_domains()
# -- if that source changes, this copy is silently stale; check both.
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
# Named host_source, not "source" -- scripts/ci/fence-no-source-
# credential-files.sh greps tree-wide for any line whose first token is
# literally "source" (a shell-sourcing violation pattern), with no
# language awareness; it cannot distinguish this Python assignment
# inside a heredoc from a real `source $FILE` shell statement. Renamed
# to stay out of that pattern's way rather than seeking an allowlist
# exemption -- this was never a real sourcing hit to begin with.
host_source = None
if services and services.get(service):
    candidate = sorted(services[service])[0]
    host_source = "docker_compose_domains"
elif fqdn:
    candidate = fqdn
    host_source = "fqdn"

if not candidate:
    print("NONE")
    print("")
    sys.exit(0)

host = strip_scheme(candidate)
if "://" in host:
    print("REFUSED")
    print(f"'{candidate}' (from {host_source}) still carries a scheme prefix after stripping -- refusing to build a URL against it.")
    sys.exit(0)
if not HOSTNAME_RE.match(host):
    print("REFUSED")
    print(f"derived host '{host}' (from {host_source}, raw value '{candidate}') is not hostname-shaped -- refusing to build a URL against it.")
    sys.exit(0)

print(host)
print(host_source)
PYEOF
}

resend_probe() {
  # resend_probe <sibling_container_id> -- see this file's own LEG 4
  # header for the real-run 27 root cause and fix. `sibling_container_id`
  # is resolved LOCALLY first, by the caller, via find_running_container()
  # (a container id, not sensitive) and passed in as an env var here;
  # everything from resolving the `auth` container onward -- INCLUDING
  # reading GOTRUE_SMTP_PASS and building/sending the request -- happens
  # in ONE remote ssh session. The key is read, used, and discarded
  # entirely on the box: it is never assigned to a local (operator-side)
  # shell variable in this function, never printed, and never crosses
  # back to the operator's machine even transiently. A single-quoted
  # heredoc (`<<'REMOTE'`, unlike this file's other remote-script
  # functions) is deliberate here -- every value this remote script needs
  # (STACK_UUID, SIBLING_CID) arrives via the `env VAR=val` prefix instead
  # of local interpolation, so no `\$`-escaping convention is needed and
  # none of this script's own `$` (JS/psql) text can be mistaken for a
  # local-shell substitution.
  #
  # Prints exactly one of: RESEND_KEY_ABSENT / RESEND_AUTH_CONTAINER_NOT_FOUND
  # / RESEND_AUTH_CONTAINER_AMBIGUOUS / RESEND_SIBLING_CONTAINER_NOT_FOUND
  # (defensive -- the caller already validated this, see below) /
  # RESEND_STATUS_<code> / RESEND_CONN_ERROR / RESEND_PAYLOAD_PARSE_ERROR.
  local sibling_cid="$1"
  sshx "env STACK_UUID=\"$STACK_UUID\" SIBLING_CID=\"$sibling_cid\" bash -s" <<'REMOTE'
set -e
AUTH_CIDS="$(docker compose --project-name "$STACK_UUID" ps -q auth)"
AUTH_COUNT="$(printf '%s\n' "$AUTH_CIDS" | grep -c . || true)"
if [[ "$AUTH_COUNT" -eq 0 ]]; then
  echo "RESEND_AUTH_CONTAINER_NOT_FOUND"
  exit 0
elif [[ "$AUTH_COUNT" -gt 1 ]]; then
  echo "RESEND_AUTH_CONTAINER_AMBIGUOUS"
  exit 0
fi
AUTH_CID="$AUTH_CIDS"
ENV_LINES="$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$AUTH_CID")"
KEY="$(printf '%s\n' "$ENV_LINES" | grep -m1 '^GOTRUE_SMTP_PASS=' | cut -d= -f2-)"
FROM="$(printf '%s\n' "$ENV_LINES" | grep -m1 '^GOTRUE_SMTP_ADMIN_EMAIL=' | cut -d= -f2-)"
if [[ -z "$KEY" ]]; then
  echo "RESEND_KEY_ABSENT"
  exit 0
fi
if [[ -z "$SIBLING_CID" ]]; then
  # Defensive -- should be unreachable: the caller only invokes this
  # function after find_running_container() already succeeded.
  echo "RESEND_SIBLING_CONTAINER_NOT_FOUND"
  exit 0
fi
NODE_SCRIPT='
const https = require("https");
let stdin = "";
process.stdin.on("data", (c) => { stdin += c; });
process.stdin.on("end", () => {
  let payload;
  try { payload = JSON.parse(stdin); } catch (e) { console.log("RESEND_PAYLOAD_PARSE_ERROR"); return; }
  const body = JSON.stringify({
    from: payload.from || "onboarding@resend.dev",
    to: ["delivered@resend.dev"],
    subject: "smoke-remaining-checks: CA-7/TZ-1/RLS/auth-login synthetic probe",
    text: "synthetic Resend send-acceptance probe (docs/deployment-runbook.md remaining-checks). No real recipient."
  });
  const req = https.request({
    host: "api.resend.com", path: "/emails", method: "POST",
    headers: { "Authorization": "Bearer " + payload.key, "Content-Type": "application/json", "Content-Length": Buffer.byteLength(body) }
  }, (res) => { res.on("data", () => {}); res.on("end", () => console.log("RESEND_STATUS_" + res.statusCode)); });
  req.on("error", () => console.log("RESEND_CONN_ERROR"));
  req.write(body);
  req.end();
});
'
# Sec F-2 (PR #883 review): passing "$KEY"/"$FROM" as python3 -c argv (an
# earlier draft's shape) puts the key on python3's OWN argv -- readable
# from /proc/<pid>/cmdline by anything on the box for the duration of the
# call, contradicting this function's own header claim that the key
# never appears on any process's argv. Fixed to match this repo's own
# established stdin-only convention (resolve_app()'s PY_API_HELPER /
# `api()` passes the Coolify token via curl's `-K -` stdin config, never
# argv, for the identical reason) -- NUL-separated on python3's stdin
# instead, mirroring the docker-exec/node half's own stdin-only shape.
printf '%s\0%s' "$KEY" "$FROM" \
  | python3 -c 'import json,sys; parts = sys.stdin.buffer.read().split(b"\x00"); k = parts[0].decode(); f = parts[1].decode() if len(parts) > 1 else ""; print(json.dumps({"key": k, "from": f}))' \
  | docker exec -i "$SIBLING_CID" node -e "$NODE_SCRIPT"
REMOTE
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
    #
    # real-run 25 fix (2026-09-22) -- see this file's own LEG 4 header
    # for the MEASURED envelope shape. A plain HTTP 400 is still
    # accepted; an HTTP 200 is now inspected as a possible SvelteKit
    # form-action-failure envelope instead of being treated as a defect
    # outright.
    SIGNUP_HDR="$(mktemp)"
    SIGNUP_BODY="$(mktemp)"
    SIGNUP_STATUS="$(curl -s -o "$SIGNUP_BODY" -D "$SIGNUP_HDR" -w '%{http_code}' --max-time 10 \
      -H "Origin: https://$AUTH_HOST" \
      --data-urlencode "email=smoke-remaining-checks-invalid@example.invalid" \
      "https://$AUTH_HOST/signup" 2>/dev/null || true)"
    SIGNUP_CTYPE="$(grep -i '^content-type:' "$SIGNUP_HDR" 2>/dev/null | tail -1 | tr -d '\r\n' | awk -F': ' '{print $2}' || true)"

    if [[ -z "$SIGNUP_STATUS" ]]; then
      AUTH_STATUS="FAILED"
      AUTH_MSG="the POST https://$AUTH_HOST/signup probe produced no output at all -- precondition, not a validation finding."
    elif [[ "$SIGNUP_STATUS" == "403" ]]; then
      AUTH_STATUS="FAILED"
      AUTH_MSG="POST https://$AUTH_HOST/signup (missing password) -> HTTP 403 -- the CSRF guard rejected the request (Origin header wrong/missing?) before the route's own validation ever ran; this leg cannot prove Zod .strict() fired."
    elif [[ "$SIGNUP_STATUS" == "400" ]]; then
      ok "auth login: POST /signup with a missing 'password' field -> HTTP 400 (validation rejected; no account created)"
    elif [[ "$SIGNUP_STATUS" == "200" ]]; then
      if [[ "$SIGNUP_CTYPE" != *"application/json"* ]]; then
        AUTH_STATUS="FAILED"
        AUTH_MSG="POST https://$AUTH_HOST/signup (missing password) -> HTTP 200 with Content-Type '$SIGNUP_CTYPE' -- not the application/json SvelteKit action-failure envelope this leg expects; refusing to guess whether an account was created."
      else
        SIGNUP_PARSE="$(python3 - "$SIGNUP_BODY" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    raw = f.read()
try:
    envelope = json.loads(raw)
except Exception as e:
    print("PARSE_ERROR:" + str(e))
    sys.exit(0)
if not isinstance(envelope, dict):
    print("PARSE_ERROR:not a JSON object")
    sys.exit(0)
etype = envelope.get("type")
status = envelope.get("status")
data = envelope.get("data")
data_text = data if isinstance(data, str) else json.dumps(data)
print("TYPE:" + str(etype))
print("STATUS:" + str(status))
print("MENTIONS_PASSWORD:" + ("yes" if "password" in data_text else "no"))
PYEOF
)"
        if [[ "$SIGNUP_PARSE" == PARSE_ERROR:* ]]; then
          AUTH_STATUS="FAILED"
          AUTH_MSG="POST https://$AUTH_HOST/signup (missing password) -> HTTP 200 but the body did not parse as JSON (${SIGNUP_PARSE#PARSE_ERROR:}) -- not the envelope this leg expects."
        else
          SIGNUP_TYPE="$(printf '%s\n' "$SIGNUP_PARSE" | awk -F: '/^TYPE:/{print $2; exit}')"
          SIGNUP_ENV_STATUS="$(printf '%s\n' "$SIGNUP_PARSE" | awk -F: '/^STATUS:/{print $2; exit}')"
          SIGNUP_MENTIONS_PW="$(printf '%s\n' "$SIGNUP_PARSE" | awk -F: '/^MENTIONS_PASSWORD:/{print $2; exit}')"
          if [[ "$SIGNUP_TYPE" == "success" ]]; then
            AUTH_STATUS="FAILED"
            AUTH_MSG="POST https://$AUTH_HOST/signup (missing password) -> HTTP 200 with a SvelteKit action-SUCCESS envelope (type=success) -- this would mean an account WAS created from a malformed body."
          elif [[ "$SIGNUP_TYPE" == "failure" && "$SIGNUP_ENV_STATUS" == "400" && "$SIGNUP_MENTIONS_PW" == "yes" ]]; then
            ok "auth login: POST /signup with a missing 'password' field -> action failure 400 (SvelteKit envelope over HTTP 200; Zod .strict() fired; no account created)"
          else
            AUTH_STATUS="FAILED"
            AUTH_MSG="POST https://$AUTH_HOST/signup (missing password) -> HTTP 200 envelope type='$SIGNUP_TYPE' status='$SIGNUP_ENV_STATUS' mentions-password='$SIGNUP_MENTIONS_PW' -- expected type=failure, status=400, mentioning 'password'."
          fi
        fi
      fi
    else
      AUTH_STATUS="FAILED"
      AUTH_MSG="POST https://$AUTH_HOST/signup (missing password) -> HTTP $SIGNUP_STATUS, expected 400 or a 200 SvelteKit action-failure envelope."
    fi
    rm -f "$SIGNUP_HDR" "$SIGNUP_BODY"
  fi

  if [[ "$AUTH_STATUS" != "FAILED" ]]; then
    # real-run 27 fix (2026-09-22): resolved via find_running_container()
    # first (Sec F4 ambiguity discipline, same as CA-7's own sibling
    # lookup) -- a fresh, independent resolution, never assuming CA-7's
    # own leg already ran or succeeded earlier in the SAME invocation.
    set +e
    RESEND_SIBLING_CID="$(find_running_container "$SIBLING_UUID" "$COMPOSE_SERVICE")"
    RESEND_FIND_RC=$?
    set -e
    if [[ $RESEND_FIND_RC -ne 0 ]]; then
      AUTH_STATUS="FAILED"
      AUTH_MSG="could not find exactly one running '$COMPOSE_SERVICE' container under '$SIBLING_APP_NAME' to run the Resend probe from (rc=$RESEND_FIND_RC) -- precondition, not a Resend finding."
    else
      set +e
      RESEND_OUT="$(resend_probe "$RESEND_SIBLING_CID")"
      RESEND_RC=$?
      set -e
      if [[ $RESEND_RC -ne 0 || -z "$RESEND_OUT" ]]; then
        AUTH_STATUS="FAILED"
        AUTH_MSG="could not run the Resend send-acceptance probe (rc=$RESEND_RC) -- see resend_probe()'s own header for the mechanism this replaced and why."
      elif [[ "$RESEND_OUT" == "RESEND_KEY_ABSENT" ]]; then
        info "auth login: GOTRUE_SMTP_PASS is absent on the auth container -- Resend not yet configured (infra/supabase/README.md: intentionally left unset pending a secrets-manifest.yml decision). Not a failure; the send-acceptance sub-check is not attempted."
      elif [[ "$RESEND_OUT" == "RESEND_STATUS_200" ]]; then
        ok "auth login: Resend send-acceptance probe (to delivered@resend.dev, Resend's own test address, via the sibling app container's node runtime) -> 200"
      else
        AUTH_STATUS="FAILED"
        AUTH_MSG="Resend send-acceptance probe -> $RESEND_OUT, expected RESEND_STATUS_200 or RESEND_KEY_ABSENT."
      fi
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
