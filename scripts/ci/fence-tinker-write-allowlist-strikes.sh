#!/usr/bin/env bash
#
# fence-tinker-write-allowlist-strikes.sh -- offline golden-test battery
# for fence-tinker-write-allowlist.sh, per this role's own standing rule:
# every fence proposal ships the catch criterion AND the fixture proving
# it catches what it claims. The five legs Sec asked to see fire, plus
# the sixth (F-6 control leg) added when Sec's review found the earlier
# file-wide unresolvable-site exemption fail-open, were golden-tested by
# hand during development but never captured as a checked-in, repeatable
# test -- this file closes that gap.
#
# Runs the REAL fence script (never a re-implementation of its detection
# logic -- "the fake restates the lie" is the exact failure mode a
# duplicated-logic fixture risks) against disposable scratch trees, via
# the FENCE_TINKER_ALLOWLIST_{SCRIPTS_DIR,FILE,PIN_FILE} overrides that
# exist ONLY for this purpose (see the fence's own header). Never
# touches the real scripts/ tree or the real allowlist/pin.
#
# Six scenarios:
#   1. CLEAN       -- one write-verb site + one unresolvable site, both
#                      correctly marked and allowlisted -- exit 0.
#   2. UNMARKED     -- an independent, unmarked write-verb line -- exit 1,
#                      "unmarked tinker write".
#   3. DUPLICATE    -- the same marker ID consumed by two sites -- exit 1,
#                      "DUPLICATE marker".
#   4. STALE-PIN    -- allowlist .txt edited without regenerating its
#                      .sha256 -- exit 2, pin mismatch FATAL.
#   5. UNRESOLVABLE -- a write moved entirely into a bash variable, no
#                      write-verb text anywhere in the file, no marker --
#                      exit 1, via the unresolvable-body path specifically
#                      (asserted by message text, not just exit code).
#   6. F-6 CONTROL  -- one bound unresolvable site correctly exempts its
#                      nearest write verb, but a SECOND, unrelated write
#                      verb in the same file is left unmarked -- must
#                      still be exit 1 ("unmarked tinker write"), proving
#                      the 1:1 fix (not file-wide) is what's running.
#
# Exit 0 only if all six scenarios behave as expected.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FENCE="$REPO_ROOT/scripts/ci/fence-tinker-write-allowlist.sh"
[[ -x "$FENCE" ]] || { echo "FATAL: $FENCE missing or not executable" >&2; exit 2; }

FAIL=0
pass() { printf '  \033[32mok\033[0m  %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*" >&2; FAIL=1; }

pin_for() {
  # $1 = file to pin
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

run_fence() {
  # $1 = scratch scripts dir, $2 = allowlist file, $3 = pin file
  local out rc
  out="$(FENCE_TINKER_ALLOWLIST_SCRIPTS_DIR="$1" \
         FENCE_TINKER_ALLOWLIST_FILE="$2" \
         FENCE_TINKER_ALLOWLIST_PIN_FILE="$3" \
         bash "$FENCE" 2>&1)" && rc=0 || rc=$?
  printf '%s\n%s\n' "$rc" "$out"
}

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# --- Scenario 1: CLEAN ------------------------------------------------
step1() {
  local dir="$SCRATCH/1-clean"
  mkdir -p "$dir"
  cat > "$dir/direct.sh" <<'EOF'
#!/usr/bin/env bash
# /* TINKER-WRITE-ALLOW-01 */
docker exec coolify php artisan tinker --execute='$app->fqdn = null; $app->save();'
EOF
  cat > "$dir/indirect.sh" <<'EOF'
#!/usr/bin/env bash
SCRIPT_CONTENT="$(cat body.php)"
# /* TINKER-WRITE-ALLOW-02 */
ssh box 'docker exec coolify php artisan tinker --execute="$SCRIPT_CONTENT"'
EOF
  local allow="$dir/allow.txt" pin="$dir/allow.sha256"
  printf 'TINKER-WRITE-ALLOW-01 direct write\nTINKER-WRITE-ALLOW-02 indirect write\n' > "$allow"
  pin_for "$allow" > "$pin"
  local result rc out
  result="$(run_fence "$dir" "$allow" "$pin")"
  rc="$(sed -n '1p' <<<"$result")"; out="$(tail -n +2 <<<"$result")"
  if [[ "$rc" == "0" ]]; then
    pass "1-CLEAN: exit 0 as expected"
  else
    fail "1-CLEAN: expected exit 0, got $rc -- $out"
  fi
}

# --- Scenario 2: UNMARKED ----------------------------------------------
step2() {
  local dir="$SCRATCH/2-unmarked"
  mkdir -p "$dir"
  cat > "$dir/unmarked.sh" <<'EOF'
#!/usr/bin/env bash
docker exec coolify php artisan tinker --execute='$app->fqdn = null; $app->save();'
EOF
  local allow="$dir/allow.txt" pin="$dir/allow.sha256"
  : > "$allow"
  pin_for "$allow" > "$pin"
  local result rc out
  result="$(run_fence "$dir" "$allow" "$pin")"
  rc="$(sed -n '1p' <<<"$result")"; out="$(tail -n +2 <<<"$result")"
  if [[ "$rc" != "0" ]] && grep -q "unmarked tinker write" <<<"$out"; then
    pass "2-UNMARKED: reddened with 'unmarked tinker write'"
  else
    fail "2-UNMARKED: expected non-zero + 'unmarked tinker write', got rc=$rc -- $out"
  fi
}

# --- Scenario 3: DUPLICATE ----------------------------------------------
step3() {
  local dir="$SCRATCH/3-duplicate"
  mkdir -p "$dir"
  cat > "$dir/site-a.sh" <<'EOF'
#!/usr/bin/env bash
# /* TINKER-WRITE-ALLOW-01 */
docker exec coolify php artisan tinker --execute='$app->fqdn = null; $app->save();'
EOF
  cat > "$dir/site-b.sh" <<'EOF'
#!/usr/bin/env bash
# /* TINKER-WRITE-ALLOW-01 */
docker exec coolify php artisan tinker --execute='$other->ports = null; $other->save();'
EOF
  local allow="$dir/allow.txt" pin="$dir/allow.sha256"
  printf 'TINKER-WRITE-ALLOW-01 copy-pasted onto two sites\n' > "$allow"
  pin_for "$allow" > "$pin"
  local result rc out
  result="$(run_fence "$dir" "$allow" "$pin")"
  rc="$(sed -n '1p' <<<"$result")"; out="$(tail -n +2 <<<"$result")"
  if [[ "$rc" != "0" ]] && grep -q "DUPLICATE marker" <<<"$out"; then
    pass "3-DUPLICATE: reddened with 'DUPLICATE marker'"
  else
    fail "3-DUPLICATE: expected non-zero + 'DUPLICATE marker', got rc=$rc -- $out"
  fi
}

# --- Scenario 4: STALE-PIN ----------------------------------------------
step4() {
  local dir="$SCRATCH/4-stale-pin"
  mkdir -p "$dir"
  cat > "$dir/direct.sh" <<'EOF'
#!/usr/bin/env bash
# /* TINKER-WRITE-ALLOW-01 */
docker exec coolify php artisan tinker --execute='$app->fqdn = null; $app->save();'
EOF
  local allow="$dir/allow.txt" pin="$dir/allow.sha256"
  printf 'TINKER-WRITE-ALLOW-01 direct write\n' > "$allow"
  pin_for "$allow" > "$pin"
  # Edit the allowlist AFTER pinning -- the pin now describes stale content.
  printf 'TINKER-WRITE-ALLOW-01 direct write\nTINKER-WRITE-ALLOW-99 unreviewed addition\n' > "$allow"
  local result rc out
  result="$(run_fence "$dir" "$allow" "$pin")"
  rc="$(sed -n '1p' <<<"$result")"; out="$(tail -n +2 <<<"$result")"
  if [[ "$rc" == "2" ]] && grep -q "does not match the pinned hash" <<<"$out"; then
    pass "4-STALE-PIN: FATAL exit 2, pin-mismatch message present"
  else
    fail "4-STALE-PIN: expected exit 2 + pin-mismatch message, got rc=$rc -- $out"
  fi
}

# --- Scenario 5: UNRESOLVABLE (no write-verb text anywhere) -------------
step5() {
  local dir="$SCRATCH/5-unresolvable"
  mkdir -p "$dir"
  cat > "$dir/indirect-only.sh" <<'EOF'
#!/usr/bin/env bash
BODY="$(cat body.php)"
ssh box 'docker exec coolify php artisan tinker --execute="$BODY"'
EOF
  local allow="$dir/allow.txt" pin="$dir/allow.sha256"
  : > "$allow"
  pin_for "$allow" > "$pin"
  local result rc out
  result="$(run_fence "$dir" "$allow" "$pin")"
  rc="$(sed -n '1p' <<<"$result")"; out="$(tail -n +2 <<<"$result")"
  if [[ "$rc" != "0" ]] && grep -q "statically unresolvable" <<<"$out"; then
    pass "5-UNRESOLVABLE: reddened via the unresolvable-body path specifically"
  else
    fail "5-UNRESOLVABLE: expected non-zero + 'statically unresolvable', got rc=$rc -- $out"
  fi
}

# --- Scenario 6: F-6 CONTROL (1:1, not file-wide, exemption) ------------
step6() {
  local dir="$SCRATCH/6-f6-control"
  mkdir -p "$dir"
  # One bound unresolvable site (nearest write below it gets exempted),
  # PLUS a second, unrelated write verb further down in the SAME file
  # that carries NO marker of its own. Under the old file-wide rule this
  # entire file would have gone green. Under the 1:1 fix, only the
  # nearest write is exempted -- the second must still redden.
  cat > "$dir/two-writes-one-indirect.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'PHPBODY' > /tmp/body.php
$row->save();
PHPBODY
SCRIPT_CONTENT="$(cat /tmp/body.php)"
# /* TINKER-WRITE-ALLOW-06 */
ssh box 'docker exec coolify php artisan tinker --execute="$SCRIPT_CONTENT"'

# unrelated second write, no marker anywhere near it -- must NOT be
# silently covered by the exemption above.
some_other_function() {
  docker exec coolify php artisan tinker --execute='$widget->status = "off"; $widget->save();'
}
EOF
  local allow="$dir/allow.txt" pin="$dir/allow.sha256"
  printf 'TINKER-WRITE-ALLOW-06 indirect write, one of two in this file\n' > "$allow"
  pin_for "$allow" > "$pin"
  local result rc out
  result="$(run_fence "$dir" "$allow" "$pin")"
  rc="$(sed -n '1p' <<<"$result")"; out="$(tail -n +2 <<<"$result")"
  if [[ "$rc" != "0" ]] && grep -q "unmarked tinker write" <<<"$out"; then
    pass "6-F6-CONTROL: second write in the same file reddened -- 1:1 exemption confirmed, not file-wide"
  else
    fail "6-F6-CONTROL: expected non-zero + 'unmarked tinker write' for the SECOND write, got rc=$rc -- $out"
  fi
}

echo "fence-tinker-write-allowlist-strikes: 6 scenarios"
step1
step2
step3
step4
step5
step6

if [[ "$FAIL" -ne 0 ]]; then
  echo "FAIL: one or more scenarios did not behave as expected." >&2
  exit 1
fi
echo "OK: [fence-tinker-write-allowlist-strikes] all 6 scenarios behaved as expected."
exit 0
