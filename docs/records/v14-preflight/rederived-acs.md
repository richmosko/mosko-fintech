# V1.4 (§2.5 Estimated taxes) — re-derived acceptance criteria

**What this file is.** Landing-ready replacement AC text, per issue, for the V1.4 pre-flight recalibration ([ADR-063](../../../DECISIONS.md#adr-063) Decision 1). Each block is written to be pasted into its Linear issue **as a whole**, replacing the drafted ACs. The analysis and evidence behind every change live in [`architect-findings.md`](architect-findings.md); this file carries the text, not the argument.

**Baseline, carried per block rather than in this header only.** Every block below self-carries `2cd94ae` — per [ADR-063](../../../DECISIONS.md#adr-063)'s Consequences, *"a document header does not travel into the artifact each block lands in."*

**Placeholders.** Where a block depends on a ruling not yet made, the dependency appears as **`⟨RULING: …⟩`** in the AC text itself. **Those are not to be resolved by the builder** — they are resolved at the sitting and the resolved text is what lands. A block containing an unresolved `⟨RULING⟩` is not dispatchable.

**PM's product wording.** ⚠ **Not merged.** `origin/meta/v14-preflight-pm` did not exist at `git fetch` time (checked in-turn: `fatal: couldn't find remote ref meta/v14-preflight-pm`). This file therefore ships **without** PM's (a)-class copy. Where a block below rewrites user-facing copy — empty states, captions, marker text — **PM's wording governs on conflict for those strings**; the schema wording in every other position is Architect's and governs on conflict, as the V1.3 file did.

**Sec.** Cited by flag id (`M-n` / `F-n`) against `origin/meta/v14-preflight-sec` @ `39bc549`, `docs/records/v14-preflight/sec-findings.md`. **Cited, never restated** — a paraphrase of a Sec flag in an AC is a second copy that drifts.

---

## SELF-263 — §2.5.1.a tax-relevant attribute migration + F/CTO bootstrap seed

**⚠ This block is CONDITIONAL on a re-scope ruling and is written for Option A** (re-scope to the value-inventory session). If the sitting rules Option B (close as discharged, open a new issue), this text moves to the new issue unchanged and SELF-263 closes with a pointer to it.

> **Baseline: `origin/main` @ `2cd94ae`.**
>
> **⚠ Re-scoped at the V1.4 pre-flight (2026-09-03). The originally drafted deliverable is already on `main` under other names, and the ACs below replace it entirely.** What shipped, with evidence: `pfin.user_taxonomy.tax_relevant` (`boolean not null default false`) and `.tax_character` landed at `009`; `011` replaced the inline CHECK with `fk_user_taxonomy_tax_character` referencing the **global value-registry table** `pfin.tax_character(code)` — deliberately a table and **not** a PostgreSQL enum, per `011`'s Option-C-hybrid rationale, so the drafted `pfin.tax_character_enum` must **not** be created; [ADR-058](../../../DECISIONS.md#adr-058)'s split moved the cash-flow posting vocabulary to `pfin.posting_prototype` / `pfin.posting_prototype_default` at `084`, so `user_taxonomy` holds no cash-flow rows to mark; `041` seeded the values; `091` shipped the disjoint `is_tax_payment` marker. **The residual — and the whole of this issue — is that nobody has audited the seeded VALUES.**
>
> **Source.** BACKLOG `§7.28` item 3 (*"V1.4 tax-value inventory session (F/CTO)"*), promoted from a booking to this issue's deliverable. PRD §2.5.1 (ζ-2). [ADR-062](../../../DECISIONS.md#adr-062) Decision 3 + Decision 4.
>
> **Acceptance criteria**
>
> 1. **An F/CTO inventory session runs and its outcome is recorded on this issue.** Every `pfin.posting_prototype_default` row's `tax_relevant` and `tax_character` is **confirmed or corrected** against the V1.4 tax model. The session's output is a row-by-row disposition, not a summary.
> 2. **`Equity / Contribution`'s flag is resolved per account type.** It currently enters `tax_relevant = true` as **flag-for-review** with [ADR-062](../../../DECISIONS.md#adr-062) Decision 4's `notes` rider (*"potentially deductible; resolve per account type at the V1.4 tax inventory"*). Resolution either keeps `true` with a corrected rider, or changes the value — and either way the **rider is updated or removed**, because `notes` is copied to every provisioned user's row.
> 3. **The corrections land as a migration**, and the migration reaches already-provisioned users by **explicit backfill** — [ADR-057](../../../DECISIONS.md#adr-057)'s rule as generalized to the posting pair by [ADR-062](../../../DECISIONS.md#adr-062) Decision 5. `provisionCashflowPrototypes` in `api/src/lib/server/queries/taxonomy.ts` is **existence-guarded** (`if (existing) return;`), so a user holding even one `posting_prototype` row **never receives a later default-set change**. Correcting `posting_prototype_default` alone reaches nobody who already exists.
> 4. **Both tables of the pair are corrected**, per [ADR-058](../../../DECISIONS.md#adr-058) Decision 3's pair discipline — `posting_prototype_default` **and** `posting_prototype`. ⚠ `084`'s Amendment 1 records the per-table check not actually having been run on the second table of a pair; state the check per table.
> 5. **This issue discharges [ADR-062](../../../DECISIONS.md#adr-062) Decision 3's HARD PRECONDITION**, which is a sequencing commitment with no mechanism: *"nothing in the schema prevents the surface being built against an unmarked column."* Note that ADR-062's precondition is scoped to **Expense-class** prototypes for `is_tax_payment`; this inventory is **not** so scoped — it covers every class, because `tax_relevant` / `tax_character` are read on Revenue rows. Sec's **M-6** and **F-6(b)** are this same obligation and are discharged with it.
> 6. **`tax_relevant`'s fail-open `DEFAULT false` is dispositioned, not merely observed.** Per Sec's **M-5** and **F-5** — cite the ruling taken; do not restate the option set. ⚠ If the ruling is *leave the DEFAULT*, a `comment on column` scoping what `false` means is required on each of the three tables carrying the column, in the shape [ADR-062](../../../DECISIONS.md#adr-062) Decision 2 used for `is_tax_payment`: without it, `false` reads as *the question was asked and answered* rather than *nobody has looked*.
> 7. **No new vocabulary.** `pfin.tax_character_enum` is **not** created. The five V1 values are `pfin.tax_character`'s seeded codes and membership is FK-enforced; a sixth value is a seed migration on `011`, never a CHECK edit.
> 8. **QA:** a two-tenant pgTAP battery paired in the same PR, asserting (i) a user provisioned **before** this migration holds the corrected values after it — the backfill's only watcher; and (ii) a fresh signup receives the full cash-flow prototype set, **asserted by ROW COUNT**, because the provisioning branch is fail-soft (`console.error(...); return`) and a broken path returns cleanly with zero rows and no error.
>
> **Sec joint-review:** mandatory — it changes values a money-path filter reads, and it carries a provisioning-reach decision. **Light loop: NO** — [ADR-066](../../../DECISIONS.md#adr-066) Decision 1 (a), a migration.
>
> **Dependencies.** Upstream: none blocking. Downstream: **SELF-262** (reads `tax_relevant` as a filter and `tax_character` as routing), SELF-264, SELF-266.

---

## SELF-264 — §2.5.1.c tax-relevant income decomposition table UI

> **Baseline: `origin/main` @ `2cd94ae`.**
>
> **Acceptance criteria**
>
> 1. SvelteKit page at `/taxes/decomposition` loads via `+page.server.ts` SSR, invoking **SELF-262**'s `pfin.fn_compute_tax_liability(p_data_as_of date)`. ⚠ That function does **not exist at this baseline** — verified against the function inventory at `2cd94ae`. Its exact signature and return shape are ratified at SELF-262 and **read from there**, not assumed from this AC.
> 2. Three-column table — Ordinary Income / ST CG / LT CG — at Sub-Cat granularity, **current tax year**. ⚠ The year is derived in the **database** (`pfin.fn_server_today()`, `070`), never in Node: [ADR-044](../../../DECISIONS.md#adr-044) records the two-clock hazard this avoids, and the `061` TimeZone pin is *necessary and not sufficient*.
> 3. Two sections: **Income** (cash-flow contributions, sourced from `pfin.posting_prototype`) and **Capital Gains** (realized-G/L contributions, sourced under the holding's asset Sub-Cat in `pfin.user_taxonomy`). ⚠ These are **two disjoint id spaces** — `posting_prototype.id` begins at `1000000000` (`084`), `user_taxonomy.id` at `1` — so the surface renders a **UNION discriminated by domain**, never a join on id. A join on id returns nothing and does so silently.
> 4. Cat-grouped section headers with Sub-Cat detail rows beneath; total row foots the table; per-Cat-group subtotals as group aggregates (the §2.2.2 pattern).
> 5. Each row communicates its `tax_character` so schedule-routing intent is legible at a glance. ⚠ The vocabulary is `pfin.tax_character`'s **five seeded codes** (`011`), FK-enforced — not a client-side list, and not an enum type.
> 6. Live recompute as transactions land and as tax attributes change.
> 7. `tax_relevant = false` Sub-Cats are excluded from the table entirely. ⚠ Per Sec's **M-5**, the column carries a fail-**open** `DEFAULT false`, so an unmarked row and a deliberately-excluded row are indistinguishable here. Whatever SELF-263 AC 6 rules about that default, this surface **must not present exclusion as a determination** it cannot make.
> 8. **A realized sale with no resolvable holding period** renders per Sec's **M-1** and the **F-2** ruling: **⟨RULING: F-2 — route unmatched sells to ST/ordinary · render UNAVAILABLE-with-a-reason and exclude · route to LT⟩**. Cite the ruling; do not re-derive it here.
> 9. **Empty state** — a user with no tax-relevant Sub-Cats sees a one-line explanation and no fabricated zeros. ⚠ It must **not** offer a CTA to a route that does not exist; the drafted *"CTA to migration-time docs"* names no route. Copy is PM's. *(PM's wording not available at authoring — see this file's header.)*
> 10. No inline edit (V2+), per PRD §2.5.1 and [ADR-013](../../../DECISIONS.md#adr-013) P5.
>
> **Light loop: NO** — [ADR-066](../../../DECISIONS.md#adr-066) Decision 1 (b): it renders money figures, and *"a rendering-only change to a money figure still counts as a money-path change."*
>
> **Dependencies.** Upstream: **SELF-262** (helper; **Platform V1.x — not audited at the V1.4 pre-flight**), SELF-263 (values).

---

## SELF-265 — §2.5.2.a tax-brackets settings editor

> **Baseline: `origin/main` @ `2cd94ae`.**
>
> **⚠ At this baseline, `pfin.tax_bracket_schedule` and `pfin.tax_bracket_row` DO NOT EXIST.** They are Lock 14 **ratified names with zero DDL** — [ADR-011](../../../DECISIONS.md#adr-011) Decision 18's amendment states it verbatim: *"None of the five is built except `planning_target`."* Every column name in this issue is therefore a **proposal**, ratified at **SELF-259**'s DDL and read from there.
>
> **Acceptance criteria**
>
> 1. Settings route at `/settings/tax-brackets`, the **third-of-four** Settings occupant per [ADR-013](../../../DECISIONS.md#adr-013) P5. Lists three schedules: **Federal ordinary** + **Federal LT CG** (PRD §2.5.2 (λ)) + **CA FTB ordinary** (PRD §2.5.2 (κ)).
> 2. Per-schedule editor: an ordered bracket-row table (a marginal rate and a lower-bound threshold per row) plus a standard-deduction scalar. ⚠ **Column names are SELF-259's to fix**, not this issue's — the drafted `bracket_floor` / `bracket_rate` are carried forward as the **recommendation** and are correct against PRD's *"lower-bound threshold"*, but a settings editor is the wrong place for a column name to originate.
> 3. **Replace-all write semantics under SERIALIZABLE** — the entire schedule plus its rows replaced by one POST — per [ADR-011](../../../DECISIONS.md#adr-011) Decision 18's Sec mod. Endpoint per SELF-259's contract. ⚠ A schedule identifier arriving from the client is an **object reference** and therefore an IDOR / mass-assignment surface: Decision 18's *"`users_id` from `auth.uid()` not `req.body`"* mod applies to it, and the isolation traps in the replace-all path are enumerated in Sec's §3 — build to that text.
> 4. **Lock 14 V1-SHIP-BLOCK mods applied at the app layer**: Zod `.strict()` validation; mass-assignment prevention; the numeric-input adversarial battery (NaN / Inf / currency-string regex / overflow / scientific-notation / locale-formatted reject).
> 5. **Bracket-row monotonicity enforced server-side by DB trigger** (SELF-259) **and** surfaced client-side as inline validation. ⚠ **The client-side half is a courtesy and the DB trigger is the control** — never the reverse. Sec's **M-7** bounds what the trigger must actually check (a lower floor, an upper bound, and a stated unit for the rate) and **M-10** records that a one-sided `>= 0` CHECK **admits `NaN`**; the shipped idiom that answers M-10 is `090`'s (`… >= 0 and … <> 'NaN'::numeric`). Both are obligations on **SELF-259's DDL**, cited here so this issue's reviewer can see the second layer exists.
> 6. No inline edit on the §2.5.3 tables ([ADR-013](../../../DECISIONS.md#adr-013) P5); the "Edit tax brackets" affordance **on SELF-266** routes here.
> 7. First visit is pre-populated from **SELF-260**'s seed and is user-revisable.
> 8. **Sec joint-review mandatory** — settings write path plus the numeric adversarial battery, mirroring the SELF-233 / SELF-242 pattern.
> 9. **The new tables carry the `025` aal2 step-up backstop clause** on their `authenticated` policies. ⚠ No documented `025` exclusion applies: `pfin.user_settings` is named in `025` as a **NON-NEGOTIABLE** exclusion because clausing it recurses into the policy that reads it, and that exclusion **does not generalize to siblings**. This obligation is invisible once omitted, which is why it is named in an AC and not only in the migration.
>
> **Light loop: NO** — [ADR-066](../../../DECISIONS.md#adr-066) Decision 1 (b) *and* (c): a bracket rate is an input to every money figure in §2.5, and the issue carries `sec-joint-review`.
>
> **Dependencies.** Upstream: **SELF-259** (tables + endpoint; **Platform V1.x — not audited**), **SELF-260** (seed; same), SELF-242 (Settings shell), SELF-233 (write-path hardening). Downstream: SELF-262 reads the edited data live.

---

## SELF-266 — §2.5.3.b two parallel quarterly estimated-tax tables

> **Baseline: `origin/main` @ `2cd94ae`.**
>
> **Acceptance criteria**
>
> 1. SvelteKit page at `/taxes/quarterly`, SSR via `+page.server.ts`, invoking **SELF-262**'s `pfin.fn_compute_tax_liability(p_data_as_of date)`. Signature and return shape are read from SELF-259–262, not assumed here.
> 2. Two parallel tables — **Federal Income Taxes** and **California State Income Taxes (CA FTB)** — with PRD §2.5.3's row structure: Tax Balance Prior Year (**informational only** per μ-2; it does **not** drive V1 computation); four Estimated Tax Payments rows with their due dates (Federal Apr 15 / Jun 15 / Sep 15 / **Jan 15 of the following year**; CA aligns on Q1/Q2/Q4 and differs on Q3); a Sub-Total running obligation; YTD Paid; and Estimated Funds Due as the gap.
> 3. The current quarter is visually emphasized (ξ-1), parallel to §2.3.2's month-emphasis pattern.
> 4. **Applied-rate caption** per (δ-2): Federal *"Federal ordinary: X% / Federal LT CG: Y%"*; California *"California: Z%"*. ⚠ **These rates are an output SELF-262 must emit** — the drafted `applied_marginal_rate` field does not exist because the helper does not. If SELF-262 does not supply it, this caption must render **unavailable**, never a rate computed in the component: a marginal rate derived twice is a marginal rate that drifts.
> 5. **(ν-1) overpayment renders as a negative value on the same line** — sign-flipped, single-line continuity with the underpayment case. No separate "Refund Expected" line (V2+).
> 6. Live recompute on §2.5.2 bracket edits, §2.5.1 decomposition changes, and §2.4.3 manual-entry edits.
> 7. No inline edit ([ADR-013](../../../DECISIONS.md#adr-013) P5). The "Edit tax brackets" button routes to `/settings/tax-brackets` — **SELF-265**. ⚠ *Correction: the drafted AC cited this target as "SELF-261-equivalent". **SELF-261 is the wash-sale annotation table**, not the settings editor. Both labels are real and the pairing was not — the false-composite class recorded in [ADR-011](../../../DECISIONS.md#adr-011) Decision 4's CHANGELOG, which survives every spot-check.*
> 8. **Empty states**, two, and they are distinct conditions: (i) **no bracket schedule configured** → a one-line explanation with a CTA to `/settings/tax-brackets`; (ii) **no account carries a `tax_jurisdiction` value** → a one-line explanation with a CTA to manual-account onboarding (SELF-201). ⚠ The second condition is *"no account is marked as IRS or FTB"*, **not** *"no account is named IRS"* — the marking is `pfin.account.tax_jurisdiction`, per F/CTO Gate B Option A (`CHANGELOG.md` Wave 5 / PR #92) and SELF-267. Copy is PM's. *(PM's wording not available at authoring.)*
> 9. **Figures arriving from SELF-262 may be shaped by rulings not yet made** — Sec's **M-8** (the ÷4 split does not reconcile to the annual liability) and **M-9** (the standard deduction can drive taxable income negative with nothing flooring it). Those are obligations on SELF-262; this AC records them so a reviewer of this surface knows a plausible-looking number here may be a defect there.
>
> **Light loop: NO** — [ADR-066](../../../DECISIONS.md#adr-066) Decision 1 (b).
>
> **Dependencies.** Upstream: **SELF-262** (**Platform V1.x — not audited**), SELF-265 (the Edit-button target), SELF-267 (YTD Paid).

---

## SELF-267 — §2.5.3.c IRS/FTB YTD-Paid semantic overlay backend

> **Baseline: `origin/main` @ `2cd94ae`.**
>
> **Ruled, not open.** F/CTO **Gate B Option A** (2026-06-03) locks the identification mechanism: a `tax_jurisdiction` enum column on `pfin.account`, F/CTO-marked at account creation. Recorded at `CHANGELOG.md` Wave 5 / V1.4 / PR #92 verbatim as *"F/CTO Gate B Option A (`tax_jurisdiction` enum column)"*. ⚠ **Sec's F-1 routes this to F/CTO as an open question with three options** — it is not open; Sec had the tree and not this ruling, and Sec's option (C) **is** Gate B Option A. Do not re-litigate it. ⚠ Note also that Sec's leaning option (A) would have added a Decision-3 family member; **Gate B Option A does not**, which leaves `tax_bracket_row` as the milestone's only Decision-3 candidate.
>
> **Acceptance criteria**
>
> 1. `pfin.tax_jurisdiction_enum` created with V1 values `irs` / `ftb`.
> 2. `tax_jurisdiction pfin.tax_jurisdiction_enum null` added to `pfin.account`, with a `comment on column` stating that a NULL means *"not a tax-authority ledger"* and **not** *"unknown"*.
> 3. ⚠ **A partial unique index prevents two accounts claiming the same jurisdiction per user** — `unique (users_id, tax_jurisdiction) where tax_jurisdiction is not null`. Without it, AC 4's primitive silently sums two ledgers and the result is well-formed and wrong. *(Raised by Sec under F-1 option (C); it survives the Gate B ruling unchanged.)*
> 4. **`pfin.fn_ytd_paid_per_jurisdiction(p_as_of date, p_jurisdiction pfin.tax_jurisdiction_enum) returns numeric`** — `security invoker`, `stable`, `set search_path = ''`. ⚠ **Three corrections against the drafted signature, each of which is invisible in the output:**
>    - **(a) No `p_users_id` parameter.** No shipped `pfin` reader takes a tenant parameter — `fn_cashflow_items(date)`, `fn_account_cash_as_of(date)`, `fn_account_unrealized_gl(date)`, `fn_nav_composition(date)` all derive the tenant from `auth.uid()` through RLS. A client-supplied tenant on a SECURITY INVOKER function is either **ignored** — a lie in the signature — or **used in the predicate**, which is an ownership-forge vector. The drafted AC 6 (*"RLS enforced under SECURITY INVOKER composition"*) and the drafted AC 3 contradicted each other; this resolves it toward AC 6.
>    - **(b) `p_jurisdiction` is the enum type, not `text`.** The drafted ACs created an enum and then declared the parameter `TEXT` — a type mismatch inside one issue.
>    - **(c) No `p_through_quarter` parameter, and no quarter grammar.** The figure is a **balance as of a date**, `fn_account_cash_as_of`-shaped, which is what the PRD text this issue quotes actually specifies (*"the cumulative balance of these account ledgers"*). ⚠ **The drafted quarter-ordinal form drops the Federal Q4 payment every year**: Q4 for tax year *Y* is due **Jan 15 of Y+1**, so it falls outside every calendar-quarter flag of *Y* — including `pfin.fn_cashflow_items`' `in_q4`, whose bounds run Oct 1 – Dec 31 (`093`). A balance read never meets this. Sec's **M-4** reaches the same date boundary from the tax-year-scope side; **⟨RULING: F-4 — what §2.5.3 shows for the prior year's outstanding Q4 between Jan 1 and Jan 15⟩** settles both, and this AC and Sec's F-4 must receive the **same** answer.
> 5. The primitive reads `pfin.account_trans` only through accounts whose `tax_jurisdiction` matches, composing under RLS on `pfin.account`. **No `service_role` reach.**
> 6. **No money movement** — [ADR-002](../../../DECISIONS.md#adr-002) §3.0. Payments are user-recorded §2.4.3 manual transactions; this is a read-path semantic overlay only.
> 7. **No [ADR-011](../../../DECISIONS.md#adr-011) Decision 3 obligation, stated per column rather than per migration.** `tax_jurisdiction` is an enum column: no FK, no relation reference, no id array — there is no referenced row and therefore no tenant to match. ⚠ Stated explicitly per `085`'s rule, because `084`'s Amendment 1 records the check not actually having been run on the second table of a pair.
> 8. **The creation-path pairing check is RUN and RECORDED, not assumed.** ⚠ **Check the LATEST body, not the migration the function is named after.** `pfin.fn_create_manual_account` has been replaced twice — `013` → `048` → **`087`**, which is the live definition at this baseline and whose INSERT column list is `(name, account_type, scope, tax_treatment)`. Reading `013` would show a `sub_cat_id` column that `048` dropped. The new column is nullable with no NOT NULL, so it does not break that path — but [ADR-062](../../../DECISIONS.md#adr-062) Decision 6 records the identical hazard being caught twice on columns that *were* NOT NULL, and the check is cheap. **If SELF-267 also adds a creation-time affordance for marking the jurisdiction, `087`'s signature and column list are what change.**
> 9. **An ADR fold-in ships in this PR.** Gate B Option A changes the column set of `pfin.account` — a central table — and lives only in `CHANGELOG.md` and a Linear description. ⚠ It was independently re-derived from scratch at this pre-flight because it was not findable from `DECISIONS.md`, which is the failure mode [ADR-011](../../../DECISIONS.md#adr-011) Decision 18's amendment generalizes: *"A downstream register can carry a decision; it cannot carry an amendment to a lock."*
> 10. **QA:** two-tenant pgTAP paired in the same PR, with the AC-7 leg of SELF-269 (cross-tenant jurisdiction pen-test) written against **this** signature, not the drafted one.
>
> **Sec joint-review:** mandatory — a money figure, a new column on a central tenant table, and a new read primitive. **Light loop: NO** — Decision 1 (a).
>
> **Dependencies.** Upstream: SELF-201 (manual accounts), SELF-202 (manual transactions). Downstream: **SELF-262**, SELF-266.

---

## SELF-268 — §2.5.4 NAV composition flip

> **Baseline: `origin/main` @ `2cd94ae`.**
>
> **⚠ ONE-WAY DOOR. This issue is not dispatchable until the ruling below is made.** The drafted AC 4 instructed the option that is rejected on the record.
>
> **What is actually on the tree, because the drafted ACs describe two display rows and this is four layers plus a NAV-definition change.** `pfin.fn_nav_composition` (`051`) emits both tax lines as `0::numeric` literals — and those literals are **inside the `nav` key's arithmetic**: `'nav', (s.total_non_re + s.real_estate) - (-s.liability_signed) - 0::numeric - 0::numeric`. `api/src/lib/nav-composition.ts` flags both rows `isTaxPlaceholder: true`. `api/src/lib/components/NavCompositionTable.svelte` renders `{row.isTaxPlaceholder ? usd.format(0) : usd.format(row.displayValue)}` — **discarding `displayValue`**. And `pfin.fn_compute_nav` (`050`) has **no tax leg at all**.
>
> **Acceptance criteria**
>
> 1. **`051` supplies real values** from SELF-262's helper, replacing both `0::numeric` literals — **including the two in the `nav` expression**. ⚠ This changes the **value of NAV** on the §2.1.5 surface; it is not a change to two rows beside it.
> 2. **`api/src/lib/nav-composition.ts`**: `isTaxPlaceholder` is removed for both rows, so `buildupRows` carries their real `displayValue`.
> 3. **`api/src/lib/components/NavCompositionTable.svelte`**: the `isTaxPlaceholder` ternary is removed, and the V1.4 trace tooltips with it. ⚠ **This is the silent layer.** Fix layers 1–2 and miss this one and the surface renders `$0` against correct data — no error, no failing assertion, a passing type-check, and a green suite.
> 4. **⟨RULING: Seam E — the relationship between §2.1.5's NAV and the checkpointed trajectory⟩.** The drafted AC read *"SELF-226 NAV trajectory consumes flipped Tax Liab values; historical NAV recompute back-fills correctly."* **That cannot be built.** `pfin.nav_daily` (`054`) is **append-only audit-class** under [ADR-011](../../../DECISIONS.md#adr-011) Decision 2, carries `nav_value numeric not null`, and has **no definition-version column**; a back-fill is a rewrite of an audit surface, and the tax state for a past date is not recoverable, so back-filled values would be a fabrication with the shape of a measurement. The ruled options are recorded in [`architect-findings.md`](architect-findings.md) Seam E — keep the trajectory pre-tax permanently and say so · add a definition discriminator and branch every trajectory reader · back-fill (rejected). **The resolved text replaces this AC; the builder does not choose.**
> 5. **A single combined Federal + California value per row** (ρ lock) — one Realized row, one Unrealized row, not four.
> 6. **⟨RULING: F-3 — does Unrealized Tax Liability floor at zero?⟩** Per Sec's **M-2**: a negative aggregate unrealized G/L yields a negative Unrealized Tax Liability, and `051` **subtracts** it — so **NAV rises on an unrealized loss**. This is arithmetic, not rendering, and the AC cannot be written until it is ruled.
> 7. **Sign convention verified end to end** per Sec's **M-3**. ⚠ `debt` is currently the ladder's **only** sign flip (`051` emits a positive magnitude, `nav-composition.ts` negates it). Adding two more subtractions must not make it three flips or none — the double-negation route Sec names is exactly how a correct value renders with the wrong sign.
> 8. **The (π) tax-advantaged exclusion is applied to the Unrealized aggregation** — `tax_treatment = 'taxable'` only. ⚠ `pfin.fn_account_unrealized_gl` (`049`) carries **no such filter** at this baseline; `pfin.account.tax_treatment` is `not null` with a three-value CHECK (`003`), so the filter is total with no NULL case. Where the filter lives is [`architect-findings.md`](architect-findings.md) Seam F; the **recommendation is the §2.5.4 composer, not a signature change on `049`**, because `049`'s signature is asserted by other files' catalog legs.
> 9. **Live recompute** on bracket edits, decomposition changes, market-value refresh, and manual-entry edits.
> 10. **Placeholder removal is verified by a test that would fail if a layer were missed** — an assertion that a non-zero helper value reaches the rendered cell, not an assertion that the string `$0` is absent. ⚠ The four layers are individually green today; a suite that stubs one of them proves the others work alone. This is the seam class, and it is the class [ADR-066](../../../DECISIONS.md#adr-066)'s context paragraph records as caught only by a person driving the real thing.
>
> **Sec joint-review:** mandatory — it changes the definition of NAV. **Live walk precedes the Sec spawn** ([ADR-063](../../../DECISIONS.md#adr-063) Decision item 4). **Light loop: NO** — Decision 1 (b).
>
> **Dependencies.** Upstream: **SELF-262** (**Platform V1.x — not audited**), SELF-211 / SELF-225 / SELF-226 (the shipped surfaces), and the Seam E + F-3 rulings.

---

## SELF-269 — §2.5.5 RLS verification battery (V1.4 close-gate)

> **Baseline: `origin/main` @ `2cd94ae`.**
>
> **⚠ Scope note. This battery's coverage set includes SELF-259 / 260 / 261 / 262, which are in the Platform / Cross-cutting V1.x milestone and were NOT audited at the V1.4 pre-flight.** The battery cannot be finalized until they are. It stays last regardless.
>
> **Acceptance criteria**
>
> 1. Two-tenant coverage of every V1.4 backend surface: SELF-263's corrected values, SELF-265's write path, SELF-267's primitive and column, SELF-268's composition change, and — once audited — SELF-259 / 260 / 262. The canonical leg is *tenant A injects tenant B's `users_id` → rejected*.
> 2. Tenant isolation through **SELF-262**'s SECURITY INVOKER composition, per the Wave 1 B5 / SELF-209 cross-tenant-leak analysis pattern.
> 3. Scope-attribute-not-isolation-boundary discipline preserved at every §2.5 surface (PRD §2.5.5).
> 4. **Three-attribute orthogonality at §2.5.4's (π) exclusion**: `tax_deferred` and `tax_free` accounts filtered out of the Unrealized aggregate, `taxable` included. ⚠ **This leg is the only watcher the exclusion will have**, since `049` carries no filter of its own (Seam F). `tax_treatment` is `not null` with three CHECKed values, so **assert all three states**, not two.
> 5. Bracket-schedule cross-tenant leak: tenant A reads only its own schedules; tenant B's are invisible in the helper's output.
> 6. Bracket-row monotonicity holds across replace-all replay under SERIALIZABLE.
> 7. `tax_jurisdiction` cross-tenant pen-test on SELF-267. ⚠ **Written against SELF-267's corrected signature** — `fn_ytd_paid_per_jurisdiction(p_as_of date, p_jurisdiction pfin.tax_jurisdiction_enum)`. The drafted leg pen-tested a `p_users_id` parameter that the corrected function does not have; a battery written against the drafted signature would be **testing the defect rather than the fix**.
> 8. ⚠ **The drafted wash-sale annotation leg is STRUCK.** It read *"tenant A cannot create / update / read tenant B's `pfin.transaction_annotation` row."* **No such table exists** — the tree has `pfin.account_trans_annotation` (`023`) — and no wash-sale column exists on it or anywhere else; the only `wash_sale` on the tree is a `basis_adjust` metadata **reason** (`030` / `034`), Suspense-routed at `035` P7. **⟨RULING: Seam G — whether V1 ships a user-marked wash-sale flag at all⟩.** If it does, this leg returns against the real table and column names; if it does not, it stays struck. ⚠ A leg written against a `to_regclass` existence guard would **skip silently** and report green — do not restore it in that form.
> 9. **Forward fence:** no `service_role` reach in any V1.4 surface; all execute under the `authenticated` tier per ARCH §4.1. ⚠ The drafted range *"SELF-259-266"* crosses a milestone boundary; scope this to the surfaces enumerated in AC 1.
> 10. Sec review pass with the verdict recorded, per the SELF-257 precedent. **Where Sec's §4 catch-criteria and this AC set overlap, Sec's text governs** — it is this battery's specification.
> 11. **Harness obligations, stated in the AC because each fails silently:**
>     - **Verify with `pg_prove`, never bare `psql`** — pgTAP's plan count enforces only through a TAP-aware consumer; `psql` exits 0 on a short plan.
>     - **`isnt()` PASSES on NULL** (`IS DISTINCT FROM`), so a negative isolation assertion over a subquery is **fail-open**. Use `ok()`; prove three states.
>     - **`set local` outside a transaction is a silent no-op** — the battery then runs as superuser and every leg passes. A control leg runs **first**.
>     - **Smoke at `current_date`** — freshly-seeded rows are invisible to a past as-of under [ADR-011](../../../DECISIONS.md#adr-011) Decision 19's `created_at` half, and an all-zero result is byte-identical to broken.
>     - **Rebuild the scratch DB before any full-suite claim** — `rollback` does not reset sequences, so a re-used scratch hides a whole failure class.
> 12. **V1.4 close-gate: no V1.4 issue closes to milestone until this battery passes.**
>
> **Sec joint-review:** mandatory. **Light loop: NO** — [ADR-066](../../../DECISIONS.md#adr-066) Decision 1 (c). ⚠ A test-only battery looks light — it adds no DB surface and computes no money — but (c) is decisive and this is the V1-SHIP-BLOCK close-gate.
>
> **Dependencies.** Upstream: every V1.4 surface, plus the four Platform V1.x issues.

---

## SELF-302 — GL follow-up: `basis_adjust` `wash_sale` P&L posting

> **Baseline: `origin/main` @ `2cd94ae`.**
>
> The issue text is accurate against the tree and needs no schema correction: `035`'s P7 routes a `wash_sale`-reason `basis_adjust` contra to **Suspense** with the comment *"P&L deferral not yet specified"*, and `037` names it as a Suspense-parked floor. **One AC is added.**
>
> **Added AC — this issue moves §2.5 figures, in two directions, and the drafted text does not say so.** Until it lands, a disallowed wash-sale loss is parked rather than added to the replacement lot's basis. That understates `cost_basis`, which **overstates** `unrealized_gl` at `049` and therefore **overstates** §2.5.4 Unrealized Tax Liability; and it leaves the disallowed loss unrecognized on §2.5.1's ST/LT columns, which **understates** taxable gain. **⟨RULING: Seam I — whether SELF-302/303 land before SELF-262, or SELF-262 lands first carrying a named residual⟩.** If the latter, the residual is recorded in SELF-262's migration header in the shape `093` uses for its own (*"Recorded so a reader does not conclude the case is handled"*) **and** in SELF-262's AC — a header alone is not read at the moment it matters.
>
> **Sec joint-review:** mandatory (money flow) — already stated in the issue. **Light loop: NO** — Decision 1 (a), (b) and (c).

---

## SELF-303 — GL follow-up: substantive `corp_action` GL (spin-off / cash-in-lieu)

> **Baseline: `origin/main` @ `2cd94ae`.**
>
> Accurate against the tree; book-neutral `corp_action`s already emit zero legs and substantive ones are Suspense-parked. The non-gating test-durability nit (a co-located aal2 pass/block assertion on the `037` battery, currently relying on `033`'s battery for the re-created `journal_insert` policy) is correctly marked non-blocking and is retained.
>
> **Added AC — this issue also moves §2.5 figures.** Spin-off basis allocation changes `cost_basis`, which feeds `fn_account_unrealized_gl` (`049`) and therefore §2.5.4's Unrealized line; cash-in-lieu is a realized disposition and therefore lands in §2.5.1's capital-gain columns. Same **⟨RULING: Seam I⟩** as SELF-302, and it must receive the **same** answer — two GL follow-ups sequenced differently against one helper is the drift this seam exists to prevent.
>
> **Sec joint-review:** mandatory (money flow) — already stated. **Light loop: NO** — Decision 1 (a), (b) and (c).

---

## Unresolved rulings referenced above, in one list

Every `⟨RULING⟩` placeholder in this file, so the sitting can discharge them without re-reading nine blocks. **Nothing here is Architect's to take.**

| Ruling | Blocks | Owner |
|---|---|---|
| **Seam A** — bracket-table storage grain (**one-way-door sub-part**: the child's parent FK is a Decision-3 evaluation) | SELF-259 → SELF-265, SELF-262 | F/CTO, Sec joint-review |
| **Seam E** — §2.1.5 NAV vs the checkpointed trajectory (**one-way door**) | SELF-268 AC 4 | F/CTO, Sec joint-review |
| **Seam G** — does V1 ship a user-marked wash-sale flag at all (PRD-vs-tree conflict) | SELF-264 AC 8, SELF-269 AC 8 | F/CTO + PM |
| **Seam I** — SELF-302/303 before SELF-262, or a named residual | SELF-302, SELF-303, SELF-262 | F/CTO |
| **SELF-263 re-scope** — Option A / B (C rejected on the tree) | SELF-263 | F/CTO |
| **Sec F-2** — unmatched sell's ST/LT disposition | SELF-264 AC 8, SELF-262 | F/CTO |
| **Sec F-3** — does Unrealized Tax Liability floor at zero | SELF-268 AC 6 | F/CTO |
| **Sec F-4** — the prior year's Q4 between Jan 1 and Jan 15 | SELF-267 AC 4(c), SELF-266 | F/CTO — ⚠ **one answer for both**, they are the same date boundary |
| **Sec F-5** — `tax_relevant DEFAULT false` | SELF-263 AC 6 | F/CTO |
| **Sec F-6(b) / §7.28 item 3** — owner and slot for the inventory session | SELF-263 | F/CTO — ⚠ discharged **by** the SELF-263 re-scope, not separately |
| **Sec F-7 + the SELF-259–262 milestone placement** — one reconciliation of the ledger against live Linear | the whole dispatch order | team-lead |
