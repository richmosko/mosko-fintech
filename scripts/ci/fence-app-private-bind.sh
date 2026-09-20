#!/usr/bin/env bash
#
# fence-app-private-bind — the `app` (V1 web-app) Coolify APPLICATION's own
# network-exposure config-lint, over its committed `api/docker-compose.yaml`.
# F/CTO ruling 2026-09-19 (docs/deployment-runbook.md Open Flags #12, option
# A — `app` becomes a `dockercompose` resource with an `external:` network
# attachment to the Supabase stack, the migrator's own proven shape).
# DevOps-owned. Sibling fence to scripts/ci/fence-migrator-private-bind.sh —
# SAME layer (network-exposure config-lint over a committed Coolify Compose
# manifest), DIFFERENT subject, and a DELIBERATELY DIFFERENT predicate.
#
# ⚠ WHY THIS IS NOT fence-migrator-private-bind.sh REUSED, OR WIDENED:
# `expose:` is FORBIDDEN in the migrator fence (that container takes ZERO
# legitimate inbound connections of any kind) but is REQUIRED-SHAPED and
# ALLOWED here — `app` is the fleet's one user-facing surface, and Coolify's
# Traefik reaches a `dockercompose` application's container over the
# project's own Docker network on the port that container `expose:`s; that
# IS the mechanism a public Domain routes through, not an exposure alongside
# it. Reusing the migrator's zero-tolerance predicate here would make this
# fence permanently RED against the one file it is meant to protect — not a
# stricter fence, a broken one. Widening the migrator's sentinel to admit an
# `expose:`-allowed exception for one file would be the ADR-011 Decision 4
# layer-attribution drift this repo's own fences are built to avoid (a
# widened sentinel covering two different exposure postures cannot later be
# narrowed without leaving one manifest unfenced) — a sibling fence with its
# own sentinel is the shape F/CTO ratified for exactly this class of
# decision at ADR-072 Amendment 4, reused here without re-litigating it.
#
# Ships UNLABELED (no RT-NN) — minting a catalog id is an F/CTO ADR-011
# Decision-4 ratify act on a Sec proposal, not taken by this PR (same
# precedent RT-32 and fence-migrator-private-bind.sh both followed from
# creation to ratify).
#
# ┌─ WHAT THIS FENCE ENFORCES ─────────────────────────────────────────────┐
# │ Over a COMMITTED Coolify Compose manifest describing the `app`          │
# │ APPLICATION, every service must carry:                                 │
# │   - NO `ports:` key AT ALL — a HOST-port publish bypasses Coolify's own │
# │     Traefik proxy layer entirely, the exact class of incident §4 (1d)   │
# │     records for `api-gw` (`ports: - 8000:8000` collided with Coolify's  │
# │     own dashboard on the same host port). Public routing goes through   │
# │     Coolify's Domain/Traefik mechanism, over the exposed port, never a  │
# │     published host port.                                               │
# │   - NO reverse-proxy Domain / Traefik `Host()` label / Coolify          │
# │     `SERVICE_FQDN_*` / `SERVICE_URL_*` magic COMMITTED IN THIS FILE —   │
# │     `app`'s Domain is a Coolify-dashboard-managed resource setting      │
# │     (docs/deployment-runbook.md §2/§9's DNS cutover), never a compose-  │
# │     committed label; a label here would be a second, unreviewed route.  │
# │   - NO `network_mode: host` (host-namespace bind, bypasses the project  │
# │     network — and this file's own `external:` network attachment —     │
# │     entirely).                                                          │
# │   `expose:` IS PERMITTED and EXPECTED — not checked by this fence at    │
# │   all, unlike the migrator's fence (which forbids it outright).         │
# │                                                                          │
# │ ALSO ENFORCED — vector 4 (Sec, PR #833 joint review, via team-lead):    │
# │   the top-level `networks.default.name` MUST reference EXACTLY          │
# │   `${APP_STACK_NETWORK_NAME:?...}` — never a literal network name and   │
# │   never a different variable. Permitting `expose:` + a Domain leaves    │
# │   only two OTHER predicates (ports:, host-network); without this        │
# │   fourth one, a mistyped/foreign attachment (a hardcoded network name,  │
# │   or a variable that happens to resolve to some OTHER resource's        │
# │   network) would pass this fence cleanly while attaching `app` to the   │
# │   wrong Docker network entirely — a config-lint gap this predicate      │
# │   closes structurally, before it ever reaches a live deploy.            │
# │                                                                          │
# │ This fence covers the COMMITTED-CONFIG exposure vector ONLY — a UI-     │
# │ added Domain or a UI-toggled published port is invisible to a compose-  │
# │ file grep; that vector needs a live/deploy-time check, not this one     │
# │ (same carve-out as RT-32, RT-27, and fence-migrator-private-bind.sh).   │
# └──────────────────────────────────────────────────────────────────────────┘
#
# VECTOR-1 PREDICATE (ports: only — zero tolerance, no allowlist; `expose:`
# is intentionally NOT a vector in this fence):
#   1. Locate every `ports:` key at a service-nesting indent.
#   2. A `ports:` key that collects ZERO value lines -> exit 2 (structural,
#      fail closed — a block the walker could not read must never produce
#      a pass).
#   3. Any `ports:` key found AT ALL, with any value, is a violation
#      (exit 1). There is no allowlisted token.
#
# Vectors 2 and 3 mirror fence-migrator-private-bind.sh's own (reverse-proxy
# Domain request; `network_mode: host`) — same structural fail-closed
# guards, same discipline, different sentinel and subject.
#
# VECTOR-4 PREDICATE (external-network reference, this fence's own —
# fence-migrator-private-bind.sh has no equivalent, since the migrator's
# network name has no fixed variable-name contract the way `app`'s does):
#   1. Locate the top-level `networks:` key (column 0) and everything after
#      it in the file.
#   2. No top-level `networks:` key at all, or no `name:` line inside it ->
#      exit 2 (structural, fail closed — cannot confirm the reference).
#   3. The `name:` line's value must contain the literal substring
#      `${APP_STACK_NETWORK_NAME:?` -- any other value (a bare literal, a
#      different `${VAR}` reference, a `${VAR:-default}` fallback form
#      instead of the fail-loud `:?` form) is a violation (exit 1).
#
# TARGET-LOCATION FAIL-CLOSED: the target file MUST carry the sentinel line
#   `# fence-app-private-bind: target`
# proving it is an intended `app`-application manifest. A file missing the
# sentinel → exit 2 (refuse to emit a clean pass over an unmarked/renamed
# file). Both the real compose and every golden fixture carry the sentinel.
#
# Usage:
#   bash fence-app-private-bind.sh <compose-file-path>
#
# Exit codes:
#   0  — clean: no ports:, no public FQDN, no host network mode, and the
#        external network reference is exactly ${APP_STACK_NETWORK_NAME:?...}.
#   1  — one or more committed exposure/misattachment vectors found
#        (fail-closed).
#   2  — argument / structural error: missing/empty/non-compose file, the
#        target sentinel is absent, a `ports:` key's value block could not
#        be read, or the top-level `networks:`/`name:` reference could not
#        be located (manifest cannot be confirmed — fail closed).

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
if ! grep -Eq '^[[:space:]]*services:[[:space:]]*$' "$TARGET"; then
  echo "FATAL: no top-level 'services:' key in $TARGET — not a compose manifest; failing closed." >&2
  exit 2
fi
if ! grep -Eq '^#[[:space:]]*fence-app-private-bind:[[:space:]]*target[[:space:]]*$' "$TARGET"; then
  echo "FATAL: app-application-target sentinel not found in $TARGET." >&2
  echo "Expected a line: '# fence-app-private-bind: target'" >&2
  echo "Refusing to emit a clean pass over an unmarked file (app-application" >&2
  echo "manifest cannot be confirmed). Failing closed." >&2
  exit 2
fi

VIOLATIONS=0

# --- Vector 1: ANY `ports:` key (no allowlist; `expose:` NOT checked) ------
# A line-based grep cannot bind a `ports:` block to the service it belongs
# to, so this walks each block's value lines with awk, tracking "am I still
# inside this block" by indentation the way a single grep pattern cannot —
# same mechanism as fence-migrator-private-bind.sh's own walker, with the
# `expose:` branches removed (that key is permitted here).
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

  # Inline-value form (flow-sequence, YAML alias, or any other scalar on
  # the same line) and quoted-key form both count -- same coverage
  # fence-migrator-private-bind.sh's own walker carries (its item-25-class
  # golden fixtures apply identically here; this fence reuses the same
  # walker shape, only the key set differs).
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
    echo "VIOLATION (vector 2: reverse-proxy Domain / public-FQDN request committed in the manifest — app's Domain is a Coolify-dashboard setting, never compose-committed):" >&2
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
#     ${APP_STACK_NETWORK_NAME:?...} -- never a literal, never another var --
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
NAME_LINE="$(printf '%s\n' "$NETWORKS_BLOCK" | grep -E '^[[:space:]]*name:' | head -1)"
if [ -z "$NAME_LINE" ]; then
  echo "FATAL: top-level 'networks:' block in $TARGET has no 'name:' key — cannot confirm the external network reference; failing closed." >&2
  exit 2
fi
if ! printf '%s' "$NAME_LINE" | grep -qF '${APP_STACK_NETWORK_NAME:?'; then
  STRIPPED_NAME_LINE="$(printf '%s' "$NAME_LINE" | sed 's/^[[:space:]]*//')"
  echo "VIOLATION (vector 4: top-level networks block's name: does not reference \${APP_STACK_NETWORK_NAME:?...} — found: $STRIPPED_NAME_LINE):" >&2
  echo "  $TARGET" >&2
  VIOLATIONS=$((VIOLATIONS+1))
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "FAILED: $VIOLATIONS committed exposure/misattachment vector(s) in $TARGET." >&2
  echo "The app application must never publish a host port, commit a public-Domain" >&2
  echo "label, use host network mode, or attach to any network other than exactly" >&2
  echo "\${APP_STACK_NETWORK_NAME:?...}. See scripts/ci/fence-app-private-bind.sh" >&2
  echo "header (expose: IS allowed here, unlike the migrator's fence)." >&2
  exit 1
fi

echo "OK: $TARGET — app application commits no host-port publish, no public-Domain label, no host network mode (expose: permitted, not checked), and attaches to exactly \${APP_STACK_NETWORK_NAME:?...}."
exit 0
