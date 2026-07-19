#!/usr/bin/env bash
#
# fence-admission-private-bind — SELF-212 Option-C admission endpoint
# network-exposure config-lint (limb (b) of C6-1; RT-27's §10-catalogued
# network-exposure layer).
#
# Lock anchors:
#   - SELF-212 app→worker handoff, Option C (ADR-027 amendment (v); (hh) at build).
#   - Sec joint-review temp/self212-sec-c6-review.md — C6-1 limb (b) + CA-3/CA-5.
#   - ADR-011 Decision 4 §10 catalogued-instance ledger: RT-27 = THIRD instance
#     (network-exposure/config layer), distinct from RT-22 (infra-credential-presence,
#     first) + RT-26 (code-layer, second). Formalized at (hh); this file is the
#     ENFORCEMENT VENUE, not a §10 attribution surface.
#   - Models scripts/ci/fence-tbc-node.sh (dual-mode grep fence) + the
#     fence-rt22/rt26/secrets-nonoverlap inversion-guard shape.
#
# ┌─ WHAT THIS FENCE ENFORCES ─────────────────────────────────────────────────┐
# │ Over a COMMITTED Coolify Compose manifest describing the provider-sync        │
# │ admission service, the admission endpoint must stay INTERNAL-ONLY:            │
# │   - it may `expose:` its port (sibling-container reach on the project net);   │
# │   - it must NOT `ports:`-publish to the host (public reach);                  │
# │   - it must NOT carry a reverse-proxy Domain / Traefik `Host()` label / a     │
# │     Coolify `SERVICE_FQDN_*` / `SERVICE_URL_*` magic requesting a public FQDN;│
# │   - it must NOT set `network_mode: host` (host-namespace bind, bypasses the    │
# │     project network + the expose:/ports: distinction).                        │
# │ Any of the latter three = a committed exposure vector → FAIL CLOSED.          │
# │                                                                              │
# │ This fence covers the COMMITTED-CONFIG exposure vector ONLY. The UI-added-    │
# │ Domain vector (not visible in committed config) is covered by the worker's    │
# │ limb-(a) startup public-route env tripwire + the CA-2 deploy negative smoke.  │
# │ Multi-layer per Sec CA-3.                                                     │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# TARGET-LOCATION FAIL-CLOSED (Sec: "admission service cannot be located → fail
# closed"): the target file MUST carry the sentinel line
#   `# fence-admission-private-bind: target`
# proving it is the intended admission manifest. A file missing the sentinel →
# exit 2 (we refuse to emit a clean pass over an unmarked/renamed file). Both the
# real compose and every golden fixture carry the sentinel.
#
# Usage:
#   bash fence-admission-private-bind.sh <compose-file-path>
#
# Exit codes:
#   0  — clean: internal-only (expose:-only, no host-publish, no public FQDN).
#   1  — one or more committed public-exposure vectors found (fail-closed).
#   2  — argument / structural error: missing/empty/non-compose file, or the
#        target sentinel is absent (admission manifest cannot be confirmed).

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
# (2) Must carry the admission-target sentinel — proves this is the intended
#     admission manifest and not an unrelated/renamed compose. Absent → fail closed.
if ! grep -Eq '^#[[:space:]]*fence-admission-private-bind:[[:space:]]*target[[:space:]]*$' "$TARGET"; then
  echo "FATAL: admission-target sentinel not found in $TARGET." >&2
  echo "Expected a line: '# fence-admission-private-bind: target'" >&2
  echo "Refusing to emit a clean pass over an unmarked file (admission service cannot" >&2
  echo "be confirmed). Failing closed." >&2
  exit 2
fi

VIOLATIONS=0

# --- Vector 1: published host-port mapping (`ports:`) ------------------------
# `expose:` (internal) is ALLOWED; `ports:` (host-publish) is FORBIDDEN. Match the
# compose `ports:` key at a service-nesting indent. Anchored to the key so a value
# line like `- "8787:8787"` under `expose:` is NOT matched, and the word `ports`
# inside a comment/other-key is not matched.
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
# `network_mode: host` drops the container onto the HOST network namespace — the
# admission port then binds directly on the host's interfaces, bypassing the
# project Docker network AND the expose:/ports: distinction entirely (a committed
# host-level exposure vector). Forbidden. Value may be quoted; comment lines skipped.
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
  echo "The SELF-212 admission endpoint must stay INTERNAL-ONLY (expose:-only, no" >&2
  echo "host-publish, no public Domain). See scripts/ci/fence-admission-private-bind.sh header." >&2
  exit 1
fi

echo "OK: $TARGET — admission service is internal-only (expose:-only, no host-publish, no public Domain)."
exit 0
