# V1.5 re-derived ACs — Architect

**Resolved against [`sitting-log.md`](sitting-log.md) @ `1417337`.** Every ruling-owed marker that stood in the pre-sitting revision is replaced with the ruled text and **cites its sitting-log entry by R-number without restating its reasoning** ([ADR-063](DECISIONS.md#adr-063) Decision 2). None remains anywhere in this file, including in this sentence — the marker string is deliberately not written here, so a mechanical check over the file cannot be tripped by the prose describing the check. Items the sitting did **not** settle are marked **`⟨OPEN⟩`** and named — an `⟨OPEN⟩` is a residual with a stated owner and route, never a ruling this file invented.

**Round 2 (2026-09-04).** Landing-ready replacement AC text, one block per issue, for paste into Linear at the amendment batch. **Each block self-carries its baseline sha.**

**The per-block `b90b846` baselines are unchanged and deliberately kept** — they name the tree each block's measurements were taken against. Measured at resolution time: `git diff --stat b90b846 1417337` over `supabase/ api/ web/ workers/ docs/ scripts/ .github/ DECISIONS.md` touches **only the six `docs/records/v15-preflight/` files**, so every measurement below stands at the resolution sha.

**The ruled dispatch order is NOT re-listed here.** It is [`sitting-log.md`](sitting-log.md) **R13** — the one copy, by that ruling's own terms. Read it from there.

**Ledger discipline, applied throughout (R14 rider 1; Path B).** No Decision 3 tally, no §10 catalogued count, no DEFINER-allowlist size appears in this file, in any block, or in any migration or `comment on` an AC below calls for. The blocks state **which existing label a column realizes** and allocate none. [ADR-011](DECISIONS.md#adr-011) Decisions 3, 4 and 9 are read **live** at authoring.

**Round-2 folds (carried forward).** PM's product wording (`pm-findings.md` §8, read at `origin/meta/v15-preflight-pm` @ `4c9f628`, md5 `06db14a4…`) is folded **verbatim and credited `(PM)`** into the blocks that own each string. The canonical RT labels Sec names at `sec-findings.md` **D-3** (read at `origin/meta/v15-preflight-sec` @ `374ba8e`, md5 `a8e7090d…`) are on the blocks they belong to. The ADR-029 / `025` **aal2** clause is stated on A1, A2 and A8 per Sec **F-9** and the `090` policy standard.

Sibling items are **cited by id, never restated** — read them in their own files. Seam ids (`S-n`) and finding ids (`F-n`) are this pass's Architect ids in `architect-findings.md`; PM ids are `A-n` / `D-n`, Sec ids are `F-n` / `M-n` / `D-n` / `R-n` — **all three files use `F-n` and `D-n` independently, so every citation below names its owner.**

**Link form.** `DECISIONS.md#adr-nnn` is written bare rather than repo-relative throughout, deliberately: these blocks are Linear paste targets, where a repo-relative path resolves to nothing either way, and a single form is greppable.

**Milestone (R8).** A1–A8 and A10 carry the Linear milestone **"V1.5 — Monthly report full (§2.6)"**; project stays **Platform / Cross-cutting**. **A9 stays unmilestoned** in Platform. The milestone is stated per block below and is the liaison's write at the amendment batch.

---

## SELF-345 — A1. `pfin.monthly_report` header table (Lock 11)

> **Baseline.** `b90b846` (2026-09-04). Every identifier below verified against the tree at this sha.
>
> **Milestone: V1.5 — Monthly report full (§2.6)** (R8). Project: Platform / Cross-cutting.
>
> **Source.** [ADR-011 Decision 15 / Lock 11](DECISIONS.md#adr-011) verbatim; [PRD §2.6.1](docs/PRD/index.html#story-2-6-1) header + [§2.6.2](docs/PRD/index.html#story-2-6-2) commentary persistence per Wave 6 Gate B Option C (4 named TEXT columns on the header table; no JSONB commentary blob per the Lock 14 forward-compat fence) — **read §2.6 as amended at the R10 PR**. ⚠ *Source corrected* — the four **sub-section headings** are **Cash / Bonds / Marketable Securities / Alternatives** per PRD §2.6.2 verbatim, F/CTO-ratified 2026-08-19 following ADR-058 Decision 7 (migration `082`).
>
> **⚠ This block is the vehicle for the consolidated ADR (R14) and for the R7 audit helper (block AH below), and it is reviewed as ONE design unit with A2 and A3 under ONE Sec joint-review (R13 step 6).** R1 rider 8 makes that unit's joint review mandatory on its own ground.
>
> **AC.**
> 1. **Table** `pfin.monthly_report`: `users_id UUID NOT NULL` · `target_month DATE NOT NULL` · `generation_status` with the Lock 11 vocabulary `draft` / `final` / `superseded` · `data_as_of DATE NOT NULL` · `generated_at TIMESTAMPTZ` · `owner_header_at_generation TEXT` · `commentary_cash`, `commentary_bonds`, `commentary_marketable_securities`, `commentary_alternatives` (all `TEXT`) · `commentary_disposition` (item 9) · the frozen-payload carrier (item 2) · `created_at` · `updated_at`.
>    - **`commentary_marketable_securities` is the ruled identifier — R11 (a).** The Zod key and the P3 text-area heading follow; the heading text is **Marketable Securities** under every outcome. ⚠ **R11 rider 1: the rename is recorded as a correction to Gate B's ratify text inside the consolidated ADR (R14), never by migration alone.** It does not arrive as a schema fact with no register entry.
>    - `owner_header_at_generation` is **required, not optional** (Arch F-2 · PM D-5 · Sec M-1). It is **NULLable and stays NULL** for a report generated before the user set a header — PM **A-13**, authorized at **R10**, rules that state and its rendering.
>    - ⚠ **Each commentary column carries a CHECK-enforced length bound** (Sec **N-5**), mirrored in P3's Zod schema. Bare `TEXT` here would leave P3's *"length bounds"* battery as a **single-layer app control on a Lock 14 write path**, and ADR-011 Decision 4's user-facing-surface class is explicitly a multi-layer commitment. The consumer is a browser engine rendering a PDF, where unbounded prose is a memory and render-time cost it is not on a scrollable web page. **The number is PM's** — taken as default-and-notify at the sitting (*"commentary CHECK-enforced length bound mirrored in Zod, PM picks the number"*), and it is a product prerequisite for this migration, not a blocker on it. **Catch criterion (Sec):** a body one byte over is rejected 400 at the app layer **and** the same value is rejected by the DB when submitted directly through PostgREST — *"two facts that can disagree, which is what makes it a real second layer."*
> 2. **THE FROZEN RENDERED PAYLOAD — RULED at R1 (A).** A `final` report **stores its rendered values**; it is not recomposed at read time. A3 composes as drafted; its return is written **once, at finalization**, and every later read of a `final` report — in-app view and PDF export alike — reads the stored payload. Option (B) (narrow φ-1 to live-recompute-as-of) and option (C) (hybrid) were not taken.
>    - **DDL call, which R1 delegates to Architect: the payload lands as COLUMNS ON THIS HEADER, not as a payload child.** `rendered_payload JSONB` + `payload_schema_version SMALLINT`. **Reasons:** (i) the item-6 immutability trigger already governs this row whole-row, so the payload inherits the wave's canonical Decision 2 fence with no second surface to fence; (ii) a payload child would be a third table owing its own RLS, grants, immutability trigger **and** an explicit Decision 3 disposition on its parent FK — cost with no queryability gain, since nothing queries *into* the payload (A2 is the queryable index, per R1); (iii) one row, one artifact, one lock. **Losing side, named:** the header row grows large and every `select *` over it carries the payload; readers that only need status/`generated_at` must project columns. Accepted — the alternative buys narrow rows at the price of a fourth fenced surface.
>    - ⚠ **R1's parenthetical sketch says `rendered_payload JSONB NOT NULL`, and that form is not buildable — the ruling's substance is what governs, and it is what is built here.** The cron writes a `draft` row **before** any payload exists (R9 rider 1; A7 item 4), so an unconditional `NOT NULL` would make the cron's own INSERT fail. **Realized as:** the columns are NULLable, with a CHECK enforcing the conditional — `generation_status = 'draft'` permits NULL; `final` and `superseded` require **both** `rendered_payload` and `payload_schema_version` NOT NULL. That is R1's "written once, at finalization" stated as a constraint that can fail. **This is the DDL call R1 assigns, not a re-opening of R1**; it is recorded in the consolidated ADR (R14) so the ruling's sketch and the shipped shape do not read as divergent.
>    - **Frozen IN (R1 rider 1), as rendered at generation:** every `{status, reason}` and `{status, amount}` envelope · `basis_year` · the tax-authority exclusion line's state · the unclassified count · the owner header (`owner_header_at_generation`). **Frozen OUT (R1 rider 2):** §2.6.5 staleness markers — read live at every render and export (P8 item 2; the §2.6.4 carve-out).
>    - **`payload_schema_version` ships with the payload (R1 rider 4).** A §2.x rendering change keeps reading old payloads — the `nav_daily` lesson, [ADR-040](DECISIONS.md#adr-040) / [ADR-067](DECISIONS.md#adr-067) Decision 3. The version is bumped by the renderer, never re-derived from the payload's shape.
>    - **JSONB here does not touch Lock 14's no-JSONB forward-compat fence (R1 rider 5).** That fence governs the **settings store** (`101` precedent); `monthly_report` is a Lock 11 audit-class artifact, not a settings table. Recorded so it is not re-litigated at this issue's review.
>    - **The stored artifact is the rendered VALUES (JSON), never PDF bytes (R1 rider 7).** PDFs are regenerated from the payload on every export and are never persisted (PRD §2.6.4 *"no PDF caching V1"*). ⚠ Sec **M-6**'s standing condition survives verbatim: **the first AC that persists PDF bytes creates a storage-class surface and is joint-review-mandatory at that PR.**
>    - **A frozen payload freezes its defects (R1 rider 6).** The "Regenerate" affordance (P5 item 4) and the pre-finalize no-tax-ledger prompt (P4 item 4) are **load-bearing, not optional**, and are carried in those blocks as such.
> 3. **`included_reconciliation_event_ids INTEGER[]` — RULED at R5 (a): ship the column with its Lock 11 mod #9 fence, DORMANT.** This **realizes [ADR-011 Decision 3](DECISIONS.md#adr-011) label #3** — verified live at the resolution sha as `pfin.monthly_report.included_reconciliation_event_ids INTEGER[]` → `pfin.reconciliation_event`, **P1** matched-tenant array-element BEFORE INSERT/UPDATE trigger, carried **UNREALIZED**. It **allocates no label and renumbers nothing**; the drafted "6th instance" ordinal is struck by citation. Option (b) (retire or re-defer by D3 amendment) not taken.
>    - The migration header states in terms that `pfin.reconciliation_event` has **no writer at this sha**, so the fence is correct, mandatory and **DORMANT**, and names the **revival condition**: the first `reconciliation_event` writer, expected at the V1.6 statement tie-out ([ADR-035](DECISIONS.md#adr-035)).
>    - ⚠ **R5 rider — the paired QA leg is labelled CONSTRUCTION-ONLY in its own text.** It asserts the trigger **exists, is attached to the column, and carries the matched-tenant body**; it does **not** assert firing, because nothing can populate the array in V1.5. *"So no later reader mistakes a leg that cannot fail for coverage."*
>    - ⚠ The instance is the `INTEGER[]` column, **never `users_id`** — a matched-tenant fence on the tenant anchor is *the leg that cannot fail* (`007`/`015`; [ADR-062](DECISIONS.md#adr-062) Decision 2). The DDL states, per column, **which allocated label it realizes and which fence-pattern class (P1 / P2 / CR) it uses** (Sec F-1).
> 4. **Uniqueness — the locked partial index, verbatim:** `UNIQUE (users_id, target_month) WHERE generation_status = 'final'`. Kept verbatim and keeps firing under R4. Sec **D-5**'s catch criterion is the sharp one: **regenerate the same month three times**, not twice — a two-regeneration leg passes against the defective three-column form.
> 5. **Decision 2, both halves, with the reading RATIFIED at R4.** The *immutable* half governs `monthly_report_account_snapshot` (A2) and the frozen payload (read-only post-write); the *INSERT-new-version* half governs this header's regeneration path. ⚠ **`draft → final` promotion is itself an UPDATE, so D2's blanket "UPDATE blocked" was never literally true of this table under its own locked vocabulary.** The consolidated ADR (R14) says so and names where the mutability window closes. **Sec's own named cost stands and is not softened:** D2's blanket append-only claim stops being true of this table, and the ADR must say so. The mitigation is that the exemption is **a monotone transition on one column**, checkable in the trigger and in a battery leg — not a column allowlist.
> 6. **Supersession mechanism — RULED at R4 (B), with Sec's four conditions.** **No SECURITY DEFINER supersession function; the Decision 9 allowlist is untouched by this issue.** The drafted `fn_supersede_monthly_report` is struck. Option (A) (derive `superseded` from ordering) not taken — withdrawn as internally incoherent; option (C) (DEFINER + D9 amendment) not taken.
>    - **The whole-row immutability trigger — the same trigger, not role-conditional — permits:** (i) any column while `generation_status = 'draft'`; (ii) `generation_status` only on the single monotone transition **`final → superseded`**; (iii) **nothing else, ever**. `users_id` and `target_month` are fenced in **every** state (Lock 12's Sec catch: a parent re-tenant orphans A2's children from their original tenant; D3 label #4's own text names this parent-immutability extension as part of that instance).
>    - **(a) DELETE stays blocked** on every non-`draft` row, by the same trigger, with a battery leg. D2 is a **two-verb** rule and clauses (i)–(iii) govern only UPDATE. `authenticated` must hold INSERT for the on-demand path (A10) and **never DELETE** — PRD §2.6.4 commits to indefinite retention, with user-initiated deletion explicitly V2+. ⚠ Sec names the shape: *"enumeration-stops-one-short, applied to a two-verb rule restated with one verb."*
>    - **(b) The trigger is NOT role-conditional.** The same monotone rule binds `authenticated` and `service_role` **identically**, and the battery proves refusal **under both**. ⚠ The realistic later defect is named: the cron performs the `final → superseded` UPDATE under `service_role`, so someone adds an early return for `service_role` to make it work — **and a leg run only as `authenticated` passes with that exemption in place.**
>    - **(c) Legal INSERT STATES are constrained, not only legal transitions.** A transition guard governs UPDATE and is **silent on a row written directly in the target state**: with `authenticated` holding INSERT, a row can be POSTed straight in as `final`, **taking the month's single `final` slot without passing the author-before-generate gate**. The AC states which states a row may be INSERTed in — **`draft` only** — and the trigger enforces it. (A10 rider 1 makes the same statement from the write path's side: A10 writes `draft`, never `final` directly.)
>    - **(d) `superseded` is TERMINAL** — stated in the trigger and in the migration header so the battery has an obvious leg. **Runbook line, required:** this trigger is the **only applicable layer** for an RLS-exempt writer and, per [ADR-011 Decision 4](DECISIONS.md#adr-011)'s 2026-09-03 amendment, **goes inert under `session_replication_role = replica`** — so any bulk-load or restore path touching this table **owes an explicit post-load validation step**. Verified live: that amendment states the applicable-layer count for such a writer goes to zero, not to one.
>    - ⚠ **`service_role` is fenced on THIS table too.** ADR-011 Decision 2 verbatim requires append-only *"across both `authenticated` AND `service_role` roles"*; A2 item 4(iii) carries a `service_role` bypass DB-trigger for the child, and **a child fenced against a role its parent is not is a fence with a door beside it.** `service_role` carries `rolbypassrls`, so on this surface the trigger is its only applicable layer — there is no RLS behind it to catch a miss.
>    - ⚠ `updated_at` + `fn_refresh_updated_at` are **legitimate only within the `draft` window** (PM D-6, ratified at R4). On a final-immutable row the trigger is dead code or a hole; the migration states which.
> 7. **RLS** per the `090` standard: USING **and** WITH CHECK per verb; `users_id = auth.uid()`; explicit grants; **and the [ADR-029](DECISIONS.md#adr-029) / `025` aal2 step-up backstop clause on the `authenticated` read and write policies** (Sec **F-9**; default-and-notify, taken). None of the three documented exclusions applies — in particular **not** the `user_settings` exclusion, which exists only because that table is the clause's own subquery target. **Catch criterion (Sec F-9):** a totp/passkey-enrolled caller presenting a below-aal2 JWT lands on the refusal leg — a **different leg** from the cross-tenant leg; a battery testing only cross-tenant passes with the clause absent.
> 8. **Status vocabulary bridge**, stated once against the transition. Cron writes `draft`; completing **or explicitly skipping** authoring promotes to `final`; regeneration supersedes. **Presentation mapping, authorized at R10 (PM A-8) and worded to hold under R4:** *"pending = draft; generated = the current final; a superseded version is never rendered in V1."* The bridge is recorded in the consolidated ADR (R14) as well as here.
> 9. **A durable authored-vs-skipped fact per report — RULED at R12 rider 1: it is a V1.5 column on this table, and it is frozen into the payload.** `commentary_disposition` distinguishes **authored** from **explicitly skipped**; *"a skip must be distinguishable from four empty strings"*, and four empty strings are a legitimate authored state (P3 item 8). P4 item 5 is the affordance that writes it. **R12 (A) makes it load-bearing beyond V1.5:** a month whose commentary was explicitly skipped does **not** count toward SELF-365's N = 2, so this column is the fact that gate reads. ⚠ **SELF-365's own AC wording is PM's** — re-worded to R12's six-clause definition at the amendment batch; this block owes it the column, not the definition.
> 10. **Sec joint-review mandatory** (R1 rider 8 — A1/A2/A3 as one design unit, one review). **QA:** two-tenant pgTAP battery pairs in the same PR, carrying the aal2 leg as a **separate leg** from the cross-tenant leg, and the R5 construction-only leg labelled as such in its own text.
> 11. **The R7 general audit-log helper ships in this PR** — its full AC is the **AH** block below, and A1's PR is its vehicle (R13 step 6). It is not a separate deliverable of this issue's substance; it is stated here because this is the PR that must carry it.
>
> **Dependencies.** Upstream: SELF-232, SELF-233. Downstream: A2, A3, A7, A10, P2, P3, P5.

---

## SELF-346 — A2. `pfin.monthly_report_account_snapshot` child table (Lock 12)

> **Baseline.** `b90b846`.
>
> **Milestone: V1.5 — Monthly report full (§2.6)** (R8). Project: Platform / Cross-cutting.
>
> **Source.** [ADR-011 Decision 16 / Lock 12](DECISIONS.md#adr-011) verbatim; [PRD §2.6.4](docs/PRD/index.html#story-2-6-4) **as amended at the R10 PR**.
>
> **⚠ Reviewed as one design unit with A1 and A3, under ONE Sec joint-review** (R1 rider 8 · R13 step 6).
>
> **This table's role is settled by R1 (A): the child is the per-account QUERYABLE INDEX over the frozen artifact, not a second copy of it.** The artifact is A1's `rendered_payload`. That rule decides the column set: the child carries what a **query** must answer on — per-account rows the payload cannot be filtered or joined on — and nothing that exists only to be read back whole.
>
> **AC.**
> 1. Child table, FK to `pfin.monthly_report` **ON DELETE RESTRICT** (Lock 12 verbatim — not CASCADE).
> 2. **Columns: Lock 12's locked three — `(monthly_report_id, account_id, acct_name_at_generation)` — plus only what the index rule above admits.** ⚠ **`scope` is DROPPED** (R1 rider 3, and it was already unavailable as a typed column: `pfin.scope` does not exist as a type at this sha; `pfin.account.scope` is `text not null`, a free-text [ADR-004](DECISIONS.md#adr-004) Decision B label). `pfin.account.tax_treatment` **is** real (`003`); if carried it is a **copy of the account's value at generation time, named as such** in the column comment.
>    - ⚠ **Every column beyond Lock 12's locked three is a Lock 12 AMENDMENT, ratified in the consolidated ADR (R14), not an implementation detail** (R1 rider 3 · Arch F-7). The amendment **enumerates** the widened set; this AC does not widen it by writing DDL and calling it detail. The enumeration is authored at this migration and lands in the same PR.
> 3. **Decision 3 — realizes the existing `account_id` label; allocates none.** Verified live at the resolution sha: label #4 is `pfin.monthly_report_account_snapshot.account_id` → `pfin.account`, **P1** matched-tenant trigger **+ parent-immutability extension fencing `monthly_report.users_id` UPDATE post-creation**, carried **UNREALIZED**. Read Decision 3's body live at authoring; **state no count**. The parent-immutability half of that instance is built at **A1 item 6** and verified from this side.
>    - ⚠ **The parent FK needs its own explicit disposition, and R5's consequences make it Architect's to write, not to leave unstated.** This child carries **two** FK-shaped columns and Decision 3's rule is written over *any* of them. Either the parent FK is fenced — and if it is a genuinely new relationship it takes the next canonical label, **allocated AT the migration, never in advance** ([ADR-011 Decision 18](DECISIONS.md#adr-011)'s amendment bars advance drafting) — or it is **argued out with the reasoning recorded in the DDL**. ⚠ **`⟨OPEN⟩` — which of the two, and the reasoning, is authored at this migration and reviewed at the unit's joint review. The sitting ruled the OBLIGATION (R5, consequences), not the answer.**
> 4. **Lock 12's three V1-SHIP-BLOCK mods in full:** matched-tenant trigger on `account_id`; parent `users_id` + `target_month` immutability (lives at A1 item 6, verified from this side); `service_role` bypass DB-trigger on the child — and A1 now carries its equivalent, so the pair is symmetric.
> 5. **RLS via the parent FK chain** (`090` standard; USING + WITH CHECK per verb; **aal2 clause per Sec F-9**). ⚠ The join to the parent keys on the **surrogate `monthly_report_id`**, never on a `(users_id, target_month)` value pair: a surrogate-id join fails **closed** under an RLS regression, a shared-vocabulary join fails **open**.
> 6. Read-only post-write — Decision 2's **immutable** half, which R4 ratifies as the half that governs this table (A1 item 5).
> 7. **Canonical test label: RT-20**, not RT-21 (Sec **D-3**; default-and-notify, taken). ⚠ The drafted *"RT-21 HIGH"* is a false composite — [ADR-011 Decision 16](DECISIONS.md#adr-011) names **RT-20 HIGH** for this surface (fourth-instance FK-bypass + service_role bypass + parent immutability extension); RT-21 is the PDF-worker JWT battery on a different surface. Built as drafted, **the RT-20 battery is never written and nothing notices, because an RT-21 battery will exist and will be green.**
> 8. **SD-12 child sub-class addendum** — the correct home; **not** a new SD class (Sec M-3 and Sec §5 both confirm; PRD §2.6.6 resolves it as a derivative surface).
> 9. **Sec joint-review mandatory** (as part of the A1+A2+A3 unit). **QA:** two-tenant battery same PR.
>
> **Dependencies.** Upstream: A1, SELF-214, SELF-201. Downstream: A3, A7.

---

## SELF-347 — A3. SECURITY INVOKER read-composition helper

> **Baseline.** `b90b846`.
>
> **Milestone: V1.5 — Monthly report full (§2.6)** (R8). Project: Platform / Cross-cutting.
>
> **Source.** [ADR-011 Decision 15 / Lock 11](DECISIONS.md#adr-011) read-composition pattern; Gate A Option B unified — **and Gate A's shape is recorded in the consolidated ADR (R14), not only in a downstream register.** ⚠ *Source note:* Lock 11's own join list names `pfin.nav`, **which does not exist at this sha**; the ruling stands, the identifier is dated — grep the identifiers, not the list. ⚠ The drafted *"SELF-260/261 §2.5.1"* citation is struck — **SELF-261 closed unbuilt**; §2.5.1's readers are `100`/`104` (PM **D-11**).
>
> **⚠ Reviewed as one design unit with A1 and A2, under ONE Sec joint-review** (R1 rider 8 · R13 step 6).
>
> **AC.**
> 1. **Signature: `pfin.fn_render_monthly_report(p_target_month DATE, p_data_as_of DATE) RETURNS JSONB`.** ⚠ **No `p_users_id` parameter — RULED at R3 (i), and it is also the default-and-notify item taken at the sitting.** Tenant identity is `auth.uid()`. PM **D-11** logs the drafted parameter as the 6th recurrence of the §7.19 signature family; Sec **F-4** states the security half: with `p_users_id` present, a bypass-RLS caller makes the *parameter* the only tenant fence, which is ADR-011 Decision 1 clause (c) unacknowledged. Precedent on the tree: `105` (*"p_users_id DROPPED"*) and `101` (*"takes NO tenant parameter"*).
>    - **Under R1 (A) this helper is the COMPOSING form only.** A historical read of a `final` report is a **payload read** off A1, not a call to this function. The third entry path takes **the report row**; it does not re-enter `(month, as_of)`. P2 item 2 and P5 state the same rule from the read side.
> 2. **Tenant binding for every non-JWT caller — RULED at R3 (i), option α: IMPERSONATION.** `SET LOCAL ROLE authenticated` + `set_config('request.jwt.claims', …, true)` per tenant, per transaction, **with the singular `request.jwt.claim.sub` GUC nulled first** — the pattern already shipped as `TenantBoundConnection` at `workers/etl/src/pfin_back_etl/connection.py` (verified present at the resolution sha). A7 **names and reuses that module** rather than re-specifying it. Sec's β (`service_role` + a code-layer parameter) and γ (session-minting) not taken.
>    - **The hazard the ruling closes (Sec F-4):** claims **without** the role leaves `rolbypassrls` in force — `auth.uid()` returns the intended tenant, every RLS predicate is skipped, the composition reads every tenant's rows, **nothing raises**.
>    - Under **R2 (C)** this is the **only** non-JWT path left: the PDF worker no longer reaches the database or this helper at all.
> 3. **ARCH `:208` — RULED at R3 (ii): the clause constrains the SESSION CONTEXT, not the process identity, and it is PDF-scoped.** Verified verbatim at the resolution sha: *"All **reads** flow through a single `SECURITY INVOKER` read-composition helper (**user-session only — never invoked from a worker**), which is also the render source the PDF worker reaches through the V1 web-app's `/internal/pdf-render` endpoint rather than the database directly."*
>    - *"User-session only"* means the helper always executes under a session where **RLS applies** and `auth.uid()` resolves to the tenant whose data is read. The cron satisfies it **by impersonating** — at the database layer that caller **is** a user session. What the sentence forbids is the thing its own second clause is about: a **worker reaching the database directly**, outside any user session.
>    - **Why the general reading cannot be right (recorded at the ruling):** under it **A7 could not exist at all**, and Lock 11 **mod #4 locks a ratified *V1-SHIP-BLOCK cron tenant-binding discipline*** — meaningless if the cron could never invoke the helper it binds a tenant for.
>    - ⚠ **This makes Sec F-4 sharper, not weaker.** If *"user-session only"* is a session-context constraint, **claims-without-role does not satisfy it either** — `rolbypassrls` remains in force and the session is not a user session in the only sense that matters.
>    - **Owed, and it lands on the tree rather than in a records file (R3 (ii), Sec's rider):** ARCH `:208` is **narrowed in the consolidated ADR's doc PR (R14)** to say *"never invoked from a worker's own database connection; a worker composing per tenant does so under an impersonated user session (Lock 11 mod #4)."*
> 4. **Composes the six PRD §2.6.1 sections in verbatim order** — §2.6 **as amended at the R10 PR** — over the live substrate: Account Holdings ← `fn_nav_composition` (`105`); NAV Performance ← the §2.1.2/§2.1.3/§2.1.4 readers; Asset Allocation ← `fn_subcat_market_value` (`076`/`081`) + `planning_target` (`074`); Rebalancing Targets ← A1's commentary columns; Cash Flow ← `fn_cashflow_items` / `fn_cashflow_cross` / `fn_historical_expenditures` (`093`/`096`); Estimated Taxes ← `fn_compute_tax_liability` (`104`).
> 5. **§2.5.4's two NAV-component values render on Account Holdings via the §2.1.5 buildup, NOT as Estimated Taxes rows** (PRD §2.6.1 verbatim).
> 6. **Every envelope and every basis note is carried, never collapsed** — R1 rider 1 makes this the frozen content, so a collapse here is permanent for that month. `{status, amount}` / `{status, reason}` objects cross unflattened, `reason` stays a stable machine code, `basis_year` and `current_year_schedule_empty` travel ([ADR-067](DECISIONS.md#adr-067) Decision 5 — the type does the work, not consumer discipline). No coalesce, no zero-fill, no currency formatting inside this helper. **The `unavailable` case is the bootstrap default, not an edge case.** R10's A-1 / A-2 / A-3 pointer edits make §2.6 say the same thing.
> 7. **ONE CALL, ONE CLOCK.** `p_data_as_of` threads unchanged into every callee; nothing derives its own date; the payload echoes `as_of` back so a consumer can prove the threading (Lock 15; R3 rider 4 of the V1.4 record).
> 8. **Posture, per the `104`/`105` precedent:** `security invoker` · `set search_path = ''` · volatility `stable` **declared in the body per signature** (`CREATE OR REPLACE` resets it) · EXECUTE to `authenticated`, **never to a `rolbypassrls` role**. ⚠ **R3 rider 1 makes the ACL a standing assertion, not a posture note** — for a bypass-RLS caller the EXECUTE grant is the **entire perimeter** rather than the weakest fence. `revoke … from public; grant … to authenticated;` — the `104`/`105` shape; `008` grants no function EXECUTE. P10 item 3 carries the standing leg.
> 9. ⚠ **Known transitive volatility gap, inherited not introduced:** `fn_gl_entries` and `fn_holdings_as_of` are `provolatile = 'v'` at this sha (SELF-326 open). Name it in the header; do not claim a fully-pinned read set.
> 10. **Canonical test labels: RT-19** (read-time composition tenant-scoping, [ADR-011 Decision 15](DECISIONS.md#adr-011)) **and RT-25** (as-of parameter-bypass adversarial input, [Decision 19](DECISIONS.md#adr-011)) — Sec **D-3**; default-and-notify, taken.
> 11. **Render-budget statement (PM §10, routed to Architect).** This helper is the heaviest read on the tree — `fn_nav_composition` **plus** every §2.1–§2.3 reader **plus** `104` in one call. ⚠ **R1 (A) reduces the exposure and does not remove it:** a `final` report is read from the payload, so this composition runs on **generation** (cron and on-demand) and on the **draft** view, not on every historical read. **The latency probe on `fn_compute_tax_liability` runs before this signature is fixed**, and this AC states a render budget the **on-demand generation path** (A10, interactive) meets or names the async shape.
> 12. **Sec joint-review mandatory** (as part of the unit). **QA:** the Sec F-4 catch criterion — a two-tenant fixture where the cron runs for tenant A while tenant B's rows exist, asserting **zero** tenant-B rows in the composed output, ⚠ **with a positive control proving the leg reds when the role assumption is struck** (R3 rider 2 — the leg is vacuous by default on a fresh fixture with no tenant-B rows).
>
> **Dependencies.** Upstream: A1, A2, SELF-262, SELF-268, the Wave 1–5 substrate. Downstream: P2, P5, P6, A7, A10.

---

## AH — the general audit-log helper (R7). Ships inside the A1+A2+A3 unit's PR; no Linear issue of its own

> **Baseline.** `b90b846`.
>
> **⚠ RULED at R7, option (2): A7's [ADR-011 Decision 1](DECISIONS.md#adr-011) clause (d) obligation is discharged by AUTHORING the general audit-log helper that [ADR-011 Decision 9](DECISIONS.md#adr-011)'s amendment records as reserved-unauthored**, and A7 writes through it. Option (1) (widen `linked_source_sync_audit`'s `source` and `provider` CHECKs) not taken — it changes the domain of a shipped append-only audit-class table from *"sync"* to *"any privileged write"*, a Decision 2 change reached for convenience. Option (3) (a report-scoped audit table) not taken — a fourth audit surface with one consumer.
>
> **Why this is a block and not an issue.** R13 step 6 places the helper *"drafted inside"* the A1+A2+A3 unit, and R7's consequences put it on the critical path **behind** that unit rather than beside it. It therefore has no milestone and no id of its own; **A1's PR is its vehicle** (A1 item 11). ⚠ **`⟨OPEN⟩` — no ruling names a Linear home for it.** It travels into Linear appended to **SELF-345**'s description, which is the issue whose PR carries it; if F/CTO prefers a distinct issue, that is a create-and-relabel at the amendment batch, not a re-design.
>
> **What was measured (Sec N-2, PM D-8), re-verified at the resolution sha:** `pfin.plaid_sync_audit` is created at `007:456` and **dropped at `015:174`** — it is not a live table. Its successor `pfin.linked_source_sync_audit` (`015`) carries `users_id` commented *"resolved tenant (Decision 1 clause (d))"* but **rejects a report-generation row** on `source in ('webhook', 'scheduled_poll')` and on a provider list with no internal/report member. `git grep -lE "emit_audit_log|fn_audit_log"` over `supabase/migrations/` returns **nothing**. `linked_source_sync_audit` is **untouched** by this work.
>
> **AC.**
> 1. **A general same-transaction audit-log surface and its insert helper are authored**, and A7 and A10 write through it. The row is written **in the same transaction as the privileged write it describes** — a row that survives a rolled-back generation is worse than no row.
> 2. **Posture: INVOKER-first (R7 rider 1).** Architect drafts it `security invoker`, executed under the writer's own `service_role` context (Decision 1 clause (b): privileged writes execute under `service_role`), `set search_path = ''`, EXECUTE granted explicitly and never to `public`. **The migration header states which posture it takes and why**, in terms.
>    - ⚠ **If and only if it needs DEFINER, the [ADR-011 Decision 9](DECISIONS.md#adr-011) amendment rides the SAME PR** (R7 rider 1; Sec R2.3 R-1 addition) — **never a later reconciliation.** Read the allowlist **live** at authoring: the general audit-log insert helper is recorded there as a **committed-and-reserved, unauthored** slot, so a DEFINER authoring **realizes** that reserved entry rather than growing the allowlist. **State no size.**
>    - ⚠ **`⟨OPEN⟩` — if the helper lands INVOKER, the reserved DEFINER slot's disposition is not ruled.** It would then be a committed allowlist entry with no consumer and no author. Routed to **Sec joint-review at this PR**, with the D9 amendment (whichever direction) riding it. Do not resolve it silently by leaving the slot as-is.
> 3. **Row shape — at minimum (R7 rider 2):** trigger source (`cron` / `on_demand`) · resolved `users_id` · the **tenant-resolution chain** · `data_as_of` · the report row it produced. These are the fields PM §6 needs for V1.final's *"month of operation"* measurability — **R12 clause (2)** reads exactly this row (trigger = cron, `data_as_of` = last day of M) — and that [Decision 19](DECISIONS.md#adr-011) extends with `data_as_of`.
> 4. **Append-only under Decision 2, under BOTH roles (R7 rider 3).** It is **aal2-clause-exempt only because no `authenticated` policy reads it** — **stated in the migration header, not assumed.** The moment an `authenticated` read policy is added, the exemption ends.
> 5. **The surface name is a REQUIRED argument, CHECK-constrained against an enumerated list that grows only by migration (R7 rider 5).** Sec's losing side is recorded and this is its mitigation: *a general helper is where per-surface discipline goes to be forgotten.* A caller that omits or invents a surface name fails; it does not write an unattributed row.
> 6. **Two callers at V1.5, not one (R7 rider 4):** A7 (cron) and A10 (on-demand). Both write the same shape, discriminated only by trigger source.
> 7. **Sec joint-review mandatory** — a new audit-class surface, a Decision 1 clause (d) discharge, and a possible Decision 9 event. **QA:** legs at **P10** — the row exists in the same transaction, names the resolved tenant, and is **absent when the generation transaction rolls back** (R7's restored catch criterion).
> 8. **Consequence recorded, not discharged here:** [`BACKLOG.md`](BACKLOG.md) §7.6 **S7** is the standing tracker for the D1(d) deferral this helper's absence created on the W-1 NAV worker. Authoring the helper makes S7 dischargeable; **whether S7's own worker is retrofitted in this PR is not ruled and is not this wave's** — team-lead's to book. ⚠ Stated so the helper is not later read as having closed S7 by existing.
>
> **Dependencies.** Upstream: none blocking (it is substrate). Downstream: A7 item 5, A10, P10.

---

## SELF-348 — A4. Node PDF worker container (extend, not scaffold)

> **Baseline.** `b90b846`.
>
> **Milestone: V1.5 — Monthly report full (§2.6)** (R8). Project: Platform / Cross-cutting.
>
> **Source.** [ADR-011 Decision 17 / Lock 13](DECISIONS.md#adr-011) **as amended at R14** (direction; see item 0); Gate C V1.x Platform scope.
>
> **⚠ NOT GREENFIELD.** `workers/pdf-render/Dockerfile` + `.env.example` exist (landed `eada4b2`) as a deliberate placeholder *"shipped so the RT-22 fence has a real target to audit"*; the `.husky` hadolint hook and the `workers/CLAUDE.md` row are on the tree (PM §2 A4; Sec **D-2** independently). **This issue EXTENDS that file** — the word is *extend*, never *scaffold* (default-and-notify, taken; R6 consequences) — and every commit to it is already gated by the live RT-22 fence.
>
> **AC.**
> 0. **Direction — RULED at R2 (C). The app pushes FINISHED HTML; the worker returns PDF bytes.** The app composes the report under the user's own live session, renders it through the **same Svelte template the in-app view uses**, escapes every free-text field there, and pushes finished HTML to this worker; the worker runs it through headless Chrome and returns bytes. **The worker holds no DB access, no template, no tenant or money knowledge — "a PDF printer, nothing else."** Option (A) (worker pulls rendered HTML from the app under a machine JWT, per ARCH §3.2 as written) not taken — it forces the app to render a page for a user identity with no session. Option (B) (JSON push, worker composes HTML) not taken — dominated. **The Lock 13 direction amendment and ARCH §3.2's sequence diagram ride the consolidated ADR's PR (R14 rider 2).**
> 1. Extend the existing Dockerfile with Puppeteer + system Chromium deps. **Do not restructure the `ENV`/`ARG` block** — the shipped fence's criterion (i) keys on `^\s*(ENV|ARG)\s+SUPABASE_`.
> 2. **Zero-DB-isolation, unchanged (Lock 13 mod #2): no `SUPABASE_*` env vars at all** — ⚠ *there is no `SUPABASE_URL` carve-out* (Sec **D-1**, a **veto**, carried into R6 rider 3). Single permitted variable: `PDF_WORKER_SIGNING_KEY` per SD-20. No Postgres client. **Under R2 (C) this fence stops being a constraint the worker must respect and becomes a description of what it is** — it has nothing to say to a database.
> 3. ⚠ **The dependency manifest is the live gap** (Sec **F-6**): the moment this issue lands a real Puppeteer app, the standard shape is `COPY package*.json .` then `RUN npm ci`, and the shipped RT-22 fence **documents manifest inspection as a deliberate non-catch** — verified verbatim in its own header at the resolution sha: *"COPY of package.json / requirements.txt manifests (install intent revealed at RUN time, not COPY time; manifest inspection is human-second-line)."* So `pg` can enter through a path the fence cannot see while the fence reports clean.
>    - **The sequencing constraint is WITHDRAWN and REPLACED by a fence shape — RULED at R6 rider 2.** The re-scoped RT-22 fence (A6) **audits `package.json` if present and passes if absent**, so it lands at any time, no-ops until this issue creates the file, and **bites on this issue's first commit**. **The ordering requirement disappears rather than being remembered** — *"a sequencing constraint stated in an AC is a convention with no mechanism, and conventions with no mechanism rot silently."* If for any reason that shape is not adopted, the ordering becomes a **blocking dependency edge in Linear**, never a sentence in an AC.
> 4. Lock 13 mod #7 browser hardening: browser-context-per-render, system-fonts-only, `--disable-features=BackgroundFetch,ServiceWorker,BackgroundSync`, cache disabled, per-render PDF metadata cleared.
> 4b. **RESOURCE-LOADING FENCE — REQUIRED, and it is an ADDITION to Lock 13 mod #7's list, not an inheritance from it** (Sec **R2.2 condition 1**, adopted with **R2**). Under (C) the worker renders **network-supplied HTML** in a browser engine, and `<iframe src="file:///proc/self/environ">` returned inside the PDF **exfiltrates `PDF_WORKER_SIGNING_KEY` — this container's only secret, therefore its entire compromise.** Render via `page.setContent()` **plus request interception that aborts every request whose scheme is not `data:`** — no `file:`, no `http`, no `https`.
>    - **Catch criterion (Sec, adopted at the ruling):** POST HTML containing `<iframe src="file:///proc/self/environ">` and `<img src="http://169.254.169.254/">`; assert the returned PDF contains **neither the signing key nor any fetched content**, **AND** assert the **interception handler recorded two aborts**. ⚠ Asserting only *"the PDF looks fine"* is **vacuous — a failed fetch and a blocked fetch render identically.** Both legs live at P10.
>    - ⚠ The round-1 conditional (*"not required under Option A"*) is **struck**: (C) is ruled, the fence is unconditional, and the AC is written under that outcome.
> 4c. **Compose manifest + RT-27 private-bind wiring — REQUIRED** (Sec **N-4**, adopted with **R2** as condition 2). `scripts/ci/fence-admission-private-bind.sh` finds its target by an **in-file sentinel** in a Coolify Compose manifest — verified at the resolution sha: the script takes the compose path as an argument and **exits 2 when the sentinel is absent**, *"proving it is the intended admission manifest."* `workers/pdf-render/` has **no such manifest**, so under (C) this container's admission endpoint would come up with **no private-bind fence over it**. Ship a manifest carrying the sentinel and wire the RT-27 job to it — *"a wiring change, not a new fence"*, since the script is already generic over its target. **Owner: DevOps; joint-review-mandatory** (a CI fence-boundary change is a standing escalation trigger); ships with a **golden fixture that fails closed**.
>    - ⚠ **This is an INTRA-instance coverage expansion of RT-27 on the CI-fenced side only. NO catalogued-ledger effect; NO new §10 instance may be drafted; NO ledger edit is owed.** Precedent cited rather than re-argued — **by pointer, not by quotation: SECURITY §4.5's RT-30 entry**, which dispositions an intra-instance expansion of an already-catalogued surface as leaving the ledger untouched. ⚠ **Do not restore the quoted form the pre-sitting draft carried.** Measured at the resolution sha: that quotation was a **false composite** — its two halves come from two different sites (the RT-30 row and an HTML comment), the bracketing and wording differ from both, and the second half is a **truncated quote that drops the figure its source carries**. Path B: the pointer carries it, and no figure travels. Stated at all because catalogueing this channel *"would look like diligence"* (Sec). ⚠ **The §10 catalogued set and the CI-fenced set are different sets and are never reconciled.**
> 5. **Escaping of user-controlled free text — the CONTROL is discharged structurally here and the PROOF LEG is NOT this issue's** (R2 consequences, on §7.32 item 6). Under (C) **this worker composes nothing**: the app renders through the shared Svelte template and **Svelte's default escaping is the control**. This AC therefore carries a **negative assertion** — the worker constructs no HTML, interpolates no field, and has no template — and nothing else. **The proof leg's home is P6** (PM 12.3 · Sec R2.9 · Architect §9.5, all three): a stored `<script>` in commentary, the owner string and `schedule_label` render **inert** in the PDF, spanning both engines under INV-2. Sec **R-5** is resolved by that split — PM's "home it on A4" and Sec's "fold it into P6" were both partly right and neither unconditionally so; the ruling separates the control from its proof.
> 6. **`fence-tbc-node.sh`'s exclusion of `workers/pdf-render/` rests on the zero-DB-reach premise, and A6's manifest fence is what keeps that premise a CONTROL rather than an assumption** (R6 consequences). No `TenantBoundConnection` fence applies here — that fence is the Python ETL's — but this issue is the one that could falsify the exclusion, and without A6 nothing would notice.
> 7. Deploys per the V1 greenfield posture ([ADR-021](DECISIONS.md#adr-021)); Coolify→Discord on deploy. ⚠ **cax21 is reference-only, NOT the deploy target** — the drafted *"deploys on cax21"* is struck (PM **D-9**; default-and-notify, taken).
> 8. **Sec joint-review mandatory** — two independent triggers: the resource-loading fence (4b) and the CI fence-boundary change (4c).
>
> **Dependencies.** Upstream: A6's manifest fence per item 3 (**no ordering edge required** under R6 rider 2's pass-if-absent shape). Downstream: A5, P6.

---

## SELF-349 — A5. The app→worker render call + the RT-21 battery

> **Baseline.** `b90b846`. **This surface is genuinely unbuilt** and Sec D-2 confirms that half of the wave is correctly scoped.
>
> **Milestone: V1.5 — Monthly report full (§2.6)** (R8). Project: Platform / Cross-cutting.
>
> **Source.** [ADR-011 Decision 17 / Lock 13](DECISIONS.md#adr-011) **as amended at R14**; [ARCH §3.2](docs/ARCH/index.html) **as amended in the same PR**; SECURITY §4.5 **RT-21** (rewritten in that PR) + **SD-20**.
>
> **AC.**
> 1. **Direction — RULED at R2 (C), and this issue's SHAPE CHANGES because of it.** ARCH §3.2 as written has the worker minting a JWT and issuing `GET /internal/pdf-render` against the app, which returns rendered HTML. **Under (C) that inverts:** the **app** signs a short-lived token and **POSTs finished HTML to the worker's render endpoint**; the worker verifies, renders, and returns PDF bytes. **`/internal/pdf-render` as an app route is retired** — there is no inbound render endpoint on the app under (C).
>    - ⚠ **Measured, and it is why this re-derivation is not merely bookkeeping: SD-20 and ARCH §3.2 CONTRADICT EACH OTHER on the tree today, and R2 (C) resolves in SD-20's favour.** SD-20 verbatim at the resolution sha: *"V1 app signs short-lived (60s freshness) JWT containing users_id claim ONLY … PDF worker verifies signature + freshness + nonce."* ARCH §3.2 verbatim: *"The PDF worker mints a custom JWT signed with `PDF_WORKER_SIGNING_KEY`"* and its sequence diagram has the worker issuing the `GET /internal/pdf-render` call to the app. Both are ratified; they cannot both be right. **SD-20 already describes the ruled direction and needs no change; ARCH §3.2 and RT-21 do.** Recorded here so the R14 doc PR amends the two that are wrong and does not "reconcile" the one that is right.
> 2. **The JWT's PURPOSE changes** (R2 consequences, verbatim): from *"prove who is asking"* to **"prove the caller is our app."** Every letter below is re-derived against that.
> 3. **RT-21's canonical (a)–(g) RE-DERIVED under R2 (C).** The letters are kept so the battery keeps pointing at the catalog; each states what survives, what moves, and what converts. RT-21's body is rewritten in the R14 PR to match, under Sec joint-review.
>    - **(a) Tier restriction → key restriction.** The clause was written over a *worker-presented* Supabase-tier token, and *"authenticated-tier only; `service_role` JWT rejected at signature verification"* has no referent when the app mints the token. **What survives is the signature-verification half**, which is (b)'s: only the dedicated key's signatures are accepted, so a `service_role` Supabase JWT is rejected **because it is not signed with the PDF-worker key** — not because of a tier claim. The leg is kept and re-labelled; it must not be deleted, because deleting it removes the assertion that a Supabase-issued token cannot drive a render.
>    - **(b) Dedicated signing key — SURVIVES verbatim and STRENGTHENS.** The worker accepts only `PDF_WORKER_SIGNING_KEY` signatures and rejects Supabase-JWT-signed tokens. Under (C) this is the whole of the worker's admission control.
>    - **(c) 60-second freshness window — SURVIVES verbatim; the verifier moves to the worker.** ⚠ A leg asserting `exp` rather than a 60-second `iat` window is a red whose message names the wrong defect, and the tempting repair is to loosen the window.
>    - **(d) Nonce replay protection — SURVIVES; the nonce store moves into the worker.** ⚠ The store is now **per-worker-container** rather than per-app; the AC states where it lives and what happens on worker restart (a cleared store admits a replay inside the 60-second window — bounded, stated, not discovered).
>    - **(e) No `service_role` escalation — CONVERTS from a behavioural assertion to a STRUCTURAL one.** Under (C) the worker holds no Supabase credential and no DB reach, so escalation is impossible **by construction** — and RT-22 (A4 item 2) is the fence that keeps it so. The leg becomes the negative assertion that the worker has no such credential, which is A4's fence, asserted here.
>    - **(f) Dedicated endpoint — the REFERENT MOVES.** Verification logic lives at the **worker's render endpoint only**, not at an app route; **`/internal/pdf-render` is retired as an app path**. ⚠ The round-1 correction (*"the drafted `/api/internal/pdf-render` is not cosmetic; (f) is written over `/internal/pdf-render`"*) is **superseded by the direction change** and must not be carried forward — carrying it would pin the battery to a path that no longer exists. The AC names the worker endpoint; RT-21's (f) is rewritten to it in the R14 PR.
>    - **(g) Rejected payloads dropped with a detection signal — SURVIVES, moves to the worker, and its known-defective inheritance is STILL ROUTED TO SEC AT BUILD** (R2 consequences, explicit). [ADR-050](DECISIONS.md#adr-050) F3 records (g) as inheriting RT-05's defect **unbuilt**; RT-21's own body states its answer *"may legitimately differ"* and marks it Sec joint-review-mandatory at the build. It also names `pfin.plaid_sync_audit` as the storage surface — **dropped at `015`, re-verified at the resolution sha.** ⚠ **(g) gets its own design call, and the attacker model moved with the direction**: the rejecting party is now the worker, not the app, so ADR-050 Decision 4's criterion is evaluated **at the worker** under the private-container-network threat model. **Do not reason from RT-05's resemblance.**
>    - **A5's inventions — tenant-claim presence, audience check, issuer check — are wanted and are KEPT, labelled as ADDITIONS**, so the canonical letters keep pointing at the catalog (Sec F-3; default-and-notify, taken).
> 4. **Under (C) the "server derives the payload; it does not trust one" problem is DISSOLVED, not mitigated** (Sec **F-5**). The app composes under the user's own session and pushes what it rendered; there is no caller-supplied payload for a render JWT to launder. ⚠ **The dual obligation lands on the worker instead and is stated:** the worker renders exactly the bytes it was given and **derives nothing** — no fetching, no templating, no substitution (A4 item 4b is the fence that makes that true).
> 5. **Tenant binding — RULED at R3 (i), and under (C) this endpoint has NO tenant binding to do.** The composition happens app-side under the user's live session before anything is pushed. ⚠ The drafted *"Arch-locked binding per RT-21(e)"* is **struck as a false composite** — RT-21(e) is the no-escalation clause and names no mechanism (R3 consequences). The impersonation pattern R3 ruled applies to **A7**, not here.
> 6. **The token carries a `users_id` claim only — no `data_as_of` claim** (SD-20 verbatim; Lock 15 mod #7b). ⚠ **`⟨OPEN⟩` — R2 (C) says the worker holds "no tenant or money knowledge", and a `users_id` claim gives it one.** SD-20 is ratified and already written for this direction, so the claim is **kept as ratified** and the question — whether under (C) it should be replaced by an opaque correlation id, since the worker has no use for a tenant — is **routed to Sec at this issue's build**, alongside (g). The sitting ruled the direction; it did not rule the token's claim set. Do not resolve this by editing SD-20 without that review.
> 7. This surface is inside RT-26's audit scope and **holds no allowlist entry**. ⚠ Under (C) the app-side caller is a **§4.1 server-source surface** and the endpoint being verified is the worker's — the AC states both sides so the audit scope is unambiguous after the direction flip. **Canonical test labels: RT-21** (this battery) **+ RT-25** (the `p_data_as_of` parameter-bypass axis, Sec D-3; default-and-notify, taken).
> 8. **Sec joint-review mandatory.** **QA:** the seven re-derived canonical legs plus the labelled additions, **each failing for its own reason**.
>
> **Dependencies.** Upstream: A4, A3 (the app-side compose). Downstream: P6.

---

## SELF-350 — A6. RT-22 — **RE-SCOPED IN PLACE to the dependency-manifest fence**

> **Baseline.** `b90b846`.
>
> **Milestone: V1.5 — Monthly report full (§2.6)** (R8). Project: Platform / Cross-cutting. **Title, id, dependency edges and the `sec-joint-review` label are all KEPT** (R6).
>
> **⚠ First sentence, deliberately: the fence this issue was written to build already exists and has since Phase 5 Step 4 W1. This issue is re-scoped, in place, to the gap that fence cannot see.**
>
> **Disposition — RULED at R6, option (ii): re-scope in place.** Option (i) (close and open a successor) not taken. Round 1 measured that the fence is *implemented* and concluded nothing remained; Sec **F-6** measured the fence's *reach against what A4 will actually do* and found live successor work. Re-scoping keeps the RT-22 work under one id and keeps A4's dependency edge valid. **Sec's named losing side stands** — the issue's title and history then describe work already done, which is why this AC says so in its first sentence.
>
> **Already discharged on the tree (no further work):** `scripts/ci/fence-rt22-pdf-worker-dockerfile.sh` (fail-closed; exit 1 on violation, exit 2 on unreadable target) + the `security-scan.yml` job running it **production-mode** against `workers/pdf-render/Dockerfile` and **inversion-mode** against `tests/fixtures/ci/rt22-violation.Dockerfile`, failing the build if the fence reports clean on the fixture. Run-always, not path-triggered. Documented at `scripts/ci/README.md`.
>
> **Two drafted clauses are struck and must NOT be implemented (R6 rider 3):**
> 1. ⚠ **Sec D-1 is a VETO on the `SUPABASE_*` carve-out, adopted at the ruling.** Lock 13 mod #2 verbatim is *"no `SUPABASE_*` env vars"* with **no exception**, and the shipped fence implements it without exception. A PR implementing the drafted AC would **loosen a fence that is live, run-always and fail-closed today.** ⚠ The same defective text sits in `BACKLOG.md` §7.1 — **the defect is in the promotion source, not a Linear transcription** — and that fix lands in the close-out PR, not here.
> 2. ⚠ **The *"both catalogued instances"* parenthetical is struck and replaced by NOTHING.** It is a ledger-figure claim; [ADR-011 Decision 4](DECISIONS.md#adr-011) is read live. **Path B — let the link carry it. Do not restore a number.** ⚠ **Neither correction is ever inherited by a future edit of the fence** (R6 rider 3, explicit).
> - Also absent from the drafted AC and present in the shipped job: the **inversion-mode golden fixture** step. ⚠ **It is preserved verbatim through the re-scope (R6 rider 4)** — removing it makes every green run uninformative.
>
> **New AC — the RT-22 dependency-manifest fence.**
> 1. Extend RT-22's catch criteria to `workers/pdf-render/package.json` **and its lockfile**, rejecting Postgres-client packages — `pg`, `postgres`, `node-postgres`, `@supabase/supabase-js`, and `knex`/`sequelize`-class packages that bundle a driver.
> 2. **Paired with a golden violation fixture and an inversion-mode step, exactly as the Dockerfile fence is paired today.** *A fence that does not fail closed is theatre* (Sec F-6); the existing job is the pattern to copy. ⚠ **The catch criterion and its fixture come to Sec BEFORE merge** (R6, explicit) — a fence-boundary change is joint-review-mandatory and an escalation trigger regardless of who proposes it.
> 2b. ⚠ **FENCE SHAPE — RULED at R6 rider 2: audit `workers/pdf-render/package.json` IF PRESENT, PASS IF ABSENT.** This **replaces** the A4 sequencing constraint rather than supplementing it: *"a sequencing constraint stated in an AC is a convention with no mechanism, and conventions with no mechanism rot silently."* Under this shape the fence **lands at any time, no-ops until A4 creates the file, and bites on A4's first commit** — the ordering requirement **disappears rather than being remembered**. ⚠ **This deliberately DIFFERS from the shipped RT-22 Dockerfile fence, which exits 2 on a missing target**; that is correct there because its target already exists, and **copying it here would red CI from the day it lands.** If the pass-if-absent shape is not adopted, the ordering becomes a **blocking dependency edge in Linear**, never a sentence in an AC.
> 2c. ⚠ **The successor AC CITES the shipped fence's own header (R6 rider 1).** The reason this gap exists is documented *inside* `scripts/ci/fence-rt22-pdf-worker-dockerfile.sh`, verbatim at the resolution sha: *"COPY of package.json / requirements.txt manifests (install intent revealed at RUN time, not COPY time; manifest inspection is human-second-line)."* **Without that citation a future reader finds a fence that already says it does not do this and closes this issue as redundant.** The AC's first sentence (above) and this citation are the two halves of that protection.
> 3. The base-image transitive residual stays **human PR-review second line** per `scripts/ci/README.md` and ARCH §6.1 — unchanged, and stated so the extension is not read as closing it.
> 4. **Ledger effect: NONE (R6, explicit).** RT-22 was catalogued in 2026-05; **building or extending its fence adds, removes, reorders and renumbers nothing in [ADR-011 Decision 4](DECISIONS.md#adr-011).** ⚠ **The CI-fenced set and the §10 catalogued set are different sets and are not reconciled** — RT-22's membership in both is coincidence, not identity (Sec D-2).
> 5. **Owner: DevOps (fence) + QA (fixture).** Sec joint-review retained — the `sec-joint-review` label stays valid under the re-scope.
>
> **Dependencies.** Downstream: **A4 — item 3 of that block.** **No ordering edge is required** under item 2b's ruled shape.

---

## SELF-351 — A7. monthly_report cron worker

> **Baseline.** `b90b846`.
>
> **Milestone: V1.5 — Monthly report full (§2.6)** (R8). Project: Platform / Cross-cutting.
>
> **Source.** [ADR-011 Decision 15 + Decision 17](DECISIONS.md#adr-011); **Gate F Option α native Coolify cron container — recorded in the consolidated ADR (R14) as a MECHANISM RIDER on Lock 13, which locks location, not mechanism.**
>
> **AC.**
> 1. Native Coolify cron container, **1st of each month, generating the prior month's report**; `p_data_as_of` = last day of the prior month, **server-derived** (Lock 15 server-derived-only fence for §2.6 paths; **RT-25** per Sec D-3).
> 2. **Tenant binding — RULED at R3 (i), option α: IMPERSONATION, reusing the shipped module. Do not re-specify it.** `workers/etl/src/pfin_back_etl/connection.py` (`TenantBoundConnection`: READ as `authenticated` via `SET LOCAL ROLE` + `set_config('request.jwt.claims', …, true)`; WRITE as `service_role` via `SET LOCAL ROLE`) and the per-tenant loop in `nav_backfill.py`. `service_role` for **tenant enumeration only** (Lock 11 mod #4). Verified present at the resolution sha.
>    - ⚠ **The role half is non-negotiable (Sec F-4):** claims without the role leaves `rolbypassrls` in force and the composition reads every tenant, silently, with nothing raising.
>    - **`RESET ROLE` discipline between tenants on a pooled connection, WITH A TEST (R3 rider 3** — Sec's named losing side of α, adopted). A leaked `SET` across tenants is its own leak.
>    - ⚠ **R3 rider 4, recorded and NOT resolved at the sitting:** α puts a **role-assumable identity on the cron host**, which `055`'s deliberately non-owner ETL identity exists to keep small. **This issue's Sec joint-review carries that expansion** — it is named here so the reviewer is not discovering it.
> 3. **ARCH `:208` — RULED at R3 (ii).** The clause constrains the **session context**, not the process identity, and is **PDF-scoped**; this cron satisfies it **by impersonating**. The reading is stated in full at **A3 item 3** and is deliberately not restated here — one copy. Lock 11 mod #4's V1-SHIP-BLOCK cron tenant-binding discipline is what it binds. ⚠ **The sentence is narrowed on the tree in the R14 doc PR**, so the next reader does not hit this.
> 4. ⚠ **Inherit the singular-GUC hazard handling.** `auth.uid()` prefers `request.jwt.claim.sub` over the plural blob, so a session-scoped singular GUC left set serves **one tenant's data for every tenant, with no code bug and no app-layer assertion failure** (`054`; `connection.py` nulls it).
> 5. **Cron does not finalize and does not skip.** PRD §2.6.3 **as amended at the R10 PR**: cron fire moves the month to **pending** and surfaces it through *"an in-app notification + pending-monthly-report queue affordance"*; **cron never auto-finalizes**. Coolify→Discord stays the **operator** channel for run success/failure (PM A-14, authorized at R10), never the user's authoring notice. The row written is `draft`, and it is **the same INSERT shape A10 writes** (R9 rider 1).
> 6. **The Decision 1 clause (d) audit row — RULED at R7, option (2): it is written through the general audit helper, whose AC is block AH above.** The drafted *"Lock 13 mod #4 audit-log entry"* is struck: `pfin.plaid_sync_audit` was dropped at `015` and its successor `pfin.linked_source_sync_audit` **cannot take a report-generation row** (`source in ('webhook', 'scheduled_poll')`; a provider list with no internal/report member). Options (a) (widen those two CHECKs) and (c) (a report-scoped table) not taken. **`linked_source_sync_audit` is untouched.**
>    - **Catch criterion, RESTORED now that the home is named (R7 consequences):** assert the same-transaction audit row **exists**, **names the resolved tenant**, and is **absent when the generation transaction rolls back**. ⚠ Sec's round-1 criterion had been withdrawn as untestable against a surface that did not exist; it is testable now and is carried at **P10**.
>    - The row carries the **trigger source** (`cron`), the resolved `users_id`, the resolution chain, `data_as_of`, and the report row it produced (AH item 3). ⚠ **R12 clause (2) reads exactly this row** — a month counts toward V1.final's N = 2 only if evidenced by it — so this is V1.5 work, not a V1.final concern.
>    - **A7 is no longer RED; it sits on the critical path BEHIND the helper**, which is why the helper is drafted inside the A1+A2+A3 unit's PR (R13 step 6) and this issue is dispatched after it.
> 7. **Ruled per-tenant wording** (PM **A-7**, authorized at R10): *"One scheduled run generates per tenant under tenant binding (ADR-011 Decision 1); there is no per-user job, and no cross-tenant data path inside the run."*
> 8. ⚠ **cax21 struck** — the V1 Coolify target per [ADR-021](DECISIONS.md#adr-021) (PM **D-9**; default-and-notify, taken).
> 9. ⚠ **UTC-pin residual, recorded not discharged.** If `data_as_of` derives from the UTC-pinned clock (`061`/`070`), a Pacific user's month-end is UTC's, ~7 hours early. **Not a §2.6 defect and not measured here** (this worker is unbuilt); recorded so the **still-unnamed owner** of `BACKLOG.md` §7.32 item 3 sees a second consumer (default-and-notify, taken — *"the A7 UTC year-boundary second consumer recorded (owner unnamed)"*).
> 10. **Sec joint-review mandatory.**
>
> **Dependencies.** Upstream: A3, block **AH** (the audit helper), the `workers/etl` incumbent. Downstream: P2, P5, P4.

---

## SELF-352 — A8. `pfin.owner_identification` settings table

> **Baseline.** `b90b846`. **Nearest to buildable in the A-lane; unblocked. FIRST DISPATCH, with P7** (R13 step 1).
>
> **Milestone: V1.5 — Monthly report full (§2.6)** (R8 — ruled PM's way: P7 is in the milestone and V1-SHIP-BLOCK and cannot ship without A8, and A1's `owner_header_at_generation` is written from A8's row, so A8 is §2.6 substrate **on product trace**. Architect's ground — Lock 14 family span — is recorded as the losing side). Project: Platform / Cross-cutting.
>
> **Source.** [ADR-011 Decision 18 / Lock 14](DECISIONS.md#adr-011) **as amended 2026-08-16 — the family is FIVE per-domain tables**, and this is the last unbuilt member. ⚠ *Source corrected:* the drafted line quoted the locked *"four per-domain tables"* while the AC built against five; that amendment names **this very entry** as the measurement that made the divergence visible. [ADR-013](DECISIONS.md#adr-013) Decision 7 — Settings 4th-of-four occupant.
>
> **Measured:** `planning_target` (`074`), `cashflow_target` (`090`), `tax_bracket_schedule` + `tax_bracket_row` (`101`) exist; `owner_identification` does not. Editors: `api/src/routes/settings/{allocation,cash-flow-targets,tax-brackets}`. Closes the table family at 5/5 and the editor ramp at 4/4 — the tax pair is one editor, which is why the numbers differ.
>
> **AC.**
> 1. `pfin.owner_identification`: `users_id UUID NOT NULL` · `owner_id_header_text TEXT` · `created_at` · `updated_at`; `UNIQUE (users_id)`.
> 2. **Length bound: 120 characters — decided** (PM §12.4; default-and-notify, taken), a product prerequisite so this pair is not blocked at dispatch; the parity example is 41 characters, and *"a bound is what RT-12's 'length bounds' asks for"*. Enforced as a CHECK **and** in the Zod schema.
> 3. **Single line, plain text** (PRD ψ-1; INV-1). Reject embedded newlines at the write path.
> 4. **RLS** per the `090` standard: USING + WITH CHECK per verb, `users_id = auth.uid()`, explicit grants, **and the [ADR-029](DECISIONS.md#adr-029) / `025` aal2 step-up backstop clause on the `authenticated` policies** (Sec **F-9**; default-and-notify, taken). ⚠ Not eligible for the `user_settings` exclusion — that exists only because that table is the clause's own subquery target.
> 5. Reuse `pfin.fn_refresh_updated_at()` and the SELF-233 settings write-path hardening shared layer. UPSERT-in-place; no edit-history rows (Lock 14: settings are not audit-class).
>    - ⚠ **Consequence stated, not discovered:** with no history a rename cannot be read as-of — which is exactly why PRD §2.6.4 requires the header be **snapshotted** onto A1 (`owner_header_at_generation`), not read live (Sec **M-1**). **R1 (A) makes the snapshot the frozen payload's too** (A1 item 2, rider 1).
> 6. **Not a Decision 3 instance** — the only reference column is the direct `users_id` owner anchor. Decision 3 unchanged, and **no label may be drafted**: Decision 18's own amendment warns that a recorded expectation of membership *"is how a draft label gets invented and then reasoned out of existence."*
> 7. No JSONB (Lock 14 forward-compat fence). ⚠ **R1 rider 5 does not reach here** — that rider exempts A1's payload from the fence on the ground that `monthly_report` is not a settings table. **This table is one, and the fence binds it fully.**
> 8. **Canonical test label: RT-12** — SECURITY §4.1 axis iv, *"the §2.6.4 owner-identification settings-store write path (RT-12)"* (Sec **D-3**; default-and-notify, taken).
> 9. **Review classification: Sec joint-review MANDATORY** — taken as default-and-notify at the sitting (*"A8 Sec joint-review MANDATORY (Sec R-6); Sec's map governs classification"*), with all three roles agreeing. The drafted *"Sec advisory (not joint-review — single-column user-scoped table with no chain)"* is **struck**: *"'No chain' is true and is not the predicate. The predicate is Lock 14 membership, and A8 is the fifth member."* The same amendment that ratifies the five-table family says of itself that touching Lock 14 carries mandatory joint-review.
> 10. **QA:** two-tenant battery same PR, carrying the aal2 leg (Sec F-9) as a **separate leg** from the cross-tenant leg.
>
> **Dependencies.** Upstream: SELF-232, SELF-233. Downstream: P7; A3 reads it for the §2.6.1 header at generation.

---

## SELF-353 — A9. NAV component-checkpoint capture substrate

> **Baseline.** `b90b846`. **Buildable as drafted; only the provenance tense needs correcting** (default-and-notify: *"A9 tense fix only"*). Sec §5 requires **no change** and names it *"the best-drafted issue in the wave … the model the other eight A-items should follow."*
>
> **Milestone: NONE — A9 stays UNMILESTONED in Platform / Cross-cutting (R8).** [ADR-054](DECISIONS.md#adr-054) Decision 6 makes it orthogonal by construction, it has no §2.6 consumer, and **it must not gate SELF-362.** ⚠ **Its clock argument stands independent of milestone (R8 consequences): every day it does not exist is an unrecoverable observation gap** — which is why R13 dispatches it early (step 2), in parallel with the first dispatch, despite carrying no milestone.
>
> **Source.** ⚠ *Corrected:* [ADR-054](DECISIONS.md#adr-054) is **Accepted (2026-08-12)** and on the tree, including Decision 5's two closures. The drafted *"ratifies with the same doc PR"* / *"ratifies with the ADR"* describe a gate that has already closed.
>
> **AC** — unchanged in substance from the drafted (1)–(7); restated only where the tense moves:
> 1. New append-only audit-class sibling table beside `pfin.nav_daily` (`054`) — explicitly **not** columns on `054` (ADR-054 Decision 2; a ratified never-item).
> 2. Written by the same W-1 cron worker, same transaction, same credential model (LOGIN `pfin_etl` / WRITE `service_role` via `SET LOCAL ROLE`; `055` / [ADR-023](DECISIONS.md#adr-023) / SD-24).
> 3. **Per-account leaf granularity** (ADR-054 Decision 3): a leaf capture is retroactively re-aggregatable under any taxonomy and a pre-rolled one is not — on an append-only table that asymmetry is permanent. `051` already emits leaf values. Stated growth commitment: row count scales with account count forever.
> 4. **Capture-only.** No UI, no chart, no sheet-history backfill, **and no V1.x read helper** — closed at ADR-054 Decision 5(1).
> 5. **Decision 3 family member via `account_id`; matched-tenant validation in the DDL is non-negotiable.** Read Decision 3's body **live** at authoring; **carry no count**. Plus new RLS and the **required aal2 step-up backstop clause** — ⚠ this AC's own sentence says why (*"invisible once omitted"*), and Sec **F-9** uses it as the evidence that naming it is the convention.
> 6. **QA** two-tenant pgTAP battery same PR, carrying the **Σ(leaves) ↔ scalar-checkpoint reconciliation leg** (required — the property is by-construction today, so the leg exists to catch it ceasing to be, which nothing else would notice).
> 7. The sheet identity is a **documented parity property, not a schema-enforced invariant** — ADR-054 Decision 5(2), with the F/CTO rider recorded verbatim at the ADR.
> 8. **Sec joint-review mandatory** — four independent triggers, enumerated at ADR-054's Governance block.
>
> **Coherence post-V1.4, checked:** [ADR-067](DECISIONS.md#adr-067) Decision 3 keeps `nav_daily` the **gross pre-tax** series permanently while `105` composes tax-adjusted NAV at read time. A9 captures **leaves in the same cron transaction as the scalar row**, introduces no read helper, and therefore cannot drift from `105`'s definition because it never renders. ADR-054 Decision 6 makes its independence from the Chart-of-Accounts question structural. **This is why A9 was safe to dispatch before the sitting ruled, and R8 places it accordingly.**
>
> **Dependencies.** Upstream: `054`, the W-1 cron worker, `051` — all shipped. **No V1.5 dependency.** Downstream: the V2 subcomponent visualization; the drop-replace cutover clock.

---

## A10. On-demand monthly-report generation write path

> **Baseline.** `b90b846`. **⚠ NEW ISSUE — RULED at R9, option (2).** It has no Linear id until the liaison creates it at the amendment batch; the block moved here from the file's tail because R9 promotes it from *proposed* to a member of the A-lane.
>
> **Milestone: V1.5 — Monthly report full (§2.6)** (R9, applying R8's rule for substrate). Project: Platform / Cross-cutting. **Label: `sec-joint-review`.**
>
> **Why it is its own issue, not a fold into P5 (R9).** A3 is a **READ** helper and A7 is **cron-only**, so nothing on the tree or in the wave wrote a `monthly_report` row on the on-demand path. Generating a report is a **write** — a Lock 11 row with a server-derived `data_as_of` — and **a Decision 2 write inside a Frontend-reviewed SvelteKit issue has no Sec gate and no independent record**; if P5 slips, the write path and its obligations slip invisibly. Option (1) (fold all five of PM §7 item 2) not taken; option (3) (two new issues) not taken. ⚠ **[ADR-064](DECISIONS.md#adr-064) Decision 5 is cited for its REASONING only** — *"the trigger is the surface, not the layer, and not the author's assessment of risk"* — **and expressly NOT as jurisdiction** (D5 is scoped to `pfin.account_trans`; conflating them would be the false-composite class). **Losing side recorded at the ruling: 19 issues and a new blocking edge into P5.**
>
> **AC.**
> 1. **App endpoint under the user's OWN session** — the session *is* the tenant binding, which is why this path does not inherit R3's impersonation pattern. `users_id` from `auth.uid()`; no tenant parameter anywhere on the path.
> 2. **Writes the `draft` row per Lock 11 INSERT-new-version — NEVER `final` directly (R9 rider 1, and A1 item 6(c) is the DB-layer fence that enforces it).** Finalization is P4's path. **A10's row is the one the cron would have written on the 1st**, so the two paths share the **same INSERT shape**.
> 3. **`p_data_as_of` is SERVER-DERIVED and never client-asserted (R9 rider 2; Lock 15; RT-25).** A client-supplied as-of is **refused**, not ignored — battery leg at P10 item 8.
> 4. **Emits the per-generation audit row through the R7 helper (block AH), with trigger source = `on_demand`.** ⚠ **The helper therefore has two callers at V1.5, not one** (R7 rider 4) — this path and A7 — and both write the same shape.
> 5. **Refuses to finalize until P4's complete-or-explicitly-skip gate passes.** A10 opens the window; it does not close it.
> 6. **Under R1 (A) this path also OWNS THE FREEZE POINT** — when P4 promotes `draft → final`, A1 item 2's payload is composed (A3) and written **once**. ⚠ Whether the composing call is issued by this endpoint at finalization or by P4's transition handler is an **implementation split inside the same reviewed surface**; the AC states which, and the write happens **in the transition's transaction** so a half-finalized report cannot exist.
> 7. **Sec joint-review mandatory** — Decision 2 is the governing trigger (a new user-reachable **write** path onto a Decision 2 audit-class table), independent of the RT-25 obligation.
> 8. **QA:** legs at **P10** items 8 and 3.
>
> **Fallback, recorded so this is not read as binary (R9, Sec's own):** had F/CTO taken PM's fold-all-five, the fold would have been acceptable **only** with `joint-review:sec` on P5 and P5's AC naming the Decision 2 and RT-25 obligations explicitly rather than inheriting them. **It was not taken** — recorded because Sec's *"I would rather have the label on P5 than a nineteenth issue that gets dropped at promotion"* is **Architect's own named losing side for A10** and a live risk at promotion.
>
> **Dependencies.** Upstream: A1, A3, block **AH**. Downstream: P5, P4.

---

## SELF-354 — P2. §2.6.1.b in-app rendering UI

> **Baseline.** `b90b846`.
>
> **Milestone: V1.5 — Monthly report full (§2.6)**. Project: Platform / Cross-cutting.
>
> **AC.**
> 1. SvelteKit page at `/reports/monthly/{target_month}`, SSR via `+page.server.ts`, rendering the six PRD §2.6.1 sections in verbatim order — §2.6 **as amended at the R10 PR**. **Sidebar entry owed** — `+layout.svelte` records *"the rest of the locked app-sidebar (Monthly Report / Settings) lands as those…"*.
> 2. **The read path is RULED at R1 (A): a `final` report renders FROM THE STORED PAYLOAD.** ⚠ **Strike *"live-recompute on upstream surface changes when viewing latest report"*** — it contradicts φ-1, **latest included**. A `draft` report renders from A3's live composition; a `final` or `superseded` one renders from `rendered_payload`. The live view is the app's own surfaces, not this page.
>    - **The renderer reads `payload_schema_version` and keeps rendering old payloads** (R1 rider 4). A §2.x rendering change that cannot render an old version is a defect, not a migration.
> 3. ⚠ ***"Edit commentary" routes to P3***, not P4 — P4 is the trigger integration.
> 4. **The report renders the unavailable states, basis lines and the exclusion line the live surfaces render** (PM **A-1 / A-2 / A-3**, authorized at R10), and the §2.3 sections carry the one-source unclassified footnote the live rollup carries. ⚠ Under R1 these are **frozen values read back**, not recomputed — the copy below describes what was true at generation.
>    - **Copy (PM), folded verbatim:**
>      - Month/year stamp: *"{Month YYYY} · data as of {Mon D, YYYY} · generated {Mon D, YYYY}"*
>      - NAV Performance basis line (PM: *reuse the live copy verbatim*): *"This trend shows the checkpointed gross Net Worth — before the two tax lines and the designated tax-authority ledgers; the Account Holdings foot is the tax-adjusted figure."*
>      - Account Holdings tax rows unavailable (PM: *reuse the live §2.1.5 register*): *"Unavailable — no {IRS|FTB} ledger designated when this report was generated."* Exclusion line, three states as shipped on §2.1.5.
>      - Estimated Taxes capital-gains half (frozen state): *"Capital gains were unavailable when this report was generated — sale recording lands at a later V1.x."*
>      - Cash Flow partial footnote (PM: *reuse AC9's*): *"Partial — N items were unclassified as of {data as of}."*
>      - Report header: the owner string as set; unset → *"Set the report header in Settings"* (link). **PDF unset → no header line** (PM **A-13**, authorized at R10).
>      - PDF button: *"Download PDF"*; disabled on a pending report with tooltip *"Finalize this report to export it."*
> 5. **Envelope rendering is mandatory, not defensive:** a `{status:'unavailable', reason:…}` object renders as unavailable-with-reason. `?? 0` or currency-formatting an envelope is a defect, and the object type is what makes it fail loudly ([ADR-067](DECISIONS.md#adr-067) Decision 5). ⚠ Under R1 rider 1 the envelopes are **inside the frozen payload**, so a collapse here is permanent for that month.
> 6. **Sign convention:** the buildup ladder negates debt, realized and unrealized at **one** flip site applied to three rows, so the column foots. ⚠ A second flip anywhere renders a correct value with the wrong sign (`105`'s comment is the canonical home).
> 7. **Staleness markers are read LIVE at every render** — R1 rider 2's frozen-OUT carve-out; the page composes them over the frozen payload rather than from it. P8 owns the markers.
> 8. **Inline editing — no inline edit, on §2.6.2's ground.** ⚠ The drafted *"NO inline edit per ADR-013 P5"* citation is **struck**: ADR-013 Decision 7 governs the four **planning values**, and commentary is not one of them (Arch F-10, PM confirming; default-and-notify: *"P2 no inline commentary edit (§2.6.2 V2+)"*). **The answer is still no inline edit** — PRD §2.6.2 places copy-from-prior and the `$ ReAlloc` reference *in the editor*, and editing a **final** report's commentary is §2.6.2's V2+ *"late-edit / amend-after-generation"* item. **So: "Edit commentary" routes to P3 for a `draft` report and to "Regenerate" for a `final` one.** Cite §2.6.2's V2+ boundary; do not cite ADR-013 P5. Losing side (PM's): one extra click for the amend-a-final case.
>
> **Dependencies.** Upstream: A1, A3.

---

## SELF-355 — P3. §2.6.2.b commentary editor UI

> **Baseline.** `b90b846`. Unblocked once A1 lands.
>
> **Milestone: V1.5 — Monthly report full (§2.6)**. Project: Platform / Cross-cutting.
>
> **AC.**
> 1. **Four plain text areas** at `/reports/monthly/{target_month}/commentary`. **Headings (PM), verbatim: Cash · Bonds · Marketable Securities · Alternatives.** ⚠ The drafted *"Equity"* predates the 2026-08-19 ratify. **The column identifier is `commentary_marketable_securities` — RULED at R11 (a)**, so the Zod key and this heading now agree with the schema. Option (b) (keep `commentary_equity`, change only the heading) not taken — *a column on an immutable audit-class table is permanent, and the rename is free before the migration lands and a migration after.* ⚠ **R11 rider 1: the rename is recorded as a correction to Gate B's ratify text in the consolidated ADR (R14), never by migration alone.**
>    - Sub-heading under each (PM): *"Keyed to this month's $ ReAlloc for {Cat} — shown at right."*
> 2. **Copy-from-prior-month affordance — a V1 PRD commitment, absent from the draft, and FOLDED HERE at R9 (iv).** Copy (PM): per-sub-section *"Copy from {prior Month}"*; global *"Copy all from {prior Month}"*. ⚠ **The editor opens BLANK and copy-from-prior is an explicit affordance (R9 rider 4)** — disabled, with copy, when the prior month has no commentary: *"No {prior Month} commentary to copy."*
> 3. **`$ ReAlloc` side-by-side reference rendering — the second V1 commitment folded here at R9 (iv).** PRD: *"the V1 PRD commitment is that the $ ReAlloc reference data is visible alongside the editor during authoring"*; the **layout shape** (modal / inline panel / linked / dual-pane) is Architect's and is **not** a PRD commitment. Read-only; the authoring path never writes back to §2.2.2.
> 4. Blank by default; **no auto-pre-population** (PRD, deliberately — stale commentary must not leak forward). Editor note (PM): *"Plain text. Line breaks are kept; formatting is not."* Actions (PM): *"Save draft"* · *"Finalize {Month YYYY}"*.
> 5. **Write semantics.** Replace-all per the Lock 14 pattern. ⚠ **"SERIALIZABLE" is not reachable from this transport** — PostgREST runs each call as its own transaction and `SET TRANSACTION ISOLATION LEVEL` cannot be issued inside a function body. Follow the ratified realization at [ADR-011 Decision 18's 2026-09-03 amendment](DECISIONS.md#adr-011) / `101`: one SECURITY INVOKER plpgsql body whose **first statement takes a `FOR UPDATE` row lock**, which is also the tenant fence. **No tenant parameter** — `users_id` from `auth.uid()`.
>    - ⚠ **This write targets a Lock 11 row and therefore runs INSIDE THE DRAFT WINDOW ONLY** (PM **D-6**, ratified at R4). The immutability trigger permits any column while `generation_status = 'draft'` and **nothing** after; a write to a `final` row is refused at the DB, not merely hidden in the UI (A1 item 6).
> 6. Lock 14 hardening via the SELF-233 shared layer: Zod `.strict()`, mass-assignment prevention (`users_id` from `auth.uid()`). **The adversarial battery is the TEXT variant** — control characters, length bounds, encoding; the numeric battery does not apply. **The length bound mirrors A1 item 1's CHECK** — the two facts can disagree, which is what makes it a real second layer (Sec N-5).
> 7. Plain text only; line breaks preserved; **no markdown rendering**. ⚠ INV-1 makes plain-text-only **security-load-bearing**, so a future markdown affordance is a Sec re-touch, not a refinement (Sec **M-2**). ⚠ **Under R2 (C) this sentence carries more weight, not less**: the same string is escaped once, in the shared Svelte template, and rendered into both the page and the PDF (A4 item 5 · P6 item 7).
> 8. Empty sub-sections are legitimate and render with their label and an empty body (PRD §2.6.2 verbatim) — **no sub-section is hidden**. ⚠ **Four empty strings are an AUTHORED state and are not a skip** — R12 rider 1; the skip is P4's affordance writing A1's `commentary_disposition`.
> 9. **Canonical test label: RT-11** — SECURITY §4.1 axis iv, *"the §2.6.2 commentary write path (RT-11)"* (Sec **D-3**; default-and-notify, taken). ⚠ The leg names `commentary_marketable_securities` per R11.
>
> **Dependencies.** Upstream: A1. Downstream: P4.

---

## SELF-356 — P4. §2.6.2.c author-before-generate trigger

> **Baseline.** `b90b846`. ⚠ Sec §6 counts this **buildable as drafted**; PM §2 and Arch F-8 both find it contradicts the PRD. The three predicates differ — Sec §5 states explicitly that P4's gating *"is not a security control and I do not treat it as one"*, which is why it can be clean on Sec's predicate and not on the other two.
>
> **Milestone: V1.5 — Monthly report full (§2.6)**. Project: Platform / Cross-cutting. **Sec joint-review is CONDITIONAL** (R13 gates): mandatory unless this lands as control flow **inside** the already-reviewed A7 / A10 surface.
>
> **AC.**
> 1. **The gate is complete-**or-explicitly-skip**, not commentary-present** (default-and-notify, taken). PRD §2.6.3: *"completes (or explicitly skips) authoring"*; §2.6.2: empty sub-sections render as empty. **Skip is a V1 affordance; blocking removes it.**
> 2. **The notification is in-app, not Discord** (default-and-notify, taken). PRD §2.6.3: cron fire moves the month to **pending**, surfaced through *"an in-app notification + pending-monthly-report queue affordance (parallel to §2.4.1's iv-1)"*. Discord is the operator channel (Gate F), not the user's notification.
> 3. **Copy (PM), folded verbatim:**
>    - Pending item in the queue: *"{Month YYYY} — awaiting your Rebalancing Targets commentary."* CTA: *"Write commentary"* · secondary: *"Skip commentary and finalize"*.
>    - Skip confirmation: *"Finalize {Month YYYY} without commentary? The Rebalancing Targets section will show its four headings with empty bodies. You can regenerate this month later."*
> 4. **The pending view surfaces the no-ledger-designated prompt BEFORE finalize** — ⚠ **R1 rider 6 makes this LOAD-BEARING, not optional**: a frozen payload freezes its defects, and this is **the one moment** to catch a state that otherwise freezes into that month's report and its PDF forever. Copy (PM): *"No IRS/FTB ledger designated — NAV on this report will exclude tax liabilities"*, with the Settings/accounts link. **A prompt, not a block** (α′-1 spirit).
> 5. **The skip affordance WRITES the durable authored-vs-skipped fact — RULED at R12 rider 1.** It writes A1's `commentary_disposition`; *"a skip must be distinguishable from four empty strings."* ⚠ **R12 (A): an explicitly-skipped month does NOT count toward SELF-365's N = 2** — the gate exists to exercise the editor. **Losing side recorded at the ruling:** a month with genuinely nothing to rebalance fails that gate for a reason unrelated to V1's correctness and may add a month to V1.final — accepted as cheap next to a false close. ⚠ **SELF-365's own AC wording is PM's**, re-worded at the amendment batch; this block owes the write, not the definition.
> 6. **State transition: cron (or A10) writes `draft` → complete-or-skip promotes to `final` → regeneration supersedes.** ⚠ The promotion is an **UPDATE inside the draft window**, and the payload freeze happens in **the same transaction** (A10 item 6). A row may never be INSERTed directly as `final` (A1 item 6(c)).
>
> **Dependencies.** Upstream: P3, P5, A7, A10, A1.

---

## SELF-357 — P5. §2.6.3.b on-demand UI + pending queue

> **Baseline.** `b90b846`.
>
> **Milestone: V1.5 — Monthly report full (§2.6)**. Project: Platform / Cross-cutting.
>
> **AC.**
> 1. **Report listing surface with target-month selection — a V1 PRD surface no issue carried, FOLDED HERE at R9 (i).** Lists prior generated reports; **indefinite retention, no user deletion at V1** (and A1 item 6(a) blocks DELETE at the DB, so this is a fence, not a UI convention). Empty state (PM): *"No monthly reports yet. Your first report is generated on the 1st of next month, or generate one now."* CTA: *"Generate monthly report"*.
> 2. **Pending queue + in-app pending notification — FOLDED HERE at R9 (iii)**; the in-app half of P4 item 2. ⚠ **"Pending" means awaiting COMMENTARY, not a job state** (R9 rider 3; default-and-notify, taken): strike *"queued/in-flight/done"*; *"generation failed"* in-app notification is **V2+ by §2.6.3's own list**.
>    - ⚠ **The listing and queue reads are TENANT-SCOPED AT THE DB LAYER AND ASSERTED** (R9 rider 3; Sec **F-8**) — a queue leaks existence (row counts, timing, target months) even when it leaks no values. The natural implementation (read `monthly_report` under RLS) is scoped by construction; **Sec wants it asserted, not redesigned**, with a P10 leg proving tenant A sees **zero** of tenant B's entries.
> 3. **Target-month selection** (PM): default = prior month; current month labelled *"{Month YYYY} (in progress — as of today)"*.
> 4. **Regeneration entry (PM)** — ⚠ **load-bearing under R1 rider 6, because a frozen payload freezes its defects and this is the user's only repair**: *"Regenerate {Month YYYY}? The current report is replaced; your existing commentary is loaded into the editor to edit or keep."* Reuses Lock 11 INSERT-new-version; the prior row goes `final → superseded` (A1 item 6(ii)), which is **terminal**.
> 5. **The on-demand generation WRITE path is A10's, not this issue's — RULED at R9.** P5 **calls** it; P5 does not implement it. ⚠ A10 sits on this issue's critical path and is dispatched immediately before it (R13 steps 7–8).
> 6. `p_data_as_of` is **server-derived** on this path too — Lock 15's server-derived-only fence covers §2.6 cron **and** on-demand; §2.3.3 drill-down is the only surface where a client toggle is legitimate. **RT-25** (Sec D-3; default-and-notify, taken).
> 7. **Historical reads come from the frozen payload (R1 (A))** — this listing never re-composes a past month, and a "recompute" affordance is not a V1 surface.
>
> **Dependencies.** Upstream: A1, A3, A10, P4. Downstream: P6.

---

## SELF-358 — P6. §2.6.3.c PDF export

> **Baseline.** `b90b846`.
>
> **Milestone: V1.5 — Monthly report full (§2.6)**. Project: Platform / Cross-cutting.
>
> **AC.**
> 1. **Direction — RULED at R2 (C), and the drafted shape is struck.** The drafted browser→A5 JSON-payload-plus-JWT shape **inverts the ruling and puts the worker credential's trust boundary in the browser**. ⚠ **The user's Download click hits a USER-SESSION app route** (R2 consequences); **the worker credential never reaches the browser**; the app composes, renders the shared template, pushes finished HTML to the worker (A4/A5), and streams the returned bytes back.
> 2. "Download PDF" affordance on the P2 report page. Copy (PM): *"Download PDF"*; **available only from a generated-state report** — **no PDF of a pending report** (R2 consequences; default-and-notify, taken) — disabled on a pending one with tooltip *"Finalize this report to export it."*
> 3. **ONE HTML template, shared with P2 — and under R2 (C) this is STRUCTURAL, not a discipline** (R2 consequences: *"the in-app view and the PDF cannot drift; one template"* — PM's product requirement, byte-for-byte content except the live staleness layer). It is also what discharges the escaping control (item 7).
> 4. The PDF is a **transient export, not persisted server-side** (PRD §2.6.3 verbatim; the server-side artifact is A1's frozen payload per R1 rider 7). ⚠ Sec **M-6** is an explicit non-objection *with a standing condition*: **the first AC that persists rendered PDF bytes creates a new storage-class surface and is Sec-joint-review-mandatory at that PR.**
> 5. **Filename convention:** `mosko-monthly-{YYYY-MM}-{generated_at}.pdf` (default-and-notify, taken). ⚠ **Never the owner string in the filename** — *"a PDF name travels further than its contents"* (PM).
> 6. **PDF staleness markers are read LIVE at export**, not from the frozen payload — R1 rider 2's carve-out, stated from the export side (PRD §2.6.4; PM §2 P6 · Sec M-4). Everything else in the PDF comes from the payload.
> 7. **The escaping PROOF LEG lives here — RULED at R2's consequences on §7.32 item 6, and this is Sec R-5's resolution.** The *control* is discharged structurally at A4 (the worker composes nothing; Svelte's default escaping is the control). The *proof* is owed here under **INV-2, because it spans both engines**: a stored `<script>` in commentary, the **owner string** (A8) and the inherited **`schedule_label`** (`101`) render **inert** in the PDF as well as on the page. ⚠ Sec **M-2**'s scope note matters and is carried: `BACKLOG.md` §7.32 item 6 was drafted against `schedule_label` before the other fields existed and reaches them only through its *"every other free-text field"* clause. **§7.32 item 6 reduces to header + citation once this lands** — team-lead's edit, not this issue's.
> 8. **QA:** the two-abort leg (A4 item 4b's interception handler) and the inert-`<script>` leg both live at **P10** and are named there.
>
> **Dependencies.** Upstream: A4, A5, P2.

---

## SELF-359 — P7. §2.6.4.b owner-identification Settings editor

> **Baseline.** `b90b846`. **Unblocked. FIRST DISPATCH, with A8** (R13 step 1).
>
> **Milestone: V1.5 — Monthly report full (§2.6)**. Project: Platform / Cross-cutting. ⚠ **V1-SHIP-BLOCK, and R8 turns on that fact**: P7 is in the milestone and cannot ship without A8, which is why A8 is milestoned with it.
>
> **AC.**
> 1. Settings route `/settings/owner-id`, extending the SELF-242 shell, beside the shipped `/settings/{allocation,cash-flow-targets,tax-brackets,security}`. Single TEXT input.
> 2. **Copy (PM), folded verbatim:** page title *"Report header"*; field label *"Owner identification"*; helper *"Appears at the top of every monthly report generated after you save. Plain text, one line, up to 120 characters. Example: THE ⟨NAME⟩ 2023 TRUST."* — 120 per A8 item 2 (default-and-notify, taken). Empty state: *"No header set — reports show no owner line until you add one."*
> 3. Replace-all write to A8 via the SELF-233 hardening shared layer: Zod `.strict()`, mass-assignment prevention, the **TEXT-variant** adversarial battery. A single-row UPSERT through PostgREST needs no lock; if routed through an RPC, the P3 item 5 note applies.
> 4. **The editor says so:** a rename applies **forward only**, and P7 renders, at the editor, *"Reports already generated keep the header they were generated with."* (PRD §2.6.4; Sec **M-1**.) ⚠ **Under R1 (A) that is true twice over** — the header is both snapshotted onto A1 and frozen inside the payload.
> 5. **Canonical test label: RT-12** (Sec **D-3**; default-and-notify, taken).
> 6. Closes the Settings ramp at 4/4 (SELF-242 V1.2 + SELF-252 V1.3 + SELF-265 V1.4 + this).
> 7. **QA:** the leg proving a rename leaves a prior `final` report's header unchanged belongs in **P10** and is listed there.
> 8. ⚠ **Walk-gated before the Sec spawn** (R13 gates: every user-facing issue).
>
> **Dependencies.** Upstream: A8, SELF-233, SELF-242.

---

## SELF-360 — P8. §2.6.5 staleness markers on §2.6 surfaces

> **Baseline.** `b90b846`.
>
> **Milestone: V1.5 — Monthly report full (§2.6)**. Project: Platform / Cross-cutting. **Not Sec joint-review-mandatory** (R13 gates: P8 and P9 are the two exceptions).
>
> **AC.**
> 1. **α′-1 generate-with-markers, not block.** Cron generates regardless of staleness.
> 2. ⚠ **Markers are computed LIVE at every render and every export — never frozen at generation.** This is **R1 rider 2's frozen-OUT carve-out**, and it survives the (A) ruling intact: the payload freezes values, the markers are not values. The drafted *"at generation time"* inverts PRD §2.6.4's explicit live-read carve-out (PM §4 calls it *"the load-bearing defect"*; Sec **M-4** names the direction: *a report generated while every item was healthy, viewed a month later when an item is pending re-auth, shows no badge* — the §2.4.4 headline commitment inverted). **The frozen payload carries NO markers** (default-and-notify: *"P8 markers live at every render/export"*).
> 3. **Both halves are required** and PRD §2.6.5 rejects either alone: per-section inline markers **and** a report-level banner naming stale accounts. ⚠ α′-3 banner-only is a named rejected alternative — not a valid V1.5 reduction. **The banner is PM §7 item 2(v)'s uncarried surface, FOLDED HERE at R9 (v).**
> 4. **Attribution route — taken as default-and-notify at the sitting: the PER-SECTION half is attributed IN THE APP LAYER, reusing the shipped V1.3 shape** (`api/src/lib/cashflow-row-staleness.ts`, `CashflowRowStaleTag.svelte`). The DB primitive is **not** extended. `pfin.fn_aggregation_has_stale_constituent()` (`046`/`059`) takes **zero arguments** and returns **one aggregate row for the calling user** — it serves the **banner**; it cannot serve per-section attribution. ⚠ A scope-typed argument is **not** available in any case — `pfin.scope` is not a type (A2 item 2).
> 5. **The informational tier is a second, distinct signal** (§2.4.4's second staleness source): a carried reference-series value marks affected sections **per-section only and never enters the banner**, which names stale-contributing *accounts*. Copy (PM): per-section badge reuses `<StaleConstituentBadge>`; informational tier reuses `<InformationalMarkerBadge>`.
> 6. **Two exclusions:** §2.6.2 commentary and the §2.6.4 owner header are **not** marked — not account-derived (PRD §2.6.5).
> 7. **Banner copy (PM), folded verbatim** — and note it carries the live-vs-generation distinction in the string itself, which is item 2 stated to the user: *"These accounts are currently in re-auth state; sections sourced from them are marked stale as of today, not as of {Month YYYY}: {account list}."*
> 8. Extends SELF-208 / 229 / 243 / 258 per ADR-013 D1. ⚠ **Walk-gated before any Sec touch** (R13 gates).
>
> **Dependencies.** Upstream: SELF-208, A3, P2, P6 (both render surfaces the markers overlay).

---

## SELF-361 — P9. §2.5.x staleness ramp

> **Baseline.** `b90b846`. **Unblocked.** Sec §5 requires no Sec review of it and calls it light-loop-eligible; PM §2 finds one leg already shipped.
>
> **Milestone: V1.5 — Monthly report full (§2.6)**. Project: Platform / Cross-cutting. **Not Sec joint-review-mandatory** (R13 gates).
>
> **AC.**
> 1. ⚠ **Retitle to two surfaces, not three.** The **NAV-composition leg is already shipped** — `NavCompositionTable.svelte` carries the aggregation badge and per-row leaf staleness from the SELF-229 ramp, and `105` reused the same payload. The `taxes/decomposition` and `taxes/quarterly` routes carry **no** `StaleConstituentBadge`; **those two legs stand.**
> 2. Consumes `pfin.fn_aggregation_has_stale_constituent()` — zero-argument signature, verified (PM **D-10**).
> 3. ⚠ **The §2.5 surfaces carry a second, non-Plaid degraded state that must NOT merge into the stale badge:** the `{status:'unavailable', reason:…}` envelopes and the `basis_year` fallback ([ADR-067](DECISIONS.md#adr-067) Decision 5). *"No ledger designated"* and *"your brokerage needs re-auth"* are different facts with different user actions. State the separation in the AC so a future consolidation cannot collapse them.
>    - **No new copy is owed here** — both registers are already shipped: `reasonCopy()` for the envelopes, `<StaleConstituentBadge>` for staleness. **State the separation by pointing at the two shipped components**, not by writing strings.
> 4. **Sequenced AFTER the R10 PRD PR** (R13 step 4, and R10's own sequencing clause): the R10 batch lands with SELF-364's §2.5.3 amendments **before P9's dispatch**, because P9's copy is written against amended §2.5.3. **364 and P9 do not overlap in substance** — 364 builds nothing.
>
> **Dependencies.** Upstream: SELF-208, SELF-264, SELF-266, SELF-268 — all shipped. Sequencing: after the R10 PRD PR (with SELF-364).

---

## SELF-362 — P10. §2.6.6 RLS verification battery (V1.5 close-gate)

> **Baseline.** `b90b846`. **LAST in the dispatch order (R13 step 12), and extended IN THE SAME PR as each surface it covers.** Inherits every ruling.
>
> **Milestone: V1.5 — Monthly report full (§2.6)**. Project: Platform / Cross-cutting.
>
> **AC.**
> 1. Two-tenant coverage of A1 + A2 + A3 + A5 + A7 + A8 + A10 + block **AH** + P3's write path: cross-tenant injection rejected on each. ⚠ **R8 makes the close-gate see its substrate** — *"no V1.5 issue closes until the battery passes"* now reaches A1–A8 and A10 because they carry the milestone.
> 2. **aal2 legs are SEPARATE legs from cross-tenant legs** on A1, A2 and A8 (Sec **F-9**): a totp/passkey-enrolled caller presenting a below-aal2 JWT lands on the refusal leg. ⚠ A battery testing only cross-tenant **passes with the aal2 clause absent.**
> 3. **A3 cross-tenant leak analysis** — a foreign caller gets the **empty/unavailable shape**, i.e. fails closed *into a shape that says so*. Plus Sec **F-4**'s cron leg **with its positive control** (R3 rider 2): run for tenant A with tenant B's rows **present**; assert zero tenant-B rows composed; **prove the leg reds when the role assumption is struck.** A fresh fixture with no tenant-B rows makes this leg vacuous by default.
>    - ⚠ **The no-`rolbypassrls`-EXECUTE leg is a STANDING catalog assertion, not a one-time check — R3 rider 1.** *"The single most valuable assertion in the file … the leg that closes F-4 at the database layer regardless of how S-2 and S-3 resolve."* Mechanism verified: the shipped pattern at `104`/`105` is `revoke execute … from public; grant execute … to authenticated;`, and `008` contains **no** function-level EXECUTE grant, so `service_role` acquires EXECUTE only by an explicit future grant. **The failure mode is a future migration adding a grant to make something work**, which is why the leg must be standing. ⚠ For a SECURITY INVOKER function the EXECUTE ACL is normally the weakest of several fences; **against a `rolbypassrls` caller it is the only one.**
>    - **`RESET ROLE` discipline between tenants on a pooled connection has its own leg** (R3 rider 3).
> 4. ⚠ **Tri-axis is CONDITIONAL in the PRD and must be built conditionally** (Sec **M-3**; default-and-notify, taken): tri-axis `tenant × scope × tax_treatment` **where the underlying classes carry tax-treatment**; for §2.6.1 surfaces with no tax-treatment dimension it **collapses to `tenant × scope`**. The drafted unconditional form puts a `tax_treatment` axis over surfaces with no such dimension — **legs that cannot fail, which is the tell.** **The PRD condition is quoted per leg**, so a future reader cannot "fix" the asymmetry into uniformity.
>    - ⚠ Both non-tenant axes are `text not null` columns on `pfin.account` (`003`); `scope` is a free-text ADR-004 label, **not** an enum or a type. Include a leg proving both are **orthogonal to tenancy**: a matching `scope` string across two tenants must not leak.
> 5. **SD-12 child sub-class addendum; NOT a new SD class** (Sec M-3 and Sec §5 both confirm).
> 6. **A1's immutability trigger — the four R4 catch criteria, each a separate leg:** (i) **regenerate one month THREE times → three rows, exactly one `final`** (a two-regeneration leg passes against the defective three-column UNIQUE — Sec D-5); (ii) UPDATE a `final` row **as `authenticated` AND as `service_role`** → refused (R4 condition (b) — a leg run only as `authenticated` passes with a `service_role` early-return in place); (iii) **DELETE as each role → refused** on any non-`draft` row (R4 condition (a)); (iv) **INSERT directly as `final` → refused** (R4 condition (c)). Plus (v) `superseded` is **terminal** — every transition out of it refused (R4 condition (d)).
> 7. **A1's frozen payload (R1):** a `final` report's stored payload is byte-stable across reads; a read of a `final` report issues **no** call to A3; the payload's envelopes survive round-trip **unflattened**; `payload_schema_version` is present and non-NULL on every `final` and `superseded` row and NULL is permitted only on `draft` (A1 item 2's CHECK, both directions).
> 8. **A5 / A4 under R2 (C):** the **two-abort leg** — HTML carrying `<iframe src="file:///proc/self/environ">` and `<img src="http://169.254.169.254/">` yields a PDF containing neither the signing key nor any fetched content **AND** an interception handler recording **two aborts** (asserting only *"the PDF looks fine"* is vacuous). Plus the **inert-`<script>`** leg spanning both engines (P6 item 7): a stored `<script>` in commentary, the owner string and `schedule_label` render inert in the PDF. Plus the re-derived RT-21 letters (A5 item 3), **each failing for its own reason**.
> 9. **The R7 audit helper (block AH):** the same-transaction row **exists**, **names the resolved tenant**, and is **absent when the generation transaction rolls back**; the surface-name argument is required and a bad value is refused; append-only holds **under both roles**.
> 10. **A7's cron tenant-binding isolation**, including a leg that would catch the **singular-GUC** failure (one tenant's data served for every tenant) — no app-layer symptom, so only a DB-side leg sees it.
> 11. **Added legs:** superseded rows invisible to every read path · `owner_header_at_generation` frozen (a Settings rename does not change a prior `final` report — P7 item 7) · **A10's server-derived `data_as_of`: a client-supplied as-of is REFUSED, not ignored** (**RT-25**; R9 rider 2) · the pending queue **tenant-scoped** (tenant A sees zero of tenant B's entries — R9 rider 3 / Sec F-8) · **A1's `commentary_disposition`: a skip and four empty strings are distinguishable** (R12 rider 1) · **the R5 CONSTRUCTION-ONLY leg on `included_reconciliation_event_ids`, labelled as such in its own text** — it asserts the fence exists and is attached, **not** that it fires.
> 12. **Canonical labels named per surface** — RT-11 / RT-12 / RT-19 / RT-20 / RT-21 / RT-25 (Sec **D-3**). ⚠ This battery's coverage list is *"the natural place to catch the omissions in one pass"*; a false-composite label (A2's RT-21-for-RT-20) is invisible precisely because the RT-21 battery **will** exist and **will** be green.
> 13. ⚠ Battery hygiene: pgTAP `isnt()` **passes on NULL**, so a negative assertion over a subquery is fail-open — use `ok()` and prove three states. Verify with `pg_prove`, never bare `psql` (exits 0 on a failed plan). Rebuild the scratch DB before any full-suite claim — `rollback` does not reset sequences.
> 14. **V1.5 close-gate:** no V1.5 issue closes until this passes. **Sec verdict recorded per the SELF-269 precedent** — ⚠ **R12 clause (5) reads that record**: a month counts toward V1.final only if this battery was green on the tree that generated it.
>
> **Dependencies.** Upstream: all V1.5 issues, all rulings.

---

## Rulings applied above — resolved, indexed

Every ruling this file depends on, with the sitting-log entry that carries it. **The reasoning is cited, never restated** ([ADR-063](DECISIONS.md#adr-063) Decision 2) — read [`sitting-log.md`](sitting-log.md) **@ `1417337`**. **Nothing here was Architect's to take.**

| Seam / question | Entry | Blocks carrying it |
|---|---|---|
| **S-1 / PM A-5** — does a `final` report store its rendered values or recompose | **R1 (A)** frozen rendered payload + riders 1–8 | A1 items 2 / 5 / 9, A2 header + item 2, A3 items 1 / 6 / 11, P2 items 2 / 4 / 5 / 7, P4 item 4, P5 items 4 / 7, P6 items 4 / 6, P8 item 2, P10 item 7 |
| **S-2 / PM D-7 / Sec F-5** — the PDF render direction | **R2 (C)** app pushes finished HTML + Sec's two conditions | A4 items 0 / 2 / 4b / 4c / 5, A5 (whole block; RT-21 re-derived at item 3), P6 items 1 / 3 / 7, P3 item 7, P10 item 8 |
| **S-3 / Sec R-3 + F-4** — tenant binding for the non-JWT caller | **R3 (i) α** impersonation, reusing `connection.py` | A3 items 1 / 2 / 8 / 12, A7 item 2, A5 item 5 (moot half), P10 items 3 / 10 |
| **Sec N-3** — the ARCH `:208` reading | **R3 (ii)** session context, PDF-scoped; narrowed on the tree | A3 item 3 (the one copy), A7 item 3, R14's doc PR |
| **Sec R-1 / Arch §8.3** — supersession on the immutable header | **R4 (B)** + Sec conditions (a)–(d) | A1 items 5 / 6, A2 items 4 / 6, P3 item 5, P4 item 6, P5 item 4, P10 item 6 |
| **S-5 / Sec F-2** — `included_reconciliation_event_ids INTEGER[]` | **R5 (a)** ship dormant; realizes label #3 | A1 item 3, A2 item 3, P10 item 11 |
| **Sec R-2 / F-6** — SELF-350's disposition | **R6 (ii)** re-scope in place + riders 1–4 | A6 (whole block), A4 items 3 / 6 |
| **Sec N-2 / A7-AUDIT** — the D1 clause (d) audit-log home | **R7 (2)** author the reserved general helper | **AH** (new block), A1 item 11, A7 item 6, A10 item 4, P10 item 9 |
| **Platform A-item milestone placement** | **R8** A1–A8 → V1.5; A9 unmilestoned | every A-block's milestone line, A9's header, P7 header, P10 item 1 |
| **PM §7 item 2** — five PRD surfaces no issue carried | **R9 (2)** fold four, open A10 | **A10** (promoted to a full block), P3 items 2 / 3, P5 items 1 / 2, P8 item 3, P10 item 11 |
| **PRD §2.6 amendment batch** | **R10** authorized as drafted | every *"as amended at the R10 PR"* citation; A1 source, A2 source, A3 item 4, A7 items 5 / 7, P2 items 1 / 4, P9 item 4 |
| **D-4 / Arch F-3** — the commentary column identifier | **R11 (a)** rename | A1 items 1 / 3-adjacent, P3 items 1 / 9 |
| **PM §6** — V1.final's month of operation; skipped months | **R12** definition ratified; **(A)** a skip does not count | A1 item 9, P4 item 5, A7 item 6, P10 items 11 / 14 · **SELF-365's own AC is PM's** |
| **Dispatch order** | **R13** accepted as listed | not re-listed here — [`sitting-log.md`](sitting-log.md) **R13** is the one copy; gates cited at P4, P7, P8, P9, P10 |
| **The consolidated ADR** | **R14** Architect authors; rides A1's PR | A1 header + items 1 / 2 / 5 / 8, A2 item 2, A3 items 3 / source, A4 item 0, A5 items 1 / 3, A7 source |
| **Sec R-5** — the escaping control's home | discharged **by** R2's consequences, not separately | A4 item 5 (control), P6 item 7 (proof leg) |
| **Sec R-6** — A8's review classification | default-and-notify, taken | A8 item 9 |
| **S-4** — the §2.6.5 attribution route | default-and-notify, taken (app layer, V1.3 shape) | P8 item 4 |

**Default-and-notify items are TAKEN** — reversal window open until the amendment batch merges — and are applied in the blocks above, credited inline where they land. They are enumerated in [`sitting-log.md`](sitting-log.md) § *Default-and-notify* and are deliberately **not** re-listed here.

**`⟨OPEN⟩` items — three, each named where it lives.** A2 item 3 (the parent FK's disposition — the obligation is ruled, the answer is authored at the migration and reviewed at the unit's joint review) · AH item 2 (the reserved DEFINER slot's disposition if the helper lands INVOKER — routed to Sec at that PR) and AH's Linear home · A5 item 6 (whether the app→worker token keeps its `users_id` claim under (C) — routed to Sec at A5's build alongside (g)). **None of the three is a ruling this file invented; each is a residual with a stated owner and route.**

---

## Not in this wave

**SELF-365 (P11, V1.final), SELF-363 (CA 2026 seed), SELF-364 (PRD §2.5.3 amendments), SELF-326 (volatility pin)** carry no V1.5 milestone and none blocks a V1.5 issue.

- **SELF-326** is context for A3 item 9. When it lands, pin by `ALTER` — a `DROP`+`CREATE` destroys grants (`072`), and `CREATE OR REPLACE` silently resets volatility, so the pin must be re-asserted per signature.
- **SELF-364** settles the installment-count definition A3 renders; `104` already implements the ratified reading, so the PRD is catching up to the code. ⚠ **R10 and R13 step 3 sequence its PRD PR — with the R10 batch, before P9's dispatch.**
- **SELF-365** — **R12 ratified its definition and ruled (A) on the skip question**, and its **AC re-wording is PM's**, landing at the amendment batch. This file owes it the V1.5 facts that make it measurable, all now homed: the per-generation audit row with trigger source and `data_as_of` (**block AH** item 3, written by **A7 item 6** and **A10 item 4**), the durable authored-vs-skipped fact (**A1 item 9**, written by **P4 item 5**), `generated_at` on the final row (**A1 item 1**), and the recorded battery verdict (**P10 item 14**). **The definition itself is not restated here** — read R12.

---

## Observations booked out of this pass (no V1.5 issue)

1. **Two dated `comment on` texts read as live state** and are falsified by ADR-011 Decision 3 read at this sha: `059`'s stale-constituent comment and `054`'s trigger comment both state old family tallies. `104`/`105` already state the corrected convention, so the generator is fixed going forward. **Not proposing a comment-only migration in V1.5** — team-lead's to book (Arch F-14).
2. **`BACKLOG.md` §7.1 carries the vetoed `SUPABASE_URL` text** (Sec **D-1**, veto adopted at R6 rider 3) — the defect is in the **promotion source**. **Not touched by this pass**; it lands in the close-out PR.
3. **`BACKLOG.md` §7.32 item 6 reduces to header + citation once P6 lands** (R2 consequences) — team-lead's edit, booked, not this file's.
4. **`BACKLOG.md` §7.6 item S7** — the standing tracker for the Decision 1 clause (d) deferral on the W-1 NAV worker. Block **AH** makes it dischargeable; **whether that worker is retrofitted is not ruled and is not this wave's** (AH item 8). Booked so the helper is not later read as having closed S7 by existing.
5. **ARCH §3.2's overview paragraph names `pfin.plaid_sync_audit` as the audit-log emit target for privileged-context writes** (verified at the resolution sha; the table was dropped at `015`). It sits two lines above the `:208` sentence R3 (ii) narrows and inside the §3.2 diagram R2 amends, so **the R14 doc PR is already in that neighbourhood.** Not a §2.6 defect and not this file's to fix — recorded so the doc PR's author sees it while there.
6. **ARCH §4's cross-container row cites the RT-21 battery as *"a/b/c/d/e/f"* — six letters against RT-21's canonical seven.** Same neighbourhood, same PR, same reason for recording it here rather than fixing it.
