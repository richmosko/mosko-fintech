#!/usr/bin/env bash
#
# TBC-node — TenantBoundClient CI grep fence (Node/TS provider-sync analogue)
#
# Lock anchors:
#   - ADR-011 Decision 17 / Lock 13 mod #3 (V1-SHIP-BLOCK verbatim — tenant-binding
#     in code is the ONLY sanctioned pfin DB-access path for any DB-touching worker).
#   - ADR-011 Decision 4 Privileged-context-surfaces bullet
#     (NOT catalogued §10 numbered list — discipline-preservation guard).
#   - ADR-019 amendment (provider-sync sibling worker; Node/TS; F/CTO-ratified
#     2026-07-17): the FIRST DB-touching Node worker. pdf-render is Node but has
#     ZERO DB reach (Lock 13 mod #2 / RT-22), so this is the first place a Node
#     TenantBoundConnection-equivalent is required.
#   - ARCH §6 Security scan stage (ii) + ARCH §6.1 TBC row (Node analogue).
#
# §10 attribution: like the Python fence-tbc, TBC-node is the Privileged-context-
# surfaces bullet — code-layer parallel to RT-26, NOT a third catalogued §10
# instance. Decision 4's numbered list stays 2-instance (RT-22 first, RT-26 second)
# per the discipline-preservation guard. Lock 13 mod #3 V1-SHIP-BLOCK is orthogonal
# to the §10 catalogued-instance axis.
#
# WHY A SECOND FENCE (not extend fence-tbc): the Python fence greps SQLAlchemy /
# psycopg patterns and discovers `class TenantBoundConnection`. Those patterns do
# not match TypeScript. A Node worker touching pfin needs a Node TenantBoundClient-
# equivalent + a TS-native pattern set. This is that fence.
#
# ┌─ SANCTIONED-TRANSPORT CONTRACT (the class this fence discovers) ─────────────┐
# │ The provider-sync worker's ONLY sanctioned Postgres entry point is a class    │
# │ `TenantBoundClient` (Backend-owned worker source at                          │
# │ workers/provider-sync/src/). It MUST:                                         │
# │   - bind users_id at construction (per Lock 13 mod #3 / Decision 1 clause d); │
# │   - be the sole file constructing a raw Postgres client (postgres()/pg Pool/  │
# │     Client);                                                                   │
# │   - use DIRECT Postgres (postgres.js / node-postgres + PFIN_DB_PASSWORD),      │
# │     NEVER @supabase/supabase-js createClient() — that keeps provider-sync OFF  │
# │     the RT-26 SUPABASE_SERVICE_ROLE_KEY allowlist (RT-26 stays confined to     │
# │     api/src/ per SECURITY §4.1).                                              │
# │ DevOps owns THIS FENCE + its fixture; Backend owns the TenantBoundClient       │
# │ CLASS implementation matching this contract (role separation).                │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# Catch criterion — TWO independent legs, both fail-closed:
#
# LEG 1 — raw-client construction OUTSIDE the file declaring class TenantBoundClient:
#   1. postgres.js instance construction:   postgres(          (porsager postgres.js)
#   2. node-postgres construction:          new Pool( / new Client( / new pg.Pool( / new pg.Client(
#   3. Supabase admin JS client:            createClient(      (BANNED in worker —
#      the worker must NOT use @supabase/supabase-js; this doubles as RT-26
#      confinement enforcement so provider-sync never enters the RT-26 allowlist).
#   4. Supabase client import:              from '@supabase/supabase-js'  (belt-and-
#      suspenders for #3).
#   Scope: *.ts / *.mts / *.cts / *.js / *.mjs / *.cjs. Pure line-comment hits
#   (// … or block-comment continuation * …) are skipped as documentation.
#
# LEG 2 — SUPABASE_SERVICE_ROLE_KEY ABSENCE tripwire (Sec CONDITION, 2026-07-17):
#   The literal SUPABASE_SERVICE_ROLE_KEY MUST NOT appear ANYWHERE in the target
#   tree (zero hits, fail-closed) — NO class exclusion, NO comment-skip. Rationale
#   (Sec): the "provider-sync never touches the service-role key" invariant is what
#   keeps ADR-016 UN-amended; a future dev adding @supabase/supabase-js + the KEY
#   (e.g. for a Storage/Auth call) would silently create an UNALLOWLISTED RT-26
#   surface — exactly the drift RT-26 exists to catch. This asserts ABSENCE (it is
#   NOT a new allowlist entry), so it does NOT touch ADR-016 D2 — it ENFORCES the
#   confinement rather than widening it. Strict zero-hit (comments included) mirrors
#   RT-26's own no-comment-skip posture for the KEY literal. Leg 1 (#4 import ban)
#   and Leg 2 (key-literal absence) are the belt-and-suspenders pair Sec requires.
#
# Allowlist mechanism: class-declaration discovery (NOT hardcoded path).
#   1. Find file declaring `class TenantBoundClient` → ALLOWED_FILE.
#   2. If none found → fail-closed (exit 2), UNLESS --allow-missing-class is passed
#      (inversion/fixture mode, which has no class by design).
#   3. Grep target tree for the pattern set; exclude ALLOWED_FILE; any other hit =
#      violation.
#
# Usage:
#   bash fence-tbc-node.sh [--allow-missing-class] <target-ts-tree-path>
#
#   --allow-missing-class : tolerate absence of the TenantBoundClient class
#                           (inversion/fixture mode ONLY — the fixture tree has no
#                           class by design; production mode MUST NOT pass it, so
#                           class absence fails closed there).
#
# Exit codes:
#   0   — target tree clean (TBC class exists; no raw client construction outside it).
#   1   — one or more raw client constructions outside TenantBoundClient (fail-closed).
#   2   — argument / environment error OR TenantBoundClient class not found in
#         target (unless --allow-missing-class was passed).
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
      echo "Usage: bash $(basename "$0") [--allow-missing-class] <target-ts-tree-path>" >&2
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
  echo "Usage: bash $(basename "$0") [--allow-missing-class] <target-ts-tree-path>" >&2
  exit 2
fi
if [ ! -e "$TARGET" ]; then
  echo "FATAL: target tree path not found: $TARGET" >&2
  exit 2
fi

# Discover the file declaring `class TenantBoundClient`.
# (|| true so empty result doesn't trip set -e.)
ALLOWED_FILES=$(grep -rln 'class TenantBoundClient' "$TARGET" 2>/dev/null || true)

if [ -z "$ALLOWED_FILES" ]; then
  # Class absence = TBC discipline mechanism absent in this target.
  #
  # DEFAULT (production mode): FAIL CLOSED (exit 2). If TenantBoundClient does not
  # exist, the sole sanctioned Postgres-client entry point is gone — the discipline
  # is not merely violated, it is ABSENT. A clean grep in that state is meaningless.
  #
  # --allow-missing-class (inversion/fixture mode ONLY): the fixture tree has no
  # class by design; the whole point is to prove the fence flags the violation
  # fixture. There we tolerate class absence and let the grep stage trip.
  if [ "$ALLOW_MISSING_CLASS" -eq 0 ]; then
    echo "FATAL: TenantBoundClient class not found in $TARGET." >&2
    echo "Lock 13 mod #3: TenantBoundClient is the ONLY sanctioned Postgres-client" >&2
    echo "entry point in workers/provider-sync/. Its absence means the discipline" >&2
    echo "mechanism does not exist in this tree. Failing closed (a clean grep against" >&2
    echo "a class-less tree proves nothing)." >&2
    echo "(If this is the fixture/inversion invocation, pass --allow-missing-class.)" >&2
    exit 2
  fi
  echo "INFO: TenantBoundClient class not found in $TARGET." >&2
  echo "INFO: --allow-missing-class set (inversion/fixture mode) — proceeding under" >&2
  echo "INFO: no-class-file assumption; every raw client construction in scope is a violation." >&2
  ALLOWED_FILES=""
fi

# Pattern set (POSIX ERE; boundary-aware where an identifier prefix could false-match):
#   1. postgres.js factory — porsager `postgres(` (word-boundary guarded so
#      `mypostgres(` does not match).
#   2. node-postgres — `new Pool(` / `new Client(` optionally qualified `new pg.Pool(`.
#   3. Supabase admin JS client construction — `createClient(` (BANNED in worker).
#   4. Supabase client import — `from '@supabase/supabase-js'` (belt-and-suspenders).
PATTERN_POSTGRES_JS='(^|[^[:alnum:]_.])postgres\('
PATTERN_PG_POOL_CLIENT='new[[:space:]]+(pg\.)?(Pool|Client)\('
PATTERN_SUPABASE_CREATE='(^|[^[:alnum:]_.])createClient\('
PATTERN_SUPABASE_IMPORT="@supabase/supabase-js"

# Scan ALL in-scope files (including the class file) — do NOT pre-exclude by
# basename. The sole exclusion mechanism is the FULL-PATH re-verify loop below.
#
# WHY NOT grep --exclude=<basename> (the false-negative Sec caught 2026-07-17):
# grep --exclude matches on BASENAME, so excluding the class file `client.ts` would
# ALSO exclude a violator `new Pool()` in a DIFFERENT directory that happens to share
# the basename (e.g. class at src/db/client.ts + violator at src/adapters/plaid/
# client.ts). The violator would never enter RAW_HITS, so the full-path re-verify
# loop could never recover it — silently skipped. Dropping --exclude and letting the
# full-path loop do ALL the exclusion is correct: the class file's own postgres()/
# Pool() is skipped by full-path match, and a same-basename violator elsewhere has a
# distinct full path → caught. (See tests/fixtures/ci/tbc-node-basename-collision/.)
RAW_HITS=$(grep -rEnH \
  --include='*.ts' --include='*.mts' --include='*.cts' \
  --include='*.js' --include='*.mjs' --include='*.cjs' \
  -e "$PATTERN_POSTGRES_JS" \
  -e "$PATTERN_PG_POOL_CLIENT" \
  -e "$PATTERN_SUPABASE_CREATE" \
  -e "$PATTERN_SUPABASE_IMPORT" \
  "$TARGET" 2>/dev/null || true)

# Filter each hit:
#   (1) Skip pure line-comment (// …) and block-comment continuation (* … or /* …)
#       lines — documentation mentioning a banned pattern is not real code. Does
#       NOT strip trailing inline comments; a human reviewer adjudicates that rare
#       shape if surfaced (mirrors the Python fence's comment-skip caveat).
#   (2) Exclude a hit ONLY if its FULL PATH matches an allowed (class-declaring)
#       file. This is the SOLE exclusion mechanism (grep --exclude is deliberately
#       NOT used — it matches basenames and would over-exclude a same-basename
#       violator in an unrelated path; see the scan-comment above).
VIOLATIONS=0
if [ -n "$RAW_HITS" ]; then
  while IFS= read -r hit; do
    hit_file=$(echo "$hit" | cut -d: -f1)
    hit_content=$(echo "$hit" | cut -d: -f3-)
    stripped=$(echo "$hit_content" | sed 's/^[[:space:]]*//')
    case "$stripped" in
      //*) continue ;;
      /\**) continue ;;
      \**) continue ;;
    esac
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
      echo "VIOLATION (leg 1: raw-client construction): outside TenantBoundClient:" >&2
      echo "  $hit" >&2
      VIOLATIONS=$((VIOLATIONS+1))
    fi
  done <<< "$RAW_HITS"
fi

# ── LEG 2 — SUPABASE_SERVICE_ROLE_KEY ABSENCE tripwire (Sec condition) ─────────
# Assert-ABSENT over the WHOLE target tree: NO class exclusion, NO comment-skip.
# Any occurrence of the literal is a violation (strict zero-hit). See the LEG 2
# rationale block in the header. Independent of the class-discovery gate — but note
# production-mode already exits 2 above if TenantBoundClient is absent, so this leg
# runs when the class exists (real tree) or under --allow-missing-class (fixture).
KEY_HITS=$(grep -rEnH \
  --include='*.ts' --include='*.mts' --include='*.cts' \
  --include='*.js' --include='*.mjs' --include='*.cjs' \
  -e 'SUPABASE_SERVICE_ROLE_KEY' \
  "$TARGET" 2>/dev/null || true)
if [ -n "$KEY_HITS" ]; then
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    echo "VIOLATION (leg 2: SUPABASE_SERVICE_ROLE_KEY must be ABSENT in provider-sync source):" >&2
    echo "  $hit" >&2
    VIOLATIONS=$((VIOLATIONS+1))
  done <<< "$KEY_HITS"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "TBC-node fence: $VIOLATIONS violation(s) in $TARGET. Failing closed." >&2
  echo "Lock 13 mod #3: TenantBoundClient is the only allowed Postgres-client entry" >&2
  echo "point in workers/provider-sync/." >&2
  echo "  LEG 1: a raw postgres()/new Pool()/new Client(), OR any @supabase/supabase-js" >&2
  echo "         createClient()/import outside the TenantBoundClient class, is V1-SHIP-BLOCK." >&2
  echo "  LEG 2: any SUPABASE_SERVICE_ROLE_KEY reference in provider-sync source is" >&2
  echo "         V1-SHIP-BLOCK — the worker uses DIRECT Postgres only. Referencing the" >&2
  echo "         key would create an unallowlisted RT-26 surface (Sec condition tripwire)." >&2
  if [ -n "$ALLOWED_FILES" ]; then
    echo "" >&2
    echo "Allowed file(s) declaring TenantBoundClient class:" >&2
    echo "$ALLOWED_FILES" | sed 's/^/  /' >&2
  fi
  exit 1
fi

echo "TBC-node fence: $TARGET clean (no raw client construction outside TenantBoundClient class)."
exit 0
