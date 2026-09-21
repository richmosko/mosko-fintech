#!/usr/bin/env bash
#
# fence-tinker-write-allowlist.sh -- tree-wide structural fence: every
# Eloquent write-verb occurrence (`->save(`, `->update(`, `->delete(`,
# `->create(`, `->fill(`, or `DB::(update|insert|delete|statement)(`)
# anywhere in `scripts/*.sh` PHP text destined for a tinker --execute
# call, AND every `tinker --execute` invocation whose value is a bash
# variable reference (body built elsewhere, statically unresolvable),
# must be marked with a UNIQUE `/* TINKER-WRITE-ALLOW-NN */` id that
# exists, exactly once, in the sha256-pinned allowlist below. Sec
# ruling, PR #862 review (CA-1 fix) -- the escape hatch this fence
# closes is a NEW unmarked write, or an EXISTING marker copy-pasted
# onto a second site, landing without the reviewer's eye being forced
# to the allowlist file (the same visibility-not-access-control shape
# as fence-no-source-credential-files.sh's own sha-pinned allowlist,
# PR #780 C-a -- copied verbatim below, see that fence's own header for
# the full rationale this one does not repeat).
#
# SEVEN SITES, MEASURED (not assumed) -- the count went through two
# corrections this review round, both instructive:
#   1. team-lead/Sec's own initial count was FIVE, all in
#      provision-vps.sh. A DevOps tree-wide sweep for the same write-
#      verb set found a SIXTH, pre-existing:
#      scripts/coolify-materialize-supabase-mounts.sh's `$row->save()`.
#   2. Sec's own re-measurement (their own words): "I measured the
#      write set inside provision-vps.sh only and then stated it as
#      the tree-wide set" -- re-swept tree-wide, confirmed SEVEN is
#      correct (01-05 provision-vps.sh, 06 coolify-materialize-
#      supabase-mounts.sh, 07 provision-worker.sh's new CA-1 fqdn
#      clear) -- no eighth found, with the scope limit below stated
#      plainly rather than claimed as exhaustive.
#
# TWO DETECTION MODES, NOT ONE -- an earlier revision of this fence only
# had the first and was fail-OPEN on site 06, found by inverting its
# marker and watching the fence stay GREEN:
#   (i)  LITERAL body, write verb visible in scripts/*.sh text -- find
#        its NEAREST marker (searched both directions, bounded to
#        WRITE_WINDOW_LINES), the write-verb-anchored shape sites
#        01/02/03/04/05/07 all use.
#   (ii) UNRESOLVABLE body -- `--execute=` whose ENTIRE value is a bash
#        variable reference (e.g. `--execute="$SCRIPT_CONTENT"`), no
#        PHP text at that line at all. Sec ruling: fail closed on this
#        shape UNCONDITIONALLY -- require a marker at the invocation
#        line (tight window, UNRESOLVABLE_WINDOW_LINES) regardless of
#        whether a write verb is visible anywhere nearby, since the
#        variable's content could hide anything. Site 06 uses this
#        shape -- its marker sits at the `ssh ... --execute="$SCRIPT_
#        CONTENT"` line, NOT at the `$row->save()` body 30 lines above
#        (Sec: "the marker goes where the fence LOOKS"). A bound
#        unresolvable-site marker exempts AT MOST ONE nearby literal
#        write-verb line (its nearest, not-yet-exempted one) from ALSO
#        requiring its own SEPARATE marker -- 1:1, not file-wide (F-6
#        fix, Sec PR #862 review; see SCOPE below for exactly how far
#        that exemption reaches).
#
# ⚠ A MARKER IS NOT UNIQUE BY CONSTRUCTION -- stated, not assumed. Copy
# an allowlisted line (marker included) to a NEW site and the new site
# would be auto-exempt under a presence-only check. This fence does NOT
# do a presence-only check: every marker consumed by either detection
# mode is counted, and a count > 1 for the same ID anywhere in
# scripts/*.sh fails CLOSED (see CATCH CRITERION). This is the leg Sec
# asked to see fire before trusting this fence.
#
# CATCH CRITERION -- for every line in `scripts/*.sh` (top-level only,
# matching fence-heredoc-stdin-drain.sh's own scope note; comment lines
# excluded from write-verb/unresolvable detection but still scanned for
# markers) that is EITHER (i) a write-verb line OR (ii) an unresolvable
# `--execute=` line: find its nearest unclaimed `/* TINKER-WRITE-
# ALLOW-NN */` marker within that mode's own window (see above),
# excluding a marker already consumed by an earlier, closer site.
# Unresolvable sites are resolved FIRST; each one that binds exempts AT
# MOST ONE nearby write-verb line, 1:1 (see SCOPE). Violations, each
# independently fatal:
#   - a write-verb line with no unclaimed marker within
#     WRITE_WINDOW_LINES AND no unresolvable-site exemption covering it
#   - an unresolvable `--execute=` line with no unclaimed marker within
#     UNRESOLVABLE_WINDOW_LINES
#   - a site whose nearest marker's ID is not in the allowlist
#   - any marker ID consumed by MORE THAN ONE site tree-wide (the
#     copy-paste hole)
#   - the allowlist file missing, or present but not matching its own
#     pinned sha256 (same fail-closed shape as fence-no-source-
#     credential-files.sh's own allowlist pin)
#
# ⚠ SCOPE, STATED PLAINLY -- this fence's write-verb set is Sec's own
# literal list (PR #862 review), not a general "any Eloquent mutation"
# claim. Sanctum's `createToken(...)` (used at provision-vps.sh's token-
# mint sites) IS a DB write but does not contain the literal substring
# `->create(` (it is `->createToken(`, a different method name) --
# outside this fence's catch criterion by construction. Also scoped to
# Eloquent-shaped PHP text specifically -- a bash script containing the
# literal substring "->save(" for an unrelated reason (none exist in
# this tree today, checked) would also be flagged; same fail-closed-
# over-precise tradeoff this repo's other grep-based fences (fence-
# tinker-no-echo.sh's own header names it explicitly) already accept.
# The "unresolvable site exempts a write-verb line" rule (mode ii) is
# 1:1 (F-6 fix, Sec PR #862 review): each bound unresolvable site
# exempts its OWN nearest not-yet-exempted write-verb line, greedily
# assigned across all unresolvable sites in the file. A SECOND,
# unrelated write verb in a file that also has an unresolvable site
# gets NO exemption and must carry its own marker -- the earlier,
# file-wide version of this rule let one indirect call cover every
# write in the file, which was the fail-open Sec's review caught (the
# third found in this fence; each one latent, none live, when found).
# Today's tree has exactly one unresolvable site and one write verb in
# the one file with this shape (coolify-materialize-supabase-
# mounts.sh), so this fix changes no live behavior.
# This fence reads `scripts/*.sh` ONLY -- PHP text that lives in a
# non-`.sh` file (a `.php` fixture, a heredoc sourced from a separate
# template file, etc.) and is `cat`'d or otherwise fed into a tinker
# body is outside this fence's reach, same as fence-no-source-
# credential-files.sh's own "visibility control, not access control"
# framing (Sec, PR #862 review). No such file exists in this tree
# today; stated so the next person doesn't have to rediscover it.
#
# Structural / source-literal, same convention as fence-heredoc-stdin-
# drain.sh and fence-boolean-cast-pairing.sh -- parses the tree's own
# scripts/*.sh text and executes nothing.
#
# Exit 0 only if zero violations found.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Overridable ONLY for this fence's own offline strike battery
# (fence-tinker-write-allowlist-strikes.sh), so that battery can point
# the real detection logic at a disposable scratch tree instead of
# duplicating it -- a fixture that re-implements the fence's own logic
# risks "the fake restates the lie" (this repo's own recurring failure
# mode). Unset in every real CI invocation, so production behavior is
# unchanged.
SCRIPTS_DIR="${FENCE_TINKER_ALLOWLIST_SCRIPTS_DIR:-$REPO_ROOT/scripts}"
ALLOWLIST="${FENCE_TINKER_ALLOWLIST_FILE:-$SELF_DIR/fence-tinker-write-allowlist.txt}"
ALLOWLIST_PIN="${FENCE_TINKER_ALLOWLIST_PIN_FILE:-$SELF_DIR/fence-tinker-write-allowlist.sha256}"

[[ -d "$SCRIPTS_DIR" ]] || { echo "FATAL: $SCRIPTS_DIR missing" >&2; exit 2; }

# Same fail-closed allowlist-pin shape as fence-no-source-credential-
# files.sh (Sec PR #780 C-a) -- see that fence's own header for the full
# visibility-not-access-control rationale, not repeated here.
[[ -f "$ALLOWLIST" ]] || {
  echo "FATAL: allowlist file missing: $ALLOWLIST -- this fence requires an explicit (even if empty) allowlist file to distinguish 'no exemptions' from 'exemption file not created'. Failing closed." >&2
  exit 2
}
[[ -f "$ALLOWLIST_PIN" ]] || {
  echo "FATAL: pinned hash file missing: $ALLOWLIST_PIN -- required so a change to $ALLOWLIST cannot land without also touching this file. Failing closed." >&2
  exit 2
}
if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_HASH="$(sha256sum "$ALLOWLIST" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  ACTUAL_HASH="$(shasum -a 256 "$ALLOWLIST" | awk '{print $1}')"
else
  echo "FATAL: neither sha256sum nor shasum is available -- cannot verify the allowlist pin. Failing closed." >&2
  exit 2
fi
PINNED_HASH="$(awk '{print $1}' "$ALLOWLIST_PIN")"
if [[ "$ACTUAL_HASH" != "$PINNED_HASH" ]]; then
  echo "FATAL: $ALLOWLIST does not match the pinned hash in $ALLOWLIST_PIN (got $ACTUAL_HASH, expected $PINNED_HASH)." >&2
  echo "The allowlist changed without its pin being updated -- an unreviewed tinker-write exemption is the exact escape hatch this fence exists to surface. If this is a genuine, reviewed change (Sec sign-off naming the new/changed site), regenerate the pin: sha256sum $ALLOWLIST > $ALLOWLIST_PIN" >&2
  exit 2
fi

PY_TMP="$(mktemp)"
trap 'rm -f "$PY_TMP"' EXIT
cat > "$PY_TMP" <<'PYEOF'
import re, sys, os

# F-5 (Sec, PR #862 review): widened from the original 5-verb list.
# Stated plainly, same as the SCOPE note below -- this is a denylist
# over an open vocabulary, not a claim of exhaustive Eloquent-write
# coverage. The unresolvable-`--execute=` detection mode is the
# fail-closed backstop for whatever this list still misses (a body
# built into a variable is caught regardless of which verb it hides).
# Re-verified zero hits for every added verb in scripts/*.sh today
# (grep, positive-controlled against `->save(` which does match) --
# this widening is a no-behavior-change addition on the current tree.
WRITE_RE = re.compile(
    r'->save\(|->saveQuietly\(|->update\(|->updateOrCreate\(|'
    r'->delete\(|->forceDelete\(|->create\(|->firstOrCreate\(|'
    r'->fill\(|->insert\(|->upsert\(|->increment\(|->decrement\(|'
    r'->truncate\(|->push\(|->attach\(|->sync\(|->detach\(|'
    r'::destroy\(|'
    r'DB::\s*(?:update|insert|delete|statement|unprepared)\s*\('
)
MARKER_RE = re.compile(r'/\*\s*TINKER-WRITE-ALLOW-(\d+)\s*\*/')
COMMENT_LINE = re.compile(r'^\s*#')
# A `tinker --execute=` value that is ENTIRELY a bash variable reference
# (quoted or not) -- e.g. `--execute="$SCRIPT_CONTENT"` -- carries no PHP
# text at this line at all: the body was built elsewhere (a heredoc into
# a file, a earlier-assigned variable, ...) and is statically
# UNRESOLVABLE from this line. Sec ruling (PR #862 review): fail closed
# on this shape -- require a marker regardless of whether a write verb
# is visible here, since a write could be hiding in that variable's
# content with nothing at this line to prove otherwise.
UNRESOLVABLE_RE = re.compile(r'''--execute=(["'])\$[A-Za-z_][A-Za-z0-9_]*\1''')
WRITE_WINDOW_LINES = 80
UNRESOLVABLE_WINDOW_LINES = 10

def scan_file(path):
    with open(path) as f:
        lines = f.readlines()
    write_lines = []          # line indices with a write verb
    unresolvable_lines = []    # line indices with an unresolvable --execute value
    marker_lines = {}          # line index -> marker id
    for i, raw in enumerate(lines):
        line = raw.rstrip('\n')
        if COMMENT_LINE.match(line):
            m = MARKER_RE.search(line)
            if m:
                marker_lines[i] = m.group(1)
            continue
        if UNRESOLVABLE_RE.search(line):
            unresolvable_lines.append(i)
        elif WRITE_RE.search(line):
            write_lines.append(i)
        m = MARKER_RE.search(line)
        if m:
            marker_lines[i] = m.group(1)

    findings = []          # message strings
    consumed = set()        # marker line-indices already claimed
    site_ids = []            # (id, lineno) for every successfully bound site

    def claim_nearest(idx, window):
        best, best_dist, best_id = None, None, None
        for midx, mid in marker_lines.items():
            if midx in consumed:
                continue
            dist = abs(midx - idx)
            if dist > window:
                continue
            if best_dist is None or dist < best_dist:
                best, best_dist, best_id = midx, dist, mid
        return best, best_id

    # Unresolvable --execute sites FIRST, own tight window -- Sec: "the
    # marker goes at the invocation line".
    bound_unresolvable_lines = []  # line indices that successfully bound a marker
    for u in unresolvable_lines:
        best, best_id = claim_nearest(u, UNRESOLVABLE_WINDOW_LINES)
        lineno = u + 1
        if best is None:
            findings.append(f"{path}:{lineno}: 'tinker --execute' value is a bash variable reference (body built elsewhere, statically unresolvable) with NO unclaimed /* TINKER-WRITE-ALLOW-NN */ marker within {UNRESOLVABLE_WINDOW_LINES} lines -- refusing. -- {lines[u].strip()[:120]}")
            continue
        consumed.add(best)
        site_ids.append((best_id, lineno))
        bound_unresolvable_lines.append(u)

    # F-6 fix (Sec, PR #862 review): the exemption below is 1:1, not
    # file-wide. An earlier revision let ANY bound unresolvable site
    # exempt EVERY write-verb line in the whole file -- a single
    # `--execute="$VAR"` anywhere would silently cover an unrelated
    # second write elsewhere in the same file, which is exactly the
    # escape hatch this fence exists to close (found by Sec's review,
    # not by this agent's own inversion testing -- the third fail-open
    # found in this fence, each one latent when found). Fix, matching
    # the same `consumed`-set discipline already used for markers: each
    # bound unresolvable site exempts AT MOST ONE write-verb line -- its
    # nearest not-yet-exempted one, greedily assigned in unresolvable-
    # site order. A second, unrelated write verb in the same file gets
    # NO exemption and must carry its own marker like any other site.
    # Today's tree is unaffected (exactly one unresolvable site, one
    # write verb, in coolify-materialize-supabase-mounts.sh) -- this
    # only changes behavior for a file that doesn't exist yet.
    exempted_write_lines = set()
    for u in bound_unresolvable_lines:
        nearest_w, nearest_dist = None, None
        for w in write_lines:
            if w in exempted_write_lines:
                continue
            dist = abs(w - u)
            if nearest_dist is None or dist < nearest_dist:
                nearest_w, nearest_dist = w, dist
        if nearest_w is not None:
            exempted_write_lines.add(nearest_w)

    for w in write_lines:
        lineno = w + 1
        if w in exempted_write_lines:
            # Scope note above: this write is presumed to be the ONE
            # reaching its nearest bound unresolvable --execute call --
            # not independently required to carry its own marker too.
            continue
        best, best_id = claim_nearest(w, WRITE_WINDOW_LINES)
        if best is None:
            findings.append(f"{path}:{lineno}: write-verb line has NO unclaimed /* TINKER-WRITE-ALLOW-NN */ marker within {WRITE_WINDOW_LINES} lines -- unmarked tinker write, refusing. -- {lines[w].strip()[:120]}")
            continue
        consumed.add(best)
        site_ids.append((best_id, lineno))
    return findings, site_ids

allowlist_path = sys.argv[1]
root = sys.argv[2]

allowed_ids = set()
with open(allowlist_path) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split()
        if parts and parts[0].startswith('TINKER-WRITE-ALLOW-'):
            allowed_ids.add(parts[0].replace('TINKER-WRITE-ALLOW-', ''))

any_findings = False
all_site_ids = []  # (id, path, lineno)
for fn in sorted(os.listdir(root)):
    path = os.path.join(root, fn)
    if not (os.path.isfile(path) and fn.endswith('.sh')):
        continue
    findings, site_ids = scan_file(path)
    for msg in findings:
        any_findings = True
        print(msg)
    for mid, lineno in site_ids:
        all_site_ids.append((mid, path, lineno))

# Every consumed marker's ID must be in the allowlist.
for mid, path, lineno in all_site_ids:
    if mid not in allowed_ids:
        any_findings = True
        print(f"{path}:{lineno}: nearest marker TINKER-WRITE-ALLOW-{mid} is not in the allowlist ({allowlist_path}) -- refusing.")

# No marker ID may be consumed by more than one write-verb site tree-wide
# (the copy-paste hole this fence exists to close).
from collections import Counter
counts = Counter(mid for mid, _, _ in all_site_ids)
for mid, count in counts.items():
    if count > 1:
        any_findings = True
        sites = [f"{path}:{lineno}" for m, path, lineno in all_site_ids if m == mid]
        print(f"DUPLICATE marker TINKER-WRITE-ALLOW-{mid} consumed by {count} write-verb sites -- must be unique tree-wide: {sites}")

sys.exit(1 if any_findings else 0)
PYEOF

if FINDINGS="$(python3 "$PY_TMP" "$ALLOWLIST" "$SCRIPTS_DIR")"; then
  RC=0
else
  RC=$?
fi

if [[ $RC -ne 0 ]]; then
  echo "FAIL: [tinker-write-allowlist-treewide] one or more unmarked, unlisted, or duplicated tinker-write markers found. Offending site(s):" >&2
  printf '%s\n' "$FINDINGS" >&2
  exit 1
fi

echo "OK: [tinker-write-allowlist-treewide] every write-verb line has exactly one, allowlisted, tree-wide-unique nearest marker."
exit 0
