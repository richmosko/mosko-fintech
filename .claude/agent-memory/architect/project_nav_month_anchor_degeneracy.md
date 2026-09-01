---
name: nav-month-anchor-degeneracy
description: The 071/072 month-anchor is degenerate on month-end days (delta always 0); 073 carries the same defect and the RATIFIED copy of the ruling; Option C RATIFIED 2026-08-30; fixed by 097 + ADR-065 on feature/self-344.
metadata:
  type: project
---

`pfin.fn_nav_delta_panel()`'s `v_base` CASE makes today its own base when today IS a
month-end, so the month anchor and the current endpoint resolve via the identical
at-or-before LOCF query -> `delta_nominal = 0` (not NULL) on ~12 days/year.
`073_fn_nav_reference_dates` re-derives the same CASE and binds `prior_month` to it,
so its levels table shows two identical NAV rows the same days.

**Why:** authored latent; QA reproduced it live on the 2026-08-31 wall clock. Root
cause of the latency: the 071 battery pins `:base` with a **verbatim copy of the
body's CASE**, violating 071's own header rule (c) — fixture and body agreed by
construction. See [[feedback_mirror_a_function_from_the_catalog_not_the_file]].

**How to apply:**
- **The live object is 072's, not 071's** — 072 DROP+CREATEs it for the added
  `delta_inflation_adjusted_percent` column. Any fix is a NEW migration; shape is
  unchanged so `create or replace` works and no other file's `regprocedure` leg
  breaks. ⚠ CoR **preserves** the comment, so re-issue `comment on function`
  explicitly or 072's false "month = base" text survives. And restate `stable`
  ([[reference_create_or_replace_resets_volatility]]).
- **The ruling exists twice with DIFFERENT statuses.** 071's header calls it "a
  PRODUCT CALL IMPLEMENTED AS A DEFAULT, NOT AN ARCHITECTURAL RULING"; 073's header
  calls the same question "NOW RULED … F/CTO-ratified 2026-08-14". Citing 071's
  weak copy understates what an anchor change reopens. No `DECISIONS.md` home
  exists for either — grep DECISIONS.md for `fn_nav_reference_dates`: zero hits.
  Generalizes [[feedback_a_rationale_home_is_not_an_enforcement_home]].
- **RATIFIED and SHIPPED (Option C, 097 @ 8fa8a93):** the month horizon and 073's
  `prior_month` use the existing CASE's ELSE branch unconditionally
  (`date_trunc('month', today) - 1 day`); `v_base` untouched for 1y/3y/5y.
  Making `v_base` itself strictly-before is WRONG — it moves the 1y anchor to 13
  months back on those days.
- **ADR-065 is now the canonical home** — the rule previously lived in four
  migration headers and two catalog comments at two ratification statuses. 071
  was deliberately LEFT UNEDITED (072 commits to that), so its weak-status copy
  is still reachable and still misleading; cite ADR-065, never 071's header.
- The 071 header's rejection of "month-end at-or-before (today - 1 month)"
  ("up to six weeks back") is **not** reopened by option C: on month-end days the
  two readings coincide exactly and the excess is zero. Check a rejection's stated
  COST at the boundary before treating it as blocking.
