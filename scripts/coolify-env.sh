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
#   No secret value, and no Coolify API token, is ever placed in this
#   script's own OR the box's on-box process argv, at any point --
#   BACKLOG.md §7.36 item 25's class ("a credential in a ps-visible argv
#   on the production box," Sec-ruled BLOCKING at PR #752 C-1). The token
#   crosses into curl via a `-K <temp-config-file>` directive (file mode
#   0600 under /root/.pfin/, unlinked in a `finally` immediately after the
#   call -- never a command-line argument, the #734/#735 pattern already
#   proven in provision-supabase-stack.sh / push-production-secrets.sh's
#   own api()), and every request BODY (which, for `set`, carries the env
#   VALUE) crosses via `--data-binary @-` fed through the subprocess's
#   stdin pipe -- neither appears in `ps` / `/proc/*/cmdline` on the box.
#   This is a step PAST push-production-secrets.sh's own api(), which
#   still puts its JSON body on `-d '<json>'` argv (item 25 named the
#   TOKEN half of that script's exposure, not the body half -- left
#   standing there as a separate, smaller-blast-radius gap since that
#   script's whole job is pushing real secret values and closing it is
#   that script's own follow-up, not this PR's). Reusing the `-d`-in-argv
#   shape here, in a script landing specifically to close by-hand secret
#   handling, would reintroduce item 25's exact defect as new code in the
#   same PR that removes it from the runbook -- so the bar here is the
#   full stdin-body pattern from the start, not the partial one.
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
SET_ALLOWLIST=(PGRST_DB_SCHEMAS MIGRATOR_DB_USER)
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
#   --post-check '<cmd>': after a successful (optionally deployed) apply,
#   run <cmd> via `bash -c` on THIS machine, with BOX_IP, AUTOMATION_KEY
#   and POST_CHECK_APP_UUID exported for it to use -- this script never
#   dumps a container's raw `env` itself (that risks carrying OTHER
#   secrets past this tool's own hygiene boundary, exactly the mistake
#   docs/deployment-runbook.md §6.9 step 5 warns against by name); the
#   caller's own command does its own scoped, filtered read, e.g. for
#   §6.9:
#     --post-check 'ssh -o BatchMode=yes -i "$AUTOMATION_KEY" root@"$BOX_IP" \
#       "docker compose --project-name $POST_CHECK_APP_UUID exec -T rest env" \
#       | grep "^PGRST_DB_SCHEMAS=" | scripts/ci/fence-pgrst-schemas-live.sh'

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
# api() -- identical hardened shape to provision-supabase-stack.sh /
# push-production-secrets.sh's own 2026-09-11 fix (#734/#735): the token
# crosses via a `curl -K <tempfile>` directive, a real on-disk file
# (0600, under /root/.pfin/, unlinked in a `finally`) rather than a `-K -`
# stdin config -- freeing stdin for the request BODY, which crosses via
# `--data-binary @-` fed through subprocess `input=`. Neither the token
# nor the body ever appears in this process's own argv, so neither can
# appear in `ps` / `/proc/*/cmdline` on the box, and neither appears in a
# raised CalledProcessError's default str(argv) representation either.
read -r -d '' PY_API_HELPER <<'PY' || true
import json, os, subprocess, sys

def die(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)

def api(token, method, path, body=None):
    if '"' in token or "\n" in token:
        die("Coolify API token contains an unexpected character -- refusing to build a curl config for it")
    cfg_path = f"/root/.pfin/.curlcfg.{os.getpid()}.{path.__hash__() & 0xffffff}"
    old_umask = os.umask(0o077)
    try:
        with open(cfg_path, "w") as f:
            f.write('header = "Authorization: Bearer ' + token + '"\n')
            if body is not None:
                f.write('header = "Content-Type: application/json"\n')
        cmd = ["curl", "-fsS", "-K", cfg_path, "-X", method]
        stdin_input = None
        if body is not None:
            cmd += ["--data-binary", "@-"]
            stdin_input = json.dumps(body).encode()
        cmd += [f"http://localhost:8000/api/v1{path}"]
        try:
            result = subprocess.run(cmd, input=stdin_input, capture_output=True, check=True)
        except subprocess.CalledProcessError as exc:
            die(f"Coolify API {method} {path} failed: exit {exc.returncode} ({exc.stderr.decode(errors='replace').strip()[:200]})")
    finally:
        os.umask(old_umask)
        try:
            os.unlink(cfg_path)
        except OSError:
            pass
    out = result.stdout.decode()
    return json.loads(out) if out.strip() else None
PY

UUID_RE='^[a-z0-9]{20,32}$'
if [[ "$APP_QUERY" =~ $UUID_RE ]]; then
  APP_UUID="$APP_QUERY"
else
  APP_UUID="$(sshx_in <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "$APP_QUERY" <<'PYEOF'
$PY_API_HELPER
import sys
token, name = sys.argv[1], sys.argv[2]
apps = api(token, "GET", "/applications")
matches = [a for a in apps if a.get("name") == name]
if not matches:
    die(f"no application named '{name}' found")
print(matches[0]["uuid"])
PYEOF
REMOTE
)"
fi
[[ -n "$APP_UUID" ]] || die "could not resolve application '$APP_QUERY' to a UUID"
ok "application '$APP_QUERY' -> $APP_UUID"

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
fi

# --- Step 7: optional caller-supplied post-check ----------------------------
if [[ -n "$POST_CHECK" ]]; then
  step "Running post-check"
  BOX_IP="$BOX_IP" AUTOMATION_KEY="$AUTOMATION_KEY" POST_CHECK_APP_UUID="$APP_UUID" bash -c "$POST_CHECK"
  ok "post-check passed"
fi

step "Done"
info "$OP on $APP_UUID for: ${KEYS[*]}$( [[ $DEPLOY -eq 1 ]] && echo ' (deployed)' )$( [[ -n "$POST_CHECK" ]] && echo ' (post-check passed)' )"
