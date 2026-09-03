# V1.4 pre-flight recalibration — sitting agenda

**Status: NOTHING HERE IS RULED.** This file is the team-lead's consolidation of three findings files into the order F/CTO rules them in. Rulings land in `sitting-log.md` (not yet written) as they are made, with provenance per [ADR-063](../../../DECISIONS.md#adr-063) Decision 3 — F/CTO ruling vs default-and-notify, never flattened.

**Baseline: `origin/main` @ `2cd94ae`** (2026-09-02). `main` moved to `7818504` during the pass by two agent-definition-only merges (#599, #600); no schema or code moved, so the baseline was held, not re-read.

**Inputs, by ref** (each verified on `origin` at consolidation):

| File | Owner | Branch tip | Scope |
|---|---|---|---|
| [`architect-findings.md`](architect-findings.md) | Architect | `94d68c6` | schema-identifier audit of 9 + 4 issues, 10 seams (A–J), dispatch order, promotion recommendation |
| [`rederived-acs.md`](rederived-acs.md) | Architect (PM copy folded, credited) | `94d68c6` | landing-ready replacement AC text, every block self-carrying the baseline sha; `⟨RULING⟩` placeholders where a ruling is owed |
| [`pm-findings.md`](pm-findings.md) | PM | `25c5685` | PRD §2.5 slice (13 passages), product classification, SELF-264 ruling, §7.28 item 3 carrier, 302/303 placement, scope flags, Part B product pass |
| [`sec-findings.md`](sec-findings.md) | Sec | `637987d` | joint-review map (13 of 13 MANDATORY), 11 money flags, isolation exposure, catch criteria, F/CTO items, two retractions named |

Issue text: `temp/v14-preflight/issue-dump.md` (md5 `9d128f6d…`, 9 V1.4 issues + context 211/225/226/245) and `issue-dump-deps.md` (md5 `c35fe5ef…`, SELF-259/260/261/262, all Backlog, no comments). Gitignored; the findings quote what they rely on.

---

## 1. What the pass measured

- **0 of 9 V1.4 issues buildable as drafted; 0 of 4 Platform dependencies buildable as drafted.** All three files agree. Same result in kind as V1.3 (0 of 14), same cause: drafted at Wave 5 against the pre-GL substrate.
- **The two halves fail differently.** The §2.5 seven are product-correct with falsified identifiers. The Platform four are identifier-correct with falsified conventions and stale Decision-3 ordinals.
- **The milestone's schema surface is not in the milestone.** SELF-259 (bracket tables), SELF-260 (seed) and SELF-262 (the helper five of seven issues call first) sit in Platform V1.x. Six of nine V1.4 issues block on them.
- **Sec map: 13 of 13 joint-review MANDATORY, none light-loop eligible** under ADR-066.
- **Two issues are IMPOSSIBLE as written** (SELF-263: deliverable already on `main` under `009`/`011`/`041`/`084`/`091`; SELF-268: AC4 instructs the rejected one-way-door option). **One is likely to close, not build** (SELF-261: duplicates `023`).

## 2. Already ruled — on the agenda only to be RECORDED, not re-decided

- **Gate B Option A** (`account.tax_jurisdiction` enum; F/CTO 2026-06-03). Lives only in CHANGELOG + a Linear description. Owed an ADR home at SELF-262's ADR (with Gate A Option B). Not a Decision-3 instance (enum column, not FK-shaped). Sec's F-1 retracted as an open item.
- **`is_tax_payment` marking pass outcome = zero** (F/CTO 2026-08-25 on SELF-245). Sec's M-6 retracted. ⚠ Does NOT clear the `tax_relevant`/`tax_character` inventory (§7.28 item 3, Sec M-5/F-6b), which is a different deferral and still unowned.
- **Seam E option C (back-fill `nav_daily`) — Sec VETO**, two grounds, reached independently by all three. Options A and B remain.

## 3. Rulings owed, in proposed sitting order

Order follows PM's proposal with Architect's dependency reasoning. One per turn.

| # | Ruling | Options and leans | Blocks |
|---|---|---|---|
| R1 | **Seam J — §2.5.1's capital-gains columns have no V1 input path.** `088` is BUY-only; `lot_match` has zero writers in migrations and `api/`. The columns would render `0.00` forever. Milestone-shape question. | (A) ship §2.5.1 with the CG section UNAVAILABLE-with-reason, Ordinary Income live — PM + Architect lean. (B) pull the sale writer + lot_match activation into V1.4. (C) defer §2.5.1 whole. Consequence of (A): Sec F-2 becomes a V1.x ruling, not a V1.4 blocker. | 264, 266, 269, 262 AC2 |
| R2 | **Seam W/G — does V1 ship a user-marked wash-sale flag?** PRD §2.5.1 names it; nothing on the tree implements it; the only `wash_sale` is a `basis_adjust` reason. | (A) no V1 flag (nearly free under R1-A: no sale to mark) — PM + Architect lean. (B) the `basis_adjust` route; SELF-302 then returns as §2.5.1 fuel. (C) an annotation column — rejected by both. Decides SELF-261's disposition. | 264 AC12, 269 AC8, 261, 302 |
| R3 | **Seam E + E-2 — the NAV composition flip, ruled TOGETHER with the tax-authority NAV exclusion.** One-way door. `051` hardcodes both tax lines as `0` inside the `nav` arithmetic; `nav_daily` is append-only with no definition-version column. E-2 (PM's A-9, Sec-confirmed): IRS/FTB ledgers as manual accounts plus a net-of-payments liability double-count each payment, NAV moves +P for money that is gone. SELF-268 creates the defect. | (A/A′) headline + §2.1.5 foot composed at read time over `fn_compute_nav` + `fn_compute_tax_liability`; `nav_daily` and the chart stay gross and say so — PM lean, Architect confirms feasible with `fn_compute_nav` untouched, Sec non-objection. (B) Sec non-objection under three conditions in its file. Exclusion: rendered, not just applied (ADR-049); one extracted predicate shared with YTD-Paid (ADR-063 D2). ⚠ Sec: under (A) the headline-vs-foot copy must name BOTH tax lines AND designated-ledger balances. | 268 AC3a/AC4, 267 AC2a, 262 AC12 |
| R4 | **Seam A — bracket-table grain, with its Decision-3 sub-part.** SELF-259's drafted AC1/AC2 ARE Option A (child references parent only). | (A) as drafted: `schedule_id` is the sole tenant anchor, `tax_bracket_row` gets a matched-tenant fence that Sec judges a leg that CANNOT FAIL. (C) child carries its own `users_id` beside `schedule_id`: the fence is falsifiable, one D3 label allocated AT the migration per D18 — Architect + Sec lean. ⚠ The drafted "(4th instance)" ordinal is STRUCK either way; no number is drafted in advance. | 259 → 265, 262 |
| R5 | **SELF-263 re-scope.** Its migration deliverable already shipped under other names. Residual = the §7.28 item 3 inventory session (`tax_relevant`/`tax_character` on BOTH the posting-prototype pair AND the asset-side `taxonomy_default` rows — the booking omitted the asset side, which gates the whole CG half). | (A) re-title 263 to carry the inventory session + seed-delta migration, first in the order — PM + Architect lean; discharges Sec F-6b by construction. (B) close 263, open a fresh issue. (C) rejected on the tree. | 263, 264 hard-gate AC |
| R6 | **Seam I + SELF-302/303 placement.** Neither traces to a §2.5 story; both arrived by the `037` deferral note; both move §2.5 numbers silently until they land. PM: the Suspense parking they fix has an EMPTY domain today (no `basis_adjust` writer). | (A) move both to Platform V1.x, 262 first with a named residual, return trigger recorded — PM lean, Architect concedes with the residual. (B) keep in V1.4 at step 5 before 262. Sec D-6 rider on 303 survives either way. | 302, 303, 262 |
| R7 | **Platform-lane promotion.** SELF-259/260/262 into V1.4 (the SELF-245/246/247 precedent); SELF-261 stays in Platform pending R2. | (A) promote the three; V1.4 becomes 12 named issues; ledger names the set and drops the count — PM + Architect lean. ⚠ Architect names the losing side: Platform is always in Linear, so this buys ownership clarity and a close-gate that sees its substrate, NOT access or throughput. (B) keep in Platform; steps 2/4/6 of the order run on Platform cadence and a stall reads as a V1.4 problem. | the whole order |
| R8 | **Sec F-4 — the prior year's Q4, due Jan 15, between Jan 1 and Jan 15.** UTC pin + calendar-year scope drop it. ONE answer for 266 and 267, same date boundary. | (A) accept the gap for V1, book in §5 with the reason. (B) extend the §2.5.3 render window to show the outstanding Q4 until its due date — PM lean. (C) tax-year cursor instead of calendar year. | 267 AC4c, 266 |
| R9 | **Sec F-3 — does Unrealized Tax Liability floor at zero?** Negative aggregate unrealized G/L makes it negative and `051` subtracts it: NAV rises. | (A) clamp at zero — PM lean. (B) allow negative. (C) clamp + informational "unrealized loss carry" note. | 268 AC6 |
| R10 | **Sec F-5 — `tax_relevant DEFAULT false`.** | (A)+(C) keep the DEFAULT, fence at the consumer, `comment on column` scoping what `false` means — PM + Sec agree. (B) drop the DEFAULT ADR-062-style. ⚠ Constrains the column, not the reader; R5 still owns the inventory. | 263 AC6 |
| R11 | **Sec F-2 — unmatched sell's ST/LT disposition.** Under R1-A this has no V1 instance. | (A) route to ST/ordinary, fail-closed on tax — Sec + PM lean. (B) UNAVAILABLE-with-reason. (C) LT — understates silently, Sec would flag. Recommend: rule now for the record, cite at V1.x. | 262 AC2 (dormant) |
| R12 | **Ordering judgment — SELF-268 at step 9, after the two read surfaces.** Not a dependency; Architect and PM both prefer it (walk the legible tax surfaces before the flip moves the headline). | Accept, or invert to right after 262. | the order |

**Default-and-notify candidates** (team-lead takes these unless F/CTO objects; recorded in the log with reasoning, reversal window open until the amendment batch merges): PM's `tax_authority` (copy) vs ratified `tax_jurisdiction` (schema) — schema wording governs, product phrase kept for user-facing strings · SELF-266 AC7's false-composite citation (SELF-261 → SELF-265) · SELF-269 AC8's non-existent `pfin.transaction_annotation` → the shipped `account_trans_annotation`, AC6's "SERIALIZABLE guarantees integrity" struck, AC4's `tax_deferred`/`tax_free` literal · SELF-267's `p_users_id` parameter dropped from an INVOKER signature (SELF-211 precedent; Sec D-2) · SELF-259's monotonicity trigger re-shaped to a deferred CONSTRAINT TRIGGER (BEFORE ROW cannot see later rows in the same statement) · SELF-259 AC3 raised to the `090` policy standard (USING + WITH CHECK, per-verb, `025` aal2 clause, grants) · SELF-260 AC5's "no Sec joint-review" struck (Architect + Sec both route it to joint-review) · SELF-262 AC2's ">365 days → LT" corrected to "more than one year" · SELF-262's EXECUTE ACL pair + `set search_path = ''` + volatility added.

## 4. Doc fixes owed, no ruling needed

- `MILESTONES.md` Active Feature row: "8 issues" omits SELF-264 (in V1.4 in Linear, PRD-traced, V1-ship-block). Name the set, drop the count. Folded into the close-out PR after R7 settles the set.
- ADR fold-in of Gate A Option B + Gate B Option A at SELF-262's ADR (two rulings currently findable only in CHANGELOG + Linear; the class ADR-062 opens by naming, found a second time).
- `BACKLOG.md` §7.28 item 3: widen to the asset-side `taxonomy_default` rows (per R5).

## 5. Proposed dispatch order (Architect §5, PM concurs, R6/R7/R12 may move rows)

```
Step 0  the sitting (R1–R12)
1       SELF-263 re-scoped: inventory session + seed delta      ∥ 2 and 3
2       SELF-259 bracket tables (Seam A lands here)             ∥
3       SELF-267 YTD-Paid overlay + Gate B ADR fold-in           ∥
4       SELF-260 seed                                            after 2
5       [SELF-302 + 303 — only if R6 keeps them in V1.4]
6       SELF-262 fn_compute_tax_liability — the keystone         after 1,2,3,4
7       SELF-265 brackets settings editor                        after 2,4
8       SELF-264 ∥ SELF-266 — the two read surfaces              after 6 (7 for 266's Edit target)
9       SELF-268 NAV composition flip (R3)                       after 6, 8
10      SELF-269 RLS battery — close-gate, LAST                  after all
```

Every issue is Sec joint-review MANDATORY; every user-facing one is walk-gated before the Sec spawn (ADR-063 Decision 4).

## 6. Bookings that outlive the sitting (candidates for a §7.32)

- Off-tree F/CTO rulings living only in Linear descriptions/comments — second and third instances found this pass (Gate B; the SELF-245 marking outcome). Sec's proposed rule: before calling an absence an omission, ask what the discharge would have looked like.
- `lot_match` is write-ENABLED (`036`) with zero writers: the grants advertise a live surface nothing reaches (Architect, Seam J).
- SELF-261's design rationale is worth preserving as the account of why `023` has its shape, even as the issue closes.
- The M-4 UTC-pin year boundary (Pacific user flips year ~7h early) is broader than §2.5 and unowned.
