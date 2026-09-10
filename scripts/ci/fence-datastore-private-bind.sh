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
#     §10/RT attribution. This file carries RT-32, per F/CTO Decision-4
#     ratify 2026-09-10 (relayed via team-lead; catalog entry
#     docs/SECURITY/index.html §4.5 in #724, ADR-008 record in #725).
#     Shipped unlabeled from creation until this ratify landed.
#
# ┌─ WHAT THIS FENCE ENFORCES ─────────────────────────────────────────────────┐
# │ Over a COMMITTED Coolify Compose manifest describing a datastore/infra       │
# │ stack (Postgres, its pooler, its gateway — anything with no legitimate      │
# │ reason to answer requests from the public internet), every service must    │
# │ stay INTERNAL-ONLY:                                                         │
# │   - it may `expose:` its port (sibling-container reach on the project net); │
# │   - it must NOT `ports:`-publish to the host, with ONE enumerated exception:│
# │     the exact literal mapping `- "127.0.0.1:3000:3000"` (Supabase Studio's  │
# │     SSH-tunnel loopback bind, Sec-elected 2026-09-10). Enumerated, not      │
# │     patterned: this fence is line-based and cannot bind a `ports:` block to │
# │     the service it belongs to, so a loopback-PREFIX rule would silently     │
# │     permit `127.0.0.1:5432:5432` on `db`. Changing the enumeration is a Sec │
# │     joint-review, not an edit — see scripts/ci/fence-datastore-private-bind │
# │     .sh's Vector-1 predicate below for exactly what else that buys;         │
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
# VECTOR-1 PREDICATE (exact-string enumeration, not a prefix match):
#   1. Locate every `ports:` key at a service-nesting indent.
#   2. For each, collect its value lines — every subsequent line more-indented
#      than the `ports:` key, stopping at the first line at or below that indent.
#   3. A `ports:` key that collects ZERO value lines -> exit 2 (structural,
#      fail closed). A block the walker could not read must never produce a pass.
#   4. Each collected line must be a scalar list item whose token — after
#      stripping the leading `- ` and any surrounding single/double quotes — is
#      BYTE-EXACTLY `127.0.0.1:3000:3000`. Anything else is a violation (exit 1):
#      a bare `3000:3000`; `0.0.0.0:3000:3000`; `[::1]:3000:3000`;
#      `127.0.0.1:5432:5432`; any `${VAR}` anywhere in the token; a port range;
#      a `/udp`/`/tcp` suffix.
#   5. Any collected line that OPENS A MAPPING (contains `target:`, `published:`,
#      `host_ip:`, `mode:`, or ends in `:`) is a violation — compose long syntax
#      can express a public bind, and the fence refuses forms it cannot evaluate
#      as one literal token rather than trying to parse them.
#   6. At most ONE permitted publish line per FILE. A second occurrence of the
#      allowlisted string is a violation — the allowance is for one service, and
#      the fence cannot tell which service a `ports:` block belongs to.
# Vectors 2 and 3 are unchanged by this amendment.
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
#   0  — clean: internal-only (expose:-only; no host-publish beyond at most one
#        exact `127.0.0.1:3000:3000` Studio loopback line; no public FQDN).
#   1  — one or more committed public-exposure vectors found (fail-closed).
#   2  — argument / structural error: missing/empty/non-compose file, the
#        target sentinel is absent, or a `ports:` key's value block could not
#        be read (datastore manifest cannot be confirmed — fail closed).
#
# ALLOWLISTED_LOOPBACK_TOKEN is the ONE literal Vector 1 exempts. Changing it
# is a Sec joint-review, not a config edit — see the Vector-1 predicate above.
ALLOWLISTED_LOOPBACK_TOKEN='127.0.0.1:3000:3000'

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
# `expose:` (internal) is ALLOWED. `ports:` is FORBIDDEN except for the one
# enumerated exact-string exception (see the Vector-1 predicate in the header).
# A line-based grep cannot bind a `ports:` block to the service it belongs to,
# so this is deliberately NOT a regex-in-a-loop: it walks each `ports:` block's
# value lines with awk, which can track "am I still inside this block" by
# indentation the way a single grep pattern cannot.
AWK_SCRIPT="$(mktemp)"
trap 'rm -f "$AWK_SCRIPT"' EXIT
cat > "$AWK_SCRIPT" <<'AWK_EOF'
function flush_block(    ) {
  if (block_lines == 0) {
    print "STRUCTURAL:" block_start
    structural = 1
  }
  in_block = 0
}
{
  line = $0
  n = match(line, /[^ ]/)
  if (n == 0) {
    indent = -1
    trimmed = ""
  } else {
    indent = n - 1
    trimmed = substr(line, n)
  }

  if (in_block) {
    if (indent == -1) { next }
    if (indent > block_indent) {
      block_lines++
      if (trimmed ~ /(^|[^A-Za-z0-9_])target:/ || \
          trimmed ~ /(^|[^A-Za-z0-9_])published:/ || \
          trimmed ~ /(^|[^A-Za-z0-9_])host_ip:/ || \
          trimmed ~ /(^|[^A-Za-z0-9_])mode:/ || \
          trimmed ~ /:[ \t]*$/) {
        print "LONGSYNTAX:" NR ":" line
        violations++
        next
      }
      tok = trimmed
      sub(/^-[ \t]*/, "", tok)
      gsub(/^["']/, "", tok)
      gsub(/["']$/, "", tok)
      if (tok == allow) {
        allowed++
        print "ALLOWED:" NR ":" line
      } else {
        print "VIOLATION:" NR ":" line
        violations++
      }
      next
    } else {
      flush_block()
    }
  }

  if (!in_block && indent > 0 && trimmed ~ /^ports:[ \t]*(#.*)?$/) {
    in_block = 1
    block_indent = indent
    block_lines = 0
    block_start = NR
    next
  }
}
END {
  if (in_block) { flush_block() }
  if (allowed > 1) {
    print "TOOMANY:" allowed
    violations++
  }
  print "SUMMARY:" violations ":" allowed ":" structural
}
AWK_EOF

AWK_OUT="$(awk -v allow="$ALLOWLISTED_LOOPBACK_TOKEN" -f "$AWK_SCRIPT" "$TARGET")"
rm -f "$AWK_SCRIPT"
trap - EXIT

# A `ports:` key with zero value lines is a structural failure, not a Vector-1
# violation — fail closed immediately, matching the sentinel/services: checks
# above (a block the walker could not read must never produce a pass).
STRUCTURAL_HIT="$(echo "$AWK_OUT" | grep '^STRUCTURAL:' || true)"
if [ -n "$STRUCTURAL_HIT" ]; then
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    lineno="${s#STRUCTURAL:}"
    echo "FATAL: 'ports:' key at $TARGET:$lineno collected zero value lines — cannot confirm what it publishes; failing closed." >&2
  done <<< "$STRUCTURAL_HIT"
  exit 2
fi

echo "$AWK_OUT" | { grep '^LONGSYNTAX:' || true; } | while IFS= read -r h; do
  [ -z "$h" ] && continue
  echo "VIOLATION (vector 1: 'ports:' long-syntax mapping — refused, cannot evaluate as one literal token):" >&2
  echo "  $TARGET:${h#LONGSYNTAX:}" >&2
done
echo "$AWK_OUT" | { grep '^VIOLATION:' || true; } | while IFS= read -r h; do
  [ -z "$h" ] && continue
  echo "VIOLATION (vector 1: published host-port mapping not the allowlisted Studio loopback — use expose:, not ports:):" >&2
  echo "  $TARGET:${h#VIOLATION:}" >&2
done
TOOMANY_HIT="$(echo "$AWK_OUT" | grep '^TOOMANY:' || true)"
if [ -n "$TOOMANY_HIT" ]; then
  echo "VIOLATION (vector 1: the allowlisted Studio loopback line appears more than once — the allowance is for ONE service):" >&2
  echo "  $TARGET: ${TOOMANY_HIT#TOOMANY:} occurrences of $ALLOWLISTED_LOOPBACK_TOKEN" >&2
fi

VECTOR1_SUMMARY="$(echo "$AWK_OUT" | grep '^SUMMARY:')"
VECTOR1_VIOLATIONS="$(echo "$VECTOR1_SUMMARY" | cut -d: -f2)"
VIOLATIONS=$((VIOLATIONS + VECTOR1_VIOLATIONS))

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
  echo "This datastore/infra service must stay INTERNAL-ONLY (expose:-only; the" >&2
  echo "ONLY permitted host-publish is the exact, single Studio loopback line" >&2
  echo "'- \"$ALLOWLISTED_LOOPBACK_TOKEN\"'; no public Domain). See" >&2
  echo "scripts/ci/fence-datastore-private-bind.sh header." >&2
  exit 1
fi

echo "OK: $TARGET — datastore service(s) internal-only (expose:-only, no public Domain; at most one exact Studio loopback publish)."
exit 0
