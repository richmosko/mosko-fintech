#!/usr/bin/env bash
#
# smoke-ca1-env-pattern.sh -- docs/deployment-runbook.md Part 3, the CA-1
# deploy-gate half (BACKLOG.md §7.36 item 79, W-5). DevOps-owned.
# `workers/provider-sync/src/http/admissionGuard.ts` names two halves of
# CA-1: the code half (PATTERN-match, not exact-name, so a Coolify
# env-var rename can't slip past it) lives in the worker; the deploy-gate
# half -- confirming THIS Coolify version's actually-injected env-var
# names still match what the code's pattern set expects -- is DevOps's
# job. This script is that check.
#
# THE INVERSION THIS SCRIPT PROVES (Sec, PR #847 review F-7 -- an
# earlier draft of this AC described the check backwards): the failure
# is a route-signal name that IS actually injected by the running
# Coolify version but is matched by NO pattern in
# `PUBLIC_ROUTE_ENV_MATCHERS` -- a pattern gap the code would have
# silently missed. A name that IS matched by a pattern is one the code
# already anticipated and would refuse to boot on -- that is a PASS, not
# a finding. A benign zero-match on a name that genuinely is not a route
# signal is also not a finding (Subject B) -- CA-2's empirical
# reachability smoke (scripts/smoke-admission-endpoint.sh) is the actual
# backstop for that case.
#
# THE PATTERNS ARE READ FROM THE RUNNING CONTAINER'S OWN COMPILED CODE,
# NEVER HAND-COPIED -- this script does not reimplement
# `PUBLIC_ROUTE_ENV_MATCHERS`'s matching logic in bash/python. It
# `docker exec`s into the running `provider-sync` container and runs a
# Node one-liner that dynamically `import()`s the container's own
# `dist/http/admissionGuard.js` and calls `PUBLIC_ROUTE_ENV_MATCHERS[i]
# .test(name)` directly -- so a code change to the matcher set is picked
# up automatically on the next run, and this script can never drift from
# what the container is actually running.
#
# ⚠ THE ROUTE-SIGNAL REFERENCE LIST IS PINNED, NOT LIVE-MEASURED --
# stated, not glossed. The AC (BACKLOG item 79) calls for "the running
# Coolify version's own documented injected-var list, supplied as a
# pinned input." No prior live cross-check of Coolify 4.3.18's actual
# injected-var set exists anywhere in this repo (grepped for the
# temp/self212-devops-ca1-coolify-route-envvars.md file the code's own
# comment cites -- absent, never committed). ROUTE_SIGNAL_REFERENCE
# below is therefore derived from the matcher SOURCE's own documented
# families (each pattern's own code comment names a representative
# example), NOT from an independent measurement against a live Coolify
# install. Update this list, and this comment, the day a real live
# cross-check is performed -- do not read this pinned set as "measured."
#
# USAGE
#   BOX_IP=<box-ip> scripts/smoke-ca1-env-pattern.sh [--compose-service <name>]
#
#   PROVIDER_SYNC_APP_NAME (default pfin-provider-sync) is env-var-overridable.
#
# EXIT CODES
#   0  VERIFIED -- every pinned route-signal name that is ACTUALLY
#      injected in the running container is matched by at least one
#      PUBLIC_ROUTE_ENV_MATCHERS pattern (Subject A clean). Zero-match on
#      a non-route-signal name is expected and not reported as a finding.
#   1  REFUSED -- a real finding: a pinned route-signal name IS injected
#      but matched by NO pattern (the exact inversion CA-1's deploy-gate
#      half exists to catch), or ambiguous (>1) running container match.
#   2  FAILED -- a precondition this smoke could not even attempt under
#      (box unreachable, resource/container not found, the Node import
#      itself failed -- e.g. the compiled file path has moved).
#
# ORCHESTRATOR CONTRACT (BACKLOG.md §7.36 item 76's provision.sh calls
# this directly): non-interactive, no prompts, no `read`. Read-only --
# never mutates anything. Every fact used (container id, injected env
# names, matcher behavior) is resolved LIVE each run, never cached.

set -euo pipefail

BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
PROVIDER_SYNC_APP_NAME="${PROVIDER_SYNC_APP_NAME:-pfin-provider-sync}"
COMPOSE_SERVICE="provider-sync"

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
die2() { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 2; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

for arg in "$@"; do
  case "$arg" in
    --compose-service) shift; COMPOSE_SERVICE="${1:-}" ;;
    *) : ;;
  esac
  shift || true
done

[[ -n "$BOX_IP" ]] || die2 "BOX_IP is required, not defaulted -- set it explicitly."

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

step "Resolving '$PROVIDER_SYNC_APP_NAME'"
UUID_RE='^[a-z0-9]{20,32}$'
APP_UUID="$(sshx "env app_query=$(printf '%q' "$PROVIDER_SYNC_APP_NAME") bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "\$app_query" <<'PYEOF'
$PY_API_HELPER
import sys
token, query = sys.argv[1], sys.argv[2]
apps = api(token, "GET", "/applications")
matches = [a for a in apps if a.get("name") == query]
if len(matches) != 1:
    die(f"expected exactly one application matching name='{query}', found {len(matches)}")
print(matches[0]["uuid"])
PYEOF
REMOTE
)"
[[ "$APP_UUID" =~ $UUID_RE ]] || die2 "could not resolve '$PROVIDER_SYNC_APP_NAME' to a uuid-shaped application id"
ok "resolved '$PROVIDER_SYNC_APP_NAME' -> $APP_UUID"

step "Finding the running '$COMPOSE_SERVICE' container"
RUNNING_LIST="$(sshx "docker compose --project-name $APP_UUID ps -q $COMPOSE_SERVICE | xargs -r -I{} docker inspect --format '{{.State.Running}}{{\"\\t\"}}{{.Id}}{{\"\\t\"}}{{.Created}}' {} | awk -F'\t' '\$1==\"true\"{print \$2\"\t\"\$3}'")"
[[ -n "$RUNNING_LIST" ]] || die2 "no running container found for compose service '$COMPOSE_SERVICE' under project '$APP_UUID' -- is '$PROVIDER_SYNC_APP_NAME' deployed and healthy?"
RUNNING_COUNT="$(printf '%s\n' "$RUNNING_LIST" | grep -c .)"
[[ "$RUNNING_COUNT" -eq 1 ]] \
  || die "AMBIGUOUS: $RUNNING_COUNT running containers match compose service '$COMPOSE_SERVICE' under project '$APP_UUID' -- refusing to silently pick one."
CONTAINER="$(awk -F'\t' '{print $1}' <<<"$RUNNING_LIST")"
ok "running container: $CONTAINER"

step "Reading the container's own injected env NAMES (names only, never values)"
INJECTED_NAMES="$(sshx "docker exec $CONTAINER env | cut -d= -f1")"
info "$(printf '%s\n' "$INJECTED_NAMES" | grep -c .) name(s) injected"

# Pinned reference set -- see the header's own ⚠ note on why this is
# PINNED, not live-measured. One representative example per matcher
# family named in admissionGuard.ts's own PUBLIC_ROUTE_ENV_MATCHERS
# comments, plus one deliberately-benign non-route-signal name (Subject
# B control -- proves this script does not over-fire on ordinary env).
ROUTE_SIGNAL_REFERENCE="SERVICE_FQDN_APP
SERVICE_URL_APP
COOLIFY_URL
COOLIFY_FQDN
ADMISSION_PUBLIC_URL"

step "Cross-checking each ACTUALLY-INJECTED pinned-reference name against the container's OWN compiled PUBLIC_ROUTE_ENV_MATCHERS (read live, never hand-copied)"
read -r -d '' NODE_CHECK <<'NODEEOF' || true
const names = process.argv.slice(2);
import('/app/dist/http/admissionGuard.js').then(({ PUBLIC_ROUTE_ENV_MATCHERS }) => {
  for (const name of names) {
    const upper = name.toUpperCase();
    const matched = PUBLIC_ROUTE_ENV_MATCHERS.some((m) => m.test(upper));
    console.log(`${name}\t${matched ? '1' : '0'}`);
  }
}).catch((err) => {
  console.error('IMPORT_FAILED: ' + (err && err.message ? err.message : String(err)));
  process.exit(2);
});
NODEEOF

TO_CHECK=()
while IFS= read -r ref_name; do
  [[ -n "$ref_name" ]] || continue
  if grep -qxF "$ref_name" <<<"$INJECTED_NAMES"; then
    TO_CHECK+=("$ref_name")
  fi
done <<<"$ROUTE_SIGNAL_REFERENCE"

if [[ ${#TO_CHECK[@]} -eq 0 ]]; then
  ok "none of the pinned reference names are actually injected on this deploy -- nothing to cross-check, Subject A trivially clean"
  step "Done"
  exit 0
fi

# bash 3.2 has no ${arr[*]@Q} quote-transform (bash 4.4+ only) -- build
# the quoted argument list by hand instead.
TO_CHECK_QUOTED=""
for name in "${TO_CHECK[@]}"; do
  TO_CHECK_QUOTED="$TO_CHECK_QUOTED $(printf '%q' "$name")"
done

set +e
CHECK_OUT="$(sshx "docker exec $CONTAINER node -e $(printf '%q' "$NODE_CHECK")$TO_CHECK_QUOTED" 2>&1)"
CHECK_RC=$?
set -e
[[ $CHECK_RC -eq 0 ]] || die2 "the Node cross-check itself failed (exit $CHECK_RC) -- likely the compiled admissionGuard.js path has moved. Output: $CHECK_OUT"

UNMATCHED=()
while IFS=$'\t' read -r name matched; do
  [[ -n "$name" ]] || continue
  info "$name -> matched=$matched"
  [[ "$matched" == "1" ]] || UNMATCHED+=("$name")
done <<<"$CHECK_OUT"

if [[ ${#UNMATCHED[@]} -gt 0 ]]; then
  die "CA-1 deploy-gate FINDING: the following pinned route-signal name(s) are ACTUALLY INJECTED on this deploy but matched by NO PUBLIC_ROUTE_ENV_MATCHERS pattern -- this is the exact inversion this check exists to catch: ${UNMATCHED[*]}. Update the matcher set in workers/provider-sync/src/http/admissionGuard.ts (Backend-owned) before trusting CA-1's code half again."
fi

ok "every actually-injected pinned route-signal name is matched by at least one pattern"

step "Done"
info "CA-1 deploy-gate: no pattern gap found against the pinned reference set."
exit 0
