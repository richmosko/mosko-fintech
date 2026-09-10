#!/usr/bin/env bash
# scripts/mac-tunnel.sh — install a persistent SSH tunnel to the production
# box as a macOS LaunchAgent, so reaching the Coolify dashboard/API/MCP and
# Studio stops being a command you remember to run.
#
# Runs on F/CTO's OWN Mac, as F/CTO's OWN ssh identity — never the
# passphrase-free automation key `provision-vps.sh` uses. Nothing on the
# production box or its firewall changes: 8000 and 3000 stay closed to the
# internet exactly as decided in the runbook's §1/§4 exposure tables; this
# only makes the *local* end of the existing tunnel pattern automatic.
#
# Supply-chain minimalism (house rule): plain `ssh` under launchd KeepAlive,
# not autossh. See the plist template's own header comment for why that is
# a complete substitute here, not a corner cut.
#
# Same dry-run-by-default / --apply convention as provision-vps.sh and
# provision-supabase-stack.sh: this prints a plan and touches nothing until
# you pass --apply. --status and --verify are read-only and always run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/launchagents/com.pfin.tunnel.plist.template"
LABEL="com.pfin.tunnel"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_FILE="$HOME/Library/Logs/pfin-tunnel.log"
SSH_CONFIG="$HOME/.ssh/config"
SSH_HOST_ALIAS="pfin-prod"

ACTION="install"
APPLY=0
BOX_IP=""
IDENTITY="$HOME/.ssh/id_ed25519"
YES=0

info() { printf '\033[36m[mac-tunnel]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[mac-tunnel]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[mac-tunnel]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[mac-tunnel] FATAL:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<USAGE
Usage: $0 [install|uninstall|status|verify] [options]

  install (default)   Write ~/Library/LaunchAgents/$LABEL.plist and load it.
  uninstall            Unload and remove the LaunchAgent. Leaves ~/.ssh/config
                        and the log file alone.
  status                launchctl state + last 20 log lines. Read-only.
  verify                Curl checks against the forwarded ports. Read-only.

Options:
  --apply               Actually write files / touch launchd. Without this,
                         install/uninstall only print what they would do.
  --box-ip <ip>          Production box primary IPv4. Needed only if
                         ~/.ssh/config has no "Host $SSH_HOST_ALIAS" block yet.
  --identity <path>      SSH private key to reference in the config block.
                         Default: $HOME/.ssh/id_ed25519 (F/CTO's own key —
                         see the plist template header for why this is never
                         the automation key).
  --yes                  Don't prompt before appending to ~/.ssh/config.
  --kill-test             (verify only) kill the running tunnel process and
                         confirm launchd restarts it within ~15s. Disrupts
                         an active session — opt-in, not part of plain verify.
  -h, --help
USAGE
}

KILL_TEST=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    install|uninstall|status|verify) ACTION="$1" ;;
    --apply) APPLY=1 ;;
    --box-ip) BOX_IP="$2"; shift ;;
    --identity) IDENTITY="$2"; shift ;;
    --yes) YES=1 ;;
    --kill-test) KILL_TEST=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done

[[ "$(uname -s)" == "Darwin" ]] || die "this script is macOS-only (launchd/launchctl); found $(uname -s)."

# ---------------------------------------------------------------------------
# ~/.ssh/config — ensure the "pfin-prod" alias exists. Never overwrite an
# existing block; only ever append a new one, and only with confirmation
# (or --yes) since this is a personal, unversioned file outside this repo's
# surface — the same boundary already crossed once this stand-up and worth
# holding hard.
# ---------------------------------------------------------------------------
ssh_alias_block() {
  cat <<BLOCK
Host $SSH_HOST_ALIAS
    HostName ${BOX_IP:-<box-ip — see docs/records/v1final/standup-log.md>}
    User root
    IdentityFile $IDENTITY
    IdentitiesOnly yes
    UseKeychain yes
    AddKeysToAgent yes
BLOCK
}

check_ssh_alias() {
  if [[ -f "$SSH_CONFIG" ]] && grep -qE "^Host[[:space:]]+$SSH_HOST_ALIAS(\$|[[:space:]])" "$SSH_CONFIG"; then
    ok "~/.ssh/config already has a \"Host $SSH_HOST_ALIAS\" block — not touching it."
    if [[ -n "$BOX_IP" ]]; then
      existing_ip="$(awk "/^Host[[:space:]]+$SSH_HOST_ALIAS(\$|[[:space:]])/{f=1} f&&/HostName/{print \$2; exit}" "$SSH_CONFIG")"
      if [[ -n "$existing_ip" && "$existing_ip" != "$BOX_IP" ]]; then
        warn "existing HostName ($existing_ip) differs from --box-ip ($BOX_IP) — not auto-editing; update ~/.ssh/config by hand if the box was rebuilt."
      fi
    fi
    return 0
  fi

  info "~/.ssh/config has no \"Host $SSH_HOST_ALIAS\" block yet. Would append:"
  echo
  ssh_alias_block | sed 's/^/    /'
  echo
  if [[ -z "$BOX_IP" ]]; then
    die "no --box-ip given and no existing alias — pass --box-ip <ip> (see docs/records/v1final/standup-log.md for the current primary IP) or add the block above by hand first."
  fi
  if [[ $APPLY -eq 0 ]]; then
    info "(preflight only — pass --apply to actually append this)"
    return 0
  fi
  if [[ $YES -eq 0 ]]; then
    read -r -p "Append this block to $SSH_CONFIG? [y/N] " reply
    [[ "$reply" == "y" || "$reply" == "Y" ]] || die "aborted — not appending."
  fi
  mkdir -p "$(dirname "$SSH_CONFIG")"
  { echo; ssh_alias_block; } >> "$SSH_CONFIG"
  chmod 600 "$SSH_CONFIG"
  ok "appended Host $SSH_HOST_ALIAS to $SSH_CONFIG"
}

check_key_loaded() {
  if ssh-add -l 2>/dev/null | grep -qF "$(ssh-keygen -lf "$IDENTITY" 2>/dev/null | awk '{print $2}')"; then
    ok "$IDENTITY is loaded in the agent."
  else
    warn "$IDENTITY is not currently loaded in the ssh-agent."
    warn "One-time fix so launchd (no terminal to type a passphrase into) can use it:"
    warn "    ssh-add --apple-use-keychain $IDENTITY"
    warn "(UseKeychain/AddKeysToAgent in the config block above make this persist across reboots.)"
  fi
}

do_install() {
  [[ -f "$TEMPLATE" ]] || die "template missing: $TEMPLATE"
  check_ssh_alias
  check_key_loaded

  info "Plan:"
  echo "      plist       $PLIST_DST"
  echo "      log         $LOG_FILE"
  echo "      forwards    127.0.0.1:8000 -> localhost:8000 (Coolify dashboard/API/MCP)"
  echo "                  127.0.0.1:3000 -> localhost:3000 (Studio, once deployed)"
  echo "      identity    $IDENTITY (F/CTO's own key, NOT the automation key)"

  if [[ $APPLY -eq 0 ]]; then
    printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing was installed. Re-run with --apply.\n'
    exit 0
  fi

  mkdir -p "$(dirname "$PLIST_DST")" "$(dirname "$LOG_FILE")"
  sed "s#__HOME__#$HOME#g" "$TEMPLATE" > "$PLIST_DST"
  plutil -lint "$PLIST_DST" >/dev/null || die "generated plist failed plutil -lint — template/substitution bug, fix before retrying"

  # Idempotent reinstall: bootout a prior load if present, ignore failure if not.
  launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
  launchctl enable "gui/$(id -u)/$LABEL"
  ok "LaunchAgent installed and loaded: $LABEL"
  info "Unload command (kept here, not just in your head): launchctl bootout gui/\$(id -u)/$LABEL"
  info "Next: $0 verify"
}

do_uninstall() {
  info "Plan: unload $LABEL and remove $PLIST_DST. ~/.ssh/config and $LOG_FILE are left alone."
  if [[ $APPLY -eq 0 ]]; then
    printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing was removed. Re-run with --apply.\n'
    exit 0
  fi
  launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || warn "was not loaded"
  rm -f "$PLIST_DST"
  ok "removed."
}

do_status() {
  if launchctl print "gui/$(id -u)/$LABEL" >/tmp/mac-tunnel-status.$$ 2>&1; then
    ok "loaded:"
    grep -E "state|pid|last exit" /tmp/mac-tunnel-status.$$ || true
  else
    warn "not loaded (run: $0 install --apply --box-ip <ip>)"
  fi
  rm -f /tmp/mac-tunnel-status.$$
  if [[ -f "$LOG_FILE" ]]; then
    echo "--- last 20 lines of $LOG_FILE ---"
    tail -n 20 "$LOG_FILE"
  fi
}

do_verify() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 http://localhost:8000 || echo "000")"
  if [[ "$code" == "302" ]]; then
    ok "localhost:8000 -> $code (Coolify dashboard reachable, redirecting to login — as expected)"
  else
    warn "localhost:8000 -> $code (expected 302). If \"000\": tunnel isn't up. If something else: check for a local process already bound to 8000 (lsof -i :8000) and grep $LOG_FILE for \"Address already in use\" / \"bind:\" — that's the ExitOnForwardFailure -> restart-loop failure mode; launchd will keep retrying every ThrottleInterval (10s) and never succeed until the collision is cleared."
  fi

  local code3000
  code3000="$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 http://localhost:3000 || echo "000")"
  if [[ "$code3000" == "000" ]]; then
    info "localhost:3000 -> unreachable (fine if Studio hasn't been deployed via provision-supabase-stack.sh yet; the forward is harmless either way)."
  else
    ok "localhost:3000 -> $code3000 (Studio reachable)"
  fi

  if [[ $KILL_TEST -eq 1 ]]; then
    warn "--kill-test: killing the running tunnel process to prove launchd restarts it. This disrupts any active tunnel use for a few seconds."
    local pid
    pid="$(pgrep -f "ssh .*-N .*$SSH_HOST_ALIAS" | head -1 || true)"
    [[ -n "$pid" ]] || die "no running tunnel process found to kill (is it installed? $0 status)"
    kill "$pid"
    info "killed pid $pid, waiting up to 15s for launchd to relaunch..."
    for _ in $(seq 1 15); do
      sleep 1
      new_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 http://localhost:8000 || echo "000")"
      [[ "$new_code" == "302" ]] && { ok "back up after restart — KeepAlive confirmed working."; return 0; }
    done
    die "did not come back within 15s — check $LOG_FILE and $0 status"
  fi
}

case "$ACTION" in
  install) do_install ;;
  uninstall) do_uninstall ;;
  status) do_status ;;
  verify) do_verify ;;
esac
