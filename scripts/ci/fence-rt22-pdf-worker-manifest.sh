#!/usr/bin/env bash
#
# RT-22 — PDF worker dependency-manifest audit (SELF-350 A6, re-scoped at R6)
#
# Lock anchors:
#   - ADR-011 Decision 17 / Lock 13 mod #2 (zero-DB-isolation)
#   - SECURITY §4.5 RT-22 entry
#   - ARCH §6 Security scan stage (iii) + ARCH §6.1 RT-22 row
#
# Relationship to fence-rt22-pdf-worker-dockerfile.sh (R6 rider 1 — the gap this
# fence closes is cited verbatim from that fence's own header):
#   "COPY of package.json / requirements.txt manifests (install intent revealed
#    at RUN time, not COPY time; manifest inspection is human-second-line)."
# The Dockerfile fence deliberately does not open and read the manifest it
# COPYs — it only greps RUN-verb install commands. This fence closes exactly
# that gap by parsing the manifest and lockfile directly. The Dockerfile fence
# is unmodified by this work.
#
# Catch criterion: workers/pdf-render/package.json `dependencies`,
# `devDependencies`, `optionalDependencies` and `peerDependencies`, AND
# package-lock.json's fully resolved dependency tree (direct + transitive),
# must not name a Postgres-client or DB-driver-bundling ORM package: pg,
# postgres, node-postgres, @supabase/supabase-js, @supabase/postgrest-js,
# knex, sequelize. Fail-closed: exit 1 on any hit, in either the manifest or
# the lockfile.
#
# Evasion coverage (Sec F-3, joint-review 2026-09-05):
#   (a) npm alias — a manifest entry like `"db": "npm:pg@^8"` installs `pg`
#       under a non-denylisted key name. Manifest values are checked for the
#       `npm:<name>@<spec>` alias form and the ALIASED name is what's tested
#       against the denylist. Symmetrically, a lockfile `packages` entry is
#       identified by up to three independent signals — its own key's last
#       `node_modules/` path segment, its `name` field (npm writes this when
#       the install-tree folder name and the real package name diverge, which
#       is exactly what an alias produces), and the package name parsed from
#       its `resolved` tarball URL (the path segment(s) immediately before
#       `/-/`, which is scope-aware) — any one of the three matching the
#       denylist is a violation.
#   (b) optionalDependencies / peerDependencies — npm 7+ installs both, and
#       the live gap is exactly the manifest-present/lockfile-absent window
#       PASS-IF-ABSENT sanctions (rider 2): with no lockfile the manifest is
#       the only signal, so it is scanned on all four dependency fields.
#   (c) @supabase/postgrest-js — the PostgREST HTTP client @supabase/supabase-js
#       wraps; usable directly with no `pg` anywhere in the tree.
#
# PASS-IF-ABSENT (R6 rider 2 — deliberately DIFFERS from the Dockerfile fence,
# which exits 2 on a missing target): workers/pdf-render/package.json does not
# exist yet at this sha — A4 has not landed it. Exiting non-zero here would red
# CI from the day this fence merges, for a file with no sequencing guarantee
# to exist yet. This fence exits 0 with a clear "target absent — pass" line and
# no-ops until A4 creates the manifest, then bites on A4's first commit. A
# present manifest with an absent lockfile is handled the SAME way (pass on
# the lockfile half only) — a lockfile only exists once npm has run against a
# real manifest, and its absence is not itself a violation.
#
# Fail-closed on the fence's OWN dependency: this fence parses JSON with
# `node`. If `node` is not on PATH, or either JSON file fails to parse, the
# fence cannot make a truthful pass/fail claim and exits 1 (fail-closed) —
# never a silent 0.
#
# Explicitly NOT catching at CI (unchanged human PR-review second line per
# scripts/ci/README.md + ARCH §6.1 RT-22 row):
#   - A Postgres client pulled in transitively through the base image. Not a
#     Node manifest/lockfile concern; out of this fence's reach by design.
#
# Ledger effect: NONE. This fence extends RT-22's existing CI coverage; it adds,
# removes, reorders and renumbers nothing in ADR-011 Decision 4 (read live,
# never pinned here). The CI-fenced set and the §10 catalogued set are
# different sets and are not reconciled by this file.
#
# Usage:
#   bash fence-rt22-pdf-worker-manifest.sh <path-to-package.json>
#
# Exit codes:
#   0 — target absent (pass), or manifest + lockfile both clean.
#   1 — denylisted package found (fail-closed), OR node is unavailable /
#       either JSON file fails to parse (fail-closed on the fence's own
#       dependency).
#   2 — argument error (no target path given).

set -euo pipefail

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "FATAL: missing target package.json arg." >&2
  echo "Usage: bash $(basename "$0") <path-to-package.json>" >&2
  exit 2
fi

if [ ! -f "$TARGET" ]; then
  echo "RT-22 manifest fence: target absent at $TARGET — pass (A4 has not landed the PDF worker package.json yet; R6 rider 2)."
  exit 0
fi

if ! command -v node >/dev/null 2>&1; then
  echo "FATAL: node is required to parse $TARGET and its lockfile, and is not on PATH." >&2
  echo "Failing closed — a fence that cannot verify its target must not pass it." >&2
  exit 1
fi

LOCKFILE="$(dirname "$TARGET")/package-lock.json"
DENYLIST_JSON='["pg","postgres","node-postgres","@supabase/supabase-js","@supabase/postgrest-js","knex","sequelize"]'

set +e
OUTPUT="$(node -e '
const fs = require("fs");

const manifestPath = process.argv[1];
const lockPath = process.argv[2];
const denylist = new Set(JSON.parse(process.argv[3]));

function fail(msg) {
  console.log("PARSE_ERROR:" + msg);
  process.exit(1);
}

// Resolve an npm alias spec ("npm:<name>@<version-range>") to the real
// package name. Scope-aware: the name may itself start with "@", so the
// version separator is the FIRST "@" after position 0, not position 0 itself.
// Returns null for a non-alias (plain semver range, git url, tag, etc).
function aliasTarget(spec) {
  if (typeof spec !== "string" || !spec.startsWith("npm:")) return null;
  const rest = spec.slice(4);
  if (rest.length === 0) return null;
  const searchFrom = rest.startsWith("@") ? 1 : 0;
  const at = rest.indexOf("@", searchFrom);
  return at === -1 ? rest : rest.slice(0, at);
}

// Parse the real (scope-aware) package name out of an npm tarball "resolved"
// URL, e.g. "https://registry.npmjs.org/@supabase/supabase-js/-/supabase-js-2.0.0.tgz"
// -> "@supabase/supabase-js", or ".../pg/-/pg-8.11.3.tgz" -> "pg". The path
// segment(s) immediately before the literal "/-/" separator are the name;
// returns null if the URL does not follow this convention (git/file/etc).
function nameFromResolved(url) {
  if (typeof url !== "string") return null;
  const marker = "/-/";
  const idx = url.indexOf(marker);
  if (idx === -1) return null;
  const withoutMarker = url.slice(0, idx);
  const lastSlash = withoutMarker.lastIndexOf("/");
  if (lastSlash === -1) return null;
  // Walk back one more segment if the preceding segment is a scope ("@...").
  const nameSeg = withoutMarker.slice(lastSlash + 1);
  const beforeName = withoutMarker.slice(0, lastSlash);
  const scopeSlash = beforeName.lastIndexOf("/");
  const maybeScope = beforeName.slice(scopeSlash + 1);
  if (maybeScope.startsWith("@")) return `${maybeScope}/${nameSeg}`;
  return nameSeg;
}

let manifest;
try {
  manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
} catch (e) {
  fail(`${manifestPath}: ${e.message}`);
}

const violations = [];
const MANIFEST_FIELDS = ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"];
for (const field of MANIFEST_FIELDS) {
  const deps = manifest[field] || {};
  for (const [name, spec] of Object.entries(deps)) {
    if (denylist.has(name)) {
      violations.push(`manifest:${field}:${name}`);
      continue;
    }
    const aliased = aliasTarget(spec);
    if (aliased && denylist.has(aliased)) {
      violations.push(`manifest:${field}:${name}(npm-alias-for:${aliased})`);
    }
  }
}

if (!fs.existsSync(lockPath)) {
  console.log("NOTE:lockfile absent at " + lockPath + " — treated as absent manifest (pass on lockfile half).");
} else {
  let lock;
  try {
    lock = JSON.parse(fs.readFileSync(lockPath, "utf8"));
  } catch (e) {
    fail(`${lockPath}: ${e.message}`);
  }

  const hits = new Set();

  // npm lockfileVersion 2/3 shape: flat "packages" map keyed by node_modules
  // path (including nested transitive paths, e.g.
  // "node_modules/knex/node_modules/pg"). Each entry is tested on THREE
  // independent signals so an aliased folder name cannot hide the real
  // package: (1) the key own last node_modules/ path segment, (2) the
  // entry "name" field (npm writes this when the folder name and the real
  // package name diverge — exactly what an alias produces), (3) the name
  // parsed from the entry "resolved" tarball URL.
  if (lock.packages && typeof lock.packages === "object") {
    for (const key of Object.keys(lock.packages)) {
      if (key === "") continue;
      const entry = lock.packages[key] || {};
      const segs = key.split("node_modules/").filter(Boolean);
      const keySegName = segs[segs.length - 1];
      const candidates = [keySegName, entry.name, nameFromResolved(entry.resolved)];
      for (const candidate of candidates) {
        if (candidate && denylist.has(candidate)) hits.add(candidate);
      }
    }
  }

  // npm lockfileVersion 1 shape: nested "dependencies" tree. Each node may
  // likewise carry a "version"/no distinguishing alias field historically,
  // but v1 predates common use of the npm: alias protocol — key name and
  // "resolved" are checked for parity with the v2/v3 branch above.
  (function walk(depsObj) {
    if (!depsObj) return;
    for (const [name, meta] of Object.entries(depsObj)) {
      const resolvedName = meta && typeof meta === "object" ? nameFromResolved(meta.resolved) : null;
      for (const candidate of [name, resolvedName]) {
        if (candidate && denylist.has(candidate)) hits.add(candidate);
      }
      if (meta && typeof meta === "object" && meta.dependencies) walk(meta.dependencies);
    }
  })(lock.dependencies);

  for (const name of hits) violations.push(`lockfile:${name}`);
}

if (violations.length > 0) {
  console.log("VIOLATIONS:" + violations.join(","));
  process.exit(1);
}
console.log("CLEAN");
process.exit(0);
' "$TARGET" "$LOCKFILE" "$DENYLIST_JSON")"
RC=$?
set -e

echo "$OUTPUT" | grep -Ev '^(VIOLATIONS:|CLEAN$|PARSE_ERROR:)' || true

if [ "$RC" -ne 0 ]; then
  echo "" >&2
  if echo "$OUTPUT" | grep -Eq '^PARSE_ERROR:'; then
    DETAIL="$(echo "$OUTPUT" | grep -E '^PARSE_ERROR:' | sed 's/^PARSE_ERROR://')"
    echo "RT-22 manifest fence: $DETAIL — cannot verify. Failing closed." >&2
  else
    DETAIL="$(echo "$OUTPUT" | grep -E '^VIOLATIONS:' | sed 's/^VIOLATIONS://')"
    echo "RT-22 manifest fence: $DETAIL in $TARGET / $LOCKFILE. Failing closed." >&2
  fi
  echo "PDF worker manifest/lockfile must not resolve a Postgres client or" >&2
  echo "DB-driver-bundling ORM package (pg, postgres, node-postgres," >&2
  echo "@supabase/supabase-js, @supabase/postgrest-js, knex, sequelize) per" >&2
  echo "Lock 13 mod #2 (zero-DB-isolation)." >&2
  exit 1
fi

echo "RT-22 manifest fence: $TARGET clean (manifest + lockfile resolve no denylisted Postgres-client/ORM package)."
exit 0
