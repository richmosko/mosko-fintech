---
name: nav-definition-flip-is-a-oneway-door
description: Flipping §2.5.4's tax lines to real values changes the VALUE of NAV inside 051's arithmetic and diverges it from fn_compute_nav/nav_daily, which is append-only with no definition-version column — a genuine one-way door, and the surface is four layers not two.
metadata:
  type: project
---

Measured at `2cd94ae` during the V1.4 pre-flight (SELF-268 / Seam E).

**The two tax lines are not placeholders beside NAV — they are literals inside it.** `051`
`fn_nav_composition` emits `'realized_tax_liab', 0::numeric` / `'unrealized_tax_liab', 0::numeric`
**and** computes `'nav', (total_non_re + real_estate) - (-liability_signed) - 0::numeric - 0::numeric`.
So supplying real values **changes the value of NAV**, not the contents of two display rows.

**Four layers, and the fourth is silent:**
1. `051`'s literals (both the buildup keys and the `nav` expression).
2. `api/src/lib/nav-composition.ts` — `isTaxPlaceholder: true` on both rows.
3. `api/src/lib/components/NavCompositionTable.svelte` — `{row.isTaxPlaceholder ? usd.format(0) : usd.format(row.displayValue)}` **discards `displayValue`**. Fix 1–2 and miss this and the surface renders `$0` against correct data: no error, no failing assertion, passing type-check, green suite.
4. `fn_compute_nav` (`050`) has **no tax leg** — verified by grep. It is what the cron writes to `nav_daily`.

**⚠ The one-way door.** `pfin.nav_daily` (`054`) is append-only audit-class (ADR-011 D2), carries
`nav_value numeric not null`, and has **no definition-version discriminator**. Once the checkpointed
definition changes, history is a mixture of two definitions with nothing in the row to tell them
apart — and a back-fill is (a) a rewrite of an audit surface and (b) a fabrication, since past tax
state is not recoverable. SELF-268's drafted AC4 instructed exactly that back-fill.

**Why:** PRD §2.1.1/§2.1.5 scope the four-component NAV to the composition buildup; the trajectory
(`062` / `067` / `071` / `073`, all reading `nav_daily`) was never given a tax leg. Nobody noticed
because the divergence is zero while the literals are zero.

**How to apply:** treat any change to `051`'s `nav` expression as a NAV-definition change requiring
F/CTO ratify, never as a display fix. My lean was Option A — keep the trajectory pre-tax permanently
and say so in its comments — because it is the only branch that never mixes definitions in an
append-only table. Also: `051` and `049` carry **no volatility keyword** (default VOLATILE) while
`093` is explicitly `stable`; a `create or replace` that adds or drops one is a planner-contract
change no value assertion can see.

Related: [[project_prd_predates_gl_recalibration]] · [[feedback_layers_green_seam_absent]] ·
[[reference_create_or_replace_resets_volatility]] · [[feedback_ratified_name_is_not_a_built_table]]
