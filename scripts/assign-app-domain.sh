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
# THE COOLIFY PATCH FIELD NAME IS UNMEASURED -- stated, not glossed. Every
# sibling script that READS an application's domain(s) uses the `fqdn`
# field on the `GET /applications/<uuid>` response (deploy-app.sh,
# smoke-admission-endpoint.sh both read `a.get("fqdn")`), comma-separated
# for multiple domains. Whether `PATCH /applications/<uuid>` with
# `{"fqdn": "..."}` in the body is the correct way to SET that same field
# is NOT measured anywhere in this repo -- no script has ever written it.
# The preflight below prints the EXACT body this script would PATCH and
# says so explicitly; only `--apply` actually fires it, and the apply
# path's own read-back (a fresh GET immediately after) is what turns
# "unmeasured" into "measured, this run" -- if the field name is wrong,
# the read-back will show the OLD value unchanged and this script refuses
# to report success.
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
#   0  VERIFIED -- DNS records match the target state, the Coolify PATCH
#      read-back confirms the new fqdn value, and both apex and `www`
#      answer HTTPS 200 with a valid chain.
#   1  REFUSED -- a real finding: an existing record of an unexpected
#      type at a target name, ambiguous (>1) application match, the
#      Coolify read-back does not show the PATCHed value (the field-name
#      guess was wrong), the cert poll exhausts its bound, or `www` does
#      not serve.
#   2  FAILED -- a precondition this script could not even attempt under
#      (missing .env names, box unreachable, Porkbun/Coolify API error).
#
# ORCHESTRATOR CONTRACT (BACKLOG.md §7.36 item 76's provision.sh calls
# this directly): non-interactive, no prompts, no `read`. Idempotent by
# construction -- Porkbun's `editByNameType` overwrites in place rather
# than duplicating, and a re-run against an already-correct state reports
# "already matches" on every leg rather than re-issuing a write. Every
# fact used (DNS records, the Coolify fqdn field, the live HTTPS response)
# is resolved LIVE each run, never cached.

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

step "Coolify PATCH (Sec ask: UNMEASURED field name -- printed, never assumed)"
COOLIFY_TARGET_FQDN="https://$ROOT_DOMAIN,https://www.$ROOT_DOMAIN"
info "would PATCH /api/v1/applications/<uuid> body {\"fqdn\": \"$COOLIFY_TARGET_FQDN\"}"
info "UNMEASURED: no script in this repo has ever WRITTEN this field before -- only --apply's own read-back (a fresh GET immediately after) turns this into a measured fact this run."

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

step "Resolving '$APP_NAME' and PATCHing its Coolify domain"
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
PYEOF
REMOTE
)"
APP_UUID="$(sed -n '1p' <<<"$RESOLVED")"
OLD_FQDN="$(sed -n '2p' <<<"$RESOLVED")"
UUID_RE='^[a-z0-9]{20,32}$'
[[ "$APP_UUID" =~ $UUID_RE ]] || die2 "could not resolve '$APP_NAME' to a uuid-shaped application id"
ok "resolved '$APP_NAME' -> $APP_UUID (current fqdn: ${OLD_FQDN:-<empty>})"

NEW_FQDN="$(sshx "env app_uuid=$(printf '%q' "$APP_UUID") target_fqdn=$(printf '%q' "$COOLIFY_TARGET_FQDN") bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "\$app_uuid" "\$target_fqdn" <<'PYEOF'
$PY_API_HELPER
import sys
token, uuid, target = sys.argv[1], sys.argv[2], sys.argv[3]
api(token, "PATCH", f"/applications/{uuid}", {"fqdn": target})
readback = api(token, "GET", f"/applications/{uuid}")
print(readback.get("fqdn") or "")
PYEOF
REMOTE
)"
[[ "$NEW_FQDN" == "$COOLIFY_TARGET_FQDN" ]] \
  || die "Coolify PATCH read-back shows fqdn='$NEW_FQDN', expected '$COOLIFY_TARGET_FQDN' -- the 'fqdn' PATCH field name guess (Sec-flagged UNMEASURED above) is likely WRONG. Investigate the live Coolify API's actual write path for domain assignment before re-running."
ok "Coolify PATCH read-back confirms fqdn = $NEW_FQDN"

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
[[ "$WWW_CODE" == "200" ]] || die "https://www.$ROOT_DOMAIN/ -> ${WWW_CODE:-(no response)}, expected 200 -- both domains are on the Coolify fqdn list, so www should serve directly (no HTTP redirect is configured); investigate before treating step 9 as done."
ok "https://www.$ROOT_DOMAIN/ -> 200"

step "Done"
info "DNS + Coolify domain assignment + LE cert all verified for $ROOT_DOMAIN and www.$ROOT_DOMAIN."
exit 0
