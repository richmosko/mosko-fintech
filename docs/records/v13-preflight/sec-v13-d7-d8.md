# Sec — V1.3 pre-flight bounded consult: D-7 + D-8

Read-only against `main` @ `0491830` (verified `git rev-parse HEAD origin/main` in-turn, both equal).
Every citation below re-read from the tree, not from `temp/v13-preflight/architect-findings.md`.

---

## D-7 — reading (A). Confidence HIGH. I do NOT make a (B) fence-exceeded finding.

### Canonical text I anchored on (DECISIONS.md:4738, ADR-011 Decision 19, verbatim span)

> server-derived-only fence for §2.6 paths (NO client-asserted `data_as_of` for cron + on-demand
> monthly_report; §2.3.3 drill-down is the ONLY surface where client toggle is legitimate)

Structure: the clause is the **second item of a parenthetical attached to a mod whose named scope is
"§2.6 paths"**, whose first item states the fence and whose second states its rationale — which PRD
story authorises a user-facing historical as-of control.

### Four measurements

1. **No live client-supplied as-of exists anywhere in the app.** `grep -rn "userSuppliedAsOf" api/src`
   → `lib/server/time/asOf.ts`, `lib/server/schemas/allocation.ts`, + their two test files. Zero
   routes. `grep -rn "serverTodayAsOf\|userSuppliedAsOf" api/src/routes` → four loaders, all
   `serverTodayAsOf()`. `api/src/routes/allocation/+page.server.ts:49` says so in the file:
   "NO `as_of` QUERY-PARAM SUPPORT YET"; `allocation/us-equity/+page.server.ts:34` mirrors it.
2. **The clause is still TRUE AS WRITTEN against the PRD.** `docs/PRD/index.html` `story-2-3-3`:
   "V1 also includes an **as-of-date toggle** on this view". `story-2-2-2` / `story-2-2-3` carry no
   as-of language at all. §2.3.3 remains the only V1 story with a toggle. Nothing to retract ⇒ (C)
   is off.
3. **The §2.6 fence has no live surface either** — no `monthly_report` table exists
   (`grep -rln "monthly_report" supabase/migrations` → 007 / 013 / 015, comment mentions only).
   The whole Decision-19 as-of apparatus is prospective.
4. **The literal reading over-reaches — reductio.** Under (B), two *live* client-supplied dates would
   also be instances: `chart_start` / `chart_end` (`lib/server/schemas/nav-series-params.ts:95-96`,
   wired at `routes/+page.server.ts:21`) and `as_of_date` on manual-account create
   (`routes/accounts/new/+page.svelte:36` → `p_as_of_date`). Nobody calls a chart window or an
   opening-balance date a "client as-of toggle". A reading that sweeps them in is the wrong reading.

### Premise correction (belongs in the same message as the finding)

`api/src/lib/server/time/asOf.ts` header states SELF-238/240 "are the **FIRST live path**". Measured:
**not live** — the factory and schema exist; no route wires them. "Live" is the load-bearing word a
(B) finding would have rested on, and it is wrong *in the code comment*, which is where a future
reader will find it. → **Backend**: correct to "the first path to VALIDATE one — not wired to any
route as of `0491830`".

### Commit-ready ADR text (Architect commits VERBATIM — no paraphrase, no re-flow)

Append to ADR-011 Decision 19, after the **Cross-references** paragraph:

**[Amendment 2026-08-22 — scope clarification, NO behavior change (Sec-reviewed at the V1.3 pre-flight sitting).** The clause "§2.3.3 drill-down is the ONLY surface where client toggle is legitimate" is a statement about the **PRD's V1 as-of-toggle inventory**, stated as the rationale for the §2.6 server-derived-only fence it shares a parenthetical with. It scopes **which PRD story authorises a user-facing historical as-of control**, and it remains true as written: §2.3.3 is still the only V1 story carrying one (PRD `story-2-3-3`, "V1 also includes an **as-of-date toggle** on this view"); `story-2-2-2` and `story-2-2-3` carry none. It does **not** speak to client-supplied dates that are not as-of toggles — a chart window (`chart_start` / `chart_end`), or a manual account's opening-balance date (`p_as_of_date`), both of which are live and neither of which is an instance. **SELF-238 / SELF-240 did not exceed it:** AC8 / AC6 delivered a validated `as_of` **capability** (`api/src/lib/server/schemas/allocation.ts`; `userSuppliedAsOf`) that no route wires — both allocation loaders pass `serverTodayAsOf()`, and `userSuppliedAsOf` has no caller outside that schema module and its tests (measured 2026-08-22 at `0491830`). **Standing condition:** the PR that first wires an `as_of` query parameter onto a §2.2 surface is **Sec-joint-review-mandatory** and must at that PR either implement this Decision's app-layer DATE range battery (upper bound: no future dates; the `2015-12-01` floor to be re-derived or retired — it has no referent anywhere in the current tree) or record why it does not.**]**

### Residual FLAG carried by (A), not closed by it

Decision 19's *other* V1-SHIP-BLOCK — "app-layer DATE input validation battery (Zod `.date()` +
tightened range `2015-12-01 ≤ as_of_date ≤ CURRENT_DATE` per NAV anchor floor + no future dates)" —
is **unimplemented in the only client-supplied-as_of validator that exists**.
`schemas/allocation.ts:31-43` gives shape + real-calendar-date + `.strict()`; `userSuppliedAsOf`
re-checks shape only. No range on either. Harmless while unreachable; it is a fence gap the moment
the query param is wired. Covered by the standing condition in the amendment text above.
`grep -rn "2015-12-01" api/src supabase/migrations` → no match; the floor has no current referent,
so I am **not** requiring it — Architect's call whether to re-derive or retire it. Stated as
uncertainty, not as a requirement.

---

## D-8 — I will NOT make the out-of-threat-model statement. Therefore (A) is out. Choose **(C), reformulated in three respects.**

### The statement I decline, and why

I do **not** state that non-endpoint `authenticated` paths are out of V1's threat model.

- Measured: `supabase/migrations/023_account_trans_annotation.sql:414` —
  `grant select, insert, update, delete on pfin.account_trans_annotation to authenticated;`
- Precedent, verbatim from `docs/SECURITY/index.html:730`: "the SELF-242 endpoint's own
  `.eq('users_id', …)` predicate is an app-layer control and **does not bound what other paths may
  send**" — and that bullet records it as **QA-measured** with a corrupt-the-control pair, not
  reasoned. ⚠ Attribution correction to the brief: that sentence lives in the **"Lock-14
  settings-family DELETE-policy fence"** posture bullet, which *names* SD-22 as one of four unbuilt
  family members. It is not SD-22's own matrix row.
- V1 ships public signup. `authenticated` is a role many principals hold, not one trusted client.

**Honest severity nuance, stated because it changes the argument's shape:** 023's four policies are
all `wr_access`-JOIN scoped (023:221), so a writer reaches only their **own** rows. This is **not**
cross-tenant. It is silent financial-correctness corruption of the writer's own ledger, reachable by
any path that is not the SELF-248 endpoint — a second client, a bulk import, a future worker, a
mis-scoped route. That is why this is a **FLAG with binding conditions, not a veto**.

### The defect, re-measured

`084_gl_split_posting_prototype.sql:865-874`, P3 contra, ordered `CASE`: `Revenue` → `Expense` →
`Equity` → `Transfer AND journal_id is not null` → else `Suspense`. A journaled transfer leg reaches
`'Journal Clearing'` only by falling through the first three. P3's guard (`:885-886`) is
`where t.transaction_type = 'standard' and t.security_id is null and t.split_count = 0 and t.amount <> 0`
— **no `journal_id` term**, which is exactly why M1 and M4 are fail-silent and M3 is not.

### (C′) — the PREDICATE. Not "non-Transfer".

`084:588` fixes the vocabulary: `cat in ('Revenue', 'Expense', 'Transfer', 'Equity', 'Trade')`.
A `transfer_in_kind` journal's legs are security rows, and `084:1233`'s biconditional
`(security_id is not null) <> (cat = 'Trade')` forces them to `cat = 'Trade'`. **"Refuse a
non-Transfer cat when `journal_id IS NOT NULL`" would refuse every in-kind transfer.**

Catch criterion, stated as the invariant:

> `journal_id IS NOT NULL` ⇒ resolved `posting_prototype.cat NOT IN ('Revenue','Expense','Equity')`

The refused set is **exactly the fall-through set of the `084:869-872` ordered CASE** — derivable
from the defect rather than chosen, which is what lets the function's COMMENT explain itself.

### (C″) — the SCOPING. A STATE invariant, not a transition guard.

Architect's `WHEN new.sub_cat_id IS DISTINCT FROM old.sub_cat_id` is correct for a full
`classifiable()` fence (B) and **wrong for M3** — it leaves one of the two reachability orders open:

- attach-then-classify → `sub_cat_id` changes → fires → refused ✓
- **classify-then-attach → only `journal_id` changes → does not fire → defect state reached** ✗

Use a pure state predicate on NEW, valid on both ops and referencing no OLD (a WHEN clause on an
`INSERT OR UPDATE` trigger **cannot** reference OLD):

```
before insert or update on pfin.account_trans_annotation
for each row
when (new.sub_cat_id is not null and new.journal_id is not null)
```

Architect's B hazard does not apply to this shape: attaching a journal to a Transfer- or
Trade-classified leg fires and passes; only Revenue/Expense/Equity + journaled raises — which is the
defect state itself, not a legitimate flow. Detach (`new.journal_id` NULL) is WHEN-skipped.
Note-only edits on an already-valid row fire and pass.

⚠ Precedent worth knowing: `030:280-284` already creates
`account_trans_annotation_trade_constraints` with `when (new.sub_cat_id is not null)` — the exact
WHEN clause flagged as hazardous. It already fires on journal-attachment UPDATEs today and passes,
because it checks only the trade biconditional.

### (C‴) — the PLACEMENT. New function + new trigger, not an edit to 084's.

`fn_account_trans_annotation_trade_constraints` already resolves both the parent txn and
`posting_prototype.cat` (084:1209-1219), so folding M3 in looks free. Don't:

- it was already re-targeted once at 084 (ADR-058 fan-out that was *found by measuring the live
  catalog*, per 084:1181-1183);
- it carries a long behavior-describing COMMENT that ships to `pg_description`, and edits to it
  move catalog assertions;
- a separate `fn_..._journaled_cat_fence` keeps attribution readable and states its own rationale.

Cost: one extra `posting_prototype` lookup, only on writes where both fields are non-null.

### Binding conditions

1. **NULL-safe fail-closed.** Unresolvable `posting_prototype` row → `raise`, matching 084's existing
   idiom (084:1222-1227). Never a silent skip.
2. **SECURITY INVOKER + `set search_path = ''`.** No SECURITY DEFINER; the ADR-011 D9 allowlist does
   not move (read it live — I am not restating its size).
3. **Paired pgTAP battery, `pg_prove` only, never bare `psql`.** Legs must include **both orders** —
   classify-then-attach AND attach-then-classify — plus `lives_ok` controls for (a) attaching a
   Transfer-classified leg and (b) attaching a Trade-classified in-kind leg. A battery testing only
   attach-then-classify **cannot distinguish this fence from the transition-scoped one**, which is
   the whole point of (C″). Corrupt-the-control pair on the fence itself.
4. **Existing-violation count reported in the migration PR**: rows with `journal_id is not null` and
   resolved `cat in ('Revenue','Expense','Equity')`. Non-zero → back to Sec before the fence lands.
5. **The app guard (item 6a) still ships in full.** The DB fence covers M3 only. The function COMMENT
   must state why M1/M4 stay app-layer — measured never-read via P3's `where` at `084:885-886` — so
   a future reader neither "completes" the fence nor deletes it as arbitrary.
6. **UX consequence, named:** attaching a journal to an already-Revenue/Expense/Equity-classified leg
   now fails. Frontend must surface reclassify-then-attach; the endpoint's typed error and the
   trigger's raise must be distinguishable.
7. **ADR-011 D2 surface** (financial-correctness data). Fence lands at the surface-introducing PR
   (SELF-248) under joint review; Architect commits the ADR text.

### Explicit non-objections

- I do **NOT** require a DB fence for M1 or M4. Measured fail-silent; app guard is sufficient.
- I do **NOT** require narrowing 023's `authenticated` grant. Revoking UPDATE breaks the classify
  path; column-level grants are a larger change with their own review. Considered and declined.
- I do **NOT** require (B). It is viable; it is more surface than the measured defect needs, and it
  amends 029's deliberately-soft precedence rule as a side effect.
- No veto on either question.

---

## Found in passing — separate FLAG, deliberately NOT attributed to Decision 19

`accounts/new`'s `as_of_date` is a **live** client-supplied date on a **write** path
(`routes/accounts/new/+page.svelte:36` → `p_as_of_date`). `api/src/lib/schemas/account.ts:54` gives
`isoDate()` only — no future-date guard. No DB-side bound either: `grep -rn "p_as_of_date"
supabase/migrations` → 013 / 048 / 087, none constraining the value. A future-dated create writes a
future-dated `acct_setup` row and (087:514) a future-dated `eod_price` `manual_valuation`.

⚠ **Same field name as Decision 19's `as_of_date`, different parameter** (opening-balance event date
vs point-in-time read parameter). Attributing this to Decision 19 would be a false composite, so I
do not. Ask: a `pastOrTodayDate()` variant of the shared `isoDate()` idiom, app + client-mirror.
Non-blocking; PM/Architect scope call.
