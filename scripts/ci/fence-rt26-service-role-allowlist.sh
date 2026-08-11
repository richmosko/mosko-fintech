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
#   4. Else → trip (exit 1; fence fails closed).
#   Before any of that: the registry itself is validated — every entry must name a
#   file that EXISTS and that actually REFERENCES the key (exit 2 on either).
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
# Exit codes — three DISTINCT classes; do not collapse them (see the registry
# validation block for why the inversion probe depends on the distinction):
#   0   — audit scope clean (zero hits OR all hits at allowlisted paths).
#   1   — one or more hits outside allowlist. A statement about the CODE.
#   2   — argument / environment error, OR registry integrity failure (an entry
#         naming a nonexistent file, or naming a file that references no key).
#         A statement about the REGISTRY — the scan did not run.
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
  REGISTRY_BAD=0
  if [ -n "$STALE" ]; then
    REGISTRY_BAD=1
    echo "FATAL: allowlist registry names path(s) that do not exist:" >&2
    printf '%s' "$STALE" | sed 's/^/  /' >&2
    echo "" >&2
    echo "Each is a standing pre-authorization: nothing references the key there" >&2
    echo "TODAY, so the fence stays green — but the moment a file lands at that" >&2
    echo "path holding a raw SUPABASE_SERVICE_ROLE_KEY, this fence PERMITS it." >&2
    echo "" >&2
  fi

  # -------------------------------------------------------------------------
  # REGISTRY USE VALIDATION (Sec-adopted follow-up to (D), 2026-08-10).
  #
  # Existence validation asks "does this path name a real file?". It is the weaker
  # question, and it MISSED one of the three entries the ADR-016 D4 prune removed:
  # the Plaid `webhook/` route EXISTED while holding no key. This asks the stronger
  # one — "does this file actually reference the key?" — which makes the registry
  # SELF-DESCRIBING rather than merely non-fictional. An entry that uses no key is a
  # permit nothing needs, i.e. the same standing pre-authorization, one step subtler.
  #
  # ⚠ NOW THAT THE REGISTRY IS A SINGLE ENTRY, THIS IS A TRIPWIRE ON THE FACTORY
  # ITSELF. If api/src/lib/server/supabase-admin.ts ever stops referencing
  # SUPABASE_SERVICE_ROLE_KEY, this fires.
  #
  # ⚠ AND THE FIX IS TO REMOVE THE ENTRY — NEVER TO RE-ADD THE KEY. That inversion
  # is the whole reason this diagnostic is worded the way it is (Sec condition, and
  # it is the condition most likely to be got wrong under time pressure): the
  # obvious-looking repair for "allowlisted file has no key" is to put a key back,
  # which would re-introduce exactly the raw reference RT-26 exists to confine. A
  # surface that stopped needing service_role is GOOD NEWS. The registry should
  # shrink to match; per ADR-016 D3 the factory is one audited key-home, and if the
  # home itself is gone the permit has nothing to protect.
  #
  # ⚠ TEMPO CHANGE AGAINST ADR-016 D2 — recorded because it narrows a ratified
  # process. D2 requires Sec-consult + an ADR-016 amendment "at the surface-
  # introducing lock". Before this check, an entry could be ratified and land in the
  # amendment PR while its code landed later. It cannot now: an entry whose file
  # does not yet reference the key FAILS CI. So the entry must land in the SAME
  # change as the key-referencing code, or after it — never before. D2's gate is
  # unchanged in substance; only the ORDER is constrained. Flagged to Architect as
  # possibly worth an ADR-016 note; ADR authorship is not DevOps's to perform.
  # -------------------------------------------------------------------------
  UNUSED=""
  while IFS= read -r allow; do
    [ -z "$allow" ] && continue
    # Skip paths already reported as nonexistent — otherwise a stale entry would be
    # reported twice under two different diagnoses, and the second would be wrong.
    [ -f "$allow" ] || continue
    if ! grep -q 'SUPABASE_SERVICE_ROLE_KEY' "$allow" 2>/dev/null; then
      UNUSED="${UNUSED}${allow}"$'\n'
    fi
  done <<< "$ALLOWED_PATHS"
  if [ -n "$UNUSED" ]; then
    REGISTRY_BAD=1
    echo "FATAL: allowlist registry permits path(s) that reference no service_role key:" >&2
    printf '%s' "$UNUSED" | sed 's/^/  /' >&2
    echo "" >&2
    echo "The file exists but holds no SUPABASE_SERVICE_ROLE_KEY, so the permit" >&2
    echo "protects nothing and stands open for whatever lands there next." >&2
    echo "" >&2
    echo "⚠ THE FIX IS TO REMOVE THE ENTRY. DO NOT ADD A KEY REFERENCE TO MAKE THIS" >&2
    echo "  PASS — that would re-introduce the raw reference RT-26 exists to confine," >&2
    echo "  and it inverts the finding. A surface that no longer needs service_role" >&2
    echo "  is a GOOD outcome; the registry shrinks to match it." >&2
    echo "" >&2
    echo "Per ADR-016 D3 the factory is one audited key-home: callers import" >&2
    echo "supabaseAdmin() and hold no key. Removing an entry REQUIRES Sec-consult +" >&2
    echo "an ADR-016 amendment per D2 (scope fixed to cover removals by D4)." >&2
    echo "" >&2
  fi

  # Single exit covering BOTH registry-integrity classes. They are reported together
  # on purpose: a registry carrying both defects should surface both in ONE run.
  # Exiting inside the existence branch would show only the nonexistent paths, invite
  # a fix, and then reveal the unused permits on the NEXT run — which reads as "a new
  # problem appeared" rather than "you were shown half of it". That is precisely the
  # shape that let the four-entry registry look one defect smaller than it was.
  if [ "$REGISTRY_BAD" -ne 0 ]; then
    echo "Fix the REGISTRY, not this check. Changing the composition in EITHER" >&2
    echo "direction REQUIRES Sec-consult + an ADR-016 amendment per D2 (scope fixed" >&2
    echo "to cover removals by D4) — a prune is not editorial. Registry: $ALLOWLIST" >&2
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
