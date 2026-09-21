#!/usr/bin/env bash
#
# fence-mint-jwt-boxip-strikes.sh -- offline strike-proof for ONE guard
# in scripts/mint-supabase-jwt-keys.sh: BOX_IP is required, never
# defaulted (team-lead, provision.sh --dry-run follow-up, 2026-09-20).
#
# WHY THIS EXISTS -- this script used to carry a hardcoded
# `${BOX_IP:-188.245.166.206}` fallback, the EXACT silent-fall-through-
# to-prod shape the 2026-09-11 incident already fixed everywhere else in
# this repo (see provision-supabase-stack.sh's own header). It stayed
# masked because scripts/provision.sh's own run_mint_jwt() never passed
# BOX_IP through either -- every orchestrated run silently relied on
# this default, which happened to equal the real prod box's IP, so it
# "worked" by accident. Found sweeping provision.sh's own BOX_IP-passing
# mechanism for the D-1 defect (live --dry-run, 2026-09-20); fixed the
# same way every sibling script already was: no default, refuse loud.
#
# ⚠ NARROW, SINGLE-GUARD FENCE -- no strike-proof for the REST of
# mint-supabase-jwt-keys.sh exists (this script has none before this
# PR); building one is a separate, larger undertaking out of scope here.
# This fence proves exactly the one guard this PR added. The guard fires
# BEFORE any network call (before the first `sshx true`), so no
# curl/docker mocking is needed to prove scenario 1; a fake `ssh` is
# still installed so scenario 2 (BOX_IP present) fails FAST at the
# script's own NEXT real check instead of hanging on a real connection
# attempt to whatever IP the fence happens to pass.
#
# Scenarios:
#   1. BOX_IP-ABSENT-REFUSES -- BOX_IP unset -> exit 1, "BOX_IP is
#      required, not defaulted" -- proves the guard fires.
#   2. BOX_IP-PRESENT-PROCEEDS -- BOX_IP set -> that message never
#      appears; the script proceeds past this guard to its own next
#      real check instead (box-reachability over the fake ssh, which
#      always fails -> the script's own "not reachable over SSH"
#      message) -- proves the BOX_IP guard specifically did not fire,
#      isolating it from every other reason this script can fail.
#
# Exit 0 only if both scenarios behave exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_SH="$REPO_ROOT/scripts/mint-supabase-jwt-keys.sh"
[[ -f "$TARGET_SH" ]] || { echo "FATAL: $TARGET_SH not found" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/ssh" <<'EOF'
#!/usr/bin/env bash
# Fails fast. The real script's own sshx() wraps this first call in its
# OWN `>/dev/null 2>&1`, so this fake's stderr is discarded before the
# fence ever sees it -- what the fence actually asserts on is the real
# script's OWN die() message one level up ("box at ... not reachable
# over SSH ... run scripts/provision-vps.sh first"), which fires because
# this fake always exits non-zero.
exit 255
EOF
chmod +x "$FAKE_BIN/ssh"

FAIL=0

run_case() {
  # run_case <desc> <expect_exit> <box_ip-or-empty-for-unset>
  local desc="$1" expect_exit="$2" box_ip="$3"
  local out="$WORK/out.$$.$RANDOM"
  set +e
  if [[ -n "$box_ip" ]]; then
    PATH="$FAKE_BIN:$PATH" BOX_IP="$box_ip" bash "$TARGET_SH" > "$out" 2>&1
  else
    PATH="$FAKE_BIN:$PATH" env -u BOX_IP bash "$TARGET_SH" > "$out" 2>&1
  fi
  local rc=$?
  set -e
  if [[ "$rc" != "$expect_exit" ]]; then
    echo "FAIL: [$desc] expected exit $expect_exit, got $rc" >&2
    cat "$out" >&2
    FAIL=1
  else
    echo "OK: [$desc] exit $rc as expected." >&2
  fi
  cat "$out"
  return 0
}

OUT1="$(run_case "box-ip-absent-refuses" 1 "")"
if ! printf '%s' "$OUT1" | grep -qF "BOX_IP is required, not defaulted"; then
  echo "FAIL: [box-ip-absent-refuses] did not print the required-not-defaulted message" >&2
  printf '%s\n' "$OUT1" >&2
  FAIL=1
fi

OUT2="$(run_case "box-ip-present-proceeds" 1 "127.0.0.1")"
if printf '%s' "$OUT2" | grep -qF "BOX_IP is required, not defaulted"; then
  echo "FAIL: [box-ip-present-proceeds] the BOX_IP guard fired even though BOX_IP was set" >&2
  FAIL=1
fi
if ! printf '%s' "$OUT2" | grep -qF "not reachable over SSH"; then
  echo "FAIL: [box-ip-present-proceeds] never reached the script's own next real check (box-reachability, against the fake ssh) -- something else blocked it before the BOX_IP guard could be isolated" >&2
  printf '%s\n' "$OUT2" >&2
  FAIL=1
fi

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: mint-supabase-jwt-keys.sh's BOX_IP guard did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: mint-supabase-jwt-keys.sh BOX_IP guard strike-proof passed."
exit 0
