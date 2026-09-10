#!/usr/bin/env bash
#
# fence-datastore-private-bind — self-hosted Supabase compose network-exposure
# config-lint. Sec-mandated (2026-09-10 ruling, relayed by team-lead) after a
# live production incident: infra/supabase/docker-compose.yml originally
# published api-gw on host port 8000 (colliding with Coolify's own dashboard —
# the deploy failure that surfaced this) and supavisor on host ports
# 5432/6543 (a multi-tenant Postgres's wire protocol + pooler proxy directly
# on the host's public interface, unreachable that day only because the
# Hetzner cloud firewall happened to filter those ports — not by anything in
# this stack's own config). See docs/deployment-runbook.md §4 (1d).
#
# Lock anchors:
#   - Sec ruling 2026-09-10 (relayed via team-lead): delete the published
#     ports:, expose:-only; do NOT ufw (Docker DNAT bypasses it — measured
#     live); build this as a fence, own sentinel, NOT a reuse of
#     fence-admission-private-bind's sentinel (that one asserts an ADMISSION
#     MANIFEST per RT-27 — a credential-admission channel; this one asserts a
#     DATASTORE manifest. Same layer (network-exposure config-lint), different
#     subject. Reusing the admission sentinel would be exactly the
#     layer-attribution drift ADR-011 Decision 4 catalogues).
#   - Models scripts/ci/fence-admission-private-bind.sh's shape (same three
#     vectors, same structural fail-closed guards) — NOT its sentinel, NOT its
#     §10/RT attribution. This file carries NO RT-NN string anywhere: whether
#     this exposure class earns a catalog entry (and a fourth §10 instance) is
#     a separate F/CTO Decision-4-ratify + docs/SECURITY/index.html step, not
#     performed here. Label this job with an RT id only after that entry lands.
#
# ┌─ WHAT THIS FENCE ENFORCES ─────────────────────────────────────────────────┐
# │ Over a COMMITTED Coolify Compose manifest describing a datastore/infra       │
# │ stack (Postgres, its pooler, its gateway — anything with no legitimate      │
# │ reason to answer requests from the public internet), every service must    │
# │ stay INTERNAL-ONLY:                                                         │
# │   - it may `expose:` its port (sibling-container reach on the project net); │
# │   - it must NOT `ports:`-publish to the host (public reach) — a loopback    │
# │     `127.0.0.1:<port>:<port>` bind is STILL a violation: this fence checks  │
# │     committed config shape only, and Sec's ruling treats even the bounded   │
# │     loopback fallback as a decision to make explicitly with Sec at that     │
# │     time, not a standing allowance baked into the fence;                    │
# │   - it must NOT carry a reverse-proxy Domain / Traefik `Host()` label / a   │
# │     Coolify `SERVICE_FQDN_*` / `SERVICE_URL_*` magic requesting a public    │
# │     FQDN;                                                                   │
# │   - it must NOT set `network_mode: host` (host-namespace bind, bypasses     │
# │     the project network + the expose:/ports: distinction).                  │
# │ Any of the latter three = a committed exposure vector → FAIL CLOSED.        │
# │                                                                              │
# │ This fence covers the COMMITTED-CONFIG exposure vector ONLY — same scope    │
# │ carve-out as fence-admission-private-bind (a UI-added Domain is invisible   │
# │ to a compose-file grep; that vector needs a live/deploy-time check, not     │
# │ this one).                                                                  │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# TARGET-LOCATION FAIL-CLOSED: the target file MUST carry the sentinel line
#   `# fence-datastore-private-bind: target`
# proving it is an intended datastore manifest. A file missing the sentinel →
# exit 2 (refuse to emit a clean pass over an unmarked/renamed file). Both the
# real compose and every golden fixture carry the sentinel.
#
# Usage:
#   bash fence-datastore-private-bind.sh <compose-file-path>
#
# Exit codes:
#   0  — clean: internal-only (expose:-only, no host-publish, no public FQDN).
#   1  — one or more committed public-exposure vectors found (fail-closed).
#   2  — argument / structural error: missing/empty/non-compose file, or the
#        target sentinel is absent (datastore manifest cannot be confirmed).

set -euo pipefail

TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  echo "FATAL: missing target compose-file arg." >&2
  echo "Usage: bash $(basename "$0") <compose-file-path>" >&2
  exit 2
fi
if [ ! -f "$TARGET" ]; then
  echo "FATAL: target compose file not found: $TARGET" >&2
  exit 2
fi
if [ ! -s "$TARGET" ]; then
  echo "FATAL: target compose file is empty: $TARGET (failing closed)." >&2
  exit 2
fi

# --- Structural fail-closed guards ------------------------------------------
# (1) Must be a compose manifest (has a top-level `services:` key). A refactor
#     that points the fence at a non-compose file must not silently pass.
if ! grep -Eq '^[[:space:]]*services:[[:space:]]*$' "$TARGET"; then
  echo "FATAL: no top-level 'services:' key in $TARGET — not a compose manifest; failing closed." >&2
  exit 2
fi
# (2) Must carry the datastore-target sentinel — proves this is an intended
#     datastore manifest and not an unrelated/renamed compose. Absent → fail closed.
if ! grep -Eq '^#[[:space:]]*fence-datastore-private-bind:[[:space:]]*target[[:space:]]*$' "$TARGET"; then
  echo "FATAL: datastore-target sentinel not found in $TARGET." >&2
  echo "Expected a line: '# fence-datastore-private-bind: target'" >&2
  echo "Refusing to emit a clean pass over an unmarked file (datastore manifest cannot" >&2
  echo "be confirmed). Failing closed." >&2
  exit 2
fi

VIOLATIONS=0

# --- Vector 1: published host-port mapping (`ports:`) ------------------------
# `expose:` (internal) is ALLOWED; `ports:` (host-publish, including a bounded
# 127.0.0.1 loopback form) is FORBIDDEN. Match the compose `ports:` key at a
# service-nesting indent. Anchored to the key so a value line like
# `- "5432:5432"` under `expose:` is NOT matched, and the word `ports` inside
# a comment/other-key is not matched.
PORTS_HITS=$(grep -En '^[[:space:]]+ports:[[:space:]]*(#.*)?$' "$TARGET" 2>/dev/null || true)
if [ -n "$PORTS_HITS" ]; then
  echo "VIOLATION (vector 1: published host-port mapping — use expose:, not ports:):" >&2
  while IFS= read -r h; do
    [ -z "$h" ] && continue
    echo "  $TARGET:$h" >&2
    VIOLATIONS=$((VIOLATIONS+1))
  done <<< "$PORTS_HITS"
fi

# --- Vector 2: reverse-proxy Domain / public-FQDN request --------------------
# Any of: Traefik Host() rule, traefik.enable=true, Coolify SERVICE_FQDN_* /
# SERVICE_URL_* magic (requesting a public domain), or a Caddy-style Host label.
# Comment lines (leading `#`) are skipped — documentation naming a pattern (this
# header, the compose's own explanatory comments) is not a live label.
PROXY_PATTERN='Host\(|traefik\.enable=true|traefik\.http\.routers|SERVICE_FQDN_|SERVICE_URL_|caddy_[0-9]+\.host'
PROXY_HITS=$(grep -EnH "$PROXY_PATTERN" "$TARGET" 2>/dev/null || true)
if [ -n "$PROXY_HITS" ]; then
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    # hit form: <file>:<lineno>:<content>
    content=$(echo "$hit" | cut -d: -f3-)
    stripped=$(echo "$content" | sed 's/^[[:space:]]*//')
    case "$stripped" in
      \#*) continue ;;  # comment line — documentation, not a live label
    esac
    echo "VIOLATION (vector 2: reverse-proxy Domain / public-FQDN request):" >&2
    echo "  $hit" >&2
    VIOLATIONS=$((VIOLATIONS+1))
  done <<< "$PROXY_HITS"
fi

# --- Vector 3: host-network mode (`network_mode: host`) ----------------------
# `network_mode: host` drops the container onto the HOST network namespace —
# the service then binds directly on the host's interfaces, bypassing the
# project Docker network AND the expose:/ports: distinction entirely (a
# committed host-level exposure vector). Forbidden. Value may be quoted;
# comment lines skipped.
HOSTNET_HITS=$(grep -EnH '^[[:space:]]*network_mode:[[:space:]]*["'"'"']?host["'"'"']?[[:space:]]*(#.*)?$' "$TARGET" 2>/dev/null || true)
if [ -n "$HOSTNET_HITS" ]; then
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    content=$(echo "$hit" | cut -d: -f3-)
    stripped=$(echo "$content" | sed 's/^[[:space:]]*//')
    case "$stripped" in
      \#*) continue ;;  # comment line — documentation, not a live setting
    esac
    echo "VIOLATION (vector 3: host-network mode — bypasses the project network):" >&2
    echo "  $hit" >&2
    VIOLATIONS=$((VIOLATIONS+1))
  done <<< "$HOSTNET_HITS"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "FAILED: $VIOLATIONS committed public-exposure vector(s) in $TARGET." >&2
  echo "This datastore/infra service must stay INTERNAL-ONLY (expose:-only, no" >&2
  echo "host-publish — not even a loopback bind, no public Domain). See" >&2
  echo "scripts/ci/fence-datastore-private-bind.sh header." >&2
  exit 1
fi

echo "OK: $TARGET — datastore service(s) internal-only (expose:-only, no host-publish, no public Domain)."
exit 0
