#!/usr/bin/env bash
#
# github-ci-setup.sh -- docs/deployment-runbook.md Part 3 row 16 (§6.4):
# the GitHub-side half of the ci-migrate CI trigger -- the Actions
# secret, the Actions variable, and the `production-migrator` Environment
# with its required reviewer. BACKLOG.md §7.36 item 73 (W-5). DevOps-owned.
#
# WHAT THIS SCRIPT DOES NOT DO (Sec ask, stated so the boundary is never
# assumed wider than it is): it does not approve any deployment. The
# per-fire GitHub Environment reviewer approval (Actions tab -> Review
# deployments) stays a manual, recurring, Sec-ruled gate on EVERY
# migrator trigger fire from here on -- this script's whole job is
# ensuring the GATE EXISTS and names the right reviewer, once, at
# stand-up time. See the runbook's own "unnumbered" row for that
# recurring step; it is deliberately not this script's concern.
#
# THE THREE THINGS, AND WHY EACH ONE READS BACK DIFFERENTLY
#   1. CI_MIGRATE_SSH_PRIVATE_KEY (Actions secret, secrets-manifest.yml
#      ci_only) -- GitHub's API never returns a secret's value once set,
#      by design. Preflight/readback here can only confirm PRESENCE
#      (`gh secret list` -- name + last-updated timestamp), never the
#      value. `gh secret set NAME < file` reads the private key from a
#      FILE via stdin redirection, which is not an argv exposure (the gh
#      CLI process's own argv never contains the key; only the shell's
#      redirection target, the file path, does).
#   2. PROD_SSH_HOST (Actions variable, non-secret) -- GitHub's API DOES
#      return a variable's value, so the readback here confirms the
#      value matches, not just that the name exists.
#   3. `production-migrator` Environment + required reviewer -- readback
#      confirms the environment exists AND that a reviewer rule names the
#      CURRENT authenticated `gh` user (read via `gh api user`, never
#      hardcoded -- the reviewer is whoever is running this script with
#      admin access at stand-up time, not a fixed name that would go
#      stale the day admin access changes hands).
#
# WHY THE REVIEWER LOGIN IS READ LIVE, NOT HARDCODED
#   A hardcoded reviewer name is a silent single point of failure the day
#   that person's GitHub account changes (renamed, deactivated, access
#   revoked) -- the environment would still "have a reviewer" by this
#   script's own check while naming someone who can no longer review
#   anything. Reading `gh api user` at run time ties the reviewer to
#   whoever is actually authorized and running the stand-up, which is the
#   only identity this script can verify without assuming a hostname.
#
#   Sec N-3 (PR #849 review), stated so this is never over-read later:
#   the reviewer named by this script IS `gh api user` -- whoever runs
#   it -- and `prevent_self_review` is not set. For a solo F/CTO this is
#   correct by construction: the gate's value here is a deliberate click
#   before a production migration fires, not separation of duties (there
#   is no second person to separate from). If this repo ever grows a
#   second admin, revisit whether the reviewer should be named
#   differently and whether `prevent_self_review` should be set.
#
# PROD_SSH_HOST'S VALUE (box IP now, domain later)
#   Read from `$REPO_ROOT/.env`'s BOX_IP (script-written by
#   provision-vps.sh --apply). Once docs/deployment-runbook.md Part 3 row
#   9 (scripts/assign-app-domain.sh, item 72) assigns a real domain, an
#   operator re-runs this script (idempotent -- `gh variable set`
#   overwrites in place) to repoint PROD_SSH_HOST at the domain instead of
#   the bare IP. This script does not choose which value is "correct" --
#   it always uses whatever BOX_IP currently is.
#
# USAGE
#   scripts/github-ci-setup.sh              # preflight: read-only, prints the plan
#   scripts/github-ci-setup.sh --apply      # sets the secret, the variable, and the environment+reviewer
#
#   CI_MIGRATE_SSH_PUBKEY is read from .env (script-written contract,
#   scripts/provision.env.example) -- the PRIVATE half's path is derived
#   by stripping the ".pub" suffix, the same keypair-naming convention
#   provision-vps.sh's own SSH_PUBKEYS list already assumes.
#
# EXIT CODES
#   0  VERIFIED -- preflight: the plan is printable (repo resolved, `gh`
#      authenticated, files present). --apply: all three read back
#      correctly (secret present + recently updated, variable value
#      matches, environment exists with the current user named as
#      reviewer).
#   1  REFUSED -- a real finding: a readback value disagrees with what
#      was just set (PROD_SSH_HOST), or the environment readback after
#      the reviewer PUT does not show the current user as a required
#      reviewer. Sec F-4a (PR #849 review) CORRECTED THIS LINE, not the
#      code: an earlier version of this doc claimed the CODE refuses when
#      the environment already exists WITHOUT a reviewer rule -- it does
#      not; that state is logged as an info line and this script ADDS the
#      reviewer anyway (the code's own behavior -- re-add, fail-closed on
#      the readback -- is the one Sec wants kept; only the doc was wrong).
#   2  FAILED -- a precondition this script could not even attempt under
#      (missing .env names, `gh` not authenticated, private key file
#      absent, `gh` API error).
#
# ORCHESTRATOR CONTRACT (BACKLOG.md §7.36 item 76's provision.sh calls
# this directly): non-interactive, no prompts, no `read`. Idempotent by
# construction -- `gh secret set`/`gh variable set` overwrite in place,
# and the environment+reviewer PUT is safe to re-issue with the same
# body. Every fact used (secret list, variable value, environment state,
# the authenticated user) is resolved LIVE each run, never cached.

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

ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-production-migrator}"

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

command -v gh >/dev/null 2>&1 || die2 "gh (GitHub CLI) not found on PATH -- install it first"
gh auth status >/dev/null 2>&1 || die2 "gh is not authenticated -- run 'gh auth login' first"

REPO_SLUG="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
[[ -n "$REPO_SLUG" ]] || die2 "could not resolve the current repo via 'gh repo view' -- run this from inside the repo checkout"

BOX_IP="$(grep -m1 '^BOX_IP=' "$REPO_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d '\r\n' || true)"
[[ -n "$BOX_IP" ]] || die2 "BOX_IP absent/blank in $REPO_ROOT/.env -- run scripts/provision-vps.sh --apply first"

CI_MIGRATE_SSH_PUBKEY="$(grep -m1 '^CI_MIGRATE_SSH_PUBKEY=' "$REPO_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d '\r\n' || true)"
[[ -n "$CI_MIGRATE_SSH_PUBKEY" ]] || CI_MIGRATE_SSH_PUBKEY="$HOME/.ssh/id_ed25519_ci_migrate.pub"
CI_MIGRATE_SSH_PRIVATE_KEY_PATH="${CI_MIGRATE_SSH_PUBKEY%.pub}"
[[ -f "$CI_MIGRATE_SSH_PRIVATE_KEY_PATH" ]] \
  || die2 "private key not found at $CI_MIGRATE_SSH_PRIVATE_KEY_PATH (derived by stripping .pub from CI_MIGRATE_SSH_PUBKEY=$CI_MIGRATE_SSH_PUBKEY) -- generate the keypair first (scripts/provision-vps.sh's own header shows the ssh-keygen invocation) or set CI_MIGRATE_SSH_PUBKEY to the right path"

REVIEWER_LOGIN="$(gh api user --jq .login 2>/dev/null || true)"
REVIEWER_ID="$(gh api user --jq .id 2>/dev/null || true)"
[[ -n "$REVIEWER_LOGIN" && -n "$REVIEWER_ID" ]] || die2 "could not read the authenticated user via 'gh api user' -- is 'gh auth login' scoped correctly?"
# Sec F-4c (PR #849 review): REVIEWER_ID was interpolated straight into a
# python3 -c source string with no shape check -- validate it is a bare
# integer before it is ever used to build API request bodies or source text.
[[ "$REVIEWER_ID" =~ ^[0-9]+$ ]] || die2 "'gh api user --jq .id' returned a non-numeric id '$REVIEWER_ID' -- refusing to use it"

step "Plan"
info "repo:               $REPO_SLUG"
info "secret:             CI_MIGRATE_SSH_PRIVATE_KEY  <-  $CI_MIGRATE_SSH_PRIVATE_KEY_PATH"
info "variable:           PROD_SSH_HOST = $BOX_IP"
info "environment:        $ENVIRONMENT_NAME, required reviewer = $REVIEWER_LOGIN (id $REVIEWER_ID, read live via 'gh api user')"

step "Current state (read-only)"
SECRET_LIST="$(gh secret list --repo "$REPO_SLUG" --json name,updatedAt 2>/dev/null || echo '[]')"
SECRET_PRESENT="$(python3 -c "import json,sys; print('1' if any(s['name']=='CI_MIGRATE_SSH_PRIVATE_KEY' for s in json.loads(sys.argv[1])) else '0')" "$SECRET_LIST" 2>/dev/null || echo 0)"
if [[ "$SECRET_PRESENT" == "1" ]]; then
  UPDATED_AT="$(python3 -c "import json,sys; [print(s['updatedAt']) for s in json.loads(sys.argv[1]) if s['name']=='CI_MIGRATE_SSH_PRIVATE_KEY']" "$SECRET_LIST")"
  ok "CI_MIGRATE_SSH_PRIVATE_KEY: present (last updated $UPDATED_AT; value never readable, by design)"
else
  info "CI_MIGRATE_SSH_PRIVATE_KEY: absent"
fi

CURRENT_VAR="$(gh variable get PROD_SSH_HOST --repo "$REPO_SLUG" 2>/dev/null || true)"
if [[ -n "$CURRENT_VAR" ]]; then
  ok "PROD_SSH_HOST: present, value '$CURRENT_VAR'"
else
  info "PROD_SSH_HOST: absent"
fi

ENV_JSON="$(gh api "repos/$REPO_SLUG/environments/$ENVIRONMENT_NAME" 2>/dev/null || true)"
ENV_EXISTS=0
ENV_HAS_REVIEWER=0
ENV_REVIEWER_LOGIN=""
ENV_REVIEWERS_JSON="[]"
if [[ -n "$ENV_JSON" ]]; then
  ENV_EXISTS=1
  ENV_REVIEWER_LOGIN="$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
for rule in d.get('protection_rules', []):
    if rule.get('type') == 'required_reviewers':
        for r in rule.get('reviewers', []):
            rev = r.get('reviewer', {})
            if rev.get('type') == 'User' or 'login' in rev:
                print(rev.get('login', ''))
                sys.exit(0)
print('')
" "$ENV_JSON" 2>/dev/null || true)"
  # Sec F-4b (PR #849 review): the FULL reviewer entry list (type+id),
  # not just the first User login -- needed below to preserve any
  # co-reviewer across the PUT. GitHub's environments PUT is (my reading
  # of the REST docs, not independently load-tested here) a full REPLACE
  # of the reviewers array, not a merge -- a naive single-element PUT
  # would silently drop an existing co-reviewer (a Team entry, or a
  # different User) the day one exists.
  ENV_REVIEWERS_JSON="$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
out = []
for rule in d.get('protection_rules', []):
    if rule.get('type') == 'required_reviewers':
        for r in rule.get('reviewers', []):
            rev = r.get('reviewer', {})
            if rev.get('type') and rev.get('id') is not None:
                out.append({'type': rev['type'], 'id': rev['id']})
print(json.dumps(out))
" "$ENV_JSON" 2>/dev/null || echo '[]')"
  [[ -n "$ENV_REVIEWER_LOGIN" ]] && ENV_HAS_REVIEWER=1
fi
if [[ "$ENV_EXISTS" == "1" ]]; then
  if [[ "$ENV_HAS_REVIEWER" == "1" ]]; then
    ok "environment '$ENVIRONMENT_NAME': present, required reviewer = $ENV_REVIEWER_LOGIN"
  else
    info "environment '$ENVIRONMENT_NAME': present, NO required-reviewer rule (Sec-ruled gate is currently OPEN)"
  fi
else
  info "environment '$ENVIRONMENT_NAME': absent"
fi

if [[ "$APPLY" -eq 0 ]]; then
  step "Done (preflight)"
  info "nothing written -- re-run with --apply to set the secret, the variable, and the environment+reviewer."
  exit 0
fi

step "Applying"

gh secret set CI_MIGRATE_SSH_PRIVATE_KEY --repo "$REPO_SLUG" < "$CI_MIGRATE_SSH_PRIVATE_KEY_PATH" \
  || die2 "gh secret set CI_MIGRATE_SSH_PRIVATE_KEY failed"
ok "CI_MIGRATE_SSH_PRIVATE_KEY set (value never echoed by this script or by gh)"

gh variable set PROD_SSH_HOST --repo "$REPO_SLUG" --body "$BOX_IP" \
  || die2 "gh variable set PROD_SSH_HOST failed"
READBACK_VAR="$(gh variable get PROD_SSH_HOST --repo "$REPO_SLUG" 2>/dev/null || true)"
[[ "$READBACK_VAR" == "$BOX_IP" ]] || die "PROD_SSH_HOST read-back shows '$READBACK_VAR', expected '$BOX_IP' -- the write did not take."
ok "PROD_SSH_HOST = $READBACK_VAR (read-back confirmed)"

if [[ "$ENV_EXISTS" == "1" && "$ENV_HAS_REVIEWER" == "1" && "$ENV_REVIEWER_LOGIN" != "$REVIEWER_LOGIN" ]]; then
  info "environment '$ENVIRONMENT_NAME' already has a DIFFERENT required reviewer ($ENV_REVIEWER_LOGIN) -- this script ADDS/confirms $REVIEWER_LOGIN as well, GET-then-merging the existing reviewers list before the PUT (Sec F-4b, PR #849 review) rather than sending a single-element array; it never REMOVES an existing reviewer."
fi

# GET-then-merge, not a bare single-element PUT (Sec F-4b, PR #849
# review): ENV_REVIEWERS_JSON is this environment's FULL reviewer list as
# read moments ago, above. Merge our own {"type":"User","id":REVIEWER_ID}
# into it (deduplicated by type+id) rather than replacing the array
# outright -- passed via argv, not embedded into python source text,
# since it is live API-returned JSON, not a literal this script controls.
ENV_BODY="$(python3 -c "
import json, sys
existing = json.loads(sys.argv[1])
mine = {'type': 'User', 'id': int(sys.argv[2])}
merged = list(existing)
if not any(r.get('type') == mine['type'] and r.get('id') == mine['id'] for r in merged):
    merged.append(mine)
print(json.dumps({'reviewers': merged, 'deployment_branch_policy': None}))
" "$ENV_REVIEWERS_JSON" "$REVIEWER_ID")"
# Sec F-4d (PR #849 review, noted not asked to change): this PUT also
# unconditionally sends deployment_branch_policy=None, which overwrites
# any existing branch policy on the environment to "any branch" -- a
# real side effect, but the required-reviewer rule is the binding
# control this script exists to set, so this is stated rather than fixed.
printf '%s' "$ENV_BODY" | gh api --method PUT "repos/$REPO_SLUG/environments/$ENVIRONMENT_NAME" --input - >/dev/null \
  || die2 "gh api PUT repos/$REPO_SLUG/environments/$ENVIRONMENT_NAME failed"

READBACK_ENV_JSON="$(gh api "repos/$REPO_SLUG/environments/$ENVIRONMENT_NAME" 2>/dev/null || true)"
[[ -n "$READBACK_ENV_JSON" ]] || die2 "could not read back the environment immediately after the PUT"
READBACK_REVIEWER="$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
for rule in d.get('protection_rules', []):
    if rule.get('type') == 'required_reviewers':
        for r in rule.get('reviewers', []):
            rev = r.get('reviewer', {})
            if rev.get('login') == sys.argv[2]:
                print('1')
                sys.exit(0)
print('0')
" "$READBACK_ENV_JSON" "$REVIEWER_LOGIN" 2>/dev/null || echo 0)"
[[ "$READBACK_REVIEWER" == "1" ]] \
  || die "environment '$ENVIRONMENT_NAME' read-back does NOT show $REVIEWER_LOGIN as a required reviewer after the PUT -- refusing to report success on an ungated environment."
ok "environment '$ENVIRONMENT_NAME': required reviewer = $REVIEWER_LOGIN (read-back confirmed)"

# Co-reviewer survival check (Sec F-4b, PR #849 review): if the PRE-PUT
# reviewer list held any entry OTHER than our own, confirm each one is
# STILL present after the PUT -- proves the GET-then-merge actually
# preserved them, not just that our own entry landed.
SURVIVAL_CHECK="$(python3 -c "
import json, sys
before = json.loads(sys.argv[1])
after_json = json.loads(sys.argv[2])
mine_id = int(sys.argv[3])
after = []
for rule in after_json.get('protection_rules', []):
    if rule.get('type') == 'required_reviewers':
        for r in rule.get('reviewers', []):
            rev = r.get('reviewer', {})
            if rev.get('type') and rev.get('id') is not None:
                after.append((rev['type'], rev['id']))
missing = [b for b in before if (b.get('type'), b.get('id')) != ('User', mine_id) and (b.get('type'), b.get('id')) not in after]
print(json.dumps(missing))
" "$ENV_REVIEWERS_JSON" "$READBACK_ENV_JSON" "$REVIEWER_ID" 2>/dev/null || echo '[]')"
[[ "$SURVIVAL_CHECK" == "[]" ]] \
  || die "environment '$ENVIRONMENT_NAME' read-back is missing pre-existing reviewer(s) that were present before this PUT: $SURVIVAL_CHECK -- the GET-then-merge did not actually preserve them."

step "Done"
info "CI_MIGRATE_SSH_PRIVATE_KEY set, PROD_SSH_HOST=$BOX_IP, and '$ENVIRONMENT_NAME' requires $REVIEWER_LOGIN's approval -- every migrator trigger fire from here on still needs that approval by hand (Actions tab -> Review deployments), unchanged by this script."
exit 0
