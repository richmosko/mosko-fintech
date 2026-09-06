#!/usr/bin/env bash
#
# RT-22-manifest — PDF worker dependency-manifest audit
# (SELF-350 A6, re-scoped at R6; allowlist adopted at SELF-348 A4 per Sec F-4
# Option B, finalized against Backend's shipped dependency list — verified at
# origin/feature/self-348 @ d44d7d0)
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
# ENFORCEMENT MODEL (Sec F-4 Option B — "allowlist as the fence + denylist
# kept as legibility"): on the MANIFEST side, the decision is "reject anything
# not known-good," not "reject known-bad." Every direct dependency (across
# `dependencies`, `devDependencies`, `optionalDependencies`, `peerDependencies`,
# PLUS `overrides`/`resolutions` — Sec F-9) must (a) name an ALLOWLIST_JSON
# entry, AND (b) pin it with a PLAIN REGISTRY SEMVER SPEC. ALLOWLIST_JSON is
# exactly Backend's shipped `workers/pdf-render/package.json` dependency set —
# `puppeteer-core` + `jsonwebtoken`, no devDependencies (verified at
# origin/feature/self-348 @ d44d7d0). PLUS a SEVENTH source, `scripts` — Sec
# F-11B: `npm ci` runs lifecycle scripts regardless of the six fields above,
# so any `scripts` key outside `{"start","test"}` (this worker's real, and
# only legitimate, script keys) is its own violation, independent of the
# allowlist/denylist machinery entirely. DENYLIST_JSON and its lockfile/alias
# detection logic are UNCHANGED and still run — kept for human legibility (an
# explicit "these are definitely forbidden" list next to the allowlist a
# reviewer actually reads) and as defense-in-depth (a denylisted name that
# somehow entered the allowlist by mistake still trips). The LOCKFILE side is
# UNCHANGED (denylist + all three evasion signals, with the F-10 lastIndexOf
# fix) — the resolved tree can run to dozens of transitive packages, and
# allowlisting that whole set is not what Sec F-4 asked for.
#
# ONE RULE, NOT FIVE PATCHES (team-lead direction, folding Sec F-7/F-8/F-9):
# rather than separately patching for an npm-alias-via-tarball-URL manifest
# value (F-7: `"db": "https://registry.npmjs.org/pg/-/pg-8.11.3.tgz"`), a
# `github:`/`file:`/`git+ssh:`/`link:`/`workspace:` spec (F-8), or scanning
# `overrides`/`resolutions` (F-9) with their own bespoke per-shape checks, the
# manifest side enforces a SINGLE rule uniformly across all six DEPENDENCY
# sources (four dependency fields + overrides + resolutions): the spec string
# for an allowlisted name must be a PLAIN REGISTRY SEMVER — a
# character-allowlist (`isPlainRegistrySpec()`), not a grammar trying to
# enumerate every escape. Any spec containing `:` or `/` or `#` — which covers
# every alias/git/file/tarball/workspace form Sec named, uniformly, because
# none of them can be expressed without at least one of those three
# characters — is a violation regardless of what name it resolves to. This is
# why `aliasTarget()` is not consulted for the primary manifest-side decision
# (a non-registry spec is caught before its target name would even matter);
# it is kept ONLY to label a denylist-legibility hit more specifically when
# one fires. `scripts` (the seventh source, F-11B) is a DIFFERENT shape — a
# script's VALUE is an arbitrary shell command, not a dependency spec, so
# there is no spec-shape rule to apply to it; the key itself is what is
# allowlisted instead.
#
# TARGET MUST EXIST — PASS-IF-ABSENT RETIRED AT A4 (Sec F-6, redirected
# 2026-09-05): R6 rider 2 shipped this fence PASS-IF-ABSENT, deliberately
# UNLIKE the Dockerfile fence's exit-2-on-missing-target, because SELF-350 (A6)
# landed before SELF-348 (A4) — `workers/pdf-render/package.json` legitimately
# did not exist yet, and exiting non-zero for that would have red CI from day
# one for a file with no sequencing guarantee. SELF-348 (A4) has now landed
# that file (origin/feature/self-348 @ d44d7d0) — it is REQUIRED from here on,
# so this fence's shape now matches the Dockerfile fence's own precedent
# exactly, for the identical reason R6 rider 2 stated for that fence: "correct
# because its target already exists." A missing target is now a structural
# error (exit 2, fail-closed), not a legitimate pre-build state. An earlier
# attempt to bridge the two states with a Dockerfile-apt-get-line readiness
# guess (tried in a since-retracted revision of the CI job) was itself a
# convention with no mechanism and was removed — the real fix is this: once
# the manifest exists, its absence needs no guessing to be a violation.
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
#   0 — manifest + lockfile both clean (every dependency allowlisted with a
#       plain registry spec; no denylist hit anywhere).
#   1 — a manifest dependency is not allowlisted, or is allowlisted but pinned
#       by a non-registry spec, or a denylisted package is found (manifest or
#       lockfile) — fail-closed. OR node is unavailable / either JSON file
#       fails to parse (fail-closed on the fence's own dependency).
#   2 — argument error (no target path given), OR the target package.json
#       does not exist (structural error post-A4 — see TARGET MUST EXIST
#       above; matches the Dockerfile fence's own missing-target convention).

set -euo pipefail

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "FATAL: missing target package.json arg." >&2
  echo "Usage: bash $(basename "$0") <path-to-package.json>" >&2
  exit 2
fi

if [ ! -f "$TARGET" ]; then
  echo "FATAL: target package.json not found at: $TARGET" >&2
  echo "PASS-IF-ABSENT (R6 rider 2) was the pre-A4 shape and was retired once" >&2
  echo "SELF-348 (A4) landed workers/pdf-render/package.json. The manifest is" >&2
  echo "now REQUIRED; a missing target is a structural error. Failing closed." >&2
  exit 2
fi

if ! command -v node >/dev/null 2>&1; then
  echo "FATAL: node is required to parse $TARGET and its lockfile, and is not on PATH." >&2
  echo "Failing closed — a fence that cannot verify its target must not pass it." >&2
  exit 1
fi

LOCKFILE="$(dirname "$TARGET")/package-lock.json"
DENYLIST_JSON='["pg","postgres","node-postgres","@supabase/supabase-js","@supabase/postgrest-js","knex","sequelize"]'
# Backend's shipped workers/pdf-render/package.json dependency set, verified
# at origin/feature/self-348 @ d44d7d0: exactly puppeteer-core + jsonwebtoken,
# no devDependencies. Adding a new dependency requires an entry here — that
# review IS the control (Sec F-4 Option B).
ALLOWLIST_JSON='["puppeteer-core","jsonwebtoken"]'

set +e
OUTPUT="$(node -e '
const fs = require("fs");

const manifestPath = process.argv[1];
const lockPath = process.argv[2];
const denylist = new Set(JSON.parse(process.argv[3]));
const allowlist = new Set(JSON.parse(process.argv[4]));

function fail(msg) {
  console.log("PARSE_ERROR:" + msg);
  process.exit(1);
}

// Sec F-4 Option B "single rule" (folds F-7/F-8/F-9): a character-allowlist,
// not an attempt to enumerate every escape grammar. A plain npm semver range
// never needs ":" (rules out every "<scheme>:" form — npm alias "npm:",
// "github:", "git:", "git+ssh:", "git+https:", "file:", "link:",
// "workspace:", "catalog:", "http(s):"), "/" (rules out github "user/repo"
// shorthand AND a bare tarball URL path), or "#" (rules out a git ref).
// Anything outside [0-9A-Za-z.\-+^~*<>=| ] is rejected outright, regardless
// of what package name it would otherwise resolve to.
function isPlainRegistrySpec(spec) {
  if (typeof spec !== "string" || spec.length === 0) return false;
  return /^[0-9A-Za-z.\-+^~*<>=| ]+$/.test(spec);
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
//
// Sec F-10 (joint-review 2026-09-05): split on the LAST "/-/", not the
// first. A proxy/mirror registry URL can legitimately contain "/-/" earlier
// in its path (e.g. a proxy route segment before the real registry path is
// appended) — indexOf() would split at that spurious earlier occurrence and
// misparse the host or a proxy path segment as the package name instead of
// the real one immediately before the tarball filename.
function nameFromResolved(url) {
  if (typeof url !== "string") return null;
  const marker = "/-/";
  const idx = url.lastIndexOf(marker);
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
    // Sec F-4 Option B: allowlist membership and spec shape are INDEPENDENT
    // checks, not gated behind each other — an unallowlisted name with a
    // non-registry spec must report BOTH, not whichever is checked first.
    if (!allowlist.has(name)) {
      violations.push(`manifest:${field}:${name}(not-allowlisted)`);
    }
    if (!isPlainRegistrySpec(spec)) {
      // Non-registry spec — the single rule folding F-7/F-8/F-9 — reported
      // regardless of whether the name is also allowlisted.
      violations.push(`manifest:${field}:${name}(non-registry-spec:${JSON.stringify(spec)})`);
    }
    // Denylist kept for legibility + defense-in-depth (Option B): still
    // checked and still reported, even for a name that is (incorrectly)
    // allowlisted. aliasTarget() is consulted here only to give a denylist
    // hit a more specific label when the spec is an npm: alias — it no
    // longer drives the primary manifest-side decision (see header).
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

// Sec F-9: npm `overrides` (nested-object shape; a "." key overrides the
// parent key OWN version, any other key overrides a transitive dependency
// reached through it) and Yarn `resolutions` (flat, glob-path-shaped keys,
// e.g. "**/pg" or "foo/pg" — the real package name is the LAST path
// segment). Every key encountered (excluding ".") is a package name checked
// against the allowlist; every string value is a spec checked against the
// single plain-registry-spec rule, at any nesting depth.
function scanOverridesObject(obj, sourceLabel) {
  if (!obj || typeof obj !== "object") return;
  for (const [key, value] of Object.entries(obj)) {
    const name = key === "." ? null : key;
    if (name && !allowlist.has(name)) {
      violations.push(`${sourceLabel}:${name}(not-allowlisted)`);
    }
    if (typeof value === "string") {
      if (!isPlainRegistrySpec(value)) {
        violations.push(`${sourceLabel}:${name || "(self)"}(non-registry-spec:${JSON.stringify(value)})`);
      }
    } else if (value && typeof value === "object") {
      scanOverridesObject(value, sourceLabel);
    }
  }
}
if (manifest.overrides) scanOverridesObject(manifest.overrides, "manifest:overrides");
if (manifest.resolutions && typeof manifest.resolutions === "object") {
  for (const [key, value] of Object.entries(manifest.resolutions)) {
    const segs = key.split("/").filter((s) => s && s !== "**");
    const name = segs[segs.length - 1] || key;
    if (!allowlist.has(name)) violations.push(`manifest:resolutions:${name}(not-allowlisted)`);
    if (typeof value === "string" && !isPlainRegistrySpec(value)) {
      violations.push(`manifest:resolutions:${name}(non-registry-spec:${JSON.stringify(value)})`);
    }
  }
}

// Sec F-11B: `npm ci` runs lifecycle scripts (preinstall/install/postinstall/
// prepare/prepublish/prepack, both the root package OWN AND every
// dependency OWN) whether or not `--ignore-scripts` is passed at the install
// site — this fence has no visibility into WHAT a script does (it could
// silently `npm i pg` outside every field scanned above), so the only
// fail-closed posture is to allowlist the SCRIPT KEYS themselves. This
// worker real package.json declares exactly {"start","test"} and has no
// legitimate use for any lifecycle hook — so, matching the "allowlist as the
// fence" model applied everywhere else in this file, any `scripts` key
// outside {"start","test"} is a violation, regardless of what its value is.
const SCRIPT_KEY_ALLOWLIST = new Set(["start", "test"]);
if (manifest.scripts && typeof manifest.scripts === "object") {
  for (const key of Object.keys(manifest.scripts)) {
    if (!SCRIPT_KEY_ALLOWLIST.has(key)) {
      violations.push(`manifest:scripts:${key}(script-not-allowlisted)`);
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
' "$TARGET" "$LOCKFILE" "$DENYLIST_JSON" "$ALLOWLIST_JSON")"
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
  echo "PDF worker manifest/lockfile dependencies must each be an ALLOWLISTED" >&2
  echo "package (puppeteer-core, jsonwebtoken) pinned by a plain registry" >&2
  echo "semver spec; manifest.scripts must contain no key outside {start,test}" >&2
  echo "(npm ci runs lifecycle scripts regardless of the allowlist); and must" >&2
  echo "not resolve a Postgres client or DB-driver-bundling ORM package (pg," >&2
  echo "postgres, node-postgres, @supabase/supabase-js, @supabase/postgrest-js," >&2
  echo "knex, sequelize) per Lock 13 mod #2 (zero-DB-isolation)." >&2
  exit 1
fi

echo "RT-22 manifest fence: $TARGET clean (every dependency allowlisted with a plain registry spec; no denylisted Postgres-client/ORM package anywhere)."
exit 0
