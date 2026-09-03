# V1.4 (§2.5 Estimated taxes) — re-derived acceptance criteria

**What this file is.** Landing-ready replacement AC text, per issue, for the V1.4 pre-flight recalibration ([ADR-063](../../../DECISIONS.md#adr-063) Decision 1). Each block is written to be pasted into its Linear issue **as a whole**, replacing the drafted ACs. The analysis and evidence behind every change live in [`architect-findings.md`](architect-findings.md); this file carries the text, not the argument.

**Baseline, carried per block rather than in this header only.** Every block below self-carries `2cd94ae` — per [ADR-063](../../../DECISIONS.md#adr-063)'s Consequences, *"a document header does not travel into the artifact each block lands in."*

**Placeholders.** Where a block depends on a ruling not yet made, the dependency appears as **`⟨RULING: …⟩`** in the AC text itself. **Those are not to be resolved by the builder** — they are resolved at the sitting and the resolved text is what lands. A block containing an unresolved `⟨RULING⟩` is not dispatchable.

**PM's product wording — MERGED at round 2.** Folded from `origin/meta/v14-preflight-pm` @ `b462816`, `docs/records/v14-preflight/pm-findings.md`. PM-authored strings are credited ***(PM)*** inline. The three *"not available at authoring"* markers from round 1 are retired. **PM's wording governs on user-facing strings** (empty states, captions, footnotes, banner copy); **schema wording governs everywhere else**, as the V1.3 file did. **Conflicts are flagged explicitly rather than silently resolved** — there is one, at SELF-267 AC 2, and it is marked.

**Sec.** Cited by flag id (`M-n` / `F-n` from pass 1 @ `39bc549`; `D-n` from pass 2 @ `3eb0554`), `docs/records/v14-preflight/sec-findings.md`. **Cited, never restated** — a paraphrase of a Sec flag in an AC is a second copy that drifts.

⚠ **Round 2 changed the shape of two blocks beyond wording.** Seam **J** (§2.5.1's capital-gain columns have **no V1 input path** — no sale writer, no `lot_match` writer, both measured at zero) rewrites SELF-264's CG section and hollows out one SELF-269 leg. Seam **E-2** (PM's A-9, arithmetic verified against `051`) adds a NAV-exclusion clause to SELF-268 and SELF-267. Both are in [`architect-findings.md`](architect-findings.md).

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
> 3. Two sections: **Income** (cash-flow contributions, sourced from `pfin.posting_prototype`) and **Capital Gains** (realized-G/L contributions, sourced under the holding's asset Sub-Cat in `pfin.user_taxonomy`). ⚠ These are **two disjoint id spaces** — `posting_prototype.id` begins at `1000000000` (`084`), `user_taxonomy.id` at `1` — so the surface renders a **UNION discriminated by domain**, never a join on id. A join on id returns nothing and does so silently. Add PM's A-1 pointer to the page's basis note *(PM)*.
> 3a. ⚠ **The Capital Gains section renders UNAVAILABLE-with-a-reason, not zeros — ⟨RULING: Seam J / PM §6 item 1⟩.** Measured at `2cd94ae`: `088` rejects `p_quantity <= 0` (no sale writer), and `insert into pfin.lot_match` appears **zero times** in `supabase/migrations/` and **zero times** in `api/src`. There is no route by which a realized capital gain can exist, so both CG columns would otherwise render `0.00` for every Sub-Cat forever — indistinguishable from *"you realized no gains."* **The predicate is the STRUCTURAL fact (no sale-recording capability), never the row-count fact (`lot_match` empty this year)** — the row-count form silently becomes *"you had no gains"* the day the writer lands and a user has a quiet quarter. ADR-049 non-silence. Copy names the missing **capability**, not the milestone that will add it: milestone names move, capabilities do not. Under this ruling **§2.5.3's Federal LT-CG walk stays live** — it sums `qualified_dividend`-tagged Ordinary contributions, and `041` seeds `Revenue / Dividend` as exactly that.
> 3b. **Unclassified cash items are excluded LOUDLY, from the same query that sums** — the V1.3 S-2 ruling and the one-source predicate inside `fn_cashflow_items`; a second query for the count forfeits the property the extraction exists to deliver. ⚠ Copy **must not** claim the excluded items are income *(PM)*: *"N items unclassified — any may be income — classify"*.
> 4. Cat-grouped section headers with Sub-Cat detail rows beneath; total row foots the table; per-Cat-group subtotals as group aggregates (the §2.2.2 pattern).
> 5. Each row communicates its `tax_character` so schedule-routing intent is legible at a glance. ⚠ The vocabulary is `pfin.tax_character`'s **five seeded codes** (`011`), FK-enforced — not a client-side list, and not an enum type.
> 6. Live recompute as transactions land and as tax attributes change.
> 7. `tax_relevant = false` Sub-Cats are excluded from the table entirely. ⚠ Per Sec's **M-5**, the column carries a fail-**open** `DEFAULT false`, so an unmarked row and a deliberately-excluded row are indistinguishable here. Whatever SELF-263 AC 6 rules about that default, this surface **must not present exclusion as a determination** it cannot make.
> 8. **A realized sale with no resolvable holding period** renders per Sec's **M-1** (including its per-`lot_match`-row apportionment half, cited not restated) and the **F-2** ruling: **⟨RULING: F-2⟩** — PM's lean and mine agree on **ST / ordinary**, fail-closed on tax, with the row footnoted *"holding period unresolved — treated as short-term"* *(PM)*. ⚠ **Under Seam J this AC has no V1 instance** — there are no sells at all, matched or unmatched — so F-2 is a **V1.x** ruling owed before the sale writer ships, not a V1.4 blocker. Keep the AC; expect it to be unexercised.
> 9. **Empty states, two, and they are different conditions** *(PM)*. ⚠ The drafted *"Mark tax-relevant Sub-Cats… CTA to migration-time docs"* is wrong twice: no user can mark anything (taxonomy CRUD is V2+), and every provisioned user already carries seven `tax_relevant = true` Revenue rows from `041`, so that state is **unreachable**. (i) **Income section, reachable state**: *"no tax-relevant activity this tax year yet"*. (ii) **Capital Gains section**: the AC 3a capability banner. Neither offers a CTA to a route that does not exist.
> 10. No inline edit (V2+), per PRD §2.5.1 and [ADR-013](../../../DECISIONS.md#adr-013) P5.
> 11. **Hard-gate precondition on SELF-263** *(PM's consumer-side half of Seam H)*: this surface does not ship until SELF-263's inventory migration is on `main`, and the page names the seed-delta migration it was built against. ⚠ [ADR-062](../../../DECISIONS.md#adr-062) Decision 3's shape — *"a sequencing commitment, not a mechanism"* — which is why it lives in the **consumer's** AC and not only in the backlog entry. `tax_relevant = false` is never read as an answered question (Sec **M-5**).
> 12. **Wash-sale treatment per ⟨RULING: Seam W / Seam G⟩.** Under PM's (A) this surface ships none and says nothing about it; under (B) it consumes the `basis_adjust` route. Do not build a flag.
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
> 7. **First visit is pre-populated from SELF-260's seed, and the seed is presented as a TEMPLATE, not a determination** *(PM's A-6 / AC7′)*. The seeded set **states its filing-status assumption in its label** and the user revises it; the editor shows which **`tax_year`** each schedule is for (Decision 18's `tax_year SMALLINT` from day one). ⚠ PRD §2.5.2's (ι) text scopes the standard deduction to *"the F/CTO's current filing status (fixed at V1 seed time)"* — founding-user framing that does not survive general multi-user software; PM's replacement wording is the product fix and this AC is its consumer.
> 7a. **UNSET is rendered, never coalesced to zero** *(PM, from Sec **M-11**)*. A jurisdiction with no schedule for the current tax year makes §2.5.3 render **UNAVAILABLE-with-a-reason** — *"No Federal schedule entered for 2026 — enter it in Settings"* — and never `$0`. The **standard-deduction scalar is nullable-until-set under the same rule**: a missing deduction coalesced to `0` silently overstates taxable income and therefore the tax owed. ⚠ At Jan 1 the prior year's schedule is **not inherited** (bracket inheritance stays V2+); the CTA is the mechanism that gets the new year entered, so it is load-bearing rather than a courtesy.
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
> 8. **Empty states**, two, distinct conditions: (i) **no bracket schedule for the current tax year** → the AC-7a UNAVAILABLE line with a CTA to `/settings/tax-brackets`; (ii) **no account carries a `tax_jurisdiction` value** → a one-line explanation whose CTA lands on **the §2.4.2 form's tax-authority field** *(PM)*, not on generic onboarding. ⚠ The second condition is *"no account is marked as a tax authority"*, **not** *"no account is named IRS"* — the marking is `pfin.account.tax_jurisdiction`, per F/CTO Gate B Option A (`CHANGELOG.md` Wave 5 / PR #92) and SELF-267.
> 8a. **No as-of toggle on this or any §2.5 surface** *(PM)*. Lock 15's client-toggle allowance is §2.3.3's alone; every §2.5 surface reads server-derived today (Seam C). ⚠ Stated as an AC so nobody adds one as an obvious convenience.
> 8b. **Rounding and the Q4 residual are specified, not left to the renderer** — Sec **M-8**: annual ÷ 4 does not reconcile to the annual liability, so the AC must say which quarter carries the remainder and at what precision. The obligation is SELF-262's; this surface must not silently absorb a cent-level mismatch into a rendered total. CA weighting stays ÷4 *(PM's A-11)*.
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
> 2. `tax_jurisdiction pfin.tax_jurisdiction_enum null` added to `pfin.account`, with a `comment on column` stating that a NULL means *"not a tax-authority ledger"* and **not** *"unknown"*. **The user sets the designation on the §2.4.2 form at creation or edit** *(PM's D-9 correction — the drafted "F/CTO populates … at creation" is founding-user framing that does not survive general multi-user software)*.
>
>    ⚠ **FLAGGED CONFLICT — schema wording governs.** PM writes this column `tax_authority`; the Gate B ratify at `CHANGELOG.md`:1550 and this issue both write **`tax_jurisdiction`**. **The column is `tax_jurisdiction`.** *"Tax authority"* is the better **product** phrase and PM's user-facing copy keeps it — the two need not match, but the schema name must be single, and two names across two pre-flight artifacts is how a migration and its consumer diverge.
>
>    ⚠ **The write path is an UPDATE, not a new creation parameter.** The live `fn_create_manual_account` body is **`087`** (`013` → `048` → `087`; `013` still names the `sub_cat_id` that `048` dropped), and adding a parameter is a **signature change** that breaks other files' `regprocedure` assertions. Set the designation by a subsequent `UPDATE` under the ordinary `authenticated` policy, as every other editable account attribute is set. The form may still present the field.
> 2a. **Tax-authority-designated accounts are EXCLUDED from §2.1.5's composition buildup** — PM's **A-9**, arithmetic verified against `051` at [`architect-findings.md`](architect-findings.md) Seam E-2. `tax_jurisdiction is not null` is the exclusion predicate and the designation is its only hook. ⚠ **This clause is ruled TOGETHER with Seam E and cannot be taken alone**: `051` asserts `nav = Σ 049(active) = fn_compute_nav`, and dropping accounts from its leaf set breaks that identity — which is Seam E's one-way door reached from a second direction. ⚠ It is also **not a live defect until SELF-268 flips the tax lines**; the double-count is *created* by that flip, so it cannot be deferred past it as pre-existing.
> 3. ⚠ **A partial unique index prevents two accounts claiming the same jurisdiction per user** — `unique (users_id, tax_jurisdiction) where tax_jurisdiction is not null`. Without it, AC 4's primitive silently sums two ledgers and the result is well-formed and wrong. *(Raised by Sec under F-1 option (C); it survives the Gate B ruling unchanged.)*
> 4. **`pfin.fn_ytd_paid_per_jurisdiction(p_as_of date, p_jurisdiction pfin.tax_jurisdiction_enum) returns numeric`** — `security invoker`, `stable`, `set search_path = ''`. ⚠ **Three corrections against the drafted signature, each of which is invisible in the output:**
>    - **(a) No `p_users_id` parameter — Sec's D-2, its sharpest pass-2 finding, reached independently and cited not restated.** No shipped `pfin` reader takes a tenant parameter — `fn_cashflow_items(date)`, `fn_account_cash_as_of(date)`, `fn_account_unrealized_gl(date)`, `fn_nav_composition(date)` all derive the tenant from `auth.uid()` through RLS. A client-supplied tenant on a SECURITY INVOKER function is either **ignored** — a lie in the signature — or **used in the predicate**, which is an ownership-forge vector. The drafted AC 6 (*"RLS enforced under SECURITY INVOKER composition"*) and the drafted AC 3 contradicted each other; this resolves it toward AC 6.
>    - **(b) `p_jurisdiction` is the enum type, not `text`.** The drafted ACs created an enum and then declared the parameter `TEXT` — a type mismatch inside one issue.
>    - **(c) No `p_through_quarter` parameter, and no quarter grammar.** The figure is a **balance as of a date**, `fn_account_cash_as_of`-shaped, which is what the PRD text this issue quotes actually specifies (*"the cumulative balance of these account ledgers"*). ⚠ **The drafted quarter-ordinal form drops the Federal Q4 payment every year**: Q4 for tax year *Y* is due **Jan 15 of Y+1**, so it falls outside every calendar-quarter flag of *Y* — including `pfin.fn_cashflow_items`' `in_q4`, whose bounds run Oct 1 – Dec 31 (`093`). A balance read never meets this. Sec's **M-4** reaches the same date boundary from the tax-year-scope side; **⟨RULING: F-4 — what §2.5.3 shows for the prior year's outstanding Q4 between Jan 1 and Jan 15⟩** settles both, and this AC and Sec's F-4 must receive the **same** answer.
> 5. The primitive reads `pfin.account_trans` only through accounts whose `tax_jurisdiction` matches, composing under RLS on `pfin.account`. **No `service_role` reach.**
> 5a. **The source predicate is stated explicitly, because "which rows count as a payment" is otherwise invented at build time** *(PM, answering Sec's catch 2)*: *"YTD Paid = the designated ledger's cash balance as-of today (`056` shape); every `standard` cash row on that ledger counts — a refund recorded as a negative payment reduces it; there is no per-row 'is payment' flag."* ⚠ In particular it is **not** `is_tax_payment`, which [ADR-062](../../../DECISIONS.md#adr-062) scopes to **Expense**-class prototypes while the seeded tax buckets (`041`) are **Transfer**-class — the flag cannot reach them, and a `false` there reads as an answered question (Sec **M-6**).
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
> 3a. **Tax-authority-designated accounts are excluded from the buildup's leaf set** — PM's **A-9** / Seam **E-2**, arithmetic verified against `051`. Without it, each payment moves NAV by **+P** for money that is gone: the cash lands in a counted ledger account while the obligation falls by the same amount. ⚠ Ruled **with** AC 4, never separately — the exclusion breaks the `nav = Σ 049(active) = fn_compute_nav` identity `051` asserts, and that is AC 4's door.
> 4. **⟨RULING: Seam E — the relationship between §2.1.5's NAV and the checkpointed trajectory⟩.** ⚠ Sec's **D-4** calls the drafted AC *"veto-shaped if taken literally"* and reaches this from the write-refusal side; PM independently flags the drafted **AC 1** as putting the tax leg **into `fn_compute_nav`** and therefore into `nav_daily` — the same door through a third route. **Feasibility answered (PM's A′):** `051` can compose `fn_compute_nav`'s gross value with `fn_compute_tax_liability`'s two scalars **at read time**, leaving `fn_compute_nav`'s body and `nav_daily` untouched — Lock 11 read-composition doing what it is for. Two riders if that shape is ruled: the AC-3a exclusion then makes `051`'s Gross deliberately differ from `fn_compute_nav`'s, **which must be stated in `051`'s `comment on function`, since the current comment asserts the identity it breaks**; and both functions must be called with **one** `fn_server_today()` value in the same request or the foot reconciles to nothing. The drafted AC read *"SELF-226 NAV trajectory consumes flipped Tax Liab values; historical NAV recompute back-fills correctly."* **That cannot be built.** `pfin.nav_daily` (`054`) is **append-only audit-class** under [ADR-011](../../../DECISIONS.md#adr-011) Decision 2, carries `nav_value numeric not null`, and has **no definition-version column**; a back-fill is a rewrite of an audit surface, and the tax state for a past date is not recoverable, so back-filled values would be a fabrication with the shape of a measurement. The ruled options are recorded in [`architect-findings.md`](architect-findings.md) Seam E — keep the trajectory pre-tax permanently and say so · add a definition discriminator and branch every trajectory reader · back-fill (rejected). **The resolved text replaces this AC; the builder does not choose.**
> 5. **A single combined Federal + California value per row** (ρ lock) — one Realized row, one Unrealized row, not four.
> 6. **⟨RULING: F-3 — does Unrealized Tax Liability floor at zero?⟩** Per Sec's **M-2**: a negative aggregate unrealized G/L yields a negative Unrealized Tax Liability, and `051` **subtracts** it — so **NAV rises on an unrealized loss**. This is arithmetic, not rendering, and the AC cannot be written until it is ruled.
> 7. **Sign convention verified end to end** per Sec's **M-3**. ⚠ `debt` is currently the ladder's **only** sign flip (`051` emits a positive magnitude, `nav-composition.ts` negates it). Adding two more subtractions must not make it three flips or none — the double-negation route Sec names is exactly how a correct value renders with the wrong sign.
> 8. **The (π) tax-advantaged exclusion is applied to the Unrealized aggregation** — `tax_treatment = 'taxable'` only. ⚠ `pfin.fn_account_unrealized_gl` (`049`) carries **no such filter** at this baseline; `pfin.account.tax_treatment` is `not null` with a three-value CHECK (`003`), so the filter is total with no NULL case. Where the filter lives is [`architect-findings.md`](architect-findings.md) Seam F; the **recommendation is the §2.5.4 composer, not a signature change on `049`**, because `049`'s signature is asserted by other files' catalog legs.
> 9. **Live recompute** on bracket edits, decomposition changes, market-value refresh, and manual-entry edits.
> 9a. **The §2.5.4 user-facing disclaimer gets a rendering home** *(PM's §6 item 7(ii); Sec-endorsed at App B (p))* — PRD's *"treat the Unrealized Tax Liability as an LT-aware floor estimate, not a precise tax forecast"* currently has no AC anywhere. It lands as a footnote or tooltip on the §2.1.5 Unrealized row. ⚠ It must be **readable without hover** on the same grounds §2.4.4 requires of its informational marker: the surface is a dense right-aligned numeric cell that has to survive PDF export, print, and assistive technology.
> 9b. **`051`'s `-- Option A V1.1 (AC#5); V1.4 ramp` comments and its `comment on function` are updated in the SAME migration** *(Sec catch 4)*. A comment that still says *"V1.4 ramp"* after V1.4 ramped is the falsified-premise class this repo has booked twice.
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
> 4. **Three-attribute orthogonality at §2.5.4's (π) exclusion**: `tax_deferred` and `tax_free` accounts filtered out of the Unrealized aggregate, `taxable` included. ⚠ **This leg is the only watcher the exclusion will have**, since `049` carries no filter of its own (Seam F). `tax_treatment` is `not null` with three CHECKed values, so **assert all three states**, not two. ⚠ **The fixture literals are `tax_deferred` / `tax_free` with UNDERSCORES** (Sec **D-5**): PRD writes them hyphenated, `003`'s CHECK does not, and a fixture seeding the PRD spelling is rejected by the CHECK — **which reads as a passing fence rather than a broken fixture.**
> 4a. **A fourth attribute now shares this leg: `tax_jurisdiction`.** Assert that a designated ledger is excluded from the §2.1.5 buildup (AC 3a of SELF-268) and that a NULL-designation account is not — the only watcher Seam E-2's exclusion will have.
> 5. Bracket-schedule cross-tenant leak: tenant A reads only its own schedules; tenant B's are invisible in the helper's output.
> 6. **Bracket-row monotonicity holds across replace-all replay.** ⚠ **The drafted parenthetical *"(SERIALIZABLE replace-all guarantees integrity)"* is STRUCK** (Sec **D-5**). SERIALIZABLE guarantees only that concurrent transactions are equivalent to *some* serial order; it says **nothing** about whether a single transaction leaves the rows monotone — that is the trigger's job, and per Sec §3 trap 1 a BEFORE-ROW trigger cannot see rows inserted later in the same statement. The parenthetical would let a reviewer accept SERIALIZABLE **in place of** the monotonicity check, which is the one substitution that must not be available.
> 7. `tax_jurisdiction` cross-tenant pen-test on SELF-267. ⚠ **Written against SELF-267's corrected signature** — `fn_ytd_paid_per_jurisdiction(p_as_of date, p_jurisdiction pfin.tax_jurisdiction_enum)`. The drafted leg pen-tested a `p_users_id` parameter that the corrected function does not have; a battery written against the drafted signature would be **testing the defect rather than the fix**.
> 8. ⚠ **The drafted wash-sale annotation leg is STRUCK.** It read *"tenant A cannot create / update / read tenant B's `pfin.transaction_annotation` row."* **No such table exists** — the tree has `pfin.account_trans_annotation` (`023`) — and no wash-sale column exists on it or anywhere else; the only `wash_sale` on the tree is a `basis_adjust` metadata **reason** (`030` / `034`), Suspense-routed at `035` P7. **⟨RULING: Seam G — whether V1 ships a user-marked wash-sale flag at all⟩.** If it does, this leg returns against the real table and column names; if it does not, it stays struck. ⚠ A leg written against a `to_regclass` existence guard would **skip silently** and report green — do not restore it in that form.
> 8a. ⚠ **A capital-gains isolation leg over an empty set is VACUOUS and must be marked as such.** Per Seam **J**, no `lot_match` row can exist in V1 (no sale writer; zero `insert into pfin.lot_match` sites anywhere). A leg asserting *"tenant A cannot see tenant B's realized gains"* would pass on both tenants having none. **Either** assert the structural fact (the CG surface renders UNAVAILABLE for both tenants, per SELF-264 AC 3a) **or** state in the battery header that the leg is deferred to the sale-writer milestone. **What must not happen is a green leg that reads as isolation evidence** — the pgTAP `isnt()`-on-NULL and the vacuous-harness classes are both this shape.
> 9. **Forward fence:** no `service_role` reach in any V1.4 surface; all execute under the `authenticated` tier per ARCH §4.1. ⚠ The drafted range *"SELF-259-266"* crosses a milestone boundary; scope this to the surfaces enumerated in AC 1. Sec's **D-5** marks the AC-9 sentence itself as correct and worth keeping verbatim — it matches ADR-016's allowlist staying flat and **it is a leg that can fail**, which is the property most of a battery's legs need and few have.
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
| **Seam J** — §2.5.1's two capital-gain columns have **no V1 input path** (no sale writer, no `lot_match` writer; both measured at zero). **The largest ruling of the pass — a milestone-shape question, not an AC fix.** PM's §6 item 1; PM and Architect both lean (A) render UNAVAILABLE | SELF-264 AC 3a + AC 8, SELF-266, SELF-269 AC 8a, Sec F-2 | F/CTO + PM |
| **Seam A** — bracket-table storage grain (**one-way-door sub-part**: the child's parent FK is a Decision-3 evaluation) | SELF-259 → SELF-265, SELF-262 | F/CTO, Sec joint-review |
| **Seam E + E-2** — §2.1.5 NAV vs the checkpointed trajectory (**one-way door**), **ruled together with** the tax-authority NAV exclusion; Sec **D-4** and PM's **A-9** reach it from two further directions | SELF-268 AC 3a + AC 4, SELF-267 AC 2a | F/CTO, Sec joint-review |
| **Seam W / G** — does V1 ship a user-marked wash-sale flag at all (PRD-vs-tree conflict). ⚠ Seam J makes PM's (A) nearly free — there is no sale to mark | SELF-264 AC 12, SELF-269 AC 8, SELF-302's placement | F/CTO + PM |
| **SELF-302 / SELF-303 placement** — PM recommends **moving both to Platform / Cross-cutting V1.x** (neither traces to a §2.5 story; both arrived by the `037` deferral note). Interacts with Seam W: under W(B), SELF-302 becomes §2.5.1 fuel and returns | SELF-302, SELF-303, the dispatch order | F/CTO |
| **Seam I** — SELF-302/303 before SELF-262, or a named residual | SELF-302, SELF-303, SELF-262 | F/CTO |
| **SELF-263 re-scope** — Option A / B (C rejected on the tree) | SELF-263 | F/CTO |
| **Sec F-2** — unmatched sell's ST/LT disposition | SELF-264 AC 8, SELF-262 | F/CTO |
| **Sec F-3** — does Unrealized Tax Liability floor at zero | SELF-268 AC 6 | F/CTO |
| **Sec F-4** — the prior year's Q4 between Jan 1 and Jan 15 | SELF-267 AC 4(c), SELF-266 | F/CTO — ⚠ **one answer for both**, they are the same date boundary |
| **Sec F-5** — `tax_relevant DEFAULT false` | SELF-263 AC 6 | F/CTO |
| **Sec F-6(b) / §7.28 item 3** — owner and slot for the inventory session | SELF-263 | F/CTO — ⚠ discharged **by** the SELF-263 re-scope, not separately |
| **Sec F-7 + the SELF-259–262 milestone placement** — one reconciliation of the ledger against live Linear | the whole dispatch order | team-lead |

---
---

# Part B — the four Platform / Cross-cutting V1.x dependency issues

**Source.** `temp/v14-preflight/issue-dump-deps.md`, md5 `c35fe5ef96caa6b647655cb39a0bfea1`. Analysis at [`architect-findings.md`](architect-findings.md) §7. Promotion recommendation at §5a. Baseline unchanged.

---

## SELF-259 — `tax_bracket_schedule` + `tax_bracket_row` migration + replace-all endpoint

> **Baseline: `origin/main` @ `2cd94ae`.**
>
> **⚠ This issue carries the Seam A grain ruling and the milestone's only Decision-3 family extension.** The ACs below are written for the drafted **Option A** grain (child references parent, no `users_id` on the child). If the sitting rules **Option C** (child carries its own `users_id` alongside `schedule_id`), ACs 2, 3 and 4 change together — the fence becomes the 012-shape **P1 local-anchor** pattern and the row policy becomes a direct equality instead of a JOIN. **⟨RULING: Seam A grain⟩.**
>
> **Acceptance criteria**
>
> 1. **`pfin.tax_bracket_schedule`** — `id bigint generated always as identity primary key`, `users_id uuid not null default auth.uid() references auth.users (id) on delete cascade`, `tax_year smallint not null`, `schedule_type pfin.tax_schedule_type_enum not null` (`federal_ordinary` / `federal_lt_cg` / `california_ordinary`), `standard_deduction numeric not null`, `tax_balance_prior_year numeric null`, `created_at`, `updated_at`, `unique (users_id, tax_year, schedule_type)`.
>    ⚠ **`bigint … identity`, not `SERIAL`** — the repo idiom on every table (`003` `004` `074` `090`); `SERIAL` leaves an owned sequence with different `ALTER` semantics and `INT` caps the surface at 2³¹ for no reason.
>    ⚠ **`standard_deduction` stays NOT NULL, and the reason goes in the header** so a later reader does not "fix" it: under replace-all a schedule and its rows are written as one unit, so **the unset state is the ABSENCE of the row**, not a NULL inside it. That is what makes PM's *"never coalesce to 0"* (Sec **M-11**) enforceable at the reader rather than a convention.
>    ⚠ **`tax_balance_prior_year` is NEW** — PRD §2.5.3's informational Tax Balance Prior Year row had no home in any issue *(PM §6 item 7(iv); placement confirmed by Architect)*. Per-jurisdiction, per-`tax_year`, entered at rollover on the brackets' cadence, rendered `—` when unset. **`comment on column` states it is informational only under the μ-2 lock and MUST NOT enter the computation** — a nullable numeric beside the standard deduction is one `coalesce` away from being summed.
> 2. **`pfin.tax_bracket_row`** — `id bigint generated always as identity primary key`, `schedule_id bigint not null references pfin.tax_bracket_schedule (id) on delete cascade`, `bracket_floor numeric not null`, `bracket_rate numeric not null`, `created_at`, `unique (schedule_id, bracket_floor)`.
>    ⚠ **Both numerics carry the `090` finiteness idiom**: `check (… >= 0 and … <> 'NaN'::numeric)`. A one-sided `>= 0` CHECK **admits `NaN`** (Sec **M-10**), and `NaN >= 0` is false so the row is *rejected* — but the inverse form used elsewhere is not, which is why the idiom is copied rather than re-derived.
>    ⚠ **`bracket_rate`'s UNIT is stated in its column comment** — percent (`24`) or fraction (`0.24`), never inferred from the seed. Sec **M-7** additionally asks for the bound; `<= 100` or `<= 1` follows from the unit chosen.
> 3. **RLS**: schedule — `users_id = auth.uid()` in USING and WITH CHECK; row — via JOIN to its schedule. `authenticated` SELECT/INSERT/UPDATE/DELETE as the replace-all path requires; `anon` zero-grant; `service_role` ungranted.
> 4. **Matched-tenant validation on `tax_bracket_row.schedule_id`** per [ADR-011](../../../DECISIONS.md#adr-011) Decision 3 — the referenced schedule's `users_id` must match the writer's tenant. ⚠ **The drafted *"(4th instance)"* is STRUCK.** Read Decision 3 live: the canonical family is a **non-contiguous labeled set**, and the operational running tallies it supersedes are named in the Decision itself. **The label is allocated AT THE MIGRATION, never drafted in advance** — Decision 18's amendment is explicit on this, having paid for a pre-drafted label once already. Keep the obligation, drop the ordinal. Fence class follows the Seam A grain: a parent lookup under Option A, the 012-shape P1 local anchor under Option C.
> 5. **Bracket-row monotonicity, enforced in a form that CAN observe the property.** ⚠ **The drafted BEFORE-ROW shape cannot fire correctly** (Sec §3 trap 1): a BEFORE ROW trigger cannot see rows inserted later in the same statement, and replace-all writes the whole set in one multi-row INSERT — so a per-row trigger validates each row against an incomplete set and **passes a non-monotone batch**. Use a **`CONSTRAINT TRIGGER … AFTER INSERT OR UPDATE … DEFERRABLE INITIALLY DEFERRED`** (or a statement-level AFTER check) so it evaluates once the set exists. ⚠ **This is a fence written in a form that cannot observe the property it names** — the inverse of the usual by-construction-property problem, and worse, because it reads to a reviewer as a live guarantee.
> 6. **Replace-all endpoint** at `/api/settings/tax-brackets/{schedule_id}` under SERIALIZABLE isolation. ⚠ **SERIALIZABLE and the monotonicity check are INDEPENDENT controls and neither substitutes for the other** (Sec **D-5**): SERIALIZABLE guarantees only equivalence to *some* serial order and says nothing about whether one transaction leaves the rows monotone. ⚠ Also an **app surface inside a `role:migration` issue** — split it or label it, so the migration's Sec review is not diluted by an endpoint review.
> 7. `pfin.fn_refresh_updated_at()` reuse (SELF-232). ✓
> 8. ⚠ **The `025` aal2 step-up backstop clause on BOTH tables' `authenticated` policies.** New sensitive tenant-owned `pfin` tables; **no documented `025` exclusion applies** — `pfin.user_settings` is `025`'s NON-NEGOTIABLE exclusion for policy-recursion reasons that **do not generalize to siblings**. Named in an AC because it is invisible once omitted.
> 9. `set search_path = ''` on every function this migration creates; `revoke execute … from public` before any grant.
> 10. **Sec joint-review mandatory** — Lock 14 surface, a Decision-3 family extension, and financial-calculation inputs.
> 11. **QA:** two-tenant pgTAP in the same PR, including a leg asserting a **non-monotone multi-row batch is rejected** — the leg that would have caught AC 5's original shape — and a leg proving the matched-tenant fence rejects a foreign `schedule_id`.
>
> **Light loop: NO** — [ADR-066](../../../DECISIONS.md#adr-066) Decision 1 (a), (b) and (c).

---

## SELF-260 — Federal + California bracket + standard-deduction seed

> **Baseline: `origin/main` @ `2cd94ae`.**
>
> **Acceptance criteria**
>
> 1. Three schedules seeded for the current tax year: `federal_ordinary`, `federal_lt_cg`, `california_ordinary`. ⚠ `federal_lt_cg` carries `standard_deduction = 0` per PRD §2.5.3's *"no standard deduction applied to this schedule"* — and the seed comment records that this `0` means **"this schedule takes no deduction"**, not **"not yet entered"**. It is the one place a literal zero is the right answer, and distinguishing it is what keeps AC 1's absence-is-unset rule readable.
> 2. Per-schedule rows per the current-year IRS and CA FTB published brackets.
> 3. Monotonicity verified on seed insert. ⚠ **This is the first exercise of SELF-259's trigger**, and a whole schedule's rows arrive in one statement — which is exactly the case the drafted BEFORE-ROW shape would have passed incorrectly. Treat a green here as evidence only if 259 shipped the deferred form.
> 4. Smoke test: the seeded schedules are readable by their owner and consumed correctly by SELF-262 for a representative income scenario.
> 5. ⚠ **Sec joint-review — NOT "advisory".** The drafted AC reads *"no Sec joint-review required — data-only against Issue 1 schema."* **Bracket rates and standard deductions are financial-calculation inputs**; every dollar §2.5.3 and §2.5.4 render is a function of them, and *financial calculations* is on the ratified joint-review-mandatory map. *"Data-only"* describes the **change shape**, not the **surface**, and the standing rule is that the trigger is the surface, not the author's assessment of risk.
> 6. **The seeded set is a TEMPLATE that states its filing-status assumption in its label** *(PM's A-6)*, which the user revises. ⚠ The drafted *"fixed-at-seed-time per F/CTO's filing status"* is founding-user framing that does not survive general multi-user software.
> 7. ⚠ **Reach:** a seed change reaches already-provisioned users only by explicit backfill ([ADR-057](../../../DECISIONS.md#adr-057), as generalized at [ADR-062](../../../DECISIONS.md#adr-062) Decision 5). State the reach decision in the header — a bracket seed that silently reaches nobody who already exists is the `077` case again.
>
> **Light loop: NO** — Decision 1 (a) and (b).

---

## SELF-261 — `transaction_annotation` table for the wash-sale flag

> **Baseline: `origin/main` @ `2cd94ae`.**
>
> **⚠ NO REPLACEMENT AC SET IS OFFERED. This issue should be held, and most likely closed rather than built.** Three independent blockers, any one of which is sufficient; analysis at [`architect-findings.md`](architect-findings.md) §7.
>
> 1. **Its design rationale is already implemented.** The stated Architect design call — *"separate annotation table (NOT column on `account_trans`) per Lock 10 immutability semantics"* — **is `pfin.account_trans_annotation` (`023`)**: a separate table keyed 1:1 by `trans_id`, carrying mutable meta-information beside the immutable ledger, for exactly that reason. Building a second one gives one immutable ledger two annotation tables, which is the outcome Lock 10's discipline exists to prevent.
> 2. **The identifiers are false.** `REFERENCES pfin.account_trans(id)` — the PK is **`trans_id bigint`** (`004`). And *"RLS WITH CHECK `users_id = auth.uid()` on annotation row"* does not describe the shipped shape: **`account_trans_annotation` carries no `users_id`**, inheriting tenancy through its `trans_id` FK. The *"(5th instance)"* D3 ordinal is the same stale tally struck at SELF-259 AC 4.
> 3. **⟨RULING: Seam W⟩ may retire it.** Under PM's (A) V1 ships no wash-sale mark at all; under (B) the mechanism is a `basis_adjust` reason, not an annotation column. Only (C) needs this issue, and **both PM and Architect reject (C)** — Seam J establishes there is no sale row to annotate.
>
> **Disposition: hold pending Seam W; on (A) or (B), close with the rationale recorded** — the "separate table beside the immutable ledger" reasoning is correct and is worth preserving as the account of why `023` has the shape it has. ⚠ **If a wash-sale mark is ever wanted, the amendment is COLUMNS ON `account_trans_annotation`, not a second table.**
>
> **Keep in Platform / Cross-cutting V1.x** — do not promote an issue whose likely outcome is closure onto the milestone's critical path.

---

## SELF-262 — `fn_compute_tax_liability` unified SECURITY INVOKER helper

> **Baseline: `origin/main` @ `2cd94ae`.**
>
> **The signature is ADOPTED AS DRAFTED and is the single authored copy** — `pfin.fn_compute_tax_liability(p_data_as_of date default current_date) returns jsonb`, SECURITY INVOKER. It matches `051`'s shape exactly (scalar JSONB, `default current_date`), which is what makes it composable, and the Lock 15 `p_data_as_of` parameter is the correct V1.5 cron forward-compat. **SELF-264 / 266 / 268 resolve their provisional citations against this line and nowhere else.**
>
> **Acceptance criteria**
>
> 1. SECURITY INVOKER; RLS preserved at the JWT-user-session layer across `posting_prototype`, `user_taxonomy`, `tax_bracket_schedule`, `tax_bracket_row`, `account_trans`, `account`. ⚠ **Two names are STRUCK from the drafted composition list**: `transaction_annotation` (does not exist — SELF-261), and **`nav_daily`** (§2.5.4's Unrealized reads current market value and cost basis through `049`, **not** the checkpointed series; pointing a live tax figure at the append-only NAV history is exactly the coupling Seam E exists to avoid).
> 2. **§2.5.1 decomposition** — filter `tax_relevant = true`; ST/LT by holding period from `lot_match` joined twice to `account_trans` (> 365 days → LT); §1256 60/40 on the `Volatility-60/40` Sub-Cat. ⚠ **Under Seam J these clauses have no rows to run on** — no sale writer, zero `lot_match` writers — so they ship correct and unexercised, and the surface renders the CG section UNAVAILABLE (SELF-264 AC 3a) rather than zeros. Wash-sale gates on **⟨RULING: Seam W⟩**.
> 3. **§2.5.2 routing**, PRD-verbatim. ✓ The vocabulary is `011`'s five seeded codes, FK-enforced.
> 4. **§2.5.3 computation**, PRD-verbatim 6-step Federal / 3-step CA; annual ÷ 4 per μ-2. ⚠ **Name the quarter that carries the ÷4 remainder and the rounding precision** (Sec **M-8** — the split does not reconcile to the annual liability). ⚠ **Floor taxable income at zero** or state why not — the standard deduction can drive it negative and nothing floors it today (Sec **M-9**). ⚠ **A jurisdiction with no schedule for the tax year returns UNAVAILABLE, never zeros** (Sec **M-11**).
> 5. **§2.5.4 Realized** — the two Estimated Funds Due gaps summed, single combined value per (ρ); (ν-1) overpayment-as-negative supported. Consumes SELF-267's **balance-as-of** primitive (Seam B), not a quarter-ordinal one.
> 6. **§2.5.4 Unrealized** per the ο-a formula. **(π) exclusion applied at the query layer** — this **is** Seam F Option B and is the recommendation. ⚠ **Add the extract-on-second-consumer rule to this AC**: the moment a second surface wants the taxable-only aggregate, the predicate is extracted rather than copied. ⚠ **⟨RULING: Sec F-3 — does Unrealized floor at zero?⟩** — a negative value makes `051` **add** to NAV.
> 7. `p_data_as_of` per Lock 15. ✓ ⚠ One `fn_server_today()` value is threaded per request and shared with `fn_compute_nav` (Seam C), or the §2.1.5 foot reconciles to nothing.
> 8. **Sec joint-review mandatory.** ✓
> 9. **Parity test coverage** across the representative scenarios. ⚠ **Parity evidence keeps structure and percentages and REDACTS concrete dollar figures** — a committed fixture carrying the founding user's real tax numbers is the thing this rule exists to prevent.
> 10. **ADR drafted** — and it is the right home for **two** ADR debts at once: **Gate A Option B** (this helper's unified shape) and **Gate B Option A** (`tax_jurisdiction`, SELF-267), both of which currently live only in `CHANGELOG.md` and Linear descriptions.
> 11. ⚠ **Owed and absent from every drafted AC:** the **EXECUTE ACL pair** — `revoke execute on function … from public; grant execute … to authenticated` — which every shipped reader carries; **`set search_path = ''`**; and an **explicit volatility declaration** (`051` and `049` carry none and default VOLATILE, `093` is `stable` — choose deliberately, and note a `stable` caller of a `volatile` callee is an unbacked promise).
> 12. **Its role in Seam E** — whether this helper's two scalars compose into `051`'s foot at read time (PM's A′, which Architect confirms is feasible with `fn_compute_nav` untouched) — is **⟨RULING: Seam E⟩** and lands in this AC once ruled.
>
> **Light loop: NO** — Decision 1 (a), (b) and (c). **This is the milestone's keystone.**
