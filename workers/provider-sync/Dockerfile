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
#   - ADR-027 slice-3b (sync scheduler): the `poll` entrypoint runs as a native
#     Coolify Scheduled Task on this resident container (V1 worker cron convention;
#     see docs/deployment-runbook.md §7).
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
# SECRETS: NONE are baked into the image (no ARG/ENV secret surface — matching
# workers/etl/Dockerfile). Coolify injects env at RUNTIME (deploy-time, greenfield
# VPS per ADR-021). The `poll` Scheduled Task's REQUIRED subset (confirmed against
# loadConfig()) = PFIN_DB_* (authenticator transport; writes AS service_role via
# SET LOCAL ROLE per ADR-023) + Plaid creds (PLAID_CLIENT_ID/PLAID_SECRET/PLAID_ENV,
# required-at-boot). NOT SIMPLEFIN_TOKEN (poll reads the stored Access URL from
# decrypted_source_credential; the bridge token is the `admit` entrypoint's concern
# in the full .env.example image contract). NEVER `SUPABASE_SERVICE_ROLE_KEY` (see
# posture block). Precise poll env-scoping: docs/deployment-runbook.md §7.

# --- Build stage: install ALL deps + compile TS → dist/ -----------------------
FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src/ src/
RUN npm run build

# --- Runtime stage: prod deps only + built dist/ ------------------------------
FROM node:22-bookworm-slim AS runtime
WORKDIR /app
# postgres.js is a LEGITIMATE prod dependency here (unlike pdf-render).
# @supabase/supabase-js is NOT a dependency — see posture block.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY --from=build /app/dist ./dist

# --- Cron via Coolify (Pattern A — the V1 worker cron convention) --------------
# The container stays RESIDENT; the scheduled sync is a native Coolify **Scheduled
# Task** (@daily) that runs `node dist/cli/poll.js` — which drives one poll pass
# across all poll-eligible linked_source rows and exits (design memo §1). This
# matches workers/etl/Dockerfile ("triggered via scheduled task"). A one-shot
# container is deliberately NOT used: Coolify has no one-shot-cron primitive, and
# an exited Application container restart-loops under Coolify's restart policy.
# The @daily cadence + the `node dist/cli/poll.js` command are Coolify UI config
# (deploy-time), documented in docs/deployment-runbook.md §7 — not baked here.
# Fleet-fatal → non-zero exit → Scheduled-Task failure → Coolify→Discord (incumbent);
# per-source errors stay audited + isolated in linked_source_sync_audit (no page).
CMD ["tail", "-f", "/dev/null"]
