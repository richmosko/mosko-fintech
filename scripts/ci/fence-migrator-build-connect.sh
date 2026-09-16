#!/usr/bin/env bash
#
# fence-migrator-build-connect.sh — CI build+connect fence for the migrator
# image (infra/supabase/migrator/Dockerfile), per BACKLOG §7.36 item 21's
# Sec-escalated CONDITION (Sec joint-review of PR #755 at 9a08a7ff).
#
# WHAT THIS CATCHES: the migrator image was, until this fence, built nowhere
# in CI (`grep -rn 'docker build' .github/workflows/` found only
# web-tests.yml's `api/` build). Three packaging defects shipped through that
# gap, each invisible to the Dockerfile's own build-time `supabase --version`
# self-check because `--version` never crosses the shim -> supabase-go
# forward: PR #752 (build context), PR #753 (missing `supabase-go` binary),
# PR #755 (missing `supabase/templates/**`). This fence builds the image in
# CI and runs `supabase db push` against a DELIBERATELY UNREACHABLE
# --db-url, so the CLI is forced to walk its full startup path (extract
# config -> validate config incl. template content_paths -> shim-forward to
# supabase-go -> attempt the TCP dial) before failing. Passing requires the
# failure to be THAT dial — the connection attempt — and nothing upstream of
# it.
#
# CATCH CRITERION (Sec's spec, verbatim): PASS only if the failure is a
# connection failure. `Invalid config` (template/content_path validation,
# PR #755's class) or `Could not find the` (missing supabase-go binary,
# PR #753's class) = RED. A bare `rc != 0` is VACUOUS here — the connection
# failure itself is also non-zero, so an rc-only check would pass on either
# a healthy image OR a broken one. This script asserts on the named token
# in the CLI's own stderr/stdout, never on exit code alone.
#
# MODES:
#   (default)               Production leg. Builds the REAL, committed
#                            Dockerfile and asserts:
#                              1. the image builds clean
#                              2. /usr/local/bin/supabase-go is present + executable
#                              3. supabase/templates/ is present in the image
#                              4. `supabase db push` against the unreachable
#                                 --db-url fails with the CONNECT token and
#                                 neither BAD token
#   --inversion=supabase-go Strike leg. Generates (at test time, via sed into
#                            a temp file — the broken Dockerfile is NEVER
#                            committed) a variant that drops `supabase-go`
#                            from both the tar-extraction member list and the
#                            chmod target list — reproducing PR #753's exact
#                            defect shape (build succeeds; binary silently
#                            absent). Builds it and asserts the db-push probe
#                            comes back with the `Could not find the` token
#                            (never the CONNECT token) — proving the
#                            production leg's assertion is non-vacuous: if
#                            this defect shipped again, the real job would
#                            RED on it, not pass by accident.
#   --inversion=templates   Strike leg for PR #755's class. Generates a
#                            variant with the `COPY supabase/templates/ ...`
#                            line removed (build still succeeds). Asserts the
#                            db-push probe comes back with the
#                            `Invalid config` token (never the CONNECT
#                            token).
#
# Both inversion legs must observe the DEFECT-CLASS token (not the CONNECT
# token) to pass. If a strike leg instead observes the CONNECT token, the
# fence's own assertion would have been fooled by that defect — fail closed
# (exit 1) with a FATAL message naming which leg was vacuous.
#
# Hermetic: no secrets. The unreachable target
# (postgres://x:x@127.0.0.1:1/postgres?sslmode=disable, PGSSLMODE=disable in
# env) matches the production mechanism of record (BACKLOG §7.36 item 26 —
# PGSSLMODE/PGSSLROOTCERT env vars are the TLS-mode mechanism for this CLI,
# never trust the --db-url query parameter alone) and is unroutable from any
# CI runner or laptop, so this never risks a real connection attempt landing
# anywhere.
#
# Repo-root build context, matching infra/supabase/docker-compose.yml's own
# declared build context for this service.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCKERFILE="${REPO_ROOT}/infra/supabase/migrator/Dockerfile"
UNREACHABLE_DB_URL="postgres://x:x@127.0.0.1:1/postgres?sslmode=disable"
CONNECT_TOKEN="dial error (dial tcp"
BAD_TOKEN_INVALID_CONFIG="Invalid config"
BAD_TOKEN_MISSING_BINARY="Could not find the"

MODE="production"
for arg in "$@"; do
  case "$arg" in
    --inversion=supabase-go) MODE="inversion-supabase-go" ;;
    --inversion=templates) MODE="inversion-templates" ;;
    *)
      echo "FATAL: unrecognized argument '$arg' (expected --inversion=supabase-go or --inversion=templates)" >&2
      exit 2
      ;;
  esac
done

TMP_DOCKERFILE=""
IMAGE_TAG=""
cleanup() {
  if [ -n "$TMP_DOCKERFILE" ] && [ -f "$TMP_DOCKERFILE" ]; then
    rm -f "$TMP_DOCKERFILE"
  fi
  if [ -n "$IMAGE_TAG" ]; then
    docker rmi "$IMAGE_TAG" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

build_image() {
  local dockerfile="$1" tag="$2"
  echo "--- building ${tag} from ${dockerfile}" >&2
  if ! docker build -f "$dockerfile" -t "$tag" "$REPO_ROOT" >/tmp/fence-migrator-build.log 2>&1; then
    echo "FATAL: docker build failed for ${tag} (dockerfile: ${dockerfile})" >&2
    tail -n 60 /tmp/fence-migrator-build.log >&2
    return 1
  fi
  return 0
}

run_db_push_probe() {
  local tag="$1"
  docker run --rm -e PGSSLMODE=disable -w /workspace "$tag" \
    supabase db push --db-url "$UNREACHABLE_DB_URL" --yes 2>&1
}

assert_leg_present() {
  # $1 = image tag, $2 = path, $3 = leg name
  local tag="$1" path="$2" name="$3"
  if docker run --rm "$tag" test -x "$path" >/dev/null 2>&1 || docker run --rm "$tag" test -e "$path" >/dev/null 2>&1; then
    echo "OK: ${name} present (${path})" >&2
    return 0
  fi
  echo "FATAL: ${name} MISSING (${path} not found in image)" >&2
  return 1
}

case "$MODE" in
  production)
    IMAGE_TAG="migrator-fence-production:$$"
    build_image "$DOCKERFILE" "$IMAGE_TAG" || exit 1

    fail=0

    # Explicit leg 1: supabase-go binary present + executable.
    docker run --rm "$IMAGE_TAG" test -x /usr/local/bin/supabase-go
    if [ $? -ne 0 ]; then
      echo "FATAL: leg 'supabase-go executable' FAILED — /usr/local/bin/supabase-go missing or not executable" >&2
      fail=1
    else
      echo "OK: leg 'supabase-go executable' passed" >&2
    fi

    # Explicit leg 2: supabase/templates/ present in the image.
    docker run --rm "$IMAGE_TAG" test -d /workspace/supabase/templates
    if [ $? -ne 0 ]; then
      echo "FATAL: leg 'templates present' FAILED — /workspace/supabase/templates missing" >&2
      fail=1
    else
      echo "OK: leg 'templates present' passed" >&2
    fi

    # Explicit leg 3: db push against an unreachable target fails with the
    # connection token, and NEITHER bad token.
    output="$(run_db_push_probe "$IMAGE_TAG")"
    echo "$output" | sed 's/^/[db push probe] /' >&2

    if echo "$output" | grep -qF "$BAD_TOKEN_INVALID_CONFIG"; then
      echo "FATAL: leg 'db push connect-only failure' FAILED — output carries '${BAD_TOKEN_INVALID_CONFIG}' (config-validation-class failure, e.g. missing supabase/templates/**), not a connection failure" >&2
      fail=1
    elif echo "$output" | grep -qF "$BAD_TOKEN_MISSING_BINARY"; then
      echo "FATAL: leg 'db push connect-only failure' FAILED — output carries '${BAD_TOKEN_MISSING_BINARY}' (missing supabase-go binary), not a connection failure" >&2
      fail=1
    elif echo "$output" | grep -qF "$CONNECT_TOKEN"; then
      echo "OK: leg 'db push connect-only failure' passed — failure is a real connection attempt ('${CONNECT_TOKEN}')" >&2
    else
      echo "FATAL: leg 'db push connect-only failure' FAILED — output matched NEITHER the connect token nor either bad token; unrecognized failure shape, failing closed" >&2
      fail=1
    fi

    if [ "$fail" -ne 0 ]; then
      echo "FENCE RED (production mode): one or more legs failed — see FATAL lines above" >&2
      exit 1
    fi
    echo "FENCE GREEN (production mode): all legs passed" >&2
    exit 0
    ;;

  inversion-supabase-go)
    TMP_DOCKERFILE="$(mktemp /tmp/Dockerfile.migrator-inversion-supabase-go.XXXXXX)"
    sed -E \
      -e 's/-C \/usr\/local\/bin supabase supabase-go/-C \/usr\/local\/bin supabase/' \
      -e 's#/usr/local/bin/supabase /usr/local/bin/supabase-go#/usr/local/bin/supabase#' \
      "$DOCKERFILE" > "$TMP_DOCKERFILE"
    if diff -q "$DOCKERFILE" "$TMP_DOCKERFILE" >/dev/null 2>&1; then
      echo "FATAL: sed transform produced NO change vs the real Dockerfile — the inversion fixture generator no longer matches the Dockerfile's current text (drift). Fixture is not testing what it claims; failing closed." >&2
      exit 2
    fi
    IMAGE_TAG="migrator-fence-inversion-nogo:$$"
    build_image "$TMP_DOCKERFILE" "$IMAGE_TAG" || {
      echo "FATAL: the no-supabase-go inversion variant failed to BUILD — PR #753's defect shape was that this build succeeds while silently dropping the binary. A build failure here means the fixture no longer reproduces that historical defect shape; the strike is inconclusive, failing closed." >&2
      exit 1
    }

    output="$(run_db_push_probe "$IMAGE_TAG")"
    echo "$output" | sed 's/^/[db push probe, no-supabase-go variant] /' >&2

    if echo "$output" | grep -qF "$CONNECT_TOKEN"; then
      echo "FATAL: STRIKE FAILED — the no-supabase-go broken variant produced the CONNECT token, meaning the production leg's assertion would have PASSED (vacuously) on this defect. The fence is not catching what it claims." >&2
      exit 1
    elif echo "$output" | grep -qF "$BAD_TOKEN_MISSING_BINARY"; then
      echo "OK: STRIKE PASSED — broken variant correctly produced '${BAD_TOKEN_MISSING_BINARY}'; the production leg's assertion would RED on this defect class." >&2
      exit 0
    else
      echo "FATAL: STRIKE INCONCLUSIVE — broken variant's output matched neither the connect token nor the expected '${BAD_TOKEN_MISSING_BINARY}' token; cannot confirm the fence catches this defect class. Failing closed." >&2
      exit 1
    fi
    ;;

  inversion-templates)
    TMP_DOCKERFILE="$(mktemp /tmp/Dockerfile.migrator-inversion-templates.XXXXXX)"
    sed '/^COPY supabase\/templates\/ supabase\/templates\/$/d' "$DOCKERFILE" > "$TMP_DOCKERFILE"
    if diff -q "$DOCKERFILE" "$TMP_DOCKERFILE" >/dev/null 2>&1; then
      echo "FATAL: sed transform produced NO change vs the real Dockerfile — the templates COPY line the fixture targets is no longer present verbatim (drift). Fixture is not testing what it claims; failing closed." >&2
      exit 2
    fi
    IMAGE_TAG="migrator-fence-inversion-notpl:$$"
    build_image "$TMP_DOCKERFILE" "$IMAGE_TAG" || {
      echo "FATAL: the no-templates inversion variant failed to BUILD — PR #755's defect shape was that this build succeeds while silently omitting supabase/templates/. A build failure here means the fixture no longer reproduces that historical defect shape; the strike is inconclusive, failing closed." >&2
      exit 1
    }

    output="$(run_db_push_probe "$IMAGE_TAG")"
    echo "$output" | sed 's/^/[db push probe, no-templates variant] /' >&2

    if echo "$output" | grep -qF "$CONNECT_TOKEN"; then
      echo "FATAL: STRIKE FAILED — the no-templates broken variant produced the CONNECT token, meaning the production leg's assertion would have PASSED (vacuously) on this defect. The fence is not catching what it claims." >&2
      exit 1
    elif echo "$output" | grep -qF "$BAD_TOKEN_INVALID_CONFIG"; then
      echo "OK: STRIKE PASSED — broken variant correctly produced '${BAD_TOKEN_INVALID_CONFIG}'; the production leg's assertion would RED on this defect class." >&2
      exit 0
    else
      echo "FATAL: STRIKE INCONCLUSIVE — broken variant's output matched neither the connect token nor the expected '${BAD_TOKEN_INVALID_CONFIG}' token; cannot confirm the fence catches this defect class. Failing closed." >&2
      exit 1
    fi
    ;;
esac
