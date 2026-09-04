# npm-audit fence pin — Security joint-review

**Verdict: AMBER.** The pin is the right remediation and fail-closed is preserved. Three comment/leg fixes
must land before merge, none of which requires reworking the pin — **and the fence has not yet demonstrated
green on this tip** (the re-run of `Dep scan — npm audit` on `7d2be57` concluded `failure`; cause not yet
readable — see §7 condition 4).

- **Reviewed ref:** `7d2be57ca5f2b207d0223c79f775921e8ca310f9` (`origin/meta/npm-audit-fence-fix`, PR #608)
- **Base:** `origin/main` `762f793`
- **Diff extent (verified):** `git diff --stat origin/main...HEAD` → `.github/workflows/security-scan.yml | 57 +++++`, **57 insertions, 0 deletions**, one file. Matches the brief.
- **Date of measurements:** 2026-09-04

---

## 1. Verify-hook — canonical anchors read live and verbatim

Read from `DECISIONS.md` on the branch tip, located by bracketing `## ADR-` heading (never by line number).

### ADR-011 Decision 4 — §10 catalogued-instance ledger

Read verbatim, including its Amendment (2026-09-03 / SELF-257). The Catalogued-§10-instances bullet
reads **`§10 catalogued-instance count = 3` — RT-22 first / RT-26 second / RT-27 third**, with RT-22 at the
infrastructure-credential-presence layer, RT-26 at the code layer, RT-27 at the network-exposure/config layer.
The Privileged-context-surfaces bullet and the three-layer composition definitions were read in the same pass.

**Three-axis cross-check on this PR:**

| Axis | Result |
|---|---|
| (i) instance-numbering | **CLEAN** — the PR asserts no §10 instance numbering. `scanner-npm-audit` carries no RT label and is not a catalogued instance. |
| (ii) layer-attribution | **CLEAN** — no layer attribution is added, moved or restated. |
| (iii) verbatim-vs-paraphrase | **CLEAN for canonical text** — the added comment block quotes npm CLI output and the npm/cli#7911 PR title, not ADR/Lock wording. No canonical content is absorbed or paraphrased. (Separate factual-accuracy defects in the same comment are F-3 / F-4 below; they are not §10 paraphrase drift.) |

**Ledger effect: NONE.** No catalogued instance is added, removed, reordered or renumbered.
This is not an ADR-011 D4 change and is not joint-review-mandatory on that basis.

### CI-fenced RT set vs §10 catalogued set — measured, NOT reconciled

```
grep -rhoE 'RT-[0-9]{2}' .github/workflows/ | sort -u
```

- On branch tip `7d2be57`: **RT-05, RT-22, RT-26, RT-27**
- On `origin/main` `762f793`: **RT-05, RT-22, RT-26, RT-27**

**Unchanged by this PR.** This is not a fence-boundary change and is not an escalation trigger.

⚠ The CI-fenced set (RT-05/22/26/27) and the §10 catalogued set (RT-22/26/27) are **different sets and
must never be reconciled.** RT-05's presence in the fenced set is a comment reference in `web-tests.yml:73`
(a Sec condition on the `jose@^6.2.5` dependency for RT-05's ES256/JWK verify) — a dependency-hygiene note,
not a fence label. Do not "clean this up."

### ADR-016 Decision 1 — read verbatim, NOT engaged

ADR-016 Decision 1 is titled *"V1 RT-26 `service_role` allowlist composition is three named surfaces"*.
It governs the `SUPABASE_SERVICE_ROLE_KEY` allowlist. **It is not a "fail-closed CI fences" decision**
(the review brief described it that way — see D-1 below). This PR touches no `service_role` surface,
adds no allowlist entry, and does not engage ADR-016 D1 or D2's addition convention.

**I do NOT require an ADR amendment for this change.**

### Brief-vs-source drift surfaced by the verify-hook

- **D-1 — ADR-016 D1 mis-glossed in the brief** as "fail-closed CI fences". It is the RT-26 `service_role`
  allowlist composition. No consequence for the verdict; recorded so the gloss is not inherited forward.
- **D-2 — RT-05 mis-attributed in the brief** as "RT-05 / the dep-scan fence". Measured: RT-05 in
  `docs/SECURITY/index.html` (`id="rt-05"`, line 442) is *"Plaid webhook authenticity — ES256-JWT signature
  verification (gates production credential-state mutations)"*, critical severity. It has no relationship to
  dependency scanning. See F-6 for what this means for the amendment question.
- **D-3 — my own error, named here rather than in a follow-up.** I first read the brief's cited evidence job
  `100951099828` as belonging to a different run and was preparing to report it as misattributed. It is
  correct: `gh api .../actions/jobs/100951099828` resolves to *"Dep scan — npm audit (high+critical)"*,
  `run_id 33850227966`, conclusion `failure`. The `100955132589` I found by `gh pr checks` is a **re-run** of
  the same job in the same run. The brief's citation is accurate; my initial reading was not.

---

## 2. Fail-closed posture — PRESERVED

Read `.github/workflows/security-scan.yml` lines 293–410 on the branch tip.

- No `|| true` anywhere in the job.
- `--audit-level=high` unchanged.
- Enumerator unchanged (`git ls-files '*package.json' 'package.json' | grep -v '^tests/'`).
- The nested-`node_modules` inversion probe (plant → assert not enumerated → fail closed) unchanged.
- The audit loop is `(cd "$d" && npm audit --audit-level=high)` under `set -euo pipefail`, **not piped**,
  so npm's exit code propagates and a registry error fails the job.
- The new pin step is a bare `run:` with no error suppression: if the global install fails, the job fails.
- The pin step is inserted **after** `actions/checkout@v4` + `actions/setup-node@v4` and **before** the
  audit step. Ordering correct.

**Demonstrated, not merely reasoned** — reproduced locally against the branch worktree with npm **11.19.0**
(the pinned version):

- **Root tree (`.`) → `found 0 vulnerabilities`.** This is the exact tree that failed under npm 10 with the
  `/audits/quick` 400. Under the pinned client it audits **clean**. This is a positive demonstration that the
  pin fixes the reported failure, and it independently confirms the comment's conclusion that the root
  lockfile is not stale.
- **`api/` tree → bulk-endpoint network timeout → `npm error audit endpoint returned an error`,
  non-zero.** Confirms both halves of the intended behaviour: the error now names the **bulk** endpoint
  (no quick fallback, no misleading "run npm install" message), and the fence **fails closed** on a
  registry transient. (This leg is inconclusive as to `api/`'s cleanliness — the timeout is plausibly local
  to my sandbox; it is conclusive as to the failure *shape*.)

### Ruling: the 5xx-vs-finding question

**I do NOT require a mechanical retry-then-fail loop, and I rule against adding one.**

Rationale: (i) npm exits `1` for both a genuine advisory and an endpoint error, so any mechanical
discriminator must grep npm's stderr — a fragile predicate on an unstable string, and a fence built on a
fragile predicate is worse than no discriminator; (ii) GitHub's re-run control already supplies the retry,
operated by a human who has seen the log; (iii) a retry loop is a new place for the fence to be softened —
the natural next edit under schedule pressure is "retry N times, then warn", and that is how a fail-closed
fence becomes theatre.

**What I require instead is attributability: the job must not label a registry error as a dependency
finding.** `security-scan.yml :: scanner-npm-audit` satisfies this today — it emits no claim about the cause.
`scheduled-dep-audit.yml` does not. See F-1.

---

## 3. Findings

### F-1 — FLAG — `scheduled-dep-audit.yml` carries the identical defect, unpinned, and its inversion probe goes vacuous under exactly this failure. Owner: **DevOps**

Measured: `.github/workflows/scheduled-dep-audit.yml` uses `actions/setup-node@v4` with `node-version: '22'`
(line 54). Node 22's current release bundles **npm 10.9.8** (`https://nodejs.org/dist/index.json`) — i.e.
**pre-#7911, the same defective client this PR exists to escape**. That job runs `npm audit
--audit-level=moderate` over the same three tracked manifests and has **not** received the pin.

Two consequences, and the second is the serious one:

1. The scheduled fence is still exposed to the masked `/audits/quick` 400.
2. **Its inversion probe (lines 74–96) asserts only `rc != 0`** on a tree pinned to
   `nanoid@3.3.16` / GHSA-2v37-7h3g-55p8. An endpoint error satisfies `rc != 0` **identically to a real
   advisory**. Under the exact condition this PR exists to fix, the probe passes for the wrong reason —
   it stops proving "this job can detect an advisory" and starts proving "this job can exit non-zero."
   The probe's own comment states its purpose as *"proves this job CAN go red on a real advisory"*;
   that property is not what it currently measures.
3. The audit loop then annotates the failure as
   `::error title=Dependency advisory in $d::npm audit --audit-level=moderate exited $rc` — a **RED whose
   message names the wrong defect**. The repair that message invites is triaging a non-existent advisory,
   or lowering the threshold. Both disable the watcher.

**Catch criterion for the fix (two parts, both required):**

- Add the same pin step to `scheduled-dep-audit.yml` before the inversion probe.
- Strengthen the probe so it asserts the *advisory* is reported, not merely that the command failed —
  e.g. run `npm audit --json`, and fail closed unless the output contains the pinned advisory's identifier
  (`GHSA-2v37-7h3g-55p8`). A probe that cannot distinguish "found the vulnerability" from "could not reach
  the registry" is not an inversion probe.

**Scope boundary:** `scheduled-dep-audit.yml` only. Do not change its `moderate` threshold; the existing
comment's rationale for not using `low` (the `cookie <0.7.0` advisory reaching `@sveltejs/kit` with no
non-breaking remediation) still stands and is correct.

### F-2 — FLAG — `web-tests.yml :: api — dependency vuln audit` is also unpinned. Owner: **DevOps**

Measured: `.github/workflows/web-tests.yml` line 140 `node-version: '22'` → npm 10.9.8; line 144
`run: npm audit --audit-level=moderate`. Same pre-#7911 client, same latent masked-400 failure, over the
`api/` tree at PR time.

Lower urgency than F-1 (it audits one tree, it has no misleading annotation, and it fails closed), but the
tree now has **three npm-audit fences and only one pinned client**. A fix applied to one of three instances
of a defect class is a fix that will be re-diagnosed from scratch the next time the other two trip.

**Catch criterion:** same pin step, same version, before the audit step.
**Scope boundary:** the `api — dependency vuln audit` job only; do not touch the `Web app` build job's Node.

### F-3 — FLAG — the comment's central causal claim is false as measured. Owner: **DevOps**

The comment asserts, and rests its conclusion on:

> today (2026-09-04) it is fully retired and returns a blanket 400 "Invalid package tree" to ANY request it
> receives — including a well-formed one — rather than genuinely reporting this repo's lockfiles as malformed

**Measured today (2026-09-04), directly against the endpoint:**

```
POST https://registry.npmjs.org/-/npm/v1/security/audits/quick   →  HTTP 200
```

with a well-formed minimal tree body, returning a valid audit result — and, with `nanoid@3.3.16` in the body,
correctly returning advisory `1139427` / GHSA-2v37-7h3g-55p8. The endpoint **is live and functional**. It
emits a *retirement notice*; it has not been retired.

Also measured: `POST .../-/npm/v1/security/advisories/bulk` → **HTTP 200**, returning the same advisory.
The bulk endpoint is up.

**Why this matters even though the fix is right.** The remediation is correct and the conclusion "the root
lockfiles are not stale" is correct — I proved the latter independently (§2: root audits clean under
11.19.0). What is wrong is the **stated mechanism**, and this comment is a durable record that the next
engineer will cite rather than re-measure. A false mechanism in a security-fence comment is the seed of the
next misdiagnosis. It also matters directionally: if the 400 was a *genuine* response about the body npm 10
constructed for the root tree, that is a different fact about npm 10 than "the endpoint blanket-rejects",
and only one of those is true.

**Commit-ready replacement** for the sentence beginning *"registry.npmjs.org scheduled that endpoint"*
through *"neither is stale)"* — DevOps commits verbatim, no paraphrase, no re-flow:

```
      # registry.npmjs.org has scheduled that endpoint for retirement and npm
      # emits a retirement notice on every call to it. It is NOT yet fully
      # retired: measured 2026-09-04, a well-formed POST to
      # /-/npm/v1/security/audits/quick returns HTTP 200 with a valid audit
      # result (verified by submitting a tree pinning nanoid@3.3.16 and getting
      # back advisory GHSA-2v37-7h3g-55p8). So the 400 "Invalid package tree"
      # the ROOT tree received is the endpoint's genuine validation response to
      # the body npm 10 constructed for it, not a blanket rejection. The
      # lockfiles themselves are fine and this is measured, not inferred: root
      # and api and workers/provider-sync are all lockfileVersion 3, and under
      # the PINNED npm 11.19.0 the root tree audits clean ("found 0
      # vulnerabilities") — the same tree that 400s under npm 10. What npm 11
      # buys is therefore not a working /audits/quick; it is the removal of a
      # fallback to an endpoint whose 400 said nothing true about this repo.
```

### F-4 — NOTE — `11.19.0` is not the 11-line head. Owner: **DevOps**

The comment states the pin matches *"npm's current 11-line HEAD at authoring time"*. Measured against the
registry: `dist-tags.next-11` = **11.19.1**, and the highest published `11.x` is **11.19.1**.

**Do not bump.** `11.19.0` is past #7911 (merged 2024-11-20), satisfies the engine constraint, and pin-exact
is the correct policy. But the comment's stated justification for choosing that exact patch is off by one,
and a future reader will treat it as the head. Correct the parenthetical to
`(11.19.0; the 11-line head at authoring time was 11.19.1 — either is past #7911)` or drop the head claim.

### F-5 — FLAG — the global npm install has no integrity assertion. Owner: **DevOps**. Two acceptable shapes; state the losing side

`npm install -g npm@11.19.0` resolves and downloads at run time. What it *does* verify: npm checks the
tarball against the `dist.integrity` sha512 the registry serves in the packument. What it does **not**
verify: that the integrity value itself is the one we intended. A registry-side or publisher-account
compromise substitutes both tarball and integrity together, and the install still succeeds. This is a real
class — the September 2025 npm publisher-account-takeover wave is directly on point — mitigated here by the
fact that `npm` is published by npm/GitHub itself, and by npm's no-republish rule making a *published*
version's contents immutable in the ordinary case.

**Against supply-chain minimalism:** the job already contacts the registry (that is what `npm audit` does),
so the marginal new surface is narrow but real — the fence job now **executes a freshly downloaded binary**
rather than the toolcache npm that GitHub provisions.

**Options, with the losing side of each named:**

- **A — accept as-is (my recommendation for V1).** Version-pinned, immutable published version, first-party
  publisher, ephemeral runner. *Losing side:* a registry/publisher compromise of `npm` itself in the window
  between publish and our run is undetected, and we would learn about it from the news rather than from CI.
- **B — pin + assert (cheap, and I recommend it as the F-5 fix).** Keep the install, then fail closed unless
  `npm --version` is exactly `11.19.0`, and additionally assert the resolved integrity against a committed
  value: `sha512-SDd/hHg3KqHE5Ht2NHWxNYNtqCQ2pXAPLl6OtQhPyED5PHsRfrOtO199MZTIG2cQoQ1ZRI9t28shrD+2cr3AAw==`
  (measured from `registry.npmjs.org/npm/11.19.0` → `dist.integrity`, 2026-09-04), compared against
  `npm view npm@11.19.0 dist.integrity`. *Losing side:* the integrity assertion compares the registry's
  claim to a value we once read **from the same registry**, so it detects a *change* in what the registry
  serves, not a compromise that was already in place at the moment we recorded it. It is a
  tamper-evidence control, not an authenticity control — say so in the comment so nobody over-reads it.
  It does close the realistic failure it is worth closing: a silently partial or wrong-version install.
- **C — vendor the tarball into the repo with a committed sha512.** The only shape that actually pins
  authenticity. *Losing side:* an ~11 MB binary blob in the repo, a manual bump ritual, and a new
  never-updated artifact — which is its own security debt. **I do not recommend C at V1** and I am not
  requiring it.

**Minimum I require: option B's version assertion** (`npm --version` equals `11.19.0`, else exit 1). Without
it, a partially-failed global install leaves the job running the *unpinned* npm 10 and re-entering the exact
failure the pin exists to prevent — silently, because the audit's subsequent error would look like the same
registry problem.

### F-6 — NOTE — no `docs/SECURITY/index.html` amendment is owed, because the dep-scan fence has no row there at all. Owner: **Architect** (disposition), **PM** (backlog if adopted)

Measured on the branch tip:

- `grep -c 'npm audit' docs/SECURITY/index.html` → **0**
- `grep 'security-scan.yml' docs/SECURITY/index.html` → **0 matches**

So: **the pin is below the abstraction of every existing row, and there is no row to amend.** The brief's
premise that an RT-05 row might need its mechanism sentence updated does not hold — RT-05 is the Plaid
webhook ES256-JWT authenticity test (D-2 above), and this change does not touch it.

The residual is a different observation: **the npm/pip dependency-scanning posture is entirely uncatalogued
in the V1 canonical Sec reference layer.** Three fail-closed dep fences run in CI and none is described in
`docs/SECURITY/index.html`. That is a documentation gap, not a defect in this PR, and the disposition is
Architect's call — not mine to make and **not something I am blocking on**. I flag it so it is a decision
rather than an omission. If it is adopted, the §10 disposition is **Path B (drop-enumeration-let-link-carry)**:
the doc should reference the workflow, not restate the fence mechanics, which drift on every pin.

### F-7 — FLAG — the job retains a fail-OPEN empty-enumeration escape whose stated rationale is obsolete, and whose sibling job already refuses it by name. Owner: **DevOps**

Pre-existing, not introduced by this PR, but it is inside the reviewed surface and it is the strongest
finding in this review.

`scanner-npm-audit` currently reads:

```
          if [ -z "$PKG_FILES" ]; then
            echo "INFO: no package.json under mosko-fintech V1 scope — npm audit no-op as expected at W1."
            echo "INFO: This scanner becomes load-bearing at first npm-init commit."
            exit 0
          fi
```

An empty enumeration exits **0 — green**. The stated justification is the *"pre-SvelteKit-init posture"* at
W1. That premise is now false: measured on the branch tip, `git ls-files '*package.json' 'package.json' |
grep -v '^tests/'` returns **three** manifests — `api/package.json`, `package.json`,
`workers/provider-sync/package.json`. There is no pre-init state to accommodate.

What remains is a leg that converts an enumerator breakage into a **silent green** on a fail-closed security
fence — the same class the job's own nested-`node_modules` probe exists to catch, left open on the other
side. `scheduled-dep-audit.yml` already refuses exactly this posture in its own words: *"an empty enumeration
means the enumerator broke, not that there is nothing to audit. Failing closed."* Two jobs, one enumerator,
opposite postures on the same failure.

**Catch criterion:** an empty `PKG_FILES` must fail the job, not pass it. Commit-ready replacement —
DevOps commits verbatim:

```
          if [ -z "$PKG_FILES" ]; then
            echo "FATAL: no tracked package.json found. This job audits a known-nonempty set"
            echo "       (root + api/ + workers/provider-sync/ as of 2026-09-04); an empty"
            echo "       enumeration means the enumerator broke, not that there is nothing to"
            echo "       audit. The W1 pre-SvelteKit-init no-op posture this leg used to carry"
            echo "       is obsolete. Failing closed — same posture as scheduled-dep-audit.yml."
            exit 1
          fi
```

**Paired golden-test fixture required** (QA, or DevOps if it lands in-workflow): an inversion leg asserting
that an empty enumeration exits non-zero. A fence that does not fail closed is theatre, and a fence whose
fail-closed leg has no watcher becomes fail-open on the next refactor.

### F-8 — NOTE — the comment enumerates two of three audited trees. Owner: **DevOps**

The comment states *"root's and api's package-lock.json are both lockfileVersion 3 and both match their
package.json"*. The job audits **three** trees. `workers/provider-sync/package-lock.json` is omitted from the
claim. Measured: all three are `lockfileVersion 3` (root `mosko-fintech@0.0.0`, `api@0.0.1`,
`provider-sync@0.0.1`). No defect — the claim is true as far as it goes; it just stops one short of the set
it is characterising. The F-3 replacement text above already covers all three.

### F-9 — NOTE — stale enumerations in the file header, pre-existing. Owner: **DevOps**

Two, both in `.github/workflows/security-scan.yml` lines 5–21, both predating this PR:

- Line 11: `ADR-016 D1 (3 V1 RT-26 allowlist surfaces)`. Accurate as a citation of D1's *content*, but the
  **live** registry is one surface — `scripts/ci/rt26-allowlist.txt` header: *"ONE V1 service_role surface
  per ADR-016 Decision 4"*, after D3 added a fourth and D4 removed three. A reader consulting this header to
  learn the current allowlist size gets `3` against a live `1`. This is the scoped-count-characterising-an-
  unscoped-collection shape that ADR-011 D4's own CHANGELOG documents.
- Lines 8, 14–15: the §10 enumeration names RT-22 first and RT-26 second and stops. The same file hosts
  RT-27's fence and names it *"the THIRD catalogued §10 instance"* at line 501. The header's assertions are
  each **true**; the enumeration is **incomplete** relative to both the live ADR-011 D4 ledger (count = 3)
  and the file's own body.

Neither is a false assertion and neither blocks. Fixing them can ride this PR since it already edits the
file. If they are fixed, the correct shape is to **drop the parenthetical counts** rather than update them —
they will re-stale — and let the ADR links carry the content (Path B).

---

## 4. Scope of the pin — CONFIRMED job-local

`npm install -g npm@11.19.0` runs inside `scanner-npm-audit`. GitHub Actions gives every `job` a fresh
runner, so a global install cannot reach another job. Verified there is no shared composite setup step:
each job in `security-scan.yml` declares its own `steps:` beginning with `actions/checkout@v4`.

Specifically confirmed unaffected:

- `Unit + typecheck + build (hermetic)` — a different workflow entirely (run `33850228117`), not in
  `security-scan.yml`.
- `web-tests.yml :: Web app — svelte-check + build + docker` — separate workflow, separate runner,
  Node 22 / npm 10.9.8 unchanged. Its `npm ci` still resolves under the bundled npm. No behaviour change.
- `dedup-hash — import_hash canonical↔copy drift fence` — same workflow file, separate job, its own
  `setup-node` at `node-version: '22'`. Unaffected.
- `worker-ci.yml` — separate workflow, no `npm audit`, unaffected.

**I do NOT require the pin be scoped more narrowly.**

---

## 5. Verified claims from the change's comment block

| Claim in comment | Verification | Result |
|---|---|---|
| npm/cli#7911 is *"fix!: remove old audit fallback request"* | `api.github.com/repos/npm/cli/pulls/7911` | **TRUE** — title byte-matches; merged 2024-11-20, base `latest` |
| npm 11 is the first major past #7911 | merge date 2024-11-20 vs npm 11.0.0 (2024-12-16) | **TRUE** |
| `setup-node` @ Node 20 installs npm 10.x | `nodejs.org/dist/index.json` → v20.20.2 bundles **npm 10.8.2** | **TRUE** |
| npm 12.0.2 `engines.node` = `^22.22.2 \|\| ^24.15.0 \|\| >=26.0.0` | `registry.npmjs.org/npm/latest` | **TRUE** — verbatim match; EBADENGINE against Node 20 is correct |
| npm 11.x `engines.node` = `^20.17.0 \|\| >=22.9.0` | `registry.npmjs.org/npm/11.19.0` | **TRUE** — verbatim match; Node 20.20.2 satisfies it |
| root + api lockfiles are lockfileVersion 3, not stale | parsed all three lockfiles; root audits clean under 11.19.0 | **TRUE**, and stops one short — see F-8 |
| the `/audits/quick` endpoint is fully retired, blanket-400 | direct POST, twice | **FALSE** — HTTP 200 with valid results. See F-3 |
| 11.19.0 is the current 11-line head | `dist-tags.next-11` | **FALSE** — head is 11.19.1. See F-4 |
| the 314-vs-3 enumerator figure (pre-existing comment) | not re-measured; requires a warm workspace | **NOT VERIFIED** — relayed, not confirmed |
| run 33850227966 job 100951099828 log contents | job resolves and `conclusion: failure` confirmed via API; **log archive not retrievable while the run is in progress** | **PARTIALLY VERIFIED** — the failure is confirmed; the specific log lines are DevOps's measurement relayed, not independently read by me |

---

## 6. Explicit non-objections

- I do **NOT** require an ADR amendment. ADR-011 D4's ledger is unchanged (count = 3, RT-22/26/27, read
  verbatim); ADR-016 D1/D2 are not engaged; the CI-fenced RT set is byte-identical on both refs.
- I do **NOT** require the pin be reverted, replaced with a vendored tarball, or moved to `corepack`.
- I do **NOT** require a mechanical 5xx-vs-finding discriminator or a retry loop — I rule against both (§2).
- I do **NOT** require the `--audit-level=high` threshold to change.
- I do **NOT** require the `docs/SECURITY/index.html` gap (F-6) be closed before merge.
- I do **NOT** object to the long comment block. A measured cause recorded at the fix site is exactly the
  right shape; the objection is to two of its factual claims, not to its existence or length.
- I do **NOT** treat this as an ADR-011 D1/D2/D3, Lock 11, Lock 13, Lock 14, SD-03, or `secrets-manifest.yml`
  surface. None is touched.

---

## 7. Merge conditions

**Blocking (must land before merge):**

1. **F-3** — replace the false mechanism sentence with the commit-ready text above, verbatim. *(DevOps)*
2. **F-5** — add the `npm --version` equals `11.19.0` fail-closed assertion after the install. *(DevOps)*
3. **F-7** — flip the empty-enumeration leg to fail closed, verbatim text above. *(DevOps)*
4. **Green `Dep scan — npm audit` on the final tip — CURRENTLY UNMET, and this is a live condition, not a
   formality.** APPLIED is not DEMONSTRATED. Measured during this review: the job was re-run on tip
   `7d2be57` as `run 33850227966 / job 100955132589` and **concluded `failure`**
   (`gh api repos/richmosko/mosko-fintech/actions/jobs/100955132589` → `status: completed`,
   `conclusion: failure`). The run's log archive is not retrievable while the run is in progress, so
   **I have not read the cause and do not assert it.**

   Context that bounds the reading: the "wait for the outage to clear" premise no longer holds — I measured
   both `/audits/quick` and `/-/npm/v1/security/advisories/bulk` returning **HTTP 200** today, and the root
   tree audits **clean** under the pinned 11.19.0. My own local `api/` and `workers/provider-sync/` legs did
   hit bulk-endpoint network timeouts, which is consistent with continued intermittency, but that is a
   plausible explanation, not a measured one.

   **DevOps owes the failing log line before merge.** Two outcomes with different dispositions, and they must
   not be conflated: if it is another registry transient, re-run and merge on green. If the pinned client
   fails for a *different* reason, the diagnosis in the comment block is incomplete and this review is not
   discharged — bring it back. Branch protection enforces the gate mechanically
   (`mergeStateStatus: BLOCKED`); this is recorded so a subsequent green is not waved through without
   someone having read why the red happened.

**Non-blocking, tracked:**

5. **F-1** — pin `scheduled-dep-audit.yml` and de-vacuum its inversion probe. *(DevOps)* — should be its own
   issue; it is the higher-severity finding and it is not this PR's scope.
6. **F-2** — pin `web-tests.yml :: api — dependency vuln audit`. *(DevOps)*
7. **F-4 / F-8 / F-9** — comment accuracy; may ride this PR or the F-1 PR. *(DevOps)*
8. **F-6** — dep-scan posture catalogue disposition. *(Architect)*

---

## 8. Escalations to F/CTO

- **None on veto grounds.** No veto is issued.
- **One judgment call you might have made differently:** I classified F-7 (the fail-open empty-enumeration
  leg) as a **blocking flag on this PR** rather than a separate issue, on the grounds that it is inside the
  reviewed surface, its stated rationale is measurably obsolete, and it is a three-line fix. A reasonable
  alternative is to merge the pin now and take F-7 as its own PR with a paired inversion fixture. I did not
  veto and will not block if you prefer that ordering — but it should be an explicit decision, not a
  deferral, because a fail-open leg in a fail-closed fence is precisely what nobody comes back for.
- **Attribution discrepancy, for the record:** the review brief specified
  `Co-Authored-By: Claude Fable 5.1` and a different `Claude-Session` URL than the one this session was
  subsequently instructed to use. I followed the later session-level instruction, which stated it replaces
  earlier attribution guidance. Flagging rather than silently choosing.

---

## 9. Re-review — 2026-09-04, diff `7d2be57` → `94a13c3`

**Verdict on the diff: GREEN, conditional on CI green.** One file, `94 insertions / 15 deletions`
(`git diff --stat 7d2be57 origin/meta/npm-audit-fence-fix`). All three blocking items discharged. One
new non-blocking flag (F-10) on the *added probe*, not on the fence.

### Discharged

| Item | Verification | Result |
|---|---|---|
| **F-3** mechanism text | extracted the block from `git show 94a13c3:.github/workflows/security-scan.yml` and from §F-3 of this record; both **14 lines, md5 `f849d2419e3b84eba2c2c1148ac6fe2f`**; `diff` empty | **DISCHARGED — byte-identical.** Committed verbatim, no paraphrase, no re-flow |
| **F-8** all three trees named | the landed text reads *"root and api and workers/provider-sync are all lockfileVersion 3"* | **DISCHARGED** (carried by the F-3 block) |
| **F-4** version-line head | parenthetical now reads *"11.19.0; the 11-line head at authoring time was 11.19.1 — either is past #7911"*; **no bump**, as required | **DISCHARGED** |
| **F-5** version assertion | new `Assert pinned npm version` step: `ACTUAL="$(npm --version)"`, exact string compare against `11.19.0`, `exit 1` otherwise, under `set -euo pipefail` | **DISCHARGED — option B minimum met.** Doubly covered: the runner's default `bash -e` already fails the pin step on a failed install, and this catches the wrong-version case it cannot |
| **F-7** the leg itself | audit step's empty-enumeration branch now `exit 1` with the supplied FATAL text, read verbatim from `94a13c3` | **DISCHARGED — verbatim** |
| **F-7** paired fixture | see F-10 | **NOT DISCHARGED** |

### F-10 — FLAG (non-blocking) — the added inversion probe is vacuous. It cannot red on the regression it names. Owner: **DevOps**. **This is my own requirement returning defective, and I own the correction**

The `Inversion probe (empty enumeration must FAIL closed)` step **re-implements the leg inside itself**
rather than exercising the real one. It `git init`s a throwaway repo, then runs its **own inlined copy**
of `if [ -z "$PKG_FILES" ]; then echo FATAL...; exit 1; fi` and asserts that copy exits non-zero. That
proves shell `exit 1` works. It has no coupling to the leg in the audit step.

**Measured by corrupt-the-control, not reasoned:**

1. Extracted the probe step's `run:` block from `94a13c3` and ran it standalone →
   `OK: empty-enumeration leg exited 1 with the expected FATAL message.`, rc 0.
2. Produced a mutant workflow with **the real leg reverted to `exit 0`** — the exact defect F-7 exists to
   prevent, fully reintroduced — re-extracted the probe **from the mutant**, and ran it →
   `OK: empty-enumeration leg exited 1 with the expected FATAL message.`, **rc 0. Still green.**

**The drift guard is aimed at the wrong object too, and this is the part that would mislead.** The step's
third check greps `$PROBE_OUT` — the output of its *own* inlined copy — and its failure text claims to
catch *"the message text drifted from the leg it is meant to prove."* It cannot: the real leg's message
is never read. So the probe asserts a property about itself while describing that property as being
about the fence. That is a **false strength claim in a control's self-description**, and its
characteristic harm is that the one real control next to it starts looking like a redundant belt.

**Why this is a flag and not a veto, stated plainly:** the security-load-bearing change — the leg now
failing closed — is landed and correct, and the probe does not weaken it. The probe is decorative. But a
decorative probe is worse than no probe, because it reads as a watcher, and it was *my* requested fixture,
so it must not be recorded as discharging F-7's second half.

**Remediation — replace the probe with a static watcher over the real artifact. I built and tested this;
it is a verified control, not a proposal.** The leg lives inside a `run:` block and cannot be invoked in
isolation, so the honest options are (A) extract the leg to `scripts/ci/` and have both callers use it —
correct but a real refactor of a live fence, or (B) scan the workflow itself. **B is the cheap honest one
and I recommend it.** Delete the `Inversion probe` step (its inlined copy is also a second, confusing
occurrence of the leg) and substitute:

```yaml
      # STATIC WATCHER for the empty-enumeration fail-closed leg (Sec review F-7 / F-10).
      # The leg lives inside the audit step's `run:` block and cannot be invoked in
      # isolation, so a probe that re-implements it proves only that shell `exit 1`
      # works — measured 2026-09-04 by Sec corrupt-the-control: with the real leg
      # reverted to `exit 0`, the re-implementing probe stayed GREEN. This scans the
      # REAL artifact instead, and fails closed if it loses its target.
      - name: Assert empty-enumeration leg still fails closed
        run: |
          set -euo pipefail
          WF=.github/workflows/security-scan.yml
          LEG=$(awk '/- name: npm audit \(fails on high or critical\)/{f=1} f && /if \[ -z "\$PKG_FILES" \]; then/{p=1} p{print} p && /^          fi$/{exit}' "$WF")
          if [ -z "$LEG" ]; then
            echo "FATAL: could not locate the empty-enumeration leg in $WF — the watcher lost"
            echo "       its target, which is indistinguishable from the leg being gone."
            echo "       Failing closed (Sec review F-10)."
            exit 1
          fi
          if ! printf '%s\n' "$LEG" | grep -q 'exit 1'; then
            echo "FATAL: the empty-enumeration leg no longer exits non-zero. A broken enumerator"
            echo "       would pass through to a false-green audit. Failing closed (Sec F-7)."
            exit 1
          fi
          if ! printf '%s\n' "$LEG" | grep -q 'no tracked package.json found'; then
            echo "FATAL: the empty-enumeration leg's FATAL message drifted from what this watcher"
            echo "       asserts. Failing closed so the drift is caught, not silently accepted."
            exit 1
          fi
          echo "OK: empty-enumeration leg still exits non-zero with its FATAL message."
```

**Measured behaviour of that watcher (four cases):** clean `94a13c3` → `OK`, rc 0 · real leg mutated to
`exit 0` → `FATAL: … no longer exits non-zero`, rc 1 · FATAL message mutated → `FATAL: … message drifted`,
rc 1 · leg deleted entirely → `FATAL: … watcher lost its target`, rc 1. **It reds on every mutation the
vacuous probe sleeps through.**

⚠ Note for whoever lands it: this is a fence that scans the prose of its own workflow file. That is the
right shape here, but it means the `awk` anchors (`- name: npm audit (fails on high or critical)` and the
ten-space `fi`) are load-bearing — the empty-`LEG` branch exists precisely so a renamed step or a
re-indent reds instead of silently matching nothing.

### Merge condition 4 — still UNMET, and the "outage" premise is now evidenced rather than assumed

DevOps reports four failing runs across two tips (08:11–08:44Z) all reading
`npm warn audit 503 Service Unavailable - POST …/-/npm/v1/security/advisories/bulk` at the `api/` audit,
with the three new steps passing every run. **I relay that, I did not read those logs.**

What I can add from my own probes: at ~08:00Z I measured the bulk endpoint returning **HTTP 200**; at
~08:35Z the same probe failed three consecutive times at the connection level (`HTTP 000`).
That is **consistent with** DevOps's measurement in direction and timing, but it is connection-level
failure from my host, not an observed 503 — I am corroborating intermittency, not confirming the status
code. `status.npmjs.org` reporting operational does not contradict either observation; endpoint-level
degradation routinely does not reach a status page.

**The disposition I set at condition 4 is satisfied on the branch that matters:** the failure is the
honest, un-masked bulk-endpoint error the pin exists to surface, the three new steps pass, and the same
tree audits clean locally minutes apart. **Re-run until green and merge on green.** If the failure ever
changes shape — anything other than a bulk-endpoint 5xx/timeout at the `api/` audit — bring it back;
that would mean the diagnosis is incomplete.

### Standing items unchanged by this diff

F-1 (`scheduled-dep-audit.yml` unpinned, and its inversion probe vacuous under this same failure —
**note the shared root with F-10: two probes in this repo assert "the command failed" rather than
"the defect was detected"**), F-2 (`web-tests.yml` unpinned), F-6 (dep-scan posture uncatalogued in
`docs/SECURITY/index.html`), F-9 (stale header enumerations). None blocks this PR.

### Verify-hook, re-run against `94a13c3`

`grep -rhoE 'RT-[0-9]{2}' .github/workflows/` → **RT-05, RT-22, RT-26, RT-27** — identical to `origin/main`
and to `7d2be57`. No fence-boundary change. ADR-011 D4 ledger untouched (no §10 claim added; the diff
asserts no instance numbering and moves no layer attribution). ADR-016 D1 still not engaged. **No ADR
amendment owed.** Three axes clean.
