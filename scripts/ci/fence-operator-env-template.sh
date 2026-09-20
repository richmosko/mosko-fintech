#!/usr/bin/env bash
#
# fence-operator-env-template.sh -- asserts scripts/provision.env.example
# is the COMPLETE operator-side .env contract: every name any script under
# scripts/*.sh actually reads from the operator's local `$REPO_ROOT/.env`
# must appear in that file (commented or not). BACKLOG.md §7.36 item 68,
# W-2 rider (F/CTO asked "is the .env.example template up to date?";
# measured answer was NO -- the template was missing the entire
# push-production-secrets.sh-read production_only secret set). DevOps-owned.
#
# ┌─ WHAT THIS FENCE DERIVES, LIVE, EVERY RUN (never a hand-maintained list
# │  duplicated here) ───────────────────────────────────────────────────────┐
# │ SOURCE 1 -- literal call-site names via the read_env_var()/env_or_dotenv()
# │   helper idiom: `grep -ohE '\b(read_env_var|env_or_dotenv)[[:space:]]+
# │   [A-Z][A-Z0-9_]*' scripts/*.sh`, second field of each match.
# │ SOURCE 2 -- literal names via the DIRECT `grep -m1 '^NAME='
# │   "$REPO_ROOT/.env"` idiom (not routed through a helper function) --
# │   matched by the same shape, filtered to lines that actually target
# │   `$REPO_ROOT/.env` (excludes the on-BOX `/root/.pfin/*.env` reads and
# │   the log-file reads that use the identical grep SHAPE against a
# │   different file -- both real, both intentionally out of THIS file's
# │   scope, since neither is the operator-side local-.env contract).
# │ SOURCE 3 -- secrets-manifest.yml's own `production_only:` names, MINUS
# │   the `EXCLUDED_SUPABASE_STACK` / `EXCLUDED_DEFERRED` python set
# │   literals scripts/push-production-secrets.sh itself declares (that
# │   script reads every NAME in the remainder from THIS SAME local .env,
# │   dynamically -- not one literal grep per name, so it cannot be found
# │   by source 1 or 2's own pattern; this is a SEPARATE derivation, unioned
# │   in, not merely "another instance of the same grep").
# └───────────────────────────────────────────────────────────────────────────┘
#
# The union of sources 1-3 is the REQUIRED set. Every name in it must appear
# in scripts/provision.env.example as a literal `NAME=` line (commented or
# not -- a `# NAME=<placeholder>` line still counts, matched the same way).
# A name present in the template but NOT in the required set is NOT an
# error (over-documenting forward-looking / recorded-but-not-yet-read names,
# e.g. ETL_UUID before any script reads it back, is fine and expected).
#
# Usage:
#   bash fence-operator-env-template.sh [repo-root]
#
# Exit codes:
#   0 -- every required name is present in the template.
#   1 -- one or more required names are missing (fail-closed).
#   2 -- structural error (manifest/template/scripts dir not found, or the
#        EXCLUDED_* set literals could not be located -- cannot confirm the
#        derivation, must not emit a false pass).

set -euo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SCRIPTS_DIR="$REPO_ROOT/scripts"
MANIFEST="$REPO_ROOT/secrets-manifest.yml"
TEMPLATE="$REPO_ROOT/scripts/provision.env.example"
PUSH_SECRETS_SH="$REPO_ROOT/scripts/push-production-secrets.sh"

[[ -d "$SCRIPTS_DIR" ]] || { echo "FATAL: $SCRIPTS_DIR not found." >&2; exit 2; }
[[ -f "$MANIFEST" ]] || { echo "FATAL: $MANIFEST not found." >&2; exit 2; }
[[ -f "$TEMPLATE" ]] || { echo "FATAL: $TEMPLATE not found." >&2; exit 2; }
[[ -f "$PUSH_SECRETS_SH" ]] || { echo "FATAL: $PUSH_SECRETS_SH not found." >&2; exit 2; }

# --- Source 1: read_env_var()/env_or_dotenv() call-site names --------------
SOURCE1="$(grep -ohE '\b(read_env_var|env_or_dotenv)[[:space:]]+[A-Z][A-Z0-9_]*' "$SCRIPTS_DIR"/*.sh 2>/dev/null \
  | awk '{print $2}' | sort -u)"

# --- Source 2: direct `grep -m1 '^NAME=' "$REPO_ROOT/.env"` idiom ----------
# Restricted to lines whose grep target is $REPO_ROOT/.env (single- or
# double-quoted) -- NOT /root/.pfin/*.env (on-box files) and NOT any other
# path (e.g. a staged-log-file read using the identical grep SHAPE).
SOURCE2="$(grep -hoE "grep -m1 '\\^[A-Z_]+=' \"?\\\$REPO_ROOT/\\.env\"?" "$SCRIPTS_DIR"/*.sh 2>/dev/null \
  | grep -oE "\\^[A-Z_]+=" | tr -d '^=' | sort -u)"

# --- Source 3: secrets-manifest.yml production_only names, minus
#     push-production-secrets.sh's own EXCLUDED_* python set literals ------
MANIFEST_NAMES="$(python3 -c "
import re, sys
text = open('$MANIFEST').read()
m = re.search(r'^production_only:\s*\n(.*?)(?=^\S|\Z)', text, re.S | re.M)
if not m:
    print('FATAL: could not locate a production_only: block in $MANIFEST', file=sys.stderr)
    sys.exit(2)
block = m.group(1)
for line in block.splitlines():
    lm = re.match(r'\s*-\s*([A-Z][A-Z0-9_]*)', line)
    if lm:
        print(lm.group(1))
")" || { echo "FATAL: could not parse production_only names out of $MANIFEST -- cannot confirm the derivation; failing closed." >&2; exit 2; }
[[ -n "$MANIFEST_NAMES" ]] || { echo "FATAL: parsed zero production_only names out of $MANIFEST -- the manifest's shape may have changed; failing closed." >&2; exit 2; }

EXCLUDED_NAMES="$(python3 -c "
import re, sys
text = open('$PUSH_SECRETS_SH').read()
names = set()
for var in ('EXCLUDED_SUPABASE_STACK', 'EXCLUDED_DEFERRED'):
    m = re.search(var + r'\s*=\s*\{([^}]*)\}', text, re.S)
    if not m:
        print(f'FATAL: could not locate {var} = {{...}} in $PUSH_SECRETS_SH', file=sys.stderr)
        sys.exit(2)
    for lit in re.findall(r'\"([A-Z][A-Z0-9_]*)\"', m.group(1)):
        names.add(lit)
for n in sorted(names):
    print(n)
")" || { echo "FATAL: could not parse EXCLUDED_SUPABASE_STACK/EXCLUDED_DEFERRED out of $PUSH_SECRETS_SH -- cannot confirm the derivation; failing closed." >&2; exit 2; }

SOURCE3="$(comm -23 <(echo "$MANIFEST_NAMES" | sort -u) <(echo "$EXCLUDED_NAMES" | sort -u))"

REQUIRED="$(printf '%s\n%s\n%s\n' "$SOURCE1" "$SOURCE2" "$SOURCE3" | grep -v '^$' | sort -u)"

MISSING=""
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  if ! grep -qE "^${name}=" "$TEMPLATE"; then
    MISSING="${MISSING}${name}"$'\n'
  fi
done <<< "$REQUIRED"

if [[ -n "$MISSING" ]]; then
  echo "FAILED: scripts/provision.env.example is missing the following name(s) a script actually reads from the operator's local .env:" >&2
  printf '%s' "$MISSING" | sed 's/^/  /' >&2
  echo "" >&2
  echo "Add each as a '<NAME>=<placeholder>' line (or a commented one) to $TEMPLATE." >&2
  exit 1
fi

echo "OK: scripts/provision.env.example carries every name derived from sources 1-3 ($(echo "$REQUIRED" | grep -c .) names)."
exit 0
