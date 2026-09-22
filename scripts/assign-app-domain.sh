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
#   - www: handled by MEASURED type -- an existing A record is EDITED IN
#     PLACE to box_ip (never a CNAME created alongside it); an existing
#     CNAME is edited in place to the apex domain (unchanged); no record
#     creates a CNAME, as before. Anything else refuses, by name
#     (corrected 2026-09-22 -- AAAA is no longer a passed-through type;
#     see the live measurement below for why).
#   - apex CAA: refuses explicitly, by name, if a CAA record exists that
#     does not authorise Let's Encrypt -- otherwise this would only ever
#     surface later as an opaque cert-poll timeout.
#
# LIVE MEASUREMENT, 2026-09-22 ~15:45Z (F/CTO-run `--from dns
# --confirm-cutover`, real cutover attempt) -- www.pfindash.com already
# existed as an A record (ttl 600), NOT a CNAME. A follow-up read-only
# measurement confirmed its content already MATCHES box_ip (same as the
# apex A) -- the defect was never about a WRONG value at www, only that
# this script never checked for an A record there at all, and would
# have attempted a doomed CNAME create regardless of what the existing
# A pointed at. Porkbun refuses a CNAME create beside an existing A of
# the same name (dns/create -> HTTP 400; a name cannot hold a CNAME
# alongside any other record type). A second, independent defect
# compounded this: porkbun_api() used `curl -fsS`, which discards the
# response body on any non-2xx, so the actual Porkbun error (its own
# `message` field explaining WHY) never reached the operator -- only a
# bare "exit 56" curl transport error. Both fixed in this same pass;
# see porkbun_api() below for the second fix and the DIFF_JSON python
# block below for the first.
#
# There was also a `*.pfindash.com` wildcard A record, MEASURED
# pointing at the incumbent host (not box_ip) -- F/CTO ruled to delete
# it, and it WAS deleted the same day (id-based, exactly-one guard,
# re-read confirmed zero wildcard records afterward; apex + www A both
# confirmed intact and pointing at box_ip). The wildcard check below
# stays as a GENERAL read-only guard regardless -- it will simply not
# fire on this box any more, but a future wildcard record (re-added by
# hand, or on a different domain this script is pointed at via
# ROOT_DOMAIN) is still worth a WARN, never a silent surprise at
# cutover.
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
#   READ-BACK ASYMMETRY (COOLIFY-FACT-06/15) -- the WRITE shape is an
#     array; the RESPONSE model's own `docker_compose_domains` field is
#     documented as a plain nullable STRING, not an array. MEASURED
#     2026-09-22 ~17:10Z (COOLIFY-FACT-15, run 21 hit this live): the
#     runtime string content is itself a JSON OBJECT keyed by compose
#     service name (`{"app":{"domain":"https://a,https://b"}}`), NOT a
#     flat comma-separated list -- the original read-back parser
#     (splitting the raw string on commas directly) produced a single
#     nonsense "domain" equal to the whole JSON blob and could never
#     match. The read-back below now `json.loads()`s the string a
#     SECOND time, selects the target service key, and compares ITS
#     `domain` value (split on commas) as a SET against the intended
#     domain set (Sec F-4, PR #866 review: a substring/containment check
#     passes even with extra domains present, or on a superstring
#     near-miss like "notexample.com" containing "example.com" --
#     neither means this app now serves EXACTLY the intended domains),
#     refusing by name if the service key is absent or an unexpected
#     second one is present -- see COOLIFY-FACT-15 for the full raw
#     strings.
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
# THE CONTAINER-ENV FACT IS MEASURED ONLY POST-REDEPLOY (team-lead,
# run-21 fix follow-up, 2026-09-22) -- Coolify only injects
# SERVICE_FQDN_*/COOLIFY_FQDN/COOLIFY_URL and regenerates Traefik proxy
# labels at container START, never retroactively for an already-running
# one. A domain PATCH alone (everything above) leaves the OLD
# pre-assignment container running; reading ITS env, or polling for a
# cert against the routing IT was started with, would be a
# READ-OF-THE-WRONG-THING, not a measurement -- the exact mistake an
# earlier draft of this section made. `--apply` therefore ALWAYS
# triggers a redeploy (POST /deploy + poll, the same mechanism
# deploy-app.sh uses, duplicated here per this repo's own sibling-script
# convention) immediately after a successful domain PATCH, before the
# env read or the cert poll below: the env read then REQUIRES the new
# container id to differ from whatever was running pre-redeploy
# (refusing, never silently reading the old one), and the cert poll
# runs against a container that actually carries the new routing.
#
# ENV-READ VALUES RELAXATION (Sec, run-21 fix follow-up): the
# post-redeploy env read prints VALUES, not just names, for EXACTLY
# THREE families -- `COOLIFY_FQDN`, `COOLIFY_URL`, `SERVICE_FQDN_*` --
# a deliberate, narrow exception to this repo's names-only discipline
# for env-store contents elsewhere. Justified because (a) these are
# public HOSTNAMES, not secrets -- the sslip form already embeds a uuid
# that is in this repo in plaintext (COOLIFY-FACT-04) -- and (b) this
# app now carries BOTH the app-level sslip `fqdn` and the
# service-level `docker_compose_domains`, so only the VALUE (not just
# the name) attributes which source produced which route; naming alone
# cannot distinguish them. Nothing outside these three exact names is
# ever read or printed by this step.
#
# SSLIP REACHABILITY RE-MEASURED POST-REDEPLOY, WITH A CONTROL (Sec,
# same follow-up): COOLIFY-FACT-05/06's own "not routed, 404 identical
# to control" fact was measured BEFORE this app carried
# `docker_compose_domains` at all and no longer covers this state --
# this app may now be reachable via BOTH the intended domain AND its
# own Coolify-assigned sslip default, an unintended second route. The
# post-redeploy step re-probes the app's own sslip host (http AND
# https) against a nonexistent-host control on the same box, prints
# both side by side, and reports a status-code DIVERGENCE as a
# FINDING, never a failure -- this script has no mechanism to change
# `fqdn` and does not attempt to; it only surfaces the observation
# before DNS cutover completes.
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
#   DEPLOY_POLL_ATTEMPTS (default 90) / DEPLOY_POLL_INTERVAL_SECONDS
#   (default 4 -- so 90x4s = 6 minutes bounded) are the same shape,
#   env-var-overridable, for the post-domain-assignment redeploy's own
#   status poll (see step 9 below) -- FAILS CLOSED (refuses, never falls
#   through to the container-env read) if the deployment has not reached
#   status=finished within the bound.
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
#      contain the target domain, the post-domain-assignment redeploy
#      failing to reach status=finished within DEPLOY_POLL_ATTEMPTS x
#      DEPLOY_POLL_INTERVAL_SECONDS, the post-redeploy container-env read
#      failing to resolve a SINGLE, DIFFERENT-from-pre-deploy,
#      CONFIRMED-RUNNING container (no container / ambiguous /
#      non-container-id-shaped / docker ps, inspect, or exec itself
#      failing / identical to the pre-redeploy container / docker
#      inspect not reporting State.Running=true -- see
#      resolve_running_cid(), confirm_container_running(), and their
#      callers below), the cert poll exhausts its bound, or `www` does
#      not serve.
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
# Sec ask (run-21 fix follow-up, redeploy addenda): the redeploy-status
# poll's bound must be a NAMED, fail-closed timeout like the cert poll
# above, not a hardcoded loop -- 90x4s=360s is the real-world default,
# but a fence needs to exercise the timeout path in well under a second.
DEPLOY_POLL_ATTEMPTS="${DEPLOY_POLL_ATTEMPTS:-90}"
DEPLOY_POLL_INTERVAL_SECONDS="${DEPLOY_POLL_INTERVAL_SECONDS:-4}"
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

    def scrub(t):
        # Sec F-1, PR #877 review: this function's whole purpose is to
        # start printing response bodies -f used to discard, and the
        # SUBMITTED REQUEST body carries both Porkbun keys ({"apikey":
        # ..., "secretapikey": ...}). If Porkbun ever echoes the
        # submitted request back on a validation error -- exactly the
        # undocumented-response shape the raw-text fallbacks below exist
        # for -- a key would print to the operator's terminal and into
        # a run log, which gets pasted into chat/PR bodies. Applied to
        # every piece of Porkbun response text this function ever
        # prints, not just the three sites Sec named, since it costs
        # nothing and the alternative is trusting a fallback path to
        # never contain one. Deliberately NOT applied to the Coolify
        # api() helper below -- its token travels as a header via `-K -`
        # on stdin, never in the request body, so its own raw-body
        # prints cannot carry the credential; scrubbing there would be
        # cargo-culting, per Sec's own explicit instruction.
        return t.replace(api_key, "<redacted>").replace(secret_key, "<redacted>")

    body = {"apikey": api_key, "secretapikey": secret_key}
    if extra:
        body.update(extra)
    old_umask = os.umask(0o077)
    fd, body_path = tempfile.mkstemp(prefix=".porkbunbody.")
    os.umask(old_umask)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(json.dumps(body).encode())
        # Status-preserving, not `-fsS` (measured 2026-09-22: a Porkbun
        # 400 on the www CNAME create surfaced ONLY as "curl: (56) The
        # requested URL returned error: 400" -- `-f` discards the
        # response BODY on any non-2xx, so Porkbun own `message` field
        # explaining WHY never reached the operator; same class as the
        # Coolify api() `-f` fix this file already carries -- see that
        # helper below for the identical shape, already Sec-reviewed
        # there).
        cmd = ["curl", "-sS", "-X", "POST", "--data-binary", f"@{body_path}",
               "-w", "\n%{http_code}",
               f"https://api.porkbun.com/api/json/v3{path}"]
        result = subprocess.run(cmd, capture_output=True)
    finally:
        try:
            os.unlink(body_path)
        except OSError:
            pass
    if result.returncode != 0:
        die(f"Porkbun API POST {path} failed: curl exit {result.returncode} "
            f"({result.stderr.decode(errors='replace').strip()[:200]})")
    raw = result.stdout.decode()
    out_text, _, code = raw.rpartition("\n")
    if not code.isdigit():
        die(f"Porkbun API POST {path}: could not parse an HTTP status code off curls own -w output -- refusing to guess success or failure. Raw tail: {scrub(raw)[-200:]!r}")
    status = int(code)
    try:
        out = json.loads(out_text)
    except json.JSONDecodeError:
        die(f"Porkbun API POST {path} -> HTTP {status}: response body was not valid JSON: {scrub(out_text)[:200]!r}")
    if not (200 <= status < 300):
        die(f"Porkbun API POST {path} -> HTTP {status}: {scrub(out.get('message', out_text))[:300]}")
    if out.get("status") != "SUCCESS":
        die(f"Porkbun API {path} returned status={out.get('status')}: {scrub(out.get('message', ''))[:200]}")
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
wildcard = at("*")

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

# www handled by MEASURED type (2026-09-22 ~15:45Z, this file own
# header): www already existed as an A record on the real domain, and
# Porkbun refuses a CNAME create beside an existing A of the same name
# (dns/create -> HTTP 400) -- a name cannot hold a CNAME alongside any
# other record type. Three, and only three, handled shapes; anything
# else refuses, by name, rather than falling through to a guessed
# create that a live 400 would then explain badly:
#   A     -> edit that A in place to box_ip. Never create a CNAME
#            alongside it -- that IS the conflict measured live.
#   CNAME -> existing edit-in-place path, unchanged.
#   none  -> create a CNAME to the apex domain, as before.
www_a = [r for r in www if r["type"] == "A"]
www_cname = [r for r in www if r["type"] == "CNAME"]
www_other = [r for r in www if r["type"] not in ("A", "CNAME")]
if www_other:
    refuse(f"www: existing record(s) of unexpected type {[r['type'] for r in www_other]} -- "
           f"refusing to touch anything but A (edited in place to the box) or CNAME")

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

if www_a:
    www_type = "a"
    www_current = www_a[0]["content"]
    www_target = box_ip
    www_action = "none" if www_current == box_ip else "edit"
elif www_cname:
    www_type = "cname"
    www_current = www_cname[0]["content"]
    www_target = domain
    www_action = "none" if www_current.rstrip(".") == domain else "edit"
else:
    www_type = "cname"
    www_current = None
    www_target = domain
    www_action = "create"

# Wildcard A -- READ-ONLY, never a refusal and never a write target. A
# wildcard A pointing at the incumbent was MEASURED PRESENT on this
# domain 2026-09-22 and DELETED the same day by F/CTO ruling -- this
# check stays general regardless (it simply will not fire on this box
# any more): if a future one points somewhere other than box_ip,
# cutover would leave it dangling on the incumbent host, an F/CTO
# decision this script does not make on its own.
wildcard_a = [r for r in wildcard if r["type"] == "A"]
wildcard_warning = None
if wildcard_a and wildcard_a[0]["content"] != box_ip:
    wildcard_warning = wildcard_a[0]["content"]

plan = {
    "refuse": None,
    "apex_current": apex_a[0]["content"] if apex_a else None,
    "apex_target": box_ip,
    "apex_action": "none" if apex_a and apex_a[0]["content"] == box_ip else ("edit" if apex_a else "create"),
    "www_type": www_type,
    "www_current": www_current,
    "www_target": www_target,
    "www_action": www_action,
    "wildcard_warning": wildcard_warning,
}
print(json.dumps(plan))
PYEOF
)"

REFUSAL="$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d.get('refuse') or '')" "$DIFF_JSON")"
[[ -z "$REFUSAL" ]] || die "$REFUSAL"

APEX_ACTION="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['apex_action'])" "$DIFF_JSON")"
WWW_TYPE="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['www_type'])" "$DIFF_JSON")"
WWW_ACTION="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['www_action'])" "$DIFF_JSON")"
WWW_TARGET="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['www_target'])" "$DIFF_JSON")"
APEX_CURRENT="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['apex_current'] or '(absent)')" "$DIFF_JSON")"
WWW_CURRENT="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['www_current'] or '(absent)')" "$DIFF_JSON")"
WILDCARD_WARNING="$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('wildcard_warning') or '')" "$DIFF_JSON")"

step "DNS diff"
info "apex A:      $APEX_CURRENT -> $BOX_IP  [$APEX_ACTION]"
if [[ "$WWW_TYPE" == "a" ]]; then
  info "www  A:      $WWW_CURRENT -> $WWW_TARGET  [$WWW_ACTION] (CNAME not created -- an A record already exists at www; measured 2026-09-22)"
else
  info "www  CNAME:  $WWW_CURRENT -> $WWW_TARGET  [$WWW_ACTION]"
fi
if [[ -n "$WILDCARD_WARNING" ]]; then
  info "(warn) wildcard A (*.${ROOT_DOMAIN}) points elsewhere: $WILDCARD_WARNING (not $BOX_IP) -- cutover leaves it dangling on the incumbent; F/CTO decision, not changed by this script."
fi

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
  if [[ "$WWW_TYPE" == "a" ]]; then
    ok "www A already -> box -- nothing to change"
  else
    ok "www CNAME already correct -- nothing to change"
  fi
else
  # www_type "a" (MEASURED 2026-09-22 ~15:45Z) edits the EXISTING A
  # record in place to box_ip -- never creates a CNAME alongside it,
  # which is the exact conflict a live Porkbun 400 measured. action can
  # only be "edit" when www_type is "a" (an A record that already
  # exists cannot also be the "create" case -- see the DIFF_JSON python
  # above), but this still branches on action defensively rather than
  # assuming that invariant holds.
  PY_WWW_FILE="$(porkbun_scratch_file)"
  cat > "$PY_WWW_FILE" <<PYEOF
import sys
api_key = sys.stdin.readline().rstrip("\n")
secret_key = sys.stdin.readline().rstrip("\n")
domain, box_ip, action, wtype = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
$PY_PORKBUN_HELPER
if wtype == "a":
    porkbun_api(api_key, secret_key, f"/dns/editByNameType/{domain}/A/www", {"content": box_ip, "ttl": "300"})
elif action == "create":
    porkbun_api(api_key, secret_key, f"/dns/create/{domain}", {"name": "www", "type": "CNAME", "content": domain, "ttl": "300"})
else:
    porkbun_api(api_key, secret_key, f"/dns/editByNameType/{domain}/CNAME/www", {"content": domain, "ttl": "300"})
PYEOF
  printf '%s\n%s\n' "$PORKBUN_API_KEY" "$PORKBUN_SECRET_KEY" | python3 "$PY_WWW_FILE" "$ROOT_DOMAIN" "$BOX_IP" "$WWW_ACTION" "$WWW_TYPE"
  rm -f "$PY_WWW_FILE"
  if [[ "$WWW_TYPE" == "a" ]]; then
    ok "www A -> $BOX_IP ($WWW_ACTION; CNAME not created because an A record exists)"
  else
    ok "www CNAME -> $ROOT_DOMAIN ($WWW_ACTION)"
  fi
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
import sys, json
token, uuid, service, target = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
status, body = api_allow_status(token, "PATCH", f"/applications/{uuid}",
    {"docker_compose_domains": [{"name": service, "domain": target}]}, 422)
if status == 422:
    print("PATCH_422")
    print((body or "")[:500].replace("\n", " "))
    sys.exit(0)
readback = api(token, "GET", f"/applications/{uuid}")
live_raw = readback.get("docker_compose_domains") or ""
print("PATCH_OK")
print(live_raw)
print(readback.get("fqdn") or "")

# MEASURED 2026-09-22 ~17:10Z, Coolify 4.3.18 (COOLIFY-FACT-15): the
# read-back is NOT a plain comma-separated domain list -- it is a JSON
# STRING whose own content is a JSON OBJECT keyed by compose service
# name, e.g. the outer field value equals the TEXT
# {"app":{"domain":"https://a,https://b"}} (already unescaped once by
# the OUTER json.loads() this function ran on the whole response body
# -- a SECOND json.loads() below parses that text into the real
# structure). The PATCH itself still sends the array form
# [{"name": service, "domain": target}] -- Coolify accepts that shape
# and stores/serves the object shape back; this is a genuine write/read
# asymmetry, not a bug in the write. normalize_domains() below tolerates
# BOTH the measured object form and the array form (Coolify might
# change this later), rather than assuming only one shape forever.
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

services = normalize_domains(live_raw)
if services is None:
    print("DOMAIN_READBACK_UNPARSEABLE")
    print(str(live_raw)[:300].replace("\n", " "))
elif service not in services:
    print("DOMAIN_SERVICE_ABSENT")
    print(",".join(sorted(services.keys())) or "-")
elif len(services) > 1:
    print("DOMAIN_SERVICE_UNEXPECTED_EXTRA")
    print(",".join(sorted(k for k in services if k != service)))
else:
    # Sec F-4 (PR #866 review): a CONTAINS($ROOT_DOMAIN) check passes
    # even with EXTRA domains present in the live comma-separated list,
    # or on a superstring near-miss (e.g. notexample.com contains
    # example.com) -- neither means this app now serves EXACTLY the
    # domains intended. Compare SETS, not substrings, say precisely
    # what differs.
    intended_set = {d.strip() for d in target.split(",") if d.strip()}
    live_set = services[service]
    if live_set != intended_set:
        print("DOMAIN_SET_MISMATCH")
        print(",".join(sorted(intended_set - live_set)) or "-")
        print(",".join(sorted(live_set - intended_set)) or "-")
    else:
        print("DOMAIN_SET_OK")
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
DOMAIN_SET_CHECK="$(sed -n '4p' <<<"$PATCH_OUT")"
# MEASURED 2026-09-22 ~17:10Z (COOLIFY-FACT-15): the read-back is a JSON
# string whose own content is a JSON object keyed by compose service
# name, not a plain comma-separated list -- the python block above
# parses both that measured shape and the array shape the PATCH itself
# sends (tolerant of either), so this bash side only ever sees one of
# these five named result tokens, never raw JSON to re-parse itself.
case "$DOMAIN_SET_CHECK" in
  DOMAIN_SET_OK)
    ;;
  DOMAIN_READBACK_UNPARSEABLE)
    RAW_TAIL="$(sed -n '5p' <<<"$PATCH_OUT")"
    die "docker_compose_domains PATCH 200'd but the read-back could not be parsed as JSON (even after accounting for the field's own string-of-JSON shape, COOLIFY-FACT-06/15) -- raw: '$RAW_TAIL'. Investigate before treating step 9 as done."
    ;;
  DOMAIN_SERVICE_ABSENT)
    OTHER_SERVICES="$(sed -n '5p' <<<"$PATCH_OUT")"
    die "docker_compose_domains PATCH 200'd but the read-back has no '$APP_COMPOSE_SERVICE' service key -- services present: $OTHER_SERVICES. Investigate before treating step 9 as done."
    ;;
  DOMAIN_SERVICE_UNEXPECTED_EXTRA)
    OTHER_SERVICES="$(sed -n '5p' <<<"$PATCH_OUT")"
    die "docker_compose_domains PATCH 200'd but the read-back carries an unexpected extra service key beyond '$APP_COMPOSE_SERVICE': $OTHER_SERVICES -- refusing to guess which service is authoritative. Investigate before treating step 9 as done."
    ;;
  DOMAIN_SET_MISMATCH)
    MISSING_DOMAINS="$(sed -n '5p' <<<"$PATCH_OUT")"
    EXTRA_DOMAINS="$(sed -n '6p' <<<"$PATCH_OUT")"
    die "docker_compose_domains PATCH 200'd but the read-back domain SET for '$APP_COMPOSE_SERVICE' does not exactly equal the intended set -- live='$NEW_COMPOSE_DOMAINS' intended='$COOLIFY_TARGET_DOMAIN' (missing: $MISSING_DOMAINS; extra: $EXTRA_DOMAINS) -- a substring/containment check would have passed this silently (extra domains route real traffic this script never intended; a superstring near-miss like 'notexample.com' containing 'example.com' would also have passed). Investigate before treating step 9 as done; do not assume success from a 200 alone."
    ;;
  *)
    die "docker_compose_domains PATCH 200'd but this script's own read-back check printed an unrecognised result token ('$DOMAIN_SET_CHECK') -- refusing to guess whether the write succeeded."
    ;;
esac
ok "docker_compose_domains PATCH read-back domain SET for '$APP_COMPOSE_SERVICE' exactly matches intended: $NEW_COMPOSE_DOMAINS"
info "app-level fqdn after this PATCH: ${NEW_FQDN_AFTER_COMPOSE_PATCH:-<empty>} -- INFORMATIONAL ONLY (whether Coolify derives/mirrors fqdn from docker_compose_domains is UNMEASURED; this script's success does not depend on it)."

# resolve_running_cid -- prints exactly one RESULT LINE, never guesses:
#   CID:<hex>          -- exactly one running container matched
#   READ_FAILURE:<msg> -- 'docker ps' itself failed (ssh/transport error)
#   NONE               -- no running container matched (not an error)
#   AMBIGUOUS:<ids>     -- more than one running container matched
#   BAD_SHAPE:<value>  -- 'docker ps' returned something not
#                         container-id-shaped
# Shared by the PRE- and POST-redeploy capture below (team-lead, run-21
# fix follow-up) -- previously this logic lived inline, used once,
# informationally. It is now REQUIRED post-redeploy (a fresh container
# must exist and must differ from whatever was running before), so it
# is a function, not duplicated prose.
resolve_running_cid() {
  local raw rc count shape_re='^[a-f0-9]{6,64}$'
  set +e
  raw="$(sshx "docker ps --filter 'name=$APP_UUID' --filter 'status=running' --format '{{.ID}}'" </dev/null 2>&1)"
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    printf 'READ_FAILURE:%s' "$raw"
    return
  fi
  if [[ -z "$raw" ]]; then
    printf 'NONE'
    return
  fi
  count="$(printf '%s\n' "$raw" | grep -c .)"
  if [[ "$count" -gt 1 ]]; then
    printf 'AMBIGUOUS:%s' "$(printf '%s' "$raw" | tr '\n' ' ')"
    return
  fi
  if [[ ! "$raw" =~ $shape_re ]]; then
    printf 'BAD_SHAPE:%s' "$raw"
    return
  fi
  printf 'CID:%s' "$raw"
}

# confirm_container_running <cid> -- prints exactly one RESULT LINE:
#   true / false / <anything else docker inspect prints (unexpected)
#   INSPECT_FAILURE:<msg> -- 'docker inspect' itself failed
# A second, independent check on top of resolve_running_cid()'s own
# 'docker ps --filter status=running' (Sec ask, redeploy addenda
# requirement 4) -- never trusts the ps filter alone for something as
# consequential as "safe to docker exec and read env from".
confirm_container_running() {
  local cid="$1" raw rc
  set +e
  raw="$(sshx "docker inspect --format '{{.State.Running}}' $cid" </dev/null 2>&1)"
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    printf 'INSPECT_FAILURE:%s' "$raw"
    return
  fi
  printf '%s' "$raw"
}

# PRE-redeploy capture -- informational only (the very first-ever
# assignment legitimately has nothing running yet); its only job is to
# give the POST-redeploy check below something to compare against.
PRE_DEPLOY_RESULT="$(resolve_running_cid)"
case "$PRE_DEPLOY_RESULT" in
  CID:*) PRE_DEPLOY_CID="${PRE_DEPLOY_RESULT#CID:}" ;;
  *) PRE_DEPLOY_CID="" ;;
esac

# Trigger a redeploy so the new domain assignment actually reaches a
# running container (team-lead, run-21 fix follow-up: without this, the
# env read below and the cert poll further down both hit the OLD,
# pre-assignment container -- Coolify only injects env / regenerates
# Traefik proxy labels at deploy time, never retroactively for an
# already-running container). Same POST /deploy + 90x4s poll shape
# deploy-app.sh already uses (duplicated here rather than sourced --
# this repo's own convention for sibling scripts, see this file's own
# TARGET GUARD section above for the same pattern applied to a
# different helper).
step "Triggering a redeploy of '$APP_NAME' so the domain assignment above reaches a running container"
DEPLOY_OUT="$(sshx "env app_uuid=$(printf '%q' "$APP_UUID") deploy_poll_attempts=$(printf '%q' "$DEPLOY_POLL_ATTEMPTS") deploy_poll_interval=$(printf '%q' "$DEPLOY_POLL_INTERVAL_SECONDS") bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "\$app_uuid" "\$deploy_poll_attempts" "\$deploy_poll_interval" <<'PYEOF'
$PY_API_HELPER
import sys, time
token, app_uuid = sys.argv[1], sys.argv[2]
poll_attempts, poll_interval = int(sys.argv[3]), int(sys.argv[4])
d = api(token, "POST", f"/deploy?uuid={app_uuid}")
deployments = (d or {}).get("deployments") or [{}]
deploy_uuid = deployments[0].get("deployment_uuid", "")
if not deploy_uuid:
    die("deploy call did not return a deployment_uuid")
print(f"QUEUED: {deploy_uuid}")
status = ""
for _ in range(poll_attempts):
    dep = api(token, "GET", f"/deployments/{deploy_uuid}")
    status = (dep or {}).get("status", "")
    if status in ("finished", "failed"):
        break
    time.sleep(poll_interval)
if status != "finished":
    # Sec ask (redeploy addenda): a bounded timeout FAILS CLOSED -- this
    # covers BOTH an explicit status=failed AND the loop simply exhausting
    # its bound without ever reaching a terminal state, with ONE die(),
    # never a fall-through to the container-env read below.
    dep = api(token, "GET", f"/deployments/{deploy_uuid}") or {}
    raw = dep.get("logs") or "[]"
    import json as _json
    entries = _json.loads(raw) if isinstance(raw, str) else (raw or [])
    print("\n".join(e.get("output", "") for e in entries[-60:]), file=sys.stderr)
    die(f"deployment {deploy_uuid} did not reach status=finished within {poll_attempts} attempts x {poll_interval}s (last observed status={status!r}) -- see log above. Refusing to proceed to the container-env read.")
print("FINISHED")
PYEOF
REMOTE
)"
grep -qF "FINISHED" <<<"$DEPLOY_OUT" || die "redeploy of app $APP_NAME did not finish -- see captured deploy output: $DEPLOY_OUT -- re-run this script once fixed (idempotent)."
ok "redeploy finished"

# POST-redeploy container-env read -- now REQUIRED, not informational:
# a fresh container must exist AND must differ from whatever was
# running before the redeploy above -- a read of the OLD container is a
# READ-OF-THE-WRONG-THING, not a measurement (team-lead, run-21 fix
# follow-up). Prints VALUES, not just names, for exactly three env
# families -- COOLIFY_FQDN, COOLIFY_URL, SERVICE_FQDN_* -- Sec
# explicitly relaxed the names-only discipline used everywhere else in
# this repo's env-store handling for ONLY these three: they are public
# hostnames (the sslip form already embeds a uuid that is in this repo
# in plaintext), and since this app now carries BOTH the app-level
# sslip `fqdn` and the service-level docker_compose_domains, only the
# VALUE (not just the name) attributes which source produced which
# route -- naming alone cannot distinguish them. Nothing outside these
# three names is ever read or printed here.
step "Post-redeploy container-env read (VALUES for COOLIFY_FQDN/COOLIFY_URL/SERVICE_FQDN_* only -- see header)"
POST_DEPLOY_RESULT="$(resolve_running_cid)"
case "$POST_DEPLOY_RESULT" in
  READ_FAILURE:*)
    die "post-redeploy container-env read FAILED -- 'docker ps' itself failed: ${POST_DEPLOY_RESULT#READ_FAILURE:} -- the redeploy reported finished but this script could not confirm a running container. Investigate before treating step 9 as done."
    ;;
  NONE)
    die "post-redeploy container-env read found NO running container for '$APP_NAME' -- the redeploy reported finished but nothing is running. Investigate before treating step 9 as done."
    ;;
  AMBIGUOUS:*)
    die "post-redeploy container-env read is AMBIGUOUS -- multiple running containers matched name filter '$APP_UUID' (${POST_DEPLOY_RESULT#AMBIGUOUS:}) -- refusing to guess which is this deploy's. Investigate on the box before treating step 9 as done."
    ;;
  BAD_SHAPE:*)
    die "post-redeploy container-env read: 'docker ps' returned a non-container-id-shaped value (${POST_DEPLOY_RESULT#BAD_SHAPE:}) -- refusing to pass it to docker exec."
    ;;
  CID:*)
    NEW_APP_CID="${POST_DEPLOY_RESULT#CID:}"
    # Sec ask (redeploy addenda, requirement 1): the comparison is a
    # set-difference on ids captured BEFORE vs AFTER the redeploy, never
    # "most recent" / start time / "the one running" -- both AMBIGUOUS
    # above already refuses whenever more than one running container
    # matches the name filter on either side, so this single-id
    # inequality check IS that set-difference at the only cardinality
    # this script ever proceeds past (exactly one, on each side). On a
    # match, name BOTH ids explicitly rather than just the new one.
    if [[ -n "$PRE_DEPLOY_CID" && "$NEW_APP_CID" == "$PRE_DEPLOY_CID" ]]; then
      die "post-redeploy container id ($NEW_APP_CID) is IDENTICAL to the pre-redeploy container id ($PRE_DEPLOY_CID) -- the redeploy reported finished but did not actually replace the running container. Refusing to read its env as a measurement of the new domain assignment -- a read of the OLD container is a READ-OF-THE-WRONG-THING, not a measurement. Investigate on the box before treating step 9 as done."
    fi
    # Sec ask (redeploy addenda, requirement 4): 'docker ps --filter
    # status=running' already excludes a merely-created container, but
    # this is a second, independent confirmation via 'docker inspect'
    # rather than trusting that filter alone -- Coolify injects env at
    # container START, not creation, so a container this script has not
    # independently confirmed as State.Running=true is not yet a valid
    # env-read target even if 'docker ps' listed it.
    RUNNING_CHECK="$(confirm_container_running "$NEW_APP_CID")"
    case "$RUNNING_CHECK" in
      true)
        ;;
      INSPECT_FAILURE:*)
        die "post-redeploy container-env read FAILED -- 'docker inspect' on $NEW_APP_CID itself failed: ${RUNNING_CHECK#INSPECT_FAILURE:} -- refusing to treat an uninspectable container as running."
        ;;
      *)
        die "post-redeploy container $NEW_APP_CID was resolved via 'docker ps' but 'docker inspect' reports State.Running=$RUNNING_CHECK, not true -- Coolify injects env at container START, not creation; refusing to read its env until it is confirmed genuinely running."
        ;;
    esac
    set +e
    ENV_RAW="$(sshx "docker exec $NEW_APP_CID env" </dev/null 2>&1)"
    ENV_RC=$?
    set -e
    if [[ $ENV_RC -ne 0 ]]; then
      die "post-redeploy container-env read FAILED -- 'docker exec $NEW_APP_CID env' rc=$ENV_RC: $ENV_RAW. Investigate before treating step 9 as done."
    fi
    ENV_LINES_FOUND="$(printf '%s\n' "$ENV_RAW" | grep -E '^(SERVICE_FQDN_[A-Za-z0-9_]*|COOLIFY_FQDN|COOLIFY_URL)=' | sort -u || true)"
    if [[ -z "$ENV_LINES_FOUND" ]]; then
      info "MEASURED $(date -u +%Y-%m-%d): NEW container $NEW_APP_CID (post-redeploy, differs from pre-deploy) for '$APP_NAME' injects NONE of SERVICE_FQDN_*/COOLIFY_FQDN/COOLIFY_URL -- this is a CONTROL GAP to report (CA-1's admission-guard-relevant surface would have nothing to see for this app), not something to paper over."
    else
      info "MEASURED $(date -u +%Y-%m-%d): NEW container $NEW_APP_CID (post-redeploy, differs from pre-deploy) for '$APP_NAME' injects: $(printf '%s' "$ENV_LINES_FOUND" | tr '\n' ' ')"
    fi
    info "Append this line to scripts/COOLIFY-API-MEASURED.md's COOLIFY-FACT-06 entry (this run's date) -- this script does not write to that file itself."
    ;;
esac

# Re-take the off-box sslip reachability probe, post-redeploy, WITH a
# nonexistent-host control (Sec ask, run-21 fix follow-up, and reaffirmed
# in the redeploy addenda requirement 2: this probe MUST run after the
# redeploy above, never before it -- Coolify only regenerates Traefik's
# proxy config at deploy time, so a pre-redeploy probe would still be
# measuring the OLD routing state):
# COOLIFY-FACT-05/06's own "not routed, 404 identical to control" fact
# was measured BEFORE docker_compose_domains existed on this app and no
# longer covers this state -- this app may now be reachable via BOTH
# the intended domain (this script's own target) and its own
# Coolify-assigned sslip default, an UNINTENDED second route. Observed
# and reported as a FINDING, never a failure -- this script does not
# change fqdn and has no mechanism to fix a divergence, only to surface
# it before DNS cutover completes.
step "Re-taking the sslip reachability probe (post-redeploy) with a nonexistent-host control"
SSLIP_HOST="${NEW_FQDN_AFTER_COMPOSE_PATCH#http://}"
SSLIP_HOST="${SSLIP_HOST#https://}"
SSLIP_HOST="${SSLIP_HOST%%/*}"
if [[ -z "$SSLIP_HOST" ]]; then
  info "sslip reachability probe SKIPPED -- app-level fqdn is empty; nothing to probe."
else
  CONTROL_HOST="nonexistent-$((RANDOM * RANDOM)).${BOX_IP}.sslip.io"
  SSLIP_HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$SSLIP_HOST/" 2>/dev/null || true)"
  SSLIP_HTTPS_CODE="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "https://$SSLIP_HOST/" 2>/dev/null || true)"
  CONTROL_HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$CONTROL_HOST/" 2>/dev/null || true)"
  CONTROL_HTTPS_CODE="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "https://$CONTROL_HOST/" 2>/dev/null || true)"
  info "sslip host $SSLIP_HOST: http=${SSLIP_HTTP_CODE:-(no response)} https=${SSLIP_HTTPS_CODE:-(no response)}  |  nonexistent-host control $CONTROL_HOST: http=${CONTROL_HTTP_CODE:-(no response)} https=${CONTROL_HTTPS_CODE:-(no response)}"
  if [[ "$SSLIP_HTTP_CODE" != "$CONTROL_HTTP_CODE" || "$SSLIP_HTTPS_CODE" != "$CONTROL_HTTPS_CODE" ]]; then
    info "FINDING: the sslip host answered DIFFERENTLY from the nonexistent-host control (http $SSLIP_HTTP_CODE vs $CONTROL_HTTP_CODE; https $SSLIP_HTTPS_CODE vs $CONTROL_HTTPS_CODE) -- this app may be reachable via an UNINTENDED second route (its own Coolify-assigned sslip default), not just the domain this script assigned. Not a failure -- investigate before DNS cutover completes."
  fi
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
