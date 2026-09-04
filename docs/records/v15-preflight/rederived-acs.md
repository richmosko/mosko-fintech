# V1.5 re-derived ACs — Architect

**Round 2 (2026-09-04).** Landing-ready replacement AC text, one block per issue, for paste into Linear after the sitting. **Each block self-carries its baseline sha.**

**Round-2 folds.** PM's product wording (`pm-findings.md` §8, read at `origin/meta/v15-preflight-pm` @ `4c9f628`, md5 `06db14a4…`) is folded **verbatim and credited `(PM)`** into the blocks that own each string. The canonical RT labels Sec names at `sec-findings.md` **D-3** (read at `origin/meta/v15-preflight-sec` @ `374ba8e`, md5 `a8e7090d…`) are added to the blocks they belong to. The ADR-029 / `025` **aal2** clause is stated on A1, A2 and A8 per Sec **F-9** and the `090` policy standard. A6's block is a **re-scope-in-place** block carrying Sec **D-1** and **F-6**.

**Round-2 second pass — PM's by-block list applied.** PM's round 2 (`origin/meta/v15-preflight-pm` @ `77425b3`, md5 `eb7bcb2cc0bec0a737dad1708e79e45d`, verified) carries at **§12.5** a by-block list of user-facing-string and PRD-contradiction fixes for this file. All are applied and credited `(PM)`. ⚠ **PM read Architect's ROUND-1 file (`f3335c48`)**, so several §12.5 items were already applied in round 2 — each such item is marked *ref-skew, not disagreement* in its block rather than silently absorbed. **Every `⟨PM⟩` placeholder in this file is now resolved; no copy string remains owed.**

Sibling items are **cited by id, never restated** — read them in their own files. `⟨RULING⟩` marks a seam still owed a ruling. Seam ids (`S-n`) and finding ids (`F-n`) are this pass's Architect ids in `architect-findings.md`; PM ids are `A-n` / `D-n`, Sec ids are `F-n` / `M-n` / `D-n` / `R-n` — **all three files use `F-n` and `D-n` independently, so every citation below names its owner.**

---

## SELF-345 — A1. `pfin.monthly_report` header table (Lock 11)

> **Baseline.** `b90b846` (2026-09-04). Every identifier below verified against the tree at this sha.
>
> **Source.** [ADR-011 Decision 15 / Lock 11](DECISIONS.md#adr-011) verbatim; [PRD §2.6.1](docs/PRD/index.html#story-2-6-1) header + [§2.6.2](docs/PRD/index.html#story-2-6-2) commentary persistence per Wave 6 Gate B Option C (4 named TEXT columns on the header table; no JSONB commentary blob per the Lock 14 forward-compat fence). ⚠ *Source corrected* — the four **sub-section headings** are **Cash / Bonds / Marketable Securities / Alternatives** per PRD §2.6.2 verbatim, F/CTO-ratified 2026-08-19 following ADR-058 Decision 7 (migration `082`). Arch F-3 · PM D-3 · Sec D-4.
>
> **⚠ BLOCKED ON `⟨RULING⟩` S-1** (= PM **A-5**) — whether a `final` report stores its rendered values or is recomposed at read time. The column list below is complete under either answer **except** the frozen-value carrier, which S-1 adds.
>
> **AC.**
> 1. **Table** `pfin.monthly_report`: `users_id UUID NOT NULL` · `target_month DATE NOT NULL` · `generation_status` with the Lock 11 vocabulary `draft` / `final` / `superseded` · `data_as_of DATE NOT NULL` · `generated_at TIMESTAMPTZ` · `owner_header_at_generation TEXT` · `commentary_cash`, `commentary_bonds`, `commentary_marketable_securities`, `commentary_alternatives` (all `TEXT`) · `created_at` · `updated_at`.
>    - `owner_header_at_generation` is **required, not optional** (Arch F-2 · PM D-5 · Sec M-1). It is **NULLable and stays NULL** for a report generated before the user set a header — PM **A-13** rules that state and its rendering.
> 2. **`included_reconciliation_event_ids INTEGER[]`** — `⟨RULING⟩` **S-5** (= Sec **F-2**, which states the options as A build / B retire-by-amendment / C re-defer, Sec lean B; Arch round-1 lean was A). ⚠ **Whatever is ruled, the disposition is written down**: Sec F-2's load-bearing point is that shipping this table with the column silently absent converts a DDL-deferred Decision-3 instance into a permanently invisible one.
> 3. **Uniqueness — the locked partial index, verbatim:** `UNIQUE (users_id, target_month) WHERE generation_status = 'final'`. Arch F-1 · Sec D-5 (whose catch criterion is the sharp one: **regenerate the same month three times**, not twice — a two-regeneration leg passes against the defective three-column form).
> 4. **[ADR-011 Decision 3](DECISIONS.md#adr-011) — realizes an existing label; allocates none.** Read Decision 3's body live at authoring. The DDL states, per column, **which allocated label it realizes and which fence-pattern class (P1 / P2 / CR) it uses** (Sec F-1's requirement). ⚠ The instance is the `INTEGER[]` column, never `users_id` — Sec F-1 defect 3 names why a matched-tenant fence on `users_id` is *the leg that cannot fail*. **No count is stated in this AC, in the migration, or in any `comment on`.**
> 5. **Decision 2, both halves.** The header is **INSERT-new-version** on regeneration; a row that has reached `final` is immutable thereafter. **Supersession mechanism = `⟨RULING⟩` Sec R-1** — ⚠ the drafted `SECURITY DEFINER fn_supersede_monthly_report` is struck either way: it is a new DEFINER function outside the Decision 9 allowlist with no recorded justification. **Architect's position is Sec R-1 option B (narrow column-scoped UPDATE exemption), not option A — see `architect-findings.md` §8.3; the disagreement is left standing for the sitting.**
> 6. **Mutability window** — PM **D-6**: commentary is editable while the report is `draft` and frozen at `final`. The immutability trigger's scope (final-only vs all rows) follows R-1's answer; whatever lands, it also UPDATE-fences `users_id` and `target_month` post-creation (Lock 12's Sec catch: a parent re-tenant orphans A2's children from their original tenant).
>    - ⚠ `updated_at` + `fn_refresh_updated_at` are **correct only on the draft window** (PM D-6). On a final-immutable row the trigger is dead code or a hole; the migration states which.
> 7. **RLS** per the `090` standard: USING **and** WITH CHECK per verb; `users_id = auth.uid()`; explicit grants; **and the [ADR-029](DECISIONS.md#adr-029) / `025` aal2 step-up backstop clause on the `authenticated` read and write policies** (Sec **F-9**). None of the three documented exclusions applies — in particular **not** the `user_settings` exclusion, which exists only because that table is the clause's own subquery target. **Catch criterion (Sec F-9):** a totp/passkey-enrolled caller presenting a below-aal2 JWT lands on the refusal leg — a **different leg** from the cross-tenant leg; a battery testing only cross-tenant passes with the clause absent.
> 8. **Status vocabulary bridge**, stated once against the transition (PM **A-8**): cron writes `draft`; completing **or explicitly skipping** authoring promotes to `final`; regeneration supersedes. **Presentation mapping (PM §12.3 R-1, reworded so it holds under all three R-1 options):** *"pending = draft; generated = the current final; a superseded version is never rendered in V1."* ⚠ This replaces the earlier *"superseded is a storage state only"* phrasing, which presumes `superseded` exists as a **stored value** — true under R-1 options B and C and false under option A. The reworded sentence is true under all three, so the AC does not have to wait on R-1.
>    - ⚠ **The column rename `commentary_equity` → `commentary_marketable_securities` (Arch F-3) rides the §9 consolidated ADR, not this migration alone** (PM **§12.3 F-3**). The four column names are a **Gate B ratify record** carried in CHANGELOG, so the rename is stated in that ADR as a correction to Gate B's text and the migration implements it. **Architect concurs** — a migration that silently renames a ratified enumeration is the same "downstream register cannot amend a lock" failure ADR-011 Decision 18's amendment names. Sec D-4 has no objection either way.
> 9. **A durable authored-vs-skipped fact per report.** PM §6 shows V1.final's N=2 gate cannot be measured without it, and *"a skip must be distinguishable from four empty strings"* (PM) — so it is a V1.5 column on this table, not a V1.final concern.
> 10. **Sec joint-review mandatory.** **QA:** two-tenant pgTAP battery pairs in the same PR.
>
> **Dependencies.** Upstream: SELF-232, SELF-233, **`⟨RULING⟩` S-1**, **`⟨RULING⟩` Sec R-1**. Downstream: A2, A3, A7, P2, P3, P5.

---

## SELF-346 — A2. `pfin.monthly_report_account_snapshot` child table (Lock 12)

> **Baseline.** `b90b846`.
>
> **Source.** [ADR-011 Decision 16 / Lock 12](DECISIONS.md#adr-011) verbatim; [PRD §2.6.4](docs/PRD/index.html#story-2-6-4).
>
> **⚠ BLOCKED ON `⟨RULING⟩` S-1** (= PM **A-5**). This table's column set **is** the S-1 decision made concrete. Lock 12 locks `(monthly_report_id, account_id, acct_name_at_generation)`; widening it is a **Lock 12 amendment** needing F/CTO ratify + Sec joint-review, not an implementation detail (Arch F-7 · PM A-5, which notes the drafted AC already reaches for the widening *"without saying so"*).
>
> **AC.**
> 1. Child table, FK to `pfin.monthly_report` **ON DELETE RESTRICT** (Lock 12 verbatim — not CASCADE).
> 2. Columns: Lock 12's locked three, plus whatever S-1 rules. ⚠ **`scope` is not available as a typed column** — `pfin.scope` does not exist as a type at this sha; `pfin.account.scope` is `text not null`, a free-text [ADR-004](DECISIONS.md#adr-004) Decision B label. `pfin.account.tax_treatment` **is** real (`003`). Either, if carried, is a copy of the account's value at generation time, named as such.
> 3. **Decision 3 — realizes the existing `account_id` label; allocates none** (Arch F-6 · Sec F-1 · PM D-4). Read Decision 3 live; state no count.
>    - ⚠ **The parent FK needs its own explicit disposition** (Sec F-1's open question, and it is a genuine one): this child carries **two** FK-shaped columns, and Decision 3's rule is written over *any* of them. Either the parent FK is fenced — and if it is a genuinely new relationship it takes the next canonical label, **allocated at the migration, never in advance** — or it is argued out with the reasoning recorded in the DDL. It may not be left unstated.
> 4. **Lock 12's three V1-SHIP-BLOCK mods in full:** matched-tenant trigger on `account_id`; parent `users_id` + `target_month` immutability (lives on A1 item 6, verified from this side); `service_role` bypass DB-trigger on the child.
> 5. **RLS via the parent FK chain** (`090` standard; USING + WITH CHECK per verb; **aal2 clause per Sec F-9**). ⚠ The join to the parent keys on the **surrogate `monthly_report_id`**, never on a `(users_id, target_month)` value pair: a surrogate-id join fails **closed** under an RLS regression, a shared-vocabulary join fails **open**.
> 6. Read-only post-write (Decision 2 immutable half).
> 7. **Canonical test label: RT-20**, not RT-21 (Sec **D-3**). ⚠ The drafted *"RT-21 HIGH"* is a false composite — [ADR-011 Decision 16](DECISIONS.md#adr-011) names **RT-20 HIGH** for this surface (fourth-instance FK-bypass + service_role bypass + parent immutability extension); RT-21 is the PDF-worker JWT battery on a different surface. Built as drafted, **the RT-20 battery is never written and nothing notices, because an RT-21 battery will exist and will be green.**
> 8. **SD-12 child sub-class addendum** — the correct home; **not** a new SD class (Sec M-3 and Sec §5 both confirm; PRD §2.6.6 resolves it as a derivative surface).
> 9. **Sec joint-review mandatory.** **QA:** two-tenant battery same PR.
>
> **Dependencies.** Upstream: A1, **`⟨RULING⟩` S-1**, SELF-214, SELF-201. Downstream: A3, A7.

---

## SELF-347 — A3. SECURITY INVOKER read-composition helper

> **Baseline.** `b90b846`.
>
> **Source.** [ADR-011 Decision 15 / Lock 11](DECISIONS.md#adr-011) read-composition pattern; Gate A Option B unified. ⚠ *Source note:* Lock 11's own join list names `pfin.nav`, **which does not exist at this sha** (Arch F-note; PM A-5 quotes the same list). ⚠ The drafted *"SELF-260/261 §2.5.1"* citation is struck — **SELF-261 closed unbuilt**; §2.5.1's readers are `100`/`104` (PM **D-11**).
>
> **⚠ BLOCKED ON `⟨RULING⟩` S-1** (= PM A-5) **and `⟨RULING⟩` S-3** (= Sec **R-3** / Sec **F-4**).
>
> **AC.**
> 1. **Signature: `pfin.fn_render_monthly_report(p_target_month DATE, p_data_as_of DATE) RETURNS JSONB`.** ⚠ **No `p_users_id` parameter** — PM **D-11** logs this as the 6th recurrence of the §7.19 signature family, and Sec **F-4** states the security half: with `p_users_id` present, a bypass-RLS caller makes the *parameter* the only tenant fence, which is ADR-011 Decision 1 clause (c) unacknowledged. Precedent on the tree: `105` (*"p_users_id DROPPED"*) and `101` (*"takes NO tenant parameter … R4 rider 4 / Sec D-2"*).
>    - ⚠ Under S-1 Option A the third entry path takes **the report row**, not `(month, as_of)` — PM §2 (A3) names this; the signature above is the composing form and a historical read is a payload read.
> 2. **Composes the six PRD §2.6.1 sections in verbatim order** over the live substrate: Account Holdings ← `fn_nav_composition` (`105`); NAV Performance ← the §2.1.2/§2.1.3/§2.1.4 readers; Asset Allocation ← `fn_subcat_market_value` (`076`/`081`) + `planning_target` (`074`); Rebalancing Targets ← A1's commentary columns; Cash Flow ← `fn_cashflow_items` / `fn_cashflow_cross` / `fn_historical_expenditures` (`093`/`096`); Estimated Taxes ← `fn_compute_tax_liability` (`104`).
> 3. **§2.5.4's two NAV-component values render on Account Holdings via the §2.1.5 buildup, NOT as Estimated Taxes rows** (PRD §2.6.1 verbatim).
> 4. **Every envelope and every basis note is carried, never collapsed** — PM's product rider at §2 (A3) and PM **A-1 / A-2 / A-3**. `{status, amount}` / `{status, reason}` objects cross unflattened, `reason` stays a stable machine code, `basis_year` and `current_year_schedule_empty` travel ([ADR-067](DECISIONS.md#adr-067) Decision 5 — the type does the work, not consumer discipline). No coalesce, no zero-fill, no currency formatting inside this helper. **The `unavailable` case is the bootstrap default, not an edge case.**
> 5. **ONE CALL, ONE CLOCK.** `p_data_as_of` threads unchanged into every callee; nothing derives its own date; the payload echoes `as_of` back so a consumer can prove the threading (Lock 15; R3 rider 4).
> 6. **Posture, per the `104`/`105` precedent:** `security invoker` · `set search_path = ''` · volatility `stable` **declared in the body per signature** (`CREATE OR REPLACE` resets it) · EXECUTE to `authenticated`, **never to a `rolbypassrls` role** — for such a caller the EXECUTE grant is the entire perimeter rather than the weakest fence; the standing Sec-joint-review condition on `104`/`105` is inherited.
> 7. ⚠ **Known transitive volatility gap, inherited not introduced:** `fn_gl_entries` and `fn_holdings_as_of` are `provolatile = 'v'` at this sha (SELF-326 open). Name it in the header; do not claim a fully-pinned read set.
> 8. **Canonical test labels: RT-19** (read-time composition tenant-scoping, [ADR-011 Decision 15](DECISIONS.md#adr-011)) **and RT-25** (as-of parameter-bypass adversarial input, [Decision 19](DECISIONS.md#adr-011)) — Sec **D-3**; neither appears in the drafted AC.
> 9. **Render-budget statement (PM §10, routed to Architect).** This helper is the heaviest read on the tree — `fn_nav_composition` **plus** every §2.1–§2.3 reader **plus** `104` in one call, on three paths, two of them interactive. **The latency probe on `fn_compute_tax_liability` runs before this signature is fixed**, and this AC states a render budget the interactive paths meet or names the async shape.
> 10. **Sec joint-review mandatory.** **QA:** the Sec F-4 catch criterion — a two-tenant fixture where the worker runs for tenant A while tenant B's rows exist, asserting **zero** tenant-B rows in the composed output, ⚠ **with a positive control proving the leg reds when the binding is struck** (the leg is vacuous by default on a fresh fixture).
>
> **Dependencies.** Upstream: A1, A2, **`⟨RULING⟩` S-1**, **`⟨RULING⟩` S-3 / Sec R-3**, SELF-262, SELF-268, the Wave 1–5 substrate. Downstream: P2, P5, P6, A7.

---

## SELF-348 — A4. Node PDF worker container (extend, not scaffold)

> **Baseline.** `b90b846`.
>
> **Source.** [ADR-011 Decision 17 / Lock 13](DECISIONS.md#adr-011); Gate C V1.x Platform scope.
>
> **⚠ NOT GREENFIELD.** `workers/pdf-render/Dockerfile` + `.env.example` exist (landed `eada4b2`) as a deliberate placeholder *"shipped so the RT-22 fence has a real target to audit"*; PM §2 (A4) additionally measures the `.husky` hadolint hook and the `workers/CLAUDE.md` row on the tree. Sec **D-2** states the same measurement independently. **This issue extends that file**, and every commit to it is already gated by the live RT-22 fence.
>
> **⚠ BLOCKED ON `⟨RULING⟩` S-2** (= PM **D-7** / Sec **F-5**) — direction and payload shape.
>
> **AC.**
> 1. Extend the existing Dockerfile with Puppeteer + system Chromium deps. **Do not restructure the `ENV`/`ARG` block** — the shipped fence's criterion (i) keys on `^\s*(ENV|ARG)\s+SUPABASE_`.
> 2. **Zero-DB-isolation, unchanged (Lock 13 mod #2): no `SUPABASE_*` env vars at all** — ⚠ *there is no `SUPABASE_URL` carve-out* (Sec **D-1**, a **veto** on the drafted carve-out). Single permitted variable: `PDF_WORKER_SIGNING_KEY` per SD-20. No Postgres client.
> 3. ⚠ **The dependency manifest is the live gap** (Sec **F-6**): the moment this issue lands a real Puppeteer app, the standard shape is `COPY package*.json .` then `RUN npm ci`, and the RT-22 fence is **documented not to look at manifests** — `pg` can enter through a path the fence cannot see while the fence reports clean. **A4 may not land its `package.json` before the RT-22 manifest extension lands** (re-scoped SELF-350 — see that block). Sequencing, not a duplicate control.
> 4. Lock 13 mod #7 browser hardening: browser-context-per-render, system-fonts-only, `--disable-features=BackgroundFetch,ServiceWorker,BackgroundSync`, cache disabled, per-render PDF metadata cleared.
> 5. **Escaping of user-controlled free text — `⟨RULING⟩` S-2 decides whether this control lives here at all**, and PM and Sec currently home it differently (PM §10 attaches it to A4; Sec **R-5** leans folding it into P6). **Architect's position: the home follows S-2 and neither is unconditionally right — `architect-findings.md` §8.4.** Under S-2 Option B the worker composes HTML and the control is **mandatory here**, asserted per free-text field on the **rendered output** — commentary (A1), `owner_id_header_text` (A8) and the inherited `schedule_label` (`101`), per Sec **M-2**, whose scope note matters: [BACKLOG.md](BACKLOG.md) §7.32 item 6 was drafted against `schedule_label` before the other fields existed and reaches them only through its *"every other free-text field"* clause. Under S-2 Option A or C the worker composes no HTML and the obligation converts into a **negative assertion** that it does not.
> 6. No `TenantBoundConnection` fence applies — that fence is the Python ETL's. ⚠ Sec **F-6** notes `fence-tbc-node.sh` excludes `workers/pdf-render/` on the stated premise *"has ZERO DB reach"* — **a premise, not a control**; this issue is the one that could falsify it, and nothing would notice.
> 7. Deploys per the V1 greenfield posture ([ADR-021](DECISIONS.md#adr-021)); Coolify→Discord on deploy. ⚠ **cax21 is reference-only, NOT the deploy target** — PM **D-9** strikes the drafted *"deploys on cax21"*, quoting `.env.example` verbatim.
>
> **Dependencies.** Upstream: **`⟨RULING⟩` S-2**, and the re-scoped SELF-350 manifest fence per item 3. Downstream: A5, P6.

---

## SELF-349 — A5. `/internal/pdf-render` + the RT-21 battery

> **Baseline.** `b90b846`.
>
> **Source.** [ADR-011 Decision 17 / Lock 13](DECISIONS.md#adr-011); [ARCH §3.2](docs/ARCH/index.html); SECURITY §4.5 **RT-21** + SD-20. **This surface is genuinely unbuilt** and Sec D-2 confirms that half of the wave is correctly scoped.
>
> **⚠ BLOCKED ON `⟨RULING⟩` S-2 and `⟨RULING⟩` S-3 (= Sec R-3).**
>
> **AC.**
> 1. **Direction is S-2's subject** (Arch S-2 · PM **D-7** · Sec **F-5**). ARCH §3.2 has this endpoint answering a **`GET` from the PDF worker** and returning **rendered HTML**. Do not build either shape until S-2 rules.
> 2. ⚠ **The server derives the payload; it does not trust one** (Sec **F-5**). As drafted, the PDF's *content* comes from the caller and the JWT authenticates only that *a* caller may render — so a valid render JWT renders arbitrary content under whatever owner header the payload asserts. **The endpoint derives the payload server-side from A3 under the JWT's tenant, or the AC records explicitly why a client-supplied payload is trusted and what bounds it.** **Catch criterion (Sec F-5):** POST a well-formed tenant-A JWT with a payload carrying tenant-B figures; assert 4xx, or assert the rendered PDF carries tenant A's server-derived figures and none of the submitted ones.
> 3. **The RT-21 battery is the canonical (a)–(g), read verbatim from SECURITY §4.5** (Arch F-4 · Sec **F-3**): **(a)** authenticated-tier JWT only, `service_role` JWT rejected at signature verification; **(b)** dedicated signing key — Supabase-JWT-signed tokens rejected; **(c)** **60-second freshness window**; **(d)** nonce replay protection; **(e)** no `service_role` escalation; **(f)** dedicated endpoint — verification logic at `/internal/pdf-render` only; **(g)** rejected payloads dropped **with a detection signal**.
>    - ⚠ **The path is part of clause (f)** — the drafted `/api/internal/pdf-render` is not cosmetic; (f) is written over `/internal/pdf-render` (Sec F-3).
>    - ⚠ **A5's inventions — tenant-claim presence, audience check, issuer check — are wanted and are kept, labelled as ADDITIONS**, so the canonical letters keep pointing at the catalog (Sec F-3). A leg named `(c)` asserting `exp` rather than a 60-second `iat` window is a red whose message names the wrong defect, and the tempting repair is to loosen the window.
> 4. ⚠ **(g) must not be built by inheritance from RT-05.** [ADR-050](DECISIONS.md#adr-050) F3 records RT-21(g) as inheriting RT-05's defect **unbuilt**; RT-21's body states its answer *"may legitimately differ"* (RT-05's webhook is internet-facing, this endpoint is on the private container network) and marks it **Sec joint-review-mandatory at the build**. It also names `pfin.plaid_sync_audit` as the storage surface — **dropped at `015`**. (g) gets its own design call.
> 5. **The tenant-binding mechanism is `⟨RULING⟩` S-3 / Sec R-3 and is NOT locked.** ARCH §3.2 verbatim: the mechanism *"is Phase 5 detail design"*. ⚠ The drafted *"Arch-locked … per RT-21(e)"* is struck — **RT-21(e) is the no-escalation clause and contains no binding mechanism.** ⚠ Sec F-4 names the fail-open shape precisely: setting `request.jwt.claims` **without also assuming the `authenticated` role** leaves `rolbypassrls` in force — `auth.uid()` returns the intended tenant, every RLS predicate is skipped, and the composition reads every tenant's rows, silently. Prior art for the correct shape: `workers/etl/src/pfin_back_etl/connection.py`.
> 6. The JWT carries a **`users_id` claim only** — no `data_as_of` claim (Lock 15 mod #7b; SD-20; PM D-7's product half: *the worker renders what the app renders, nothing the client asserts*).
> 7. This route is a §4.1 server-source surface inside RT-26's audit scope and **holds no allowlist entry** (ARCH §3.2). **Canonical test labels: RT-21** (this battery) **+ RT-25** (the `p_data_as_of` parameter-bypass axis, Sec D-3).
> 8. **Sec joint-review mandatory.** **QA:** seven canonical legs plus the labelled additions, each failing for its own reason.
>
> **Dependencies.** Upstream: A4, **`⟨RULING⟩` S-2**, **`⟨RULING⟩` S-3 / Sec R-3**. Downstream: P6.

---

## SELF-350 — A6. RT-22 — **RE-SCOPE IN PLACE to the dependency-manifest extension**

> **Baseline.** `b90b846`.
>
> **⚠ First sentence, deliberately: the fence this issue was written to build already exists and has since Phase 5 Step 4 W1. This issue is re-scoped, in place, to the gap that fence cannot see.**
>
> **Disposition — `⟨RULING⟩` Sec R-2, and Architect concurs with Sec's lean (ii), re-scope-in-place, over Architect's round-1 "close".** Reason for the change, recorded rather than quietly adopted: round 1 measured that the fence is *implemented* and concluded nothing remained. Sec **F-6** measured the fence's *reach against what A4 will actually do* and found live successor work. Re-scoping keeps the RT-22 work under one id and keeps A4's dependency edge valid; Sec's named losing side stands — the issue's title and history then describe work already done, which is why this AC says so in its first sentence.
>
> **Already discharged on the tree (no further work):** `scripts/ci/fence-rt22-pdf-worker-dockerfile.sh` (fail-closed; exit 1 on violation, exit 2 on unreadable target) + the `security-scan.yml` job running it **production-mode** against `workers/pdf-render/Dockerfile` and **inversion-mode** against `tests/fixtures/ci/rt22-violation.Dockerfile`, failing the build if the fence reports clean on the fixture. Run-always, not path-triggered. Documented at `scripts/ci/README.md`.
>
> **Two drafted clauses are struck and must NOT be implemented:**
> 1. ⚠ **Sec D-1 is a VETO on the `SUPABASE_*` carve-out.** Lock 13 mod #2 verbatim is *"no `SUPABASE_* `env vars"* with no exception, and the shipped fence implements it without exception. A PR implementing the drafted AC would **loosen a fence that is live, run-always and fail-closed today.** ⚠ The same defective text sits at `BACKLOG.md` §7.1 line 300 — **the defect is in the promotion source, not a Linear transcription** — and that fix lands in the close-out PR after the sitting, not here.
> 2. ⚠ **The *"both catalogued instances"* parenthetical is struck and replaced by nothing.** It is a ledger-figure claim; [ADR-011 Decision 4](DECISIONS.md#adr-011) is read live. **Path B — let the link carry it. Do not restore a number** (Sec D-1 defect 1).
> - Also absent from the drafted AC and present in the shipped job: the **inversion-mode golden fixture** step. An AC re-speccing the fence without it, landing as a replacement, would remove the only thing proving the fence can still bite (Sec D-1).
>
> **New AC — the RT-22 dependency-manifest extension (Sec F-6).**
> 1. Extend RT-22's catch criteria to `workers/pdf-render/package.json` **and its lockfile**, rejecting Postgres-client packages — `pg`, `postgres`, `node-postgres`, `@supabase/supabase-js`, and `knex`/`sequelize`-class packages that bundle a driver.
> 2. **Paired with a golden violation fixture and an inversion-mode step**, exactly as the Dockerfile fence is paired today. *A fence that does not fail closed is theatre* (Sec F-6); the existing job is the pattern to copy.
> 3. The base-image transitive residual stays **human PR-review second line** per `scripts/ci/README.md` and ARCH §6.1 — unchanged, and stated so the extension is not read as closing it.
> 4. **Ledger effect: none.** Decision 4 catalogues *instances*, not automation states; extending a fence's catch criteria adds, removes, reorders and renumbers nothing. ⚠ **The CI-fenced set and the §10 catalogued set are different sets and are not reconciled** — Sec D-2 makes the same point (RT-22's membership in both is coincidence, not identity).
> 5. **Owner: DevOps (fence) + QA (fixture).** Sec joint-review retained — the `sec-joint-review` label stays valid under the re-scope.
>
> **Dependencies.** Downstream: **A4 — item 3 of that block; the manifest fence lands before A4's `package.json`.**

---

## SELF-351 — A7. monthly_report cron worker

> **Baseline.** `b90b846`.
>
> **Source.** [ADR-011 Decision 15 + Decision 17](DECISIONS.md#adr-011); Gate F Option α native Coolify cron container.
>
> **⚠ Depends on `⟨RULING⟩` S-1 (what the cron writes) and `⟨RULING⟩` S-3 / Sec R-3 (how it binds a tenant).**
>
> **AC.**
> 1. Native Coolify cron container, **1st of each month, generating the prior month's report**; `p_data_as_of` = last day of the prior month, **server-derived** (Lock 15 server-derived-only fence for §2.6 paths; **RT-25** per Sec D-3).
> 2. **Reuse the shipped tenant-binding module; do not re-specify it.** `workers/etl/src/pfin_back_etl/connection.py` (`TenantBoundConnection`: READ as `authenticated` via `SET LOCAL ROLE` + `set_config('request.jwt.claims', …, true)`; WRITE as `service_role` via `SET LOCAL ROLE`) and the per-tenant loop in `nav_backfill.py`. `service_role` for **tenant enumeration only** (Lock 11 mod #4).
>    - ⚠ **Sec F-4 is the reason the role half is non-negotiable:** claims without the role leaves `rolbypassrls` in force and the composition reads every tenant, silently, with nothing raising. Sec's α also requires a **`RESET ROLE` discipline and a test** — a leaked `SET` across tenants in a pooled connection is its own leak.
> 3. ⚠ **Inherit the singular-GUC hazard handling.** `auth.uid()` prefers `request.jwt.claim.sub` over the plural blob, so a session-scoped singular GUC left set serves **one tenant's data for every tenant, with no code bug and no app-layer assertion failure** (`054`; `connection.py` nulls it, N7).
> 4. **Cron does not finalize and does not skip.** PRD §2.6.3 verbatim — cron fire moves the month to **pending** and surfaces it through *"an in-app notification + pending-monthly-report queue affordance"*; cron never auto-finalizes (PM **§2 P4** · Arch F-8). Coolify→Discord stays the **operator** channel for run success/failure (PM A-14), never the user's authoring notice.
> 5. **The per-generation audit row has no home on the tree** — PM **D-8**: Lock 13 mod #8's `pfin.plaid_sync_audit` was **dropped at `015`**. This AC creates or names its home, carrying at minimum the **trigger source** and **`data_as_of`** (Decision 19's shape). ⚠ PM §6 shows V1.final's N=2 gate is **unmeasurable without it**, so this is V1.5 work, not a V1.final concern.
> 6. **Ruled per-tenant wording** (PM **A-7**): *"One scheduled run generates per tenant under tenant binding (ADR-011 Decision 1); there is no per-user job, and no cross-tenant data path inside the run."*
> 7. ⚠ **cax21 struck** — the V1 Coolify target per [ADR-021](DECISIONS.md#adr-021) (PM **D-9**).
> 8. ⚠ **UTC-pin residual, recorded not discharged** (PM §10, Sec M-4(a) lineage): if `data_as_of` derives from the UTC-pinned clock (`061`/`070`), a Pacific user's month-end is UTC's, ~7 hours early. **Not a §2.6 defect and not measured here** (this worker is unbuilt); recorded so the still-unnamed owner of BACKLOG §7.32 item 3 sees a second consumer.
> 9. **Sec joint-review mandatory.**
>
> **Dependencies.** Upstream: A3, **`⟨RULING⟩` S-1**, **`⟨RULING⟩` S-3 / Sec R-3**, the `workers/etl` incumbent. Downstream: P2, P5, P4.

---

## SELF-352 — A8. `pfin.owner_identification` settings table

> **Baseline.** `b90b846`. **Nearest to buildable in the A-lane; unblocked. Recommended first dispatch with P7.**
>
> **Source.** [ADR-011 Decision 18 / Lock 14](DECISIONS.md#adr-011) **as amended 2026-08-16 — the family is FIVE per-domain tables**, and this is the last unbuilt member. ⚠ *Source corrected:* the drafted line quoted the locked *"four per-domain tables"* while the AC built against five; that amendment names **this very entry** as the measurement that made the divergence visible. [ADR-013](DECISIONS.md#adr-013) Decision 7 — Settings 4th-of-four occupant.
>
> **Measured:** `planning_target` (`074`), `cashflow_target` (`090`), `tax_bracket_schedule` + `tax_bracket_row` (`101`) exist; `owner_identification` does not. Editors: `api/src/routes/settings/{allocation,cash-flow-targets,tax-brackets}`. Closes the table family at 5/5 and the editor ramp at 4/4 — the tax pair is one editor, which is why the numbers differ.
>
> **AC.**
> 1. `pfin.owner_identification`: `users_id UUID NOT NULL` · `owner_id_header_text TEXT` · `created_at` · `updated_at`; `UNIQUE (users_id)`.
> 2. **Length bound: 120 characters — decided** (PM **§12.4**, taken as a product prerequisite so this pair is not blocked at dispatch; the parity example is 41 characters, and *"a bound is what RT-12's 'length bounds' asks for"*). Enforced as a CHECK **and** in the Zod schema.
> 3. **Single line, plain text** (PRD ψ-1; INV-1). Reject embedded newlines at the write path.
> 4. **RLS** per the `090` standard: USING + WITH CHECK per verb, `users_id = auth.uid()`, explicit grants, **and the [ADR-029](DECISIONS.md#adr-029) / `025` aal2 step-up backstop clause on the `authenticated` policies** (Sec **F-9**). ⚠ Not eligible for the `user_settings` exclusion — that exists only because that table is the clause's own subquery target.
> 5. Reuse `pfin.fn_refresh_updated_at()` and the SELF-233 settings write-path hardening shared layer. UPSERT-in-place; no edit-history rows (Lock 14: settings are not audit-class).
>    - ⚠ **Consequence stated, not discovered:** with no history a rename cannot be read as-of — which is exactly why PRD §2.6.4 requires the header be **snapshotted** onto A1 (`owner_header_at_generation`), not read live (Sec **M-1**).
> 6. **Not a Decision 3 instance** — the only reference column is the direct `users_id` owner anchor. Decision 3 unchanged, and **no label may be drafted**: Decision 18's own amendment warns that a recorded expectation of membership *"is how a draft label gets invented and then reasoned out of existence."*
> 7. No JSONB (Lock 14 forward-compat fence).
> 8. **Canonical test label: RT-12** — SECURITY §4.1 axis iv, *"the §2.6.4 owner-identification settings-store write path (RT-12)"* (Sec **D-3**); absent from the drafted AC.
> 9. ⚠ **Review classification: `⟨RULING⟩` Sec R-6 — MANDATORY, and all three roles now agree.** The drafted *"Sec advisory (not joint-review — single-column user-scoped table with no chain)"* is **not accepted by Sec** (**F-7**): *"'No chain' is true and is not the predicate. The predicate is Lock 14 membership, and A8 is the fifth member."* **Architect concurs; PM §12.3 R-6 concurs.** The same amendment that ratifies the five-table family says of itself that touching Lock 14 carries mandatory joint-review. F/CTO has final authority.
>    - ⚠ PM **§12.5** lists this block as still reading *"advisory, not joint-review … as drafted"*. That describes Architect's **round-1** file (`f3335c48`), which is the ref PM read; the concurrence above landed in round 2. **Not a disagreement — a ref-skew.**
> 10. **QA:** two-tenant battery same PR, carrying the aal2 leg (Sec F-9) as a **separate leg** from the cross-tenant leg.
>
> **Dependencies.** Upstream: SELF-232, SELF-233. Downstream: P7; A3 reads it for the §2.6.1 header at generation.

---

## SELF-353 — A9. NAV component-checkpoint capture substrate

> **Baseline.** `b90b846`. **Buildable as drafted; only the provenance tense needs correcting.** Sec §5 requires **no change** to it and names it *"the best-drafted issue in the wave … the model the other eight A-items should follow."* PM §2 records it as out-of-§2.6-scope with no product finding.
>
> **Source.** ⚠ *Corrected:* [ADR-054](DECISIONS.md#adr-054) is **Accepted (2026-08-12)** and on the tree, including Decision 5's two closures. The drafted *"ratifies with the same doc PR"* / *"ratifies with the ADR"* describe a gate that has already closed.
>
> **AC** — unchanged in substance from the drafted (1)–(7); restated only where the tense moves:
> 1. New append-only audit-class sibling table beside `pfin.nav_daily` (`054`) — explicitly **not** columns on `054` (ADR-054 Decision 2; a ratified never-item).
> 2. Written by the same W-1 cron worker, same transaction, same credential model (LOGIN `pfin_etl` / WRITE `service_role` via `SET LOCAL ROLE`; `055` / [ADR-023](DECISIONS.md#adr-023) / SD-24).
> 3. **Per-account leaf granularity** (ADR-054 Decision 3): a leaf capture is retroactively re-aggregatable under any taxonomy and a pre-rolled one is not — on an append-only table that asymmetry is permanent. `051` already emits leaf values. Stated growth commitment: row count scales with account count forever.
> 4. **Capture-only.** No UI, no chart, no sheet-history backfill, **and no V1.x read helper** — closed at ADR-054 Decision 5(1).
> 5. **Decision 3 family member via `account_id`; matched-tenant validation in the DDL is non-negotiable.** Read Decision 3's body **live** at authoring; **carry no count**. Plus new RLS and the **required aal2 step-up backstop clause** — ⚠ this AC is the *only one of the eighteen* that names aal2, and its own sentence says why (*"invisible once omitted"*); Sec **F-9** uses it as the evidence that naming it is the convention.
> 6. **QA** two-tenant pgTAP battery same PR, carrying the **Σ(leaves) ↔ scalar-checkpoint reconciliation leg** (required — the property is by-construction today, so the leg exists to catch it ceasing to be, which nothing else would notice).
> 7. The sheet identity is a **documented parity property, not a schema-enforced invariant** — ADR-054 Decision 5(2), with the F/CTO rider recorded verbatim at the ADR.
> 8. **Sec joint-review mandatory** — four independent triggers, enumerated at ADR-054's Governance block.
>
> **Coherence post-V1.4, checked:** [ADR-067](DECISIONS.md#adr-067) Decision 3 keeps `nav_daily` the **gross pre-tax** series permanently while `105` composes tax-adjusted NAV at read time. A9 captures **leaves in the same cron transaction as the scalar row**, introduces no read helper, and therefore cannot drift from `105`'s definition because it never renders. ADR-054 Decision 6 makes its independence from the Chart-of-Accounts question structural. **This is why A9 is safe to dispatch before S-1 is ruled, and PM §7 item 3 reaches the same placement: keep, unmilestoned, dispatch when Architect has a gap; it must not gate the close-gate issue.**
>
> **Dependencies.** Upstream: `054`, the W-1 cron worker, `051` — all shipped. **No V1.5 dependency.** Downstream: the V2 subcomponent visualization; the drop-replace cutover clock.

---

## SELF-354 — P2. §2.6.1.b in-app rendering UI

> **Baseline.** `b90b846`. **⚠ BLOCKED ON `⟨RULING⟩` S-1** (= PM A-5).
>
> **AC.**
> 1. SvelteKit page at `/reports/monthly/{target_month}`, SSR via `+page.server.ts`, rendering the six PRD §2.6.1 sections in verbatim order. **Sidebar entry owed** — `+layout.svelte` records *"the rest of the locked app-sidebar (Monthly Report / Settings) lands as those…"* (PM §2 P2).
> 2. ⚠ **Strike *"live-recompute on upstream surface changes when viewing latest report"*** — it contradicts φ-1 (PM §2 P2 · Sec **M-5** adjacent). A `final` report is frozen, latest included; the live view is the app's own surfaces. The read path itself is S-1's subject.
> 3. ⚠ ***"Edit commentary" routes to P3***, not P4 — P4 is the trigger integration (PM §2 P2).
> 4. **The report renders the unavailable states, basis lines and the exclusion line the live surfaces render** (PM **A-1 / A-2 / A-3**), and the §2.3 sections carry the one-source unclassified footnote the live rollup carries.
>    - **Copy (PM), folded verbatim:**
>      - Month/year stamp: *"{Month YYYY} · data as of {Mon D, YYYY} · generated {Mon D, YYYY}"*
>      - NAV Performance basis line (PM: *reuse the live copy verbatim*): *"This trend shows the checkpointed gross Net Worth — before the two tax lines and the designated tax-authority ledgers; the Account Holdings foot is the tax-adjusted figure."*
>      - Account Holdings tax rows unavailable (PM: *reuse the live §2.1.5 register*): *"Unavailable — no {IRS|FTB} ledger designated when this report was generated."* Exclusion line, three states as shipped on §2.1.5.
>      - Estimated Taxes capital-gains half (frozen state): *"Capital gains were unavailable when this report was generated — sale recording lands at a later V1.x."*
>      - Cash Flow partial footnote (PM: *reuse AC9's*): *"Partial — N items were unclassified as of {data as of}."*
>      - Report header: the owner string as set; unset → *"Set the report header in Settings"* (link). **PDF unset → no header line** (PM **A-13**).
>      - PDF button: *"Download PDF"*; disabled on a pending report with tooltip *"Finalize this report to export it."*
> 5. **Envelope rendering is mandatory, not defensive:** a `{status:'unavailable', reason:…}` object renders as unavailable-with-reason. `?? 0` or currency-formatting an envelope is a defect, and the object type is what makes it fail loudly (ADR-067 Decision 5).
> 6. **Sign convention:** the buildup ladder negates debt, realized and unrealized at **one** flip site applied to three rows, so the column foots. ⚠ A second flip anywhere renders a correct value with the wrong sign (`105`'s comment is the canonical home).
> 7. **Inline editing — answered by PM §12.3 F-10; no ruling owed.** ⚠ The drafted *"NO inline edit per ADR-013 P5"* citation is **struck**: ADR-013 Decision 7 governs the four **planning values**, and commentary is not one of them (Arch F-10, which PM confirms). **The answer is still no inline edit, on a different ground** — PRD §2.6.2 places copy-from-prior and the `$ ReAlloc` reference *in the editor*, and editing a **final** report's commentary is §2.6.2's V2+ *"late-edit / amend-after-generation"* item. **So: "Edit commentary" routes to P3 for a `draft` report and to "Regenerate" for a `final` one.** Cite §2.6.2's V2+ boundary; do not cite ADR-013 P5. Losing side (PM's): one extra click for the amend-a-final case.
>
> **Dependencies.** Upstream: A3, **`⟨RULING⟩` S-1**.

---

## SELF-355 — P3. §2.6.2.b commentary editor UI

> **Baseline.** `b90b846`. Unblocked once A1 lands.
>
> **AC.**
> 1. **Four plain text areas** at `/reports/monthly/{target_month}/commentary`. **Headings (PM), verbatim: Cash · Bonds · Marketable Securities · Alternatives.** ⚠ The drafted *"Equity"* predates the 2026-08-19 ratify (PM **D-3** · Sec **D-4** · Arch F-3). **Product phrase governs the heading; the schema identifier governs the column** — PM D-3's rule.
>    - Sub-heading under each (PM): *"Keyed to this month's $ ReAlloc for {Cat} — shown at right."*
> 2. **Copy-from-prior-month affordance — a V1 PRD commitment, absent from the draft** (PM §2 P3 · Arch F-9). Copy (PM): per-sub-section *"Copy from {prior Month}"*; global *"Copy all from {prior Month}"*. Empty prior month → affordance disabled with *"No {prior Month} commentary to copy."*
> 3. **`$ ReAlloc` side-by-side reference rendering — the second missing V1 commitment** (PM §2 P3). PRD: *"the V1 PRD commitment is that the $ ReAlloc reference data is visible alongside the editor during authoring"*; the **layout shape** (modal / inline panel / linked / dual-pane) is Architect's and is **not** a PRD commitment. Read-only; the authoring path never writes back to §2.2.2.
> 4. Blank by default; **no auto-pre-population** (PRD, deliberately — stale commentary must not leak forward). Editor note (PM): *"Plain text. Line breaks are kept; formatting is not."* Actions (PM): *"Save draft"* · *"Finalize {Month YYYY}"*.
> 5. **Write semantics.** Replace-all per the Lock 14 pattern. ⚠ **"SERIALIZABLE" is not reachable from this transport** — PostgREST runs each call as its own transaction and `SET TRANSACTION ISOLATION LEVEL` cannot be issued inside a function body. Follow the ratified realization at [ADR-011 Decision 18's 2026-09-03 amendment](DECISIONS.md#adr-011) / `101`: one SECURITY INVOKER plpgsql body whose **first statement takes a `FOR UPDATE` row lock**, which is also the tenant fence. **No tenant parameter** — `users_id` from `auth.uid()`.
>    - ⚠ **This write targets a Lock 11 row and therefore runs inside the draft window only** (PM **D-6**); its interaction with the immutability trigger follows `⟨RULING⟩` Sec R-1.
> 6. Lock 14 hardening via the SELF-233 shared layer: Zod `.strict()`, mass-assignment prevention (`users_id` from `auth.uid()`). **The adversarial battery is the TEXT variant** — control characters, length bounds, encoding; the numeric battery does not apply.
> 7. Plain text only; line breaks preserved; **no markdown rendering**. ⚠ INV-1 makes plain-text-only **security-load-bearing**, so a future markdown affordance is a Sec re-touch, not a refinement (Sec **M-2**, which asks that this sentence be kept).
> 8. Empty sub-sections are legitimate and render with their label and an empty body (PRD §2.6.2 verbatim) — **no sub-section is hidden** (PM §3).
> 9. **Canonical test label: RT-11** — SECURITY §4.1 axis iv, *"the §2.6.2 commentary write path (RT-11)"* (Sec **D-3**).
>
> **Dependencies.** Upstream: A1. Downstream: P4.

---

## SELF-356 — P4. §2.6.2.c author-before-generate trigger

> **Baseline.** `b90b846`. ⚠ Sec §6 counts this **buildable as drafted**; PM §2 and Arch F-8 both find it contradicts the PRD. The three predicates differ — `architect-findings.md` §8.2. Sec §5 states explicitly that P4's gating *"is not a security control and I do not treat it as one"*, which is why it can be clean on Sec's predicate and not on the other two.
>
> **AC.**
> 1. **The gate is complete-**or-explicitly-skip**, not commentary-present.** PRD §2.6.3: *"completes (or explicitly skips) authoring"*; §2.6.2: empty sub-sections render as empty. **Skip is a V1 affordance; blocking removes it** (PM §2 P4).
> 2. **The notification is in-app, not Discord.** PRD §2.6.3: cron fire moves the month to **pending**, surfaced through *"an in-app notification + pending-monthly-report queue affordance (parallel to §2.4.1's iv-1)"*. Discord is the operator channel (Gate F), not the user's notification (PM §2 P4 · Arch F-8).
> 3. **Copy (PM), folded verbatim:**
>    - Pending item in the queue: *"{Month YYYY} — awaiting your Rebalancing Targets commentary."* CTA: *"Write commentary"* · secondary: *"Skip commentary and finalize"*.
>    - Skip confirmation: *"Finalize {Month YYYY} without commentary? The Rebalancing Targets section will show its four headings with empty bodies. You can regenerate this month later."*
> 4. **The pending view surfaces the no-ledger-designated prompt** (PM §10): *"No IRS/FTB ledger designated — NAV on this report will exclude tax liabilities"*, with the Settings/accounts link, **before finalize**. Not a block (α′-1 spirit); a prompt. This is the one moment to catch a state that otherwise freezes into that month's report and its PDF forever.
> 5. **A durable authored-vs-skipped fact is written** (A1 item 9). PM §6's V1.final N=2 gate depends on it, and *"a skip must be distinguishable from four empty strings."*
> 6. State transition: cron writes `draft` → complete-or-skip promotes to `final` → regeneration supersedes.
>
> **Dependencies.** Upstream: P3, P5, A7, A1.

---

## SELF-357 — P5. §2.6.3.b on-demand UI + pending queue

> **Baseline.** `b90b846`. Depends on A1/A3 and therefore on `⟨RULING⟩` S-1.
>
> **AC.**
> 1. **Report listing surface** — a V1 PRD surface no issue carried (PM §7 item 2(i)). Lists prior generated reports; **indefinite retention, no user deletion at V1**. Empty state (PM): *"No monthly reports yet. Your first report is generated on the 1st of next month, or generate one now."* CTA: *"Generate monthly report"*.
> 2. **Pending queue** — the in-app half of P4 item 2. ⚠ **"Pending" means awaiting authoring, not a job state** (PM §2 P5): strike *"queued/in-flight/done"*; *"generation failed"* in-app notification is **V2+ by §2.6.3's own list**.
>    - ⚠ **Tenant-scope the queue read at the DB layer** (Sec **F-8**) — a queue leaks existence (row counts, timing, target months) even when it leaks no values. The natural implementation (read `monthly_report` under RLS) is scoped by construction; **Sec wants it asserted, not redesigned**, with a P10 leg proving tenant A sees zero of tenant B's entries.
> 3. **Target-month selection** (PM): default = prior month; current month labelled *"{Month YYYY} (in progress — as of today)"*.
> 4. Regeneration entry (PM): *"Regenerate {Month YYYY}? The current report is replaced; your existing commentary is loaded into the editor to edit or keep."*
> 5. ⚠ **The on-demand generation WRITE path is not this issue's.** A3 is a **read** helper; generation is a Lock 11 **write** with a server-derived `data_as_of`, and A7 is cron-only — so no issue owns it (PM §7 item 2(ii)). **Architect's position: a new A-item, not a fold into P5 — `architect-findings.md` §8.5.** P5 calls it; P5 does not implement it.
> 6. `p_data_as_of` is **server-derived** on this path too — Lock 15's server-derived-only fence covers §2.6 cron **and** on-demand; §2.3.3 drill-down is the only surface where a client toggle is legitimate. **RT-25** (Sec D-3).
> 7. Reuses Lock 11 INSERT-new-version on regeneration.
>
> **Dependencies.** Upstream: A1, A3, P4, **`⟨RULING⟩` S-1**, and the on-demand write path (item 5). Downstream: P6.

---

## SELF-358 — P6. §2.6.3.c PDF export

> **Baseline.** `b90b846`. **⚠ BLOCKED ON `⟨RULING⟩` S-2** (= PM D-7 / Sec F-5).
>
> **AC.**
> 1. ⚠ **The drafted browser→A5 JSON-payload-plus-JWT shape is struck.** It inverts ARCH §3.2 and puts the worker credential's trust boundary in the browser; PM D-7's product half: *the user's click lands on a user-session route; the worker credential never reaches the browser*. Re-draft after S-2.
> 2. "Download PDF" affordance on the P2 report page. Copy (PM): *"Download PDF"*; **available only from a generated-state report** — disabled on a pending one with tooltip *"Finalize this report to export it."* (PM §2 P6 flags the no-PDF-of-pending rule as missing from the draft.)
> 3. **One HTML template, shared with P2** — under S-2 Option A or C this is structural rather than a discipline, and it is what discharges the escaping obligation.
> 4. The PDF is a **transient export, not persisted server-side** (PRD §2.6.3 verbatim; the server-side artifact is the §2.6.4 snapshot). ⚠ Sec **M-6** is an explicit non-objection *with a standing condition*: **the first AC that persists a rendered PDF creates a new storage-class surface and is Sec-joint-review-mandatory at that PR.**
> 5. **Filename convention (PM §12.5), resolved:** keep the draft's `mosko-monthly-{YYYY-MM}-{generated_at}.pdf`. ⚠ **Never the owner string in the filename** — *"a PDF name travels further than its contents"* (PM). This is the last round-1 `⟨PM⟩` placeholder in the file; **no copy strings remain owed.**
> 6. **PDF staleness markers are read live at export**, not from the snapshot (PRD §2.6.4 carve-out; PM §2 P6 · Sec M-4).
> 7. **Escaping control home = `⟨RULING⟩` Sec R-5, and it follows S-2** — see A4 item 5 and `architect-findings.md` §8.4. PM homes it on A4, Sec leans folding it here; **Architect's position is that neither is unconditionally right.**
>
> **Dependencies.** Upstream: A4, A5, P2, **`⟨RULING⟩` S-2**.

---

## SELF-359 — P7. §2.6.4.b owner-identification Settings editor

> **Baseline.** `b90b846`. **Unblocked. Recommended first dispatch with A8.**
>
> **AC.**
> 1. Settings route `/settings/owner-id`, extending the SELF-242 shell, beside the shipped `/settings/{allocation,cash-flow-targets,tax-brackets,security}`. Single TEXT input.
> 2. **Copy (PM), folded verbatim:** page title *"Report header"*; field label *"Owner identification"*; helper *"Appears at the top of every monthly report generated after you save. Plain text, one line, up to {N} characters. Example: THE ⟨NAME⟩ 2023 TRUST."* — N per the A8 length bound (PM proposes 120). Empty state: *"No header set — reports show no owner line until you add one."*
> 3. Replace-all write to A8 via the SELF-233 hardening shared layer: Zod `.strict()`, mass-assignment prevention, the **TEXT-variant** adversarial battery. A single-row UPSERT through PostgREST needs no lock; if routed through an RPC, the P3 item 5 note applies.
> 4. **The editor says so** (PM **§12.4/§12.5**, resolving the round-1 placeholder): a rename applies **forward only**, and P7 renders, at the editor, *"Reports already generated keep the header they were generated with."* (PRD §2.6.4; PM §5; Sec **M-1**.)
> 5. **Canonical test label: RT-12** (Sec **D-3**), absent from the drafted AC.
> 6. Closes the Settings ramp at 4/4 (SELF-242 V1.2 + SELF-252 V1.3 + SELF-265 V1.4 + this).
> 7. **QA:** one leg proving a rename leaves a prior `final` report's header unchanged (PM §5) — it belongs in P10, and is listed there.
>
> **Dependencies.** Upstream: A8, SELF-233, SELF-242.

---

## SELF-360 — P8. §2.6.5 staleness markers on §2.6 surfaces

> **Baseline.** `b90b846`. **Depends on `⟨RULING⟩` S-4.**
>
> **AC.**
> 1. **α′-1 generate-with-markers, not block.** Cron generates regardless of staleness.
> 2. ⚠ **Markers are computed LIVE at every render and every export — never frozen at generation.** The drafted *"at generation time"* inverts PRD §2.6.4's explicit live-read carve-out (PM §4, which calls this *"the load-bearing defect"* · Sec **M-4**, which names the direction: *a report generated while every item was healthy, viewed a month later when an item is pending re-auth, shows no badge* — the §2.4.4 headline commitment inverted). **The snapshot carries no markers.**
> 3. **Both halves are required** and PRD §2.6.5 rejects either alone: per-section inline markers **and** a report-level banner naming stale accounts. ⚠ α′-3 banner-only is a named rejected alternative — not a valid V1.5 reduction. The banner is PM §7 item 2(v)'s uncarried surface, folded here.
> 4. **The banner is served by the shipped primitive; the per-section half is not.** `pfin.fn_aggregation_has_stale_constituent()` (`046`/`059`) takes **zero arguments** and returns **one aggregate row for the calling user**. `⟨RULING⟩` **S-4** decides the attribution route: reuse the shipped V1.3 per-row shape (`api/src/lib/cashflow-row-staleness.ts`, `CashflowRowStaleTag.svelte`) or extend the DB primitive. ⚠ A scope-typed argument is **not** available — `pfin.scope` is not a type.
> 5. **The informational tier is a second, distinct signal** (PM §2 P8, §2.4.4's second staleness source): a carried reference-series value marks affected sections **per-section only and never enters the banner**, which names stale-contributing *accounts*. Copy (PM): per-section badge reuses `<StaleConstituentBadge>`; informational tier reuses `<InformationalMarkerBadge>`.
> 6. **Two exclusions:** §2.6.2 commentary and the §2.6.4 owner header are **not** marked — not account-derived (PRD §2.6.5).
> 7. **Banner copy (PM), folded verbatim** — and note it carries the live-vs-generation distinction in the string itself: *"These accounts are currently in re-auth state; sections sourced from them are marked stale as of today, not as of {Month YYYY}: {account list}."*
> 8. Extends SELF-208 / 229 / 243 / 258 per ADR-013 D1.
>
> **Dependencies.** Upstream: SELF-208, A3, **`⟨RULING⟩` S-4**.

---

## SELF-361 — P9. §2.5.x staleness ramp

> **Baseline.** `b90b846`. **Unblocked.** Sec §5 requires no Sec review of it and calls it light-loop-eligible; PM §2 finds one leg already shipped.
>
> **AC.**
> 1. ⚠ **Retitle to two surfaces, not three.** The **NAV-composition leg is already shipped** — `NavCompositionTable.svelte` carries the aggregation badge and per-row leaf staleness from the SELF-229 ramp, and `105` reused the same payload (PM §2 P9). The `taxes/decomposition` and `taxes/quarterly` routes carry **no** `StaleConstituentBadge`; **those two legs stand.**
> 2. Consumes `pfin.fn_aggregation_has_stale_constituent()` — zero-argument signature, verified (PM **D-10** confirms the identifier).
> 3. ⚠ **The §2.5 surfaces carry a second, non-Plaid degraded state that must NOT merge into the stale badge:** the `{status:'unavailable', reason:…}` envelopes and the `basis_year` fallback (ADR-067 Decision 5). *"No ledger designated"* and *"your brokerage needs re-auth"* are different facts with different user actions. State the separation in the AC so a future consolidation cannot collapse them.
>    - **No new copy is owed here** (PM **§12.5**): both registers are already shipped — `reasonCopy()` for the envelopes, `<StaleConstituentBadge>` for staleness. **State the separation by pointing at the two shipped components**, not by writing strings. The round-1 *"`⟨PM⟩` copy for both"* is withdrawn.
> 4. **Sequence after SELF-364's PRD PR** (PM §4): 364 amends the §2.5.3 copy this issue's per-row copy sits beside; dispatching P9 first writes copy against text about to change. **364 and P9 do not overlap in substance** — 364 builds nothing.
>
> **Dependencies.** Upstream: SELF-208, SELF-264, SELF-266, SELF-268 — all shipped. Sequencing: after SELF-364's PRD PR.

---

## SELF-362 — P10. §2.6.6 RLS verification battery (V1.5 close-gate)

> **Baseline.** `b90b846`. Last. Inherits every ruling.
>
> **AC.**
> 1. Two-tenant coverage of A1 + A2 + A3 + A5 + A7 + A8 + P3 write path: cross-tenant injection rejected on each.
> 2. **aal2 legs are SEPARATE legs from cross-tenant legs** on A1, A2 and A8 (Sec **F-9**): a totp/passkey-enrolled caller presenting a below-aal2 JWT lands on the refusal leg. ⚠ A battery testing only cross-tenant **passes with the aal2 clause absent.**
> 3. A3 cross-tenant leak analysis — a foreign caller gets the **empty/unavailable shape**, i.e. fails closed *into a shape that says so*. ⚠ That argument covers only callers subject to RLS: assert as a catalog fact that **no `rolbypassrls` role holds EXECUTE** on A3. Plus Sec **F-4**'s worker leg **with its positive control**.
> 4. ⚠ **Tri-axis is CONDITIONAL in the PRD and must be built conditionally** (Sec **M-3**, which quotes §2.6.6 verbatim): tri-axis `tenant × scope × tax_treatment` **where the underlying classes carry tax-treatment**; for §2.6.1 surfaces with no tax-treatment dimension it **collapses to `tenant × scope`**. The drafted unconditional form puts a `tax_treatment` axis over surfaces with no such dimension — **legs that cannot fail, which is the tell.** The split is stated per-leg with the PRD condition quoted, so a future reader cannot "fix" the asymmetry into uniformity.
>    - ⚠ Both non-tenant axes are `text not null` columns on `pfin.account` (`003`); `scope` is a free-text ADR-004 label, **not** an enum or a type. Include a leg proving both are **orthogonal to tenancy**: a matching `scope` string across two tenants must not leak.
> 5. **SD-12 child sub-class addendum; NOT a new SD class** (Sec M-3 and Sec §5 both confirm).
> 6. A7 cron tenant-binding isolation, including a leg that would catch the **singular-GUC** failure (one tenant's data served for every tenant) — no app-layer symptom, so only a DB-side leg sees it.
> 7. A5 endpoint JWT tenant-binding — shape depends on `⟨RULING⟩` S-2 / S-3.
> 8. **Added legs (PM §2 P10 + Sec F-8 + PM §5):** superseded rows invisible to every read path · `owner_header_at_generation` frozen (a Settings rename does not change a prior `final` report) · the on-demand write path's server-derived `data_as_of` (**RT-25**) · the pending queue tenant-scoped (tenant A sees zero of tenant B's entries) · **regenerate one month three times, asserting three rows with exactly one `final`** (Sec **D-5** — a two-regeneration leg passes against the defective constraint and is the leg most likely to be written).
> 9. **Canonical labels named per surface** — RT-11 / RT-12 / RT-19 / RT-20 / RT-21 / RT-25 (Sec **D-3**). ⚠ Sec notes this battery's coverage list is *"the natural place to catch the omissions in one pass"*; a false-composite label (A2's RT-21-for-RT-20) is invisible precisely because the RT-21 battery **will** exist and **will** be green.
> 10. ⚠ Battery hygiene: pgTAP `isnt()` **passes on NULL**, so a negative assertion over a subquery is fail-open — use `ok()` and prove three states. Verify with `pg_prove`, never bare `psql` (exits 0 on a failed plan). Rebuild the scratch DB before any full-suite claim — `rollback` does not reset sequences.
> 11. **V1.5 close-gate:** no V1.5 issue closes until this passes. Sec verdict recorded per the SELF-269 precedent.
>
> **Dependencies.** Upstream: all V1.5 issues, all rulings.

---

## Proposed new issue — A10. On-demand monthly-report generation write path

> **Baseline.** `b90b846`. **Proposed, not drafted-and-promoted** — `⟨RULING⟩` PM §7 item 2 disposition; Architect's position and its losing side are at `architect-findings.md` §8.5, where the recommendation is one new A-item rather than a fold into P5.
>
> **Why it is not P5's.** A3 is a **read** helper. Generating a report is a **write** — a Lock 11 row with a server-derived `data_as_of` — and A7 owns only the cron path. Folding it into P5 puts a Lock 11 write path with an **RT-25** obligation inside a SvelteKit UI issue whose reviewer is Frontend and whose gate is not `sec-joint-review`.
>
> **AC sketch.** App endpoint under the **user's own session** (the session is the tenant binding, which is why this path does not inherit S-3). Server-derives `p_data_as_of` — never client-asserted (Lock 15; **RT-25**). Writes the `draft` row per Lock 11 INSERT-new-version; refuses to finalize until P4's complete-or-skip. Emits the same per-generation audit row as A7 item 5, with **trigger source = on-demand**. `sec-joint-review` label; **QA** legs listed at P10 item 8.
>
> **Dependencies.** Upstream: A1, A3, **`⟨RULING⟩` S-1**. Downstream: P5, P4.

---

## Not in this wave

**SELF-365 (P11, V1.final), SELF-363 (CA 2026 seed), SELF-364 (PRD §2.5.3 amendments), SELF-326 (volatility pin)** carry no V1.5 milestone and none blocks a V1.5 issue.

- **SELF-326** is context for A3 item 7. When it lands, pin by `ALTER` — a `DROP`+`CREATE` destroys grants (`072`), and `CREATE OR REPLACE` silently resets volatility, so the pin must be re-asserted per signature.
- **SELF-364** settles the installment-count definition A3 renders; `104` already implements the ratified reading, so the PRD is catching up to the code. **PM §4 sequences its PRD PR before P9's dispatch.**
- **SELF-365** is measurable only if V1.5 ships the facts PM §6 enumerates: the per-generation audit row with trigger source and `data_as_of` (**A7 item 5**), the durable authored-vs-skipped fact (**A1 item 9**), `generated_at` on the final row, and the recorded battery verdict. `⟨RULING⟩` PM §6 — does an explicitly-skipped month count toward N=2? **PM leans no.** Architect has no independent position; the schema obligation is the same either way, which is why A1 item 9 is stated without waiting for the ruling.

---

## Observations booked out of this pass (no V1.5 issue)

1. **Two dated `comment on` texts read as live state** and are falsified by ADR-011 Decision 3 read at this sha: `059`'s stale-constituent comment and `054`'s trigger comment both state old family tallies. `104`/`105` already state the corrected convention, so the generator is fixed going forward. **Not proposing a comment-only migration in V1.5** — team-lead's to book (Arch F-14).
2. **`BACKLOG.md` §7.1 line 300 carries the vetoed `SUPABASE_URL` text** (Sec **D-1**) — the defect is in the promotion source. **Not touched by this pass**; it lands in the close-out PR after the sitting.
3. **PM's §9 ADR consolidation** — Gates A, B and F each changed a locked shape and wrote only to a downstream register, which Decision 18's own amendment names as the failure mode (*"a Gate ratify that changes a LOCKED ENUMERATION must amend the ADR holding it"*). PM recommends one consolidated ADR riding **A1's implementing PR**. **Architect concurs and will author it** — it is the natural home for the S-1 ruling, the Lock 12 widening (F-7), the Gate F mechanism rider, and the `generation_status` bridge, so the sitting's rulings land in the register rather than in ACs.
