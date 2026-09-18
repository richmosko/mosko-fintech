# infra/supabase/migrator/Dockerfile
#
# The `migrator` service — ADR-072 (Option E) production migration-apply
# mechanism. DevOps-owned. CHUNK 1 of the ADR-072 build (the container +
# credential plumbing only; the ci-migrate trigger path and the RT-27/RT-32
# fence extension are later chunks — see ADR-072 Consequences).
#
# ┌─ WHAT THIS CONTAINER IS ────────────────────────────────────────────────┐
# │ A resident, otherwise-idle container (Pattern A — same convention as     │
# │ workers/etl and workers/provider-sync: `CMD tail -f /dev/null`) that a  │
# │ Coolify Scheduled Task `docker exec`s into to run ONE fixed command    │
# │ (ADR-072 Amendment 7 — see scripts/migrator-scheduled-task.md for the  │
# │ current byte-exact literal; docs/deployment-runbook.md §6.5 is the ONE │
# │ place to change it). It never listens on a port,                       │
# │ never accepts inbound connections, and its ONLY outbound reach is to    │
# │ `db` on the shared Coolify project network (ADR-072 Decision 1/C9 — no  │
# │ `ports:`, no Domain, no firewall change; see docker-compose.yml).       │
# └───────────────────────────────────────────────────────────────────────┘
#
# BAKED AT BUILD, PER COMMIT (ADR-072 Decision 1 + Decision 5 "container
# side" channel) — the supabase/ project layout (config.toml + migrations/)
# is COPIEd in here, not mounted or pulled at runtime. No runtime git
# credential, no container-vs-repo drift: the image IS the migration set as
# of the commit that built it. Rebuilding this image is how a new migration
# reaches production (load-bearing sequence: rebuild THIS image -> run the
# Scheduled Task -> then deploy the app — ADR-072 Decision 5).
#
# CLI VERSION — pinned to 2.107.0, the SAME version
# .github/actions/supabase-cli-setup pins for CI (db-tests / worker-ci /
# etl-ci / security-scan). Not a hard requirement of ADR-072, but a
# deliberate DevOps call: the migrator's `db push` and CI's `supabase test
# db` / `supabase start` should behave identically against the same
# migration set. Bump both together if the CLI is ever upgraded.
#
# NO SECRETS ARE BAKED INTO THIS IMAGE. PROD_DB_URL is supplied at RUNTIME
# via the migrator service's Coolify-injected env (see docker-compose.yml +
# .env.example in this directory) — matching every other worker Dockerfile
# in this repo (workers/etl, workers/provider-sync, workers/pdf-render).

FROM debian:bookworm-slim

# ADR-072 Amendment 6 (ratified, c2b20cc2) — Sec's "assert the OUTCOME, not the STATUS"
# ruling on the 119 fire. Measured, 2026-09-17: this Dockerfile carried NO
# label, build-arg, or marker identifying the migration set baked into the
# image — only the plain `COPY supabase/migrations/` below. That gap let
# three Phase D fires run `db push` against a STALE image (the migrator
# service was never rebuilt/redeployed after the sha that added those
# migrations merged) and report clean success, because an empty diff is a
# valid `db push` outcome. The container never held the migration it was
# "fired for."
#
# GIT_SHA/SOURCE_COMMIT below are meant to be populated FROM Coolify's own
# build-time git sha at deploy time. ⚠ UNVERIFIED WHICH BUILD-ARG NAME
# COOLIFY 4.3.18 INJECTS — no vendored Coolify source or docs exist in this
# repo to confirm it from, and this session has no network egress either.
# STATED HONESTLY AS UNCONFIRMED, defaulted to `SOURCE_COMMIT` (the name
# commonly documented for Coolify's Nixpacks/Dockerfile build-arg
# injection) with a runbook verify line — docs/records/v1final/production-
# standup.md (line 32-34, an EARLIER attempt at this same problem for the
# four app-tier Dockerfiles) recorded the identical gap and the identical
# caveat, never confirmed then either.
# BOTH `GIT_SHA` and `SOURCE_COMMIT` are accepted (Sec-approved, ADR-072
# Amendment 6, PR #791) so the mechanism does not hard-depend on guessing
# right: `GIT_SHA` wins if supplied, else `SOURCE_COMMIT` is used, and the
# RUN step below FAILS CLOSED only when NEITHER is set — the dual path is
# not permanent-by-default, it is meant to be COLLAPSED once the first
# real Coolify build emits which name it used (see `GIT_SHA_SOURCE` below
# and the runbook verify line) — confirm on the tree, don't leave this
# open indefinitely.
ARG SOURCE_COMMIT=""
ARG GIT_SHA=""
# Captures whether `GIT_SHA` itself arrived non-empty, BEFORE the merge
# line below overwrites it — this is what lets the build emit which of
# the two names actually supplied the value (Sec condition 2), rather than
# only ever recording the resolved sha with no record of its source.
ARG GIT_SHA_SOURCE=${GIT_SHA:+GIT_SHA}
ARG GIT_SHA=${GIT_SHA:-$SOURCE_COMMIT}
ARG GIT_SHA_SOURCE=${GIT_SHA_SOURCE:-SOURCE_COMMIT}

# Pinned Supabase CLI release — matches .github/actions/supabase-cli-setup.
# Bump both together.
ARG SUPABASE_CLI_VERSION=2.107.0
# Populated automatically by buildx (amd64 / arm64) — production (Hetzner
# cax21) is arm64 (CORRECTED 2026-09-14, standup step 6 Phase B: measured
# live on the box, `uname -m` = aarch64; the prior "amd64" claim here was
# stale/wrong and did not affect the build, which is arch-driven by
# TARGETARCH regardless of what this comment said); TARGETARCH keeps this
# Dockerfile buildable+verifiable (`supabase --version` actually EXECUTES
# below, not just downloaded) on either architecture, rather than
# hardcoding one and leaving the RUN step unable to self-verify elsewhere.
ARG TARGETARCH

# CORRECTED 2026-09-14 (standup step 6 Phase B) — measured live against the
# production box: `supabase_linux_${TARGETARCH}.tar.gz` ships TWO binaries,
# `supabase` and `supabase-go`. The prior extraction (`tar -xzf ... -C
# /usr/local/bin supabase`) took only `supabase` and dropped `supabase-go`.
# `supabase --version` still worked (build-time RUN step below, and it
# passed) because that subcommand doesn't need the companion binary, but
# `supabase db push` failed at runtime: "Could not find the `supabase-go`
# binary" — the CLI at this pinned version ships as a shim that forwards
# DB-affecting subcommands to a co-located Go binary. Extract both.
#
# ⚠ ADR-072 Amendment 7 (2026-09-17): `postgresql-client-15` added —
# scripts/migrator-scheduled-task.md's Command now runs `psql` inside this
# container (reading the ledger's top row post-apply, for
# migrator-orchestrate.sh's docker-free delivery assertion). Pinned to the
# `-15` package name explicitly (Debian bookworm's own default major, so
# this pin does not change what would resolve anyway; explicit rather than
# the floating `postgresql-client` meta-package so a future bookworm point
# release cannot silently move which major gets installed here). `migrator`
# authenticates to its own ledger schema with `MIGRATOR_DB_USER`/
# `MIGRATOR_DB_PASSWORD` (already in this container's env per docker-
# compose.yml) — it owns `supabase_migrations.schema_migrations` per
# Amendment 5's design, so no new grant is needed for the `select
# max(version)` read the Command runs.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tar postgresql-client-15 \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL -o /tmp/supabase-cli.tar.gz \
       "https://github.com/supabase/cli/releases/download/v${SUPABASE_CLI_VERSION}/supabase_linux_${TARGETARCH}.tar.gz" \
    && tar -xzf /tmp/supabase-cli.tar.gz -C /usr/local/bin supabase supabase-go \
    && chmod +x /usr/local/bin/supabase /usr/local/bin/supabase-go \
    && rm /tmp/supabase-cli.tar.gz \
    && supabase --version \
    && psql --version

WORKDIR /workspace

# The repo's supabase/ project layout, baked at build. `supabase db push`
# (run with --workdir /workspace, or from this WORKDIR) reads
# supabase/config.toml + supabase/migrations/**  from here — the SAME
# migration set this commit's CI already ran against a local stack.
# tests/ is NOT copied: db push never reads it.
#
# CORRECTED 2026-09-14 (standup step 6 Phase B.4) — measured live: `supabase
# db push` FAILS if `supabase/templates/**` is absent, even though the verb
# never functionally uses email templates. The CLI validates config.toml's
# FULL path set (incl. `[auth.email.template.*].content_path`) before
# running any command, not just the paths the invoked verb touches:
#   Invalid config for auth.email.template.magic_link.content_path:
#   open supabase/templates/magic_link.html: no such file or directory
# The prior comment here said templates/ "can carry local-only
# interpolation this container must never see" — reviewed at fix time:
# supabase/templates/{confirmation,recovery,magic_link}.html are static,
# system-authored HTML (SELF-290/Auth-1) using only GoTrue's own template
# vars (`{{ .ConfirmationURL }}`, `{{ .Token }}`) — no secrets, no
# environment-specific values, no user-supplied content. Baking them in is
# safe; the prior caution was a defensive assumption that did not survive
# contact with these three files' actual contents. If a future template
# ever needs real interpolation (a real domain, a real signing value), that
# changes this call and needs its own review before landing here.
COPY supabase/config.toml supabase/config.toml
COPY supabase/templates/ supabase/templates/
COPY supabase/migrations/ supabase/migrations/

# ADR-072 Amendment 6 (ratified, c2b20cc2) — the OUTCOME marker Sec's
# ruling requires, in TWO forms so both a `docker inspect` (no exec
# needed, matches how migrator-orchestrate.sh's box-side check reads it)
# and a `docker exec cat` can confirm what migration set this specific
# container's filesystem actually carries:
#   (1) an OCI LABEL, readable via `docker inspect --format
#       '{{index .Config.Labels "org.mosko.migrator.git-sha"}}'` with no
#       exec into the container at all;
#   (2) a plain file at /workspace/.build-sha, for a fallback `docker exec`
#       read and for a human `cat`ting it interactively without needing to
#       recall the label key.
#
# FAILS THE BUILD (distinct FATAL message, matched by
# scripts/ci/fence-migrator-build-connect.sh's `--inversion=no-sha` leg —
# NOT the harness's own generic "FATAL: docker build failed" string, which
# would make that leg vacuous) if the resolved sha came through empty —
# neither GIT_SHA nor SOURCE_COMMIT was supplied. A silently-empty marker
# would make every comparison against it vacuously pass (an empty expected
# sha "matching" an empty file), which is the exact defect class this
# mechanism exists to close. DO NOT weaken this to a non-empty default
# (e.g. "dev"/"unknown") to make a build succeed — a present-but-wrong
# marker is worse than a loud failure (Sec, ADR-072 Amendment 6, PR #791).
#
# ALSO fails the build (a second, distinct FATAL message) if the resolved
# value is non-empty but not a well-formed 40-character hex git sha — Sec
# condition, PR #791: if Coolify ever injects a branch name or a short
# sha, a bare `test -n` would pass and bake a non-sha marker, and the
# defect would only surface later, one layer away, when
# migrator-orchestrate.sh's own 40-hex check (exit 5, defence-in-depth)
# rejects it on the box. Catching the same malformed-value class HERE, at
# build time, lands the failure where the cause actually is. Same regex as
# the orchestrator's check (`^[0-9a-f]{40}$`) — kept in sync deliberately.
RUN set -eu; \
    if [ -z "$GIT_SHA" ]; then \
      echo "FATAL: GIT_SHA/SOURCE_COMMIT build-arg is empty -- neither was supplied. Coolify's actual build-arg name is unconfirmed (see the ARG block's own comment above). Refusing to bake an empty migration-set marker." >&2; \
      exit 1; \
    fi; \
    if ! printf '%s' "$GIT_SHA" | grep -Eq '^[0-9a-f]{40}$'; then \
      echo "FATAL: resolved sha '$GIT_SHA' (from build-arg $GIT_SHA_SOURCE) is not a well-formed 40-character hex git sha. Refusing to bake a malformed migration-set marker." >&2; \
      exit 1; \
    fi
LABEL org.mosko.migrator.git-sha="$GIT_SHA"
LABEL org.mosko.migrator.git-sha-source="$GIT_SHA_SOURCE"
# ⚠ /workspace/.build-sha stays SHA-ONLY, single line, no trailing
# annotation -- migrator-orchestrate.sh's own check does
# `RUNNING_SHA="$(docker compose ... exec -T migrator cat
# /workspace/.build-sha)"` and compares that WHOLE captured value for
# EQUALITY against MIGRATOR_EXPECT_SHA (a bare 40-hex sha). A second line
# in this same file would make RUNNING_SHA carry an embedded newline and
# never equal anything again -- that would silently turn every future
# fire into a permanent mismatch, which is worse than the problem Sec's
# condition 2 is trying to solve. The "which build-arg was used" marker
# therefore lives in the LABEL above (Sec's own stated alternative) AND
# in a SEPARATE file below, never inside .build-sha itself.
RUN printf '%s' "$GIT_SHA" > /workspace/.build-sha
RUN printf '%s\n' "$GIT_SHA_SOURCE" > /workspace/.build-sha-source

# Resident Pattern-A keepalive — the Coolify Scheduled Task execs the real
# work into this container; it is never this image's own CMD/ENTRYPOINT.
# Matches workers/etl/Dockerfile and workers/provider-sync/Dockerfile.
CMD ["tail", "-f", "/dev/null"]
