# V1.5 pre-flight recalibration — sitting log

**Baseline: `origin/main` @ `d1e5e3d`** (2026-09-04, the findings + agenda merge, PR #623). The findings files hold `b90b846`; the two merges between (the agent-memory chore and #623 itself) touch no schema, source, or doc artifact, so the findings' measurements stand.

**Provenance convention** per [ADR-063](../../../DECISIONS.md#adr-063) Decision 3: each entry is marked **F/CTO RULING** or **DEFAULT-AND-NOTIFY** (team-lead, reversal window open until the amendment batch merges). Never flattened. V1.5 is not under the V1.4 execution delegation; every ruling here was put to F/CTO one per turn.

Agenda: [`sitting-agenda.md`](sitting-agenda.md). Rulings are numbered as there (R1–R14).

---

## Rulings

### R1 — S-1 / A-5: the monthly report is a FROZEN RENDERED ARTIFACT · **F/CTO RULING: (A)** · 2026-09-04

**Ruled.** Freeze the rendered payload at finalization. A3 composes as drafted; its return is written once, at finalization, onto the report header (`rendered_payload JSONB NOT NULL` + `payload_schema_version SMALLINT`, or a payload child — Architect's DDL call), and every later read of a `final` report — in-app view and PDF export alike — reads the stored payload. The Lock 12 child stays the per-account queryable index over the frozen artifact. Option (B) (narrow φ-1 to live-recompute-as-of) not taken — Sec's veto stands on ADR-067 D3 ground (ii) alone (settings-derived cells have no history, so a recomputed past month presents values that were never true of it). Option (C) (hybrid) not taken. PM's un-vetoed variant (amend the promise, label historical reports as recomputed) was put to F/CTO and declined.

**F/CTO's question at the ruling, answered for the record:** transaction history is complete and does recompose (Lock 15); what has no history is the Lock 14 settings store (targets, bracket schedules, owner string) and category labels. The requirement the report proxies is archive fidelity — the month as the user closed it — not computation.

**Riders adopted with the ruling:**
1. Frozen IN: every `{status, reason}` envelope, `basis_year`, the tax-authority exclusion line's state, the unclassified count, and the owner header (`owner_header_at_generation`) — as rendered at generation (PM 12.3, Architect A3 item 4).
2. Frozen OUT: §2.6.5 staleness markers, read live at every render and export (§2.6.4 carve-out; Sec M-4).
3. The A2 widening beyond Lock 12's three columns is drafted as a **Lock 12 amendment** in the consolidated ADR (R14), not as an implementation detail (Architect F-7); `scope` is dropped (`pfin.scope` is not a type).
4. `payload_schema_version` ships with the payload; a §2.x rendering change keeps reading old payloads (the `nav_daily` lesson, ADR-040 / ADR-067 D3).
5. JSONB here does not touch Lock 14's no-JSONB forward-compat fence; that fence governs the settings store (`101` precedent). Recorded so it is not re-litigated at A1's review.
6. A frozen payload freezes its defects (PM's losing-side half): the "Regenerate" affordance and the pre-finalize no-tax-ledger prompt (agenda §6) are load-bearing, not optional, and are carried into P4/P5's ACs.
7. **The stored artifact is the rendered VALUES (JSON), not a PDF.** PDFs are regenerated from the payload on every export and are never persisted (PRD §2.6.4 "no PDF caching V1"; Sec M-6 non-objection with its standing condition: the first AC that persists PDF bytes creates a storage-class surface and is joint-review-mandatory at that PR).
8. Sec joint-review mandatory on A1/A2/A3 as one design unit (Lock 11/12 surfaces, D2 + D3, financial values).

**Consequences recorded:**
- PRD §2.6.4 φ-1 stays as written; A-5's exception wording is withdrawn; the PRD amendment batch (R10) carries only the pointer edits.
- The P10 battery fences one stored object and one read path (Sec R2.1's testability argument).
- Blocks released: A1, A2, A3, P2, P5, P10 (subject to R4, R5, R7).

**Consuming issues:** A1 · A2 · A3 · P2 · P5 · P6 · P10.

### R2 — S-2 / D-7: the PDF render direction · **F/CTO RULING: (C)** · 2026-09-04

**Ruled.** The app composes the report under the user's own live session, renders it through the same Svelte template the in-app view uses, escapes every free-text field there, and pushes **finished HTML** to the PDF worker; the worker runs it through headless Chrome and returns PDF bytes. The worker holds no DB access, no template, no tenant or money knowledge — "a PDF printer, nothing else" (F/CTO's framing at the ruling, confirmed). Option (A) (conform to ARCH §3.2: worker pulls rendered HTML from the app under a machine JWT) not taken — it forces the app to render a page for a user identity with no session, which is S-3. Option (B) (JSON push, worker composes HTML) not taken — dominated; nobody supported it.

**Sec's two conditions adopted with the ruling (sec-findings R2.2):**
1. **Resource-loading fence in the worker** — `page.setContent()` plus request interception aborting every request whose scheme is not `data:` (no `file:`, no `http`, no `https`). An addition to Lock 13 mod #7's hardening list, not an inheritance. Catch criterion: HTML carrying `<iframe src="file:///proc/self/environ">` and `<img src="http://169.254.169.254/">` renders a PDF containing neither the signing key nor any fetched content, AND the interception handler records two aborts (a failed fetch and a blocked fetch render identically, so "the PDF looks fine" is vacuous).
2. **N-4 — a compose manifest for `workers/pdf-render/` carrying the RT-27 private-bind sentinel**, with the fence job invoking `scripts/ci/fence-admission-private-bind.sh` against it. An **intra-instance coverage expansion of RT-27 on the CI-fenced side only — no catalogued-ledger effect, no new §10 instance drafted** (RT-30 precedent). It is a CI fence-boundary change: DevOps proposes the catch criterion, Sec reviews, golden fixture fails closed.

**Consequences recorded:**
- **Lock 13 amendment + RT-21 rewrite** ride the consolidated ADR (R14): the JWT's purpose changes from "prove who is asking" to "prove the caller is our app"; ARCH §3.2's sequence diagram and RT-21's body are amended in that PR under Sec joint-review. RT-21's canonical (a)–(g) letters are re-derived against the new direction at A5, with (g)'s known-defective inheritance still routed to Sec at build.
- **S-3 is moot for the PDF path.** The app half of the tenant-binding question disappears; R3 now covers only the cron half (A7) and the ARCH :208 reading.
- **§7.32 item 6** (PDF-worker escaping control): the *control* is discharged structurally — the worker composes nothing, Svelte's default escaping is the control. The *proof leg* is still owed under INV-2 (spans both engines): a stored `<script>` in commentary, the owner string and `schedule_label` renders inert in the PDF. Home: **P6** (PM 12.3, Sec R2.9, Architect §9.5 — all three). The §7.32 entry reduces to header + citation once P6 lands.
- A4 gains a second Sec trigger (CI fence-boundary change via N-4) and "extend the placeholder", never "scaffold".
- P6's user path: the Download button hits a **user-session** app route; the worker credential never reaches the browser; no PDF of a pending report.
- The in-app view and the PDF cannot drift: one template (PM's product requirement — byte-for-byte content except the live staleness layer).

**Consuming issues:** A4 · A5 · P6 · P10 (two-abort leg + the inert-`<script>` leg).

### R3 — S-3 / Sec R-3 + N-3: tenant binding for the cron; the ARCH :208 reading · **F/CTO RULING: α + Architect's reading** · 2026-09-04

**Ruled (i).** Every non-JWT caller of the SECURITY INVOKER read-composition helper binds a tenant by **impersonation**: `SET LOCAL ROLE authenticated` + `set_config('request.jwt.claims', …, true)` per tenant, per transaction, with the singular `request.jwt.claim.sub` GUC nulled first — the pattern already shipped as `TenantBoundConnection` in `workers/etl/src/pfin_back_etl/connection.py` (W-1). A7 names and reuses that module rather than re-specifying it; **A3 drops `p_users_id`** and reads `auth.uid()` (the `101` / `105` precedent). Under R2 (C) this is the only non-JWT path left. Sec's options β (keep `service_role` + a code-layer parameter — excluded by ARCH §3.2's "the endpoint does not use `service_role` in V1"; retracted by Sec) and γ (session-minting) not taken.

**The hazard the ruling closes (Sec F-4):** claims WITHOUT the role leaves `rolbypassrls` in force — `auth.uid()` returns the intended tenant, every RLS predicate is skipped, the composition reads every tenant's rows, nothing raises. A `p_users_id` on an INVOKER helper is the trap in the other direction: it either does nothing or turns a wrong question into "no data" (Architect S-3).

**Riders adopted:**
1. **Standing catalog assertion in P10** (Architect P10 item 2; Sec R2.5 — "the best leg in the wave"): no `rolbypassrls` role holds EXECUTE on the helper (`revoke … from public; grant … to authenticated;` — the `104`/`105` shape; `008` grants no function EXECUTE). Standing, not one-time: the failure mode is a future migration adding a grant to make something work. For an INVOKER function the EXECUTE ACL is normally the weakest fence; against a bypass-RLS caller it is the only one.
2. **Two-tenant leg with a positive control** (Sec F-4 catch criterion): run the cron for tenant A with tenant B's rows present; assert zero tenant-B rows composed; the battery proves the leg reds when the role assumption is struck. A fresh fixture with no tenant-B rows makes this leg vacuous by default.
3. `RESET ROLE` discipline between tenants on a pooled connection, with a test (Sec's named losing side of α).
4. Sec's second losing side of α recorded, not resolved here: it puts a role-assumable identity on the cron host, which `055`'s deliberately non-owner ETL identity exists to keep small. A7's Sec joint-review carries that expansion.

**Ruled (ii).** ARCH `:208` — *"user-session only — never invoked from a worker"* — **constrains the session context, not the process identity, and is PDF-scoped** (Architect 2c). The cron satisfies it by impersonating: at the DB layer that caller IS a user session. The general reading would void Lock 11 mod #4's ratified V1-SHIP-BLOCK cron tenant-binding discipline and cannot be right. **The sentence is narrowed on the tree** in the consolidated ADR's doc PR (R14) — Sec's rider that it end up unambiguous in ARCH, not in a records file. It makes F-4 sharper, not weaker: claims-without-role does not satisfy a session-context constraint either.

**Consequences recorded:** A5's "Arch-locked binding per RT-21(e)" false composite is struck (RT-21(e) is the no-escalation clause and names no mechanism). A7 inherits the singular-vs-plural claims-GUC hazard handling from `connection.py` (Architect F-11). The D1 clause (d) audit row for A7 is R7.

**Consuming issues:** A3 · A7 · A5 (moot half recorded) · P10.

### R4 — Sec R-1 / Architect §8.3: supersession on the immutable header · **F/CTO RULING: (B), with Sec's four conditions** · 2026-09-04

**Ruled.** No SECURITY DEFINER supersession function; the D9 allowlist is untouched. The `monthly_report` immutability trigger — the same trigger, not role-conditional — permits (i) any column while `generation_status = 'draft'`; (ii) `generation_status` only on the single monotone transition `final → superseded`; (iii) nothing else, ever; and fences `users_id` / `target_month` in every state. Lock 11's partial UNIQUE `(users_id, target_month) WHERE generation_status = 'final'` is kept verbatim and keeps firing. Option (A) (derive `superseded` from ordering) not taken — withdrawn by Sec at R2.9 as internally incoherent (the index permits at most one `final` row, so there is never a set to order; both rescues either amend the locked index or leave it never firing). Option (C) (DEFINER as drafted + D9 amendment) not taken — rejected by Architect and Sec.

**Sec's four conditions, adopted (sec-findings R2.9):**
- **(a) DELETE stays blocked** on every non-`draft` row. D2 is two verbs; `authenticated` needs INSERT for the on-demand path and never DELETE (PRD §2.6.4: indefinite retention, deletion V2+).
- **(b) The trigger is not role-conditional.** Refusal is proven under `authenticated` AND `service_role` — two legs. The cron performs the `final → superseded` UPDATE, so the realistic later defect is an early-return for `service_role` added to make the cron work.
- **(c) Legal INSERT states are constrained**, not only transitions: a row written straight in as `final` would take the month's single slot without passing the authoring gate.
- **(d) `superseded` is terminal**, stated in the trigger and the header; plus the ADR-011 D4 runbook line: this trigger is the only applicable layer for an RLS-exempt writer and goes inert under `session_replication_role = replica`.

**D2's reading on this surface, recorded (Architect S-1 answer, ratified here):** the *immutable* half governs `monthly_report_account_snapshot` and the frozen payload (read-only post-write); the *INSERT-new-version* half governs the header's regeneration path. `draft → final` promotion is itself an UPDATE, so D2's blanket "UPDATE blocked" was never literally true of this table under its own locked vocabulary; the consolidated ADR (R14) says so and names where the mutability window closes. Sec's own named cost stands: D2's blanket append-only claim stops being true of this table and the ADR must say so; the mitigation is that the exemption is a monotone transition on one column, checkable in the trigger and in a battery leg, not a column allowlist.

**Consequences recorded:** Sec's A1 pre-verdict moves AMBER → GREEN once (a)–(d) are in the AC (they are, at Architect 2d). Catch criteria for P10: regenerate one month **three** times → three rows, exactly one `final` (a two-regeneration leg passes against the defective triple-column UNIQUE); UPDATE a `final` row as each role → refused; DELETE as each role → refused; INSERT directly as `final` → refused. PM's status-bridge sentence ("pending = draft; generated = the current final; a superseded version is never rendered in V1") holds under (B). A1's `updated_at` + `fn_refresh_updated_at` is legitimate only within the `draft` window (PM D-6).

**Consuming issues:** A1 · P3 · P4 · P5 · P10.

### R5 — S-5 / Sec F-2: `included_reconciliation_event_ids INTEGER[]` · **F/CTO RULING: (a) ship dormant** · 2026-09-04

**Ruled.** A1 ships Lock 11 mod #9 as locked: the `INTEGER[]` column referencing `pfin.reconciliation_event` and its array-element matched-tenant BEFORE INSERT/UPDATE trigger. This **realizes ADR-011 Decision 3 label #3**; it allocates no label and renumbers nothing (the drafted "6th instance" is struck by citation). The migration header names the fence DORMANT with the revival condition — the first `reconciliation_event` writer, expected at the V1.6 statement tie-out (ADR-035). Option (b) (retire or re-defer the instance by D3 amendment) not taken — Sec's round-1 lean, withdrawn at R2.3 (ADR-035 names a consumer, so the instance is deferred-with-a-consumer, not orphaned; D3's #15/#16 record twice that fold-ins get forgotten).

**Rider adopted (Sec's condition):** the paired QA leg is **labelled construction-only in its own text** — it asserts the trigger exists, is attached to the column and carries the matched-tenant body; it does not assert firing, because nothing can populate the array in V1.5. A later reader must not mistake it for behavioural coverage (the "leg that cannot fail" tell).

**Consequences recorded:** A1's D3 fence sits on the array column, not on `users_id` (the tenant anchor is not a family member — `007`/`015`; a `users_id = auth.uid()` fence is the leg that cannot fail, ADR-062 D2). A2's `account_id` realizes label #4 the same way; A2's FK to the A1 parent is disposed explicitly in the DDL (fenced, or argued out with the reasoning recorded — Sec F-1's open question, Architect's to write). No Decision 3 edit is owed; Path B.

**Consuming issues:** A1 · A2 · P10 (construction-only leg).

### R6 — A6 / SELF-350 disposition + Sec F-6 · **F/CTO RULING: (ii) re-scope in place** · 2026-09-04

**Ruled.** SELF-350 keeps its id, its dependency edges and its `sec-joint-review` label, and is re-scoped in place to the **RT-22 dependency-manifest fence**: audit `workers/pdf-render/package.json` and its lockfile for Postgres-client packages (`pg`, `postgres`, `node-postgres`, `@supabase/supabase-js`, driver-bundling ORMs), paired with a golden violation fixture and an inversion-mode CI step exactly as the shipped Dockerfile fence is paired today. Owner DevOps + QA; catch criterion and fixture route through Sec before merge. Option (i) (close and open a successor) not taken.

**Riders adopted:**
1. **First AC sentence states that the Dockerfile fence is already built** (`scripts/ci/fence-rt22-pdf-worker-dockerfile.sh`, `security-scan.yml` production + inversion, landed `eada4b2`) and **cites the shipped fence's own header**, which documents manifest inspection as a deliberate non-catch — otherwise a future reader finds a fence that says it does not do this and closes the issue as redundant (Sec R2.9).
2. **Fence shape makes ordering moot** (Sec's condition, adopted by Architect 2d): audit the manifest if present, pass if absent — deliberately unlike the Dockerfile fence's exit-2-on-missing-target, which would red CI from day one. The fence lands any time, no-ops until A4 creates the file, bites on A4's first commit. The earlier "A4's `package.json` may not land before the fence" sentence is withdrawn as a convention with no mechanism; fallback if the shape is not adopted is a blocking Linear edge, never an AC sentence.
3. **Sec veto D-1 recorded in the re-scope comment:** the drafted `SUPABASE_URL` carve-out is struck — Lock 13 mod #2 is "no `SUPABASE_*` env vars", no exception; the shipped fence rejects all of them — and the "both catalogued instances" figure is struck by citation to ADR-011 D4 read live. **The AC carries no ledger figure** (Path B). Neither correction is ever inherited by a future edit of the fence.
4. The inversion-mode golden-fixture step is preserved verbatim through the re-scope (removing it makes every green run uninformative).

**Ledger effects: none.** RT-22 was catalogued in 2026-05; building or extending its fence adds, removes, reorders or renumbers nothing in Decision 4. The **catalogued** set and the **CI-fenced** set remain different sets and are not reconciled.

**Consequences recorded:** A4's AC says "extend the placeholder", never "scaffold", and does not restructure the ENV/ARG block the Dockerfile fence keys on. `BACKLOG.md` §7.1 A6 text is corrected in the close-out PR (agenda §4). `scripts/ci/fence-tbc-node.sh`'s exclusion of `workers/pdf-render/` rests on the zero-DB-reach premise; the manifest fence is what keeps that premise a control rather than an assumption.

**Consuming issues:** A6 (re-scoped) · A4 · P10.

### R7 — Sec N-2 / A7-AUDIT: the D1 clause (d) audit-log home · **F/CTO RULING: (2) author the reserved general helper** · 2026-09-04

**Ruled.** A7's ADR-011 Decision 1 clause (d) obligation — a same-transaction audit row naming the resolved tenant and the tenant-resolution chain — is discharged by **authoring the general audit-log helper that ADR-011 Decision 9's amendment records as reserved-unauthored**, and A7 writes through it. Option (1) (widen `linked_source_sync_audit`'s `source` and `provider` CHECKs) not taken — it changes the domain of a shipped append-only audit-class table from "sync" to "any privileged write", a D2 change reached for convenience. Option (3) (a report-scoped audit table) not taken — a fourth audit surface with one consumer.

**What was measured (Sec N-2, PM D-8):** the drafted "Lock 13 mod #4 audit log" (`pfin.plaid_sync_audit`) was dropped at `015`; its successor `pfin.linked_source_sync_audit` (`015:441`) carries `users_id` commented "resolved tenant (Decision 1 clause (d))" but rejects a report-generation row on `source in ('webhook','scheduled_poll')` and on a provider list with no internal/report member; `git grep` finds no `emit_audit_log` / `fn_audit_log` in migrations at the baseline. Built as drafted, A7 would either silently drop D1(d) on the wave's only privileged non-JWT writer or widen CHECKs on an audit-class table without a review that noticed.

**Riders adopted:**
1. The helper is a **Decision 9 allowlist event** only if it needs DEFINER; Architect drafts it INVOKER-first under the writer's own `service_role` context (D1 clause (b): writes under `service_role`) and states in the migration header which posture it takes and why. If DEFINER, the D9 amendment rides the same PR (Sec R2.3 R-1 addition), never a later reconciliation.
2. The row shape carries at least: trigger source (`cron` / `on_demand`), resolved `users_id`, the resolution chain, `data_as_of`, and the report row it produced — the fields PM §6 needs for V1.final's "month of operation" measurability (clause 2) and that Decision 19 extends with `data_as_of`.
3. The helper is **append-only under D2** (both roles), aal2-clause-exempt only because no `authenticated` policy reads it — stated, not assumed.
4. The on-demand write path (A10 / R9) writes through the same helper; the helper therefore has two callers at V1.5, not one.
5. Sec's losing side recorded: a general helper is where per-surface discipline goes to be forgotten. Mitigation: the helper takes the surface name as a required argument and CHECK-constrains it against an enumerated list that grows only by migration.

**Consequences recorded:** A7's catch criterion is restored — assert the same-transaction audit row exists, names the resolved tenant, and is absent when the generation transaction rolls back. A7 is no longer RED; it sits on the critical path behind the helper, so the helper is drafted inside the A1+A2+A3 design unit's PR sequence (R13). `linked_source_sync_audit` is untouched.

**Consuming issues:** A7 · A10 · P10 · SELF-365 (measurability).

### R8 — Milestone placement of the Platform A-items · **F/CTO RULING: A1–A8 → V1.5; A9 stays unmilestoned** · 2026-09-04

**Ruled.** SELF-345 … SELF-352 (A1–A8) are assigned the Linear milestone "V1.5 — Monthly report full (§2.6)"; their project stays Platform / Cross-cutting (project ≠ milestone, V1.4 R7). SELF-353 (A9) stays unmilestoned in Platform: ADR-054 Decision 6 makes it orthogonal by construction, it has no §2.6 consumer, and it must not gate SELF-362. The one live cross-role split (A8) is ruled PM's way: P7 is in the milestone and V1-SHIP-BLOCK and cannot ship without A8, and A1's `owner_header_at_generation` is written from A8's row — A8 is §2.6 substrate on product trace. Architect's ground (Lock 14 family span) recorded as the losing side; Architect had already recorded PM's argument as the stronger one.

**Consequences recorded:**
- The close-gate (SELF-362) now sees its substrate: "no V1.5 issue closes until the battery passes" reaches A1–A8.
- `MILESTONES.md` Active Feature row names the set as A1–A8 + P2–P10 (+ A9 unmilestoned, dispatched early); the count is dropped, the set is named (close-out PR).
- Linear writes are the liaison's, at the amendment batch: milestone on eight issues; A6's re-scope (R6) rides the same pass.
- A9's clock argument stands independent of milestone: every day it does not exist is an unrecoverable observation gap (Architect §4; PM §7 item 3).

**Consuming issues:** A1–A8 (milestone) · A9 (placement recorded) · P10 (gate set).

### R9 — PM §7 item 2: five PRD-required V1 surfaces no issue carries · **F/CTO RULING: (2) fold four, open A10** · 2026-09-04

**Ruled.** (i) the report listing with target-month selection and (iii) the in-app pending notification + queue fold into **P5**; (iv) copy-from-prior-month (per-sub-section and global) and the `$ ReAlloc` side-by-side reference fold into **P3**; (v) the report-level staleness banner naming stale accounts folds into **P8**. (ii) the **on-demand generation write path** becomes a new Platform issue, **A10** — a Lock 11 (Decision 2) INSERT under the user's own session with a server-derived `data_as_of` (Lock 15 / RT-25), writing its D1(d)-shaped audit row through the R7 helper — carrying `sec-joint-review`, milestone V1.5 (per R8's rule for substrate), project Platform / Cross-cutting. Option (1) (fold all five) not taken; option (3) (two new issues) not taken. The `rederived-acs.md` A10 sketch block is promoted from proposed-not-promoted to the issue's AC at the amendment batch.

**Why the write path is its own issue (Architect §8.5, Sec R2.9):** A3 is a READ helper and A7 is cron-only, so nothing on the tree or in the wave wrote a `monthly_report` row on the on-demand path. A D2 write inside a Frontend-reviewed SvelteKit issue has no Sec gate and no independent record; if P5 slips, the write path and its obligations slip invisibly. ADR-064 D5 is cited for its reasoning only — "the trigger is the surface, not the layer, and not the author's assessment of risk" — and expressly not as jurisdiction (D5 is scoped to `account_trans`). Sec's fallback (a fold with `joint-review:sec` on P5 and explicit D2 + RT-25 lines) was available and not needed.

**Riders adopted:**
1. A10 writes `draft` (never `final` directly — R4 condition (c)); finalization is P4's path. A10's row is the one the cron would have written on the 1st, so the two paths share the R7 audit helper and the same INSERT shape.
2. `data_as_of` is server-derived and never client-asserted (Lock 15); a client-supplied as-of is refused — battery leg in P10.
3. P5's listing and queue reads are **tenant-scoped at the DB layer and asserted** (Sec F-8): tenant A sees zero of tenant B's entries. "Pending" means awaiting commentary; no job-state vocabulary (queued/in-flight/done) and no in-app failure notification (V2+ per §2.6.3).
4. P3's editor opens blank; copy-from-prior is an explicit affordance, disabled with copy when the prior month has no commentary (PM §8).

**Consequences recorded:** the V1.5 set becomes A1–A8 + A10 + P2–P10, with A9 unmilestoned; the ledger names the set. A10 sits on P5's critical path and is dispatched inside Track 1 right after the A1+A2+A3 unit (R13). Losing side recorded: 19 issues and a new blocking edge into P5.

**Consuming issues:** A10 (new) · P3 · P5 · P8 · P10.

### R10 — PRD §2.6 amendment batch · **F/CTO RULING: authorized as drafted** · 2026-09-04

**Ruled.** PM's fourteen §2.6 passages (pm-findings A-1 … A-14) land in one PRD PR, owned by PM, classified per BACKLOG §7.19 AC1: 5 text amendments (a), 8 pointer edits (c), the one design conflict (A-5) resolved at R1 with φ-1 kept as written. Sequenced **before P9's dispatch** (PM §4: P9's copy is written against amended §2.5.3), in the same PR as SELF-364's §2.5.3 amendments or the adjacent one.

**Contents authorized:**
- **Pointer edits (c):** A-1 §2.6.1 Account Holdings renders the shipped V1.4 ladder — tax rows are `{status, amount}` envelopes, may render Unavailable-with-reason, the tax-authority exclusion line renders as on §2.1.5 · A-2 NAV Performance reads the checkpointed gross series and carries the live surfaces' gross-basis line; foot-to-chart difference = two tax lines + designated ledgers (ADR-067 D3 rider 2) · A-3 Estimated Taxes renders §2.5.1/§2.5.3 as shipped incl. Unavailable states and basis notes; a state unavailable at generation is frozen as unavailable · A-6 storage pointer to Lock 11 (below) · A-9 owner-id is `pfin.owner_identification`, the last Lock 14 table (D18 as amended) · A-10 server-side PDF resolved at Lock 13 · A-12 snapshot derivative surface discharged at PR #95 (SECURITY §4.4) · A-14 cron failures → Coolify→Discord.
- **Text amendments (a):** A-7 one scheduled run generates per tenant under tenant binding (no per-user job) · A-8 the status bridge: *"pending = draft; generated = the current final; a superseded version is never rendered in V1"* (worded to hold under R4) · A-11 founding-user sweep — "the F/CTO" as actor → "the user"; "the F/CTO's existing system" as parity source stays · A-13 the unset owner header: in-app prompt linking to Settings; the PDF carries no owner line; `owner_header_at_generation` NULL and stays NULL for such reports · **Sec R-4 / PM A-6**: §2.6.3 idempotency paragraph, §2.6.3 V1 list, §2.6.4 regeneration paragraph, §2.6.4 V1 list — "overwrite" → "supersede" with PM's exact replacement sentences (pm-findings 12.3): one current report per month, superseded snapshot retained immutable and not user-visible, revision history V2+; App B (f) marked RESOLVED-AT-Lock-11.
- **A-4** no change (the PRD's four commentary names are right; downstream drifted — corrected at R11's home).
- **A-5** φ-1 stands verbatim under R1; the exception wording is withdrawn.

**Consequences recorded:** every §2.6 AC that cites the PRD "verbatim" then cites text that agrees with the Locks (Sec M-5's residual — citation, not implementation — closes). App B / App C rows updated in the same PR. Losing side recorded: the PRD PR grows by one section while A-5's wording waited on R1 — moot now that R1 is ruled.

**Consuming issues:** SELF-364 (vehicle) · P2 · P4 · P5 · P9 (sequenced after).

### R11 — D-4 / Architect F-3: the commentary column identifier · **F/CTO RULING: (a) rename** · 2026-09-04

**Ruled.** A1's fourth commentary column is `commentary_marketable_securities` (with `commentary_cash`, `commentary_bonds`, `commentary_alternatives`); the Zod key and the P3 text-area heading follow (heading text: **Marketable Securities**, PRD §2.6.2 / ADR-058 D7, F/CTO 2026-08-19). Option (b) (keep `commentary_equity`, change only the heading) not taken — a column on an immutable audit-class table is permanent, and the rename is free before the migration lands and a migration after.

**Riders adopted:**
1. The rename is recorded **as a correction to Gate B's ratify text inside the consolidated ADR (R14)**, never by migration alone (PM 12.3; the Decision 18 amendment's own rule that a Gate ratify changing a locked enumeration amends the ADR that holds it).
2. Both `rederived-acs.md` blocks (A1 item 1, P3 item 1) resolve their `⟨RULING D-4⟩` marker to (a) at the amendment batch.
3. `BACKLOG.md` §5.6 and SELF-355's "(Cash / Bonds / Equity / Alternatives)" are corrected to the PRD's four names (agenda §4).

**Consuming issues:** A1 · P3 · P2 (rendering) · P10 (RT-11 leg names the column).

### R12 — PM §6: V1.final's "month of operation"; skipped-commentary months · **F/CTO RULING: definition ratified; (A) a skipped month does not count** · 2026-09-04

**Ruled.** For SELF-365 (PRD §3.4(c), N = 2 consecutive months), a calendar month M **counts** when all six hold: (1) V1 held the tenant's connected and manual accounts for the whole of M — the deploy month never counts; (2) the 1st-of-(M+1) cron fired and created M's pending report, evidenced by the R7 audit row (trigger = cron, `data_as_of` = last day of M); (3) the user **authored** commentary for M and finalized; (4) the user exported M's PDF at least once (the R2 path exercised end-to-end); (5) the §2.6.6 battery (SELF-362) was green on the tree that generated M; (6) the F/CTO attests no reconciliation against the spreadsheet was needed for M — the one criterion that is a statement, not a measurement, and §3.4's own named failure mode. **Two consecutive** = M and M+1 both pass. Earliest V1.final on a greenfield deploy = the close of the second full month after V1.5 ships; the calendar sets it, not the roster.

**Skip ruling: (A).** A month whose commentary was explicitly skipped (all four sub-sections) does not count toward N = 2 — §3.4(c) and SELF-365 AC (c) both say *commentary authoring*; the gate exists to exercise the editor. Options (B) (count if ≥ 1 sub-section authored) and (C) (any finalized report) not taken. Losing side recorded: a month with genuinely nothing to rebalance fails the gate for a reason unrelated to V1's correctness and may add a month to V1.final — accepted as cheap next to a false close.

**Riders adopted:**
1. **A skip is persisted distinguishably from four empty strings** — a V1.5 AC on A1 (a durable authored-vs-skipped fact per report, frozen into the payload) and on P4 (the skip affordance writes it). Not a V1.final AC.
2. What V1.final needs FROM V1.5 to be measurable, now all homed: the R7 audit row with trigger source + `data_as_of` (clause 2); the authored-vs-skipped fact (clause 3); `generated_at` on the final row; the SELF-362 verdict recorded per the SELF-269 precedent (clause 5).
3. SELF-365's AC is re-worded to this definition at the amendment batch (PM drafts; liaison writes).

**Consuming issues:** SELF-365 · A1 · P4 · A7 · P10.

### R13 — Dispatch order · **F/CTO RULING: accepted as listed** · 2026-09-04

**Ruled dispatch order** (the one copy; `rederived-acs.md` and the agenda point here):

```
Track 3 — unblocked today
  1   A8 → P7    owner-identification table + Settings editor (closes Lock 14 5/5, Settings ramp 4/4)   FIRST DISPATCH
  2   A9         NAV component-checkpoint capture (own clock; unmilestoned)                              ∥ 1
  3   PRD §2.6 amendment PR (R10) with SELF-364's §2.5.3 amendments                                      ∥ 1
  4   P9         §2.5 staleness ramp — two routes (taxes/decomposition, taxes/quarterly); NAV leg shipped  after 3
  5   A6         re-scoped RT-22 manifest fence (R6) — lands any time, shape-safe                        ∥ 1
Track 1 — after R1 / R4 / R5 / R7
  6   A1 + A2 + A3   ONE design unit, ONE Sec joint-review; the R7 audit helper drafted inside it;
                     the consolidated ADR (R14) rides A1's PR
  7   A10        on-demand generation write path (R9)                                                    after 6
  8   P2 ∥ P5    in-app render · listing + queue + pending notification                                  after 6 (P5 also after 7)
  9   P3 → P4    commentary editor (copy-from-prior, $ReAlloc side-by-side) → author-before-generate     after 6
  10  P8         §2.6 staleness markers (S-4: app-layer attribution reusing the V1.3 shape)               after 8
Track 2 — after R2
  11  A4 (extend the placeholder; manifest fence first or shape-safe) → A5 → P6                          A4 ∥ 6; P6 after 8
Close
  12  P10        §2.6.6 RLS battery — close-gate, LAST; extended in the same PR as each surface it covers
```

Alternative not taken: A1+A2+A3 first as the critical path with A8→P7 in parallel — declined; the unit's design load (R1/R4/R5/R7 all land in it) makes a small first slice the better opener, and A9's clock argues for early Track 3 anyway.

**Gates carried:** every issue except P8/P9 is Sec joint-review MANDATORY (P4 conditional on landing as control flow inside the reviewed A7); every user-facing issue is walk-gated before the Sec spawn (ADR-063 Decision 4); the A1+A2+A3 unit is one review, not three.

**Consuming issues:** all of V1.5.

### R14 — The consolidated ADR · **F/CTO RULING: Architect authors; rides A1's implementing PR** · 2026-09-04

**Ruled.** One consolidated ADR in the ADR-067 shape, authored by Architect, lands in the A1+A2+A3 design unit's PR under the same Sec joint-review. Contents: **Gate A** (the unified INVOKER read-composition helper's shape — no tenant parameter, R3); **Gate B** (the four named TEXT commentary columns as the locked enumeration, with **R11's rename stated as a correction to the ratify record**); **Gate F** (native Coolify cron container as the mechanism rider on Lock 13 — Lock 13 locks location, not mechanism); **R1** (frozen rendered payload + `payload_schema_version`; the Lock 12 widening as a Lock 12 amendment); **R2** (Lock 13 direction amendment: app pushes finished HTML, worker returns bytes; RT-21's purpose and letters rewritten; the resource-loading fence added to mod #7; N-4's compose-manifest wiring recorded as intra-instance, no ledger effect); **R3** (ARCH :208 narrowed to session context, PDF-scoped); **R4** (Decision 2's reading on Lock 11 — which half applies to which table; the one monotone transition; DELETE blocked); **R5** (label #3 realized dormant, revival condition); **R7** (the general audit helper's posture and its Decision 9 standing); the `generation_status` presentation bridge (R10 A-8). Alternatives not taken: a standalone doc PR before A1 (lands rulings without the DDL that realizes them; the two can drift before A1 merges); PM as author (three items are gate records, but the register is a Lock amendment — Architect's). Losing side recorded: A1 becomes the wave's largest review.

**Riders adopted:**
1. **Ledger discipline in the ADR:** no Decision 3 tally, no §10 count, no DEFINER-allowlist size — read live, Path B; the ADR states which existing labels it realizes (#3, #4) and allocates none.
2. ARCH §3.2's sequence diagram, RT-21's SECURITY row and ARCH :208 are amended in the same PR (doc halves of R2/R3), Sec joint-review covering the whole.
3. Sec N-1 applied: ADR-067 D3 is cited for the veto; the "shape of a measurement" rationale is cited to the V1.4 record or promoted deliberately — never quoted as ADR-067's words.
4. The three off-tree gate rulings are thereby homed; the BACKLOG §7.32 item 4 rule (before calling an absence an omission, ask what the discharge would have looked like) is discharged for A/B/F by construction.

**Consuming issues:** A1 (vehicle) · A2 · A3 · A4 · A5 · A7 · P3.

---

## Default-and-notify (team-lead; reversal window open until the amendment batch merges)

Taken as listed in the agenda's §3 default-and-notify block, none contested at the sitting: the five canonical RT labels placed (RT-11→P3, RT-12→A8/P7, RT-19+RT-25→A3, RT-20→A2 replacing the RT-21 false composite, RT-25→A5/A7/P5/A10) · aal2 step-up clause on A1/A2/A8 per the `090` standard · A5's RT-21 (a)–(g) restored verbatim with the inventions kept as labelled additions and (g) routed to Sec at build (re-derived under R2) · A1's UNIQUE = Lock 11's partial index verbatim · `owner_header_at_generation` on A1 · A3 drops `p_users_id` · cax21 → the Coolify V1 target on A4/A7 · A4 "extend", A7 names `connection.py` · P4 complete-or-explicitly-skip + in-app queue, not Discord · P8 markers live at every render/export · P10 tri-axis only where `tax_treatment` exists, two-axis elsewhere, PRD condition quoted per leg · P6 no PDF of a pending report; filename `mosko-monthly-{YYYY-MM}-{generated_at}.pdf`, never the owner string · P5 "pending = awaiting commentary", no job states · P2 no inline commentary edit (§2.6.2 V2+) · owner header 120-character bound; unset → in-app prompt, no PDF line · commentary CHECK-enforced length bound mirrored in Zod, PM picks the number (Sec N-5) · **A8 Sec joint-review MANDATORY** (Sec R-6; Sec's map governs classification) · S-4 per-section staleness attribution in the app layer reusing the V1.3 shape · A9 tense fix only · A2's `scope` column dropped · the A7 UTC year-boundary second consumer recorded (owner unnamed).

## Ruled dispatch order

See R13 — the one copy.

## Amendment batch (what lands next, in order)

1. **Linear (liaison):** paste each `rederived-acs.md` block as the issue's AC with `⟨RULING⟩` markers resolved to R1–R14; milestone V1.5 on A1–A8 (R8); re-scope SELF-350 (R6); create A10 (R9) with `sec-joint-review`; re-word SELF-365 (R12); comments citing this log by entry.
2. **PRD PR (PM):** the R10 batch + SELF-364.
3. **Close-out PR (team-lead):** `BACKLOG.md` §7.1 A6 text + §5.6 names + §7.32 item 6 conditional + a §7.34 for agenda §6's bookings; `MILESTONES.md` Active Feature (set named, count dropped) + Next deliverable (A8 → P7) + Recent activity; this log's final revision.
4. **First dispatch:** A8 → P7 (R13).
