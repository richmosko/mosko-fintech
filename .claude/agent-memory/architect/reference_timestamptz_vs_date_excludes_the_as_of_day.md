---
name: timestamptz-vs-date-excludes-the-as-of-day
description: `created_at <= $1` with a DATE $1 promotes to MIDNIGHT and drops every row created on the as-of day — Lock 15 / ADR-011 D19 states the filter in exactly this defective form.
metadata:
  type: reference
---

Comparing a `timestamptz` column against a `date` parameter promotes the date to **00:00:00 in
the session zone**, so `created_at <= $1` **excludes everything created ON day `$1`**. The
correct form is the half-open `created_at < ($1 + 1)`.

**Measured** (local stack `supabase_db_mosko-fintech`, read-only, session `TimeZone=UTC`,
2026-08-22): `current_date::timestamptz` → `2026-08-22 00:00:00+00`; `now() <= current_date` →
**false**; `now() < current_date + 1` → **true**.

⚠ **ADR-011 Decision 19 (Lock 15) states the as-of filter verbatim as
`transaction_date <= $1 AND created_at <= $1`** — i.e. the defective form, in ratified text, on
the §2.3.3 drill-down's V1-SHIP-BLOCK path. Implemented literally with `D = today`, **every
transaction the user entered today disappears from the surface**, silently, behind a
correct-looking total. `account_trans.created_at` is `timestamptz` (`004:127`).

**How to apply:** write the half-open bound, and treat the divergence as an **ADR amendment**,
not a build detail — a ratified predicate must not be quietly "fixed" in an implementation.
The promotion is session-zone-sensitive, so this compounds with [[reference_timezone_pin_is_a_default_not_a_fence]]
and the ADR-044 two-clock discipline. A battery leg asserting *a row created ON the as-of date
is INCLUDED* is what catches it; no value assertion will. Related:
[[feedback_prove_derived_text_against_its_source]] — the quote was byte-exact and still wrong.
