#!/usr/bin/env bash
#
# fence-migrator-private-bind — the `migrator` Coolify APPLICATION's own
# network-exposure config-lint. ADR-072 Amendment 4 (2026-09-16,
# F/CTO-ratified sentinel shape (1) — see DECISIONS.md's ADR-072 entry, the
# "ONE-WAY DOOR" paragraph). Sibling fence to
# scripts/ci/fence-datastore-private-bind.sh (RT-32) — SAME layer
# (network-exposure config-lint over a committed Coolify Compose manifest),
# DIFFERENT subject, and a DELIBERATELY DIFFERENT sentinel.
#
# ⚠ WHY THIS FILE EXISTS INSTEAD OF REUSING RT-32's SENTINEL, STATED SO IT
# IS NOT "FIXED" LATER: RT-32's sentinel (`fence-datastore-private-bind:
# target`) asserts a DATASTORE manifest — Postgres, its pooler, its
# gateway. `infra/supabase/migrator/docker-compose.yaml` is not a
# datastore; it is a one-service APPLICATION with no `ports:` and no
# published surface of any kind. Reusing RT-32's sentinel here would be
# exactly the layer-attribution drift ADR-011 Decision 4 catalogues —
# ADR-072 Amendment 4 named this choice explicitly and F/CTO ratified
# shape (1), a sibling fence with its own sentinel, over shape (2), a
# widened RT-32 sentinel covering two subjects (REJECTED as the one-way
# door — a widened sentinel cannot later be narrowed without leaving one
# manifest unfenced).
#
# Ships UNLABELED (no RT-NN) — minting a catalog id is an F/CTO
# ADR-011 Decision-4 ratify act on a Sec proposal, not taken by this PR
# (same precedent RT-32 itself followed from creation to ratify).
#
# ┌─ WHAT THIS FENCE ENFORCES ─────────────────────────────────────────────┐
# │ Over a COMMITTED Coolify Compose manifest describing the `migrator`    │
# │ APPLICATION (a one-service, no-inbound-traffic DDL-apply container —   │
# │ never a datastore, never a service with a legitimate inbound reason),  │
# │ every service must carry:                                              │
# │   - NO `ports:` key AT ALL — unlike RT-32's datastore fence, there is  │
# │     no allowlisted exception here (no Studio-loopback analogue; this   │
# │     application has no UI surface of any kind). ANY `ports:` key is a  │
# │     violation, published-loopback or not.                              │
# │   - NO `expose:` key either — this application takes ZERO inbound      │
# │     connections, not even sibling-container reach; it is invoked ONLY  │
# │     by a Coolify Scheduled Task `docker exec`ing into it. An `expose:` │
# │     key here would be a change to the mechanism the docker-compose.yaml│
# │     header describes and needs its own review, not merely a passing   │
# │     fence — this fence rejects it structurally, same as `ports:`.      │
# │   - NO reverse-proxy Domain / Traefik `Host()` label / Coolify         │
# │     `SERVICE_FQDN_*` / `SERVICE_URL_*` magic requesting a public FQDN. │
# │   - NO `network_mode: host` (host-namespace bind, bypasses the project │
# │     network entirely).                                                 │
# │ Any of the above = a committed exposure vector → FAIL CLOSED.          │
# │                                                                          │
# │ This fence covers the COMMITTED-CONFIG exposure vector ONLY — a         │
# │ UI-added Domain is invisible to a compose-file grep; that vector needs │
# │ a live/deploy-time check, not this one (same carve-out as RT-32 and    │
# │ RT-27).                                                                 │
# └──────────────────────────────────────────────────────────────────────────┘
#
# VECTOR-1 PREDICATE (stricter than RT-32's — zero tolerance, no
# allowlist):
#   1. Locate every `ports:` OR `expose:` key at a service-nesting indent.
#   2. A `ports:`/`expose:` key that collects ZERO value lines -> exit 2
#      (structural, fail closed — a block the walker could not read must
#      never produce a pass).
#   3. Any `ports:` OR `expose:` key found AT ALL, with any value, is a
#      violation (exit 1). There is no allowlisted token — this
#      application publishes and exposes nothing, ever.
#
# Vectors 2 and 3 mirror fence-datastore-private-bind.sh's own (reverse-
# proxy Domain request; `network_mode: host`) — same structural fail-closed
# guards, same discipline, different sentinel and subject.
#
# TARGET-LOCATION FAIL-CLOSED: the target file MUST carry the sentinel line
#   `# fence-migrator-private-bind: target`
# proving it is an intended migrator-application manifest. A file missing
# the sentinel → exit 2 (refuse to emit a clean pass over an unmarked/
# renamed file). Both the real compose and every golden fixture carry the
# sentinel.
#
# Usage:
#   bash fence-migrator-private-bind.sh <compose-file-path>
#
# Exit codes:
#   0  — clean: no ports:, no expose:, no public FQDN, no host network mode.
#   1  — one or more committed exposure vectors found (fail-closed).
#   2  — argument / structural error: missing/empty/non-compose file, the
#        target sentinel is absent, or a `ports:`/`expose:` key's value
#        block could not be read (manifest cannot be confirmed — fail
#        closed).

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
# (2) Must carry the migrator-application-target sentinel — proves this is
#     an intended migrator-application manifest and not an unrelated/
#     renamed compose (e.g. the datastore's own, or someone else's).
#     Absent → fail closed.
if ! grep -Eq '^#[[:space:]]*fence-migrator-private-bind:[[:space:]]*target[[:space:]]*$' "$TARGET"; then
  echo "FATAL: migrator-application-target sentinel not found in $TARGET." >&2
  echo "Expected a line: '# fence-migrator-private-bind: target'" >&2
  echo "Refusing to emit a clean pass over an unmarked file (migrator-application" >&2
  echo "manifest cannot be confirmed). Failing closed." >&2
  exit 2
fi

VIOLATIONS=0

# --- Vector 1: ANY `ports:` or `expose:` key (no allowlist at all) ----------
# Unlike fence-datastore-private-bind.sh, this application has no
# legitimate reason to publish OR expose anything — it is invoked solely
# via `docker exec` by a Coolify Scheduled Task. A line-based grep cannot
# bind a `ports:`/`expose:` block to the service it belongs to, so this is
# deliberately NOT a regex-in-a-loop: it walks each block's value lines
# with awk, tracking "am I still inside this block" by indentation the way
# a single grep pattern cannot.
AWK_SCRIPT="$(mktemp)"
trap 'rm -f "$AWK_SCRIPT"' EXIT
cat > "$AWK_SCRIPT" <<'AWK_EOF'
function flush_block(    ) {
  if (block_lines == 0) {
    print "STRUCTURAL:" block_start ":" block_key
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
      print "VIOLATION:" block_key ":" NR ":" line
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
    block_key = "ports"
    print "VIOLATION:ports:" NR ":" line
    next
  }
  if (!in_block && indent > 0 && trimmed ~ /^expose:[ \t]*(#.*)?$/) {
    in_block = 1
    block_indent = indent
    block_lines = 0
    block_start = NR
    block_key = "expose"
    print "VIOLATION:expose:" NR ":" line
    next
  }
}
END {
  if (in_block) { flush_block() }
}
AWK_EOF

AWK_OUT="$(awk -f "$AWK_SCRIPT" "$TARGET")"
rm -f "$AWK_SCRIPT"
trap - EXIT

# A `ports:`/`expose:` key with zero value lines is still a violation here
# (the key itself is forbidden, regardless of content) — but if the walker
# could not confirm even that much structurally, report it as structural
# rather than silently treating "key present, unreadable body" as a clean
# pass. In practice a bare `ports:`/`expose:` key line is ALSO reported as
# VIOLATION at the moment it is seen (see the awk script above), so the
# STRUCTURAL branch below only fires for a genuinely unreadable block —
# kept for parity with fence-datastore-private-bind.sh's own discipline.
STRUCTURAL_HIT="$(echo "$AWK_OUT" | grep '^STRUCTURAL:' || true)"
if [ -n "$STRUCTURAL_HIT" ]; then
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    rest="${s#STRUCTURAL:}"
    lineno="${rest%%:*}"
    key="${rest#*:}"
    echo "FATAL: '$key:' key at $TARGET:$lineno collected zero value lines — cannot confirm what it publishes/exposes; failing closed." >&2
  done <<< "$STRUCTURAL_HIT"
  exit 2
fi

echo "$AWK_OUT" | { grep '^VIOLATION:ports:' || true; } | while IFS= read -r h; do
  [ -z "$h" ] && continue
  rest="${h#VIOLATION:ports:}"
  echo "VIOLATION (vector 1: 'ports:' key present — this application publishes nothing, ever; no allowlist exists here):" >&2
  echo "  $TARGET:$rest" >&2
done
PORTS_COUNT="$(echo "$AWK_OUT" | grep -c '^VIOLATION:ports:' || true)"
VIOLATIONS=$((VIOLATIONS + PORTS_COUNT))

echo "$AWK_OUT" | { grep '^VIOLATION:expose:' || true; } | while IFS= read -r h; do
  [ -z "$h" ] && continue
  rest="${h#VIOLATION:expose:}"
  echo "VIOLATION (vector 1: 'expose:' key present — this application takes zero inbound connections of any kind, not even sibling-container reach):" >&2
  echo "  $TARGET:$rest" >&2
done
EXPOSE_COUNT="$(echo "$AWK_OUT" | grep -c '^VIOLATION:expose:' || true)"
VIOLATIONS=$((VIOLATIONS + EXPOSE_COUNT))

# --- Vector 2: reverse-proxy Domain / public-FQDN request --------------------
# Same predicate as fence-datastore-private-bind.sh's Vector 2. Comment
# lines (leading `#`) are skipped — documentation naming a pattern (this
# header, the compose's own explanatory comments) is not a live label.
PROXY_PATTERN='Host\(|traefik\.enable=true|traefik\.http\.routers|SERVICE_FQDN_|SERVICE_URL_|caddy_[0-9]+\.host'
PROXY_HITS=$(grep -EnH "$PROXY_PATTERN" "$TARGET" 2>/dev/null || true)
if [ -n "$PROXY_HITS" ]; then
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
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
# Same predicate as fence-datastore-private-bind.sh's Vector 3.
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
  echo "FAILED: $VIOLATIONS committed exposure vector(s) in $TARGET." >&2
  echo "The migrator application must take ZERO inbound connections of any kind —" >&2
  echo "no ports:, no expose:, no public Domain, no host network mode. See" >&2
  echo "scripts/ci/fence-migrator-private-bind.sh header." >&2
  exit 1
fi

echo "OK: $TARGET — migrator application takes zero inbound connections (no ports:, no expose:, no public Domain, no host network mode)."
exit 0
