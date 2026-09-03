# V1.4 (§2.5 Estimated taxes) — Architect AC-vs-tree feasibility audit

**Baseline.** `origin/main` at `2cd94aebd034fbad43ef2401821a860679e72d6b` (detached read in the architect worktree). Migrations `001`–`099` on the tree. Every schema identifier below was grepped or read in-file at this sha; no count or identifier is carried from recall.

**Standing.** This pass is the [ADR-063](../../../DECISIONS.md#adr-063) Decision 1 discharge for the V1.4 milestone — the pre-flight recalibration pass run before the first build dispatch, not during it. It is also the second application of BACKLOG §7.19 AC 3 at a milestone-rotation boundary.

**§10 3-axis cross-check** — performed against [ADR-011](../../../DECISIONS.md#adr-011) Decision 4 read verbatim and live before drafting. This memo introduces no catalogued instance, reorders none, changes no layer-attribution, and restates the catalogued list nowhere (Path B — referenced, not copied). No ledger change; not a §10 Sec trigger. ⚠ The §10 CATALOGUED set and the CI-FENCED set (`grep -rhoE 'RT-[0-9]{2}' .github/workflows/`) are different sets and are **not** reconciled anywhere below; the CI set is strictly larger and that difference is deliberate.

**[ADR-011](../../../DECISIONS.md#adr-011) Decision 3** — read live at this sha. No tally appears below. **Seam A carries a live D3 determination**: the unbuilt `pfin.tax_bracket_row` carries an FK-shaped reference column crossing a tenant boundary, so it takes the next canonical label under Decision 3's standing discipline and owes matched-tenant validation in its DDL. No label is drafted here — D18's own amendment records what drafting a label in advance already cost this family once.

**Instrument note.** Function bodies were read from the migration files at this sha, not from a live catalog. Where a `create or replace` chain could have superseded a body, the superseding migration was searched for by symbol across the whole `supabase/migrations/` tree rather than by filename; the function inventory below was derived from `git grep -oE 'create or replace function pfin\.[a-z_0-9]+'` over the tree at `2cd94ae`, deduped.

---

## 1. Classification summary

*(per-issue rows land when the issue dump arrives; the seam inventory below is complete and independent of it)*

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

**Options — the YTD-Paid source.** *(F/CTO ruling; reversible, but a wrong pick ships a wrong money figure)*

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

**Architect's lean:** **Option A**, and the account-designation gap routed as its own small ruling — the Jan-15 defect is real and Option A is the only one that never meets it. Recorded as a lean, not a conclusion.

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

## 3. Cross-cutting determinations

- **[ADR-011](../../../DECISIONS.md#adr-011) Decision 3.** One new family member is in scope across the milestone (Seam A). No label is drafted here. Every FK-shaped column in any V1.4 migration — including any `INTEGER[]` — carries matched-tenant validation in its DDL, non-negotiable.
- **SECURITY DEFINER.** No §2.5 surface identified in this pass requires one. Lock 11 SECURITY INVOKER read-composition is the default and every function read at this sha in the §2.5-adjacent path (`049` `051` `056` `093`) is `security invoker` + `set search_path = ''`. Any DEFINER proposal routes to Sec joint-review; read the allowlist ([ADR-011](../../../DECISIONS.md#adr-011) Decision 9) live.
- **aal2 step-up backstop.** Any new sensitive tenant-owned `pfin` table (Seam A's two) owes the `025` backstop clause on its `authenticated` policies unless a documented `025` exclusion applies. ⚠ `pfin.user_settings` is named in `025` as a **non-negotiable exclusion** (policy recursion) — that exclusion does not generalize to siblings, and the bracket tables are not covered by it.
- **QA pairing.** Every migration extending RLS surface ships its two-tenant pgTAP battery in the same PR. Batteries live at `supabase/tests/rls/NNN_*.sql`. ⚠ Verify with `pg_prove`, never bare `psql` — `psql` exits 0 on a failed plan.
- **Ledgers flat.** No §10 count and no D3 tally appears in this memo. Citations are by name.

---

## 4. Per-issue findings

*(pending the issue dump at `temp/v14-preflight/issue-dump.md`)*

---

## 5. Proposed dispatch order

*(pending the issue dump — the seam dependencies above already fix most of the ordering; see the re-derived AC file for the per-issue baseline blocks)*
