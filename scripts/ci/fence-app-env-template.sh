#!/usr/bin/env bash
#
# fence-app-env-template.sh -- asserts api/.env.example carries EXACTLY the
# set of names api/docker-compose.yaml's `app` service `environment:` block
# declares -- BIDIRECTIONAL equality, not a one-way "at least" check.
# BACKLOG.md §7.36 item 68 (F/CTO ruling 2026-09-20: retire the repo-root
# `.env.example`; api/.env.example becomes the single app-surface contract).
# DevOps-owned.
#
# WHY BIDIRECTIONAL, NOT ONE-WAY. A name in docker-compose.yaml but missing
# from api/.env.example is undocumented -- an operator reading the template
# alone would not know the app needs it. A name in api/.env.example but
# ABSENT from docker-compose.yaml is the OPPOSITE failure this repo has
# already been burned by once (BACKLOG §7.36 item 68 N-item, root
# .env.example retirement): a stale/orphaned entry the running container
# never actually receives, giving a false impression that setting it would
# do anything. Both directions are real defects; this fence catches both.
#
# WHAT THIS FENCE DERIVES, LIVE, EVERY RUN (never a hand-maintained list
# duplicated here):
#   SOURCE 1 -- every `^[A-Z][A-Z0-9_]*=` line in api/.env.example.
#   SOURCE 2 -- every `NAME:` key inside api/docker-compose.yaml's `app:`
#     service `environment:` block specifically (a positional block-scan,
#     stopping at the first line back out to the block's own indentation
#     level or shallower -- same technique coolify-env.sh's own manifest
#     parser uses, not a YAML library, since PyYAML is not guaranteed on
#     every runner this could ever execute against).
#
# Exit codes:
#   0 -- the two sets are identical.
#   1 -- the sets differ (fail-closed), naming every name on the wrong side.
#   2 -- structural error (a file is missing, or the environment: block
#        could not be located at all -- cannot confirm the derivation, must
#        not emit a false pass).

set -euo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ENV_EXAMPLE="$REPO_ROOT/api/.env.example"
COMPOSE="$REPO_ROOT/api/docker-compose.yaml"

[[ -f "$ENV_EXAMPLE" ]] || { echo "FATAL: $ENV_EXAMPLE not found." >&2; exit 2; }
[[ -f "$COMPOSE" ]] || { echo "FATAL: $COMPOSE not found." >&2; exit 2; }

# --- Source 1: api/.env.example's own declared names ------------------------
SOURCE1="$(grep -oE '^[A-Z][A-Z0-9_]*=' "$ENV_EXAMPLE" | tr -d '=' | sort -u)"
[[ -n "$SOURCE1" ]] || { echo "FATAL: parsed zero NAME= lines out of $ENV_EXAMPLE -- the file's shape may have changed; failing closed." >&2; exit 2; }

# --- Source 2: api/docker-compose.yaml's app.environment block keys --------
SOURCE2="$(python3 -c "
import re, sys

names = set()
in_block = False
base_indent = None
with open('$COMPOSE') as f:
    for line in f:
        stripped = line.rstrip('\n')
        if re.match(r'^\s*environment:\s*\$', stripped):
            in_block = True
            continue
        if in_block:
            if not stripped.strip():
                continue
            indent = len(stripped) - len(stripped.lstrip(' '))
            if base_indent is None:
                base_indent = indent
            if indent < base_indent:
                break
            m = re.match(r'^\s*([A-Z][A-Z0-9_]*):', stripped)
            if m:
                names.add(m.group(1))
if not names:
    print('FATAL: could not locate a non-empty environment: block in $COMPOSE', file=sys.stderr)
    sys.exit(2)
for n in sorted(names):
    print(n)
")" || { echo "FATAL: could not parse the app.environment block out of $COMPOSE -- cannot confirm the derivation; failing closed." >&2; exit 2; }
[[ -n "$SOURCE2" ]] || { echo "FATAL: parsed zero environment: keys out of $COMPOSE -- failing closed." >&2; exit 2; }

ONLY_IN_ENV_EXAMPLE="$(comm -23 <(echo "$SOURCE1") <(echo "$SOURCE2"))"
ONLY_IN_COMPOSE="$(comm -13 <(echo "$SOURCE1") <(echo "$SOURCE2"))"

if [[ -n "$ONLY_IN_ENV_EXAMPLE" || -n "$ONLY_IN_COMPOSE" ]]; then
  echo "FAILED: api/.env.example and api/docker-compose.yaml's app.environment block disagree on the name set." >&2
  if [[ -n "$ONLY_IN_ENV_EXAMPLE" ]]; then
    echo "  Documented in api/.env.example but NOT in docker-compose.yaml's environment: block (stale/orphaned -- the running container never receives these):" >&2
    printf '%s' "$ONLY_IN_ENV_EXAMPLE" | sed 's/^/    /' >&2
  fi
  if [[ -n "$ONLY_IN_COMPOSE" ]]; then
    echo "  Required by docker-compose.yaml's environment: block but NOT documented in api/.env.example (undocumented -- an operator reading the template would not know the app needs these):" >&2
    printf '%s' "$ONLY_IN_COMPOSE" | sed 's/^/    /' >&2
  fi
  exit 1
fi

echo "OK: api/.env.example and api/docker-compose.yaml's app.environment block name the same $(echo "$SOURCE1" | grep -c .) names."
exit 0
