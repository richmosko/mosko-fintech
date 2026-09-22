#!/usr/bin/env bash
#
# coolify-discord-notify.sh -- BACKLOG.md §7.36 item 74 (docs/deployment-
# runbook.md §8 / ARCH §4 Observability): re-establish Coolify -> Discord
# notifications on the box. Replaces `provision.sh`'s old `run_discord()`
# BY-HAND stub ("Coolify dashboard -> Notifications -> add the webhook").
# DevOps-owned. Sec joint-review mandatory (a new TINKER-WRITE-ALLOW
# marker + a secrets-adjacent write path).
#
# MEASURED (team-lead, live Coolify 4.3.18 box, 2026-09-21 22:35Z) --
# cited here, not re-derived:
#   - `php artisan route:list --path=api` grepped for notif/team: ZERO
#     hits. There is NO public Coolify REST-API surface for notification
#     config (confirmed live, not by omission) -- unlike every other
#     script in this repo, this one has no `api()`/curl helper at all.
#   - `discord_notification_settings` -- exactly ONE row exists, team_id 0
#     ("Root Team"). Columns: `discord_enabled` (bool), `discord_webhook_
#     url` (text, `encrypted` CAST on the Eloquent model
#     `App\Models\DiscordNotificationSettings` -- raw SQL cannot write it,
#     same reason `coolify-materialize-supabase-mounts.sh`'s own
#     TINKER-WRITE-ALLOW-06 goes through the model instead of psql),
#     `discord_ping_enabled`, and 15 per-event booleans. Relation:
#     `App\Models\Team::find(0)->discordNotificationSettings`
#     (Team.php:346; row created at team creation, Team.php:68).
#   - Test-send mechanism: `app/Livewire/Notifications/Discord.php:208`
#     does `$this->team->notify(new \App\Notifications\Test(channel:
#     'discord'))` -- queued (`Test implements ShouldQueue`), and
#     `app/Jobs/SendMessageToDiscordJob.php::handle()` (read live,
#     temp/discord-measurements/SendMessageToDiscordJob.php.txt) ends in
#     `Http::withOptions(...)->post($url, $message->toPayload());` with
#     NO `->throw()` and NO status check -- a 4xx from Discord is
#     swallowed, the job reports success, nothing reaches `failed_jobs`.
#     Neither `dispatchSync` nor a `failed_jobs` delta can observe
#     acceptance. This script therefore does NOT go through the queued
#     job at all -- it builds the SAME payload the job would
#     (`(new \App\Notifications\Test(channel: 'discord'))->toDiscord()
#     ->toPayload()`), POSTs it itself inside the SAME tinker process, and
#     asserts the raw HTTP status Discord returns (204, or 200 also
#     accepted) -- read + one outbound POST, not an Eloquent write, so it
#     needs no TINKER-WRITE marker and runs in a SEPARATE tinker
#     invocation from the ALLOW-08 write below.
#   - Team-lead measured, 2026-09-21, that `.env`'s `DISCORD_WEBHOOK_URL`
#     at that moment held a 21-character placeholder that did NOT match a
#     real Discord webhook URL's shape (`^https://(discord|discordapp)
#     \.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+$`, ~120 chars) -- a GET
#     against it returned nothing. F/CTO supplied the real value shortly
#     after (team-lead re-verified, 2026-09-22: 121 chars, matches the
#     shape, GET 200, already live in every consumer). This script does
#     NOT trust either fact as current state, though -- `--apply` always
#     shape-checks whatever `.env` holds AT RUN TIME (before ANY box
#     contact) rather than a claim about what it held on any one date --
#     see WEBHOOK_URL_RE below.
#   - UNMEASURED, stated rather than assumed: whether Coolify's own
#     `SendMessageToDiscordJob` retries (`$tries = 5`) ever race this
#     script's own direct POST (they would send two structurally-
#     identical test messages to the same channel in that case) -- not a
#     safety issue (idempotent notification, no state mutated by
#     receiving it twice), just an honest gap.
#
# WHAT NEVER CROSSES ARGV, ENV DUMP, OR STDOUT
#   The webhook URL is read from `$REPO_ROOT/.env` LOCALLY (same
#   `read_env_var()` shape as provision-vps.sh/provision-supabase-
#   stack.sh), shape-checked LOCALLY, and delivered to the box the SAME
#   way provision-vps.sh's TINKER-WRITE-ALLOW-02 root-password reset
#   delivers COOLIFY_ADMIN_PASSWORD: a 0600 seed env-file written over SSH
#   STDIN (`umask 077; cat > $SEED_ENV_FILE`), read inside the remote PHP
#   process with `getenv()`, NEVER as a `docker exec -e`/`--execute`
#   argument (both would be ps-visible on the box). The seed file is
#   shredded via a `trap ... EXIT` registered FIRST inside the one remote
#   script that reads it (same discipline as db-role-handoff.sh's own
#   SEED_FILE) -- fires on success, a `set -e` abort, or a signal, never
#   left behind on any exit path. Nothing this script prints, anywhere,
#   ever contains the URL -- only its truncated (16 hex char) SHA-256, the
#   same hash-bound-readback shape db-role-handoff.sh's own leg E uses,
#   and a defensive post-hoc grep of the whole captured remote-script
#   output for the literal URL (FATAL, value never printed, if found) --
#   belt-and-suspenders on a value that structurally should never reach
#   that stream in the first place.
#
# TWO INDEPENDENT MODES, NOT A PREFLIGHT/APPLY PAIR THAT SHARE A .env READ
#   --state  read-only. SSHs to the box, reads the live
#            DiscordNotificationSettings row via tinker, and prints
#            `current state: ABSENT|DISABLED|ENABLED-URL-EMPTY|ENABLED`
#            plus every flag as `name=true/false` -- NEVER the URL.
#            Deliberately does NOT read `$REPO_ROOT/.env` at all (an
#            operator inspecting live box state should not need a local
#            .env present, and this mode's own exit code is what
#            `provision.sh`'s preflight call uses to decide whether to
#            proceed to `--apply` -- see run_discord() in provision.sh).
#            Exit 0 whenever the box answered (any of the four states,
#            including ABSENT/DISABLED -- "not yet enabled" is not a
#            failure of THIS read). Exit 1 (FATAL) only on an SSH/tinker
#            infrastructure failure or a cardinality anomaly (more than
#            one settings row for team_id=0, or the row genuinely
#            missing while the team itself exists -- an anomaly worth
#            investigating by hand, not silently averaging over).
#   --apply  reads + shape-checks `$REPO_ROOT/.env`'s DISCORD_WEBHOOK_URL
#            FIRST, before any SSH call at all -- a malformed value
#            refuses immediately (exit 1), never touching the box.
#            Idempotent: re-reads live state + a hash-bound comparison of
#            the STORED value against the .env value; if the row is
#            already ENABLED, the hash matches, and all four target flags
#            (see below) are already true, the Eloquent write is SKIPPED
#            ("already correct" -- exit 0, VERIFIED, no-op) -- but the
#            live Discord test-send below still runs every `--apply`,
#            whether or not a write happened, since that is the actual
#            liveness proof this step exists to provide (BACKLOG item
#            74's own AC: "verify a test event is received").
#
# THE FOUR FLAGS THIS SCRIPT TURNS ON (team-lead, ARCH §4 Observability --
# deploy + cron visibility; recorded here as the trivial decision it is,
# not silently assumed): `deployment_success`, `status_change`,
# `scheduled_task_success`, `server_reachable`. Every OTHER flag is left
# at its measured current value (see the table above) -- this script's
# own `update()` call sets every column to its FINAL target value
# unconditionally (idempotent by construction: applying it twice reaches
# the same end state either way), not a read-modify-write over a partial
# set.
#
# ⚠ Sec F1 gate (ARCH §4 Observability -- "default Discord payloads must
# be audited for log/PII excerpts before V1 ships with Discord active"),
# RULED (Sec, PR #871 review): two of the 20 `toDiscord()` builders under
# app/Notifications/** carry COMMAND OUTPUT as a field value, not just
# names/links -- `app/Notifications/Database/BackupFailed.php:54`
# (`addField('Output', $this->output)`) and
# `app/Notifications/Database/BackupSuccessWithS3Warning.php:61`
# (`addField('S3 Error', $this->s3_error)`), gated by `backup_failure`
# and `backup_success` respectively. Sec's ruling: `backup_failure` is
# WRITTEN `false` by this script (corrected from an earlier draft that
# would have re-asserted the box's measured `true` default on every
# apply) -- both `Output` and `S3 Error` are unbounded command output
# (pg_dump/restore errors routinely carry connection strings, role/
# schema/table names, and row fragments on constraint/encoding errors)
# reaching a third party (Discord) that retains messages indefinitely;
# no Coolify-managed backup runs on this stack today, so disabling it
# costs nothing, while leaving it enabled would arm a real financial-
# data disclosure channel silently the moment a backup is configured,
# with no further review. `backup_success` was already `false` in the
# original write, consistent with this ruling.
# ⚠ TREAT THE PAIR TOGETHER: both `backup_failure` AND `backup_success`
# gate output-bearing builders (`Output` / `S3 Error` respectively) --
# enabling EITHER one requires a fresh Sec ruling, not just a flip of
# the literal in the update() call below. Sec's own bound on this
# ruling: Sec did NOT verify the two builders -- Coolify is not
# vendored in this repo, so the citations above rest on the
# implementer's measurement of Coolify's source on the box,
# corroborated by the 20-builder field-name dump but not
# independently checked. If a re-measurement finds the builders
# differ, re-run the ruling rather than inheriting it.
#
# USAGE
#   BOX_IP=<box-ip> scripts/coolify-discord-notify.sh              # same as --state
#   BOX_IP=<box-ip> scripts/coolify-discord-notify.sh --state
#   BOX_IP=<box-ip> scripts/coolify-discord-notify.sh --apply
#
# EXIT CODES (this repo's `provision.sh` vocabulary -- returned directly,
# never translated, same convention as smoke-ca1-env-pattern.sh /
# smoke-remaining-checks.sh):
#   0  VERIFIED -- --state: box answered, state printed. --apply: the
#      settings row is ENABLED with a hash-matching URL and every target
#      flag correct (written this run, or already correct), AND the live
#      Discord test-send was accepted (HTTP 200/204).
#   1  FAILED -- malformed .env URL (shape check), SSH/tinker
#      infrastructure failure, a cardinality anomaly, a hash mismatch
#      after write, a cleartext-URL leak detected in captured output, or
#      Discord rejected the test-send (non-2xx, status named, URL never
#      printed).
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

MODE=""
for arg in "$@"; do
  case "$arg" in
    --state) MODE="state" ;;
    --apply) MODE="apply" ;;
    *) echo "unknown flag: $arg" >&2; echo "usage: $0 [--state|--apply]" >&2; exit 2 ;;
  esac
done
[[ -n "$MODE" ]] || MODE="state"   # bare invocation == --state (provision.sh's own preflight call)

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# --- Apply mode's OWN preflight: read + shape-check $REPO_ROOT/.env's
# DISCORD_WEBHOOK_URL LOCALLY, before ANY SSH/box contact at all -- not
# even the bare reachability ping below. `--state` never reaches this
# block (deliberately does not need .env present -- see this script's
# own header).
if [[ "$MODE" == "apply" ]]; then
  step "Reading + shape-checking DISCORD_WEBHOOK_URL from $REPO_ROOT/.env (before any box contact)"
  read_env_var() { grep -m1 "^$1=" "$REPO_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d '\r\n' || true; }
  WEBHOOK_URL="$(read_env_var DISCORD_WEBHOOK_URL)"
  [[ -n "$WEBHOOK_URL" ]] || die "DISCORD_WEBHOOK_URL is missing or empty in $REPO_ROOT/.env -- add it (target channel -> Settings -> Integrations -> Webhooks, per docs/deployment-runbook.md Part 1) and re-run."
  # Real Discord webhook URLs: https://discord.com/api/webhooks/<id>/<token>
  # (discordapp.com is the legacy/still-accepted host). This check runs
  # against WHATEVER $REPO_ROOT/.env holds AT RUN TIME -- it never trusts
  # a claim about a past value (team-lead measured a malformed placeholder
  # here on 2026-09-21, then a corrected real value the next day; this
  # code cares about neither snapshot, only the live read). Refusing here,
  # before any SSH call, is the load-bearing property -- the box is never
  # contacted with a value this check has already rejected.
  WEBHOOK_URL_RE='^https://(discord|discordapp)\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+$'
  if ! [[ "$WEBHOOK_URL" =~ $WEBHOOK_URL_RE ]]; then
    die "DISCORD_WEBHOOK_URL in .env is not a Discord webhook URL (shape check; value not shown)"
  fi
  ok "DISCORD_WEBHOOK_URL shape-checked (value never printed)"
  EXPECTED_HASH="$(printf '%s' "$WEBHOOK_URL" | sha256sum | cut -c1-16)"
fi

BOX_IP="${BOX_IP:-}"
[[ -n "$BOX_IP" ]] || die "BOX_IP is required, not defaulted -- set it explicitly (same discipline as every other scripts/*.sh in this repo)."
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }

sshx true >/dev/null 2>&1 || die "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"

# --- The one read-only state query, shared by --state and --apply's own
# idempotency check. A pure read (no write verb) -- carries no
# TINKER-WRITE marker. `</dev/null` per this repo's own tree-wide
# heredoc-stdin-drain discipline (scripts/ci/fence-heredoc-stdin-drain.sh)
# -- this specific invocation is a single ssh ARGUMENT, not fed via a
# heredoc remote block, so it is not actually in that fence's flagged
# shape (plain `docker exec`, no -i/-it), but the redirect is added
# unconditionally anyway, same "defensively, not because this exact line
# needs it today" posture db-role-handoff.sh's own header states for its
# leg B.
read_state() {
  sshx "docker exec coolify php artisan tinker --execute='
/* probe:discord-notification-settings-state */
\$t = \App\Models\Team::find(0);
if (!\$t) { echo \"FATAL_TEAM_ABSENT\"; return; }
\$cnt = \App\Models\DiscordNotificationSettings::where(\"team_id\", 0)->count();
if (\$cnt === 0) { echo \"ABSENT\"; return; }
if (\$cnt > 1) { echo \"FATAL_CARDINALITY_\" . \$cnt; return; }
\$s = \App\Models\DiscordNotificationSettings::where(\"team_id\", 0)->firstOrFail();
\$fields = [\"discord_ping_enabled\",\"deployment_success\",\"deployment_failure\",\"status_change\",\"backup_success\",\"backup_failure\",\"scheduled_task_success\",\"scheduled_task_failure\",\"docker_cleanup_success\",\"docker_cleanup_failure\",\"server_disk_usage\",\"server_reachable\",\"server_unreachable\",\"server_patch\",\"traefik_outdated\",\"restart_limit_reached\"];
\$parts = [\$s->discord_enabled ? \"true\" : \"false\", ((string) \$s->discord_webhook_url === \"\") ? \"true\" : \"false\"];
foreach (\$fields as \$f) { \$parts[] = \$f . \"=\" . (\$s->\$f ? \"true\" : \"false\"); }
echo implode(\"|\", \$parts);
' </dev/null" 2>/dev/null | tail -1 | tr -d '\r\n'
}

# Parses read_state()'s own pipe-delimited output into:
#   STATE            ABSENT|DISABLED|ENABLED-URL-EMPTY|ENABLED
#   FLAG_LINE        the printed "name=true/false ..." block (--state only)
#   FLAG_<name>      per-flag bash variable, true/false (apply's own idempotency check)
parse_state() {
  local raw="$1"
  case "$raw" in
    FATAL_TEAM_ABSENT) die "Team id=0 does not exist on the box -- this is not a Discord-specific problem, something upstream (RootUserSeeder / provision-vps.sh's admin bootstrap) never ran. Investigate before retrying." ;;
    FATAL_CARDINALITY_*) die "discord_notification_settings has ${raw#FATAL_CARDINALITY_} rows for team_id=0, expected exactly 1 -- refusing to guess which is authoritative." ;;
    "") die "read_state() returned empty output -- SSH/tinker call produced nothing to parse." ;;
  esac
  if [[ "$raw" == "ABSENT" ]]; then
    STATE="ABSENT"; FLAG_LINE=""
    return 0
  fi
  [[ "$raw" =~ ^(true|false)\|(true|false)\|.+$ ]] || die "read_state() returned unparseable output ('$raw') -- refusing to guess."
  local enabled url_empty rest
  enabled="${raw%%|*}"
  rest="${raw#*|}"
  url_empty="${rest%%|*}"
  rest="${rest#*|}"
  FLAG_LINE="$rest"
  if [[ "$enabled" == "false" ]]; then
    STATE="DISABLED"
  elif [[ "$url_empty" == "true" ]]; then
    STATE="ENABLED-URL-EMPTY"
  else
    STATE="ENABLED"
  fi
  # Populate FLAG_<name>=true/false for apply's own idempotency check.
  local IFS='|' entry name val
  for entry in $FLAG_LINE; do
    name="${entry%%=*}"; val="${entry#*=}"
    printf -v "FLAG_${name}" '%s' "$val"
  done
}

if [[ "$MODE" == "state" ]]; then
  step "Discord notification settings -- live state (team_id=0)"
  RAW="$(read_state)"
  parse_state "$RAW"
  printf 'current state: %s\n' "$STATE"
  if [[ -n "$FLAG_LINE" ]]; then
    printf '%s\n' "$FLAG_LINE" | tr '|' '\n' | sed 's/^/      /'
  fi
  exit 0
fi

# --- --apply -----------------------------------------------------------
# WEBHOOK_URL/EXPECTED_HASH already computed above, before the SSH
# reachability check -- see this script's header for why that ordering
# is load-bearing.
step "Current live state (idempotency check)"
RAW="$(read_state)"
parse_state "$RAW"
info "current state: $STATE"

NEED_WRITE=1
if [[ "$STATE" == "ENABLED" ]]; then
  # Hash-bound comparison -- re-read the STORED value's own truncated
  # hash (never the value) and compare to EXPECTED_HASH computed above.
  STORED_HASH="$(sshx "docker exec coolify php artisan tinker --execute='
/* probe:discord-webhook-hash */
\$s = \App\Models\DiscordNotificationSettings::where(\"team_id\", 0)->first();
echo \$s ? substr(hash(\"sha256\", (string) \$s->discord_webhook_url), 0, 16) : \"ABSENT\";
' </dev/null" 2>/dev/null | tail -1 | tr -d '\r\n')"
  if [[ "$STORED_HASH" == "$EXPECTED_HASH" ]]; then
    # Every flag this script's own update() call below sets to something
    # OTHER than the box's measured default must be checked here, or the
    # idempotency skip could report "already correct" while a real flag
    # (e.g. backup_failure, Sec's PR #871 ruling) still needs writing.
    # deployment_success/status_change/scheduled_task_success/
    # server_reachable target "true"; backup_failure targets "false".
    FLAGS_MATCH=1
    for f in deployment_success status_change scheduled_task_success server_reachable; do
      var="FLAG_${f}"
      [[ "${!var:-}" == "true" ]] || FLAGS_MATCH=0
    done
    [[ "${FLAG_backup_failure:-}" == "false" ]] || FLAGS_MATCH=0
    if [[ "$FLAGS_MATCH" -eq 1 ]]; then
      NEED_WRITE=0
      ok "already ENABLED, hash-bound URL match, every target flag already correct -- write skipped (idempotent no-op)"
    fi
  fi
fi

if [[ "$NEED_WRITE" -eq 1 ]]; then
  step "Delivering the webhook URL to the box as a 0600 seed (piped over SSH stdin, never argv)"
  SEED_ENV_FILE="/root/.pfin/_discord_seed.$$.env"
  sshx "mkdir -p /root/.pfin && chmod 700 /root/.pfin"
  printf 'DISCORD_WEBHOOK_URL=%s\n' "$WEBHOOK_URL" | sshx "umask 077; cat > $SEED_ENV_FILE"
  ok "seed delivered to $SEED_ENV_FILE (0600, root-only)"

  step "Writing discord_enabled + discord_webhook_url + flags via Coolify's own Eloquent model (encrypted-cast column -- raw SQL cannot write it)"
  WRITE_LOG="$(mktemp)"
  chmod 600 "$WRITE_LOG"
  if sshx "env SEED_ENV_FILE=\"$SEED_ENV_FILE\" bash -s" <<'REMOTE' > "$WRITE_LOG" 2>&1
set -euo pipefail
umask 077
trap 'shred -u "$SEED_ENV_FILE" 2>/dev/null || rm -f "$SEED_ENV_FILE"' EXIT
docker exec --env-file "$SEED_ENV_FILE" coolify php artisan tinker --execute='
/* TINKER-WRITE-ALLOW-08 */
(function () {
  $url = getenv("DISCORD_WEBHOOK_URL");
  $s = \App\Models\DiscordNotificationSettings::where("team_id", 0)->first();
  if (!$s) { echo "FATAL_ROW_ABSENT"; return; }
  $s->update([
    "discord_enabled" => true,
    "discord_webhook_url" => $url,
    "discord_ping_enabled" => true,
    "deployment_success" => true,
    "deployment_failure" => true,
    "status_change" => true,
    "backup_success" => false,
    "backup_failure" => false,
    "scheduled_task_success" => true,
    "scheduled_task_failure" => true,
    "docker_cleanup_success" => false,
    "docker_cleanup_failure" => true,
    "server_disk_usage" => true,
    "server_reachable" => true,
    "server_unreachable" => true,
    "server_patch" => true,
    "traefik_outdated" => true,
    "restart_limit_reached" => true,
  ]);
  echo "WRITE_OK";
})();
' </dev/null
echo REMOTE_DONE
REMOTE
  then
    WRITE_RC=0
  else
    WRITE_RC=$?
  fi

  # Cleartext-scrub guard -- structural, unconditional, same shape as
  # provision-vps.sh's own $BOOTSTRAP_LOG check. Never print the value
  # even while reporting the leak.
  if grep -qF -- "$WEBHOOK_URL" "$WRITE_LOG"; then
    rm -f "$WRITE_LOG"
    die "the webhook URL's cleartext value appeared in the write step's own captured output -- refusing to proceed or print it. Investigate before retrying."
  fi
  if [[ "$WRITE_RC" -ne 0 ]]; then
    info "write step output (mode 600, preserved for diagnosis): $WRITE_LOG"
    die "the remote write script exited $WRITE_RC -- see $WRITE_LOG"
  fi
  if grep -qF "FATAL_ROW_ABSENT" "$WRITE_LOG"; then
    rm -f "$WRITE_LOG"
    die "discord_notification_settings row for team_id=0 disappeared between the idempotency read and the write -- a race, or something deleted it. Refusing to guess."
  fi
  if ! grep -qF "WRITE_OK" "$WRITE_LOG"; then
    info "write step output (mode 600, preserved for diagnosis): $WRITE_LOG"
    die "the write script completed without printing the expected WRITE_OK sentinel -- refusing to trust an unconfirmed write. See $WRITE_LOG"
  fi
  rm -f "$WRITE_LOG"
  ok "write applied"

  step "Hash-bound readback (post-write, value never printed)"
  STORED_HASH_AFTER="$(sshx "docker exec coolify php artisan tinker --execute='
/* probe:discord-webhook-hash-postwrite */
\$s = \App\Models\DiscordNotificationSettings::where(\"team_id\", 0)->first();
echo \$s ? substr(hash(\"sha256\", (string) \$s->discord_webhook_url), 0, 16) : \"ABSENT\";
' </dev/null" 2>/dev/null | tail -1 | tr -d '\r\n')"
  [[ "$STORED_HASH_AFTER" == "$EXPECTED_HASH" ]] || die "post-write hash-bound readback does not match the .env value's hash (stored='$STORED_HASH_AFTER' expected='$EXPECTED_HASH') -- the write did not take effect as expected. Hash only -- neither value is ever read back or printed."
  ok "hash-bound readback confirmed: the stored discord_webhook_url matches .env's DISCORD_WEBHOOK_URL"
fi

step "Sending the live Discord test notification (same payload Coolify's own Test-notification button sends) and asserting acceptance"
TEST_LOG="$(mktemp)"
chmod 600 "$TEST_LOG"
if sshx "docker exec coolify php artisan tinker --execute='
/* probe:discord-test-send -- read + one outbound POST, no Eloquent write, no TINKER-WRITE marker needed */
\$s = \App\Models\DiscordNotificationSettings::where(\"team_id\", 0)->first();
if (!\$s || (string) \$s->discord_webhook_url === \"\") { echo \"FATAL_NO_URL\"; return; }
\$url = \$s->discord_webhook_url;
\$payload = (new \App\Notifications\Test(channel: \"discord\"))->toDiscord()->toPayload();
\$resp = \Illuminate\Support\Facades\Http::withOptions(\App\Rules\SafeWebhookUrl::httpClientOptions(\$url))->post(\$url, \$payload);
echo \"HTTP_STATUS_\" . \$resp->status();
' </dev/null" > "$TEST_LOG" 2>&1
then
  TEST_RC=0
else
  TEST_RC=$?
fi
TEST_STATUS_LINE="$(tail -1 "$TEST_LOG" | tr -d '\r\n')"
rm -f "$TEST_LOG"
[[ "$TEST_RC" -eq 0 ]] || die "the test-send tinker call itself failed (exit $TEST_RC) -- see above for any captured output."
if [[ "$TEST_STATUS_LINE" == "FATAL_NO_URL" ]]; then
  die "discord_webhook_url read back empty immediately after a confirmed write -- a race, or the write did not persist. Refusing to guess."
fi
if [[ ! "$TEST_STATUS_LINE" =~ ^HTTP_STATUS_([0-9]+)$ ]]; then
  die "test-send did not report a parseable HTTP status ('$TEST_STATUS_LINE') -- refusing to guess whether Discord accepted it."
fi
HTTP_STATUS="${BASH_REMATCH[1]}"
if [[ "$HTTP_STATUS" != "204" && "$HTTP_STATUS" != "200" ]]; then
  die "Discord rejected the test notification: HTTP $HTTP_STATUS (webhook URL never printed). Check the URL is still valid in the target channel's Integrations -> Webhooks settings."
fi

printf '\n\033[32mOK: Discord accepted the Coolify test notification (HTTP %s)\033[0m\n' "$HTTP_STATUS"
exit 0
