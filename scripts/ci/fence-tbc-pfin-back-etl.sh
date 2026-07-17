#!/usr/bin/env bash
#
# TBC — TenantBoundConnection CI grep fence
#
# Lock anchors:
#   - ADR-011 Decision 17 / Lock 13 mod #3 (V1-SHIP-BLOCK verbatim)
#   - ADR-011 Decision 4 Privileged-context-surfaces bullet
#     (NOT catalogued §10 numbered list — discipline-preservation guard)
#   - ARCH §6 Security scan stage (ii) + ARCH §6.1 TBC row
#   - ARCH §6 Phase 5 detail item (d)
#
# §10 attribution: TBC is the Privileged-context-surfaces bullet — code-layer
# parallel to RT-26, NOT a third catalogued §10 instance. Decision 4 numbered list
# stays 2-instance per the discipline-preservation guard (RT-22 first, RT-26 second).
# V1-SHIP-BLOCK axis (Lock 13 mod #3) is orthogonal to the §10 catalogued-instance axis.
#
# Catch criterion:
#   - Bare SQLAlchemy engine construction: `sqla.create_engine(` /
#     `sqlalchemy.create_engine(` / unqualified `create_engine(` — the ETL's
#     REAL DB connection path (core.py routes it through
#     TenantBoundConnection.system(); a bare create_engine() bypasses the sole
#     sanctioned engine factory). This is the pattern the pre-fix fence missed,
#     causing it to fail OPEN against the actual code (Backend DP5).
#   - Raw psycopg2.connect() / psycopg.connect() (psycopg3) / asyncpg.connect()
#     invocations outside the file declaring the TenantBoundConnection class —
#     kept as defense-in-depth (a future raw-driver regression must still trip).
#   - Includes from-import shape (`from psycopg2 import connect`).
#   All patterns are scoped `--include='*.py'` and evaluated outside the file
#   declaring the TenantBoundConnection class.
#
# Allowlist mechanism: class-declaration discovery (NOT hardcoded path).
#   1. Find file declaring `class TenantBoundConnection` → ALLOWED_FILE.
#   2. If none found → fail-closed (exit 2), UNLESS --allow-missing-class is
#      passed (inversion/fixture mode, which has no class by design).
#   3. Grep target tree for pattern set; exclude ALLOWED_FILE; any other hit = violation.
#
# Cross-repo posture (per F/CTO α + paired-PR ratify 2026-06-08):
#   - This script is the source-of-truth in mosko-fintech repo at scripts/ci/.
#   - Vendored (literal file copy) into pfin_back_etl repo at the same path.
#   - mosko-fintech CI runs in inversion mode only against tests/fixtures/ci/.
#   - pfin_back_etl CI runs in production mode against the actual Python tree
#     + inversion mode redundantly.
#
# Usage:
#   bash fence-tbc-pfin-back-etl.sh [--allow-missing-class] <target-python-tree-path>
#
#   --allow-missing-class : tolerate absence of the TenantBoundConnection class
#                           (inversion/fixture mode ONLY — the fixture tree has
#                           no class by design; production mode MUST NOT pass it,
#                           so class absence fails closed there).
#
# Exit codes:
#   0   — target tree clean (TBC class exists; no engine/connect construction outside class).
#   1   — one or more engine/connect constructions outside TBC class (fail-closed).
#   2   — argument / environment error OR TBC class not found in target
#         (unless --allow-missing-class was passed).
#

set -euo pipefail

ALLOW_MISSING_CLASS=0
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --allow-missing-class)
      ALLOW_MISSING_CLASS=1
      ;;
    -*)
      echo "FATAL: unknown flag: $arg" >&2
      echo "Usage: bash $(basename "$0") [--allow-missing-class] <target-python-tree-path>" >&2
      exit 2
      ;;
    *)
      if [ -n "$TARGET" ]; then
        echo "FATAL: multiple target args (got '$TARGET' and '$arg')." >&2
        exit 2
      fi
      TARGET="$arg"
      ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "FATAL: missing target tree arg." >&2
  echo "Usage: bash $(basename "$0") [--allow-missing-class] <target-python-tree-path>" >&2
  exit 2
fi
if [ ! -e "$TARGET" ]; then
  echo "FATAL: target tree path not found: $TARGET" >&2
  exit 2
fi

# Discover the file declaring `class TenantBoundConnection`.
# (|| true so empty result doesn't trip set -e.)
ALLOWED_FILES=$(grep -rln 'class TenantBoundConnection' "$TARGET" 2>/dev/null || true)

if [ -z "$ALLOWED_FILES" ]; then
  # Class absence = TBC discipline mechanism absent in this target.
  #
  # DEFAULT (production mode): FAIL CLOSED (exit 2). If the TenantBoundConnection
  # class does not exist, the sole sanctioned Postgres-client entry point is gone
  # — the discipline is not merely violated, it is ABSENT. A clean grep in that
  # state is meaningless, so we must not let it exit 0. (Prior behavior fell
  # through to the grep and exited 0 when no raw hit happened to be present —
  # that was the fail-OPEN hole this branch now closes.)
  #
  # --allow-missing-class (inversion/fixture mode ONLY): the fixture tree has no
  # class by design; the whole point of that run is to prove the fence flags the
  # violation fixture. There we tolerate class absence and let the grep stage
  # trip on the fixture's deliberate violations.
  if [ "$ALLOW_MISSING_CLASS" -eq 0 ]; then
    echo "FATAL: TenantBoundConnection class not found in $TARGET." >&2
    echo "Lock 13 mod #3: TenantBoundConnection is the ONLY sanctioned Postgres-client" >&2
    echo "entry point in pfin_back_etl. Its absence means the discipline mechanism does" >&2
    echo "not exist in this tree. Failing closed (a clean grep against a class-less tree" >&2
    echo "proves nothing)." >&2
    echo "(If this is the fixture/inversion invocation, pass --allow-missing-class.)" >&2
    exit 2
  fi
  echo "INFO: TenantBoundConnection class not found in $TARGET." >&2
  echo "INFO: --allow-missing-class set (inversion/fixture mode) — proceeding under" >&2
  echo "INFO: no-class-file assumption; every engine/connect construction in scope is a violation." >&2
  ALLOWED_FILES=""
fi

# Pattern set:
#   1. Bare SQLAlchemy engine construction — the ETL's REAL DB connection path
#      (Backend DP5). Matches `sqla.create_engine(`, `sqlalchemy.create_engine(`,
#      and unqualified `create_engine(`. This is the primary catch: the pre-fix
#      fence lacked it and failed OPEN against the actual code.
#   2. Raw .connect() calls (defense-in-depth against a future raw-driver regression).
#   3. from-import-connect shape.
PATTERN_CREATE_ENGINE='(sqla\.|sqlalchemy\.)?create_engine\('
PATTERN_CONNECT='(psycopg2|psycopg|asyncpg)\.connect\('
PATTERN_FROM_IMPORT='from[[:space:]]+(psycopg2|psycopg|asyncpg)[[:space:]]+import[[:space:]]+connect'

# Scan ALL in-scope .py files (including the class file) — do NOT pre-exclude by
# basename. The sole exclusion mechanism is the FULL-PATH re-verify loop below.
#
# WHY NOT grep --exclude=<basename> (the false-negative Sec caught 2026-07-17;
# fixed here for Python/Node parity in lockstep with fence-tbc-node.sh): grep
# --exclude matches on BASENAME, so excluding the class file `core.py` would ALSO
# exclude a violator create_engine()/connect() in a DIFFERENT directory sharing the
# basename (e.g. class at db/core.py + violator at etl/core.py). The violator would
# never enter RAW_HITS, so the full-path re-verify loop could never recover it —
# silently skipped. Letting the full-path loop do ALL the exclusion is correct: the
# class file's own construction is skipped by full-path match, and a same-basename
# violator elsewhere has a distinct full path → caught.
# (See tests/fixtures/ci/tbc-basename-collision/.)
RAW_HITS=$(grep -rEnH --include='*.py' \
  -e "$PATTERN_CREATE_ENGINE" \
  -e "$PATTERN_CONNECT" \
  -e "$PATTERN_FROM_IMPORT" \
  "$TARGET" 2>/dev/null || true)

# Filter each hit:
#   (1) Skip if the matched line is a pure `#` comment (the connect-pattern in
#       the line is just text, not real code). This catches the false-positive
#       class where comments documenting psycopg2.connect() usage would otherwise
#       trip the fence. Caveats: does NOT skip docstrings or inline trailing
#       comments — those are rare false-positive shapes; human reviewer
#       adjudicates if surfaced.
#   (2) Exclude a hit ONLY if its FULL PATH matches an allowed (class-declaring)
#       file. This is the SOLE exclusion mechanism (grep --exclude is deliberately
#       NOT used — it matches basenames and would over-exclude a same-basename
#       violator in an unrelated path; see the scan-comment above).
VIOLATIONS=0
if [ -n "$RAW_HITS" ]; then
  while IFS= read -r hit; do
    # Extract filename (field 1) + content (field 3+).
    hit_file=$(echo "$hit" | cut -d: -f1)
    hit_content=$(echo "$hit" | cut -d: -f3-)
    # (1) Skip pure-# comment lines.
    stripped=$(echo "$hit_content" | sed 's/^[[:space:]]*//')
    case "$stripped" in
      \#*) continue ;;
    esac
    # (2) Re-verify against ALLOWED_FILES.
    norm_hit=$(echo "$hit_file" | sed 's|^\./||')
    is_allowed=0
    if [ -n "$ALLOWED_FILES" ]; then
      while IFS= read -r allow; do
        [ -z "$allow" ] && continue
        norm_allow=$(echo "$allow" | sed 's|^\./||')
        if [ "$norm_hit" = "$norm_allow" ]; then
          is_allowed=1
          break
        fi
      done <<< "$ALLOWED_FILES"
    fi
    if [ "$is_allowed" -eq 0 ]; then
      echo "VIOLATION: DB engine/connect construction outside TenantBoundConnection class:" >&2
      echo "  $hit" >&2
      VIOLATIONS=$((VIOLATIONS+1))
    fi
  done <<< "$RAW_HITS"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "TBC fence: $VIOLATIONS violation(s) in $TARGET. Failing closed." >&2
  echo "Lock 13 mod #3: TenantBoundConnection is the only allowed Postgres-client entry" >&2
  echo "point in pfin_back_etl. A bare sqla.create_engine()/create_engine() OR raw" >&2
  echo "psycopg2/psycopg/asyncpg .connect() outside the TenantBoundConnection class is" >&2
  echo "V1-SHIP-BLOCK." >&2
  if [ -n "$ALLOWED_FILES" ]; then
    echo "" >&2
    echo "Allowed file(s) declaring TenantBoundConnection class:" >&2
    echo "$ALLOWED_FILES" | sed 's/^/  /' >&2
  fi
  exit 1
fi

echo "TBC fence: $TARGET clean (no engine/connect construction outside TenantBoundConnection class)."
exit 0
