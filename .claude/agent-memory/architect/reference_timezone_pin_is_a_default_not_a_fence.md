---
name: timezone-pin-is-a-default-not-a-fence
description: Migration 061 pins the DATABASE TimeZone, which any client can override via PGTZ — so timestamptz/date comparisons stay session-dependent; make them invariant by margin
metadata:
  type: reference
---

**`061` pins the DATABASE TimeZone to UTC. It is a DEFAULT, not a FENCE.** `061`'s own
header records the measurement:

| state | resulting TimeZone | source |
|---|---|---|
| pin active, no `PGTZ` | UTC | database |
| pin active, `PGTZ=Asia/Tokyo` | **Asia/Tokyo** | **client** |

*"Any client … can move ITS OWN session zone while the database default stays UTC."*
(`TZ` alone is a no-op on the DB session — measured; `PGTZ` is the one that moves it.)

**Consequence:** any comparison mixing `timestamptz` with `date`/`timestamp` is evaluated
in the **session** zone and can answer differently per caller. `date + interval` yields
`timestamp WITHOUT time zone`; comparing a `timestamptz` to it coerces using the session
zone. This is why `062` and `067` both instruct future editors to keep clock functions
and zone-aware casts out of their bodies — the open `nav_date` zone one-way door is not
closed by the pin.

## The technique when you genuinely need such a comparison

**Make it zone-invariant BY MARGIN.** The session-zone offset range is **UTC−12 … UTC+14
— a 26-hour span.** If the two populations you are separating differ by far more than
that, a threshold comfortably above 26 hours gives the same answer under every zone.

Worked case — `069 fn_first_cron_checkpoint`, classifying cron-written vs imported
`nav_daily` rows by `created_at` vs `nav_date`:
- cron rows: gap 0–24 hours (written at day close)
- imported rows: gap **months to years** (historical `nav_date`, backfill-run `created_at`)
- chosen margin **7 days** — ~6.5× the zone span, orders of magnitude under the smallest
  real gap. No session zone can move a row across it.

**How to apply:**
- State the margin's arithmetic in the DDL — *why this number*, not just the number.
- ⚠ **Name the standing condition that could falsify it.** Here: the margin holds only
  while imported rows are separated from their write time by more than 7 days. ADR-053
  makes a near-dated import impossible *today* but guarantees **no minimum distance** —
  a future near-dated import would be silently reclassified, with no error.
- ⚠ **Assert the property, not the tokens.** QA runs the function under two extreme
  session zones and asserts byte-identical output. A token grep would pass over a
  narrowed margin. See [[watcher-not-fence-for-by-construction-properties]] for when a
  test beats a constraint, and [[structural-fence-must-cover-the-same-class]] for why the
  token legs don't substitute.
