# Sec — V1.4 pre-flight recalibration: bounded consult

**Baseline: `origin/main` @ `2cd94ae`** (`git rev-parse HEAD` in-worktree, equal to `origin/main` at
branch cut). Every citation below is re-read from the tree at that sha, not relayed from any
teammate's memo. Precedent: `docs/records/v13-preflight/sec-v13-d7-d8.md`.

**Canonical reads performed live, in this session, before drafting:** ADR-011 Decisions 1 / 2 / 3 / 4
(including the 2026-09-03 `session_replication_role` amendment) / 9 / 18 (incl. the family-size
amendment) / 19 (incl. both 2026-08-22 amendments) · ADR-016 Decisions 1–3 · ADR-062 · ADR-063 ·
ADR-066 · PRD `story-2-5-1` … `story-2-5-5` · `docs/SECURITY/index.html` SD-04 / SD-11 / SD-21 /
SD-22 / SD-23 and RT-23 / RT-24 / RT-25 · migrations `041` `051` `061` `070` `084` `085` `090` `091`
`032` · `supabase/tests/rls/090_cashflow_target_rls.sql`.

**⚠ TWO PASSES, and the second one moved things.** Pass 1 was drafted with the issue dump **absent**
(directory empty; checked three times) and marked four map rows PROVISIONAL. Pass 2 read the dump at
`/Users/mosko/Projects/mosko-fintech/temp/v14-preflight/issue-dump.md`
(md5 `9d128f6d8d78c9a24620116da5912d69`, verified in-turn; `origin/main` re-read and still `2cd94ae`).

**§1 is rewritten by pass 2 and is current. §8 holds the pass-2 findings.** Two pass-1 findings are
annotated in place rather than deleted, per this repo's supersede-don't-rewrite convention: **M-6 is
RETRACTED** and **F-1 is RESOLVED-WITH-A-CAVEAT**. Everything else in §2–§6 stands as written.

**Ledger statements, read live and stated so they are not inferred from silence:**

- **§10 catalogued-instance ledger (ADR-011 Decision 4):** RT-22 first / RT-26 second / RT-27 third.
  Nothing in V1.4 as scoped adds, reorders or renumbers a catalogued instance; no layer-attribution
  moves; no surface becomes "four-layer". Decision 4 is **linked, not restated** (Path B) and **no
  count is carried in this file**.
- **The CI-fenced RT set** is a **different set** and is not reconciled here.
  Measured: `grep -rhoE 'RT-[0-9]{2}' .github/workflows/` → `RT-05 RT-22 RT-26 RT-27`. It returns
  comment-cited labels too, by design. **Do not tighten that grep and do not make the two sets match** —
  they were once described identically and are not equal.
- **SECURITY DEFINER allowlist (ADR-011 Decision 9, read live):** V1.4 as scoped authors **no new
  DEFINER function**. `pfin.fn_nav_composition` is `security invoker` (`051:146`) and the V1.4 flip
  must not change that.
- **RT-26 `SUPABASE_SERVICE_ROLE_KEY` allowlist (ADR-016 Decision 1 + Decision 3):** V1.4 introduces
  no `service_role` surface. **I do NOT require an ADR-016 amendment for this milestone.** If any
  V1.4 issue reaches for the admin factory, that is Sec-consult + ADR amendment at the
  surface-introducing PR, per ADR-016 Decision 2.

---

## §1 — Sec map, per issue — CLOSED at pass 2

**All nine are MANDATORY. No V1.4 issue is ADVISORY, none is NOT-REQUIRED, and none qualifies for
the ADR-066 light loop.** That is not a defensive default: each row below names the specific
triggering surface, and every one of the nine either authors DDL, changes a figure a user reads as
money, or is the isolation battery itself.

⚠ **SELF-264's milestone membership is resolved:** the dump's own closing section records it as
*currently in* the V1.4 milestone, `updatedAt` 2026-09-03T05:09:51Z. `MILESTONES.md:44` (which
enumerates eight and omits it) is the **stale** side. F-7 stands as a doc-reconciliation, and the
map treats V1.4 as **nine**.

| Issue | Surface (from the AC text) | Sec verdict | Triggering surface |
|---|---|---|---|
| **SELF-263** | `tax_relevant` / `tax_character` attribute migration + F/CTO bootstrap seed | **MANDATORY** | Migration authoring a new **type** and columns on the taxonomy spine, feeding the §2.5.1 money gate. ⚠ Its ACs are substantially falsified by the tree — see **D-1**. |
| **SELF-264** | §2.5.1 three-column decomposition table UI at `/taxes/decomposition` | **MANDATORY** | ADR-011 D4 financial calculation. Labelled `role:frontend`, but ADR-066 D1(b) is explicit: a **rendering-only** change to a money figure is still a money-path change. |
| **SELF-265** | §2.5.2 tax-bracket settings editor at `/settings/tax-brackets` | **MANDATORY** | **Lock 14** settings write-path + **SD-04 HIGH** + **RT-24**. Its own labels already carry `sec-joint-review` + `surface:rls`. ⚠ Both its hard upstreams are unscheduled — see **D-3**. |
| **SELF-266** | §2.5.3 two parallel quarterly tables UI at `/taxes/quarterly` | **MANDATORY** | ADR-011 D4 — money the user pays a government, plus the (ν-1) sign rendering M-3 turns on. |
| **SELF-267** | §2.5.3.c IRS/FTB YTD-Paid overlay: new enum + new column on `pfin.account` + `fn_ytd_paid_per_jurisdiction()` | **MANDATORY** | New DDL on a **central tenant-anchored table**, a new SQL function, and a money aggregate. ⚠ Its stated signature carries a **forgeable tenant parameter** — see **D-2**, the sharpest finding of pass 2. |
| **SELF-268** | §2.5.4 NAV composition flip — placeholder → real Realized + Unrealized Tax Liab | **MANDATORY** | ADR-011 D4 — the single top-line money figure. `051:221-222` hard-code both to `0::numeric` marked *"V1.4 ramp"*. ⚠ AC4 asks for a write `pfin.nav_daily` **refuses** — see **D-4**. |
| **SELF-269** | §2.5.5 RLS verification battery; V1.4 close-gate | **MANDATORY** | Multi-tenant isolation; ADR-011 D3 + D4. I review its **catch criteria**, not its green. ⚠ Three of its ACs are unbuildable as written — see **D-5**. |
| **SELF-302** | GL follow-up — `basis_adjust` `wash_sale` P&L posting (disallowed loss → replacement-lot basis) | **MANDATORY** | **Self-declared** in the issue: *"Own migration, joint-review-mandatory (money-flow)."* Independently: it writes the GL and adjusts **cost basis**, which feeds `fn_account_unrealized_gl` → §2.5.4 Unrealized. It is a §2.5 money path, not a housekeeping item. |
| **SELF-303** | GL follow-up — substantive `corp_action` GL (spin-off basis allocation, cash-in-lieu) | **MANDATORY** | **Self-declared** in the issue: *"Own migration, joint-review-mandatory."* Same basis-feeds-§2.5.4 path. ⚠ It also carries a **prior Sec NOTE** as a rider — see **D-6**; confirm it is not dropped in scoping. |

**The decision rule below is retained** — not because a row still needs it, but because ADR-066
clause (c) points at the ratified map and a mid-arc scope change re-evaluates against it. An issue
is **MANDATORY** if ANY of these is true; otherwise **ADVISORY**; **NOT-REQUIRED** only if none is
true AND ADR-066 D1 (a) and (b) both hold:

1. It authors or alters a migration touching schema / RLS policy / grant / trigger / function.
2. It changes a figure a user reads as money, **including rendering-only** (ADR-066 D1(b)).
3. It touches an ADR-011 D1 privileged-context write surface, a D2 audit-class table's **write
   surface in app code** (ADR-064 D5 — `reverseAndReplaceTrans`, the classify/recategorize/split
   writers, any `pfin.account_trans` writer), a D3 FK-shaped reference column, or the D4 §10 ledger.
4. It proposes a `SECURITY DEFINER` function, adds an RT-26 allowlist entry, adds a
   pgsodium-encrypted BYTEA column, or changes a CI fence / `TenantBoundConnection`.
5. It is a Lock 14 user-facing settings write-path.

**On the light-loop tier (ADR-066) — CLOSED at pass 2.** **No V1.4 issue qualifies.** Every one of
the nine fails at least two of (a) / (b) / (c), and the conjunction admits no discretion. Pass 1 left
SELF-302 / 303 open on the possibility they were GL-internal; the dump closes that — both state
*"Own migration"* (falsifying (a)) and *"money-flow"* / *"joint-review-mandatory"* (falsifying (b)
and (c)). **The tier still re-evaluates** if any issue's scope moves, and on trigger it lapses over
the **whole arc**, not the increment (ADR-066 D2) — but there is no light-tier entry to lapse from
on this milestone.

---

## §2 — Money-correctness flags on the drafted ACs

Ordered by my judgement of severity. Every one is a **flag** unless labelled otherwise; none is a
veto today, because nothing has been built yet — several become vetoes if they reach a PR unaddressed.

### M-1 (flag, highest) — an unmatched sell has no holding period, and the ST/LT column it lands in decides its tax rate

PRD `story-2-5-1`: §2.5.1 column placement is *"structural (… realized capital-gain events → ST CG
or LT CG column per holding period)"*, and holding period comes from *"the existing-system Open-Date
mechanism"*. In the built substrate the only holding-period source is `pfin.lot_match`
(`032`) — a `(sell_trans_id, buy_trans_id, quantity_matched, match_seq)` junction carrying **no date
column of its own**; the acquisition date is the matched buy's.

**Unmatched sells are a sanctioned, reachable state**, not an edge case: `059_drop_is_active.sql:639`
(the `fn_account_unrealized_gl` catalog text) states *"unmatched sells leave basis on the books per
037 Suspense floor."*

So a realized sale with no `lot_match` row has **no derivable holding period and therefore no
column**. Federal routes the ST CG column to the **ordinary** schedule and the LT CG column to the
**0/15/20** schedule — materially different rates. An unknown that silently resolves to LT CG
**understates tax**; one that resolves to ST **overstates**. Neither is visible to a value assertion,
because the totals stay internally consistent over the row set they were computed on.

**Second half of the same flag: partial matches split one sale across holding periods.** `lot_match`
is keyed `(sell_trans_id, buy_trans_id, match_seq)` with a per-match `quantity_matched`, so one sell
can match several buys on both sides of the one-year line. The decomposition must apportion **per
match row**, not per transaction. A per-transaction implementation is wrong for exactly the case
lot-matching exists to serve.

**What I want:** the unknown-holding-period state is discharged **in the consumer, fail-closed** —
a `LEFT JOIN` producing NULL must be tested for NULL *before* any membership test, per the shipped
sibling-fold hazard. Fail-closed here means ST/ordinary (the higher-tax direction) **or** an explicit
UNAVAILABLE-with-a-reason render per the ADR-049 non-silence discipline. It must not silently
resolve to LT. **F/CTO ruling required** — see F-2.

### M-2 (flag) — a negative aggregate unrealized G/L yields a NEGATIVE Unrealized Tax Liability, which ADDS to NAV

PRD `story-2-5-4` locks
`Unrealized Tax Liability = (Federal_LT_CG_top_bracket_rate × aggregate_unrealized_G/L_taxable) + (CA_top_marginal_rate × aggregate_unrealized_G/L_taxable)`,
and `051:131` defines `nav = gross_total − debt − realized_tax_liab − unrealized_tax_liab`.

A **net unrealized loss** across taxable holdings is entirely reachable and makes
`aggregate_unrealized_G/L_taxable` negative, so the product of two positive rates and a negative base
is negative, and subtracting a negative **increases NAV**. The app would then book a tax *benefit*
for a loss that has not been harvested, may never be, and is capital-loss-capped even if it is.
The PRD addresses neither the sign nor a floor. **Fail direction: NAV overstated** — the silent one.

**F/CTO ruling required** — see F-3. My own position: clamp at zero for V1, and say so in the
`comment on` so a later reader does not "restore symmetry" by removing the clamp.

### M-3 (flag) — sign convention on the two NAV rows, and the double-negation route

`fn_nav_composition` SUBTRACTS both tax rows, so both must arrive as **positive magnitudes**. But
PRD `story-2-5-3` (ν-1) renders overpayment as a **negative** Estimated Funds Due
(*"-$X overpaid through Q2"*), and `story-2-5-4` says Realized Tax Liability then *"surfaces a
smaller (or negative) value."* A negative arriving at `051`'s subtraction is arithmetically correct
(an overpayment is a receivable and should raise NAV). **The hazard is a second flip:** if the
§2.5.3 reader sign-flips for display and the §2.5.4 feed reads the display-shaped value, the
overpayment is counted twice with the wrong sign.

`051:58` already carries a load-bearing `DEBT-SIGN (D-1)` note precisely because this codebase has
been bitten by a sign convention on this function before. **The V1.4 migration header must state, in
one sentence, which value is signed which way at the boundary**, and the battery must carry a
**boundary pair** — an overpaid tenant and an underpaid tenant, one step apart, all else identical.

### M-4 (flag) — the tax-year boundary flips ~7 hours early for a Pacific user, and Q4 straddles it

Measured, not reasoned: `061_pin_database_timezone_utc.sql:95` pins the database TimeZone to `UTC`;
`070_fn_server_today.sql`'s own `comment on function` states the function *"returns the database's
own `current_date`, evaluated in the CALLER'S SESSION zone"* and — verbatim — *"⚠⚠ … `current_date`
is ITSELF session-TimeZone-evaluated, so this function DOES NOT make the as-of date
zone-independent."*

Two consequences specific to §2.5, whose entire scope is *"the current calendar year (Jan 1 – Dec 31)"*:

- **(a)** From ~16:00/17:00 Pacific on **Dec 31**, the DB's `current_date` is already Jan 1, so every
  §2.5 surface flips to the new tax year while the user's own day is still Dec 31 — showing $0
  income and $0 obligation against a year they still owe.
- **(b)** The **Federal Q4 due date is Jan 15 of the FOLLOWING year** (`story-2-5-3`). Between Jan 1
  and Jan 15 the locked "current calendar year" scope has rolled forward while the prior year's Q4
  installment is still outstanding and unpaid. On the PRD as written, that obligation **disappears
  from the surface on Jan 1**. This is a structural gap in the locked scope, not an implementation
  bug. **F/CTO ruling required** — see F-4.

### M-5 (flag) — `tax_relevant` carries a fail-OPEN `DEFAULT false` on all three tables

Measured: `041:235` (`pfin.taxonomy_default`), `084:500` (`pfin.posting_prototype`), `084:550`
(`pfin.posting_prototype_default`) — each `tax_relevant boolean not null default false`.

PRD `story-2-5-1`: *"The boolean gates whether a Sub-Cat contributes to §2.5.1 at all."* So an
unmarked tax-relevant bucket is **silently excluded** from the decomposition — income vanishes, tax
is understated, and nothing errors. This is the exact axis ADR-062 Decision 2 identified for
`is_tax_payment` and fixed by **omitting the DEFAULT** so *"every INSERT must state the value."*
ADR-062's own words on the direction: *"a false negative there is silent; a false positive is merely
examined."*

I am **not** asking for the default to be dropped — that is a breaking change to a provisioning path
and to the V2 taxonomy-CRUD INSERT grant, and my standing guidance is that a narrowing constraint
breaks every fixture seeding the barred value. I am asking that the **V1.4 consumer not treat
`false` as an answered question**, and that the ADR-062 `comment on column` scoping precedent be
followed. **F/CTO ruling** — see F-5.

### M-6 — ⚠ **RETRACTED AT PASS 2. The measurement was right and the conclusion was wrong.**

**The retraction, first, so nobody acts on the body below.** SELF-245 is **Done** (2026-08-26,
migration `091`, PR #555) and its Comment 2 records the discharge verbatim: *"AC6 marking pass
COMPLETE (F/CTO ruling, 2026-08-25): **zero** Expense-class prototypes marked `is_tax_payment =
true`."* The ruled enumeration principle is stated there too — the tax buckets
(`Tax - US Federal` / `Tax - California`) are **Transfer-class** by `041`'s founding categorization
and *"never enter the §2.3.4 expense series — the class filter excludes them by construction, not
the marker"*; property-tax transactions were explicitly ruled to stay in their Expense buckets.
Its conclusion is the exact inverse of mine: *"every row carries a **deliberate** false, not an
unmarked default."*

**The generalizable failure, which is the only reason this is worth keeping.** My measurement —
zero rows set `true` — was correct and remains correct. **A tree cannot distinguish "nobody ran the
enumeration" from "the enumeration ran and its ruled outcome was zero."** The two states are
byte-identical in the database and in every migration. The record of which one obtained lived in a
Linear comment, off-tree. **An absence is evidence of an omission only if the discharge would have
left a trace, and a ruling whose outcome is "change nothing" leaves none.** I asserted the omission
without asking that question.

⚠ **What survives, and it is NOT this flag:** SELF-245's own AC-strike block defers a *different*
inventory to V1.4 — original AC4 (`tax_relevant` / `tax_character` for every cash-flow Sub-Cat) is
*"**struck and deferred to V1.4** (§2.5.1 fuel; PM's mid-milestone tax inventory session is booked at
close-out)."* That is `BACKLOG.md:1190` and it is **still unowned**, so **M-5 and F-6b stand
unchanged**. Do not read this retraction as clearing them: `is_tax_payment` is discharged;
`tax_relevant` / `tax_character` are not, and they are the two attributes §2.5.1 actually gates on.

<details><summary>Pass-1 body, retained unedited as the record of what was claimed</summary>

### M-6 (flag) — ADR-062 Decision 3's HARD PRECONDITION is undischarged, and it is a V1.4 dependency

ADR-062 Decision 3, verbatim: *"The F/CTO marking enumeration is a HARD PRECONDITION on the §2.3.4
surface shipping — not a follow-up. Until it completes, every row reads `false` … ⚠ **The gate is a
sequencing commitment, not a mechanism.**"*

**Measured: nothing is marked.** `grep -rn "is_tax_payment" supabase/migrations/*.sql | grep -i true`
returns **one** hit, and it is a comment line (`091:195`). `091` backfills both tables with
`set is_tax_payment = false where is_tax_payment is null` (`091:236-237`, `091:240-241`) and seeds
the two Equity rows explicitly `false`. No row anywhere is `true`.

`BACKLOG.md:1190-1193` (§7 item 3) already books the remedy — *"V1.4 tax-value inventory session
(F/CTO) … The session happens before §2.5.1 implementation ships."* **The mechanism is recorded; the
gap is that no V1.4 issue owns it.** I checked before ruling it novel, and it is not novel — it is
unowned. It must be an explicit dependency on whichever issue builds §2.5.1, or it will be
discovered mid-arc.

⚠ **Do not conflate `is_tax_payment` with §2.5.3's YTD Paid.** `is_tax_payment` is scoped by its own
`comment on column` to **Expense-class** prototypes; the seeded tax buckets
`('cashflow','Transfer','Tax - US Federal')` and `('cashflow','Transfer','Tax - California')`
(`041:341-342`) are **Transfer** class and are therefore outside that flag's scope. The names collide;
the mechanisms do not.

</details>

⚠ **The one paragraph above that pass 2 CONFIRMED rather than retracted** is the last one — the
`is_tax_payment` / YTD-Paid non-conflation. SELF-245's F/CTO ruling reaches the same conclusion by
the same route (Transfer-class, excluded by the class filter rather than by the marker), which is
why it is worth stating that this half was right for the right reason and is now independently
ratified.

### M-7 (flag) — bracket-boundary arithmetic: no lower floor, no upper bound, no unit

SD-04's recorded shape gives `pfin.tax_bracket_row (schedule_id, ordinal, lower_bound, marginal_rate)`
with *"BEFORE INSERT/UPDATE trigger enforcing strictly-increasing `lower_bound` per `schedule_id`."*
Three gaps in that shape, each of which silently misstates tax:

- **No floor.** Nothing forces `ordinal = 1` to have `lower_bound = 0`. A schedule whose first
  bracket starts at $11,000 leaves the first $11,000 of income matched by **no bracket**, and the
  progressive walk silently taxes it at zero. Monotonicity does not catch this — a monotone sequence
  starting at 11000 is perfectly monotone.
- **No upper bound.** Each bracket's ceiling is the *next* ordinal's `lower_bound`, and the top
  bracket is unbounded. That is a reasonable design, but it must be **stated** — a walk that reads
  a non-existent `upper_bound` column, or that stops at the last row instead of extending it to
  infinity, truncates every high-income liability.
- **No unit on `marginal_rate`.** Percent (`22`) or fraction (`0.22`) is a **100× error** in either
  direction and there is nothing in SD-04 that says which. This needs a `CHECK` bounding the domain
  **and** a `comment on column` stating the unit in words.

**Boundary semantics** must also be pinned: is a dollar exactly at `lower_bound` in the lower or the
upper bracket? Half-open `[lower, next_lower)` is the only form that partitions without gap or
overlap. This is the same class of correction ADR-011 Decision 19 Edit 1 already had to make for the
as-of filter's upper bound — a defect that had *"never been implemented"*, caught before first use.
It is cheaper to pin it now.

### M-8 (flag) — the ÷4 quarterly split does not reconcile to the annual liability

PRD `story-2-5-3`: *"The expected annual liability divided by four yields the per-quarter expected
installment."* With any rounding, `4 × round(annual/4) ≠ annual`. The Q4 row must absorb the residual
(annual − 3 × rounded installment) or the four installments will not sum to the obligation the same
page shows. State the rounding rule — half-up to cents, at which step — in the migration/helper
header, because a rounding rule discovered later is a money change.

Related: `Estimated Funds Due = (installment × quarters_elapsed) − (YTD payments)` makes
`quarters_elapsed` a date-derived integer read off the same UTC clock as M-4.

### M-9 (flag) — the standard deduction can drive taxable income NEGATIVE, and nothing floors it

PRD `story-2-5-3` step (2): *"subtract Federal standard deduction → Federal ordinary taxable income"*,
then step (3) walks the schedule. A user whose ordinary income is below the standard deduction gets a
**negative** taxable income. A progressive walk over a negative input, unclamped, produces a
**negative ordinary tax**, which then reduces the total liability and the NAV subtraction. The CA
path (`story-2-5-3`, CA step 2) has the identical shape.

Clamp the post-deduction input at zero **before** the walk, per jurisdiction, per schedule. This is a
`max(0, …)` and a test leg, not a design question — but it is invisible to any fixture whose income
exceeds the deduction, which is every plausible happy-path fixture.

### M-10 (flag) — `NaN` is storable and a one-sided `>= 0` CHECK ADMITS it

Not speculative: migration `090`'s own header states it, at `090:75-77` — *"NaN IS storable in a
constrained numeric and sorts ABOVE every non-NaN numeric, so a one-sided `>= 0` ADMITS IT. The
explicit `<> 'NaN'::numeric` literal is the 014 / 053 idiom and is what refuses it."* `090:173`
records the shipped form: `CHECK (col is null or (col >= 0 and col <> 'NaN'::numeric))`.

Every new numeric column in V1.4 — `lower_bound`, `marginal_rate`, `standard_deduction`, and any
stored intermediate — needs the **two-sided** form. A `NaN` marginal rate propagates to a `NaN` tax,
a `NaN` NAV, and a rendered figure with no error anywhere on the path.

### M-11 (flag) — the fail-open/fail-closed posture of every default, per ADR-062's discipline

ADR-062 is the reference and its rule generalizes: **on a tax surface, the absence of a value must
not be representable as a benign value.** Concretely, for V1.4:

- A missing bracket schedule for a jurisdiction must render UNAVAILABLE-with-a-reason, **not** a $0
  liability. A $0 tax obligation and "you have not entered a schedule" are different facts and the
  user acts on them differently. This is the `090` unset-semantics ruling (NULL, never zero) applied
  to a computation rather than a stored scalar.
- A missing standard deduction must not silently coalesce to `0` (which **overstates** tax) nor to a
  hard-coded figure (which is a silent, unversioned tax input).
- A `0` result and an `absent` result must arrive as **distinguishable shapes** at the reader — the
  same reader obligation `090`'s header records for `cashflow_target`.

---

## §3 — Multi-tenant isolation exposure

### The new tables the ACs imply, and the RLS shape each needs

**`pfin.tax_bracket_schedule`** — per SD-04: `(users_id, jurisdiction, schedule_kind,
standard_deduction, tax_year)`, `UNIQUE (users_id, jurisdiction, schedule_kind, tax_year)`.

- Direct-owner RLS `users_id = auth.uid()` on **all four verbs**, each policy **ANDed with the
  `025` aal2 step-up backstop clause**, reused **byte-faithfully** (the `090` precedent —
  `090_cashflow_target_rls.sql` header records the idiom).
- Full `authenticated` CRUD grant; **anon zero-grant; `service_role` UNGRANTED** (the `090` posture).
- `users_id uuid not null default auth.uid() references auth.users (id) on delete cascade` — never
  a parameter, never from `req.body`.
- **D3: not a family member.** `users_id` is the sole tenant anchor and `auth.users(id)` has no
  tenant dimension. **No label is taken and none may be drafted in advance** — ADR-011 Decision 3's
  standing discipline, and the family has already paid once for a pre-drafted label.

**`pfin.tax_bracket_row`** — per SD-04: `(schedule_id, ordinal, lower_bound, marginal_rate)`.

⚠ **This is the load-bearing design choice of the whole milestone, and it must be made deliberately
rather than inherited:** does the child carry its **own `users_id`**?

- **If it does NOT** (SD-04's recorded shape): `schedule_id` is the **sole tenant anchor**, so there
  is no second anchor to mismatch and it is **NOT an ADR-011 Decision 3 family member** — the same
  disposition ADR-011 Decision 9's 2026-07-24 amendment records for
  `account_trans_annotation_history.trans_id`. **But then RLS must be chain-resolved**: every policy
  on the child is an `EXISTS` join to `pfin.tax_bracket_schedule` under the parent's own predicate,
  on all four verbs, each still ANDed with the aal2 backstop.
- **If it DOES** carry its own `users_id` (a denormalization some teams reach for to simplify the
  policy), then `schedule_id` becomes a genuine FK-shaped cross-tenant reference with a second
  anchor to mismatch — **it IS a Decision 3 instance and it takes canonical label #18**, with a
  **P1 matched-tenant local-anchor** fence (the `012` / `022` / `074` shape: `BEFORE INSERT OR
  UPDATE` — the table is mutable settings data, so an INSERT-only fence would leave the repoint path
  open — `SECURITY INVOKER`, `set search_path = ''`, NULL-safe fail-closed by resolving the
  referenced row into locals rather than comparing inside a subquery that returns NULL on a miss).

**I am not choosing between them** — that is Architect's, and it is F-6 below. I am stating that the
choice **determines both the RLS shape and D3 membership**, and that the migration must say which
branch it took and why.

⚠ **Whichever branch: ADR-011 Decision 18's locked clause *"NOT a new instance of §8 cross-tenant
FK-bypass family at V1 — settings writes are user-session-bounded"* is the wrong test.** Its own
2026-08-16 amendment already records why: *"'settings writes are user-session-bounded' is an argument
about the write path, while Decision 3 membership turns on column shape — so the original claim was
answering a different question from the one that decides it."* Do not cite that clause to conclude
these tables are outside the family.

⚠ **And the REST of that sentence is live and must not be swept up.** The same amendment: *"the V2+
live-tax-API ingestion trigger stands, the Sec re-consult at that adoption remains mandatory, and
the Lock 12 mod #2-pattern fence becoming V1-SHIP-BLOCK at that adoption remains a standing
obligation."* V1.4 does **not** adopt live-tax-API ingestion (`BACKLOG.md:115` keeps it V2+), so that
trigger does not fire here — stated explicitly so its absence is not read as its discharge.

**The IRS/FTB account pointer (if F-1 lands on a stored reference).** If the identification mechanism
becomes a settings row pointing at `pfin.account(account_id)`, **that** is an FK-shaped
cross-tenant reference on a table with its own `users_id` → **P1 matched-tenant, local anchor →
canonical instance #18**, `BEFORE INSERT OR UPDATE`, INVOKER, `set search_path = ''`, NULL-safe
fail-closed. The fence's own `comment on function` states the label, and — per ADR-011 Decision 3's
2026-08-04 rule, consequence (c) — **the Decision 3 fold-in is due in the PR that DDL-realizes the
instance, not at a later reconciliation.** A migration asserting `#18` against an ADR that does not
yet contain it converts an un-folded instance into an apparent fabrication for the next reviewer
obeying the read-Decision-3-live discipline.

### Non-obvious isolation and correctness traps in the replace-all write path

1. **⚠ The monotonicity trigger and the replace-all transaction fight each other.** Lock 14 mod #3
   specifies a `BEFORE INSERT/UPDATE` row trigger enforcing strictly-increasing `lower_bound` per
   `schedule_id`; Lock 14 mod #4 specifies replace-all under SERIALIZABLE. A **BEFORE ROW** trigger
   sees only rows already committed to the table at the instant it fires, so it will **reject a
   legal replace-all inserted in any order but ascending**, and it **cannot see rows inserted later
   in the same statement**. Either (i) make it a `CONSTRAINT TRIGGER … DEFERRABLE INITIALLY
   DEFERRED` firing once at commit over the whole schedule, or (ii) make it a per-statement check,
   or (iii) mandate ascending insert order — but (iii) is a convention with no mechanism and will
   rot. **My preference is (i).**
2. **⚠ The trigger is trigger-realized and therefore INERT under `session_replication_role =
   replica`** — ADR-011 Decision 4's 2026-09-03 amendment, verbatim from `057`: *"a policy survives
   ALTER TABLE ... DISABLE TRIGGER and session_replication_role = replica; a trigger does not."*
   The same GUC also suppresses FK enforcement, so a `tax_bracket_row.schedule_id` FK and any
   matched-tenant fence on it **go inert together, in the same statement**. This is operational, not
   adversarial (`authenticated` and `service_role` are both denied setting the GUC), but the
   **restore / bulk-load runbook already booked on the V1.4 deck owes an explicit post-load
   validation step over these tables**, and the migration header must name the inertness rather than
   leave it to be rediscovered.
3. **⚠ The DELETE↔SELECT policy conjunction is CONDITIONAL.** Postgres consults the SELECT policy
   during a DELETE **only when the statement reads or filters by a column**. A bare
   `DELETE FROM pfin.tax_bracket_row` is gated by the DELETE policy's `USING` **alone** — so that
   predicate is never redundant, and a cross-tenant DELETE assertion written *with* a
   `where users_id = …` filter is satisfied by **either** policy and proves neither. The
   `090_cashflow_target_rls.sql` AC12 leg is the worked precedent; SELF-269 must copy its shape, not
   its wording.
4. **Replace-all under RLS on a chain-resolved child.** If the child's DELETE `USING` resolves the
   tenant through the parent, a replace-all that deletes the parent first orphans the children
   beyond the reach of any policy. Delete children first, or `ON DELETE CASCADE` from the parent, and
   assert it.

### What SELF-269's battery must cover that existing batteries do not

The existing batteries (`074_planning_target_rls.sql`, `090_cashflow_target_rls.sql`) cover
**direct-owner** Lock-14 tables. Neither covers a **chain-resolved child**, and that is the new shape.
SELF-269 owes, at minimum:

- **A boundary pair on the child's tenant fence, one step apart, all else identical:** tenant A
  inserting a row against tenant A's `schedule_id` **succeeds**; tenant A inserting against tenant
  B's `schedule_id` **is refused**. Not two unrelated legs — a pair, so the discriminator is the one
  varied field.
- **The ownership-forge route, not only the RLS-exempt one.** If the child carries its own
  `users_id`, a plain `authenticated` caller submitting **their own real `schedule_id` with a foreign
  `users_id`** trips the fence *before* RLS's `WITH CHECK` is reached (a `BEFORE` trigger precedes
  `WITH CHECK` evaluation). ADR-011 Decision 3's `#17` entry records this correction verbatim and
  records that the first draft got it wrong *"in the direction that hides the attack a real caller
  can mount."* Do not inherit that overclaim a third time.
- **A DELETE-policy-alone leg** per trap 3, isolating the DELETE `USING` from the SELECT `USING`.
- **The aal2 backstop conjunct asserted on every policy of both tables** — not sampled on one.
- **A corrupt-the-control canary that corrupts the relation whose regression the fence names** — the
  child's own policy, not a sibling's — and verify placement by what runs **after** it: a `lives_ok`
  control persists rows, and a `= 0` leg placed after a tenant switch passes vacuously forever.
- **NaN / Inf legs on all three numeric columns**, asserting the two-sided CHECK per M-10.
- **A monotonicity leg exercised through the actual replace-all path**, not through a single
  hand-ordered INSERT — per trap 1, that is the only ordering that can fail.
- **A negative-taxable-income leg** (M-9) and a **negative-aggregate-G/L leg** (M-2), because the
  happy-path fixture cannot reach either.

⚠ **`grep` the battery before scoping any of this as new work** — some of it may already be in the
tree, as SELF-252 option B was.

---

## §4 — Catch criteria, per MANDATORY issue, stated NOW so builders build to them

These are what I will check at joint review. Nothing here is a surprise if it is read at dispatch.

**SELF-264 (§2.5.1 decomposition)**
1. The unknown-holding-period path (M-1) is discharged **in the consumer**, tested for NULL **before**
   any membership test, and its resolution is the fail-closed direction or an explicit UNAVAILABLE.
2. Apportionment is **per `lot_match` row**, not per transaction (M-1, second half).
3. `tax_relevant = false` is not treated as an answered question (M-5), and the ADR-062 marking
   dependency (M-6) is either discharged or named as an unmet precondition on the issue.
4. Read composition is `SECURITY INVOKER` + `set search_path = ''`; **no new DEFINER**.

**SELF-265 (§2.5.2 settings write-path — Lock 14)**
1. **Zod `.strict()` on the request body, reject 400 on unknown keys**; `users_id` derived from
   `auth.uid()` on the server and **never** read from `req.body`. (Lock 14 mod #1; RT-24.)
2. **Numeric adversarial battery at the endpoint** — `NaN` / `Infinity` / currency-string strict
   regex / overflow at a jurisdiction-realistic bound / scientific notation / locale-formatted, all
   rejected. (Lock 14 mod #2; RT-24 names the shipped regex.)
3. **Two-sided DB CHECKs** on `lower_bound`, `marginal_rate`, `standard_deduction` (M-10), plus the
   `marginal_rate` unit CHECK and its `comment on column` (M-7).
4. The monotonicity fence is **deferrable-constraint-shaped, not BEFORE-ROW-shaped** (trap 1), and
   the migration header names its inertness under `session_replication_role = replica` (trap 2).
5. RLS on both tables per §3, aal2 backstop on every policy, `service_role` ungranted, anon
   zero-grant. If a Decision 3 label is taken, **the ADR-011 fold-in ships in this same PR.**
6. **No JSONB blob** in the settings store — ADR-011 Decision 18 Sec mod, and its amendment states
   the forward-compat fence *"stands in full."*

**SELF-266 (§2.5.3 quarterly tables + YTD Paid)**
1. The IRS/FTB account-identification mechanism is **explicit and stated** (F-1). If it is a stored
   reference, §3's `#18` treatment applies in this PR.
2. YTD Paid's source predicate is stated: which rows in that ledger count as a payment, and what a
   refund or an inbound transfer does to the figure.
3. Rounding rule + Q4 residual absorption (M-8) stated in the header.
4. `quarters_elapsed` and every date derivation name **which clock** (M-4), and the Jan 1–15 Q4
   straddle has a ruled behaviour (F-4).
5. Negative-taxable-income clamp (M-9) present, per jurisdiction, before the walk.
6. Bracket walk: half-open boundaries, floor at zero, unbounded top bracket — all three (M-7).

**SELF-267 (computation engine, if it authors a DB function)**
1. `SECURITY INVOKER` + `set search_path = ''` + `revoke execute … from public` + `grant execute …
   to authenticated`. **A `SECURITY DEFINER` proposal is a gate** — allowlist read live at ADR-011
   Decision 9, and an addition needs its justification and its ADR in the same PR.
2. The declared volatility is a testable claim; if it declares `STABLE`, that is pinned.
3. Cross-tenant caller sees **no rows** and the function **fails closed**, not `0` — the `049`/`051`
   INVOKER posture.
4. Every money flag above that lands inside the engine has a leg that can fail.

**SELF-268 (NAV composition flip)**
1. `fn_nav_composition` stays `SECURITY INVOKER` (`051:146`).
2. The sign convention at the boundary is stated in one sentence in the header, and a
   **boundary-pair** leg (overpaid vs underpaid tenant) discriminates it (M-3).
3. The negative-aggregate-G/L case has a ruled behaviour and a leg (M-2).
4. The `V1.4 ramp` markers at `051:221-222` and the function's `comment on function` are updated
   **in the same migration** — a catalog comment asserting a placeholder that is no longer a
   placeholder reads to the next reviewer as live state.
5. Zero-value sentinels: with the placeholders gone, a genuine `0` and an unavailable input must be
   distinguishable at the reader (M-11).

**SELF-269 (close-gate battery)** — §3's list. Plus: I review the battery's **catch criteria and its
inversion**, not its green. A leg that cannot fail is the tell; strike the control on a copy and
require its watcher to red.

---

## §5 — Needs an F/CTO ruling (not mine to take)

**F-1 — ⚠ RESOLVED AT PASS 2, three months ago, in a place nothing can grep. The caveat is live.**
SELF-267's description records: ***"F/CTO Gate B Option A locked 2026-06-03:** `tax_jurisdiction
pfin.tax_jurisdiction_enum NULL` column on `pfin.account`; F/CTO marks IRS + FTB accounts at
creation."* That is **option (C) below**, already ratified. My pass-1 statement — that the PRD
specifies no mechanism — was true of the PRD and true of the tree, and false of the project.

**The finding is now about the record, not the decision, and it is the second instance of a named
failure class.** Measured: `tax_jurisdiction` and *"Gate B Option A"* appear **nowhere** in
`DECISIONS.md`, `supabase/`, `api/`, `docs/`, `BACKLOG.md` or `MILESTONES.md` — the ruling exists
only in a Linear issue description. ADR-062 opens by naming exactly this: *"The original Option-A
ratify existed **only in a Linear issue description**. That is not a durable record: it is not
greppable from the tree, it does not travel with the migration, and it was re-litigated at the V1.3
pre-flight because nobody could find it."* **It happened again, and it was again found at a
pre-flight.** The V1.4 milestone should land this ruling in an ADR at the migration that realizes
it, not carry it in Linear for a fourth month.

⚠ **My option-(C) caveat is now a live build requirement, not a tradeoff:** nothing in an
`account.tax_jurisdiction NULL` column prevents **two accounts carrying `'irs'`**, and
`fn_ytd_paid_per_jurisdiction` sums over *all* matching accounts — so a duplicate mark silently
**double-counts YTD Paid**, which **understates Estimated Funds Due**, which **understates Realized
Tax Liability**, which **overstates NAV**. One partial unique index closes it:
`unique (users_id, tax_jurisdiction) where tax_jurisdiction is not null`. **State whether more than
one account per jurisdiction is legal** — if it is, the index is wrong and the double-count is a
feature; if it is not, the index is owed. It cannot be left unanswered.

✅ **And it is NOT an ADR-011 Decision 3 instance.** `tax_jurisdiction` is an **enum-typed value
column**, not FK-shaped: no FK, no reference to any relation, no array of ids. There is no referenced
row and therefore no tenant to match; no matched-tenant validation is owed and **no label is taken**.
My pass-1 warning that this would become canonical **#18** was conditional on option (A), which is
not what was ratified — **the family stays flat and `#18` remains unallocated.** Stated per column,
per `085`'s rule.

<details><summary>Pass-1 options, retained — (C) is the ratified one</summary>

PRD `story-2-5-3` says they are
*"standard §2.4.2 manual accounts with tax-domain semantic interpretation overlaid by §2.5.3's read
path"* and specifies **no identification mechanism at all**. Nothing in the schema marks an account
as the IRS account. Without a ruling this gets invented at build time.
- **(A) A per-user settings row holding two nullable `account_id` references.** Explicit,
  user-controlled, survives renames. **Cost:** two FK-shaped cross-tenant reference columns → an
  ADR-011 Decision 3 evaluation and, on a table with its own `users_id`, canonical **#18** with a P1
  fence and a same-PR ADR fold-in. **My lean.**
- **(B) Name matching on the account label.** Zero schema. **Cost:** a label is shared vocabulary,
  fails **open** rather than closed, silently captures any account the user renames, and silently
  loses the ledger when they rename it back. I would flag this at review.
- **(C) An `account.tax_authority` enum column.** One column, no junction, no new table. **Cost:**
  widens an already-central table for a §2.5-only concern, and it is still a value a user could set
  on more than one account unless a partial unique index prevents it.

</details>

**F-2 — What does a realized sale with no resolvable holding period do?** (M-1.)
- **(A) Route to ST / ordinary** — fail-closed on tax, overstates rather than understates. **My
  lean**, on ADR-062's own stated direction.
- **(B) Render UNAVAILABLE-with-a-reason and exclude from the totals** — the ADR-049 non-silence
  discipline; most honest, most disruptive to the surface.
- **(C) Route to LT CG.** Cheapest and the only one that **understates tax silently**. I would flag
  it, not veto it, but it needs to be a decision rather than a default.

**F-3 — Does Unrealized Tax Liability floor at zero?** (M-2.)
- **(A) Clamp at zero.** Conservative, matches "tax cost of liquidating today", cannot inflate NAV.
  **My lean.**
- **(B) Allow negative.** Arithmetically symmetric with the formula as locked; inflates NAV by an
  unrealized, capital-loss-capped, possibly-never-realized benefit.
- **(C) Clamp and surface a separate informational "unrealized loss carry" note.** Most accurate,
  most build.

**F-4 — What happens to the prior year's Q4 obligation between Jan 1 and Jan 15?** (M-4b.) The
locked "current calendar year" scope drops it on Jan 1 while it is still owed.
- **(A) Accept the gap for V1** and put it in `BACKLOG.md` §5 with the reason written down.
- **(B) Extend the §2.5.3 render window** to show the prior year's outstanding Q4 until its due date
  passes. Small, bounded, and the honest behaviour.
- **(C) Re-scope §2.5's tax-year definition to a tax-year cursor rather than the calendar year.**
  Correct and out of proportion to V1.

**F-5 — `tax_relevant DEFAULT false`.** (M-5.)
- **(A) Leave the DEFAULT; fence at the consumer** and rely on the F/CTO inventory session (F-6/M-6)
  to make the stored values right. **My lean** — the DEFAULT is load-bearing for provisioning and a
  narrowing change breaks every fixture that seeds the barred value.
- **(B) Drop the DEFAULT on the two `posting_prototype` tables**, ADR-062-style. Fail-closed by
  construction; breaks the provisioning column list and every fixture, and needs a total backfill.
- **(C) Leave it and add a `comment on column` scoping what `false` means**, exactly as ADR-062 did
  for `is_tax_payment` — the cheap half of (B).

**F-6 — Two structural questions I am routing rather than answering.** (a) Does
`pfin.tax_bracket_row` carry its own `users_id`? — Architect's, and §3 states what each branch costs.
(b) The ADR-062 marking enumeration / V1.4 tax-value inventory session (M-6, `BACKLOG.md:1190`) needs
an **owning issue and a scheduled slot before §2.5.1 ships** — currently it is booked with no owner.

**F-7 — the SELF-264 discrepancy.** `MILESTONES.md:44` enumerates eight V1.4 issues and omits
SELF-264; the dispatch brief lists nine and includes it; `BACKLOG.md:348` names SELF-264 as a real
surface. Someone should reconcile the milestone ledger against live Linear.

---

## §6 — Non-objections, stated explicitly

An unstated non-objection reads as an unexamined surface. For V1.4 as scoped:

- **I do NOT require an ADR-016 amendment** or any RT-26 allowlist addition. V1.4 introduces no
  `service_role` surface. If one appears, the gate applies at that PR.
- **I do NOT require a new SD entry.** SD-04 already covers the tax-bracket storage surfaces at HIGH
  tier and its shape paragraph is the build reference. SD-21 is the sole remaining reserved-vacant
  slot and I am not spending it here.
- **I do NOT require a new RT entry.** RT-24 already scopes the tax-bracket settings write path and
  RT-23 the sibling planning-target path; V1.4 **discharges** RT-24 rather than extending the catalog.
- **I do NOT require any §10 catalogued-instance change.** Nothing in V1.4 introduces a
  layer-distinct mechanism; this is intra-class work, and the ledger is linked, not restated.
- **I do NOT object to the ADR-062 `DEFAULT false` on `tax_relevant` as a stored shape** — see F-5;
  my objection is to a consumer that reads `false` as an answered question.
- **I do NOT object to `pfin.tax_bracket_row` lacking its own `users_id`** — it is a defensible and
  arguably better shape. I object only to it being **inherited** rather than chosen, and to a
  direct-owner RLS policy being copied onto a table that has no direct owner.
- **I make no finding on SELF-263 / 267 / 302 / 303's content.** The issue dump was absent; §1's
  decision rule is what disposes them, and I will complete the map on receipt rather than guess.

---

## §7 — My own errors, named here rather than in a follow-up

**E-1.** In my interim message to team-lead (before this file), I called the NULL `tax_character` on
`041:345` / `041:347` (`Trade / STC`, `Trade / BTC`) a *"veto-grade-adjacent"* routing gap, on the
reasoning that PRD §2.5.2's routing table has no NULL row. **That was wrong.** Re-reading
`story-2-5-3` verbatim, Federal steps (1) and (4) route capital gains by **COLUMN** — *"sum Ordinary
Income column (excluding qualified_dividend and tax_exempt_interest-tagged contributions) + ST CG
column"* and *"sum LT CG column + qualified_dividend-tagged Ordinary Income contributions"* — so the
`tax_character` enum discriminates only within the **Ordinary Income** column. A NULL on a Trade row
is coherent by design, and `041`'s own note says so: *"character from holding period (§2.4.3)."*
I read the enum as the discriminator without checking which column the row lands in first.

The **corrected** finding is M-1, which is a different and sharper hazard: the column placement
depends on a **holding period** that an unmatched sell does not have. The original framing pointed at
a table that is fine; the corrected one points at a state the tree explicitly sanctions.

**E-2.** My interim message stated the ADR-062 marking gap without first grepping for an existing
booking. `BACKLOG.md:1190-1193` already books it. The finding stands, but its correct shape is
"**recorded and unowned**", not "**missing**" — a distinction I have been bitten by before, and the
one that decides whether this needs a new issue or a dependency edge on an existing one.

**E-3 (pass 2, and the one that actually cost something).** M-6 was **wrong**, and E-2 was the near
miss that should have caught it: I grepped the *repo* for a booking, found one, and downgraded
"missing" to "unowned" — but I never asked whether the discharge had happened somewhere the repo
cannot see. It had, a week earlier, with an F/CTO ruling attached. **I searched one more layer and
stopped one layer short of the answer**, which is the same shape as the finding itself.

The reusable rule: **before calling an absence an omission, ask what the discharge would have
LOOKED like.** A ruling whose outcome is "change nothing" writes no row, no migration, and no diff —
so its absence from the tree is not evidence of anything. Where the discharge is a *decision* rather
than a *change*, the tree is the wrong instrument and the issue tracker is the right one.

Two secondary costs, recorded because they are how a wrong finding propagates: M-6 shipped in my
interim message and again in my pass-1 report before this retraction existed, and F-1 was raised as
an **open ruling** when it had been ratified on 2026-06-03 — I framed a three-month-old decision as
undecided, which invites re-litigation of a settled call. Both would have been avoided by reading
the issue text first; neither was avoidable from the tree alone, which is the honest half.

---

## §8 — Pass-2 findings, from the issue text measured against the tree

Six findings the AC text produced that the tree alone could not. Every claim below was re-measured
against `2cd94ae` in the same turn it was written; none is relayed from the dump.

### D-1 (flag) — SELF-263 would FORK the `tax_character` vocabulary into a third representation

AC1 asks for *"`pfin.tax_character_enum` PostgreSQL enum created with 5 V1 values."* **That
vocabulary already exists twice and neither is an enum type.** `009` shipped it as an inline
`text CHECK (tax_character in (…))`; `011_tax_character_registry.sql` then *"promotes the `009`
inline `text CHECK (5 values)`"* to a **registry table** `pfin.tax_character (code, label, notes,
display_order)` with `user_taxonomy.tax_character` converted to
`FOREIGN KEY … REFERENCES pfin.tax_character(code) ON DELETE RESTRICT` (`011:158`, `011:254-258`) —
the ADR-024 global registry. Creating a PG enum now makes a **third** spelling of one vocabulary,
and the three drift independently the moment a value is added.

Two further AC-vs-tree falsifications on the same issue, stated because they change who owns the fix
rather than because they are mine to fix:

- **AC2 targets the wrong table for the cash-flow half.** It adds the columns to
  `pfin.user_taxonomy`, but ADR-058's `084` moved the **posting vocabulary** to
  `pfin.posting_prototype`, which is where the cash-flow `tax_relevant` / `tax_character` now live
  (`084:500`, `084:550`). `user_taxonomy` is the **storage-classification spine** and carries no
  cash-flow rows to mark — `084`'s own table comment says so.
- **AC2's columns already exist on the table it names.** `009` added both; `011` re-typed one. So
  the AC as written is partly a no-op and partly a fork.
- **AC7 (*"read-only via migration in V1"*) is false of the shipped grants.** `084` grants
  `authenticated` **SELECT + INSERT** on `posting_prototype`, and `041` added the
  `user_taxonomy_insert` policy. Rows are user-insertable today; only UPDATE and DELETE are
  deferred. **This matters to me specifically:** an AC that believes a table is read-only will not
  specify a write-path fence for it, and `tax_relevant` is a money gate.

**Sec position:** I do not object to any *particular* resolution — that is Architect's and PM's. I
object to AC1 shipping as written, because a third vocabulary spelling is a defect that cannot be
fixed later without a data migration. **AC4's substance is a live money decision, not a
transcription:** it asks for asset-side Sub-Cats to be set `tax_relevant = TRUE` /
`tax_character = long_term_capital_gain_eligible`, and `041` currently seeds **all 36 asset rows**
`false` / `null` (`041:275-310`). That flip is the F-6b inventory session's business, not a
migration author's.

### D-2 (⚠ the sharpest pass-2 finding) — SELF-267's stated signature carries a FORGEABLE TENANT PARAMETER

AC3 specifies
`pfin.fn_ytd_paid_per_jurisdiction(p_users_id UUID, p_year INT, p_jurisdiction TEXT, p_through_quarter INT) RETURNS NUMERIC`,
while AC6 specifies *"RLS enforced under SECURITY INVOKER composition."* **Those two ACs are in
tension and the project has already ruled on it once.** SELF-211's own reconciliation comment states
the rule verbatim: *"INVOKER means tenancy is `auth.uid()` via RLS, so there is **no**
`user_id`/`scope` param"* — and the shipped substrate obeys it: `fn_compute_nav(p_as_of date)`,
`fn_nav_composition(p_as_of date)` (`051:143`), `fn_server_today()` — **not one takes a tenant
parameter.**

**Why this is not a style objection.** A `p_users_id` parameter on an INVOKER function is *merely
redundant today* — RLS ignores it and the caller cannot read another tenant's rows regardless. But
it is a **latent cross-tenant read that arms itself on any future posture change**: the day someone
makes this function `SECURITY DEFINER` for a performance or composition reason, the parameter
becomes the tenant selector and there is no fence behind it. The function would then read exactly
what its caller asked for. **A parameter that is inert under one posture and authoritative under
another is a fence that depends on nobody ever changing the posture** — and posture changes are
precisely what my DEFINER gate exists to catch, which means the gate would fire on the DEFINER
change and the reviewer would have to notice the parameter *at that moment* to catch it.

**Requirement: drop `p_users_id` from the signature.** Tenancy comes from `auth.uid()` via RLS on
`pfin.account` and `pfin.account_trans`. If a future privileged caller genuinely needs a tenant
parameter, that is an ADR-011 Decision 1 privileged-context surface with its own four-clause
discipline, not a default argument on a read helper.

**Second defect in the same signature: `p_jurisdiction TEXT` against an enum-typed column.** Make
the parameter `pfin.tax_jurisdiction_enum`, so an unknown jurisdiction is a **type error at the
boundary** rather than a silent zero-row sum that renders as `$0 YTD Paid` — which **overstates
Estimated Funds Due** and is indistinguishable from "you have paid nothing." A `text` parameter here
is also the RT-25 parameter-bypass shape on a new surface.

**Third: AC3 says "sums payments" and never says what a payment IS.** The predicate is
`account_trans` rows on accounts where `tax_jurisdiction = p_jurisdiction` — which will also match a
**refund received**, an **inbound transfer**, and any correction row. Sign convention and row
selection both need stating in the function's `comment on function`, per M-3.

### D-3 (flag) — SELF-265's two hard upstreams are not in the milestone, and one of them carries all the security

SELF-265's Dependencies name **SELF-259** (*"tax_bracket_schedule / tax_bracket_row migration +
SERIALIZABLE replace-all endpoint"*) and **SELF-260** (the seed) as upstream. **Neither is among the
nine V1.4 issues.** The same is true of **SELF-262** (`fn_compute_tax_liability()`), which SELF-264
AC1, SELF-266 AC1, SELF-267 AC4 and SELF-268 AC1 **all** invoke.

This is PM/team-lead's scheduling problem, not mine, and I flag it only because of where the security
sits: **SELF-259 is the issue that would carry the RLS policies, the aal2 backstop conjunct, the
Decision-3 evaluation, the monotonicity fence and the two-sided NaN CHECKs** — everything in §3 and
most of §4's SELF-265 block. If SELF-259 is unscheduled and SELF-265 (labelled `role:frontend`,
though it also carries `role:backend` + `surface:rls`) absorbs the DDL, then **a frontend-shaped
issue silently becomes the milestone's principal schema surface.** That is survivable if it is
*decided*; it is not survivable if it happens by default, because the DDL review would arrive
attached to a UI PR.

**Minor, but fix it before the migration is written:** SELF-265 AC2 names the columns
**`bracket_floor` + `bracket_rate`**, while the ratified SD-04 cell names **`lower_bound` +
`marginal_rate`**. Pick one and make SD-04 and the DDL agree; a settings editor and a security
matrix naming the same column two ways is how M-7's unit ambiguity survives review.

### D-4 (⚠ veto-shaped if taken literally) — SELF-268 AC4 asks for a write `pfin.nav_daily` REFUSES

AC4 reads: *"SELF-226 NAV trajectory consumes flipped Tax Liab values; **historical NAV recompute
back-fills correctly**."*

**`pfin.nav_daily` is append-only ADR-011 Decision 2 audit-class.** `054` describes it as the
*"append-only per-user daily NAV checkpoint"* and authors
`pfin.fn_nav_daily_block_mutation()` — *"SECURITY INVOKER; **BEFORE UPDATE OR DELETE**"*
(`054:235`, `054:257`). `055`'s role comment records the fences as deliberately
*"un-bypassable by the writer."* **A back-fill of that series is an UPDATE, and it is trigger-blocked
for every role including `service_role`.**

There are two readings and they have opposite dispositions, which is why this needs stating rather
than assuming:

- **If AC4 means the stored checkpoint series:** it is asking to rewrite immutable financial history
  with today's tax state, which D2 forbids by construction and which would be **wrong even if it
  were permitted** — §2.5.2 holds exactly ONE current-tax-year bracket set, so applying today's
  brackets to a 2024 checkpoint produces a number that was never true on that date. **I would veto
  this at the PR.**
- **If AC4 means the read-time trajectory composition** — that the chart recomputes from live inputs
  and therefore "back-fills" visually — it is fine, and the AC is merely worded in a way that names
  a forbidden operation.

**Resolve the wording before dispatch.** An AC that names a blocked write will either be built as a
blocked write and fail late, or be silently reinterpreted by whoever builds it, and the
reinterpretation will not be reviewed. ⚠ Note the direction if the first reading were somehow
enabled: it would make NAV history a function of *current* settings, so a bracket edit today would
retroactively change last year's reported net worth.

Related and smaller: **SELF-268 is labelled `role:frontend` only**, but AC1 says *"SELF-211 NAV
backend updated"* and the flip lands in `fn_nav_composition` (`051`). It is a backend + migration
issue wearing a frontend label; the label should not be what decides its review depth, and on this
map it does not.

### D-5 (flag) — three of SELF-269's ACs are unbuildable as written, and one states a false guarantee

The close-gate battery is the issue I care most about being right, so:

- **AC8 targets a relation that does not exist.** *"tenant A cannot create / update / read tenant
  B's `pfin.transaction_annotation` row."* Measured: `grep -rn "pfin.transaction_annotation"
  supabase/migrations` → **zero hits**. The built table is **`pfin.account_trans_annotation`**
  (`023`, with `031` adding its history child). A battery leg written against the AC's name would
  fail to compile; one written against a *guessed* name is unreviewable. ⚠ **And the wash-sale flag
  the AC is reaching for may not live there at all** — SELF-302 is the issue that posts wash-sale,
  and it is a `basis_adjust` reason, not an annotation column. Confirm the surface before writing
  the leg.
- **AC1 enumerates surfaces from outside the milestone** — SELF-259 / 260 / 261 / 262. Per D-3 these
  are unscheduled. A close-gate whose coverage list names unbuilt surfaces either blocks forever or
  gets quietly trimmed, and **the trim is the dangerous half**: this is the milestone's only
  isolation gate.
- **AC6 states a guarantee that is not one.** *"Bracket-row monotonicity invariant verified across
  replay scenarios (**SERIALIZABLE replace-all guarantees integrity**)."* SERIALIZABLE guarantees
  that concurrent transactions are equivalent to *some* serial order. **It guarantees nothing about
  whether a single transaction leaves the rows monotone** — that is the trigger's job, and per §3
  trap 1 a BEFORE-ROW trigger cannot see rows inserted later in the same statement. The parenthetical
  would let a reviewer accept SERIALIZABLE *in place of* the monotonicity check. Strike it.

**What AC9 gets right and should be kept verbatim:** *"NO `service_role` reach in any of
SELF-259-266 Wave 5 surfaces; all execute under `authenticated` tier per ARCH §4.1."* That is the
correct posture, it matches ADR-016's allowlist staying flat, and it is a leg that can fail.

**One literal to get right in AC4:** the PRD writes the three-way tag as `tax-deferred` / `tax-free`
with hyphens; the shipped CHECK at `003:101-102` is
`tax_treatment in ('taxable', 'tax_deferred', 'tax_free')` — **underscores**. A battery fixture
seeding the PRD's spelling is rejected by the CHECK, which reads as a passing fence rather than a
broken fixture.

### D-6 (note) — SELF-303 carries a prior Sec NOTE as a rider; do not let scoping drop it

SELF-303's description ends: *"Also carry the non-gating test-durability nit: add a co-located aal2
pass/block assertion to the `037` battery (currently relies on `033`'s battery for the re-created
`journal_insert` policy — Sec NOTE, non-blocking)."*

Recording it here for one reason: **a non-blocking finding attached to an issue's tail is the thing
scoping removes first**, and this one is a watcher for an aal2 conjunct that a *different*
migration's battery currently covers by coincidence of ordering. It is genuinely non-blocking and I
am not raising its severity. I am asking that it survive to the PR, and that if it is dropped, it is
dropped **explicitly** rather than by omission — a rider that vanishes silently reads at the next
review as never having existed.

### Where §4's catch criteria change

Three additions, all from the above. Everything else in §4 stands:

- **SELF-267:** `p_users_id` is **gone** from the signature; `p_jurisdiction` is enum-typed; the
  partial unique index on `(users_id, tax_jurisdiction)` is present **or** multi-account-per-
  jurisdiction is explicitly declared legal; the payment-row predicate and its sign are in the
  `comment on function`; the 2026-06-03 Gate B ruling lands in an ADR in this PR.
- **SELF-268:** AC4's meaning is resolved in writing before build, and if it means the checkpoint
  series it does not ship.
- **SELF-269:** AC8's relation name corrected to the built one; AC6's SERIALIZABLE parenthetical
  struck; AC1's coverage list reconciled against what V1.4 actually builds.

---

## §9 — Round 2: review of PM's A-9 / F-5 and Architect's Seam A + Seam E

Read from the refs, not from a worktree: PM `origin/meta/v14-preflight-pm` @ `b462816`,
Architect `origin/meta/v14-preflight-arch` @ `b98f2f5`. **Baseline stays `2cd94ae`** — `origin/main`
has moved to `7818504` by agent-def-only merges and is deliberately not re-baselined here.

⚠ **Recording a convergence, because it is a cross-check signal rather than a courtesy.** Architect's
Seam B (line 115) corrects my F-1 — *"Sec had the tree and not the dump"* — and reaches the same
conclusion my pass 2 reached independently from the dump, **including the consequence that matters
most to me**: Gate B Option A is an enum column, not FK-shaped, so it adds no Decision-3 member and
retires my pass-1 `#18` warning. Two agents, two routes, same answer, neither having read the other.
That is worth more than either finding alone.

### 9.1 — PM's A-9 (tax-authority ledgers double-count payments in NAV): **CONFIRMED, and yes, I own it**

**This is a money-correctness flag on my side of the line**, not merely a PRD-wording seam: it changes
the top-line figure by a real amount in a predictable direction, and the direction is the silent one.

**Arithmetic verified independently against the tree**, not accepted from the memo. `051:131` defines
`nav = gross_total − debt − realized_tax_liab − unrealized_tax_liab`, and `051:157`/`051:167` group
every account by `account_type` with **`manual_other` as category 5 — inside the asset half of the
buildup.** So for a payment P:

- checking `−P` → `gross_total −P`; the IRS ledger `+P` → `gross_total +P`. **Net zero, correctly** —
  money moved between two of the user's own accounts.
- YTD Paid `+P` → Realized Liability `−P` → NAV `−(realized −P)` = **NAV `+P`**.

**NAV rises by exactly the amount the user just paid the government.** PM's reading is right, and
PM's corroboration is the strongest part of it: `041:304` seeds `Liabilities / EstTax-Pending`
(*"Estimated Taxes Due but not yet paid"*), so the **incumbent books the net obligation and treats
paid money as gone** — which is §2.5.4's net-of-payments form only if the ledgers sit outside the
composition. **I concur with option (A).** Option (C) overstates NAV by YTD Paid and is not a
candidate.

**Now the question I was actually asked — does the exclusion itself open a fail direction? Yes, three,
and they are not symmetric.** Naming the losing side is required of any replacement control:

1. **⚠ The exclusion is gated on a nullable, user-set attribute, so its DEFAULT state is the BUG.**
   An unmarked IRS account is not excluded, and the double-count returns **silently, with no error and
   no marker** — NAV overstated by YTD Paid. This is structurally identical to M-5's
   `tax_relevant DEFAULT false`: absence of a mark produces the wrong answer rather than no answer.
   ⚠ **And the two halves fail in OPPOSITE directions from the same omission**, which is what makes it
   worse than either: an unmarked ledger is simultaneously excluded from YTD Paid (Funds Due
   **overstated**) and included in the buildup (NAV **overstated**). The user sees a bigger net worth
   *and* a bigger tax bill, and neither number contradicts the other visibly.
2. **The inverse: a mis-designated ordinary account VANISHES from NAV.** Marking a real checking
   account `irs` silently removes its balance from the buildup — NAV understated. Conservative in
   direction, but it defeats the one property §2.1.5 is specified to have: PRD §2.1.5 commits that the
   table makes NAV *"visually traceable from its parts"* and *"the single headline number doesn't hide
   its structure."* **An excluded account appears nowhere, so the foot cannot be reconciled by hand.**
   Under the ADR-049 non-silence discipline the exclusion must be **rendered, not merely applied** — an
   excluded-ledger row or a footnote naming the designated accounts and their balances. I do not
   require a particular presentation; I require that the exclusion is visible somewhere on the surface
   whose selling point is traceability.
3. **The exclusion predicate and the YTD-Paid predicate MUST be one extracted predicate, not two.**
   They live in different objects (`fn_nav_composition` vs the YTD-Paid reader) and are gated on the
   same attribute. If they drift — one written `= 'irs'`, the other `is not null`, or a third
   jurisdiction added to one — the result is a **partial** exclusion, and the partial cases are exactly
   the two failures above. This is ADR-063 Decision 2's extraction discipline verbatim: *"a seam's
   answer is stated once, and consuming issues cite it… four restatements of one predicate drift
   independently and the drift is invisible, because each copy is locally plausible."*

**⚠ A-9 and Seam E COMPOSE, and the composed gap is not what either seam's copy will say.** Under
Seam E Option A the headline (`fn_compute_nav`) and the §2.1.5 foot already differ by the two tax
lines. Add A-9 and they differ by **the tax lines PLUS the designated ledgers' balances** — unless the
A-9 exclusion also lands in `fn_compute_nav`, which Seam E Option A is specifically designed not to
touch. So either (i) the exclusion lands in both and Seam E's no-touch property is broken, or (ii) it
lands in §2.1.5 only and the "gross NAV vs tax-adjusted NAV" copy is **wrong as written**, because the
difference is no longer only tax. **Neither seam's memo states this and it is not derivable from
either alone.** Route to Architect: the two rulings must be taken together, and the copy drafted
against the composed gap.

**One consequence for the trajectory, recorded so it is not read later as a defect.** Whenever the
A-9 exclusion lands, every `pfin.nav_daily` row already written was computed with the ledgers
**included**. The series will carry a step at the changeover that is a **definitional** change, not a
portfolio movement, and it cannot be corrected — `054`'s `fn_nav_daily_block_mutation` is BEFORE
UPDATE OR DELETE. Same class as Seam E's mixture problem, same append-only cause, and it lands on the
same table; whatever Seam E rules about discriminating definitions should absorb this too rather than
be decided twice.

### 9.2 — PM's F-5 lean (keep `tax_relevant`'s DEFAULT; A+C): **AGREEMENT, with a residual that agreement does not discharge**

**No daylight on the ruling.** My §5 F-5 named **(A)** as my lean and described **(C)** as *"the cheap
half of (B)"*; PM's A+C is precisely that union. I do **not** ask for the DEFAULT to be dropped: it is
load-bearing for the provisioning INSERT, and a narrowing change breaks every fixture seeding the
barred value. **Recommend F/CTO rule A+C.**

⚠ **Stating the residual explicitly, because "Sec agrees with F-5" is exactly the sentence that would
otherwise be read as clearing M-5, and it does not.** My M-5 objection was never to the DEFAULT — it
was, verbatim, *"that the V1.4 consumer not treat `false` as an answered question."* A+C rules on the
**column**; it does not constrain the **reader**. Both halves are still owed and neither is implied by
the ruling:

- The §2.5.1 consumer must not read `false` as *"this bucket was examined and found non-tax-relevant."*
  Measured in `041`'s seed: **all 36 asset rows** carry `false` / `null` (`041:275-310`), and of the
  **27** cash-flow rows **9 are `true` and 18 are `false`** (`041:321-347`). For those 54 rows `false`
  is the seeded default and nothing more. ⚠ `091` then adds two Equity rows to the **posting** side
  (`Contribution` `true`, `Distribution` `false`), so a reader counting against
  `posting_prototype_default` rather than `taxonomy_default` gets different figures — state which
  table any count is over.
- **F-6b still stands and is the thing that actually fixes this**: the tax-value inventory session
  (`BACKLOG.md:1190`, SELF-245's struck AC4 deferred to V1.4) is **still unowned**. Ruling A+C without
  scheduling that session leaves the values unexamined behind a column that now has an explicit
  comment saying they were not examined — which is honest, and still wrong in §2.5.1's output.

### 9.3 — Architect's Seam A Decision-3 sub-part: **CONFIRMED as the only candidate; the membership claim CONTESTED as unconditional**

**Confirmed, without reservation:** ✅ `tax_bracket_row`'s parent reference is **the milestone's only
Decision-3 candidate**, now that Gate B Option A is settled as an enum column. ✅ Decision 18's locked
*"NOT a new instance… settings writes are user-session-bounded"* clause **argues from the write path
and Decision 3 turns on column shape** — Architect quotes D18's own amendment on this and is right;
my §3 reached the same conclusion by the same route. ✅ **No label is drafted in advance**, and `#18`
stays unallocated until the migration allocates it. ✅ The **tail** of D18's sentence — the V2+
live-tax-API trigger, the mandatory Sec re-consult, the Lock 12 mod #2 fence going V1-SHIP-BLOCK —
is untouched and live. Architect protecting that tail unprompted is the correct handling.

**Contested — and the contest is narrow, mechanical, and moot under the option we both prefer.**
Seam A's framing line states the membership **unconditionally**: *"the unbuilt `pfin.tax_bracket_row`
carries an FK-shaped reference column crossing a tenant boundary, so it takes the next canonical
label."* **That is true under Option C and false under Option A**, and Seam A's own option table
already half-concedes it by listing the family extension as a *cost of A* while listing "no
Decision-3 family extension" as a *buy of B*.

**The mechanism, stated so it can be checked rather than weighed.** Decision 3's predicate is an
FK-shaped column *"that crosses an isolation boundary."* A crossing requires **two** tenant facts that
can disagree:

- **Option C** (child carries its own `users_id` **and** `schedule_id`): two anchors, they can
  disagree, a fence can detect the disagreement. **Genuine family member, P1 local-anchor fence, and
  the fence has a real failure mode.** Every canonical instance has this shape — #2's
  `replaces_trans_id` is a *second* reference beside the tenant-bearing `account_id`; #14's `lot_match`
  compares the two legs' resolved tenants against each other.
- **Option A** (child carries **only** `schedule_id`): `schedule_id` **is** the tenant anchor. There
  is no second fact, so there is nothing to mismatch — a row pointing at another tenant's schedule
  does not become *inconsistent*, it becomes *that tenant's row*, and whether the writer was allowed
  to do that is an **RLS** question (a chain-resolved `EXISTS` on the parent), not a matched-tenant
  question. This is the disposition ADR-011 Decision 9's 2026-07-24 amendment already records for
  `account_trans_annotation_history.trans_id` — *"the sole anchor / NOT-D3"* — and the same ground on
  which `posting_prototype_default` sits outside the family.

⚠ **Why I care enough to contest a point that changes no recommendation: under Option A a
matched-tenant fence would be a leg that CANNOT FAIL.** With one tenant fact there is no second value
to compare it against, so the trigger would resolve the parent's `users_id` and compare it to…
itself. That is precisely the anti-pattern ADR-062 Decision 2 rejected in writing — *"a constraint
over a by-construction property is a leg that reads to a later reviewer as a live guarantee and is not
one"* — and it would enter the canonical enumeration as instance `#18`, where a future reviewer
auditing the family finds a fence with no adversarial test and no way to write one.

**Disposition: I concur with Architect's Option C lean, which makes this disagreement moot**, and I
concur for a reason worth adding to Architect's: **C is the only grain whose fence is falsifiable.**
Architect's stated ground — *"the redundancy it introduces is exactly the thing the fence checks"* —
is the same observation from the other side. **Requirement, whichever way F/CTO rules:** the migration
states which grain it built and, **if it built Option A, it does NOT author a matched-tenant fence and
does NOT take a canonical label** — it carries chain-resolved RLS on all four verbs and says in its
header why no label was taken. An unnecessary label is as damaging to the enumeration as a missing one.

**Also confirmed from Seam A, and I want it in my own file so it is not carried only in Architect's:**
the `025` aal2 backstop is owed on both new tables' `authenticated` policies, and `025`'s
`pfin.user_settings` exclusion is **non-negotiable-for-`user_settings`** and **does not generalize** to
siblings. `090`'s header records the same reasoning for `cashflow_target`. The bracket tables get the
clause.

### 9.4 — Architect's Seam E (four-part flip, one-way door): **CONFIRMED and EXTENDED. Option C is VETOED.**

**VETO — Seam E Option C (backfill `pfin.nav_daily` history to the new definition).** F/CTO sign-off
required to override. Two independent grounds, either sufficient:

1. **It is a write to an ADR-011 Decision 2 append-only audit-class surface.** `054` authors
   `pfin.fn_nav_daily_block_mutation()` as **BEFORE UPDATE OR DELETE** (`054:257`), and `055`'s role
   comment records the fences as deliberately *"un-bypassable by the writer"* — the ETL identity can
   neither `DISABLE TRIGGER` nor set `session_replication_role`. Executing this option therefore
   requires either weakening a D2 fence or running as an RLS-exempt owner outside every layer, and
   **both of those are separately veto-grade under my standing list.**
2. **The values would be fabricated.** Architect's phrasing is exact and I adopt it rather than
   restate it: *"a fabrication with the shape of a measurement."* §2.5.2 holds one current-tax-year
   bracket set, so there is no recoverable tax state for a past date. A backfilled series would be a
   *current* opinion about the past, indistinguishable in the table from a contemporaneous measurement.

This is the same finding as my §8 **D-4**, which I raised as *"veto-shaped if taken literally"*.
**Three agents reached it independently** — my D-4 from `054`'s triggers, Architect's Seam E from the
`fn_compute_nav` identity, PM's SELF-268 note (*"Seam E Option C, rejected on the record"* — strike
AC4). I am now stating it as a veto rather than a flag because the flag-first step has been taken and
the answer did not move.

**On Options A and B — I do NOT object to either, and I state that explicitly.**

- **Option A (Architect's lean, and mine):** it is the only option that never mixes definitions in an
  append-only table. **I have no Sec objection.** Its cost is copy, not schema — but see 9.1's
  composition warning: the copy must describe the **composed** gap if A-9 also lands.
- **Option B (`nav_definition` discriminator) is ACCEPTABLE, not preferred, on three conditions.**
  Adding a column to an append-only table is **not** an immutability violation — the trigger blocks
  row UPDATE/DELETE, not `ALTER TABLE … ADD COLUMN` — so the D2 objection does not apply, and I say so
  rather than let a D2 reflex kill a legitimate option. The conditions:
  (i) **`085`-shape discipline** — add nullable, **total** backfill, then `set not null`, **no
  DEFAULT**, so a future INSERT must state the definition rather than inherit one. NULL must not be
  representable, or a reader coalescing NULL to the current definition **relabels the entire history**;
  (ii) the backfill value is a **claim about history** — it asserts every existing row is pre-tax,
  which is true here and must be stated in the `comment on column` as an assertion, not implied;
  (iii) **every trajectory reader is enumerated and each branches** — `062` `fn_nav_series`, `067`,
  `071`, `073`. ⚠ That enumeration is the part that goes stale: a reader added later inherits no
  branch and silently averages two definitions. If B is taken, the enumeration needs a watcher, not a
  comment.

**Extended — the catch Architect made that I did not, and it changes my §4.** Seam E part 3:
`api/src/lib/components/NavCompositionTable.svelte` renders
`{row.isTaxPlaceholder ? usd.format(0) : usd.format(row.displayValue)}` — **it ignores `displayValue`
entirely for those two rows.** So correct values can land at the DB layer and the surface still
renders `$0`, with no error at any layer. **This is the fail-open shape a green suite cannot see**, and
it is exactly why the live walk gate exists. My §4 SELF-268 criteria gain a fifth item:

> **(5) All four layers are demonstrated on one walk, in one session:** `051`'s emitted value ≠ 0 ·
> `nav-composition.ts` no longer flags `isTaxPlaceholder` · `NavCompositionTable.svelte` renders
> `displayValue` rather than a literal zero · and the **rendered figure in the browser** matches the
> DB value. A test at any single layer passes while the layer above it discards the result.

⚠ **And one Sec-relevant item from Seam E's volatility note, which I confirm:** `051` and `049` are
`language sql` with **no volatility keyword**, so both default to `VOLATILE`. A replacing body that
adds `stable` is a planner-contract change no value assertion can see, and any out-of-band
`ALTER FUNCTION … STABLE` is **silently erased** by a later `create or replace`. State the intended
volatility explicitly in the replacing migration and pin it in the paired battery — a declared
volatility is a testable claim, and an unpinned one is an assertion with no watcher.

### 9.5 — What round 2 did NOT change

- **§10 catalogued-instance ledger:** unchanged. Nothing in A-9, F-5, Seam A or Seam E adds, reorders
  or renumbers a catalogued instance; no layer-attribution moves; no surface becomes "four-layer".
  ⚠ Seam E's *"four-part change"* and *"four layers"* are **not** the §10 four-layer framing and must
  not be read as it — this Decision explicitly disclaims a per-surface four-layer composition. Path B;
  no count carried. **Recording the near-collision deliberately**, because the PR #368 catch in
  Decision 4's own CHANGELOG is precisely a *"four"* vocabulary collision inherited from a
  mislabelled source.
- **SECURITY DEFINER allowlist:** untouched. Nothing proposed in round 2 authors a DEFINER function;
  `fn_nav_composition` stays INVOKER (`051:146`).
- **RT-26 allowlist:** no addition, no ADR-016 amendment. Seam E and A-9 are `authenticated`-tier
  read paths.
- **Decision 3 family:** flat, and `#18` unallocated. The only candidate is Seam A's, conditional on
  the grain ruling per 9.3.
- **The §1 map:** unchanged — all nine still MANDATORY, none light-loop eligible. Architect reaches
  the same conclusion for SELF-268 by ADR-066 D1(b), independently.

---

## §10 — Part B: SELF-259 / 260 / 261 / 262 (the Platform dependencies)

Source: `/Users/mosko/Projects/mosko-fintech/temp/v14-preflight/issue-dump-deps.md`, md5
`c35fe5ef96caa6b647655cb39a0bfea1`, verified in-turn. Baseline still `2cd94ae`.

⚠ **Note on the section number:** this is the tenth section of this file. It has **nothing to do
with the ADR-011 Decision 4 "§10" meta-pattern**, and no statement here touches that ledger. Said
plainly because a "§10" in a Sec document is exactly the collision that produces an
attribution-drift catch.

| Issue | Sec verdict | Triggering surface |
|---|---|---|
| **SELF-259** | **MANDATORY** | Two new tables, new enum type, RLS, a matched-tenant trigger, a monotonicity trigger, and a Lock 14 replace-all endpoint. This is the milestone's principal schema surface. Its own labels already carry `sec-joint-review` + `surface:rls`. |
| **SELF-260** | **MANDATORY — I contest its AC5** | AC5 says *"Sec advisory review on seed values (no Sec joint-review required — data-only against Issue 1 schema)."* See below. |
| **SELF-261** | **MANDATORY** | A new table with an FK-shaped reference to the immutable ledger, its own `users_id`, and UPDATE permitted — a genuine ADR-011 D3 candidate and a D2-adjacent mutability decision. Labels already carry `sec-joint-review`. |
| **SELF-262** | **MANDATORY** | The unified computation helper: every money figure in §2.5 comes out of it, and its RLS composition spans six relations. Labels already carry `sec-joint-review` + `V1-ship-block`. |

**None is light-loop eligible** — all four author DDL or a money path, failing ADR-066 (a) and (b).

### ⚠ 10.1 — THE FINDING THAT MUST NOT REACH A MIGRATION: both drafted D3 labels are STALE, and one would REUSE A RETIRED LABEL

SELF-259 AC4 instructs a matched-tenant trigger *"per ADR-011 Decision 3 cross-tenant FK-bypass
family (**4th instance**)"*. SELF-261 AC3 says the same for *"(**5th instance**)"*.

**Those numbers are the pre-reconciliation Wave-5 operational grain and both are already taken by
different instances.** Read live at `2cd94ae`: `#4` is
`monthly_report_account_snapshot.account_id` (DDL-deferred), and `#5` is
`pfin.account.sub_cat_id` — **DROPPED at `048`**. Decision 3's DROP resolution, consequence (b), is
explicit: *"The #5 label is **retired-in-place, NOT renumbered or reused**… no future instance
reuses #5."*

**A migration written against AC3 would stamp `#5` into a `comment on function` on a live catalog
object** — asserting a canonical label that the canon records as retired for a different, removed
column. Decision 3's own 2026-08-04 fold-in bullet (c) describes what that costs, and it is worse
than untidiness: *"a reviewer obeying the standing read-Decision-3-live discipline finds no #16 here
and correctly concludes the migration invented a label."* Here they would find `#5` and correctly
conclude the migration **resurrected** one.

**Requirement, both issues: the ACs say "the next canonical label, allocated at the migration and
folded into ADR-011 Decision 3 in the same PR" and name NO NUMBER.** That is Decision 3's standing
discipline, D18's *"none may be drafted in advance"*, and the 2026-08-04 rule that the fold-in is
due **in the PR that DDL-realizes the instance**. I am not naming the number here either.

### 10.2 — SELF-259: the drafted grain is Architect's Option A, so my §9.3 contest is now LIVE

AC2 gives `tax_bracket_row (id, schedule_id, bracket_floor, bracket_rate, created_at)` — **no
`users_id`.** That is **Option A**, and per §9.3 it means `schedule_id` is the **sole tenant anchor**:
there is no second tenant fact to disagree with it, so **AC4's matched-tenant trigger has nothing to
compare and cannot fail.** AC4 and AC2 are jointly inconsistent — you cannot have Option A's shape
and Option C's fence. **Resolve at the Seam A ruling, and if Option A stands, AC4 is struck** and
replaced by chain-resolved RLS on all four verbs, with the migration header stating why no label was
taken.

**Nine further catch criteria, each measured against a built sibling rather than asserted:**

1. **⚠ AC3 specifies a WRITE fence only.** *"RLS **WITH CHECK** on both tables"* — a `WITH CHECK` is
   an INSERT/UPDATE clause. **It says nothing about SELECT**, and AC3 names no `USING`, no per-verb
   policies, and **no `025` aal2 backstop clause**. `090`'s battery header records the shipped
   standard for a Lock-14 table: owner RLS *"on ALL FOUR policies (select/insert/update/delete)"*,
   each ANDed with the aal2 clause, full `authenticated` CRUD, **anon zero-grant, `service_role`
   UNGRANTED**. AC3 as written is materially weaker than every built sibling. This is the single
   biggest gap in the four issues.
2. **`users_id` needs `default auth.uid()` and `on delete cascade`.** AC1 gives
   `users_id UUID NOT NULL REFERENCES auth.users(id)` — no default. Without it the client must
   supply `users_id`, which **is** the mass-assignment surface Lock 14 mod #1 exists to close.
   `090` and `074` both carry `default auth.uid() references auth.users (id) on delete cascade`.
3. **Two-sided NaN CHECKs on all three numerics** — `standard_deduction`, `bracket_floor`,
   `bracket_rate`. Per M-10 and `090:75-77` verbatim: a one-sided `>= 0` **admits NaN**. A NaN rate
   propagates to a NaN tax and a NaN NAV with no error on the path.
4. **`bracket_rate` needs a unit and a domain CHECK** (M-7). `NUMERIC NOT NULL` does not say whether
   `22` or `0.22` is 22%. The `comment on column` states the unit in words.
5. **Nothing forces the first bracket's floor to zero** (M-7). `UNIQUE(schedule_id, bracket_floor)`
   prevents duplicates and AC5 enforces ascent, but a schedule whose lowest `bracket_floor` is
   11000 leaves the first $11,000 matched by no bracket and **taxed at zero, silently**. Monotonicity
   cannot catch this — a sequence starting at 11000 is perfectly monotone.
6. **AC5's monotonicity trigger is the §3 trap-1 shape and will misfire under AC6's replace-all.**
   A BEFORE ROW trigger sees only already-committed siblings, so it rejects any legal replace-all not
   inserted in ascending order and cannot see rows inserted later in the same statement. Make it a
   `CONSTRAINT TRIGGER … DEFERRABLE INITIALLY DEFERRED` over the schedule. ⚠ And per ADR-011
   Decision 4's 2026-09-03 amendment it is **trigger-realized and therefore inert under
   `session_replication_role = replica`**, together with the FK it sits beside — name that in the
   header, and the restore/bulk-load runbook owes these tables a post-load validation step.
7. **✅ Non-objection, stated because it resolves something I raised:** AC2's
   `ON DELETE CASCADE` on `schedule_id` closes my §3 trap 4 (a replace-all deleting the parent
   orphaning children beyond any policy's reach). I do **not** require the delete-children-first
   ordering I asked for in §3; the cascade is the better answer.
8. **`SERIAL` / `INT` against the project convention.** `009`'s header records this exact correction
   already made once — *"AC SERIAL→identity"*. The convention is
   `bigint generated always as identity`. Not a security finding; raised so it is corrected at the
   DDL rather than shipped and re-litigated.
9. **AC2 and SD-04 disagree on the child's columns.** SD-04 records
   `(schedule_id, ordinal, lower_bound, marginal_rate)`; AC2 gives
   `(schedule_id, bracket_floor, bracket_rate)` and **no `ordinal`**. SD-04 is Sec-owned: **I will
   reconcile it to whatever the DDL ratifies**, after the ruling. It is not the migration author's to
   guess and not the UI AC's to originate.

### 10.3 — SELF-260: I contest AC5. Seed values a money path reads are joint-review-mandatory

AC5 asserts *"no Sec joint-review required — data-only against Issue 1 schema."* **The precedent is
directly against it and is only a week old.** ADR-062's Consequences: *"Sec joint-review is mandatory
at the implementing PR — a new column on the posting vocabulary that a money-path filter reads."*
These rows are not incidental data: **`bracket_rate` and `bracket_floor` are the coefficients of
every money figure in §2.5**, and `standard_deduction` is subtracted before every ordinary walk. PM
reaches the same conclusion for SELF-263's seed delta by the same route.

**Scoping my own review honestly, because "Sec reviews the seed" could be read as more than I can
deliver:** I am **not** a tax authority and I will **not** certify that the Federal or CA figures
match IRS Pub 17 or FTB Form 540 — that is F/CTO's, and the AC correctly assigns the values to
F/CTO. What I check is **shape and posture**: the rate unit matches the column's stated unit
(10.2 item 4); the lowest floor is zero (item 5); ascent holds; no NaN; the values carry a
**source and a tax year in the migration header**, so a later reader can tell a 2026 bracket from a
2027 one; and the seed is idempotent.

⚠ **One zero-value sentinel, per AC1:** `federal_lt_cg` gets `standard_deduction = 0`. That is
**correct** — PRD §2.5.3 says *"no standard deduction applied to this schedule"* — but a structural
zero is indistinguishable from a data-entry zero and from an unset value. The `comment on column`
should record that `0` on the LT-CG schedule means *"none applies, by construction"*, or a later
tidy-up reads it as missing data and "fixes" it.

### 10.4 — SELF-261: it duplicates a built substrate, and the copy is the one WITHOUT the audit trail

**This is my substantive objection to SELF-261 and it is a security argument, not a tidiness one.**

`pfin.account_trans_annotation` (`023`) already exists and is, measured, the same construct at the
same grain: `trans_id bigint primary key references pfin.account_trans (trans_id)` — **one mutable
overlay row per immutable ledger row** — carrying `sub_cat_id`, a free-text `note`, and
`created_at` / `updated_at`. SELF-261 AC1 proposes `UNIQUE(account_trans_id)` — **the same grain, the
same parent, and the same stated rationale** (*"separate annotation table (NOT column on
`account_trans`) per Lock 10 immutability semantics… Forward-compat for future per-transaction
annotations"*). That rationale describes `023`.

**Why it matters to me specifically.** `031` authors `fn_reclass_history_insert` — an
**ADR-011 Decision 9 SECURITY DEFINER allowlist entry** — and its capture trigger is
`after insert or update **on pfin.account_trans_annotation**` (`031:348-349`), writing the
append-only `account_trans_annotation_history`. **That capture is scoped to that one table.** A
second annotation table inherits none of it, so:

> **Wash-sale marks — which change a user's taxable income — would be mutable and UNTRACKED, while
> Sub-Cat reclassifications on the sibling table are tamper-evident.** Two overlays on one immutable
> ledger, one audited and one not, is a worse posture than either alone, because a reader who knows
> the ledger is audited will reasonably assume its annotations are.

**Sec position: prefer adding `is_wash_sale` + `disallowed_loss_amount` to `pfin.account_trans_annotation`.**
It is additive, it inherits the `031` capture for free, and it takes **no new D3 label** (`023`'s
`trans_id` is already the tenant chain and `#10` already covers its `sub_cat_id`). **The design call
is Architect's** — there may be a grain or lifecycle reason I cannot see — but if a separate table is
chosen, **the `031`-equivalent capture must ship with it in the same migration**, and that is a new
DEFINER function and therefore a gate under my standing list.

**If SELF-261 ships as drafted, four further catches:**

1. **AC1 names the wrong parent column.** `pfin.account_trans(id)` — the PK is **`trans_id`**
   (`023` references `pfin.account_trans (trans_id)`; Decision 3 entries #2 / #14 name it likewise).
2. **It IS a genuine D3 member** — unlike SELF-259 under Option A. It carries **its own `users_id`
   AND** `account_trans_id`, so two tenant facts exist and can disagree; the referenced side resolves
   its tenant through the account chain. That is the **hybrid** shape of instance `#12`
   (`account_trans_annotation.journal_id`), not a plain local-anchor. The fence is `BEFORE INSERT OR
   UPDATE` (AC4 permits UPDATE, so an INSERT-only fence would leave the repoint path open), INVOKER,
   `set search_path = ''`, NULL-safe fail-closed. **Label per 10.1 — no number in the AC.**
3. **⚠ This means Architect's *"the milestone's only Decision-3 candidate"* is true of the nine and
   FALSE if SELF-261 is promoted.** Promoting the deps adds a **second** candidate. Flagged because
   that sentence, quoted later, would license a reviewer to stop looking after one.
4. **`is_wash_sale BOOLEAN NOT NULL DEFAULT FALSE` is the M-5 shape again** — a fail-open default on
   a flag a money path reads, and `disallowed_loss_amount NUMERIC NULL` needs the two-sided NaN
   CHECK. ADR-062 chose *no DEFAULT* for exactly this reason on `is_tax_payment`; here the default is
   more defensible (an unmarked transaction genuinely is not a wash sale, and the user is the only
   possible source of the mark) — so I do **not** require dropping it. I require the `comment on
   column` to say that `false` means *"not marked"*, not *"examined and found not to be a wash sale"*.

### 10.5 — SELF-262: the signature is RIGHT, and it makes SELF-267's wrong one unmistakable

✅ **`pfin.fn_compute_tax_liability(p_data_as_of DATE DEFAULT CURRENT_DATE) RETURNS JSONB`, SECURITY
INVOKER — no tenant parameter.** This is the correct shape, it matches every built helper
(`fn_compute_nav(p_as_of)`, `fn_nav_composition(p_as_of)` at `051:143`), and **it strengthens D-2**:
the unified helper gets it right while SELF-267's `fn_ytd_paid_per_jurisdiction(p_users_id UUID, …)`
gets it wrong, **and 267's output is consumed by 262** (267 AC4). Two composed INVOKER functions with
opposite tenant-parameter conventions is how the wrong one gets copied. **Drop `p_users_id`.**

**⚠ 10.5a — AC2's ST/LT rule is wrong tax law, and it errs toward UNDERSTATING tax.** AC2 reads
*"route ST/LT by Open Date (**>365d → LT**)."* The Federal test is **more than one year**, not more
than 365 days. In a period spanning a leap day, an asset held 365 days has been held **less** than
one year and is **short-term** — AC2 routes it to the LT CG schedule (0/15/20%) instead of the
ordinary schedule. **Understates tax, silently, and only in leap years**, which is as close to
undetectable as a defect gets. Use `sale_date > acquisition_date + interval '1 year'` and let the
calendar decide. ⚠ **And the boundary itself needs pinning:** an asset sold *exactly* on the one-year
anniversary is **short-term**; only the day after qualifies. That is a half-open boundary, the same
class of correction ADR-011 Decision 19 Edit 1 made for the as-of filter before first use.

**10.5b — AC2 does not say what happens when there is no Open Date.** This is M-1 landing on the
issue that owns it. `lot_match` is the only holding-period source and *"unmatched sells leave basis
on the books"* (`059:639`) is a sanctioned state. AC2 needs the F-2 ruling written into it.

**⚠ 10.5c — AC2's wash-sale treatment DELETES a loss that tax law DEFERS.** *"wash-sale
`is_wash_sale = TRUE` disallowed-loss exclusion."* A wash-sale disallowed loss is **added to the
basis of the replacement lot** — deferred, not extinguished. Excluding it from §2.5.1 and adding it
nowhere makes the loss **disappear permanently** from the user's tax picture. **SELF-302 is the issue
that posts it to basis**, and SELF-302 is in V1.4 while SELF-262 is not yet. So the ordering matters
with a money consequence: **262 before 302 = a vanished loss; 302 before or with 262 = correct
deferral.** State the dependency in both directions, or the two issues each look complete alone.

**10.5d — the three ACs that are missing entirely, and every built function in this tree has all
three.** None of AC1–AC10 mentions:

- **`set search_path = ''`** — the injection fence on every function in `pfin`.
- **`revoke execute … from public` + `grant execute … to authenticated`** — without the revoke,
  `anon` may execute it. For an INVOKER function RLS still fences the rows, so this is the weakest of
  the three fences rather than the perimeter — but it is a fence, it is universal in this tree, and
  its absence from a ten-item AC list is how it gets omitted.
- **An explicit volatility declaration.** Per Seam E's measurement, `051` and `049` are
  `language sql` with no keyword and therefore default `VOLATILE`. A declared volatility is a
  testable claim; an undeclared one is an assertion with no watcher, and a later
  `create or replace` **silently erases** any out-of-band `ALTER FUNCTION … STABLE`.

**10.5e — AC1's RLS composition spans `nav_daily`, which is written by a privileged writer.** The
helper reads it as `authenticated` under INVOKER, so `nav_daily`'s SELECT policy must admit the owner
— assert it in the battery rather than assume it, and assert that a **cross-tenant caller gets no
rows and the function fails closed rather than returning `0`** (the `049`/`051` posture; a zero tax
liability and an invisible tenant are different facts).

**10.5f — `DEFAULT CURRENT_DATE` should be `pfin.fn_server_today()`.** They evaluate identically
today, and that is exactly why the convention exists: `073:391` uses `v_today :=
pfin.fn_server_today()` so that every surface shares **one** derivation. M-4's tax-year boundary
rides on this — under the `061` UTC pin, a bare `CURRENT_DATE` in a §2.5 helper flips the tax year
~7 hours early for a Pacific user.

### 10.6 — What promoting these four changes in my earlier findings

- **D-3 is DISCHARGED by the promotion itself.** Its entire content was that SELF-259 / 260 / 262
  were outside the milestone while six issues depended on them. Promote them and the dependency gap
  closes. ⚠ **The sub-finding survives and is now sharper:** SELF-259 is *"the milestone's principal
  schema surface"*, and 10.2 measures its RLS AC as weaker than every built sibling — so the
  question of who reviews it at what depth is answered (MANDATORY), and the answer arrived because
  the issue was promoted rather than absorbed into a UI issue.
- **D-5 is REFINED, not withdrawn.** SELF-269 AC8's `pfin.transaction_annotation` is not a mistaken
  name — it is a relation **SELF-261 would create**. So: *if 261 is promoted and ships as drafted,
  AC8 is buildable; if 261 is not promoted, or if 10.4's preferred additive route is taken, AC8 is
  unbuildable as written and must name `pfin.account_trans_annotation`.* **AC8 cannot be finalized
  before the 10.4 ruling.** D-5's other two halves (AC1's coverage list, AC6's false SERIALIZABLE
  guarantee) are unchanged, and AC1's list becomes coherent under promotion.
- **D-2 is REINFORCED** — see 10.5.
- **§9.3 is now LIVE rather than hypothetical:** SELF-259 AC2 drafts Option A and AC4 instructs the
  Option C fence. The two ACs are jointly inconsistent and the Seam A ruling resolves them.
- **§9.3's "only D3 candidate" needs a rider:** true across the nine, **false once SELF-261 is
  promoted** — there would be two (10.4 item 3).
- **The §1 map is unchanged**, and gains four rows, all MANDATORY.
- **M-1, M-3, M-4, M-7, M-9, M-10 all now have named owners** — 262 for M-1/M-9, 259/260 for
  M-7/M-10, 268 for M-3, 262 for M-4. **M-5 and F-6b remain unowned**; nothing in these four
  discharges the `tax_relevant` / `tax_character` inventory.
- **Ledgers still flat.** No catalogued §10 instance moves; **the Decision 3 family gains one or two
  members at the migrations that realize them, and no label is drafted anywhere in this file.**
  SECURITY DEFINER allowlist untouched **unless** 10.4's separate-table route is taken, in which case
  the `031`-equivalent capture helper is a new DEFINER entry and a gate. RT-26 allowlist unchanged —
  SELF-269 AC9's *"NO `service_role` reach"* is the correct posture and I endorse it verbatim.
