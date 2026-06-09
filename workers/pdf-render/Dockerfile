# workers/pdf-render/Dockerfile
#
# PDF worker container — V1 PDF generation surface.
#
# Lock anchors:
#   - ADR-011 Decision 17 / Lock 13 (hybrid 3-container topology — PDF worker is
#     the third container; Puppeteer browser-context-per-render hitting V1 app
#     /internal/pdf-render under short-lived signed JWT).
#   - Lock 13 mod #2 — ZERO-DB-ISOLATION: NO SUPABASE_* env vars; NO Postgres
#     client installed. The single permitted env var is PDF_WORKER_SIGNING_KEY
#     per SD-20.
#   - SECURITY §4.5 RT-22 entry — Dockerfile-credential-absence audit (this file).
#   - RT-22 CI fence at scripts/ci/fence-rt22-pdf-worker-dockerfile.sh enforces
#     credential absence + Postgres-client-install absence on every PR.
#
# W1 STATUS: this is a PLACEHOLDER Dockerfile shipped as part of Phase 5 Step 4 W1
# so the RT-22 fence has a real target to audit (rather than no-op'ing when the
# Dockerfile doesn't exist). Backend (Wave 6 PDF worker implementation work)
# extends this with the actual Puppeteer + Node application code. The structure
# below is the load-bearing baseline that the RT-22 fence will continue to enforce
# as Backend extends.

FROM node:20-bookworm-slim

WORKDIR /app

# Environment — ONLY PDF_WORKER_SIGNING_KEY per SD-20 + Lock 13 mod #2.
# DO NOT add any SUPABASE_* env vars here; the RT-22 fence will fail-closed
# at PR-time per ARCH §6 Security scan stage (iii).
ARG PDF_WORKER_SIGNING_KEY
ENV PDF_WORKER_SIGNING_KEY=${PDF_WORKER_SIGNING_KEY}

# DO NOT add any Postgres client install commands here (psycopg2 / psycopg2-binary
# / asyncpg / pg / node-postgres / postgresql-client). RT-22 enforces absence at
# PR-time. The PDF worker reaches the data layer ONLY via the V1 web-app's
# /internal/pdf-render endpoint under the short-lived signed JWT per Lock 13 mod #1.
#
# Puppeteer + system Chromium dependencies will land here when Backend extends
# this Dockerfile at Wave 6. Those are NOT Postgres clients; they don't trip RT-22.

# Placeholder entrypoint — replaced at Wave 6 PDF worker implementation.
CMD ["node", "--version"]
