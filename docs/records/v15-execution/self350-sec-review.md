# Sec re-verify — PR #630 @ `bf4aee5` (SELF-350 A6, RT-22 manifest fence)

Date: 2026-09-05. Prior verdict: AMBER on `19a5bdd` (F-1/F-2/F-3 blocking).
Worktree: `/Users/mosko/Projects/mosko-fintech-worktrees/security-engineer`, detached at `bf4aee5`.
All measurements re-run in this worktree at `bf4aee5`.

## Scope of change (verified, not accepted)

`git diff --name-status 19a5bdd bf4aee5` → exactly 2 files:
`.github/workflows/security-scan.yml`, `scripts/ci/fence-rt22-pdf-worker-manifest.sh`.
`git diff --stat 19a5bdd bf4aee5 -- tests/fixtures` → empty (fixtures untouched, as reported).
`git diff --name-only 19a5bdd bf4aee5 -- DECISIONS.md docs/ scripts/ci/README.md` → 0 (no ledger/doc surface touched).
`scripts/ci/fence-rt22-pdf-worker-dockerfile.sh` unchanged (0 files) — the sibling fence's
header, from which this fence quotes verbatim, did not move.

Hunk inventory — the three fixes and one in-scope comment correction, nothing else:
- fence script: denylist `+@supabase/postgrest-js` (F-3c); `aliasTarget()` + `nameFromResolved()`
  helpers (F-3a); MANIFEST_FIELDS 2→4 (F-3b); lockfile v2/v3 3-signal candidate set + v1
  `resolved` parity (F-3a); stderr banner reflow to carry the new denylist entry.
- workflow: discovery loop (F-1); captured-output token assertions (F-2).
- workflow comment correction: the lockfile-transitive fixture description read "package.json
  names only knex" — `knex` is itself denylisted, so the comment described a fixture that would
  trip the manifest leg. Corrected to "names only a non-denylisted dep." This is the stale
  residue of commit `48c4e7c`'s isolation fix, and correcting it is in F-2's scope.

## F-1 — production step discovers manifests (DISCHARGED)

Step body extracted verbatim from the YAML and run under `bash -e` (GitHub's default non-Windows
shell; `python3 -c "yaml.safe_load(...)"` confirms no `shell:` key on any of the 4 steps and no
top-level `defaults:` — so process substitution `< <(find ...)` is valid and `found` survives
because the loop runs in the current shell, not a pipe subshell).

- P0, real tree at `bf4aee5`: `workers/pdf-render/` contains only `.env.example` + `Dockerfile`;
  `find` yields zero manifests → fallback to canonical path → "target absent — pass", rc=0.
  PASS-IF-ABSENT preserved exactly for the pre-A4 state.
- P1, scratch mirror tree with (i) clean top-level `workers/pdf-render/package.json`,
  (ii) `workers/pdf-render/app/package.json` with `pg`, (iii) `workers/pdf-render/node_modules/evil/package.json`
  with `pg`: discovery listed exactly (i) and (ii) — `node_modules/` excluded — and the step
  exited **rc=1** on (ii) under `bash -e`. Errexit propagates out of the `while` body; the step
  fails closed.

Residual (new, flag F-6): discovery is scoped to `workers/pdf-render`. If A4 lands the worker at
a different top-level directory the loop finds zero, falls back to the canonical path, and reports
"absent — pass" forever — the identical rot F-1 named, relocated one directory up. Note also that
the loop aborts on the FIRST violating manifest, so a multi-manifest tree reports one violation per
run (fail-closed, but not a complete enumeration).

## F-2 — inversion step asserts output tokens (DISCHARGED)

Both fixtures run from the worktree with the step's exact capture form; all three assertions
evaluated against real output:

| assertion | measured |
|---|---|
| `rc_manifest != 0` | rc=1 |
| `out_manifest` contains `manifest:dependencies:pg` | grep -c = 1 |
| `rc_lockfile != 0` | rc=1 |
| `out_lockfile` contains `lockfile:pg` | grep -c = 1 |
| `out_lockfile` contains NO `manifest:` | grep -c = 0 |

The "no `manifest:` token" assertion is not defeated by the fixture's own path
(`.../rt22-manifest-violation/...` has no `manifest:` substring) nor by the stderr banner
("RT-22 manifest fence:" / "manifest/lockfile" — neither is `manifest:`). Measured, not reasoned.

Positive control that the assertion is not decorative — the three ways a non-zero exit could lie,
each re-run and each now caught:
- malformed manifest → rc=1, output `PARSE_ERROR:… — cannot verify. Failing closed.`, no route token.
- malformed lockfile → rc=1, same shape, no route token.
- `node` off PATH (`PATH=/bin:/usr/bin`, `which node` = `/opt/homebrew/bin/node`) → rc=1,
  `FATAL: node is required…`; run against the manifest-direct fixture the expected-token count is
  **0**, i.e. the F-2 assertion fires. This is exactly the defect F-2 named and it is now observable.

## F-3 — alias / extra dependency fields / postgrest-js (DISCHARGED)

Evasion matrix, one scratch case dir each, `rc` and emitted token recorded:

| case | shape | rc | verdict |
|---|---|---|---|
| E1 | `devDependencies: knex` | 1 | caught (`manifest:devDependencies:knex`) |
| E2 | lockfileVersion 1 nested transitive `pg` | 1 | caught (`lockfile:pg`) |
| E3 | malformed manifest | 1 | fail-closed |
| E4 | malformed lockfile | 1 | fail-closed |
| E5 | `node` off PATH | 1 | fail-closed |
| E6 | manifest present, lockfile absent, `sequelize` | 1 | caught (manifest half still scanned) |
| F3a | lockfile alias, `name` only (no `resolved`) | 1 | caught (`lockfile:pg`) |
| F3b | lockfile alias, `resolved` only (no `name`) | 1 | caught (`lockfile:pg`) |
| F3-alias | manifest `"db": "npm:pg@^8"` | 1 | caught (`manifest:dependencies:db(npm-alias-for:pg)`) |
| F3-scoped | manifest `"cli": "npm:@supabase/supabase-js@^2"` | 1 | caught, scope-aware split correct |
| F3-opt | `optionalDependencies: pg` | 1 | caught |
| F3-peer | `peerDependencies: postgres` | 1 | caught |
| F3-postgrest | `dependencies: @supabase/postgrest-js` | 1 | caught |
| N5 | lockfile key `node_modules/knex-lite/node_modules/pg` | 1 | caught (nested transitive) |
| NC | negative control `"lodash-alias": "npm:lodash@^4"` + matching lockfile entry | **0** | clean — no false positive |

## New evasion classes found (all rc=0 = MISS; all flag, none blocking)

Each is a manifest-side spec form that resolves to a denylisted package without naming it in the
dependency KEY, in the manifest-present/lockfile-absent window PASS-IF-ABSENT sanctions.

- **F-7 (sharpest — the fence already owns the parser).** `"db": "https://registry.npmjs.org/pg/-/pg-8.11.3.tgz"`
  → rc=0. `nameFromResolved()` exists in this very file and resolves this string correctly; it is
  simply never applied to MANIFEST values, only to lockfile `resolved` fields. Applying the existing
  helper to each manifest spec closes it.
- **F-8.** git / file / GitHub shorthand specs: `"db": "github:brianc/node-postgres"` → rc=0;
  `"db": "file:../vendor/pg"` → rc=0. `aliasTarget()` returns null for both by design. The vendored-
  fork path (`file:`) is the non-adversarial reachability leg — someone vendoring an internal fork.
- **F-9.** `overrides` (npm) / `resolutions` (yarn) can redirect a benign dep to a denylisted package:
  `"overrides": {"a": {"foo": "npm:pg@^8"}}` → rc=0. Neither field is scanned.
- **F-10 (lockfile-side, narrow).** `nameFromResolved()` uses `indexOf("/-/")`, so a registry-proxy
  URL with an earlier `/-/` — `https://npm.corp/-/proxy/pg/-/pg-8.11.3.tgz` — parses to `npm.corp`
  and misses. Only bites when `resolved` is the SOLE signal (no key segment, no `name`); measured
  rc=0 on that shape. `lastIndexOf("/-/")` fixes it.

Reachability assessment: MECHANISM confirmed empirically for all four. REACHABILITY is lower than
the F-1/F-2/F-3 family — each requires an unusual spec form surviving human PR review, and the other
Lock 13 mod #2 layers (no `SUPABASE_*` env vars, Dockerfile RUN-verb fence, JWT shape) stand
independently, so a `pg` that slipped through has no credentials to use. Defense-in-depth is intact.
Hence flag + fast-follow, not a blocker on this PR.

## Three-axis §10 hook — CLEAN on all three

ADR-011 Decision 4 read live and verbatim at `bf4aee5` (located by bracketing the
`### Decision 4 — Defense-in-depth…` header, not by line number). Canonical: catalogued set is
RT-22 first (infrastructure-credential-presence layer) / RT-26 second (code layer) / RT-27 third
(network-exposure/config layer), count 3.

- **instance-numbering** — CLEAN. The changed header and workflow comments enumerate no §10
  instance and carry no count. The `Ledger effect: NONE` paragraph (unchanged by this diff)
  says the ledger is "read live, never pinned here" — correct, Path B.
- **layer-attribution** — CLEAN. The new text claims no layer and moves none. This fence extends
  RT-22's existing CI coverage WITHIN the infrastructure-credential-presence layer D4 already
  attributes to it ("no Postgres client installed in Dockerfile"); no surface becomes "four-layer",
  no new catalogued instance is created.
- **verbatim-vs-paraphrase** — CLEAN. Nothing from D4 is restated. The header's one verbatim quote
  is from the sibling Dockerfile fence's own header and is byte-exact against
  `scripts/ci/fence-rt22-pdf-worker-dockerfile.sh:20-21`, which this PR does not touch.

Anchors verified live: `### Decision 17` exists in `DECISIONS.md`; Lock 13 mod #2
(zero-DB-isolation) is the ADR-011 Decision 17 locked option, and this change STRENGTHENS it.

## Set-boundary checks

- CI-fenced RT set: `git grep -hoE 'RT-[0-9]{2}' <sha> -- .github/workflows/ | sort -u`
  → `RT-05 RT-22 RT-26 RT-27` at BOTH `19a5bdd` and `bf4aee5`. **Unchanged** — no fence-boundary
  change, no escalation trigger.
- §10 catalogued set = RT-22 / RT-26 / RT-27 (D4, read live). It coincidentally overlaps the fenced
  set on three labels and adds RT-05 on the fenced side. **These are different sets and are not
  reconciled here.** Do not tighten the grep to make them match.
- SECURITY DEFINER allowlist: untouched — this PR authors no database function.
- `secrets-manifest.yml`: untouched.

## Note (pre-existing, not introduced by this PR) — owner DevOps

`scripts/ci/fence-rt22-pdf-worker-dockerfile.sh:20-21` still lists "COPY of package.json /
requirements.txt manifests … manifest inspection is human-second-line" under its own
NOT-catching list. That is now false at the RT-22 level: the manifest IS machine-inspected by the
sibling fence. A reader of the Dockerfile fence alone will under-estimate coverage. One-line
forward-pointer, no behaviour change. Present at `19a5bdd` too, so it does not gate this PR.

## Non-objections, stated explicitly

- I do NOT require the discovery loop to enumerate every violating manifest before exiting —
  first-hit-and-fail is correct fail-closed behaviour for a fence.
- I do NOT require a golden fixture for each F-3 evasion class. The negative control plus the
  measured matrix above discharge F-3; adding fixtures is QA's call on cost, not a Sec requirement.
- I do NOT object to PASS-IF-ABSENT surviving this change; F-1's fix preserves it exactly, and the
  discovery loop is what gives it a watcher.
- I do NOT require F-7/F-8/F-9/F-10 fixed in this PR.
