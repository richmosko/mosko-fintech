# V1.5 re-derived ACs — Architect (round 1)

Landing-ready replacement AC text, one block per issue, for paste into Linear after the sitting. **Each block self-carries its baseline sha.** `⟨RULING⟩` marks a seam that must be ruled before the block is final; `⟨PM⟩` marks user-facing copy Architect does not draft (round 2). `⟨SEC⟩` marks a finding id Sec will supply in round 2.

Seam ids (`S-n`) and finding ids (`F-n`) refer to `architect-findings.md` in this directory. Where a block's Source line is corrected, the correction is called out so the edit is not read as drift.

---

## SELF-345 — A1. `pfin.monthly_report` header table (Lock 11)

> **Baseline.** `b90b846` (2026-09-04). Every identifier below verified against the tree at this sha.
>
> **Source.** [ADR-011 Decision 15 / Lock 11](DECISIONS.md#adr-011) verbatim; [PRD §2.6.1](docs/PRD/index.html#story-2-6-1) header + [§2.6.2](docs/PRD/index.html#story-2-6-2) commentary persistence per Wave 6 Gate B Option C (4 named TEXT columns on the header table; no JSONB commentary blob per the Lock 14 forward-compat fence; PRD §2.6.2's fixed four sub-sections). ⚠ *Source corrected:* the sub-section labels are **Cash / Bonds / Marketable Securities / Alternatives** per PRD §2.6.2 verbatim, F/CTO-ratified 2026-08-19 following the [ADR-058](DECISIONS.md#adr-058) Decision 7 Cat rename shipped at migration `082`. "Equity" is the pre-rename label (F-3).
>
> **⚠ BLOCKED ON `⟨RULING⟩` S-1** — whether a `final` report stores its rendered payload or is recomposed at read time. The column list below is complete under either answer **except** the payload column, which S-1 Option A adds.
>
> **AC.**
> 1. **Table** `pfin.monthly_report`: `users_id UUID NOT NULL` (direct owner anchor) · `target_month DATE NOT NULL` · `generation_status` with the Lock 11 vocabulary `draft` / `final` / `superseded` · `data_as_of DATE NOT NULL` · `generated_at TIMESTAMPTZ` · `owner_header_at_generation TEXT` · four commentary columns `commentary_cash`, `commentary_bonds`, `commentary_marketable_securities`, `commentary_alternatives` (all `TEXT`) · `created_at` · `updated_at`.
>    - `owner_header_at_generation` is **required, not optional**: [PRD §2.6.4](docs/PRD/index.html#story-2-6-4) verbatim — *"when a historical report renders … the owner-identification header reads from the snapshot, not live from the settings store."* Lock 11 mod #2 names this column and `included_reconciliation_event_ids` as the two whose history a hard-overwrite UPDATE would destroy (F-2).
> 2. **`included_reconciliation_event_ids INTEGER[]`** — `⟨RULING⟩` **S-5**: ship now with a dormant fence, or defer to V1.6. If it ships, it carries the Lock 11 mod #9 matched-tenant array-element BEFORE INSERT/UPDATE trigger, and the migration header states in terms that **`pfin.reconciliation_event` has no writer at this sha**, so the fence is correct, mandatory and **dormant**, with the revival condition named (the V1.6 statement control tie-out successor recorded at [ADR-035](DECISIONS.md#adr-035)).
> 3. **Uniqueness — partial index, per Lock 11 verbatim:** `UNIQUE (users_id, target_month) WHERE generation_status = 'final'`. ⚠ **Not** `UNIQUE(users_id, target_month, generation_status)`: the three-column form additionally forbids a second `superseded` row for one (user, month), which is what INSERT-new-version regeneration produces on its second use — it breaks the mechanism this AC mandates (F-1).
> 4. **[ADR-011 Decision 3](DECISIONS.md#adr-011) — realizes an existing label; allocates none.** Read Decision 3's body live at authoring. ⚠ The instance on this table is the **`INTEGER[]` column**, not `users_id`: a direct `users_id = auth.uid()` anchor is explicitly **not** a Decision 3 instance (`007` and `015` both state this). Locks 11 and 12 name this table's and A2's labels in their own text and the family entries are already allocated and DDL-deferred — **do not allocate a new label** (F-6). **No count is stated in this AC, in the migration, or in any `comment on`.**
> 5. **Decision 2, both halves.** The header is **INSERT-new-version** on regeneration (Lock 11 mod #2); a row that has reached `final` is **immutable** thereafter. Supersession runs through `⟨RULING⟩` S-1's chosen mechanism — if a SECURITY DEFINER `fn_supersede_monthly_report` is proposed it routes to Sec joint-review and must justify itself against Lock 11's own SECURITY INVOKER default ([ADR-011 Decision 9](DECISIONS.md#adr-011) allowlist read live).
> 6. **Immutability fence must cover the tenant anchor itself**, per Lock 12's Sec catch: `users_id` and `target_month` are UPDATE-fenced post-creation (a parent re-tenant orphans A2's child rows from their original tenant).
> 7. **RLS** per the `090` policy standard: USING **and** WITH CHECK stated per verb; `users_id = auth.uid()`; the [ADR-029](DECISIONS.md#adr-029) / `025` **aal2 step-up backstop clause** ANDed into the `authenticated` read and write policies (new sensitive tenant-owned `pfin` table; none of the three documented exclusions applies); grants enumerated explicitly.
> 8. `updated_at` refresh via the existing `pfin.fn_refresh_updated_at()` (verified present at this sha).
> 9. **Status vocabulary mapping** is stated once, against the transition rather than the enum: cron writes `draft`; completing **or explicitly skipping** authoring promotes to `final` (PRD §2.6.3 verbatim — see SELF-356); regeneration supersedes. `⟨PM⟩` presentation labels.
> 10. **Sec joint-review mandatory.** **QA:** two-tenant pgTAP battery pairs in the same PR.
>
> **Dependencies.** Upstream: SELF-232 (`fn_refresh_updated_at`), SELF-233 (settings write-path hardening), **`⟨RULING⟩` S-1**. Downstream: A2, A3, A7, P2, P3.

---

## SELF-346 — A2. `pfin.monthly_report_account_snapshot` child table (Lock 12)

> **Baseline.** `b90b846`.
>
> **Source.** [ADR-011 Decision 16 / Lock 12](DECISIONS.md#adr-011) verbatim; [PRD §2.6.4](docs/PRD/index.html#story-2-6-4) snapshot + historical retention.
>
> **⚠ BLOCKED ON `⟨RULING⟩` S-1.** This table's column set is the S-1 decision made concrete. Lock 12 locks three columns — `(monthly_report_id, account_id, acct_name_at_generation)`. Under S-1 Option A this table widens to carry per-account frozen values, which is a **Lock 12 amendment requiring F/CTO ratify + Sec joint-review**, not an implementation detail (F-7).
>
> **AC.**
> 1. Child table `pfin.monthly_report_account_snapshot`, FK to `pfin.monthly_report` **ON DELETE RESTRICT** (Lock 12 verbatim — not CASCADE).
> 2. Columns: Lock 12's locked three, **plus** whatever S-1 rules. ⚠ **`scope` is not available as a typed column**: `pfin.scope` does not exist as a type at this sha; `pfin.account.scope` is `text not null`, a free-text [ADR-004](DECISIONS.md#adr-004) Decision B label (`105` records the identical finding). `pfin.account.tax_treatment` **is** real (`003`, `text not null`, three-value CHECK). If either is carried it is carried as a copy of the account's value at generation time, named as such.
> 3. **Decision 3 — realizes the existing label on `account_id`; allocates none** (F-6). Read Decision 3 live at authoring; state no count anywhere.
> 4. **Lock 12's three V1-SHIP-BLOCK mods, in full:** (i) matched-tenant trigger on `account_id`; (ii) parent `users_id` + `target_month` immutability fence (lives on A1, per that block's item 6, and is verified from this side); (iii) `service_role` bypass DB-trigger on the child table.
> 5. **RLS via the parent FK chain** (`090` policy standard; USING + WITH CHECK per verb; aal2 clause). ⚠ The join to the parent must key on the **surrogate `monthly_report_id`**, never on a `(users_id, target_month)` text/value pair: a surrogate-id join fails **closed** under an RLS regression, a shared-vocabulary join fails **open**.
> 6. Read-only post-write (Decision 2 immutable half).
> 7. **Sec joint-review mandatory.** RT-21 HIGH + the SD-12 child sub-class addendum. **QA:** two-tenant battery same PR; the derivative-surface leg is P10's.
>
> **Dependencies.** Upstream: A1, **`⟨RULING⟩` S-1**, SELF-214 (`nav_daily`), SELF-201. Downstream: A3, A7.

---

## SELF-347 — A3. SECURITY INVOKER read-composition helper

> **Baseline.** `b90b846`.
>
> **Source.** [ADR-011 Decision 15 / Lock 11](DECISIONS.md#adr-011) SECURITY INVOKER read-composition pattern; Gate A Option B unified. ⚠ *Source note:* Lock 11's own read-time join list names `pfin.nav`, **which does not exist at this sha** — the live substrate is `pfin.nav_daily` plus `fn_compute_nav` / `fn_nav_composition`. Lock 11 predates the GL and tax substrate ([BACKLOG.md](BACKLOG.md) §7.19).
>
> **⚠ BLOCKED ON `⟨RULING⟩` S-1** — this helper composes; whether its output is *stored* is S-1's subject.
>
> **AC.**
> 1. **Signature: `pfin.fn_render_monthly_report(p_target_month DATE, p_data_as_of DATE) RETURNS JSONB`.** ⚠ **No `p_users_id` parameter.** Under SECURITY INVOKER, RLS already scopes to `auth.uid()`; a tenant parameter either does nothing or, ANDed into the predicate, returns **empty rather than an error** when a caller passes another tenant's id — a wrong question answered as "no data". The tree has ruled this twice: `105` (*"p_users_id DROPPED (INVOKER + RLS scope by auth.uid())"*) and `101` (*"takes NO tenant parameter … R4 rider 4 / Sec D-2"*).
> 2. **Composes the six PRD §2.6.1 sections in that verbatim order**, over the live substrate at this sha: Account Holdings ← `pfin.fn_nav_composition` (`105`); NAV Performance ← §2.1.2/§2.1.3/§2.1.4 readers; Asset Allocation ← `fn_subcat_market_value` (`076`/`081`) + `planning_target` (`074`); Rebalancing Targets ← A1's four commentary columns; Cash Flow ← `fn_cashflow_items` / `fn_cashflow_cross` / `fn_historical_expenditures` (`093`/`096`); Estimated Taxes ← `pfin.fn_compute_tax_liability` (`104`).
> 3. **§2.5.4's two NAV-component values render on Account Holdings via the §2.1.5 buildup, NOT as Estimated Taxes rows** (PRD §2.6.1 verbatim).
> 4. **The tax payload's envelopes cross into the report unflattened.** `fn_compute_tax_liability` returns `{status, amount}` / `{status, reason}` objects for every genuinely-unknowable figure, and `105` carries them **verbatim** into `nav_components` ([ADR-067](DECISIONS.md#adr-067) Decision 5 — the type does the work, not consumer discipline). This helper **must not** coalesce, zero-fill or currency-format them. `reason` is a stable machine code. **The `unavailable` case is the bootstrap default, not an edge case** — no ledger is designated at signup — so the report must render unavailable-with-reason, never `$0`. Same rule for `basis_year` and `current_year_schedule_empty`: carried, not dropped.
> 5. **ONE CALL, ONE CLOCK.** `p_data_as_of` is threaded **unchanged** into every callee; nothing inside derives its own date; the caller passes the same `fn_server_today()` value to every as-of read on the request (Lock 15; R3 rider 4). The payload echoes `as_of` back so a consumer can prove the threading.
> 6. **Posture, per the `104`/`105` precedent:** `security invoker` · `set search_path = ''` · **volatility `stable`, declared in the body per signature** because `CREATE OR REPLACE` resets it · EXECUTE granted to `authenticated`, **never to a `rolbypassrls` role** — for a DEFINER or bypass-RLS caller the EXECUTE grant is the entire perimeter rather than the weakest fence, and the standing condition on `104`/`105` (any such grant is Sec-joint-review-mandatory) is inherited here.
> 7. ⚠ **Known transitive volatility gap, inherited not introduced:** `fn_gl_entries` and `fn_holdings_as_of` are `provolatile = 'v'` at this sha (SELF-326 open). Name it in the header; do not silently claim a fully-pinned read set.
> 8. **Entry paths.** In-app SSR (P2) and historical-month view are direct INVOKER calls under the user's session. The **PDF path's** caller identity is `⟨RULING⟩` **S-2/S-3** and must not be assumed here.
> 9. **Sec joint-review mandatory** (financial calculation + multi-tenant + cross-tenant leak-surface analysis). **QA:** cross-tenant leg proving a foreign caller gets the empty/unavailable shape — fails closed *into a shape that says so*.
>
> **Dependencies.** Upstream: A1, A2, **`⟨RULING⟩` S-1**, SELF-262, SELF-268, and the Wave 1–5 NAV / allocation / cashflow / tax substrate. Downstream: P2, P5, P6, A7.

---

## SELF-348 — A4. Node PDF worker container (extend, not scaffold)

> **Baseline.** `b90b846`.
>
> **Source.** [ADR-011 Decision 17 / Lock 13](DECISIONS.md#adr-011); Gate C V1.x Platform scope.
>
> **⚠ NOT GREENFIELD.** `workers/pdf-render/Dockerfile` and `workers/pdf-render/.env.example` exist at this sha (landed at `eada4b2`), deliberately, as a placeholder *"shipped so the RT-22 fence has a real target to audit"* — its own header says so. **This issue extends that file.** Every commit to it is already gated by the live RT-22 CI fence.
>
> **⚠ BLOCKED ON `⟨RULING⟩` S-2** — what crosses to this container, and in which direction. ARCH §3.2's sequence diagram has the **worker pulling rendered HTML from the app** (`PW->>V1: GET /internal/pdf-render`; `V1-->>PW: Rendered HTML`); the prior draft had the app pushing a JSON payload to the worker. The direction changes what this container must contain (F-2 / S-2).
>
> **AC.**
> 1. Extend the existing Dockerfile with Puppeteer + system Chromium deps. **Do not restructure the `ENV`/`ARG` block** — `scripts/ci/fence-rt22-pdf-worker-dockerfile.sh` keys criterion (i) on `^\s*(ENV|ARG)\s+SUPABASE_`.
> 2. **Zero-DB-isolation, unchanged (Lock 13 mod #2):** **no `SUPABASE_*` env vars at all** — ⚠ *there is no `SUPABASE_URL` carve-out*; the single permitted variable is `PDF_WORKER_SIGNING_KEY` per SD-20. No Postgres client. Both are enforced at PR time by the shipped fence.
> 3. Lock 13 mod #7 browser hardening: browser-context-per-render, system-fonts-only, `--disable-features=BackgroundFetch,ServiceWorker,BackgroundSync`, cache disabled, per-render PDF metadata cleared.
> 4. **Escaping of user-controlled free text** — **`⟨RULING⟩` S-2 decides whether this control is needed here at all.** Under S-2 Option A or C the worker never composes HTML and the control is discharged structurally by Svelte's default escaping. Under Option B it is **mandatory and must be tested** per [BACKLOG.md](BACKLOG.md) §7.32 item 6: store `<script>` in `pfin.tax_bracket_schedule.schedule_label` (up to 500 chars of user prose, forwarded unmodified into the tax payload) and prove the rendered output carries it inert.
> 5. No `TenantBoundConnection` fence applies — that fence is the Python ETL's, and this container holds no DB connection by design.
> 6. Deploys per the V1 greenfield posture ([ADR-021](DECISIONS.md#adr-021)); Coolify→Discord on deploy. ⚠ cax21 is **reference-only, not the V1 deploy target** — the prior draft's *"deploys on cax21 alongside `pfin_back_etl`"* is corrected.
>
> **Dependencies.** Upstream: **`⟨RULING⟩` S-2**. Downstream: A5, P6. **A6 is not downstream — its fence already exists and already audits this file.**

---

## SELF-349 — A5. `/internal/pdf-render` + the RT-21 battery

> **Baseline.** `b90b846`.
>
> **Source.** [ADR-011 Decision 17 / Lock 13](DECISIONS.md#adr-011); [ARCH §3.2](docs/ARCH/index.html) *PDF render cross-container handoff*; SECURITY §4.5 **RT-21** + SD-20.
>
> **⚠ BLOCKED ON `⟨RULING⟩` S-2 and `⟨RULING⟩` S-3.**
>
> **AC.**
> 1. **Direction and shape are S-2's subject.** ARCH §3.2 has this endpoint answering a **`GET` from the PDF worker** and returning **rendered HTML**, not accepting a JSON payload and returning PDF bytes. Do not build either shape until S-2 rules.
> 2. **The RT-21 battery is the canonical (a)–(g), read verbatim from SECURITY §4.5 — not the prior draft's list.** ⚠ The prior list shared RT-21's letters and matched only at (e); it dropped the freshness window and invented two clauses RT-21 does not contain (F-4). Canonically: **(a)** authenticated-tier JWT only — a `service_role` JWT is rejected at signature verification; **(b)** dedicated signing key — Supabase-JWT-signed tokens rejected; **(c)** **60-second freshness window** — `iat` older than 60s rejected; **(d)** single-use nonce, replay rejected; **(e)** no `service_role` escalation anywhere in the endpoint; **(f)** verification logic lives at this endpoint only; **(g)** rejected payloads dropped **with a detection signal**.
> 3. ⚠ **(g) must not be built by inheritance from RT-05.** [ADR-050](DECISIONS.md#adr-050) F3 records that RT-21(g) inherits RT-05's defect **unbuilt**, and RT-21's own body states its answer *"may legitimately differ"* — RT-05's webhook is internet-facing, this endpoint is on the private container network, so the objection that rules out row-per-event there does not transfer. It also names `pfin.plaid_sync_audit` as the storage surface, **a table dropped at `015`**. (g) needs its own design call at build time. **`⟨SEC⟩`**
> 4. **The tenant-binding mechanism is `⟨RULING⟩` S-3 and is NOT locked today.** ARCH §3.2 verbatim: *"Concrete binding mechanism (`SET LOCAL request.jwt.claims` vs parametric `WHERE users_id = $1` vs other) **is Phase 5 detail design**."* ⚠ The prior draft asserted `SET LOCAL request.jwt.claims` as *"Arch-locked … per RT-21(e)"*; **RT-21(e) is the no-escalation clause and contains no binding mechanism.** The parametric option is additionally excluded by ARCH §3.2 (*the endpoint "does not use `service_role` in V1"*) and by RT-21(e). Prior art for the impersonation shape: `workers/etl/src/pfin_back_etl/connection.py` (`SET LOCAL ROLE authenticated` + `set_config('request.jwt.claims', …, true)`), including its `request.jwt.claim.sub` singular-GUC handling.
> 5. The JWT carries a **`users_id` claim only** — no `data_as_of` claim (Lock 15 mod #7b; SD-20). The app reads the frozen as-of value server-side.
> 6. This route is a §4.1 server-source surface inside RT-26's audit scope and **holds no allowlist entry** (ARCH §3.2).
> 7. **Sec joint-review mandatory** (RT-21 HIGH). **QA:** the seven-leg battery, each leg failing for its own reason.
>
> **Dependencies.** Upstream: A4, **`⟨RULING⟩` S-2**, **`⟨RULING⟩` S-3**. Downstream: P6.

---

## SELF-350 — A6. RT-22 Dockerfile audit CI fence

> **Baseline.** `b90b846`.
>
> **⚠ RECOMMENDATION: CLOSE AS ALREADY DELIVERED. Do not build.**
>
> **Measured at this sha.** `scripts/ci/fence-rt22-pdf-worker-dockerfile.sh` exists and implements both catch criteria — (i) no `SUPABASE_*` `ENV`/`ARG`; (ii) no Postgres-client install across apt / apk / npm / yarn / pnpm / pip. `.github/workflows/security-scan.yml` runs it **twice**: production mode against `workers/pdf-render/Dockerfile`, and **inversion mode** against `tests/fixtures/ci/rt22-violation.Dockerfile` with an explicit fail-closed guard (*"FATAL: RT-22 fence reported clean against violation fixture — fence is broken; failing closed"*). Landed at `eada4b2` (*"Phase 5 Step 4 W1 — CI fences"*); documented at `scripts/ci/README.md`. The job is run-always, not path-triggered, deliberately.
>
> **Two AC clauses were wrong and must not be "fixed" into the shipped fence.**
> 1. The draft asked the fence to permit `SUPABASE_URL`. **Lock 13 mod #2, ARCH §3.2, RT-22, the Dockerfile's own header and the shipped script all say no `SUPABASE_*` at all.** The carve-out would **weaken** a shipped fence.
> 2. The draft said *"both catalogued instances now have V1 CI automation."* That is an instance-count claim, and it is falsified by [ADR-011 Decision 4](DECISIONS.md#adr-011) **read live**. No count is restated here.
>
> **Ledger effect of closing this issue: none.** Decision 4 catalogues *instances*, not automation states; RT-22 was catalogued in 2026-05 and building or closing its fence adds, removes, reorders and renumbers nothing. **Path B — reference, do not restate.** No ADR edit is owed.
>
> **Residual (a closing comment, not a build):** record the two corrections above so a future edit of the fence cannot inherit the weakened carve-out. Also note the fence's own documented non-catches (a `COPY` of a manifest; a Postgres client transitive via base image) stay human-PR-review second line per ARCH §6.1.

---

## SELF-351 — A7. monthly_report cron worker

> **Baseline.** `b90b846`.
>
> **Source.** [ADR-011 Decision 15 + Decision 17](DECISIONS.md#adr-011); Gate F Option α native Coolify cron container.
>
> **⚠ Depends on `⟨RULING⟩` S-1 (what the cron writes) and F-8 (what it does when commentary is absent).**
>
> **AC.**
> 1. Native Coolify cron container, **1st of each month, generating the prior month's report**; `p_data_as_of` = last day of the prior month, **server-derived** — no client-asserted value (Lock 15 server-derived-only fence for §2.6 paths).
> 2. **Reuse the shipped tenant-binding module; do not re-specify it.** `workers/etl/src/pfin_back_etl/connection.py` implements `TenantBoundConnection` (READ as `authenticated` via `SET LOCAL ROLE` + `set_config('request.jwt.claims', …, true)`; WRITE as `service_role` via `SET LOCAL ROLE`), and `nav_backfill.py` runs the per-tenant loop this AC describes. `service_role` is used **for tenant enumeration only**, never for report-data composition (Lock 11 mod #4).
> 3. ⚠ **Inherit the singular-GUC hazard handling.** `auth.uid()` prefers `request.jwt.claim.sub` over the plural claims blob, so a session-scoped singular GUC left set would serve **one tenant's data for every tenant, with no code bug and no app-layer assertion failure** (`054`'s comment states this; `connection.py` nulls it, N7). Any new loop reuses that handling rather than re-deriving it.
> 4. **Cron does not finalize.** Per [PRD §2.6.3](docs/PRD/index.html#story-2-6-3) verbatim, *"the cron-fired case does not bypass authoring — cron does not auto-finalize a report with empty commentary."* The cron writes a `draft` and surfaces it through the **in-app notification + pending-monthly-report queue** (P5). ⚠ The prior draft had the cron *skip generation* and notify via **Discord**; Discord is an operator channel and the PRD's affordance is in-app (F-8). Coolify→Discord stays for **operational** success/failure, not as the user's authoring notice.
> 5. Lock 13 mod #4 audit-log entry, same transaction.
> 6. **Sec joint-review mandatory** (cron tenant-binding + `service_role` isolation).
>
> **Dependencies.** Upstream: A3, **`⟨RULING⟩` S-1**, the `workers/etl` incumbent. Downstream: P2, P5, P4.

---

## SELF-352 — A8. `pfin.owner_identification` settings table

> **Baseline.** `b90b846`. **Buildable as drafted. Unblocked — recommended first dispatch of the wave (with P7).**
>
> **Source.** [ADR-011 Decision 18 / Lock 14](DECISIONS.md#adr-011) **as amended 2026-08-16 — the family is FIVE per-domain tables**, and `owner_identification` is the last unbuilt member. ⚠ *Source corrected:* the prior line quoted the locked *"four per-domain tables"* while the AC built against five. That amendment names **this very entry** as the measurement that made the divergence visible, and ratifies five. [ADR-013](DECISIONS.md#adr-013) Decision 7 (P5) — Settings 4th-of-four occupant.
>
> **Measured at this sha:** `planning_target` (`074`), `cashflow_target` (`090`), `tax_bracket_schedule` + `tax_bracket_row` (`101`) exist; `owner_identification` does not. Editors on the tree: `api/src/routes/settings/{allocation,cash-flow-targets,tax-brackets}`. So this closes the table family at 5/5 and the editor ramp at 4/4 — the tax pair is one editor, which is why the two numbers differ.
>
> **AC.**
> 1. `pfin.owner_identification`: `users_id UUID NOT NULL` · `owner_id_header_text TEXT` · `created_at` · `updated_at`; `UNIQUE (users_id)` (single row per user, per the Lock 14 per-domain pattern).
> 2. **RLS** per the `090` standard: USING + WITH CHECK per verb, `users_id = auth.uid()`, explicit grants — **plus the [ADR-029](DECISIONS.md#adr-029) / `025` aal2 step-up backstop clause on the `authenticated` policies.** ⚠ The prior draft omitted aal2. This is a new sensitive tenant-owned `pfin` table and none of the three documented exclusions applies — in particular **not** the `user_settings` exclusion, which exists only because that table is the clause's own subquery target.
> 3. Reuse `pfin.fn_refresh_updated_at()` (verified present) and the SELF-233 settings write-path hardening shared layer.
> 4. UPSERT-in-place; no edit-history rows (Lock 14: settings are not audit-class). ⚠ **Consequence to state, not discover:** because there is no history, a rename cannot be read as-of — which is exactly why [PRD §2.6.4](docs/PRD/index.html#story-2-6-4) requires the header be **snapshotted** onto A1 at generation (`owner_header_at_generation`), not read live.
> 5. **Not a Decision 3 instance** — the only reference column is the direct `users_id` owner anchor. Decision 3 is unchanged by this table and **no label may be drafted for it**: Decision 18's own amendment warns that a recorded expectation of membership *"is how a draft label gets invented and then reasoned out of existence."*
> 6. No JSONB (Lock 14 forward-compat fence).
> 7. **Sec advisory, not joint-review** (single-column user-scoped table, no chain) — as drafted. **QA:** two-tenant battery same PR.
>
> **Dependencies.** Upstream: SELF-232, SELF-233. Downstream: P7; A3 reads it for the §2.6.1 header at generation.

---

## SELF-353 — A9. NAV component-checkpoint capture substrate

> **Baseline.** `b90b846`. **Buildable as drafted; only the provenance tense needs correcting. Unblocked, and it has a clock.**
>
> **Source.** ⚠ *Corrected:* [ADR-054](DECISIONS.md#adr-054) is **Accepted (2026-08-12)** and on the tree at this sha, including Decision 5's two closures. The prior text described it as *"Architect-authored, ratifies with the same doc PR"* / *"ratifies with the ADR"* — it has already ratified. Everything the AC asserts about ADR-054's content is correct.
>
> **AC** — unchanged in substance from the drafted (1)–(7); restated only where the tense moves:
> 1. New append-only audit-class sibling table beside `pfin.nav_daily` (`054`) — explicitly **not** columns on `054` (ADR-054 Decision 2; `054`'s scalar surface is a ratified never-item).
> 2. Written by the same W-1 cron worker, in the same transaction, under the same credential model (LOGIN `pfin_etl` / WRITE `service_role` via `SET LOCAL ROLE`; `055` / [ADR-023](DECISIONS.md#adr-023) / SD-24).
> 3. **Per-account leaf granularity** (ADR-054 Decision 3, ratified): a leaf capture is retroactively re-aggregatable under any taxonomy and a pre-rolled one is not — on an append-only table that asymmetry is permanent. `051` already emits leaf values, so it adds no new computation. Stated growth commitment: row count scales with account count forever.
> 4. **Capture-only.** No UI, no chart, no sheet-history backfill, **and no V1.x read helper** — closed at ADR-054 Decision 5(1).
> 5. **[ADR-011 Decision 3](DECISIONS.md#adr-011) family member via `account_id`; matched-tenant validation in the DDL is non-negotiable.** Read Decision 3's body **live** at authoring — the family grows, labels are non-contiguous, and *labeled* vs *DDL-realized* diverge. **Carry no count.** Plus: new RLS, and the **aal2 step-up backstop clause is required** on the new table's `authenticated` policies.
> 6. **QA** two-tenant pgTAP battery same PR, carrying the **Σ(leaves) ↔ scalar-checkpoint reconciliation leg** (required — ADR-054 Decision 5(2) closed on the reconciliation form; the property is by-construction today, so the leg exists to catch it ceasing to be, which nothing else would notice).
> 7. The sheet identity is a **documented parity property, not a schema-enforced invariant** — closed at ADR-054 Decision 5(2), with the F/CTO rider recorded verbatim at the ADR. Under leaf granularity the schema carries no components to enforce over.
> 8. **Sec joint-review mandatory** — four independent triggers, enumerated at ADR-054's Governance block.
>
> **Coherence post-V1.4, checked:** [ADR-067](DECISIONS.md#adr-067) Decision 3 keeps `nav_daily` the **gross pre-tax** series permanently with no definition-version column, while `105` composes the tax-adjusted NAV at read time. A9 captures **leaves in the same cron transaction as the scalar row**, introduces no read helper, and therefore cannot drift from `105`'s definition because it never renders. That orthogonality is why A9 is safe to dispatch before S-1 is ruled — and ADR-054 Decision 6 makes its independence from the Chart-of-Accounts question structural, not merely asserted.
>
> **Dependencies.** Upstream: `054`, the W-1 cron worker, `051` — all shipped. **No V1.5 dependency.** Downstream: the V2 subcomponent visualization; the drop-replace cutover clock (every day before this lands is an unrecoverable observation gap — the reason it is V1.x, not V2).

---

## SELF-354 — P2. §2.6.1.b in-app rendering UI

> **Baseline.** `b90b846`. **⚠ BLOCKED ON `⟨RULING⟩` S-1.**
>
> **AC.**
> 1. SvelteKit page at `/reports/monthly/{target_month}`, SSR via `+page.server.ts`, rendering the six PRD §2.6.1 sections in verbatim order.
> 2. **The read path is S-1's subject.** ⚠ The prior AC asserted *"historical reports immutable post-final per Lock 11 mod #2"* alongside *"live-recompute on upstream surface changes"*. Lock 11 mod #2's immutability is a property of the **row**; **nothing in A1–A3 as drafted freezes the rendered values** that assertion is invoked to guarantee, and four of the six sections cannot be recomputed for a past month on this schema (S-1). Under S-1 Option A this page reads the frozen payload for a `final` report and composes live only for the current draft.
> 3. **Envelope rendering is mandatory, not defensive:** a `{status:'unavailable', reason:…}` object renders as unavailable-with-reason. A `?? 0` or a currency format applied to an envelope is a defect, and the object type is what makes it fail loudly ([ADR-067](DECISIONS.md#adr-067) Decision 5). Same for `basis_year` — *"California on the 2025 schedule"* — never a silent stale figure.
> 4. **Sign convention:** the buildup ladder negates debt, realized and unrealized at **one** flip site applied to three rows, so the column foots (`gross_total + Σ displayed = nav`). ⚠ A second flip anywhere renders a correct value with the wrong sign (`105`'s comment is the canonical home).
> 5. **Inline editing:** ⚠ the prior AC cited *"NO inline edit per ADR-013 P5"*. ADR-013 Decision 7 governs the four **planning values** (§2.2 `%Target`, §2.3.2 targets, §2.5.2 brackets, §2.6 owner-id header) — **commentary is not one of the four**, and PRD §2.6.3 leans the other way (the generation flow *"opens the §2.6.2 commentary editor"*). `⟨PM⟩` / `⟨RULING⟩` — a UX call, no architectural stake.
> 6. `⟨PM⟩` all user-facing copy.
>
> **Dependencies.** Upstream: A3, **`⟨RULING⟩` S-1**.

---

## SELF-355 — P3. §2.6.2.b commentary editor UI

> **Baseline.** `b90b846`. Unblocked once A1 lands.
>
> **AC.**
> 1. **Four plain text areas: Cash / Bonds / Marketable Securities / Alternatives** — PRD §2.6.2 verbatim, F/CTO-ratified 2026-08-19 following the ADR-058 Decision 7 Cat rename shipped at `082`. ⚠ "Equity" is the pre-rename label (F-3). Route `/reports/monthly/{target_month}/commentary`.
> 2. **Add the copy-from-prior-month affordance** — PRD §2.6.2 makes it an explicit V1 commitment: the editor opens **blank** (no auto-pre-population, deliberately, to prevent stale commentary leaking forward), and *"the editor surfaces an explicit 'copy from prior month' affordance the F/CTO invokes per-sub-section or globally."* ⚠ Absent from the prior AC (F-9). It makes the editor a reader of the prior month's row. `⟨PM⟩` affordance copy and placement.
> 3. Replace-all write via the Lock 14 settings write pattern. ⚠ **"SERIALIZABLE" is not reachable from this transport** — PostgREST runs each call as its own transaction and `SET TRANSACTION ISOLATION LEVEL` cannot be issued inside a function body. Follow the ratified realization at [ADR-011 Decision 18's 2026-09-03 amendment](DECISIONS.md#adr-011) / `101`: one SECURITY INVOKER plpgsql body whose **first statement takes a `FOR UPDATE` row lock**, which is also the tenant fence (a foreign or absent id resolves to zero rows and the function refuses). **No tenant parameter** — `users_id` from `auth.uid()`.
> 4. Lock 14 write-path hardening via the SELF-233 shared layer: Zod `.strict()`, mass-assignment prevention (`users_id` from `auth.uid()`, never the body). **The adversarial battery is the TEXT variant** — control characters, length bounds, encoding — the numeric battery does not apply to a TEXT column.
> 5. Plain text only; line breaks preserved; **no markdown rendering** (ADR-013 INV-1 — security-load-bearing at V1).
> 6. Empty sub-sections are legitimate: PRD §2.6.2 — *"empty sub-sections render with the label and an empty body region"*; the F/CTO is not required to author under every sub-section every month.
> 7. `⟨PM⟩` all copy. **`⟨SEC⟩`**
>
> **Dependencies.** Upstream: A1. Downstream: P4.

---

## SELF-356 — P4. §2.6.2.c author-before-generate trigger

> **Baseline.** `b90b846`.
>
> **AC.**
> 1. **The gate is complete-**or-explicitly-skip**, not commentary-present.** PRD §2.6.3 verbatim: the flow blocks finalization *"until the user completes (or explicitly skips) authoring"*; PRD §2.6.2 adds that empty sub-sections render as empty. ⚠ The prior AC made empty commentary an unconditional block, which leaves the user no way to say "no commentary this month, generate anyway" — a state the PRD explicitly admits (F-8).
> 2. **The notification is in-app, not Discord.** PRD §2.6.3: cron-fired authoring is surfaced *"via an in-app notification + pending-monthly-report queue affordance (parallel to §2.4.1's iv-1 notification queue pattern)"*, and *"the user resolves pending monthly reports at their convenience."* Coolify→Discord remains the **operational** channel for cron success/failure. ⚠ The prior AC routed the user's authoring notice to Discord.
> 3. State transition, stated once: cron writes `draft` → complete-or-skip promotes to `final` → regeneration supersedes.
> 4. On-demand (P5) blocks the finalize action until complete-or-skip and routes into P3.
> 5. `⟨PM⟩` all copy, including the skip affordance's wording — it must not read as "discard".
>
> **Dependencies.** Upstream: P3, P5, A7, A1.

---

## SELF-357 — P5. §2.6.3.b on-demand UI + pending queue

> **Baseline.** `b90b846`. Depends on A1/A3 and therefore on `⟨RULING⟩` S-1.
>
> **AC.**
> 1. Listing surface of prior generated reports (the retention layer per PRD §2.6.4 — **indefinite retention; no user deletion at V1**).
> 2. **Pending-monthly-report queue** — the in-app half of P4 item 2, and the surface cron-fired drafts land on.
> 3. "Generate monthly report" affordance with target-month selection; default is the prior month when cron has not fired for it.
> 4. On-demand invokes A3 through an app endpoint under the **user's own session**, never through the cron worker — the user's session is the tenant binding, which is why this path does not inherit S-3.
> 5. `p_data_as_of` is **server-derived** for this path too (Lock 15's server-derived-only fence covers §2.6 cron **and** on-demand; §2.3.3 drill-down is the only surface where a client toggle is legitimate).
> 6. Reuses Lock 11 INSERT-new-version on regeneration.
> 7. `⟨PM⟩` all copy and queue-state labels.
>
> **Dependencies.** Upstream: A1, A3, P4, **`⟨RULING⟩` S-1**. Downstream: P6.

---

## SELF-358 — P6. §2.6.3.c PDF export

> **Baseline.** `b90b846`. **⚠ BLOCKED ON `⟨RULING⟩` S-2.**
>
> **AC.**
> 1. ⚠ **The prior AC has the browser posting a composed JSON payload plus a JWT-bearer to A5 and receiving PDF bytes. That inverts ARCH §3.2** (worker pulls HTML from the app) and would additionally put `PDF_WORKER_SIGNING_KEY`'s trust boundary in the browser. Re-draft after S-2.
> 2. "Download PDF" affordance on the P2 report page.
> 3. **One HTML template, shared with P2** — under S-2 Option A or C this is structural rather than a discipline, and it is what discharges the §7.32 item 6 escaping obligation.
> 4. The PDF is a **transient export, not persisted server-side** (PRD §2.6.3 verbatim); the server-side artifact is the §2.6.4 snapshot.
> 5. Filename pattern `⟨PM⟩`.
> 6. **PDF staleness markers are read live**, not from the snapshot (PRD §2.6.4's staleness carve-out + §2.6.5).
>
> **Dependencies.** Upstream: A4, A5, P2, **`⟨RULING⟩` S-2**.

---

## SELF-359 — P7. §2.6.4.b owner-identification Settings editor

> **Baseline.** `b90b846`. **Buildable as drafted. Unblocked — recommended first dispatch with A8.**
>
> **AC.**
> 1. Settings route `/settings/owner-id`, extending the SELF-242 Settings shell. Single TEXT input for `owner_id_header_text`.
> 2. Replace-all write to A8 via the SELF-233 hardening shared layer: Zod `.strict()`, mass-assignment prevention, the **TEXT-variant** adversarial battery. Same `SERIALIZABLE`-is-not-reachable note as P3 item 3 if the write is routed through an RPC; a single-row UPSERT through PostgREST needs no lock.
> 3. PRD §2.6.4: arbitrary plain text, no formatting markup; multi-line headers, rich text, multi-named-owner and per-report overrides are V2+.
> 4. **State the snapshot consequence at the editor:** a rename applies **forward only** — historical reports keep the name in effect when they were generated (PRD §2.6.4), because A1 snapshots `owner_header_at_generation`. `⟨PM⟩` whether the editor says so to the user.
> 5. Closes the Settings ramp at 4/4 (SELF-242 V1.2 + SELF-252 V1.3 + SELF-265 V1.4 + this).
> 6. `⟨PM⟩` copy.
>
> **Dependencies.** Upstream: A8, SELF-233, SELF-242.

---

## SELF-360 — P8. §2.6.5 staleness markers on §2.6 surfaces

> **Baseline.** `b90b846`. **Depends on `⟨RULING⟩` S-4.**
>
> **AC.**
> 1. **α′-1 generate-with-markers, not block** (PRD §2.6.5 verbatim). Cron generates regardless of staleness.
> 2. **Both halves are required** and PRD §2.6.5 rejects either alone: **per-section inline markers** *and* a **report-level summary banner** naming every stale-contributing account. ⚠ α′-3 (banner-only) is a named rejected alternative — it is not a valid V1.5 reduction.
> 3. **The banner is served by the shipped primitive; the per-section half is not.** `pfin.fn_aggregation_has_stale_constituent()` (`046`, re-commented `059`) takes **zero arguments** and returns **one aggregate row for the calling user** — it answers "does this tenant have any unhealthy `linked_source`", not "is this section stale". `⟨RULING⟩` **S-4** decides the attribution route: reuse the shipped V1.3 per-row shape (`api/src/lib/cashflow-row-staleness.ts`, `CashflowRowStaleTag.svelte`, SELF-258) or extend the DB primitive. ⚠ A scope-typed argument is **not** available — `pfin.scope` is not a type.
> 4. **Two exclusions, per PRD §2.6.5:** §2.6.2 commentary and the §2.6.4 owner header are **not** marked — they are not account-derived.
> 5. **Staleness is read live even on a frozen report** (PRD §2.6.4's explicit carve-out) — a historical report shows *current* staleness, not the state at generation. This survives S-1 in either direction and must not be folded into the snapshot.
> 6. Extends SELF-208 / 229 / 243 / 258 per ADR-013 D1 (surface list illustrative-not-exhaustive).
> 7. `⟨PM⟩` marker and banner copy.
>
> **Dependencies.** Upstream: SELF-208, A3, **`⟨RULING⟩` S-4**.

---

## SELF-361 — P9. §2.5.x staleness ramp

> **Baseline.** `b90b846`. **Buildable as drafted. Unblocked — the cleanest P-item in the wave.**
>
> Extends the shipped SELF-208/229/243/258 framework onto shipped §2.5 surfaces: the §2.5.1 three-column decomposition (SELF-264), the two quarterly tables (SELF-266), and the §2.5.4 NAV-composition Tax Liab rows (SELF-268). Consumes `pfin.fn_aggregation_has_stale_constituent()` (zero-argument signature — verified at this sha) plus the shipped per-row shape. No new substrate; no seam.
>
> One addition: the §2.5 surfaces carry a **second, non-Plaid degraded state** — the `{status:'unavailable', reason:…}` envelopes and the `basis_year` fallback ([ADR-067](DECISIONS.md#adr-067) Decision 5). ⚠ These are **not** staleness and must not be merged into the stale badge: "no ledger designated" and "your brokerage needs re-auth" are different facts with different user actions. State the separation in the AC so a future consolidation does not collapse them. `⟨PM⟩` copy for both.
>
> **Dependencies.** Upstream: SELF-208, SELF-264, SELF-266, SELF-268 — all shipped.

---

## SELF-362 — P10. §2.6.6 RLS verification battery (V1.5 close-gate)

> **Baseline.** `b90b846`. Last. Inherits every ruling.
>
> **AC.**
> 1. Two-tenant coverage of A1 + A2 + A3 + A5 + A7 + A8 + P3 write path: cross-tenant injection rejected on each.
> 2. A3 cross-tenant leak analysis — a foreign caller gets the **empty/unavailable shape**, i.e. fails closed *into a shape that says so*, not into a plausible zero. ⚠ That argument covers only callers subject to RLS: assert as a catalog fact that **no `rolbypassrls` role holds EXECUTE** on A3.
> 3. Lock 12 snapshot derivative-surface Sec annotation (**not** a new SD class — snapshots of §2.5-grade values).
> 4. A7 cron tenant-binding isolation, including a leg that would catch the **singular-GUC** failure (one tenant's data served for every tenant) — that failure has no app-layer symptom, so only a DB-side leg sees it.
> 5. A5 endpoint JWT tenant-binding — shape depends on `⟨RULING⟩` S-2/S-3.
> 6. **Tri-axis orthogonality (tenant × scope × tax_treatment)** per PRD §2.6.6. ⚠ Both non-tenant axes are `text not null` columns on `pfin.account` (`003`) — `scope` is a free-text ADR-004 Decision B label, **not** an enum or a type. The battery must vary them as values, and must include a leg proving the two axes are **orthogonal to tenancy**: a matching `scope` string across two tenants must not leak, which is the failure a shared-vocabulary join would produce.
> 7. ⚠ Battery hygiene, from the V1.4 record: pgTAP `isnt()` **passes on NULL**, so a negative assertion over a subquery is fail-open — use `ok()` and prove three states. Verify with `pg_prove`, never bare `psql` (which exits 0 on a failed plan). Rebuild the scratch DB before any full-suite claim — `rollback` does not reset sequences.
> 8. **V1.5 close-gate:** no V1.5 issue closes until this passes. Sec verdict recorded per the SELF-269 precedent.
>
> **Dependencies.** Upstream: all V1.5 issues, all rulings.

---

## Not in this wave

**SELF-365 (P11, V1.final), SELF-363 (CA 2026 seed), SELF-364 (PRD §2.5.3 amendments), SELF-326 (volatility pin)** carry no V1.5 milestone and none blocks a V1.5 issue.

Two notes for whoever picks them up:

- **SELF-326** is context for A3 item 7: `fn_gl_entries` and `fn_holdings_as_of` are `provolatile = 'v'` at this sha and are reached transitively by A3's tax callee. A3 does not need SELF-326 to land, but its header must **name** the gap rather than claim a fully-pinned read set. ⚠ When SELF-326 does land, pin by `ALTER` — a `DROP`+`CREATE` destroys grants (`072`), and `CREATE OR REPLACE` silently resets volatility, so the pin must be re-asserted per signature.
- **SELF-364** item (1) settles the installment-count definition that A3 renders. `104` already implements the ratified reading (`installments_due_through_next`); SELF-364 aligns the PRD to it. If SELF-364 lands after A3, nothing in A3 changes — the PRD is catching up to the code, not the reverse.

---

## Observation booked out of this pass (no V1.5 issue)

Two dated `comment on` texts read as live state and are falsified by ADR-011 Decision 3 read at this sha: `059`'s `fn_aggregation_has_stale_constituent` comment (*"Decision-3 unchanged 15/13"*) and `054`'s trigger comment (*"unchanged at 15 labeled / 12 DDL-realized"*). Both were true when written. `104` and `105` already state the corrected convention (*"no count is stated here … read ADR-011 Decision 3/4 live"*), so the generator is fixed going forward. **Not proposing a comment-only migration in V1.5** — routed to team-lead for booking. F-14.
