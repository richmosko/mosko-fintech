---
name: cpi-positivity-check-must-be-additive
description: The recorded pfin.cpi_u_index positivity-CHECK follow-up must ADD to cpi_u_index_value_finite, never replace it — NaN > 0 is TRUE in Postgres, so a replacement silently re-admits NaN into a financial figure
metadata:
  type: project
---

The open follow-up to add a positivity CHECK on `pfin.cpi_u_index.cpi_value` **must be additive to the
existing `cpi_u_index_value_finite` constraint, never a replacement.** Raised as a Sec flag at the
SELF-218 / migration `067` joint-review (2026-08-12); not yet placed in a tracked artifact at that
time — confirm it landed somewhere durable before relying on this.

**Why:** `053` fences finiteness only (`cpi_value <> 'NaN' and <> 'Infinity' and <> '-Infinity'`), and
`067`'s deflator guards with `cpi_value <= 0`. In PostgreSQL numeric ordering **NaN compares greater
than every non-NaN value**, so `NaN <= 0` is FALSE and `NaN > 0` is TRUE. The two fences are
complementary and *neither alone is sufficient*: a positivity CHECK written as `check (cpi_value > 0)`
that supersedes the finiteness constraint re-admits NaN, which then sails through `067`'s guard and
renders as `nav_inflation_adjusted = NaN` — a financial figure, not a NULL. The migration header's own
parallel instruction (keep the zero-CPI QA leg after the CHECK lands rather than retiring it as
unreachable) is the same shape of hazard.

✅ **Condition (2) IS NOW WATCHED — stop carrying it by hand.** `supabase/tests/rls/053_cpi_u_index_rls.sql`
gained `(q1)` at the SELF-343 ship: *"cpi_u_index_value_finite EXISTS BY NAME on pfin.cpi_u_index — 095 is
ADDITIVE, never a replacement; RED if a future edit drops or renames the finiteness CHECK"*, plus `(q2)`
on the new constraint, `(q3)` on both targeting `cpi_value`, and `(p4)/(p5)/(p6)` proving the NEW
constraint rejects NaN/±Infinity standalone with the finiteness CHECK dropped. From an unwatched
review-time assertion (2026-08-12) to a mechanical fence. Verify `(q1)` still exists before relying on
this — but the review posture on this column is now "confirm the watcher fires", not "re-derive the
hazard". `054`'s `nav_daily_value_finite` has NO equivalent watcher; that half is still hand-carried.

**How to apply:** if a migration touching `pfin.cpi_u_index` constraints reaches review, check the
finiteness constraint survives by name. Four conditions given to team-lead 2026-08-12 for whatever
vehicle carries the fix: (1) the guard predicate must be **finite AND strictly positive** on both CPI
legs — `Infinity > 0` is TRUE too, and an infinite denominator fabricates a `0` adjusted figure while
an infinite numerator fabricates `Infinity`, so neither `<= 0` nor `> 0` suffices alone; (2) additive,
never a replacement; (3) a `create or replace` **preserves the catalog comment**, which is the hazard
not the reassurance — the DIVISION SAFETY paragraph must be re-issued or it describes a guard the
function no longer has; (4) once finiteness holds, a NaN print is un-seedable, so the QA leg must drop
the constraint inside a savepoint (the corrupt-the-control idiom the 067 battery already uses on
`nav_daily_select`) or it cannot exist at all.

**Widened 2026-08-13 — this is a FAMILY, not one constraint.** `054` carries `nav_daily_value_finite`
(NaN + ±Infinity barred on `nav_value`), and `071`'s `v_a_nav > 0` percent guard is sound only because
of it. So at least two fences — `cpi_u_index_value_finite` on `053` and `nav_daily_value_finite` on
`054` — stand behind a `> 0` comparison elsewhere in the tree. **Any migration replacing either with a
positivity CHECK re-admits NaN.** `071` is also the second dependent of the `053` fence (after `067`).

**Status 2026-08-29 — DISCHARGED on `feature/self-343` by migration `095` (Sec verdict AMBER, one
blocking condition on the batteries, not on the file).** All four conditions verified: additive (one
executable `drop constraint`, naming the NEW constraint), predicate `> 0 AND <> 'NaN' AND <> 'Infinity'`,
`067` guard + `comment on function` re-issued in the same file, QA leg not authored by Architect. The
durable home for the conditions is **BACKLOG §7.14 first entry** — read it there, not here.

⚠ **My wording and the artifact's diverge on condition (1), and the artifact is narrower.** This file says
*"on both CPI legs"* (the GUARD); §7.14's transcription says *"on the column"* (the CHECK). That gap made
`095`'s +Infinity clause on the guard look like a widening past the brief when under the original wording
it was already mandatory. Ruled ACCEPT either way. **When a condition of mine gets transcribed into an
artifact, the artifact governs — surface the narrowing, do not silently apply my broader version.**

⚠ **GUARD-SHAPE CENSUS, measured 2026-08-30 at the `096` review — take it before grading any sibling as a
regression.** Two guard shapes coexist over the same divisor. **Four-clause** (`is null` · `= 'NaN'` ·
`= 'Infinity'` · `<= 0`): **`067` ONLY**, and only since `095`. **Two-clause** (`is null` · `> 0` / `<= 0`,
with an in-body comment naming the split — *"053 bars NaN/±Infinity but not zero"*): `071`, `072`, `073`,
`096`. **So `067` is the OUTLIER, not the standard**, and I nearly drafted an AMBER blocking `096` for
matching the majority. Re-measure the census (`grep -n "NaN\|Infinity\|<= 0\|> 0"` over the family
migrations) before calling a two-clause guard weak. **The two-clause shape is sanctioned by MY OWN
standing condition** — §7.14's *Widened* sub-bullet: `> 0` guards in this family "are sound only because a
finiteness CHECK stands behind each." Both CHECKs stand and `066` returns only stored values or NULL, so
NaN/+Infinity are unreachable through the helper. **The general lesson: a hardening applied to one family
member makes that member the outlier; and check whether a prior binding condition of mine already blesses
the shape I am about to flag.** Operative consequence for QA: against a two-clause body a NaN/+Infinity
corrupt-the-control leg **REDs** — full 5-class test parity is not a test-only change, it requires the
code change too. Whether `067`'s shape should become the family standard (touching `071`/`072`/`073`/`096`)
is an open, unrecorded question. Dependent count on `053`'s `cpi_u_index_value_finite` is now **four**
(`067`/`071`/`073`/`096`); §7.14's *Dependent list extended* sub-bullet still says three.

Sec position on sequencing: the hardening is **no-later-than-mandatory**, not same-PR-mandatory — it
is independently correct today and better landing earlier. More generally on this codebase: a
numeric-comparison guard is never a NaN guard — see [[measure-the-fence-regex-not-its-comment]] for
the same claimed-coverage-vs-actual-coverage failure class.
