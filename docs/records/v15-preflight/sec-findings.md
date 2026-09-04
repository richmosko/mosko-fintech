# V1.5 pre-flight — Security findings (round 1)

**Baseline:** `origin/main` @ `b90b846` (worktree `security-engineer`, branch `meta/v15-preflight-sec`). Every schema identifier, function name, route, script, workflow and doc anchor cited below was grepped or read at this sha in this session. Nothing from recall.

**Inputs read:** `temp/v15-preflight/issue-dump.md` (md5 `b6f9e76c3420534d10378f2426298409`, verified with `md5` before use) · `BACKLOG.md` §7.1 / §7.2 / §7.32 · `DECISIONS.md` ADR-011 Decisions 1 / 2 / 3 / 4 / 9 / 15 / 16 / 17 / 18 / 19 verbatim including amendments, ADR-013 D1, ADR-035, ADR-050, ADR-066 D1 · `docs/PRD/index.html` `story-2-6-1` … `story-2-6-6` · `docs/SECURITY/index.html` §4.1 / §4.5 RT-11 / RT-12 / RT-21 / RT-22 rows · `supabase/migrations/` 001–105 · `.github/workflows/` · `scripts/ci/` · `workers/` · `api/src/routes/` · `secrets-manifest.yml`.

**Scope.** A bounded consult, not a joint review. No AC drafting, no product calls. Nothing in this file is ruled; items marked `⟨RULING⟩` are owed to F/CTO.

**§10 three-axis cross-check.** ADR-011 Decision 4 read verbatim at `b90b846` before drafting — instance-numbering, layer-attribution and verbatim-vs-paraphrase all checked. **This file does not touch the §10 catalogued-instance ledger: Path B, referenced not copied.** It states no tally of the ledger, of the Decision-3 family, or of the SECURITY DEFINER allowlist; each is read live from the ADR body at review time. One drafted AC *does* assert a ledger figure — see D-1.

⚠ **The §10 CATALOGUED set and the CI-FENCED set are different sets and must not be reconciled.** They overlap on this wave's surfaces (RT-22 is in both), and that coincidence is not identity. Nothing below proposes making them match.

---

## 1. Joint-review map — all 18

Classification predicate is ADR-066 Decision 1 (c), read live: light-loop eligibility requires *Sec-not-mandatory per the ratified map* — ADR-011 Decisions 1–4, a new `SECURITY DEFINER` function, a Decision 3 family extension, auth, secrets, Plaid, multi-tenant isolation, financial calculations. Triggers below are named per `spawn-sec-joint-review`.

| # | Issue | Class | Trigger(s) — named, not inferred |
|---|---|---|---|
| A1 | SELF-345 monthly_report header | **MANDATORY** | D2 (audit-class, Lock 11 immutable + INSERT-new-version) · D3 (the `monthly_report` INTEGER[] instance — see F-1) · **new SECURITY DEFINER** (`fn_supersede_monthly_report`) outside the live allowlist |
| A2 | SELF-346 snapshot child | **MANDATORY** | D2 (audit-class child) · D3 (the `monthly_report_account_snapshot.account_id` instance) · D1-adjacent (`service_role` bypass DB-trigger on the child) |
| A3 | SELF-347 INVOKER read-composition helper | **MANDATORY** | Lock 11 SECURITY INVOKER read-composition default · multi-tenant isolation · financial calculations · Lock 15 server-derived-only fence on `p_data_as_of` |
| A4 | SELF-348 PDF worker container | **MANDATORY** | **Lock 13 mod #2 zero-DB-isolation** (a standing Sec veto trigger) · secrets (`PDF_WORKER_SIGNING_KEY`) |
| A5 | SELF-349 `/internal/pdf-render` | **MANDATORY** | RT-21 HIGH · auth (JWT verification) · secrets · D1 (ingress under no user JWT — see F-4) |
| A6 | SELF-350 RT-22 CI fence | **MANDATORY** | **CI fence change touching a CI-fenced RT.** ⚠ Already built — see D-2 |
| A7 | SELF-351 cron worker | **MANDATORY** | **D1, all four clauses** · D2 (writes an audit-class table) · secrets (`service_role` for tenant enumeration) |
| A8 | SELF-352 `owner_identification` | **MANDATORY** — draft says advisory; I disagree, see F-7 | **Lock 14 family closure** (ADR-011 D18 amendment states its own edits carry mandatory joint-review) · new sensitive tenant-owned `pfin` table ⇒ ADR-029 / `025` aal2 clause · RT-12 is this surface's canonical test |
| A9 | SELF-353 NAV component checkpoint | **MANDATORY** | D3 **new instance** · D2 (new append-only audit-class table) · D1 (cron write-path extension) · aal2 backstop. Self-declared correctly and completely; see the non-objection at §5 |
| P2 | SELF-354 in-app render | **not light-loop-eligible** | ADR-013 **INV-2** — output encoding must span HTML view *and* PDF export; this is the HTML half |
| P3 | SELF-355 commentary editor | **MANDATORY** | **Lock 14 write path** (typed-input validation + mass-assignment prevention) · **RT-11** · ADR-013 INV-1 / INV-2 |
| P4 | SELF-356 author-before-generate | **conditionally light-loop-eligible** | Eligible only if it lands as pure control flow inside an already-Sec-reviewed A7. If it changes how A7 resolves or enumerates tenants, it re-enters D1 and eligibility lapses — that is the ADR-066 mid-arc re-evaluation |
| P5 | SELF-357 on-demand UI + pending queue | **not light-loop-eligible** | New server route (`/api/reports/generate`) that drives a generation path · the pending queue is a cross-tenant read surface (F-8) |
| P6 | SELF-358 PDF export | **MANDATORY** | RT-21 · the client-composed-payload trust boundary (F-5) · INV-2 PDF half |
| P7 | SELF-359 owner-id Settings editor | **MANDATORY** | **Lock 14 write path** · **RT-12** |
| P8 | SELF-360 §2.6 staleness markers | **light-loop-eligible** | No DB surface, no money path, no mandatory surface. Carries M-4 as a correctness finding, not a review trigger |
| P9 | SELF-361 §2.5 staleness ramp | **light-loop-eligible** | Pure frontend ramp of a shipped primitive (`pfin.fn_aggregation_has_stale_constituent`, `046`) onto rendered surfaces. **I do NOT require Sec review of P9.** |
| P10 | SELF-362 RLS battery | **MANDATORY** | Close-gate; the Sec verdict is an AC of the issue itself |

**15 MANDATORY · 2 light-loop-eligible (P8, P9) · 1 conditional (P4).**

---

## 2. Findings

Severity per the standing convention: **veto** = must fix, F/CTO sign-off to override · **flag** = should fix, proceed with a written plan · **note** = worth knowing.

### F-1 — A1 and A2 draft NEW Decision-3 ordinals for two instances that are ALREADY ALLOCATED — flag

**Measured (ADR-011 Decision 3, read verbatim at `b90b846`):** the family's third and fourth labels are held, by name, for exactly these two columns — `pfin.monthly_report.included_reconciliation_event_ids INTEGER[]` → `pfin.reconciliation_event`, and `pfin.monthly_report_account_snapshot.account_id` → `pfin.account`. Both carry status **UNREALIZED — V1.3+**, i.e. canonically-locked but DDL-deferred. Decision 3's own header sentence states which label the *next genuine* instance takes, and it is neither of the numbers the drafts propose.

**Drafted:** A1 — *"matched-tenant trigger on users_id FK per Decision 3 family — 6th instance"*. A2 — *"matched-tenant trigger on FK to parent (Decision 3 family — 7th instance)"*.

Three defects, in increasing order of cost:

1. **The ordinals are stale.** Struck by citation to ADR-011 D3 read live. Per the standing pin, do **not** renumber them to today's next label — these are not new instances at all.
2. **These surfaces realize existing labels; they do not add labels.** Drafting new ordinals would double-count the family and produce two labels for one column. Decision 3's own #17 entry records what that costs: *"a recorded expectation of membership is how a draft label gets invented and then reasoned out of existence."*
3. **A1 names the fence on the wrong column, and the named column cannot fail.** A1's fence is stated as *"matched-tenant trigger on users_id FK"*. `users_id` is the table's **tenant anchor**, not a cross-tenant reference — a matched-tenant fence comparing `new.users_id` to itself is the **leg that cannot fail** that ADR-011 D3 #18 records as the expressly-rejected shape (ADR-062 Decision 2). The column the allocated label actually fences is the INTEGER[] array, which A1's schema does not contain (F-2).

**Requirement, routed to Architect (matched-tenant DDL) with the migration:** the DDL states, per column, which allocated label it realizes and which fence pattern class (P1 / P2 / CR) it uses; no new label is drafted for A1 or A2.

**Open, and a genuine question rather than a defect:** A2's child carries **two** FK-shaped columns — `account_id` (the allocated label) and the FK to the A1 parent. The parent FK also crosses an isolation boundary. Decision 3's rule is written over *any* FK-shaped reference column, so the parent FK needs an explicit disposition: either it is fenced (and if it is a genuinely new relationship it takes the next label, which Architect allocates, not this file), or it is argued out with the reasoning recorded. It cannot be left unstated.

### F-2 — A1 silently drops a canonically-locked V1-SHIP-BLOCK column, and the drop is undischarged — flag

**Measured:** ADR-011 Decision 15 / Lock 11 locks `monthly_report` **with** `included_reconciliation_event_ids INTEGER[]`, and Lock 11 **mod #9** is V1-SHIP-BLOCK: the array-element matched-tenant trigger, on the stated ground that *"cross-tenant `reconciliation_event_id` population is real audit-trail-integrity leak"*. Decision 15 additionally names that column as history a hard-overwrite UPDATE would lose. A1's AC enumerates its columns explicitly and this one is absent.

**I checked what a discharge would have looked like before calling this an omission.** `pfin.reconciliation_event` is live on the tree (`005`), so the target exists — the column is buildable. But ADR-035 superseded SELF-205's reconciliation mechanism (reconciled-by-construction GL; successor is a V1.6 statement tie-out), so there is a real argument the column no longer has a consumer. **That argument is nowhere on the record.** A discharge would have read as an explicit sentence in the AC retiring or re-deferring the instance with its reason. There is none.

The cost of silence is specific: V1.5 is the surface that realizes this table. Shipping it without the column, and without a recorded disposition, converts a *DDL-deferred* instance into a permanently invisible one — nothing downstream will ever surface it again.

**Options, for Architect to pick and F/CTO to ratify (I lean B):**
- **A — Build it.** Column + Lock 11 mod #9 array-element fence as locked. Losing side: ships a fenced column with no V1 consumer, which is fence-cost with no catch.
- **B — Retire the instance explicitly** with an ADR-011 D3 amendment citing ADR-035 as the superseding reason, and a matching note on Decision 15. Losing side: an ADR amendment is real work, and retiring a label needs the same care as allocating one (D3's #5 DROPPED entry is the precedent for retired-in-place, not renumbered).
- **C — Re-defer to V1.6** alongside the statement tie-out that would consume it. Losing side: a DDL-deferred instance on a table that now exists is strictly harder to see than one on a table that does not.

### F-3 — A5's drafted "RT-21 (a)–(g)" is a different set from canonical RT-21 (a)–(g) — flag, high consequence

**Measured, `docs/SECURITY/index.html` RT-21 row, read verbatim:** (a) authenticated-tier JWT only, service_role JWT rejected at signature verification; (b) **dedicated signing key** — Supabase-JWT-signed tokens rejected; (c) **60-second freshness window**; (d) nonce replay protection; (e) no service_role escalation; (f) **dedicated endpoint** — verification logic at `/internal/pdf-render` only; (g) **rejected JWT payloads dropped with a detection signal**.

**A5 drafts:** (a) JWT signature; (b) nonce replay; (c) tenant claim presence; (d) expiry; (e) no service_role escalation; (f) audience check; (g) issuer check.

Only **(e)** agrees by letter and content. A battery built to A5's list and labelled *"RT-21 (a)–(g) full verification battery"* would ship claiming complete RT-21 coverage while omitting four canonical clauses:

- **(b) dedicated signing key.** A5's generic *"JWT signature"* does not require that a *Supabase-issued* JWT is rejected here. That is the whole point of the separate key — without it, any valid Supabase `authenticated` token becomes a render credential.
- **(c) 60-second freshness.** A5's *"expiry"* is not the same control. A token with a one-hour `exp` satisfies "expiry" and fails freshness by a factor of sixty.
- **(f) dedicated-endpoint confinement.** Absent entirely. A5 also routes the endpoint to `/api/internal/pdf-render` while (f) is written over `/internal/pdf-render` — the clause is path-named, so the path change is not cosmetic.
- **(g) detection signal.** Absent, replaced by "issuer check". ⚠ (g) is the clause the SECURITY doc flags hardest: it carries a live design instruction (satisfy ADR-050 Decision 4's catch criterion *under the internal-network threat model*, which the doc says explicitly may differ from RT-05's answer) and it is marked *"Sec joint-review-mandatory at the build."* ADR-050 records RT-21 (g) as inheriting the RT-05 defect unbuilt. Dropping it silently retires the only detection surface this endpoint gets.

A5's inventions — tenant-claim presence, audience, issuer — are good controls and I want them. They are **additions**, not the canonical letters, and must be labelled as such so the letters keep pointing at the catalog.

**Requirement, routed to Backend (endpoint) + QA (battery):** the battery's legs carry the canonical letters with the canonical content; additions are labelled separately. A leg named `(c)` that asserts `exp` rather than a 60-second `iat` window is a red whose message names the wrong defect, and the tempting repair is to loosen the window.

### F-4 — the cron's and the endpoint's tenant-binding mechanism is unstated, and the plausible implementation fails open — flag, highest isolation risk in the wave

**Measured:** A7 requires the cron to invoke A3 *"per-tenant via SECURITY INVOKER tenant-binding (NOT service_role for report data composition; only for tenant enumeration)"*. A5 requires *"tenant binding via `SET LOCAL request.jwt.claims`"*. A3 is `SECURITY INVOKER` and takes `p_users_id UUID` as a parameter.

Under `SECURITY INVOKER`, RLS binds the **role**, not the claims. `service_role` carries `rolbypassrls` — ADR-011 Decision 4's 2026-09-03 amendment states this and its consequence directly: for such a writer *"the effective number of applicable layers … goes to ZERO, not to one"* under the conditions it describes, and *"multiplicity of layers is … a property of a surface AND the writer."* Setting `request.jwt.claims` **without also assuming the `authenticated` role** leaves `rolbypassrls` in force: `auth.uid()` returns the intended tenant, every RLS predicate is skipped, and A3's composition reads **every tenant's rows**. Nothing raises. The report renders. It is a silent full-tenant read, and the surface that catches it does not exist in any drafted AC.

Compounding: A3's `p_users_id` parameter means that when RLS *is* bypassed, the parameter is the **only** tenant fence — which is ADR-011 Decision 1 clause (c) exactly (*tenant correctness derives from code, not RLS*), unacknowledged in A3's AC. And the direct precedent runs the other way: ADR-011 Decision 18's `101` amendment records that the V1.4 replace-all function takes **no tenant parameter** — *"`users_id` from `auth.uid()`, R4 rider 4 / Sec D-2"*. A3 contradicts a ruled precedent on an adjacent surface without naming it.

**⟨RULING R-3⟩ — the app→DB tenant-binding mechanism for non-JWT report generation.** Options:
- **α — Impersonation: `SET LOCAL ROLE authenticated` + `SET LOCAL request.jwt.claims`, per tenant, per transaction.** RLS applies for real; A3 drops `p_users_id` and reads `auth.uid()`, matching the `101` precedent. Losing side: the worker needs a role-assumable login and the connection must be reset between tenants — a leaked `SET` across tenants in a pooled connection is its own leak, so it needs a `RESET ROLE` discipline and a test.
- **β — Keep `service_role` + keep `p_users_id` as the explicit code-layer binding,** and discharge Decision 1 (c) + (d) in full: an explicit binding at the entry boundary plus a same-transaction audit log capturing the tenant-resolution chain. Losing side: RLS is genuinely not a layer here; the fence is code only, which is precisely the posture Decision 4's amendment warns reads as defence-in-depth and is not.
- **γ — Neither: the cron enqueues per-tenant jobs that execute under a real user session.** Losing side: needs a session-minting path, which is a larger auth surface than the problem.

I lean **α** — it is the only option where the DB is a layer rather than a witness, and it makes A3 match the `101` precedent instead of contradicting it. **Losing side of α, named:** it puts a role-assumable identity on the cron host, and `055`'s deliberately non-owner ETL identity exists to keep that surface small; α expands it and that expansion needs its own review.

**Catch criterion (whichever option lands), routed to QA:** a two-tenant fixture where the worker runs for tenant A and tenant B's rows exist; the leg asserts the composed output contains **zero** tenant-B rows. ⚠ This leg goes vacuous if the fixture has no tenant-B rows, and vacuous is the default state of a fresh fixture — the battery needs a **positive control** proving the leg reds when the binding is struck.

### F-5 — A5 accepts a client-composed report payload; the trust boundary is unstated — flag

**Measured:** A5 *"accepts JWT-bearer signed by V1 app + JSON payload (composed report)"*; P6 *"invokes A5 endpoint with composed JSON payload + JWT-bearer"* from a **browser button**. A4 *"composes HTML from JSON payload"*.

As drafted, the *content* of the PDF is supplied by the caller and the JWT authenticates only *that a caller may render*. A holder of a valid render JWT can therefore render arbitrary content, including another tenant's figures if they can obtain them by any other means, and the resulting PDF carries the owner-identification header of whoever the payload says. Nothing in A5's AC requires the server to re-derive the payload from A3 for the `(users_id, target_month)` in the JWT.

**Requirement, routed to Backend:** the endpoint derives the payload server-side from A3 under the JWT's tenant, or the AC records explicitly why the client-supplied payload is trusted and what bounds it. **Catch criterion:** POST a well-formed JWT for tenant A with a payload containing tenant B's figures; assert 4xx, or assert the rendered PDF contains tenant A's server-derived figures and none of the submitted ones.

### F-6 — the RT-22 fence cannot see the way a real Node app installs `pg` — flag, and this is the live V1.5 work

**Measured:** `scripts/ci/fence-rt22-pdf-worker-dockerfile.sh` criterion (ii) matches `RUN` lines invoking `apt/apk/pip/npm/yarn/pnpm` install verbs. Its own header names what it deliberately does not catch: *"COPY of package.json / requirements.txt manifests (install intent revealed at RUN time, not COPY time; manifest inspection is human-second-line)"*.

Today `workers/pdf-render/Dockerfile` is a placeholder whose `CMD` is `node --version`, so the exclusion is harmless. The moment A4 lands a real Puppeteer application, the standard shape is `COPY package*.json .` then `RUN npm ci` — and `npm ci` installs whatever `package.json` names. **`pg` can enter the container through a path the fence is documented not to look at, and the fence reports clean.** Lock 13 mod #2's *"no Postgres client installed"* would be false while its watcher is green.

Separately, `scripts/ci/fence-tbc-node.sh` is explicitly scoped to `workers/provider-sync/` and its header records *why* — pdf-render *"has ZERO DB reach"*. That reasoning is sound today and is a **premise, not a control**: no fence audits Node source under `workers/pdf-render/src/` for client construction, because none is expected to exist.

**Requirement, routed to DevOps (fence) + QA (fixture):** extend RT-22's catch criterion to the dependency manifest — `workers/pdf-render/package.json` and its lockfile — for Postgres client packages (`pg`, `postgres`, `node-postgres`, `@supabase/supabase-js`, `knex`/`sequelize`-class packages that bundle a driver), **paired with a golden violation fixture**, exactly as the existing Dockerfile fence is paired today. A fence that does not fail closed is theatre; the existing RT-22 job already proves the pattern by running an inversion-mode step against `tests/fixtures/ci/rt22-violation.Dockerfile`, and the extension must carry the same.

**This — not "build the fence" — is what A6 should be.** See D-2.

### F-7 — A8 classifies itself out of a mandatory surface — flag

A8's AC reads *"Sec advisory (not joint-review — single-column user-scoped table with no chain)."* I do not accept that classification, and I am naming it as my own judgment call so F/CTO can overrule it:

- Lock 14 user-facing settings write-paths are on the standing joint-review-mandatory list. ADR-011 Decision 18's own family-size amendment states of itself: *"this amendment edits an ADR-011 Decision-18 surface and touches Lock 14, so it carries Sec's mandatory joint-review."* A8 closes that family's enumeration.
- **RT-12** is the named canonical test for this exact surface (`docs/SECURITY/index.html` §4.1, axis iv: *"the §2.6.4 owner-identification settings-store write path (RT-12)"*). A8 and P7 cite neither RT-12 nor RT-11 — see D-3.
- The table is a new sensitive tenant-owned `pfin` table and therefore inherits the ADR-029 / `025` aal2 step-up backstop obligation — see F-9.

"No chain" is true and is not the predicate. The predicate is Lock 14 membership, and A8 is the fifth member.

### F-8 — the pending queue is an unscoped enumeration surface — note

P5 ships a *"pending queue [that] shows reports queued/in-flight/done"*. Nothing in the AC scopes that read to the requesting tenant, and a queue is exactly the shape that leaks existence (row counts, timing, target months) even when it leaks no values. **Requirement, routed to Backend + QA:** the queue read is tenant-scoped at the DB layer and the P10 battery carries a leg asserting tenant A sees zero of tenant B's queue entries. Low cost to state now; the reason it is a `note` and not a `flag` is that the natural implementation (read `monthly_report` under RLS) is scoped by construction — I want it asserted, not redesigned.

### F-9 — three new sensitive tenant-owned `pfin` tables, and only one AC names the aal2 backstop — flag

**Measured:** `grep -rl 'aal2' supabase/migrations/` returns 49 migrations at `b90b846`; `101` names it as *"C3 standing obligation"*. Across the 18 drafted ACs, the string `aal2` appears **exactly once** — in A9, which also explains why it is stated there: *"invisible once omitted, which is why it is named here and not only there."*

A1, A2 and A8 each introduce a new sensitive tenant-owned `pfin` table with `authenticated` policies, and none names the clause. A9's own sentence is the evidence that naming it in the AC is the convention, and that its absence is the failure mode rather than a stylistic gap.

**Requirement, routed to Architect (DDL) + QA (battery):** every `authenticated` policy on the A1 / A2 / A8 tables carries the ADR-029 / `025` aal2 step-up clause, or the migration records which documented exclusion applies. **Catch criterion:** a totp/passkey-enrolled caller presenting a below-aal2 JWT lands on the refusal leg — and note that this leg and the cross-tenant leg are *different* legs; a battery that only tests cross-tenant will pass with the aal2 clause absent.

---

## 3. Money / isolation flags

### M-1 — the owner-identification header is drafted as a LIVE read, and the PRD resolved it the other way — flag

**PRD §2.6.4, verbatim, under the heading *"Owner-identification at render time — snapshot, not live"*:** *"Open product call within ψ-1, resolved as V1 contract: when a historical report renders (in-app view or PDF export), the owner-identification header reads from the snapshot, not live from the settings store. If F/CTO renames the trust mid-year, prior historical reports continue to show the prior name … Live-read would mean historical reports retroactively re-label every time the settings string changed, which contradicts the frozen-snapshot framing under φ-1."*

**ADR-011 Decision 15, verbatim:** a hard-overwrite UPDATE *"would lose `included_reconciliation_event_ids` + `owner_header_at_generation` history."* The ADR names the snapshot column by name.

**Drafted:** A8 — *"Downstream: … A3 helper reads for §2.6.1 report header."* A3 — composes the header with no snapshot column named. A1's column list contains no `owner_header_at_generation`.

Every historical report re-labels itself the next time the settings string changes. On an audit-class artifact whose entire product premise is *"a stable, archived record of the month as the user closed it"* (§2.6.4 verbatim), that is a retroactive restatement of a compliance-shaped document, and it is silent. **Requirement:** A1 carries `owner_header_at_generation`; A3 reads it for any report that is not being generated in this call. Routed to Architect (schema) + Backend (read path).

### M-2 — commentary and owner-header text are rendered by two different engines, and only one of them escapes — flag

**ADR-013 D1, verbatim:** *"INV-1 — plain-text-only commentary/owner-id is security-load-bearing … INV-2 — output-encoding must span HTML view + PDF export and couples to Appendix-B flag (a) (PDF render-path open). RT-11 (commentary) + RT-12 (owner-id) land at the mandatory §4 Sec authoring."*

The wave introduces: four commentary `TEXT` columns (A1, unbounded), `owner_id_header_text` (A8), and it inherits `schedule_label` (`101`, up to 500 characters of user prose, forwarded unmodified into the tax payload per SELF-262). All three reach **two** renderers — SvelteKit (P2, escapes by default) and the Node PDF worker (A4, *"composes HTML from JSON payload"*, no escaping control named anywhere in A4, A5 or P6).

`BACKLOG.md` §7.32 item 6 already books this correctly and Sec-raised: *"Escaping in Svelte does not transfer to the worker."* Its AC is the right shape — *"a test that stores `<script>` and proves the rendered PDF/HTML carries it inert."* Two problems with relying on it as-is:

1. **It has no Linear issue.** It is a `BACKLOG.md` §7.32 booking listing SELF-345–362 as *dependencies*; it is not among the 18 promoted. Nothing will schedule it. See ⟨RULING R-5⟩.
2. **Its scope predates the fields.** It was written against `schedule_label`. The four commentary columns and `owner_id_header_text` did not exist when it was drafted. Its *"and every other free-text field in that payload"* clause reaches them by construction, which is good drafting — but that is worth stating rather than assuming, because a reader checking coverage will look for the field names.

**Requirement, routed to Backend (worker) + QA (battery):** the escaping control lives in the PDF worker, is asserted per free-text field, and the assertion is on the **rendered output** (the PDF/HTML carries the payload inert), not on the payload. ⚠ INV-1 says plain-text-only is *security-load-bearing* — so a future markdown affordance on commentary is a Sec re-touch, not a refinement. P3 states this correctly; keep the sentence.

### M-3 — P10's tri-axis is CONDITIONAL in the PRD and unconditional in the AC — flag

The brief asks whether P10's *"tri-axis tenant × scope × tax_treatment"* is a stale V1.4 transplant. **It is not stale — it is in PRD §2.6.6 verbatim — but the AC drops the condition that makes it correct.** The source sentence:

> *"§2.6.6 inherits the §2.5.5 tri-axis tenant_id × scope × tax_treatment framing **where the underlying classes carry tax-treatment** (e.g., snapshotted tax-bracket-derived values inherit the §2.5.5 axis); **for §2.6.1 surfaces with no tax-treatment dimension, the tri-axis collapses to the tenant_id × scope pair.**"*

P10 drafts it as *"Tri-axis orthogonality (tenant × scope × tax_treatment) verified per PRD §2.6.6 verbatim"* — asserting uniformly what the PRD asserts conditionally. A battery built that way puts a `tax_treatment` axis over surfaces that carry no such dimension, and those legs cannot fail. **A leg that cannot fail is the tell.**

The same sentence also settles the derivative-surface framing the brief asks about: §2.6.6 says the snapshot store *"is not a new sensitive-data class … §4 Sec materials should annotate the snapshot row as a derivative-surface entry rather than treating it as a fresh classification."* P10 states this correctly (*"NOT new SD class"*) and A2 states it as *"SD-12 child sub-class addendum"*, which is consistent with ADR-011 Decision 16's `SD-12 child sub-class addendum`. **No new SD class is required and I do not require one.**

**Requirement, routed to QA:** the battery is tri-axis on tax-treatment-carrying surfaces and two-axis elsewhere, and the split is stated per-leg with the PRD condition quoted, so a future reader cannot "fix" the asymmetry into uniformity.

### M-4 — P8 marks staleness at generation time; the PRD resolved it as a live read — flag

**PRD §2.6.4, verbatim, under *"Staleness-marker live-read carve-out"*:** *"§2.6.5 staleness markers are the deliberate exception to the otherwise snapshot-driven render path: staleness markers are read live at render time from the §2.4.4 credential-error state, not from the snapshot. A snapshot may carry data from an account that later went stale; when the in-app view renders that snapshot in the future, it shows the current staleness state, not the historical state at generation time."*

**P8 drafts:** *"when stale-Plaid-item constituents present **at generation time**, report renders with `<StaleConstituentBadge>`."*

The failure direction is toward silence: a report generated while every item was healthy, viewed a month later when an item is pending re-auth, shows **no badge**. That is the §2.4.4 headline commitment inverted — *"Aggregations are never silently presented as fresh when constituent accounts are pending re-auth"* (SELF-208, PRD §2.4.4 verbatim). The product call is PM's; I am flagging it because the direction of the error is the one the framework exists to prevent, and because P8's `at generation time` wording will read as deliberate to whoever implements it.

### M-5 — PRD §2.6.3/§2.6.4 say overwrite; ADR-011 Decision 15 says immutable INSERT-new-version — flag

**PRD §2.6.4, verbatim:** *"§2.6.3 locked overwrite-semantics regeneration (no revision history V1); §2.6.4 honors this — regeneration of a month overwrites the prior snapshot for that month, and only one snapshot per (tenant, target-month) tuple exists at any time in V1."*

**ADR-011 Decision 2, verbatim:** rows on audit-class surfaces are *"append-only at the RLS policy + DB-trigger layer (UPDATE/DELETE blocked across both `authenticated` AND `service_role` roles)"*, with Lock 11 named as a ratified surface. Decision 15 locks INSERT-new-version regeneration and states the reason: a hard-overwrite UPDATE loses history.

These are irreconcilable, the ADR is later and states the reason it overrode the PRD, and the drafted ACs correctly follow the ADR (A1, P2, P5). **The residual risk is citation, not implementation:** every §2.6 AC in this wave cites the PRD as *"verbatim"* source, and PRD §2.6.4's overwrite sentences are still there for a builder to read and act on. See ⟨RULING R-4⟩ — this is a PRD recalibration booking, and the standing project note that PRD/ARCH predate the current feature set applies directly.

**Adjacent, same class:** P2's *"Live-recompute on upstream surface changes when viewing latest report"* contradicts §2.6.4's φ-1 *"The report freezes the §2.1–§2.5 surfaces at the moment of generation."* Product call is PM's; I flag it because a document that silently changes its own figures after issue is a misstatement surface regardless of which way it is ruled.

### M-6 — PDF bytes at rest: not a V1 surface, stated explicitly — non-objection

**PRD §2.6.4, verbatim:** *"the PDF export re-generates the PDF from the snapshot data each time the user clicks export — no PDF caching V1."* P6's AC matches (receive bytes, serve as download; nothing persisted). **I do NOT require a storage bucket, storage RLS, or an SD entry for PDF artifacts at V1.** Standing condition, because this is exactly the kind of non-objection that goes stale: the first AC that persists a rendered PDF creates a new storage-class surface and is Sec-joint-review-mandatory at that PR.

---

## 4. Stale labels, counts and citations in the drafts

Each struck by citation to the live source. **None is renumbered here** — renumbering a stale ordinal is how a wrong number gets laundered into canon.

### D-1 — A6 asserts a §10 ledger figure that is stale, and weakens the fence it re-specifies — **veto if built as drafted**

**Drafted (SELF-350, and identically in `BACKLOG.md` §7.1 A6 line 300 — so the defect is in the promotion source, not a Linear transcription):**
> *"CI script greps A4 PDF worker Dockerfile for forbidden patterns: `SUPABASE_*` env vars (**other than `SUPABASE_URL`**) … Closes RT-22 catalogued §10 instance #1 (Wave 1 E1 closed RT-26 #2 instance; **both catalogued instances** now have V1 CI automation)."*

Two independent defects:

1. **"both catalogued instances" is false.** ADR-011 Decision 4 read verbatim at `b90b846` enumerates a third catalogued instance (RT-27, network-exposure/config layer, catalogued at F/CTO ratify 2026-07-19), and states the count explicitly. `docs/SECURITY/index.html` §4.5 carries the same figure and the same *"§10 ledger UNCHANGED"* discipline note. The AC's parenthetical is the long-running "ledger 2" drift. **Struck by citation; the AC should carry no figure at all** — Path B, let the link carry it. Do not restore a number.
2. **The `SUPABASE_URL` carve-out weakens a live fence — this is the veto.** Lock 13 mod #2 verbatim (quoted inside ADR-011 Decision 4's own Privileged-context-surfaces bullet) is *"no `SUPABASE_*` env vars in PDF worker container"* — no exception. The shipped fence implements it without exception: criterion (i) is `grep -nE '^[[:space:]]*(ENV|ARG)[[:space:]]+SUPABASE_'`, which rejects `SUPABASE_URL`. A PR implementing A6 as drafted would **loosen a fence that is live, run-always and fail-closed today.** I veto that change. `SUPABASE_URL` in a container with zero DB reach has no consumer; admitting it re-opens the namespace the fence exists to keep empty.

Also missing from the AC and present in the shipped job: the **inversion-mode golden fixture** step. An AC that re-specs the fence without it, landing as a replacement, would remove the only thing that proves the fence can still bite.

### D-2 — A6 is already built; A4 is partly built — flag

**Measured at `b90b846`:**
- `scripts/ci/fence-rt22-pdf-worker-dockerfile.sh` exists (fail-closed, exit 1 on violation, exit 2 on unreadable target).
- `.github/workflows/security-scan.yml` job `fence-rt22` runs it in **production mode** against `workers/pdf-render/Dockerfile` and in **inversion mode** against `tests/fixtures/ci/rt22-violation.Dockerfile`, failing the build if the fence reports clean against the violation fixture.
- `grep -rhoE 'RT-[0-9]{2}' .github/workflows/` returns RT-22 among the CI-fenced set. ⚠ That set is not the §10 catalogued set and must not be reconciled with it; RT-22's membership in both is coincidence, not identity.
- `workers/pdf-render/` contains `Dockerfile` and `.env.example` — the Dockerfile self-describes as *"a PLACEHOLDER Dockerfile shipped as part of Phase 5 Step 4 W1 so the RT-22 fence has a real target to audit (rather than no-op'ing when the Dockerfile doesn't exist)."* `docs/SECURITY/index.html`'s RT-21 row states the same measurement independently: *"`workers/pdf-render/` holds a Dockerfile and a `.env.example` and nothing else, there is no `/internal/pdf-render` route, and `PDF_WORKER_SIGNING_KEY` has no consumer in source."*

So A6's premise — *"deferred from Wave 1"*, fence unbuilt — is false, and A4 is a partial scaffold rather than greenfield. **A5 is genuinely unbuilt** and that half of the wave is correctly scoped.

**⟨RULING R-2⟩ — A6's disposition.** Options: **(i)** close SELF-350 as already-discharged and open the F-6 manifest extension as its successor; **(ii)** re-scope SELF-350 in place to the F-6 manifest extension, keeping the issue id and its `sec-joint-review` label. I lean **(ii)** — it keeps the RT-22 work under one id and the dependency edges from A4 stay valid. **Losing side of (ii):** the issue's title and history then describe work that was already done, which is exactly the sort of drift this pass exists to catch; if it is re-scoped, the AC must say so in its first sentence.

### D-3 — five canonical RT labels for these exact surfaces appear in none of the 18 drafts — flag

`grep -ohE 'RT-[0-9]{2}'` over the issue dump returns only RT-21, RT-22, RT-23, RT-24, RT-26. Absent, each measured as the named canonical test for a surface this wave builds:

| Missing | Canonical scope (source read verbatim) | Wave surface |
|---|---|---|
| **RT-11** | SECURITY §4.1 axis iv — *"the §2.6.2 commentary write path (RT-11)"* | P3 |
| **RT-12** | SECURITY §4.1 axis iv — *"the §2.6.4 owner-identification settings-store write path (RT-12)"* | A8, P7 |
| **RT-19** | ADR-011 Decision 15 — read-time composition tenant-scoping | A3 |
| **RT-20** | ADR-011 Decision 16 — *"new RT-20 HIGH (fourth-instance FK-bypass + service_role bypass + parent immutability extension)"* | A2 |
| **RT-25** | ADR-011 Decision 19 — as-of-date adversarial / parameter-bypass input | A3, A5, A7 (`p_data_as_of`) |

⚠ **A2 additionally makes a false-composite citation.** It reads *"RT-21 HIGH + SD-12 child sub-class addendum"*. RT-21 is real (PDF worker JWT) and Lock 12 is real, but the pairing is not: Decision 16 names **RT-20** as this surface's new test, and RT-21 belongs to a different surface entirely. This is the exact class ADR-011 Decision 4's PR #476 bullet records — *"Right content, wrong pointer — a false composite … which is exactly why it survives every spot-check."* Built as drafted, the RT-20 battery is never written and nothing notices, because an RT-21 battery *will* exist and will be green.

**Requirement, routed to QA + PM (AC text):** each surface's AC names its canonical RT label. The P10 battery's coverage list is the natural place to catch the omissions in one pass.

### D-4 — the commentary sub-section label is stale against a ratified rename — note

**PRD §2.6.2 verbatim:** *"V1 renders the Rebalancing Targets editor under four fixed sub-sections: Cash, Bonds, **Marketable Securities**, and Alternatives — … (F/CTO-ratified 2026-08-19: the sub-section label follows the §2.2.1 Cat rename per ADR-058 Decision 7 — Cat-alignment wins over literal label parity …)."*

A1 drafts the column `commentary_equity`; P3 drafts the text area *"Equity"*. Both predate the 2026-08-19 ratify. Low security weight, but it lands in **DDL** — a column name is expensive to change later on an immutable audit-class table. Routed to Architect + PM; I have no security objection to either name and raise it only because it is a stale label in a drafted schema.

### D-5 — A1's UNIQUE constraint is not the locked one, and the difference breaks regeneration — flag

**ADR-011 Decisions 2 and 15, verbatim (both):** *"partial UNIQUE on `(users_id, target_month) WHERE generation_status = 'final'`"*.

**A1 drafts:** *"UNIQUE(users_id, target_month, generation_status) for `final`"*.

These are different constraints. A three-column UNIQUE forbids two rows sharing `(users_id, target_month, generation_status)` for **every** status value — so a month can hold at most one `superseded` row and at most one `draft` row. INSERT-new-version regeneration produces a *chain* of superseded versions; the second regeneration of any month would fail on a duplicate key. The locked partial index constrains only `final` and leaves the chain free, which is why it is written that way.

**Requirement, routed to Architect:** the DDL carries the locked partial-UNIQUE verbatim. **Catch criterion, routed to QA:** regenerate the same month **three** times and assert three rows exist with exactly one `final`. A two-regeneration leg passes against the defective constraint and is the leg most likely to be written.

---

## 5. Explicit non-objections

Stated because an unstated non-objection reads as an unexamined surface.

- **I do NOT require a new SD class for the snapshot store.** PRD §2.6.6 resolves it as a derivative surface; ADR-011 Decision 16's `SD-12 child sub-class addendum` is the correct home. A2 and P10 both state this correctly.
- **I do NOT require Sec review of P9 (SELF-361).** It ramps a shipped primitive (`pfin.fn_aggregation_has_stale_constituent`, `046`) onto rendered surfaces. No DB surface, no money path, no mandatory-map surface. Light-loop-eligible.
- **I do NOT require PDF-artifact storage controls at V1** (M-6), on the stated §2.6.4 no-caching contract, with the named standing condition.
- **`secrets-manifest.yml` is clean for this wave.** `PDF_WORKER_SIGNING_KEY` is production-only (line 127) and `PDF_WORKER_SIGNING_KEY_TEST` is CI-only (line 98) — **disjoint sets, distinct names**, no overlap. No new secret is required by any of the 18 as drafted. **I raise no secrets-manifest objection.**
- **A9 (SELF-353) is the best-drafted issue in the wave and I require no change to it.** It names its own Decision-3 membership without drafting a label, names the aal2 backstop, names the Σ(leaves)↔scalar reconciliation leg, and names the migration-gate set by reference to ADR-054's Governance block rather than restating it. It is the model the other eight A-items should follow.
- **The `TenantBoundConnection` / TBC-node fences are untouched by this wave as drafted**, and I do not require changes to them — with F-6's caveat that `workers/pdf-render/`'s exclusion from TBC-node rests on a premise (zero DB reach) that A4 could falsify without any fence noticing.
- **P4's author-before-generate gating is not a security control and I do not treat it as one.** Skipping generation when commentary is absent is a product behaviour; nothing about it fences a tenant.

---

## 6. Buildable as drafted

**Definition (stated because a bare count is uninterpretable):** an issue is *buildable as drafted* if a competent implementer following its AC verbatim would produce a surface I would pass at joint review **without a correction that changes the AC's stated schema, fence shape, test label, tenant-binding mechanism, or review classification.** Ordinary implementation detail left to the builder does not count against it.

**3 of 18 — A9, P4, P9.**

The other 15 each carry at least one correction of that grade, itemised above: A1 (F-1, F-2, D-5, M-1, F-9, plus the DEFINER question at R-1) · A2 (F-1, D-3 false composite, F-9) · A3 (F-4, D-3) · A4 (D-2, F-6) · A5 (F-3, F-5) · A6 (D-1 **veto**, D-2) · A7 (F-4) · A8 (F-7, F-9, D-3) · P2 (M-5 adjacent) · P3 (D-3, D-4, M-2) · P5 (F-8) · P6 (F-5, M-2) · P7 (D-3) · P8 (M-4) · P10 (M-3, D-3).

⚠ This number is a statement about **AC text at `b90b846`**, not about difficulty. Most of these are one-sentence corrections. The reason to make them before dispatch rather than at review is that four of them (F-1's ordinals, F-3's letters, D-1's ledger figure, D-3's labels) would otherwise land in migration headers, `comment on` text and battery leg names — where a wrong label reads as canon and is corrected rather than scoped.

---

## 7. Rulings owed to F/CTO

- **⟨RULING R-1⟩ — the supersession mechanism on an immutable table.** A1 drafts *"supersession via SECURITY DEFINER `fn_supersede_monthly_report`"*. Two problems. (i) It is a **new SECURITY DEFINER function outside the V1 allowlist** (ADR-011 Decision 9 and its amendments, read live) with no justification recorded; additions of this kind are Sec-joint-review-mandatory and carry an ADR-amendment obligation that no AC books. (ii) The function exists because Decision 2 blocks UPDATE on this table *"across both `authenticated` AND `service_role` roles"* — yet flipping `generation_status` from `final` to `superseded` **is** an UPDATE. Nothing in Lock 11's nine mods mentions a DEFINER supersession function; it is draft-invented, and it is the shape you reach for when an immutability fence is in the way.
  - **A — Supersession is DERIVED, not stored.** The locked partial-UNIQUE already makes "the current final" unambiguous; `superseded` becomes a presentation label computed from `(target_month, generated_at)` ordering. **No UPDATE, no DEFINER, no allowlist change, Decision 2 untouched.** *Losing side:* `generation_status` no longer carries the full locked vocabulary as stored state, and any consumer that expects to read `'superseded'` from the column must be changed.
  - **B — A narrow UPDATE exemption on `generation_status` only,** with the immutability trigger fencing every other column. *Losing side:* Decision 2's blanket append-only claim stops being true of this table and the ADR must say so; and an exemption on one column is an exemption a future column joins.
  - **C — DEFINER function as drafted,** with an ADR-011 Decision 9 amendment extending the allowlist and recording the rationale. *Losing side:* grows the elevated-privilege surface for a status flip, and Decision 9's own history shows the allowlist is the thing that stays tight by being defended per entry.
  - **I lean A.** It is the only option where nothing is added and nothing is weakened. **Named losing side of A:** it moves a concept from the schema into the read path, and read-path concepts are easier to get silently wrong than columns.
- **⟨RULING R-2⟩ — A6's disposition** (already built): close-and-successor vs re-scope-in-place. Lean (ii). Detail at D-2.
- **⟨RULING R-3⟩ — the non-JWT tenant-binding mechanism** for A3/A5/A7. Options α/β/γ, lean α. Detail at F-4. **This is the ruling with the largest isolation consequence in the wave.**
- **⟨RULING R-4⟩ — PRD §2.6.3/§2.6.4 overwrite-semantics vs ADR-011 Decision 15.** The ADR governs and the ACs follow it; what is owed is whether the PRD text is corrected now (a recalibration edit, PM/Architect vehicle) or left with a supersession pointer. I have no security preference between the two vehicles — I object only to leaving both texts live and unmarked, because every §2.6 AC cites the PRD as *"verbatim"*. Detail at M-5.
- **⟨RULING R-5⟩ — promotion of `BACKLOG.md` §7.32 item 6** (the PDF-worker escaping control). It is Sec-raised, correctly scoped, names SELF-345–362 as dependencies, and has **no Linear issue**, so nothing will schedule it. Options: promote as a 19th V1.5 issue, or fold its AC into P6 (which is where the payload is rendered). I lean **fold into P6** — the control and its only consumer then share a review. *Losing side:* folding hides a Sec-raised item inside a product issue, and the §7.32 booking is the only record that it was raised independently.
- **⟨RULING R-6⟩ — A8's review classification**, advisory (as drafted) vs mandatory (my call). Detail at F-7. I have stated my reasoning; F/CTO has final authority.

---

## 8. Catch criteria — one per MANDATORY surface

The single test that would catch a real violation, for the P10 battery to absorb. Each is written so that it can fail; where a leg can go vacuous, the vacuity condition is named.

| Surface | Catch criterion | Vacuity risk |
|---|---|---|
| A1 | Regenerate one month **three** times; assert three rows, exactly one `final`. | Two regenerations pass against the defective constraint (D-5). |
| A1 | Attempt an UPDATE on a `final` row as `authenticated` **and** as `service_role`; both refused. | A leg testing only `authenticated` passes with the service_role fence absent. |
| A2 | Insert a child row whose `account_id` belongs to another tenant (ownership forge: the caller's own parent, a foreign `account_id`); the fence raises **before** RLS `WITH CHECK`. | If the fixture holds no second-tenant account, the leg cannot fail. |
| A2 | UPDATE the parent's `users_id` and `target_month` post-creation; both refused (Decision 16's parent-immutability extension). | Testing only `users_id` misses `target_month`, which the lock names alongside it. |
| A3 | Two-tenant fixture; compose for tenant A; assert **zero** tenant-B rows in the output. | Vacuous without tenant-B rows — needs a positive control that reds when the binding is struck (F-4). |
| A3 | Supply a client-asserted `p_data_as_of`; assert the §2.6 path refuses it (Lock 15 server-derived-only fence). | — |
| A4 | Add `pg` to `workers/pdf-render/package.json`; assert CI **fails**. Golden fixture, paired with the existing Dockerfile inversion fixture. | Without the fixture the fence is unvalidated — the false-green class (F-6). |
| A5 | (b) A valid **Supabase-issued** `authenticated` JWT is rejected at this endpoint. | A generic "bad signature" leg passes without this. |
| A5 | (c) A JWT with `iat` 61 seconds old is rejected; one 59 seconds old is accepted. **Boundary pair.** | An `exp`-based leg passes with no freshness window at all (F-3). |
| A5 | (d) Replay a previously-accepted nonce; rejected. | — |
| A5 | (g) A rejected JWT produces a retained, queryable signal that survives container-log rotation. | — |
| A6 | The fence reports **violation** against the golden fixture (inversion mode) — already shipped; preserve it verbatim through any re-scope. | Removing this step makes every green run uninformative. |
| A7 | Run the cron for tenant A with tenant B's data present; assert B's report is not written and B's rows are not read. | Needs a second tenant with data — the same vacuity as A3. |
| A7 | Assert the same-transaction audit row exists and names the resolved tenant (Decision 1 clause (d)). | — |
| A8 / P7 | POST `{users_id: <foreign>, owner_id_header_text: "x"}`; rejected by Zod `.strict()` with 400 **before** the DB layer, and `users_id` taken from `auth.uid()` (RT-12 / Lock 14 mod #1). | — |
| A8 | A totp/passkey-enrolled caller below aal2 is refused by the policy (F-9). | Distinct leg from cross-tenant; a cross-tenant-only battery passes with the clause absent. |
| A9 | As drafted at SELF-353 — I require no addition. | — |
| P3 | Store `<script>alert(1)</script>` in a commentary field; assert it renders **inert in the PDF** (not only in the HTML view). INV-2 spans both engines. | An HTML-only leg is green while the PDF path is unescaped (M-2). |
| P5 | Tenant A's queue read returns zero of tenant B's entries (F-8). | — |
| P6 | POST a valid tenant-A JWT with a payload carrying tenant-B figures; assert refusal, or assert server-derived tenant-A output (F-5). | — |
| P10 | Tri-axis on tax-treatment-carrying surfaces; **two-axis** where the dimension does not exist, with the PRD condition quoted per leg (M-3). | A uniform tri-axis battery ships legs that cannot fail. |

---

## 9. Method note

Every count in this file states what it is over. No count is stated over the Decision-3 family, the §10 catalogued ledger, or the SECURITY DEFINER allowlist — all three are read live from `DECISIONS.md` at review time, and this file cites them by shape rather than by tally, deliberately.

One drafted assertion I checked and did **not** find defective, recorded because an unstated check reads as an unexamined one: A4's claim that *"TenantBoundConnection fence (Wave 1 E2) applies to `pfin_back_etl` Python; PDF worker has NO DB connection so no TBC fence needed"* is consistent with `scripts/ci/fence-tbc-node.sh`'s own header at `b90b846`, which records the same reasoning. It is true today and is a premise rather than a control — F-6 names the condition under which it stops holding.

---
---

# Round 2

**Sibling refs, re-read from `origin` in this session — not taken from the round-2 brief.**

| Ref | sha | Artifact | md5 (from the ref) |
|---|---|---|---|
| `origin/meta/v15-preflight-arch` | `66288e0` | `architect-findings.md` | `d43968e7795e0bd65842d8a20819bd5c` |
| " | " | `rederived-acs.md` | `f3335c4840b22dabb5cdeb665b6651f1` |
| `origin/meta/v15-preflight-pm` | `4c9f628` | `pm-findings.md` | `06db14a407c89cf5dedc4ecfffb39c5d` |

All three agree with the brief. `git merge-base origin/main <each>` = `b90b846` for both siblings, and `git diff --stat origin/main <each>` shows each touches only its own records file and its own agent-memory — **no carried sibling blobs, no cross-contamination**, so the baseline this file was written against is still the baseline all three describe. `origin/main` re-read at the start of this pass: unmoved at `b90b846`.

Sibling findings are cited **by their own ids and never restated**. Where I confirm one, I say so and stop; where my round-1 text is now wrong, I say *retracted* and say why. Nothing below re-decides a ratified lock.

**§10 three-axis cross-check re-run** against ADR-011 Decision 4 read live at `b90b846` before drafting this section. Round 2 touches the ledger by reference only — still Path B. It states no ledger tally. ⚠ The catalogued set and the CI-fenced set remain different sets and are not reconciled here; N-4 below concerns the CI-fenced side only and explicitly does not move the catalogued side.

---

## R2.1 — Position on S-1 (Architect `S-1` = PM `A-5`)

**I confirm the seam and I confirm it is a one-way door.** My round-1 M-1 and M-5 each touched one edge of it; neither reached the structural claim, which is Architect's: **read-time recomposition cannot reproduce the settings-derived cells of a past month, because Lock 14 locks the settings store as UPSERT-in-place with no edit-history rows.** That is not a gap in my round-1 pass I want to paper over — I found the two symptoms (a live owner header, a live-recompute contradiction) and did not find the cause.

### Position: **Option A (freeze the rendered payload)**, and **I veto Option B**.

**Why A, on grounds only this role supplies.** Under A the report is **one stored artifact** that both the in-app view and the PDF read. That makes the P10 tenant-isolation battery's job finite: there is a single object to fence and a single read path to prove. Under C there are two render paths and the battery must prove tenancy on both, forever, including for every §2.x surface added later — and the two-path boundary is exactly the seam where a future contributor puts a section on the wrong side without noticing. Under B there is no artifact at all.

**The veto on Option B, stated without hedging.** B renders unrecoverable past state as present fact on an audit-class artifact the user archives. F/CTO sign-off is required to override, and I would want that override recorded rather than assumed.

⚠ **I am scoping the veto's ground precisely, because half of the precedent transfers and half does not, and overclaiming here would be the error I flag in others.** ADR-067 Decision 3 records a **Sec VETO on Option C (backfill the series)** — read verbatim at `b90b846`: *"**Option C** (backfill the series) carries a recorded **Sec VETO**, reached independently by Architect, Sec and PM."* Its two grounds, from the V1.4 record:

- **Ground (i) — a backfill rewrites an append-only audit surface.** This does **NOT** transfer to S-1 Option B. B writes nothing; there is no rewrite.
- **Ground (ii) — the tax state for a past date is not recoverable, so the values would be fabricated.** This **DOES** transfer, and it transfers intact. Rendering April's report from September's schedules, September's designations and September's `%Target` values produces figures that were never true of April, presented on a document whose own PRD contract (§2.6.4 φ-1) promises they are. Stored or not stored is immaterial to ground (ii); *presented as a measurement* is the whole of it.

So the veto rests on ground (ii) alone, and it is enough. **Losing side of vetoing B, named:** B is genuinely the cheapest option and the only one requiring no new storage; if the PRD's φ-1 commitment were itself reopened and narrowed, the veto's basis would narrow with it — which is why PM's A-5 Option (A) (*amend φ-1 to name the exceptions, loudly labelled*) is a **different proposal from S-1 Option B and is not vetoed by this.** It is honest where B is not: it changes the promise instead of breaking it. I have no security objection to PM's A-5 (A) as a product call, only the standing requirement that the label be rendered on the historical report and not merely recorded in the PRD.

**Between A and C.** Architect leans A; PM's A-5 leans (B) — *freeze only the history-less inputs, recompose everything that has history* — which is Architect's Option C by another route. **I back A over the hybrid**, and the reason is a security-testability one rather than an architectural one: the hybrid's per-section boundary is a classification that must be re-applied by every future author of a §2.x surface, and a misclassification is silent — the section simply recomposes and nobody sees a symptom. **Losing side of A, named, and it is real:** A pays a permanent payload-compatibility cost that the hybrid pays for only four of six sections, and Architect's `payload_schema_version SMALLINT` mitigation is a mitigation, not an elimination. If F/CTO weights payload-compat above render-path unity, PM's (B) / Architect's C is defensible and I will not block it — I would then require the section classification to be stated **in the schema** (a per-section frozen/recomposed marker on the child), not in prose, so a misclassification is a visible column value rather than an absence.

**⚠ N-1 — a citation-form correction, raised because the S-1 argument will be quoted into an ADR.** Architect's S-1 presents the ground-(ii) sentence as ADR-067 Decision 3's own words: *"ADR-067 Decision 3 rules, on `nav_daily`: 'the tax state for a past date is not recoverable, so a back-fill would be a fabrication with the shape of a measurement (Sec veto).'"* **That sentence is not in `DECISIONS.md`.** `git grep -n 'shape of a measurement' b90b846` returns five hits, all in `docs/records/` — `v14-preflight/architect-findings.md:219` and `:479`, `v14-preflight/rederived-acs.md:177`, `v14-execution/self268-sec-findings.md:119`, and my own `v14-preflight/sec-findings.md:1046`. The **ruling** is correctly attributed and real; the **rationale sentence** is from the V1.4 pre-flight records, which are not canon. The substance survives untouched — I have just relied on it myself, above. What must not happen is the sentence entering a V1.5 migration header or an ADR as a quotation *of ADR-067*, which is the ADR-011 Decision 4 PR #476 "right ruling, wrong pointer" class. **Fix: cite ADR-067 D3 for the veto, cite the records file for the rationale, or promote the sentence into the ADR deliberately.** Not a substantive finding; a five-word attribution fix.

---

## R2.2 — Position on S-2 (Architect `S-2` = PM `D-7`)

**I confirm the inversion, and I confirm I missed it.** I did not read `docs/ARCH/index.html` §3.2 in round 1. Re-measured myself at `b90b846`: `docs/ARCH/index.html:325` reads `PW->>V1: "GET /internal/pdf-render + signed JWT"`, `:330` reads `V1-->>PW: Rendered HTML`, `:332` reads `PW->>Pup: "Load HTML in browser-context-per-render"`. **The worker pulls.** The drafts invert it.

### Position: **Option C (the app composes and escapes; the worker receives finished HTML and returns PDF bytes)** — with two conditions Architect's option does not carry.

**Why C.** It removes the impersonation surface entirely. Under Option A the app must serve a rendered page *for a user identity* to a machine caller with no user session — that is S-3, it is unsolved, and a tenant-confusion defect there is silent and leaks exactly the data the whole RLS posture exists to protect. Under C the composition happens under the user's own live session with their own RLS, and the worker becomes a pure function. **Trading a silent tenant-confusion class for a loud network class is the right trade on a fintech surface.**

**⚠ The losing side of C, named — and Architect's S-2 does not name it.** C makes the HTML body an **inbound network input to a browser engine**. Under Option A the worker only ever loads what it fetched from a known app URL; under C anyone who can reach the worker's port supplies arbitrary HTML to Puppeteer. The concrete consequence is not abstract: `<iframe src="file:///proc/self/environ">` rendered into a PDF the caller receives back exfiltrates `PDF_WORKER_SIGNING_KEY`, which is that container's only secret and therefore its entire compromise. Two conditions follow, and **C is not safe without both**:

1. **The worker renders with all outbound and local resource loading denied.** `page.setContent()` plus request interception that aborts every request whose scheme is not `data:` — no `file:`, no `http`, no `https`. Lock 13 mod #7's shipped hardening list (system-fonts-only, `--disable-features=BackgroundFetch,ServiceWorker,BackgroundSync`, cache-disable, per-render metadata clear) does **not** contain this, so it is an addition rather than an inheritance. **Catch criterion:** POST HTML containing `<iframe src="file:///proc/self/environ">` and `<img src="http://169.254.169.254/">`; assert the returned PDF contains neither the key nor any fetched content, and assert the interception handler recorded two aborts. ⚠ Asserting only "the PDF looks fine" is vacuous — a failed fetch and a blocked fetch render identically.
2. **⚠ N-4 — C creates a second inbound admission channel, and the RT-27 fence does not cover it.** Measured: `scripts/ci/fence-admission-private-bind.sh` audits a **Coolify Compose manifest** and locates its target by an in-file sentinel (`# fence-admission-private-bind: target`), rejecting `ports:`-publishing and `network_mode: host`. Its shipped invocation is the **provider-sync** manifest. `workers/pdf-render/` holds a `Dockerfile` and a `.env.example` and **no compose manifest at all** — so under S-2 B or C the pdf-render admission endpoint would come up with no private-bind fence over it. **Requirement, routed to DevOps:** pdf-render ships a compose manifest carrying the sentinel, and the RT-27 fence job invokes the script against it. The fence script is already generic over its target, so this is a wiring change, not a new fence.
   - ⚠ **This is an INTRA-instance coverage expansion of RT-27 and changes NOTHING on the §10 catalogued ledger.** The direct precedent is on the record and should be cited rather than re-argued: SECURITY §4.5 records RT-30's fourth RT-26 surface as *"an INTRA-instance allowlist expansion (RT-26 3→4)"* with *"§10 ledger UNCHANGED"*. **No new catalogued instance may be drafted for pdf-render's channel, and no ledger edit is owed.** Stated here because the alternative failure — someone reading "a second admission channel" and catalogueing it — would look like diligence.
   - ⚠ It **is** a CI fence-boundary change, which is a standing escalation trigger and joint-review-mandatory: DevOps proposes the catch criterion, I review it, and it ships with a golden fixture that fails closed.

**Option A remains correct and I will not block it** — it is the only option requiring no ADR amendment, and its network posture is strictly better (the worker holds no listener at all). If F/CTO prefers not to reopen Lock 13, **A is the answer and S-3 becomes live and must be ruled**, at which point my R2.3 position on R-3 applies. **Option B I do not support:** Architect's "dominated by C" is right, and it additionally carries the escaping obligation C discharges.

**On §7.32 item 6 — I am changing my round-1 position.** Round 1 I asked for the escaping control to live in the PDF worker (M-2) and asked for the booking to be promoted (R-5). Under A or C the worker composes no HTML and Svelte's default escaping is the control, so **both of those are wrong under the ratified direction**. See R2.3 M-2 and R-5.

---

## R2.3 — Disposition of every round-1 item

Confirmed / retracted / narrowed, by id, against the sibling files.

### Rulings

| id | Disposition |
|---|---|
| **R-1** DEFINER supersession | **CONFIRMED**, now nested under S-1. Lean unchanged: derive supersession from the partial-UNIQUE ordering rather than store it — no UPDATE, no allowlist growth. The re-derived A1 item 5 routes it correctly. ⚠ Addition: if a DEFINER lands, the ADR-011 Decision 9 **allowlist amendment is owed in the same PR**, not at a later reconciliation — A1 item 5 names the allowlist but not the amendment obligation. |
| **R-2** A6 disposition | **CONFIRMED**, and **my lean is changed.** Round 1 I leaned (ii) re-scope-in-place; both siblings independently reached *close as delivered* (Architect F-5, PM §2 A6). I now back **(i) close, and open the F-6 manifest extension as a separate successor** — the successor is genuinely different work from what the issue's title describes, and closing is the cleaner record. My round-1 objection to (i) (that the successor loses the dependency edges) is answered by Architect's A4 block, which already states *"A6 is not downstream — its fence already exists and already audits this file."* |
| **R-3** tenant binding | **CONFIRMED as a hazard, NARROWED twice, and one option retracted.** (a) The **cron half is already solved on the tree** — I verified `workers/etl/src/pfin_back_etl/connection.py` myself: `SET LOCAL ROLE authenticated` + `set_config('request.jwt.claims', …, true)`, with `request.jwt.claim.sub` explicitly nulled first. My option α *is* the shipped pattern, which makes it the default rather than a proposal. (b) The **app half is subsumed by S-2** — vote C and it disappears. (c) ⚠ **I retract option β** (keep `service_role` + `p_users_id` as the code-layer binding): ARCH §3.2 states the endpoint *"does not use `service_role` in V1"*, so β was excluded by a ratified artifact I had not read. Naming the retraction rather than quietly dropping it. |
| **R-4** PRD overwrite vs ADR | **CONFIRMED; my open question is answered and withdrawn.** I asked which vehicle corrects the PRD; PM's A-6 answers it as a class (c) pointer edit with drafted wording, and separates the product-visible claim (one current report per month — survives) from the storage claim (gets the Lock 11 pointer). I endorse A-6 as the discharge and withdraw the question. |
| **R-5** §7.32 item 6 promotion | **RETRACTED IN PART.** Promoting it as a 19th issue is wrong: under S-2 A or C the ruling deletes the work. Correct disposition is **conditional** — the booking stays in `BACKLOG.md` §7.32 and activates only if S-2 lands on B. The re-derived A4 item 4 already carries it that way, correctly. What survives from R-5: the booking must not be read as discharged until S-2 rules, and if S-2 lands on B it becomes mandatory and testable. |
| **R-6** A8 classification | **CONFIRMED, and now with two independent supports.** PM §2 A8 reaches it (*"'Sec advisory (not joint-review)' is Sec's to accept — INV-1 makes the owner string security-load-bearing and RT-12 is its test"*). And the re-derived A8 block contradicts itself: item 2 **adds** an ADR-029 aal2 requirement while item 7 carries *"Sec advisory, not joint-review … as drafted."* An AC that adds an aal2 clause to a new sensitive tenant-owned `pfin` table is not advisory. Still my call, still overridable. |

### Isolation findings

- **F-1** (D3 ordinals) — **CONFIRMED**, independently by Architect F-6 and PM D-4. Absorbed into re-derived A1 item 4 and A2 item 3. Closed on absorption.
- **F-2** (dropped INTEGER[] column) — **CONFIRMED**, and **my lean is retracted.** I leaned B (retire the instance by ADR amendment). ADR-035 names a **V1.6 successor** (the statement control tie-out), so the instance is *deferred-with-a-consumer*, not orphaned — retiring it would have to be undone. I back Architect's **S-5 (a)**: ship the column with the dormant fence, header naming the revival condition. The decisive argument is Decision 3's own history: fold-ins get forgotten (its `#15`/`#16` record says so twice), and a fence that must be *remembered* at V1.6 is a fence that will not exist at V1.6. ⚠ Condition: the paired QA leg is labelled **construction-only** in its own text — it asserts the fence exists and is attached, not that it fires — so a later reader cannot mistake a leg that cannot fail for coverage.
- **F-3** (RT-21 letter collision) — **CONFIRMED**, reached independently by Architect F-4. **Fully absorbed** by re-derived A5 item 2, which restores the canonical (a)–(g) verbatim, and item 3, which handles (g)'s known-defective status correctly. Closed.
- **F-4** (fail-open tenant binding) — see R-3. The hazard is confirmed and is exactly what `connection.py` guards against; the remedy is *reuse that module*, not invent one.
- **F-5** (client-composed payload) — **CONDITIONAL, not retracted.** Void under S-2 A or C; live under B. Re-derived P6 item 1 absorbs it and adds the half I did not state — that the drafted direction *"would additionally put `PDF_WORKER_SIGNING_KEY`'s trust boundary in the browser."*
- **F-6** (RT-22 blind to the dependency manifest) — **CONFIRMED, and I hold it against the sibling's disposition.** Named disagreement below at R2.5.
- **F-7** (A8 mandatory) — **CONFIRMED** = R-6.
- **F-8** (pending queue) — **CONFIRMED and NOT absorbed.** Re-derived P5 items 1–2 add the listing surface and the pending queue and state no tenant scoping for either. Severity unchanged (note): the natural implementation is scoped by construction; I want it asserted, not redesigned.
- **F-9** (aal2 on three new tables) — **CONFIRMED and fully absorbed**: re-derived A1 item 7, A2 item 5, A8 item 2, A9 item 5 each carry it, and A8 item 2 additionally names why the `user_settings` exclusion does not apply. Closed.

### Money / isolation flags

- **M-1** (live owner header) — **CONFIRMED**, reached independently by Architect F-2 and PM D-5. Absorbed into A1 item 1, A8 item 4, P7 item 4. Closed.
- **M-2** (escaping location) — ⚠ **RETRACTED IN PART, and this is the round-1 statement of mine most likely to mislead if left standing.** I wrote *"the escaping control lives in the PDF worker."* Under ARCH §3.2's ratified direction the worker composes no HTML, so that requirement is **wrong** and would have had Backend build a control the architecture makes unnecessary. **Corrected statement: the escaping control lives wherever HTML is composed, and S-2 decides where.** What survives intact is the underlying requirement, which is direction-independent: *every free-text field is escaped by whatever composes the HTML, and it is asserted on the RENDERED OUTPUT — a stored `<script>` proving inert in the PDF, not only in the HTML view* (ADR-013 INV-2 spans both). Under A or C that assertion is a regression test on the Svelte template; under B it is a new control in the worker.
- **M-3** (conditional tri-axis) — **CONFIRMED and NOT absorbed.** Re-derived P10 item 6 states tri-axis unconditionally. It adds a genuinely valuable mechanical correction I did not have (both non-tenant axes are `text not null` columns on `pfin.account`, so they are varied as values, and `pfin.scope` is not a type) — but it does not carry PRD §2.6.6's collapse condition. See the AMBER on P10.
- **M-4** (staleness frozen at generation) — **CONFIRMED**, reached independently by PM §2 P8. **Absorbed** by re-derived P8 item 5, which states it survives S-1 in either direction and must not be folded into the snapshot. Closed.
- **M-5** (PRD overwrite) — **CONFIRMED**; discharged by PM A-6. Closed.
- **M-6** (no PDF bytes at rest) — **CONFIRMED and strengthened.** Re-derived P6 item 4 states it from PRD §2.6.3 verbatim (*"a transient export, not persisted server-side"*). **My non-objection stands**, with its standing condition: the first AC that persists a rendered PDF creates a storage-class surface and is joint-review-mandatory at that PR.

### Drift findings

- **D-1** (A6 veto + stale ledger figure) — **CONFIRMED by both siblings independently** (Architect F-5 items 1–2; PM §2 A6). **The veto stands.** Absorbed verbatim into re-derived A6, including *"The carve-out would weaken a shipped fence"* and the Path-B ledger non-effect.
- **D-2** (A6 built, A4 partial) — **CONFIRMED by both.** Architect adds the landing commit `eada4b2`, which I had not measured.
- **D-3** (five missing RT labels) — **PARTIALLY absorbed.** RT-11 / RT-12 / RT-19 / RT-25 are fold items for Architect's round 2 and I do not grade them. ⚠ **RT-20 is different and did not fold:** re-derived A2 item 7 still reads *"RT-21 HIGH + the SD-12 child sub-class addendum."* That is not a missing label, it is the **wrong test named for this surface** — Decision 16 verbatim names *"new RT-20 HIGH (fourth-instance FK-bypass + service_role bypass + parent immutability extension)"*. PM §2 A2 caught it; the re-derived block did not absorb it. See the AMBER on A2.
- **D-4** (commentary label) — **CONFIRMED by both, AND THE TWO SIBLINGS DISAGREE ON THE FIX.** Architect F-3 renames the **column** (`commentary_marketable_securities`, carried into re-derived A1 item 1 and P3 item 1). PM D-3 rules the opposite: *"Product phrase governs the user-facing heading (**Marketable Securities**); the identifier `commentary_equity` stands (schema wording governs identifiers). Fix lands in SELF-355's AC and BACKLOG §5.6, not the PRD."* **This is a live cross-sibling conflict on a DDL identifier that will be permanent once the migration lands.** I have **no security stake and I state that explicitly: I do NOT require either name.** I am surfacing it because the two re-derived blocks currently carry Architect's answer and PM's file carries the opposite, and whoever writes the migration will resolve it silently by picking one. It needs one line at the sitting.
- **D-5** (UNIQUE constraint) — **CONFIRMED**, reached independently by Architect F-1. Absorbed into re-derived A1 item 3. Closed.

---

## R2.4 — New in round 2

Findings that exist only because a sibling's measurement changed what I looked at, plus one correction to my own round-1 output.

**N-2 — A7's ADR-011 Decision 1 clause (d) audit log has no writable home, and this corrects a catch criterion I published in round 1. — flag.**

PM's D-8 reports that A7's cited *"Lock 13 mod #4 audit log"* table was dropped at `015`. Measured myself at `b90b846`, and the precise state is one step further on than "dropped":

- `pfin.plaid_sync_audit` appears in `007`, `008`, `015`, `047` and is not a live table.
- Its successor **exists**: `pfin.linked_source_sync_audit` (`015:441`), whose `users_id` column is commented *"resolved tenant (Decision 1 clause (d))"* and whose `detail jsonb` is commented *"tenant-resolution chain"*. So there *is* a D1(d) surface.
- ⚠ **But it cannot take a report-generation row.** Its `source` column is `check (source in ('webhook', 'scheduled_poll'))` and its `provider` column is checked against a provider list with no internal/report member. A monthly-report generation event is neither, on both columns.
- And the **general** audit-log helper is unauthored: `git grep -lni 'emit_audit_log|fn_audit_log' b90b846 -- supabase/migrations/` returns nothing, consistent with ADR-011 Decision 9's amendment recording the general slot as *reserved-unauthored*.

**My own error, named here rather than in a follow-up:** my round-1 catch-criteria table carries, for A7, *"assert the same-transaction audit row exists and names the resolved tenant."* I wrote that as if the surface existed. A builder following it would either widen two CHECK constraints on a shipped **append-only audit-class table** — a Decision 2 surface change, joint-review-mandatory, and not something an AC should reach by accident — or invent a table with no design. **Corrected criterion: A7's D1(d) obligation needs a named home before the criterion is testable; the ruling on which home is Architect's.** Options I can see: extend the successor's two CHECKs (cheap, but widens an audit-class table's domain from "sync" to "any privileged write"); author the reserved general helper (largest, and it discharges a long-standing reservation); or a report-scoped audit table (narrow, and adds a fourth audit surface). I have no lean and it is not mine to pick.

**N-3 — a third ratified artifact constrains S-3, and neither sibling quoted it in this form. — note.**

`docs/ARCH/index.html:208` reads: *"All **reads** flow through a single `SECURITY INVOKER` read-composition helper (**user-session only — never invoked from a worker**), which is also the render source the PDF worker reaches through the V1 web-app's `/internal/pdf-render` endpoint rather than the database directly."*

Re-derived A7 item 2 has the **cron worker** invoking A3 per tenant from Python. That is a worker invoking the helper, which this sentence forbids in terms. Two readings are available and I do not know which is intended: the sentence may be scoped to the *PDF* worker (its subject in the second clause), or it may be the general statement it appears to be. Either way it is a third ratified artifact bearing on S-3 and it should be read at the sitting rather than discovered at the A7 joint review. If it is general, A7's whole shape changes; if it is PDF-scoped, the sentence is imprecise and should be narrowed so the next reader does not hit this. **Raising it as a genuine ambiguity, not as a confirmed defect** — I am not confident which reading is correct.

**N-5 — the commentary columns are unbounded TEXT feeding a PDF renderer. — flag.**

Re-derived A1 item 1 specifies the four commentary columns as bare `TEXT`. Re-derived P3 item 4 correctly requires the **TEXT-variant** adversarial battery including *"length bounds"* — but a length bound asserted in the app layer over a column with no DDL bound is a single-layer control on a Lock 14 write path, and Decision 4's user-facing-surface class is explicitly a multi-layer commitment. The consumer is a browser engine rendering a PDF: unbounded prose is a memory and render-time cost there in a way it is not on a web page the user scrolls. PM's §2 A8 already proposes a bound for the owner string (120 characters, parity example 41) and nothing proposes one for commentary. **Requirement, routed to Architect (DDL) + Backend (Zod):** a CHECK-enforced length bound on each commentary column, mirrored in the Zod schema, with the bound chosen by PM against the parity artifact. **Catch criterion:** a body one byte over the bound is rejected 400 at the app layer **and** the same value is rejected by the DB when submitted directly through PostgREST — two facts that can disagree, which is what makes it a real second layer.

**N-6 — cross-sibling disagreement on a permanent identifier.** See D-4 above. Recorded as its own item because it needs a decision and neither sibling's file records that the other disagrees.

---

## R2.5 — What moves on my map and my criteria

**Joint-review map — three rows move, and one does not move but is worth stating.**

1. **A6 → from MANDATORY-because-fence-change to MANDATORY-because-closure-review.** The trigger changes, not the classification. Round 1 I classified it under *CI fence change touching a fenced RT*. Since the fence already exists and the recommendation is to close, what I now review is the **closing comment** — specifically that it records the `SUPABASE_URL` correction so no future edit inherits the weakened carve-out. Same class, different object.
2. **A4 → gains a second trigger under S-2 B or C.** Round 1 its trigger was Lock 13 mod #2 alone. Under B or C it also becomes a **CI fence-boundary change** via N-4 (the RT-27 private-bind wiring) — which is a standing escalation trigger, not merely joint review. Under Option A this second trigger does not arise, because the worker holds no listener.
3. **P5 → I am adding a trigger I did not name in round 1.** Re-derived P5 item 4 makes the on-demand path *"invoke A3 through an app endpoint under the user's own session."* PM §2 P5 measured what I missed: **generation is a WRITE** (a Lock 11 row with a server-derived `data_as_of`) and no issue owns that write path — A7 is cron-only. A new user-reachable write path onto a **Decision 2 audit-class table** is D2-mandatory. P5 was already not-light-loop-eligible in my map, so the row's class is unchanged; the trigger is now D2 rather than only the queue-read surface.
4. **Not moving, stated because silence would read as agreement:** P4's conditional light-loop eligibility survives all three files. Both siblings found real PRD contradictions in P4 (Architect F-8, PM §2 P4), and re-derived P4 fixes them — but every fix is product wording and control flow, none touches a mandatory surface. **P4 remains conditionally light-loop-eligible on the same condition: it lands as control flow inside an already-reviewed A7.** P8 and P9 remain light-loop-eligible unconditionally.

**Catch criteria — two change.**

- **A7's audit-log leg is withdrawn as written** and replaced per N-2. It is not testable until the home is named.
- **A3 gains the best leg in the wave, and it is Architect's, not mine.** Re-derived P10 item 2 requires asserting *as a catalog fact* that **no `rolbypassrls` role holds EXECUTE on A3**. I verified the mechanism it depends on: the shipped pattern at `104:913-914` and `105:434-435` is `revoke execute … from public; grant execute … to authenticated;`, and `008_pfin_service_role_grants.sql` contains **no** function-level EXECUTE grant, so `service_role` acquires EXECUTE only by an explicit future grant. **This is the leg that closes F-4 at the database layer regardless of how S-2 and S-3 resolve** — if no bypass-RLS role can execute the helper, no bypass-RLS caller can compose across tenants through it, whatever the app does. I want it stated as a **standing** catalog assertion, not a one-time check, because the failure mode is a future migration adding a grant to make something work. ⚠ Note the asymmetry that makes it load-bearing here: for a SECURITY INVOKER function the EXECUTE ACL is normally the weakest of several fences; against a `rolbypassrls` caller it is the **only** one, because RLS is not in the picture.

**Named disagreement with Architect — F-6 and A6's residual.** Architect's re-derived A6 residual leaves the fence's documented non-catches (*"a `COPY` of a manifest; a Postgres client transitive via base image"*) as *"human-PR-review second line per ARCH §6.1."* That disposition is correct **today**, while the Dockerfile is a placeholder whose `CMD` is `node --version`. It stops being correct the moment A4 lands a real Puppeteer application, because the standard shape is `COPY package*.json .` then `RUN npm ci`, and at that point `pg` enters the container through the exact path the fence is documented not to look at — with the fence reporting clean. Lock 13 mod #2 is a **V1-SHIP-BLOCK** property; leaving it to human review at the moment it becomes reachable is the disposition I decline. **My requirement stands: A4's PR extends RT-22's catch criterion to `workers/pdf-render/package.json` and its lockfile, with a paired golden fixture.** Stated as a disagreement rather than folded in silently, because Architect and I reached different dispositions from the same measurement and F/CTO should see both.

---

## R2.6 — PRE-verdicts on `rederived-acs.md` @ `66288e0`

**These verdict the ROUND-1 blocks at `66288e0`.** Architect is folding PM wording, my RT labels and the aal2 clauses in parallel, so **I do not grade a block down for a missing RT label or a missing aal2 clause** — those are listed separately as fold items. I grade on substance: *would this AC, built verbatim, pass at joint review?*

**GREEN 12 · AMBER 5 · RED 1.**

| Block | Verdict | Named sentence / clause |
|---|---|---|
| **A1** | **AMBER** | **Item 6.** It fences `users_id` and `target_month` post-creation, and item 5 *asserts* that a `final` row is immutable — but **no item states the mechanism that blocks UPDATE on a final row, and nothing addresses `service_role` on this table at all.** Decision 2 verbatim requires append-only *"across both `authenticated` AND `service_role` roles"*; A2 item 4(iii) carries a `service_role` bypass trigger for the child and A1 has no equivalent. Built verbatim this ships the wave's canonical D2 surface with a two-column fence where a whole-row-on-final fence is locked. AMBER bordering RED: everything needed is named in the block, but the missing mechanism would be a joint-review blocker if it reached me unfixed. |
| **A2** | **AMBER** | **Item 7**, *"RT-21 HIGH + the SD-12 child sub-class addendum."* RT-21 is the PDF-worker JWT battery; Decision 16 verbatim names **RT-20** as this surface's test. A false composite — both labels real, the pairing invented — which is why it survived the re-derivation. Built verbatim, the RT-20 battery is never written and an RT-21 battery elsewhere is green, masking it. (PM §2 A2 reached this; the block did not absorb it.) |
| **A3** | **GREEN** | Item 1's dropped `p_users_id` with both tree precedents, item 4's unflattened envelopes, item 5's one-call-one-clock and item 6's EXECUTE posture are all correct. Fold: RT-19, RT-25. |
| **A4** | **AMBER** | **Item 3.** Lock 13 mod #7's hardening list is carried faithfully and does **not** contain a resource-loading fence. Under S-2 B or C the worker renders network-supplied HTML in Puppeteer; without `setContent` + request interception denying every scheme but `data:`, `file:///proc/self/environ` exfiltrates the container's only secret. Add the fence and the two-abort catch criterion (R2.2 condition 1). Also gains N-4's compose-manifest requirement under B or C. Minor: the BLOCKED line cites *"(F-2 / S-2)"* where F-2 is the A1 column-omission finding — likely a typo for F-4. |
| **A5** | **GREEN** | Item 2 restores canonical RT-21 (a)–(g) verbatim; item 3 handles (g)'s known-defective status and the dropped-table pointer; item 4 correctly retracts the *"Arch-locked per RT-21(e)"* false composite and cites `connection.py` as prior art. This block fully absorbs my F-3. The strongest block in the file. |
| **A6** | **GREEN** | Close-as-delivered with both AC corrections preserved and the Path-B ledger non-effect stated. My F-6 disagreement is with the **residual's disposition**, not with this block's verdict, and it attaches to A4. |
| **A7** | **RED** | **Item 5**, *"Lock 13 mod #4 audit-log entry, same transaction."* Per N-2 the named surface does not exist and its only successor rejects the row on two CHECK constraints. Built verbatim this either silently drops ADR-011 Decision 1 clause (d) — the forensic-detectability clause, on the wave's only privileged non-JWT writer — or widens CHECKs on a shipped append-only audit-class table without a review that noticed. The clause needs a home before it is buildable. |
| **A8** | **AMBER** | **Item 7**, *"Sec advisory, not joint-review (single-column user-scoped table, no chain) — as drafted."* Internally inconsistent with the same block's item 2, which adds an ADR-029 aal2 requirement, and with Lock 14 membership (R-6 / F-7). "No chain" is true and is not the predicate. |
| **A9** | **GREEN** | Substance unchanged from a well-drafted original; the tense correction is right and the post-V1.4 coherence check (A9 renders nothing, so it cannot drift from `105`) is the argument that makes early dispatch safe. |
| **P2** | **GREEN** | Item 3's mandatory envelope rendering (*"a `?? 0` … applied to an envelope is a defect"*) and item 4's one-flip-site sign convention are both money-correctness controls I would otherwise have had to ask for. |
| **P3** | **GREEN** | Item 3's correction — SERIALIZABLE is unreachable from this transport, realize it as the `101` `FOR UPDATE`-first-statement pattern with no tenant parameter — is exactly the ratified mechanism. Item 4's TEXT-variant battery is right. Fold: RT-11. Route N-5's length bound to A1. |
| **P4** | **GREEN** | Complete-or-explicitly-skip and the in-app-not-Discord correction both track the PRD verbatim. No mandatory surface. |
| **P5** | **GREEN** | Items 4 and 5 carry the session-binding and the server-derived-only fence correctly. Two additions rather than defects: state the tenant scoping on the listing and queue reads (F-8), and name the generation **write** path's D2 obligation (R2.5 item 3). |
| **P6** | **GREEN** | Item 1 names the browser-holding-the-worker-credential problem, which is the sharper half of my F-5. Item 4 states the no-persistence contract that carries my M-6 non-objection. |
| **P7** | **GREEN** | Item 2's note that a single-row UPSERT needs no lock is correct and avoids importing `101`'s machinery where it does not apply. Item 4 states the forward-only consequence. Fold: RT-12. |
| **P8** | **GREEN** | Item 5 absorbs M-4 and states the property that makes it durable — the live-read carve-out survives S-1 in either direction and must not be folded into the snapshot. |
| **P9** | **GREEN** | The addition — that the `{status:'unavailable'}` envelopes are **not** staleness and must not merge into the stale badge — is a real correctness control: *"no ledger designated"* and *"your brokerage needs re-auth"* are different facts with different user actions, and collapsing them would silently mislabel a configuration state as a data-freshness state. |
| **P10** | **AMBER** | **Item 6.** It states tri-axis unconditionally. PRD §2.6.6 verbatim makes it conditional — *"where the underlying classes carry tax-treatment … for §2.6.1 surfaces with no tax-treatment dimension, the tri-axis collapses to the tenant_id × scope pair"* (M-3). Its own mechanical correction (both non-tenant axes are `text not null` columns, `pfin.scope` is not a type) is valuable and I want it kept. ⚠ Item 2's no-`rolbypassrls`-EXECUTE leg is the single most valuable assertion in the file — see R2.5. Fold: RT-11/12/19/20/25 into the item 1 coverage list. |

**Blocks whose conditional structure I explicitly endorse:** A1, A2, A3 (S-1), A4, A5, P6 (S-2), P8 (S-4). Marking a block BLOCKED rather than guessing the ruling is the right shape and I do not want it read as incompleteness.

---

## R2.7 — What "3 of 18" was over

**It was over the ORIGINAL drafted AC text in `temp/v15-preflight/issue-dump.md` (md5 `b6f9e76c3420534d10378f2426298409`) at `b90b846` — not over Architect's re-derived blocks**; against those, the same predicate gives **12 GREEN / 5 AMBER / 1 RED** at `66288e0`.

The three numbers in play are over three different objects and none of them is wrong: mine (3 — A9, P4, P9) over the drafted text under a *joint-review-pass* predicate; Architect's (4 — A8, A9, P7, P9) over the drafted text under an *identifiers-resolve + contradicts-no-lock + no-unresolved-seam* predicate; PM's (2 — A8, P7, both with riders) over the drafted text under a *product-lock-contradiction* predicate. **A9 and P9 are in all three.** The spreads are the predicates, not a disagreement about the tree — A8 is buildable on Architect's and PM's predicates and fails mine only on its self-classification (R-6), and P7 fails mine only on a missing RT label, which is a fold item I have said I do not grade. Stated this way so nobody reconciles three correct numbers into one wrong one.

---

## R2.8 — Round-2 summary of position

- **S-1: Option A.** Option B **vetoed** on ADR-067 D3 ground (ii) only; ground (i) does not transfer and I say so. PM's A-5 (A) is a different, non-vetoed proposal. Losing side of A named.
- **S-2: Option C**, conditional on the resource-loading fence and the RT-27 compose-manifest wiring (N-4). **Option A is fully acceptable** and has the better network posture; it makes S-3 live. Option B not supported.
- **S-3:** moot under S-2 C; under S-2 A the answer is the shipped `connection.py` shape, not a new design.
- **S-4:** advisory; **I do NOT require Sec review of the per-section attribution route.** Architect's lean (a) is fine by me, and his own losing-side note (app-layer mapping is unfenced) is the right thing to have written down.
- **S-5:** Architect's **(a)**, ship the dormant fence — my round-1 lean B retracted, reason given.
- **One RED** (A7 item 5), **five AMBER** (A1 item 6, A2 item 7, A4 item 3, A8 item 7, P10 item 6), **one named disagreement** (F-6 vs A6's residual disposition), **one cross-sibling conflict needing a line at the sitting** (D-4, the commentary identifier), **one citation-form fix** (N-1), and **one error of my own corrected** (N-2, the A7 audit-log catch criterion).
