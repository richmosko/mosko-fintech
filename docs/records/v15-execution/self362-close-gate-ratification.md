# SELF-362 (P10) — the V1.5 close-gate verdict RATIFIED by Security · at `main` = `ab92187` · 2026-09-07

Verbatim from Security (sec-c), grading `self362-close-gate-verdict.md` (log branch `1a593f4`, md5 `b9df4dbbbc09f230d26b408b23dd868d`, computed independently) against the brief at execution log E125. The one grep-only citation (`111` LEG 10, unexecuted locally because `111` aborts at the EXPECTED-DIFFERENT-LOCALLY dblink leg) is discharged here from CI evidence at `01a39c1` carried to `ab92187` by executable identity; that sentence is appended to the verdict file as an addendum. Team-lead ruling at execution log E126.

---

**RATIFIED.** The V1.5 close-gate verdict passes from Sec's side. **md5 of the file I read: `b9df4dbbbc09f230d26b408b23dd868d`** at `1a593f4:docs/records/v15-execution/self362-close-gate-verdict.md` — computed independently, matches yours exactly.

## 1. Summary

I verified the md5 myself, graded (a)–(e), sampled seven citations against `ab92187` rather than the five asked for, and ran the verify-hook. The verdict is a disciplined single-sha measurement that discloses rather than rounds. One citation lacks execution evidence in the recorded run; the verdict says so plainly, and I discharge it below from measurements I already hold.

## 2. Paths read

`1a593f4:docs/records/v15-execution/self362-close-gate-verdict.md` · `ab92187:` — `DECISIONS.md`, `self362_v15_close_gate.sql`, and the `106`/`108`/`112`/`113`/`114`/`115` batteries for sampling. Read-only, from refs.

## 3. Broken

None.

## 4. Bubble up

**(a) ✅ A measurement at ONE sha, and it earns that claim rather than asserting it.** The file records `git rev-parse origin/main` immediately before starting, and — the part I want on the record — `git cat-file -e ab92187:…self362_v15_close_gate.sql` **before proceeding**, naming the prior dispatch sha as the STOP that produced #654. The steps 1–2 carry-forward is not taken on trust either: the empty `git diff --stat eda1179 ab92187 -- supabase/migrations/` is **corroborated independently** by the rebuilt template's `content_sha256` matching the earlier build. **That is a positive control on a carry-forward**, which is exactly the discipline a "carried from an earlier run" claim usually lacks.

**(b) ✅ Seven citations sampled at `ab92187`, seven resolve** — `108` LEG 9 (AC7 CHECK half) · `113` LEG 10 · `114` LEG 10 · `115` LEG 16 (the ×5 no-`rolbypassrls`-EXECUTE standing set) · `113` LEG 8 (AC11 / RT-25) · `112` (6b) · `115` LEG 11 (owner header frozen); plus the AC4 corrupt-the-control block present in the close-gate file itself. The AC7 no-call-to-A3 proof and the AC4 tri-axis collision leg I graded directly at the battery read and re-confirmed present here.

**⚠ ONE CITATION HAS NO EXECUTION EVIDENCE IN THE RECORDED RUN — the verdict discloses it, and I discharge it here.** `111` aborts at LEG 8-i's `dblink_connect` (the documented EXPECTED-DIFFERENT-LOCALLY leg), so **36 planned / 26 ran**, and everything from 8-i onward — **including `111` LEG 10, a cited AC9 leg** — did not execute locally. **This also reconciles the count I could not otherwise square:** the full-tree `Tests=2893` against CI's `Tests=2903` is exactly those **10** unexecuted legs. The verdict handles this correctly rather than papering over it — L45 marks LEG 10 *"present by grep; not locally re-executed"*, L50 exempts it explicitly from the "all files showed `ok`" claim, and the AC9 row at L110 carries the disclosure forward instead of reading a bare PASS. **It does not overclaim, which is the behaviour criterion (b) exists to protect.**

**The missing behavioural evidence exists and I supply it rather than making you go get it.** CI run 34142070004 on `01a39c1` reported `Files=110, Tests=2903, Result: PASS` with zero `not ok` — **2903 includes all 36 of `111`'s legs**, so LEG 10 ran and passed in CI. That transfers to `ab92187` on two measurements I made myself: `01a39c1..a115830` is **zero executable lines changed** (verified over both `+` and `−` lines, and corroborated filter-independently by `plan(54)`/54-assertion parity), and `a115830..ab92187` is a merge commit only. **So `111` LEG 10's evidence is CI at `01a39c1`, carried to `ab92187` by an executable-identity argument.** I recommend that sentence be added to the verdict file as a one-line follow-up alongside the two doc-only fixes — it converts the one grep-only citation into an executed one without a re-run.

**(c) ✅ The non-pgTAP citations name real runs, and one detail is better than it needed to be.** etl pytest on a live scratch clone with the editable-install step spelled out; `api` vitest run as the **full suite rather than a hand-picked subset**, with the reasoning stated — no literal `census` string exists in `api/src`, so guessing a file would have been the riskier scope. The 23 skips are accounted for individually, and the four cited files are confirmed present and green **by name and assertion count**. ⚠ The `workers/pdf-render` handling is the one I would single out: `PUPPETEER_EXECUTABLE_PATH` **unset silently skips the render battery**, and QA re-ran with it set specifically to avoid a false-clean. That is the vacuous-green class caught by the person who would have benefited from not catching it.

**(d) ✅ Residuals stated, not rounded — including the two that reflect on my own work.** The aal2 reachability classification stays a **source read** (E109), not a measurement — which is the bound I asked for and it is honoured. The P4 per-pending-row cost is presented as a **measurement, not a budget**, and it was re-checked against the now-merged `main` rather than carried from the branch citation, with the conclusion unchanged (one RPC per pending draft, capped at one live draft per month by `108`'s partial unique index). Both local-only reds carry their EXPECTED-DIFFERENT-LOCALLY markers with the mechanism named. And the AC11 stale-premise disclosure is handled the right way round: the outdated **justification** is flagged while the underlying conclusion is **re-verified directly** against the live route rather than inherited — the file's `load()` and actions touch only `pfin.monthly_report` and the four already-covered RPCs, no new DB object.

**(e) ✅ No Linear closure is asserted anywhere in the verdict.** Sequencing the batch after ratification is correct; nothing pre-empted it.

**Verify-hook — clean, and there was genuinely nothing to grade on the three axes.** §10 read live from the ADR body at `ab92187`: **count = 3**, RT-22 / RT-26 / RT-27, unchanged. The verdict file makes **no §10, Decision 3, Decision 4 or DEFINER claim at all** — I grepped for one specifically, because a close-gate record restating the ledger is the natural place for instance-numbering or layer-attribution drift to enter. There is nothing to cross-check, which is the right outcome for this artifact. **No drift to surface.** The CI-fenced RT set remains a different set and I did not reconcile them.

**RATIFIED — the V1.5 close-gate passes from Sec's side at `ab92187`.** Three doc-only follow-ups to the close-gate file, none blocking and none changing the verdict: the `TestImpersonationInvariants` → `TestImpersonationAssertion` class-name fix, the stale AC11 "not yet merged" premise, and the `111` LEG 10 CI citation above. **Linear sequencing is clear to proceed from my side.**
