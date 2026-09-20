#!/usr/bin/env bash
#
# fence-push-secrets-strikes.sh -- offline strike-proof for
# scripts/push-production-secrets.sh's resource-resolution and secret-
# transport fixes (PR #840). Runs entirely without a live box or
# network: a fake `ssh` (this file generates it) rewrites the
# `/root/.pfin` path the script's remote driver hardcodes to a
# throwaway temp dir, tests/fixtures/ci/push-secrets/fake-curl stands in
# for curl (PATH-shadowed, canned Coolify-API-shaped responses --
# push-production-secrets.sh itself is never modified or made aware
# this exists), and REPO_ROOT is pointed at a fixture directory carrying
# a minimal secrets-manifest.yml + .env (never the real repo files).
#
# WHY THIS FENCE EXISTS
#   MEASURED (team-lead, 2026-09-20): `GET /applications?name=X` on this
#   Coolify (4.3.18) IGNORES the `name` query parameter entirely --
#   `?name=etl`, `?name=app`, `?name=pfin-app` and `?name=does-not-exist`
#   all returned the SAME unfiltered application list. The script's old
#   per-resource query-string lookup, combined with taking the FIRST
#   element off whatever came back, silently resolved every resource
#   name to the SAME wrong uuid -- with the manifest-key-vs-Coolify-name
#   gap compounding it (KNOT 7 in the script's own header), a live
#   `--skip-missing-resource` preflight printed `resolved 'etl' ->
#   <pfin-app's uuid>` for a resource that does not exist. Had --apply
#   run, this would have pushed provider-sync's and ETL's secrets onto
#   the web-app container -- the exact confinement violation
#   secrets-manifest.yml's own PLAID_CLIENT_ID/PLAID_SECRET entries say
#   has NO CI fence. This is that fence.
#
# Six scenarios, all offline:
#   (i) RESOLUTION-CORRECTNESS -- default fixture (pfin-app exists;
#      pfin-back-etl does not), --skip-missing-resource: `pfin-app`
#      resolves to its OWN uuid, `pfin-back-etl` is SKIPPED (never
#      wrongly bound to pfin-app's uuid) -- exit 3 (partial run).
#   (ii) UNMAPPED-MANIFEST-KEY -- a manifest carrying a `production_only`
#      name with no SECRET_RESOURCE_MAP entry -> refuses (exit 2)
#      BEFORE any resource resolution is even attempted.
#   (iii) DUPLICATE-NAMES -- two Coolify applications named `pfin-app` ->
#      refuses (exit 1), never silently picks one.
#   (iv) MISSING-RESOURCE-NO-FLAG -- `pfin-back-etl` absent, NO
#      --skip-missing-resource -> refuses (exit 1), naming it.
#   (v) APPLY-NO-ARGV-LEAK -- a real --apply push of a fixture "secret"
#      value onto `pfin-app` -- greps every logged curl invocation's own
#      argv (never a body FILE's contents) for the fixture's known
#      secret-value string and asserts it is ABSENT, proving the
#      tempfile/--data-binary fix (PR #840 item 3) keeps a real secret
#      value off curl's argv, unlike the reverted shape this scenario's
#      own strike-verify exercises.
#   (vi) CROSS-RESOURCE-UNIQUENESS -- two DIFFERENT resource keys
#      (`pfin-app`, `pfin-back-etl`) resolving to the SAME uuid, each
#      individually unambiguous -> refuses (exit 1), naming both keys
#      and the shared uuid. Distinct from (iii): that scenario is ONE
#      name matching TWO applications; this one is TWO names matching
#      ONE application -- structurally the live incident's own shape.
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/push-secrets"
PUSH_SECRETS_SH="$REPO_ROOT/scripts/push-production-secrets.sh"

[[ -x "$FIXTURE_DIR/fake-curl" ]] || { echo "FATAL: $FIXTURE_DIR/fake-curl missing or not executable" >&2; exit 2; }
[[ -f "$PUSH_SECRETS_SH" ]] || { echo "FATAL: $PUSH_SECRETS_SH not found" >&2; exit 2; }
[[ -f "$FIXTURE_DIR/repo-root/secrets-manifest.yml" ]] || { echo "FATAL: fixture repo-root/secrets-manifest.yml missing" >&2; exit 2; }
[[ -f "$FIXTURE_DIR/repo-root-unmapped/secrets-manifest.yml" ]] || { echo "FATAL: fixture repo-root-unmapped/secrets-manifest.yml missing" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_TOKEN="fake-coolify-token-$(date +%s)-do-not-leak"
FAKE_ROOT_PFIN="$WORK/fakebox/root/pfin"
mkdir -p "$FAKE_ROOT_PFIN"
printf 'COOLIFY_API_TOKEN=%s\n' "$FAKE_TOKEN" > "$FAKE_ROOT_PFIN/coolify.env"

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
ln -s "$FIXTURE_DIR/fake-curl" "$FAKE_BIN/curl"

# Same fake `ssh` shape as the fence-provision-app-strikes.sh /
# fence-deploy-app-strikes.sh siblings -- see either file's own header
# for the call-shape rationale. push-production-secrets.sh uses THREE of
# the four shapes: the reachability/coolify.env probes (exact-match),
# the resolution api()'s bare `TOKEN=...; curl ...` command string (the
# plain-command fallback), the seed-file `cat > $box_seed < seed_path`
# write (also the plain-command fallback -- stdin passes through
# untouched, no explicit redirection needed), and the push step's own
# `env box_seed=... uuid=... bash -s` heredoc.
cat > "$FAKE_BIN/ssh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
LAST_PROBE="\${@: -1}"
if [[ "\$LAST_PROBE" == "true" ]]; then
  exit 0
fi
if [[ "\$*" == *"test -s /root/.pfin/coolify.env"* ]]; then
  exit 0
fi
LAST="\${@: -1}"
if [[ "\$LAST" == "-s" || "\$LAST" == *" bash -s" ]]; then
  CMDLINE="\$LAST"
  [[ "\$CMDLINE" == "-s" ]] && CMDLINE="bash -s"
  # push-production-secrets.sh's own push step passes env
  # box_seed="/root/.pfin/..." uuid="..." bash -s -- the /root/.pfin
  # path is embedded in THIS command-line prefix (an env VAR=value
  # assignment), not only in the heredoc body below it. Rewrite BOTH or
  # the remote python's open(seed_file) call looks for a path this
  # fence never wrote anything to. NOTE: no backtick characters in this
  # comment block -- this heredoc is UNQUOTED (<<EOF), so a literal
  # backtick pair here would trigger command substitution AT WRITE
  # TIME, silently splicing arbitrary command output into the generated
  # ssh script (measured: a stray backtick pair here once spliced a
  # full environment dump into this exact generated file).
  CMDLINE="\$(printf '%s' "\$CMDLINE" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
  REWRITTEN="\$(sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
  PATH="$FAKE_BIN:\$PATH" FAKE_CURL_LOG="\$FAKE_CURL_LOG" FAKE_CURL_MODE="\$FAKE_CURL_MODE" \\
    bash -c "\$CMDLINE" <<< "\$REWRITTEN"
  exit \$?
fi
CMD="\${@: -1}"
CMD_REWRITTEN="\$(printf '%s' "\$CMD" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
PATH="$FAKE_BIN:\$PATH" FAKE_CURL_LOG="\$FAKE_CURL_LOG" FAKE_CURL_MODE="\$FAKE_CURL_MODE" \\
  bash -c "\$CMD_REWRITTEN"
EOF
chmod +x "$FAKE_BIN/ssh"

run_scenario() {
  # <desc> <expect_exit> <mode> <repo_root> <log_path> [script args...]
  # log_path is CALLER-PROVIDED (never generated here) so the caller can
  # read it back afterward for scenario (v)'s own argv-leak check --
  # simpler and less fragile than smuggling the path back through stdout.
  local desc="$1" expect_exit="$2" mode="$3" repo_root="$4" log="$5"; shift 5
  : > "$log"
  set +e
  BOX_IP=127.0.0.1 AUTOMATION_KEY=/dev/null REPO_ROOT="$repo_root" \
    PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$log" FAKE_CURL_MODE="$mode" \
    bash "$PUSH_SECRETS_SH" "$@" < /dev/null > "$WORK/out.$$" 2>&1
  local rc=$?
  set -e

  if [[ "$rc" != "$expect_exit" ]]; then
    echo "FAIL: [$desc] expected exit $expect_exit, got $rc" >&2
    echo "----- captured output -----" >&2
    cat "$WORK/out.$$" >&2
    return 1
  fi

  if grep -qF "$FAKE_TOKEN" "$log" 2>/dev/null; then
    echo "FAIL: [$desc] the fake Coolify API token leaked into a curl invocation's own argv:" >&2
    grep -F "$FAKE_TOKEN" "$log" >&2
    return 1
  fi

  echo "OK: [$desc] exit $rc as expected, token absent from every logged curl argv." >&2
  cat "$WORK/out.$$"
  return 0
}

assert_output_contains() {
  local desc="$1" out="$2" needle="$3"
  if [[ -z "$out" ]]; then
    echo "FAIL: [$desc] produced no captured output to inspect (run_scenario itself already failed above)." >&2
    return 1
  fi
  if ! grep -qF "$needle" <<<"$out"; then
    echo "FAIL: [$desc] did not contain expected text '$needle'." >&2
    return 1
  fi
  return 0
}

assert_output_lacks() {
  local desc="$1" out="$2" needle="$3"
  if [[ -n "$out" ]] && grep -qF "$needle" <<<"$out"; then
    echo "FAIL: [$desc] output wrongly contains '$needle'." >&2
    return 1
  fi
  return 0
}

FAIL=0
CLEAN_ROOT="$FIXTURE_DIR/repo-root"
UNMAPPED_ROOT="$FIXTURE_DIR/repo-root-unmapped"

# (i) RESOLUTION-CORRECTNESS -- pfin-app resolves to its own uuid,
#     pfin-back-etl (absent) is SKIPPED, never wrongly bound to
#     pfin-app's uuid. Preflight (no --apply), --skip-missing-resource.
LOG_I="$WORK/log-i"
OUT_I="$(run_scenario "resolution-correctness" 3 clean "$CLEAN_ROOT" "$LOG_I" --skip-missing-resource)" || FAIL=1
assert_output_contains "resolution-correctness" "${OUT_I:-}" "resolved 'pfin-app' -> 1111aaaa2222bbbb3333cccc" || FAIL=1
assert_output_contains "resolution-correctness" "${OUT_I:-}" "SKIPPING 'pfin-back-etl'" || FAIL=1
assert_output_lacks "resolution-correctness" "${OUT_I:-}" "resolved 'pfin-back-etl' -> 1111aaaa2222bbbb3333cccc" || FAIL=1

# (ii) UNMAPPED-MANIFEST-KEY -- refuses (exit 2) before any resolution.
LOG_II="$WORK/log-ii"
OUT_II="$(run_scenario "unmapped-manifest-key" 2 clean "$UNMAPPED_ROOT" "$LOG_II" --skip-missing-resource)" || FAIL=1
assert_output_contains "unmapped-manifest-key" "${OUT_II:-}" "FAKE_UNMAPPED_SECRET_NAME" || FAIL=1
assert_output_lacks "unmapped-manifest-key" "${OUT_II:-}" "resolved '" || FAIL=1

# (iii) DUPLICATE-NAMES -- two applications named pfin-app -> refuses,
#      never silently picks one.
LOG_III="$WORK/log-iii"
OUT_III="$(run_scenario "duplicate-names" 1 duplicate "$CLEAN_ROOT" "$LOG_III" --skip-missing-resource)" || FAIL=1
assert_output_contains "duplicate-names" "${OUT_III:-}" "multiple Coolify applications named 'pfin-app'" || FAIL=1

# (iv) MISSING-RESOURCE-NO-FLAG -- pfin-back-etl absent, no
#      --skip-missing-resource -> refuses, naming it.
LOG_IV="$WORK/log-iv"
OUT_IV="$(run_scenario "missing-resource-no-flag" 1 clean "$CLEAN_ROOT" "$LOG_IV")" || FAIL=1
assert_output_contains "missing-resource-no-flag" "${OUT_IV:-}" "no Coolify resource named 'pfin-back-etl'" || FAIL=1

# (v) APPLY-NO-ARGV-LEAK -- a real --apply push; the fixture's own known
#     secret-value string must never appear in any logged curl argv.
LOG_V="$WORK/log-v"
OUT_V="$(run_scenario "apply-no-argv-leak" 3 clean "$CLEAN_ROOT" "$LOG_V" --apply --skip-missing-resource)" || FAIL=1
assert_output_contains "apply-no-argv-leak" "${OUT_V:-}" "pushed to 'pfin-app'" || FAIL=1
if [[ -f "$LOG_V" ]] && grep -qF "FIXTURE-DO-NOT-LEAK" "$LOG_V" 2>/dev/null; then
  echo "FAIL: [apply-no-argv-leak] the fixture secret value leaked into a logged curl invocation's own argv:" >&2
  grep -F "FIXTURE-DO-NOT-LEAK" "$LOG_V" >&2
  FAIL=1
fi
if grep -qF "FIXTURE-DO-NOT-LEAK" <<<"${OUT_V:-}" 2>/dev/null; then
  echo "FAIL: [apply-no-argv-leak] the fixture secret value leaked into the script's own printed output." >&2
  FAIL=1
fi

# (vi) CROSS-RESOURCE-UNIQUENESS -- Sec AC (PR #840 review, 2026-09-20):
#     uniqueness must hold over the RESOLVED SET, not only per individual
#     lookup. fake-curl's "collision" mode returns `pfin-app` (the `app`
#     key's real name) and `pfin-back-etl` (the `etl` key's real name) as
#     TWO DIFFERENT applications sharing ONE uuid -- each lookup is
#     individually unambiguous (exactly one match each), so scenario
#     (iii)'s own per-lookup ambiguity check would NOT catch this; only
#     the cross-resource check added in this same PR does. This is
#     structurally the exact shape of the original live incident (every
#     resource key resolving to the same wrong uuid) -- must refuse,
#     naming both resource keys and the shared uuid.
LOG_VI="$WORK/log-vi"
OUT_VI="$(run_scenario "cross-resource-uniqueness" 1 collision "$CLEAN_ROOT" "$LOG_VI" --skip-missing-resource)" || FAIL=1
assert_output_contains "cross-resource-uniqueness" "${OUT_VI:-}" "all resolved to the SAME Coolify application" || FAIL=1
assert_output_contains "cross-resource-uniqueness" "${OUT_VI:-}" "'pfin-app'" || FAIL=1
assert_output_contains "cross-resource-uniqueness" "${OUT_VI:-}" "'pfin-back-etl'" || FAIL=1
if [[ -n "${OUT_VI:-}" ]] && ! grep -qF "1111aaaa2222bbbb3333cccc" <<<"$OUT_VI"; then
  echo "FAIL: [cross-resource-uniqueness] refusal did not name the shared uuid." >&2
  FAIL=1
fi

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more push-production-secrets.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all push-production-secrets.sh strike-proofs passed."
exit 0
