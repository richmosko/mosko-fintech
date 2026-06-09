#!/usr/bin/env bash
#
# RT-26 — SUPABASE_SERVICE_ROLE_KEY allowlist CI grep fence (γ-hybrid shape)
#
# Lock anchors:
#   - ADR-011 Decision 4 (second catalogued §10 instance; HIGH + V1-SHIP-BLOCK)
#   - ADR-015 Decision 1 (5 SvelteKit globs — frame the audit-scope structure)
#   - ADR-016 Decision 1 (3 V1 surfaces — the allowlist registry)
#   - SECURITY §4.2 axis vi + ARCH §4.1 + ARCH §6 Security scan stage (i)
#   - ARCH §6 Phase 5 detail item (c)
#
# γ-hybrid design (per F/CTO ratify 2026-06-08):
#   - Audit scope (what the fence SCANS) = src/** + repo-root config files.
#   - Allowlist registry (what's PERMITTED within audit scope) = ADR-016 D1 file paths.
#   - The 5 SvelteKit globs from ADR-015 D1 frame the audit-scope structure
#     (describe SvelteKit server-source surfaces) but are NOT themselves the allowlist.
#
# Catch behavior:
#   1. grep -rEln 'SUPABASE_SERVICE_ROLE_KEY' over <audit-scope>.
#   2. For each hit, extract repo-root-relative file path.
#   3. If hit path matches any allowlist registry entry (exact string match) → permitted.
#   4. Else → trip (non-zero exit; fence fails closed).
#
# Allowlist shape: exact-file-path-shaped, NOT glob-shaped. Adding a 4th entry
# requires ADR-016 amendment + Sec-consult per ADR-016 D2 (webhook-allowlist
# annotation convention). Glob-shape would silently admit new files matching
# the pattern; exact-path enforces ADR amendment by-construction.
#
# Usage:
#   bash fence-rt26-service-role-allowlist.sh <audit-scope-path> <allowlist-registry-path>
#
#   <audit-scope-path>           File or directory to scan (e.g., src/ or tests/fixtures/ci/rt26-violation/).
#   <allowlist-registry-path>    Path to the registry file (e.g., scripts/ci/rt26-allowlist.txt).
#
# Exit codes:
#   0   — audit scope clean (zero hits OR all hits at allowlisted paths).
#   1   — one or more hits outside allowlist (fail-closed).
#   2   — argument / environment error.
#

set -euo pipefail

SCOPE="${1:-}"
ALLOWLIST="${2:-}"
if [ -z "$SCOPE" ] || [ -z "$ALLOWLIST" ]; then
  echo "FATAL: missing args." >&2
  echo "Usage: bash $(basename "$0") <audit-scope-path> <allowlist-registry-path>" >&2
  exit 2
fi
if [ ! -e "$SCOPE" ]; then
  echo "FATAL: audit scope path not found: $SCOPE" >&2
  exit 2
fi
if [ ! -f "$ALLOWLIST" ]; then
  echo "FATAL: allowlist registry not found: $ALLOWLIST" >&2
  exit 2
fi

# Load allowlist into a newline-separated string (skip blanks + # comments + trim whitespace).
ALLOWED_PATHS=$(grep -vE '^[[:space:]]*$|^[[:space:]]*#' "$ALLOWLIST" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Find all hits within audit scope. (|| true so empty result doesn't trip set -e.)
HITS=$(grep -rEln 'SUPABASE_SERVICE_ROLE_KEY' "$SCOPE" 2>/dev/null || true)

VIOLATIONS=0
if [ -n "$HITS" ]; then
  while IFS= read -r hit; do
    # Normalize: strip leading ./ if present.
    norm_hit=$(echo "$hit" | sed 's|^\./||')
    permitted=0
    if [ -n "$ALLOWED_PATHS" ]; then
      while IFS= read -r allow; do
        [ -z "$allow" ] && continue
        if [ "$norm_hit" = "$allow" ]; then
          permitted=1
          break
        fi
      done <<< "$ALLOWED_PATHS"
    fi
    if [ "$permitted" -eq 0 ]; then
      echo "VIOLATION: SUPABASE_SERVICE_ROLE_KEY referenced outside allowlist." >&2
      echo "  File: $hit" >&2
      grep -n 'SUPABASE_SERVICE_ROLE_KEY' "$hit" 2>/dev/null | sed 's/^/    /' >&2 || true
      VIOLATIONS=$((VIOLATIONS+1))
    fi
  done <<< "$HITS"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "RT-26 fence: $VIOLATIONS violation(s) found in scope: $SCOPE. Failing closed." >&2
  echo "" >&2
  echo "Permitted allowlist entries (per ADR-016 D1 + $ALLOWLIST):" >&2
  if [ -n "$ALLOWED_PATHS" ]; then
    echo "$ALLOWED_PATHS" | sed 's/^/  /' >&2
  else
    echo "  (none — empty allowlist registry)" >&2
  fi
  echo "" >&2
  echo "Adding a new allowlist entry REQUIRES Sec-consult + ADR-016 amendment per ADR-016 D2." >&2
  exit 1
fi

echo "RT-26 fence: scope $SCOPE clean (all SUPABASE_SERVICE_ROLE_KEY refs within allowlist, if any)."
exit 0
