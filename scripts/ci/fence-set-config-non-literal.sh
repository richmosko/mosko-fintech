#!/usr/bin/env bash
#
# fence-set-config-non-literal — GUC-name integrity watcher (Sec C3).
#
# ┌─ WHAT THIS FENCE ENFORCES ───────────────────────────────────────────────┐
# │ No function that `anon` OR `authenticated` can EXECUTE (i.e. no           │
# │ PostgREST-reachable function), in a schema PostgREST exposes              │
# │ (supabase/config.toml [api] schemas), may call `set_config` with a        │
# │ NON-LITERAL first argument (the GUC NAME being set). Fail-closed: any     │
# │ such function trips the fence, exit 1.                                    │
# └─────────────────────────────────────────────────────────────────────────┘
#
# WHY THIS EXISTS — the negative-space property with no watcher (Sec C3):
#   Three surfaces derive trust-critical behavior from a transaction-local
#   GUC set ONLY by trusted worker/app code, never by a Data-API caller:
#     - `054` (pfin.nav_daily)          — reads `app.nav_computed_for`
#     - `107` (pfin.nav_component_daily) — reads the SAME `app.nav_computed_for`
#     - `111` (the audit helper, forward-looking) — will read
#       `app.report_generation_source` (exact-match 'cron')
#   All three READ a GUC via `current_setting(...)`; NONE of them call
#   `set_config` themselves — the SETTER is trusted worker code
#   (connection.py's `impersonate()`, invoked outside PostgREST/RLS entirely).
#   The soundness of all three rests on ONE assumption this fence is the
#   first mechanical check of: that no PostgREST-reachable function (`anon`
#   or `authenticated` EXECUTE) can be made to call `set_config` with a GUC
#   NAME an ordinary caller controls. If one existed, an ordinary user could
#   invoke it over the Data API and spoof `app.nav_computed_for` (or the future
#   `app.report_generation_source`) to an arbitrary value — defeating the
#   fail-closed trigger checks these three migrations rely on, with no
#   RLS violation anywhere in the picture (the attacker never touches the
#   table directly).
#
#   ⚠ THIS FENCE CATCHES THE SETTER, WHICH IS THE POINT. It does not, and
#   cannot, distinguish "a reader of a GUC some other function sets" from
#   anything else — reading a GUC via `current_setting()` is not itself a
#   risk this fence models at all; only the ACT of setting one with a
#   caller-controlled name is. `pfin.fn_emit_audit_log` (111) — a general
#   SECURITY DEFINER RPC, EXECUTE granted to `authenticated`/`service_role`,
#   NOT a trigger — reading `app.report_generation_source` and deriving
#   `trigger_source` from it is invisible to this fence BY DESIGN: it is not
#   the surface this fence watches, and does not need to be. It has no OWN
#   opinion about what set the GUC, so a caller-controlled setter upstream is
#   the entire attack surface, and this fence is aimed exactly at that
#   upstream function, not at every downstream reader of the value it
#   produces.
#
#   ⚠ SEVERITY OF THE GAP THIS FENCE CLOSES, PER SURFACE (Sec ruling,
#   2026-09-05, wording corrected 2026-09-06) — say this at its true weight,
#   not its worst-case shape: for 111 specifically, a successful GUC-name
#   spoof (were the setter this fence forbids ever to exist) is a BOUNDED
#   residual, not an unbounded forgery channel. `fn_emit_audit_log` carries
#   its own Sec C2 REQUIREMENT, independent of this fence: an audit row must
#   annotate a real privileged write, by THIS caller, in THIS transaction —
#   not merely a row that exists somewhere. Cite the REQUIREMENT here, not
#   its enforcing expression: the predicate implementing it has changed more
#   than once, and a header tied to a specific expression goes stale the
#   next time C2's mechanism does, while the requirement itself is what
#   actually bounds the residual. Under that requirement, a forged
#   `app.report_generation_source = 'cron'` could only MISLABEL a generation
#   the caller ALREADY REALLY PERFORMED (marking their own on-demand report
#   as cron-triggered); it could not fabricate an audit row describing a
#   write that never happened, nor attribute one to another tenant. This
#   fence exists so that residual stays the only one — it does not, by
#   itself, establish that 054/107's exposure is similarly bounded, and
#   makes no such claim: their write-tenant binding triggers gate table
#   INSERTs this fence does not analyze, and that boundedness (or lack of
#   it) is a property of THOSE triggers and grants, not of this fence.
#
# MEASURED TODAY (2026-09-05, against this branch's migration set): the ONLY
# function that calls `set_config` at all is `058`'s account-closure RPC
# (`pfin.fn_close_account` or its equivalent), TWO call sites, BOTH with a
# hardcoded string-literal GUC name (`'pfin.reason_code'`,
# `'pfin.effective_date'`) — the caller-controlled argument in both calls is
# the VALUE being set, never the NAME, which is exactly the safe shape this
# fence exists to keep true. `054`/`107` currently call NO `set_config` at
# all (they are readers only, via `current_setting`). `111`'s
# `pfin.fn_emit_audit_log` also calls no `set_config` — it too is a reader
# (`current_setting('app.report_generation_source', true)`, deriving
# `trigger_source`) — so this fence's clean-tree result is not vacuous
# absence-of-surface, it is a positive check that the one function which DOES
# reference the GUC name only ever reads it.
#
# EXPLICITLY NOT CATCHING (residual, stated per this project's fence-design
# discipline — a fence that hides its own blind spot is worse than one that
# names it):
#   - DYNAMIC SQL — NARROWER THAN IT LOOKS (corrected 2026-09-06, Sec NOTE
#     1: an earlier draft of this bullet OVERSTATED the gap). This fence is
#     a TEXT-PATTERN scan of the function's rendered source — it looks for
#     the literal substring `set_config(` and inspects what textually
#     follows it up to the first top-level comma. That means a `set_config`
#     call assembled via `EXECUTE 'select set_config(' || quote_literal(...)
#     || ...` or similar concatenation STILL TRIPS THIS FENCE, because the
#     unbroken token `set_config(` still appears verbatim in the source text
#     — the scan does not care that the surrounding SQL is dynamic, only
#     that the characters are present. The ONLY dynamic-SQL shape genuinely
#     INVISIBLE to this scan is one where the literal token `set_config(`
#     itself is split across the concatenation (e.g. built from
#     `'set_' || 'config('`, or via `format('set_%s(', 'config')`), so the
#     contiguous substring never appears anywhere in the stored source.
#     Closing that narrower residual needs a parse of the PL/pgSQL AST (not
#     available via a portable catalog query) or a runtime/dynamic-SQL audit
#     — out of scope for a static CI fence, not attempted here. Stating the
#     gap at its true (narrow) size matters: an overstated residual invites
#     someone to build a second fence for ground this one already covers.
#   - A `prosrc` FUNCTION BODY THAT DOESN'T HOLD THE BODY was a silent-pass
#     hazard, FIXED 2026-09-06 (Sec FLAG; fix corrected same-day after live
#     measurement). A PG14+ SQL-standard-body function (`language sql begin
#     atomic ... end`) stores its body in `prosqlbody`, not `prosrc`. Sec's
#     original report described `prosrc` as NULL for that shape — MEASURED
#     under this project's pinned PG17 (via the golden fixture,
#     tests/fixtures/ci/c3-set-config-violation.sql), it is instead an
#     EMPTY STRING (length 0). The end result is the same either way — an
#     empty/NULL `clean_src` never matches `set_config\(`, so the original
#     `target_calls` filter EXCLUDED the row instead of FLAGGING it, a
#     silent pass on exactly the function class this fence exists to catch
#     — but the fix had to change: a plain `coalesce(p.prosrc, ...)` (which
#     substitutes only on NULL) does NOT fall through on an empty string,
#     and the first draft of this fix shipped that version, which would
#     have looked fixed while remaining exactly as blind. The query now
#     scans `coalesce(nullif(p.prosrc, ''), pg_get_functiondef(p.oid))` —
#     `nullif` normalizes an empty string to NULL first — which renders a
#     `prosqlbody` body back into text and was verified live against the
#     fixture, not merely reasoned about.
#   - A first argument built from NESTED PARENTHESES containing a comma
#     (e.g. `set_config(some_func(a, b), val, true)`) can be mis-split by
#     this fence's naive up-to-the-first-comma capture. This is FAIL-CLOSED
#     by construction, not fail-open: a mis-split capture almost never
#     happens to look like a clean `'literal'` string, so the far more
#     likely outcome of a mis-parse is a (correct-shaped, if not
#     correct-reasoned) VIOLATION flag, not a false clear. A human reviewing
#     a flagged hit resolves the ambiguity; this fence never silently clears
#     one.
#   - A first-argument string literal containing an embedded, doubled-quote-
#     escaped apostrophe (`'app.o''brien'`) is treated as NON-literal
#     (flagged) by the simple `^'[^']*'$` check below, which does not permit
#     an embedded quote at all. Accepted: a GUC NAME containing an apostrophe
#     is not a real shape this project uses anywhere, and the failure
#     direction (a spurious violation flag on a literal that is, in fact,
#     safe) is the SAFE one to fail toward.
#   - COMMENT STRIPPING is a text pass, not a parser. `prosrc` preserves
#     in-body `--` line comments and `/* ... */` block comments verbatim
#     (measured: migration 058's fn_close_account has a `--` comment reading
#     "set_config(..., is_local => true)" directly above its real call,
#     which the raw text scan matched and mis-flagged before this fence
#     stripped comments first). The strip below is itself a regex, so a
#     `--` or `/*` appearing INSIDE a quoted string literal that itself
#     contains a genuine `set_config(` call could, in a sufficiently
#     adversarial body, be mis-stripped. This is an accepted residual for
#     the same reason as the nested-parentheses case above: a mis-strip
#     changes what the scan sees, it does not manufacture a false CLEAR
#     out of a real violation's own literal shape, and remains far more
#     likely to over-flag than to hide one.
#
# SCHEMA LIST — read LIVE from supabase/config.toml's `[api] schemas`, never
# hardcoded here as a second copy that can drift from the real Data-API
# exposure surface (the same "read live, never pinned" discipline this
# project applies to the §10 ledger and the RT-26 allowlist).
#
# Usage:
#   bash fence-set-config-non-literal.sh <psql-connection-arg>...
# e.g. (matches scripts/db-template-clone.sh's own connection convention):
#   PGPASSWORD=postgres bash fence-set-config-non-literal.sh -h 127.0.0.1 -p 54322 -U postgres -d <scratch-db-name>
#
# Exit codes:
#   0 — clean: no anon/authenticated-EXECUTE function in an exposed schema
#       calls set_config with a non-literal first argument.
#   1 — one or more violations found (fail-closed), OR the catalog query
#       itself failed to run (connection/psql failure — fail-closed on the
#       fence's own dependency, never a silent pass).
#   2 — argument error (no connection args given), OR supabase/config.toml's
#       schemas list could not be read (structural error).

set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "FATAL: missing psql connection args." >&2
  echo "Usage: bash $(basename "$0") <psql-connection-args...>" >&2
  exit 2
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "FATAL: psql is required and is not on PATH. Failing closed." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_TOML="$REPO_ROOT/supabase/config.toml"

if [ ! -f "$CONFIG_TOML" ]; then
  echo "FATAL: $CONFIG_TOML not found — cannot read the [api] schemas list. Failing closed." >&2
  exit 2
fi

SCHEMAS_LINE="$(grep -m1 -E '^schemas[[:space:]]*=' "$CONFIG_TOML" || true)"
if [ -z "$SCHEMAS_LINE" ]; then
  echo "FATAL: no 'schemas = [...]' line found in $CONFIG_TOML under [api] — structural error. Failing closed." >&2
  exit 2
fi

SCHEMA_NAMES="$(echo "$SCHEMAS_LINE" | grep -oE '"[^"]+"' | tr -d '"')"
if [ -z "$SCHEMA_NAMES" ]; then
  echo "FATAL: could not parse any schema name out of: $SCHEMAS_LINE — Failing closed." >&2
  exit 2
fi

PG_ARRAY_ITEMS=""
while IFS= read -r name; do
  [ -z "$name" ] && continue
  esc="${name//\'/\'\'}"
  PG_ARRAY_ITEMS="${PG_ARRAY_ITEMS}'${esc}',"
done <<< "$SCHEMA_NAMES"
PG_ARRAY_ITEMS="${PG_ARRAY_ITEMS%,}"

echo "fence-set-config-non-literal: exposed-schema list from $CONFIG_TOML: $SCHEMA_NAMES" >&2

# NOTE: the SQL is written to a temp file with a plain heredoc redirection,
# then read back via the `$(< file)` builtin — NOT `$(cat <<'EOF' ...)`.
# macOS ships bash 3.2 (GPLv3 avoidance) as /bin/bash, and 3.2 has a known
# heredoc-inside-command-substitution bug: it mis-scans the heredoc body's
# own parens/quotes while looking for the closing `)` of `$(...)`, which
# this SQL's unbalanced-until-closed `(` per CTE and doubled `''` literal
# tripped locally (macOS bash -n: "unexpected EOF while looking for
# matching `''"). Modern bash (CI runners) does not have this bug, but a
# fence that cannot even parse under a stock macOS shell is a portability
# trap for any contributor testing it locally — avoided here at zero cost.
SQL_FILE="$(mktemp)"
trap 'rm -f "$SQL_FILE"' EXIT
cat > "$SQL_FILE" <<'EOSQL'
with target_functions as (
  select
    p.oid,
    n.nspname as schema_name,
    p.proname as function_name,
    p.oid::regprocedure::text as signature,
    -- Strip block comments then line comments before any set_config scan —
    -- prosrc preserves in-body comments verbatim, and a comment merely
    -- MENTIONING set_config( textually (e.g. documenting what a nearby
    -- real call does) is not a call at all. See header "EXPLICITLY NOT
    -- CATCHING" for this pass's own residual.
    --
    -- coalesce(nullif(p.prosrc, ''), pg_get_functiondef(p.oid)) — NOT bare
    -- p.prosrc, and NOT plain coalesce(p.prosrc, ...) either (Sec FLAG,
    -- 2026-09-06; MEASURED CORRECTION 2026-09-06 to the fix's first draft).
    -- A PG14+ SQL-standard-body function (`language sql begin atomic ...
    -- end`) stores its body in `prosqlbody`, not `prosrc` — but MEASURED
    -- under this project's pinned PG17 (a golden fixture of exactly this
    -- shape, tests/fixtures/ci/c3-set-config-violation.sql), `prosrc` for
    -- that function is an EMPTY STRING (length 0), NOT NULL as the first
    -- draft of this fix assumed. Plain `coalesce(p.prosrc, ...)` only
    -- substitutes on NULL, so it would have left this fence exactly as
    -- blind as before the fix while looking fixed — a false-negative fix
    -- for the false-negative this fence exists to catch. `regexp_replace`
    -- and `~*` over an empty string are NOT NULL-propagating (they
    -- evaluate to '' / false, not NULL), so the ORIGINAL silent-pass
    -- mechanism Sec named (NULL propagating through the filter) does not
    -- literally reproduce here either — but the OUTCOME is identical: an
    -- empty clean_src never matches `set_config\(`, so `target_calls`
    -- still excludes the row instead of flagging it. `nullif(p.prosrc,
    -- '')` normalizes empty-string to NULL first, so `coalesce(...,
    -- pg_get_functiondef(p.oid))` actually falls through — verified live
    -- against the fixture, not merely reasoned about.
    regexp_replace(
      regexp_replace(coalesce(nullif(p.prosrc, ''), pg_get_functiondef(p.oid)), '/\*.*?\*/', '', 'g'),
      '--[^\n]*', '', 'g'
    ) as clean_src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = any(array[__SCHEMA_ARRAY__])
    and (
      has_function_privilege('anon', p.oid, 'EXECUTE')
      or has_function_privilege('authenticated', p.oid, 'EXECUTE')
    )
),
target_calls as (
  select * from target_functions where clean_src ~* 'set_config\s*\('
),
calls as (
  select
    tc.schema_name,
    tc.function_name,
    tc.signature,
    btrim((regexp_matches(tc.clean_src, 'set_config\s*\(\s*([^,]*)', 'gi'))[1]) as first_arg
  from target_calls tc
)
select schema_name, function_name, signature, first_arg
from calls
where first_arg !~ '^''[^'']*''$'
order by schema_name, function_name;
EOSQL

SQL_TEMPLATE="$(< "$SQL_FILE")"
SQL="${SQL_TEMPLATE//__SCHEMA_ARRAY__/$PG_ARRAY_ITEMS}"

set +e
OUTPUT="$(psql -X -v ON_ERROR_STOP=1 -Atc "$SQL" -F ' | ' "$@" 2>&1)"
RC=$?
set -e

if [ "$RC" -ne 0 ]; then
  echo "FATAL: catalog query failed against the target database:" >&2
  echo "$OUTPUT" >&2
  echo "Failing closed — a fence that cannot query the catalog must not pass it." >&2
  exit 1
fi

if [ -n "$OUTPUT" ]; then
  echo "VIOLATIONS — anon/authenticated-EXECUTE function(s) in an exposed schema call set_config with a NON-LITERAL first argument (schema | function | signature | first_arg):" >&2
  echo "$OUTPUT" >&2
  echo "" >&2
  echo "A caller-controlled GUC name in a Data-API-reachable function lets an" >&2
  echo "ordinary PostgREST caller set an arbitrary transaction-local setting —" >&2
  echo "including app.nav_computed_for (054/107) or app.report_generation_source" >&2
  echo "(111) — defeating the trust model those trigger/audit checks rely on." >&2
  echo "Failing closed." >&2
  exit 1
fi

echo "fence-set-config-non-literal: clean — no anon/authenticated-EXECUTE function in an exposed schema calls set_config with a non-literal first argument."
exit 0
