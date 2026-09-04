# SELF-259 — Security joint-review

**Verdict: AMBER** (conditional — proceed on three doc/comment corrections; one of them needs an F/CTO disposition ruling).

**Ref reviewed:** `origin/feature/self-259` at `7ccc908` (base `origin/main` `762f793`).
**Reviewer:** security-engineer. **Date:** 2026-09-03.
**Mandate:** ADR-011 Decision 3 (new canonical instance), Decision 4 (§10 3-axis), Decision 18 / Lock 14 (settings write-path), ADR-029 / `025` aal2, Lock 11 INVOKER default, ADR-016 D1 / RT-26, CI-fence surfaces.

Verify-hook discharged: ADR-011 Decision 3, Decision 4 and Decision 18 were read **verbatim from the PR branch's own `DECISIONS.md`** (the PR edits that file), located by bracketing `## ADR-` header, never by line position. The §10 catalogued list and the CI-fenced RT set were each read live in the same pass.

---

## Verdict summary

The **security-load-bearing DDL is correct and I have no objection to any control it builds.** The matched-tenant fence, the RLS shape, the aal2 composition, the grant posture, the INVOKER rulings and the two-writer battery are all right, and several of them are better-argued than they needed to be.

What holds this at AMBER is three **documentation** defects, all on canonical or catalog surfaces, all of which tell a future reviewer something untrue about a control:

- **F-1** — ADR-011 D18's SELF-259 amendment claims the `FOR UPDATE` lock *"covers every hazard the surface has."* It does not.
- **F-2** — a third live `#18` forward pointer survived the allocation, and D3's own fold-in asserts that both were re-pointed.
- **F-3** — two live `comment on table` objects assert SERIALIZABLE as the shipped write semantics, which the same migration says is unreachable.

None is a veto. All three are cheap. F-1 additionally needs an F/CTO ruling on whether the underlying residual is accepted or closed.

---

## Findings

### F-1 — **flag, blocking** · ADR-011 D18's amendment asserts coverage the lock does not have · owner **Architect** (`DECISIONS.md` pen) + **F/CTO** (disposition)

`DECISIONS.md`, ADR-011 Decision 18, *Amendment (2026-09-03 / … SELF-259 / `101`)*, the **"Losing side, named"** bullet:

> "True SERIALIZABLE would additionally catch write skew across **different** schedules of one user. Nothing on this surface reads across schedules, so the lock's narrower guarantee covers every hazard the surface has …"

**The final clause is false, and the direction of the error is the costly one** — it names a hazard the surface does *not* have and thereby implies the one it does have is absent.

**Mechanism.** The `FOR UPDATE` lock is taken by exactly one thing: the first statement of `pfin.fn_tax_bracket_schedule_replace_all` (`supabase/migrations/101_tax_bracket_tables.sql`, the `select s.id … for update` at the top of the function body). It binds callers of that function and nothing else. But `101` grants `authenticated` **full SELECT/INSERT/UPDATE/DELETE on both tables** (the two `grant select, insert, update, delete … to authenticated` lines in the GRANTS block), and the file's own premise for the shape check is *"a caller reaching PostgREST directly with their own JWT, which is the whole premise of the Lock 14 direct-DB-write surface."* A direct row write takes no schedule-row lock.

The deferred set fence `fn_tax_bracket_row_schedule_invariants` is therefore the only thing judging concurrent direct writers, and it evaluates each transaction against that transaction's own view. Same-schedule write skew:

- Start: rows `(0, 0.10)` and `(11000, 0.40)` on schedule S.
- T1 `UPDATE … SET bracket_rate = 0.30 WHERE` (row at floor 0). T2 `UPDATE … SET bracket_rate = 0.20 WHERE` (row at floor 11000). **Different rows — no row-lock conflict.**
- Both deferred triggers fire at COMMIT. If T1's trigger runs before T2 commits, T1 sees `(0,0.30),(11000,0.40)` — monotone, passes. If T2's trigger runs before T1's commit record lands, T2 sees `(0,0.10),(11000,0.20)` — monotone, passes.
- Committed result: `(0, 0.30), (11000, 0.20)` — **non-monotone**, exactly what SERIALIZABLE would have refused.

**Both halves of the hazard, stated honestly.**
- *Mechanism:* real, and not remediable by anything in the current file.
- *Reachability:* **narrow.** It needs the interleave between a transaction's deferred-trigger execution and its commit-record write. It is **same-tenant only** — RLS confines both writers to one `users_id`. There is **no cross-tenant effect, no privilege escalation, and no leak.** The worst realistic outcome is a user corrupting the monotonicity of their own bracket table. If either transaction commits before the other's trigger runs, the fence catches it (the trigger's set read takes a fresh READ COMMITTED snapshot).

I am not calling this a veto, and I would not block the migration over the code. **I am blocking on the sentence**, because a canonical Lock register asserting "covers every hazard the surface has" is precisely how the next reviewer is told to stop looking — and this ADR is read live, by rule, at every future Lock 14 surface.

**Disposition options — F/CTO's call, not mine:**

- **Option A — accept and name the residual (doc-only).** Amend the bullet to state that the lock serializes *callers of the function*, that direct table DML remains an unserialized path by design, and that same-schedule write skew across two concurrent direct writers is an accepted same-tenant residual. Cheapest; the gap stays open but stops being invisible.
- **Option B — close it (one statement in `101`).** Make `fn_tax_bracket_row_schedule_invariants`'s **first** statement `select 1 from pfin.tax_bracket_schedule s where s.id = v_schedule_id for update;`, before it reads the set. Every transaction touching any row of schedule S then serializes on S's parent row at commit; the blocked transaction's subsequent set read takes a fresh snapshot and sees the committed rows, so the skew above becomes a leg-B raise on the second committer. Re-entrant with the RPC's own lock on the same row, so no self-deadlock. Cost: one extra lock acquisition per firing, and a lock-ordering exposure only for a transaction touching rows of **two or more** schedules — QA should check that before it lands.
- **Option C — revoke direct DML from `authenticated` — NOT AVAILABLE.** I name it only to close it: the function is SECURITY INVOKER, so it executes with the caller's privileges and *needs* those grants. Withdrawing them breaks the RPC, and the only way to keep them withdrawn is DEFINER, which I would refuse here for the reason the migration header already gives.

**I do NOT require a pgTAP leg for this.** pgTAP is single-session and structurally cannot observe a two-transaction interleave; `(RA10)`'s catalog text pin says so in its own message and that is the honest instrument. If Option B is taken, its watcher is a manual two-session measurement of the same shape `101`'s header already records for the lock itself.

---

### F-2 — **flag, blocking** · a third live `#18` forward pointer survived the allocation; D3's fold-in asserts otherwise · owner **Architect**; escalate **F/CTO** (ledger)

`DECISIONS.md`, **ADR-042 Decision 5** (`pfin.account_event`: the audit surface), the *"Named for the general class"* paragraph:

> "… a second near-identical audit table later would duplicate RLS + grants + immutability triggers **and add a Decision-3 instance** (`account_id → account` a second time, **as #18**)."

`#18` is now allocated to `pfin.tax_bracket_row.schedule_id`. That sentence **asserts** a label for a hypothetical future instance and is now wrong. Under Decision 4's own ASSERTS-vs-NAMES distinction it is an assertion, therefore drift.

The sharper half is what it collides with. ADR-011 Decision 3's SELF-259 fold-in, consequence **(b)**:

> "**Both forward pointers are re-pointed to #19 in the same edit**, because a pointer that survives its own allocation is the next instance's version of the #16 slip."

That is a **completeness claim, and it is false.** Three live sites in `DECISIONS.md` named `#18` as the next label; two were re-pointed (the D3 `#10` entry and D3 consequence (a)), one was not. The consequence bullet that congratulates the discipline for closing the #16 slip is itself the instance of it.

**Live harm, not tidiness:** the next author of a second `account_event`-class audit table obeys the standing *read-Decision-3-live* discipline, lands on ADR-042 D5, reads `#18`, and takes an already-allocated label. That is the duplicate-label form of the #16 failure.

**Fix — recommended shape (Path B, matching Decision 4's own PR #368 discharge, "numeral dropped so it cannot re-stale"):** strike the numeral rather than re-point it —

> "… **and add a Decision-3 instance** (`account_id → account` a second time)."

and correct consequence (b) to state what was actually done (three sites carried the pointer; two re-pointed, ADR-042 D5's numeral dropped). Re-pointing to `#19` would work too but recreates the same trap one allocation later.

**Explicit non-objection.** I do **NOT** require edits to `supabase/migrations/084_gl_split_posting_prototype.sql:281` or `supabase/migrations/089_fn_asset_priced_flags.sql:122`, which also read `#18`. Landed migrations are dated historical records, and this branch already applies exactly that reasoning correctly to the `[[SLOT-SEC]]` pin, which it annotated rather than rewrote — the right call, and I endorse it as written.

---

### F-3 — **flag, blocking** · two live `comment on table` objects assert SERIALIZABLE as the shipped write semantics · owner **Architect**

In `supabase/migrations/101_tax_bracket_tables.sql`:

- `comment on table pfin.tax_bracket_schedule` — *"**WRITE SEMANTICS:** the schedule and its rows are replaced as ONE unit **under SERIALIZABLE isolation** …"*
- `comment on table pfin.tax_bracket_row` — *"**WRITE SEMANTICS: replace-all under SERIALIZABLE** — the schedule's rows are deleted and re-inserted as one unit … **SERIALIZABLE and the set fence are INDEPENDENT controls** and neither substitutes for the other."*

The same file's own replace-all header states the opposite and is correct: *"`SET TRANSACTION ISOLATION LEVEL` **cannot** be issued inside a function body … the serialization comes from an explicit `FOR UPDATE` lock … rather than from the isolation level."* The ADR-011 D18 amendment records the same.

These are **live catalog objects asserting a control the schema does not build** — the #16 class this migration's own header is careful about elsewhere. Anyone reading `\d+`-level documentation, or any future audit that greps `comment on`, gets the wrong answer.

**Fix:** replace both `WRITE SEMANTICS` clauses with the mechanism actually shipped (one SECURITY INVOKER function, therefore one transaction, serialized by a `FOR UPDATE` lock on the schedule row), keeping the "two independent controls" point — which remains true of the **lock** and the set fence. If F-1 resolves as Option B, these comments should say so too.

---

### F-4 — **flag, non-blocking** · `tax_year` is the one numeric field on this Lock 14 surface that bypasses the mod #2 battery · owner **Backend**

`api/src/lib/server/schemas/tax-bracket-schedule.ts`:

```
tax_year: z.coerce.number().int().min(1913).max(2100),
```

`z.coerce.number()` **coerces rather than rejects**, which is the inverse of the discipline `numeric.ts` opens with (*"REJECT, not coerce-by-stripping"*) and of what ADR-011 D18's **V1-SHIP-BLOCK** mod #2 names (*"NaN/Inf/currency-string regex/overflow/scientific-notation/locale-formatted reject"*).

Measured (`node -e` over `Number(x)`), each of these lands as an integral 2000 inside `[1913, 2100]` and is **accepted**:

| input | result |
|---|---|
| `"2e3"` | 2000 — scientific notation, explicitly a mod #2 reject class |
| `"0x7d0"` | 2000 — hex |
| `" 2000 "` | 2000 — whitespace-padded |
| `[2000]` | 2000 — array coercion |

The RT-24 app battery (`tax-brackets.rt24-adversarial.server.test.ts`) covers `standard_deduction`, `tax_balance_prior_year`, `bracket_floor` and `bracket_rate` across all six adversarial categories. It does **not** cover `tax_year`, and no `numeric.ts` wrapper exists for it.

**Data effect today: none, and I say so plainly.** The endpoint's 409 schedule-identity guard requires `parsed.data.tax_year` to equal the resolved row's `tax_year`, so a coerced value can never change stored state. Mechanism present, reachability to a data effect nil.

**The reason to fix it anyway** is that the schema is written to be mirrored (its own header: *"Frontend's editor (SELF-265) mirrors this client-side … and must never ship a looser schema"*) and the next surface that copies this line will not have a 409 guard behind it.

**Fix:** add a `sanitizeYear` wrapper to `api/src/lib/server/validation/numeric.ts` on the existing reject-not-coerce core (`^\d{4}$`, integral, `[1913, 2100]`), route `tax_year` through the Zod adapter pattern the other three fields use, and add one RT-24 leg per rejected form above. **Catch criterion:** each of `"2e3"`, `"0x7d0"`, `" 2000 "`, `[2000]` returns 400 with a field error on `tax_year`.

---

### F-5 — **flag, non-blocking** · RT-24's acceptance text in `docs/SECURITY/index.html` is superseded on **four** counts, not two · owner **security-engineer (me)**

The dispatch brief named two (BEFORE-trigger, `lower_bound`). Reading the row verbatim, there are four. Current text:

> "**Bracket-row monotonicity DB-trigger verification (per Lock 14 mod #3 advisory):** BEFORE INSERT/UPDATE trigger on `pfin.tax_bracket_row` rejects writes that violate strictly-increasing `lower_bound` per `schedule_id` ordinal ordering (defense-in-depth backstop; app-layer validation is first line). **Replace-all SERIALIZABLE transaction semantics (per Lock 14 mod #4 advisory):** schedule+rows update wrapped in SERIALIZABLE transaction with DELETE + INSERT replace-all (prevents schedule-without-rows broken state + mid-tx monotonicity violations)."

Superseded:

1. **"BEFORE INSERT/UPDATE trigger"** → a **DEFERRED CONSTRAINT TRIGGER** (`AFTER INSERT OR UPDATE OR DELETE`, `DEFERRABLE INITIALLY DEFERRED`). `101` records that a BEFORE ROW trigger *cannot observe the property*, so the row currently mandates a control that cannot work.
2. **"`lower_bound`"** → the column is **`bracket_floor`**.
3. **"strictly-increasing `lower_bound` per `schedule_id` ordinal ordering"** → the checked property is **non-decreasing `bracket_rate` in ascending `bracket_floor` order**. Floor ordering is *deliberately not a leg* (`unique (schedule_id, bracket_floor)` makes it true by construction — the ADR-062 D2 rejected shape). There is no ordinal column. As written, RT-24 mandates the shape R4 rejected.
4. **"Replace-all SERIALIZABLE transaction semantics … wrapped in SERIALIZABLE transaction"** → superseded by the ADR-011 D18 amendment landing on this branch: one SECURITY INVOKER function serialized by a `FOR UPDATE` row lock, because the isolation level is not reachable on this transport.

Also **absent**: the zero-floor set property (leg A) has no RT-24 coverage at all.

**Commit-ready replacement** for the two `<strong>`-led clauses above (drop-in, same `<td>`, same house style):

> **Bracket-row set-property DB-trigger verification (per Lock 14 mod #3 advisory, as realized at migration `101` / R4 riders 1 + 8):** a **deferred** `CONSTRAINT TRIGGER` (`AFTER INSERT OR UPDATE OR DELETE`, `DEFERRABLE INITIALLY DEFERRED`) on `pfin.tax_bracket_row` evaluates the schedule's whole row set at COMMIT and rejects (**leg A**) a non-empty schedule whose lowest `bracket_floor` is not exactly `0`, and (**leg B**) any set whose `bracket_rate` decreases in ascending `bracket_floor` order. ⚠ A BEFORE ROW trigger is **not** an acceptable realization and this row no longer asks for one: it fires before its own row is visible and before the later rows of the same statement exist, so it passes a collectively-invalid multi-row `INSERT` — the shape the replace-all path sends. ⚠ Floor **ordering** is deliberately **not** a leg: `unique (schedule_id, bracket_floor)` makes one schedule's floors pairwise distinct, so such a leg could never fire (the [ADR-062](../../DECISIONS.md#adr-062) Decision 2 rejected shape). Defense-in-depth backstop; app-layer validation is first line. **Replace-all atomicity + serialization (per Lock 14 mod #4 advisory, as amended at [ADR-011](../../DECISIONS.md#adr-011) Decision 18, 2026-09-03):** the schedule and its rows are replaced as one unit inside a single `SECURITY INVOKER` function (`pfin.fn_tax_bracket_schedule_replace_all`), serialized by an explicit `FOR UPDATE` lock on the caller's own schedule row — **not** by a `SERIALIZABLE` transaction, which is not reachable from the PostgREST transport. That first statement is also the tenant fence: under `SECURITY INVOKER` it runs with the caller's own RLS, so an absent or other-tenant `schedule_id` resolves to zero rows and the function refuses, with one message for both cases so the error is not an existence oracle.

Two further edits, same row, same PR:

- The column-name substitution `lower_bound` → `bracket_floor` is carried by the replacement above; there is no other occurrence in the row.
- No change is owed to the row's first sentence (two-tenant RLS fixture) or to its app-layer-fences sentence — both are accurate as written. Stated so the untouched half does not read as unexamined.

**Ruling on vehicle:** this does **not** ride `feature/self-259`. I do not hold the pen on that branch, and paraphrase-through-a-third-party is the failure class this split exists to prevent. It lands as a **follow-up doc PR that I author, no later than the SELF-259 merge — not after it.** Merging `101` while `docs/SECURITY/index.html` still asserts a BEFORE trigger over `lower_bound` and a SERIALIZABLE transaction reproduces the #16 class on the register QA's battery is graded against.

---

### F-6 — **note** · two stale authorship caveats shipped in source · owner **Backend**, comment-only

- `api/src/lib/server/schemas/tax-bracket-schedule.ts` still points the reader at *"the `UPDATE→DELETE→INSERT` sequencing, **why there is no RPC**"*. There is an RPC; the endpoint calls it.
- `api/src/routes/api/settings/tax-brackets/[schedule_id]/+server.ts` still says the RPC contract is *"not yet independently confirmed against a landed sha as of this file's authorship"* and that *"the migration has not landed as of this file's authorship"*, and instructs *"READ THAT FILE LIVE, once pushed, before merging this endpoint."*

**I discharged that instruction as part of this review.** The landed signature —

```
pfin.fn_tax_bracket_schedule_replace_all(
  p_schedule_id bigint, p_tax_year smallint, p_schedule_type pfin.tax_schedule_type_enum,
  p_standard_deduction numeric, p_tax_balance_prior_year numeric, p_rows jsonb) returns void
```

— matches the endpoint's `.rpc()` argument object exactly, name for name and type for type. The caveats should be replaced with the confirmation, not deleted: a caveat removed silently reads as never having been owed.

**One residual the endpoint names and I am not asking it to fix here:** the P0001 collapse. Three distinct DB-side rejections (the RPC's own lock/ownership raise, the `#18` matched-tenant fence, the deferred set fence) all surface as `P0001`, and the endpoint maps them to one generic 400 rather than parsing message text. **That is the right call and I endorse it** — message-string classification of a security-relevant error is exactly the fragile guesswork it declines to do, and the pre-RPC ownership read gives a reliable, SQLSTATE-independent 404 for the case that actually needs distinguishing. The endpoint's own recommendation (a distinct SQLSTATE on the function's lock-failure raise, e.g. `raise exception … using errcode = 'PT404'`) is a sound future improvement, not a condition of this review.

---

### F-7 — **note** · a below-aal2 caller receives 404, not 403

The `025` clause is AND-ed into the **SELECT** policy as well as the write policies, so a `totp`/`passkey` user below `aal2` fails the endpoint's pre-RPC ownership read and gets `not_found` before `mapWriteError`'s `42501 → step_up_required` branch can ever fire. **Fail-closed and correct** — recorded only so nobody later reads the 403 branch as the live step-up path and builds a step-up prompt on it.

### F-8 — **note** · double-precision transit, pre-existing, not this PR's

`sanitizeDecimal` returns `Number(s)`, so a `bracket_floor` above 2^53 loses precision in the app layer before it reaches `numeric(20,4)`. This is inherent to every consumer of `sanitizeCurrencyAmount` since SELF-201, is not a SELF-259 regression, and is not reachable by any real bracket threshold. No action; recorded so it is not re-discovered as new.

---

## Explicit non-objections

Stated individually, because an unstated non-objection reads as an unexamined surface.

- **I do NOT object to `p_rows jsonb`.** Decision 18's forward-compat fence bars *"no JSONB blobs in the settings store"* — it governs **storage**. Every value lands in a typed numeric column carrying its own two-sided CHECK, no JSONB column exists on either table, and nothing reads settings back out of a document. The exact-two-numeric-keys shape check is what prevents the parameter becoming a de-facto blob. The header's argument is correct as written and I am not asking for it to be softened.

- **I do NOT object to SECURITY INVOKER on `fn_tax_bracket_schedule_replace_all`, and I would have refused DEFINER.** Under DEFINER the first `SELECT … FOR UPDATE` would see every tenant's row and ownership would become hand-rolled — replacing a fence the database applies with one a reviewer must verify. The ADR-011 Decision 9 SECURITY DEFINER allowlist is **untouched** by this migration; `(FN1)` pins `prosecdef = false` on all three functions.

- **I do NOT object to the EXECUTE split** (granted to `authenticated` on the replace-all, withheld from both trigger fences). PostgreSQL does not check EXECUTE when firing a trigger, so a grant on a fence buys nothing and hands out a callable entry point that can only ever error. `(FN1)` + `(RA9)` watch both halves. ⚠ Correctly, and stated in the file: for an **INVOKER** function EXECUTE is the weakest fence with RLS behind it — the inverse of the DEFINER case where the ACL is the entire perimeter.

- **I do NOT object to the undistinguished "absent vs other-tenant" RAISE.** It is the right existence-oracle posture and `(RA1)`/`(RA2)` prove the two messages are byte-identical. ⚠ One thing I checked rather than assumed: `SELECT … FOR UPDATE` applies the **SELECT** policy's `USING` *and* the **UPDATE** policy's `USING`, both of which are the same predicate on this table, and a row filtered by RLS is never locked — so there is no lock-wait **timing** oracle over another tenant's schedule id either.

- **I do NOT object to the coupling claim, and I confirm it as stated.** D3 consequence (e) and `101`'s own fence-2 note both say the set fence's sufficiency rests on `#18` and that striking `#18` makes it **narrow silently rather than fail**. Verified: `fn_tax_bracket_row_schedule_invariants` is `security invoker` and reads the set through RLS, so without `#18` a foreign-owned row could sit under the same `schedule_id` and be invisible to the fence's own read. **Narrow, not fail** — the wording is exact, and "narrow" is the more dangerous of the two, which is why it is the right word.

- **I do NOT require a floor-ordering leg**, and I would object to one being added. `unique (schedule_id, bracket_floor)` makes it true by construction; the leg could never fire. `(CAT5)` pins the premise the exclusion rests on.

- **I do NOT require a §10 ledger change.** Decision 4's Catalogued-§10 list is byte-untouched by this branch (`git diff origin/main...HEAD -- DECISIONS.md` produces no hunk inside it). Read live at review: **RT-22 / RT-26 / RT-27**. The **CI-fenced** set, read live via `grep -rhoE 'RT-[0-9]{2}' .github/workflows/`: **RT-05 / RT-22 / RT-26 / RT-27**. ⚠ **These are DIFFERENT SETS and must not be reconciled** — the CI-fenced set carries RT-05, which is not a catalogued §10 instance. `101`'s own §10 3-axis block is Path B (link, no restatement, no count) and is correct on all three axes: no instance added/reordered/renumbered, no layer re-attributed, no surface becomes "four-layer", Decision 4 linked rather than paraphrased.

- **I do NOT require an ADR-016 D1 / RT-26 allowlist amendment.** No `service_role` key reaches this route; `(GR2)` pins zero `service_role` table privileges on both tables and the migration grants none.

- **I do NOT require a CI fence change.** `fence-tbc-node`'s production-mode scope is `workers/provider-sync/src/` only (`.github/workflows/security-scan.yml`), so `api/` carries no `TenantBoundClient` obligation — the endpoint's claim is confirmed against the workflow, not relayed.

- **I do NOT object to the D3 `#18` entry's own numbering.** Verified against D3's live body: header reads *eighteen labeled (#1–#18), fifteen DDL-realized*; fold-in consequence (a) enumerates `#1, #2, #6–#18` = fifteen; `#5` stays DROPPED and `#3` + `#4` stay DDL-deferred. Internally consistent. **No tally appears on any derived surface** — `101` and the battery each state they carry none, and ADR-058's pointer says *"No count is carried here."* That discipline is held. The `[[SLOT-SEC]]` pin was **annotated rather than rewritten**, which is the correct treatment of a dated record and I endorse it. The **verbatim-vs-paraphrase** axis is clean: `101`'s quotations of D3's forward pointer and of D18's *"NOT a new instance … settings writes are user-session-bounded"* clause are byte-exact against the source, and the tail of the D18 sentence (V2+ live-tax-API trigger, mandatory Sec re-consult, Lock 12 mod #2 fence going V1-SHIP-BLOCK) is correctly carried forward as **live**, not retired.

- **I do NOT object to the battery.** Every fence leg has a demonstrated failure mode **and a non-vacuous control**: `(RA1)`/`(RA1c)`, `(D1)`/`(D2)`, `(RA11)`/`(RA11b)`/`(RA11c)`/`(RA11d)`. The adversarial cross-tenant `schedule_id`-under-forged-`users_id` leg is **real and present twice, once per writer** — `(W4)` from plain `authenticated` (the ownership forge, which is the route a real attacker has) and `(D1)` from an RLS-exempt `service_role` — each with its own control, and the file correctly declines to inherit the ADR-042/ADR-056 "RLS-exempt writer only" overclaim. The `S1–S8` USING/WITH-CHECK split correctly avoids the OR-masking trap. `(GR2)`'s parenthetical, that the service_role zero-grant is measured **before** Block D's temporary grant and undone by the final `rollback` rather than by an explicit `revoke`, is the right way to say it.

---

## Conditions to clear AMBER

| # | Condition | Owner |
|---|---|---|
| 1 | ADR-011 D18 amendment's *"covers every hazard the surface has"* clause corrected, **and** F-1's residual dispositioned (Option A accept-and-name, or Option B lock-in-the-set-fence). | Architect (text) · **F/CTO** (ruling) |
| 2 | ADR-042 Decision 5's `as #18` numeral dropped, **and** D3 fold-in consequence (b)'s "Both forward pointers" corrected to match what was done. | Architect · **F/CTO** notified (ledger) |
| 3 | The two `comment on table` `WRITE SEMANTICS` clauses in `101` corrected off SERIALIZABLE onto the shipped `FOR UPDATE` mechanism. | Architect |

Non-blocking, tracked: **F-4** (Backend — `sanitizeYear` + RT-24 legs), **F-5** (me — RT-24 doc PR, landing no later than the SELF-259 merge), **F-6** (Backend — comment-only).

**Nothing else.** The controls this migration builds are sound and I have no further finding against them.

---

## Re-review verdict — 2026-09-04, `3a599de`

**GREEN.** All three blocking conditions discharged; diffs reviewed since `7ccc908` only.

**F-1 (option B) — cleared, and the two shape departures are ACCEPTED as ruled at E20.**
The set fence's first statement after resolving the schedule takes `FOR UPDATE` on the parent
row, before the set read. I verified the ordering is what carries the property, not merely the
lock's presence.

- **Departure (i) — lock, read, RETURN on `count = 0`, and only then raise — is correct and
  necessary, not a weakening.** `on delete cascade` removes the child rows when the parent goes,
  so at COMMIT the parent is already gone and the lock resolves to zero rows; a lock-then-RAISE
  would make deleting a schedule impossible. **The deleting transaction is still serialized** —
  its own `DELETE` holds the lock on the very parent tuple the fence's statement tried to take.
  I walked the other zero-row paths rather than assuming: a caller that deletes all rows but
  keeps the parent took the lock at step (0); a caller to whom the parent is invisible also has
  the child rows invisible (that is what #18 buys), so `count = 0` and nothing was written. No
  unserialized path that matters.
- **Departure (ii) — KEEP THE OBSERVER LEG. Asked directly, my answer is that I prefer the
  observer to no leg, and the distinction is not the one ADR-062 D2 forbids.** A *rejected* leg is
  one that can never fire for **any** writer — the floor-ordering leg, which the unique constraint
  makes impossible even for a superuser. This leg fires for an RLS-exempt writer and under
  `session_replication_role = replica`; its unreachability is **conditional on another control**,
  which is exactly the shape ADR-011 Decision 4's own amendment describes (*"multiplicity of
  layers is … a property of a surface AND the writer"*). The alternative is worse in a specific
  way: **delete the leg and a non-empty set with an unresolved parent falls through to legs A and
  B, which then read a partial set under a caller whose RLS hides the rest — the silent narrowing
  this fence's own header names.** The leg converts that into a loud failure. It is the watcher
  for #18's absence, and a control whose watcher is removed because it "cannot fire today" is the
  regression this repo has already paid for. Message family and non-distinguishability match the
  replace-all's refusal, so it is not an existence oracle either.

**F-2 — cleared, and the correction is more complete than my finding was.** I named three sites;
classifying every occurrence of the literal found **six**. I have verified the six myself against
the live text: the `[[SLOT-SEC]]` pin and the `#17` entry (both dated records, **annotated in
place**), ADR-058's pointer, the `#10` entry, consequence (a) (**re-pointed**), and ADR-042
Decision 5 (**de-numbered**, the shape I recommended). ⚠ **The site I missed is the `#17` entry's
`"The next instance takes #18."`, and it was in my own grep output — I read the hits and
enumerated three.** My failure was in reading, not in grepping, which is the harder half to fix.
Consequence (b) now states the **predicate** rather than a count, and records that the review
which caught the completeness failure committed the same one. That is the right correction and I
endorse it as written; I do **NOT** ask for the wording to be softened on my account.

**F-3 — cleared.** Every `SERIALIZABLE` occurrence in `101` is now either the shipped mechanism or
an explicitly-marked historical note. Both `comment on table` `WRITE SEMANTICS` clauses are off
the false claim.

**F-4 — cleared, and better than asked.** `sanitizeYear` over a dedicated `sanitizeInteger` core,
with the real reason recorded (`maxDecimalPlaces: 0` would build `\d{1,0}`, an invalid
quantifier). All four measured inputs — `"2e3"`, `"0x7d0"`, `" 2000 "`, `[2000]` — have their own
rejecting legs, **plus two positive controls** (`2000` as number and as string), so the battery is
not vacuous.

**F-6 — cleared.** The stale caveats are replaced with the confirmation rather than deleted.

### Flags carried forward (neither blocks this merge)

- **R-1 — flag / QA. The battery is UNTOUCHED while the fence gained a statement and a leg.**
  `git diff --stat 7ccc908..HEAD -- supabase/tests/` is empty; `grep -c "set fence refused"` on the
  battery is `0`; `plan(91)` is unchanged. So **this round's entire deliverable — the second lock —
  ships with less watching than the first lock has**: `(RA10)` pins `for update` in the
  replace-all's body via `pg_get_functiondef`, and nothing pins it in the set fence. A future
  reader comparing the two reasonably concludes the fence has no lock. **Catch criterion, two legs,
  `plan(91) → plan(93)`:** (1) a `pg_get_functiondef` pin that
  `fn_tax_bracket_row_schedule_invariants`'s body contains `for update`, carrying RA10's own honest
  caveat that a text pin evidences **presence, never effect**; (2) the load-bearing one — an
  **ordering** pin that `for update` appears **before** the `count(*)` set read, because the
  header's own claim is *"this must be the FIRST statement after the schedule is resolved"* and a
  later edit moving the lock after the read would kill the control with every existing leg still
  green. The new raise leg is genuinely untestable in pgTAP (it needs the FK inert, i.e. a
  superuser-context GUC that `054`'s battery already declines to assert) — that is a fair
  no-watcher-possible, but it should be **stated in the battery header** rather than left silent.
  ⚠ **I considered AMBER on this and landed on GREEN deliberately:** the control was measured
  working two-session by Architect, so the gap is regression-detection rather than a live hole, and
  the leg I am asking for is itself only a text pin. Recorded so F/CTO can overrule me cheaply.
- **R-2 — flag / Architect, due at SELF-260's landing, not now. The 40P01 "RECORDED, NOT TESTED"
  ruling is right; one of its premises is not.** The ADR justifies not testing partly on *"no V1
  writer touches two schedules in one transaction"*, and enumerates two writers —
  `fn_tax_bracket_schedule_replace_all` (per-schedule ✓) and the SELF-265 editor (one schedule per
  save ✓). **SELF-260's seed is a third writer and it touches three:** its AC1 is *"3 rows inserted
  into `pfin.tax_bracket_schedule`"* (PM pre-flight findings). **The conclusion survives — a lone
  migration transaction cannot deadlock against itself, and per-user provisioning writes in a
  deterministic order — but the premise does not**, and the premise is what a future reader will
  rely on. One clause fixes it. Recorded because a correct conclusion resting on a false premise is
  the failure that outlives the review.

### Non-objections on this round

I do **NOT** object to: the observer leg (see above); the `RETURN` before the raise; the
re-entrancy claim (N deferred firings take one acquisition; the RPC's lock and the fence's compose
on the same row rather than deadlocking); the 40P01 disposition itself; or the decision to leave
`084` and `089` untouched. I do **NOT** require any further ADR wording change — consequence (b)'s
self-correction and the D18 amendment's two-lock bullet are both accurate as written, and the
amendment now states plainly that **neither** lock covers cross-schedule write skew.

**Nothing else.**

---

## Diff re-look verdict — 2026-09-04, `e9772e5` (schedule_label, E27/E29)

**AMBER.** One flag I want closed in-branch before merge (**D-1**, Architect, one DDL line plus one
battery leg). Everything else in the range is clean and the column itself is well-built. **Scope:
`git diff 6b3aa61..e9772e5` only** — the GREEN'd tip to the current tip, six files, nothing outside
them. `6b3aa61` was confirmed to contain `3a599de` (the ref the GREEN named) and to be an ancestor
of `e9772e5`, so this range is contiguous with the prior review and leaves no gap between them.

**Verify-hook discharged.** ADR-011 Decision 3, Decision 4 and Decision 18 were read **verbatim
from this branch's own `DECISIONS.md`**, each located by bracketing `## ADR-` heading, never by line
position, and Decision 4's amendments read in the same pass. **§10 three axes clean:** no catalogued
instance is added, removed, reordered or renumbered (the list reads RT-22 first / RT-26 second /
RT-27 third, unchanged); no layer attribution moves; and the migration's new paragraph is **Path B**
— it drops the enumeration and tells the reader to read Decision 4's list live, rather than
restating it. ⚠ The §10 **catalogued** set and the **CI-fenced** RT set are different sets and are
not reconciled here. Nothing in this range touches `.github/workflows/`, `secrets-manifest.yml`, the
ADR-016 D1 / RT-26 allowlist, or the ADR-011 Decision 9 SECURITY DEFINER allowlist — the diff is six
files and none of them is one of those surfaces.

### The six checks, answered

**(1) Decision 3 — no obligation, and the migration says so in the right shape.** Decision 3's rule,
verbatim, binds *"Any FK-shaped reference column (single FK, self-FK, INTEGER[] array element) that
crosses an isolation boundary."* `schedule_label text` is none of the three: it references no row,
holds no id, and is not an array of ids. The family is unchanged — eighteen labeled instances,
fifteen DDL-realized, #18 at `101`. `101`'s new ⚠ paragraph states the non-membership explicitly
rather than leaving it to inference, which is the same disposition `085` records for itself
(`085_taxonomy_element.sql`: *"085 added no FK-shaped column and no Decision-3 instance"*). Stating
it in the migration is the right home, because the per-column sweep above it is a sweep over column
SHAPE and a column added after that sweep is exactly the one it would miss.

**(2) RLS — the new column is covered, with nothing column-level anywhere.** Measured: a grep for
column-list grants against either `pfin.tax_bracket_*` table across `supabase/migrations/` returns
nothing; the only grants on the parent are the two table-level `grant select, insert, update, delete
… to authenticated` lines in `101`'s GRANTS block. A column added to a table whose access is
governed entirely by row-level policies plus a table-level DML grant is covered by those policies by
construction — there is no column ACL for it to fall outside of. QA also pins it behaviourally at
`(LBL-R)`: tenant A querying on B's known label value returns zero rows, so the column is inside the
row fence and not merely assumed to be. The eight structural policy legs (`S1`–`S8`) and the aal2
backstop blocks are untouched by this range.

**(3) The signature change — clean on every axis except the drop.** No stale six-argument text
survives anywhere in the tree (a tree-wide grep for the old parameter list at `e9772e5` returns
nothing); all twelve replace-all call sites and all seven schedule `INSERT`s are re-pinned; the
`revoke … from public` / `grant … to authenticated` pair and the `comment on function` are all three
re-attached to the seven-argument form, with the ACL shape identical to what it replaced (and
`(RA9)` still pins that `anon`, `service_role` and `PUBLIC` hold no `EXECUTE`). `(FN1)` still pins
`prosecdef = false` on all three functions — **no new SECURITY DEFINER function, and the Lock 11
INVOKER default is untouched.** What is missing is the `drop` — see **D-1**.

**(4) The overload hazard is documented — but not where an operator applying migrations reads it.**
It is stated well in two places: the endpoint's header (`+server.ts`, the ⚠ block on
`create or replace` adding an overload) and the battery's `⟦WIRE-VALIDATE⟧` header (which also
records that the scratch DB was rebuilt by sequential apply rather than cloned from a template, for
exactly this reason). It is **not** in `101` itself. See **D-1** and **D-2**.

**(5) The 500-char bound — the app-layer half is right; the render half is prospective.** The Zod
field is `z.string().trim().min(1).max(500)` inside the existing `.strict()` object, so the DB CHECK
is mirrored on the trimmed value and the whitespace-only case collapses onto the empty case, which
is what `101`'s own comment asks for. **The two bounds cannot disagree in the dangerous direction:**
JS `String.length` counts UTF-16 code units and Postgres `length(text)` counts characters, so for
any string the JS count is greater than or equal to the Postgres count — the app is stricter or
equal, never more permissive, and an astral-plane character is refused by the app before the DB
would have accepted it. The DB CHECK remains as the backstop either way. On rendering: **there is no
consumer today.** A grep for `schedule_label` across `api/src` at `e9772e5` returns only the schema,
the route, and that route's two test files — no Svelte component reads it yet. The obligation is
therefore **prospective, not a live gap**, and it is stated as such at **D-3**.

**(6) R-1 is fully discharged — all three of its asks, not two.** `(SF-L1)` pins the set fence's own
`FOR UPDATE` by `pg_get_functiondef`, carrying RA10's presence-never-effect caveat. `(SF-L2)` pins
the load-bearing half — the lock's position ahead of the `count(*)` set read. I verified `SF-L2`'s
premise against the actual body rather than trusting the leg: the function contains exactly one
`for update`, it is the parent-row lock, and the first `count(*)` is the set read that follows it,
so the position test is measuring the thing its message claims. R-1's third ask — that the
genuinely-untestable raise leg be *stated* in the battery header rather than left silent — is
discharged in the header's own leg-by-leg block, which names the leg UNTESTABLE and gives the
reason (`session_replication_role = replica`, a superuser-only GUC, which `054`'s battery already
declines to assert). `plan(91) → plan(100)`: `+2` from R-1's pins at `78f581b`, `+7` from the label
work, and the header's own leg enumeration sums to exactly 100.

### Findings

- **D-1 — flag / Architect. `101` adds no `drop function` for the superseded six-argument form, so
  on any database that already applied the file, the old function survives with its `EXECUTE` grant
  to `authenticated` intact.** Measured: `101` at `e9772e5` contains no `drop function` /
  `drop routine` statement of any kind, and the prior form (measured at `6b3aa61`) took six
  arguments. `create or replace` with a changed parameter list adds an overload; it does not replace.
  **Why this is a security finding and not only an operations one:** the surviving overload is a
  *live write path that does not take the label*. Its `UPDATE` never touches `schedule_label`, so
  the `NOT NULL` does not stop it — the brackets are rewritten and the caption that states which
  filing status and basis year they rest on is silently carried forward from the previous set. That
  is precisely the condition E27 created the column to prevent, and it would be reachable by any
  client still posting the old body shape, because PostgREST resolves an RPC by name against the
  argument names it is given. **The runbook in the route header is not a control** — it is advice in
  a file the person applying migrations does not open, and it degrades to nothing the moment nobody
  reads it. ⚠ **The repo's "drop-replace migration pattern" does not cover this** — I checked, and
  that term in `docs/MILESTONE-FRAMING.md` §8.2 names the Google-Sheets-to-V1 data-plane transition,
  not a convention of re-applying migrations to a fresh database. The name collision should not be
  allowed to retire this flag.
  **Catch criterion, and it is cheap:** a `drop function if exists
  pfin.fn_tax_bracket_schedule_replace_all(bigint, smallint, pfin.tax_schedule_type_enum, numeric,
  numeric, jsonb);` immediately ahead of the `create or replace`, which no-ops on a fresh database
  and removes the hazard **by construction** rather than by runbook; plus one QA leg pinning that
  exactly **one** `pg_proc` row carries `proname = 'fn_tax_bracket_schedule_replace_all'` in `pfin`.
  ⚠ **Three existing legs already fail if the stale overload is present** — `(FN1)`'s count would
  read 4 instead of 3, and `(RA9)` and `(RA10)` are scalar subqueries keyed on `proname` alone, so
  each would error on a second matching row. **That is a real detector and I am crediting it — but
  it can never fire in CI**, because CI builds the database from scratch and so structurally cannot
  hold the object the legs would catch. A detector that only fires in the environment nobody runs
  the battery in is not the fence; the `drop` is.
  **If F/CTO rules that no environment has ever applied `101`'s six-argument form and none will,
  D-1 downgrades to a note and this verdict is GREEN.** I cannot measure deployed database state
  from the repository, so I am naming the conditional rather than assuming either way.

- **D-2 — flag / QA. Comment-only, but it is the exact sentence an operator would read to decide
  whether their database is affected, and it points them at the wrong object.** The battery's
  `⟦WIRE-VALIDATE⟧` header says a stale template *"already had the old 7-argument-without-label
  signature."* The old form has **six** arguments (measured at `6b3aa61`); seven is the **new** form.
  A reader checking their database for a "7-argument" function will find the new one and conclude
  they are clean. One-word fix, same file.

- **D-3 — note / Frontend + Backend, prospective. The render-side obligation on `schedule_label`,
  stated now so it is not discovered at the consuming surface.** The column is user-authored text
  with no character-class restriction, and it is destined for the §2.5.2 editor and the
  tax-liability payload. **There is nothing to catch today** — no component reads it (measured
  above), and the only `{@html}` in the tree is the MFA QR at
  `api/src/routes/settings/security/+page.svelte`, which is unrelated. The criterion for whichever
  surface picks it up: render through Svelte's default `{…}` interpolation, which escapes; `{@html}`
  on this field would be a veto, not a flag. If the label ever reaches a CSV export or the PDF
  worker's payload, formula-injection (a leading `=` / `+` / `-` / `@`) and the worker's own escaping
  become live questions — neither surface exists at `e9772e5`, so neither is a finding now.

- **D-4 — note / Backend. A `U+0000` code point in `schedule_label` produces a 500 rather than a
  400.** `z.string()` accepts it; Postgres `text` cannot hold it, so the write fails with a code
  `mapWriteError`'s switch does not name, and its `default` branch returns
  `{ status: 500, error: 'internal_error' }`. This **fails closed** — nothing is written and nothing
  leaks, and the logged line carries only the code and the driver's message — so it is a status-code
  and log-noise residual, not a hole. Cheap fix if Backend wants it: a `.refine()` on
  `scheduleLabel()` rejecting a string that contains the `U+0000` code point, which moves the case
  into the existing 400 path with the other shape rejections.

- **D-5 — note / QA. Two small gaps in an otherwise thorough battery, neither blocking.** (i) `SF-L2`
  is a text-position test over `pg_get_functiondef`, whose output includes the body's own comments.
  A future comment containing the literal `for update` placed above the real lock would make the leg
  pass **vacuously** even if the lock had moved after the read — the fail-open direction. I verified
  it is clean at `e9772e5`; hardening it to assert exactly one occurrence would close the direction
  that matters. (ii) Nothing asserts that the **trim** reaches the database — the rejection legs
  cover whitespace-only input, and `(RA7e)` reads back an untrimmed literal, so the one path that
  silently mutates a user's data is the one path with no leg on it.

### Non-objections on this diff

I do **NOT** object to: `schedule_label` being plain `text` rather than a structured type — it
respects Decision 18's forward-compat fence (*"no JSONB blobs in settings store under any future
surface"*) and a constrained shape would be the wrong instrument for a free-text caption. I do
**NOT** object to the column being `NOT NULL` with no default: a replace-all that determines the
post-write state completely has no *"leave this one alone"*, and the function comment says so. I do
**NOT** object to the 500-character bound, to the empty string being refused, or to the label and
the rows being deliberately unconstrained to agree — the column comment names that non-guarantee
explicitly, which is the right disposition for user-authored data. I do **NOT** object to
`p_schedule_label` sitting in fourth position, since PostgREST binds by name. I do **NOT** require
any ADR amendment, any change to the §10 ledger, any Decision 3 fold-in, or any change to the
SECURITY DEFINER allowlist — none of them is touched by this range. I do **NOT** require a
re-review of the surfaces the prior GREEN cleared; this section is scoped to the diff and says
nothing about them.

**Nothing else.**

---

## Superseding verdict — 2026-09-04, `f540cbb` (E31 remediation)

**GREEN.** This section **supersedes the AMBER at `e9772e5` above**, which is left unedited as the
account of that moment per this file's supersede-don't-rewrite convention. **Scope:
`git diff e9772e5..f540cbb`** — five files, with `e9772e5` confirmed an ancestor of `f540cbb`, so
the three sections of this record now cover `7ccc908 → f540cbb` with no gap between them. Two items
are carried below; neither blocks, and **the first is my own error**.

**D-1 is discharged, by option (B) as ruled at E31.** The `drop function if exists
…(bigint, smallint, pfin.tax_schedule_type_enum, numeric, numeric, jsonb)` is present, and its
placement is correct and now load-bearing by statement: the `create type
pfin.tax_schedule_type_enum` sits at line 557, the drop at 1420, the `create or replace` at 1423 —
so the type exists when the drop is parsed, which is the failure mode I asked to be guarded against.
`101`'s new FRESH-APPLY-ONLY header does the thing I asked and does it better than I asked it:
it names the two guards (`create table if not exists`, the enum `do $$` block) as the constructs
that make the file **runnable twice but not correct twice**, states that the absence of an
`add column if not exists` pair is deliberate, and gives the reason option (A) was refused — that a
`NOT NULL` backfill would be a code path exercisable against no real row, choosing a default nobody
chose. **I accept (B) and I want the reasoning recorded, not just the outcome:** I named the
*half-state* as the veto, never option (B) itself, and (B) with the belt-and-braces drop is the
disposition that leaves nothing looking safer than it is.

**D-2 is discharged.** The battery header now reads *six*-argument and records the correction
rather than silently overwriting it.

**D-5(i) is discharged, and the fix is the right shape.** `SF-L2` moved from
`position('for update' in src) > 0` to `regexp_count(src, 'for update') = 1`. That closes the
fail-open direction exactly: a future comment mentioning the phrase can no longer coexist with the
real clause — it collides with it and reds. The leg's own message now states the mechanism
(`pg_get_functiondef` returns prosrc **with comments**) rather than asserting the property.

**The canonical-form CHECK landed verbatim in the shape I supplied, and the residual is stated
without a parity claim.** `check (schedule_label = btrim(schedule_label, E' \t\n\r\f\v') and
length(schedule_label) between 1 and 500)` — the stored-length bound is intact, so the padding
bypass I flagged against `length(btrim(x))` is closed. The column comment states the NBSP / U+2028
residual plainly (*"DB-LEGAL and APP-ILLEGAL … visually blank and structurally valid"*) and gives
the reason a Unicode whitespace class was **not** adopted: it would trade a stated residual for an
unstated one. **That is the right call and I want it on the record as a call, not a gap.**
⚠ **I do NOT require the NBSP residual fixed.** It is self-inflicted, reachable only by a caller
bypassing the endpoint, confined to that caller's own row, and it now has a written home.

**The two-fact watcher is what I asked for.** `(RA-SIG1a)` counts by `proname` **alone** — no
`pronargs` filter, so a stale overload is counted rather than excluded — and `(RA-SIG1b)` then
asserts that one proc's `pronargs = 7`, keyed `order by p.oid limit 1` so it cannot itself error
into ambiguity. Two facts that can disagree. `plan(100) → plan(110)` is `+6` canonical-form legs
(including `(LBL-CHECK1b)`, the TAB case, which is the member one-argument `btrim` would have
missed and is the reason the explicit character set was needed) `+2` RPC-path legs `+2` signature
legs, and the header's own leg enumeration sums to 110.

**Backend's arm is correct at the layer it sits in.** Control characters are refused across
U+0000–U+001F and U+007F–U+009F **after** the trim, so the bounded value and the forwarded value are
the same value; `(D-4)` is closed with a 400 and a field error and zero RPC calls, and its test
message names the future edit it exists to catch — a later narrowing of the range's lower
end so that U+0000 falls outside it and the hole silently reopens. The
`<script>` arm asserts the payload reaches `p_schedule_label` **byte-for-byte**, and the schema
comment says plainly that rejecting angle brackets would be the wrong fence at this layer.
**That is the correct disposition — sanitize on render, never on store** — and the render-side leg
is correctly assigned to SELF-265 rather than smuggled in here.

**Verify-hook re-run on this diff, not assumed.** ADR-011 Decision 3 and Decision 4 were re-read
because the DDL moved. A CHECK-constraint change introduces no FK-shaped reference column, so no
Decision 3 obligation arises and the family is unchanged; `101`'s Decision-3 ⚠ paragraph is
untouched by this diff (zero hunks against it). **§10 three axes clean:** no catalogued instance
added, removed, reordered or renumbered; no layer attribution moves; no enumeration restated. The
catalogued set and the CI-fenced set remain different sets and are not reconciled here. Nothing in
this range touches `.github/workflows/`, `secrets-manifest.yml`, the RT-26 allowlist, or the
SECURITY DEFINER allowlist. My own prior section merged into this branch unedited — 170 insertions,
zero deletions.

### Carried, neither blocking

- **E-1 — flag / Architect. Comment-only, and it is MY error: the measurement I supplied for the
  FRESH-APPLY-ONLY header now defeats its own re-verification.** The header reads *"13 migrations
  use it (010, 012, 015, 017, 019, 030, 033, 037, 044, 045, 058, 085, 091)."* **The enumeration is
  correct — thirteen entries, and `101` is rightly not among them.** But the header itself now
  contains the literal string `add column if not exists`, twice, in the course of saying the file
  does **not** use it. So the obvious re-verification —
  `git grep -l "add column if not exists" -- supabase/migrations/ | wc -l` — returns **14** at
  `f540cbb`, and the fourteenth is `101` matching on its own prose. A future reader running that
  command finds a number one higher than the header's, "corrects" the header to 14, and thereby
  asserts that `101` follows the convention it explicitly declines. **The drift is not in the
  claim; it is in the claim's testability, and I introduced it by handing over a count.** This
  repo's own test applies and resolves it — Decision 4's *"can a reader derive it by looking?"*:
  the count is derivable from the list, so stating it adds nothing and can only ever be wrong.
  **Drop the numeral, keep the enumeration** — or keep the numeral and add the one clause that
  makes it re-verifiable (thirteen *use* it; a fourteenth file *names* it, this one). Either is a
  single edit; I have no preference between them.

- **E-2 — note / Architect. The column comment's "WHERE THEY DO NOT [agree]" block enumerates one
  of two divergences.** It names the exotic-Unicode-whitespace residual and stops there. There is a
  second, in the same direction: **control characters are app-illegal and DB-legal.** The CHECK's
  `btrim` reaches only the *ends* of the value, so `E'federal\tordinary'` — a tab in the middle —
  satisfies `schedule_label = btrim(schedule_label, E' \t\n\r\f\v')` and is accepted by the
  database, while the endpoint refuses it 400 (and `(LBL-CHECK1b)` only pins the tab-**only** case,
  where btrim does reach it). Same shape as the NBSP residual: self-inflicted, own row, no
  cross-tenant reach, no leak — **a note, not a hole.** I raise it because the block is explicitly
  framed as the honest statement of where the layers part, and an enumeration that stops one short
  in exactly that block is the thing a later reader will trust as complete. One clause.

### Non-objections on this diff

I do **NOT** object to option (B), to the absence of an `add column if not exists` pair, or to the
`NOT NULL` column shipping without a backfill path. I do **NOT** require the NBSP residual, the
control-character residual (E-2), or the file's fresh-apply-only property to be given a mechanical
watcher — I said in advance that no battery leg can observe file shape and that a CI grep for this
would not earn a fence-boundary change, and I have not changed my mind now that the header exists.
I do **NOT** object to `<script>` being stored unmodified; write-layer sanitization would have been
the wrong fix and I would have flagged it. I do **NOT** object to the C1 range being refused, to
`.trim()` preceding the length and regex checks, or to the RPC declining to trim on the caller's
behalf. I do **NOT** require any ADR amendment, §10 ledger change, Decision 3 fold-in, RT-26
allowlist change, or SECURITY DEFINER allowlist change — none is touched. I did **not** run the api
suite or the pgTAP battery myself; team-lead reports 1962 green and `check` clean, and I am
recording that as a relayed figure rather than as my own measurement.

**Nothing else.**
