# SELF-262 — Security joint-review of `104_fn_compute_tax_liability.sql` + ADR-067

**Reviewer:** security-engineer · **Date:** 2026-09-04 · **Anchor:** `origin/feature/self-262` @ `982ae4a`
**Gate:** joint-review MANDATORY — financial calculation + money figures + multi-tenant read composition.

## VERDICT — **AMBER**

Cross-tenant isolation, the posture pair, the DEFINER allowlist, the §10 ledger, the Decision-3
family, Lock 11 and Lock 15 are all **clean and measured**. Three items block, each cheap:

| id | blocking condition | clears |
|---|---|---|
| **F-1** | `schedules.federal_lt_cg.current_year_schedule_empty` is computed for only one of the two no-fallback cases. Mirror the ordinary leg's `_empty_no_fallback` correction onto the LT CG leg, + one QA leg. | Architect (code) + QA (leg) |
| **F-2** | PRD §2.5.3's *"no standard deduction applied to this schedule"* is realized by a **seed value**, not by construction, and the value is user-editable. Record the disposition (fence or accepted-with-reason). | Architect, or F/CTO if the answer is "accepted" |
| **F-3** | `quarters_elapsed` is read as *due dates on or before as-of*; I read PRD §2.5.3's purpose sentence differently, and the shipped reading is the smaller of the two for most of the year. Confirm or correct the reading. | PM (spec), then Architect if it moves |

**Evidence base.** Fresh scratch database `secscratch262`, built by sequential apply
`001` → `104` with `ON_ERROR_STOP=1`, zero failures. New database name; not `pfin_tmpl`; no
destructive local-stack command was used at any point. Two synthetic tenants A/B provisioned
through the shipped `fn_provision_tax_brackets()`.
⚠ **This is a schema/data-level control only** — it exercises Postgres roles and RLS, not the
HTTP session layer, and it says nothing about how the app derives or bounds `p_data_as_of`.

---

## Verify-hook — canonical anchors read verbatim and live from `DECISIONS.md` on this branch

- **ADR-011 Decision 4 (§10).** Read verbatim. Catalogued list is **RT-22 first** (infrastructure-credential-presence layer) / **RT-26 second** (code-layer) / **RT-27 third** (network-exposure/config layer); the Decision states *"§10 catalogued-instance count = 3"*. Three-class composition and the per-surface three-layer language are as the Decision words them. **Three axes clean** for both `104` and ADR-067: (i) instance-numbering — neither surface numbers, adds, reorders or renumbers an instance; (ii) layer-attribution — neither re-attributes a layer and neither makes a surface "four-layer"; (iii) verbatim-vs-paraphrase — both take **Path B**, carry **no count** and **no enumeration**, and both state that the §10 catalogued set and the CI-fenced set are different sets and are not reconciled. **No drift.**
- **The two sets, measured separately and NOT reconciled.** CI-fenced: `grep -rhoE 'RT-[0-9]{2}' .github/workflows/` → `RT-05 RT-22 RT-26 RT-27`. §10 catalogued (from D4's body) → `RT-22 RT-26 RT-27`. They coincide on three members and the fenced set adds RT-05. **Coincidence is not identity; do not reconcile them.**
- **ADR-011 Decision 9 (DEFINER allowlist).** The allowlist lives in Decision 9's *amendments*, not its heading (heading is Lock 5 / `acct_number`) — pointer verified. Committed = 4, authored-in-migrations = 3. Measured on `secscratch262`: `select proname from pg_proc … where nspname='pfin' and prosecdef` returns exactly `fn_grant_creator_access`, `fn_reclass_history_insert`, `fn_refresh_updated_at`. **UNCHANGED.** `git diff main...HEAD -- supabase/migrations/` introduces no `security definer` in any statement (all hits are prose). ✅
- **ADR-011 Decision 3.** `104` creates no table, no column and no FK-shaped reference of any kind. **FLAT** — as `104`:77-79 and ADR-067's Consequences both state. `101` is what extends the family and says so in its own header. I read D3's body live and did **not** rely on any tally, in this file or elsewhere. ✅
- **ADR-011 Lock 11 (Decision 15).** *"V1-SHIP-BLOCK SECURITY INVOKER on read-time composition (no DEFINER bypass)."* Measured `prosecdef = f`. ✅
- **ADR-011 Lock 15 (Decision 19).** The Locked option specifies *"SECURITY INVOKER composition helper signature extends with `p_data_as_of DATE`"* — the parameter is named `p_data_as_of`, exactly. `104`:161 quotes the dual-column filter as `` transaction_date <= $1 AND created_at < ($1 + 1) `` — **byte-exact** against the Locked option **as amended 2026-08-22 (Edit 1, half-open)**, i.e. against the corrected text and not the retracted one. The `"its rule 6"` citation at `104`:160-161 resolves: `093`:139 is `-- RULE 6 — Lock 15 dual-column as-of, HALF-OPEN upper bound`. ✅
- **The non-silent-staleness citation, corrected form.** ADR-067 Decision 5(c) and `104`:220-224 both cite **PRD §2.4.4 per ADR-013**, naming ADR-049 Decision 5 as the *consumer* that routes to it. I read ADR-049 Decision 5 verbatim: it does record the mis-citation hazard on this exact principle (*"a composite citation pointing at a real ADR and a real label that do not belong together passes every spot-check"*). **The corrected form is what landed.** ✅
- **R3 rider 0 (`fn_compute_nav` / `fn_nav_composition` untouched).** `git diff --stat main...HEAD` touches neither `050` nor `051`. `102` re-creates `fn_nav_composition`, but `102 ≤ 103`, so it is inside the control chain and not a `104` effect. The claim is correctly scoped. `104`'s body contains no `nav_daily`, `fn_compute_nav` or `fn_nav_composition` reference. ✅

---

## Scope-1 — Fail-closed cross-tenant behaviour: **CLEAN**

Measured on `secscratch262`, tenant B (`bbbbbbbb-…`) calling `pfin.fn_compute_tax_liability('2026-09-04')`
while tenant A holds seeded schedules, income and a designated `irs` ledger:

- Both jurisdictions `status: "unavailable"`, `reason: "no_schedule_any_year"`.
- `ytd_paid` → `{"status":"unavailable","reason":"no_ledger_designated"}` — **not `0`**, and not A's `126000.0000`.
- `funds_due` → `unavailable`. `nav_components.realized_tax_liab` and `unrealized_tax_liab` → both `unavailable`. **No zeros anywhere a figure is unknowable.**
- `annual_liability`, `installments`, `basis_year`, `inputs.*`, `taxable_income.*` all JSON `null`.
- With **both** tenants holding data: B's `decomposition` shows only `7777.0000` under B's own `sub_cat_id` (`1000000035`); A's payload is unchanged and still shows `120000.0000` / `126000.0000` and A's designated ledger. **No blending in either direction.**
- `anon`: `permission denied for schema pfin` — unreachable at the schema layer before the ACL is even consulted.

**Role reachability, measured** (`has_schema_privilege` / `has_function_privilege` on `secscratch262`):

| role | `rolbypassrls` | `pfin` USAGE | EXECUTE on `fn_compute_tax_liability(date)` |
|---|---|---|---|
| `anon` | f | **f** | f |
| `authenticated` | f | t | **t** |
| `authenticator` | f | f | f |
| `pfin_etl` | f | f | f |
| `service_role` | **t** | t | **f** |

The one role that would produce a cross-tenant blended payload — `service_role`, RLS-exempt by
attribute — **cannot call the function.** That is correct, and see **N-3** for why the header's
stated reason for it is not.

The three tenancy joins are all on surrogate ids: `pp.id = i.sub_cat_id` (`104`:346), `a.account_id = g.account_id` (`104`:644), `r.schedule_id in (select … from targets)` (`104`:456). Joining two RLS'd reads on a global id fails **closed**; a shared-vocabulary string join would fail **open**. The header's claim on this is correct and load-bearing. The `postgres`-owned schedule concern does not arise: `tax_bracket_schedule` / `tax_bracket_row` carry per-user `users_id` with direct-owner RLS (`101`:1251-1350), there are no global rows, and tenant B saw zero schedules before provisioning its own.

## Scope-2 — Posture pair and `stable` honesty: **CLEAN, with N-1 on the stated argument**

Measured in the catalog on `secscratch262`: `fn_compute_tax_liability` and every function in its
read path (`fn_cashflow_items`, `fn_account_unrealized_gl`, `fn_ytd_paid_per_jurisdiction`,
`fn_tax_authority_ledgers`, `fn_account_cash_as_of`, `fn_server_today`) are `prosecdef = f`,
`provolatile = 's'`, `proconfig = {search_path=""}`. ACL on `104` is
`{postgres=X/postgres,authenticated=X/postgres}` — **PUBLIC absent, `authenticated` present**,
revoke-before-grant as `104`:721-722 orders them. See **N-1** for the transitive set.

## Scope-3 — Money correctness: **CLEAN on every ruled property; N-2 / N-5 on rendering**

Measured end-to-end against a synthetic tenant (salary 120000 · qualified dividend 5000 · tax-free interest 1000):

- **§2.5.2 routing** — `federal.inputs.ordinary_input = 120000.0000` (qualified dividend and tax-exempt interest both excluded), `federal.inputs.lt_cg_input = 5000.0000`, `california.inputs.ordinary_input = 125000.0000` (tax-exempt excluded, qualified dividend collapsed in). Matches PRD §2.5.3's six-step Federal / three-step CA exactly. ✅
- **Installment exactness (E25 / M-8)** — California: `1883.25 × 3 + 1883.23 = 7532.98 = round(annual, 2)`. **Exact.** Q4 carries the residual, Q1–Q3 equal. ✅
- **Taxable income floor at 0 (M-9)** — with `standard_deduction = 999999` against income `120000`, `taxable_income.ordinary = 0` and `annual_liability = 0`. Never negative. ✅
- **NULL-vs-0 (M-11)** — every unknowable figure arrives as a `{status, …}` object. Confirmed for both `nav_components` scalars, both jurisdictions' `ytd_paid` and `funds_due`, and `capital_gains`. A consumer's `?? 0` receives an object. ✅
- **`applied_marginal_rate`** — omitted entirely on an unavailable jurisdiction (E26 ruling 5), present on a computed one, and `jsonb_strip_nulls` correctly drops `lt_cg` for California. Federal `lt_cg: 0.00000000` at zero taxable income is the **genuine 0% bracket**, which is a legitimate 0 and is the right answer. ✅
- **Overpayment (ν-1)** — with a designated `irs` ledger: `funds_due = {"status":"computed","amount":-119586.4200}`. Negative, unclamped, on the same line. ✅
- **`nav_components.realized_tax_liab` fail-closed** — reported `unavailable / ytd_paid_unavailable` while California had no designated `ftb` ledger even though Federal's was computed. *Unavailable if EITHER jurisdiction is* — a half-sum is never reported as the whole. ✅
- **R8 window** — `open` true on 2026-01-01 and 2026-01-15, false on 2026-01-16. Jan 15 inclusive, per E26 ruling 2. Date-only, no paid-ness field. ✅
- **`quarters_elapsed`** across the year: `0 · 0 · 0 · 0 · 1 · 2 · 3 · 3` at Jan 1 / Jan 15 / Jan 16 / Apr 14 / Apr 15 / Jun 15 / Sep 15 / Dec 31. Q4 never counts inside the tax year, as documented. See **F-3**.

⚠ **Not independently reproduced by me:** the `Trade / STC` split-child decoy leg (the shipped
annotation trade-constraint trigger refuses a Trade prototype without a `security_id`, so the
decoy has to arrive through `account_trans_split`, which I did not seed), and the negative-aggregate
Unrealized clamp (needs a securities fixture). Both are recorded as measured in ADR-067's
Consequences and both are named SELF-269 legs. I read the SQL for each — `104`:360-361 carries
both conjuncts, `104`:671 carries `greatest(…, 0)` — and I am relying on the QA battery for the
behavioural proof. **Stated so it is not read as verified here.**

---

## Blocking findings

### F-1 — `current_year_schedule_empty` is not computed for the LT CG leg with no fallback · `104`:520 / 528-529 / 585 / 592 · ADR-067 Decision 5(c)

ADR-067 Decision 5(c): *"A present-but-empty current-year schedule is treated as ABSENT for
selection **and the payload says so**."* `104`:228-235 states the same commitment and spends eight
lines on why it matters. **For `federal_lt_cg` the payload does not say so.**

`walked.current_year_empty` can only be set when a fallback was found — `pick` has no row for a
type with no usable schedule in any year, so `walked` has no row either. `104`:528-529 corrects
for this on the ordinary leg with `ord_empty_no_fallback`, OR-ed in at `104`:585. **The LT CG leg
at `104`:592 has no counterpart**, so `coalesce(NULL, false)` reports `false`.

**Measured, as a boundary pair one step apart on `secscratch262`:**

| case | `schedules.{type}.current_year_schedule_empty` |
|---|---|
| `federal_ordinary` 2026 present, all bracket rows deleted, no prior year | **`true`** ✅ |
| `federal_lt_cg` 2026 present, all bracket rows deleted, no prior year | **`false`** ❌ |

Identical situation, opposite answer, and the wrong one is the silent one. The jurisdiction reads
`unavailable / no_schedule_any_year` — fail-closed on the money, so no figure is wrong — but the
one field that tells the user *an empty schedule is why* says the opposite. Three UI issues read
`schedules.{type}` per the dispatch brief.

**Reachable by an ordinary `authenticated` caller.** `101`:1570 states of the replace-all RPC:
*"an empty array is legal and clears the schedule."* The app-layer Zod requires `rows.min(1)`
(`api/src/lib/server/schemas/tax-bracket-schedule.ts`:214), but the RPC is granted directly to
`authenticated`, so the app schema is not the fence. Deleting the rows of a seeded 2026
`federal_lt_cg` schedule reproduces it exactly — that is what I did.

**Fix:** add an `ltcg_empty_no_fallback` mirroring `104`:528-529 (`exists (… ec.schedule_type = j.ltcg_type) and wl.schedule_id is null`) and OR it in at `104`:592. **Clears:** Architect commits the change; QA adds a leg that goes RED when the OR-term is struck — a leg asserting only `true` on the ordinary leg cannot fail for the LT CG one.

### F-2 — PRD §2.5.3's *"no standard deduction applied to this schedule"* is realized by a seed value, not by construction · `104`:437-442

PRD §2.5.3, Federal step (5), verbatim: *"walk Federal LT CG bracket schedule progressively
**(no standard deduction applied to this schedule)**"*.

`104`:437-442 subtracts `pk.standard_deduction` for **every** schedule type, including
`federal_lt_cg`. The rule holds today only because `103`:421 seeds that schedule with
`0.0000`, and `103`:296-303 records that the zero carries the rule. **Nothing enforces it.**
`fn_tax_bracket_schedule_replace_all` takes `p_standard_deduction`, is granted to `authenticated`,
and refuses no non-zero value on a `federal_lt_cg` schedule; the settings schema requires every
scalar on every POST, so the value passes through the surface on any bracket edit.

A non-zero LT CG standard deduction **reduces** Federal LT CG taxable income and therefore
**understates** the liability — the under-reserving direction, on the keystone.

**Three options, tradeoffs named — this is a disposition, not a demand for code:**

- **A — CHECK at `101`** (`schedule_type <> 'federal_lt_cg' or standard_deduction = 0`). Enforced for every writer including a future one; costs a follow-up migration and makes a PRD-layer rule a permanent DDL fact that a filing-status or V2 schedule change would have to amend.
- **B — `case` in `104`** (`when 'federal_lt_cg' then 0 else pk.standard_deduction end`). One line, keeps the rule where the computation is, and the stored value stops being load-bearing — but it makes the payload's `inputs.standard_deduction` disagree with the stored row, which needs a comment.
- **C — record as accepted.** State in `104`'s header that the LT CG deduction is data, that `0` is its ruled value, and that the settings surface must not offer it. Cheapest; leaves the rule with no enforcement and no watcher, which is the state that produced this finding.

I do **not** have a preference strong enough to override Architect's. **Clears:** Architect records the disposition; if it is C, F/CTO signs it, because C accepts an unfenced under-reserving path.

### F-3 — I read PRD §2.5.3's `quarters_elapsed` differently, and the shipped reading is the smaller one · `104`:549-552, 561-562

`104`:262-267 states the reading explicitly and honestly: *the number of due dates on or before
`p_data_as_of`*. The dispatch brief invited me to flag a different reading. **I have one.**

PRD §2.5.3's purpose sentence: *"so the user reads at a glance **how much they owe each
jurisdiction by the next due date**"*. Under the shipped reading, on 2026-04-14 the answer is
**zero installments owed** — measured, `quarters_elapsed = 0` — one day before the Q1 payment is
due. Under the purpose sentence's reading it is one. The two differ by a full installment for most
of the year, and **the shipped one is always the smaller**, i.e. the under-reserving direction.
The PRD gives no numeric definition, so this is a spec reading, not a code defect.

The same paragraph carries a second unresolved shape: *"Each quarter's table row shows … Estimated
Funds Due"* describes a **per-quarter** figure, while the table structure paragraph lists Sub-Total /
YTD Paid / Estimated Funds Due as **single rows**. `104` emits one scalar per jurisdiction.

**Clears:** PM confirms the reading against the purpose sentence (and books the per-quarter-vs-single-row
ambiguity with the Q3-due-date sentence it is already booking); if it moves, `104`:549-552 is a
one-line change and returns to me.

---

## Notes

**N-1 — the `stable` honesty argument does not cover the transitive read set · `104`:61-66.**
The header argues: *"a `stable` caller of a `volatile` callee is an unbacked promise, and all five
callees were measured `provolatile = 's'`."* The five named are all `s` — I re-measured them.
But the enumeration is neither the direct-callee set nor the reach set. It **includes two
non-callees** (`fn_tax_authority_ledgers`, which `104`:138 itself says is *"reached only THROUGH
102"*, and `fn_server_today`, which `104`:90 says is not called at all), and it **omits three
functions that are reached** — and two of those falsify the argument:

```
fn_compute_tax_liability (s) → fn_account_unrealized_gl (s) → fn_gl_entries      (provolatile = 'v')
                                                            → fn_holdings_as_of  (provolatile = 'v')
```

Measured on `secscratch262`. **There is no live defect**: both are `language sql` with no
INSERT/UPDATE/DELETE/TRUNCATE in `prosrc`, so they are pure reads that were simply never pinned
(VOLATILE is the `language sql` default), and `104`'s *"it writes nothing"* holds. But the exact
hazard the header names sits one level down, inside a function that is itself declared `stable`,
and ADR-067's Consequences generalise it further to *"every callee was measured `provolatile = 's'`"* —
which is false for the reach set. Postgres does not check this, so no green suite will ever say so.
**Recommend:** either extend `079`'s pin to `fn_gl_entries` and `fn_holdings_as_of` (Architect's
call, out of scope for this PR), or reword both texts to the claim that is actually true — every
function in the transitive read set is read-only, and the two unpinned ones are named.

**N-2 — a negative Q4 installment is emitted at `annual_liability = $0.02` · `104`:543, 560.**
Measured: `installments = [0.01, 0.01, 0.01, -0.01]`. `q4 = round(annual,2) − 3·round(annual/4,2)`
goes negative whenever `round(annual/4,2)` rounds up and `annual ≤ ~$0.06`; `$0.02` is the case
that lands. **The exactness property is intact** — the four still sum to `round(annual,2)` — so
E25 / M-8 is not violated; what ships is a negative dollar amount on an estimated-payment row.
Reachability is real but narrow: taxable income ≈ $0.20 over the deduction, or any user who edits
their own schedule to that point. **Remedy if wanted:** `trunc(annual/4, 2)` instead of `round(…)`
makes `3·q123 ≤ annual` by construction, so Q4 is non-negative **and** still exact, at the cost of
Q4 running up to 3¢ above Q1–Q3 instead of ±1.5¢ either way. Strictly better; not blocking.

**N-3 — for a `rolbypassrls` caller the EXECUTE grant is the ONLY fence, and the header says the opposite · `104`:39-43.**
The header reads: *"For an INVOKER function the EXECUTE grant is the WEAKEST of the fences — RLS on
every underlying table still applies to the caller regardless of it."* That is true for
`authenticated` and **false for `service_role`**, which carries `rolbypassrls` and holds `pfin`
USAGE (both measured). Today `service_role` has **no EXECUTE**, so the control is correct — but it
is correct *because of the grant*, which is the thing the header calls weakest. This is the shape
ADR-011 Decision 4's own 2026-09-03 amendment names: *"Multiplicity of layers is … a property of a
surface AND the writer … reading the inventory without naming the writer is what makes that
invisible."* A future PR granting EXECUTE to a worker role would be argued harmless by this header's
own reasoning and would not be. **Recommend** one sentence naming the writer, and a standing
condition: **any grant of EXECUTE on `104` to a `rolbypassrls` role is Sec-joint-review-mandatory.**

**N-4 — `basis_year` is populated on an `unavailable` jurisdiction · `104`:544, 579.**
`least(ord_basis_year, coalesce(ltcg_basis_year, ord_basis_year))` — SQL `LEAST` **ignores NULLs**.
Measured: with `federal_ordinary` absent and `federal_lt_cg` present, the payload carries
`"status":"unavailable"` beside `"basis_year": 2026`. A surface rendering *"Federal — on the 2026
schedule"* next to *"unavailable"* is contradictory, and the brief records that three UI issues read
this field. The per-schedule `schedules.{type}.basis_year` is correct in the same payload.
**Recommend:** gate the jurisdiction-level `basis_year` on `computed` (same shape as
`annual_liability` at `104`:601), or state in ADR-067 Decision 5 that consumers read
`schedules.{type}.basis_year` and gate on `status`.

**N-5 — `annual_liability` is unrounded and the payload carries no rounded annual · `104`:601.**
Measured: `annual_liability = 12827.159442000000` while the four installments sum to `12827.16`.
`104`:246-248 and ADR-067 5(d) are both honest that the four sum to `round(annual, 2)`, but §2.5.3
renders the annual and the four quarters on **one table**, and it will not foot unless the consumer
rounds. **Recommend** a SELF-266 AC condition, or an `annual_liability_rounded` key so the rounding
rule lives in one place rather than in each consumer.

**N-6 — the `computed` gate covers the money outputs, not the intermediates · `104`:594-602, 610.**
`annual_liability`, `installments` and `applied_marginal_rate` are gated. `inputs.*`,
`taxable_income.*`, `tax_balance_prior_year` and `quarters_elapsed` are not. Measured: an
`unavailable` federal jurisdiction still emitted `inputs.ordinary_input: 0` and
`taxable_income.ordinary: 0`. Not a leak and not a wrong figure — but a consumer can render a
confident `$0` taxable income beside an `unavailable` status, which is the collapse the envelopes
exist to prevent, one field over.

**N-7 — `decomposition.ordinary_income.total` deliberately does not equal `Σ inputs.ordinary_input`, and nothing says so.**
Measured: `126000.0000` vs Federal `120000.0000` vs California `125000.0000`. **I checked the PRD
before calling this a defect, and it is not one.** PRD §2.5.1: *"§2.5.1 column placement is
STRUCTURAL … the enum is a separate attribute that travels with the contribution into §2.5.3."*
So the Ordinary Income *column* correctly carries tax-exempt interest and qualified dividends, and
the routed *inputs* correctly exclude them. Three money figures that look like they should foot,
deliberately do not, and neither `104`'s header nor ADR-067 Decision 5 says the divergence is
intended. A SELF-264 / SELF-266 implementer will read it as drift and "fix" one of them.
**Recommend one sentence** in `104`'s header.

**N-8 — `no_schedule_any_year` is also what an aal1 caller of an MFA-enrolled account receives.**
`101`:1251-1310 conditions the schedule and row SELECT policies on the ADR-029 / `025` aal2
step-up. A user whose `mfa_policy` is `totp` or `passkey`, at aal1, sees zero schedules and gets a
payload asserting *"no schedule of that type with bracket rows exists for the tax year or any prior
year"* — which is false about the world. **Fail-closed, so not a security defect**; a diagnostic
one. Worth either a distinct reason code or a consumer note.

**N-9 — an item whose `sub_cat_id` resolves to no readable prototype vanishes from both the sum and the count · `104`:365-369.**
`unclassified` keys on `i.sub_cat_id is null`, not on `pp.id is null`. The LEFT JOIN at `104`:346
correctly preserves genuinely-unclassified items — that is the case `104`:334-335 argues, and it
holds — but an item with a **non-null** `sub_cat_id` that the caller cannot read drops out of `inc`
(via `where it.pp_tax_relevant`) *and* is not counted as unclassified. Direction is right (it fails
closed, not open) but it is silent. Reachability is fenced by the Decision-3 matched-tenant triggers
on the annotation and split writers, so this is **prospective** — except that ADR-011 Decision 4's
2026-09-03 amendment records that those triggers and the FKs behind them **go inert together** under
`session_replication_role = replica`, which is exactly the restore / bulk-load path that amendment
says owes a post-load validation step. **Cheap remedy:** a separate `unresolved_sub_cat_count`, so
the case is visible rather than absent.

**N-10 — `104` places no bound on `p_data_as_of`, and Lock 15's DATE battery is owed on the consumers.**
Any `date` is accepted. A far-future or `'infinity'` argument raises `smallint out of range` from
`104`:326 rather than returning a shape — an error, not a leak, and not a tenant issue. A merely
future date behaves correctly and honestly (`pick` never selects a future schedule, so `basis_year`
renders the staleness). Lock 15's Locked option names the control — *"app-layer DATE input validation
battery (Zod `.date()` + tightened range … + no future dates)"* — and its 2026-08-22 Edit 2 makes the
PR that first wires an `as_of` query parameter Sec-joint-review-mandatory. **Stating it so it is not
assumed discharged here:** it lands on SELF-264 / SELF-266 / SELF-268, not on `104`.

---

## Dispositions on the four departures the brief named

**(a) `schedule_present` dropped; per-type `schedules.{type} = {present, basis_year, current_year_schedule_empty}` added; jurisdiction `basis_year` = OLDEST resolved — CONCUR.**
Strictly more informative than the memo's flat `schedule_present`, and it is what makes the
empty-schedule suppression visible per type rather than inferable from a `basis_year` that moved.
Two conditions ride with it: **F-1** (one of the two legs does not compute the field) and **N-4**
(the jurisdiction-level `basis_year` survives an `unavailable` status because `LEAST` ignores NULLs).

**(b) A jurisdiction is `computed` only when EVERY schedule it needs resolved — CONCUR, and it is the right direction.**
Verified: with `federal_ordinary` absent and `federal_lt_cg` present, Federal reads `unavailable`
rather than reporting the LT CG half as the whole liability. `104`:524-525 cannot yield NULL
(`is not null` never returns NULL), so the `not jj.computed` test at `104`:659 cannot fall through —
I checked, because a three-valued `computed` there would have made the `nav_components` guard leak.

**(c) `quarters_elapsed` = due dates on or before as-of, so Q4 never counts inside the tax year — I READ THE PRD DIFFERENTLY. See F-3.** The mechanics are correct and the `>= 4` branch at `104`:561 is unreachable-by-construction (Q4's due date is always in the following calendar year) — harmless as a guard, but it means the annual is never the obligation-to-date under any input.

**(d) R11's dormant capital-gains clause as header prose, not SQL — CONCUR on the form, with one condition.**
Live SQL for a row set that cannot exist would be dead code contradicting E26 ruling 4, and the two
mechanics that make the rule correct travel with it. **But the rule currently has no watcher:** it
lives in a 725-line header on a function the sale-writer author has no reason to open, plus
ADR-067's Consequences. The named residual ships in *two* homes precisely because *"a header alone
is not read at the moment it matters"* (`104`:168-170, AC 2b) — the dormant clause gets one and a
half. **Condition:** the R11 disposition lands on the SELF-302 / SELF-303 AC or a `BACKLOG.md` §7
entry, so it is read at the moment it matters. Routes to PM.

**(e) `p_data_as_of date default current_date` vs Lock 15 as-of discipline — NO OBJECTION, explicitly.**
`pfin.fn_server_today()` is literally `select current_date` (`070`:159-170), evaluated in the
caller's session zone. The default and the threaded clock are therefore **the same expression**,
not two clocks, and my standing DB-UTC-vs-repo-PDT caution does not create a divergence here.
It is also the established sibling convention — `049`, `051`, `056`, `076`, `078`, `081`, `084`,
`086`, `102` all carry `date default current_date`. The residual is the one the header already
names: a caller invoking `fn_compute_tax_liability()` and `fn_compute_nav(fn_server_today())` as
two statements can straddle midnight, which is why Seam C requires one value threaded to both.
That is a consumer obligation and `104` echoes `as_of` back so it can be proven.

## Scope-5 — header claims the SQL does not realize

Three, all recorded above: **F-1** (`104`:228-235 — the payload does not say so for `federal_lt_cg`),
**N-1** (`104`:61-66 — the `stable` argument, and the enumeration that is neither the callee set nor
the reach set), **N-3** (`104`:39-43 — "regardless of it" is false for a `rolbypassrls` caller).
Everything else I checked in the header is accurate, including the two I expected to fail:
*"049 already filters is_active"* (`104`:638) is **true** — `fn_account_unrealized_gl` as re-issued
at `056` ends `where acc.is_active`, which also discharges ADR-039's forward-flag for the
current-state half, though neither `104` nor ADR-067 names ADR-039 as the flag it is discharging;
and *"is_tax_payment is NOT a source anywhere"* is true — the string appears nowhere in the body.

## Explicit non-objections

- I do **NOT** require a SECURITY DEFINER function anywhere on this surface. INVOKER is correct and is the only correct posture here.
- I do **NOT** require a second as-of predicate in `104`. The Lock 15 dual-column filter is applied once inside `093` and adding one here would double-filter.
- I do **NOT** require the `(π)` `tax_treatment = 'taxable'` predicate to be extracted now, and I specifically do **NOT** want it folded into `fn_tax_authority_ledgers()` — designated-ledger exclusion and tax-advantaged-account exclusion are different concepts.
- I do **NOT** object to the Unrealized zero clamp being asymmetric with `102`'s unclamped YTD Paid. The two must not be reconciled, and the rationale is correctly carried in the `comment on function` where a later reader will meet it.
- I do **NOT** object to `capital_gains` carrying no `rows` key.
- I do **NOT** object to `annual_liability` being a bare nullable scalar rather than an envelope — the jurisdiction `status` carries it, and it is gated on `computed`.
- I do **NOT** require any change to the §10 ledger, the Decision-3 family, the DEFINER allowlist, `secrets-manifest.yml`, or any CI fence. Nothing on this branch touches them.
- I do **NOT** object to `104` being merged with F-1 fixed and F-2 / F-3 dispositions recorded; none of the notes need to land in this PR.

## Conditions on downstream issues (not on this PR)

- **SELF-264 / SELF-266 / SELF-268** — Lock 15's app-layer DATE range battery (N-10); read `schedules.{type}.basis_year` and gate on `status` (N-4); round `annual_liability` for display (N-5); do not treat `decomposition.ordinary_income.total` as a routed input (N-7).
- **SELF-269** — a leg for F-1 that reds when the OR-term is struck; the volatility pin leg named in ADR-067 (and, if N-1 is taken, over the reach set rather than the direct callees); the Trade decoy and negative-aggregate clamp legs I did not reproduce.
- **SELF-302 / SELF-303 or `BACKLOG.md` §7** — R11's disposition needs a home that is read at the moment it matters (departure (d)).
- **Standing** — any grant of EXECUTE on `104` to a `rolbypassrls` role is Sec-joint-review-mandatory (N-3).
