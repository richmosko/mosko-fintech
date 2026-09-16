#!/usr/bin/env bash
#
# db-shell.sh — the filled-in vehicle for docs/deployment-runbook.md §6's
# interactive psql sessions, so an operator never hand-substitutes
# <box-ip> / <supabase-stack-app-uuid> into a raw ssh/docker one-liner
# again. DevOps-owned. BACKLOG.md §7.36 item 33 ("the runbook must serve
# a stranger").
#
# Reads BOX_IP and MIGRATOR_SERVICE_UUID from the repo-root gitignored
# .env — written there by scripts/provision-vps.sh --apply (BOX_IP) and
# scripts/record-coolify-uuids.sh --apply (MIGRATOR_SERVICE_UUID). Both
# are non-secret (an internal IP and a Coolify resource UUID), so no
# secret ever passes through this script's own variables for the
# ordinary --as path.
#
# USAGE
#   scripts/db-shell.sh --as supabase_admin      # open an interactive
#                                                  psql session as
#                                                  supabase_admin (default)
#   scripts/db-shell.sh --as postgres             # same, as postgres
#   scripts/db-shell.sh --as supabase_admin --print
#                                                  # print the filled-in
#                                                  command, don't run it
#   scripts/db-shell.sh --migrator-url --i-am-a-human
#                                                  # runbook §6.0 Step 0.2
#                                                  # — OPERATOR-ONLY, see
#                                                  # the guard below
#
# ⚠ --migrator-url prints a LIVE CREDENTIAL (MIGRATOR_DB_PASSWORD, embedded
# in the printed PROD_DB_URL). This is the one case
# docs/SECURITY/index.html#container-env-dump-credential-disclosure's
# names-only rule permits — the operator genuinely needs the VALUE to type
# into `\password migrator`, not just its name. Sec's runbook §6.0
# condition (PR #763 C-1, 2026-09-14): an agent must NEVER run this. The
# guard below is mechanical, not just documentation — it refuses unless
# BOTH stdin and stdout are an interactive terminal AND --i-am-a-human is
# passed explicitly. An agent piping this script's output, or running it
# non-interactively, cannot satisfy either condition. This is a control
# against the 2026-09-14 disclosure class (a credential landing in an
# agent's own session transcript), not a claim that a human at a real
# terminal is risk-free — read it, type it into \password, and do not
# paste it into a report, a PR, a chat, or a commit (§6.0's own wording).

set -euo pipefail

# REPO_ROOT resolution -- .env lives at the MAIN checkout root, never inside
# an agent worktree. 2026-09-16 incident: `dirname "$0"/..` resolved to the
# worktree itself under .claude/worktrees/<name>/, so record-coolify-uuids.sh
# and provision-vps.sh's BOX_IP writer silently wrote MIGRATOR_SERVICE_UUID /
# APP_UUID / MIGRATOR_TASK_UUID / BOX_IP / CI_MIGRATE_SSH_PUBKEY into a
# throwaway per-worktree .env -- discarded when that worktree was removed at
# merge, leaving the real repo-root .env (what F/CTO's own --apply run reads)
# never updated. Refuse by default when invoked from inside
# .claude/worktrees/ rather than silently redirecting into the main
# checkout's .env; set REPO_ROOT explicitly to override.
if [[ -n "${REPO_ROOT:-}" ]]; then
  :
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ "$SCRIPT_DIR" == *"/.claude/worktrees/"* ]]; then
    printf '\n\033[31mFAIL\033[0m  running from an agent worktree (%s) -- .env lives at the main checkout root and would be silently discarded when this worktree is removed. Set REPO_ROOT=<main checkout path> to override, or run this script from the main checkout.\n' "$SCRIPT_DIR" >&2
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

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
info() { printf '      %s\n' "$*"; }

read_env_var() { grep -m1 "^$1=" "$REPO_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d '\r\n' || true; }

AS_ROLE="supabase_admin"
PRINT_ONLY=0
MIGRATOR_URL=0
I_AM_A_HUMAN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --as)              AS_ROLE="${2:?--as needs a value (supabase_admin|postgres)}"; shift 2 ;;
    --print)           PRINT_ONLY=1; shift ;;
    --migrator-url)     MIGRATOR_URL=1; shift ;;
    --i-am-a-human)     I_AM_A_HUMAN=1; shift ;;
    *) die "unknown argument: $1 (usage: --as supabase_admin|postgres | --migrator-url) [--print] [--i-am-a-human]" ;;
  esac
done

[[ -f "$REPO_ROOT/.env" ]] || die "no .env at $REPO_ROOT — BOX_IP is read from there (scripts/provision-vps.sh --apply writes it)"

BOX_IP="$(read_env_var BOX_IP)"
[[ -n "$BOX_IP" ]] || die "BOX_IP not set in .env — run scripts/provision-vps.sh --apply first (it records BOX_IP there), or set it by hand"

MIGRATOR_SERVICE_UUID="$(read_env_var MIGRATOR_SERVICE_UUID)"
[[ -n "$MIGRATOR_SERVICE_UUID" ]] || die "MIGRATOR_SERVICE_UUID not set in .env — run scripts/record-coolify-uuids.sh --apply first (queries the Coolify API by resource name), or set it by hand"

if [[ $MIGRATOR_URL -eq 1 ]]; then
  # OPERATOR-ONLY GUARD — mechanical, not just a comment. See the header
  # block above and docs/deployment-runbook.md §6.0 Step 0.2.
  if [[ $I_AM_A_HUMAN -ne 1 ]]; then
    die "--migrator-url requires --i-am-a-human (it prints a live credential — see this script's own header comment and runbook §6.0)"
  fi
  if [[ ! -t 0 || ! -t 1 ]]; then
    die "--migrator-url refuses to run with stdin or stdout not a TTY — this is the guard against an agent (or any non-interactive caller) capturing a live credential into a transcript, log, or pipe. Run this directly at a real terminal."
  fi
  CMD=(ssh -t "root@$BOX_IP" "docker compose --project-name $MIGRATOR_SERVICE_UUID exec -T migrator sh -c \"echo \\\$PROD_DB_URL\"")
  if [[ $PRINT_ONLY -eq 1 ]]; then
    printf '%s\n' "${CMD[*]}"
    info "(the password is the substring between 'migrator:' and '@db' in the printed URL — see runbook §6.0 Step 0.2 for what to do with it)"
    exit 0
  fi
  exec "${CMD[@]}"
fi

case "$AS_ROLE" in
  supabase_admin|postgres) ;;
  *) die "--as must be supabase_admin or postgres, got: $AS_ROLE" ;;
esac

CMD=(ssh -t "root@$BOX_IP" "docker compose --project-name $MIGRATOR_SERVICE_UUID exec -it db psql -U $AS_ROLE -d postgres")

if [[ $PRINT_ONLY -eq 1 ]]; then
  printf '%s\n' "${CMD[*]}"
  exit 0
fi

exec "${CMD[@]}"
