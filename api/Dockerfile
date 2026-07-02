# syntax=docker/dockerfile:1
# ============================================================================
# mosko-fintech — V1 web-app container (SvelteKit + adapter-node)
# ----------------------------------------------------------------------------
# Multi-stage: build with the full toolchain, ship a slim Node runtime that
# serves adapter-node's `build/` output (`node build`, default port 3000).
# Deploys as the third container in the Lock 13 3-container topology on cax21
# (Coolify). Pinned base tag + npm ci + exec-form CMD + non-root user =
# hadolint-clean (repo pre-commit runs hadolint).
# ============================================================================

# ---- Stage 1: build ----
FROM node:22-bookworm-slim AS builder
WORKDIR /app

# Install deps from the lockfile first (better layer caching).
COPY package.json package-lock.json ./
RUN npm ci

# Build the SvelteKit app, then drop dev dependencies for the runtime copy.
COPY . .
RUN npm run build && npm prune --omit=dev

# ---- Stage 2: runtime ----
FROM node:22-bookworm-slim AS runner
WORKDIR /app
ENV NODE_ENV=production

# Copy only what the Node server needs to run, owned by the unprivileged user.
COPY --from=builder --chown=node:node /app/build ./build
COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --from=builder --chown=node:node /app/package.json ./package.json

USER node
EXPOSE 3000
CMD ["node", "build"]
