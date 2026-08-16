---
name: rls-battery-file-keyed-to-original-migration
description: supabase/tests/rls/ battery files are named after the function's FIRST migration number and extended in place when a later migration amends the same function — never renumbered/duplicated.
metadata:
  type: reference
---

When a later migration amends an already-battery-tested function (e.g. `072_fn_nav_delta_panel_real_percent.sql` amending the function `071` created), the RLS battery lives at the ORIGINAL file — `071_fn_nav_delta_panel_rls.sql` — and gets extended in place (new `describe`/legs appended, `plan()` count bumped) rather than getting a new `072_..._rls.sql` file. Confirmed via git log: `071_fn_nav_delta_panel_rls.sql` has commits tagged both "071 battery" and "072 battery — ..." in the same file's history (30→33→43→44).

**How to apply:** before assuming a migration lacks its battery half, check whether an EARLIER-numbered `_rls.sql` file was extended for it — `git log -- supabase/tests/rls/<earlier-file>` and grep the file for the later migration's new columns/behavior. Don't conclude a gap from "no file matching this migration's number."

Also: `select plan(N)` counts drift fast (multiple Sec rounds each add legs) — always read the live `plan()` line, never cite a remembered count. See [[feedback_scratch_db_pgtap_harness_gotchas]].
