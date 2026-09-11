#!/usr/bin/env bash
#
# standup.sh — top-level orchestrator over the scripted stand-up spine.
# Collapses the three separately-run --apply scripts into one operator
# invocation. DevOps-owned. F/CTO directive 2026-09-10: the stand-up must be
# a single command a stranger can execute.
#
# WHAT THIS IS
#   A thin wrapper. It does not reimplement any of the three stages' logic
#   -- it runs them, in order, fail-fast, and carries the one piece of state
#   that only exists after stage 1 (the box's IP) into stages 2 and 3. Each
#   stage is already idempotent and preflight-guarded on its own; this file
#   adds nothing to that contract beyond sequencing + the handoff.
#
# STAGES, IN ORDER
#   1. scripts/provision-vps.sh              -- Hetzner provision + hardening
#                                                + Coolify install + admin/
#                                                token bootstrap
#   2. scripts/provision-supabase-stack.sh    -- create/adopt the Supabase
#                                                Coolify app, mint stack
#                                                secrets, materialize mounts,
#                                                deploy, battery (it already
#                                                calls
#                                                coolify-materialize-supabase-
#                                                mounts.sh internally -- this
#                                                wrapper does NOT call that
#                                                separately)
#   3. scripts/mint-supabase-jwt-keys.sh      -- mint real HS256 ANON_KEY /
#                                                SERVICE_ROLE_KEY, redeploy,
#                                                wait-healthy, four-probe
#                                                verify
#
# CONVENTION -- same as every script it wraps
#   Preflight (no --apply): runs each stage's OWN preflight, in order,
#   fail-fast. Nothing is created or mutated.
#   --apply: passes --apply through to every stage that supports it.
#
# BOX_IP HANDOFF
#   Stages 2 and 3 both require BOX_IP, which does not exist until stage 1
#   provisions (or resolves) the box. provision-vps.sh prints a
#   machine-readable `BOX_IP=<ip>` sentinel line to its own stdout as soon as
#   it resolves the box's address (both in preflight against an EXISTING box,
#   and after a real --apply create) -- this script captures that line and
#   carries the value into stages 2 and 3. See provision-vps.sh's own
#   "machine-readable BOX_IP handoff" comment at the point it prints the
#   sentinel.
#
#   A brand-new box has no resolvable IP during a first-ever preflight (the
#   box doesn't exist yet) -- expected, not an error; this script reports it
#   and skips preflighting stages 2/3, which cannot run without an IP either.
#
#   RESUME / OPERATOR OVERRIDE: set BOX_IP yourself to skip stage 1 entirely
#   and jump straight to stage 2:
#     BOX_IP=<box-ip> scripts/standup.sh --apply
#   Useful for re-running after a partial failure in stage 2 or 3 without
#   re-running (idempotent, but slower) stage 1's Hetzner-side checks.
#
# IDEMPOTENT + RESUMABLE
#   Every stage already guards its own idempotence (name/state lookups before
#   any create or mutate). Re-running the whole spine against an
#   already-provisioned, already-deployed box is safe and reports
#   "already satisfies" at each step. A failed run can be resumed either by
#   re-running standup.sh from the top (stage 1 will report "already exists"
#   and fall through quickly) or, once BOX_IP is known, by exporting it and
#   resuming at stage 2 as shown above.
#
# FAIL-FAST
#   Any stage's non-zero exit aborts immediately with "stage N (<name>)
#   failed" and this script's own non-zero exit. No stage is ever run after
#   an earlier one has failed.
#
# WHAT IS DELIBERATELY OUTSIDE THIS WRAPPER
#   Steps that need a human decision or a console, not a missing script:
#     §2  DNS records            -- point the domain at the primary IP.
#                                    F/CTO-only registrar access; see runbook
#                                    §2.
#     §5  Production secrets     -- the app-service secrets (SUPABASE_
#         entry                     SERVICE_ROLE_KEY, PLAID_*, etc.) are
#                                    entered directly into Coolify's UI.
#                                    Currently manual by design -- see the
#                                    DESIGN SEAM note below for where a
#                                    future scripted stage would slot in.
#     §6  `supabase db push`     -- Architect-authored migrations, applied
#                                    by an operator against the fresh
#                                    instance.
#     §6.1/§6.2 role provisioning -- interactive `\password` role handoff
#                                    for pfin_etl / pfin_provider_sync.
#                                    Deliberately interactive (see runbook
#                                    §6.1: a scripted/piped password would
#                                    reach shell history or a log); never
#                                    scripted into this or any other file.
#     §7  Worker Coolify         -- creating the etl / pdf-render /
#         resources                 provider-sync Coolify services
#                                    themselves (this wrapper stands up the
#                                    VPS + Supabase stack only).
#   Running this script to completion does NOT mean the stand-up is done --
#   see the "Remaining steps" block this script prints at the end.
#
# DESIGN SEAM -- a future §5 secret-push stage
#   A later stage could bulk-push the production_only secrets from local
#   .env to Coolify via the envs/bulk API (the same pattern already proven
#   for SMTP_PASS in provision-supabase-stack.sh). That stage is Sec-gated
#   and NOT built here -- it would slot in as a new STAGE 2.5, between the
#   Supabase stack deploy (stage 2) and the JWT mint (stage 3), or as its own
#   stage between 3 and the (also-not-scripted) worker step. The stage list
#   below is a plain array specifically so inserting a stage is a one-line
#   change, not a restructure.
#
# USAGE
#   scripts/standup.sh              # preflight: runs each stage's own
#                                    # preflight, in order; nothing mutated
#   scripts/standup.sh --apply      # runs each stage for real, in order
#   BOX_IP=<ip> scripts/standup.sh [--apply]   # skip stage 1, resume at 2
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
usage: scripts/standup.sh [--apply]

Runs the scripted production stand-up spine as one command:
  1. scripts/provision-vps.sh              (Hetzner + hardening + Coolify)
  2. scripts/provision-supabase-stack.sh    (Supabase Coolify stack)
  3. scripts/mint-supabase-jwt-keys.sh      (real HS256 keys + verify)

Default (no flag): preflight only -- runs each stage's own preflight,
in order, fail-fast. Nothing is created or mutated.

--apply: passes --apply through to every stage. Still fail-fast: a
failing stage aborts before the next one runs.

BOX_IP=<ip> scripts/standup.sh [--apply]
  Skip stage 1 (Hetzner provisioning) and resume at stage 2, using the
  given box IP. Useful to re-run after a partial stage-2/3 failure, or
  against a box provisioned by hand/another run.

Deliberately OUTSIDE this wrapper (human decision or console, not an
oversight) -- see this file's own header comment for the full list:
  runbook §2   DNS records
  runbook §5   production secrets entered into Coolify's UI
  runbook §6   `supabase db push` / migration apply
  runbook §6.1/§6.2  interactive `\password` role provisioning
  runbook §7   worker Coolify resources (etl / pdf-render / provider-sync)
USAGE
}

APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply)   APPLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown flag: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

STAGE_APPLY_ARGS=()
[[ $APPLY -eq 1 ]] && STAGE_APPLY_ARGS=(--apply)

BOX_IP="${BOX_IP:-}"
BOX_IP_FROM_OPERATOR=0
[[ -n "$BOX_IP" ]] && BOX_IP_FROM_OPERATOR=1

##############################################################################
# Stage 1 — provision-vps.sh
##############################################################################
step "Stage 1/3 — provision-vps.sh (Hetzner provision + hardening + Coolify)"

if [[ $BOX_IP_FROM_OPERATOR -eq 1 ]]; then
  info "BOX_IP=$BOX_IP given by operator -- skipping stage 1, resuming at stage 2"
else
  STAGE1_LOG="$(mktemp)"
  set +e
  # ${arr[@]+"${arr[@]}"}, not a bare "${arr[@]}": under `set -u`, expanding
  # an EMPTY array with plain "${arr[@]}" is treated as an unset parameter
  # and aborts on bash < 4.4 (macOS ships 3.2) -- measured while validating
  # this script. The `+` form only expands when the array is set, empty or
  # not, so a preflight run (STAGE_APPLY_ARGS empty) passes zero args
  # instead of dying here.
  "$REPO_ROOT/scripts/provision-vps.sh" ${STAGE_APPLY_ARGS[@]+"${STAGE_APPLY_ARGS[@]}"} 2>&1 | tee "$STAGE1_LOG"
  STAGE1_RC=${PIPESTATUS[0]}
  set -e
  [[ $STAGE1_RC -eq 0 ]] || { rm -f "$STAGE1_LOG"; die "stage 1 (provision-vps.sh) failed with exit $STAGE1_RC"; }

  # Machine-readable handoff: provision-vps.sh prints `BOX_IP=<ip>` to its
  # own stdout as soon as it resolves the box's address (see that script's
  # own comment at the print site). `-m1`, first match wins -- the value
  # never changes within one run once printed.
  BOX_IP="$(grep -m1 '^BOX_IP=' "$STAGE1_LOG" | cut -d= -f2- || true)"
  rm -f "$STAGE1_LOG"

  if [[ -z "$BOX_IP" ]]; then
    if [[ $APPLY -eq 0 ]]; then
      ok "stage 1 preflight: box does not exist yet -- would be created under --apply"
      step "Preflight summary"
      info "stage 1 (provision-vps.sh): OK -- would create the box"
      info "stage 2 (provision-supabase-stack.sh): SKIPPED -- no BOX_IP until stage 1 creates the box"
      info "stage 3 (mint-supabase-jwt-keys.sh): SKIPPED -- same reason"
      printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing was created. Re-run with --apply to execute the full spine.\n'
      exit 0
    else
      die "stage 1 (provision-vps.sh) succeeded but printed no BOX_IP -- cannot proceed to stage 2/3. This is a stage-1 defect, not expected behavior under --apply."
    fi
  fi
fi
ok "BOX_IP=$BOX_IP"

##############################################################################
# Stage 2 — provision-supabase-stack.sh
##############################################################################
step "Stage 2/3 — provision-supabase-stack.sh (Supabase Coolify stack)"
# Do NOT call coolify-materialize-supabase-mounts.sh here -- stage 2 already
# calls it internally, with BOX_IP passed through explicitly (fixed
# 2026-09-11 after a sibling-script default caused a prod write). Calling it
# again from this wrapper would be redundant at best and, if this wrapper
# ever passed it a different BOX_IP than stage 2 resolved, exactly the kind
# of silent-fallthrough bug that incident was about.
if ! BOX_IP="$BOX_IP" "$REPO_ROOT/scripts/provision-supabase-stack.sh" ${STAGE_APPLY_ARGS[@]+"${STAGE_APPLY_ARGS[@]}"}; then
  die "stage 2 (provision-supabase-stack.sh) failed"
fi
ok "stage 2 complete"

##############################################################################
# Stage 3 — mint-supabase-jwt-keys.sh
##############################################################################
step "Stage 3/3 — mint-supabase-jwt-keys.sh (real HS256 keys + verify)"
# --verify-live always: runs the four-probe check whether or not this
# invocation also mints (under --apply). Without --apply it verifies
# whatever keys are already live; mint-supabase-jwt-keys.sh itself skips the
# verify with a printed reason if the stack has no containers yet (nothing
# to verify against).
MINT_ARGS=(--verify-live)
[[ $APPLY -eq 1 ]] && MINT_ARGS+=(--apply)
if ! BOX_IP="$BOX_IP" "$REPO_ROOT/scripts/mint-supabase-jwt-keys.sh" "${MINT_ARGS[@]}"; then
  die "stage 3 (mint-supabase-jwt-keys.sh) failed"
fi
ok "stage 3 complete"

##############################################################################
# Remaining steps -- always printed, apply or preflight
##############################################################################
step "Remaining steps -- NOT run by this script"
cat <<REMAINING
      The scripted spine above covers runbook §1 + §3 (VPS + Coolify) and
      §4 (Supabase stack + real keys). What's left needs a human decision
      or a console, not a forgotten script:

      §2  DNS            point the domain's A record at the box's PRIMARY
                          IP (printed by stage 1 above / on re-run). F/CTO-
                          only registrar access.

      §5  Secrets        enter the production_only app-service secrets
                          (SUPABASE_SERVICE_ROLE_KEY, PLAID_*, etc.) into
                          Coolify's UI directly. Sec-gated; not scripted
                          here by design -- see this script's own "DESIGN
                          SEAM" header comment for where a future scripted
                          push would slot in.

      §6  Migrations     run \`supabase db push\` (or the CI/Coolify-driven
                          apply, per runbook §6) against the fresh instance.

      §6.1/§6.2 Roles     interactive \\password handoff for pfin_etl and
                          pfin_provider_sync -- deliberately never scripted
                          (a piped/scripted password reaches shell history
                          or a server log; see runbook §6.1).

      §7  Workers         create the etl / pdf-render / provider-sync
                          Coolify resources.

      One command did NOT do all of the above -- it did §1/§3/§4 only.
REMAINING

if [[ $APPLY -eq 0 ]]; then
  printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing was created. Re-run with --apply to execute the full spine.\n'
else
  ok "standup.sh --apply complete through §1/§3/§4"
fi
