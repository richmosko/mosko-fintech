# SELF-217 historical NAV seeding run — tracked-safe record

Run executed by F/CTO on 2026-08-13 against the local dev DB (the only environment
that exists pre-Phase-7, per [ADR-021](../../DECISIONS.md#adr-021) greenfield). This
record is the **only surviving pre-import-boundary evidence**: after the import, the
fact of where the tenant's history began cannot be reconstructed from the data, by
construction (per the run script's tracked-safe summary contract, Sec-ruled at
[ADR-053](../../DECISIONS.md#adr-053)).

## Tracked-safe summary (verbatim from the run)

```
=== TRACKED-SAFE SUMMARY (no dollar figures, no full UUID — safe to paste into a tracked artifact) ===
Pre-import first_cron_checkpoint (the fact this import ERASES): 2026-08-10
Run date (UTC): 2026-08-13
Requested date range (inclusive): 2015-12-31 .. 2026-07-31
Admissible rows: 128 | Refused rows: 0
Tenant identity: CLI-supplied and DB-resolved uid AGREED (prefix b1aa21a2...)
--commit requested: True
--ack-delta passed: True (required for this run: True)
AC5 delta as % of the boundary-month figure: -99.40%
```

## Post-run verification (team-lead, from the tree, same day)

- 129 rows stand for the tenant: 128 imported + the pre-existing 2026-08-10 cron
  checkpoint; date span 2015-12-31 .. 2026-08-10; written in **one transaction**
  per ADR-053 Decision 6 (all rows or none).
- Sec's pre-run check satisfied by construction: `--end-date 2026-07-31` is 13 days
  before the run date (margin requirement: ≥ 7 days, so no admissible row could be
  silently reclassified as cron by the 7-day zone rule).
- `pfin_etl` re-disarmed immediately after (`rolcanlogin = f`, verified).
- AC5 note: the −99.40% delta is the expected local-dev artifact — the app-side
  computed NAV is near-empty in this environment; acknowledged deliberately via
  `--ack-delta` after reading the printed figures, per the AC5 contract.
