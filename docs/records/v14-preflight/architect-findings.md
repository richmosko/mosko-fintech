# V1.4 (§2.5 Estimated taxes) — Architect AC-vs-tree feasibility audit

**Baseline.** `origin/main` at `2cd94aebd034fbad43ef2401821a860679e72d6b` (detached read in the architect worktree). Migrations `001`–`099` on the tree. Every schema identifier below was grepped or read in-file at this sha; no count or identifier is carried from recall.

**Standing.** This pass is the [ADR-063](../../../DECISIONS.md#adr-063) Decision 1 discharge for the V1.4 milestone — the pre-flight recalibration pass run before the first build dispatch, not during it. It is also the second application of BACKLOG §7.19 AC 3 at a milestone-rotation boundary.

**§10 3-axis cross-check** — performed against [ADR-011](../../../DECISIONS.md#adr-011) Decision 4 read verbatim and live before drafting. This memo introduces no catalogued instance, reorders none, changes no layer-attribution, and restates the catalogued list nowhere (Path B — referenced, not copied). No ledger change; not a §10 Sec trigger. ⚠ The §10 CATALOGUED set and the CI-FENCED set (`grep -rhoE 'RT-[0-9]{2}' .github/workflows/`) are different sets and are **not** reconciled anywhere below; the CI set is strictly larger and that difference is deliberate.

**[ADR-011](../../../DECISIONS.md#adr-011) Decision 3** — read live at this sha. No tally appears below. **Seam A carries a live D3 determination**: the unbuilt `pfin.tax_bracket_row` carries an FK-shaped reference column crossing a tenant boundary, so it takes the next canonical label under Decision 3's standing discipline and owes matched-tenant validation in its DDL. No label is drafted here — D18's own amendment records what drafting a label in advance already cost this family once.

**Instrument note.** Function bodies were read from the migration files at this sha, not from a live catalog. Where a `create or replace` chain could have superseded a body, the superseding migration was searched for by symbol across the whole `supabase/migrations/` tree rather than by filename; the function inventory below was derived from `git grep -oE 'create or replace function pfin\.[a-z_0-9]+'` over the tree at `2cd94ae`, deduped.

---

## 1. Classification summary

| Issue | Surface | Verdict | Light-loop ([ADR-066](../../../DECISIONS.md#adr-066) D1) |
|---|---|---|---|
| SELF-263 | `tax_relevant` / `tax_character` migration + seed | **IMPOSSIBLE** — deliverable already shipped under other names; needs a re-scope ruling | no — (a) |
| SELF-264 | §2.5.1 decomposition table UI | **AMENDABLE** | no — (b) |
| SELF-265 | §2.5.2 tax-brackets settings editor | **AMENDABLE** — column names are proposals, ratified at SELF-259 | no — (b) + (c) |
| SELF-266 | §2.5.3 quarterly tables UI | **AMENDABLE** — one false-composite citation | no — (b) |
| SELF-267 | §2.5.3 YTD-Paid overlay backend | **DRIFT (severe) + needs-ruling** — signature, type, and period grammar all wrong | no — (a) |
| SELF-268 | §2.5.4 NAV composition flip | **IMPOSSIBLE as written** — AC 4 instructs the rejected one-way-door option | no — (b) |
| SELF-269 | §2.5.5 RLS battery (close-gate) | **AMENDABLE (severe)** — AC 8 names a table and a column that do not exist | no — (c) |
| SELF-302 | GL follow-up — `wash_sale` P&L | **BUILDABLE** — but it moves §2.5 numbers and does not say so | no — (a) + (b) + (c) |
| SELF-303 | GL follow-up — substantive `corp_action` | **BUILDABLE** — same | no — (a) + (b) + (c) |

**Zero of nine buildable as written.** The V1.3 pass measured zero of fourteen; this milestone was drafted in the same Wave-5 window against the same pre-GL substrate, and the result is the same in kind. ⚠ **And the figure understates the exposure**, because four blocking upstream issues (SELF-259/260/261/262) were outside the dumped set and are unmeasured — see the scope defect at the head of §4.

**Light-loop column:** the failing bullet is named — (a) no new DB surface · (b) no money-path change · (c) Sec-not-mandatory. None of the nine qualifies.

---

## 2. Seam inventory

Per [ADR-063](../../../DECISIONS.md#adr-063) Decision 2: a seam is a question no single issue owns because several answer it the same way. Each seam is stated **once** here; consuming issues **cite** it and do not restate it. The extraction discipline — not the inventory — is the load-bearing half.

---

### Seam A — The bracket-table storage grain, and the Decision-3 evaluation nobody has run

**The state at `2cd94ae`, measured not recalled.** `pfin.tax_bracket_schedule` and `pfin.tax_bracket_row` are **ratified names with zero DDL**.

- Evidence: `git grep -n -i -E 'tax_|bracket|estimated' 2cd94ae -- supabase/migrations/` returns no `create table` for either name; the only `bracket` hits are prose inside `011`'s seed `notes` strings.
- Corroborated by the canonical record rather than only by absence: [ADR-011](../../../DECISIONS.md#adr-011) Decision 18's amendment states verbatim — *"None of the five is built except `planning_target`"*.

**Two live precedent shapes exist and neither is the shape this surface needs.**

| Built surface | Migration | Grain | Key |
|---|---|---|---|
| `pfin.planning_target` | `074` | one row per (user, sub-cat) — a **vector** | `unique (users_id, sub_cat_id)` |
| `pfin.cashflow_target` | `090` | one **wide** row per user, two nullable scalars | `unique (users_id)` |

The bracket surface is neither: it is a **two-level parent/child** — a schedule (jurisdiction × kind × tax year) owning an ordered set of rows (rate, lower-bound threshold). That is what Lock 14's own enumeration already says by naming *two* tables, and it is the reason the two built precedents do not settle the question.

**What is locked and is NOT reopened by this seam.** From Decision 18, unamended: `tax_year SMALLINT` from V1 day-one; UPSERT-in-place with `updated_at` and **no edit-history rows** (settings are explicitly not audit-class); the **forward-compat fence — no JSONB blobs in the settings store under any future surface**; and Sec's nine mods, of which these attach directly here — strict typed-input validation + mass-assignment prevention, the numeric-input adversarial battery (NaN / Inf / currency-string regex / overflow / scientific-notation / locale-formatted reject), the **bracket-row monotonicity DB-trigger**, **schedule+rows replace-all under SERIALIZABLE**, and the `updated_at` refresh trigger via `pfin.fn_refresh_updated_at()`.

**⚠ ONE-WAY DOOR (sub-part): `tax_bracket_row`'s parent reference is a Decision-3 family evaluation, and the locked text points the wrong way.**

Decision 18's locked sentence reads *"**NOT a new instance of §8 cross-tenant FK-bypass family at V1** — settings writes are user-session-bounded…"*. That clause argues from the **write path**. Decision 3 membership turns on **column shape**. Decision 18's own amendment already names this exact reasoning error and records that it survived a rebuild unnoticed, costing the family instance #17 when `planning_target` was rebuilt with a `sub_cat_id`:

> *"the original claim was answering a different question from the one that decides it, which is why it survived the rebuild unnoticed."*

A `tax_bracket_row.schedule_id → pfin.tax_bracket_schedule` FK is FK-shaped, and `tax_bracket_schedule` carries a `users_id` tenant anchor, so the reference **crosses an isolation boundary**. Matched-tenant validation is owed in the DDL and is non-negotiable. **No canonical label is drafted here** — it is allocated at the migration, per Decision 3's standing discipline and D18's explicit instruction that *"none may be drafted in advance."*

⚠ The **tail** of that locked sentence is untouched by anything above and remains a live standing obligation: the V2+ live-tax-API ingestion trigger, the mandatory Sec re-consult at that adoption, and the Lock 12 mod #2-pattern fence becoming V1-SHIP-BLOCK then. Quoting the first clause alone is how that obligation would get retired as collateral damage.

**Options — the storage grain.** *(F/CTO ruling; one-way door on the sub-part above)*

- **Option A — two tables, as Lock 14 names them.** `tax_bracket_schedule (id, users_id, jurisdiction, schedule_kind, tax_year, standard_deduction, …)` + `tax_bracket_row (id, schedule_id, rate, lower_bound, …)`.
  - *Buys:* it is the ratified shape, so it costs no amendment. It carries `tax_year` naturally on the parent, which is where multi-year history wants it. Monotonicity is a per-schedule property and a trigger over the child set expresses it directly. Replace-all-under-SERIALIZABLE is a clean parent-scoped operation.
  - *Costs:* it is the first two-level surface in the settings store, and it adds a Decision-3 family member with its fence and its paired battery legs.
  - *Makes harder later:* nothing identified. Splitting or merging later would be a data migration either way.
- **Option B — one table, `tax_bracket_row` with the schedule identity denormalized onto every row** (`users_id, jurisdiction, schedule_kind, tax_year, rate, lower_bound`).
  - *Buys:* no cross-tenant FK at all, so **no Decision-3 family extension** — every row carries its own `users_id` and is fenced by the ordinary policy. Fewer objects; replace-all is a single `DELETE … WHERE (users_id, jurisdiction, schedule_kind, tax_year) = …` + insert.
  - *Costs:* the standard-deduction scalar has no home — it is per-(jurisdiction, tax_year), not per-row, so it needs either a third table or a home on `cashflow_target`-style wide row, which re-opens the family enumeration. Amends Lock 14's locked table list (5 → 4 or 5-with-a-different-member), which per D18's own generalizable rule *must amend the ADR holding the enumeration, not only the log*.
  - *Makes harder later:* per-schedule attributes (a V2 filing-status enum, a schedule effective-date) have nowhere to attach without a second migration.
- **Option C — two tables, with `tax_bracket_row` carrying its OWN `users_id` alongside `schedule_id`.**
  - *Buys:* the fence becomes the 012-shape local-anchor pattern (P1) rather than a lookup through the parent — the cheapest fence class in the family, and the one with the most precedent.
  - *Costs:* a denormalized tenant anchor that must be kept consistent with the parent's; that consistency is itself what the matched-tenant trigger asserts, so the redundancy is load-bearing rather than waste — but it is still a redundancy a future reader will want to remove.
  - *Makes harder later:* nothing identified.

**Architect's lean:** **Option C**, on the grounds that it is Option A's ratified shape with the cheapest and most-precedented fence class, and that the redundancy it introduces is exactly the thing the fence checks. But this is one input; the sub-part is a one-way door and the ruling is F/CTO's.

**Consuming issues:** the §2.5.2 settings-store issue · the §2.5.2 settings-UI issue · the §2.5.3 computation issue (walks the schedules) · the §2.5.4 unrealized issue (reads the two top-bracket rows) · the §2.5.3/§2.5.4 QA battery.

**Routing:** Sec joint-review **mandatory** before locking — Lock 14 surface, a Decision-3 family extension, and a financial-calculation input. QA — the battery extends in the same PR.

---

### Seam B — YTD-Paid: the period grammar, and which source is the truth

**Half one — the ratified S-3 grammar exists and does not fit.**

`pfin.fn_cashflow_items(p_as_of date)` (`093`) already emits `in_month, in_q1, in_q2, in_q3, in_q4, in_ytd`. Its `bounds` CTE defines those quarters as **calendar** quarters, read verbatim from the file at this sha: `q1_end = Mar 31`, `q2_start = Apr 1` / `q2_end = Jun 30`, `q3_start = Jul 1` / `q3_end = Sep 30`, `q4_start = Oct 1` / `q4_end = Dec 31`, all built with `extract(year from p_as_of)`.

⚠ **PRD §2.5.3's four Federal installments are due Apr 15 / Jun 15 / Sep 15 / *Jan 15 of the following year*.** A Q4 payment for tax year *Y* therefore carries a `transaction_date` in year *Y+1*. Against `fn_cashflow_items` it satisfies `in_q1` and `in_ytd` of **Y+1** and **no flag of Y at all**. A YTD-Paid overlay composing naively on those flags **silently under-counts Q4 in every year**, and the failure is invisible: the number is well-formed, merely wrong, and it is wrong in the direction that overstates Estimated Funds Due.

The grammar the overlay needs is a **payment-period grammar keyed to the tax year the payment is *for***, which is a different question from *when the money moved*. `fn_cashflow_items` does not carry it, and should not — the reader's six rules are §2.3's, and Decision 2's extraction discipline says a §2.5 rule appearing in that body **is** the drift defect the extraction exists to prevent.

**Half two — two candidate sources exist on the tree and PRD names only one.**

- **(i) PRD §2.5.3 verbatim:** *"the cumulative balance of these account ledgers feeds the YTD Paid column"* — the IRS and FTB accounts are standard §2.4.2 manual accounts. The built reader is `pfin.fn_account_cash_as_of(p_as_of date) -> (account_id, balance_native)` (`056`).
- **(ii) The `041` seed:** `('cashflow','Transfer','Tax - US Federal', …)` and `('cashflow','Transfer','Tax - California', …)` are seeded posting prototypes, and a payment transaction classified under one of them is directly summable.

These **double-count if both are live**: one payment is one transaction, and it both moves cash into the IRS account *and* carries a Tax-Transfer sub-cat. A ruling is owed on which is the source of truth.

⚠ **`is_tax_payment` is not the answer to either half, and the reason is structural.** `091` / [ADR-062](../../../DECISIONS.md#adr-062) Decision 2 scope the flag's meaning to **Expense-class** prototypes in its own `comment on column`, and the two real tax rows above are **Transfer**-class. The flag cannot reach them. Anyone reaching for it will find `false` on both rows and read that as an answered question.

**⚠ HALF TWO IS ALREADY RULED, AND THE OPTIONS BELOW ARE RETAINED AS THE RECORD OF WHAT WAS WEIGHED — NOT AS A LIVE CHOICE.** Added after the issue dump arrived; the seam was drafted before it. `CHANGELOG.md` line 1550 (Wave 5 / V1.4 / PR #92) records verbatim: ***"F/CTO Gate B Option A (`tax_jurisdiction` enum column)"***, and SELF-267's own issue text dates it 2026-06-03 and states the shape — `tax_jurisdiction pfin.tax_jurisdiction_enum NULL` on `pfin.account`, F/CTO marking the IRS and FTB accounts at creation. That ruling **presupposes the account-ledger route** (Option A below) and supplies the account-designation mechanism Option A was missing. **Do not re-open it at the sitting.**

⚠ Two consequences, and the second is the one that costs if missed:

1. **Sec's F-1 is answered.** Sec's findings at `origin/meta/v14-preflight-sec` @ `39bc549` route *"How does the system identify the IRS and the FTB account?"* to F/CTO as an open question with three options, stating *"Nothing in the schema marks an account as the IRS account."* The **schema** half of that is true at `2cd94ae` — nothing does. The **ruling** half is not open: Sec's option (C) is Gate B Option A under a different column name, and it is already F/CTO-ratified. Sec had the tree and not the dump. **Cite Gate B; do not re-litigate F-1's option set.** ⚠ This also retires F-1's D3 consequence: Sec's leaning option (A) — *"two nullable `account_id` references"* — would have been a Decision-3 family extension. Gate B Option A is an **enum column, not FK-shaped**, so it adds no family member. With that settled, **`tax_bracket_row`'s parent reference (Seam A) is the milestone's only Decision-3 candidate.**
2. **The ruling reached a downstream register and no ADR.** `tax_jurisdiction` changes the column set of `pfin.account` — a central table — and the ruling lives in `CHANGELOG.md` plus a Linear issue description. That is precisely the shape [ADR-011](../../../DECISIONS.md#adr-011) Decision 18's amendment generalizes: *"a Gate ratify that changes a LOCKED ENUMERATION must amend the ADR holding it, not only the log that records the Gate… A downstream register can carry a decision; it cannot carry an amendment to a lock."* No locked enumeration names `pfin.account`'s columns, so this is the weaker case rather than a violation — but the same failure mode is live: it was re-derived from scratch by Sec this cycle because it was not findable from `DECISIONS.md`. **Recommend an ADR fold-in in SELF-267's implementing PR**, which is where ADR-062 put its equivalent.

**Options — the YTD-Paid source (RULED; retained as the record of what was weighed).**

- **Option A — account-ledger balance (PRD-verbatim).** Sum `fn_account_cash_as_of` over the accounts the user designates IRS / FTB.
  - *Buys:* it is what the PRD says, and it needs no new period grammar at all — a ledger balance as-of a date *is* the cumulative-through-that-date figure. The Jan-15 problem dissolves entirely, because the balance does not care which flag a date satisfies.
  - *Costs:* it needs a way to know **which** accounts are the IRS and FTB accounts. `pfin.account` has `account_type` ∈ {depository, investment, retirement, crypto, manual_other, real_estate, liability} — no tax-authority member — so the designation is a new attribute or a settings pointer. PRD §2.5.3 says V1 does not auto-seed them.
  - *Makes harder later:* a balance carries no tax-year attribution, so multi-year history (a V2 item) would need the transaction grain anyway.
- **Option B — sum Transfer-class tax sub-cats.** Sum `account_trans` classified `Tax - US Federal` / `Tax - California`.
  - *Buys:* no new account attribute; the seed rows already exist; the transaction grain carries `transaction_date`, so tax-year attribution is available.
  - *Costs:* it needs the payment-period grammar from half one, including the Jan-15 rule. And it diverges from PRD §2.5.3's stated mechanism, so it is a PRD amendment, not just an implementation choice.
  - *Makes harder later:* nothing identified.
- **Option C — ledger balance as the figure, Transfer sub-cats as a reconciliation watcher.** Ship A; add a QA leg asserting the two agree.
  - *Buys:* the PRD-verbatim figure plus a watcher that catches the double-entry going out of sync.
  - *Costs:* two mechanisms to maintain, and the watcher will red on any legitimate divergence (a payment recorded one way and not the other), which is a support cost at V1 scale of one user.

**Architect's lean at drafting was Option A, and Gate B confirms it.** The Jan-15 defect in half one is real and Option A is the only route that never meets it — *provided the figure is taken as a ledger balance as-of a date.* ⚠ **SELF-267's AC 3 does not do that.** It specifies `fn_ytd_paid_per_jurisdiction(…, p_through_quarter INT)` which *"sums payments through end of `p_through_quarter`"* — the **transaction-grain, quarter-flagged** route, i.e. Option B — while the same issue quotes the PRD's *"cumulative balance of these account ledgers"* two paragraphs above. **The issue picks Option A's mechanism and Option B's arithmetic**, and Option B's arithmetic is the one that drops the Jan-15 Q4 payment. The re-derived AC in §4 corrects this to a balance-as-of read; it is the single highest-value correction in this pass. Sec's M-4 reaches the same boundary from the tax-year side (the year flips on Jan 1 while the Q4 obligation is still owed through Jan 15) — **two independent routes to the same date, and they need one answer, not two.**

**Consuming issues:** the §2.5.3 computation issue · the §2.5.3 table-render issue · the §2.5.4 Realized-Tax-Liability issue (which sums §2.5.3's two Estimated-Funds-Due gaps) · the QA battery.

**Routing:** Sec joint-review **mandatory** — a money figure the user reads and acts on.

---

### Seam C — Which clock, and which as-of form

**One answer, three issues.** Every §2.5 surface is *"current calendar year"*-scoped (§2.5.1 θ-1, §2.5.2, §2.5.3, §2.5.4 all mirror it).

- **The tax year is derived in the DATABASE.** `pfin.fn_server_today()` (`070`) is the ratified R2 shape from [ADR-044](../../../DECISIONS.md#adr-044) Decision 2. ADR-044's recorded hazard is precisely this: the app produced a date in Node (`new Date().toISOString().slice(0,10)`, unconditionally UTC) while Postgres compared it in the session TimeZone — *"two clocks in two processes"* — and they agreed only because the dev stack happened to be UTC. Decision 18 independently locks the V1 read pattern as `EXTRACT(YEAR FROM CURRENT_DATE)` for §2.5.3 in-app. **No §2.5 surface derives its tax year in Node.**
- ⚠ **The `061` TimeZone pin does not relieve this.** ADR-044 Decision 1 states the pin is *necessary and not sufficient* — three conjuncts, only the first enforced in DDL; `PGTZ` at `source = client` and a role-level override at `source = user` both outrank `source = database`, and *"a half-pinned deployment INSPECTS CLEAN."*
- **The as-of filter form is `093`'s, not [ADR-011](../../../DECISIONS.md#adr-011) Decision 19's prose.** Any new §2.5 reader over `pfin.account_trans` owes the Lock 15 dual-column as-of. `093`'s rule 6 states the correct half-open form and says why: `transaction_date <= $1 AND created_at < ($1 + 1)`. ⚠ A `created_at <= $1` form promotes the date to midnight in the session TimeZone and **excludes every row created ON the as-of date**. Copy `093`; do not copy the filter out of the Decision-19 prose.

**Not an options question** — this is a determination from the record, offered so three issues do not each re-derive it differently. No F/CTO ruling sought.

**Consuming issues:** every §2.5 issue that reads a date.

---

### Seam D — Where `tax_character` actually lives now, and why §2.5.1's join is across two id spaces

**Two live homes, both correct, for different domains.** Post-[ADR-058](../../../DECISIONS.md#adr-058) split:

| Column pair | Table | Migration | Domain it serves |
|---|---|---|---|
| `tax_relevant`, `tax_character` | `pfin.user_taxonomy` | `009`, FK'd at `011` | the **storage-classification spine** (asset side, §2.2.1) |
| `tax_relevant`, `tax_character` | `pfin.posting_prototype` + `pfin.posting_prototype_default` | `084` | the **posting vocabulary** (cash-flow side, §2.3.1) |

Both reference `pfin.tax_character (code)` `on delete restrict` — the global shared-read value registry at `011`, whose five seeded codes are the ζ-2 enum verbatim (`ordinary`, `qualified_dividend`, `tax_exempt_interest`, `long_term_capital_gain_eligible`, `short_term_only`).

**Consequence for §2.5.1, which is the whole reason this is a seam.** PRD §2.5.1 says *"Two input sources, one decomposition surface, joined by Sub-Cat."* Those two sources sit in **two different taxonomies**: Ordinary-Income contributions carry a `posting_prototype` id; capital-gain contributions are surfaced *"under the Sub-Cat the underlying holding carries per §2.2.1"* — a `user_taxonomy` id.

⚠ The two id spaces are **disjoint by construction, and the disjointness is deliberate**: `posting_prototype.id` is `generated always as identity (start with 1000000000 minvalue 1000000000 no cycle)` (`084`) while `user_taxonomy.id` starts at 1. That is what makes a UNION safe. It is also exactly what makes a naive **join** on id silently return nothing — a fail-closed direction, but a silent one. §2.5.1 composes a **UNION of two id spaces discriminated by domain**, never a join.

**A decomposition table is not needed.** The enum already routes, and the routing table is PRD §2.5.2's, ratified as hardcoded per PRD flag (g-1) and recorded as such in `011`'s own header. Adding a sixth `tax_character` value is a seed migration on `011`, not a CHECK edit — the `009` inline CHECK was dropped and replaced by the FK at `011`.

**Not an options question** — a determination, stated once. ⚠ It does interact with **§7.28 item 3** (below): the *values* on those rows are unaudited even though the *columns* are correct.

**Consuming issues:** the §2.5.1 decomposition issue · the §2.5.3 computation issue (routing) · the §2.5.1 render issue.

---

### Seam E — The NAV composition flip is a FOUR-part change, and one part is a one-way door

**⚠ ONE-WAY DOOR. Flagged first, before the options.**

**What is already shipped.** `realized_tax_liab` and `unrealized_tax_liab` are **not absent** — they are present as **hardcoded zeros at three layers**, which is why an AC whose identifiers all resolve can still be wrong about the work:

1. **`051` `pfin.fn_nav_composition(date)`** emits them literally, read verbatim at this sha:
   `'realized_tax_liab', 0::numeric, -- Option A V1.1 (AC#5); V1.4 ramp` and the same for unrealized. ⚠ **The `nav` key in the same object is computed as `(total_non_re + real_estate) - (-liability_signed) - 0::numeric - 0::numeric`** — so the zeros are inside the NAV arithmetic, not merely displayed beside it.
2. **`api/src/lib/nav-composition.ts`** flags both rows `isTaxPlaceholder: true`.
3. **`api/src/lib/components/NavCompositionTable.svelte`** renders `{row.isTaxPlaceholder ? usd.format(0) : usd.format(row.displayValue)}` — it **ignores `displayValue` entirely** for those two rows. ⚠ This is the silent one: supply correct values at the DB layer and fix nothing else, and the surface renders `$0` against correct data with no error anywhere.

**The fourth part, and the one-way door.** `051`'s own comment states the identity it currently satisfies: `nav = gross_total − debt − 0 − 0 = … = fn_compute_nav(p_as_of, true)`. `pfin.fn_compute_nav` (`050`) has **no tax leg** — verified: `git show 2cd94ae:supabase/migrations/050_*.sql | grep -i tax` returns nothing. So the moment §2.1.5's NAV subtracts real tax liabilities, **§2.1.5's NAV and `fn_compute_nav`'s NAV diverge**, and `fn_compute_nav` is what the cron writes into `pfin.nav_daily`.

`pfin.nav_daily` (`054`) is **append-only audit-class**, carries `nav_value numeric not null`, and has **no definition-version discriminator column**. Once the checkpointed definition changes, the historical series is a mixture of two definitions with nothing in the row to tell them apart, and the mixture is **not reversible without a data migration** — the prior values cannot be recomputed, because the tax state they would need is itself derived from a book that has since moved.

**Options.** *(F/CTO ruling — one-way door; decide slowly)*

- **Option A — the flip lands on §2.1.5 only; `fn_compute_nav` and `nav_daily` keep the pre-tax definition, permanently, and are renamed in their comments to say so ("gross NAV").**
  - *Buys:* the trajectory series stays a single consistent definition forever. No migration of history, no discriminator column, no mixture. The §2.1.5 table becomes the only surface carrying the four-component NAV — which is what PRD §2.1.1 and §2.1.5 actually commit to.
  - *Costs:* two numbers both called NAV, differing by the tax lines, on adjacent surfaces. That is a real user-facing inconsistency and it needs copy to survive it.
  - *Makes harder later:* if V2 wants a tax-adjusted trajectory, it needs a second checkpoint column or a second table — additive, not a migration.
- **Option B — the flip lands everywhere; `nav_daily` gains a `nav_definition` discriminator and the cron writes the new definition going forward.**
  - *Buys:* one NAV everywhere. The discriminator makes the mixture legible rather than silent, and it is additive.
  - *Costs:* a column on an append-only audit-class table, which is an [ADR-011](../../../DECISIONS.md#adr-011) Decision 2 surface and a Sec gate. Every trajectory reader (`062` `fn_nav_series`, `067` inflation-adjusted, `071` delta panel, `073` reference dates) must filter or branch on it — a wide blast radius. And the trajectory visibly steps down on the changeover day, which is a chart artifact the user will ask about.
  - *Makes harder later:* every future NAV-definition change now has a precedent for adding a discriminator value rather than for not changing the definition.
- **Option C — the flip lands everywhere and `nav_daily` history is backfilled to the new definition.**
  - *Buys:* one definition, one continuous series, no artifact.
  - *Costs:* **rejected on the record, not on preference** — `nav_daily` is append-only audit-class; a backfill is a rewrite of an audit surface. And the tax state for a past date is not recoverable, so the backfilled values would be a fabrication with the shape of a measurement.

**Architect's lean:** **Option A**, on the grounds that it is the only one that never mixes definitions in an append-only table, and that PRD §2.1.1/§2.1.5 already scope the four-component NAV to the composition buildup rather than to the trajectory. The user-facing two-numbers cost is real and is copy work, not schema work. One input; F/CTO decides.

⚠ **Regardless of option, the flip is not light-loop eligible** — ADR-066 Decision 1 (b): *"A rendering-only change to a money figure still counts as a money-path change."* All four parts are money-path.

⚠ **Volatility, measured rather than assumed.** `051` and `049` are both declared `language sql` with **no volatility keyword**, so both default to `VOLATILE` — unlike `093`'s `fn_cashflow_items`, which is explicitly `stable`. Two consequences for the flip: a replacing body that *adds* `stable` is a planner-contract change that no value assertion can see; and if any `ALTER FUNCTION … STABLE` pin is ever applied out of band, a later `create or replace` **silently erases it**. State the intended volatility explicitly in the replacing migration, per signature, and note that a `stable` caller of a `volatile` callee is an unbacked promise.

**Consuming issues:** the §2.5.4 NAV-component issue · the §2.5.3 issue (Realized is a sum of its two gaps) · any issue touching 211/225/226 as-shipped · the QA battery.

**Routing:** Sec joint-review **mandatory** · F/CTO — one-way door · QA — the battery extends · Frontend — part 3 is theirs and it is the silent one.

---

### Seam F — The (π) tax-advantaged exclusion has no implementation, and adding it to `049` is a signature change

`pfin.fn_account_unrealized_gl(p_as_of date)` (`049`) returns `(account_id, current_market_value, cost_basis, unrealized_gl)` and carries **no `tax_treatment` filter** — verified: `git show 2cd94ae:supabase/migrations/049_*.sql | grep -i 'tax_treatment\|taxable'` returns nothing.

PRD §2.5.4's (π) lock requires the Unrealized aggregation to exclude `tax_deferred` and `tax_free` holdings. The filter itself is clean and total: `pfin.account.tax_treatment` is `text not null check (tax_treatment in ('taxable','tax_deferred','tax_free'))` at `003`, so `tax_treatment = 'taxable'` is exhaustive with no NULL case and no default to fail open through.

**Options — where the filter lives.**

- **Option A — a new parameter on `049`** (`p_tax_treatment text[]` or `p_taxable_only boolean`).
  - *Buys:* the filter sits with the aggregation it constrains; one place to get it right.
  - *Costs:* ⚠ **a signature change**. `049` returns rows consumed by `051`, and other files' pgTAP legs assert against its `regprocedure`. A `DROP`+`CREATE` breaks those legs in files the migration is not named after. A defaulted parameter avoids the drop but creates an overload, and an overload is its own hazard: a caller that omits the argument silently gets the unfiltered aggregate.
  - *Makes harder later:* the overload, if taken, is permanent.
- **Option B — the §2.5.4 composer filters**, joining `049`'s output to `pfin.account` and applying `tax_treatment = 'taxable'` itself.
  - *Buys:* `049`'s signature is untouched, so no catalog assertions move. §2.5.4's exclusion is stated where §2.5.4's other rules are.
  - *Costs:* if a second consumer ever wants the taxable-only aggregate, the filter gets copied — which is the four-hand-copies drift risk this project has already booked once. Mitigated by extracting it as its own helper the first time a second consumer appears, not now.
  - *Makes harder later:* nothing, provided the "extract on second consumer" rule is written into the issue.
- **Option C — a sibling function** `fn_account_unrealized_gl_taxable(p_as_of date)` composing on `049`.
  - *Buys:* no signature change, no copied predicate, and the name states the scope.
  - *Costs:* a second function whose only difference is one predicate; a reader must check which one a given surface calls.

**Architect's lean:** **Option B**, with the extract-on-second-consumer rule written into the AC. `049`'s signature is load-bearing across files and a one-predicate filter does not earn a signature change.

**Consuming issues:** the §2.5.4 Unrealized issue · the §2.5.4 NAV-component issue (Seam E) · the QA battery.

---

### Seam G — Holding period, wash sale, and §1256: one is buildable, one is schema-impossible as written

Stated once because §2.5.1 and §2.5.3 both consume all three, and ARCH §9 leaves (d) open as *"materialized column vs computed view."*

- **Holding period — buildable, no new column needed.** `pfin.lot_match` (`032`) carries `sell_trans_id`, `buy_trans_id`, `quantity_matched`, `match_seq` and **no holding-period column**. The period is `sell.transaction_date − buy.transaction_date`, obtained by joining `pfin.account_trans` twice. PRD's rule is *"> 365 days → LT, otherwise ST."* **Computed, not materialized** — a materialized column would need a fence to stay true, and this is a by-construction property of two dates already on the tree (the watcher-not-fence discipline). ⚠ `lot_match` carries **no `users_id`**; its tenancy is inherited through two `account_trans` FKs, which is an RLS-composition fact any §2.5.1 reader must honor rather than assume.
- **§1256 60/40 — buildable, the seed row exists.** `041` seeds `('asset','Alternatives','Volatility-60/40', …, 'IRS Section 1256 contract on Index/ForEx/Commodity')`. The mechanism is PRD's user-classification-at-the-Sub-Cat-level, and it is present. ⚠ **Identifier drift in the PRD, not in the tree:** §2.5.1's worked example writes *"US-Index_Non_Sector"* while `041` seeds `US-Index-Non_Sector` (hyphen, not underscore, after `Index`), and §2.5.1 names the parent Cat *"Marketable Securities"*, which is correct **only post-`082`** — `041` seeds it as `Equity` and `082` renames it. An AC copying the PRD's spelling will not match a row.
- ⚠ **Wash sale — SCHEMA-IMPOSSIBLE AS WRITTEN, and the search was widened before concluding so.** PRD §2.5.1 requires a *"user-marked wash-sale flag **on the underlying sale transaction**"* whose disallowed-loss amount is excluded from the ST/LT column. There is **no such flag**. `git grep -n -i 'wash_sale\|wash-sale' 2cd94ae -- supabase/migrations/ api/src` returns hits only as a **`basis_adjust` metadata `reason`** value — a member of `{depreciation, return_of_capital, wash_sale}` on a *separate transaction type* (`030`, `034`), and `035`'s P7 routes it to **Suspense** with the comment *"P&L deferral not yet specified."* Per ADR-063 Decision 1's widen-the-search rule, this is the widened result and it is **not** the AC's mechanism under a different name: it is a different transaction, at a different grain, whose P&L treatment is explicitly unspecified. This is a PRD-vs-tree conflict, and it routes to PM and F/CTO — it is a product question about which mechanism V1 ships, not an implementation detail.

**Consuming issues:** the §2.5.1 decomposition issue · the §2.5.3 computation issue · the §2.5.1 QA legs.

**Routing:** PM + F/CTO on the wash-sale conflict · Sec joint-review on the §2.5.1 reader (financial calculation + multi-tenant read composition).

---

### Seam H — §7.28 item 3 gates §2.5.1, and the gate is a sequencing commitment with no mechanism

BACKLOG §7.28 item 3 (*"V1.4 tax-value inventory session (F/CTO)"*) states its AC: *"The session happens before §2.5.1 implementation ships: every `posting_prototype_default` row's `tax_relevant`/`tax_character` confirmed or corrected against the V1.4 tax model; the Contribution flag resolved per account type."*

**Why it is a seam rather than one issue's dependency.** Seam D establishes that the *columns* are correct and correctly FK'd. This item is about the *values* on them, and those values decide what §2.5.1 renders, what §2.5.3 computes, and what §2.5.4's Realized line sums. Three issues consume the same unaudited data.

⚠ **The gate is a sequencing commitment, not a mechanism** — nothing in the schema prevents §2.5.1 being built and shipped against unaudited values, and the result would be a well-formed decomposition that is quietly wrong. This is the same shape [ADR-062](../../../DECISIONS.md#adr-062) Decision 3 records for `is_tax_payment`'s marking precondition, and it fails the same way. It must live in the **consuming issue's acceptance criteria**, not only in the backlog entry.

The two rows most likely to move: `Equity / Contribution` enters `tax_relevant = true` as **flag-for-review** with ADR-062's notes rider (*"potentially deductible; resolve per account type at the V1.4 tax inventory"*), and the `041` cash-flow seed marks seven Revenue rows `tax_relevant = true` with characters assigned — `Bond Premium` as `ordinary` and `Dividend` as `qualified_dividend` are the two whose §2.5.2 routing consequences are largest.

**Routing:** F/CTO — the session itself · PM — the inventory's scope.

---

### Seam I — SELF-302 and SELF-303 both change §2.5 numbers, and both are silently wrong in a known direction until they land

The brief asked whether 302/303 move any §2.5 figure. **Both do, by different routes, and neither issue's text says so.**

- **SELF-302 — `basis_adjust` `wash_sale` P&L.** `035`'s P7 routes a `wash_sale`-reason `basis_adjust` contra to **Suspense**, with the comment *"P&L deferral not yet specified"*. Until 302 lands, a disallowed wash-sale loss is parked rather than added to the replacement lot's basis. That understates `cost_basis`, which **overstates** `unrealized_gl` at `049`, which **overstates** §2.5.4 Unrealized Tax Liability — and it leaves the disallowed loss unrecognized on the §2.5.1 ST/LT columns, which **understates** taxable gain. Two errors in opposite directions on two different surfaces.
- **SELF-303 — substantive `corp_action` GL.** Spin-off basis allocation and cash-in-lieu are likewise Suspense-parked at `035`/`037`. Basis allocation moves `cost_basis` → `049` → §2.5.4 Unrealized; cash-in-lieu is a realized disposition → §2.5.1's CG columns.

⚠ **The consequence for sequencing, which is why this is a seam and not two issue notes:** SELF-262's `fn_compute_tax_liability` computes over whatever the book says. If it lands while both are parked, it produces well-formed figures that are wrong by a known, un-annotated amount, and nothing on any surface says so. Two dispositions are available and the choice is F/CTO's:

- **Land 302 + 303 before SELF-262**, so the helper computes over a settled book. Costs: two money-path migrations with their own mini-designs on the critical path.
- **Land SELF-262 first and carry an explicit named residual** — recorded in the migration header and in the issue AC, in the shape `093` uses for its own named residual (*"Recorded so a reader does not conclude the case is handled"*). Costs: correct-looking wrong numbers for the interval, mitigated only by a note nobody reads at the moment they matter.

⚠ **A third option must be named to be rejected:** shipping SELF-262 with no residual recorded. That is the state the milestone is in **by default** if this seam is not ruled, and it is the one where the defect is invisible.

**Consuming issues:** SELF-302 · SELF-303 · SELF-262 (out-of-milestone) · the §2.5.1 and §2.5.4 issues.

**Routing:** F/CTO — sequencing · Sec joint-review — both are money-flow migrations and both issues already say so.

---

## 3. Cross-cutting determinations

- **[ADR-011](../../../DECISIONS.md#adr-011) Decision 3.** One new family member is in scope across the milestone (Seam A). No label is drafted here. Every FK-shaped column in any V1.4 migration — including any `INTEGER[]` — carries matched-tenant validation in its DDL, non-negotiable.
- **SECURITY DEFINER.** No §2.5 surface identified in this pass requires one. Lock 11 SECURITY INVOKER read-composition is the default and every function read at this sha in the §2.5-adjacent path (`049` `051` `056` `093`) is `security invoker` + `set search_path = ''`. Any DEFINER proposal routes to Sec joint-review; read the allowlist ([ADR-011](../../../DECISIONS.md#adr-011) Decision 9) live.
- **aal2 step-up backstop.** Any new sensitive tenant-owned `pfin` table (Seam A's two) owes the `025` backstop clause on its `authenticated` policies unless a documented `025` exclusion applies. ⚠ `pfin.user_settings` is named in `025` as a **non-negotiable exclusion** (policy recursion) — that exclusion does not generalize to siblings, and the bracket tables are not covered by it.
- **QA pairing.** Every migration extending RLS surface ships its two-tenant pgTAP battery in the same PR. Batteries live at `supabase/tests/rls/NNN_*.sql`. ⚠ Verify with `pg_prove`, never bare `psql` — `psql` exits 0 on a failed plan.
- **Ledgers flat.** No §10 count and no D3 tally appears in this memo. Citations are by name.

---

## 4. Per-issue findings

**Source.** `temp/v14-preflight/issue-dump.md`, md5 `9d128f6d8d78c9a24620116da5912d69`, verified in-turn. Nine issues: SELF-263/264/265/266/267/268/269/302/303.

**⚠ Scope defect in the pass itself, stated first because it bounds every verdict below.** Four of this milestone's load-bearing upstream issues — **SELF-259** (`tax_bracket_schedule` / `tax_bracket_row` migration + SERIALIZABLE replace-all), **SELF-260** (bracket + standard-deduction seed), **SELF-261** (the wash-sale annotation table), **SELF-262** (`fn_compute_tax_liability`, the unified SECURITY INVOKER helper) — **are not in the dumped set and were not audited here.** They are not missing: `CHANGELOG.md` line 1550 records Wave 5 as *"11 issues SELF-259→SELF-269 across 2 milestones (Platform V1.x = 4 Architect; Estimated taxes V1.4 = 7 PM §2.5)"*, so those four sit in **Platform / Cross-cutting V1.x**, not V1.4.

That placement is defensible; the consequence is not. **They were drafted at the same Wave 5 moment, against the same pre-GL premises, as the seven that this pass has now measured as almost entirely undeliverable as written** — and they carry the milestone's entire schema surface plus the helper that five of the seven call in their first AC. **Six of the nine issues below have an unaudited blocking dependency.** SELF-259 is where Seam A's ruling lands and where the Decision-3 label is allocated; SELF-262 is where Seams B, C, F and I all converge. **Recommend: extend this pass to those four before the sitting closes, or dispatch nothing that depends on them.**

**Ledger discrepancies, two, in opposite directions.** (i) `MILESTONES.md` line 44 enumerates eight V1.4 issues and omits SELF-264 while the dump lists nine and includes it — **Sec's F-7 names this and I confirm it rather than restate it**; `BACKLOG.md` line 348 names SELF-264 as a real surface. (ii) The same line's "8 issues in Linear" excludes SELF-259–262 entirely, which is correct as a milestone statement and misleading as a dependency statement. Both need one reconciliation against live Linear, not two.

**Light-loop eligibility ([ADR-066](../../../DECISIONS.md#adr-066) Decision 1) — evaluated per issue, conjunction, no discretion. Result: ZERO of nine qualify.** Recorded as a measurement because it is the answer to a question the dispatch brief asks per-issue, and a per-issue table of nine identical "no"s would obscure that the result is uniform. The failing bullet differs: (a) *no new DB surface* fails for 263 / 267 / 302 / 303; (b) *no money-path change* fails for 264 / 266 / 268 — and for the two settings issues, since a bracket rate is an input to every money figure on the milestone; (c) *Sec-not-mandatory* independently fails for 265 / 269 / 302 / 303, which carry `sec-joint-review` labels. ⚠ **SELF-269 is the one worth stating explicitly**, because a test-only battery looks light: it adds no DB surface and computes no money, but (c) is decisive and it is the V1-SHIP-BLOCK close-gate.

---

### SELF-263 — §2.5.1.a tax-relevant attribute migration + bootstrap seed · **IMPOSSIBLE (deliverable already shipped; needs a re-scope ruling)**

**This is [ADR-063](../../../DECISIONS.md#adr-063) Decision 1's widen-the-search case, and it is the second consecutive cycle to produce one.** Every schema identifier in the AC is falsified, and the reason is that the work landed under other names.

| AC | Identifier as written | State at `2cd94ae` | Evidence |
|---|---|---|---|
| 1 | `pfin.tax_character_enum` — *"PostgreSQL enum created with 5 V1 values"* | **ABSENT, and deliberately so** | `011` shipped `pfin.tax_character` as a **global shared-read value-registry TABLE** with a natural-key PK, seeded with exactly those 5 codes, chosen as *"Option C hybrid"* over an enum. `git grep -n 'tax_character_enum' 2cd94ae` → no hits. |
| 2 | `tax_relevant BOOLEAN NOT NULL DEFAULT FALSE` + `tax_character` on `pfin.user_taxonomy` | **ALREADY PRESENT** | `009` lines 157–160 ship both; `011` converts the inline CHECK to `fk_user_taxonomy_tax_character` referencing `pfin.tax_character(code) on delete restrict`. |
| 3 | F/CTO bootstrap seed values | **PARTIALLY SHIPPED, UNAUDITED** | `041` seeds them — 7 cash-flow Revenue rows carry `tax_relevant = true` with characters assigned (`Dividend` → `qualified_dividend`, `Interest - Tax Free` → `tax_exempt_interest`, five → `ordinary`). Whether those values are *right* is BACKLOG §7.28 item 3, undischarged. |
| 4 | *"`Volatility-60/40` rows already shipped at SELF-231"* | **TRUE, with a caveat the AC does not carry** | `041` seeds `('asset','Alternatives','Volatility-60/40', …)`. But `082` renamed asset Cat `Equity` → `Marketable Securities` after that seed, so any AC or fixture spelling the parent Cat from the `041` text will not match. |
| 5 | *"Cashflow-side Sub-Cats (SELF-245 substrate)"* on `user_taxonomy` | **WRONG TABLE** | [ADR-058](../../../DECISIONS.md#adr-058)'s split moved the cash-flow posting vocabulary to `pfin.posting_prototype` / `posting_prototype_default` at `084`, and dropped `domain` from `user_taxonomy`. `user_taxonomy` holds no cash-flow rows to mark. See Seam D. |
| 6 | disjointness from `is_tax_payment` | **CORRECT, and shipped** | `091` / [ADR-062](../../../DECISIONS.md#adr-062). The AC's semantic distinction (outflow-marker vs character-input) is right. |
| 7 | read-only via migration in V1 | **CORRECT and already enforced** | `009`'s V1-WRITE-DORMANT posture: `authenticated` holds SELECT only; write policies and grants deferred to the V2 taxonomy-CRUD PR. |

**What is actually left.** Nothing schema-side. The residual is **entirely the BACKLOG §7.28 item 3 value inventory** (Seam H): confirming or correcting every `posting_prototype_default` row's `tax_relevant` / `tax_character` against the V1.4 tax model, and resolving `Equity / Contribution`'s flag-for-review per account type.

**Ruling needed (F/CTO, re-scope).**
- **Option A — re-scope SELF-263 to the inventory session and its outcome-recording migration.** The issue keeps its slot as the milestone's first item and becomes the §7.28 item 3 owner Sec's F-6(b) says it currently lacks. *Buys:* one issue, one owner, and the gate lands in an AC rather than in a backlog entry — which is what [ADR-062](../../../DECISIONS.md#adr-062) Decision 3 says a sequencing gate needs to be. *Costs:* the issue's title and every inbound reference now describe something else.
- **Option B — close SELF-263 as discharged and open a new issue for the inventory.** *Buys:* honest history; the closed issue records what actually happened. *Costs:* the §7.28 item 3 booking is homeless for as long as the new issue takes to exist, which is the state Sec flagged.
- **Option C — keep the AC and build it.** *Rejected on the tree:* AC 1 would create a second, competing `tax_character` vocabulary beside `011`'s registry, and AC 2's columns already exist. This option is named so the sitting can see it was weighed, not missed.

**Architect's lean:** **Option A.** ⚠ Whichever is chosen, Sec's **M-6** (ADR-062 Decision 3's hard precondition undischarged) and **F-6(b)** (the session has no owner and no slot) are the same obligation as §7.28 item 3 seen from the Sec side — **one ruling, not three.**

**Routing:** F/CTO (re-scope) · PM (inventory scope) · Sec joint-review at the implementing PR if any DDL results.

---

### SELF-264 — §2.5.1.c decomposition table UI · **AMENDABLE**, blocked on an unaudited dependency

- **AC 1** invokes `fn_compute_tax_liability()` (SELF-262). **Absent at `2cd94ae`** — not in the function inventory. Not a defect in this AC; a dependency on an unaudited issue.
- **AC 3** — *"Capital Gains section (asset-side realized G/L decomposed by holding period)"* is buildable per Seam G: `lot_match` (`032`) joined twice to `account_trans` yields the period; no new column. ⚠ **Sec's M-1 governs what an *unmatched* sell does** — it has no holding period and therefore no column to land in. Cite M-1 and Sec's F-2 option set; do not re-derive.
- **AC 5** — *"`tax_character` enum visually communicated per row"* is buildable and its vocabulary is the `011` registry's 5 codes, FK-enforced. The word *enum* is loose (it is a registry table) but harmless in a UI AC.
- **AC 7** — *"`tax_relevant = FALSE` Sub-Cats excluded entirely."* ⚠ Correct per PRD, and **Sec's M-5 is the reason this AC is load-bearing rather than cosmetic**: `tax_relevant` carries a fail-**open** `DEFAULT false`, so an unmarked row is excluded silently and reads identically to a deliberately-excluded one. The AC as written cannot distinguish them.
- **AC 8** empty-state — *"CTA to migration-time docs"* is not a route that exists. Minor; re-worded below.

**Verdict:** amendable. The corrections are the helper's real signature, the M-1 disposition cited not restated, and the empty-state copy.

---

### SELF-265 — §2.5.2.a tax-brackets settings editor · **AMENDABLE**, and it is the consumer of Seam A

- **AC 1** — *"lists 3 schedules (Federal ordinary + Federal LT CG + CA FTB ordinary)"*. **Correct** against PRD §2.5.2's (λ) two-Federal-schedules lock and (κ) single-CA lock.
- **AC 2** — `bracket_floor` + `bracket_rate`. **These are proposals, not facts**: neither column exists, because `tax_bracket_row` does not exist (Seam A). They are reasonable names and PRD's *"lower-bound threshold"* matches `bracket_floor`. They must be **ratified at SELF-259's DDL**, not inherited from a UI AC — a settings editor is the wrong place for a column name to originate.
- **AC 3** — replace-all SERIALIZABLE, endpoint `/api/settings/tax-brackets/{schedule_id}`. **Correct** and it is Decision 18's Sec mod verbatim. ⚠ The `{schedule_id}` path parameter is an **object reference from the client** and therefore a mass-assignment / IDOR surface; Decision 18's *"mass-assignment prevention; `users_id` from `auth.uid()` not `req.body`"* mod applies to it. Sec's §3 covers the replace-all write path's isolation traps — cite it.
- **AC 4 / AC 5** — the Lock 14 V1-SHIP-BLOCK mods and the monotonicity trigger. **Correct and locked.** ⚠ Sec's **M-7** (no lower floor, no upper bound, no unit on bracket-boundary arithmetic) and **M-10** (`NaN` is storable and a one-sided `>= 0` CHECK **admits** it) are constraints on **SELF-259's DDL**, not on this editor — the editor's client-side validation is the second layer, never the first. The `090` `cashflow_target` CHECKs (`… >= 0 and … <> 'NaN'::numeric`) are the shipped idiom that answers M-10 and should be copied, not re-invented.
- **AC 7** — pre-populated from SELF-260's seed. Dependency on an unaudited issue.

**Verdict:** amendable, with the column names explicitly demoted to proposals pending SELF-259.

---

### SELF-266 — §2.5.3.b quarterly tables UI · **AMENDABLE**, one false-composite citation

- **AC 1** — `fn_compute_tax_liability()`, absent. Same dependency.
- **AC 2** — the row structure is PRD §2.5.3 verbatim and correct. ⚠ **Sec's M-8** (the ÷4 split does not reconcile to the annual liability) applies to the arithmetic behind these rows and belongs in SELF-262's AC, not here; **M-9** (the standard deduction can drive taxable income negative with nothing flooring it) likewise. Cited so the UI issue's builder knows the numbers arriving may be shaped by a ruling not yet made.
- **AC 4** — the (δ-2) applied-rate caption, populated from an `applied_marginal_rate` output. That output field **does not exist** because the helper does not; it is a contract SELF-262 must be told to emit. Recorded here because a caption whose input is never specified is exactly how a surface ships with a hardcoded rate.
- ⚠ **AC 7 carries a false-composite citation.** It reads *"routes to `/settings/tax-brackets` (SELF-261-equivalent — Settings editor PM Issue 4 above; pending Linear assignment)"*. **SELF-261 is the wash-sale annotation table**, not the settings editor; the settings editor is **SELF-265**, which is in this same dump. Both labels are real and the pairing is not — the [ADR-011](../../../DECISIONS.md#adr-011) Decision 4 CHANGELOG's *"right content, wrong pointer"* class, which *"survives every spot-check."* Corrected in §4 of the re-derived ACs.
- **AC 8** — the zero-IRS/FTB-accounts empty state is now well-defined given Gate B: the condition is *no account carries a `tax_jurisdiction` value*, not *no account named IRS exists*.

**Verdict:** amendable.

---

### SELF-267 — §2.5.3.c YTD-Paid overlay backend · **DRIFT (severe) + needs-ruling**

The identification mechanism is ruled (Seam B, Gate B Option A) and the AC states it correctly. **The primitive it specifies is wrong in three independent ways, and each is invisible in the output.**

1. ⚠ **AC 3's signature takes `p_users_id UUID`.** `pfin.fn_ytd_paid_per_jurisdiction(p_users_id UUID, p_year INT, p_jurisdiction TEXT, p_through_quarter INT)`. **No shipped `pfin` reader takes a tenant parameter** — `fn_cashflow_items(date)`, `fn_account_cash_as_of(date)`, `fn_account_unrealized_gl(date)`, `fn_nav_composition(date)` all take the as-of date alone and derive the tenant from `auth.uid()` through RLS. A `p_users_id` parameter is either **ignored** (in which case it is a lie in the signature that a caller will trust) or **used in the predicate** (in which case it is an ownership-forge vector on a `SECURITY INVOKER` function whose whole isolation story is that the tenant is not client-supplied). AC 6 says *"RLS enforced under SECURITY INVOKER composition"* — **AC 3 and AC 6 contradict each other.** ⚠ SELF-269's AC 7 pen-tests precisely this parameter, which means the battery is being written against the defect rather than against the fix.
2. ⚠ **AC 1 creates `pfin.tax_jurisdiction_enum`; AC 3 declares the parameter `p_jurisdiction TEXT`.** A type mismatch inside one issue's own ACs. Either the parameter is the enum type, or the function accepts strings the enum would have rejected.
3. ⚠ **AC 3's period grammar is the wrong one, and it is the Jan-15 defect (Seam B half one).** *"Sums payments through end of `p_through_quarter`"* is the transaction-grain quarter-flag route; the PRD text the same issue quotes is the **ledger-balance** route. The Federal Q4 installment for tax year *Y* is due **Jan 15 of Y+1**, so it falls outside every quarter flag of *Y*. Sec's **M-4** reaches the same boundary from the tax-year-scope side. **One correction fixes both:** a balance-as-of read, `fn_account_cash_as_of`-shaped, taking a date rather than a quarter ordinal.

**Also owed and not in the ACs:**
- `pfin.account` gains a column, so `fn_create_manual_account`'s INSERT column list must be checked for the pairing hazard [ADR-062](../../../DECISIONS.md#adr-062) Decision 6 records. ⚠ **The live body is `087`, not `013`** — the function has been replaced twice (`013` → `048` → `087`), and `013`'s body still names the `sub_cat_id` that `048` dropped. Reading the file the function is named after is how a superseded body gets mirrored. A nullable column with no DEFAULT does not create the hazard here, but the check must be **run and recorded**, not assumed.
- **No Decision 3 obligation.** `tax_jurisdiction` is an enum column, not FK-shaped: no FK, no relation reference, no id array. Stated per-column per `085`'s rule, because `084`'s Amendment 1 records the check not actually having been run on the second table of a pair.
- ⚠ A **partial unique index** is worth considering so two accounts cannot both claim `irs` — Sec raises this under its F-1 option (C) and it survives the ruling. Without it, `fn_ytd_paid_per_jurisdiction` silently sums two ledgers.

**Verdict:** severe drift. The re-derived AC replaces the signature, the type, and the period grammar.

---

### SELF-268 — §2.5.4 NAV composition flip · **IMPOSSIBLE as written (one-way door; AC 4 instructs the rejected option)**

Seam E holds the analysis and is not restated. Per-AC:

- **AC 1 / AC 2** reach two of the four layers. ⚠ **Neither says what actually changes in `051`:** the two tax lines are `0::numeric` literals **inside the `nav` key's arithmetic**, not values beside it — `'nav', (s.total_non_re + s.real_estate) - (-s.liability_signed) - 0::numeric - 0::numeric`. So this is a **change to the value of NAV**, not a change to two display rows. The ACs read as the latter.
- **AC 6** — *"no `$0` placeholders remain; no 'V1.4' trace tooltips remain"* — reaches layer 3 (`nav-composition.ts`'s `isTaxPlaceholder`) and, if read strictly, layer 4. ⚠ **Layer 4 must be named explicitly**: `NavCompositionTable.svelte` renders `{row.isTaxPlaceholder ? usd.format(0) : usd.format(row.displayValue)}` — it **discards `displayValue`** for those rows. Fix layers 1–3 and miss this one and the surface renders `$0` against correct data, with no error, no failing assertion, and a passing type-check.
- ⚠ **AC 4 IS THE ONE-WAY DOOR, AND IT INSTRUCTS THE REJECTED OPTION.** It reads: *"SELF-226 NAV trajectory consumes flipped Tax Liab values; **historical NAV recompute back-fills correctly**."* `pfin.nav_daily` (`054`) is **append-only audit-class** under [ADR-011](../../../DECISIONS.md#adr-011) Decision 2, carries `nav_value numeric not null`, and has **no definition-version column**. A back-fill is a rewrite of an audit surface. And the tax state for a past date is **not recoverable** — the book has moved — so back-filled values would be a fabrication with the shape of a measurement. **AC 4 cannot be amended into correctness; it needs the Seam E ruling first**, and the re-derived block leaves it as a named placeholder rather than picking.
- **AC 3** — single combined Federal + CA row per (ρ). Correct.
- **AC 5** — live recompute. Correct, and cheap: every input is already read live.
- ⚠ **Sec's M-2 changes what AC 2 renders**, and it is not a display question: a negative aggregate unrealized G/L makes Unrealized Tax Liability negative, and `051` **subtracts** it, so **NAV rises on an unrealized loss**. Sec's F-3 holds the option set (clamp / allow / clamp-plus-note). **Sec's M-3** covers the sign convention on both rows and the double-negation route — the `debt` row is already the file's one sign flip and the two tax rows must not accidentally become three. Cite; do not restate.

**Verdict:** impossible as written. Requires the Seam E ruling and Sec's F-3 before it can be dispatched.

---

### SELF-269 — §2.5.5 RLS verification battery · **AMENDABLE (severe)**; V1.4 close-gate

- ⚠ **AC 8 is schema-impossible on two counts.** *"tenant A cannot create / update / read tenant B's `pfin.transaction_annotation` row."* **No such table.** The tree has `pfin.account_trans_annotation` (`023`); `git grep -n 'transaction_annotation' 2cd94ae -- supabase/` returns no `create table`. And the *wash-sale annotation* the leg is aimed at does not exist as a column anywhere — Seam G. The leg tests a table that does not exist for a column that does not exist, and would be **silently vacuous** if written against a `to_regclass` guard that skips on absence.
- ⚠ **AC 1, AC 5, AC 7 and AC 9 reference SELF-259 / 260 / 261 / 262**, none of which is in this milestone (see the scope defect above). AC 9's *"SELF-259-266"* is a **range across a milestone boundary**. The battery cannot be scoped until those four are.
- **AC 4** — the (π) three-way `tax_treatment` orthogonality leg. **Buildable and important**, and it is the only watcher Seam F's exclusion will have: `049` carries no filter, so whichever option lands, this leg is what proves it. `pfin.account.tax_treatment` is `not null check (… in ('taxable','tax_deferred','tax_free'))` at `003`, so the leg can assert all three states with no NULL case.
- **AC 6** — monotonicity across replay. Correct, and it is a leg on SELF-259's trigger.
- **AC 2 / AC 3 / AC 5** — standard and correct against the SELF-257 precedent.
- **AC 10** — Sec verdict recorded. Correct.

**Standing obligations that do not appear in any AC and must:**
- ⚠ **Verify with `pg_prove`, never bare `psql`.** pgTAP's plan count enforces only through a TAP-aware consumer: `pg_prove` exits 1 on a short plan, **`psql` exits 0**.
- ⚠ **pgTAP `isnt()` PASSES on NULL** (it is `IS DISTINCT FROM`), so a negative isolation assertion over a subquery is **fail-open**. Use `ok()` and prove three states, not two.
- ⚠ **A `set local` outside a transaction is a silent no-op** — the smoke then runs as superuser and every leg passes. A control leg must come first.
- ⚠ **A freshly-seeded row is invisible to a past as-of** under [ADR-011](../../../DECISIONS.md#adr-011) Decision 19's `created_at` half; an all-zero result is byte-identical to broken. Smoke at `current_date`.
- **Where Sec's §4 catch-criteria and this list overlap, Sec's text governs** — it is the battery's spec and this is a cross-check of it.

**Verdict:** amendable, but **not draftable until the four out-of-milestone issues are audited**, since its scope is defined by them. It stays last regardless.

---

### SELF-302 · SELF-303 — GL follow-ups · **BUILDABLE, and both move §2.5 numbers**

Both issue texts are short, accurate about the tree, and correctly self-identify as joint-review-mandatory money-flow migrations with their own mini-designs. `035` P7's Suspense parking and `037`'s *"Suspense-parked floor"* are both verified present at `2cd94ae`.

**The finding is not in either issue: neither says it changes a §2.5 figure.** Seam I holds the analysis and the sequencing options. SELF-303 additionally carries a non-gating test-durability nit (a co-located aal2 assertion on the `037` battery) which is correctly marked non-blocking.

**Verdict:** buildable. Their **placement** relative to SELF-262 is a ruling (Seam I), not a build question.

---

## 5. Proposed dispatch order

**Constraints honored, each with its source.** SELF-269 last (its own text: *"no V1.4 issue closes to milestone until this battery passes"*, and the SELF-244 / SELF-228 / SELF-257 precedent) · the BACKLOG §7.28 item 3 inventory session before §2.5.1 ships (its own AC) · light-loop eligibility flagged per issue (result: none) · Seam dependencies as stated in §2.

**Step 0 — the sitting itself, before any dispatch.** Rulings owed: Seam A grain (one-way-door sub-part) · Seam E disposition (one-way door) · Seam G wash-sale PRD-vs-tree conflict · Seam I sequencing · SELF-263 re-scope · Sec's F-2 / F-3 / F-4 / F-5 · the §7.28 item 3 owner and slot (Sec F-6(b)) · **and the decision on whether to extend this pass to SELF-259/260/261/262.** That last one is a prerequisite for steps 2, 4 and 6 being dispatchable at all.

| # | Issue | Why here | Blocked by |
|---|---|---|---|
| 1 | **SELF-263**, re-scoped | Discharges §7.28 item 3. Every downstream tax figure reads the values it settles, so it is genuinely first — and post-re-scope it carries no schema work, which is what lets it run in parallel with 2–4. | Step 0 re-scope ruling |
| 2 | **SELF-259** *(Platform V1.x, UNAUDITED)* | The bracket tables. Seam A's ruling lands here and the Decision-3 label is allocated here. Nothing in §2.5.2/§2.5.3 exists without it. | Step 0 Seam A ruling; an audit of its own ACs |
| 3 | **SELF-267** | Independent of the bracket chain — it touches `pfin.account` and `account_trans` only. Runs in parallel with 2. Ships the Gate B ADR fold-in. | Step 0 (period-grammar correction is in the re-derived AC) |
| 4 | **SELF-260** *(Platform V1.x, UNAUDITED)* | The seed. Needs 2's DDL. | 2 |
| 5 | **SELF-302** + **SELF-303** | Seam I: land them here and SELF-262 computes over a settled book. If Step 0 rules the other way, they move after 6 and 6 carries a named residual. | Step 0 Seam I ruling |
| 6 | **SELF-262** *(Platform V1.x, UNAUDITED)* | **The milestone's keystone.** Five of the seven V1.4 issues call it in their first AC. Seams B, C, F and I all converge here, as do Sec's M-1 / M-4 / M-7 / M-8 / M-9. | 1, 2, 3, 4, and 5-or-a-residual |
| 7 | **SELF-265** | The settings editor. Needs 2's tables and 4's seed; its column names are ratified at 2, not here. | 2, 4 |
| 8 | **SELF-264** ∥ **SELF-266** | The two read surfaces. Parallel — disjoint routes (`/taxes/decomposition`, `/taxes/quarterly`), disjoint components, one shared upstream. | 6 (7 for SELF-266's Edit-button target) |
| 9 | **SELF-268** | The NAV flip. **After 8**, so the live walk on the two tax surfaces has already exercised the helper's output before that output starts moving NAV. Four layers; layer 4 is silent. | 6, 8, and the Step-0 Seam E ruling |
| 10 | **SELF-269** | Close-gate, last. Its scope is defined by everything above, which is why it cannot be drafted earlier even though the battery pattern is known. | all |

**The one ordering choice that is not forced, stated as such.** Placing SELF-268 *after* the read surfaces (step 9, not step 7) is a judgment call, not a dependency. The argument for it: SELF-268 changes the value of NAV on surfaces that have shipped and been walked for three milestones, and doing that **after** a human has driven the tax numbers themselves means a wrong figure is caught where it is legible rather than where it is one row in a buildup ladder. The argument against: it puts the milestone's most delicate change last-but-one, next to the close-gate. **F/CTO may reasonably invert it**; recorded so the choice is visible rather than inherited.

**Not scheduled here, and deliberately.** The four Platform V1.x issues appear in this order because V1.4 cannot ship without them, **not** because this pass has authority over another milestone's sequencing. If they are dispatched from Platform on a different cadence, steps 6–10 stall and the stall will look like a V1.4 problem.
