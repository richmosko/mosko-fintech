#!/usr/bin/env bash
#
# verify-worker-ca1-clear.sh -- die-level, post-deploy CA-1 container-env
# assertion. Sec ruling (PR #862 review, option C): provision-worker.sh's
# own done-predicate can only assert the API-level state (fqdn/
# ports_exposes cleared via the Coolify API/tinker write) -- it never
# deploys, so there is no guarantee a running container's OWN env
# reflects that clear (Coolify injects env only at container START).
# The authoritative check -- does the ACTUALLY RUNNING container still
# carry a CA-1 route signal -- belongs at the point a fresh container is
# guaranteed to exist: immediately after a real deploy. This script is
# that check, called from `provision.sh`'s `run_deploy_workers()`
# alongside item 10's own post-deploy store re-verify
# (`verify_worker_store_binds`).
#
# WHAT IT CHECKS -- `docker exec <container> env`, grepped ON THE BOX
# (inside the remote command, before the SSH hop -- same discipline as
# every other env-read in this repo) for `COOLIFY_FQDN=` / `COOLIFY_URL=`
# with a NON-EMPTY value. Either present-and-non-empty FAILS, naming
# CA-1 explicitly -- this is the exact signal
# `workers/provider-sync/src/http/admissionGuard.ts`'s own
# `detectPublicRouteSignal` reacts to; if THIS check passes, the
# guard's own refusal branch is structurally unreachable on this
# deploy.
#
# SCOPE -- provider-sync only. The admission guard this check exists to
# protect lives in `workers/provider-sync` alone; `pfin-back-etl` and
# `pfin-pdf-render` have no HTTP admission surface to guard. Their own
# fqdn/ports_exposes ARE still cleared by `provision-worker.sh` (defense
# in depth against a future domain reassignment), but this specific
# die-level post-deploy gate is scoped to the one resource where a live
# route signal is an actual live-exposure finding, not a general
# "verify every worker's env" sweep.
#
# USAGE
#   BOX_IP=<box-ip> scripts/verify-worker-ca1-clear.sh <container-name>
#
# EXIT CODES
#   0  VERIFIED -- no non-empty COOLIFY_FQDN/COOLIFY_URL in the
#      container's own env.
#   1  FAILED -- a real finding: the container carries a non-empty
#      route signal. This IS a live-exposure state, not a soft warning
#      -- the caller must not treat this deploy as done.
#   2  FAILED -- a precondition this script could not even attempt
#      under (missing BOX_IP, box unreachable, container not found).

set -euo pipefail

BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
CONTAINER="${1:-}"

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
die2() { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 2; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

[[ -n "$CONTAINER" ]] || die2 "usage: $0 <container-name> (BOX_IP env var required)"
[[ -n "$BOX_IP" ]] || die2 "BOX_IP is required, not defaulted -- set it explicitly (same discipline as every other scripts/*.sh)."

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }

sshx true >/dev/null 2>&1 || die2 "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY."

step "CA-1 post-deploy container-env check ($CONTAINER)"
if ! sshx "docker inspect $CONTAINER" </dev/null >/dev/null 2>&1; then
  die2 "container '$CONTAINER' not found on the box -- cannot check its env. Did the deploy actually create it under this name?"
fi

# Grepped ON THE BOX, inside the remote command -- never pull the whole
# env dump across the wire (same discipline every other env-read in
# this repo follows; COOLIFY_FQDN/URL are non-secret here, but the
# convention is the convention regardless of this call's own payload).
ROUTE_SIGNAL="$(sshx "docker exec $CONTAINER env | grep -E '^(COOLIFY_FQDN|COOLIFY_URL)=.' || true" </dev/null 2>/dev/null || true)"
if [[ -n "$ROUTE_SIGNAL" ]]; then
  die "CA-1 FINDING: container '$CONTAINER' carries a non-empty Coolify route signal after deploy -- $(printf '%s' "$ROUTE_SIGNAL" | cut -d= -f1 | tr '\n' ' ')-- this is the exact signal admissionGuard.ts's detectPublicRouteSignal reacts to; if the guard did NOT refuse to boot on this deploy, investigate why immediately (a guard regression is worse than this finding). Do not treat this deploy as done."
fi
ok "container '$CONTAINER' carries no non-empty COOLIFY_FQDN/COOLIFY_URL -- CA-1 clear, post-deploy, confirmed on the running container."
exit 0
