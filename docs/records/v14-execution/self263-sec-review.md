# SELF-263 — Security joint-review (ADR-011 D1 / D2-adjacent / D3 / D4 mandatory gate)

**Reviewed ref:** `origin/feature/self-263` at **4ee2a10**, base `origin/main` at **762f793**.
**Date:** 2026-09-03. **Reviewer:** Security Engineer. **Worktree:** `~/Projects/mosko-fintech-worktrees/sec-263` (detached at 4ee2a10; source read-only).

---

## Verdict — **AMBER**

**One blocking condition, owner QA.** The migration's own header states a control that is not
built: it names the silent-miss cost of its equality guards and says *"The watcher is QA's paired
battery asserting the POST state row by row."* For the two **DEFAULT** tables — the provisioning
source every future signup inherits — that watcher does not exist for 27 of the 29 corrected
values. See **A-1** below for the catch criterion and the inversion argument.

Nothing else blocks. The migration's values, tenant posture, reach decision, ADR-011 D1 / D3 / D4
evaluations, ADR-057 / ADR-058 D3 / ADR-062 D5+D6 compliance, and the four column comments are all
correct as shipped and were measured, not accepted. Findings F-1 through F-6 are documentation
accuracy and carry-forward routing; none blocks merge.

---

## Verify-hook — canonical anchors read verbatim and live at 4ee2a10

| Anchor | Read | Result |
|---|---|---|
| ADR-011 Decision 1 (four clauses a–d) | verbatim | see D-1 |
| ADR-011 Decision 3 (rule sentence + live numbered family) | verbatim | family **+0**; next label still **#18** |
| ADR-011 Decision 4 (catalogued list + three-layer composition) | verbatim | ledger **UNCHANGED**; three axes clean |
| ADR-011 Decision 9 (SECURITY DEFINER allowlist) | live | untouched — branch authors no function |
| CI-fenced RT set (`grep -rhoE 'RT-[0-9]{2}' .github/workflows/`) | measured | RT-05 RT-22 RT-26 RT-27 |
| ADR-057 (reach rule + Sec surface) | verbatim | applied correctly |
| ADR-058 Decision 3 (pair discipline, per-table check) | verbatim | satisfied, all four tables |
| ADR-062 Decisions 2 / 3 / 4 / 5 / 6 | verbatim | see F-1, F-2 |
| `docs/records/v14-preflight/sec-findings.md` M-5 / M-6 / F-6b | verbatim | see F-2, F-3 |

### §10 three-axis cross-check — CLEAN

Decision 4's catalogued-instance list read live from the ADR body, not from the dispatch brief and
not from recall. Canonical ordering as its own text words it: **RT-22 first** (Lock 13 / Decision 17,
infrastructure-credential-presence layer) · **RT-26 second** (code-layer, V1-web-app
`SUPABASE_SERVICE_ROLE_KEY` allowlist CI grep fence) · **RT-27 third** (network-exposure/config
layer, app→worker credential-admission inbound channel).

- **(i) Instance-numbering** — UNCHANGED. Nothing added, removed, reordered or renumbered. The
  branch carries no §10 enumeration and no §10 count anywhere.
- **(ii) Layer-attribution** — UNCHANGED. No catalogued instance's layer moves; the per-surface
  three-layer defense language is untouched; no surface becomes "four-layer".
- **(iii) Verbatim-vs-paraphrase** — the migration takes **Path B** (Decision 4 REFERENCED, not
  restated). Correct disposition: `100` is not the canonical anchor and does not absorb canonical
  content. Its §10 block claims exactly this and the claim is accurate.

⚠ The **§10 catalogued** set and the **CI-fenced** set are DIFFERENT SETS. Measured this branch:
catalogued = RT-22 / RT-26 / RT-27; CI-fenced adds **RT-05**. This branch changes neither and
reconciles neither, and the migration's own header says so. **I would veto a reconciliation.**

---

## A-1 (AMBER — blocking) — the DEFAULT tables' post-state has no positive watcher, and the header claims one

**Owner: QA.** **Clearance: the legs below exist and are proved by inversion.**

**What the header promises.** `supabase/migrations/100_tax_value_inventory_seed_delta.sql`, the
"WHY EVERY STATEMENT IS GUARDED" block, cost **(c)**: *"A MISS IS SILENT… if a row's current value
is not what this file expects, the UPDATE affects zero rows and says nothing. The watcher is QA's
paired battery asserting the POST state row by row, not anything in this file."*

**What is actually watched, measured leg by leg against
`supabase/tests/rls/100_tax_value_inventory_seed_delta.sql`:**

- **BLOCK BF (BF1–BF8)** asserts POST state on `pfin.posting_prototype` / `pfin.user_taxonomy` for
  the fixture tenant `tPre`. Those rows were **inserted by the battery's own fixture** and then
  corrected by the battery's own **replayed copies** of statements (2), (4) and (6). The fixture and
  the replay share one string list, so BF1–BF8 observe the battery, not the migration.
- **BLOCK IDEM (IDEM1, IDEM2, IDEM3)** does hit the real, already-migrated default tables — but by
  asserting **zero rows affected**. Zero-affected is satisfied both by "the row was corrected" and
  by "the guard never matched anything", and a `(cat, sub_cat)` string that resolves to no row
  produces zero in the real apply *and* zero in the replay. Vacuous on exactly the failure mode
  cost (c) names.
- **What IS genuinely observed against a real default row:** `091`'s inverted **(E1)** leg
  (`Equity / Contribution` on `posting_prototype_default`), and **(BF3)** — which reads
  `d.tax_relevant / d.tax_character / d.display_order` out of the real
  `posting_prototype_default` through the replayed statement (6), so statement **(5)**'s row add is
  positively pinned. Plus the count re-pins in `041` / `082` / `091`.

**Not observed anywhere against a real default row — 27 corrected values:**
1. `posting_prototype_default` `('Revenue','Dividend')` → `tax_character = 'ordinary'`.
2. `posting_prototype_default` `('Revenue','Bond Premium')` → `notes` off the mark-to-market wording.
3. `taxonomy_default` — all **25** asset-side corrections (24 `long_term_capital_gain_eligible`
   + `('Cash','T-Bill')` `short_term_only`).

**Why this is the sharp end and not tidiness.** The default tables are what **every future signup**
inherits — `api/src/lib/server/queries/taxonomy.ts:37` (`DEFAULT_PROVISION_COLUMNS`) already carries
`tax_relevant, tax_character`, so provisioning copies whatever those tables hold. If those 27 values
were ever not applied, a new user silently receives the **fail-OPEN** direction on both halves:
`tax_relevant = false` on 25 asset rows (E4 D-iii's marking principle absent), and the generic
`Dividend` bucket back on `qualified_dividend` — which is the precise outcome E4 rejected as option
(C) because it *"would route to LT-CG rates and understate Federal tax."* The whole battery stays
green.

**I measured the current state and it is CORRECT** — this is a coverage gap, not a live defect. Set
comparison of `100`'s 25-row VALUES list against `041:275–312`'s asset seed with `082`'s
`Equity → Marketable Securities` rename applied: **25 of 25 targets resolve to a seeded row; zero
unmatched.** So the miss has not happened; nothing watches whether it does.

**Catch criterion — four to five legs, all against the REAL default tables (no fixture, no replay):**

- `(D1)` `select tax_character from pfin.posting_prototype_default where cat='Revenue' and sub_cat='Dividend'` **is** `'ordinary'`, and its `notes` matches the corrected string.
- `(D2)` `pfin.posting_prototype_default` `('Revenue','Bond Premium')` — `notes not like '%Mark-to-Market%'` and `tax_character = 'ordinary'`.
- `(D3)` `select count(*) from pfin.taxonomy_default where tax_relevant = true` **is** `25`.
- `(D4)` `select count(*) from pfin.taxonomy_default where tax_character = 'long_term_capital_gain_eligible'` **is** `24`; and `array_agg(cat||'/'||sub_cat) where tax_character = 'short_term_only'` **is** `array['Cash/T-Bill']` (identity, not merely a count — the BF7 shape).
- `(D5)` `select count(*) from pfin.taxonomy_default where cat = 'Real Estate' and tax_relevant = true` **is** `0` (the BF8 control, retargeted at the real table).

This is BF2 / BF4 / BF5 / BF6 / BF7 / BF8 **re-aimed at the default tables**. Bump `plan()`
accordingly.

**Inversion proof required, and it is cheap.** On a scratch clone, strike statement **(3)** from
`100` and re-apply the chain: `(D3)/(D4)/(D5)` must go **RED** while **BF5–BF8 stay GREEN** — that
divergence is the whole finding, demonstrated. Repeat with statement **(1)**'s Dividend UPDATE
struck: `(D1)` RED, `BF2` GREEN. If any proposed leg cannot be made to red this way, it is not the
leg. Do **not** replace a pinned expectation with a live `select count(*)` off the same table — that
is ADR-057's named tautology and it can never red again.

---

## Findings

### F-1 (flag) — ADR-062 Amendment 1 and `100`'s AC-5 attribute Decision 3's discharge to the wrong authority

**Owner: Architect (`DECISIONS.md` pen) + Backend (migration header).**

ADR-062 Decision 3, verbatim: *"The **F/CTO** marking enumeration is a HARD PRECONDITION on the
§2.3.4 surface shipping — not a follow-up."*

The branch records that precondition as discharged **by this session**:

- `DECISIONS.md`, ADR-062 Amendment 1: *"Decision 3's hard precondition is discharged by the same
  session — its Expense-class marking enumeration ran and produced **zero** `is_tax_payment` marks"*,
  with provenance *"TEAM-LEAD RULING UNDER DELEGATION"*.
- `100`'s header, AC 5: *"ADR-062 DECISION 3's HARD PRECONDITION IS DISCHARGED BY THIS ISSUE."*

**It was already discharged, by F/CTO, on 2026-08-25.** My own pass-2 retraction of M-6 records it
verbatim from SELF-245 Comment 2: *"AC6 marking pass COMPLETE (F/CTO ruling, 2026-08-25): **zero**
Expense-class prototypes marked `is_tax_payment = true`"* — `docs/records/v14-preflight/sec-findings.md:195-198`.

**Why this is a flag and not a note.** The outcome is identical (zero marks both times), so there is
no substantive risk. But Decision 3 scopes the enumeration to **F/CTO**, and the branch writes a
**team-lead-delegated** discharge of it into `DECISIONS.md` — a weaker authority recorded over a
stronger one, in the canonical artifact. It also makes the F/CTO ruling unrecoverable from the tree:
it lives only in a Linear comment, which is the exact off-tree-record failure ADR-062's own
"Why this ADR exists at all" paragraph was written about. A later reader reconstructing the
authority chain gets the wrong answer.

**Commit-ready replacement text** (Architect commits verbatim into ADR-062 Amendment 1; the clause
replaces *"and Decision 3's hard precondition is discharged by the same session — its Expense-class
marking enumeration ran and produced **zero** `is_tax_payment` marks, so `100` changes no
`is_tax_payment` value"*):

> and Decision 3's hard precondition is **CONFIRMED, not discharged, here** — it was discharged by
> **F/CTO ruling on 2026-08-25**, recorded at SELF-245 Comment 2 (*"AC6 marking pass COMPLETE… **zero**
> Expense-class prototypes marked `is_tax_payment = true`"*) and quoted verbatim at
> `docs/records/v14-preflight/sec-findings.md`'s M-6 retraction. The V1.4 session re-ran the
> Expense-class enumeration under team-lead delegation and reached the **same** outcome — zero marks
> — so `100` changes no `is_tax_payment` value. **A delegated re-run cannot discharge an
> F/CTO-scoped precondition; it can only agree with it**, and the distinction is recorded because
> the F/CTO ruling exists only in Linear and is not recoverable from the tree

Mirror the same correction in `100`'s AC-5 header block ("IS DISCHARGED BY THIS ISSUE" →
"WAS DISCHARGED BY F/CTO ON 2026-08-25 AND IS CONFIRMED BY THIS ISSUE").

### F-2 (flag) — `100` books F-6b's discharge under the one axis F-6b is not about

**Owner: Backend. One line.**

`100`'s AC-5 block closes: *"Sec's M-6 and F-6(b) are the same obligation as Decision 3's and are
discharged with it."* Two errors in one sentence, and the second matters:

1. **M-6 is RETRACTED** (`sec-findings.md:193`, *"⚠ RETRACTED AT PASS 2. The measurement was right
   and the conclusion was wrong."*). It is not a live finding and cannot be discharged.
2. **F-6b is NOT "the same obligation as Decision 3's".** The retraction says so in terms:
   *"Do not read this retraction as clearing them: `is_tax_payment` is discharged; `tax_relevant` /
   `tax_character` are not, and they are the two attributes §2.5.1 actually gates on."* F-6b is the
   **`tax_relevant` / `tax_character` inventory session** — a different axis from `is_tax_payment`.

**`100` genuinely and completely discharges F-6b** — it *is* that session. The defect is purely
wrong-section attribution: filing the discharge under the AC-5 `is_tax_payment` heading loses the
fact that the tax-value inventory was the surviving obligation and `is_tax_payment` was not.

**Commit-ready replacement** for that sentence:

> Sec's **M-6 is RETRACTED** (`docs/records/v14-preflight/sec-findings.md`) and is not discharged
> here because it is not live. Sec's **F-6b is discharged by this issue in full, on a DIFFERENT
> axis** from AC 5's: F-6b is the `tax_relevant` / `tax_character` inventory session
> (`BACKLOG.md` §7 item 3; SELF-245's struck AC4), which is what statements (1)–(6) above ARE — not
> the `is_tax_payment` marking enumeration this AC covers. M-6's own retraction draws exactly that
> line: *"`is_tax_payment` is discharged; `tax_relevant` / `tax_character` are not."*

### F-3 (flag) — M-5's residual is NARROWED, not discharged, and it transfers to SELF-262

**Owner: Architect → SELF-262 acceptance criteria.**

M-5's ask, verbatim: *"I am asking that the **V1.4 consumer not treat `false` as an answered
question**, and that the ADR-062 `comment on column` scoping precedent be followed."* My §9.2 flagged
that *"Sec agrees with F-5"* must not be read as clearing it. Stating precisely what `100` moves:

- **DISCHARGED — the column half.** F-5 option (C) is shipped: four `comment on column …
  tax_relevant` statements, one per table carrying the column. Verified below at F-5.
- **DISCHARGED — the data half.** The rows seeded **up to `100`** now carry determinations, not
  defaults. F-6b's *"leaves the values unexamined behind a column that now has an explicit comment
  saying they were not examined"* no longer obtains.
- **STANDS — the reader half**, and it is now sharply statable rather than diffuse:
  **for a row seeded up to `100`, `false` IS a determination and a consumer may rely on it; for any
  row inserted AFTER `100` — a V2 taxonomy-CRUD row, or the next seed delta that omits the column —
  `false` is the fail-open `DEFAULT` and means nothing.** The four column comments say exactly this;
  a comment constrains the column, never the reader.

**Carry-forward, two clauses, both belong in an AC and not only in a comment:**
(a) SELF-262's §2.5.1 reader must not infer a determination from `false`; (b) **every future seed
delta into any of the four tables must state `tax_relevant` explicitly**, because the DEFAULT is
retained deliberately and is fail-open. I do **NOT** ask for the DEFAULT to be dropped — unchanged
from F-5 (A): it is load-bearing for the provisioning INSERT and a narrowing change breaks every
fixture that seeds the barred value.

### F-4 (flag) — PM's R-1 carry-forward: SELF-262's Income reader MUST be class-scoped

**Owner: Architect → SELF-262 AC + a QA leg. Stating this as the brief requires.**

**Measured:** `041:345` seeds `Trade / STC` and `041:347` seeds `Trade / BTC` as
`tax_relevant = true, tax_character = null`. `100` leaves both `true` — correctly; they are genuine
disposition events whose character comes from the holding period, not from `tax_character`. After
E4 D-i flips `Equity / Contribution` to `false`, **STC and BTC are the only non-`Revenue` rows in
`posting_prototype` carrying `tax_relevant = true`.**

**The hazard:** PRD §2.5.1 sources Ordinary Income from *"the Income side of §2.3.1"*. **A reader
that filters on `tax_relevant` alone, without also scoping `cat = 'Revenue'`, sums sale proceeds
into Ordinary Income.** That is a money-path overstatement with no error and no marker.

It is already carried in two places — the ⚠ CLASS-SCOPE THE READ paragraph on
`pfin.posting_prototype.tax_relevant`'s comment, and `self263-inventory.md:45` (R-1). **Neither
constrains a reader.** It must land as an explicit SELF-262 acceptance criterion with a QA leg that
seeds an STC row and asserts it is absent from the Ordinary Income figure.

⚠ **Asymmetry worth fixing while the pen is open:** the CLASS-SCOPE paragraph is on
`posting_prototype.tax_relevant` **only**. `posting_prototype_default.tax_relevant`'s comment does
not carry it, and that is the table a schema reader consults first. One sentence, same wording.
Owner Backend, non-blocking.

### F-5 (note) — the four column comments: none carries the negated reading. Confirmed.

**R10 / E15 clearance.** I read all four `comment on column` bodies verbatim at 4ee2a10. Every one
states *"`false` may simply be the DEFAULT… meaning NOT MARKED / NOT YET INVENTORIED"* and
*"A consumer MUST NOT infer from a `false` that the question was asked."* **None carries the
negated reading.** The `taxonomy_default` and `user_taxonomy` comments additionally spell out the
Real Estate case — *"`false` because a property sale is a taxable event the lot machinery does not
model, not because it is untaxed"* — which is the strongest form of the R10 requirement.

**E15's rephrase was correct and its watcher can fire.** Commit `d9f645a` removed the clause
`never "examined and found not tax-relevant"` from two of the four comments; that string contained
the exact substring `(COM1)`–`(COM4)` now assert absent (`not ilike '%found not tax-relevant%'`). So
the negative half of the COM legs **would have red-ed against the pre-E15 text** — it is a real
watcher, not a leg that cannot fail. On the two comments that never carried the clause the negative
half passes vacuously; that is a harmless standing guard, and it is the right shape.

### F-6 (note) — the header's NON-CLOBBERING claim (b) is true per statement, not per column

**Owner: Backend. One clause. Reachability today is NIL.**

`100`'s header, guard rationale **(b)**: *"NON-CLOBBERING. No V1 code path lets a user edit these
columns… The day a CRUD path lands, a hand-edited row is left ALONE by these predicates rather than
silently reverted."*

**The Dividend UPDATEs in statements (1) and (2) guard on `tax_character = 'qualified_dividend'`
and overwrite `notes` unguarded.** A future CRUD user who edited only `notes` would have it silently
reverted. The Contribution and Bond Premium statements do guard on `notes`; the Dividend one does
not, because `notes` is not the value it replaces.

**The "no V1 notes edit path" claim is VERIFIED and I am not disputing it.** Measured grants across
all four tables: `084:638` grants `authenticated` **SELECT + INSERT only** on
`pfin.posting_prototype`; `084:658` grants **SELECT only** on `pfin.posting_prototype_default`;
`009:184` grants **SELECT** and `041:369` grants **INSERT** on `pfin.user_taxonomy`; `041:266`
grants **SELECT only** on `pfin.taxonomy_default`. **No `UPDATE` grant exists on any of the four
tables at any tier.** Mechanism real, reachability nil in V1. Suggested clause: scope (b) to
*"the guarded columns"* and name the Dividend row's `notes` as the one column outside the guard.

⚠ One live consequence of the INSERT grant on `posting_prototype`, stated so it is not an
unexamined surface: a user **can** pre-insert their own `('Revenue','Dividend - Qualified')` row
before `100` applies, and statement (6)'s `on conflict do nothing` would leave their values in
place. Tenant-scoped, self-inflicted, no V1 UI reaches it, affects only that user's own tax figure.
**No action required.**

### F-7 (note) — `taxonomy_default.tax_character`'s inline CHECK vs the FK on its three siblings: hygiene, and it fails CLOSED

**Owner: Architect / PM (a BACKLOG line, not a change here). Answering the brief's question directly:
hygiene, not a Sec concern.**

Measured: `pfin.posting_prototype.tax_character`, `pfin.posting_prototype_default.tax_character` and
`pfin.user_taxonomy.tax_character` all carry FOREIGN KEYs to `pfin.tax_character(code)`
`ON DELETE RESTRICT`; `pfin.taxonomy_default.tax_character` still carries `041`'s inline five-value
CHECK. Both admit exactly the same five values today. `100` states this asymmetry explicitly rather
than generalizing from one table — which is the right call and is why I am not raising it higher.

**Failure direction, which is what settles the severity:** a sixth code seeded on `011` would be
**accepted** by the three FK-bound columns and **rejected** by `taxonomy_default`'s CHECK. That
blocks a future seed delta loudly; it never admits an unvalidated value. **Fails closed.** It is a
maintenance trap for whoever adds the sixth code (the ADR-024 g-2 jurisdiction work, already booked
this branch at BACKLOG §5), not a security defect. **I do NOT require conversion to the FK.** Worth
one BACKLOG line so it is discovered at design time rather than at `alter` time.

### F-8 (note) — the battery replays copies of the migration rather than observing it. I do NOT object.

BLOCK BF replays verbatim copies of statements (2), (4) and (6) against fixture tenants created
after `100` applied. That is **unavoidable** — a pgTAP battery cannot re-run an applied migration
for tenants that did not exist when it ran — and it is `091`'s established shape. Stated explicitly
because it is *why* **A-1** is needed: the per-user half genuinely cannot be observed any other way,
but the **default** half can be observed directly and is not.

### F-9 (note) — `(VOC2)` is a prospective guard with nothing to catch. Say so; keep it.

`select is(to_regtype('pfin.tax_character_enum'), null::regtype, …)` can fail only if someone
creates that type. It catches nothing on the tree today. It is the right standing guard against the
"a sixth value is a CHECK/enum edit" mistake and should stay — it just should not be counted as
coverage of anything present.

---

## Non-objections, stated explicitly

- **I do NOT object to the D1-ADJACENT classification, and I evaluated the claim rather than
  accepting it.** ADR-011 Decision 1 read verbatim, clause by clause against statements (2), (4)
  and (6): **(a) MET** — no JWT, the writer is not a user session; **(b) NOT MET** — the writer is
  the schema owner under the migration role, **not** `service_role`; **(c) MET** — tenant
  correctness derives from the statement, not RLS (no `pfin` table carries `FORCE ROW LEVEL
  SECURITY`, measured: `grep -rn "force row level security" supabase/migrations/` returns nothing,
  so the owning role is not subject to the policies and the `025` aal2 backstop conjunct is not
  evaluated); **(d) NOT MET** — no audit-log row. That is precisely ADR-057's ruling for `077`
  (*"D1-ADJACENT rather than a convenience — a **migration-role write**, a distinct class"*) and
  precisely `091`'s header text at `091:67-68`. `100` also repeats the anti-precedent guard —
  *"do not cite 100 as precedent for a service_role surface shipping without (d)"* — which is the
  clause that keeps D1 from being weakened by accretion. **Architect's claim is correct.**
- **I do NOT require an audit-log row for this backfill.** Its forensic record is the
  version-controlled joint-reviewed migration plus the applied-migrations ledger, per ADR-057.
- **I do NOT require matched-tenant validation anywhere in this migration, and I concur with the
  per-column D3 evaluation.** ADR-011 Decision 3's rule sentence read verbatim: *"Any FK-shaped
  reference column… **that crosses an isolation boundary** requires explicit matched-tenant
  validation."* `tax_character` **is** FK-shaped on three of the four tables — `100` refuses the
  loose *"no FK-shaped column is touched"* formulation, correctly. Its referent
  `pfin.tax_character` (`011:158-165`) is a **global value registry with no `users_id` column at
  all**, so no isolation boundary is crossed and there is no second tenant anchor a fence could
  compare against. Not even the P2 *global-OR-matched-tenant* shape applies — that pattern exists
  for `pfin.asset`, which is global-**or**-owned; `tax_character` is global only.
  `taxonomy_default.tax_character` is not FK-shaped at all. `tax_relevant` is `boolean`; `notes` is
  `text`. Statement (6) writes `posting_prototype.users_id`, which is that table's **tenant anchor**,
  copied from an existing row of the same table — not a cross-tenant reference. **Family +0. The
  next genuine instance still takes #18.**
- **I do NOT require any change to the reach decision.** Statement (6)'s user set is
  `select distinct users_id from pfin.posting_prototype` — the already-provisioned set **by
  construction**, the shape ADR-057 marks load-bearing. A zero-row user contributes no `users_id`
  and is therefore **unreachable**, not excluded by a predicate a later simplification could drop.
  Statements (2) and (4) UPDATE in place and touch no `users_id`. The statement cannot mint a
  tenant, cannot cross one tenant's row into another's, and cannot strand a zero-row user behind
  `041`'s existence guard. Correct, and correct for the stated reason.
- **I do NOT require a paired app-source change, and I verified the claim rather than taking it.**
  ADR-062 Decision 6's hazard is a **new NOT NULL column** absent from the provisioning column list.
  `100` adds no column. Measured `api/src/lib/server/queries/taxonomy.ts:37` — `DEFAULT_PROVISION_COLUMNS`
  is `'cat, sub_cat, tax_relevant, tax_character, display_order, notes'`, with
  `ASSET_DEFAULT_PROVISION_COLUMNS` adding `element` (`:52`) and `CASHFLOW_DEFAULT_PROVISION_COLUMNS`
  adding `is_tax_payment` (`:67`) — **both already carry `tax_relevant` and `tax_character`.** So a
  fresh signup inherits the corrected values and the new `Dividend - Qualified` row with **no app
  edit**, and the fail-soft zero-row hazard does not fire. The claim is TRUE.
- **I do NOT object to ADR-058 Decision 3's pair discipline as discharged.** The check is stated and
  performed **per table** for all four — `100` does not run it once for a pair, which is the
  specific failure `084`'s Amendment 1 records. Statements (1)/(2), (3)/(4) and (5)/(6) are separate
  statements rather than one join, deliberately.
- **I do NOT require the `tax_relevant` `DEFAULT false` to be dropped.** Unchanged from F-5 (A).
- **§10 catalogued-instance ledger: NO CHANGE.** Three axes clean, verified above against Decision 4
  read verbatim and live from the ADR body.
- **SECURITY DEFINER allowlist: UNCHANGED.** The branch creates, replaces and drops no function.
  No new SECURITY DEFINER function is proposed against the Lock 11 SECURITY INVOKER default.
- **No new pgsodium-encrypted-BYTEA column.** SD-03 storage-class discipline not engaged.
- **No CI fence change**, no `TenantBoundConnection` change, no `.github/workflows/` change, no
  `secrets-manifest.yml` change, no Dockerfile change, no PDF-worker database reach. Lock 13 mod #2
  zero-DB-isolation untouched.
- **Lock 14 not engaged** — no user-facing settings write-path is introduced; the four tables carry
  no `UPDATE` grant at any tier.
- **ADR-011 Decision 2 (audit-class):** none of the four tables is audit-class and no audit-class
  write surface is touched. `pfin.account_trans` and its writers are not in this diff.
- **RLS posture unchanged and correctly reasoned.** No policy, grant or trigger is added or altered.
  `posting_prototype` and `user_taxonomy` already carry the `025` aal2 backstop conjunct;
  `posting_prototype_default` and `taxonomy_default` are `025`-excluded under exclusion (i) as global
  shared-read. Writing VALUES into existing tables triggers no aal2 obligation — that obligation
  attaches to a **new** sensitive tenant-owned table.
- **Two-tenant isolation legs are real.** `(ISO2)` / `(ISO5)` use
  `_rls.expect_cross_tenant_read_empty`; `(ISO3)` uses `_rls.expect_cross_tenant_write_blocked` with
  a genuine ownership-forge (`tOther` inserting `users_id = tPre`), and the file restores the session
  role immediately after, per `084`/`091`'s documented helper gotcha. `(ISO-PRE)` proves the global
  backfill reached a **second, independent** tenant with its own `users_id` — which is the leg that
  distinguishes "reached both" from "merged them".
- **ADR-062 Amendment 1 is accurate** on the ruling, the value, the equality-guard mechanism, the
  `pfin.account.tax_treatment` rationale, and the "Decision 4's text is left UNEDITED"
  supersede-don't-rewrite discipline. Its one inaccuracy is F-1's authority attribution.
- **The rider string is byte-exact across every site.** Measured:
  `grep -ho "potentially deductible[^']*"` across `091`, `100`, `DECISIONS.md` and the `100` battery
  returns **12 occurrences of exactly one distinct string**. The guard cannot miss on a
  transcription drift, and if a future reader changes that string anywhere the guard stops matching
  — by design, and stated as such in the header.
- **Value spot-checks against the seed all pass.** `041:326` seeds `Revenue / Dividend` as
  `qualified_dividend` (guard matches); `041:325` seeds `Revenue / Bond Premium` `notes` as
  `'Mark-to-Market Gain for Tax Purposes'` (guard matches byte-exact); `display_order = 65` sits
  between `Dividend` (60, `041:326`) and `Salary Untagged` (70, `041:327`), is unoccupied, and no
  `display_order` column anywhere carries a unique constraint (measured across
  `supabase/migrations/*.sql`). Row arithmetic reconciles end to end: `posting_prototype_default`
  27 at `041` → 29 at `091` → **30** at `100`; `taxonomy_default` 36 at `041` → **38** after
  `077`/`080`, of which **25 corrected + 13 confirmed** = 38. Every re-pin in `041` / `082` / `091`
  matches (29→30, 67→68, `taxonomy_default` correctly left at 38).
- **The `082` rename trap is avoided.** `100` writes `'Marketable Securities'`, not `041`'s
  pre-rename `'Equity'`, on the asset pair — while correctly using `'Equity'` as the **accounting
  class** on the posting pair. Two different meanings of one token in one file, handled correctly.

---

## Escalation

**To F/CTO** — three items, none a veto:

1. **The E4 D-ii reversal window is open and is a money-path default.** `100`'s header flags it:
   the choice between generic `Dividend = ordinary` (shipped, option C′, fail-closed) and
   `= qualified_dividend` (option C, fail-open) *"depends on the actual dividend mix, which F/CTO
   knows."* Reversing is one value on each of two rows — no DDL, no data migration. **Sec's position:
   C′ is the correct posture and I support it as shipped** — an unsorted user's money-market / REIT /
   bond-fund distributions routing to LT-CG rates understates Federal tax silently, and C′'s only
   cost is re-sorting dividend history, which is zero on a greenfield deployment.
2. **F-1's authority attribution** — a team-lead-delegated discharge of an F/CTO-scoped precondition
   is being written into `DECISIONS.md`. Text supplied; Architect commits verbatim.
3. **A-1 blocks the gate until QA lands the default-table legs.** Not an architecture call, but it
   is the reason this review is AMBER rather than GREEN.

**To team-lead** — F-3 and F-4 are carry-forward conditions on **SELF-262**, not on this branch.
They must land as acceptance criteria on that issue before its Income reader is built, or they will
be discovered on a tax table.
