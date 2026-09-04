# SELF-263 — tax-value inventory proposal (row-by-row dispositions + the four decisions)

**Status:** PM PROPOSAL — team-lead rules by recommendation (F/CTO delegation, sitting-log R5 provenance). Nothing here is a ruling. No migration is drafted here; the seed delta + backfill + `comment on column` are SELF-263 AC 3 / 4 / 6 and Architect's.

**Baseline:** `origin/main` @ `762f793` (read 2026-09-03). Method: migration files read in full — no psql. Row sets derived by replaying every statement that touches the two default tables (`grep -n 'insert into\|update\|delete from' supabase/migrations/*.sql` filtered to `posting_prototype_default` / `taxonomy_default`, then each hit read).

| Table | Rows | Derivation |
|---|---|---|
| `pfin.posting_prototype_default` | **29** | `041` cashflow 27 (7 Revenue / 12 Expense / 4 Transfer / 4 Trade) copied at `084:715` → +2 Equity at `091:272`. No value UPDATE on `tax_relevant`/`tax_character` anywhere after `084` (`091` touches `is_tax_payment` only). |
| `pfin.taxonomy_default` (asset) | **38** | `041` asset 36 → +`Cash / Cash Balances` (`077`) → +`Liabilities / Liability Balances` (`080`) → Cat `Equity` renamed `Marketable Securities` (`082`) → `element` added (`085`, not a tax column). Cashflow rows deleted at `084:1316`. All 38 are `false` / NULL today. |

**Vocabulary (fixed, `011`):** `ordinary` · `qualified_dividend` · `tax_exempt_interest` · `long_term_capital_gain_eligible` · `short_term_only`. FK-enforced; no sixth value is proposed (AC 7).

**Two facts that bound every disposition below.** (a) PRD §2.5.2's routing table reads `tax_character` **only on Ordinary-Income-column contributions**; the ST CG / LT CG columns route by holding period, `any` character. So an asset-side character routes nothing in V1 — it is the eligibility declaration the PRD reserves for the V2+ §2.5.4 refinement. (b) A prototype row is one value for **all** of a user's accounts; `pfin.account.tax_treatment` (`003`: `taxable` / `tax_deferred` / `tax_free`) and `account_type` are per-account. Anything "per account type" cannot be a value on either default table.

---

## 1. Cash-flow side — `pfin.posting_prototype_default` (29 rows)

Legend: *now* = `tax_relevant` / `tax_character` at baseline. Conf = H/M/L.

| # | Cat | Sub-Cat | now | PROPOSED | Reason | Conf |
|---|---|---|---|---|---|---|
| 1 | Revenue | Interest - Tax Free | true / tax_exempt_interest | **confirm** | Municipal-bond interest: excluded Federal; CA excluded uniformly in V1 (PRD §2.5.1; in-state split V2+). | H |
| 2 | Revenue | Interest - Ordinary Inc | true / ordinary | **confirm** | Bank/cash interest is ordinary income, Federal + CA. | H |
| 3 | Revenue | Interest - Bond/CD | true / ordinary | **confirm** (open item O-1) | Coupon/CD interest is ordinary. Treasury coupons are CA-exempt — the vocabulary cannot say so; V1 overstates CA (fail-closed). | H |
| 4 | Revenue | Rent Misc | true / ordinary | **confirm** | Rental income is ordinary. V1 counts it gross (Schedule E netting is ζ-3 V2+) — overstates, not understates. | H |
| 5 | Revenue | Bond Premium | true / ordinary | **confirm value; notes-only clarification** — see D-ii | Bond-premium amortization / market-discount accretion is an adjustment to *interest* (1099-INT/OID), so its character is ordinary; it is never capital. The seeded note *"Mark-to-Market Gain for Tax Purposes"* reads as §1256 MTM, which is 60/40 capital — the note is wrong, the value is right. | H |
| 6 | Revenue | Dividend | true / qualified_dividend | **confirm value; notes-only clarification** ("qualified") — see D-ii, which also proposes an added sibling row | Qualified dividends are taxed at LT-CG rates Federally; CA ordinary. The row cannot distinguish non-qualified dividends (REIT, bond-fund, money-market) — D-ii. | M |
| 7 | Revenue | Salary Untagged | true / ordinary | **confirm** (open item O-2) | Wages are ordinary. | H |
| 8–19 | Expense | Auto & Transport · Bills & Utilities · Cash & ATM · Entertainment · Food, Dining, & Alcohol · Gifts and Donations · Health & Fitness · Home · Misc · Personal Care · Shopping · Travel | false / NULL (×12) | **confirm ×12** | Expenses are not income. Itemized deductions (charitable under *Gifts and Donations*, medical, mortgage interest under *Home*) are a Schedule-A model V1 does not carry — §2.5.2 holds a standard-deduction scalar only. Decided, not defaulted. | H |
| 20 | Transfer | Cash | false / NULL | **confirm** | Inter-account movement; not income. | H |
| 21 | Transfer | Tax - US Federal | false / NULL | **confirm** | A tax payment is not income. §2.5.3 YTD Paid reads the tax-authority account ledger (Gate B Option A, `tax_jurisdiction`), never this flag — SELF-263 AC 5 rider. | H |
| 22 | Transfer | Tax - California | false / NULL | **confirm** | Same as 21. | H |
| 23 | Transfer | Fixed Assets | false / NULL | **confirm** | Purchase of a fixed asset is a transfer to a slush fund per the seeded note; not income. | H |
| 24 | Trade | BTO | false / NULL | **confirm** | Opening a long is not a tax event. | H |
| 25 | Trade | STC | true / NULL | **confirm** (reader obligation R-1) | Closing a long is a disposition; character is by holding period (§2.4.3), NULL by design (Sec E-1). Dormant under R1-A (no sale writer). | H |
| 26 | Trade | STO | false / NULL | **confirm** | Opening a short: premium/proceeds are not recognized until close. | H |
| 27 | Trade | BTC | true / NULL | **confirm** (reader obligation R-1) | Closing a short is the disposition; as 25. | H |
| 28 | Equity | Contribution | true / NULL + ADR-062 D4 rider | **CHANGE → false / NULL; rider REPLACED** — see D-i | Owner capital entering the portfolio is never income. Deductibility of a retirement contribution is an AGI adjustment (per-account, `tax_treatment`) that V1's §2.5.2 model has no line for. | H |
| 29 | Equity | Distribution | false / NULL | **confirm** | Owner capital leaving the portfolio is not income. A taxable IRA withdrawal into a *tracked* account is a `Transfer / Cash`, not this row; the tax event is one V1 does not model (PRD §2.5.4 (π) says so for the mirror case). Open item O-3. | H |

**Cash-flow tally (29 rows):** 1 value change (#28) · 2 notes-only clarifications (#5, #6) · 26 pure confirms · **+1 proposed row add** (D-ii option C — a scope extension beyond confirm/correct; team-lead rules whether the seed delta may add a row; `091` is the precedent).

**R-1 (reader obligation, not a value):** with #28 going `false`, the only non-Revenue `tax_relevant = true` rows are STC/BTC. PRD §2.5.1 sources Ordinary Income from *"the Income side of §2.3.1"*. If SELF-262's Income reader filters on `tax_relevant` alone, **sale proceeds sum into Ordinary Income**; it must be class-scoped (`cat = 'Revenue'`). Vacuous under R1-A; stated so the day a sale exists it is not discovered on a tax table. Routes to SELF-262's AC via Architect.

---

## 2. Asset side — `pfin.taxonomy_default` (38 rows) — **NOT on V1.4's critical path (R1-A)**

The capital-gains half renders UNAVAILABLE under R1-A; these values reach no V1.4 surface. Decided here because it is the same act and the seed delta is cheap (R5). Rows change here in the seed delta; nothing consumes them until the sale writer lands.

**Marking principle (AC 1a iii), stated once:** *An asset Sub-Cat is `tax_relevant = true` iff a holding classified under it is disposed of through the §2.4.3 lot/sale machinery and that disposition is a taxable event whose gain or loss §2.5.1 must place in the ST CG / LT CG columns.* Corollaries: (1) rows that hold cash or cash-equivalents under an insurance regime, and rows that are balances rather than holdings (Liabilities), are `false` — there is no disposition; (2) rows whose disposition is a taxable event **outside** the lot machinery (Real Estate — §121 exclusion, depreciation recapture, no lots) are `false` **explicitly**, with the event named as unmodelled; (3) among `true` rows, `long_term_capital_gain_eligible` where a holding period > 1 year can yield LT treatment, `short_term_only` where the gain is taxed at ordinary rates regardless of holding period. Character is the eligibility declaration only (fact (a) above); the §1256 60/40 split is carried by the `Volatility-60/40` Sub-Cat's identity (PRD §2.5.1, ADR-004 D), not by the enum.

| # | Cat | Sub-Cat | now | PROPOSED | Reason | Conf |
|---|---|---|---|---|---|---|
| 1 | Cash | Cash Balances | false / NULL | **confirm** | Raw cash; no disposition. | H |
| 2 | Cash | FDIC | false / NULL | **confirm** | Insured deposit; interest flows via Revenue #2. | H |
| 3 | Cash | SPIC | false / NULL | **confirm** | Brokerage sweep cash; interest/MMF dividends flow via the Revenue side. | H |
| 4 | Cash | T-Bill | false / NULL | **CHANGE → true / short_term_only** (D-iv; open item O-1) | Bought at discount, matures at par: the lot machinery shows a realized gain that is legally *interest* (ordinary). ≤ 1-year paper cannot be LT. `short_term_only` routes it to Ordinary — correct Federally. `false` would make the gain vanish (understates). CA overstated (Treasury exemption unmodelled). | M |
| 5 | Cash | CD | false / NULL | **confirm** | Interest is paid as coupons (Revenue #3); a brokered CD sold early has an immaterial gain. Accepted simplification. | M |
| 6–9 | Bonds | IGL · IGI · HYI · INTL | false / NULL (×4) | **CHANGE ×4 → true / long_term_capital_gain_eligible** | Bonds and bond funds sold are capital dispositions; > 1 year yields LT. Market-discount-as-ordinary on individual bonds is unmodelled (V2). | H |
| 10 | Marketable Securities | UNKNOWN | false / NULL | **CHANGE → true / long_term_capital_gain_eligible** | Fail-closed: a sale under an as-yet-unclassified holding must not vanish from the CG table. | H |
| 11–20 | Marketable Securities | US-01-Basic_Materials … US-10-Utilities (10 GICS rows) | false / NULL (×10) | **CHANGE ×10 → true / long_term_capital_gain_eligible** | Equities: capital dispositions, LT after > 1 year. | H |
| 21 | Marketable Securities | US-Index-Non_Sector | false / NULL | **CHANGE → true / long_term_capital_gain_eligible** | As 11–20. | H |
| 22 | Marketable Securities | US-Growth-Non_Sector | false / NULL | **CHANGE → true / long_term_capital_gain_eligible** | As 11–20. | H |
| 23 | Marketable Securities | ExUS-Developed_Market | false / NULL | **CHANGE → true / long_term_capital_gain_eligible** | Foreign equities/ADRs/ETFs: capital; PFIC edge cases unmodelled. | H |
| 24 | Marketable Securities | ExUS-Emerging_Market | false / NULL | **CHANGE → true / long_term_capital_gain_eligible** | As 23. | H |
| 25 | Alternatives | REIT | false / NULL | **CHANGE → true / long_term_capital_gain_eligible** | REIT *shares* sold are capital. (REIT *dividends* are the non-qualified case D-ii covers.) | H |
| 26 | Alternatives | Crypto-Fx | false / NULL | **CHANGE → true / long_term_capital_gain_eligible** (open item O-4) | Crypto is property: capital, LT-eligible. The Fx half (§988 ordinary) is mixed into the same row; raw foreign cash already classifies per-currency to Cash Balances (`077`), so held-FX positions are the residual. | M |
| 27 | Alternatives | Commodities-Other | false / NULL | **CHANGE → true / long_term_capital_gain_eligible** (open item O-5) | Commodity ETFs/physical metals are capital dispositions. The collectibles 28% cap is a rate V1 has no schedule for — accepted simplification, understates for physical-metal holders. | M |
| 28 | Alternatives | Volatility-Hedges | false / NULL | **CHANGE → true / long_term_capital_gain_eligible** | Non-§1256 options on single names take normal holding-period treatment; straddle rules unmodelled. | M |
| 29 | Alternatives | Volatility-60/40 | false / NULL | **CHANGE → true / long_term_capital_gain_eligible** (D-iv) | §1256: 60% LT / 40% ST regardless of holding period, so the row is LT-eligible by construction; the split is by Sub-Cat identity (PRD §2.5.1). `short_term_only` would be false; NULL would make the sale vanish. | M |
| 30 | Liabilities | Credit-Balance | false / NULL | **confirm** | Balance, not a holding. | H |
| 31 | Liabilities | EstTax-Pending | false / NULL | **confirm** | Accrued liability; §2.5.3 owns the estimate. | H |
| 32 | Liabilities | Loan-Balance | false / NULL | **confirm** | Balance; debt-forgiveness income out of scope. | H |
| 33 | Liabilities | Liability Balances | false / NULL | **confirm** | As 30–32. | H |
| 34 | Real Estate | Residential | false / NULL | **confirm — explicit** (open item O-6) | A home sale is a taxable event (§121 exclusion) outside the lot machinery (`087` binds a value, not lots). Unmodelled, named. | H |
| 35 | Real Estate | Commercial | false / NULL | **confirm — explicit** (O-6) | Sale = capital + §1250 recapture; outside the lot machinery. | H |
| 36 | Real Estate | Remodel-Equity | false / NULL | **confirm — explicit** | Basis in progress, not a disposable holding. | H |
| 37 | Real Estate | Vehicle | false / NULL | **confirm — explicit** | Personal-use asset: losses non-deductible, gains rare. | H |
| 38 | Real Estate | Misc | false / NULL | **confirm — explicit** | As 37. | H |

**Asset tally (38 rows):** 25 changes (24 → `long_term_capital_gain_eligible`, 1 → `short_term_only`) · 13 confirms (4 Cash, 4 Liabilities, 5 Real Estate). The post-delta `true` set is non-empty — the QA leg PM §4 AC7 named.

---

## 3. The four decisions (AC 1a)

### D-i — `Equity / Contribution` per account type; the ADR-062 D4 rider

Basis: US treatment — a contribution of capital is never income; a **deductible** retirement contribution (Traditional IRA / pre-tax 401(k)) is an above-the-line AGI adjustment, and a Roth / after-tax contribution is not. Fact (b): deductibility depends on the receiving account's `tax_treatment`, which no prototype row can carry.

| Option | What | Tradeoff |
|---|---|---|
| **(A) `false` / NULL; rider REPLACED with a user-facing description** — **LEAN** | Contribution leaves §2.5.1 entirely. Notes → *"Owner capital contribution — value moved into the portfolio from the owner. Not income; retirement-contribution deductibility is per account and not modelled in V1."* | V1 overstates tax for a user making deductible Traditional contributions (no AGI line) — fail-closed direction, same as R11. Books a V2+ item (O-3). |
| (B) keep `true`, corrected rider | Row stays "flag-for-review". | There is no reviewer after this session; and if the Income reader is not class-scoped (R-1), a capital deposit sums as Ordinary Income — the one outcome worse than either error. |
| (C) `true` with negative-contribution (deduction) semantics | Models the deduction. | Needs a sign convention and a per-account filter the schema cannot express; a §2.5.2 line that does not exist. Out of proportion. |

**Rider consequence under (A):** the ADR-062 D4 string is removed from the default row; the backfill UPDATEs `posting_prototype.notes` **equality-guarded** on the exact rider string (no V1 notes edit path exists, so equality is safe; a user-edited value would be left alone). ADR-062's *"dormant surface mismatch"* consequence is discharged by removal rather than by re-phrasing — a one-line ADR-062 amendment is Architect's. `is_tax_payment` stays `false` (untouched).

### D-ii — Bond Premium = `ordinary`, Dividend = `qualified_dividend`

**Bond Premium → confirm `ordinary`.** Basis: §171 premium amortization and market-discount accretion adjust *interest* income — ordinary in both directions; never capital. Routing consequence: Ordinary → Federal ordinary + CA ordinary; had it been `qualified_dividend` it would have routed to Federal LT CG. **Notes-only correction** proposed: *"Bond premium amortization / market-discount accretion — ordinary-interest adjustment (1099-INT / OID)."* The current note names mark-to-market, which is the §1256 concept the asset-side `Volatility-60/40` row owns.

**Dividend — the value is defensible, the row is under-specified.** Basis: qualified dividends (US / qualified-foreign corporations, holding period met) are taxed at LT-CG rates; REIT, bond-fund and money-market-fund "dividends" are ordinary. One row cannot say both. Routing consequence is the largest on the table: `qualified_dividend` → Federal **LT CG** schedule; `ordinary` → Federal ordinary. Under R1-A, `Revenue / Dividend` is the **only** V1.4 input to §2.5.3's Federal LT-CG walk (SELF-264 AC 3a).

| Option | What | Tradeoff |
|---|---|---|
| (A) confirm as-is | All dividends route LT CG. | Fail-open: MMF / REIT / bond-fund dividends taxed at 0/15/20% instead of ordinary — understates Federal tax. LT-CG walk live. |
| (B) change to `ordinary` | All dividends route ordinary. | Fail-closed, but the LT-CG walk becomes **dead code in V1.4** — contradicts PRD §2.5.1's *"a V1 capability, not a deferral"* and SELF-264 AC 3a's premise. |
| **(C) confirm `Dividend` = `qualified_dividend` (notes: "qualified"); ADD `Revenue / Dividend - Ordinary` = `true / ordinary`** — **LEAN** | Both characters live; the user classifies non-qualified payers to the new row. Naming follows the seeded `Interest - …` pattern; no rename, so no `(cat, sub_cat)` collision. | A row add (scope extension; `091` precedent, same backfill shape). The generic `Dividend` bucket stays fail-open for an unsorted user. |
| (C′) as (C) but the generic bucket is the ordinary one: `Dividend` → `ordinary`, add `Dividend - Qualified` = `qualified_dividend` | Fail-closed default. | Every already-classified `Dividend` transaction re-routes ordinary until re-sorted — a reclassification burden on the founding user's history. Right choice only if the actual mix is MMF-heavy; **F/CTO knows the mix, PM does not** — the C/C′ choice is theirs. |

### D-iii — asset-side principle

Stated once at the head of §2 and applied row by row. Two non-obvious calls inside it: T-Bill is the one legitimate `short_term_only` (a discount gain that is interest, on paper that cannot be LT); Real Estate is `false` **explicitly** because its sale is a taxable event the lot machinery does not see — not because it is tax-free.

### D-iv — LT-eligible / ST-only assignments

`long_term_capital_gain_eligible` × 24 (Bonds 4 · Marketable Securities 15 · Alternatives 5); `short_term_only` × 1 (Cash / T-Bill). `Volatility-60/40` is LT-eligible with the split carried by Sub-Cat identity — alternatives weighed: NULL (sale vanishes; rejected) and a sixth `section_1256` code (a seed row on `011`, permitted by AC 7, but with no consumer on the tree; rejected for V1 — bookable). No seeded row is ST-only on the "always ordinary regardless of period" ground except T-Bill; `Crypto-Fx`'s §988 half is O-4.

---

## 4. Open items — values or rules NOT in the tree (named, not invented)

- **O-1 Treasury interest is CA-exempt** (coupons #3 cash side; T-Bill discount asset side). The five-value vocabulary has no *federal-taxable / state-exempt* character. V1 overstates CA; a sixth code is a seed row on `011` (AC 7 shape) **if** F/CTO wants it in V1.x — PM lean: V2+ (§5), it needs a jurisdiction-aware routing column ADR-024 deferred as g-2.
- **O-2 Salary gross-vs-net convention.** Whether a paycheck lands gross with withholding as `Transfer / Tax - …` rows, or net, is a data-entry convention, not a row value — but §2.5.3 YTD Paid reads the tax-authority **account ledger** (Gate B), so withholding counts only if it reaches that ledger. Product-docs item for SELF-266/267 copy; no value change.
- **O-3 Retirement-account tax events** (deductible contributions; taxable Traditional distributions) keyed on `account.tax_treatment` — V2+ §5 booking; PRD §2.5.4 (π) already names the distribution half as unmodelled.
- **O-4 `Crypto-Fx` mixes property (capital) with §988 currency (ordinary).** Splitting is a row add on the asset side (`077`/`080` shape) — not proposed while the CG half has no consumer (R1-A); bookable.
- **O-5 Collectibles 28% rate** (physical metals under `Commodities-Other`) — no V1 schedule; accepted simplification, understates for that holder.
- **O-6 Real-estate dispositions** (§121, §1250 recapture) — outside the lot machinery; V2+.
- **Not proposed, noted:** eight spelling errors in `041` asset-row notes (*Grate, Manufaaturing, Investemnt, Commoditiy, investent, assesed, withdrawls, Witholding*) — hygiene, separate from this inventory; the seed delta should not fold them in.
- **No rate, threshold or filing-status value is needed by any disposition above.** Rates live in SELF-260's seed, not on these rows.
