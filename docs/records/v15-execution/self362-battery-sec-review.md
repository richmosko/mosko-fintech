# SELF-362 (P10) — the close-gate BATTERY branch (PR #654) · Sec joint-review verdict · GREEN at `378c456` · 2026-09-07

Verbatim from Security (sec-c), measured against `main` @ `eda1179`. This is the review of the battery itself (the new close-gate file plus the `111`/`115` battery edits); the close-gate VERDICT (AC item 14) is measured by QA at the `main` sha this merge produces and ratified by Sec separately (`self362-close-gate-verdict.md`). Team-lead ruling and the corrected anchor (`115` is SECURITY INVOKER, not a D9 member — a brief-drift of mine) recorded at execution log E117.

---

The P10 close-gate battery is **GREEN at `378c456`**, measured against `main` @ `eda1179`. **CLEAR TO MERGE from Sec's side: YES, no conditions.** One brief-drift correction surfaced inline per the verify-hook, and one residual noted.

**md5 `1f145f63ff27a672a62b9cb7330dbac0`** — the three blobs of `910148c..378c456` concatenated in `git diff --name-only` order, read via `git show 378c456:<path>`.

## 1. Summary

I graded the three specific asks — strike controls, a five-citation sample against `main`, and the plan-minus-counter watcher's non-vacuity — plus my own two landed requirements from the #636 and P3-era reviews. All pass. The battery makes no claim I could falsify against the tree.

## 2. Paths changed — all three

`supabase/tests/rls/self362_v15_close_gate.sql` (+501, **new**, `plan(6)`) · `supabase/tests/rls/115_fn_finalize_monthly_report_rls.sql` (+79/−, now `plan(54)`) · `supabase/tests/rls/111_audit_log_rls.sql` (+36/−). **Test files only** — no migration, no workflow, no app source, no `DECISIONS.md`.

**The branch tip has already moved and I checked it rather than waiting for your predicate.** `origin/feature/self-362` is now `e3cc3f7` = `378c456` + a merge of `main`; `git diff --stat 378c456 e3cc3f7 -- supabase/tests/rls/` is **empty**, so all three blobs are byte-identical at the tip and this verdict carries there.

## 3. Broken

None.

## 4. Bubble up

**⚠ BRIEF DRIFT — your anchor list says "D9 (`fn_finalize_monthly_report` DEFINER)". `115` is `SECURITY INVOKER`.** Measured at `origin/main:supabase/migrations/115_fn_finalize_monthly_report.sql` L398–399: `language plpgsql` / `security invoker`. This matches what I measured at the P4 read, and `115` is **not** a member of the ADR-011 Decision 9 DEFINER allowlist. **The good news is that the battery does not repeat it:** `grep -niE "definer|decision 9|D9|allowlist"` over `self362_v15_close_gate.sql` returns **zero**. So the wrong anchor lives only in the dispatch, not in the artifact — but it would have been a wrong-anchor citation in a close-gate record had QA followed it, and it should not propagate into the ratification brief.

**✅ THE STRIKE CONTROLS ARE REAL, and each carries its own non-vacuity proof.** AC7 revokes EXECUTE on `fn_render_monthly_report` outright inside a savepoint to prove the finalize path never calls it — and then, **post-restore**, asserts A3 is callable again and composes a non-null payload for the same tenant, with the leg text saying exactly why: *"the revoke above was a genuine disable, not an accident that happened to leave the leg trivially true."* That is the positive control I would have required, present without my asking. AC4's tri-axis collision carries a corrupt-the-control leg mirroring `110` LEG 1's `(1b)`. `plan(6)` matches six assertion calls (L420/425/438/469/478/492).

**✅ THE FIVE-CITATION SAMPLE — five for five, resolved against `main` @ `eda1179`, not against the branch.** (1) `110` LEG 5/6/7 → 4 header matches; (2) `110` LEG 8 → 1; (3) `110` LEG 1's `(1b)` → 2; (4) `106` `(R2)`/`(X1)` → 5; (5) `109_monthly_report_account_snapshot_rls.sql` present. Every sampled COMPOSED citation points at a leg that exists today. I also note the stack declaration is phrased *"106-115-applied (main tip `910148c` **or later**)"* — an open lower bound rather than a pinned sha, so it does not go stale as `main` moves. That is the right shape and I would have flagged the pinned form.

**✅ THE RAN-COUNT WATCHER IS NOT VACUOUS — and it is better than what I asked for.** `plan(54)`; the watcher compares the declared plan (set once, pre-savepoint, never rolled back) against pgTAP's bookkeeping counter (49) and asserts the gap is **exactly 5** — the four known trailing `14h-i..iv` legs plus the watcher itself, planned but not yet run at comparison time. **A new trailing savepoint-wrapped leg bumps the plan without moving the counter, widening the gap, and REDs this leg by name** — which is precisely the residual I named at the P3-era ruling. It was **inversion-proved**: an injected-fifth-leg scratch copy with `plan()` bumped to match. My wording requirement also landed in substance — *"⚠ THIS IS A KNOWINGLY DISARMED PLAN/RAN WATCHER, NEVER 'COSMETIC'"*, with the reasoning that a watcher exists and has been deliberately disarmed, rather than that nothing was there.

**⚠ NOTE-1 — the watcher's own soundness rests on an unguarded ordering property.** With the watcher in place the *"planned N ran M"* comment no longer appears at all, because the watcher leg's own `ok()` write resurrects the counter to match the plan; the file states that the watcher's comparison runs **before** that resurrecting write. **That read-before-write ordering is what makes it work, and nothing observes the ordering.** If a future edit moved the read after the write — or wrapped the watcher in a savepoint — it would compare 54 against 54 and pass forever, silently, having replaced a knowingly-disarmed watcher with an undetectably-dead one. Failure direction is quiet, not loud. **Not gating** — the file documents the dependency and the inversion proof is on record — but it is the one place in this battery where a plausible future edit turns a control vacuous with nothing to catch it. Worth a sentence in the leg text naming the ordering as load-bearing, if that file is next touched.

**✅ MY TWO LANDED REQUIREMENTS ARE DISCHARGED — re-read at the re-confirm rather than assumed.** (a) `111` leg 8-i is now **re-runnable**: a `conn111i_reset` dblink DELETEs tenant E's `auth.users` row before the insert (relying on `on delete cascade` to clear both tables), with `on conflict (id) do nothing` as defence-in-depth on top. That closes the leak-on-abort finding I raised at #636 — the leg no longer PK-conflicts after a failed run on a persistent DB. (b) The EXPECTED-DIFFERENT-LOCALLY annotation is framed correctly: *"RED in CI would be the genuine finding, RED here is not"*, with the disposition record named. Both are honest about what is and is not proven.

**Verify-hook, read live from the ADR body at `main` @ `eda1179`.** §10 catalogued-instance ledger: **count = 3**, RT-22 / RT-26 / RT-27 — unchanged by this diff, which touches no migration and no ADR. The battery cites RT-21 and RT-25 in leg text but makes **no §10, Decision 3 or Decision 4 claim** — I grepped for one specifically, since a close-gate artifact restating the ledger would be the natural place for instance-numbering drift to enter, and there is nothing to grade on any of the three axes. **No drift to surface** beyond the D9 anchor above. The CI-fenced RT set remains a different set and I did not reconcile them.

**VERDICT — GREEN. CLEAR TO MERGE: YES, no conditions.** Two asks for the ratification brief: drop the D9/DEFINER anchor, and do not carry the verdict forward as having *proven* anything the battery marks COMPOSED — a composed citation is a pointer to another leg's evidence, and my sample verified the pointers resolve, not that the cited legs pass.

---

## Correction to NOTE-1 (Sec, same day, at the fix tip `01a39c1`)

The ordering property is stronger than NOTE-1 stated. The two `_get` calls are ARGUMENTS to the assertion call itself — `is(_get('plan') - _get('curr_test'), 5, …)` — and PostgreSQL evaluates a function's arguments before invoking it, so the counters are necessarily read before `is()` → `ok()` → `_set('curr_test', …)` writes. The ordering is guaranteed by argument-evaluation semantics, not by line placement, and cannot be broken by moving a line; breaking it would require restructuring the leg into two statements with the assertion first. The residual is therefore "do not restructure this into separate statements," not "do not reorder these lines." Sec does not require a comment line on that ground; the constraint-3 comment (the prose-only precedent; the loud failure on a renamed internal) stands on its own merits. The fix at `01a39c1` was measured as one file, +1/−1, both calls, no other schema-qualified pgTAP call in the file (Sec grepped); GREEN stands for all three blobs.

## Re-confirm at the final tip `b4c7a00` and a second Sec self-correction (constraint 3)

GREEN on all three blobs at `b4c7a00`, no conditions. The annotation commit measured as one file +17/−0 with zero executable lines changed (filtered over both `+` and `−` lines). Constraint 2 closed by CI's own log: the pgTAP job reports `115 … ok` with no planned-vs-ran note inside a whole-suite PASS with zero `not ok`/`Dubious`; since the watcher asserts `is(_get('plan') - _get('curr_test'), 5, …)`, a file-level `ok` with a complete plan means it ran in CI and measured exactly five there. Constraint 3 CORRECTED: the risk was overweighted — pgTAP 1.3.3 exposes no public accessor for either counter and `finish()` itself calls `_get('plan')`/`_get('curr_test')`, so every file already carries the dependency transitively; a renamed internal breaks the whole battery loudly, not this leg quietly. The dependency is made explicit here, not introduced. Sec named the pattern for the close-out: two self-corrections in two turns, both over-reading fragility — a cost in hardening effort, not in safety.
