---
name: adr-named-function-semantics-can-move-under-the-name
description: An ADR naming a source function is dated; a later migration can change what that function RETURNS while the identifier still resolves — grepping the name cannot catch it, so diff the live body's row/leaf set against the property you are relying on.
metadata:
  type: reference
---

An ADR that names a function as the source of some data is making a **dated** claim about that function's SEMANTICS, not just its existence. A later `create or replace` can change the row set it returns while the identifier keeps resolving — so the usual defence (grep the identifiers, per [[reference_lock_join_lists_are_dated_artifacts]]) **cannot catch it**. The name is fine. The meaning moved.

**Measured, SELF-353 / A9 (2026-09-05).** ADR-054 Decision 3 (2026-08-12) named `pfin.fn_nav_composition` (`051`) as the per-account leaf source, and the re-derived AC repeated it. `102` and then `105` replaced that function so it now ANTI-JOINS OUT tax-authority-designated ledgers, while `pfin.nav_daily.nav_value` stays `fn_compute_nav(as_of, true)` — gross, still including them (ADR-067 D3). So:

    Sum(051 leaves) = nav_daily.nav_value − Sum(designated ledger balances)

Building the capture worker to the ADR-named source would have made the issue's own reconciliation AC **false on day one** — and false only for users who had designated a ledger, so it would present as a data bug rather than a source-selection bug. The right source was one hop upstream: `fn_account_unrealized_gl` (049), the single leaf substrate `051` itself composes on, whose sum IS `fn_compute_nav` exactly.

**Why the coherence check missed it, and this is the reusable half.** The AC carried an explicit post-V1.4 coherence note that checked A9 against `105` — and the check was SOUND. It checked the **definition** axis ("A9 never renders, so it cannot drift from 105's NAV definition"). The **leaf-set** axis is a different axis. *A coherence note that names the right later artifact still only covers the axis its author was thinking about.*

**How to apply.** Before building to any function an ADR names as a source:
1. Find every `create or replace function <name>` in `supabase/migrations/` — the replacing migration is usually named after something else entirely ([[feedback_mirror_a_function_from_the_catalog_not_the_file]]).
2. Read the LIVE body's FROM/JOIN/WHERE, not the originating migration's.
3. Ask specifically: has the ROW SET moved? An added anti-join, filter, or exclusion is invisible to every identifier grep and to every value assertion that only checks one side.
4. If the ADR sentence is dated and still true of its own date, record the divergence as a **finding in the new artifact**, not as a correction of the ADR — [[feedback_prove_derived_text_against_its_source]].

⚠ Related but distinct: [[reference_lock_join_lists_are_dated_artifacts]] is the case where the IDENTIFIER rots. This is the case where the identifier survives and the SEMANTICS rot, which is strictly harder to see.
