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
# SELF-348 (A4) STATUS: EXTENDED, not scaffolded, per that issue's own AC —
# "the word is extend, never scaffold." The RT-22 fence's criterion (i) — no
# SUPABASE_* ENV/ARG — keys on the exact ARG/ENV block below, UNCHANGED in
# place and position (AC item 1: "Do not restructure the ENV/ARG block").
# Everything added around it is Puppeteer + system Chromium + this worker's
# own Node application code (src/); nothing in this file is a Postgres client
# or a SUPABASE_* variable — RT-22 + the RT-22-manifest fence both audit this
# file/its package.json on every PR.

# Base image bumped 20 -> 22 from the placeholder (the ENV/ARG block below is
# what the AC forbids restructuring; the FROM line is not it). Forced by
# puppeteer-core's own dependency chain: the version that clears a real `npm
# audit` high-severity finding (extract-zip path traversal via
# @puppeteer/browsers, CVE-class GHSA-jmr9-qjv8-65gv — reachable only through
# puppeteer's browser-download code path, which this worker never calls since
# it launches system Chromium via PUPPETEER_EXECUTABLE_PATH, but present in
# the dependency tree regardless and would trip any package.json/lockfile
# vuln scan) requires Node >=22.12 (measured: `npm install` under Node 20
# succeeds with an EBADENGINE warning, not a hard failure, but "warns and
# might work" is not the bar for a Sec-joint-review-mandatory surface).
# node:22-bookworm-slim is current Debian-bookworm-based Node LTS.
FROM node:22-bookworm-slim

WORKDIR /app

# System Chromium + its runtime shared-library dependencies (apt resolves the
# full transitive set — ~40 packages — automatically; not individually listed
# here the way some Puppeteer Docker recipes do, because Debian's own
# dependency resolution IS that list, kept in sync by apt rather than by hand).
# `--no-install-recommends` keeps the image to what Chromium actually needs to
# run headless, not its desktop-integration extras (a smaller attack surface,
# not a functional requirement). NOT a Postgres client — does not trip RT-22.
# Versions pinned (hadolint DL3008) to the Debian bookworm candidates measured
# at authoring time (2026-09-05, arm64 + amd64 both carry these in bookworm's
# repos) — reproducible builds trade against staying current with Debian's own
# security patches automatically; bumping this pin is a routine maintenance
# task, not a one-way door.
RUN apt-get update && apt-get install -y --no-install-recommends \
      chromium=152.0.7977.75-1~deb12u1 \
      fonts-liberation=1:1.07.4-11 \
    && rm -rf /var/lib/apt/lists/*

# Environment — ONLY PDF_WORKER_SIGNING_KEY per SD-20 + Lock 13 mod #2.
# DO NOT add any SUPABASE_* env vars here; the RT-22 fence will fail-closed
# at PR-time per ARCH §6 Security scan stage (iii).
ARG PDF_WORKER_SIGNING_KEY
ENV PDF_WORKER_SIGNING_KEY=${PDF_WORKER_SIGNING_KEY}

# DO NOT add any Postgres client install commands here (psycopg2 / psycopg2-binary
# / asyncpg / pg / node-postgres / postgresql-client). RT-22 enforces absence at
# PR-time. Under the R2 (C) ruling (docs/records/v15-preflight/sitting-log.md
# § R2) this worker has NO database reach BY DESIGN and NO endpoint reaches for
# one — "a PDF printer, nothing else" — this fence stops being a constraint the
# worker must respect and becomes a description of what it is.

# Not SUPABASE_*-namespaced (does not trip RT-22 criterion (i)) — the system
# Chromium binary's location, so puppeteer-core (which bundles no Chromium of
# its own) knows what to launch. `--headless=new` is set at launch time
# (src/render.js), not baked into this variable.
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium

# Dependency manifest FIRST, app source second — the RT-22-manifest fence
# (scripts/ci/fence-rt22-pdf-worker-manifest.sh, SELF-350 A6) audits
# package.json + package-lock.json for a Postgres-client or DB-driver-bundling
# ORM package (pg / postgres / node-postgres / @supabase/supabase-js /
# @supabase/postgrest-js / knex / sequelize) — none is a dependency of this
# worker (see package.json: puppeteer-core + jsonwebtoken, nothing else).
# `npm ci` (not `npm install`) — reproducible from the committed lockfile.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY src/ ./src/

EXPOSE 8080

CMD ["node", "src/server.js"]
