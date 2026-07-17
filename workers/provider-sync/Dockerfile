# workers/provider-sync/Dockerfile
#
# Provider-sync worker container — V1 per-user account ingest (Plaid PRIMARY +
# SimpleFIN FALLBACK per ADR-027 gate (i)). The 4th Coolify deployed unit, added
# alongside the SvelteKit web app (api/), the Python ETL (workers/etl/), and the
# PDF worker (workers/pdf-render/).
#
# Lock anchors:
#   - ADR-019 amendment (F/CTO-ratified 2026-07-17): additive Node/TS sibling
#     worker; the FIRST DB-touching Node worker in the monorepo.
#   - ADR-011 Decision 17 / Lock 13 (hybrid multi-container topology on the
#     greenfield Coolify host).
#   - ADR-011 Lock 13 mod #3 — TenantBoundClient is the ONLY sanctioned Postgres
#     entry point (enforced at PR-time by scripts/ci/fence-tbc-node.sh).
#   - ADR-023 (pfin service_role role-of-record) + SECURITY §4.1.
#
# ┌─ POSTURE — the OPPOSITE of workers/pdf-render/ ─────────────────────────────┐
# │ This worker LEGITIMATELY has database reach. Do NOT apply the PDF worker's    │
# │ RT-22 zero-DB Dockerfile audit here — that is a category error. RT-22 is      │
# │ specific to pdf-render (Lock 13 mod #2). provider-sync connects to Postgres   │
# │ DIRECTLY (postgres.js / node-postgres + PFIN_DB_PASSWORD) via TenantBoundClient.│
# │                                                                               │
# │ TRANSPORT CONSTRAINT (keeps this worker OFF the RT-26 allowlist):             │
# │   - Connect to pfin via DIRECT Postgres + PFIN_DB_PASSWORD.                    │
# │   - Do NOT set SUPABASE_SERVICE_ROLE_KEY here, and do NOT install/use          │
# │     @supabase/supabase-js. Either would (a) trip fence-tbc-node and (b) pull   │
# │     provider-sync onto the RT-26 SUPABASE_SERVICE_ROLE_KEY allowlist, which    │
# │     SECURITY §4.1 confines to api/src/. Direct Postgres keeps RT-26 there.     │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# STATUS: PLACEHOLDER scaffold shipped so the topology + CI-fence surface exist
# ahead of Backend's worker-source implementation (task #12 / SELF-197+). Backend
# extends this with the actual adapter + TenantBoundClient + sync-driver Node app
# code. The structure below is the load-bearing baseline (base image + env-var
# contract + native-cron entrypoint shape) that DevOps owns; the app code is
# Backend's. Coolify Base Directory = workers/provider-sync/.

FROM node:22-bookworm-slim

WORKDIR /app

# Environment — the provider-sync secret surface. Values are Coolify-injected at
# deploy time (greenfield VPS per ADR-021); NONE are baked into the image.
#   - PFIN_DB_* / PFIN_DB_PASSWORD : direct-Postgres transport to pfin (service_role
#     DB role per ADR-023; TenantBoundClient binds users_id per Lock 13 mod #3).
#   - PLAID_CLIENT_ID / PLAID_SECRET : Plaid primary provider (production tier gated
#     by SELF-212).
#   - SIMPLEFIN_TOKEN : SimpleFIN fallback provider access token/URL.
#   - DISCORD_WEBHOOK_URL : Coolify->Discord failure/health routing (incumbent).
#
# DO NOT add SUPABASE_SERVICE_ROLE_KEY (RT-26 confinement — see posture block).
ARG PFIN_DB_HOST
ARG PFIN_DB_PORT
ARG PFIN_DB_NAME
ARG PFIN_DB_USER
ARG PFIN_DB_PASSWORD
ARG PLAID_CLIENT_ID
ARG PLAID_SECRET
ARG SIMPLEFIN_TOKEN
ENV PFIN_DB_HOST=${PFIN_DB_HOST} \
    PFIN_DB_PORT=${PFIN_DB_PORT} \
    PFIN_DB_NAME=${PFIN_DB_NAME} \
    PFIN_DB_USER=${PFIN_DB_USER} \
    PFIN_DB_PASSWORD=${PFIN_DB_PASSWORD} \
    PLAID_CLIENT_ID=${PLAID_CLIENT_ID} \
    PLAID_SECRET=${PLAID_SECRET} \
    SIMPLEFIN_TOKEN=${SIMPLEFIN_TOKEN}

# Dependency install lands here when Backend adds package.json + the lockfile:
#   COPY package.json package-lock.json ./
#   RUN npm ci --omit=dev
# Then the built app:
#   COPY dist/ dist/
# The Postgres driver (postgres.js or pg) is a LEGITIMATE dependency here (unlike
# pdf-render). @supabase/supabase-js is NOT — see posture block.

# Scheduled sync runs as a native Coolify cron container (same mechanism as the
# ETL poll + the monthly_report cron per Gate F); keep the container resident and
# let Coolify's scheduler trigger the sync entrypoint. Backend replaces this
# placeholder with the real entrypoint at implementation.
CMD ["node", "--version"]
