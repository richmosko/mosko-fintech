#!/usr/bin/env bash
#
# RT-26 — SUPABASE_SERVICE_ROLE_KEY allowlist CI grep fence (γ-hybrid shape)
#
# Lock anchors:
#   - ADR-011 Decision 4 (second catalogued §10 instance; HIGH + V1-SHIP-BLOCK)
#   - ADR-015 Decision 1 (5 SvelteKit globs — frame the audit-scope structure)
#   - ADR-016 Decision 4 (ONE V1 surface — the allowlist registry, pruned 2026-08-10
#     from the superseded 3-route composition of Decision 1)
#   - ADR-016 Decision 3 (delegate-to-worker model; the factory is one audited key-home)
#   - SECURITY §4.2 axis vi + ARCH §4.1 + ARCH §6 Security scan stage (i)
#   - ARCH §6 Phase 5 detail item (c)
#
# γ-hybrid design (per F/CTO ratify 2026-06-08):
#   - Audit scope (what the fence SCANS) = src/** + repo-root config files.
#   - Allowlist registry (what's PERMITTED within audit scope) = ADR-016 D4 file path.
#   - The 5 SvelteKit globs from ADR-015 D1 frame the audit-scope structure
#     (describe SvelteKit server-source surfaces) but are NOT themselves the allowlist.
#
# Catch behavior:
#   1. grep -rEln 'SUPABASE_SERVICE_ROLE_KEY' over <audit-scope>.
#   2. For each hit, extract repo-root-relative file path.
#   3. If hit path matches any allowlist registry entry (exact string match) → permitted.
#   4. Else → trip (non-zero exit; fence fails closed).
#
# Allowlist shape: exact-file-path-shaped, NOT glob-shaped. ANY change to the
# composition — addition OR removal — requires ADR-016 amendment + Sec-consult per
# ADR-016 D2, whose scope D4 fixed to cover both directions. Glob-shape would
# silently admit new files matching the pattern; exact-path enforces ADR amendment
# by-construction. Per D3 the factory is one audited key-home: a new service_role
# surface REUSES supabaseAdmin() rather than earning an entry here.
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

# ---------------------------------------------------------------------------
# REGISTRY EXISTENCE VALIDATION (ADR-016 Decision 4 alternative (D), adopted
# 2026-08-10 AFTER the prune — deliberately not instead of it).
#
# WHY. Until now this fence matched grep hits against registry lines and never
# checked that a line corresponds to a real file. A stale entry was therefore
# INVISIBLE to CI and cost nothing — right up until a file appeared at that path,
# at which point the fence SILENTLY PERMITTED it. That is a standing
# pre-authorization to bypass the factory discipline ADR-016 D3 ratifies, and it is
# how the four-entry registry survived three ratified architecture changes without
# anything going red. An allowlist entry naming a path that does not exist is
# mechanically checkable, and nothing checked it.
#
# This would have surfaced that defect automatically. It is the cheapest possible
# check on the only layer that observes this class at PR-time.
#
# ⚠ EXIT 2, NOT 1, AND THAT IS LOAD-BEARING. Exit 1 means "a violation was found in
# the scanned scope" — a statement about the CODE. A stale registry is a statement
# about the REGISTRY, and the scan never ran. Collapsing them would make the
# inversion-mode CI leg (which expects a violation) unable to tell "the fence caught
# the fixture" from "the fence aborted before scanning anything" — it would report a
# broken fence as a working one. Exit 2 is already this script's argument/environment
# class; a registry that does not describe the tree belongs there.
# ---------------------------------------------------------------------------
if [ -n "$ALLOWED_PATHS" ]; then
  STALE=""
  while IFS= read -r allow; do
    [ -z "$allow" ] && continue
    if [ ! -f "$allow" ]; then
      STALE="${STALE}${allow}"$'\n'
    fi
  done <<< "$ALLOWED_PATHS"
  if [ -n "$STALE" ]; then
    echo "FATAL: allowlist registry names path(s) that do not exist:" >&2
    printf '%s' "$STALE" | sed 's/^/  /' >&2
    echo "" >&2
    echo "Each is a standing pre-authorization: nothing references the key there" >&2
    echo "TODAY, so the fence stays green — but the moment a file lands at that" >&2
    echo "path holding a raw SUPABASE_SERVICE_ROLE_KEY, this fence PERMITS it." >&2
    echo "" >&2
    echo "Fix the registry, not this check. Removing an entry REQUIRES Sec-consult" >&2
    echo "+ an ADR-016 amendment per D2 (scope fixed to cover removals by D4) —" >&2
    echo "a prune is not editorial. Registry: $ALLOWLIST" >&2
    exit 2
  fi
fi

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
  echo "Permitted allowlist entries (per ADR-016 D4 + $ALLOWLIST):" >&2
  if [ -n "$ALLOWED_PATHS" ]; then
    echo "$ALLOWED_PATHS" | sed 's/^/  /' >&2
  else
    echo "  (none — empty allowlist registry)" >&2
  fi
  echo "" >&2
  echo "The fix is almost never 'add this path to the registry'. Per ADR-016 D3 the" >&2
  echo "factory is one audited key-home: import supabaseAdmin() from" >&2
  echo "api/src/lib/server/supabase-admin.ts and hold no key. ANY change to the" >&2
  echo "composition — addition OR removal — REQUIRES Sec-consult + an ADR-016" >&2
  echo "amendment per ADR-016 D2 (scope fixed to both directions by D4)." >&2
  exit 1
fi

echo "RT-26 fence: scope $SCOPE clean (all SUPABASE_SERVICE_ROLE_KEY refs within allowlist, if any)."
exit 0
