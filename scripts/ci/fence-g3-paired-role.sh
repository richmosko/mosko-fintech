#!/usr/bin/env bash
#
# fence-g3-paired-role — pfin-lane ownership-pair config-lint over a directory of
# Supabase migrations. Sec-mandated at the PR #784 review (2026-09-16, B-2):
# "describing a fence is not building one, and this is the PR that lands the
# convention on 114 files. Until it exists, nothing stops file 120 from omitting
# the pair."
#
# Anchors:
#   - ADR-072 Amendment 5, Decision G3 (the one-time sweep) and Decision F1 as
#     CORRECTED BY DECISION J (which mechanism is refused, and why).
#   - Sec §3 widening: strip comments on EVERY leg, and assert EXACT COUNTS,
#     never presence. A naive `--.*$` strip also truncates a line whose STRING
#     LITERAL contains `--`, which can hide a later hit on that line; an
#     exact-count predicate goes RED on such a truncation, a presence predicate
#     goes green. That is why every leg below counts.
#   - OWN sentinel-free directory target. This fence lints a DIRECTORY, not a
#     manifest, so it carries no sentinel line; its fail-closed guards are the
#     structural ones below (non-empty corpus, both lanes non-empty).
#
# ┌─ WHAT THIS FENCE ENFORCES ──────────────────────────────────────────────────┐
# │ Every migration in the PFIN LANE must open with `set role pfin_owner;` as   │
# │ its first executable statement and close with `reset role;` as its last, so │
# │ every object it creates is owned by pfin_owner WHICHEVER identity applies    │
# │ the file. Files in the SUPERVISED LANE must carry NEITHER, because           │
# │ pfin_owner holds no CREATEROLE and no ADMIN OPTION and their own statements  │
# │ would fail under it.                                                         │
# │                                                                              │
# │ LANE IS DERIVED FROM CONTENT, NEVER FROM A FILENAME LIST. A hard-coded list  │
# │ rots the moment a file is added or renamed, and it rots SILENTLY in the      │
# │ permissive direction: a new role-lane file not on the list would be required │
# │ to carry a pair it cannot execute, and — worse — a renamed pfin-lane file    │
# │ would be exempted from carrying one. A file is SUPERVISED iff its            │
# │ comment-stripped body contains an executable role-graph statement.           │
# └──────────────────────────────────────────────────────────────────────────────┘
#
# ⚠ THE `set local role` LEG AND ITS RED MESSAGE — Sec's explicit requirement.
# Do NOT reword the RED below to say that variant "silently does nothing". That
# was Decision F1's original claim and DECISION J MEASURED IT FALSE: it emits
# WARNING 25P01 and STILL TAKES EFFECT, because the CLI sends a migration file as
# one multi-statement query which Postgres runs in an implicit transaction. A RED
# that states the wrong mechanism dictates the wrong repair — the operator who
# reads it will "fix" the fence rather than the file.
#
# Hermetic: reads files only. No network, no database, no secrets.
set -uo pipefail

DIR="${1:-supabase/migrations}"

fail=0
red() { printf 'RED  %s\n' "$*"; fail=1; }
fatal() { printf 'FATAL: %s\n' "$*" >&2; exit 1; }

[ -d "$DIR" ] || fatal "target directory does not exist: $DIR"

shopt -s nullglob
files=("$DIR"/*.sql)
[ "${#files[@]}" -gt 0 ] || fatal "no .sql files under $DIR — a fence over an empty corpus is vacuous and passes everything"

# Comment-strip: drop lines whose first non-space characters are `--`.
strip() { sed -e 's/^[[:space:]]*--.*$//' "$1"; }

pfin_lane=0
supervised_lane=0

for f in "${files[@]}"; do
  body="$(strip "$f")"

  # ---- lane detection, content-derived ----
  # A role-graph statement counts only where it can EXECUTE:
  #   · `create/drop/alter role` and `grant <app_role> to` — anchored at STATEMENT
  #     START (line start after optional indent), because the same words appear as
  #     PROSE inside `comment on ...` string literals. Measured: 060 carries
  #     "ALTER ROLE ... SET timezone" mid-sentence inside a catalog comment and is
  #     a pfin-lane file; an unanchored predicate mis-classifies it and would then
  #     demand it DROP a pair it correctly carries.
  #   · `comment on role` — matched ANYWHERE outside a `--` line, because the
  #     role-lane guards issue it via `execute format('comment on role ... %L')`,
  #     i.e. inside a literal, and anchoring would miss 117/119 entirely.
  # ⚠ The two halves use DIFFERENT anchoring on purpose. Unifying them breaks one
  #   direction or the other: anchor both and 117/119 escape the supervised lane;
  #   anchor neither and 060 is dragged into it.
  if printf '%s\n' "$body" | grep -qiE '^[[:space:]]*(create|drop|alter)[[:space:]]+role[[:space:]]|^[[:space:]]*grant[[:space:]]+(service_role|authenticated|anon)[[:space:]]+to[[:space:]]|comment[[:space:]]+on[[:space:]]+role[[:space:]]'; then
    lane=supervised; supervised_lane=$((supervised_lane+1))
  else
    lane=pfin; pfin_lane=$((pfin_lane+1))
  fi

  n_open="$(printf '%s\n' "$body" | grep -cE '^[[:space:]]*set[[:space:]]+role[[:space:]]+pfin_owner[[:space:]]*;[[:space:]]*$')"
  n_close="$(printf '%s\n' "$body" | grep -cE '^[[:space:]]*reset[[:space:]]+role[[:space:]]*;[[:space:]]*$')"
  n_local="$(printf '%s\n' "$body" | grep -cE '^[[:space:]]*set[[:space:]]+local[[:space:]]+role[[:space:]]')"

  # ---- LEG (d): the transaction-scoped variant, in EITHER lane ----
  if [ "$n_local" -ne 0 ]; then
    red "$f: uses the transaction-scoped role statement ($n_local occurrence(s)). Use the SESSION-scoped pair instead. REASON (ADR-072 Amendment 5 Decision J, measured): that variant emits WARNING 25P01 and STILL TAKES EFFECT — it is NOT a no-op. It is refused because (i) it warns on every apply, and this project uses RAISE WARNING as a real control in the role-lane guards, so drowning that channel attacks the fences it sits beside; and (ii) its correctness depends on the CLI batching a file into one implicit transaction, an undocumented detail whose change would land ownership wrong SILENTLY. The engine backstop (migrator holds no CREATE on schema pfin) is what turns that silent path into a loud 42501."
  fi

  if [ "$lane" = supervised ]; then
    # ---- supervised lane: must carry NEITHER half ----
    if [ "$n_open" -ne 0 ] || [ "$n_close" -ne 0 ]; then
      red "$f: SUPERVISED-lane file (it carries an executable role-graph statement) must carry NEITHER half of the ownership pair; found opener=$n_open closer=$n_close. pfin_owner holds no CREATEROLE and no ADMIN OPTION, so its own statements would fail under that role."
    fi
    continue
  fi

  # ---- pfin lane: LEG (a) exact counts ----
  if [ "$n_open" -ne 1 ] || [ "$n_close" -ne 1 ]; then
    red "$f: PFIN-lane file must carry EXACTLY ONE opener and EXACTLY ONE closer (comment-stripped); found opener=$n_open closer=$n_close. Exact counts, never presence: a comment-strip that truncates a line whose string literal contains a double dash would hide a hit, and only an exact count goes RED on that."
    continue
  fi

  # ---- LEG (b)/(c): position. Opener FIRST, closer LAST. ----
  first="$(printf '%s\n' "$body" | grep -nE '[^[:space:]]' | head -1 | cut -d: -f1)"
  last="$(printf '%s\n' "$body"  | grep -nE '[^[:space:]]' | tail -1 | cut -d: -f1)"
  o_at="$(printf '%s\n' "$body" | grep -nE '^[[:space:]]*set[[:space:]]+role[[:space:]]+pfin_owner[[:space:]]*;[[:space:]]*$' | cut -d: -f1)"
  c_at="$(printf '%s\n' "$body" | grep -nE '^[[:space:]]*reset[[:space:]]+role[[:space:]]*;[[:space:]]*$' | cut -d: -f1)"

  [ "$o_at" = "$first" ] || red "$f: the opener is not the FIRST executable statement (opener at line $o_at, first executable at $first). Anything executing before it runs as the applying identity and lands mis-owned."
  [ "$c_at" = "$last" ]  || red "$f: the closer is not the LAST statement (closer at line $c_at, last executable at $last). NOTHING may follow it: the CLI writes its ledger row on this same session immediately after the file, as migrator, and pfin_owner cannot write supabase_migrations — a statement after the closer either breaks the ledger INSERT or silently creates a mis-owned object."
done

# ---- fail-closed structural guards: a fence that lints nothing passes everything ----
[ "$pfin_lane" -gt 0 ] || fatal "no PFIN-lane files found under $DIR — every file classified supervised. Either the corpus is wrong or the lane predicate is broken; refusing to pass vacuously."
[ "$supervised_lane" -gt 0 ] || printf 'NOTE: no supervised-lane files in %s (expected for a fixture corpus; the real set has four).\n' "$DIR"

if [ "$fail" -ne 0 ]; then
  printf '\nfence-g3-paired-role: FAIL (%d pfin-lane, %d supervised-lane files scanned)\n' "$pfin_lane" "$supervised_lane"
  exit 1
fi
printf 'fence-g3-paired-role: OK (%d pfin-lane, %d supervised-lane files scanned)\n' "$pfin_lane" "$supervised_lane"
exit 0
