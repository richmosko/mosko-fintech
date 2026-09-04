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

---

# Re-review — 2026-09-04, tip `393c7af`

**Verdict: RED.** Two new vetoes, three flags, two notes. **Every round-1 finding is
discharged** — V-1, V-2, F-1, F-2 and F-3 all landed, and V-1 landed better than I asked. The
new RED is entirely on the **unpropagated half of the signature change that V-2's fix required**:
`fn_tax_bracket_schedule_replace_all` gained a seventh parameter and nothing outside the
migration moved with it.

Reviewed `7e8026c..393c7af` (4 files: `101`, `103`, the battery, and my own round-1 record
merged in). `origin/feature/self-259` is at `b073641` and is contained in this tip, so the `101`
label column and the signature change are in the tree I am verdicting — the app half is not
"in flight elsewhere", it is stale here.

## VETO 3 — the `p_schedule_label` signature change is unpropagated, and the stale overload is undefended

- `101:1324-1331` declares `pfin.fn_tax_bracket_schedule_replace_all` with **seven** parameters,
  `p_schedule_label text` fourth, **no DEFAULT**.
- `api/src/routes/api/settings/tax-brackets/[schedule_id]/+server.ts:260-265` — read from the
  committed blob at `393c7af`, not the worktree — calls
  `rpc('fn_tax_bracket_schedule_replace_all', {…})` with **six** named arguments and no
  `p_schedule_label`. Its last touch is `d5cb00c`, which predates `ae9ff35`. PostgREST resolves
  RPC by named-argument set, so no function matches: **`PGRST202`, every §2.5.2 settings save
  fails.**
- `git show 393c7af:api/src/lib/server/schemas/tax-bracket-schedule.ts | grep -c schedule_label`
  → **0**. `grep -rn schedule_label api/src/` → nothing tree-wide.

**The security half, which is the part that is not merely broken-loud.**
`grep -n "drop function" supabase/migrations/101_tax_bracket_tables.sql` → **NONE**.
`create or replace function` with a **changed argument list creates an OVERLOAD; it does not
replace.** On a clean apply only the 7-arg form is ever created, so this is inert in CI and in
production — I want that stated plainly. But in any environment where `101` was applied at its
6-arg revision and the amended file is then applied, **both overloads exist and both carry
`EXECUTE` to `authenticated`** — and the 6-arg form satisfies the endpoint's existing call
exactly. It performs a full DELETE-and-reinsert of the bracket set while **never touching
`schedule_label`**, leaving the label stating the old filing status and old basis year for
numbers that changed underneath it. That is precisely the state V-2 was opened to prevent,
reachable by a plain authenticated caller, silently, with no error. The file offers no defense
against it and does not mention the possibility.

**Fix criterion:**
1. **Architect** — `drop function if exists pfin.fn_tax_bracket_schedule_replace_all(bigint,
   smallint, pfin.tax_schedule_type_enum, numeric, numeric, jsonb);` immediately before the
   `create or replace`, so the old signature cannot survive any apply order.
2. **Backend** — the endpoint passes `p_schedule_label`; see VETO 4 for what it may pass.
3. **QA** — a catalog leg pinning that `pfin` holds **exactly one** proc named
   `fn_tax_bracket_schedule_replace_all` with `pronargs = 7`. That is the watcher which makes the
   *next* signature change fail loudly instead of overloading; without it this class recurs
   silently.

## VETO 4 — `schedule_label` is the first user-controlled free-text field on a Lock 14 write path, and it ships with the DB half only

This is a joint-review-mandatory surface (Lock 14 — typed-input validation + mass-assignment
prevention) and the app-layer control is **absent**, not weak. The only validation in the tree is
the DDL's `length(schedule_label) between 1 and 500`. Owed before the field is reachable:

- **Backend** — `schedule_label: z.string().min(1).max(500)` on
  `taxBracketScheduleReplaceSchema` (`api/src/lib/server/schemas/tax-bracket-schedule.ts:165-173`),
  keeping `.strict()`. Refuse control characters (`.regex(/^[^\p{Cc}]*$/u)`, or an explicit
  newline/tab policy if multi-line captions are intended). Refuse whitespace-only — `.trim()`
  then `.min(1)`, or `.refine(s => s.trim().length > 0)`. **State whether the trimmed or the
  untrimmed value is written**; the DB stores exactly what it is handed.
- **Frontend** — the label must render **escaped**. Svelte's `{label}` is safe; `{@html label}`
  is not. I require that `schedule_label` never reaches `{@html}`, and that any client-side 500
  bound in the §2.5.2 editor is a **mirror** of the server control, never the control itself.
- **⚠ Unresolved, and I am saying so rather than either ignoring it or asserting it.** The column
  comment states the label is *"passed through to the tax-liability payload."* I have **not**
  established whether that payload reaches the Lock 13 PDF worker's template. If it does, 500
  characters of user-controlled text enter a renderer inside a zero-DB-isolation container, and
  escaping there is a **separate control** from escaping in Svelte — it must be shown, not
  assumed. The answer is owed before the §2.5.3 render lands. Owner: Architect to answer,
  DevOps/Backend to realize if the answer is yes.
- **QA** — the RT-24 adversarial battery
  (`api/src/routes/api/settings/tax-brackets/[schedule_id]/tax-brackets.rt24-adversarial.server.test.ts`)
  covers numeric inputs only; it gains a **string arm**: over-length (501), empty,
  whitespace-only, control characters, and a `<script>` payload asserted **stored and escaped at
  render** rather than rejected — the label is prose, and rejecting angle brackets would be the
  wrong control.

## FLAG 4 — the DDL admits the blank its own comment says it refuses

`101:547-549` is `check (length(schedule_label) between 1 and 500)`. The column comment says *"a
schedule whose assumptions go unstated is the condition this column exists to prevent, so the
empty string is refused rather than admitted as a blank."* A single space has length 1 and
passes. `check (length(btrim(schedule_label)) between 1 and 500)` enforces what the comment
claims. **Owner: Architect.** This is the second-line control; the Zod `.trim()` in VETO 4 is the
first, and neither substitutes for the other.

## FLAG 5 — the battery's `BINDS TO MIGRATION` line is stale, on the very file whose F-3 fix is a hash pin

`supabase/tests/rls/103_tax_bracket_seed.sql:8` still names `07871f6`; `103` has moved twice
since (`817c44e`, `8247778`). **Answering the question directly: yes, this must move before
GREEN.** F-3's remediation was to pin the transcribed statement's md5 — a binding claim that is
itself wrong, sitting a few lines above that pin, defeats what the pin is for. **Owner: QA**, and
re-derive it from the committed blob (`git show <sha>:supabase/migrations/103_tax_bracket_seed.sql`),
never from the worktree file.

## FLAG 6 — "`Mental Health` count 0" is true of the migrations and false of the battery

`grep -c "Mental Health"`: `103` → **0**, `101` → **0**,
`supabase/tests/rls/103_tax_bracket_seed.sql` → **2** (line 31, the header; line 159, the `(T6)`
assertion message). F-1 is discharged in the DDL and not in the assertions that describe it.
**Owner: QA.** Two test-message strings do not matter much on their own; I am naming it because
the report and the tree disagreed, and that is the thing worth catching.

## NOTE 4 — the CA label has 27 characters of headroom

Measured by extracting the three label literals from `103` and counting: **180 / 190 / 473**
characters against the 500 bound (E29 widened 200→500 after the label gained its citations). One
more source line breaks the apply. It breaks **loudly** — the CHECK, plus `(L4)` and the `(L5)`
exact-473 pin — so this is a bound to know about, not a defect.

## NOTE 5 — the seeded label is OUR claim until the user edits it

Option A makes the disclosure user-editable, which is right for settings, and the column comment
is honest that the label is user-authored and *"NOT constrained to agree"* with the rows — I do
**not** require a fence that would make them agree. But a **never-edited** seeded label is ours,
not the user's, and that disclaimer lives in a DB comment no user reads. Not a blocker, and I am
not requiring a fix. Route to SELF-262/265 as a rendering question: does the §2.5.3 payload
distinguish a never-edited label from a user-edited one?

## Round-1 findings — all discharged

- **V-1 — discharged, and better than I asked.** The flat/un-indexed statement now cites **both**
  §17043(c)(2) and (c)(3) at every site, and it adds what I did not think to require: it names
  what the SINGLE assumption *does* govern on that schedule — the standard deduction from the
  Form 540 chart at status 1. `grep '\$500,000'` over `101` / `103` / the battery → no hits.
  `(L2)` is a durable watcher asserting the stored CA label states the threshold is FLAT, so the
  regression cannot return silently.
- **V-2 — discharged.** Both writers persist the label. ⚠ **`select distinct` now carries
  `schedule_label`, which RESTORES the self-policing property the round-1 version had lost by
  excluding it** — a label that disagreed across one schedule's rows now yields two parent rows
  for one unique key and aborts, rather than diverging quietly. BLOCK L reads the **stored**
  column throughout, and `(L6)` exercises the signup-path writer independently of the backfill
  writer, so a regression in one is attributed correctly.
- **F-1 — discharged in the DDL** (subject to FLAG 6 in the battery).
- **F-2 — discharged, in the right shape.** `(U2)` asserts the identical call **succeeds** once a
  tenant is set, so `(U1)` cannot be a stub that always throws.
- **F-3 — discharged in substance** (transcription annotation with the statement's md5 pinned),
  subject to FLAG 5.

## Verify-hook, re-run live at `393c7af`

- **D3** — read live again. `schedule_label` is correctly ruled **outside** the Decision 3 family:
  it is text, references no row, holds no id, and is not an `INTEGER[]` of ids. `101`'s new header
  paragraph states this rather than leaving it to inference, which is the right call — the
  per-column sweep it sits under predates the column, and a column added after a sweep is exactly
  the one that escapes it. **Family unchanged.**
- **D4 (§10)** — catalogued list read live again: RT-22 / RT-26 / RT-27. No instance added,
  removed, reordered or renumbered; no layer attribution moves; no surface becomes "four-layer".
  Neither file carries a count. **Three axes clean.** The CATALOGUED and CI-FENCED sets remain
  different sets and nothing here touches either.
- **D18** — the label column is a new column on a Lock 14 settings-store table, which is why VETO
  4 exists. It stores **text, not JSONB**, so Decision 18's forward-compat no-JSONB-blobs fence is
  intact. The family is still five tables; no table was added.
- `DECISIONS.md` is **unchanged** in this range — the D18 40P01 bullet I cleared in round 1 has
  not moved.

## Non-objections carried forward and re-checked at this tip

Everything in round 1's non-objection list still holds and I re-checked the two that the diff
could have moved: `fn_provision_tax_brackets` and `fn_tax_bracket_seed_template` are **still both
SECURITY INVOKER** with `set search_path = ''`, and the **SECURITY DEFINER allowlist is
untouched** — `(P3)` still pins `pfin`'s `prosecdef = true` set to the same three names. The
tenant binding in both writers is still taken from the same CTE row, so #18 leg 2 still holds by
construction with the label column added. `secrets-manifest.yml`, RT-26 and every CI fence remain
untouched by this branch.

---

# Re-review 2 — 2026-09-04, tip `2173263`

**Verdict: AMBER — no veto, no security defect.** VETO 3 and VETO 4 are discharged, F-4 landed
**stronger** than I asked, and F-5 / F-6 are clean. What remains is **one finding class in four
sites**, all prose, all in the app layer: the superseded shape of the label CHECK, including one
line claiming a parity that `101` explicitly refuses to claim. Text only; no code, no DDL, no
re-review. **Merge once the four lines are corrected.**

Reviewed `393c7af..2173263` (8 files), which contains the final `feature/self-259` at `f540cbb`.
Everything below is read from the **committed blob at `2173263`** — my worktree is checked out on
`feature/self-260-sec` and is not the review surface.

## FLAG 7 — four app-layer sites carry the superseded CHECK shape; one asserts a parity the DDL disclaims

The constraint as landed at `eab2ad1` is
`check (schedule_label = btrim(schedule_label, E' \t\n\r\f\v') and length(schedule_label) between 1 and 500)`
— a **canonical-form invariant**, not a length rule.

| Site | What it says | Owner |
|---|---|---|
| `api/src/lib/server/schemas/tax-bracket-schedule.ts:93` | states the CHECK as `length(schedule_label) between 1 and 500` | Backend |
| same file `:97` | *"max 500 **mirroring the DB CHECK exactly**"* | Backend |
| same file `:96` | quotes `101` as saying *"the empty string is refused rather than admitted as a blank"* | Backend |
| `.../tax-brackets.rt24-adversarial.server.test.ts:119` | describe block — *"migration 101 CHECK, length 1..500"* | QA |
| same file `:136` | the same quotation of `101` | QA |

⚠ **`:97` is the load-bearing one.** `101`'s column comment goes out of its way to say the
opposite: *"THE RESIDUAL, STATED HONESTLY: the two layers are NOT at parity and no parity claim
is made here."* The app file makes precisely the claim the DDL refuses to make.

⚠ **The two quotations outlived their source.** `git show 2173263:supabase/migrations/101_tax_bracket_tables.sql | grep -c "rather than admitted as a blank"` → **0**. That sentence was
rewritten at `eab2ad1`; both files still attribute it to `101` inside quotation marks.

`+server.ts` and `supabase/tests/rls/101_tax_bracket_tables.sql` are **clean** — the DB layer and
its own battery describe the invariant correctly. The drift is one-directional, into the app.

**Why four comment lines are worth a flag on this branch specifically.** This is the identical
class as VETO 1 and VETO 2 — prose asserting a control shape the tree does not have — on the same
surface, in the round that fixed it. The direction is safe here: it *understates* the DB control.
But *"mirroring exactly"* invites exactly the future edit that removes a Zod control on the belief
that the DB mirrors it, and `101`'s honest-residual paragraph is the thing that would have
prevented that. **Fix:** restate the canonical-form shape at all four sites, replace *"mirroring
the DB CHECK exactly"* with a pointer to `101`'s stated residual, and drop or re-quote the two
verbatim quotations.

## NOTE 6 — the control-character fence is app-only, and the DDL's residual paragraph does not name it

`101`'s honest-residual paragraph is scoped to **whitespace** (JS `trim()` strips Unicode
whitespace; the CHECK strips the six ASCII kinds). The Zod control-character regex — the
`U+0000`–`U+001F` and `U+007F`–`U+009F` exclusion class — has **no DB counterpart at all**: the
canonical-form CHECK looks only at the ends, so a caller reaching PostgREST directly can store a
label with an interior newline, tab, or ANSI escape. Bounded: an escaped HTML render makes it
inert, and Postgres `text` cannot hold `U+0000` regardless. Worth one sentence in that same
paragraph so a reader meets both asymmetries in one place instead of one.

## NOTE 7 — E30's carry-forward has no durable home yet

You ruled my open VETO 4 question at **E30**: V1.4's §2.5 surfaces are web-only; the
monthly-report renderer is V1.5 and carries the escaping control separately. **I accept that
ruling and withdraw the PDF-worker item for V1.4.** ⚠ But E30 sits on the pending execution-log
batch, and the V1.5 escaping obligation exists **nowhere in the tree**. A carry-forward with no
watcher is how an obligation gets discovered at adoption rather than at design. Route it to
`BACKLOG.md` §7 or the V1.5 Linear issue before this branch closes — a one-line placement, and it
is the whole difference between a ruling and a control.

## Discharged at this tip

- **VETO 3 (i)** — `drop function if exists ...(bigint, smallint, pfin.tax_schedule_type_enum,
  numeric, numeric, jsonb)` at `101:1420`, after the enum block at `:557` and immediately before
  the `create or replace` at `:1423`. ⚠ **The header's placement rationale is correct and
  non-obvious, and getting it wrong would have been worse than the bug:** `DROP FUNCTION IF
  EXISTS` suppresses only *"function does not exist"*, **not type resolution**, so naming the enum
  ahead of its own creation would fail the apply on a fresh database — turning a belt-and-braces
  statement into the thing that breaks every clean apply.
- **VETO 3 (ii)** — the endpoint passes `p_schedule_label`, and its new comment correctly
  identifies that coexisting overloads leave PostgREST an **ambiguous candidate set** rather than
  resolving silently to one.
- **VETO 3 (iii)** — `(RA-SIG1a)` counts by `proname` **with no `pronargs` filter**, so a stale
  6-arg overload is *counted, not excluded* — the failure mode a combined leg would have had.
  `(RA-SIG1b)` then pins that row's `pronargs = 7`. Two legs that can disagree, which is what
  makes the pair a watcher rather than a single assertion.
- **VETO 4, app half** — `z.string()` then `.trim()`, `.min(1)`, `.max(500)`, and the
  control-character `.regex(...)`, inside a retained `.strict()`. The RT-24 string arm covers a
  mid-string tab, C0 (`U+0001`), `U+0000` **with an explicit rationale** for why `z.string()`
  alone would have yielded a 500 rather than a 400, C1 (`U+0085` NEL), and the `<script>` positive
  control. ⚠ **Every rejection leg asserts `writeCalls === 0`**, so the fence is proven to stop
  *before* the write rather than merely to return 400.
- **FLAG 4 — landed stronger than I asked.** I asked for `length(btrim(...))`; what landed
  **refuses** a non-canonical value instead of accepting-and-trimming, so what a user reads back
  is byte-for-byte what was accepted and the 500 bound is measured on the stored bytes.
  `(LBL-CHECK2)` pins that `' x '` is *rejected*, not silently stored as `'x'`; `(LBL-CHECK3)` is
  the non-vacuous control; `(LBL-CHECK1b)` uses a TAB-only label so all six `btrim` kinds are
  exercised rather than the space case standing in for them; `(LBL-CHECK4)/(LBL-CHECK5)` bracket
  500/501 with the accept leg proving 501 fires the **length** conjunct and not the canonical one.
- **FLAG 5 — verified independently, not taken on report.**
  `git show 2173263:supabase/migrations/103_tax_bracket_seed.sql | md5 -q` →
  `ce07e944123f521d1ba79ae584e7497a`, matching the value pinned in the binding line; the same blob
  at `393c7af` hashes identically. The tip the line names is two merges behind, but the **binding
  is the md5, not the tip**, and the line already instructs its reader to recompute rather than
  trust it. Correct as written.
- **FLAG 6** — `grep -ci "mental health"` on the 103 battery → **0**; both sites read *"Behavioral
  Health Services Tax"*.
- **Not asked for, and it closes VETO 3's residual from the other side:** `101:424-446` now states
  **FRESH-APPLY-ONLY** explicitly, spells out that `create table if not exists` would make the
  column a silent no-op on a database already holding the table, and reasons option (A)
  (`add column if not exists`, the repo's own convention in 13 migrations) *down* rather than
  skipping it — because a `NOT NULL` backfill would owe a label story that would be fiction.

## Verify-hook, re-run live at `2173263`

D3, D4's catalogued list and D18 read live again from the ADR body. `schedule_label` remains
**outside** the Decision 3 family (text, references no row, holds no id, not an `INTEGER[]`);
family unchanged. §10 catalogued list unmoved on all three axes — no instance added, removed,
reordered or renumbered, no layer re-attributed, no count carried by any file in this range; the
CATALOGUED and CI-FENCED sets remain different sets and neither is touched. D18 — the label
stores **text, not JSONB**, so the forward-compat fence holds, and the family is still five
tables. **`DECISIONS.md` is unchanged in `393c7af..2173263`.**

## Non-objections at this tip

- **The `<script>` payload being forwarded byte-for-byte is correct and I explicitly do NOT want
  angle-bracket rejection at this layer.** The test asserting both `p_schedule_label === payload`
  and `writeCalls === 1` is the right pair — it pins that the field is prose and that nothing
  silently sanitizes it. Escaping is the render side's job and belongs to SELF-265.
- **I do NOT require widening the CHECK to a Unicode whitespace class.** `101`'s reasoning is
  right: it would put a character-class definition in the constraint that the app's definition
  could still drift from, trading a **stated** residual for an **unstated** one. A named residual
  is worth more than a closed one here.
- **I do NOT require the `.trim()`-first ordering to change**, and the two choices compose in a
  way worth naming: `.trim()` chained first means every later check runs on the value that is
  stored, and refuse-not-normalize at the DB means the endpoint's JSON echo of
  `parsed.data.schedule_label` is byte-identical to the stored row. Neither choice alone would
  give that property.
- **I did not audit `docs/records/v14-execution/self259-sec-review.md`** (+170 in this range) — it
  is a parallel Sec pass on SELF-259, not my artifact and not this issue. I read the commit trail
  rather than the record, and the D-2 / D-4 / D-5 dispositions visible in the tree are consistent
  with everything above.
- Round-1 and round-2 non-objections all still hold; I re-checked the two the diff could have
  moved — both `103` functions remain SECURITY INVOKER with `set search_path = ''`, and the
  SECURITY DEFINER allowlist is untouched.
