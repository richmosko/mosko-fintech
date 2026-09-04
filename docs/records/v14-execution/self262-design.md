# SELF-262 design memo — `pfin.fn_compute_tax_liability`

**Status:** design only. No DDL is authored here. Written against `origin/main` @ `762f793` plus the four
unmerged migrations read from their branches: `100` (`origin/feature/self-263`), `101`
(`origin/feature/self-259`), `102` (`origin/feature/self-267`), `103` (`origin/feature/self-260`).
Signature per the AC block, adopted as drafted:
`pfin.fn_compute_tax_liability(p_data_as_of date default current_date) returns jsonb`, SECURITY INVOKER.

**§10 cross-check.** ADR-011 Decision 4 read verbatim and live before drafting, 2026-09-04. Three axes
clean — nothing appended, reordered or renumbered; no layer re-attributed; no surface becomes
"four-layer". Path B, no count carried. ⚠ The **catalogued** set and the **CI-fenced** set are different
sets and are not reconciled here. Decision 3 family **flat** — this helper creates no table, no column,
no FK-shaped reference. Decision 9 DEFINER allowlist **unchanged** — INVOKER, per Lock 11.

---

## 1. Payload contract

Three consumers read this (SELF-264, SELF-266, SELF-268), so it is the ADR-carried surface (AC 10).
Top-level keys: `as_of` · `tax_year` · `decomposition` · `jurisdictions` · `nav_components` ·
`prior_year_q4_window`.

```jsonc
{
  "as_of": "2026-09-04",                  // p_data_as_of, echoed so a consumer can prove Seam C threading
  "tax_year": 2026,                       // extract(year from p_data_as_of) — DB-derived (ADR-044; SELF-264 AC 2)

  "decomposition": {                                    // §2.5.1
    "ordinary_income": {
      "rows": [ { "sub_cat_id": 1000000007, "cat": "Revenue", "sub_cat": "Dividend - Qualified",
                  "tax_character": "qualified_dividend", "amount": 1234.5600 } ],
      "total": 1234.5600
    },
    "capital_gains": { "status": "unavailable",
                       "reason": "no_sale_recording_capability" },   // R1 rider 1 — STRUCTURAL, never a row count
    "unclassified": { "count_ytd": 3 }                  // SELF-264 AC 3b — same query that sums
  },

  "jurisdictions": {
    "federal": {
      "status": "computed",                             // | "unavailable"
      "reason": null,                                   // e.g. "no_schedule_any_year"
      "basis_year": 2026, "schedule_present": true,     // E22 — basis_year < tax_year ⇒ fallback in use
      "inputs": { "ordinary_input": …, "lt_cg_input": …, "standard_deduction": … },
      "taxable_income": { "ordinary": …, "lt_cg": … },  // floored at 0 (E25)
      "annual_liability": …,
      "applied_marginal_rate": { "ordinary": 0.2200, "lt_cg": 0.1500 },   // SELF-266 AC 4 (δ-2)
      "tax_balance_prior_year": … ,                     // informational only (μ-2)
      "installments": [ { "quarter": 1, "due_date": "2026-04-15", "amount": … }, … ],
      "ytd_paid":  { "status": "designated", "amount": … },
      "funds_due": { "status": "computed",   "amount": … }
    },
    "california": { … same shape; basis_year 2025 under 103 … }
  },

  "nav_components": {                                   // §2.5.4, the two scalars 051 subtracts
    "realized_tax_liab":   { "status": "computed", "amount": … },
    "unrealized_tax_liab": { "status": "computed", "amount": … }   // clamped ≥ 0 (R9)
  },

  "prior_year_q4_window": { "open": false, "tax_year": 2025, "due_date": "2026-01-15" }  // R8, computed ONCE here
}
```

**Decided — the `{status, amount}` envelope on every figure that can be genuinely unknown**
(`ytd_paid`, `funds_due`, both `nav_components` scalars, plus the existing `capital_gains` shape).
This is B3's enforcement mechanism and not decoration: a consumer writing `payload…ytd_paid ?? 0`
receives an **object**, not a number, so the forbidden `coalesce(…, 0)` cannot be written by accident —
it is a type error at the first arithmetic. Two states that must mean one thing belong in the type, not
in consumer discipline; this is the same move R1 already forced on `capital_gains`, applied uniformly.
**Losing side:** three consumers unwrap `.amount` everywhere, and the JSON is wordier than a nullable
scalar. The alternative — bare nullable numbers plus a QA leg — leaves the coalesce writable and
catchable only if someone remembers the leg. Not taken.

**Decided — money is emitted unrounded at `numeric(20,4)` scale except installments**, which are
rounded to cents with the residual on Q4 (E25): `q1..q3 = round(annual, 2) / 4` rounded to cents,
`q4 = round(annual, 2) − (q1 + q2 + q3)`. The four sum to the rounded annual by construction.

**Decided — `reason` is a stable machine code, not prose.** Copy is the surfaces'. Codes:
`no_sale_recording_capability` · `no_schedule_any_year` · `no_ledger_designated` ·
`ytd_paid_unavailable`.

---

## 2. Composition graph (AC 7, Seam C)

One `p_data_as_of` threaded into every callee. Nothing derives its own date.

| Callee | Migration | Used for |
|---|---|---|
| `pfin.fn_cashflow_items(p_as_of)` | `093` | §2.5.1 Ordinary Income rows + the unclassified count |
| `pfin.posting_prototype` (join `pp.id = sub_cat_id`) | `084` / `100` | `tax_relevant`, `tax_character`, `cat` |
| `pfin.fn_account_unrealized_gl(p_as_of)` | `049` (pinned `079`) | §2.5.4 Unrealized aggregate G/L |
| `pfin.account` | `003` | (π) `tax_treatment = 'taxable'` |
| `pfin.fn_ytd_paid_per_jurisdiction(p_as_of, 'irs'\|'ftb')` | `102` | YTD Paid, twice |
| `pfin.tax_bracket_schedule` / `tax_bracket_row` | `101` / `103` | the bracket walks + standard deductions |

**Not read, deliberately:** `nav_daily`, `fn_compute_nav`, `fn_nav_composition` (`051`),
`transaction_annotation` (does not exist), `fn_tax_authority_ledgers()`. AC 1 strikes the first two;
`051` calls **this**, never the reverse. A `nav_daily` read here would be an AC 1 change routed back to
Sec, and would move Sec 10.5e's SELECT-policy obligation off the `051` read-time path where R3 placed it.

**The `posting_prototype` join is on the surrogate id** (`pp.id = i.sub_cat_id`, the key `093` itself
uses), never on `(cat, sub_cat)` text. A surrogate-id join fails **closed** under an RLS regression; a
shared-vocabulary string join fails **open** and would need an explicit `users_id` conjunct to be safe.

**Revenue-class scope (PM R-1 / Sec 263 F-4, carried at E18).** The Ordinary Income reader filters
`pp.tax_relevant and pp.cat = 'Revenue'`. `Trade / STC` and `Trade / BTC` also carry
`tax_relevant = true` with `tax_character` NULL by design — they are disposition events whose character
comes from the holding period. A reader filtering on the flag alone sums **sale proceeds** into Ordinary
Income. `100`'s own `comment on column` states this on all four tables; the fence is here.
`amount_net` is already positive-for-inflow on Revenue (`093`'s sign table), so no flip is applied.

**M-5, reader half.** For rows the SELF-263 inventory reached, `false` is a determination; for any row
inserted after `100`, `false` is the fail-open DEFAULT. This reader **infers nothing from `false`** — it
selects on `true` and never renders or reports an exclusion as an examined determination. R10 constrains
the column; it does not constrain the reader, and this is the reader's half.

**ADR-062 D2.** `is_tax_payment` is **not** a source anywhere in this helper. It is Expense-scoped and
the seeded tax buckets are Transfer-class, so it cannot reach them. YTD Paid comes from `102` and
nowhere else.

---

## 3. Volatility — `stable`, and it is honest (measured, not assumed)

Declared `stable` in the body, per signature (`create or replace` resets it — AC 11). Every callee's
live declaration, measured against the migration chain on `origin/main`:

| Callee | Declared | Where |
|---|---|---|
| `fn_cashflow_items(date)` | `stable` | `093`, in the body |
| `fn_account_unrealized_gl(date)` | `stable` | **`079` `alter function … stable`** |
| `fn_ytd_paid_per_jurisdiction(date, enum)` | `stable` | `102`, in the body |
| `fn_tax_authority_ledgers()` | `stable` | `102`, in the body |
| `fn_server_today()` | `stable` | `070`, in the body |

**Verdict: `stable` is backed, not an unbacked promise.** ⚠ **A premise repeated in R3 rider 7,
SELF-262 AC 11 and SELF-268 AC 4c is falsified on the tree:** *"`051` and `049` carry none and default
VOLATILE."* `079_volatility_pin_stable.sql` pinned `fn_account_unrealized_gl(date)`,
`fn_compute_nav(date)`, `fn_compute_nav(date, boolean)` and `fn_nav_composition(date)` to `stable`, and
no later `create or replace` has reset them (`102` re-creates `fn_nav_composition` **with** an explicit
`stable`). The **instruction** those three ACs give is still right — declare explicitly, in the body.
Only the stated reason is stale. Correct by amendment, not by dropping the instruction.

⚠ The pin is one `create or replace` away from silent loss, and nothing watches it. Battery leg L-VOL
below closes that.

---

## 4. Where the (π) exclusion lives — Seam F Option B, confirmed

The predicate is `pfin.account.tax_treatment = 'taxable'`, written **inline in this helper's Unrealized
leg** as a join condition to `pfin.account` over `fn_account_unrealized_gl`'s rows. Query layer, one
consumer, one copy.

`tax_treatment` is `not null` with a three-value CHECK (`003`) — so unlike `tax_jurisdiction` (nullable,
R3 rider 0b's default-state bug) there is **no unmarked state** and no silent-omission hazard. Stated
because the two attributes look alike and are not.

**Extract-on-second-consumer rule (AC 6).** The moment a second surface wants the taxable-only
aggregate, the predicate is **extracted** into a shared helper, not copied — the `fn_tax_authority_ledgers()`
shape. Recorded now so the second author extracts rather than restates. ⚠ It is a **different** predicate
from `fn_tax_authority_ledgers()`'s and must not be folded into it: designated-ledger exclusion and
tax-advantaged-account exclusion are different concepts that happen to both be exclusions.

---

## 5. The named residual (R6) — header **and** AC, `093`'s shape

> **NAMED RESIDUAL — recorded so a reader does not conclude the case is handled.** While `wash_sale`
> `basis_adjust` and substantive `corp_action` remain Suspense-parked at `035` / `037`, `cost_basis` is
> understated → `049`'s `unrealized_gl` is overstated → the §2.5.4 Unrealized Tax Liability this function
> emits is overstated; and on the §2.5.1 side the disallowed loss is unrecognized. ⚠ Under R1 the §2.5.1
> half is **currently vacuous on the tree** — no sale writer and no `basis_adjust` writer exist, so the
> Suspense parking's domain is empty today. The residual is recorded precisely so it does not become
> **invisible** when SELF-302 / SELF-303 land. The rejected third state — this function shipping with no
> residual at all — is named at R6 so it is seen to have been weighed.

A header alone is not read at the moment it matters, so it ships in both homes (AC 2b).

---

## 6. The `051` chain of responsibility for SELF-268 — the exact seam

`pfin.fn_nav_composition(p_as_of date)` (`051`, replaced at `102`, `stable`) emits
`buildups.{total_non_re, gross_total, debt, realized_tax_liab, unrealized_tax_liab}` and `nav`. Today
both tax keys are `0::numeric` literals **and both appear inside the `nav` arithmetic**:

```
'nav', (s.total_non_re + s.real_estate) - (-s.liability_signed) - 0::numeric - 0::numeric
```

**SELF-268's whole DB-side change is: replace those four literals — the two in `buildups` and the two
inside `nav` — with `(pfin.fn_compute_tax_liability(p_as_of) -> 'nav_components' -> 'realized_tax_liab'
->> 'amount')::numeric` and its `unrealized_tax_liab` sibling.** One call, threaded with `051`'s own
`p_as_of`. **No second composition path.** The §2.1.1 headline moves its read to `051` (R3 rider 0,
SELF-268 AC 1a); it does not compose its own, and it does not call this helper directly.

⚠ **An obligation R3 did not state, and SELF-268's author must not resolve by instinct.** Under the
`{status, amount}` envelope a scalar can be `"unavailable"`, and `051`'s `nav` expression cannot
subtract a JSON null without turning the whole NAV to NULL. See open question **Q1**.

---

## 7. ADR skeleton — ADR-067 (next free at `762f793`; re-check the number at drafting)

`## ADR-067 — The V1.4 tax substrate: the unified liability helper, the jurisdiction designation, and
the two one-way doors ruled with them`

- `### Decision 1 — Gate A Option B: ONE unified SECURITY INVOKER helper, not per-surface readers`
  Ratified at the Gate A close; recorded only in `CHANGELOG.md` and a Linear description until now.
  Five §2.5 surfaces call one function; §2.5.1 / §2.5.3 / §2.5.4 share one walk and one as-of.
- `### Decision 2 — Gate B Option A: tax-authority designation as an enum on pfin.account`
  `pfin.tax_jurisdiction_enum` + `account.tax_jurisdiction`, realized at `102`. SELF-267 AC 9 records the
  same debt from the consumer side and authors no second copy — one ADR, this one.
- `### Decision 3 — R3 (A′): the NAV composition flip. ⚠ ONE-WAY DOOR.`
  One composed value, one reader; `fn_compute_nav` keeps its gross definition and is read by no live
  surface; `nav_daily` stays gross permanently and is labelled. E-2 exclusion in `051`'s leaf set only.
  Sec VETO on backfill (option C) recorded.
- `### Decision 4 — R4 (C): bracket-table storage grain, child carrying its own users_id. ⚠ ONE-WAY DOOR (sub-part).`
  Decision-3 family membership and the label allocated **at** `101`; the `(4th instance)` ordinal struck.
- `### Consequences` — the residual (§5 above); the E22 fallback; the `{status, amount}` envelope as
  B3's enforcement; the R8 boundary's single home.
- `### Ledgers` — §10 unchanged (D4 read verbatim, three axes clean, Path B, no count); DEFINER
  allowlist unchanged; Decision 3 flat **for this helper** (`101` extends it, and says so itself).
- `### Cross-references` — `049` `051` `056` `070` `079` `084` `093` `100` `101` `102` `103` ·
  PRD §2.5.1–§2.5.4 · sitting-log R1/R3/R4/R6/R8/R9/R11 · execution log E11/E19/E19b/E22/E25 ·
  ADR-011 D3/D4/D9/D18 + Lock 11/14/15 · ADR-044 · ADR-062 D2 · ADR-063.

Headings and one-line decisions only, per the brief. Prose at drafting, in the SELF-262 PR or the next.

---

## 8. Battery outline — every fence gets a leg that can go red

| Leg | Fixture | Asserts |
|---|---|---|
| **L-REV** | seed a `Trade / STC` row with `tax_relevant = true`, `tax_character` NULL, in the tax year | `decomposition.ordinary_income.total` **unchanged**; the row is absent from `rows[]`. Strike the `cat = 'Revenue'` conjunct → red. |
| **L-YTD** | designate no ledger for `ftb` | `california.ytd_paid.status = "no_ledger_designated"`, `.amount` JSON null, **and** `funds_due.status = "unavailable"`. Any `coalesce(…,0)` on the composition path → red. |
| **L-YTD0** | designate an FTB ledger holding nothing | `status = "designated"`, `amount = 0`. Distinguishes 0 from NULL — the leg that makes L-YTD non-vacuous. |
| **L-E22** | only a 2025 `california_ordinary` schedule (i.e. `103` as seeded), `p_data_as_of` in 2026 | `california.status = "computed"`, `basis_year = 2025`, `schedule_present = true`, `annual_liability > 0`. Never `$0`, never silent. |
| **L-E22N** | delete every `california_ordinary` schedule | `status = "unavailable"`, `reason = "no_schedule_any_year"` — **not** zeros (M-11). |
| **L-FLOOR** | Revenue total below the standard deduction (a net-contra Revenue Sub-Cat will do) | `taxable_income.ordinary = 0` and `annual_liability = 0`; never negative, never a negative tax. |
| **L-Q4** | any computed jurisdiction | `sum(installments[].amount) = round(annual_liability, 2)`; `q1 = q2 = q3`; the residual sits on Q4; every amount is cent-scaled. |
| **L-CLAMP** | aggregate unrealized G/L net **negative** across taxable accounts | `nav_components.unrealized_tax_liab.amount = 0`. Strike the clamp → red. (Pairs with SELF-269 AC 4b.) |
| **L-PI** | one `tax_deferred` account carrying a large gain | that gain is absent from the Unrealized aggregate; moving the account to `taxable` moves the figure. |
| **L-R8** | `p_data_as_of` = Jan 10, Jan 15, Jan 16 | `prior_year_q4_window.open` = true, true, false; `tax_year` = prior, prior, current. Three states, one boundary. |
| **L-VOL** | catalog | `pg_proc.provolatile = 's'` for `fn_compute_tax_liability` **and** for each of the five callees in §3. The watcher for a future `create or replace` silently resetting the pin. |
| **L-ACL** | catalog | `revoke execute … from public` / `grant … to authenticated`; `prosecdef = false`; `proconfig` carries `search_path=`. |
| **L-TEN** | two-tenant | tenant B's designated ledger, brackets and Revenue rows are invisible to tenant A's call; a cross-tenant caller gets the empty/unavailable shape, never another tenant's figure. |

Parity evidence keeps structure and percentages and **redacts concrete dollar figures** (AC 9).

---

## 9. Open questions for team-lead

**Q1 — What does `051` subtract when a `nav_components` scalar is `"unavailable"`?** This is the
sharpest one and R3 did not reach it. At bootstrap **no ledger is designated**, so `funds_due` is
genuinely unknown and `realized_tax_liab` is unavailable — the default state, not an edge case.
(a) `051` subtracts 0 and the §2.1.5 row renders unavailable-with-reason; NAV is gross-minus-unrealized
and the row says why. (b) NULL propagates and §2.1.5 renders "NAV unavailable" — loud, but the flagship
number disappears for every un-set-up user. (c) treat no-ledger as `ytd_paid = 0` — that is exactly B3's
forbidden collapse. **Lean (a)**, and it lands as a new AC on SELF-268 rather than here. **Losing side,
named:** (a) omits a real liability, so NAV reads **high** until the user designates a ledger — the same
direction as R3 rider 0b's unmarked-ledger bug, and it needs the rendered reason to be visible, not just
present.

**Q2 — "Until it is paid" is not computable, so the R8 window is date-only.** PRD §2.5.3 says the prior
year's Q4 row shows *"until it is paid or the date passes."* Under Seam B Option A, YTD Paid is the
ledger's balance **since inception** (E19 B1) — it cannot separate prior-year payments from
current-year, so "is it paid?" has no answer in V1. **Lean: the window keys on the date alone**
(`month = 1 and day <= 15`, Jan 15 inclusive), and the payload carries no paid-ness field so no consumer
invents one. This is a PRD-text reconciliation, PM's to land.

**Q3 — California's Q3 due date.** PRD and SELF-266 AC 2 both say CA *"aligns on Q1/Q2/Q4 and differs on
Q3"* without naming the difference. CA FTB's published cadence differs from Federal in the **weighting**
(30/40/0/30), not the dates — and E25 / PM A-11 rule CA weighting stays ÷4. **Lean: emit the same four
dates for both jurisdictions and book the PRD sentence for correction**, because a due date invented in
the helper is a date rule with no source. Alternative: omit `due_date` from the CA block entirely and
let SELF-266 render Federal dates with a caption — worse, it hides the question.

**Q4 — Does this helper emit the §2.5.1 Capital Gains section's Sub-Cat rows at all?** Under R1 they are
structurally empty. **Lean: no rows key at all under `capital_gains`, only `{status, reason}`** — an
empty `rows: []` beside a status is a second way to say the same thing and invites a consumer to render
the array. Costs: SELF-264 must branch on status before reaching for rows, which is what AC 3a wants.

**Q5 — `applied_marginal_rate` when a jurisdiction is unavailable.** **Lean: omit the key entirely**
(not `null`, not `0`), so SELF-266 AC 4's caption renders unavailable by the absence rather than by
interpreting a zero as a 0% bracket.

**Q6 — Does the helper emit `decomposition.unclassified.count_ytd`?** SELF-264 AC 3b requires the count
to come from *the same query that sums*. **Lean: yes** — it is one predicate inside `fn_cashflow_items`
(`sub_cat_id is null and in_ytd`), and emitting it here is the only way the consumer gets it without a
second query that forfeits the property the extraction exists to deliver.
