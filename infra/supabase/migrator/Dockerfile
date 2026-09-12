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

# Pinned Supabase CLI release — matches .github/actions/supabase-cli-setup.
# Bump both together.
ARG SUPABASE_CLI_VERSION=2.107.0
# Populated automatically by buildx (amd64 / arm64) — production (Hetzner
# cax21) is amd64; TARGETARCH keeps this Dockerfile buildable+verifiable
# (`supabase --version` actually EXECUTES below, not just downloaded) on an
# arm64 dev machine too, rather than hardcoding the one prod needs and
# leaving the RUN step unable to self-verify anywhere else.
ARG TARGETARCH

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tar \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL -o /tmp/supabase-cli.tar.gz \
       "https://github.com/supabase/cli/releases/download/v${SUPABASE_CLI_VERSION}/supabase_linux_${TARGETARCH}.tar.gz" \
    && tar -xzf /tmp/supabase-cli.tar.gz -C /usr/local/bin supabase \
    && chmod +x /usr/local/bin/supabase \
    && rm /tmp/supabase-cli.tar.gz \
    && supabase --version

WORKDIR /workspace

# The repo's supabase/ project layout, baked at build. `supabase db push`
# (run with --workdir /workspace, or from this WORKDIR) reads
# supabase/config.toml + supabase/migrations/**  from here — the SAME
# migration set this commit's CI already ran against a local stack.
# templates/ and tests/ are NOT copied: db push never reads either, and
# templates/ in particular can carry local-only interpolation this
# container must never see (keep the baked surface to what the apply verb
# actually consumes).
COPY supabase/config.toml supabase/config.toml
COPY supabase/migrations/ supabase/migrations/

# Resident Pattern-A keepalive — the Coolify Scheduled Task execs the real
# work into this container; it is never this image's own CMD/ENTRYPOINT.
# Matches workers/etl/Dockerfile and workers/provider-sync/Dockerfile.
CMD ["tail", "-f", "/dev/null"]
