#!/usr/bin/env bash
#
# assign-app-domain.sh -- docs/deployment-runbook.md Part 3 row 9 (DNS,
# §2): point the production domain at the box and assign it to the
# `pfin-app` Coolify resource. BACKLOG.md §7.36 item 72 (W-5). DevOps-owned.
#
# THREE SURFACES, THREE TRANSPORTS -- stated up front because each one
# fails differently:
#   1. Porkbun DNS API (operator's own Mac -- public, no SSH). Sets the
#      apex A record to BOX_IP and a `www` CNAME to the apex.
#   2. Coolify API (box-only -- SSH-wrapped `localhost:8000`, same as
#      every sibling script). Assigns the domain(s) to `pfin-app`.
#   3. Public HTTPS (operator's own Mac -- public, no SSH). Polls for the
#      Let's Encrypt cert Coolify's Traefik mints once the domain resolves
#      and routes, then confirms `www` also serves.
#
# WHY THIS REFUSES TO TOUCH ANYTHING BUT THE APEX A / `www` CNAME (Sec
# ask, BACKLOG §7.36 item 72 AC) -- a registrar credential is DNS
# control, which is cert-issuance control, which is an MITM surface (the
# same reasoning that kept PORKBUN_API_KEY/PORKBUN_SECRET_KEY out of
# provision.env.example until this item landed). The full record set is
# READ and printed (so an MX/TXT row is visible in the diff, for operator
# awareness) but NEVER a write target. The refusal logic is scoped to
# what would actually CONFLICT, not to "any type other than the one this
# script writes" (Sec F-2, PR #849 review corrected an earlier version
# that refused on the apex's own MX/TXT rows -- present on the REAL
# target domain, measured live):
#   - apex: refuses only if a CNAME/ALIAS already exists there (DNS's
#     CNAME-exclusivity rule -- it cannot coexist with the A record this
#     script sets). MX/TXT/NS/SRV pass through untouched.
#   - www: refuses on anything other than A/AAAA/CNAME (unchanged).
#   - apex CAA: refuses explicitly, by name, if a CAA record exists that
#     does not authorise Let's Encrypt -- otherwise this would only ever
#     surface later as an opaque cert-poll timeout.
#
# THE COOLIFY DOMAIN-ASSIGNMENT MECHANISM IS docker_compose_domains, NOT
# fqdn -- corrected 2026-09-21 (Sec merge condition, PR #866 review, on
# `cfdc56b4`). This header PREVIOUSLY claimed the app-level `fqdn` PATCH
# field name was UNMEASURED; that was FALSE, and the correct measurement
# was already in-tree and simply had not traveled to this script. PR #862
# measured, live, on THIS SAME build_pack (dockercompose) --
#   PATCH {"fqdn": ""}    -> HTTP 422 "This field is not allowed."
#   PATCH {"domains": ""} -> HTTP 422 "The domains field cannot be used
#     for dockercompose applications. Use docker_compose_domains instead."
# (scripts/provision-worker.sh:556; see scripts/COOLIFY-API-MEASURED.md,
# entry COOLIFY-FACT-05, for the full citation).
#
# SCOPE, STATED PRECISELY (Sec F-1, PR #866 review) -- that measurement
# used an EMPTY value (""). Whether a non-empty valid URL is accepted by
# `fqdn`/`domains` on a dockercompose app is UNMEASURED; "This field is
# not allowed" reads field-level (present on every request regardless of
# value), so the honest position is "probably rejected regardless of
# value, not proven for a non-empty one." This script does not attempt
# the `fqdn`/`domains` PATCH at all, on any value, and uses the
# known-accepted mechanism instead:
#   docker_compose_domains -- an array, PATCHable (PR #862 measured only
#     `[]`, a no-op on the app-level `fqdn` column -- confirming the
#     ENDPOINT accepts a write to this field, not that a real domain
#     entry then routes traffic correctly, which remains UNMEASURED
#     until this run's own post-assignment container-env read below, and
#     fully only at step 22's live DNS cutover). Per Coolify's own
#     v4.3.18 OpenAPI schema (COOLIFY-FACT-06;
#     github.com/coollabsio/coolify tag v4.3.18, openapi.yaml,
#     `update-application-by-uuid` operation), each array element is
#     `{"name": "<compose service>", "domain": "<comma-separated
#     URLs>"}` -- this script PATCHes exactly one element, name="app"
#     (this repo's own api/docker-compose.yaml service name).
#   READ-BACK ASYMMETRY (COOLIFY-FACT-06, same source, worth stating
#     explicitly since it shapes the read-back check below): the WRITE
#     shape is an array; the RESPONSE model's own `docker_compose_domains`
#     field is documented as a plain nullable STRING, not an array --
#     Coolify evidently serializes it differently for read than it
#     accepts it for write. The exact runtime string shape is UNMEASURED
#     -- the read-back below does a SUBSTRING containment check for the
#     target domain within whatever comes back, never an exact-value
#     comparison, and logs the raw field so a future run turns this into
#     a measured fact (append it to COOLIFY-API-MEASURED.md).
#   NO TINKER FALLBACK HERE (Sec explicit instruction, PR #866 review):
#     if docker_compose_domains cannot actually route traffic, this
#     script STOPS -- a new tinker-write proposal goes to Sec FIRST, it
#     is never added unilaterally under this script's own scope, the
#     same review gate the existing TINKER-WRITE-ALLOW-07 site in
#     provision-worker.sh went through before it existed.
# The preflight below prints the EXACT body this script would PATCH;
# only `--apply` actually fires it, and the apply path's own read-back
# (a fresh GET immediately after) is what confirms the write took.
#
# KEYS NEVER TOUCH ANY PROCESS'S OWN ARGV -- same discipline as every
# sibling script that handles a credential, applied at BOTH hops this
# script has (Sec VETO-2, PR #849 review corrected an earlier version of
# this heading that only covered the SECOND hop and so read as a broader
# claim than the code made true):
#   1. python3's OWN argv -- PORKBUN_API_KEY/PORKBUN_SECRET_KEY are read
#      from `.env`, then piped to python3's STDIN (two lines, the
#      script's own first two reads), never passed as `sys.argv`
#      elements -- same shape the Coolify API token already uses via
#      `curl -K -`. The python SCRIPT BODY itself (never a secret) is
#      written to a local 0600 tempfile and unlinked immediately after
#      each call (porkbun_scratch_file() below), so it can still be
#      interpolated with `$ROOT_DOMAIN`/`$BOX_IP`/etc the same way a
#      heredoc would, without needing python3's own argv for anything
#      secret.
#   2. curl's OWN argv (inside that python process) -- the two keys are
#      written into a LOCAL 0600 tempfile as the Porkbun JSON request
#      body (Porkbun's own API puts the key pair IN the POST body, not a
#      header -- see porkbun_api() below), passed to curl via
#      `--data-binary @file`, and unlinked in a `finally` immediately
#      after each call. Neither key is ever passed as a curl `-d`/`-H`
#      argument, logged, or printed.
#
# USAGE
#   scripts/assign-app-domain.sh              # preflight: read-only, prints the DNS diff + the Coolify PATCH body
#   scripts/assign-app-domain.sh --apply      # create/edit DNS records, PATCH the Coolify domain, poll for the cert
#
#   ROOT_DOMAIN (default pfindash.com) is env-var-overridable.
#   APP_NAME (default pfin-app) is env-var-overridable.
#   BOX_IP is read from .env (script-written by provision-vps.sh --apply).
#   CERT_POLL_ATTEMPTS (default 30) / CERT_POLL_INTERVAL_SECONDS (default
#   30 -- so 30x30s = 15 minutes bounded) are env-var-overridable, for a
#   slower or faster LE issuance than the default bound assumes.
#
# EXIT CODES
#   0  VERIFIED -- DNS records match the target state, ports_exposes and
#      docker_compose_domains PATCH read-backs both confirm the new
#      values, and both apex and `www` answer HTTPS 200 with a valid
#      chain.
#   1  REFUSED -- a real finding: an existing record of an unexpected
#      type at a target name, ambiguous (>1) application match, a
#      docker_compose_domains 422 (see this script's own header --
#      distinct from a read-back mismatch), a read-back that does not
#      contain the target domain, the cert poll exhausts its bound, or
#      `www` does not serve.
#   2  FAILED -- a precondition this script could not even attempt under
#      (missing .env names, box unreachable, Porkbun/Coolify API error).
#
# ORCHESTRATOR CONTRACT (BACKLOG.md §7.36 item 76's provision.sh calls
# this directly): non-interactive, no prompts, no `read`. Idempotent by
# construction -- Porkbun's `editByNameType` overwrites in place rather
# than duplicating, and a re-run against an already-correct state reports
# "already matches" on every leg rather than re-issuing a write. Every
# fact used (DNS records, the Coolify docker_compose_domains field, the
# live HTTPS response) is resolved LIVE each run, never cached.

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

ROOT_DOMAIN="${ROOT_DOMAIN:-pfindash.com}"
APP_NAME="${APP_NAME:-pfin-app}"
CERT_POLL_ATTEMPTS="${CERT_POLL_ATTEMPTS:-30}"
CERT_POLL_INTERVAL_SECONDS="${CERT_POLL_INTERVAL_SECONDS:-30}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"

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

PORKBUN_API_KEY="$(grep -m1 '^PORKBUN_API_KEY=' "$REPO_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d '\r\n' || true)"
PORKBUN_SECRET_KEY="$(grep -m1 '^PORKBUN_SECRET_KEY=' "$REPO_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d '\r\n' || true)"
BOX_IP="$(grep -m1 '^BOX_IP=' "$REPO_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d '\r\n' || true)"

[[ -n "$PORKBUN_API_KEY" ]] || die2 "PORKBUN_API_KEY absent/blank in $REPO_ROOT/.env -- see scripts/provision.env.example"
[[ -n "$PORKBUN_SECRET_KEY" ]] || die2 "PORKBUN_SECRET_KEY absent/blank in $REPO_ROOT/.env -- see scripts/provision.env.example"
[[ -n "$BOX_IP" ]] || die2 "BOX_IP absent/blank in $REPO_ROOT/.env -- run scripts/provision-vps.sh --apply first"

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }

# --- Porkbun DNS API: local, public, keys via a 0600 tempfile body, never argv ---
read -r -d '' PY_PORKBUN_HELPER <<'PY' || true
import json, sys, subprocess, tempfile, os

def die(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)

def porkbun_api(api_key, secret_key, path, extra=None):
    if '"' in api_key or '"' in secret_key or "\n" in api_key or "\n" in secret_key:
        die("a Porkbun key contains an unexpected character -- refusing to build a request body for it")
    body = {"apikey": api_key, "secretapikey": secret_key}
    if extra:
        body.update(extra)
    old_umask = os.umask(0o077)
    fd, body_path = tempfile.mkstemp(prefix=".porkbunbody.")
    os.umask(old_umask)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(json.dumps(body).encode())
        cmd = ["curl", "-fsS", "-X", "POST", "--data-binary", f"@{body_path}",
               f"https://api.porkbun.com/api/json/v3{path}"]
        try:
            result = subprocess.run(cmd, capture_output=True, check=True)
        except subprocess.CalledProcessError as exc:
            die(f"Porkbun API POST {path} failed: exit {exc.returncode} "
                f"({exc.stderr.decode(errors='replace').strip()[:200]})")
    finally:
        try:
            os.unlink(body_path)
        except OSError:
            pass
    out = json.loads(result.stdout.decode())
    if out.get("status") != "SUCCESS":
        die(f"Porkbun API {path} returned status={out.get('status')}: {out.get('message', '')[:200]}")
    return out
PY

# porkbun_scratch_file -- a fresh LOCAL 0600 tempfile for a python SCRIPT
# BODY (never a credential value itself). Caller writes to it via
# `cat > "$(porkbun_scratch_file)" <<PYEOF ... PYEOF` (the heredoc still
# interpolates bash variables exactly as it would piping into `python3 -`
# directly), invokes `python3 "$file" <non-secret argv>` piping
# PORKBUN_API_KEY/PORKBUN_SECRET_KEY on stdin as the script's own first
# two reads, then removes the file. See this script's own header (Sec
# VETO-2, PR #849 review) for why keys move off python3's argv entirely.
porkbun_scratch_file() {
  local f
  f="$(mktemp -t pfin-porkbun-py.XXXXXX)"
  chmod 600 "$f"
  printf '%s' "$f"
}

step "Snapshotting the live Porkbun record set for '$ROOT_DOMAIN' (read-only -- every record shown, only A/AAAA/www-CNAME are ever a write target)"
PY_RETRIEVE_FILE="$(porkbun_scratch_file)"
cat > "$PY_RETRIEVE_FILE" <<PYEOF
import sys, json
api_key = sys.stdin.readline().rstrip("\n")
secret_key = sys.stdin.readline().rstrip("\n")
domain = sys.argv[1]
$PY_PORKBUN_HELPER
out = porkbun_api(api_key, secret_key, f"/dns/retrieve/{domain}")
print(json.dumps(out["records"]))
PYEOF
RECORDS_JSON="$(printf '%s\n%s\n' "$PORKBUN_API_KEY" "$PORKBUN_SECRET_KEY" | python3 "$PY_RETRIEVE_FILE" "$ROOT_DOMAIN")"
rm -f "$PY_RETRIEVE_FILE"

MX_TXT_COUNT="$(python3 -c "import json,sys; r=json.loads(sys.argv[1]); print(sum(1 for x in r if x['type'] in ('MX','TXT')))" "$RECORDS_JSON")"
info "record snapshot: $(python3 -c "import json,sys; r=json.loads(sys.argv[1]); print(len(r))" "$RECORDS_JSON") total, $MX_TXT_COUNT MX/TXT (never touched by this script)"

# --- Compute the target state and refuse on any unexpected existing type ---
DIFF_JSON="$(python3 - "$RECORDS_JSON" "$ROOT_DOMAIN" "$BOX_IP" <<'PYEOF'
import json, sys
records, domain, box_ip = json.loads(sys.argv[1]), sys.argv[2], sys.argv[3]

def at(name_suffix):
    # The Porkbun `name` field is the FULL name (e.g. "pfindash.com" or
    # "www.pfindash.com"); apex records report name == domain itself.
    target = domain if name_suffix == "" else f"{name_suffix}.{domain}"
    return [r for r in records if r["name"] == target]

apex = at("")
www = at("www")

def refuse(msg):
    print(json.dumps({"refuse": msg}))
    sys.exit(0)

# Sec F-2 (PR #849 review): only CNAME/ALIAS at the apex actually
# CONFLICT with the A record this script sets there (the DNS CNAME
# exclusivity rule -- a name cannot hold a CNAME/ALIAS alongside any
# other record type). MX/TXT/NS/SRV (and anything else) pass through
# UNTOUCHED and are never a refusal trigger. The PRIOR allowed-set
# {"A","AAAA"} refused on ANY other type, including the real target
# domain own MX x2 and TXT x2 rows sitting at the apex (measured live,
# read-only: `dig +short MX pfindash.com` / `dig +short TXT
# pfindash.com`) -- this script was never asked to understand those
# rows, only to leave them alone, and the over-broad refusal was itself
# the defect (it refused on the REAL domain, every run).
#
# NO APOSTROPHE ANYWHERE IN THIS HEREDOC BLOCK, DELIBERATELY -- one
# inside a heredoc NESTED inside this file own outer $(...) command
# substitution breaks the OUTER bash parser quote-tracking; the same
# trap this file hit once already this session (the fix there was
# identical in spirit: reword around it, do not fight it).
apex_conflict = [r for r in apex if r["type"] in ("CNAME", "ALIAS")]
if apex_conflict:
    refuse(f"apex: existing {[r['type'] for r in apex_conflict]} record(s) cannot coexist "
           f"with an A record at the same name -- refusing to overwrite or delete them")

bad_www = [r for r in www if r["type"] not in ("A", "AAAA", "CNAME")]
if bad_www:
    refuse(f"www: existing record(s) of unexpected type {[r['type'] for r in bad_www]} -- "
           f"refusing to touch anything but A/AAAA/CNAME")

# CAA governs certificate issuance -- a CAA row at the apex that does NOT
# authorise the Let s Encrypt CA blocks Traefik issuance outright. Left
# unchecked, this would only ever surface later as an opaque LE-poll
# timeout with no diagnosis. Sec F-2 (PR #849 review): name it here,
# explicitly, the moment it is visible, rather than letting a widened
# apex allowed-set make it reachable by this write path without a check.
apex_caa = [r for r in apex if r["type"] == "CAA"]
if apex_caa:
    le_authorised = any("letsencrypt.org" in (r.get("content") or "") for r in apex_caa)
    if not le_authorised:
        refuse(f"apex: a CAA record exists that does not authorise the Let s Encrypt CA "
               f"({[r.get('content') for r in apex_caa]}) -- certificate issuance will "
               f"fail. Add a CAA record authorising letsencrypt.org (or remove the "
               f"restrictive one) before retrying.")

apex_a = [r for r in apex if r["type"] == "A"]
www_cname = [r for r in www if r["type"] == "CNAME"]

plan = {
    "refuse": None,
    "apex_current": apex_a[0]["content"] if apex_a else None,
    "apex_target": box_ip,
    "apex_action": "none" if apex_a and apex_a[0]["content"] == box_ip else ("edit" if apex_a else "create"),
    "www_current": www_cname[0]["content"] if www_cname else None,
    "www_target": domain,
    "www_action": "none" if www_cname and www_cname[0]["content"].rstrip(".") == domain else ("edit" if www_cname else "create"),
}
print(json.dumps(plan))
PYEOF
)"

REFUSAL="$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d.get('refuse') or '')" "$DIFF_JSON")"
[[ -z "$REFUSAL" ]] || die "$REFUSAL"

APEX_ACTION="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['apex_action'])" "$DIFF_JSON")"
WWW_ACTION="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['www_action'])" "$DIFF_JSON")"
APEX_CURRENT="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['apex_current'] or '(absent)')" "$DIFF_JSON")"
WWW_CURRENT="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['www_current'] or '(absent)')" "$DIFF_JSON")"

step "DNS diff"
info "apex A:      $APEX_CURRENT -> $BOX_IP  [$APEX_ACTION]"
info "www  CNAME:  $WWW_CURRENT -> $ROOT_DOMAIN  [$WWW_ACTION]"

# --- ports_exposes preflight (Sec availability finding, run-10 stop, MEASURED
# live): pfin-app's ports_exposes is Coolify's OWN create-time default ('80'),
# while api/docker-compose.yaml's `expose:` block is 3000 and the app's own
# Dockerfile EXPOSEs 3000 (no PORT override anywhere in this repo) -- nothing
# in this script, provision-app.sh, or provision.sh has ever SET ports_exposes
# for the app (grep across all three: zero hits). Left uncorrected, at the DNS
# step Coolify's router would resolve the domain to the WRONG in-container
# port and 502 -- and this script's OWN cert-poll below (waiting for a 200 on
# https://$ROOT_DOMAIN/) would spin to its bound and report a failure whose
# real cause is an unrelated port misconfiguration it never looked at.
#
# Resolved here (before the preflight-exit gate, matching deploy-app.sh's own
# precedent of an SSH-backed identity read during preflight, not just apply)
# so an operator sees the mismatch before ever running --apply.
sshx true >/dev/null 2>&1 || die2 "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die2 "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

read -r -d '' PY_API_HELPER <<'PY' || true
import json, sys, subprocess

def die(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)

def api(token, method, path, body=None):
    if '"' in token or "\n" in token:
        die("Coolify API token contains an unexpected character -- refusing to build a curl config for it")
    config = 'header = "Authorization: Bearer ' + token + '"\n'
    body_path = None
    try:
        cmd = ["curl", "-fsS", "-K", "-", "-X", method]
        if body is not None:
            config += 'header = "Content-Type: application/json"\n'
            import tempfile, os
            old_umask = os.umask(0o077)
            fd, body_path = tempfile.mkstemp(dir="/root/.pfin", prefix=".curlbody.")
            os.umask(old_umask)
            with os.fdopen(fd, "wb") as f:
                f.write(json.dumps(body).encode())
            cmd += ["--data-binary", f"@{body_path}"]
        cmd += [f"http://localhost:8000/api/v1{path}"]
        try:
            result = subprocess.run(cmd, input=config.encode(), capture_output=True, check=True)
        except subprocess.CalledProcessError as exc:
            die(f"Coolify API {method} {path} failed: exit {exc.returncode} ({exc.stderr.decode(errors='replace').strip()[:200]})")
    finally:
        if body_path is not None:
            try:
                import os
                os.unlink(body_path)
            except OSError:
                pass
    return json.loads(result.stdout.decode()) if result.stdout.strip() else None
PY

step "Resolving '$APP_NAME' (identity + ports_exposes)"
RESOLVED_FULL="$(sshx "env app_query=$(printf '%q' "$APP_NAME") bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "\$app_query" <<'PYEOF'
$PY_API_HELPER
import sys
token, query = sys.argv[1], sys.argv[2]
apps = api(token, "GET", "/applications")
matches = [a for a in apps if a.get("name") == query]
if len(matches) != 1:
    die(f"expected exactly one application named '{query}', found {len(matches)}")
a = matches[0]
print(a["uuid"])
print(a.get("base_directory") or "")
print(a.get("build_pack") or "")
print(a.get("ports_exposes") or "")
PYEOF
REMOTE
)"
APP_UUID="$(sed -n '1p' <<<"$RESOLVED_FULL")"
APP_BASE_DIR_LIVE="$(sed -n '2p' <<<"$RESOLVED_FULL")"
APP_BUILD_PACK_LIVE="$(sed -n '3p' <<<"$RESOLVED_FULL")"
APP_PORTS_LIVE="$(sed -n '4p' <<<"$RESOLVED_FULL")"
UUID_RE='^[a-z0-9]{20,32}$'
[[ "$APP_UUID" =~ $UUID_RE ]] || die2 "could not resolve '$APP_NAME' to a uuid-shaped application id"
ok "resolved '$APP_NAME' -> $APP_UUID (base_directory=$APP_BASE_DIR_LIVE, build_pack=$APP_BUILD_PACK_LIVE, ports_exposes=${APP_PORTS_LIVE:-<empty>})"

# TARGET GUARD (Sec, this review): this setter must never write
# ports_exposes against a WORKER resource -- provision-worker.sh's own
# fqdn/ports_exposes clear (the CA-1 fix) writes `ports_exposes:""` for a
# worker, and a caller pointing APP_NAME at a worker by mistake (it is
# env-var-overridable) would fight that clear. TWO INDEPENDENT checks,
# both required (Sec: belt and suspenders, derive rather than name):
#   (a) POSITIVE identity -- base_directory/build_pack must be exactly
#       this script's own hardcoded expectation (this script is
#       app-specific by design, unlike deploy-app.sh's generic guard).
#   (b) NEGATIVE worker-shape -- the resolved target's OWN docker-
#       compose.yaml must not declare a serve-admission command
#       override, the SAME structural grep provision.sh's
#       worker_has_admission_guard() uses (duplicated here rather than
#       sourced -- this repo's own convention for sibling scripts, see
#       e.g. the api() helper above, copied verbatim rather than
#       imported from one shared file).
# Fails CLOSED, naming CA-1 explicitly -- corrupting a worker's
# fqdn/ports_exposes clear via a wrong-target write here would be a
# CA-1 regression, not merely a misconfiguration.
EXPECT_APP_BASE_DIR="/api"
EXPECT_APP_BUILD_PACK="dockercompose"
[[ "$APP_BASE_DIR_LIVE" == "$EXPECT_APP_BASE_DIR" ]] \
  || die2 "TARGET GUARD FAILED (CA-1): resolved application '$APP_NAME' ($APP_UUID) has base_directory='$APP_BASE_DIR_LIVE', expected '$EXPECT_APP_BASE_DIR' -- this script is app-specific and refuses to write ports_exposes against anything else, including a worker resource whose own CA-1 fqdn/ports_exposes clear this write could otherwise fight."
[[ "$APP_BUILD_PACK_LIVE" == "$EXPECT_APP_BUILD_PACK" ]] \
  || die2 "TARGET GUARD FAILED (CA-1): resolved application '$APP_NAME' ($APP_UUID) has build_pack='$APP_BUILD_PACK_LIVE', expected '$EXPECT_APP_BUILD_PACK'."
APP_COMPOSE_FILE="$REPO_ROOT/${APP_BASE_DIR_LIVE#/}/docker-compose.yaml"
[[ -f "$APP_COMPOSE_FILE" ]] || die2 "TARGET GUARD: no docker-compose.yaml at $APP_COMPOSE_FILE -- cannot verify this target is not a worker resource."
if grep -q 'serve-admission' "$APP_COMPOSE_FILE"; then
  die2 "TARGET GUARD FAILED (CA-1): resolved application '$APP_NAME' ($APP_UUID)'s own docker-compose.yaml declares a serve-admission command override -- that shape belongs to a WORKER (provider-sync), never the app resource this script exists to configure. Refusing to write ports_exposes against it."
fi
ok "TARGET GUARD passed: base_directory/build_pack match, no admission-guard shape in its compose."

# app_compose_expose_port <file> -- the ONE expose: port, comment-
# stripped FIRST (Sec ask: prove the parser still finds the real key
# through a comment, not just that it happens to work on today's
# comment-free expose: block -- this repo's own compose files are
# comment-heavy by convention, see this very block's own header
# comments a few lines up). Refuses (returns nothing; caller dies) on
# zero or MORE THAN ONE match -- never "the first of several". Not a
# general YAML/shell-quote-aware comment parser -- narrow to this one
# read, matching this repo's low-tech grep/awk convention for compose
# files (worker_has_admission_guard() in provision.sh is the same
# shape) rather than introducing a YAML library dependency.
app_compose_expose_port() {
  local file="$1"
  awk '
    /^[[:space:]]*#/ { next }
    { sub(/[[:space:]]+#.*$/, "") }
    /^[[:space:]]*expose:[[:space:]]*$/ { in_expose=1; next }
    in_expose && /^[[:space:]]*-[[:space:]]*"?[0-9]+"?[[:space:]]*$/ {
      line=$0; gsub(/[^0-9]/, "", line); print line; next
    }
    in_expose && !/^[[:space:]]*-/ { in_expose=0 }
  ' "$file"
}
EXPOSE_PORTS="$(app_compose_expose_port "$APP_COMPOSE_FILE")"
EXPOSE_COUNT="$(printf '%s\n' "$EXPOSE_PORTS" | grep -c . || true)"
[[ "$EXPOSE_COUNT" -eq 1 ]] \
  || die2 "expected exactly one 'expose:' port in $APP_COMPOSE_FILE, found $EXPOSE_COUNT -- refusing to guess which one Coolify's ports_exposes should carry (never 'the first of several')."
EXPOSE_PORT="$EXPOSE_PORTS"
ok "compose declares expose: $EXPOSE_PORT"

step "ports_exposes diff"
info "Coolify ports_exposes:  ${APP_PORTS_LIVE:-<empty>} -> $EXPOSE_PORT"
if [[ "$APP_PORTS_LIVE" == "$EXPOSE_PORT" ]]; then
  ok "ports_exposes already matches the compose's own expose: port -- nothing to change"
  PORTS_NEEDS_PATCH=0
else
  info "would PATCH /api/v1/applications/$APP_UUID body {\"ports_exposes\": \"$EXPOSE_PORT\"}"
  PORTS_NEEDS_PATCH=1
fi

step "Coolify PATCH -- docker_compose_domains (Sec-corrected mechanism, PR #866 review; see this script's own header + scripts/COOLIFY-API-MEASURED.md COOLIFY-FACT-05/06)"
COOLIFY_TARGET_DOMAIN="https://$ROOT_DOMAIN,https://www.$ROOT_DOMAIN"
APP_COMPOSE_SERVICE="app"
info "would PATCH /api/v1/applications/<uuid> body {\"docker_compose_domains\": [{\"name\": \"$APP_COMPOSE_SERVICE\", \"domain\": \"$COOLIFY_TARGET_DOMAIN\"}]}"
info "known-accepted PATCH target (fqdn/domains 422-refuse on this build_pack, empty-value measured -- see header); a real domain here actually routing traffic remains UNMEASURED until this run's own post-assignment container-env read."

if [[ "$APPLY" -eq 0 ]]; then
  step "Done (preflight)"
  info "nothing written -- re-run with --apply to create/edit DNS, PATCH Coolify, and poll for the cert."
  exit 0
fi

sshx true >/dev/null 2>&1 || die2 "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die2 "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

step "Applying DNS changes"
if [[ "$APEX_ACTION" == "none" ]]; then
  ok "apex A already correct -- nothing to change"
else
  PY_APEX_FILE="$(porkbun_scratch_file)"
  cat > "$PY_APEX_FILE" <<PYEOF
import sys
api_key = sys.stdin.readline().rstrip("\n")
secret_key = sys.stdin.readline().rstrip("\n")
domain, box_ip, action = sys.argv[1], sys.argv[2], sys.argv[3]
$PY_PORKBUN_HELPER
if action == "create":
    porkbun_api(api_key, secret_key, f"/dns/create/{domain}", {"name": "", "type": "A", "content": box_ip, "ttl": "300"})
else:
    porkbun_api(api_key, secret_key, f"/dns/editByNameType/{domain}/A/", {"content": box_ip, "ttl": "300"})
PYEOF
  printf '%s\n%s\n' "$PORKBUN_API_KEY" "$PORKBUN_SECRET_KEY" | python3 "$PY_APEX_FILE" "$ROOT_DOMAIN" "$BOX_IP" "$APEX_ACTION"
  rm -f "$PY_APEX_FILE"
  ok "apex A -> $BOX_IP ($APEX_ACTION)"
fi

if [[ "$WWW_ACTION" == "none" ]]; then
  ok "www CNAME already correct -- nothing to change"
else
  PY_WWW_FILE="$(porkbun_scratch_file)"
  cat > "$PY_WWW_FILE" <<PYEOF
import sys
api_key = sys.stdin.readline().rstrip("\n")
secret_key = sys.stdin.readline().rstrip("\n")
domain, action = sys.argv[1], sys.argv[2]
$PY_PORKBUN_HELPER
if action == "create":
    porkbun_api(api_key, secret_key, f"/dns/create/{domain}", {"name": "www", "type": "CNAME", "content": domain, "ttl": "300"})
else:
    porkbun_api(api_key, secret_key, f"/dns/editByNameType/{domain}/CNAME/www", {"content": domain, "ttl": "300"})
PYEOF
  printf '%s\n%s\n' "$PORKBUN_API_KEY" "$PORKBUN_SECRET_KEY" | python3 "$PY_WWW_FILE" "$ROOT_DOMAIN" "$WWW_ACTION"
  rm -f "$PY_WWW_FILE"
  ok "www CNAME -> $ROOT_DOMAIN ($WWW_ACTION)"
fi

# ports_exposes PATCH -- BEFORE the domain is assigned (below), on
# purpose: Coolify's router needs the RIGHT in-container port wired
# before a domain routes traffic at it, or the cert-poll below spins on
# an unrelated 502. Reuses $APP_UUID/$EXPOSE_PORT/$PORTS_NEEDS_PATCH
# already resolved and target-guarded in the preflight above -- no
# second resolution, no second guard check.
if [[ "$PORTS_NEEDS_PATCH" -eq 1 ]]; then
  step "PATCHing '$APP_NAME's ports_exposes to match its own compose"
  NEW_PORTS="$(sshx "env app_uuid=$(printf '%q' "$APP_UUID") target_port=$(printf '%q' "$EXPOSE_PORT") bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "\$app_uuid" "\$target_port" <<'PYEOF'
$PY_API_HELPER
import sys
token, uuid, target = sys.argv[1], sys.argv[2], sys.argv[3]
api(token, "PATCH", f"/applications/{uuid}", {"ports_exposes": target})
readback = api(token, "GET", f"/applications/{uuid}")
print(readback.get("ports_exposes") or "")
PYEOF
REMOTE
)"
  [[ "$NEW_PORTS" == "$EXPOSE_PORT" ]] \
    || die "ports_exposes PATCH read-back shows '$NEW_PORTS', expected '$EXPOSE_PORT' -- investigate the live Coolify API's actual write path for this field before treating step 9 as done."
  ok "ports_exposes PATCH read-back confirms ports_exposes = $NEW_PORTS"
else
  ok "ports_exposes already correct (checked in preflight) -- no PATCH issued"
fi

step "Resolving '$APP_NAME' and PATCHing its Coolify domain (docker_compose_domains -- COOLIFY-FACT-05/06)"
# Status-preserving api() (same shape as provision-worker.sh's own,
# ALREADY Sec-reviewed there) -- NOT the earlier `curl -fsS` shape this
# file used for the fqdn attempt, which loses the response BODY on any
# non-2xx (`-f` suppresses it) and therefore could never have built a
# distinct 422 message even before the fqdn/domains mechanism was
# retired. api_allow_status() lets exactly ONE call (the
# docker_compose_domains PATCH below) treat one specific extra status as
# non-fatal so this script can name it precisely; every other call still
# dies on any non-2xx via api(), unchanged from this file's own
# established discipline.
read -r -d '' PY_API_HELPER <<'PY' || true
import json, sys, subprocess, tempfile, os

def die(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)

def _curl(token, method, path, body=None):
    if '"' in token or "\n" in token:
        die("Coolify API token contains an unexpected character -- refusing to build a curl config for it")
    config = 'header = "Authorization: Bearer ' + token + '"\n'
    body_path = None
    try:
        cmd = ["curl", "-sS", "-K", "-", "-X", method, "-w", "\n%{http_code}"]
        if body is not None:
            config += 'header = "Content-Type: application/json"\n'
            old_umask = os.umask(0o077)
            fd, body_path = tempfile.mkstemp(dir="/root/.pfin", prefix=".curlbody.")
            os.umask(old_umask)
            with os.fdopen(fd, "wb") as f:
                f.write(json.dumps(body).encode())
            cmd += ["--data-binary", f"@{body_path}"]
        cmd += [f"http://localhost:8000/api/v1{path}"]
        result = subprocess.run(cmd, input=config.encode(), capture_output=True)
    finally:
        if body_path is not None:
            try:
                os.unlink(body_path)
            except OSError:
                pass
    if result.returncode != 0:
        die(f"Coolify API {method} {path} failed: curl exit {result.returncode} ({result.stderr.decode(errors='replace').strip()[:200]})")
    raw = result.stdout.decode()
    out, _, code = raw.rpartition("\n")
    if not code.isdigit():
        die(f"Coolify API {method} {path}: could not parse an HTTP status code off curl's own -w output -- refusing to guess success or failure. Raw tail: {raw[-200:]!r}")
    return int(code), out

def api(token, method, path, body=None):
    status, out = _curl(token, method, path, body)
    if not (200 <= status < 300):
        die(f"Coolify API {method} {path} -> HTTP {status}: {out.strip()[:500]}")
    return json.loads(out) if out.strip() else None

def api_allow_status(token, method, path, body, allowed_extra_status):
    status, out = _curl(token, method, path, body)
    if status == allowed_extra_status:
        return status, out
    if not (200 <= status < 300):
        die(f"Coolify API {method} {path} -> HTTP {status}: {out.strip()[:500]}")
    return status, (json.loads(out) if out.strip() else None)
PY

RESOLVED="$(sshx "env app_query=$(printf '%q' "$APP_NAME") bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "\$app_query" <<'PYEOF'
$PY_API_HELPER
import sys
token, query = sys.argv[1], sys.argv[2]
apps = api(token, "GET", "/applications")
matches = [a for a in apps if a.get("name") == query]
if len(matches) != 1:
    die(f"expected exactly one application named '{query}', found {len(matches)}")
print(matches[0]["uuid"])
print(matches[0].get("fqdn") or "")
print(matches[0].get("docker_compose_domains") or "")
PYEOF
REMOTE
)"
APP_UUID="$(sed -n '1p' <<<"$RESOLVED")"
OLD_FQDN="$(sed -n '2p' <<<"$RESOLVED")"
OLD_COMPOSE_DOMAINS="$(sed -n '3p' <<<"$RESOLVED")"
UUID_RE='^[a-z0-9]{20,32}$'
[[ "$APP_UUID" =~ $UUID_RE ]] || die2 "could not resolve '$APP_NAME' to a uuid-shaped application id"
ok "resolved '$APP_NAME' -> $APP_UUID (current fqdn: ${OLD_FQDN:-<empty>}, current docker_compose_domains: ${OLD_COMPOSE_DOMAINS:-<empty>})"

PATCH_OUT="$(sshx "env app_uuid=$(printf '%q' "$APP_UUID") service=$(printf '%q' "$APP_COMPOSE_SERVICE") target_domain=$(printf '%q' "$COOLIFY_TARGET_DOMAIN") bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "\$app_uuid" "\$service" "\$target_domain" <<'PYEOF'
$PY_API_HELPER
import sys
token, uuid, service, target = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
status, body = api_allow_status(token, "PATCH", f"/applications/{uuid}",
    {"docker_compose_domains": [{"name": service, "domain": target}]}, 422)
if status == 422:
    print("PATCH_422")
    print((body or "")[:500].replace("\n", " "))
    sys.exit(0)
readback = api(token, "GET", f"/applications/{uuid}")
print("PATCH_OK")
print(readback.get("docker_compose_domains") or "")
print(readback.get("fqdn") or "")
PYEOF
REMOTE
)"
PATCH_STATUS="$(sed -n '1p' <<<"$PATCH_OUT")"
if [[ "$PATCH_STATUS" == "PATCH_422" ]]; then
  PATCH_422_BODY="$(sed -n '2p' <<<"$PATCH_OUT")"
  die "docker_compose_domains PATCH on '$APP_NAME' ($APP_UUID, build_pack=$APP_BUILD_PACK_LIVE) refused with HTTP 422: $PATCH_422_BODY -- this is the KNOWN-ACCEPTED mechanism (COOLIFY-FACT-05/06 measured only \`[]\`, never a real element; see this script's own header) so a 422 here means the ELEMENT SHAPE or SERVICE NAME is wrong, not that the field itself is refused. Investigate against scripts/COOLIFY-API-MEASURED.md before re-running -- do NOT fall back to a tinker write for domain ASSIGNMENT without a Sec proposal first (see header: no tinker fallback here)."
fi
NEW_COMPOSE_DOMAINS="$(sed -n '2p' <<<"$PATCH_OUT")"
NEW_FQDN_AFTER_COMPOSE_PATCH="$(sed -n '3p' <<<"$PATCH_OUT")"
if [[ "$NEW_COMPOSE_DOMAINS" != *"$ROOT_DOMAIN"* ]]; then
  die "docker_compose_domains PATCH 200'd but the read-back ('$NEW_COMPOSE_DOMAINS') does not contain '$ROOT_DOMAIN' -- the write shape (COOLIFY-FACT-06, schema-documented, not independently confirmed by a live element-carrying PATCH before this run) may not be what Coolify actually expects. Investigate before treating step 9 as done; do not assume success from a 200 alone."
fi
ok "docker_compose_domains PATCH read-back contains '$ROOT_DOMAIN': $NEW_COMPOSE_DOMAINS"
info "app-level fqdn after this PATCH: ${NEW_FQDN_AFTER_COMPOSE_PATCH:-<empty>} -- INFORMATIONAL ONLY (whether Coolify derives/mirrors fqdn from docker_compose_domains is UNMEASURED; this script's success does not depend on it)."

# Post-assignment container-env read (team-lead, Sec-adjacent ask) --
# NAMES ONLY, box-side grep, never a value: tests whether CA-1's own
# admission-guard-relevant surface can even SEE a compose-service domain
# at all. Coolify only injects env at container START (same caveat as
# provision-worker.sh's own stale-container warning), so if the app
# hasn't been redeployed since this PATCH, there is nothing to read yet
# -- informational, never a hard gate on this script's own exit code.
step "Post-assignment container-env read (informational -- names only, never a value)"
EXISTING_APP_CID="$(sshx "docker ps --filter 'name=$APP_UUID' --filter 'status=running' --format '{{.ID}}' | head -1" </dev/null 2>/dev/null || true)"
if [[ -z "$EXISTING_APP_CID" ]]; then
  info "no running container for '$APP_NAME' yet -- container-env read not applicable until the next deploy picks up this domain assignment."
else
  ENV_NAMES_FOUND="$(sshx "docker exec $EXISTING_APP_CID env | grep -oE '^(SERVICE_FQDN_[A-Za-z0-9_]*|COOLIFY_FQDN|COOLIFY_URL)=' | cut -d= -f1 | sort -u" </dev/null 2>/dev/null || true)"
  if [[ -z "$ENV_NAMES_FOUND" ]]; then
    info "MEASURED $(date -u +%Y-%m-%d): container $EXISTING_APP_CID for '$APP_NAME' injects NONE of SERVICE_FQDN_*/COOLIFY_FQDN/COOLIFY_URL -- if this persists after a redeploy, that is a CONTROL GAP to report (CA-1's admission-guard-relevant surface would have nothing to see for this app), not something to paper over."
  else
    info "MEASURED $(date -u +%Y-%m-%d): container $EXISTING_APP_CID for '$APP_NAME' injects: $(printf '%s' "$ENV_NAMES_FOUND" | tr '\n' ' ')"
  fi
  info "Append this line to scripts/COOLIFY-API-MEASURED.md's COOLIFY-FACT-06 entry (names only, this run's date, whether a redeploy had already happened) -- this script does not write to that file itself."
fi

step "Polling for the Let's Encrypt cert on https://$ROOT_DOMAIN (bounded: $CERT_POLL_ATTEMPTS x ${CERT_POLL_INTERVAL_SECONDS}s)"
CERT_OK=0
for ((i = 1; i <= CERT_POLL_ATTEMPTS; i++)); do
  CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$ROOT_DOMAIN/" 2>/dev/null || true)"
  if [[ "$CODE" == "200" ]]; then
    CERT_OK=1
    ok "https://$ROOT_DOMAIN/ -> 200 (attempt $i/$CERT_POLL_ATTEMPTS)"
    break
  fi
  info "attempt $i/$CERT_POLL_ATTEMPTS: https://$ROOT_DOMAIN/ -> ${CODE:-(no response)} -- waiting for DNS propagation + LE issuance"
  sleep "$CERT_POLL_INTERVAL_SECONDS"
done
[[ "$CERT_OK" -eq 1 ]] || die "https://$ROOT_DOMAIN/ never returned 200 within $((CERT_POLL_ATTEMPTS * CERT_POLL_INTERVAL_SECONDS))s -- DNS may not have propagated yet, or Coolify/Traefik has not issued the cert. Re-run this script (idempotent) once you've confirmed DNS has propagated (\`dig A $ROOT_DOMAIN\`)."

step "Confirming www.$ROOT_DOMAIN also serves"
WWW_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://www.$ROOT_DOMAIN/" 2>/dev/null || true)"
[[ "$WWW_CODE" == "200" ]] || die "https://www.$ROOT_DOMAIN/ -> ${WWW_CODE:-(no response)}, expected 200 -- both domains are in the PATCHed docker_compose_domains entry's comma-separated 'domain' value, so www should serve directly (no HTTP redirect is configured); investigate before treating step 9 as done."
ok "https://www.$ROOT_DOMAIN/ -> 200"

step "Done"
info "DNS + Coolify domain assignment + LE cert all verified for $ROOT_DOMAIN and www.$ROOT_DOMAIN."
exit 0
