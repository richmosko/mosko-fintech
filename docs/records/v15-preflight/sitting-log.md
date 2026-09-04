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
