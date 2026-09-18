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
#   --inversion=no-sha      Strike leg for ADR-072 Amendment 6's fail-closed
#                            sha assertion (PR #791; added 2026-09-17 after
#                            this fence's OWN three builds red'd the
#                            production/supabase-go/templates legs — the
#                            Dockerfile's `RUN test ... || (echo FATAL ...)`
#                            was working correctly against a harness that
#                            predated it and never passed --build-arg
#                            GIT_SHA/SOURCE_COMMIT at all). Builds the REAL,
#                            unmodified Dockerfile WITH NO build-arg
#                            supplied and asserts the build FAILS, AND that
#                            it fails with the Dockerfile's OWN specific
#                            "GIT_SHA/SOURCE_COMMIT build-arg is empty"
#                            message -- never this harness's generic "FATAL:
#                            docker build failed for ..." string (two FATAL
#                            strings are in play; matching the wrong one
#                            would pass on a build that failed for an
#                            unrelated reason and make this leg vacuous,
#                            Sec's condition). This is the fail-closed
#                            property the whole Amendment 6 mechanism relies
#                            on -- it must have its own dedicated RED, same
#                            as the other two defect classes above.
#   --inversion=no-pfin-task Strike leg for ADR-072 Amendment 8 (2026-09-18,
#                            F/CTO-ratified option (B)): the migrator task
#                            script is now baked into the image
#                            (infra/supabase/migrator/pfin-task.sh, COPYed
#                            in with --chmod=0755) rather than living as an
#                            inline Coolify command literal, specifically
#                            because Coolify's own scheduled_tasks.command
#                            column (character varying(255)) is too narrow
#                            for the tagged logic. This is item 21's exact
#                            blind spot again, one file over: "a COPY that
#                            silently lands a zero-byte or non-executable
#                            file would fail at fire time, not build time"
#                            (Architect's addendum). The Dockerfile's own
#                            RUN step now asserts `test -x
#                            /workspace/pfin-task.sh && sh -n
#                            /workspace/pfin-task.sh` and FATALs the BUILD
#                            if either fails -- same shape as --inversion=
#                            no-sha (a build-failure assertion, not a
#                            runtime-probe assertion like the two legs
#                            above), so this leg follows that pattern:
#                            generates (via sed into a temp file, never
#                            committed) a variant that drops the `COPY
#                            --chmod=0755 infra/supabase/migrator/
#                            pfin-task.sh /workspace/pfin-task.sh` line,
#                            builds it, and asserts the build FAILS with
#                            the Dockerfile's OWN specific "is missing or
#                            not executable after COPY" message -- never
#                            this harness's generic "docker build failed"
#                            string, same vacuity concern the no-sha leg
#                            already names.
#
# Both `supabase-go`/`templates` inversion legs must observe the
# DEFECT-CLASS token (not the CONNECT token) to pass; the `no-sha` and
# `no-pfin-task` legs must observe a build FAILURE carrying the
# Dockerfile's own specific FATAL message (not this harness's generic
# one). If a strike leg instead observes the wrong token (or a successful
# build, for the two build-failure legs), the fence's own assertion would
# have been fooled by that defect — fail closed (exit 1) with a FATAL
# message naming which leg was vacuous.
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
# The Dockerfile's OWN fail-closed message (infra/supabase/migrator/Dockerfile,
# the `RUN set -eu; if [ -z "$GIT_SHA" ]; then echo "FATAL: ..."` step) --
# kept as an exact substring of that message, distinct from this harness's
# own "FATAL: docker build failed for ..." string at build_image() below.
# Matching the wrong one would make the --inversion=no-sha leg vacuous
# (Sec's condition on this fence fix, PR #791).
DOCKERFILE_SHA_FATAL_TOKEN="GIT_SHA/SOURCE_COMMIT build-arg is empty"
# The Dockerfile's OWN fail-closed message for the pfin-task.sh
# existence-and-executable assertion (ADR-072 Amendment 8, item-21
# class) -- same discipline as DOCKERFILE_SHA_FATAL_TOKEN above: kept as
# an exact substring, distinct from this harness's own generic
# "docker build failed" string, so the --inversion=no-pfin-task leg
# cannot be fooled by matching the wrong FATAL.
DOCKERFILE_PFIN_TASK_FATAL_TOKEN="is missing or not executable after COPY"

# ADR-072 Amendment 6 (ratified, c2b20cc2): every build below now supplies
# the sha the Dockerfile's GIT_SHA/SOURCE_COMMIT ARGs require, sourced from
# the same place a real CI run would have it (GITHUB_SHA), falling back to
# the local git HEAD for a developer running this fence outside Actions.
# The one deliberate exception is the --inversion=no-sha leg, which must
# NOT pass this -- that omission is the entire point of that leg.
FENCE_SHA="${GITHUB_SHA:-$(cd "$REPO_ROOT" && git rev-parse HEAD 2>/dev/null || true)}"
if [ -z "$FENCE_SHA" ]; then
  echo "FATAL: could not resolve a sha to pass as --build-arg GIT_SHA (GITHUB_SHA unset and 'git rev-parse HEAD' failed) -- cannot exercise the production/inversion-supabase-go/inversion-templates legs, which now require a real sha to get past the Amendment 6 fail-closed check. Failing closed rather than silently building without it." >&2
  exit 2
fi

MODE="production"
for arg in "$@"; do
  case "$arg" in
    --inversion=supabase-go) MODE="inversion-supabase-go" ;;
    --inversion=templates) MODE="inversion-templates" ;;
    --inversion=no-sha) MODE="inversion-no-sha" ;;
    --inversion=no-pfin-task) MODE="inversion-no-pfin-task" ;;
    *)
      echo "FATAL: unrecognized argument '$arg' (expected --inversion=supabase-go, --inversion=templates, --inversion=no-sha, or --inversion=no-pfin-task)" >&2
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
  # $1 = dockerfile, $2 = tag, $3.. = extra `docker build` args (e.g.
  # --build-arg GIT_SHA=...). Extra args are OPTIONAL so this function
  # still serves inversion-no-sha's "build with nothing" case if ever
  # called that way, though that leg currently calls docker build directly
  # (see below) since it must assert on FAILURE, which this function
  # treats as the error case it reports and returns 1 for.
  local dockerfile="$1" tag="$2"
  shift 2
  echo "--- building ${tag} from ${dockerfile} (extra args: $*)" >&2
  if ! docker build -f "$dockerfile" -t "$tag" "$@" "$REPO_ROOT" >/tmp/fence-migrator-build.log 2>&1; then
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
    build_image "$DOCKERFILE" "$IMAGE_TAG" --build-arg "GIT_SHA=$FENCE_SHA" || exit 1

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

    # Explicit leg 2b (ADR-072 Amendment 8): pfin-task.sh present,
    # executable, AND syntactically valid -- the Dockerfile's own
    # build-time RUN step already asserts this and would have failed the
    # BUILD above if it didn't hold; this leg re-confirms it against the
    # built IMAGE directly, matching the belt-and-braces discipline of
    # leg 1/leg 2 above (which also re-check what the Dockerfile's own
    # steps already guarantee).
    docker run --rm "$IMAGE_TAG" test -x /workspace/pfin-task.sh
    if [ $? -ne 0 ]; then
      echo "FATAL: leg 'pfin-task.sh executable' FAILED — /workspace/pfin-task.sh missing or not executable" >&2
      fail=1
    else
      echo "OK: leg 'pfin-task.sh executable' passed" >&2
    fi
    docker run --rm "$IMAGE_TAG" sh -n /workspace/pfin-task.sh
    if [ $? -ne 0 ]; then
      echo "FATAL: leg 'pfin-task.sh syntax' FAILED — sh -n /workspace/pfin-task.sh reported a parse error inside the built image" >&2
      fail=1
    else
      echo "OK: leg 'pfin-task.sh syntax' passed" >&2
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
    build_image "$TMP_DOCKERFILE" "$IMAGE_TAG" --build-arg "GIT_SHA=$FENCE_SHA" || {
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
    build_image "$TMP_DOCKERFILE" "$IMAGE_TAG" --build-arg "GIT_SHA=$FENCE_SHA" || {
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

  inversion-no-sha)
    # Strike leg for ADR-072 Amendment 6's fail-closed sha assertion. Unlike
    # the other two inversion legs, this one does NOT sed-modify the
    # Dockerfile -- it builds the REAL, committed Dockerfile, and the
    # "defect" under test is simply withholding --build-arg entirely. The
    # expected outcome is a build FAILURE, so this does not use
    # build_image() (which treats any build failure as the harness's own
    # error and returns 1 -- exactly backwards for what this leg needs).
    IMAGE_TAG="migrator-fence-inversion-no-sha:$$"
    echo "--- building ${IMAGE_TAG} from ${DOCKERFILE} WITH NO build-arg (expect FAILURE, and specifically the Dockerfile's own sha-empty FATAL message)" >&2
    if docker build -f "$DOCKERFILE" -t "$IMAGE_TAG" "$REPO_ROOT" >/tmp/fence-migrator-build-no-sha.log 2>&1; then
      echo "FATAL: STRIKE FAILED — the real Dockerfile built SUCCESSFULLY with neither GIT_SHA nor SOURCE_COMMIT supplied. Amendment 6's fail-closed property (a build with no sha marker must FATAL, not silently succeed) is not holding." >&2
      tail -n 60 /tmp/fence-migrator-build-no-sha.log >&2
      exit 1
    fi
    # No image exists on this path (the build failed) -- IMAGE_TAG is left
    # set only so cleanup()'s `docker rmi ... || true` is a harmless no-op;
    # nothing to remove either way.
    if grep -qF "$DOCKERFILE_SHA_FATAL_TOKEN" /tmp/fence-migrator-build-no-sha.log; then
      echo "OK: STRIKE PASSED — build correctly failed with the Dockerfile's own '${DOCKERFILE_SHA_FATAL_TOKEN}' message when no build-arg was supplied. This is a distinct string from this harness's own \"FATAL: docker build failed for ...\" -- matching THAT one instead would have made this leg vacuous (any build failure, for any reason, would pass)." >&2
      exit 0
    else
      echo "FATAL: STRIKE INCONCLUSIVE — the build failed (expected), but NOT with the Dockerfile's expected '${DOCKERFILE_SHA_FATAL_TOKEN}' message. Some other defect is masking the intended fail-closed assertion (e.g. a network/apt failure upstream of the sha check, or the check's own message text drifted from this constant) -- failing closed rather than passing on an unrelated failure." >&2
      tail -n 60 /tmp/fence-migrator-build-no-sha.log >&2
      exit 1
    fi
    ;;

  inversion-no-pfin-task)
    # Strike leg for ADR-072 Amendment 8's item-21-class self-check
    # (2026-09-18). Unlike inversion-no-sha (which withholds a build-arg
    # from the REAL, unmodified Dockerfile), the "defect" here requires
    # sed-modifying a temp copy -- there is no build-arg that skips a
    # COPY line -- so this leg combines BOTH prior patterns: generate the
    # broken variant like inversion-supabase-go/inversion-templates do,
    # but expect a build FAILURE like inversion-no-sha does (the
    # Dockerfile's own RUN step FATALs the build when
    # /workspace/pfin-task.sh is missing -- this is a build-time
    # assertion, not a runtime-probe one, so build_image()'s
    # "any failure is the harness's own error" framing is wrong here too).
    TMP_DOCKERFILE="$(mktemp /tmp/Dockerfile.migrator-inversion-no-pfin-task.XXXXXX)"
    sed '/^COPY --chmod=0755 infra\/supabase\/migrator\/pfin-task\.sh \/workspace\/pfin-task\.sh$/d' "$DOCKERFILE" > "$TMP_DOCKERFILE"
    if diff -q "$DOCKERFILE" "$TMP_DOCKERFILE" >/dev/null 2>&1; then
      echo "FATAL: sed transform produced NO change vs the real Dockerfile — the pfin-task.sh COPY line the fixture targets is no longer present verbatim (drift). Fixture is not testing what it claims; failing closed." >&2
      exit 2
    fi
    IMAGE_TAG="migrator-fence-inversion-no-pfin-task:$$"
    echo "--- building ${IMAGE_TAG} from ${TMP_DOCKERFILE} WITH THE pfin-task.sh COPY LINE DROPPED (expect FAILURE, and specifically the Dockerfile's own pfin-task.sh-missing FATAL message)" >&2
    if docker build -f "$TMP_DOCKERFILE" -t "$IMAGE_TAG" --build-arg "GIT_SHA=$FENCE_SHA" "$REPO_ROOT" >/tmp/fence-migrator-build-no-pfin-task.log 2>&1; then
      echo "FATAL: STRIKE FAILED — the no-pfin-task-COPY variant built SUCCESSFULLY. The build-time existence-and-executable assertion (item 21's own blind spot, applied to this file) is not holding — a COPY that silently lands nothing would ship an image whose Scheduled Task fails only at fire time." >&2
      IMAGE_TAG="$IMAGE_TAG" # leave set so cleanup() removes the (unexpectedly built) image
      tail -n 60 /tmp/fence-migrator-build-no-pfin-task.log >&2
      exit 1
    fi
    IMAGE_TAG="" # build failed -- no image exists; nothing for cleanup() to remove
    if grep -qF "$DOCKERFILE_PFIN_TASK_FATAL_TOKEN" /tmp/fence-migrator-build-no-pfin-task.log; then
      echo "OK: STRIKE PASSED — build correctly failed with the Dockerfile's own '${DOCKERFILE_PFIN_TASK_FATAL_TOKEN}' message when the pfin-task.sh COPY was dropped. Distinct from this harness's own \"FATAL: docker build failed for ...\" string — matching THAT one instead would have made this leg vacuous (any build failure, for any reason, would pass)." >&2
      exit 0
    else
      echo "FATAL: STRIKE INCONCLUSIVE — the build failed (expected), but NOT with the Dockerfile's expected '${DOCKERFILE_PFIN_TASK_FATAL_TOKEN}' message. Some other defect is masking the intended assertion (e.g. an unrelated build failure upstream) -- failing closed rather than passing on an unrelated failure." >&2
      tail -n 60 /tmp/fence-migrator-build-no-pfin-task.log >&2
      exit 1
    fi
    ;;
esac
