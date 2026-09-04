# SELF-260 / `103` — Security joint-review

**Verdict: RED.** Two vetoes, three flags, three notes. Both vetoes are on the
**California §17043 surtax row and its disclosure**; every other reviewed property is
clean, and the federal figures verified exactly against the primary source.

- **Reviewed diff:** `origin/feature/self-259...origin/feature/self-260`, tip **`7e8026c`**
  (`Merge QA 103 seed battery into feature/self-260`). Base `origin/feature/self-259` at
  **`55f19bc`** — re-read from the ref in this session, not carried from the brief.
- **Surfaces:** `supabase/migrations/103_tax_bracket_seed.sql` ·
  `supabase/tests/rls/103_tax_bracket_seed.sql` ·
  `api/src/lib/server/queries/taxonomy.ts` + `taxonomy.test.ts` ·
  `docs/records/v14-execution/self260-probes.md` · one bullet under ADR-011 Decision 18's
  amendment in `DECISIONS.md`.
- **Joint-review triggers met:** ADR-011 Decision 1 (privileged-context write — evaluated,
  D1-ADJACENT, see NO-1), Decision 3 (#18 consumer), Decision 4 (§10 — no ledger effect),
  Decision 18 (Lock 14 settings store).

---

## VETO 1 — the §17043 filing-status claim is FALSE, and it ships as an instruction to the user

**Sites (four, all carrying the same claim):**

| Site | Where |
|---|---|
| Migration header, E23 block | `supabase/migrations/103_tax_bracket_seed.sql:257-261` |
| Inline comment above the CA `VALUES` list | same file, `:409-410` |
| The `california_ordinary` `schedule_label` literal | same file, `:413` |
| `comment on function fn_tax_bracket_seed_template()` | same file, `:454-456` |

The claim, quoted from the label at `:413`:

> ⚠ That $1,000,000 threshold is the SINGLE-filer one and moves with filing status (it is
> $500,000 for married/RDP filing separately), so revise that floor too if you change the
> status.

and from the header at `:259-261`: *"the only row here whose FLOOR moves with filing
status."*

**Measured — the claim is contradicted by the cited statute's own text.**

- Fetched R&TC §17043 from `leginfo.legislature.ca.gov` (`codes_displaySection.xhtml?lawCode=RTC&sectionNum=17043`,
  HTTP 200). **§17043(a)** imposes the 1% on *"that portion of a taxpayer's taxable income in
  excess of one million dollars ($1,000,000)"* — one figure, no filing-status variant.
  **§17043(c)(2)** expressly provides that *"the provisions of Section 17041, relating to
  filing status and recomputation of the income tax brackets"* **shall not apply to the tax
  imposed by this section**; **§17043(c)(3)** likewise excludes §17045 (joint returns).
  The statute does not merely omit a status split — it affirmatively switches off the
  mechanism by which a status split could exist.
- Fetched `https://www.ftb.ca.gov/forms/2025/2025-540-booklet.pdf` (HTTP 200), `pdftotext -layout`.
  The **"Line 62 – Behavioral Health Services Tax"** worksheet subtracts a flat
  `$(1,000,000)` from Form 540 line 19 with **no filing-status branch** — on the same Form 540
  used by Single and Married/RDP-filing-separately alike.
- The string `$1,000,000 ($500,000 for married filing separately)` **does** occur in that
  booklet, at the Schedule CA **Line 8 – Home Mortgage Interest** acquisition-debt limit. That
  is a different provision. This is the most likely provenance of the error, and it is why the
  claim survives a spot-check.

**Consequence, and its direction.** §17043(c)(2) also means the threshold is **not
inflation-indexed** — a maintainer looking for an indexed 2026 figure will not find one, and
should not invent one. Worse, a married/RDP-filing-separately user who **follows the shipped
instruction** sets the top floor to 500,000 and is then charged 13.3% instead of 12.3% on the
$500,000–$1,000,000 slice of California taxable income: an overstatement of roughly **$5,000**
of tax. This is the only row on the surface the file tells the user to change, and the
instruction is wrong.

**Fix criterion (Architect owns the text; no code or DDL change required).** All four sites
state the $1,000,000 threshold as **flat across filing statuses and un-indexed, per R&TC
§17043(c)(2)** — citing subsection (c)(2) explicitly, so the next reader can check it in one
lookup — and **no site instructs the user to move that floor on a filing-status change**. The
seeded value `1000000.0000 / 0.13300000` is **correct and does not change**; battery leg `(T6)`
already pins it and needs only its message updated.

**⚠ ESCALATION — the ruling, not just the file.** Execution-log **E23** as relayed in the
review brief states *"its floor is the only value on the surface that moves with filing
status."* The migration implements that ruling faithfully. Correcting the migration without
correcting E23 leaves the false premise live in the canonical ruling, where the next surface
will inherit it — the inherited-citation class ADR-011 Decision 4's own CHANGELOG records for
PR #476. **team-lead / F/CTO must correct E23 in the same pass.**

## VETO 2 — `schedule_label` is computed and DISCARDED; the AC 6 disclosure reaches no user

**Measured.** `pfin.tax_bracket_schedule` (DDL at `supabase/migrations/101_tax_bracket_tables.sql:518-534`)
has columns `id · users_id · tax_year · schedule_type · standard_deduction ·
tax_balance_prior_year · created_at · updated_at`. `pfin.tax_bracket_row` (`:631-645`) has
`id · users_id · schedule_id · bracket_floor · bracket_rate · created_at`. **Neither table has a
label column.** Both writers in `103` list their target columns explicitly and neither includes
one (`103:499-500` for `fn_provision_tax_brackets`, `103:588-589` for the backfill).
`grep -rn schedule_label` over the worktree returns exactly four hits: the template's
`returns table` declaration (`103:358`) and three battery lines (`402/404/408`). **No writer, no
reader, no column.**

**What that falsifies.** The migration asserts a control that does not exist:

- `103:169` — *"It is carried in the schedule's own label text, which is where AC 6 places
  it."*
- `103:273` — *"The same sentence is carried in the schedule's own label so a reader
  meeting the row in the editor sees it too."*
- `comment on function` at `103:457-458` — *"Each schedule's label states its own year and its
  own SINGLE-filer assumption, which is where PM's A-6 places that assumption."*

None of these is true of the shipped system. A user opening the SELF-265 editor sees a
California schedule whose stored fields are `tax_year=2025`, `schedule_type=california_ordinary`,
`standard_deduction=5706` and ten `(floor, rate)` pairs topping out at `13.3% @ $1,000,000` —
**with no statement anywhere in the data** that it is a 2025 basis, a SINGLE-filer template, or
that its top row composes a second statute. Those three disclosures are precisely what rulings
E22 and E23 were about.

**The battery watches the wrong side of the seam.** Legs `(L1)` and `(L2)`
(`supabase/tests/rls/103_tax_bracket_seed.sql:401-411`, block header `:398-400`) assert the disclosure on
`pfin.fn_tax_bracket_seed_template()`'s **return value** — a column nothing consumes. They are
not legs that cannot fail; they are legs green over a discarded value. Nothing observes the
user-visible surface.

**Options — F/CTO / Architect disposition, not mine to pick:**

- **A — persist it.** Add `schedule_label text` to `pfin.tax_bracket_schedule` in a new
  migration and write it from both writers. *Cost:* a DDL change to a Lock 14 settings-store
  table (ADR-011 D18 joint-review, back to me); the editor must render it read-only or a user
  can delete their own disclosure.
- **B — render it.** Drop `schedule_label` from the template and own the disclosure in the
  renderer (SELF-262 / SELF-265), keyed on `(schedule_type, tax_year)`. *Cost:* no DDL, but the
  disclosure now lives in the frontend and can drift from the seed; needs its own AC and its own
  test, and the drift has no watcher unless one is built.
- **C — read it from the template.** Keep the column so the text has one home; SELF-262's
  helper calls `pfin.fn_tax_bracket_seed_template()` and matches on `(schedule_type, tax_year)`.
  *Cost:* the match falls through the moment a user edits `tax_year` — and a user editing the
  template is the whole premise of the surface.

Whichever is chosen, **the battery leg must observe the user-visible surface**, not the
template's return.

**Minimum to clear this veto for merge** (the disclosure mechanism itself may be a tracked
follow-up): **strike the three false assertions above**, and either remove `schedule_label` from
the template's `returns table` or annotate it in place — *"⚠ NOT PERSISTED: no label column
exists on either table; the AC 6 disclosure is owed by SELF-262 / SELF-265."* A file may ship
an unmet obligation named as unmet. It may not ship asserting a control it does not have.

⚠ **VETO 1 and VETO 2 are coupled.** VETO 1's corrected text partly lives in the label — which,
until VETO 2 is resolved, goes nowhere. Fixing VETO 1 alone leaves the correct statement as
invisible as the incorrect one was.

---

## FLAG 1 — the tax is renamed, for the exact tax year seeded

FTB 2025 Form 540 booklet, *2025 Tax Law Changes/What's New*: *"For taxable years beginning on
or after January 1, 2025, the Mental Health Services Act has been renamed to the Behavioral
Health Services Act. Therefore, references to the Mental Health Services Tax have been renamed
to Behavioral Health Services Tax."* Form 540 **line 62** is titled *"Behavioral Health Services
Tax."* The seed labels it **"Mental Health Services Tax"** at `103:407`, `103:409`, `103:413`,
`103:453` and battery `T6` (`:151`) — for tax year 2025, the first year of the rename.

R&TC **§17043 itself is unchanged and un-renamed**, so the statutory citation is correct; only
the popular name is superseded. Not a money error. **Owner: Architect** — fold into the VETO 1
text pass, since it touches the same four sites.

## FLAG 2 — the fail-closed unauthenticated refusal has no watcher

`fn_provision_tax_brackets()` opens with an explicit refusal when `auth.uid()` is null
(`103:483-489`) — the function's only stated fail-closed leg. Measured:
`grep -rn "no authenticated caller\|auth.uid() is null" supabase/tests/` returns exactly one hit,
`058_account_closure_fences.sql:832`, an unrelated fence. **Nothing in `103`'s battery exercises
it.** Leg `(P2)` pins the ACL (`anon` / `PUBLIC` / `service_role` EXECUTE absent) but the ACL and
the refusal are different controls; the refusal is what holds if a future grant widens.

**Catch criterion (QA):** with `request.jwt.claims` unset, `select
pfin.fn_provision_tax_brackets()` must `throws_like '%no authenticated caller%'`, **paired with a
control** showing the identical call succeeds once a tenant is set — the `(F4a)/(F4b)`
non-vacuity shape this battery already uses correctly elsewhere. One leg plus a `plan()` bump.

## FLAG 3 — `(R*)` and `(I1)/(I2)` measure a COPY of statement (3), not statement (3)

`103`'s backfill runs at apply time against whatever `auth.users` held then; the battery creates
tenants A/B afterwards and runs a **transcribed copy** of the statement
(`supabase/tests/rls/103_tax_bracket_seed.sql:178-202`, and again at `:322-346` for the
idempotency legs). If a future edit changes the migration's statement (3), the battery's copy
does not move, and `(I1)`/`(I2)` keep asserting a shape that no longer ships. This is inherent to
testing a one-shot migration statement — I am **not requiring a rewrite**. Record it: annotate
both blocks so a later reader does not read `(I1)`/`(I2)` as observing the shipped statement.
**Owner: QA (annotation only).**

---

## NOTE 1 — the backfill reaches every row of `auth.users` with no state filter

`103:574-577` cross-joins `auth.users` with no `deleted_at` / `is_anonymous` / `banned_until`
predicate. Measured: `grep -rn 'deleted_at\|is_anonymous\|banned_until' supabase/migrations/`
returns **nothing tree-wide** — `103` is the first migration to derive a user set from
`auth.users` at all, so there is no house convention to have departed from. Effect is bounded:
the rows are RLS-scoped to that user, carry no PII (they are published tax figures), and
`on delete cascade` removes them at hard delete. **I do NOT require a filter.** Recorded because
ADR-057 / ADR-062 D5 reach reasoning is about *who should be reached*, and "soft-deleted" is a
class the header's otherwise-thorough reach argument does not name.

## NOTE 2 — `create or replace` forecloses a column-list change to the template

The header commits corrections to *"a NEW migration that replaces the template function"*
(`103:139-141`, repeated at `:460-461`). `create or replace function` **cannot** change a `returns table` column list;
any future change to the returned shape — including removing `schedule_label` per VETO 2 —
requires an explicit `drop function` first. Not a defect. A fact the "just replace the template"
instruction does not carry, and the next author will meet it as an error.

## NOTE 3 — LT-CG floor convention at the exact threshold (not an error)

IRS Rev. Proc. 2025-32 §3.03 states $49,450 as the *maximum zero rate amount* (top of the 0%
band); the seed makes it the **floor of the 15% band**. Under a marginal computation — rate
applied to the slice above each floor — the two are identical for every input, and the federal
ordinary table has the same shape (*"Not over $12,400"* / *"Over $12,400"* → floor 12,400).
Stated only so a later reader comparing the seed side-by-side with the publication does not
"fix" it into a defect.

---

## Figures verified against primary sources

Method per the brief: `curl` + `pdftotext -layout`, never a WebFetch summary. Both PDFs
returned HTTP 200 on 2026-09-04.

**IRS Rev. Proc. 2025-32** (`https://www.irs.gov/pub/irs-drop/rp-25-32.pdf`, 260,406 bytes):

- **§3.01 TABLE 3 — "Section 1(j)(2)(C) – Unmarried Individuals (other than Surviving Spouses
  and Heads of Households)"**: all **seven** seeded pairs match the publication exactly —
  `0/10% · 12,400/12% · 50,400/22% · 105,700/24% · 201,775/32% · 256,225/35% · 640,600/37%`.
  ⚠ The adjacent Married-Filing-Separately table shares the first five floors and tops out at
  384,350 rather than 640,600; the seed took the right one.
- **§3.14(1) Standard Deduction**, "Unmarried Individuals … (§ 1(j)(2)(C))" → **$16,100**. Matches.
- **§3.03 Maximum Capital Gains Rate**, row "All Other Individuals" → maximum zero rate amount
  **$49,450**, maximum 15-percent rate amount **$545,500**. Matches.

**FTB 2025 California Tax Rate Schedules**
(`https://www.ftb.ca.gov/forms/2025/2025-540-tax-rate-schedules.pdf`, 52,676 bytes):

- **Schedule X — "Single or Married/RDP Filing Separately"**: all **nine** seeded pairs match
  exactly — `0/1% · 11,079/2% · 26,264/4% · 41,452/6% · 57,542/8% · 72,724/9.3% · 371,479/10.3% ·
  445,771/11.3% · 742,953/12.3%`.
- **2025 Form 540 booklet**, "California Standard Deduction Chart for Most People", filing status
  **1 – Single** → **$5,706**. Matches.
- **Tenth row `1000000.0000 / 0.13300000`** — the composed 12.3% + 1% marginal rate above the
  §17043 threshold. **The value is correct.** Only the filing-status prose attached to it is
  wrong (VETO 1).

**Rates are fractions** throughout (E1): battery leg `(T4)` pins every seeded rate into `[0,1]`,
which is the watcher that catches a `22`-for-`0.22` slip. **Filing status SINGLE is stated in
every template label** — and, per VETO 2, in nothing that reaches a user.

**Both FTB 2026 URLs re-measured this session: HTTP 404.** The E22 premise holds as stated.

---

## Verify-hook — ADR-011 D1 / D3 / D4 / D18 read verbatim from the branch body

Located by bracketing `## ADR-` heading, never by line number. **Three axes clean.**

- **D1** — four clauses (a)-(d) read verbatim. `103`'s classification is **accurate**: it meets
  (a) ingress under no JWT and (c) tenant correctness from code; it meets **neither (b)** — the
  writer is the schema owner, not `service_role` — **nor (d)** — no audit-log row. The header
  states this as **D1-ADJACENT, not a D1 instance**, and explicitly bars citing `103` as
  precedent for a `service_role` surface shipping without (d). That is the `077`/`091`
  disposition, unchanged. **I concur.**
- **D3** — the family reads *"eighteen labeled instances (#1–#18), fifteen DDL-realized; #5
  (`account.sub_cat_id`) DROPPED at `048`; #3 + #4 … DDL-deferred to V1.3+ … #18 realized latest
  at `101`."* `103` adds **no column of any kind** and no FK-shaped reference; it correctly calls
  itself a **CONSUMER** of #18's fence rather than an extension of the family. **Family unchanged,
  +0.** Verified shape, not tally.
- **D4 (§10)** — catalogued list read verbatim: **RT-22 first** (infrastructure-credential-presence
  layer), **RT-26 second** (code layer), **RT-27 third** (network-exposure/config layer); count 3.
  `103` carries **no count**, restates no enumeration, and links rather than absorbs — **Path B**,
  correct for a surface that REFERENCES. No instance added / removed / reordered / renumbered; no
  layer re-attributed; no paraphrase of the three-layer composition. ⚠ **The §10 CATALOGUED set
  and the CI-FENCED set remain DIFFERENT SETS.** Nothing in this branch reconciles them and
  nothing should.
- **D4 SELF-257 amendment** — directly adjacent and worth naming: the migration role is
  RLS-exempt (owner exemption + no `FORCE ROW LEVEL SECURITY` on any `pfin` table), so on this
  Decision-3 surface the matched-tenant **trigger is its only applicable layer**. The header names
  the writer and the exemption explicitly, which is exactly what that amendment asks for. See NO-1.
- **D18 (Lock 14)** — **answering the brief's question directly: the template is OUTSIDE the Lock
  14 enumeration, and its writes are INSIDE the store.** The enumeration is of **tables** — the
  amended family is five (`planning_target · cashflow_target · tax_bracket_schedule ·
  tax_bracket_row · owner_identification`). `103` adds **no table** and no `_default` table, so the
  family stays at five and the family-size amendment's arithmetic is untouched. But the rows it
  writes land in two of those five, so Lock 14's write-path disciplines apply — and are met (see
  NO-2). The forward-compat **no-JSONB-blobs** fence is untouched: the template returns a typed
  table and every value lands in a typed numeric column.

**⚠ Drift found — in MY OWN persisted memory, named here rather than in a follow-up.** My memory
file recorded the Decision 3 family as *"17 non-contiguous labels, 14 DDL-realized, #18
unallocated."* The live ADR reads **eighteen labeled, fifteen DDL-realized, #18 allocated at
`101`**. My memory is stale; the review above used the live body. I am correcting the memory file.

**⚠ Live V2+ obligation, restated because this branch is adjacent to it and a truncated reading
would retire it.** D18's locked sentence tail — *"chain becomes live only at V2+ live-tax-API
ingestion under service_role (Sec re-consult mandatory at that adoption with Lock 12 mod
#2-pattern fence becoming V1-SHIP-BLOCK)"* — is **NOT tripped by `103`**: these are
migration-embedded constants, no ingestion, no `service_role`. The surface to watch is the
follow-up that seeds California 2026 when the FTB publishes. **If that is ever automated against a
published source rather than hand-transcribed into a migration, this trigger fires.** Put the
obligation on that issue now, while the connection is visible.

---

## Non-objections, stated explicitly

- **NO-1 — I do NOT require `FORCE ROW LEVEL SECURITY`, an audit-log row, or any additional
  layer for the backfill.** Per D4's SELF-257 amendment the migration role stands at exactly one
  applicable layer on a Decision-3 surface, but the write is correct **by construction, not by the
  fence**: in both writers the child's `users_id` and its `schedule_id` are taken from the **same
  CTE row** (`103:511-513` and `103:588-590`), so #18's leg 2 cannot be violated by any input —
  the template carries no tenant column that could be crossed. The header states the exemption
  rather than assuming it, which is what that amendment asks of a layer inventory.
- **NO-2 — I do NOT require a Zod schema, `.strict()`, or the Lock 14 numeric-input adversarial
  battery on `provisionTaxBrackets`.** Measured: `fn_provision_tax_brackets()` takes **zero
  parameters**; `taxonomy.ts:225` calls `rpc('fn_provision_tax_brackets')` with no argument object,
  and `taxonomy.test.ts` pins that (`expect(s.rpc).toHaveBeenCalledWith('fn_provision_tax_brackets')`);
  `users_id` comes from `auth.uid()` inside the function; every value comes from a constant
  function. Mass-assignment and adversarial numeric input are impossible **by construction**, not
  by validation — which is stronger than the mod requires, not an exemption from it.
- **NO-3 — I do NOT require either function to be SECURITY DEFINER, and no ADR-011 Decision 9
  allowlist entry is added.** Read live: `pfin`'s DEFINER set is `fn_grant_creator_access ·
  fn_reclass_history_insert · fn_refresh_updated_at`; battery leg `(P3)` pins `prosecdef = true`
  in `pfin` to exactly that array. INVOKER is correct on both, and the header's reasoning is right
  — DEFINER on the provisioner would let it write past the `025` aal2 backstop conjunct on both
  tables' INSERT policies, a privilege this surface has no reason to hold.
- **NO-4 — IMMUTABLE on the template is HONEST.** The body is a constant `VALUES` list with enum
  and numeric casts; it reads no table, calls no non-immutable function, and returns the same set
  for the same (empty) input in every transaction. `volatile` on `fn_provision_tax_brackets` is
  likewise correct. Both carry `set search_path = ''` and every reference in both bodies is
  schema-qualified (`pfin.*`, `auth.uid()`, `auth.users`) — verified by reading, not assumed.
- **NO-5 — I do NOT require `103`'s battery to re-test the #18 cross-tenant fence.** Measured:
  `supabase/tests/rls/101_tax_bracket_tables.sql` already covers it adversarially — leg `(D0)`
  first proves `service_role` carries `rolbypassrls = true`, so leg `(D1)`'s `%is owned by another
  tenant … leg 2 cross-tenant%` raise is proof of the **trigger's** predicate rather than of RLS,
  plus six cross-tenant write legs. Duplicating it here would add no coverage.
- **NO-6 — I agree with Architect that an any-row existence guard must NEVER be "restored" on
  this surface, and the reasoning is right.** Per-key `on conflict (users_id, tax_year,
  schedule_type) do nothing` is exactly what keeps a user holding three schedules fully reachable
  for a fourth. An any-row guard would reproduce the `041` trap ADR-057 exists to name — and would
  do it silently. Reaching a zero-row user is the **intended** effect here, and the `077`/`080`/`091`
  derive-from-the-target-table shape is genuinely impossible on a greenfield table: it would reach
  nobody, which is the `077` defect rather than a conservative reading of it. The departure is
  sound and is declared rather than silent.
- **NO-7 — the header's E22 paragraph is ACCURATE.** Nothing in `103` makes a 2025 row answer a
  2026 question; the fallback is asserted as SELF-262's twice, and leg `(E1)` pins the **absence**
  the fallback fires on. I also confirm rejected alternative **(b)**: a present-but-empty 2026 CA
  schedule would both **suppress** the fallback (the helper never reaches 2025) and **consume** the
  `(users_id, 2026, california_ordinary)` unique key, so a later migration seeding the real
  published figures would be silently skipped by its own `on conflict do nothing`. (b) is worse
  than (a), as stated.
- **NO-8 — the 40P01 / Decision 18 amendment bullet is correct and I do not require a test.** The
  three-part argument holds: a lone migration transaction cannot deadlock against itself; the
  provisioner's `order by p.schedule_type` then `order by s.id, t.bracket_floor` gives a
  deterministic lock order across concurrent callers; and today's second caller reaches no locks at
  all because `on conflict do nothing` returns zero parents and the child INSERT is driven off that
  empty set. Stating the ordering as the **backstop** rather than the primary reason is the right
  call — the primary one stops holding the moment a future writer seeds a schedule the caller
  lacks. `pgTAP` remains structurally unable to observe a two-transaction interleave, so
  RECORDED-NOT-TESTED still stands.
- **NO-9 — the fail-soft app wiring is correct.** `provisionTaxBrackets` has its own `try/catch`,
  never rethrows, and runs last; `taxonomy.test.ts` pins branch independence in both directions
  (a taxonomy-branch failure does not stop the bracket branch, and vice versa) and pins the
  ordering. A caller below `aal2` under a `totp`/`passkey` policy is refused by the `025` clause on
  the INSERT policies — fail-closed at the DB, degraded softly at the app, which is the right
  split. No tenant data reaches the log lines.
- **NO-10 — ADR-016 Decision 1 / RT-26, `secrets-manifest.yml`, and the CI fences are UNTOUCHED
  by this branch.** No `SUPABASE_SERVICE_ROLE_KEY` surface is added; leg `(P2)` pins `service_role`
  EXECUTE **absent** on both functions. No fenced RT, no `TenantBoundConnection`, no workflow, no
  Dockerfile appears in the diff. Nothing here requires an ADR-016 amendment.

---

## Ownership summary

| # | Severity | Finding | Owner |
|---|---|---|---|
| V-1 | **VETO** | §17043 threshold is flat and un-indexed per (c)(2); "$500,000 for MFS" is false and shipped as an instruction | Architect (text, 4 sites) + **team-lead/F/CTO to correct ruling E23** |
| V-2 | **VETO** | `schedule_label` computed and discarded; three sites assert a disclosure that reaches no user | Architect (strike the assertions to clear); F/CTO to pick A/B/C for the disclosure itself |
| F-1 | flag | "Mental Health Services Tax" renamed to "Behavioral Health Services Tax" for TY2025 | Architect (same text pass) |
| F-2 | flag | Unauthenticated-refusal leg has no watcher | QA (one leg + control) |
| F-3 | flag | `(R*)`/`(I1)`/`(I2)` measure a transcribed copy of statement (3) | QA (annotate; no rewrite required) |
| N-1 | note | Backfill has no `auth.users` state filter; no house convention exists | — (recorded) |
| N-2 | note | `create or replace` cannot change the template's column list | — (recorded) |
| N-3 | note | LT-CG floor-vs-ceiling convention is correct under a marginal computation | — (recorded) |

**Nothing else.** Posture, ACL, `search_path`, INVOKER discipline, the DEFINER allowlist, the
#18 fence, idempotency, the deferred set fence's first multi-row exercise, the concurrency
argument, the app wiring, and the D1 / D3 / D4 / D18 classifications are all clean.
