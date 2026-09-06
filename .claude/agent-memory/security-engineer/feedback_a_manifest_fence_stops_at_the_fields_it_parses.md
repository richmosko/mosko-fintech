---
name: a-manifest-fence-stops-at-the-fields-it-parses
description: A dependency-allowlist fence governs only the manifest FIELDS it parses and the manifest SIDE it runs on — lifecycle scripts and the lockfile's `resolved` URL are the two doors it leaves open; and a fence's own success message is a claim about its coverage.
metadata:
  type: feedback
---

An allowlist-shaped dependency fence ("reject anything not known-good") is only as
wide as (a) the manifest fields it enumerates and (b) the manifest-vs-lockfile side
it applies the rule to. Both gaps are invisible from the fence's output, because the
fence prints a success message describing the rule it applied, not the surface it
covered.

**Why:** measured at PR #634 (SELF-348 / A4, 2026-09-05). `fence-rt22-pdf-worker-manifest.sh`
scanned six sources (four dependency fields + `overrides` + `resolutions`) and caught
every named evasion (F-7 tarball-URL alias, F-8 `github:`/`file:`, F-9 recursive
overrides, F-10 `lastIndexOf('/-/')`). It passed `CLEAN` on two shapes that install
arbitrary code anyway:
- a root `scripts.postinstall` — verified live that `npm ci --omit=dev` **executes**
  the root package's postinstall, and the Dockerfile carried no `--ignore-scripts`;
- a lockfile entry for an **allowlisted** name whose `resolved` points at an arbitrary
  host (or a git URL under a benign folder name, where `nameFromResolved()` returns
  null so no candidate is ever tested). `npm ci` installs from `resolved`.
The fence's own success line read *"every dependency allowlisted with a plain registry
spec"* — true of the six fields, false of what gets installed.

**How to apply:** when reviewing any allowlist/denylist manifest fence —
1. Enumerate the manifest's **install-triggering surfaces**, not just its dependency
   fields: `scripts` (`preinstall`/`install`/`postinstall`/`prepare`/`prepublish`/`prepack`),
   `bundleDependencies`, `workspaces`, `overrides`, `resolutions`.
2. Ask which side the installer actually reads. If it is `npm ci`, the **lockfile** is
   the install contract and the manifest is advisory — so a manifest-only rule is the
   weaker half. Require `resolved` to match the expected registry origin and `integrity`
   to be present, per entry.
3. Prefer closing the class at the **install site** (`npm ci --ignore-scripts`) over
   adding a seventh parser to the fence — one line, covers transitive deps too. Name the
   losing side: a dependency that genuinely needs a build step then silently no-ops.
4. Always run a **negative control** (the real shipped manifest must exit 0) alongside
   the evasion cases, or a fence that rejects everything reads as a fence that works.
5. Check whether the fence's success/failure text overstates coverage — it becomes the
   sentence a future reviewer quotes.

Related: [[feedback_a_name_key_denylist_misses_every_spec_form_in_the_value]] (the
mirror — enumerate value grammars; this one is enumerate the *containers*),
[[feedback_measure_the_fence_regex_not_its_comment]],
[[feedback_pass_if_absent_substitutes_a_path_convention]],
[[feedback_probe_that_only_asserts_failure_goes_vacuous]].
