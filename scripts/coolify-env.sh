#!/usr/bin/env bash
#
# coolify-env.sh — scripted set/delete of a single Coolify application's
# env-store entries for a COMMITTED ALLOWLIST of non-secret names.
# DevOps-owned. Replaces the by-hand Coolify UI steps
# docs/deployment-runbook.md §6.9 step 4 (PGRST_DB_SCHEMAS) and §6.8
# step 7 (MIGRATOR_DB_USER/MIGRATOR_DB_PASSWORD deletion) used to name --
# F/CTO correction, 2026-09-19, mid-§6.9: "this should be a procedure that
# can be run by a stranger with minimal by-hand intervention," and every
# one of those steps has an API equivalent this repo already uses
# elsewhere (provision-supabase-stack.sh / provision-migrator-app.sh /
# push-production-secrets.sh).
#
# WHAT THIS DOES
#   set    <APP_NAME|uuid> NAME=VALUE [NAME=VALUE...] [--apply] [--deploy]
#                                     [--post-check '<shell command>']
#     PATCH the named key(s) into the resolved application's env store,
#     read the store back on the box and FAIL if any value does not match
#     byte-exact, then (only with --deploy) redeploy and wait for a
#     terminal state, then (only with --post-check) run the given shell
#     command on THIS (the operator's) machine.
#   delete <APP_NAME|uuid> NAME [NAME...] [--apply] [--deploy]
#                                          [--post-check '<shell command>']
#     DELETE the named key(s) -- a real Coolify DELETE
#     (`routes/api.php:414`, `ApplicationsController::delete_env_by_uuid`,
#     confirmed on the pinned v4.3.18 source to call the model's own
#     `forceDelete()` -- not a blank-write) -- and read the store back to
#     assert the name is ABSENT, not merely blanked. `delete` may name a
#     credential (e.g. MIGRATOR_DB_PASSWORD) because deletion carries no
#     value -- there is nothing to leak by naming a key for removal.
#
# WHAT THIS REFUSES TO DO
#   `set` refuses any NAME not in SET_ALLOWLIST below, and SEPARATELY
#   refuses any NAME that appears in secrets-manifest.yml's `ci_only` or
#   `production_only` sets -- belt-and-braces: even a careless future
#   SET_ALLOWLIST edit cannot turn this into a secret-value pusher.
#   scripts/push-production-secrets.sh and the scripts/provision-*.sh
#   family already own the secret-value-injection path, with their own
#   value-origin discipline (operator .env, mint-if-absent, etc.) this
#   script does not reproduce and must not be extended to reproduce.
#
#   No secret value, and no Coolify API token, is ever placed in CURL's
#   argv on either machine -- BACKLOG.md §7.36 item 25's class ("a
#   credential in a ps-visible argv on the production box," Sec-ruled
#   BLOCKING at PR #752 C-1). The token crosses into curl via a `-K -`
#   stdin config directive (never a command-line argument -- the
#   #734/#735 pattern already proven in push-production-secrets.sh's own
#   api()), and every request BODY (which, for `set`, carries the env
#   VALUE) crosses via a 0600 temp file under /root/.pfin/ (unlinked in a
#   `finally` immediately after the call), read by `--data-binary
#   @<path>` -- neither the token nor the body ever appears in curl's own
#   argv, so neither can appear in `ps` / `/proc/*/cmdline` on the box
#   for curl's invocation, and neither appears in a raised
#   CalledProcessError's default str(argv) representation either. This is
#   a step PAST push-production-secrets.sh's own api() on the body half,
#   which still puts its JSON body on `-d '<json>'` argv (item 25 named
#   only the TOKEN half of that script's exposure) -- while matching, not
#   exceeding, that script's own `-K -` convention on the token half.
#
#   ⚠ ONE EXPOSURE REMAINS, NAMED RATHER THAN GLOSSED (Sec, PR #825
#   review, V3): the box-side `python3 - "$TOKEN"` invocations (the
#   driver script itself, not curl) pass the token as that process's OWN
#   argv[1], so it IS `ps`-visible on the box for the lifetime of each
#   call. That is a pre-existing convention copied from
#   push-production-secrets.sh:606 / provision-supabase-stack.sh:547 /
#   provision-migrator-app.sh:267, booked against all of them together at
#   BACKLOG.md §7.36 item 60 so no copy is left as the stale one. It is
#   NOT closed here, and this header must not be read as claiming it is.
#
# WHAT THIS DOES NOT PROTECT
#   The VALUE half of a `set` argv (`NAME=VALUE` on THIS command's own
#   argv, on the OPERATOR's own machine) is not hidden -- SET_ALLOWLIST is
#   built to hold only non-secret names for exactly this reason (its own
#   values are safe to type, echo, and log). If a name that is genuinely
#   secret is ever proposed for SET_ALLOWLIST, that is the wrong fix --
#   route it through push-production-secrets.sh's operator-.env-sourced
#   mechanism instead, never through a literal on this command's argv.
#
# ALLOWLISTS -- edit here to extend; each addition is a one-way trust
# decision (this script will PATCH/DELETE it against production) --
# Sec joint-review mandatory per this script's own routing (it edits
# Coolify env stores directly, same class as provision-*.sh).
#
# PUBLIC_SUPABASE_URL / PUBLIC_SUPABASE_ANON_KEY -- added for §7.1 step 1
# (the pfin-app first-deploy procedure). Both non-secret BY SEC RULING
# (2026-09-09, recorded in docs/deployment-runbook.md §5 "Non-secret
# runtime config" -- PUBLIC_SUPABASE_URL is the stack's own gateway
# address, not confidential; PUBLIC_SUPABASE_ANON_KEY is a role:anon JWT,
# publishable by construction, gated by RLS + the ADR-029 aal2 backstop,
# not by secrecy). Neither appears in secrets-manifest.yml's ci_only or
# production_only sets (confirmed live against the manifest at the same
# PR that added this allowlist entry) -- Step 2 below (the manifest
# refusal) would independently reject either name if that were ever
# wrong, so this addition does not weaken that fence.
#
# PFIN_DB_SSLMODE -- added for the etl/provider-sync workers' later
# deploys (BACKLOG.md §7.36 item 26, Sec-ruled non-secret production
# override; docs/deployment-runbook.md §5/§7). Same non-manifest-name
# status, same independent-refusal backstop.
#
# PFIN_DB_HOST / PFIN_DB_PORT / PFIN_DB_NAME / PFIN_DB_USER -- added for
# item 68's W-2 (worker DB-role handoff; docs/deployment-runbook.md §7.2).
# All four are non-secret connection-shape config, not credentials -- the
# credential is PFIN_DB_PASSWORD, which stays OFF this allowlist (it IS a
# secrets-manifest.yml production_only name, so the manifest-refusal check
# above would reject it even if someone added it here; scripts/db-role-
# handoff.sh is its own, separate, dedicated write path). Confirmed
# non-manifest names (checked against secrets-manifest.yml at the same PR
# that added this entry). Values per worker, per docs/deployment-runbook.md
# §4/§6 (the stack's own internal service DNS, not each worker's local-dev
# .env.example default): PFIN_DB_HOST=db, PFIN_DB_PORT=5432,
# PFIN_DB_NAME=postgres (the actual database name -- "pfin" is the SCHEMA,
# not the database), PFIN_DB_USER=pfin_etl or pfin_provider_sync.
#
# PLAID_ENV -- added for provider-sync's deploy. Non-secret Plaid API tier
# selector ("sandbox"/"production"), already declared as such in
# workers/provider-sync/.env.example ("non-secret — Plaid API tier").
#
# ADMISSION_PROBE_PUBLIC_URLS -- added for provider-sync's SELF-279 CA-2
# recurring reachability probe. Non-secret by construction (public https
# FQDNs, comma-separated; unset/empty is fail-safe no-op per
# workers/provider-sync/.env.example's own "non-secret" declaration) --
# never a credential, never a URL carrying embedded creds (Note N1 there).
#
# SITE_URL / MAILER_TEMPLATES_INVITE|CONFIRMATION|RECOVERY|MAGIC_LINK|
# EMAIL_CHANGE -- ADR-074 (F/CTO-ratified 2026-09-23). All six are
# non-secret (public URLs and a public hostname); none appears in
# secrets-manifest.yml (re-checked at this PR). SITE_URL is the
# confirmation-email link's own host; the five MAILER_TEMPLATES_* are
# fixed http://app:3000/... literals `scripts/provision-supabase-
# stack.sh` computes -- see this script's own value-shape constraints
# below for both.
SET_ALLOWLIST=(PGRST_DB_SCHEMAS MIGRATOR_DB_USER PUBLIC_SUPABASE_URL PUBLIC_SUPABASE_ANON_KEY PFIN_DB_SSLMODE PFIN_DB_HOST PFIN_DB_PORT PFIN_DB_NAME PFIN_DB_USER PLAID_ENV ADMISSION_PROBE_PUBLIC_URLS SITE_URL MAILER_TEMPLATES_INVITE MAILER_TEMPLATES_CONFIRMATION MAILER_TEMPLATES_RECOVERY MAILER_TEMPLATES_MAGIC_LINK MAILER_TEMPLATES_EMAIL_CHANGE)
# MIGRATOR_DB_PASSWORD is delete-only, never settable here (it is minted
# ONLY by scripts/provision-migrator-app.sh's own mint-if-absent step,
# ADR-072 Amendment 4 Decision B -- routing it through this script's
# `set` would mean the production DDL password could be typed on an
# operator's command line, which Sec already ruled the wrong direction
# for the sibling case (secrets-manifest.yml's MIGRATOR_DB_PASSWORD
# entry, "PROVISIONING" paragraph)).
DELETE_ALLOWLIST=(PGRST_DB_SCHEMAS MIGRATOR_DB_USER MIGRATOR_DB_PASSWORD)
#
# USAGE
#   BOX_IP=<box-ip> scripts/coolify-env.sh set    <APP_NAME|uuid> NAME=VALUE [NAME=VALUE...] [--apply] [--deploy] [--post-check '<cmd>']
#   BOX_IP=<box-ip> scripts/coolify-env.sh delete <APP_NAME|uuid> NAME [NAME...]              [--apply] [--deploy] [--post-check '<cmd>']
#
#   Without --apply: preflight only -- resolves the app, prints current
#   store state (value shown for non-secret names; PRESENT/ABSENT only
#   for any name that also appears in secrets-manifest.yml), writes
#   nothing.
#   --deploy (only meaningful with --apply): after a verified set/delete,
#   POST /deploy and wait for a terminal state (same 90x4s ceiling as
#   scripts/provision-migrator-app.sh's own deploy wait) before returning.
#   ⚠ THIS IS A PRECONDITION WAIT, NOT A SUCCESS CRITERION (Sec, PR #825
#   review, F7) -- a `finished` deploy means the rebuild completed, never
#   that the new value reached the running process. The outcome assertion
#   is --post-check's job (§6.9) or the next runbook step's own
#   measurement (§6.8 step 7 -> scripts/migrator-cutover-verify.sh leg
#   10). Same distinction ADR-072 Amendment 6 consequence 3 draws for the
#   migration path, named here so the two polls are not simplified to
#   one. If --deploy is given with no --post-check, this script prints a
#   NOTE rather than silently treating the deploy alone as proof.
#   --post-check '<cmd>': after a successful (optionally deployed) apply,
#   run <cmd> via `bash -c` on THIS machine, with BOX_IP, AUTOMATION_KEY
#   and POST_CHECK_APP_UUID exported for it to use -- this script never
#   dumps a container's raw `env` itself (that risks carrying OTHER
#   secrets past this tool's own hygiene boundary, exactly the mistake
#   docs/deployment-runbook.md §6.9 step 5 warns against by name); the
#   caller's own command does its own scoped, filtered read, INSIDE the
#   remote command string -- the grep must run ON THE BOX, not after the
#   ssh hop, or the unfiltered container env (PGRST_DB_URI, the
#   authenticator password; PGRST_JWT_SECRET) crosses the wire before
#   it's filtered. E.g. for §6.9:
#     --post-check 'ssh -o BatchMode=yes -i "$AUTOMATION_KEY" root@"$BOX_IP" \
#       "docker compose --project-name $POST_CHECK_APP_UUID exec -T rest env | grep \"^PGRST_DB_SCHEMAS=\"" \
#       | scripts/ci/fence-pgrst-schemas-live.sh'

set -euo pipefail

# REPO_ROOT resolution -- same worktree-refusal guard as
# record-coolify-uuids.sh / provision-migrator-app.sh (2026-09-16
# incident: a worktree-relative resolution silently wrote to a throwaway
# per-worktree file). secrets-manifest.yml is read from here.
if [[ -n "${REPO_ROOT:-}" ]]; then
  :
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ "$SCRIPT_DIR" == *"/.claude/worktrees/"* ]]; then
    printf '\n\033[31mFAIL\033[0m  running from an agent worktree (%s) -- secrets-manifest.yml should be read from the main checkout so this script sees the same tree everything else does. Set REPO_ROOT=<main checkout path> to override, or run from the main checkout.\n' "$SCRIPT_DIR" >&2
    exit 1
  fi
  GIT_COMMON_DIR="$(git -C "$SCRIPT_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || GIT_COMMON_DIR=""
  if [[ -z "$GIT_COMMON_DIR" ]]; then
    printf '\n\033[31mFAIL\033[0m  could not resolve the repo root via git rev-parse --git-common-dir from %s. Set REPO_ROOT explicitly.\n' "$SCRIPT_DIR" >&2
    exit 1
  fi
  REPO_ROOT="$(cd "$(dirname "$GIT_COMMON_DIR")" && pwd)"
fi

BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

[[ $# -ge 1 ]] || die "usage: $0 {set|delete} <APP_NAME|uuid> ... [--apply] [--deploy] [--post-check '<cmd>']"
OP="$1"; shift
case "$OP" in
  set|delete) : ;;
  *) die "unknown subcommand '$OP' -- expected 'set' or 'delete'" ;;
esac

[[ $# -ge 1 ]] || die "usage: $0 $OP <APP_NAME|uuid> ..."
APP_QUERY="$1"; shift

APPLY=0
DEPLOY=0
POST_CHECK=""
PAIRS=()   # set: "NAME=VALUE" entries. delete: bare "NAME" entries.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --deploy) DEPLOY=1; shift ;;
    --post-check) [[ $# -ge 2 ]] || die "--post-check requires an argument"; POST_CHECK="$2"; shift 2 ;;
    --*) die "unknown flag: $1" ;;
    *) PAIRS+=("$1"); shift ;;
  esac
done
[[ ${#PAIRS[@]} -ge 1 ]] || die "no NAME(s) given"

[[ -n "$BOX_IP" ]] || die "BOX_IP is required, not defaulted -- set it explicitly (same discipline as every other scripts/provision-*.sh)."

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }
sshx_in() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" bash -s; }

sshx true >/dev/null 2>&1 || die "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

# --- Step 1: parse NAME[=VALUE] pairs, validate against the allowlist ----
# Parallel arrays (KEYS[i] <-> VALUES[i]), not an associative array --
# this script's target shell is the OPERATOR's own /bin/bash, which on
# macOS is stock 3.2 (no `declare -A`; same constraint push-production-
# secrets.sh already documents for its own empty-array expansion).
KEYS=()
VALUES=()
if [[ "$OP" == "set" ]]; then
  ALLOW=("${SET_ALLOWLIST[@]}")
  for p in "${PAIRS[@]}"; do
    [[ "$p" == *=* ]] || die "'set' entries must be NAME=VALUE, got: $p"
    k="${p%%=*}"; v="${p#*=}"
    KEYS+=("$k")
    VALUES+=("$v")
  done
else
  ALLOW=("${DELETE_ALLOWLIST[@]}")
  for p in "${PAIRS[@]}"; do
    [[ "$p" != *=* ]] || die "'delete' takes bare NAMEs, not NAME=VALUE: $p"
    KEYS+=("$p")
  done
fi

for k in "${KEYS[@]}"; do
  allowed=0
  for a in "${ALLOW[@]}"; do [[ "$k" == "$a" ]] && allowed=1 && break; done
  [[ $allowed -eq 1 ]] || die "'$k' is not on the $OP allowlist (${ALLOW[*]}) -- add it to this script's own ALLOWLIST array first (Sec joint-review) if this is a genuinely new, intentional case, never as a one-off bypass."
done

# --- Step 1b: value-shape constraints on specific SET_ALLOWLIST names -----
# Sec F-5 (PR #846 review). Name-only allowlisting lets ANY value ride
# under an approved NAME -- these two carry consequences a bare name-check
# cannot catch:
#   PFIN_DB_USER -- sets the identity a worker's DB connection
#   authenticates as. Restricting the value to the three DB roles this
#   repo ever mints (§6.1/§6.2/pre-cutover authenticator) prevents an
#   operator typo, or a copy-paste of a DIFFERENT worker's value, from
#   silently pointing a worker at `postgres` or some other identity with
#   far broader privilege than any minted role.
#   ADMISSION_PROBE_PUBLIC_URLS -- echoed VERBATIM into Discord alerts
#   (workers/provider-sync/.env.example Note N1). Restricting to bare
#   comma-separated https:// FQDNs (no userinfo, no query-string, no path)
#   closes off embedding a credential or a tracking/exfil query string in
#   a value guaranteed to be posted somewhere an operator will read it.
if [[ "$OP" == "set" ]]; then
  for i in "${!KEYS[@]}"; do
    k="${KEYS[$i]}"; v="${VALUES[$i]}"
    case "$k" in
      PFIN_DB_USER)
        case "$v" in
          pfin_etl|pfin_provider_sync|authenticator) ;;
          *) die "'PFIN_DB_USER' value '$v' is not one of the three DB roles this repo mints (pfin_etl, pfin_provider_sync, authenticator) -- refusing. If a new role name is genuinely intentional, add it here (Sec joint-review), never as a one-off bypass." ;;
        esac
        ;;
      ADMISSION_PROBE_PUBLIC_URLS)
        [[ "$v" =~ ^https://[A-Za-z0-9.-]+(,https://[A-Za-z0-9.-]+)*$ ]] \
          || die "'ADMISSION_PROBE_PUBLIC_URLS' value does not match the required shape (bare comma-separated https:// FQDNs, no userinfo, no query-string, no path) -- this value is echoed verbatim into Discord alerts (workers/provider-sync/.env.example Note N1). Refusing."
        ;;
      # ADR-074 (F/CTO-ratified 2026-09-23): SITE_URL is the confirmation-
      # email link's own host, dereferenced by mail clients over the
      # public internet -- must be https://, never localhost/127.0.0.1
      # (same production-always guards scripts/provision-supabase-
      # stack.sh applies at write time; this is the belt to that
      # suspenders on any OTHER write path into this name).
      SITE_URL)
        [[ "$v" == https://* ]] \
          || die "'SITE_URL' value '$v' does not start with https:// -- refusing (this is the confirmation-email link's own host, dereferenced by mail clients over the public internet)."
        case "$v" in
          *localhost*|*127.0.0.1*)
            die "'SITE_URL' value '$v' contains localhost/127.0.0.1 -- refusing (this would ship a dead link in every auth email; see ADR-074 Part 0)." ;;
        esac
        ;;
      # MAILER_TEMPLATES_* -- Consequence 2: a bare path is silently
      # rewritten by GoTrue to SITE_URL + path, an unnoticed public
      # fetch. Each value is a fixed http://app:3000/email-templates/*
      # literal `provision-supabase-stack.sh` computes -- the prefix
      # check both confirms the scheme AND that it targets the private
      # `app` container, not some other host.
      MAILER_TEMPLATES_INVITE|MAILER_TEMPLATES_CONFIRMATION|MAILER_TEMPLATES_RECOVERY|MAILER_TEMPLATES_MAGIC_LINK|MAILER_TEMPLATES_EMAIL_CHANGE)
        [[ "$v" == http://app:3000/email-templates/* ]] \
          || die "'$k' value '$v' does not start with http://app:3000/email-templates/ -- refusing (a bare path or a different host is silently rewritten to SITE_URL + path by GoTrue, becoming an unintended public fetch)."
        ;;
    esac
  done
fi

# --- Step 2: secrets-manifest.yml refusal (set only) ----------------------
# Pure-text extraction, not PyYAML -- this script runs on the OPERATOR's
# machine, which is not guaranteed to have PyYAML installed the way the CI
# runner (check-secrets-nonoverlap.py's own environment) is. The manifest's
# actual shape (`  - NAME    # comment`, one list entry per line, under a
# `ci_only:` / `production_only:` top-level key) is stable and simple
# enough that a positional block-scan is exact, not an approximation.
MANIFEST_NAMES="$(python3 - "$REPO_ROOT/secrets-manifest.yml" <<'PY'
import re, sys
names = set()
in_block = False
with open(sys.argv[1]) as f:
    for line in f:
        line = line.rstrip("\n")
        if re.match(r'^(ci_only|production_only):\s*$', line):
            in_block = True
            continue
        if in_block:
            if re.match(r'^\S', line):  # dedent -- a new top-level key
                in_block = False
                continue
            m = re.match(r'^\s*-\s+([A-Za-z0-9_]+)', line)
            if m:
                names.add(m.group(1))
print("\n".join(sorted(names)))
PY
)"
# POSITIVE CONTROL (Sec, PR #825 review, F2) -- a parseable-but-empty
# manifest (a renamed top-level key, a reflowed list) would silently void
# the refusal below rather than fail: is_manifest_secret() returns false
# for every name over an empty MANIFEST_NAMES, same as a genuinely clean
# manifest. A missing FILE fails closed already (the command substitution
# aborts under `set -e`); this catches the parseable-but-wrong-shape case.
# Anchor on a name this file has carried since v1, whose removal is
# itself a joint-review event.
printf '%s\n' "$MANIFEST_NAMES" | grep -qx SUPABASE_SERVICE_ROLE_KEY \
  || die "secrets-manifest.yml parsed to $(printf '%s\n' "$MANIFEST_NAMES" | grep -c .) name(s) and does NOT contain SUPABASE_SERVICE_ROLE_KEY -- the manifest's shape has changed and this script's refusal cannot be trusted. Fix the parser above (REPO_ROOT=$REPO_ROOT); do not proceed."
is_manifest_secret() {
  local k="$1"
  printf '%s\n' "$MANIFEST_NAMES" | grep -qx "$k"
}

if [[ "$OP" == "set" ]]; then
  for k in "${KEYS[@]}"; do
    if is_manifest_secret "$k"; then
      die "'$k' appears in secrets-manifest.yml (ci_only or production_only) -- this script refuses to 'set' any manifest-declared secret name, regardless of SET_ALLOWLIST. Use scripts/push-production-secrets.sh or the relevant scripts/provision-*.sh mint step for secret values."
    fi
  done
fi

# --- Step 3: resolve the application UUID ---------------------------------
# api() -- token on `curl -K -` (stdin config, never touches disk --
# matches push-production-secrets.sh:617's own convention exactly, and
# is a STRICTER guarantee than a 0600 tempfile: on a SIGKILL or power
# loss mid-call there is no live token-bearing file left behind). The
# request BODY (which, for `set`, carries the env value -- non-secret by
# SET_ALLOWLIST construction, but held to the same discipline regardless)
# crosses via a 0600 temp file under /root/.pfin/ (unlinked in a
# `finally` immediately after the call), read by `--data-binary @<path>`
# -- stdin is single-owner (the token config), so the body cannot also
# use `@-` and gets the on-disk channel instead (Sec, PR #825 review,
# F5: "the two are on the wrong sides" against the prior draft, which had
# this backwards -- token on disk, body on stdin). Neither the token nor
# the body ever appears in curl's own argv, so neither can appear in
# `ps` / `/proc/*/cmdline` on the box for curl's invocation, and neither
# appears in a raised CalledProcessError's default str(argv)
# representation either. ⚠ This does NOT cover the box-side `python3 -
# "$TOKEN"` driver invocations below -- see this file's own header
# ("ONE EXPOSURE REMAINS") and BACKLOG.md §7.36 item 60.
read -r -d '' PY_API_HELPER <<'PY' || true
import json, os, subprocess, sys, tempfile

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
                os.unlink(body_path)
            except OSError:
                pass
    out = result.stdout.decode()
    return json.loads(out) if out.strip() else None
PY

UUID_RE='^[a-z0-9]{20,32}$'
if [[ "$APP_QUERY" =~ $UUID_RE ]]; then
  APP_UUID="$APP_QUERY"
else
  # APP_QUERY is OPERATOR argv, unbounded shape -- crosses via `env` on
  # the ssh command line (shell-escaped with printf %q), never by direct
  # heredoc interpolation, so it cannot be locally re-parsed while this
  # unquoted heredoc is built (Sec, PR #825 review, F4). The heredoc
  # itself stays unquoted only because $PY_API_HELPER needs local
  # substitution; $app_query is read from the REMOTE process's own
  # environment, not from this heredoc's text.
  APP_QUERY_ENV="app_query=$(printf '%q' "$APP_QUERY")"
  APP_UUID="$(sshx "env $APP_QUERY_ENV bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "\$app_query" <<'PYEOF'
$PY_API_HELPER
import sys
token, name = sys.argv[1], sys.argv[2]
apps = api(token, "GET", "/applications")
matches = [a for a in apps if a.get("name") == name]
if len(matches) != 1:
    die(f"expected exactly one application named '{name}', found {len(matches)}")
print(matches[0]["uuid"])
PYEOF
REMOTE
)"
fi
[[ -n "$APP_UUID" ]] || die "could not resolve application '$APP_QUERY' to a UUID"
# Re-validate: $APP_UUID may be Coolify API output (the name-resolution
# branch above) rather than the operator's own UUID-shaped argv -- do not
# trust it to be metacharacter-free just because it came back non-empty
# (Sec, PR #825 review, F4). Every heredoc below interpolates $APP_UUID
# directly; this is what makes that safe.
[[ "$APP_UUID" =~ $UUID_RE ]] || die "resolved UUID '$APP_UUID' is not uuid-shaped -- refusing to interpolate API output into a remote shell"
ok "application '$APP_QUERY' -> $APP_UUID"

# --- Step 3b: PFIN_DB_USER is per-resource, not global (Sec F-8, PR #846
# review) ---------------------------------------------------------------
# Step 1b's shape check above bars a NONSENSE value (`postgres`, a typo)
# cheaply, before any network call. It does NOT catch a VALID-shaped value
# on the WRONG resource: `PFIN_DB_USER=authenticator` passes Step 1b's
# check unconditionally, so it was accepted on `pfin-back-etl` just as
# readily as on `pfin-provider-sync` -- putting the ETL onto PostgREST's
# own `authenticator` identity and defeating the independent-revocability
# rationale ADR-041 / SELF-214 finding B8 chose the dedicated `pfin_etl`
# role for in the first place. This step closes that: once the resource
# is known (resolved above), gate the value against THAT resource's own
# allowed set.
if [[ "$OP" == "set" ]]; then
  for k in "${KEYS[@]}"; do
    if [[ "$k" == "PFIN_DB_USER" ]]; then
      # RESOLVED_NAME: APP_QUERY is already the canonical name when the
      # operator typed one (the common case); only when APP_QUERY was
      # itself UUID-shaped do we not yet know the name -- resolve it with
      # one more read-only API call, same api() helper Step 3 just used.
      if [[ "$APP_QUERY" =~ $UUID_RE ]]; then
        RESOLVED_NAME="$(sshx "env app_uuid=$(printf '%q' "$APP_UUID") bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "\$app_uuid" <<'PYEOF'
$PY_API_HELPER
import sys
token, uuid = sys.argv[1], sys.argv[2]
app = api(token, "GET", f"/applications/{uuid}")
print(app.get("name", ""))
PYEOF
REMOTE
)"
        [[ -n "$RESOLVED_NAME" ]] || die "could not resolve application uuid '$APP_UUID' back to a name -- refusing to set PFIN_DB_USER without knowing which resource this is (Sec F-8)."
      else
        RESOLVED_NAME="$APP_QUERY"
      fi
      v=""
      for i in "${!KEYS[@]}"; do [[ "${KEYS[$i]}" == "PFIN_DB_USER" ]] && v="${VALUES[$i]}"; done
      case "$RESOLVED_NAME" in
        pfin-back-etl)
          case "$v" in
            pfin_etl) ;;
            *) die "'PFIN_DB_USER=$v' is not valid for resource '$RESOLVED_NAME' -- this resource's ONLY minted role is pfin_etl (ADR-041 / SELF-214 B8: dedicated, independently-revocable). Refusing to point the ETL worker at any other identity, including 'authenticator' (PostgREST's own)." ;;
          esac
          ;;
        pfin-provider-sync)
          case "$v" in
            pfin_provider_sync|authenticator) ;;
            *) die "'PFIN_DB_USER=$v' is not valid for resource '$RESOLVED_NAME' -- this resource accepts pfin_provider_sync (post-§6.2-cutover, the dedicated role) or authenticator (pre-cutover, TRANSITIONAL -- BACKLOG.md §7.36 item 71 books the written expiry condition; remove this arm's 'authenticator' branch once §6.2 cutover is confirmed run). Any other value refused." ;;
          esac
          ;;
        *)
          die "PFIN_DB_USER may only be set on 'pfin-back-etl' or 'pfin-provider-sync' -- resource '$RESOLVED_NAME' is neither. Refusing (Sec F-8: no other resource is a documented holder of a PFIN_DB_* database identity)."
          ;;
      esac
      ok "PFIN_DB_USER='$v' valid for resource '$RESOLVED_NAME'"
    fi
  done
fi

# --- Step 4: preflight read of current store state -------------------------
step "Current store state"
sshx_in <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "$APP_UUID" "${KEYS[*]}" "$(printf '%s\n' "$MANIFEST_NAMES" | tr '\n' ' ')" <<'PYEOF'
$PY_API_HELPER
import sys
token, app_uuid, keys_s, manifest_s = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
keys = keys_s.split()
manifest = set(manifest_s.split())
envs = api(token, "GET", f"/applications/{app_uuid}/envs")
by_key = {e["key"]: e for e in envs if not e.get("is_preview", False)}
for k in keys:
    secret = k in manifest
    if k in by_key:
        if secret:
            print(f"      {k}: PRESENT (value withheld -- manifest-declared secret)")
        else:
            print(f"      {k}={by_key[k].get('value','')}")
    else:
        print(f"      {k}: ABSENT")
PYEOF
REMOTE

if [[ $APPLY -eq 0 ]]; then
  printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing written. Re-run with --apply to execute.\n'
  exit 0
fi

# --- Step 5: apply (set = PATCH bulk, delete = DELETE by uuid), then ------
#     read back on the box and assert the outcome byte-exact / absent.
if [[ "$OP" == "set" ]]; then
  step "Setting ${KEYS[*]} on $APP_UUID"

  # Seed file over piped SSH stdin -- same shape as
  # push-production-secrets.sh's own value crossing, applied here even
  # though SET_ALLOWLIST values are non-secret by construction, so the
  # mechanism does not depend on that fact holding forever.
  SEED_LOCAL="$(mktemp)"
  trap 'rm -f "$SEED_LOCAL"' EXIT
  : > "$SEED_LOCAL"
  chmod 600 "$SEED_LOCAL"
  i=0
  for k in "${KEYS[@]}"; do
    printf '%s=%s\n' "$k" "${VALUES[$i]}" >> "$SEED_LOCAL"
    i=$((i + 1))
  done
  BOX_SEED="/root/.pfin/.coolify_env_seed.$$"
  sshx "umask 077; mkdir -p /root/.pfin; cat > $BOX_SEED" < "$SEED_LOCAL"
  rm -f "$SEED_LOCAL"
  trap - EXIT

  sshx_in <<REMOTE
set -e
trap 'shred -u "$BOX_SEED" 2>/dev/null || rm -f "$BOX_SEED"' EXIT
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "$APP_UUID" "$BOX_SEED" <<'PYEOF'
$PY_API_HELPER
import sys
token, app_uuid, seed_file = sys.argv[1], sys.argv[2], sys.argv[3]
with open(seed_file) as f:
    kv = dict(line.rstrip("\n").split("=", 1) for line in f if "=" in line)

api(token, "PATCH", f"/applications/{app_uuid}/envs/bulk", {"data": [{"key": k, "value": v} for k, v in kv.items()]})

# Byte-exact read-back, on the box, never returning the value to the
# caller's own terminal for anything the manifest would call secret --
# these are all SET_ALLOWLIST names so it is safe to name mismatches by
# value here, but the comparison itself (not just the report) happens
# server-side either way.
envs = api(token, "GET", f"/applications/{app_uuid}/envs")
by_key = {e["key"]: e for e in envs if not e.get("is_preview", False)}
bad = []
for k, want in kv.items():
    got = by_key.get(k, {}).get("value")
    if got != want:
        bad.append((k, want, got))
if bad:
    for k, want, got in bad:
        print(f"MISMATCH: {k} -- wrote {want!r}, store reads back {got!r}", file=sys.stderr)
    sys.exit(1)
print(f"VERIFIED: {sorted(kv.keys())}")
PYEOF
REMOTE
  ok "set + byte-exact read-back verified for ${KEYS[*]}"

else
  step "Deleting ${KEYS[*]} from $APP_UUID"
  sshx_in <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "$APP_UUID" "${KEYS[*]}" <<'PYEOF'
$PY_API_HELPER
import sys
token, app_uuid, keys_s = sys.argv[1], sys.argv[2], sys.argv[3]
keys = keys_s.split()

envs = api(token, "GET", f"/applications/{app_uuid}/envs")
by_key = {e["key"]: e for e in envs if not e.get("is_preview", False)}

deleted, already_absent = [], []
for k in keys:
    env = by_key.get(k)
    if env is None:
        already_absent.append(k)
        continue
    # A real DELETE -- routes/api.php delete_env_by_uuid -> forceDelete()
    # on Coolify v4.3.18's own source, confirmed not a blank-write.
    api(token, "DELETE", f"/applications/{app_uuid}/envs/{env['uuid']}")
    deleted.append(k)

# Re-read and assert ABSENCE BY NAME, not by value -- a blanked-not-deleted
# key still carries its name and must FAIL this check (same predicate as
# docs/deployment-runbook.md §6.8 step 10's own discipline).
envs_after = api(token, "GET", f"/applications/{app_uuid}/envs")
still_present = {e["key"] for e in envs_after if not e.get("is_preview", False)} & set(keys)
if still_present:
    for k in sorted(still_present):
        print(f"STILL-PRESENT: {k} -- delete did not remove the name (blanked, not deleted?)", file=sys.stderr)
    sys.exit(1)

print(f"DELETED: {sorted(deleted)}")
print(f"ALREADY-ABSENT: {sorted(already_absent)}")
PYEOF
REMOTE
  ok "delete + absence read-back verified for ${KEYS[*]}"
fi

# --- Step 6: optional redeploy ---------------------------------------------
if [[ $DEPLOY -eq 1 ]]; then
  step "Redeploying $APP_UUID"
  sshx_in <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "$APP_UUID" <<'PYEOF'
$PY_API_HELPER
import sys, time
token, app_uuid = sys.argv[1], sys.argv[2]

d = api(token, "POST", f"/deploy?uuid={app_uuid}")
deployments = (d or {}).get("deployments") or [{}]
deploy_uuid = deployments[0].get("deployment_uuid", "")
if not deploy_uuid:
    die("deploy call did not return a deployment_uuid")
print(f"QUEUED: {deploy_uuid}")

# Same 90x4s ceiling as scripts/provision-migrator-app.sh's own deploy
# wait -- polled server-side, inside this one SSH session, rather than
# 90 separate SSH round trips from the caller.
status = ""
for _ in range(90):
    dep = api(token, "GET", f"/deployments/{deploy_uuid}")
    status = (dep or {}).get("status", "")
    if status in ("finished", "failed"):
        break
    time.sleep(4)

if status != "finished":
    dep = api(token, "GET", f"/deployments/{deploy_uuid}") or {}
    raw = dep.get("logs") or "[]"
    import json as _json
    entries = _json.loads(raw) if isinstance(raw, str) else (raw or [])
    print("\n".join(e.get("output", "") for e in entries[-60:]), file=sys.stderr)
    die(f"deployment {deploy_uuid} status={status!r} -- see log above")

print("FINISHED")
PYEOF
REMOTE
  ok "deploy finished"
  [[ -n "$POST_CHECK" ]] || info "NOTE: --deploy without --post-check -- the deploy finished, but nothing here has observed the new value in the running container. The caller owns that assertion."
fi

# --- Step 7: optional caller-supplied post-check ----------------------------
if [[ -n "$POST_CHECK" ]]; then
  step "Running post-check"
  BOX_IP="$BOX_IP" AUTOMATION_KEY="$AUTOMATION_KEY" POST_CHECK_APP_UUID="$APP_UUID" bash -c "$POST_CHECK"
  ok "post-check passed"
fi

step "Done"
info "$OP on $APP_UUID for: ${KEYS[*]}$( [[ $DEPLOY -eq 1 ]] && echo ' (deployed)' )$( [[ -n "$POST_CHECK" ]] && echo ' (post-check passed)' )"
