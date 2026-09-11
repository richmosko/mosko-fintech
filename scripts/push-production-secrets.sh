#!/usr/bin/env bash
#
# push-production-secrets.sh — bulk-push the app/worker production_only
# secrets from the operator's gitignored local .env into their Coolify
# resources, replacing the 19-by-hand UI entry with one scripted step.
# DevOps-owned. 🔒 SECURITY-SENSITIVE — this is runbook §5 territory
# (Sec joint-review mandatory before this script is trusted against prod;
# see this PR's own description for the design knots below, presented for
# Sec + F/CTO sanity-check, not yet ratified).
#
# WHY THIS EXISTS
#   secrets-manifest.yml's `production_only` set names 19 real credentials.
#   Two are already fully scripted: 9 of them (the self-hosted Supabase
#   stack's own POSTGRES_PASSWORD / JWT_SECRET / ... / SMTP_PASS) are
#   minted-or-overwritten by provision-supabase-stack.sh, and the real
#   ANON_KEY/SERVICE_ROLE_KEY JWTs are minted by mint-supabase-jwt-keys.sh.
#   The remaining app/worker secrets (SUPABASE_SERVICE_ROLE_KEY,
#   PDF_WORKER_SIGNING_KEY, PLAID_CLIENT_ID/SECRET, SIMPLEFIN_TOKEN,
#   WORKER_ADMISSION_SHARED_SECRET, DISCORD_WEBHOOK_URL, FMP_API_KEY,
#   BLS_API_KEY -- 8 of the remaining 10; PFIN_DB_PASSWORD is the 10th and
#   is explicitly OUT OF SCOPE, see DESIGN KNOT 3) were still entered by
#   hand into the Coolify UI, once per resource, per name. This script
#   closes that gap using the SAME envs/bulk API + SSH-stdin pattern
#   provision-supabase-stack.sh already uses for its own SMTP_PASS operator
#   override -- not a new mechanism, an extension of a proven one.
#
# WHAT IT REFUSES TO DO
#   No secret value is ever printed, logged, or returned to this script's
#   own stdout/stderr. Every value crosses the local .env -> SSH stdin ->
#   on-box python3 -> Coolify API boundary exactly the way
#   provision-supabase-stack.sh's SMTP_PASS override does: a per-resource
#   seed file written over SSH stdin (never a command-line argument on
#   either side), read back on the box by PATH only, and the API call
#   itself built with the token as a `curl -K -` stdin config directive
#   (never an argv element -- the #734/#735 CalledProcessError-leak fix
#   this repo already made once, reused verbatim here rather than
#   reintroduced by a fresh author who hasn't hit that incident yet).
#   Reports are NAMES ONLY, grouped by resource. Nothing is created or
#   mutated without --apply; the default is a preflight that only reads
#   (manifest, .env presence/non-emptiness by name, and each target
#   resource's existence) and prints the plan.
#
# ============================================================================
# DESIGN KNOTS -- read before trusting this script against prod. Each one
# is a place this problem is NOT a trivial "loop over a list and PATCH"
# script, stated explicitly per team-lead's brief so Sec + F/CTO can
# sanity-check the resolution, not discover it by reading between the
# lines of a diff.
# ============================================================================
#
# KNOT 1 -- names come from the manifest, not a hardcoded list.
#   PRODUCTION_SECRET_NAMES below is read LIVE from secrets-manifest.yml's
#   `production_only` key (PyYAML, same parser check-secrets-nonoverlap.py
#   already depends on in CI -- boring-choice consistency, not a new
#   dependency this repo hasn't already accepted). Hardcoding the name list
#   here would be exactly the drift the manifest exists to prevent: this
#   script's own secret set would silently stop tracking the manifest the
#   next time a name is added or retired. Only the RESOURCE MAPPING below
#   (which secret goes to which container) is hardcoded -- the manifest has
#   no notion of "which Coolify resource," only "which store."
#
# KNOT 2 -- per-resource mapping, and what's EXCLUDED and why.
#   Not all 19 production_only names are this script's job:
#     EXCLUDED_SUPABASE_STACK (9): POSTGRES_PASSWORD, JWT_SECRET,
#       SECRET_KEY_BASE, VAULT_ENC_KEY, SERVICE_ROLE_KEY, ANON_KEY,
#       DASHBOARD_PASSWORD, PG_META_CRYPTO_KEY, SMTP_PASS -- ALREADY
#       minted/overwritten by provision-supabase-stack.sh (mint-if-absent
#       + the SMTP_PASS operator-override path) and, for the JWT pair,
#       re-minted for real by mint-supabase-jwt-keys.sh. This script must
#       NEVER touch these -- double-handling them here would race the
#       mint-if-absent logic those scripts already own and could silently
#       overwrite a freshly-minted JWT_SECRET with a stale/absent .env
#       value. Cross-checked against provision-supabase-stack.sh's own
#       MINT_SECRETS dict + its SMTP_PASS block, not just copied from the
#       runbook prose -- see EXCLUDED_SUPABASE_STACK below.
#     EXCLUDED_DEFERRED (1): PFIN_DB_PASSWORD -- see KNOT 3.
#   The remaining 8 map to specific resources (SECRET_RESOURCE_MAP below),
#   cross-checked against each target's own .env.example (the enumeration
#   IS the confinement property -- this script must not push a name to a
#   resource whose own .env.example doesn't declare it). Sec review of this
#   PR caught one real gap in that check: workers/etl/.env.example did NOT
#   declare DISCORD_WEBHOOK_URL even though secrets-manifest.yml already
#   named the ETL's monthly_report cron as its fourth consumer -- brought
#   into line in this same PR (workers/etl/.env.example now declares it)
#   rather than left as a false "verified" claim:
#     app            SUPABASE_SERVICE_ROLE_KEY, PDF_WORKER_SIGNING_KEY,
#                    DISCORD_WEBHOOK_URL, WORKER_ADMISSION_SHARED_SECRET
#     pdf-render     PDF_WORKER_SIGNING_KEY (same value as app -- SD-20)
#     etl            FMP_API_KEY, BLS_API_KEY, DISCORD_WEBHOOK_URL
#     provider-sync  PLAID_CLIENT_ID, PLAID_SECRET, SIMPLEFIN_TOKEN,
#                    DISCORD_WEBHOOK_URL, WORKER_ADMISSION_SHARED_SECRET
#   `etl` open question, NOT resolved here: runbook §3's topology table
#   describes ETL as "one image, TWO Coolify units" (nightly ingest +
#   monthly-report cron, each with its own Scheduled Task). Whether that
#   means one Coolify Compose application (one UUID, envs/bulk reaches
#   both containers because they share one compose stack's env) or two
#   separately-registered Coolify resources is not yet settled -- that's a
#   §7 resource-creation-time fact, not something this script can discover
#   ahead of §7 actually creating the resource(s). This script resolves
#   `etl` as ONE resource name (ETL_RESOURCE_NAME, overridable) and dies
#   naming it if not found; if §7 ends up registering two separate
#   resources for the two units, this script needs a second name added to
#   the map for the second one -- flagged here rather than guessed at.
#
# KNOT 3 -- PFIN_DB_PASSWORD is excluded, not forgotten.
#   Two reasons, both disqualifying for a manifest-driven bulk push:
#     (a) DIFFERENT VALUE PER CONTAINER. secrets-manifest.yml's own entry
#         says so explicitly: ETL's value is `pfin_etl`'s own credential,
#         provider-sync's is a DIFFERENT value (`authenticator`'s
#         pre-cutover, `pfin_provider_sync`'s own post-cutover). One
#         manifest NAME, at least two real VALUES -- a bulk push keyed by
#         name-from-manifest has no way to hold two values under one key,
#         and inventing two new local .env names (e.g.
#         PFIN_DB_PASSWORD_ETL / _PROVIDER_SYNC) not in the manifest or
#         either .env.example would be introducing a naming convention
#         unilaterally, exactly the kind of call this file defers to
#         Sec/F/CTO rather than deciding alone.
#     (b) WRONG TIME. Per runbook §6.1/§6.2, this value doesn't EXIST until
#         the operator runs the `\password` role handoff AFTER migrations
#         apply (§6) -- which is itself deliberately interactive and
#         deliberately never scripted (a piped/scripted password reaches
#         shell history or a server log; see runbook §6.1's own PROHIBITED
#         single-statement warning). A secrets-push script that ran before
#         §6 would have nothing to read; one that ran after would be
#         reaching into a step whose whole design point is staying manual.
#   Resolution: PFIN_DB_PASSWORD stays exactly where it already lives --
#   runbook §6.1/§6.2's interactive handoff. This script SKIPS it with a
#   printed reason every run, never silently.
#
# KNOT 4 -- resource-existence ordering: RATIFIED (F/CTO) -- this runs
#   functionally AFTER §7, not before it, even though it's numbered §5 in
#   the runbook.
#   The app/etl/pdf-render/provider-sync Coolify resources are CREATED in
#   §7 -- this script can only push env vars onto a resource that already
#   exists (Coolify's envs/bulk PATCH targets an application UUID; there
#   is no "pre-create the env store for a resource that doesn't exist
#   yet"). So the runbook's §5-then-§6-then-§7 document ORDER and this
#   script's actual EXECUTION order diverge: conceptually this is a
#   post-§7 (or interleaved-with-§7, run once per resource right after
#   it's created) step, not a pre-§6 one. That is a documentation-order
#   vs. execution-order mismatch worth ratifying explicitly, not a
#   functional bug -- flagged for F/CTO/Sec rather than silently
#   resequencing the runbook's own section numbers in this PR.
#   Mechanically: this script NEVER assumes a resource exists. It resolves
#   each target resource's UUID by NAME via the Coolify API (same
#   by-name-lookup idiom provision-supabase-stack.sh already uses for its
#   own application) and FAILS CLOSED, naming the missing resource, if the
#   lookup comes back empty -- never silently skips a secret because its
#   resource isn't there yet. `--skip-missing-resource` is available for a
#   deliberate partial run (e.g. pushing app-tier secrets before the
#   worker resources exist) and prints, per skipped resource, exactly
#   which secrets were NOT pushed and why -- an operator opts into that
#   gap by name, never falls into it by a swallowed error. Sec condition
#   (non-blocking, addressed here): a partial run must be MACHINE-
#   distinguishable from a complete one, not just human-readable in the
#   log -- this script exits 3 (not 0) whenever --skip-missing-resource
#   actually skipped something, in both preflight and --apply. See
#   EXIT CODES in --help / the usage() function below.
#
# KNOT 5 -- WORKER_ADMISSION_SHARED_SECRET: NOT a Coolify "shared
#   variable" via this script, and here's why.
#   secrets-manifest.yml's own text says this should be "a Coolify
#   project-scoped SHARED var (one rotation edit point) referenced by
#   both services." Checked against Coolify's own docs before assuming
#   that's scriptable (coolify.io/docs/knowledge-base/environment-variables;
#   deepwiki.com/coollabsio/coolify/4.6-shared-variables-and-configuration,
#   both read 2026-09-11 while authoring this script): Coolify DOES have a
#   `SharedEnvironmentVariable` model at Team/Project/Environment/Server
#   scope, referenced from a resource's own env via a `{{scope.NAME}}`
#   template -- but creating or bulk-setting one is a Livewire (dashboard
#   UI) flow; NEITHER doc source turned up a REST API v1 endpoint for it,
#   only the per-application `/applications/{uuid}/envs` /
#   `/envs/bulk` endpoints this script (and provision-supabase-stack.sh)
#   already use. Assuming an unverified endpoint exists and silently
#   falling back would be exactly the kind of unstated design call this
#   header is supposed to surface instead.
#   RESOLUTION -- RATIFIED (F/CTO + Sec, PR #738; a deviation from the
#   manifest's literal text, decided explicitly rather than assumed):
#   push the SAME literal value as an ordinary per-application env var to
#   BOTH `app` and `provider-sync` in the same script run, generated or
#   read from .env exactly like every other secret here. This achieves the
#   manifest's actual REQUIREMENT (identical value on both tiers,
#   verifiable, one script invocation updates both) without depending on
#   an API surface that may not exist. What it does NOT achieve is the
#   manifest's stated MECHANISM (a single dashboard edit point) -- rotation
#   here means re-running this script (which already batches both
#   resources in one invocation), not editing one shared-variable row.
#   ⚠ ROTATION DISCIPLINE (Sec condition): the two stores are rotated
#   ONLY together, via one invocation of this script -- never hand-edit
#   one Coolify resource's copy without the other. If they ever drift
#   (a value changed on one side only, outside this script), the failure
#   mode is FAIL-CLOSED, never a bypass: provider-sync's constant-time
#   compare against `app`'s relayed value mismatches and admission is
#   DENIED, not granted on a stale/wrong secret. Drift degrades to an
#   outage, not an exposure -- same shape as every other fail-closed
#   control in this stack.
#   If F/CTO/Sec still want the literal Coolify SharedEnvironmentVariable
#   for its own sake, that stays a one-time manual UI step this script
#   does not perform; the two are not mutually exclusive, but this script
#   does not depend on the UI step having happened.
#
# KNOT 6 -- PUBLIC_SUPABASE_URL / PUBLIC_SUPABASE_ANON_KEY: deliberately
#   NOT pushed by this script.
#   Both are boot-required on `app` (runbook §5) but are NON-SECRET by
#   design (RLS + the ADR-029 aal2 backstop are the controls, not
#   confidentiality) and are therefore, correctly, ABSENT from
#   secrets-manifest.yml -- this script is keyed off the manifest (KNOT 1),
#   so they are structurally outside its charter, not an oversight.
#   They also don't have an operator-.env source the way every secret here
#   does: their real values are BOX STATE (the stack's own gateway URL and
#   the real ANON_KEY mint-supabase-jwt-keys.sh already minted on the box),
#   not something an operator types into a local file. Setting them
#   correctly is a small, DIFFERENT mechanism (read two values already
#   known on the box, push as plain non-secret env to `app`) that could
#   slot in as its own later step once `app` exists -- flagged as a
#   natural follow-up, not built here, so this script's manifest-driven
#   contract stays honest about what it covers.
#
# IDEMPOTENCE
#   Unconditional overwrite when a name has a non-empty local .env value,
#   not mint-if-absent -- these are OPERATOR-CHOSEN credentials (Plaid/
#   SimpleFIN/FMP/BLS keys, the admin service-role key), not box-generated
#   ones, so "the operator's .env is authoritative" is the correct model,
#   matching provision-supabase-stack.sh's own SMTP_PASS override
#   (unconditional overwrite, not mint-if-absent -- see that script's own
#   comment on why). Re-running with the same .env is a no-op in effect
#   (same value pushed again); re-running after editing .env re-pushes the
#   new value. A name ABSENT or EMPTY in .env is skipped with a printed
#   reason, never pushed as an empty string.
#
# ⚠ A REDEPLOY IS STILL REQUIRED. Same caveat mint-supabase-jwt-keys.sh's
#   own header states for its own env overwrite: Coolify only injects the
#   env store into a container at deploy (container-recreate) time --
#   `docker restart` does not re-read it. This script does NOT trigger a
#   redeploy of any resource it touches (unlike mint-supabase-jwt-keys.sh,
#   which owns exactly one resource and can safely auto-redeploy it; this
#   script touches up to four resources whose redeploy ordering/readiness
#   is a §7 concern, not this script's to decide). It prints which
#   resources received new values and that each needs a Coolify redeploy
#   (UI Deploy button, or `POST /deploy?uuid=<uuid>`) to take effect.
#
# USAGE
#   BOX_IP=<box-ip> scripts/push-production-secrets.sh
#     preflight: reads the manifest, .env, and each target resource's
#     existence; prints the plan (names + resource groupings only). Nothing
#     mutated.
#   BOX_IP=<box-ip> scripts/push-production-secrets.sh --apply
#     pushes the plan for real.
#   --skip-missing-resource
#     a resource that doesn't exist yet is skipped (named, with its
#     secrets listed) instead of aborting the whole run. Default: abort,
#     naming the missing resource (KNOT 4).
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"

# Resource names -- overridable, matching runbook §3's topology table.
APP_RESOURCE_NAME="${APP_RESOURCE_NAME:-app}"
ETL_RESOURCE_NAME="${ETL_RESOURCE_NAME:-etl}"
PDF_RESOURCE_NAME="${PDF_RESOURCE_NAME:-pdf-render}"
PROVIDER_SYNC_RESOURCE_NAME="${PROVIDER_SYNC_RESOURCE_NAME:-provider-sync}"

APPLY=0
SKIP_MISSING=0
usage() {
  cat <<'USAGE'
usage: BOX_IP=<box-ip> scripts/push-production-secrets.sh [--apply] [--skip-missing-resource]

Bulk-pushes the app/worker production_only secrets (secrets-manifest.yml,
minus the Supabase-stack names already handled by provision-supabase-stack.sh
/ mint-supabase-jwt-keys.sh, minus PFIN_DB_PASSWORD which stays at runbook
§6.1/§6.2) from the operator's local .env into their Coolify resources.

Default: preflight -- reads the manifest/.env/resource-existence and prints
the plan (names + resource groupings only). Nothing pushed.
--apply: pushes the plan for real.
--skip-missing-resource: a target resource that doesn't exist yet is named
  and skipped instead of aborting the whole run. Default: abort, naming it.

EXIT CODES
  0  clean run, nothing skipped (preflight or --apply)
  1  a real failure (missing BOX_IP/.env, unreachable box, a resource
     missing without --skip-missing-resource, a Coolify API error, ...)
  2  the push PLAN itself is invalid (a manifest name has no
     SECRET_RESOURCE_MAP entry, or the manifest is malformed/missing)
  3  --skip-missing-resource was given AND it actually skipped one or
     more resources this run -- a PARTIAL run, distinct from a clean
     complete one (0) or an error (1/2) so a caller can tell them apart
     without parsing output. Applies to both preflight and --apply.

See this script's own header comment for the full design-knot reasoning
(what's excluded and why, the WORKER_ADMISSION_SHARED_SECRET deviation,
etc.) -- this is Sec-joint-review territory (runbook §5), not a plain loop.
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --apply)                 APPLY=1 ;;
    --skip-missing-resource) SKIP_MISSING=1 ;;
    -h|--help)                usage; exit 0 ;;
    *) echo "unknown flag: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

[[ -n "$BOX_IP" ]] || die "BOX_IP is required, not defaulted -- same discipline as provision-supabase-stack.sh/mint-supabase-jwt-keys.sh after the 2026-09-11 incident. Set it explicitly."
[[ -f "$REPO_ROOT/.env" ]] || die "no .env at $REPO_ROOT -- this script reads the production secret VALUES from there (names come from secrets-manifest.yml)."

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }
sshx_in() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" bash -s; }

sshx true >/dev/null 2>&1 || die "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

step "Reading production_only names from secrets-manifest.yml, building the push plan"
# LOCAL ONLY, no SSH: parses the manifest (KNOT 1), applies the exclusion
# sets (KNOT 2/3), maps the remainder to resources, and reads VALUES from
# the local .env -- but does not print or return any value, only names and
# per-resource groupings. Writes the actual key/value pairs, per resource,
# to mode-600 local temp files for the push step below to pipe over SSH;
# nothing here reaches this script's own stdout/stderr as a value.
PLAN_DIR="$(mktemp -d)"
chmod 700 "$PLAN_DIR"
trap 'rm -rf "$PLAN_DIR"' EXIT
PLAN_JSON_FILE="$PLAN_DIR/plan.json"

# Output redirected STRAIGHT TO A FILE, not captured via `VAR="$(... <<EOF
# ... EOF)"`. Measured while validating this script: this specific bash
# (macOS system /bin/bash, 3.2.57) mis-parses a heredoc that is nested
# INSIDE a `$( ... )` command substitution whenever the heredoc's own body
# contains certain paren/quote patterns -- `bash -n` reports a phantom
# "unexpected EOF while looking for matching" error for a quote/paren that
# IS balanced, because it's tracking nesting depth through the heredoc body
# text instead of treating it as opaque (a known class of bash parser
# quirk with heredoc-in-command-substitution, not specific to this
# script's content). A heredoc that is NOT inside a `$( )` -- a plain
# statement with its stdout redirected to a file -- does not trigger it.
# Fixed at the mechanism (don't nest it) rather than by hunting for
# whichever character combination trips this build's parser.
if ! python3 - "$REPO_ROOT/secrets-manifest.yml" "$REPO_ROOT/.env" "$PLAN_DIR" \
  "$APP_RESOURCE_NAME" "$ETL_RESOURCE_NAME" "$PDF_RESOURCE_NAME" "$PROVIDER_SYNC_RESOURCE_NAME" \
  > "$PLAN_JSON_FILE" <<'PYEOF'
import sys, os

try:
    import yaml
except ImportError:
    print("FATAL: PyYAML not available; cannot parse secrets-manifest. "
          "Install with `pip install pyyaml`. Failing closed.", file=sys.stderr)
    sys.exit(2)

manifest_path, env_path, plan_dir, app_name, etl_name, pdf_name, ps_name = sys.argv[1:8]

with open(manifest_path) as f:
    manifest = yaml.safe_load(f)
production_only = manifest.get("production_only")
if not isinstance(production_only, list) or not production_only:
    print("FATAL: secrets-manifest.yml production_only is missing/empty/malformed.", file=sys.stderr)
    sys.exit(2)
manifest_names = set(production_only)

# KNOT 2 -- already fully handled by provision-supabase-stack.sh (mint-if-
# absent + its own SMTP_PASS operator-override path) and, for the JWT
# pair, mint-supabase-jwt-keys.sh. Cross-checked against that script's own
# MINT_SECRETS dict (POSTGRES_PASSWORD/JWT_SECRET/SECRET_KEY_BASE/
# VAULT_ENC_KEY/SERVICE_ROLE_KEY/ANON_KEY/DASHBOARD_PASSWORD/
# PG_META_CRYPTO_KEY) plus its separate SMTP_PASS block -- 9 names, not
# copied from runbook prose alone.
EXCLUDED_SUPABASE_STACK = {
    "POSTGRES_PASSWORD", "JWT_SECRET", "SECRET_KEY_BASE", "VAULT_ENC_KEY",
    "SERVICE_ROLE_KEY", "ANON_KEY", "DASHBOARD_PASSWORD", "PG_META_CRYPTO_KEY",
    "SMTP_PASS",
}
# KNOT 3 -- different value per container, generated after migrations at
# the interactive §6.1/§6.2 role handoff. Never pushed by this script.
EXCLUDED_DEFERRED = {"PFIN_DB_PASSWORD"}

excluded = EXCLUDED_SUPABASE_STACK | EXCLUDED_DEFERRED
in_scope = sorted(manifest_names - excluded)
unexpected_excluded_absent = sorted((excluded) - manifest_names)
if unexpected_excluded_absent:
    # The manifest changed under this script's exclusion list -- surface
    # it rather than silently no-op the mismatch. Not fatal (a retired
    # name is plausible), but must be seen.
    print(f"WARN: excluded name(s) not found in current manifest -- verify KNOT 2/3 lists are still current: {unexpected_excluded_absent}", file=sys.stderr)

# KNOT 2 -- per-resource mapping. Cross-checked against each target's own
# .env.example (root .env.example for `app`; workers/pdf-render/.env.example;
# workers/etl/.env.example; workers/provider-sync/.env.example).
SECRET_RESOURCE_MAP = {
    "SUPABASE_SERVICE_ROLE_KEY":       [app_name],
    "PDF_WORKER_SIGNING_KEY":          [app_name, pdf_name],
    "DISCORD_WEBHOOK_URL":             [app_name, etl_name, ps_name],
    # KNOT 5 -- pushed identically to both tiers directly; NOT a Coolify
    # SharedEnvironmentVariable via this script. See header.
    "WORKER_ADMISSION_SHARED_SECRET":  [app_name, ps_name],
    "FMP_API_KEY":                     [etl_name],
    "BLS_API_KEY":                     [etl_name],
    "PLAID_CLIENT_ID":                 [ps_name],
    "PLAID_SECRET":                    [ps_name],
    "SIMPLEFIN_TOKEN":                 [ps_name],
}

unmapped = sorted(set(in_scope) - set(SECRET_RESOURCE_MAP))
if unmapped:
    print(f"FATAL: secrets-manifest.yml has production_only name(s) with no entry in "
          f"SECRET_RESOURCE_MAP -- a new secret was added to the manifest since this "
          f"script's mapping table was last updated. Update SECRET_RESOURCE_MAP (with "
          f"Sec joint-review, per this file's own header) before pushing: {unmapped}",
          file=sys.stderr)
    sys.exit(2)

def read_env_var(path, name):
    if not os.path.exists(path):
        return ""
    with open(path) as f:
        for line in f:
            if line.startswith(name + "="):
                return line.rstrip("\n").split("=", 1)[1].strip().strip('"').strip("'")
    return ""

by_resource = {}
missing_values = []
for name in in_scope:
    value = read_env_var(env_path, name)
    if not value:
        missing_values.append(name)
        continue
    for resource in SECRET_RESOURCE_MAP[name]:
        by_resource.setdefault(resource, {})[name] = value

report = {"in_scope": in_scope, "excluded_supabase_stack": sorted(EXCLUDED_SUPABASE_STACK),
          "excluded_deferred": sorted(EXCLUDED_DEFERRED), "missing_values": missing_values,
          "resources": {}}
for resource, kv in by_resource.items():
    seed_path = os.path.join(plan_dir, resource.replace("/", "_") + ".env")
    with open(seed_path, "w", opener=lambda p, f: os.open(p, f, 0o600)) as f:
        for k, v in kv.items():
            f.write(f"{k}={v}\n")
    report["resources"][resource] = {"names": sorted(kv.keys()), "seed_path": seed_path}

import json
print(json.dumps(report))
PYEOF
then
  die "building the push plan failed (see stderr above)"
fi

# Names-only extraction for display -- python again, reading the plan back
# from its file (never re-embedding JSON as an argv string or a $(...)
# capture -- see the PLAN_JSON_FILE comment above for why). This pass only
# ever touches the JSON structure (names, paths), never a secret value.
python3 - "$PLAN_JSON_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    r = json.load(f)
print(f"      in-scope (manifest, minus exclusions): {r['in_scope']}")
print(f"      excluded (Supabase-stack, already handled by provision-supabase-stack.sh/mint-supabase-jwt-keys.sh): {r['excluded_supabase_stack']}")
print(f"      excluded (deferred to runbook §6.1/§6.2 -- different value per container, generated after migrations): {r['excluded_deferred']}")
if r["missing_values"]:
    print(f"      MISSING from local .env (skipped, not pushed as empty): {r['missing_values']}")
for resource, info in sorted(r["resources"].items()):
    print(f"      -> {resource}: {info['names']}")
PYEOF

step "Resolving target resources on Coolify (by name; fails closed on a missing one unless --skip-missing-resource)"
# Same by-name-lookup idiom provision-supabase-stack.sh already uses for
# its own application -- run ON THE BOX (Coolify's API is loopback-only;
# :8000 is deliberately not in the firewall, per runbook §1).
api() { # api <METHOD> <PATH> [json-body]
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    sshx "TOKEN=\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-); curl -fsS -X $method -H \"Authorization: Bearer \$TOKEN\" -H 'Content-Type: application/json' -d '$body' http://localhost:8000/api/v1$path"
  else
    sshx "TOKEN=\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-); curl -fsS -X $method -H \"Authorization: Bearer \$TOKEN\" http://localhost:8000/api/v1$path"
  fi
}
jqp() { python3 -c "import json,sys;$1"; }

RESOURCE_NAMES="$(python3 -c "import json,sys
with open(sys.argv[1]) as f: r = json.load(f)
print(' '.join(sorted(r['resources'])))" "$PLAN_JSON_FILE")"

# "resource|uuid" pairs, one per resolved resource, in a plain INDEXED
# array. Deliberately NOT a bash associative array (`declare -A`, bash 4+
# only -- macOS still ships bash 3.2 by default, measured on this box:
# /bin/bash is 3.2.57), and deliberately NOT a `while read ... < file`
# loop for the push step below either -- `ssh`/`sshx` inside that loop's
# body would consume the loop's own stdin out from under `read`, silently
# truncating it to one iteration (a well-known shell pitfall, not
# hypothetical). Plain `for pair in "${arr[@]}"` sidesteps both problems on
# any bash this repo's other scripts already assume.
RESOLVED_PAIRS=()
# Tracks whether --skip-missing-resource actually skipped anything this
# run (Sec condition): a partial push must be machine-distinguishable
# from a complete one, not just human-readable in the log. Drives the
# exit-3 branches below.
ANY_SKIPPED=0

for resource in $RESOURCE_NAMES; do
  found="$(api GET "/applications?name=$resource" | jqp "
d=json.load(sys.stdin)
d=d if isinstance(d, list) else d.get('data', [])
print(d[0]['uuid'] if d else '')")"
  if [[ -z "$found" ]]; then
    if [[ $SKIP_MISSING -eq 1 ]]; then
      info "SKIPPING '$resource' -- no Coolify resource by that name yet (--skip-missing-resource given). Its secrets are NOT pushed this run."
      ANY_SKIPPED=1
      continue
    fi
    die "no Coolify resource named '$resource' -- it hasn't been created yet (runbook §7). Either create it first, or pass --skip-missing-resource to push to the resources that DO exist and skip this one explicitly (never silently)."
  fi
  RESOLVED_PAIRS+=("$resource|$found")
  ok "resolved '$resource' -> $found"
done

if [[ $APPLY -eq 0 ]]; then
  printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing was pushed. Re-run with --apply to execute.\n'
  if [[ $ANY_SKIPPED -eq 1 ]]; then
    info "exiting 3 -- this preflight would be a PARTIAL run (one or more resources skipped); see EXIT CODES in --help."
    exit 3
  fi
  exit 0
fi

step "Pushing secrets -- one resource at a time, seed file over SSH stdin, never an argv/env value"
PUSHED_RESOURCES=()
PUSHED_UUIDS=()
# ${arr[@]+"${arr[@]}"}, not a bare "${arr[@]}": under `set -u`, expanding
# an EMPTY array with the plain form is treated as an unset parameter and
# aborts on bash < 4.4 (macOS ships 3.2) -- same fix as scripts/standup.sh
# needed for its own empty-array case, applied here preemptively.
for pair in ${RESOLVED_PAIRS[@]+"${RESOLVED_PAIRS[@]}"}; do
  resource="${pair%%|*}"
  uuid="${pair#*|}"
  seed_path="$(python3 -c "import json,sys
with open(sys.argv[1]) as f: r = json.load(f)
print(r['resources']['$resource']['seed_path'])" "$PLAN_JSON_FILE")"
  box_seed="/root/.pfin/_secrets_seed_${resource//\//_}.env.$$"

  # Cross the local->box boundary exactly like provision-supabase-stack.sh's
  # SMTP_PASS override: piped over SSH stdin into a file on the box, never
  # a command-line arg on either side.
  sshx "umask 077; mkdir -p /root/.pfin; cat > $box_seed" < "$seed_path"

  sshx_in <<REMOTE
set -e
umask 077
trap 'shred -u "$box_seed" 2>/dev/null || rm -f "$box_seed"' EXIT
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "$uuid" "$box_seed" <<'PYEOF'
import json, subprocess, sys

token, app_uuid, seed_file = sys.argv[1], sys.argv[2], sys.argv[3]

def die(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)

# Identical hardened api() shape to provision-supabase-stack.sh's own
# 2026-09-11 fix (#734/#735 sibling): token via curl -K stdin config, never
# an argv element -- so it cannot appear in ps, and cannot leak through an
# unhandled CalledProcessError's default str(argv) representation either.
def api(method, path, body=None):
    if '"' in token or "\n" in token:
        die("Coolify API token contains an unexpected character -- refusing to build a curl config for it")
    config = 'header = "Authorization: Bearer ' + token + '"\n'
    cmd = ["curl", "-fsS", "-K", "-", "-X", method]
    if body is not None:
        cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(body)]
    cmd += [f"http://localhost:8000/api/v1{path}"]
    try:
        result = subprocess.run(cmd, input=config, capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as exc:
        die(f"Coolify API {method} {path} failed: exit {exc.returncode} ({exc.stderr.strip()[:200]})")
    return json.loads(result.stdout) if result.stdout.strip() else None

with open(seed_file) as f:
    kv = dict(line.rstrip("\n").split("=", 1) for line in f if "=" in line)

data = [{"key": k, "value": v} for k, v in kv.items()]
api("PATCH", f"/applications/{app_uuid}/envs/bulk", {"data": data})
print(f"PUSHED: {sorted(kv.keys())}")
PYEOF
REMOTE
  ok "pushed to '$resource' ($uuid)"
  PUSHED_RESOURCES+=("$resource")
  PUSHED_UUIDS+=("$uuid")
done

step "Done -- a redeploy is still required"
info "Coolify only injects the env store into a container at deploy (container-recreate) time -- see this script's own header. Redeploy each resource that received new values:"
i=0
for resource in ${PUSHED_RESOURCES[@]+"${PUSHED_RESOURCES[@]}"}; do
  info "  - $resource (${PUSHED_UUIDS[$i]}): Coolify UI Deploy button, or POST /deploy?uuid=${PUSHED_UUIDS[$i]}"
  i=$((i + 1))
done
if [[ $ANY_SKIPPED -eq 1 ]]; then
  ok "push-production-secrets.sh --apply complete -- PARTIAL (one or more resources skipped; exiting 3, see EXIT CODES in --help)"
  exit 3
fi
ok "push-production-secrets.sh --apply complete"
exit 0
