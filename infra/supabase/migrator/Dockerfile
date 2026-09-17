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
# │ Coolify Scheduled Task `docker exec`s into to run ONE fixed command:    │
# │ `supabase db push --db-url "$PROD_DB_URL"`. It never listens on a port, │
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

# ⚠ ADR-072 Amendment 6 (draft) — Sec's "assert the OUTCOME, not the STATUS"
# ruling on the 119 fire. Measured, 2026-09-17: this Dockerfile carried NO
# label, build-arg, or marker identifying the migration set baked into the
# image — only the plain `COPY supabase/migrations/` below. That gap let
# three Phase D fires run `db push` against a STALE image (the migrator
# service was never rebuilt/redeployed after the sha that added those
# migrations merged) and report clean success, because an empty diff is a
# valid `db push` outcome. The container never held the migration it was
# "fired for."
#
# GIT_SHA below is meant to be populated FROM Coolify's own build-time git
# sha at deploy time. ⚠ UNVERIFIED WHICH BUILD-ARG NAME COOLIFY 4.3.18
# INJECTS — I could not reach Coolify's source or docs live (no network
# egress in the session that wrote this). `SOURCE_COMMIT` is the name
# commonly documented for Coolify's Nixpacks/Dockerfile build-arg
# injection, and is what this Dockerfile assumes below, but
# docs/records/v1final/production-standup.md (line 32-34, an EARLIER
# attempt at this same problem for the four app-tier Dockerfiles) recorded
# the identical gap and the identical caveat: "Coolify names this
# COMMIT_SHA or similar depending on version — unconfirmed until read on
# the real instance." That was never confirmed then either. CONFIRM THE
# ACTUAL BUILD-ARG NAME AGAINST THE RUNNING COOLIFY 4.3.18 INSTANCE (its
# own build-log output for a deploy will show every ARG it passes) BEFORE
# this PR is taken out of Draft — if the name is wrong, GIT_SHA silently
# builds empty and this whole mechanism is exactly the vacuous-green class
# it exists to close.
ARG GIT_SHA=""

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
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tar \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL -o /tmp/supabase-cli.tar.gz \
       "https://github.com/supabase/cli/releases/download/v${SUPABASE_CLI_VERSION}/supabase_linux_${TARGETARCH}.tar.gz" \
    && tar -xzf /tmp/supabase-cli.tar.gz -C /usr/local/bin supabase supabase-go \
    && chmod +x /usr/local/bin/supabase /usr/local/bin/supabase-go \
    && rm /tmp/supabase-cli.tar.gz \
    && supabase --version

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

# ADR-072 Amendment 6 (draft) — the OUTCOME marker Sec's ruling requires,
# in TWO forms so both a `docker inspect` (no exec needed, matches how
# migrator-orchestrate.sh's box-side check reads it) and a `docker exec cat`
# can confirm what migration set this specific container's filesystem
# actually carries:
#   (1) an OCI LABEL, readable via `docker inspect --format
#       '{{index .Config.Labels "org.mosko.migrator.git-sha"}}'` with no
#       exec into the container at all;
#   (2) a plain file at /workspace/.build-sha, for a fallback `docker exec`
#       read and for a human `cat`ting it interactively without needing to
#       recall the label key.
# FAILS THE BUILD if GIT_SHA came through empty — a silently-empty marker
# would make every comparison against it vacuously pass (an empty expected
# sha "matching" an empty file), which is the exact defect class this
# mechanism exists to close. Confirm the real Coolify build-arg name (see
# the GIT_SHA ARG's own comment above) before this leaves Draft — until
# then, THIS CHECK WILL FAIL EVERY BUILD, deliberately, rather than bake a
# marker nobody has verified is real.
RUN test -n "$GIT_SHA" || (echo "FATAL: GIT_SHA build-arg is empty — Coolify's build-arg name is unconfirmed (see the ARG's own comment above). Refusing to bake an empty migration-set marker." >&2 && exit 1)
LABEL org.mosko.migrator.git-sha="$GIT_SHA"
RUN printf '%s' "$GIT_SHA" > /workspace/.build-sha

# Resident Pattern-A keepalive — the Coolify Scheduled Task execs the real
# work into this container; it is never this image's own CMD/ENTRYPOINT.
# Matches workers/etl/Dockerfile and workers/provider-sync/Dockerfile.
CMD ["tail", "-f", "/dev/null"]
