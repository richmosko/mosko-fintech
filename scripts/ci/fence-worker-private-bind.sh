#!/usr/bin/env bash
#
# fence-worker-private-bind — parametrised network-exposure config-lint for
# the three sibling worker Coolify APPLICATIONS (`etl`, `pdf-render`,
# `provider-sync`), over each worker's own committed docker-compose.yaml.
# BACKLOG.md §7.36 item 68 (F/CTO-ruled fleet convention, 2026-09-19;
# ADR-073). DevOps-owned.
#
# ONE PARAMETRISED SCRIPT, not three near-identical copies — the three
# worker manifests need the SAME four vectors checked
# (scripts/ci/fence-app-private-bind.sh's own four), differing only in
# WHICH sentinel proves the file's identity and WHICH env-var name the
# external-network reference must carry (each worker gets its OWN
# uniquely-named var — ETL_STACK_NETWORK_NAME / PDF_RENDER_STACK_NETWORK_NAME
# / PROVIDER_SYNC_STACK_NETWORK_NAME — same per-resource-name discipline as
# MIGRATOR_STACK_NETWORK_NAME / APP_STACK_NETWORK_NAME, never a shared var
# across resources). A three-copy fork of fence-app-private-bind.sh would
# drift the moment one of the three predicates was fixed and the other two
# weren't — this script is the single point of truth for the shared
# predicate, with the two axes of difference taken as arguments.
#
# ⚠ WHY THIS IS NOT fence-admission-private-bind.sh (RT-27) REUSED OR
# WIDENED: RT-27 audits the ADMISSION-ENDPOINT exposure surface on
# pdf-render/provider-sync (ports:/Domain/network_mode over the RENDER/
# ADMISSION port those two already `expose:`) — a DIFFERENT layer-
# attribution (§10-catalogued, network-exposure/config layer) than this
# fence's subject (the NETWORK-ATTACHMENT config-lint item 68 introduces,
# unlabeled, same class as fence-app-private-bind.sh). `etl` has no
# admission endpoint at all and RT-27 does not cover it; this fence is the
# ONLY private-bind check `etl`'s compose gets. Reusing RT-27's sentinel
# here would be the ADR-011 Decision 4 layer-attribution drift this repo's
# fences are built to avoid. `expose:` is intentionally NOT a vector this
# fence checks (same as fence-app-private-bind.sh) — pdf-render/
# provider-sync's own `expose:` is legitimate and governed by RT-27
# separately; etl's absence of `expose:` stays "by construction, not by
# fence" per that compose file's own existing header, unchanged here.
#
# Ships UNLABELED (no RT-NN) — minting a catalog id is an F/CTO ADR-011
# Decision-4 ratify act on a Sec proposal, not taken by this PR (same
# precedent RT-32, fence-migrator-private-bind.sh and
# fence-app-private-bind.sh all followed from creation to ratify).
#
# ┌─ WHAT THIS FENCE ENFORCES (identical to fence-app-private-bind.sh's own,
# │  parametrised by $2/$3) ────────────────────────────────────────────────┐
# │   - NO `ports:` key AT ALL — a HOST-port publish bypasses Coolify's own │
# │     Traefik proxy layer entirely.                                      │
# │   - NO reverse-proxy Domain / Traefik `Host()` label / Coolify          │
# │     `SERVICE_FQDN_*` / `SERVICE_URL_*` magic COMMITTED IN THIS FILE —   │
# │     none of the three workers is ever assigned a public Domain.        │
# │   - NO `network_mode: host` (host-namespace bind, bypasses the         │
# │     project network — and this file's own `external:` attachment —     │
# │     entirely).                                                          │
# │   `expose:` IS PERMITTED and NOT checked at all by this fence (matches │
# │   fence-app-private-bind.sh; see the note above for why).              │
# │                                                                          │
# │   - the top-level `networks.default.name` MUST reference EXACTLY        │
# │     `${<NETWORK_VAR>:?...}` (the var name is this script's own $3       │
# │     argument) — never a literal network name and never a different     │
# │     variable, including another worker's own var (a copy-paste from a  │
# │     sibling compose that forgot to rename the var would otherwise pass │
# │     this fence cleanly while attaching the wrong worker to the wrong    │
# │     name at deploy time).                                              │
# │                                                                          │
# │ This fence covers the COMMITTED-CONFIG exposure vector ONLY — a UI-     │
# │ added Domain or a UI-toggled published port is invisible to a compose-  │
# │ file grep; that vector needs a live/deploy-time check, not this one.    │
# └──────────────────────────────────────────────────────────────────────────┘
#
# Usage:
#   bash fence-worker-private-bind.sh <compose-file-path> <sentinel-slug> <network-var-name>
#
#   <sentinel-slug>     — e.g. "etl" / "pdf-render" / "provider-sync". The
#                          file must carry the line
#                          "# fence-<sentinel-slug>-private-bind: target".
#   <network-var-name>  — e.g. "ETL_STACK_NETWORK_NAME". The top-level
#                          networks.default.name value must contain the
#                          literal substring "${<network-var-name>:?".
#
# Exit codes:
#   0  — clean: no ports:, no public FQDN, no host network mode, and the
#        external network reference is exactly ${<network-var-name>:?...}.
#   1  — one or more committed exposure/misattachment vectors found
#        (fail-closed).
#   2  — argument / structural error: missing arg, missing/empty/non-compose
#        file, the target sentinel is absent, a `ports:` key's value block
#        could not be read, or the top-level `networks:`/`name:` reference
#        could not be located (manifest cannot be confirmed — fail closed).

set -euo pipefail

TARGET="${1:-}"
SENTINEL_SLUG="${2:-}"
NETWORK_VAR="${3:-}"

if [ -z "$TARGET" ] || [ -z "$SENTINEL_SLUG" ] || [ -z "$NETWORK_VAR" ]; then
  echo "FATAL: missing argument(s)." >&2
  echo "Usage: bash $(basename "$0") <compose-file-path> <sentinel-slug> <network-var-name>" >&2
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

SENTINEL_LINE="# fence-${SENTINEL_SLUG}-private-bind: target"

# --- Structural fail-closed guards ------------------------------------------
if ! grep -Eq '^[[:space:]]*services:[[:space:]]*$' "$TARGET"; then
  echo "FATAL: no top-level 'services:' key in $TARGET — not a compose manifest; failing closed." >&2
  exit 2
fi
if ! grep -Fxq "$SENTINEL_LINE" "$TARGET"; then
  echo "FATAL: ${SENTINEL_SLUG}-application-target sentinel not found in $TARGET." >&2
  echo "Expected a line: '$SENTINEL_LINE'" >&2
  echo "Refusing to emit a clean pass over an unmarked file (${SENTINEL_SLUG}-application" >&2
  echo "manifest cannot be confirmed). Failing closed." >&2
  exit 2
fi

VIOLATIONS=0

# --- Vector 1: ANY `ports:` key (no allowlist; `expose:` NOT checked) ------
# Same walker as fence-app-private-bind.sh's own vector 1 — a line-based
# grep cannot bind a `ports:` block to the service it belongs to, so this
# walks each block's value lines with awk, tracking "am I still inside this
# block" by indentation.
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

  if (!in_block && indent > 0 && trimmed ~ /^["\x27]?ports["\x27]?:[ \t]*[^ \t#]/) {
    print "VIOLATION:ports:" NR ":" line
    next
  }
  if (!in_block && indent > 0 && trimmed ~ /^["\x27]?ports["\x27]?:[ \t]*(#.*)?$/) {
    in_block = 1
    block_indent = indent
    block_lines = 0
    block_start = NR
    block_key = "ports"
    print "VIOLATION:ports:" NR ":" line
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

STRUCTURAL_HIT="$(echo "$AWK_OUT" | grep '^STRUCTURAL:' || true)"
if [ -n "$STRUCTURAL_HIT" ]; then
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    rest="${s#STRUCTURAL:}"
    lineno="${rest%%:*}"
    key="${rest#*:}"
    echo "FATAL: '$key:' key at $TARGET:$lineno collected zero value lines — cannot confirm what it publishes; failing closed." >&2
  done <<< "$STRUCTURAL_HIT"
  exit 2
fi

echo "$AWK_OUT" | { grep '^VIOLATION:ports:' || true; } | while IFS= read -r h; do
  [ -z "$h" ] && continue
  rest="${h#VIOLATION:ports:}"
  echo "VIOLATION (vector 1: 'ports:' key present — public routing goes through Coolify's Domain/Traefik mechanism over the exposed port, never a published host port):" >&2
  echo "  $TARGET:$rest" >&2
done
PORTS_COUNT="$(echo "$AWK_OUT" | grep -c '^VIOLATION:ports:' || true)"
VIOLATIONS=$((VIOLATIONS + PORTS_COUNT))

# --- Vector 2: reverse-proxy Domain / public-FQDN request --------------------
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
    echo "VIOLATION (vector 2: reverse-proxy Domain / public-FQDN request committed in the manifest — this worker is never assigned a public Domain):" >&2
    echo "  $hit" >&2
    VIOLATIONS=$((VIOLATIONS+1))
  done <<< "$PROXY_HITS"
fi

# --- Vector 3: host-network mode (`network_mode: host`) ----------------------
HOSTNET_HITS=$(grep -EnH '^[[:space:]]*network_mode:[[:space:]]*["'"'"']?host["'"'"']?[[:space:]]*(#.*)?$' "$TARGET" 2>/dev/null || true)
if [ -n "$HOSTNET_HITS" ]; then
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    content=$(echo "$hit" | cut -d: -f3-)
    stripped=$(echo "$content" | sed 's/^[[:space:]]*//')
    case "$stripped" in
      \#*) continue ;;  # comment line — documentation, not a live setting
    esac
    echo "VIOLATION (vector 3: host-network mode — bypasses the project network, including this file's own external: attachment):" >&2
    echo "  $hit" >&2
    VIOLATIONS=$((VIOLATIONS+1))
  done <<< "$HOSTNET_HITS"
fi

# --- Vector 4: top-level networks.default.name must be exactly
#     ${<NETWORK_VAR>:?...} -- never a literal, never another var, never a
#     second attached network, never a non-'default' key, never
#     'external: true' missing --
TOPLEVEL_NETWORKS_LINE="$(grep -n '^networks:[[:space:]]*$' "$TARGET" | head -1 | cut -d: -f1 || true)"
if [ -z "$TOPLEVEL_NETWORKS_LINE" ]; then
  echo "FATAL: no top-level 'networks:' key found in $TARGET — cannot confirm the external network reference; failing closed." >&2
  exit 2
fi
NETWORKS_BLOCK="$(awk -v start="$TOPLEVEL_NETWORKS_LINE" '
  NR==start { found=1; next }
  found {
    if ($0 ~ /^[^[:space:]]/) { exit }
    print
  }
' "$TARGET")"

# Sec F-2 (PR #844 joint review): a `head -1` on the first key/name: line
# silently passed (1) a second top-level network with the service attached
# to both, (2) a network key not named `default`, (3) `external: true`
# removed. Each of the three now asserts its own predicate instead of
# trusting whichever line a `head -1` happened to find first.
NETWORK_KEYS="$(printf '%s\n' "$NETWORKS_BLOCK" | grep -E '^  [A-Za-z0-9_.-]+:[[:space:]]*$' || true)"
NETWORK_KEY_COUNT="$(printf '%s\n' "$NETWORK_KEYS" | grep -c . || true)"
if [ "$NETWORK_KEY_COUNT" -eq 0 ]; then
  echo "FATAL: top-level 'networks:' block in $TARGET has no network key at 2-space indent — cannot confirm the external network reference; failing closed." >&2
  exit 2
fi
if [ "$NETWORK_KEY_COUNT" -gt 1 ]; then
  echo "FATAL: top-level 'networks:' block in $TARGET declares $NETWORK_KEY_COUNT network keys (multi-attachment) — this fence only confirms a SINGLE 'default:' attachment; a second attached network is a committed misattachment vector, not something this fence may pass silently. Failing closed." >&2
  printf '%s\n' "$NETWORK_KEYS" | sed 's/^/  /' >&2
  exit 2
fi
NETWORK_KEY_NAME="$(printf '%s' "$NETWORK_KEYS" | sed -E 's/^[[:space:]]*([A-Za-z0-9_.-]+):.*/\1/')"
if [ "$NETWORK_KEY_NAME" != "default" ]; then
  echo "FATAL: top-level 'networks:' block in $TARGET declares its one network key as '$NETWORK_KEY_NAME', not 'default' — cannot confirm the expected networks.default.name/external attachment under a renamed key. Failing closed." >&2
  exit 2
fi

# Everything inside the 'default:' key's own block, one indent level deeper.
DEFAULT_BLOCK="$(printf '%s\n' "$NETWORKS_BLOCK" | awk '
  function indent_of(l,    n) { n = match(l, /[^ ]/); return (n == 0) ? -1 : n - 1 }
  {
    ind = indent_of($0)
    if (!found) {
      if ($0 ~ /^  default:[[:space:]]*$/) { found = 1; base = ind }
      next
    }
    if (ind == -1) { next }
    if (ind <= base) { exit }
    print
  }
')"

NAME_LINES="$(printf '%s\n' "$DEFAULT_BLOCK" | grep -E '^[[:space:]]*name:' || true)"
NAME_LINE_COUNT="$(printf '%s\n' "$NAME_LINES" | grep -c . || true)"
if [ "$NAME_LINE_COUNT" -eq 0 ]; then
  echo "FATAL: top-level 'networks.default' block in $TARGET has no 'name:' key — cannot confirm the external network reference; failing closed." >&2
  exit 2
fi
if [ "$NAME_LINE_COUNT" -gt 1 ]; then
  echo "FATAL: top-level 'networks.default' block in $TARGET declares $NAME_LINE_COUNT 'name:' lines — cannot confirm which is authoritative; failing closed." >&2
  exit 2
fi
NAME_LINE="$NAME_LINES"

EXTERNAL_LINE="$(printf '%s\n' "$DEFAULT_BLOCK" | grep -E '^[[:space:]]*external:[[:space:]]*true[[:space:]]*(#.*)?$' || true)"
if [ -z "$EXTERNAL_LINE" ]; then
  echo "VIOLATION (vector 4b: top-level networks.default block is missing 'external: true' — Docker would CREATE a new network by that name rather than join the stack's; a resolution failure must never be 'fixed' by removing this line):" >&2
  echo "  $TARGET" >&2
  VIOLATIONS=$((VIOLATIONS+1))
fi

EXPECTED_REF='${'"${NETWORK_VAR}"':?'
if ! printf '%s' "$NAME_LINE" | grep -qF "$EXPECTED_REF"; then
  STRIPPED_NAME_LINE="$(printf '%s' "$NAME_LINE" | sed 's/^[[:space:]]*//')"
  echo "VIOLATION (vector 4: top-level networks block's name: does not reference \${${NETWORK_VAR}:?...} — found: $STRIPPED_NAME_LINE):" >&2
  echo "  $TARGET" >&2
  VIOLATIONS=$((VIOLATIONS+1))
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "FAILED: $VIOLATIONS committed exposure/misattachment vector(s) in $TARGET." >&2
  echo "This worker must never publish a host port, commit a public-Domain label," >&2
  echo "use host network mode, or attach to any network other than exactly" >&2
  echo "\${${NETWORK_VAR}:?...}. See scripts/ci/fence-worker-private-bind.sh header." >&2
  exit 1
fi

echo "OK: $TARGET — ${SENTINEL_SLUG} worker commits no host-port publish, no public-Domain label, no host network mode (expose: permitted, not checked), and attaches to exactly \${${NETWORK_VAR}:?...}."
exit 0
