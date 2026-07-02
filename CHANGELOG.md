# Changelog

Per-version execution narrative for mosko-fintech. Each entry documents what landed in a given WORKFLOW.md version: PR work, structured decision tracking (Q-N answers, vote outcomes), sub-section locks, ADR acceptance events.

**Not auto-loaded.** Consult on demand when answering "when did X land?" or "what happened in v1.NN?" questions.

**Distinct from `DECISIONS.md`** (architectural decisions with full rationale) per the [ADR-009](DECISIONS.md#adr-009) Decision 8 hybrid policy: CHANGELOG records WHAT/WHEN; DECISIONS records WHY/HOW IT REASONED.

**Format.** Newest at top. Each entry: `### vN.NN — YYYY-MM-DD` header followed by narrative paragraphs.

**Extracted from `WORKFLOW.md`** on 2026-05-23 per [ADR-009](DECISIONS.md#adr-009) Decision 6 implementation (task #10). 68 version entries total (v0.1 → v1.62).

---

### v1.62 — 2026-07-02

**Phase 6 — SELF-193: `TenantBoundConnection` + `fence-tbc` closure (Lock 13 mod #3).** PR #129 · milestone *V1.0 — Platform foundation*. V1-SHIP-BLOCK. The first Backend + DevOps (non-migration) build-loop feature of Phase 6.

**What landed** — two disjoint surfaces:
- **Backend (`workers/etl/`):** new `connection.py` — `TenantBoundConnection`, the single sanctioned SQLAlchemy engine factory. `.system()` (V1.0 usage — service-context engine for the ETL's global market-reference writes) + `.for_tenant(users_id)` (scaffolded; registers a **dormant** `before_cursor_execute` per-tenant assertion that fails closed via `TenantBindingError`; no live caller until V1.1+) + `.engine` (NullPool preserved). `core.py:231` routed through `TenantBoundConnection.system()` — zero blast radius. `emit_audit_log` = documented `NotImplementedError` stub. 13 unit tests.
- **DevOps (CI fence — closes the tracked `fence-tbc` integrity gap):** `fence-tbc-pfin-back-etl.sh` now catches `(sqla\.|sqlalchemy\.)?create_engine\(` — the ETL's real connection shape, which the old fence (grepping only `psycopg2.connect(`) **failed open** against; class-absence now **fails closed (exit 2) by default** (was fail-open), with `--allow-missing-class` an explicit opt-out for the inversion tree only. Production-mode step stays flag-free. Inversion fixture + `security-scan.yml` step updated. 5 local proofs.

**Ratified scope — honest scaffold.** The ETL writes only global market-reference tables (no `users_id` column), so there is no per-user write path to tenant-bind in V1.0. TBC's V1.0 value is therefore **architectural** — the single sanctioned factory (the fence anchors on it; every future per-user write is forced through it) + `system()` mode + a dormant assertion. F/CTO ratified shipping it as an honest scaffold rather than implying per-query enforcement that can't run yet; per-query enforcement + mod #4 audit-wiring activate at V1.1+.

**Reviews.** Backend drilled the approach (surfacing the no-`users_id` reframing) → F/CTO ratified. **Sec joint-review 🟢 GREEN** — 0 V1-SHIP-BLOCK; all 5 adversarial items confirmed (fence fail-closed; production-mode has no `--allow-missing-class`; dormant assertion genuinely raises; `system()` sentinel un-forgeable; §10 stays 2). 3 low NOTEs, all tracked. **CI 8/8 green**; the TBC fence is a **required** status check (gates merge — confirmed against branch protection).

**Ledgers:** §10 catalogued = **2** (RT-22 + RT-26; TBC is the code-layer Privileged-context-surfaces mechanism, orthogonal to the catalogued numbered axis — NOT a new instance). No migration; no DEFINER; no RLS change. Decision-3 family unaffected (no FK-shaped column).

**Follow-ups.** **mod #4 same-transaction audit-log** wiring is blocked on the Architect authoring `pfin.plaid_sync_audit` (mod #8 cross-language audit table) + the `SECURITY DEFINER` audit-log insert helper (the still-unauthored Decision-9 allowlist entry) → V1.1+. **ETL pytest CI job** (so the 13 `test_connection.py` unit tests execute in CI) → the tracked "ETL CI re-homing" follow-up (the fence is the CI-enforced V1-SHIP-BLOCK mechanism). Dormant per-tenant predicate tightening → firms at the V1.1 first-per-tenant-write joint-review gate.

---

### v1.61 — 2026-07-02

**Phase 6 — SELF-190: `account_trans` RLS shape (`006`, Lock 3 Option B).** PR #126 · milestone *V1.0 — Platform foundation*. Discharges the RLS deferral `004` left open — `account_trans` becomes reachable by `authenticated` for the first time.

**What landed** — pure declarative RLS on `pfin.account_trans` (zero functions, zero schema/column DDL):
- **SELECT** policy: `account_users.rd_access`-JOIN (a user reads a transaction only for an account they hold rd_access on).
- **INSERT** policy: `wr_access`-JOIN WITH CHECK (**mod #3** — the write path keys on `wr_access`, NOT `rd_access`).
- **No UPDATE/DELETE** policy (default-deny; also trigger-blocked for all roles by `004`'s immutability fence — belt-and-suspenders). `grant select, insert` only.

**Lock 3 (ADR-011 Decision 7 Option B) mod dispositions (F/CTO-ratified):**
- **mod #1** (account_users column-level UPDATE restriction) — **DEFERRED as a documented forward-fence.** `006` introduces no authenticated write to `account_users`, so the `003` hard-gate ("column-restriction lands in the SAME PR that first grants any authenticated write") isn't triggered; the restriction lands atomically at the future V2 sharing-UI write-grant PR. **Conscious F/CTO-ratified deviation from the issue AC-as-written**, documented in the `006` header; Sec **blessed** the deferral (the re-tenant pivot is inert in V1 — `account_users` is double-fenced SELECT-only at both RLS and ACL).
- **mod #2** (elevate `fn_grant_creator_access` to SECURITY DEFINER) — already landed at `003`/SELF-187; **verify-only** here (the creator-grant row it seeds, rd=t/wr=t, is exactly what the new policies JOIN against).
- **mod #3** — implemented (wr_access WITH CHECK).
- **mod #4** (advisory SECURITY annotation "V1 exercises V2 sharing-shape ACL") — → **companion doc-update** (Sec-owned `docs/SECURITY/`; text authored at review).

**Cross-feature discharges (two carried forward-notes closed):** SELF-187's deferred cross-tenant read assertion (rd_access-JOIN cross-tenant read fails closed — deferred-not-faked until a SELECT policy existed); and `005`'s authenticated reconciliation-link path — now that `account_trans` has an authenticated SELECT, the `005` `fn_reconciliation_event_trans_matched_account` INVOKER fence is reachable under `authenticated` and enforces matched-account semantics (same-account accept / cross-account reject), no longer ACL-gated.

**Reviews.** Architect drilled 3 forks (mod #1 defer / UPDATE-DELETE default-deny / mod #4 routing) — F/CTO ratified. **Sec joint-review 🟢 GREEN** — 0 V1-SHIP-BLOCK; all 5 adversarial-verify items confirmed; mod #1 deferral blessed. QA battery `tests/rls/006_...` `plan(12)`.

**CI: two snags handled.** (1) The first run hung on a stalled runner for ~5.5 h (no `timeout-minutes` set → 6 h default) — cancelled + re-triggered on a fresh runner (1m47s normal). (2) A **cross-migration transition**: `006`'s new `account_trans` grant flipped `005` test #26's fail-layer — the authenticated same-account link that ACL-failed-closed at `005`-time now succeeds (matched-account semantics take over), exactly the "revisit in SELF-190 battery" forward-note QA left; discharged in-place (`throws_like`→`lives_ok`, `plan(31)` unchanged). **8/8 CI green** on re-run.

**Ledgers:** Decision-3 family **+0** (SELF-190 adds no FK-shaped column) · §10 catalogued = 2 (RT-22 + RT-26) · SECURITY DEFINER allowlist = 3 (zero functions authored). **Note — the absolute Decision-3 count is under reconciliation:** the canonical ADR-011 Decision 3 body enumerates **4** instances (each ordinally numbered); the "7" that had propagated through the Phase-6 migration headers is an *operational-not-canonical* count (see the follow-up below).

**Follow-ups.** Companion doc-update (Sec-owned, separate PR): mod #4 SECURITY §4.1 annotation + a **Decision-3 count-grain annotation**. Sec's `006` joint-review **vetoed** a naive "reconcile the body to 7" — the "7" is not confirmable from the repo (no fifth-or-later instance is enumerated anywhere) and its provenance partly **conflates the Lock-14 settings-family-of-5** (SELF-259 "Family stays at 5"). F/CTO ratified **Option A**: the canonical Decision 3 body stays at **4** with a truthful count-grain annotation; full `4→N` reconciliation is **deferred to an Architect enumeration pass + Sec joint-review** (Option B, tracked). V2 sharing-UI PR lands mod #1 with the first authenticated `account_users` write (`003` hard-gate).

---

### v1.60 — 2026-07-01

**Phase 6 — SELF-188: `reconciliation_event` family (`005`, substrate).** PR #124 · milestone *V1.0 — Platform foundation*. Third base-table migration — the Lock 9 / ADR-011 Decision 13 reconciliation substrate.

**What landed** — three append-only audit-class tables + append-only RLS + cross-tier immutability triple-fence + the Decision-3 matched-account fence on the join:
- `pfin.reconciliation_event` (SD-16 HIGH) — statement-blessed; no own `users_id` (`account_users.rd_access`-JOIN tenancy); **explicit `dimension` CHECK('balance','quantity')** + dimension→column population CHECK (DP-2); `statement_balance NUMERIC(20,4)` / `statement_quantity NUMERIC(28,8)` (DP-3); no `is_plug`/`mode`/`_cents` (dropped per Lock 9).
- `pfin.holdings_checkpoint` (SD-17) — per-asset position snapshot; sole `account_id` anchor (**no `source_event_id`** → Decision-3 family stays 7); **SUBSTRATE only** (SELECT + immutability fence land now; **no authenticated INSERT path** — the fan-out writer defers).
- `pfin.reconciliation_event_trans` (SD-18) — append-only join; RLS via **parent `reconciliation_event` FK-chain** (Lock 12 pattern; deliberately decoupled from `account_trans` policy state, which is default-deny until SELF-190).
- **Three functions, all SECURITY INVOKER (allowlist stays 3):** two shared family fences (`fn_reconciliation_family_block_mutation` BEFORE UPDATE/DELETE + `fn_reconciliation_family_block_truncate` BEFORE TRUNCATE, `tg_table_name`-parameterized for per-table-distinct raise messages) + `fn_reconciliation_event_trans_matched_account` (BEFORE INSERT, **NULL-safe `NOT EXISTS`** — the **already-catalogued** Decision-3 instance / Lock 9 mod #1, family count +0).

**Scope — full-family ratified, DP-1 = substrate-only.** F/CTO ratified full-family scope; the Architect drilled the dependency split → **DP-1 substrate-only**: tables + RLS + fences land now; the **holdings_checkpoint fan-out trigger (+ DP-4 DEFINER-vs-INVOKER posture), cost-basis cascade, and NAV(`eod_price`) composition DEFER to the V1.3 usage wave** — strictly on **missing-dependency** grounds (no `eod_price` table; `account_trans` investment columns deferred by `004`; no securities-master), NOT a posture conflict. (A team-lead brief-drift-catch corrected an overstated "append-only-vs-cascade contradiction" framing before it reached the migration header — the cascade's `SELECT … FOR UPDATE` is a concurrency row-lock + INSERT, append-only-compatible.)

**Staleness reconciled.** Phase-4-era issue spec: migration renumbered `003`→`005` (`003`=account, `004`=account_trans); `account_trans.created_at` (Lock 9-A / Decision 19) already landed in `004`; SD-16/17/18 + RT-16/17 already catalogued (not re-expanded); Decision-3 "first instance" ordinal is stale (catalogued member, +0).

**Reviews.** DPs F/CTO-ratified (DP-1 substrate / DP-2 explicit dimension CHECK / DP-3 NUMERIC(28,8); `source_event_id` deferred). **Sec joint-review 🟢 GREEN** — 0 V1-SHIP-BLOCK; all six adversarial-verify items confirmed; **commendation on trigger-over-WITH-CHECK** (the D3 fence fires under `service_role`, which an RLS WITH CHECK would not — the exact privileged path QA exercises). Two header-precision fixes applied pre-merge (NOTE-1 verbatim-anchor parenthetical restore; QA's ACL-layer-vs-NOT-EXISTS correction). QA battery `tests/rls/005_reconciliation_event_family_rls.sql` `plan(31)` (RT-17 full; RT-16 cascade slice defers with the writer).

**CI caught two test-layer bugs** (Docker down locally → CI was the first execution against applied DDL): (1) the `005` battery's mixed-case `\gset` aliases fold to lowercase → unset `:refs` → syntax abort (planned 31, ran 0); (2) a **cross-migration regression** — `005`'s inbound `reconciliation_event_trans → account_trans` FK made `TRUNCATE account_trans` trip Postgres's FK-truncate guard **before** the statement-level immutability trigger, breaking `004`'s test #9; fixed via `TRUNCATE … CASCADE` in `004`'s + `005`'s TRUNCATE tests (audit-wipe stays fenced — the FK guard is an *additional* layer). QA proactively caught the same pattern on `005`'s own `reconciliation_event`. **8/8 CI green** on re-run.

**Ledgers unchanged:** Decision-3 family = 7 · §10 catalogued = 2 (RT-22 + RT-26) · SECURITY DEFINER allowlist = 3.

**Follow-ups → V1.3:** holdings_checkpoint fan-out (+ DP-4 posture), cost-basis cascade (RT-16 full), NAV via `eod_price`; SELF-190 battery revisits the authenticated `reconciliation_event_trans` link path once `account_trans` SELECT opens.

---

### v1.59 — 2026-06-30

**Phase 6 — SELF-189: `account_trans` immutable audit ledger (`004`).** PR #123 · milestone *V1.0 — Platform foundation*. Second base-table migration — the Decision-2 audit-class transactions table.

**What landed** — `pfin.account_trans`, append-only and fenced against **UPDATE + DELETE + TRUNCATE across all roles** (incl. `service_role`):
- Minimal V1.0 cash-core (DP-2): `trans_id` PK · `account_id` FK→`pfin.account` (`ON DELETE RESTRICT`; **sole tenant anchor via the `account_users.rd_access`-JOIN — no own `users_id`**) · `transaction_date` · `amount NUMERIC(20,4)` · `vendor` · `description` · `is_reverse` · `replaces_trans_id` self-FK · `plaid_transaction_id` · `import_hash` · `created_at` IMMUTABLE (Lock 15 mod #1). **No `updated_at`/`reconciled_flag`/`skip_flag`** — append-only realization (reconciled state lives in the reconciliation link; edits via reverse-and-replace). Dedup partial-unique indexes (Decision 8). RLS **fence-only/default-deny** (the rd_access/wr_access-JOIN → SELF-190).
- **Three triggers, all SECURITY INVOKER (allowlist stays 3):** `fn_account_trans_block_mutation` (BEFORE UPDATE/DELETE, raise-loud — blocks `authenticated` AND `service_role`; service_role bypasses RLS but not triggers, Decision 2 / Lock 10 mod #8); `fn_account_trans_block_truncate` (BEFORE TRUNCATE statement-level + `REVOKE TRUNCATE` — closes a Sec-flagged bulk-erase bypass that row-level triggers miss); `fn_account_trans_matched_account` (BEFORE INSERT, **NULL-safe `NOT EXISTS`** matched-account validation on `replaces_trans_id` — Decision-3 2nd instance, implements Lock 10 mod #2, family count +0/stays 7).

**Sequencing corrected.** `004` account_trans precedes `005` reconciliation (`reconciliation_event_trans` junctions account_trans); the inverted Wave-1 order + Linear dependency flipped (SELF-188 renumbers `003`→`005`).

**Reviews.** 7 DPs F/CTO-ratified; pre-authoring Sec GREEN (3 surfaces) + 2nd Sec review GREEN on the DDL — `ON DELETE RESTRICT` accept-and-defer concurred (weakening it would be a Decision-2 violation), and the **TRUNCATE bypass caught + closed**. QA RT-18 cross-tier battery `plan(9)`: UPDATE/DELETE/TRUNCATE blocked under `service_role` (the trigger, not RLS), authenticated fenced at the table ACL, matched-account cross-account-rejected/same-account-accepted; QA's layering insight (ACL-denial under authenticated vs trigger under service_role) sharpened the cross-tier proof. **8/8 CI green first run.** §10 catalogued ledger unchanged at 2 (immutability triggers are Decision-2 mechanisms, not §10 instances). (Note: pushed via the HTTPS fallback — SSH port 22 was timing out.)

**Follow-ups.** **SELF-190 (B5):** the rd_access/wr_access-JOIN RLS policies + the Lock-3-mod-1 column-restriction hard-gate + SELF-187's deferred cross-tenant assertion (ii). **User-deletion / GDPR-erasure** cross-cutting decision (RESTRICT defer; resolution **must preserve immutability**; hard prerequisite before any user-deletion UI) — durable BACKLOG entry to follow. Decision-3 count grain reconciliation (canonical = 7) — doc-hygiene pass.

---

### v1.58 — 2026-06-30

**Phase 6 — ADR-022: `account_type` modeling rationale (CHECK vs lookup table).** Branch `meta/account-type-taxonomy-rationale`. Records the previously-unwritten rationale (surfaced by an F/CTO question) for SELF-187's `pfin.account.account_type` being a fixed `TEXT+CHECK` 7-member enumeration rather than a `pfin.account_type` lookup table.

**Principle (ADR-022, Architect):** fixed **code-coupled** taxonomies → `TEXT+CHECK`; **user-extensible** taxonomies → lookup tables (V1-seed / V2-CRUD). `account_type` is the former — per ADR-002 §1.9 each type drives ingest path + NAV grouping (PRD §2.1.5) + asset-allocation bucket + income treatment, so adding a type is a **code event, not a data event** (a lookup table buys nothing in V1: no row is addable without handling code). Contrast — the user-extensible pattern IS used where it fits: `scope` free-text (ADR-004 Decision B) + `user_taxonomy` Cat/Sub-Cat (ADR-004 Decision C). `TEXT+CHECK` over PG `enum` avoids the `ALTER TYPE` one-way-door. Terse pattern; no Sec gate (documents an existing CHECK — no DEFINER/RLS/§10/secrets surface).

**V2 follow-up (BACKLOG §5.7, PM):** a promote-`account_type`-to-`pfin.account_type`-lookup-table re-assessment candidate, triggered by the first need for **per-type metadata** (display label / icon / default `tax_treatment` / Plaid-product mapping / sort order); contained migration when it lands (create + seed 7 + swap CHECK→FK + backfill). A tracked re-assessment trigger, not a committed V2 ship.

---

### v1.57 — 2026-06-29

**Phase 6 — SELF-187: first V1 base-table migration (`003_account_and_account_users`).** PR #121 · milestone *V1.0 — Platform foundation*. The first real build-loop feature, validated end-to-end (Architect scope → QA + Sec joint-review → DevOps CI → branch-protected PR → F/CTO ratify) on production schema.

**What landed** — `pfin.account` + `pfin.account_users` + `fn_grant_creator_access` as one bundled migration (DP-1; renumbered 002→003 since `002` = `fn_mask_acct_number`):
- **`pfin.account`** — minimal V1 column set (DP-6, PRD §2.4 + SD matrix): `users_id` (`DEFAULT auth.uid()`; direct RLS `users_id = auth.uid()` + the linchpin INSERT `WITH CHECK`), `name`, `account_type` (`TEXT+CHECK` = PRD §2.1.5 verbatim, 7 members), `scope` (free-TEXT per ADR-004 Decision B), `tax_treatment` (3-way), `acct_number` (nullable, SD-15 masked-render), `is_active`, timestamps. Plaid / taxonomy FKs deferred to their owning migrations.
- **`pfin.account_users`** — V1-dormant per-account ACL (Decision 6 / Lock 2 / Lock 3): SELECT-only `authenticated` grant, `ENABLE RLS users_id = auth.uid()`, **no** authenticated I/U/D (DEFINER trigger sole writer), `account_id` FK `ON DELETE CASCADE`. UPDATE/DELETE + the Lock-3-mod-1 column-UPDATE restriction hard-gated to B5 (recorded in the schema comment).
- **`fn_grant_creator_access`** — SECURITY DEFINER (Decision 7 mod #2), `set search_path = ''`, `REVOKE EXECUTE FROM PUBLIC`, fixed insert from `NEW.users_id`.

**DEFINER allowlist reconciled 2→3.** `fn_grant_creator_access` was already locked DEFINER at Decision 7 mod #2 but uncaptured by the "exactly 2" enumeration; SELF-187 reconciles it. New Decision 9 SELF-187 amendment + `supabase/CLAUDE.md` + 3 agent cards → 3-entry; `001` header + Decision 10 get forward-pointers (not mutations); Decision 9's prior "3→2" history preserved (distinct transition — PR #106 dropped `fn_mask_acct_number`). Committed allowlist = 3 (authored DEFINER fns = 2; audit-log helper still unauthored). The **§10 catalogued ledger is unchanged at 2** (RT-22 + RT-26) — explicitly de-conflated as a separate ledger from the DEFINER allowlist.

**Reviews.** Architect scoping (6 DPs F/CTO-ratified: bundle / renumber / allowlist-2→3 / Decision-3-disposition / RLS-shape / minimal-columns) + pre-authoring Sec concurrence (GREEN, both veto surfaces) + 2nd Sec review on the DDL (GREEN; both rulings concurred — `ON DELETE CASCADE` as ACL-not-audit, direct-on-`account` RLS as anchor-not-JOIN). QA two-tenant pgTAP battery `plan(10)` (`supabase/tests/rls/003_account_and_account_users_rls.sql`): creator-grant fires under RLS, owner-reads-own, cross-tenant fails closed, the forged-`users_id` linchpin, no authenticated write on `account_users`; the account_trans-JOIN assertion correctly deferred (not faked). The wire-validate run caught **and fixed** a test-harness bug (`_rls` schema USAGE under the `authenticated` role) plus a latent false-green (schema-denied / ACL-denied / WITH-CHECK-violation all SQLSTATE 42501 → switched to message-precise `throws_like`). 8/8 CI green.

**Follow-ups** (non-blocking): `account_trans` (`004`) carries the deferred JOIN assertion + the `rd_access`-JOIN read path; B5 hard-gate (Lock-3 mod #1 column restriction MUST land in the same PR that first grants any authenticated write on `account_users`); Decision-3 family-count grain reconciliation (canonical = 7; `CHANGELOG:209` 5-vs-6 miscount) — separate doc-hygiene pass.

---

### v1.56 — 2026-06-29

**docs(meta): Linear Concept→object mapping table.** Added an explicit *Concept → Linear mapping* subsection to `docs/linear-setup.md` §1: repo project → **Initiative**; feature cluster (PRD §2 area / substrate) → **Project**; V1 sub-version → native **project-milestone**; feature/one-PR → **Issue**; sprint → **Cycle**. Notes capture the two-layer Project-vs-milestone distinction (the common mental-model slip), the V1.0-spans-3-native-milestones case, and the coarse-labels-vs-native-milestones distinction, with SELF-187 as the worked example. Clarification only — no topology change. F/CTO-requested at Phase 6 entry while orienting on SELF-187.

---

### v1.55 — 2026-06-29

**Phase 6 — ARCH §5 Deployment Topology greenfield reframe.** Companion to v1.54 ([ADR-021](DECISIONS.md#adr-021)): re-anchors the Phase-3-locked ARCH §5 on the greenfield posture before base-table work begins. Branch `phase/plan-arch-s5-greenfield-reframe` (Architect). 9 edits in §5; `docs/ARCH/index.html` only.

**Host reframe.** cax21/`pfindash.com` → **reference-precedent sizing baseline**, not the deploy target; V1 host is a **new greenfield VPS** provisioned from scratch at deploy time. Forward-pointer to `docs/deployment-runbook.md` added. **Postgres 17** stated as the chosen forward DB target (greenfield rationale; the 15.8 incumbent reading moot). The Lock 13 3-container + monthly_report-cron **topology is unchanged** — host-independent; only the host changes. Operational/admin boundaries reworded host-neutrally (VPS host SSH; Coolify control plane on the VPS; Discord *emitter* re-created on the greenfield VPS, *target* webhook reused).

**Two ARCH↔code reconcile flags closed** (both Sec-dispositioned LOW at v1.54 S3): (i) ETL DB secret reframed from single connection-string → discrete `PFIN_DB_*` params (the one sensitive credential is `PFIN_DB_PASSWORD` at `production_only`; `TenantBoundConnection` commitment preserved in substance); (ii) BLS reframed from "free/open" → requires `BLS_API_KEY` (low-sensitivity rate-limit key over public CPI data) — `BLS_API_KEY` surfaced in the §5 ETL secrets list. Mermaid host-subgraph + BLS node labels updated.

**Sec confirm-pass GREEN.** §10 catalogued-instance ledger **untouched by-construction** (RT-22/RT-26 + layer-attribution lines not in the diff — Architect by-construction claim + Sec Sec-Lock cross-check + team-lead diff cross-check, three-way confirmed; 23+ CLEAN streak preserved). Secrets surface **not expanded** (every named secret already in `secrets-manifest.yml` `production_only`; the four discrete `PFIN_DB_*` non-password fields are non-secret connection config). Mermaid **browser-render-verified** at draft-time via isolated `docs/test-arch-s5.html` harness (a `<br/>` two-line label collision caught + fixed to single-line; harness deleted post-verify).

---

### v1.54 — 2026-06-29

**Phase 6 — V1 greenfield deployment posture ([ADR-021](DECISIONS.md#adr-021)).** First Phase 6 doc-update PR (branch `meta/greenfield-deployment-posture`). While clearing the carried `config.toml major_version = 17` confirm-vs-prod gate, F/CTO ratified that V1 is **greenfield**: built from scratch on a **new VPS** at deploy time. The live `pfindash.com` deployment (self-hosted Supabase on Coolify on the Hetzner **cax21** box, alongside `pfin_back_etl`) is **reference-only, NOT a deploy dependency**, and may be torn down at ship time.

**PG-17 gate closed by-decision, not measurement.** A read-only `SHOW server_version` against the live cax21 box on 2026-06-29 returned **15.8** (vs `config.toml major_version = 17`). Under greenfield the Supabase-CLI "local must match remote" rule does not bind (no remote depended on), so **PG 17 stands as the forward target by choice**; the 15.8 reading is recorded and declared moot. Resolves the ADR-020 carried follow-up.

**ADR-021 (Architect).** Records the posture + 3 options considered (A greenfield [chosen] / B adopt-incumbent-in-place / C in-place PG 15→17 upgrade) + 2 genuine one-way doors (PG-17 migration-authorship lock-in; destructive `pfindash.com` teardown) + §10 3-axis CLEAN (catalogued ledger unchanged at 2 — RT-22 + RT-26; Path B reference-not-restate). Recommends a separate Architect-led **ARCH §5 Deployment Topology refresh** (cax21 framing → reference-only) — flagged, not done in this branch.

**`docs/deployment-runbook.md` skeleton (DevOps).** New Markdown runbook stub — 10 sections (VPS provision / DNS / Coolify / Supabase-from-scratch PG17 / secrets / migrations / workers / observability / cutover+teardown / verification) + open-flags roll-up; every section carries a `> **STUB —**` marker, real-artifact-anchored (`secrets-manifest.yml`, the three `.env.example`, migrations `001`/`002`, Lock 13 3-container topology). §5 secrets-provisioning is **Sec-joint-review-gated**; surfaces two pre-existing reconcile flags for deliberate resolution (ETL discrete `PFIN_DB_*` vs ARCH §5 connection-string; BLS key-required vs ARCH §5 "free/open").

**`config.toml` + `supabase/CLAUDE.md` reword (Architect).** `major_version = 17` kept; provisional/confirm-vs-prod framing replaced with greenfield-by-decision (cites ADR-021) on `config.toml` line 42 and the two `supabase/CLAUDE.md` mentions.

**Meta-principle codified:** *do not rely on a working existing deployment* — all V1 CI fences + migrations stand up a fresh environment from repo state alone. Memory: `feedback_greenfield_no_existing_deployment_dependency` + `reference_hetzner_cax21` reframe.

---

### v1.53 — 2026-06-29

**Phase 5 (Workshop Setup) ✅ COMPLETE + Phase 6 (Build Loop) entered.** Step 9 exit-criteria walk + SELF-186 V1.0 first-implementation close-gate smoke-test. F/CTO signed off on Phase 5 exit → Phase 6 entry. Phase-gate recorded at [ADR-020](DECISIONS.md#adr-020). PRs #116 (SELF-186) + this close PR.

**Exit-criteria walk — 7/7 PASS + mosko extensions.** (C1) task assignable end-to-end — SELF-186; (C2) CI on clean checkout — 8/8 green; (C3) branch protection on main — **configured at close** (see below); (C4) 10 agent defs with Linear scope; (C5) Phase 0.5 defs re-signed-off; (C6) invoke-by-name; (C7) agent+Linear-issue end-to-end — SELF-186. Extensions: §10 discipline preserved (every Phase 5 surface CLEAN; grain-count reconciliation carried), SD-15 + RT-15 closed (Step 4), milestone-rotation rehearsal (Step 7), 8 lessons-learned codified in WORKFLOW.md.

**SELF-186 — `001_pfin_foundation.sql` (the smoke-test) PASSED.** Architect scoping surfaced that the issue's literal "rename `tenant_id` → `users_id`" was unsatisfiable — the incumbent `pfin` schema has no `tenant_id` (20 tables, none); Lock 6 / ADR-011 Decision 10 was a naming decision already swept to `users_id` in the Step-4-close prose. F/CTO ratified **Option A**: `001` **instantiates** the `users_id = auth.uid()` convention rather than renaming — `create schema pfin` + `pfin.fn_refresh_updated_at()` SECURITY DEFINER trigger helper (1 of the 2 locked Decision-9 allowlist entries; `set search_path = ''` privesc fence; body touches no tables). **Sec joint-review GREEN** (search_path fence exact; DEFINER matches locked D9; §10 ledger untouched, 3-axis CLEAN; no RLS predicate weakened). **[ADR-011 Decision 10 amendment](DECISIONS.md#adr-011)** (greenfield reconciliation; annotate-not-rewrite) reconciled the 4 AC-drift clauses. The migration ran the full **Architect → Sec joint-review → DevOps CI (`db-tests` applied it on a live Supabase, green) → branch-protection gate → F/CTO ratify** loop, and the Linear C7 loop (read → In Progress → comment → Done). File renamed `001_users_id_rename` → `001_pfin_foundation`.

**Branch protection on main — configured (closes C3).** The exit walk found "branch protection on main" (a stated `CLAUDE.md` convention) had **never actually been enforced**. Configured via `gh api`: require PR + the 7 always-run `security-scan` checks (strict) + 0 required approvals (solo-dev) + `enforce_admins = true` (no direct push to main, including F/CTO). Path-filtered `db-tests` intentionally not a required context (would deadlock doc-only PRs). Validated live on SELF-186 (first `feature/*` PR through the gate).

**Carried into Phase 6** (per ADR-020): the `fence-tbc` integrity gap (fails open on the real ETL tree — fix at Wave 6); §10 streak grain reconciliation; `config.toml major_version = 17` confirm-vs-prod before base-table work; BLS ARCH↔code reconcile; `role:qa`/`role:devops` Linear labels; W0b Coolify repoint. **Phase 6 begins the V1.0 Build Loop** (SELF-187+ base-table migrations on the `001` substrate).

---

### v1.52 — 2026-06-28

**Phase 5 Step 8 — pre-commit hooks + secrets management.** DevOps-led; **Sec joint-review GREEN** (AMBER→GREEN); F/CTO ratified. PR #114 (`meta/phase-5-step-8-hooks-secrets`) + doc-state companion (this entry).

**Pre-commit hooks** (F/CTO decision: land runnable linters now, defer JS to Phase 6). Root `package.json` (minimal Husky host — NOT the SvelteKit app, which scaffolds under `api/` in Phase 6) + `.husky/pre-commit` running **`ruff`** (staged `workers/etl/**/*.py`) + **`hadolint`** (the 2 Dockerfiles), graceful on missing binaries. `svelte-check` + eslint are commented stubs marking the exact Phase-6 activation point. `[tool.ruff]` config added to `workers/etl/pyproject.toml`. `package-lock.json` committed (the npm-audit CI job requires a lockfile; `npm install --package-lock-only` reports 0 vulnerabilities); `node_modules/` gitignored.

**Secrets management** (per ARCH §5; per-surface confinement is the security property). Three `.env.example` files: root (V1 web-app — `SUPABASE_ANON_KEY` + `SUPABASE_SERVICE_ROLE_KEY` [RT-26 §4.1 allowlist] + `PDF_WORKER_SIGNING_KEY` [SD-20] + Plaid + Discord), `workers/etl/` (`PFIN_DB_*` + FMP + BLS + Plaid), `workers/pdf-render/` (**ONLY** `PDF_WORKER_SIGNING_KEY` per Lock 13 mod #2 zero-DB). `sample.env` superseded. **`secrets-manifest.yml`** — the CI/production non-overlap commitment: `ci_only` (3, distinct-named sandbox/test analogues) vs `production_only` (10, Coolify-injected), disjoint by construction (blast-radius containment). Fail-closed CI fence `scripts/ci/check-secrets-nonoverlap.py` + dual-mode `secrets-nonoverlap` job in `security-scan.yml` (real manifest passes; overlap fixture must fail; missing/malformed/duplicate → fail closed).

**Sec joint-review (AMBER→GREEN).** CLEAN on the load-bearing surfaces: PDF-worker zero-DB confinement (Lock 13 mod #2 — "perfect, the one true veto surface"), the non-overlap fence fails closed on all four criteria, distinct-naming discipline sound, §10 catalogued-instance ledger untouched (Path B — references RT-22/RT-26/SD-20 without restating counts or layer-attribution). One cheap **blocking condition resolved**: the ETL `.env.example` asserted TenantBoundConnection as present-tense fact, but TBC is not yet in the code (incumbent uses SQLAlchemy `create_engine` at `core.py:231`) — reworded to forward-discipline framing (Sec's exact text) so the doc doesn't assert an unenforced control as enforced. BLS key accepted-with-annotation (citation fixed to ARCH's "free/open").

**Tracked follow-ups (F/CTO-ratified, non-blocking on the lock).** (1) **`fence-tbc` integrity gap** (the more serious finding): the existing TBC CI fence is non-enforcing on the real ETL tree — its grep doesn't match `sqlalchemy.create_engine(...)` and it fails *open* on TBC-class-absence in production-mode (stale post-ADR-019 assumption). Folded into the ETL-CI-coverage follow-up; fix when TBC actually lands (Wave 6). (2) **BLS** — reconcile ARCH §5 "free/open" vs ETL code requiring `BLS_API_KEY` (Architect).

---

### v1.51 — 2026-06-28

**Phase 5 Step 7 — Linear MCP setup verification + milestone-rotation rehearsal.** Lands `docs/linear-setup.md` (operational how-to per the WORKFLOW.md `/docs` pattern). DevOps-led; PM + F/CTO ratify. PR #112 (`meta/phase-5-step-7-linear-setup`) + doc-state companion (this entry).

**F/CTO-ratified scoping.** Two decisions taken before execution: (a) the milestone-rotation rehearsal runs as a **read/verify dry-run** on the as-built model (nothing has completed, so no live rotation); (b) the per-agent permission test covers **existing-label roles only** (`role:qa`/`role:devops` labels don't exist; `role:pm` tags zero issues — those three deferred to Phase 6).

**Workspace verification.** Team `SELF` (Mosko-Personal) / initiative "V1 launch" → 7 feature-cluster projects / 89 mosko issues SELF-181→SELF-269. **Milestone model verified live as native Linear project-milestones** — V1.0 (spans 3 milestones across Platform + Onboarding + Net worth) · V1.1 Net worth · V1.2 Asset allocation · V1.3 Cash flow · V1.4 Estimated taxes · V1.5 Monthly report (shell exists, 0 issues — the BACKLOG §7 promotion target) · V1.x Cross-cutting · V1.final §3.4 close. This **corrected an earlier scouting error**: an `includeMilestones` 400 had wrongly reported "no native milestones," which was relayed as a finding before being verified — the verbatim-verify discipline (`brief-drift-catch`) caught it on direct inspection. The ADR-017 D2 per-sub-version reasoning and the as-built workspace agree; no doc reconciliation needed.

**Rotation rehearsal dry-run.** The `/milestone-rotation` Step 0 gate was validated against a **partially-complete** milestone — `V1.0 — Platform foundation` is 1/16 Done (SELF-195, an early dedup/fold-in closed 2026-06-03), explaining its 6.25% progress; not all issues Done → the gate **correctly refuses to rotate**. §7 promotion set confirmed = 18 entries (cross-checked vs BACKLOG.md). No mutations.

**Permission write-path proof.** Verified end-to-end on SELF-269: posted a test comment + flipped `Backlog → Todo`, both succeeded, then reverted `Todo → Backlog` + deleted the comment (left clean; only `updatedAt` moved). Read scope confirmed live for all 6 labeled roles; the write mechanism is identical across roles, so one cycle validates the path.

**Process note.** The DevOps execution agent died mid-run when the safety-classifier + Linear-MCP-token outage hit; team-lead finished the read/verify directly and reverified all cells on re-auth. **Open gaps** (in `docs/linear-setup.md` §4): create `role:qa`/`role:devops` labels at Phase 6 (F/CTO action); attach 3 NO-PROJECT mosko issues to their cluster (cosmetic).

---

### v1.50 — 2026-06-26

**Phase 5 Step 6 — skills library.** Adds four user-invocable skills under `.claude/skills/`, each owned by the role whose discipline it codifies — turning conventions that previously lived only in memory/ADR prose into invocable, self-checking procedures. PR #110 (`meta/phase-5-step-6-skills`). Landed in two commits: `brief-drift-catch` first (WIP 1/4, `20ab582`), then the 3 role-owned skills (`e26a42b`).

- **`brief-drift-catch`** (CoS/team-lead meta-skill) — verbatim-source cross-check (5 drift classes: paraphrase / citation-attribution / quote-completeness / header-vs-body / count) + the 2-teammate independent-verification pattern for high-stakes brief-vs-canonical boundaries. Operationalizes the `feedback_team_lead_sec_ratify_lock_cross_check` + `feedback_decision_4_instance_ledger_cross_check` + `feedback_post_ratify_v1_cross_check` + `feedback_async_mismatch_boundary_hooks` memories.
- **`milestone-rotation`** (DevOps) — the [ADR-017](DECISIONS.md#adr-017) Decision 2 rotation procedure: verify current-milestone completion against **live** Linear (not memory), rotate next→current, promote the milestone-after-next from BACKLOG.md §7 → Linear verbatim (Source/AC/Dependencies carried; §7 entries marked "Promoted to Linear at SELF-N"), update the MILESTONES.md 5-entry ledger (Decision 1) + land the CHANGELOG `vX.YY` entry. Phase 5 Step 7 rehearses its read/verify path.
- **`apply-migration`** (Architect) — the migration-authoring procedure from `supabase/CLAUDE.md`: file shape (POSTURE RATIONALE + CONTRACT blocks + `set search_path = ''` + idempotent schema), mandatory §10 3-axis cross-check before drafting, Decision 3 matched-tenant validation for every FK-shaped column (incl. `INTEGER[]`), SECURITY-DEFINER→Sec-joint-review routing, the grant-then-RLS gotcha, and same-PR QA pgTAP pairing. SELF-186 (Step 9) runs through it.
- **`spawn-sec-joint-review`** (PM) — the joint-review-mandatory trigger inventory ([ADR-011](DECISIONS.md#adr-011) D1 privileged-context-write / D2 immutable+INSERT-new-version audit-class / D3 cross-tenant FK-bypass family / D4 §10 catalogued-instance ledger + new SECURITY DEFINER fn + any §10 ledger change + auth/money/secrets/Plaid/financial-calc/multi-tenant) with Sec VETO authority, a self-checking dispatch template (embeds the §10 3-axis verify-hook + the self-triggered-task_assignment-echo drop block), and GREEN/RED/AMBER verdict interpretation.

**Process.** The 3 role-owned skills were authored by fresh role-agent spawns (DevOps/Architect/PM; the prior session's spawns had stalled without writing files). Team-lead then ran `brief-drift-catch`'s own discipline over each draft, **independently verifying every load-bearing count against live source** (not the relayed cross-check logs): D3 = **7** at Phase 4 close (correctly distinguished from the "Four V1 instances" at ADR-011 D3 drafting time), D4 ledger = **2** (RT-22 first / RT-26 second), DEFINER allowlist **3→2**, 89 Linear (SELF-181→SELF-269) + 18 BACKLOG §7. One minor path nit fixed in `milestone-rotation` (a CHANGELOG link written into MILESTONES.md corrected to root-relative). All 6 Security-scan CI checks GREEN. F/CTO signed off on content before merge per the Phase 5 gate criterion ("F/CTO sign-off on every agent definition + skills").

**Follow-up:** MILESTONES head + this CHANGELOG entry land in the companion doc-state PR (`meta/phase-5-step-6-doc-state`). Not in Step 6 scope: `start-feature`/`finish-feature` (Phase 6 entry per [ADR-009](DECISIONS.md#adr-009) Decision 7).

---

### v1.49 — 2026-06-26

**Phase 5 Step 5 — per-directory `CLAUDE.md` files.** Adds four scoped `CLAUDE.md` files giving Claude Code surface-local context (root `CLAUDE.md` + ARCH/SECURITY/DECISIONS stay source-of-truth; these are quick-references). F/CTO ratified "all 4 now, forward-looking for `api`/`web`". PR #108 (`meta/phase-5-step-5-claude-md`).

- **`supabase/CLAUDE.md`** (Architect) — migration file shape (numbering / POSTURE+CONTRACT blocks / `set search_path = ''` / idempotent `create schema`); RLS-default-trust + Lock 11 SECURITY INVOKER read-composition + the corrected **2-entry** DEFINER allowlist (ADR-011 D9); §10 SD+RT enforcement (preserve the 2-instance ledger / matched-tenant DDL incl. `INTEGER[]` per Decision 3 / paired pgTAP battery test + 3-axis pre-emptive cross-check); grant-then-RLS gotcha (PR #106); provisional PG-17.
- **`workers/CLAUDE.md`** (Backend) — ETL Python (`uv`/`pyproject`/`ruff`/`pytest`); TenantBoundConnection fence (Lock 13 mod #3; greps `workers/etl/`); same-transaction audit-log; Coolify native cron → Discord; **PDF-worker zero-DB-by-design** (Lock 13 mod #2) + the RT-22-is-infra-credential-presence-NOT-TBC distinction.
- **`api/CLAUDE.md`** (Backend; **forward-looking** — `api/` scaffolds Phase 6) — server-source surface allowlist anchored at **ARCH §4.1**; `SUPABASE_SERVICE_ROLE_KEY` confinement to the 3 ADR-016 RT-26 allowlist endpoints; Zod `.strict()` (Lock 14 mods #1 typed-input + #2 mass-assignment); SECURITY INVOKER read-composition + never-write-DEFINER; `hooks.server.ts` session chokepoint (ADR-015 D1).
- **`web/CLAUDE.md`** (Frontend; **forward-looking**) — non-`server` surface ownership; `var(--c-*)` tokens-only; ADR-013 P5 no-inline-edit; INV-1 plain-text commentary fence; the 3-signal staleness-marker framework (`stale-data-marker` D1 / `reauth-staleness-banner` P4 / `freshness-stamp`); no-secrets-in-browser.

**Process.** Role-owners drafted in parallel (Architect / Backend ×2 / Frontend); team-lead normalized for house-style + citation accuracy; Security Reviewer joint-review **GREEN on all 4** (no vetoes). **§10 attribution three-axis CLEAN** across all four (Path B link-carry — references the ledger, does not restate it; streak extended). **Two productive Sec-Lock cross-check catches:** (i) Frontend caught an ARCH-§4.1-vs-SECURITY-§4.1 anchor drift in the team-lead brief (server-source allowlist is anchored at ARCH §4.1; SECURITY §4.1 is tenant-isolation posture) — propagation fixed in `api/`; (ii) Sec caught a Lock-14 mod-number mislabel in `api/` (corrected to #1 typed-input validation + #2 mass-assignment prevention) and re-confirmed the fix at the boundary. Stale SD/RT entry-counts dropped (no-number framing).

**Follow-up:** `api/` + `web/` get a light refine when SvelteKit scaffolds in Phase 6 (pin concrete `src/routes/...` paths; reconcile the illustrative Plaid route paths + `src/lib/server/plaid/` default per ADR-016's "or equivalent per Phase 5 routing convention").

---

### v1.48 — 2026-06-25

**Phase 5 Step 4 W2 + W3 — SD-15 masking helper + pgTAP RLS battery + `db-tests.yml` CI venue.** Closes the two Phase-4-deferred implicit gaps (SD-15 `fn_mask_acct_number()` masked-rendering helper + RT-15 parity-fixture test-environment RLS posture) routed to Phase 5 Step 4 at Phase 4 close. Lands the first `supabase/` scaffold (`supabase init`: `config.toml` + `.gitignore`) and the first applied DB function migration in-repo. PR #106 (`meta/phase-5-step-4-w2-w3`).

**W2 — SD-15 `fn_mask_acct_number` migration + `supabase init` scaffold (`c23f1ab`).** New migration `supabase/migrations/002_fn_mask_acct_number.sql` (numbering reserves `001` for the foundational `users_id_rename` migration / SELF-186, authored later; `fn_mask` is order-independent). **SD-15 ratified Option A — `pfin.fn_mask_acct_number(text)` is a pure `IMMUTABLE`/`STRICT` SQL string transform (`length<=4 → '••••'`; else `'••••'` + last-4, original length not leaked; `NULL → NULL`), carrying the default SECURITY INVOKER posture — NOT SECURITY DEFINER.** It reads no tables and needs no elevated privilege: it is the masking *primitive*, not the privilege boundary. The "full value never user-facing" guarantee is enforced at the app-layer rendering + the Phase-6 PR-review fence on full-value-disclosure surfaces ([ADR-011](DECISIONS.md#adr-011) Decision 9 Sec mod #2; QA authors the disclosure-fence test in W3). See ADR-011 Decision 9 amendment.

**W2 — V1 SECURITY DEFINER allowlist corrected 3→2 (`b19b200`).** Consequence of SD-15 = Option A: `fn_mask_acct_number` is dropped from the V1 SECURITY DEFINER allowlist, which now stands at **2 entries — `fn_refresh_updated_at` + the audit-log insert helper.** Dropping a pure function *tightens* the elevated-privilege surface (a security improvement, not a weakening — Sec-confirmed). Wording applied verbatim across the three agent defs that enumerate the allowlist: `architect.md` (self-edit), `backend-engineer.md` (defining-behavior), `security-reviewer.md` (scope-of-concern + joint-review list). The two non-self edits were F/CTO-authorized (agent-def modification is human-gated; the harness blocks inter-agent relay of agent-def edits as permission-laundering).

**W3 — test infrastructure: pgTAP RLS battery + parity fixtures (`3239a4f`).** `tests/rls/DESIGN.md` (RLS verification battery design — per-Wave two-tenant cross-tenant isolation posture per SECURITY §4.5); `supabase/tests/` pgTAP suite (`00_rls_inversion_self_test.sql` RLS-inversion canary + `sd15_fn_mask_acct_number.sql` SD-15 unit coverage + `_fixtures/rls_verbs.psql` shared two-tenant verbs); `tests/fixtures/parity/README.md` (RT-15 parity-fixture posture for `workers/etl/` against production-shape data); ETL replay-parity fixtures (`workers/etl/tests/` replay harness + BLS/FMP JSON fixtures + `test_replay_parity.py` — first-green target for the deferred ETL CI follow-up).

**W3 — `db-tests.yml` pgTAP CI venue + first-run fixes (`b7aa044` / `895ed50` / `6434f8c` / `51d4f6e`).** New `.github/workflows/db-tests.yml` runs the pgTAP battery against a local Supabase via the shared `.github/actions/supabase-cli-setup` composite action. First-run fixes: dir-mode + `.psql` verb extension to resolve `\ir` container-mount path resolution; **grant table privileges to `authenticated` before RLS** on the inversion canary (the grant-then-RLS shape — RLS filters rows but table-level `GRANT` is still required for the role to reach the table at all; root-cause durable in `supabase/tests/README.md`).

**§10 attribution discipline — three-axis CLEAN (Sec-verified).** W2/W3 add no catalogued §10 instance (RT-22 + RT-26 remain the 2-instance commitment); SD-15 is a masking primitive, not a privileged-context surface; instance-numbering + layer-attribution + verbatim-vs-paraphrase all preserved. (No-number streak framing per the in-flight §10 grain reconciliation follow-up.)

**Follow-ups carried forward (durable):** (i) **ETL CI coverage** (`ruff` + `pytest` + `uv`/`pyproject`-aware dep-vuln audit for `workers/etl/`; `test_replay_parity.py` is the first-green target; `.github/actions/supabase-cli-setup` is shared infra) — high-pri, deferred from W0a. (ii) **`config.toml [db] major_version = 17` is PROVISIONAL** — F/CTO match-prod best-guess; confirm against cax21 prod before Phase 6 RLS base-table work (15/17-identical for current battery content, low-stakes today). (iii) **§10 attribution-streak grain reconciliation** — pick one canonical grain + restate (MILESTONES "25+/31+" vs Sec's fresh count). (iv) **CHANGELOG backfill** — Phase 5 Steps 2–3 agent-def PRs (#97–#103) landed without per-version CHANGELOG entries (this v1.48 names them; no separate narrative entry). (v) Trivial: `actions/checkout@v4` → `@v5` Node-20 deprecation bump across `security-scan.yml` + `db-tests.yml` + the composite action.

---

### v1.47 — 2026-06-21

**Phase 5 Step 4 W0 — monorepo topology consolidation; `pfin_back_etl` source absorbed at `workers/etl/`.** Per [ADR-019](DECISIONS.md#adr-019) (polyrepo → monorepo). W0 folds the incumbent sibling-repo `pfin_back_etl` Python source into the mosko-fintech monorepo at `workers/etl/` (sibling to `workers/pdf-render/`), retiring the cross-repo paired-PR + vendored-copy convention that Phase 5 Step 4 W1 (PR #104 + paired `pfin_back_etl` PR #14) operationalized and proved costly going-forward. **Source-organization change only — the 3-container runtime topology, all Lock 13 mods (#1–#10), and the §10 catalogued-instance ledger are unchanged by-construction.** W0 is numbered before W1 by topology-precedence but lands after W1 chronologically (W1 + paired PR #14 stand as-merged; W0 retires the pattern going-forward, not retroactively).

**5 sub-decisions ratified by F/CTO** (against Architect leans): (1) ADR shape → **C hybrid** (new ADR-019 + [ADR-011](DECISIONS.md#adr-011) Decision 17 reciprocal annotation); (2) CI restructure → **A** (extend the `fence-tbc-inversion` job to dual-mode `fence-tbc` — production + inversion in one job, matching the `fence-rt22` pattern); (3) §10 annotation surface → **A** (ADR-019 § only; **Decision 4 NOT amended** — W0 is a topology shift, not a drift catch); (4) Coolify config-change → **A** (in-place reconfigure to Base Directory `workers/etl/`; delete-recreate named fallback — W0b operational); (5) `pfin_back_etl` repo decommissioning → **A** (minimal archive + README banner — W0b operational).

**W0a execution (this PR).** W0a-1 (DevOps) — fresh import of `pfin_back_etl` `f047e88` working tree → `workers/etl/` (commit `20ca752`; no git history per F/CTO β.2 ratify; `.github/`/`scripts/ci/` excluded — fence + fixture already canonical in mosko-fintech). W0a-2 (DevOps) — `security-scan.yml` TBC job → dual-mode; `scripts/ci/README.md` retires the `Cross-repo TBC posture` subsection (§10 cross-reference subsection retained). W0a-3 (Architect) — ADR-019 body + D17 reciprocal annotation; ARCH §5 Deployment Topology source-location note + §6/§6.1 TBC grep-target retargets (`pfin_back_etl` → `workers/etl/` Python source; **§10 attribution framing preserved verbatim in-sentence** — "NOT a catalogued §10 instance" / "Decision 4 numbered list stays 2-instance" untouched); `backend-engineer.md` mechanical source-location path-swaps.

**§10 attribution discipline — three-axis CLEAN; Sec-verified at W0a-3 joint-review.** (i) instance-numbering: RT-22 first / RT-26 second; 2-instance commitment; zero new catalogued instances; (ii) layer-attribution: RT-22 infra-credential-presence (PDF-worker Dockerfile), RT-26 code-layer V1-web-app server-side, TBC at Privileged-context-surfaces bullet (explicitly NOT catalogued) — W0 retargets only the TBC CI grep path, not its layer; (iii) verbatim-vs-paraphrase: Decision 4 referenced by canonical link only (Path B). Decision 4 byte-untouched (Sec's 81-insert/0-delete diff = by-construction proof). Sec-Lock cross-check CLEAN (Lock 13 "10 mods" + D17 topology + ADR-016 precedent verbatim-match).

**Sec carry-forward FLAG-1 (citation-attribution drift) — caught pre-draft + RESOLVED before canonicalization.** The W0 plan's sub-decision 1 justification overstated the ADR-015 precedent as "Decision 17 carries an annotation." Verified verbatim: D17 carries no ADR-015 annotation; the ADR-015↔D17 link is one-directional (cross-ref inside ADR-015 only). ADR-019 reframed accurately: ADR-015 *extends* D17 (one-directional); W0 *adds* the reciprocal D17→ADR-019 back-annotation as a NEW navigation aid, not a precedent-match. SUCCESS-application of the team-lead Sec-Lock cross-check discipline (drift caught + corrected in the canonical surface before lock).

**W0 follow-ups carried forward (durable home — these survive team-tracker teardown):** (i) **ETL CI coverage in mosko-fintech** — the ETL's own `ci.yml` did not migrate at import (deferred under W0a scope-discipline): `ruff` (lint) + `pytest` (test) **+ a `uv`/`pyproject`-aware Python dependency-vulnerability audit for `workers/etl/`** (a distinct *security* gate — NOT covered by mosko's `requirements*.txt`-based `scanner-pip-audit`, so the ETL's `uv.lock` / `pyproject` deps are otherwise unscanned); a real-but-bounded CI-gating gap tracked in WORKFLOW.md Phase 5 Step 4 W-sub-wave note + team task #4. (ii) **W0b Coolify-rebuild runtime-verification gate** — confirm the ETL runs post-rebuild against the `workers/etl/` Base Directory (runtime validation deferred from W0a per the skipped local pytest) + `pfin_back_etl` GitHub repo archive with README banner.

---

### v1.46 — 2026-06-04

**Phase 4 (Project Scoping) → ✅ COMPLETE; Phase 5 (Workshop Setup) entered.** Per [ADR-018](DECISIONS.md#adr-018) Phase 4 close-gate + Phase 5 entry approval. Phase 4 ran 2026-06-02 → 2026-06-04 (3 calendar days; fastest phase-completion in mosko history per Phase 4 lessons-learned). All 6 exit criteria + mosko-specific §10 SD+RT coverage extension PASS. **107 V1 issues total decomposed** across Linear (V1.0–V1.4; 89 issues SELF-181 → SELF-269) + BACKLOG.md §7 (V1.5 + V1.final; 18 entries). Cumulative PRD §2 trace **32/32 stories**. Settings ramp 4/4 closed; Lock 14 family 5/5 closed; both V1 catalogued §10 instances (RT-22 + RT-26) ship V1 per [ADR-011 Decision 4](DECISIONS.md#adr-011) catalogued-instance ledger fully discharged. Meta-process **M1 (Plan / ARCH + SECURITY docs locked) → ✅ COMPLETE**; M2 (Implement + Verify) becomes Active at Phase 5 entry.

**Phase 4 Step 5 Wave 6 (V1.5 Monthly Report + V1.final close-gate / PR #94 / 2026-06-03).** First wave under ADR-017 D2 staging convention. PM + Architect parallel decomposition produced **18 issues staged to BACKLOG.md §7** (8 Architect A1-A8 substrate + 10 PM P2-P11 domain; PM Issues 1+3+6+9 collapsed per F/CTO Gate A unified per Wave 5 precedent + Gate B Option C 4-col absorption). F/CTO ratified 6 gates ("ratify all recommended"):

- **Gate A (cross-draft):** Architect Option B unified `fn_render_monthly_report(p_users_id, p_target_month, p_data_as_of)` SECURITY INVOKER read-composition helper absorbs PM Issues 1+6+9; Lock 11 monthly_report cron consumes via `p_data_as_of` per Lock 15 forward-compat
- **Gate B:** Architect v2 Option C — 4 named TEXT commentary columns on `pfin.monthly_report` parent header (`commentary_cash` + `commentary_bonds` + `commentary_equity` + `commentary_alternatives`); Lock 14 family stays at 5 (no JSONB per forward-compat fence; PRD §2.6.2 fixed 4-sub-section verbatim count). PM Option A separate table rejected. PM Issue 3 absorbs into Arch A1.
- **Gate C:** V1.x Platform cross-cutting scope for PDF worker container (deferred-from-Wave-1 RT-22 fence already lives there)
- **Gate D:** Single calendar-gated V1.final §3.4 verification-protocol issue (P11; N=2 consecutive months; decompose at Linear promotion if F/CTO prefers finer granularity)
- **Gate E:** SECURITY §4.4 derivative-surface annotation lands in separate Sec PR post-Wave-6 (keeps Wave 6 PR tight)
- **Gate F (Architect v2 surfaced):** Option α native Coolify cron container for §2.6.3 cron-trigger mechanism (Lock 13 locks worker location, NOT mechanism — Arch v2 catch); incumbent pattern per `reference_pfin_back_etl`; minimal infra change; Coolify→Discord covers observability

**Architect v2 brief-drift catches** (corrections to my dispatch): TenantBoundConnection vs RT-22 conflation (PDF worker has NO DB access by Lock 13 mod #2 verbatim; TBC fence applies to `pfin_back_etl` Python only — Wave 1 E2); Decision 3 family count corrected 9 → 7 (only A1+A2 add new instances; A5+A8 don't have cross-tenant FK chain); §2.6.4 retention horizon ALREADY PRD-LOCKED indefinite V1 (non-gate); `generation_status` enum vocabulary bridge between PRD presentation (`not-yet-triggered`/`pending`/`generated`) and Lock 11 DB (`draft`/`final`/`superseded`). 5 brief-drift catches total at file top.

**PM caught team-lead Lock 14 5→7 dispatch drift** (Decision 18 verbatim "four per-domain tables" originally-committed; family stays at 5; V1.4 implements 2 of original 4 named members); Architect v2 INDEPENDENTLY caught same drift ~30 sec later. **2-teammate independent verification at brief-vs-canonical-ADR cross-check boundary** — composes `feedback_team_lead_sec_ratify_lock_cross_check` as 9th application track record + new boundary class extends to non-Sec-load-bearing surfaces (architectural housekeeping).

**Phase 4 Step 5 Wave 6 Gate E SECURITY annotation (PR #95 / 2026-06-03).** Sec Reviewer drafted + F/CTO ratified post-Wave-6 Sec PR. NOTE-level verdict (no veto, no flag). 4 surgical HTML edits to `docs/SECURITY/index.html`: new §4.4 paragraph naming Wave 6 Gate B Option C resolution; SD-10 row extends storage-surface to enumerate 4 named TEXT cols + ADR-013 INV-1 cross-ref; SD-12 row appends post-Wave-6 affirmation; §4.3 axis vi paragraph extension. Sec call: commentary 4 TEXT cols inherit **SD-10** storage class (user-authored free-text; HIGH tier; tenant-scoped; ADR-013 INV-1 plain-text-only security-load-bearing); SD-12 derivative-composition framework unchanged. **No new SD class; no new RT entry; no new §10 catalogued instance.**

**Phase 4 Step 9 — exit-criteria verification + phase close (PR #TBD / 2026-06-04).** PM-led exit-criteria walk + lessons-learned subsection; Architect-led §10 SD+RT coverage cross-check + Phase 5 detailed-steps draft; team-lead synthesis + ADR-018. Walk verdict: **6/6 criteria PASS** (Criterion 6 §10 SD+RT extension DISCHARGED per Architect verdict). Coverage tally: 21/21 active SD + 25/25 active RT covered; 0 hard gaps; 2 implicit gaps (SD-15 `fn_mask_acct_number()` helper + RT-15 parity-fixture test-environment RLS posture) routed to Phase 5 Step 4 by-construction closure. F/CTO ratified 2 gates at Phase 4 close:

- **Phase 4.5 (Agentic Flow Ramp) SKIPPED** — Phase 4 execution materially exercised the agentic loop; remaining fluency gaps surface in Phase 5+ production work, not synthetic practice. WORKFLOW.md Phase 4.5 section preserved as historical scaffold.
- **SELF-186 (B1 Apply migration `001_users_id_rename.sql`) ratified as V1.0 first-implementation-issue + Phase 5 close-gate exercise.** Architect-recommended; smallest end-to-end post-Wave-1-scaffolding + foundational unblock cascade + exercises Architect → Backend → Sec → DevOps → F/CTO loop.

**Phase 4 lessons-learned subsection added to WORKFLOW.md** (replaces `*To be added after phase exit.*` placeholder at v1.44 line 826). **12 durable patterns codified:** verbatim PRD-first decomposition discipline; PM/Architect cross-draft conflict resolution pattern (3 Waves); async dispatch-vs-delivery mismatch (5 instances); brief-vs-canonical-ADR cross-check new boundary class (NEW pattern Wave 5); ADR-017 mid-phase scheme shift going-forward; Settings shell 4/4 + Lock 14 family 5/5; three-attribute orthogonality discipline; one-question-at-a-time pacing; §10 attribution discipline 25+/31+ consecutive CLEAN surfaces; both V1 catalogued §10 instances complete; cross-Wave SELF-NN reference convention; 3-calendar-day pacing compression.

**Phase 5 (Workshop Setup) detailed-steps subsection added to WORKFLOW.md** (replaces `*To be fleshed out before phase entry.*` placeholder at v1.44 line 911). **9 numbered steps** mirror Phase 4 shape: pre-entry gates + team setup; build-time agent definitions (DevOps → Backend → Frontend → QA bootstrap order); Phase 0.5 agent definition refinements; CI test-fixture establishment + per-Wave RLS verification battery operationalization (closes SD-15 + RT-15 implicit gaps); per-directory CLAUDE.md files (`/supabase` + `/api` + `/web` + `/workers`); skills library initialization (incl. `milestone-rotation.md` per ADR-017 D2); Linear MCP setup verification + workspace configuration; pre-commit hooks + secrets management (CI/production secret-store non-overlap commitment); exit-criteria verification + phase close (V1.0 first-implementation-issue SELF-186 end-to-end smoke-test validates workshop).

**Phase 4 pacing reflection:** 3 calendar days = fastest phase-completion in mosko history. Phase 1 (PRD) ~3 weeks; Phase 2+3 ~5 days; Phase 4 ~3 days. Compression reflects (a) ADR-011 + ADR-013 + ADR-016 absorbing heavy architectural drilling that would otherwise surface at Phase 4 ratify; (b) `feedback_post_ratify_v1_cross_check` + verbatim-PRD-first disciplines preventing decomposition rework; (c) parallel PM/Architect dispatch with cross-draft conflict resolution as the synthesis-boundary mechanism. **Phase 5+ implication:** Phase 4's pacing model (parallel dispatch + cross-check disciplines + going-forward scheme refinement when needed) is replicable.

---

### v1.45 — 2026-06-03

**Phase 4 (Project Scoping) Steps 1–5 → ✅ COMPLETE; Phase 4 exit-gate ready.** All 5 Phase 4 steps closed across 10 PRs (#83–#92). Cumulative output: Linear MCP activated + "V1 launch" initiative + 22-label taxonomy + 7 Linear projects + 10 Linear milestones + **89 Linear V1 issues** (SELF-181 → SELF-269) spanning V1.0 / V1.1 / V1.2 / V1.3 / V1.4 + Platform / Cross-cutting V1.x; 26 of 32 PRD §2 user stories traced to ≥1 Linear issue (Waves 1+2+3+4+5; remaining 6 cover §2.6 monthly report at V1.5 Wave 6); Settings area ramp 3/4 occupants; Lock 14 family ramp 4/5 named tables.

**Phase 4 Step 1 entry-gates (PR #83 `phase/plan-4-step-1-entry-gates`).** PM ratify-pass on Candidate P3 (FMP/stock-screening incumbent-exceeds-V1) V1-default per [ADR-011](DECISIONS.md#adr-011) Decision 20 — verdict **CONFIRM**; PRD §2 grep verified zero V1 stories depend on stock-screening; `BACKLOG.md` §5.5 + §5.7 annotated. Plaid production-tier sales call queued as ISS-001 in `temp/phase-4-linear-shadow.md` (F/CTO-owned; shadow inventory migrates to Linear at Step 2). Team `phase-4-scoping` spawned per [ADR-003](DECISIONS.md#adr-003).

**Phase 4 Step 2 Linear MCP activation (PR #84 `phase/plan-4-step-2-linear-mcp`).** Linear MCP connection verified (1 team Mosko-Personal); "V1 launch" initiative created; **22-label taxonomy** at workspace scope across 4 color-coded categories (agent-role × 8 blue, milestone × 3 cyan, surface × 7 amber, discipline × 4 red). Phase 4 exit criterion 6 ("Linear MCP integration verified working") satisfied.

**Phase 4 Step 3 PRD § → 7-project decomposition (PR #85 `phase/plan-4-step-3-projects`).** F/CTO ratified PM-recommended 7-project shape (1:1 PRD §2 cluster mapping + Platform/Cross-cutting) over alternative 3-project collapsed shape. **7 Linear projects created** all parented to "V1 launch": Onboarding/Plaid/Manual entry (§2.4), Net worth (§2.1), Asset allocation (§2.2), Cash flow (§2.3), Estimated taxes (§2.5), Monthly report (§2.6), Platform/Cross-cutting (ARCH §3-§8).

**Phase 4 Step 4 milestone sequencing (PR #86 `phase/plan-4-step-4-milestones`).** F/CTO ratified 5-bucket V1.x shape (PM-recommended): V1.0 = Platform foundation + Onboarding minimal full §2.4 + Net Worth §2.1.1; V1.1 = Net Worth full (§2.1.2-§2.1.7); V1.2 = Asset Allocation; V1.3 = Cash Flow; V1.4 = Estimated Taxes; V1.5 = Monthly Report; V1.final = §3.4 (a)/(b)/(c) all-pass close per [docs/MILESTONE-FRAMING.md](docs/MILESTONE-FRAMING.md) §8.3 routing flag (d) handoff anchor SATISFIED. **10 native Linear milestones created across 7 projects**.

**Phase 4 Step 5 issue decomposition — wave-by-V1.X dispatch (Waves 1–5 / PRs #87–#92).** F/CTO ratified wave-by-V1.X bucket shape at Wave 1; PM + Architect parallel decomposition (PM = V1.X domain; Architect = Platform V1.x cross-cutting paired) at each Wave; team-lead synthesis + F/CTO ratify gates per Wave; one-session-granularity issues with Source / Acceptance criterion / Dependencies. **Brief-drift discipline emerged at Wave 2** (PM caught team-lead §2.1 paraphrase drift); CLEAN at Waves 3+4+5 (durable). **`feedback_team_lead_sec_ratify_lock_cross_check` 8-application track record** through Wave 5 (PM Wave 5 Lock 14 5→7 catch + Architect v2 independent Lock 14 catch = 2-teammate verification on dispatch drift, validates discipline extends beyond Sec-load-bearing surfaces to architectural housekeeping).

- **Wave 1 (V1.0 / PR #87).** 31 issues SELF-181→SELF-211 across 3 milestones (Platform/Cross-cutting V1.0 foundation = 15 Architect-authored; Onboarding/Plaid/Manual entry V1.0 = 14 PM-authored §2.4; Net worth V1.0 §2.1.1 = 2 PM-authored). F/CTO ratified Option A on §2.1.1 NAV V1.0 scope (GAV-Debt with placeholders for Realized + Unrealized; tax-liability compute deferred to V1.4). 21 V1-SHIP-BLOCK + 8 sec-joint-review. Close-gate SELF-209.
- **Wave 2 (V1.1 / PR #88).** 18 issues SELF-212→SELF-229 across 2 milestones (Platform V1.x cross-cutting = 5 Architect; Net worth V1.1 = 13 PM §2.1.2–§2.1.7). F/CTO ratified Option B (precomputed `pfin.nav_daily` checkpoint) for NW trend substrate one-way-door. ISS-001 migrated from shadow to SELF-212. 10 V1-SHIP-BLOCK + 3 sec-joint-review. Close-gate SELF-228.
- **Wave 3 (V1.2 / PR #90).** 15 issues SELF-230→SELF-244 across 2 milestones (Platform V1.x = 4 Architect; Asset allocation V1.2 = 11 PM §2.2). F/CTO ratified Option A (Architect single-table `user_taxonomy` per Decision 11 literal) over PM Option B (2-table normalized). CPI-U schema deferred-from-Wave-2 closed at SELF-230. Settings area shell SELF-242 first-of-four occupant ramped per ADR-013 P5. 9 V1-SHIP-BLOCK + 3 sec-joint-review. Close-gate SELF-244.
- **Wave 4 (V1.3 / PR #91).** 14 issues SELF-245→SELF-258 across 2 milestones (Platform V1.x = 3 Architect; Cash flow V1.3 = 11 PM §2.3). F/CTO Gate A ratified Option B internal-C (new `pfin.cashflow_target` table extending Lock 14 4→5 named tables) + Gate B ratified Option A (`is_tax_payment BOOLEAN` column). Lock 15 V1-SHIP-BLOCK first legitimate client-toggle application at SELF-247. Settings ramp 2/4 (SELF-252 cash-flow targets). 11 V1-SHIP-BLOCK + 4 sec-joint-review. Close-gate SELF-257.
- **Wave 5 (V1.4 / PR #92).** 11 issues SELF-259→SELF-269 across 2 milestones (Platform V1.x = 4 Architect; Estimated taxes V1.4 = 7 PM §2.5). F/CTO Gate A ratified Option B (Architect unified `fn_compute_tax_liability(p_data_as_of)` SECURITY INVOKER helper) over PM split shape — PM Issues 6+9 absorbed into SELF-262; rationale V1.5 monthly_report forward-compat via Lock 11 pattern reuse. F/CTO Gate B Option A (`tax_jurisdiction` enum column); Gate C NAV composition placeholder-flip confirmed (SELF-268 closes §2.5↔§2.1.1/§2.1.5 cross-section contract); Gate D §2.5 staleness deferred to V1.5. PM caught team-lead Lock 14 5→7 dispatch drift; Architect v2 independently caught same — 2-teammate verification at brief-vs-canonical-ADR cross-check boundary class (new instance). Settings ramp 3/4 (SELF-265 tax-brackets editor). Lock 14 family ramp 4/5 named tables (owner_identification remains for V1.5). 8 V1-SHIP-BLOCK + 4 sec-joint-review. Close-gate SELF-269.

**Disciplines preserved through Phase 4 Step 5.** §10 attribution streak extends through 23+ consecutive CLEAN surfaces (Architect pre-emptive cross-check at file top each Wave; catalogued numbered list stays at 2 RT-22 + RT-26 per Decision 4; Lock 14/15 user-facing-surface §10 instance annotations non-catalogued per ARCH §8.5 axis-orthogonality). Decision 3 cross-tenant FK-bypass family extended to 5 instances (Lock 9 + Lock 10 + Lock 11 + Lock 12 + Wave 5 SELF-259 + SELF-261). Brief-drift discipline CLEAN at 4 consecutive Waves (Waves 2–5). Architect protocol explicit F/CTO ratify on one-way-doors applied 4 times in Phase 4 Step 5 (Wave 2 NW trend substrate + Wave 3 user_taxonomy DDL + Wave 4 cashflow_target storage shape + Wave 5 tax-computation function shape).

**Convention changes ratified at v1.45 close — codified at [ADR-017](DECISIONS.md#adr-017).**

- **MILESTONES.md Recent activity** convention narrowed from "last 7 days verbose" to **last 5 entries, 1-sentence each, with `CHANGELOG.md` pointer for detail** — restores the compact-ledger auto-load principle of [ADR-009 Decision 6](DECISIONS.md#adr-009) (extraction pattern: detail lives in CHANGELOG; MILESTONES is the lightweight ledger pointer). Drifted into multi-paragraph density across Waves 1–4 entries; v1.45 closes the drift + rewrites Wave 1–5 Recent activity entries as 1-sentence pointers to this CHANGELOG entry.
- **Linear scope** narrowed from "≤200 hot" (ADR-009 Decision 7 feature-flow scheme) to **current milestone + next milestone only**; all other milestones held in `BACKLOG.md`. Applies going-forward from Wave 6 (V1.5) onward — Wave 6 issues will land in `BACKLOG.md` rather than Linear directly; promotion to Linear happens at milestone-rotation time. Existing V1.0–V1.4 issues already in Linear stay (no retroactive export); milestone rotation handles them as implementation begins at Phase 5. Honors the spirit of ADR-009 Decision 7's feature-flow scheme more strictly (`PRD → BACKLOG → Linear → Done → MILESTONES Completed`).

---

### v1.44 — 2026-06-02

**Joint Phase 2 (UX & Design) + Phase 3 (Technical Architecture) → ✅ COMPLETE; Phase 4 (Project Scoping) entered.** Per [ADR-012](DECISIONS.md#adr-012) joint-close pattern: Phase 3 exit-gate closed 2026-06-02 (row #7 Sec sign-off APPROVED + row #8 F/CTO sign-off APPROVED on ARCH v1.0); Phase 2 ready-to-close since 2026-05-29 (Steps 1–10 complete per ADR-013 / ADR-014 / ADR-015 trio). Both phases close together at Phase 4 entry gate; WORKFLOW.md header pointer advances to Phase 4. Meta-process **M1 (Plan / ARCH + SECURITY docs locked) → ✅ COMPLETE**; M2 (Implement + Verify) becomes Active at Phase 5 entry.

**PR `meta/phase-2-3-close` — joint-close consolidated update.** Single bundled close PR per [ADR-009](DECISIONS.md#adr-009) Decision 9 + `feedback_late_phase_density_overload` (scoped tight per the precedent set at Phase 1's stacked-PR decomposition — joint-close substance is lower density than Phase 1's 16-lock close-arc, so single PR is the right shape). Team-mode close-cycle in team `meta-phase-2-3-close` per [ADR-003](DECISIONS.md#adr-003): UX Designer + Visual Designer drafted Phase 2 lessons-learned (Visual's draft formally closed the "Visual Designer notification" criterion from MILESTONES line 27); Architect drafted Phase 3 lessons-learned; PM drafted Phase 4 detailed-steps subsection (just-in-time per `docs/handoff-prompts.md` phase-transition prompt step 2). Team-lead synthesized + drafted WORKFLOW.md current-phase header rewrite + CHANGELOG entry + MILESTONES.md Current Phase block flip.

**Post-v1.43 PR-arc recap (PR #74 / #76 / PR-A / PR-B / PR-C / PR #80 / PR #81 / PR #82).** Eight PRs landed between v1.43 (PR #72) and this close without per-PR CHANGELOG entries — bundled here per the Phase-1-close-arc precedent at v1.32 (stacked close PRs land as a single CHANGELOG entry with bullet-density recap):

- **PR #74** — ARCH §8 Trade-offs & Alternatives lands; §8.1–§8.6 sub-sections; verbatim-vs-paraphrase discipline self-catch at §8.5 four-layer paraphrase drift; Path B v2-fix shape (drop enumeration + let link carry) preferred when §-surface section-hint frames REFERENCES-not-ABSORBS; Sec-validated; §10 attribution 8th consecutive CLEAN surface. `feedback_team_lead_sec_ratify_lock_cross_check` 2nd-application strong-validation codified.

- **PR #76** — ARCH §9 Open Questions + §9.1 lands; section-hint convention 5th application at Phase-3-close meta-section territory (5-6 adjacent owners); track-record extensions only, no new memory codifications. §10 attribution 9th consecutive CLEAN surface.

- **PR-A** — cross-doc cleanup pass (per-row disposition); row #4 Path B applied in some surfaces, KEEP-at-canonical-anchor disposition introduced as third disposition for surfaces where §-surface IS canonical anchor AND numbered list IS substantive content-positioning territory; §10 attribution 10th consecutive CLEAN surface; Path B 4-application track record.

- **PR-B** — annotation pass; verbatim-quote completeness drift caught at boundary (dropped prepositional phrase from PR #66 v2-mod quote); team-lead Sec-Lock cross-check discipline 5th application; §10 attribution 11th consecutive CLEAN surface; Path B 5-application.

- **PR-C** — sweep pass; §10 attribution 12th consecutive CLEAN surface; Path B 6-application; section-hint 5-application durable across §-surfaces with adjacency lists ≥6.

- **PR #80** — row #7 Sec sign-off APPROVED via comprehensive audit covering 3 sub-surfaces (auth / RLS / secrets) + 6 cross-cutting (14 SD entries / 15 RT entries / 6 posture sub-§ / [ADR-008](DECISIONS.md#adr-008) composition / §10 CHANGELOG annotation / Sec-territory Locks 1/4/12/13/14/15); 1 advisory (b)1 SECURITY HTML TOC/header drift (deferred as housekeeping per F/CTO ratify); §10 attribution 13th consecutive CLEAN surface; team-lead Sec-Lock cross-check 7-application track record (+ row #7 audit (b)1 SECURITY TOC/header citation verification at lines 32/33/100/366).

- **PR #81** — `phase/plan-arch-mermaid-fix` Mermaid render saga close. F/CTO surfaced ARCH §3.1 + §3.2 sequenceDiagrams as not-rendering during row #8 ARCH v1.0 review via `/serve-docs` comment widget. **6-round whack-a-mole arc**: round-1 `<br/>` → `<br>` wrong direction; round-2 alias `<br>` flatten; round-3 aggressive alias simplification; round-4 `&#NN;` HTML-entity dead-end defeated by browser pre-decode; round-5 `#NN;` Mermaid-entity syntax (no `&` prefix) works; round-6 message-text shortening + `.gitignore docs/test-*.html`. F/CTO meta-feedback ("why do we keep making the same mistakes?") drove pivot to isolated `docs/test-mermaid.html` test-harness pattern at round-4; harness pinpointed exact constraint set in 2 iterations vs 3 prior rounds of guessing. **Full Mermaid sequenceDiagram constraint set discovered + codified** at new memory `feedback_mermaid_sequencediagram_constraints`: cascading failure across blocks; NO line breaks in messages; `"..."` wrap on special-char messages; `;` → `#59;` + `#` → `#35;` Mermaid entities (NO `&` prefix — defeats escape via browser pre-decode); short messages render better. Recovery discipline: isolated `docs/test-NAME.html` harness pattern (gitignored) instead of iterate-against-canonical-doc. **Browser-render-verification-at-drafting-time discipline** codified: PR #67 introduced defect latent for months; surfaced only at row #8 v1.0 review; future Mermaid PRs include browser-verify in test plan.

- **PR #82** — post-PR-81 cleanup: row #7 + row #8 ratifications committed to MILESTONES head + DECISIONS ADR-011 Decision 4 §10 CHANGELOG annotation + new memory entry codified.

**Phase 2 close substance.** Steps 1–10 complete per [ADR-013](DECISIONS.md#adr-013) (D1 + P1–P6) + [ADR-014](DECISIONS.md#adr-014) (Palette B refined + Inter+JetBrains Hybrid + Canary attn + dark plan-for + primitive→semantic token tiers) + [ADR-015](DECISIONS.md#adr-015) (SvelteKit + no Tailwind; tokens.css consumed natively via Svelte component-scoped CSS). Committed home established at [`docs/DESIGN/`](docs/DESIGN/) (design system + flows + wireframes migrated from `temp/`). Two-tier token taxonomy (`--color-*` primitives → `--c-*` semantic aliases) made the framework-coupling resolution at ADR-015 close-by-composition rather than requiring a transformation layer.

**Phase 3 close substance.** ARCH v1.0 HTML drafted across 16-PR arc (#60 system overview → #62 RT-26 fence → #63 ADR-015 framework lock → #65 §4 Tech Stack → #66 §4 Auth → #67 §3 Data Flow + sequenceDiagrams → #68 §4 Observability → #69 §5 Deployment → #71 §7 Integration Points → #72 §6 CI/CD → #74 §8 → #76 §9 → PR-A/B/C cross-doc cleanup → PR #80 row #7 Sec audit → PR #81 Mermaid render fix → PR #82 row #8 ratify cleanup). [ADR-015](DECISIONS.md#adr-015) (SvelteKit + no Tailwind) + [ADR-016](DECISIONS.md#adr-016) (RT-26 three-entry service_role allowlist enumeration) ratified during Phase 3. **Five durable project conventions emerged**: section-hint canonical-territory statement (5-application); post-ratify cross-check at v1 (Sec-2 commendation as project-pattern); conditional-lock + named-fallback (PR #68 / v1.40); Path B (drop enumeration; let link carry) with KEEP-at-canonical-anchor third disposition (PR-A row #4); §10 attribution discipline 14 consecutive CLEAN surfaces on full three-axis basis (instance-numbering / layer-attribution / V1-SHIP-BLOCK-axis orthogonality). **Team-lead Sec-Lock cross-check discipline 7-application track record** (+ row #7 audit) — 6 SUCCESS-cases : 1 boundary-failure-case (PR #72 Sec-vs-Sec dispute, the boundary-failure that mechanized the catch).

**Out-of-band Phase 4 entry-gate disposition.** Per ADR-011 Decision 20: (1) **Plaid production-tier monthly minimum sales call** — non-blocking for Phase 4 entry; carries as a Phase 4/5 F/CTO-driven task. (2) **Candidate P3 PM consult (FMP/stock-screening incumbent-exceeds-V1)** — original gate position was "BEFORE Phase 3 ARCH drafting touches `pfin_back_etl` ingestion"; Phase 3 closed without P3 disposition surfacing as load-bearing on ARCH content. **F/CTO-ratified at v1.44 joint-close: Option A path** — P3 consult folded into Phase 4 entry step 1 as explicit PM ratify-pass on the [ADR-011](DECISIONS.md#adr-011) Decision 20 V1-default ("ingest + no UI") disposition; closes the gate cleanly with BACKLOG.md confirmed-V2+ entry as the durable artifact.

**WORKFLOW.md edits.** Current-phase header (line 6) rewrite — Phase 2 + Phase 3 (parallel) → Phase 4 (Project Scoping). Phase 2 Status flip 🟡 In progress → ✅ Complete (2026-06-02). Phase 3 Status flip 🟡 In progress → ✅ Complete (2026-06-02). Phase 4 Status flip ⏳ Not started → 🟡 In progress (2026-06-02). Phase 2 Lessons-learned subsection drafted (UX + Visual contributions). Phase 3 Lessons-learned subsection drafted (Architect contribution, mirroring Phase 1 Step 4 shape per `feedback_late_phase_density_overload` — dense bolded-header bullets covering durable conventions / failures / changes for Phase 4+). Phase 4 Detailed-steps subsection fleshed out (PM-led; 9 steps covering entry gates + Linear setup + PRD→projects mapping + milestone sequencing + issue decomposition + ARCH §10 SD+RT mapping + Sec joint-review triggers + exit verification). Footer version bump v1.41 → v1.44.

**MILESTONES.md edits.** Current Phase block rewrite — Phase 2 + Phase 3 → Phase 4. Active Feature block rewrite. Recent activity entry for the joint close. Last updated 2026-06-02.

**CHANGELOG.md edits.** This v1.44 entry; preamble version count 49 → 50.

**No new ADRs in this PR.** Joint-close pattern already codified at [ADR-012](DECISIONS.md#adr-012); no new architectural decisions surfaced during close-work.

**Memory entries this session.** None pending — all candidate codifications from the Phase 3 close-arc landed pre-close (PR #72 batch + PR #74 batch + PR #81 Mermaid memory).

**Team `meta-phase-2-3-close` teardown.** `TeamDelete meta-phase-2-3-close` after PR merge. Any Phase 4 work spawns a new team per [ADR-003](DECISIONS.md#adr-003).

**Phase 4 entry posture.** PM owns Phase 4. Initial work activates Linear MCP + creates the "V1 launch" initiative. First downstream milestone — first Linear-tracked work surface for mosko-fintech (no individual Linear-feature granularity before Phase 4 per ADR-009 Decision 7).

---

### v1.43 — 2026-05-31

**ARCH §6 CI/CD Pipeline lands — substantive first-time content (Hybrid scope-shape: 5-row stages table + §6.1 Sec-test catalog mapping subsection); GitHub Actions CI + Coolify auto-deploy hybrid; RT-22 PR-review→CI-automation transition; TenantBoundConnection V1-SHIP-BLOCK surface at CI per Lock 13 mod #3 verbatim; golden-test fixture obligations on three CI fence scripts; 4 Coolify auto-deploy posture commitments inline; section-hint canonical-territory statement convention (v1.41) third application — strong durability evidence; §10 attribution discipline holding for 7th consecutive surface; V1-SHIP-BLOCK-axis orthogonal to §10-catalogued-instance-axis distinction codified; same-PR SECURITY §4.5 RT-22 row sub-edit; Sec-vs-Sec dispute discipline catch (Sec original misread Lock 13 mod #3 V1-SHIP-BLOCK status; Sec-2 parallel review caught the error pre-v2).**

Phase 3 ARCH HTML drafting; team `phase-3-arch-tech-stack` (Architect lead + Sec mandatory joint-review). §6 was 6-row template scaffolding (Lint/Test/Build/Sec-scan/Deploy-staging/Deploy-prod, all TBD) with template-residual "Owned by `devops-engineer`" + obsolete-by-V1-scope staging row. F/CTO chose §6 over §8/§9 (meta-sections; less time-sensitive) and pause+teardown — §6 has strongest natural pull because multiple already-locked surfaces compose at §6 (RT-26 grep fence enforcement-mechanism + RT-22 Dockerfile audit + ADR-016 allowlist data-input + RT-21 audit-log + RT-02/RT-05 critical-severity test gates).

**Scope-shape disposition arc.** Architect proposed 3 options ((a) minimum 5-row table / (b) full subsection expansion with §6.1 stages + §6.2 Sec-test catalog + §6.3 deploy + §6.4 secret injection / (c) hybrid — 5-row stages table + §6.1 Sec-test catalog mapping subsection). Architect-leaned (c). **F/CTO ratified (c) Hybrid** + 4 downstream sub-decisions one-at-a-time per `feedback_one_question_at_a_time`: section-hint canonical-territory statement convention APPLY (third application; 9 adjacent owners — strongest territorial-overlap case yet); staging-row DROP with V2-trajectory ramp note (V1 production-only per §5 / Lock 16); §6.1 catalog scope LOAD-BEARING SUBSET (~10–12 tests: 4 V1-SHIP-BLOCK + 8 CI-mechanism-distinct); RT-22 PR-review→CI-automation TRANSITION (machine-grade enforcement front-line; human PR-review second-line). Plus async-arrived amendment ratify: CI tool family (i) GitHub Actions CI + Coolify auto-deploy hybrid (Architect sub-lean; ratified at scope-shape time).

**Architect v1** (`temp/arch-6-cicd-draft.md`, ~160 lines) with pre-emptive §10 attribution-drift cross-check at top of file (7th consecutive surface) + explicit guard against `TenantBoundConnection`-grep-fence-as-third-catalogued-§10-instance drift. Section-hint canonical-territory statement names §6's axis (CI/CD enforcement-mechanism + deployment-gate orchestration) + 9 adjacent owners + references-not-absorbs posture. §6 5-row stages table (Lint / Test / Build / Security scan / Deploy → prod with staging dropped) + §6.1 catalog mapping subsection with 12 tests (4 V1-SHIP-BLOCK + 8 CI-mechanism-distinct) + Phase 5 detail-design items (a)–(g) with Sec-consult-mandatory annotations. Post-ratify-dispatch cross-check at v1 caught 2 surgical mismatches against F/CTO verbatim (9-owner list + RT-22 rationale phrase) and patched in-place before SendMessage — **Sec-2 commendation: "worth durably codifying as a project pattern" (post-ratify cross-check at v1 file before SendMessage).**

**Sec-vs-Sec dispute discipline catch.** Sec (original teammate from prior PR cycle still alive) and Sec-2 (newly-spawned teammate I dispatched in parallel — `sec` name was reserved, system auto-suffixed) BOTH produced §6 joint-review packages with materially conflicting load-bearing findings. Sec (2/5/2) drew a distinction between Lock-V1-SHIP-BLOCK and ADR-008-catalog-formal-V1-SHIP-BLOCK for TenantBoundConnection that isn't load-bearing — **misread Lock 13 mod #3 verbatim** (DECISIONS.md line 435: *"V1-SHIP-BLOCK `TenantBoundConnection`-only CI fence (compile-time complement to runtime SQL-log assertion)"* — V1-SHIP-BLOCK status is the Lock's own commitment, not derivative of ADR-008-catalog-row presence). Sec-2 (3/5/3) caught the error + corrected: TenantBoundConnection IS V1-SHIP-BLOCK per Lock 13 mod #3; §6 surfaces existing obligation, not elevation. F/CTO ratified Sec (2/5/2) initially (team-lead boundary failure: I should have cross-checked Sec's framing against Lock 13 mod #3 wording at ratify time). After Sec-2's parallel review arrived + team-lead surfaced the conflict + verified Lock 13 mod #3 wording, F/CTO supersession-ratified Sec-2's (3/5/3) full package. Architect's blocker-pause ("request Sec verbatim before drafting v2" per `feedback_subagent_relay_format` + `feedback_decision_4_instance_ledger_cross_check` discipline) prevented v2 from being drafted against the wrong Sec package — **discipline catching its own drift at the boundary**.

**Sec-2 (3/5/3) load-bearing findings.** **(a)1 TenantBoundConnection V1-SHIP-BLOCK per Lock 13 mod #3 verbatim** — §6.1 V1-SHIP-BLOCK column flips `No (...)` → `YES per Lock 13 mod #3`; V1-SHIP-BLOCK axis orthogonal to §10 catalogued-instance axis. **(a)2 Golden-test fixtures for CI fence scripts** — RT-26 + TenantBoundConnection + RT-22 CI fence scripts MUST ship with paired negative-test fixtures at Phase 5 implementation lock to fence fail-open silent regression; Phase 5 items (c) + (d) + (e) receive fixture sub-additions; Sec-consult-mandatory at each fence-script + fixture lock + every subsequent change. **(a)3 Coolify auto-deploy webhook 4 posture commitments + Sec-consult-mandatory** — Phase 5 item (f) replaced with verbatim: (i) Coolify-watches-main-only; (ii) GitHub branch protection admin-bypass restricted/disabled; (iii) webhook URL is a secret (production secret-store); (iv) auto-deploy permission boundaries documented per ADR-002 §6.0. Sec-2 (b)1–(b)5 endorsements + (c)1 RT-22 verbatim phrase drift fix ("the" drop at line 53) + (c)2 SECURITY §4.5 RT-22 row sub-edit + (c)3 §6.1 V1-SHIP-BLOCK column flip.

**Three durability wins.** §10 attribution CLEAN 7th consecutive surface (PR #65 → §6) — strongest §10-drift-temptation surface yet (§6 is where ALL §10 fences execute); explicit guard against TenantBoundConnection-as-third-catalogued-§10-instance held in body verification; Decision 4 numbered list stays 2-instance. Section-hint canonical-territory statement convention (v1.41) — **STRONG DURABILITY EVIDENCE at 3rd application**; body verification clean across all 9 absorption-pressure surfaces; **Sec-2 recommends ratifying as durable project-convention** (F/CTO codification decision post-PR). Post-ratify cross-check at v1 file caught 2 surgical mismatches before SendMessage (Sec-2 commendation as candidate memory codification).

**Verbatim discipline track-record this PR.** Three distinct verbatim-discipline catches: (1) Architect's blocker-pause requesting Sec verbatim before v2 (prevented wrong-Sec v2 from being drafted on first cycle); (2) Team-lead's cross-check of Architect's v2 sign-off vs Sec-2 package (caught wrong-Sec v2 application post-async-crossover; required REDO); (3) Architect's post-ratify cross-check at v1 file (caught 2 surgical mismatches before SendMessage). The PR exercises the verbatim-discipline meta-pattern multiple times; all catches happened pre-apply, preserving the 7-consecutive-surface §10 CLEAN streak. Episode reinforces `feedback_subagent_relay_format` + `feedback_decision_4_instance_ledger_cross_check` as load-bearing project disciplines.

**V1-SHIP-BLOCK axis orthogonal to §10 catalogued-instance axis** — convention-significant distinction codified at v2 §10 cross-check. V1-SHIP-BLOCK status is locked per individual mod ratify (e.g., Lock 13 mod #3 for TenantBoundConnection; ADR-008 catalog for RT-02 + RT-05 + RT-21 + RT-26); §10 catalogued-instance status is locked per Decision 4 numbered list (RT-22 first + RT-26 second). The two axes are independent: TenantBoundConnection IS V1-SHIP-BLOCK AND is NOT a catalogued §10 instance. Reading either axis as derivative of the other is drift.

**Architect v2 + same-PR application** (`temp/arch-6-cicd-draft-v2.md` ~205 LOC against Sec-2 verbatim). Team-lead applied v2 to `docs/ARCH/index.html` §6 (replaces template scaffolding at lines 481–495) + (c)2 SECURITY §4.5 RT-22 row sub-edit (CI-automation front-line + Phase 6 PR-review second-line + golden-test fixture cross-reference). **No new ADR required; no SECURITY §4.2 new bullet** (Sec-2's package corrects via the V1-SHIP-BLOCK axis distinction). Cleanest PR shape since §5.

**Pattern observations.** Section-hint canonical-territory statement convention (v1.41) durability validated at third application — convention codification ratification decision pending post-PR per Sec-2 recommendation. CI tool family (i) GitHub Actions + Coolify auto-deploy hybrid composes with `pfin_back_etl` incumbent pattern + ecosystem-rich tooling + AI-coding-agent fluency. Sec-vs-Sec dispute episode validates the verbatim-discipline at multiple boundaries; team-lead-side cross-check of Sec findings against Lock wording at ratify boundary is a candidate memory codification alongside the post-ratify-cross-check pattern Sec-2 flagged. PR shape demonstrates clean composition without ADR-016 + Decision 4 ledger amendment (V1-SHIP-BLOCK axis orthogonality discipline preserved by-construction).

---

### v1.42 — 2026-05-31

**ARCH §7 Integration Points lands — substantive first-time content (Plaid subsection + 4-service table); ADR-016 enumerates the three-entry RT-26 service_role allowlist surface composition; same-PR SECURITY §4.2 webhook-allowlist annotation bullet expansion + ARCH §4.1 cohesion update; section-hint canonical-territory statement convention (v1.41) WORKS at second application at the strongest-overlap surface yet (5 owners + 1 ADR); §10 attribution discipline holding for 6th consecutive surface; verbatim-vs-paraphrase episode self-caught at Architect v2 with redo against Sec verbatim wording.**

Phase 3 ARCH HTML drafting; team `phase-3-arch-tech-stack` (Architect lead + Sec mandatory joint-review). §7 was template scaffolding (1-row Plaid table only) requiring substantive first-time content; F/CTO chose §7 over §6/§8/§9 because §5 (PR #69) forward-pointed to §7 for endpoint posture and the streak benefits from closing that obligation immediately.

**Scope-shape disposition arc.** Architect proposed 3 options ((a) minimum single-table ~30–50 LOC / (b) full per-service subsections ~150–220 LOC / (c) hybrid — Plaid subsection + table for BLS/FMP/Discord ~80–130 LOC). Architect-leaned (c); rationale: matches delivery-shape to surface complexity — Plaid's 7+ endpoints with materially different per-endpoint posture (rate-limit per Plaid product; retry semantics differ across scheduled-poll vs webhook vs on-demand vs Link; idempotency only on writes) needs subsection space + room to absorb App B (h) credential-error-state mapping + (7.2)(a) two-product throughput discussion at the canonical home; BLS/FMP/Discord have row-shaped posture (single endpoint; no idempotency; no §10 interplay) and would inflate without signal as subsections. **F/CTO ratified (c) Hybrid** + 3 downstream sub-decisions one-at-a-time per `feedback_one_question_at_a_time`: section-hint canonical-territory statement convention (v1.41) APPLY (strongest-overlap-case-yet pitch — 5 adjacent canonical owners with territorial overlap: §3.1 / §4 Auth+Ingestion+Observability / §4.1 RT-26 allowlist / §5 topology / ADR-002 §6.0 secrets); App B absorption all 3 as proposed (§2.4 (h) + §7.2 (a) + partial §2.4 (a) — algorithm choice defers to §8); `/item/remove` novel endpoint enumeration INCLUDE (anchors SD-03 `bounded-Item-active-only` retention commitment to a concrete consumed endpoint).

**Architect v1** (`temp/arch-7-integration-points-draft.md`, ~210 lines) with pre-emptive §10 attribution-drift cross-check at top of file (6th consecutive surface; broadened-memory + v1.40 convergence-outcome pattern). Section-hint canonical-territory statement (line 32) names §7's axis (per-endpoint behavioral contract at the V1 integration boundary) + 5 adjacent canonical owners + explicit `/internal/pdf-render` exclusion. §7 endpoint posture 4-row table covers Plaid (defers to §7.1) / BLS CPI-U / FMP / Discord with 6 columns (Service / Direction / Auth shape / Limits + retry / Failure mode / Observability + audit hook). §7.1 Plaid subsection: 6 paragraphs covering endpoint enumeration (7 outbound + 1 inbound, including `/item/remove` novel addition) + Auth shape (two-tier; SD-03 + Lock 4 mod #1 pgsodium decrypt-view permission anchor) + Rate-limit + throughput posture (absorbs App B §7.2 (a)) + Retry + idempotency posture + Failure-mode posture (4-class credential-error-state mapping table absorbing App B §2.4 (h)) + Observability hooks. App B forward-pointer disposition footnote at bottom (2 absorbed + 1 partial + 2 referenced-only). 5 open questions called out for Sec joint-review.

**Sec joint-review returned 11 findings** (Task #3) categorized (a) load-bearing × 3 / (b) advisory × 5 / (c) SECURITY sub-edit candidate × 1. Two durability wins flagged at top: (1) **§10 attribution cross-check CLEAN — 6th consecutive surface** (PR #65 → #71); Decision 4 canonical structure preserved at §7; no new §10 instance catalogued; cross-references only. (2) **Section-hint canonical-territory statement convention (v1.41) WORKS at second application** — body verification confirmed no neighbor-content absorption across 210 LOC; convention is delivering as designed at the strongest-overlap surface yet (5 owners + 1 ADR). Strong durability evidence for F/CTO's watch.

**Load-bearing catches.** **(a)1 §4.1 RT-26 allowlist composition needs explicit ADR amendment same-PR** — V1 draft introduces TWO new allowlist entries (`/item/public_token/exchange` + `/item/remove`) beyond the canonical first (Plaid webhook handler); SECURITY §4.2 webhook-allowlist annotation convention verbatim: *"allowlist additions require Sec-consult + ADR amendment at the surface-introducing lock."* The §7 lock IS the surface-introducing lock. Two paths: (α) both endpoints land as allowlist entries + ADR amendment + SECURITY sub-edit; (β) endpoint 3 reclassified — but reclassification still requires service_role for `vault.decrypted_plaid_access_token` per Lock 4 mod #1 so both endpoints belong on the allowlist regardless. Sec ruling: path (α). **(a)2 `/item/public_token/exchange` tier posture** — service_role on the write path; rationale: SD-03 credential-class admission surface inherits SECURITY §4.2 *"categorically stricter than financial-data classes"* posture + Lock 4 mod #1 Vault key access. Verbatim v2 wording supplied. **(a)3 4-class state-mapping discriminator TBD-at-Phase-5 acceptable ONLY with explicit Sec-fallback binding** — V1-ship-block at Phase 5 if Plaid error-code taxonomy doesn't distinguish institution-side-grant-revoked + user-side-grant-revoked sub-classes; Sec-fallback escape paths: Sec-joint-collapse to 3-class V1 model with Sec sign-off, or deferred-discriminator-via-user-flow surface. Verbatim new paragraph supplied.

**Advisory + sub-edit.** (b)1–(b)5 precision/clarity edits with verbatim wording (endpoint 2 storage-name conflation correction; endpoint 8 `/item/get` dual-path rationale; Phase 5 detail-design items explicit Sec-consult-mandatory annotation; endpoint 9 SERIALIZABLE-transaction reference correction; §10 cross-check meta-statement correction). (c)1 SECURITY §4.2 webhook-allowlist annotation bullet expansion (Sec verbatim wording for the canonical second + third allowlist entry naming; ARCH↔SECURITY cohesion at landing).

**F/CTO ratified Sec's full package + same-PR ADR amendment** (path α). Subsequent ADR-shape ratify (one-question-at-a-time per memory): (β) new short ADR-016 vs (α) amend ADR-011 Decision 4. Architect's pre-lean: (β) new ADR-016. Rationale: Decision 4 catalogues §10 *instances* (RT-22 first / RT-26 second); RT-26 allowlist expansion is *internal-to-RT-26* surface enumeration NOT a new §10 instance; keeping Decision 4 as catalogued-§10-instance ledger preserves the discipline that's now CLEAN for 6 consecutive surfaces. **F/CTO ratified (β) new ADR-016.**

**Verbatim-vs-paraphrase episode (process discipline self-catch).** Architect's first v2 paraphrased Sec mods via team-lead's summary instead of the verbatim — exactly the failure mode `feedback_subagent_relay_format` + `feedback_decision_4_instance_ledger_cross_check` warn against, especially load-bearing in §10 territory. Architect self-flagged the paraphrasing failure mode in their second v2 message: *"Won't paraphrase Sec load-bearing wording again."* Team-lead forwarded Sec's full joint-review output verbatim; Architect redid v2 against Sec's actual wording — v2 came out leaner (-20 LOC vs paraphrased v2) because Sec's wording is intentionally tighter. Architect's first v2 also misread F/CTO's "F/CTO ratified path (α)" as ADR-shape ratify when it was actually Sec's (a)1 same-PR-timing path ratify; Architect self-diagnosed the reversal-reversal arc in their second v2 message (pre-lean (β) → paraphrased v2's (α) → F/CTO restored (β)). The 6-consecutive-surface §10 CLEAN streak survives because of this kind of self-catch + redo against verbatim.

**Architect v2 + ADR-016 deliverables** (`temp/arch-7-integration-points-draft-v2.md` ~225 LOC; `temp/arch-7-adr-016-draft.md` ~135 LOC). v2 applies all 3 load-bearing + 5 advisory Sec mods verbatim with **(Sec verbatim ...)** annotations inline. ADR-016 uses consolidation pattern (matches ADR-013/014/015 precedent): Date / Status / Phase / Context / Decision 1 (three-surface enumeration) / Decision 2 (webhook-allowlist annotation convention durable ratification) / Rationale (three rationale paragraphs incl. why-§10-ledger-stays-unchanged) / Alternatives (α / γ / δ all rejected with reasons) / Cross-references / Consequences / Approved by. **Critical §10 discipline guard at top of ADR-016 file:** explicit verification that Decision 4 catalogued §10 ledger UNCHANGED + no "first §10 instance" / "second §10 instance" / "JWT-shape-layer" / "infrastructure-credential-presence-layer" phrases appear in ADR-016 body; those stay in their canonical homes.

**Team-lead applied** v2 to `docs/ARCH/index.html` lines 497–512 (replaces template scaffolding) + (c)1 sub-edit to `docs/SECURITY/index.html` SECURITY §4.2 webhook-allowlist annotation bullet (Sec verbatim wording; ARCH↔SECURITY cross-reference cohesion at landing) + §4.1 cohesion update at `src/routes/**/+server.ts` row naming the three allowlist entries with ADR-016 anchor + ADR-016 inserted in `DECISIONS.md` after the format-doc separator (newest-at-top convention). Branch: `phase/plan-arch-7-integration-points`. PR: #71.

**Pattern observations.** Section-hint canonical-territory statement convention (v1.41) durability validated at second application — was codified mid-session per F/CTO ratify with single-application + Sec-validation + structural-elegance evidence; second application at §7 confirms the convention works as designed at the strongest-overlap surface (5 owners + 1 ADR) without body-drift. §10 attribution discipline 6th consecutive surface CLEAN demonstrates durability across substantial surface category variation (Tech Stack rows + flow diagrams + Auth + Observability rows + topology + endpoint-behavioral-contract). Conditional-lock + named-fallback (v1.40) convention not invoked at §7 (no new conditional-lock surfaces — all §7 endpoints are committed-incumbent); first cross-PR composition test from PR #69 (Discord topology cite) remains the validation reference. Verbatim-vs-paraphrase Architect self-catch validates the discipline that prior PRs depended on (the 6-consecutive-surface §10 CLEAN streak would have been broken at PR #71 if Architect had landed the paraphrased v2 with misinterpreted (α) ADR-shape; the redo against verbatim restored the streak).

---

### v1.41 — 2026-05-31

**ARCH §5 Deployment Topology lands — substantive first-time content; F1 operational/admin trust boundaries paragraph addition; F2 inter-container network isolation Phase 5 forward-pointer; canonical-territory-respect section-hint pattern flagged as candidate new project convention; v1.40 conditional-lock pattern first cross-PR composition test PASSES; §10 attribution discipline holding for 5th consecutive surface.**

Phase 3 ARCH HTML drafting; team `phase-3-arch-tech-stack` (Architect lead + Sec mandatory joint-review). §5 was essentially untouched template scaffolding (Vercel CDN reference wrong — Coolify per ADR-002 §6.0; generic prod/staging/dev over-spec'd for V1 single-user scale) requiring substantive first-time content, not refresh as initially framed by team-lead.

**Scope-shape disposition arc.** Architect proposed 3 options ((a) minimum-viable rewrite ~25-30 lines / (b) substantive expansion with 5 sub-sections ~250+ lines / (c) hybrid — substantive prose + 1 Mermaid + NO sub-section unless forward-pointer obligation surfaces ~150 lines) with **novel architectural argument** distinguishing (c): *"respect canonical-section discipline"* — §5 owns topology axis; §7 owns endpoint-specific posture detail; ADR-002 §6.0 owns secrets discipline; §5 references rather than absorbs. Architect-leaned (c). **F/CTO ratified (c) Hybrid** plus 2 sub-questions in same ratify (§7 territory deferral confirmed; Phase 5 deferrals staging-env + network topology detail acceptable).

**Architect v1** (`temp/arch-5-deployment-topology-draft.md`, ~170 lines) with substantive content covering 6 surfaces: (1) Environment story (V1 prod-only on cax21 per Lock 16); (2) Container topology (3 Coolify containers + Supabase node per Lock 13); (3) 7-boundary application-data-path trust topology (browser↔web-app TLS+SBAuth / web-app↔Supabase tier-discipline / web-app↔Plaid RT-05+idempotency / web-app↔PDF-worker RT-21+RT-22 / pfin_back_etl↔Supabase TenantBoundConnection / pfin_back_etl↔Plaid+BLS+FMP / web-app↔Discord conditional-lock); (4) External integration endpoints with §7 deferral; (5) Per-container credentials surface with ADR-002 §6.0 cross-ref; (6) Coolify→Discord notification routing topology per PR #68 conditional-lock + named-fallback convention. Plus 1 comprehensive Mermaid (cax21 host outer subgraph + 3 application container subgraphs + Coolify control plane + Supabase node + 4 external endpoints + trust-boundary arrow annotations). Plus pre-emptive §10 attribution-drift cross-check at top of doc (5th consecutive surface applying broadened-memory + v1.40 convergence-outcome pattern).

**Sec joint-review returned 11 findings** (Task #14) categorized:

- **(a) Load-bearing × 1** — **F1 operational/admin trust boundaries omitted** from 7-boundary enumeration. Architect's draft covers application-data-path topology but omits 3 operational/admin boundaries squarely in §5's scope per section-hint: (i) **F/CTO ↔ Coolify control plane admin surface** — Coolify is bootstrapping trust root for V1 deployment (admin compromise = topology compromise + cross-container env-var access + container lifecycle control); (ii) **F/CTO ↔ cax21 host SSH** — load-bearing under Shape C fallback path per PR #68 (F/CTO reads flat-file notifications via SSH); (iii) **Coolify ↔ container Docker socket** — privilege-escalation boundary (root-equivalent host access). **Severity nuance:** load-bearing for §5 ratify; **NOT V1-SHIP-BLOCK on V1 ship** (F/CTO operational discipline mitigates realistic risk — single-admin F/CTO + cax21 IP + Coolify admin URL + brute-forcing auth = low realistic adversary surface; compromise impact catastrophic so boundary acknowledgment is non-negotiable Sec hygiene). Sec proposed verbatim paragraph with V1 posture commitment ("F/CTO operational discipline — strong admin auth + passphrase-protected SSH key") + Phase 5 mechanism deferrals + V2 multi-admin Sec-consult trigger per [ADR-008](DECISIONS.md#adr-008) Decision 4.

- **(b) Advisory × 9** — F2 inter-container network isolation Phase 5 forward-pointer recommended (Coolify default Docker networking allows container-to-container access; RT-22 credential-absence fence holds independently as barrier between PDF worker and Supabase node; defense-in-depth evaluation Phase 5: leave default OR configure explicit network isolation) / F3 process observation on Architect pre-emptive cross-check accuracy (paragraph 3 DOES contain canonical-correct RT-22 Nth-claim; substance clean; self-audit accuracy improvement for future drafts) / F4 Mermaid annotation accuracy CLEAN (12 annotations verified) / **F5 section-hint upfront canonical-territory statement — Sec-grade new pattern candidate convention** for future surfaces with territorial-overlap concerns / **F6 v1.40 conditional-lock pattern's first cross-PR composition test PASSES** (PR #68 introduced; PR #69 invokes for Coolify→Discord topology with PR #68 cross-ref + Shape C fallback + F1 Phase 5 verification cite; convention durability validated) / F7 audit-log implicit at supa Mermaid node acceptable (DB-resident `pfin.plaid_sync_audit` doesn't need re-enumeration in §5 topology-axis view) / F8 existing Phase 5 deferrals (staging-env + network topology detail) Sec-grade / F9 §5.X sub-section NO confirms Architect lean (no forward-pointer obligation surfaced) / **F10 §10 attribution discipline CLEAN — 5th consecutive surface** (Tech Stack rows + flow diagrams + operational rows + topology cross-cutting; both dimensions instance-numbering + layer-attribution holding; convergence-outcome pattern from v1.39 codification demonstrably durable across surface category variation).

- **(c) Sub-edit candidates × 1** — F11 `#sec-7` anchor verification: **Sec pre-emptively verified resolved** at ARCH line 444; no team-lead Task #15 work needed.

**F/CTO ratified Sec's recommendation** (F1 load-bearing + F2 advisory same-PR). Architect v2 (`temp/arch-5-deployment-topology-draft-v2.md`, ~172 lines) applied both verbatim. Architect placement call on F1: **(b) separate paragraph between paragraphs 3 and 4** (Sec accepted both placements — (a) 8th boundary in paragraph 3 OR (b) separate paragraph). Architect rationale: (1) Sec's verbatim opens with bridge sentence "The 7 boundaries above cover application-data-path topology; operational/admin boundaries are acknowledged here..." that self-justifies separation; (2) F1's multi-sub-item (i/ii/iii) + V1 posture commitment + Phase 5 deferral + V2 trigger structure doesn't fit paragraph 3's single-line-bolded `Browser ↔ X:` shape; (3) reader scan-ability — separate paragraph signals "axis change" from data-path to operational/admin; (4) items-count mismatch (paragraph 3 has 7 boundaries; F1 has 5 logical units). F2 placement: trivially mechanical as Phase 5 item (iii).

**Team-lead applied v2 to `docs/ARCH/index.html` §5** — replaces lines 411-425 with section-hint + 7 paragraphs + Mermaid + Phase 5 closing paragraph. **No SECURITY sub-edits this PR** (F11 already-resolved at ARCH line 444 per Sec pre-emptive verification).

**Pattern observations (Sec-flagged for post-PR memory work):**

- **F5 — Section-hint canonical-territory statement as candidate new project convention.** Three short clauses (§5 owns X / §7 owns Y / ADR-002 §6.0 owns Z) serve reader orientation + Architect self-discipline + Sec discipline simultaneously. Sec sees this as a candidate convention for future surfaces with similar territorial-overlap concerns (e.g., §6 CI/CD if it lands with §4 Tech Stack overlap; §8 Trade-offs if it lands with §1 Context overlap). Post-PR memory candidate: `feedback_section_hint_canonical_territory_statement` (analogous in shape to `feedback_conditional_lock_with_named_fallback` v1.40 codification).
- **F6 — v1.40 conditional-lock pattern's first cross-PR composition test PASSES.** PR #68 introduced the pattern (`feedback_conditional_lock_with_named_fallback`); this PR invokes it cleanly for Coolify→Discord notification topology with PR #68 cross-ref + named Shape C fallback + F1 Phase 5 verification cite + §4 Observability row full framing reference. Pattern composes across surface category — durability validated.
- **F10 — §10 attribution discipline 5th consecutive surface CLEAN.** Pattern now durable across full surface category variation: PR #65 §4 + §4.1 (instance numbering — Sec catch) → PR #66 Auth row (layer attribution — Sec catch) → PR #67 §3 / §3.1 / §3.2 (Architect pre-emptive self-audit CLEAN) → PR #68 Observability row (Architect pre-emptive CLEAN; deliberately stays out of §10 territory) → **this PR §5** (Architect pre-emptive CLEAN substantive content; minor self-audit accuracy noted at F3). Convergence-outcome codification in `feedback_decision_4_instance_ledger_cross_check` v1.39 working as intended.

**PR `phase/plan-arch-5-topology-refresh` edit inventory:**

- `docs/ARCH/index.html` §5 (replaces lines 411-425 wholesale) — section-hint with canonical-territory statement + 7 substantive paragraphs (environment / container topology / 7-boundary trust topology / **NEW operational/admin trust boundaries per F1** / external integration endpoints with §7 deferral / per-container credentials surface / Coolify→Discord notification routing topology per PR #68) + 1 comprehensive Mermaid (cax21 host outer subgraph + 3 application container subgraphs + Coolify control plane + Supabase node + 4 external endpoints + trust-boundary arrow annotations) + Phase 5 detail design closing paragraph with 3 items (staging-env ramp + network topology detail + **NEW inter-container network isolation per F2**).
- `MILESTONES.md` — Last-updated refresh; new Recent-activity entry covering §5 lands + scope-shape arc + Sec 11-findings disposition + Architect v2 placement calls + pattern observations.
- `WORKFLOW.md` — line 6 in-flight Phase 3 PRs list extended (adds `phase/plan-arch-5-topology-refresh`); footer v1.40 → v1.41.
- `CHANGELOG.md` — this v1.41 entry; header version count 46 → 47.

**Follow-up:**

- **Post-PR memory:** `feedback_section_hint_canonical_territory_statement` durable anchor for the F5 pattern observation (analogous to `feedback_conditional_lock_with_named_fallback` v1.40 codification). Team-lead lands post-merge.
- **Phase 5 detail design tasks accumulating from §5:** (i) staging-environment ramp at V2 onboarding; (ii) network topology detail (port allocations / reverse-proxy / TLS termination); (iii) inter-container network isolation evaluation (RT-22 sole barrier vs explicit network isolation defense-in-depth); operational/admin auth mechanism (Coolify defaults vs custom hardening + SSH key/passphrase posture + Coolify privileged-mode posture).
- **Remaining ARCH §s** — §6 CI/CD + §7 Integration Points + §8 Trade-offs + §9 Open Questions all TBD. §7 Integration Points is the natural next surface given §5's territory-deferral framing.

---

### v1.40 — 2026-05-30

**ARCH §4 Observability row lands — Coolify→Discord (incumbent) primary + Generic Webhook → on-VPS Shape C named fallback; new "conditional-lock + named-fallback" project convention; F1 V1-SHIP-BLOCK Phase 5 PII-vector verification as conditional flip-gate; F2 pull-based-detection posture explicit; F3+F9 RT-21 audit-log capture mirrors RT-05; F10 SECURITY §4.6 V2-ship-gate inventory item (v) added.**

Phase 3 ARCH HTML drafting; team `phase-3-arch-tech-stack` (Architect lead + Sec mandatory joint-review). Observability row had no pre-existing lock (unlike Auth row's ADR-011 Decision 5 / Lock 1) — genuine Phase 3 architectural choice with full scope-shape proposal cycle.

**Scope-shape disposition arc (two-stage F/CTO ratification — first-of-kind for this PR's mechanism-comparison shape):**

- **Stage 1 — initial scope-shape ratification:** Architect proposed 3 substantive options (a Coolify-native minimum / b self-hosted Grafana+Loki+Prometheus stack on cax21 / c Sentry+Pino cloud-hosted hybrid) + (d framing-rejection — hybrid local+cloud). Architect-leaned (c) on the volume-tradeoff calculus: (a) under-provisioned at V1 scale (Plaid webhook + PDF render + cron failures benefit from real-time alerting); (b) over-provisioned (same solo-maintainer ops-load argument that rejected Keycloak/Authelia on the Auth row applies — "debug-your-debugger at 3am"); (c) hits the balance with Sentry hosted = no infra burden + Pino as single SDK per container. **F/CTO picked (a) AMENDED with Coolify→Discord notification routing** (incumbent F/CTO infra that was off-canvas at Architect's scope-shape time — closed the under-alerting con + sidestepped the first-cloud-dependency-in-V1 line).
- **Stage 2 — mechanism-comparison cycle:** After Sec joint-review, F/CTO added directive to explore all 6 Coolify notification mechanisms (Email / Slack / Discord / Telegram / Pushover / Generic Webhooks) for best solution. Architect produced mechanism-comparison cycle at `temp/arch-4-observability-mechanism-comparison.md` (~113 lines; 6-mechanism × 5-criteria comparison: F1 PII vector / first-cloud-dependency line / ops-load / coverage delivered / F1 verification feasibility). **Architect lean: Discord (incumbent) primary + Generic Webhook → on-VPS Shape C named fallback** (SvelteKit `+server.ts` endpoint + flat-file write; ~20 LOC) if F1 Phase 5 verification on Discord payload cannot close the PII vector. **F/CTO sub-ratified Architect's lean.**

**Sec joint-review returned 10 findings** (Task #11) categorized:

- **(a) Load-bearing × 3** — F1 Discord PII vector ESCALATED Phase 5 detail design → V1-SHIP-BLOCK gate (Discord stores message history server-side indefinitely; realistic exposures: transaction-description fragments / [SD-15](docs/SECURITY/index.html#sd-15) acct_number / [SD-03](docs/SECURITY/index.html#sd-03) Plaid access token fragments as [RT-02](docs/SECURITY/index.html#rt-02) compromise vector / SD-01+SD-11 patterns surfacing in stack traces, unhandled exceptions, or stderr-tails the notification payload includes — V1 Sec posture cannot accept under §4.2 SD-03 protection commitments). F2 §4.6 incident-handling tension resolution (Sec found Observability row Coverage NOT delivered (ii) conflicts with §4.6 commitment to incident-logging on "suspicious webhook signature failure pattern"; resolved via explicit pull-based posture in Why cell — **V1 Sec-event detection = active pull-based query against `pfin.plaid_sync_audit`**; F/CTO weekly cadence at single-user V1; NO automated alerting at V1; V2 onboarding triggers Sec-consult per [ADR-008](DECISIONS.md#adr-008) Decision 4. **BONUS within F2**: Sec REJECTED Architect's crash-on-RT-05-trip alternative as DOS vulnerability — adversary sends repeated invalid webhooks → container crash-restart loop → V1 unavailable for legitimate Plaid traffic. RT-05 fence MUST reject WITHOUT crashing). F3 RT-21 audit-log V1-SHIP-BLOCK capture commitment ([RT-05](docs/SECURITY/index.html#rt-05) catalog committed to "invalid-signature payloads dropped with audit-log entry" but [RT-21](docs/SECURITY/index.html#rt-21) had no parallel commitment; paired with F9 same-PR SECURITY catalog (g) addition).
- **(b) Advisory × 5** — F4 notification-target access posture Phase 5 + Sec-consult mandatory (generalized from "Discord channel-access" to cover both primary + Shape C fallback paths) / F5 Coverage gap (ii) framing per F2 / F6 NO sub-section confirm (same precedent as Auth row + §4.2 — no forward-pointer obligation justifies elevation) / F7 Alternatives all Sec-grade / **F8 §10 attribution cross-check CLEAN — commendation** (Architect-side pre-emptive self-audit holding for **3rd consecutive surface review** post-PR-65/66/67; convergence-outcome pattern from broadened `feedback_decision_4_instance_ledger_cross_check` v1.39 codification is durable across surface category variation — Tech Stack rows vs flow diagrams vs operational-observability row).
- **(c) Sub-edit candidates × 2** — F9 SECURITY [RT-21](docs/SECURITY/index.html#rt-21) catalog row gets new (g) verification battery item: *"Rejected JWT payloads dropped with audit-log entry — mirrors RT-05's pattern. Storage surface: `pfin.plaid_sync_audit` row with appropriate source/event-type discriminator (Phase 5 picks schema fit). Detection surface for §4.6 incident-handling 'PDF-JWT trip pattern' triggering event"* (V1-SHIP-BLOCK paired with F3; must land same-PR). F10 SECURITY §4.6 V2-ship-gate inventory item (v) addition: *"Multi-user alerting on RT-05 / RT-21 trips (and any future critical/HIGH security-control-rejection surfaces) per ADR-008 Decision 4 incident-handling ramp; V1 ships pull-based audit-log surface as detection mechanism; V2 onboarding triggers Sec-consult on alerting shape"* (recommended same-PR).

**F/CTO ratified Sec's full package** + Architect's mechanism-comparison lean. Architect v2 (`temp/arch-4-observability-draft-v2.md`, ~94 lines) applied all Sec wording verbatim + integrated the new conditional-lock + named-fallback narrative at top of Why cell. Architect placement calls: conditional-lock narrative top of Why (establishes structural shape before details) + F2 posture immediately after Coverage NOT delivered (ii) (resolves gap adjacent to gap-statement) + F1/F3/F4 bundled under Phase 5 detail design subsection (i)/(ii)/(iii) with (iv) cron-status verification + (v) optional structured-stdout convention carried forward + DOS-vulnerability rejection folded into Coverage NOT delivered (ii) as bolded preemptive answer.

**Team-lead applied v2 to `docs/ARCH/index.html` §4 Observability row** (line 369) + **F9 SECURITY RT-21 catalog (g) addition** + **F10 SECURITY §4.6 V2-ship-gate inventory item (v) addition** + **pre-PR memory creation**: `reference_coolify_discord_notifications` durably anchors F/CTO's incumbent Coolify→Discord configuration (was off-canvas at Architect's scope-shape time + changed the answer materially; analogous to `reference_hetzner_cax21` + `reference_pfin_back_etl` incumbent-infra memories). MEMORY.md index updated.

**New project convention introduced: "conditional-lock + named-fallback" architectural pattern.** Distinct from prior precedents:

- **ADR-015 / Auth row precedent:** unconditional lock (one path; commit fully to one mechanism).
- **§3.2 PDF-JWT-binding precedent:** pure mechanism deferral (no path locked; Phase 5 picks; design-space-constrained-but-undecided).
- **PR #68 / v1.40 NEW:** primary mechanism locked + pre-specified fallback shape named simultaneously; Phase 5 verification is the conditional flip-gate determining which path is live at V1 production. Works here because Shape C fallback is well-defined (~20 LOC SvelteKit `+server.ts` endpoint + flat-file write; one-way-door cost bounded by fallback specificity).

**Post-PR memory candidate flagged:** `feedback_conditional_lock_with_named_fallback` to durably anchor this pattern for future Phase 3 / Phase 5 surfaces. Pattern signature: when a primary mechanism choice has a substantive Sec-posture-or-correctness gate (Phase 5 verification) that may fail with bounded probability, lock primary + name specific fallback shape simultaneously rather than defer choice entirely or commit unconditionally with no fallback. Team-lead to land memory post-PR.

**Substantive deferrals logged (Phase 5 V1-SHIP-BLOCK tasks):**

- **F1 — Coolify Discord payload PII audit (conditional flip-gate).** (a) Verify default payload shape (stderr-tail / unhandled-exception traces / container-log excerpts?); (b) Test against synthetic exception with PII-shaped argument values; (c) Configure scrub OR enforce app-level discipline BEFORE V1 ships with Coolify→Discord active. **If verification cannot close vector, V1 row mechanism flips to Shape C fallback.** Sec-consult mandatory.
- **F3 — RT-21 PDF-JWT-rejection audit-log commitment.** Storage surface `pfin.plaid_sync_audit` or SD-19-derivative (Phase 5 picks schema fit).
- **F4 — notification-target access posture** (Sec-consult mandatory). Discord-primary: channel privacy / webhook URL secrets discipline / message-history retention acknowledged. Shape C fallback: receiver endpoint authentication / flat-file path + permissions / log-rotation policy.
- **Coolify-cron-status visibility verification** — does Coolify natively notify on cron-container exit-status, or custom Phase 5 work needed?
- **Optional structured-JSON-to-stdout log-format conventions** for V2 Pino-adoption forward-compat.

**Discipline convergence pattern continues holding** (post-PR-65/66/67 + this PR). Architect-side pre-emptive §10 attribution cross-check at draft + Sec-side independent verification + Sec-side new-dimension catches at new surface categories. Convergence-outcome codified in `feedback_decision_4_instance_ledger_cross_check` v1.39 + validated through 4 consecutive surface reviews now (no §10 drift caught at draft or verify-pass for §3 Data Flow + Observability row).

**PR `phase/plan-arch-4-observability-row` edit inventory:**

- `docs/ARCH/index.html` (+~75 net) — §4 Observability row replaced (single row; substantial content). Conditional-lock + named-fallback narrative integrated; F1/F2/F3/F4 Sec framings applied verbatim; Coverage NOT delivered (ii) framing with crash-on-failure DOS-rejection inline; audit-log non-overlap explicit; first-cloud-dependency-line preservation explicit for both primary + fallback legs.
- `docs/SECURITY/index.html` (+~5 net) — RT-21 catalog row gets (g) verification battery item (F9 V1-SHIP-BLOCK); §4.6 V2-ship-gate inventory adds item (v) multi-user alerting trigger (F10 recommended).
- `~/.claude/projects/-Users-mosko-Projects-mosko-fintech/memory/reference_coolify_discord_notifications.md` (NEW) — incumbent-infra anchor memory; MEMORY.md index updated.
- `MILESTONES.md` — Last-updated refresh; new Recent-activity entry covering full two-stage F/CTO ratification arc + Sec 10-findings disposition + Architect v2 placement calls + conditional-lock pattern + Phase 5 V1-SHIP-BLOCK deferrals + lesson convergence.
- `WORKFLOW.md` — line 6 in-flight Phase 3 PRs list extended (adds `phase/plan-arch-4-observability-row`); footer v1.39 → v1.40.
- `CHANGELOG.md` — this v1.40 entry; header version count 45 → 46.

**Follow-up:**

- **Post-PR memory:** `feedback_conditional_lock_with_named_fallback` durable anchor for the new project convention (team-lead lands post-merge).
- **Phase 5 V1-SHIP-BLOCK tasks** enumerated above — all must close before V1 production deployment.
- **Remaining ARCH §s** — §5 Deployment Topology refresh post-v1.37 cleanup + §6 CI/CD + §7 Integrations + §8 Trade-offs + §9 Open Questions; §4 Tech Stack rows all complete (V1 web-app / Ingestion+cron / PDF render worker / Styling / Data store / Auth / Hosting / **Observability** — locked at this PR).

---

### v1.39 — 2026-05-30

**ARCH §3 Data Flow lands — prose refresh + §3.1 Plaid webhook + §3.2 PDF render cross-container sequenceDiagrams + F11 SECURITY catalog forward-cross-refs (RT-02 / RT-05 / RT-21 / RT-22 / RT-26 → §3.1 / §3.2).**

Phase 3 ARCH HTML drafting; team `phase-3-arch-tech-stack` (Architect lead + Sec mandatory joint-review). §3 was system-level-overview-only since baseline (prose paragraph + flowchart Mermaid + section-hint deferring per-story sequence diagrams). Post-PR-#65/#66 lock accumulation (SvelteKit framework + RT-26 / §4.1 allowlist + Auth row + §10 three-layer composition canonical layer definitions) made the existing §3 prose stale — needed integration.

**Scope-shape disposition (F/CTO ratified Architect's (c) Hybrid).** Architect proposed 3 shapes pre-draft per the volume-tradeoff calculus: (a) prose refresh + flowchart tighten only (~20 lines) / (b) full per-context expansion with 5 sequenceDiagrams (~200+ lines; risks duplication with later surface §s) / (c) Hybrid — prose refresh + ONLY non-trivial cross-container sequenceDiagrams (Plaid webhook + PDF render; ~100 lines). Architect's (c) rationale: the 3 deferred candidates in (b) are single-container (user-session SSR write/read) or parametric-mirrors (pfin_back_etl cron mirrors webhook privileged-context shape); only the 2 cross-container flows have non-trivial design choices that belong in §3 system-level scope (crossing trust boundaries; touching RT-22 + RT-26 + RT-02 + RT-05 + Lock 13 mod #1 in those 2 flows alone). F/CTO ratified.

**Architect's pre-SendMessage §10 attribution-drift cross-check at top of v1 draft** (lines 10–20) — the post-PR-66 broadened `feedback_decision_4_instance_ledger_cross_check` memory working at source. All 7 watch-list items checked pre-SendMessage: RT-22 first / RT-26 second / TenantBoundConnection scoped to pfin_back_etl Python (not in numbered list) / Auth supplies JWT to JWT-shape-layer / `/api/plaid/webhook` + `/internal/pdf-render` framed as "allowlisted surfaces inside RT-26's code-layer audit scope" / PDF worker container framed as "where RT-22 is enforced" / V1 webhook's analogous discipline named "TypeScript-side helper" without inventing a parallel class name. Sec commended this as the convergence-outcome pattern — broadened memory + Sec-catches → Architect-side pre-emptive discipline working as designed.

**Sec joint-review returned 11 findings** (Task #8) categorized:

- **(a) Load-bearing × 4** — F1 missing canonical Lock 4 mod #2 `users_id` lookup + tenant-binding attribution mis-direction (Architect's v1 conflated "tenant correctness bound via audit-log" — actual binding is the explicit `users_id` lookup from `plaid_items.plaid_item_id`; same-tx audit-log RECORDS the chain, doesn't BIND it; Severity: Phase 6 AI-coding-agent could implement audit-log-first ordering and skip the explicit lookup) / F2 "impersonates" wording is security-loaded and mechanically wrong (PDF worker JWT signed with `PDF_WORKER_SIGNING_KEY` NOT Supabase JWT signing key per RT-21(a/b); the two tokens are structurally different by design — only the `auth.uid()` *claim* is shared; mechanical question of how V1's `/internal/pdf-render` binds verified user identity to RLS's `auth.uid()` is **genuinely undecided in V1 architecture** — Sec recommended §3.2 defer mechanism choice to Phase 5 detail design per Lock 13 mod #1 contract, constrained by RT-21(e) no-service_role-escalation; Severity: "impersonate" could lead Phase 6 implementation to misuse `PDF_WORKER_SIGNING_KEY` to sign Supabase-shaped tokens — RT-21(b) violation + real vulnerability vector) / F3 missing V1-SHIP-BLOCK Sec mod (webhook idempotency `plaid_webhook_id` UNIQUE per Lock 4 mod #3) — distinct gate from transaction dedup; must fire before SERIALIZABLE tx / F4 SD-14 cross-ref drift (Architect's draft cited "ADR-011 Decision 16" but SD-14 lands at Decision 8 / Lock 4; Decision 16 is Lock 12 monthly_report_account_snapshot, unrelated).
- **(b) Advisory × 6** — F5 Decision 3 cross-tenant FK-bypass family attribution for matched-tenant triggers + service_role precision sentence (RLS bypassed; CHECK/UNIQUE/FK/triggers all fire) / F6 RT-21 verification battery (a)–(f) enumeration in §3.2 step 3 / F7 reverse-path tenant-scoping-by-construction note (HTML returned to PDF worker is RLS-tenant-scoped by predicate construction) / **F8 §10 attribution-drift cross-check CLEAN — commendation** (Architect's pre-SendMessage self-audit validated post-PR-66 broadened-memory convergence; recommend memory note this) / F9 confirm Architect's lean on §3.X anchors INCLUDE (distinct from Auth row NO sub-section per §4.1/§4.2 precedent — `sec-3-1`/`sec-3-2` don't collide with anything; high option-value for SECURITY forward-cross-refs) / F10 confirm flowchart subtle tighten + no §3.3 closing pointer (Architect's leans validated).
- **(c) Sub-edit candidates × 1** — F11 SECURITY catalog forward-cross-refs to ARCH §3.1 / §3.2 at RT-05 / RT-21 / RT-22 / RT-26 entries (parallel to PR #65 F7 pattern).

**Plus minor: RT-02 added to §3.1 prose alongside RT-05** (Plaid Items table critical-severity surface is exactly what the Plaid webhook touches; Sec mentioned in cross-ref verification).

**F/CTO ratified Sec's full package** + Architect's three structural-question leans (anchors yes / flowchart subtle / no §3.3 closing pointer). Architect v2 (`temp/arch-3-data-flow-draft-v2.md`, ~247 lines) applied F1–F7 + bonus RT-02 verbatim from Sec wording. Architect placement calls: F1 lookup-step **inside-SERIALIZABLE-tx** (atomicity / cleaner rollback semantics — all preconditions checked under same SERIALIZABLE level as writes; one critical section); F3 idempotency-step **first INSERT after BEGIN SERIALIZABLE** (fail-fast before tenant-resolution lookup; ON CONFLICT → ROLLBACK + 200 OK); F7 reverse-path note phrasing concise for diagram-format (*"HTML returned is tenant-scoped by RLS-predicate construction at the DB; no cross-tenant leakage path on the return even under upstream-bug-class failure"*). Sec accepted both F1 placements (between-verify-and-client OR inside-SERIALIZABLE-tx); Architect's inside-tx is the cleaner narrative.

**Team-lead applied v2 to `docs/ARCH/index.html` §3** — prose refresh (5 paragraphs replacing 1; integrates SvelteKit + §4.1 + §10 three-layer composition + ADR-011 Decisions 1/3/4/5/8/14/16/17 + ADR-015 + ADR-008 + ADR-005 + Lock 14/15) + flowchart tighten (subtle inline-label additions; no new nodes/arrows; preserves abstract clarity) + §3.1 sub-section (`<h3 id="sec-3-1">`) with 11-step sequenceDiagram (Plaid → SvelteKit `/api/plaid/webhook` allowlisted §4.1 → signature-verify RT-05 → service_role from `src/lib/server/` factory → SERIALIZABLE tx → idempotency UNIQUE Lock 4 mod #3 → tenant-resolution Lock 4 mod #2 → plaid_item_state_history SD-14 → dedup + account_trans SD-00/Lock 9 → `pfin.plaid_sync_audit` Decision 17 mod #8 → 200 OK) + intro paragraph (RT-02 + RT-05 + idempotency + Decision 1 + SD-14 + Lock 9) + layer-composition prose (allowlisted surface inside RT-26 / tenant-binding via Lock 4 mod #2 / audit-log records via Lock 13 mod #4 / matched-tenant triggers Decision 3 / SD-00 immutability Decision 14/Lock 10; JWT-shape-layer NOT in play on write path; infra-credential-presence-layer NOT in play — V1 holds creds by necessity; RT-22 scope is PDF worker only) + §3.2 sub-section (`<h3 id="sec-3-2">`) with 10-step sequenceDiagram (PDF worker no creds RT-22 → mint short-lived JWT PDF_WORKER_SIGNING_KEY 60s+nonce+auth.uid() SD-20 → V1 `/internal/pdf-render` allowlisted §4.1 → verify RT-21 battery a/b/c/d/e/f → SECURITY INVOKER → DB Note JWT-shape-layer in motion + binding-mechanism-Phase-5 → render HTML → reverse-path Note tenant-scoped-by-construction → Puppeteer Lock 13 mod #7 → PDF artifact) + intro paragraph (RT-22 + Lock 13 mod #2 + Lock 12 mod #1 + SD-20 + RT-21 V1-SHIP-BLOCK) + **JWT-mechanism Phase 5 deferral paragraph** (custom JWT signed with PDF_WORKER_SIGNING_KEY NOT Supabase Auth JWT per RT-21(a/b); shares `auth.uid()` claim only; concrete binding mechanism Phase 5 constrained by RT-21(e) no-service_role-escalation) + layer-composition prose (where RT-22 is enforced; `/internal/pdf-render` allowlisted but does NOT use service_role in V1 — authenticated tier with bound identity; three-layer composition fully exercised on this one flow).

**F11 SECURITY catalog forward-cross-refs applied at 5 RT entries** (`docs/SECURITY/index.html`): RT-02 + ARCH §3.1; RT-05 + ARCH §3.1; RT-21 + ARCH §3.2; RT-22 + ARCH §3.2; RT-26 + ARCH §3.1 + §3.2. Parallel to PR #65 F7 pattern (SECURITY ↔ ARCH mutual cross-ref anchoring).

**Substantive deferral logged.** V1 PDF-JWT-to-RLS binding mechanism (SET LOCAL request.jwt.claims vs parametric WHERE users_id = $1 vs other) is **Phase 5 detail design**, not committed in V1 ARCH — §3.2 explicitly admits the open question and constrains the design space (RT-21(e) no-service_role-escalation). This is the first ARCH-level "Phase 5 detail design" deferral on a mechanism that affects critical-security surface composition; pattern likely recurs at future Phase 3 surfaces.

**Lesson convergence.** The post-PR-66 broadened `feedback_decision_4_instance_ledger_cross_check` memory has now seen:
- **Architect-side pre-emptive discipline** (v1 §10 attribution-drift cross-check at draft time; lines 10–20 of working doc).
- **Sec-side catch on a different §10 attribution-drift dimension** (F1+F2 layer attribution + canonical-mechanism completeness; complementing PR #66 Finding F1 layer-attribution + PR #65 Finding V1 instance-numbering).

The discipline is converging: each new architectural surface triggers both Architect-side self-audit AND Sec-side independent verification on §10 attribution; the catch surface is narrowing as the pattern becomes habitual. Post-PR memory updated to note this convergence-outcome pattern as the validation criterion (two consecutive Sec catches → broadened memory → Architect-side pre-emptive discipline → Sec-side verifies + commends → memory codifies the loop).

**PR `phase/plan-arch-3-data-flow` edit inventory:**

- `docs/ARCH/index.html` (+126 net) — §3 system-level overview replaced (prose refresh + flowchart tighten + §3.1 sub-section + §3.2 sub-section + layer-composition prose blocks + Phase 5 mechanism-deferral paragraph).
- `docs/SECURITY/index.html` (+5 net) — F11 forward-cross-refs at RT-02 / RT-05 / RT-21 / RT-22 / RT-26 entries to ARCH §3.1 / §3.2.
- `MILESTONES.md` — Last-updated refresh; new Recent-activity entry covering §3 lands + Sec 11-findings disposition + Architect v2 placement calls + Phase 5 PDF-JWT deferral + lesson convergence.
- `WORKFLOW.md` — line 6 in-flight Phase 3 PRs list extended (adds `phase/plan-arch-3-data-flow`); footer v1.38 → v1.39.
- `CHANGELOG.md` — this v1.39 entry; header version count 44 → 45.

**Post-PR memory follow-up:** `feedback_decision_4_instance_ledger_cross_check` updated to note v1.39 F8 commendation + convergence-outcome pattern (Architect-side pre-emptive discipline now visible at v1 draft time; Sec-side catches on new §10 dimensions still expected as discipline-stress-test surface).

**Follow-up:**
- **Phase 5 PDF-JWT-to-RLS binding mechanism choice** — `SET LOCAL request.jwt.claims` vs parametric `WHERE users_id = $1` vs other; constrained by RT-21(e) no-service_role-escalation per Lock 13 mod #1. ARCH section will land at Phase 5 entry per the deferred-mechanism convention.
- **Phase 5 V1-web-app TypeScript-side privileged-context helper class name** — Architect's v2 named it generically as "TypeScript-side helper" without inventing a parallel class name to TenantBoundConnection (Python-side); Phase 5 detail design lands the implementation shape.
- **Remaining ARCH §s** — §6 CI/CD + §7 Integrations + §8 Trade-offs + §9 Open Questions; §4 Observability row still TBD.

---

### v1.38 — 2026-05-29

**ARCH §4 Auth row lands — Supabase Auth + native RLS Option A baseline locked per [ADR-011](DECISIONS.md#adr-011) Decision 5; JWT-shape-layer composition correctly attributed (RLS predicate at DB; Auth supplies the JWT input).**

Phase 3 ARCH HTML drafting; team `phase-3-arch-tech-stack` (Architect lead + Sec mandatory joint-review per MILESTONES line 35; load-bearing at auth surface — critical-security category). Narrower scope than [v1.37](#v137--2026-05-29) (single table row vs full §4 restructure + §4.1 sub-section).

**Process arc.** Architect drafted v1 inline (no `temp/` working doc — scope fits ~50 lines). Sec returned 7 findings (Task #5 joint-review) categorized:

- **(a) Load-bearing × 2** — F1 JWT-shape-layer attribution drift (Architect's v1 conflated "Auth = JWT-shape-layer" with the actual layer attribution; the JWT-shape-layer IS the RLS predicate `users_id = auth.uid()` enforced at the DB layer per Decision 4 + SECURITY §4.2; Auth supplies the JWT *input to* that layer, not the layer itself) + F2 §4.2 sub-section disposition (Sec confirmed Architect's lean (a) NO sub-section — no analogous outstanding forward-pointer obligation; anchor-collision contingency on (b) flagged: `sec-4-2` would collide with SECURITY §4.2 reader-naming).
- **(b) Advisory × 5** — F3 MFA + session-rotation policy reference not locked anywhere in V1 artifacts (Sec confirmed grep zero hits) — F3 (i) lock V1 posture inline ("no MFA / Supabase platform-default refresh-token rotation"; Sec preference over option (ii) drop entirely) / F4 Phase 3 qualifier restoration on Option C overlay forward-pointer + destination anchor specificity ("future ARCH section or SECURITY §4 sub-section; Sec-consult mandatory at lock-time") / F5 explicit `authenticated` vs `service_role` tier-discipline clarification sentence / F6 §10 ledger cross-check CLEAN (no Nth-catalogued-instance claim; layer-of-defense reference only — confirmation finding) / F7 Alternatives Considered Sec-grade (External IdP / Self-hosted IdP / DIY JWT all rejected with security-posture-sound rationale — confirmation finding).
- **(c) Sub-edit candidates × 0** — SECURITY + DECISIONS canonical wording stands; Auth row aligns to canonical, not the reverse.

**F/CTO ratified Sec's full package.** Architect produced v2 inline applying all 5 ratified findings + dropping the structural-question section per F2(a). Architect placement calls: F5 tier-clarification placed immediately after F1 §10-composition framing (both deal with tier separation); F3 V1-posture-lock placed after the SECURITY §4 posture-obligations sentence (flows as "posture obligations canonical home → V1 posture is X"). Architect flagged the F1 verbatim's `#sec-4-2` link as intentional dual-purpose anchoring (Sec's verbatim points to §4.2 as the §10 three-layer defense's documented home in SECURITY, separate from the top-level §4 link for posture-obligation canonical home); team-lead confirmed.

**Team-lead applied v2** to `docs/ARCH/index.html` line 249 — replacing the `class="tbd"` Auth row (`— (Phase 3 decision; Supabase Auth candidate)`) with the full Choice / Why / Alternatives content.

**Substantive Auth row content.**

- **Choice:** Supabase Auth (Supabase-native identity provider, JWT-issuing, in-stack on the same self-hosted Supabase as the Data store row per [ADR-002](DECISIONS.md#adr-002) §6.0); locked at [ADR-011](DECISIONS.md#adr-011) Decision 5 / Lock 1 as V1 multi-tenant isolation baseline (Option A: Supabase Auth + native RLS) with selective Option C overlay to be resolved at next Phase 3 architectural surface lock covering RT-02 (Plaid Items table) + RT-05 (webhook handler) critical-severity surfaces.
- **Why:** (1) 1:1 native-RLS composition — Supabase Auth's session JWT carries `auth.uid()`; native RLS predicates `users_id = auth.uid()` consume directly under `authenticated` tier; no token-translation layer. (2) SvelteKit-side chokepoint — `src/hooks.server.ts` (allowlisted per §4.1) is the centralized Supabase-session-forwarding + auth-refresh point per [ADR-015](DECISIONS.md#adr-015). (3) §10 composition — Auth row supplies the JWT shape that the JWT-shape-layer of the §10 three-layer defense consumes (Sec F1 verbatim attribution); the JWT-shape-layer itself is the RLS predicate at the DB layer per Decision 4 + SECURITY §4.2; three-layer composition = code-layer (RT-26 V1-web-app allowlist) + JWT-shape-layer (this row supplies the JWT) + infrastructure-credential-presence-layer (RT-22 PDF worker Dockerfile audit). (4) Tier discipline — Supabase Auth issues `authenticated`-tier JWTs only; `service_role` is server-only, never issued via user-facing Auth flow; service_role discipline is the RT-26 / §4.1 allowlist-fence domain. (5) Posture obligations live at SECURITY §4 (V1 Sec canonical reference layer per [ADR-008](DECISIONS.md#adr-008)). (6) V1 posture locked inline: no MFA required (single-user / invite-only-V2 scale); session-rotation = Supabase Auth platform-default refresh-token rotation. (7) Zero incumbent-switching cost.
- **Alternatives Considered:** External IdP integration (Auth0 / Clerk / Cognito) rejected at Decision 5 framing — IdP integration surface adds work without unlock; Option B portability not load-bearing for single-tenant-in-use V1 + invite-only-V2. Self-hosted identity (Keycloak / Authelia) rejected at framing — doubles operationally-managed stack on Hetzner cax21 with no V1 unlock; solo-maintainer operational-load discipline. Build-from-scratch JWT issuance rejected at framing — reinvents auth wheel; multiplies attack surface against RT-02 / RT-05 critical surfaces.

**Lesson logged: §10-surface attribution drift is a recurring failure mode** — caught at Sec review on two consecutive PRs in the same Phase 3 architectural-surface arc. PR #65 / v1.37 caught Finding V1 (TenantBoundConnection-as-"first catalogued §10 instance" instance-numbering drift). PR `phase/plan-arch-4-auth-row` / v1.38 caught Finding F1 (Auth-row-as-"JWT-shape-layer" layer-attribution drift). Same shape: a true architectural mechanism gets miscredited as the canonical anchor itself, when its actual role is to supply input to / parallel the catalogued anchor. The existing `feedback_decision_4_instance_ledger_cross_check` memory (created post-PR-65) covers instance numbering specifically; **the memory should be broadened post-PR to cover layer attribution + instance numbering as a single §10-surface attribution-drift class.** This was already flagged in the F/CTO ratify briefing; deferred to a post-PR meta-state-refresh task to consolidate the drift class definition before it ages.

**PR `phase/plan-arch-4-auth-row` edit inventory:**

- `docs/ARCH/index.html` — Auth row (line 249) `class="tbd"` placeholder replaced with full Choice / Why / Alternatives content per v2.
- `MILESTONES.md` — Last-updated refresh; new Recent-activity entry covering Auth row lands + Sec 7-findings disposition + Architect v2 + Finding F1 lesson logged.
- `WORKFLOW.md` — line 6 in-flight Phase 3 PRs list extended (adds `phase/plan-arch-4-auth-row`); footer v1.37 → v1.38; current-version + last-updated bumped.
- `CHANGELOG.md` — this v1.38 entry; header version count 43 → 44.

**Follow-up.**
- **`feedback_decision_4_instance_ledger_cross_check` memory broadening** — promote scope from "§10 instance numbering" to "§10-surface attribution-drift class" covering both instance numbering and layer attribution. Cite v1.37 Finding V1 + v1.38 Finding F1 as the two precedent catches.
- **ARCH §4 Observability row** + **§4 Hosting row** (already populated; no work) + **ARCH §3 Data Flow + §6 CI/CD + §7 Integrations + §8 Trade-offs + §9 Open Questions** remain TBD — candidate Phase 3 ARCH next surfaces.

---

### v1.37 — 2026-05-29

**ARCH §4 + §4.1 lands — Tech Stack table restructured to Option C 3-container shape ([ADR-011](DECISIONS.md#adr-011) Decision 17 / Lock 13 hybrid topology); §4.1 `sec-4-1` sub-section as V1-CONCRETE [RT-26](docs/SECURITY/index.html#rt-26) file-glob allowlist anchor.**

Phase 3 ARCH HTML drafting; team `phase-3-arch-tech-stack` (Architect lead + Sec mandatory joint-review per MILESTONES line 35 — load-bearing because §4.1's file-glob allowlist IS what RT-26's CI grep audits against). Closes RT-26's "concrete file-glob enumeration locked in ARCH §4 at framework ratify" obligation that SECURITY §4.2 carried forward as framework-agnostic; the precondition was ADR-015's framework lock at v1.36.

**Process arc.** Architect drafted v1 with 4 deliverables (Frontend framework row + Styling row + concrete server-source file-glob allowlist sub-block + Backend row 3-option disposition with Architect's lean Option C). Sec returned 9 findings (Task #2 joint-review) categorized:

- **(a) Load-bearing × 3** — F1 allowlist-semantic-ambiguity rewording (grep scope = full `src/` tree; allowlist = permitted-set, NOT search-scope — universal loaders `+page.ts` / `+layout.ts` would otherwise leak service_role to client bundle), F2 Backend row → Option C (Sec strong-prefer matching Architect lean on fence-attribution-clarity grounds: each row = one container = one runtime = one fence-class; 1:1 fence-to-container mapping vs Option B's smearing or Option A's hiding workers), F3 `<h3 id="sec-4-1">` sub-section over inline callout (stable cross-ref anchor for SECURITY §4.2 ↔ ARCH §4.1 mutual anchoring).
- **(b) Advisory × 3** — F4 extend allowlist-exclusion to repo-root `vite.config.{ts,js}` + `svelte.config.js` (build-time client-bundle-injection failure mode), F5 `src/params/**` covered by-construction under F1's "all non-allowlisted surfaces in `src/**` trip the grep" framing (no separate enumeration), F6 keep 5-row Markdown table over `<ul>` (the `Why audit-relevant` column is Phase 6 PR-review audit-trail material; table shape matches §4.4 / §4.5 SECURITY matrix convention).
- **(c) Sub-edit candidates × 3** — F7 SECURITY §4.2 RT-26 bullet cross-ref tighten `ARCH §4` → `ARCH §4.1` / F8 ADR-011 Decision 4 §10 instances line same tighten — **NO new §10 instance addition** (Sec correction to team-lead's Task #2 brief: RT-26 is already catalogued as Decision 4's 2nd §10 instance; §4.1 is the V1-CONCRETE *realization* of that obligation, not a new instance) / F9 ADR-015 Consequences bullet optional cross-ref tighten.

**F/CTO ratified Sec's full package + same-PR §1 blockquote unwind.** Architect produced v2 draft (`temp/arch-4-tech-stack-draft-v2.md`) applying F1–F4 verbatim + dropping F5 + keeping F6 + adding §1 blockquote unwind in option (b) lock-acknowledgment shape (NOT option (a) remove — Architect rationale: blockquote was a deliberate visual call-out on the framework choice; the choice IS still the most consequential §1 commitment, just now locked; (b) preserves §1 visual hierarchy + makes the lock unmissable + sets up §4 + §4.1 + RT-26 cross-refs cleanly).

**Team-lead applied v2 to HTML + same-PR sub-edits.** `docs/ARCH/index.html` edits: §1 prose tightening (`(TypeScript;` → `(SvelteKit + TypeScript;`); §1 blockquote unwind (replace "One un-locked choice flagged" framing with lock-acknowledgment shape; full mutual cross-refs to ADR-015 / ADR-012 / ADR-011 Decision 17 / §4 / §4.1 / RT-26 / ADR-014); §2 components table tightening (line 109: `(TypeScript; framework TBD)` → `(SvelteKit + TypeScript)` — team-lead caught on same-logical-edit-family scan); §5 deployment topology Mermaid tightening (line 156: `TypeScript (framework TBD)` → `SvelteKit + TypeScript` — same scan); §4 full table replacement (8 rows: V1 web-app SvelteKit / Ingestion+cron `pfin_back_etl` Python / PDF render worker Node+Puppeteer / Styling / Data store / Auth / Hosting / Observability); §4.1 sub-section added with allowlist-shaped framing per Sec's verbatim F1 wording + 5-row glob-enumeration table + repo-root build-config exclusion paragraph (F4) + worker-entry codepath bullets (pfin_back_etl TenantBoundConnection + PDF worker RT-22 infra-credential-presence) + three-layer §10 defense composition. Sub-edits: F7 + F7-consistency-extension on SECURITY RT-26 catalog entry + F8 + F9 cross-ref tightenings to `ARCH §4.1` anchor.

**Sec verify-pass caught Finding V1 (§10-instance numbering drift) at HTML review.** Architect's draft + team-lead's application both carried "First catalogued §10 instance (`TenantBoundConnection` + CI grep)" framing on the §4 Ingestion row + §4.1 pfin_back_etl bullet, but ADR-011 Decision 4's canonical "Catalogued §10 instances at V1" numbered list catalogues **RT-22 first + RT-26 second** — TenantBoundConnection lives in Decision 4's *Privileged-context-surfaces bullet*, NOT the catalogued numbered list. Not security-correctness drift (fence mechanisms correctly described); ledger-numbering consistency drift (future PR-reviewers hitting §4 + Decision 4 would see ambiguity on canonical instance numbering). Fix landed same-PR (mechanical wording correction at §4 Ingestion row "Why" column + §4.1 worker-entry bullet; both reframed to "Code-layer §10 fence (`TenantBoundConnection` + CI grep) per ADR-011 Decision 4 Privileged-context surfaces bullet" with explicit "not in Decision 4's catalogued-instance numbered list" disambiguation in the §4.1 bullet). PDF worker row's layer-qualified "First catalogued instance of the infrastructure-credential-presence layer" stands (RT-22 IS the only instance in that layer in the catalogued list per Decision 4). **Sec PASS unconditional** after Finding V1 fix.

**Substantive structural moves.**

- **§4 row layout: Option C 3-container restructure.** Replaces conventional Frontend+Backend split with three container rows mirroring [ADR-011](DECISIONS.md#adr-011) Decision 17 / Lock 13 hybrid 3-container topology one-to-one (V1 web-app / Ingestion+cron / PDF render worker) + Styling as its own row (deliverable 2). Table grows 6 → 8 rows; the conventional Tech Stack convention is the small price; the 1:1 fence-to-container mapping + §1↔§4 internal-consistency (§1 prose already broke from Frontend/Backend framing in favor of container framing) + §2 ↔ §4 ↔ §5 cohesion are the payoff. Sec-recommended on fence-attribution-clarity grounds; Architect-lean on §1↔§4 consistency grounds; both arguments compose.
- **§4.1 sub-section as RT-26 obligation-closing artifact.** Allowlist-shaped (NOT wrapping-shaped) fence design — grep scope is the V1 web-app source tree (`src/**` + repo-root config files); references in allowlisted globs are permitted, all others trip at PR-time (fail-closed). Universal loaders + non-allowlisted surfaces are by-construction-banned, closing the client-bundle-leak failure mode by the same fence that closes the RLS-bypass failure mode. Allowlist additions require Sec-consult + ADR amendment at the surface-introducing lock. 5 canonical SvelteKit server-source surfaces enumerated: `src/routes/**/+server.ts` (route handlers; Plaid webhook + `/internal/pdf-render`) / `src/routes/**/+page.server.ts` (per-route SSR data loading) / `src/routes/**/+layout.server.ts` (layout-level data + auth gates) / `src/hooks.server.ts` (centralized Supabase session forwarding) / `src/lib/server/**/*.ts` (server-only-module convention; Vite-enforced; the surface where service_role drift is most likely under a "DRY up the codebase" refactor). Worker-entry codepaths separated under their own fence layers (pfin_back_etl TenantBoundConnection code-layer; PDF worker RT-22 infra-credential-presence). Three-layer §10 defense composition (code-layer + JWT-shape-layer + infrastructure-credential-presence-layer) restated per ADR-011 Decision 4.
- **§1 blockquote unwind: lock-acknowledgment shape.** Pre-PR: "One un-locked choice flagged. The frontend framework ... is not yet decided ... This overview describes the V1 app as a TypeScript/Node web application (the ADR-011 Decision 17 topology shape, which names Next.js as the incumbent-implied candidate) but does not lock the framework." Post-PR: "Framework locked. The V1 web app is built on SvelteKit (Svelte 5) per ADR-015 — closing the Phase 2 ↔ Phase 3 coupling point per ADR-012 and anchoring the V1-web-app container in the ADR-011 Decision 17 hybrid 3-container topology. See §4 ... §4.1 ... RT-26 ... ADR-014." Preserves §1 visual hierarchy; makes the lock unmissable on a fresh read; mutual cross-ref anchoring complete.

**PR `phase/plan-arch-tech-stack` edit inventory:**

- `docs/ARCH/index.html` — §1 prose tightening + §1 blockquote unwind + §2 components table tightening + §5 deployment topology tightening + §4 full table replacement + §4.1 sub-section added + Finding V1 §10-instance-numbering-drift fix at §4 Ingestion row + §4.1 worker-entry bullet.
- `docs/SECURITY/index.html` — F7 cross-ref tighten at §4.2 RT-26 bullet + F7-consistency-extension at RT-26 catalog entry (both `ARCH §4` → `<a href="../ARCH/#sec-4-1">ARCH §4.1</a>`).
- `DECISIONS.md` — F8 cross-ref tighten at ADR-011 Decision 4 §10 instances line + F9 cross-ref tighten at ADR-015 Cross-references line (both `ARCH §4` → `[ARCH §4.1](docs/ARCH/index.html#sec-4-1)`).
- `MILESTONES.md` — Last-updated refresh; new Recent-activity entry covering ARCH §4 + §4.1 lands + Sec 9-findings disposition + Finding V1 catch + same-PR §1/§2/§5 cleanup.
- `WORKFLOW.md` — line 6 in-flight Phase 3 PRs list extended (adds `phase/plan-arch-tech-stack`); footer v1.36 → v1.37; current-version + last-updated bumped.
- `CHANGELOG.md` — this v1.37 entry; header version count 42 → 43.

**Follow-up.** ARCH Auth row + Observability row remain `class="tbd"` (Phase 3 carry-over tasks; not in this PR's Task #1 scope). RT-26 fence CI implementation (Phase 5 / 6 work; CI pipeline build).

---

### v1.36 — 2026-05-29

**[ADR-015](DECISIONS.md#adr-015) lands — SvelteKit + no Tailwind; Phase 2 Step 10 closes by composition; post-PR-63 state refresh.**

**ADR-015 framing.** Architect-originated 3-option frontend framework brief (Next.js App Router / Remix (React Router v7 framework mode) / SvelteKit) with constraint-by-constraint satisfaction tables against the Lock-13 hybrid 3-container topology + Lock-13 mod #1 PDF-render contract + Supabase JS RLS-forwarding + [ADR-014](DECISIONS.md#adr-014) two-tier token consumption. Architect's ranked lean: **Remix > Next > SvelteKit**, weighted on solo-maintainer multi-week-gap mental load + Phase-6 AI-coding-agent fluency + React-ecosystem availability. **F/CTO ratified SvelteKit** in-conversation against the Architect lean on engineering-merit grounds (verbatim: *"Better structural engineering decision"*); subsequently ratified **no Tailwind**.

**Process gap caught by Sec.** The §SECURITY §4.2 V1-web-app posture sub-§ + RT-26 framework-agnostic `SUPABASE_SERVICE_ROLE_KEY` fence (PR #62) reached verify-pass and Sec ran the grep — `SvelteKit` / `Svelte` returned zero matches across `DECISIONS.md` / `docs/` / `MILESTONES.md` / `WORKFLOW.md` despite the in-conversation ratification. Decision was real but had no committed artifact; RT-26's "concrete server-source file-glob enumeration locked in ARCH §4 at framework ratify" obligation needed the framework artifact to anchor against. ADR-015 closes the gap.

**Sec joint-review at v2 — two amendments applied before F/CTO ratify.**

- **Finding 1 (load-bearing) — audit-scope glob completeness:** Architect's v1 canonical-server-source surfaces enumeration missed `+layout.server.ts` (SvelteKit layout-level data loading + auth gates) + `src/lib/server/**/*.ts` (SvelteKit's server-only-module convention, Vite-enforced at import time). Both are real SvelteKit conventions where service-role drift could land and slip past the RT-26 CI grep. Added to the enumeration in three locations (Locked option, Cross-references, Consequences).
- **Finding 2 (framing) — Decision 17 "supersedes" → "extends":** v1 used "supersedes" for ADR-015's relationship to [ADR-011](DECISIONS.md#adr-011) Decision 17 (Lock 13 / V1 app container). Verified Decision 17's committed text is framework-neutral (verbatim: *"V1 app retains Plaid webhook handler + in-app render path"*) — nothing to supersede. Reworded to "extends" in three locations.

**Locked option.**

- **Frontend framework:** **SvelteKit (Svelte 5)** for the V1 web app container in [ADR-011](DECISIONS.md#adr-011) Decision 17's hybrid 3-container topology. Canonical server-source surfaces (the RT-26 audit scope): `+server.ts` (route handlers) / `+page.server.ts` (SSR data loading) / `+layout.server.ts` (layout-level data + auth gates) / `src/hooks.server.ts` (Supabase session forwarding + auth refresh) / `src/lib/server/**/*.ts` (server-only-module convention). Build via Vite; deploy as a small Node server in its Coolify container on the existing Hetzner cax21.
- **Styling:** **No Tailwind.** [ADR-014](DECISIONS.md#adr-014)'s two-tier CSS-custom-properties token taxonomy (`--color-*` primitives → `--c-*` semantic aliases) consumed natively via Svelte component-scoped `<style>` blocks; `tokens.css` imported globally in `src/app.css`. Component styles use `var(--c-*)` directly; no utility-class transformation layer.

**Rationale (F/CTO engineering-merit weighting).**

- **Lock 13 mod #1 PDF-render contract** (Puppeteer → V1 app `/internal/pdf-render` → SECURITY INVOKER read-composition helper): SvelteKit's `+server.ts` / `+page.server.ts` surfaces are **SSR by default** — no `dynamic = "force-dynamic"` opt-out knob to remember (Next.js's structural disadvantage on this contract) and no caching-defaults flip exposure.
- **[ADR-014](DECISIONS.md#adr-014) token consumption is 1:1.** Svelte's idiomatic styling pattern *is* component-scoped CSS + CSS custom properties — exactly the shape [ADR-014](DECISIONS.md#adr-014) locked. No Style Dictionary export, no Tailwind `@theme` round-trip, no design-token JSON intermediate.
- **Smallest container footprint** of the three options (~60–120 MB idle vs. ~80–150 MB Remix and ~200–400 MB Next.js); meaningful on a shared cax21 (16 GB) running `pfin_back_etl` + V1 app + PDF worker + Supabase concurrently.
- **Lowest framework ceremony** for Supabase RLS forwarding: centralized in `hooks.server.ts`; one place to get the user-session-JWT-forwarding pattern right, one place to audit.
- **No Tailwind** falls out naturally — adding utility classes on top of [ADR-014](DECISIONS.md#adr-014)'s already-finished CSS variables would reintroduce double-bookkeeping.

**Costs accepted explicitly.** Architect's lean prioritized (i) solo-maintainer multi-week-gap mental load (Remix's two-primitive loader/action model is the smallest mental surface); (ii) Phase-6 AI-coding-agent fluency (React-based options materially better-represented in current LLM training corpora than Svelte 5; runes API new); (iii) React-ecosystem availability (shadcn/ui, Radix). F/CTO accepted these costs, with the caveat that **Phase-6 build-loop velocity will pay a real ramp-up cost on UI work** that Phase 6 entry lessons-learned should track.

**Consequences.**

- **Phase 2 Step 10 (tokens-as-code) CLOSES by composition.** `docs/DESIGN/tokens.css` IS the consumption format; imported globally in `src/app.css`; component `<style>` blocks use `var(--c-*)` natively. Visual Designer notification follows once ADR-015 + ARCH §4 land.
- **ARCH §4 Tech Stack write-up is next** — populates Frontend framework + Styling rows; carries the Alternatives Considered material into the "alternatives" cells; enumerates the concrete SvelteKit server-source file-glob allowlist that RT-26 / [SECURITY §4.2](docs/SECURITY/index.html#sec-4-2) audits against.
- **[ADR-011](DECISIONS.md#adr-011) Decision 17's "V1 app" container is now anchored as SvelteKit.** ADR-015 extends Decision 17 — hybrid topology + privileged-context-write disciplines + Lock 13's full mod inventory all stand unchanged.
- **No other ADRs superseded or amended.** [ADR-005](DECISIONS.md#adr-005) / [ADR-013](DECISIONS.md#adr-013) / [ADR-014](DECISIONS.md#adr-014) compose unchanged.
- **ADR-015 is in-principle reversible** if Phase-6 agent-fluency cost lands materially higher than expected (UI-layer rewrite; DB / RLS / worker code is portable) — but reversal is a one-way-door-shaped cost, not the planning baseline.

**Same-day Phase 3 progress** (PRs #60 + #62 — first material content beyond ARCH scaffolding).

- **PR #60 `phase/plan-arch-system-overview`** — Phase 3 ARCH HTML §1 / system-overview content landed in `docs/ARCH/index.html`.
- **PR #62 `phase/plan-sec-rt26`** — Sec-led; lands **RT-26** in the §SECURITY risk-treatment catalog + §4.2 V1-web-app posture sub-§ committing to a framework-agnostic CI grep fence forbidding `SUPABASE_SERVICE_ROLE_KEY` import in the V1 web-app server bundle; concrete file-glob allowlist deferred to ARCH §4 at framework ratify (precondition: ADR-015). Also catalogues §10 defense-in-depth meta-pattern instances at [ADR-011](DECISIONS.md#adr-011) Decision 4. Verify-pass on this PR caught the missing-ADR process gap that triggered ADR-015.

**PR #63 `meta/adr-015-framework-lock`** — landed ADR-015 (52 lines) in `DECISIONS.md`. Architect-originated; Sec joint-reviewed at v2 (two amendments applied); F/CTO ratified.

**This PR `meta/post-adr-015-state-refresh`** — state-ledger refresh after ADR-015 lands:

- **WORKFLOW.md edits:** line 6 current-phase pointer (framework-coupling RESOLVED via ADR-015; Phase 2 Steps 1–10 complete; in-flight Phase 3 PRs noted); §Phase 2 status block (🟡 Steps 1–10 complete; Step 10 CLOSES by composition); Open Questions resolved entries for `Frontend framework choice` + `Design tokens format`; footer v1.33 → v1.36.
- **MILESTONES.md edits:** Last-updated refresh; Active Phase 2 work surface (Step 10 CLOSES); Coupling touchpoint (RESOLVED); Active Feature Status; three new Recent-activity entries (PR #63 ADR-015 lead + catch-ups for PR #60 ARCH system overview + PR #62 RT-26 / §4.2 fence).
- **CHANGELOG.md edits:** this v1.36 entry; header version count 41 → 42.

**Follow-up:** Phase 2 Step 10 hand-off to Visual Designer (notify framework + tokens-as-code closed); ARCH §4 Tech Stack write-up (Frontend framework + Styling rows + concrete SvelteKit server-source file-glob allowlist for RT-26 / §4.2).

---

### v1.35 — 2026-05-29

**Phase 2 Steps 4–9 complete — design system + `docs/DESIGN/` committed home ([ADR-014](DECISIONS.md#adr-014)).**

Team `phase-2-ux-design` carried Phase 2 from wireframes through the design system (HTML route; Figma MCP held as the escalation path; no Claude Design bridge reachable from Claude Code).

- **Step 4 — wireframes:** low-fi HTML wireframes for all 6 clusters + shell, F/CTO-approved.
- **Step 5 — UX→Visual handoff:** contract with ~45 screens + a consolidated component library; UX added INV-3 (breadcrumb / action-menu / chart-granularity chip-group).
- **Step 6 — gap-scan:** clean except the 2 INV-3 inventory gaps (routed to + resolved by UX).
- **Step 7 — mandatory palette/typography/dark checkpoint (F/CTO):** Palette **B (Restrained Semantic), refined** · **Inter + JetBrains Mono, Hybrid** · **dark plan-for** · attention **Canary-Yellow `#FFEF00`** (picked over neon-orange `#FFAD00` + true-yellow `#eaea00` via a live 3-way A/B/C, contrast-managed for WCAG-AA).
- **Step 8 — design-system spec applied across all 6 clusters;** the §2.3 non-goal fence held in the visual layer (semantic green/red scoped to actual performance only; `$ReAlloc`/`%Target` neutral; no progress/gauge/over-under/target-line).
- **Step 9 — two-tier token taxonomy:** named **primitive** tokens (`--color-*`) → **semantic aliases** (`--c-*`), no bare hex on the semantic layer (closes the recurring "can't find the token for that value" friction). Canvas resolved to a **barely-cool near-white** with pure-white cards, restoring the per-story bordered "window" regions (a prior literal-pure-white over-correction had flattened them).

**Process notes.** A multi-round stale-render was root-caused to Chrome caching the `file://` stylesheet (fixed via CSS inlining / `?v=` versioned links + a visible version stamp). Confirmed Claude Design (claude.ai/design) is browser-only with no MCP/API — not usable for agent-driven design from Claude Code.

**[ADR-014](DECISIONS.md#adr-014)** consolidates the visual foundation + barely-cool canvas + two-tier tokens + the `docs/DESIGN/` home decision (resolving the ADR-013 flow-artifact-home follow-up).

**PR `meta/phase-2-design-landing`:** establishes **`docs/DESIGN/`** (4th top-level doc alongside PRD/ARCH/SECURITY) populated with the design system (`tokens.css`/`screen.css`/`design-system-spec.md`/styled-screen HTML) + `flows/` + `wireframes/` (migrated from gitignored `temp/`) + ADR-014 + WORKFLOW Phase 2 status + MILESTONES + this entry. **Only Step 10 (tokens-as-code) remains — gated on the Phase-3 frontend-framework choice (ADR-012 coupling); Phase 2 sits at the framework-coupling pause.** Follow-up: normalize residual `temp/phase-2-*` cross-refs inside the migrated flow/wireframe markdown.

---

### v1.34 — 2026-05-28

**Phase 2 (UX & Design) Steps 1–3 complete — 6 flow clusters locked + Step 3 walk-through decisions ([ADR-013](DECISIONS.md#adr-013)).**

Phase 2 ran in parallel with Phase 3 per [ADR-012](DECISIONS.md#adr-012). UX Designer led the flow drill in team `phase-2-ux-design`; PM consulted at every cluster close; Security Reviewer consulted where security-load-bearing.

**All 6 PRD §2 clusters drilled into flow documents + locked (dependency order):** §2.4 cross-cutting (onboarding/manual-entry/re-auth) → §2.1 net worth → §2.2 asset allocation → §2.3 spending/income → §2.5 estimated taxes → §2.6 monthly report (convergence). Each closed via UX draft → PM traceability PASS → (Sec where applicable) → lock. Flow docs are gitignored working artifacts at `temp/phase-2-flows-*.md`.

**F/CTO decisions during the drill + Step 3 walk-through:**
- **PM-1 (§2.4):** "mark inactive" applies to Plaid accounts in V1 as a display/sync-pause flag; genuine un-share stays V2+ (Sec consult + re-verify PASS; 4 V1-SHIP-BLOCK flow items folded in).
- **D1 (global, ratified mid-drill):** §2.4.4 staleness-marking surface list is illustrative, not exhaustive — every derived aggregation consuming stale-account data carries the marker (Sec concurred: strictly-more-conservative).
- **Step 3 walk-through (2 sittings) + P1–P6 decision pass:** P1 persistent left sidebar · P2 number-first single-canvas Net Worth · P3 hybrid classification surfacing · P4 conditional top-chrome banner (clean-when-healthy) · P5 settings-UI-only planning-value editing (all four; no inline) · P6 category×period-table Cash Flow.

**[ADR-013](DECISIONS.md#adr-013)** consolidates D1 + P1–P6 (7 decisions) + the Phase-3 ARCH handoffs (A1–A4 inactive-Plaid lifecycle + wash-sale; H1 planning-value write-path under Lock-14 fence + §2.2 keyed-array validation; H2 as-of-date; nav-asof-timestamp; RT-13-tracks-D1; §2.6 injection invariants INV-1/INV-2; cash-flow seed catch-all recommendation). The ADR is the committed durable bridge for these handoffs since the `temp/` logs are gitignored.

**PR `meta/phase-2-step-3-adr`:** ADR-013 + WORKFLOW.md Phase 2 status (Steps 1–3 complete, Step 4 active) + MILESTONES Phase 2 progress + this CHANGELOG entry. **Step 4 (wireframing) is next** — UX produces wireframes from the locked flows + P1–P6; Visual Designer joins at the UX→Visual handoff for the design system + tokens. Follow-up: Phase 2 flow-artifact committed home (currently gitignored `temp/`) TBD per ADR-013.

---

### v1.33 — 2026-05-27

**Phase 1 → Phase 2 + Phase 3 parallel transition.** Phase 1 (Product Definition / PRD) closed 2026-05-26; Phase 2 (UX & Design) + Phase 3 (Technical Architecture) entered in parallel 2026-05-27 per [ADR-012](DECISIONS.md#adr-012).

**PR `meta/phase-2-3-entry` — phase-transition consolidated update.** Single PR landing all phase-transition artifacts via `/start-doc-update` + `/finish-doc-update` doc-update flow per [ADR-009](DECISIONS.md#adr-009) Decision 9:

- **WORKFLOW.md edits:** line 6 current-phase pointer rewrite (Phase 1 → Phase 2 + Phase 3 parallel); Phase 1 Status flip 🟡 Closing → ✅ Complete (cleanup the 5 close-work PRs missed); Phase 2 detailed-steps subsection (UX steps 1–5 flows + wireframes; Visual steps 6–11 design system + tokens — 11 numbered steps composed in team-mode); Phase 3 detailed-steps subsection (Architect steps 1–8); open-q resolution (background worker technology resolved at [ADR-011](DECISIONS.md#adr-011) Decision 17 / Lock 13 hybrid); footer v1.0 → v1.33; changelog stub pointer 37 → 39 entries.
- **DECISIONS.md edits:** [ADR-012](DECISIONS.md#adr-012) inserted between header and ADR-011 (terse pattern; documents the parallel-execution decision, alternatives considered, coordination expectations including pointer convention + framework-coupling fallback).
- **MILESTONES.md edits:** Current Phase block rewritten (Phase 2 + Phase 3 active surfaces; out-of-band entry-gate tasks; coupling touchpoint; team task trackers TBD until phase entry; outer category spans R+P); Active Feature block rewritten; Recent activity entry added; Last updated line bumped to 2026-05-27.
- **CHANGELOG.md edits:** this v1.33 entry; header version count 38 → 39.

**Phase-transition team `phase-2-3-entry` execution.** Team-lead spawned 3 teammates via `Agent(team_name="phase-2-3-entry", subagent_type=..., name=...)` per [ADR-003](DECISIONS.md#adr-003): `architect` (Phase 3 steps 1–8 draft); `ux` (Phase 2 steps 1–5 — flows + wireframes); `visual` (Phase 2 steps 6–11 — design system + tokens). All three teammates produced drafts in their owned-section scope; UX + Visual coordinated numbering via cross-teammate SendMessage DM before sending drafts back to team-lead. Drafts delivered within minutes of spawning (parallel execution).

**9 substantive flags walked one-by-one with F/CTO; all ratified at-recommend** with two minor reconciliations applied at edit-time: (1) **Flag 8 reconciliation** — UX's two-path framework-slip fallback (pause OR emit framework-agnostic intermediate format like Style Dictionary / W3C design-tokens JSON) overrides Visual's pause-only at Phase 2 Step 10; (2) **Flag 9 reconciliation** — [ADR-012](DECISIONS.md#adr-012) pointer convention (header pointer stays at "Phase 2 + Phase 3 parallel" until both close) overrides Visual's "advance pointer to Phase 4 on Phase 2 exit" at Phase 2 Step 11; "CoS-as-team-lead" terminology drift dropped per [ADR-009](DECISIONS.md#adr-009) Decision 1.

**Substantive Phase 2 + Phase 3 process locks emerged from the flag walk:** Phase 3 ARCH §-by-§ sequencing is dependency-order not scaffold-order (Task #26 before #36; #32 after #35 per [ADR-011](DECISIONS.md#adr-011) Consequences); Sec joint-review codified MANDATORY at every architectural surface (Data model / Plaid / Auth / Workers / Security model — protects against future Architect-only drift; Step 4 surfaced 8 chain-attack catches Architect's drills missed at joint reviews); Phase 2 §2.4 cross-cutting drilled FIRST not PRD-numeric (foundation-first; matches Phase 1 sequential-discovery lesson); F/CTO flow walk-through gate non-skippable + 2-sitting default per `feedback_late_phase_density_overload`; navigation-model + info-hierarchy decisions become DECISIONS.md ADRs; mandatory palette + typography F/CTO checkpoint with dark-mode disposition codified at Phase 2 Step 7.

**Phase 2 + Phase 3 closing semantics.** Both phases close together at Phase 4 (Project Scoping) entry gate per [ADR-012](DECISIONS.md#adr-012). WORKFLOW.md header pointer stays at "Phase 2 + Phase 3 (parallel)" until both close. Individual phase sections advance their own Status independently (each can mark ✅ Complete in its section before the other). Phase 4 pointer activates only when BOTH phases close.

**Out-of-band entry-gate tasks** (carry into Phase 2 + Phase 3 work surfaces): (1) Plaid production-tier monthly minimum sales/onboarding call (F/CTO driven; per [ADR-011](DECISIONS.md#adr-011) Decision 20; only load-bearing cost-target unknown; non-blocking for ARCH drafting but blocks any Phase 3 lock dependent on Plaid production-tier shape); (2) candidate P3 PM consult on FMP/stock-screening incumbent-exceeds-V1 surface (per `feedback_incumbent_exceeds_v1_review`; needed BEFORE Phase 3 ARCH drafting touches `pfin_back_etl` ingestion architecture).

---

### v1.32 — 2026-05-26

**Phase 1 Step 4 architectural drilling cycle + close-work — Phase 1 → ✅ COMPLETE.**

Active drilling cycle 2026-05-25 → 2026-05-26 ratified 16 substantive architectural locks + 4 cross-cutting project-convention meta-patterns + candidate P3 disposition + Lock 9 amendment under the Architect-lead + Sec-joint-review + F/CTO-ratification pattern (ADR-003 team-mode in team `phase-1-step-4`).

**16 locks closed across 5 waves:**

- **Wave 1 (alphanumeric + foundational):** Lock 1 / Flag #1 Multi-tenant + RLS Option A baseline; Lock 2 / Flag P2 `account_users` V1-dormant; Lock 3 / Flag E1a `account_trans` RLS Option B; Lock 4 / Flag #2 Plaid integration Option C hybrid; Lock 5 / Flag E2 `acct_number` masked-only; Lock 6 / Flag P1 `users_id` schema rename; Lock 7 / Flag #3 taxonomy migration Option A; Lock 8 / Wave 1 step 2 / Flag #10 + #12 NAV materialization + CPI ingestion.
- **Wave 2 (money correctness):** Lock 9 / Flag #4 dedup + reconciliation (Addendum 2 + 6 Sec mods including first instance of §8 cross-tenant FK-bypass family); Lock 10 / Flag #5 `account_trans` immutable + reverse-and-replace (§7 immutable INSERT-new-version discipline ratified).
- **Wave 3 (snapshot store):** Lock 11 / Flag #6 `monthly_report` Option B with 9 Sec mods (INTEGER[] matched-tenant trigger as §8 third instance); Lock 12 / Flag #7 snapshot-vs-live render Option A child table with 8 Sec mods (§8 fourth instance + Sec's 5th chain-attack catch via parent immutability extension).
- **Wave 4 (workers + settings + as-of-date):** Lock 13 / Flag #8 background-worker architecture Option C hybrid (`pfin_back_etl` + V1 app + Node PDF worker) with 10 Sec mods (§10 defense-in-depth meta-pattern emerged); Lock 14 / Flag #9 settings store Option B per-domain tables with 9 Sec mods including `updated_at` trigger addendum; Lock 15 / Flag #13 as-of-date Option A with 9 Sec mods + Lock 9 amendment re-introducing `account_trans.created_at` (§10 schema-level orthogonality awareness).
- **Wave 5 (cost-feasibility synthesis):** Lock 16 / Flag #11 Outcome 1 ≤$50/month target holds (after F/CTO clarification reframed FMP/Plaid as fixed-cost + Hetzner cax21 baseline) + FMP path (a) keep starter + candidate P3 V1-default disposition (stock-screening ingestion continues; no V1 UI).

**4 project-convention meta-patterns ratified as ADR-011 Decisions 1-4:** §6 privileged-context-write discipline (Locks 4/7/11/13); §7 immutable + INSERT-new-version for audit-class surfaces (Locks 9/10/11); §8 cross-tenant FK-bypass family + matched-tenant validation (4 V1 instances Locks 9/10/11/12); §10 defense-in-depth fencing across surface boundaries + schema-level orthogonality awareness (Locks 13/14/15).

**Sec found 23+ V1-ship-blockers across reviews; 8 chain-attack catches Architect's drills missed.** All surfaced via joint-review pattern. F/CTO ratification interventions materially load-bearing on three locks (Flag #11 cost reframe v1→v1.1; Lock 14 mod #9 amend; Lock 15 mod #2/5/7/7b amend).

**Step 4 close-work landed across 5 stacked PRs:**

- **PR #51** — ADR-011 consolidation (186 lines added to DECISIONS.md covering 4 meta-pattern Decisions + 16 per-lock Decisions) + MILESTONES drilling-cycle narratives.
- **PR #52** — §SECURITY tables: SD matrix 14→23 expansion (+9 entries; +4 row revisions); RT catalog 15→25 expansion (+10 entries including RT-21 HIGH-severity NEW V1 test; RT-09/RT-10/RT-13 amendments).
- **PR #53** — §SECURITY §4.x prose annotations: §4.2 webhook-bypass + scheduled-poll + V2+ tax-API ingestion; §4.3 Coolify-container-boundary + infrastructure-layer fence framing; §4.6 PCI-DSS scope posture + audit-class family inventory (5-nested-bullet structure).
- **PR #54** — PRD §7.3 V1-dormant `account_users` bullet per Lock 2 / Flag P2 / `feedback_incumbent_exceeds_v1_review` guardrail.
- **PR #55** — BACKLOG V2+ entries (FMP cost-saving levers + stock-screening UI + Hetzner escalation path + live-tax-API privileged-context-write annotation) + WORKFLOW.md Step 4 lessons-learned subsection + MILESTONES Phase 1 → ✅ COMPLETE state + this CHANGELOG entry.

**Pacing per `feedback_late_phase_density_overload`:** original PR plan was 4 PRs; PR 2 split into PR 2a (tables) + PR 2b (annotations) per F/CTO direction; PR 3 scope reduced (Lock 6 `users_id` sweep deferred to Phase 3 Task #16); each PR independently reviewable; stacked-PR dependency graph (#51 → #52 → #53 → #54 → #55).

**13 Phase 3 carry-over tasks booked in team tracker `phase-1-step-4`** (#11/#13/#15/#16/#17/#20/#26/#29/#32/#33/#34/#35/#36 — full per-lock Sec-mod descriptions at `temp/step-4-locks-log.md` gitignored authoritative state file).

**Five new memory entries this drilling cycle:** `feedback_team_mode_default`, `feedback_incumbent_exceeds_v1_review`, `feedback_horizontal_rule_after_fcto_input`, `reference_pfin_back_etl`, `reference_hetzner_cax21`.

**Meta-process M0 (Research / PRD lock) → ✅ COMPLETE 2026-05-26.** M1 (Plan / ARCH + SECURITY docs) becomes Active at Phase 3 entry per the phase-transition prompt invocation at `docs/handoff-prompts.md`. Architect Phase 3 consumes ADR-011 + locks log + 13 carry-over tasks. Plaid production-tier monthly minimum sales call is the only out-of-band Phase 3 entry-gate task (per ADR-011 Decision 20 / Lock 16).

---

### v1.31 — 2026-05-23

**PR #[TBD] — Task #10 changelog extraction.** Pulled all v0.1–v1.30 entries (~1278 lines) out of `WORKFLOW.md` into this `CHANGELOG.md` file at repo root per [ADR-009](DECISIONS.md#adr-009) Decision 6 (orthogonal extraction; resolves the auto-load bloat where `WORKFLOW.md` exceeded Read's 256 KB byte-limit at ~71% changelog content).

`WORKFLOW.md` dropped from 2047 lines / ~298 KB to ~780 lines / ~75 KB. A small `## Changelog` stub remains at `WORKFLOW.md` pointing here. No content changes to version entries — verbatim moves.

`CLAUDE.md` updated to add `CHANGELOG.md` as version-history artifact (consult-on-demand; not in auto-load set per the [ADR-009](DECISIONS.md#adr-009) Decision 6 compact-ledger model — `MILESTONES.md` is the auto-load anchor once it exists).

Orthogonal to the PRD-conversion PR sequence (PR A merged at #40; PR B + PR C still pending). No cross-reference retargeting required across other files — existing memory/text references to "WORKFLOW.md changelog" or "see v1.NN" remain interpretable since version numbers + dates are preserved verbatim.

### v1.30 — 2026-05-20

**PR #[TBD] — Phase 1 Step 3.5 post-rewrite verify pass closure.** Final Step 3.5 deliverable. Walks the 17-entry Q7 = γ verify-pass queue accumulated across PR 4–9 + v1.19 kickoff; produces 3 surgical PRD edits + closure documentation. **Step 4 (Architectural overview consult; Architect lead; Phase 3 entry gate) opens after PR 11 merge.** Phase 1 starts closing after Step 4 ratifies.

**Verify-pass shape and joint-merge.** At agenda-build time, PM surfaced **3 substance-duplicate pairs** (v1.19 candidates #1/#2/#3 are substantively identical to PR-5-VP-§4-1/2/3 — PR 5 / §4 rewrite re-surfaced v1.19's §4.x concerns rather than netting new ones). F/CTO Q-meta = α applied joint-merge, compressing the queue from 17 → **14 distinct gates** for the walk-through.

**Walk-through totals (14 gates)**

| Disposition | Count | VPs |
|---|---|---|
| **α — confirm as-locked / retire as already-resolved** | 11 | VP-1+11, VP-3+13, VP-4 (resolved at PR 7), VP-5 (resolved at PR 5), VP-6, VP-7, VP-9, VP-10 (resolved at PR 7), VP-14, VP-16, VP-17 |
| **β′ — surgical edit + architectural side-constraint (Sec consult)** | 1 | VP-2+12 joint (§4.3 b1 + §4.5 RT-13) |
| **β — surgical edit (editorial)** | 2 | VP-8 (§3.1 ¶1 paraphrase); VP-15 (§5 prelude §6-contrast list) |

**11-for-14 α; 3 surgical-edit gates (1 β′ + 2 β); 0 γ (no ADR amendments commissioned).** Sec hard-line preserved on ADR-008 Decision 3 critical-tier (V1-block test count stays at 2: RT-02 + RT-05).

**VP-6 — highest-leverage substance gate; resolved α (false positive).** PM flagged tension between §8.1's "illustrative-not-normative" framing of V1.0/V1.1 sub-versions vs. ADR-004's actual commitment. Direct read of ADR-004 source (DECISIONS.md L353 + L484 + L644) cleared the tension: ADR-004 itself uses deferring language ("specific sub-version sequencing remains Phase 4 work"; "natural split is V1.0 = manual balances + Plaid"). §8.1's framing matches ADR-004's intent verbatim. No tension exists. PM's flag was overcautious; verify-pass caught and cleared without an unnecessary ADR amendment.

**VP-2+12 — Sec consult; β′ resolution.** PM flagged whether §4.5 RT-13 (cross-tenant staleness-state-read leak) high-severity classification accounts for §2.6.5 banner account-name string exposure dimension. F/CTO ratified δ (Sec consult) before deciding. `sec-rt13-severity@phase-1` teammate delivered consult recommending **β′ — β with hard architectural side-constraint** (Sec lane, ADR-008 Decision 1+2+3 + agent definition). Sec findings: (i) account-name not enumerated as distinct sensitive-data class in §4.4; implicitly carried by SD-00 (high) + denormalized into SD-12 (high, tenant-scoped-derivative); closest explicit analog is SD-01 (medium, signal-correlation framing); (ii) under snapshot-sourced-name architectural reading, attacker observes only credential-state boolean (not account-name strings) — failure-mode is signal correlation, not data exposure; (iii) PRD does not explicitly commit on snapshot-sourced vs live-sourced banner name resolution — material architectural ambiguity that β′ closes by locking snapshot-sourced as V1 Sec posture. **Sec recommended against γ** (elevate RT-13 to critical): would dilute the critical-vs-high boundary (which ADR-008 deliberately reserves for credential and financial-data exposure paths), require RT-08c/RT-09/RT-10 reclassification for rubric consistency, and trade Sec hard-line preservation for a broader-but-less-defensible critical tier. F/CTO ratified β′. **Sec hard-line preserved.**

**3 PRD surgical edits applied (β′ + 2 β)**

- **VP-2/12 §4.3 b1** — expanded rationale to explicitly address §2.6.5 account-name dimension under signal-correlation framing; locked Architect Phase 3 side-constraint that banner's account-name string MUST resolve from requesting tenant's SD-12 snapshot, not from any live join surface against §2.4.4; reaffirmed high-severity under ADR-008 Decision 3 with the dimension explicit.
- **VP-2/12 §4.5 RT-13 row** — clarified that test scope includes verifying no cross-tenant account-name string surfaces on the banner, in addition to staleness-state boolean.
- **VP-8 §3.1 ¶1** — replaced quoted §1.2 text (paraphrase-not-verbatim post-PR 2) with paraphrase attribution citing §1.2's V1-done definition; dropped quotation marks; preserved substantive cross-reference.
- **VP-15 §5 prelude** — replaced 5-axis parenthetical list (advisor / public sign-up / money movement / real-time quotes / mobile-native; was partially stale post-ADR-007 TLH addition) with reference to §6 canonical enumeration ("see §6 for the full axis enumeration — five permanent product-identity axes per ADR-002 §3.0 + ADR-007"). Eliminates duplication + staleness vector.

**Adjacent Sec-flagged items from VP-2/12 consult** (surfaced for Step 4 + Phase 3 + future-PRD scoping)

- **(A)** Architecture ambiguity on banner account-name resolution path — closed by β′ surgical edit text.
- **(B)** Cross-§2 staleness-marker test coverage. §4.5 has no explicit test for §2.1–§2.5 consuming-surface staleness-marker render paths at cross-tenant collision-case shape. Low-likelihood gap given unified-query shape on those surfaces; **flag for Step 4 Architect-consult follow-up** if Architect's planned implementation introduces a join-shape similar to §2.6.5's.
- **(C)** Classification-consistency confirmation: β′ framing aligns with SD-01 + SD-11 canonical Sec posture at §4.4 lock.
- **(D)** Sec hard-line preservation rationale: keeping critical count at 2 preserves the narrow credential/financial-data boundary the hard-line's defensibility derives from.

**Already-resolved entries formally retired (3)**

- **VP-4** — §6.3 TLH information-vs-prescription axis elevation; resolved at PR 7 / §6 rewrite (v1.26).
- **VP-5** — §7.2 V1 RLS verification scope; resolved at PR 5 / §4 rewrite (v1.23) via RT catalog two-tenant-fixture framing + §4.1 b5 scale-dimension routing.
- **VP-10** — §3.5/§6 boundary clause consistency; resolved at PR 7 / §6 rewrite (v1.26) via §6 prelude mirror.

**Closure framing**

- **Step 3.5 substantively complete and now verify-pass-closed at v1.30.** All 14 distinct VP gates walked. 3 surgical edits applied. 0 ADR amendments. Sec hard-line preserved on ADR-008 Decision 3.
- **Q7 = γ queue closed**; no items deferred to Step 4 / Phase 3 (except the (B) adjacent flag explicitly Architect-consult-routed).
- **Step 4 entry gate now open** after PR 11 merge. Step 4 consumes the 87 active App B forward-pointers + §4.4 sensitive-data matrix + §4.5 RT catalog (with the β′ RT-13 update) + §8 → Phase 4 handoff anchor.
- **Phase 1 closes** after Step 4 ratifies. **Phase 2 (UX/Visual)** becomes available; PM hands off to Architect.

**Team-mode operational notes**

- `pm-vp-agenda@phase-1` produced the 17-entry inventory + disposition recommendations.
- `sec-rt13-severity@phase-1` delivered the VP-2/12 Sec consult and recommended β′.
- **Memory pattern `feedback_team_mode_idle_before_deliverable` validated four times across this session** (PR 8 / PR 9 / PR 10 / pm-vp-agenda). Diagnostic-ping resolution worked cleanly each time.
- Sec teammate idled with sign-off-in-the-same-message; no idle-before-deliverable event for the Sec consult (cleanest dispatch of the session).

**No new ADR.** Verify-pass produced 0 ADR amendments. Sec considered γ (ADR-008 Decision 3 amendment) but recommended against; F/CTO ratified Sec's β′ recommendation. **Step 3.5 closes with zero new ADRs across the entire 11-PR sequence** (10 §-rewrite + closure PRs + this verify-pass closure).

---

### v1.29 — 2026-05-19

**PR #[TBD] — Phase 1 Step 3.5 PR 10 / Step 3.5 closure (overview refresh + Appendix B consolidation + housekeeping).** Closure PR for Step 3.5 editorial rewrite sequence. **Structurally distinct from PR 2–9 §-rewrite PRs**: PR 10 adds new top-level content (overview/preamble, Appendix B body, Appendix A defer-note) and applies 12 in-body italic-marker surgical edits across §2.1 / §2.2 / §2.3 / §2.4 / §2.5 / §2.6 / §3 / §4 / §5 / §6 / §7 / §8. After PR 10 lands, **post-rewrite verify pass** (Q7 = γ queue 17 entries) gates **Step 4 entry** (Architectural overview consult; Architect lead). Phase 1 starts closing after Step 4 ratifies.

**Critical audit finding (PR 10 structure proposal).** Appendix B consolidation surface was **~114 entries, NOT the 19-entry post-PR-9 running total** the PR 10 brief initially framed. The "19 entries" framing was a counter convention the changelog established at PR 7 / v1.26, anchored on "6 entries post-PR-6" without back-summing PR 3 (73 entries from §2.1–§2.6 routing-flag blocks) / PR 4 (6 entries) / PR 5 (16 entries). All 12 in-body italic markers across §2.1–§8 explicitly stated "see Appendix B (created in PR 10; pending consolidation)"; consolidating only 19 entries would have left 95 markers dangling against a partial App B body — re-creating the forward-pointer-without-closure problem Step 3.5 closed. **F/CTO Q-S1 = α (full consolidation)** addressed the audit finding directly.

**Structure-gate decisions (Q-S1 through Q-S8)**

| Q | Locked answer | PM recommendation |
|---|---|---|
| Q-S1 | **α** — full ~114-entry consolidation | α |
| Q-S2 | **α** — by source-§ shape | α |
| Q-S3 | **β** (F/CTO override) — include tight PRD overview/preamble (~12 lines) before §1 | α (out of scope) |
| Q-S4 | **α** — symbolic-ref convention extended to App B entries per PR 9 Q-S7 precedent | α |
| Q-S5 | **β** — defer Appendix A consolidation with explicit italic note under heading | β |
| Q-S6 | **α** — consistent type-tag prefix (`[Architect Phase 3]` / `[Sec V2-implementation]` / `[Architect / Sec joint]` / `[Boundary note]` / `[Closure-trace process-record]`) | α |
| Q-S7 | **α** — inline `[RESOLVED-AT-§X]` tag on closure-trace entries alongside type-tag | α |
| Q-S8 | **α** — update 12 in-body italic markers to drop "(created in PR 10; pending consolidation)" qualifier | α |

**7-for-8 PM acceptance; 1 F/CTO override at Q-S3 = β.**

**5-tag classification convention.** PM introduced a fifth tag value `[Architect / Sec joint]` during body draft (12 entries: §2.3 (d)(f), §2.4 (b)(g)(h)(j)(k), §2.6 (m)(n)(p)(q)(r), §4 (a)(b)(c)(i)(j)) on top of the four enumerated in Q-S6 = α. F/CTO ratified the 5-tag scheme at Q-B1 = α; without it, joint flags would collapse to either Architect-only (losing Sec dimension) or Sec-only (mis-classifying as V2-gate).

**App B consolidation totals (114 entries)**

| Source-§ | Entries | Source PR |
|---|---|---|
| §2.1 | 5 | PR 3 / v1.21 |
| §2.2 | 7 | PR 3 / v1.21 |
| §2.3 | 11 | PR 3 / v1.21 |
| §2.4 | 12 | PR 3 / v1.21 |
| §2.5 | 17 | PR 3 / v1.21 |
| §2.6 | 21 | PR 3 / v1.21 |
| §3 | 6 | PR 4 / v1.22 |
| §4 | 16 | PR 5 / v1.23 |
| §5 | 6 | PR 6 / v1.24 |
| §6 | 3 | PR 7 / v1.26 |
| §7 | 5 | PR 8 / v1.27 |
| §8 | 5 | PR 9 / v1.28 |
| **Total** | **114** | — |

**Classification breakdown (114 entries)**

- **`[Architect Phase 3]`** — 65 entries. Largest category; dominates §2.x + §4.
- **`[Architect / Sec joint]`** — 12 entries. Joint Phase 3 + mandatory Sec PR-time review.
- **`[Sec V2-implementation]`** — 4 entries. Consolidated V2-ship-gate inventory.
- **`[Boundary note]`** — 6 entries. Forward-operative cross-§ documentation markers.
- **`[Closure-trace process-record]`** — 27 entries. Resolved at downstream §-locks; preserved for traceability.

**Resolved-vs-active counts**

- **Active forward-pointers:** 87 (65 + 12 + 4 + 6) — primary payload for Architect Step 4 + Phase 3 consumption.
- **Resolved process-records:** 27 — historical record; filterable via `[RESOLVED-AT-§X]` tag.

**Symbolic-ref conversion sweep (Q-S4 = α)**

- Zero `PRD.md:NNN` numerics remain in Appendix B. ~14 in-body section refs converted to symbolic form during lift (primarily §2.2 / §2.3 line-NN refs to "§X routing flag (Y)" form).
- DECISIONS.md numerics preserved verbatim per PR 9 Q-S7 scope ruling.

**Line-count outcome**

- PM α projection: ~291–401 lines net PRD growth under Q-S1 = α + Q-S5 = β + Q-S8 = α.
- Q-S3 = β override added ~12 lines for overview.
- **Realized:** PRD.md grew from 1340 → 1610 lines (+270 lines / +20%). Within projected range.

**Pattern divergence — PR 10 is structurally distinct from PR 2–9.** PR 2–9 were §-rewrite PRs (replace §N body, preserve substance). PR 10 is a closure / consolidation PR (add new top-level content, lift entries verbatim, apply housekeeping surgical edits). **Verbatim-lift attestation surface** replaces the §-body-rewrite attestation: every App B entry's substance is preserved from its source location with symbolic-ref conversion + classification-line addition.

**Acceptance-flag recap (PR 10 / Step 3.5 closure)**

- **Step 3.5 substantively complete as of 2026-05-19** (per PR 10 merge). Step 3.5 produced: archived PRD-v1.18 source; 8 §-rewrite PRs (§1 → §8); closure PR 10 with App B consolidation (114 entries), PRD overview/preamble (NEW per Q-S3 = β), Appendix A defer-note, and 12 in-body marker updates. **PM-lean track final: 30-for-38 across Step 3.5.** Eight F/CTO overrides — six β at structure gates (PR 3 Q-S4, PR 4 Q-S2, PR 5 Q-S5 γ, PR 6 Q-S2, PR 8 Q-S6, PR 9 Q-S6, PR 10 Q-S3) + two α-extended (PR 9 Q-S7) + one β at PR 10 Q-S3.
- **No new ADR for PR 10.** Verbatim consolidation only. **Step 3.5 produced zero new ADRs by construction** (presentation-only restructure); the only ADR-related event was the §1 substance amendments at PR 2 / v1.20 under §1's still-mutable carve-out (Amendment C was a PRD-internal rename with zero DECISIONS.md occurrences).
- **Substance verify-pass (Q7 = γ) queue total: 17 entries** carried forward. PR 10 surfaces zero new VP candidates (verbatim consolidation; no substance discrepancies during lift). **Verify-pass resolution is explicitly outside PR 10 scope.** Post-PR-10 sequence: (i) verify pass opens; (ii) each VP entry walked; (iii) any substance issue lands as ADR amendment; (iv) Step 4 (Architectural overview consult) opens after verify pass closes; (v) Phase 1 closes after Step 4 ratifies; Phase 2 (UX/Visual) becomes available.
- **Post-PR-10 in-body markers point exclusively to consolidated Appendix B.** 12 markers updated per Q-S8 = α; zero references to "pending consolidation" remain in PRD body. **The Step 3.5 forward-pointer-without-closure pattern closes at PR 10 merge.**
- **Step 4 entry payload:** 87 active forward-pointers (65 Architect + 12 Architect/Sec joint + 4 Sec V2-implementation + 6 boundary notes) + §4.4 14-class sensitive-data matrix + §4.5 15-row RLS test catalog + §8 → Phase 4 handoff anchor (Appendix B → §8 routing flag (d)). Step 4 produces ARCHITECTURE.md as Phase 3 entry payload.

**Team-mode operational note (fourth dispatch under v1.25 convention)**

- `pm-pr10-structure@phase-1` teammate handled both structure proposal and body draft turns. Third consecutive idle-before-deliverable timing event surfaced (idle notification arrived without sign-off; `ls` showed only structure proposal); resolved via diagnostic ping per `memory/feedback_team_mode_idle_before_deliverable.md`. **Memory pattern validated three times** across PR 8 / PR 9 / PR 10. The largest body draft of Step 3.5 (~280-line App B body + overview + recap + 12 marker triples + v1.29 changelog) completed cleanly with the diagnostic-ping resolution.

**Substance preservation**

- 0 substance amendments. Verbatim-lift consolidation only. Every App B entry byte-equivalent to its source after symbolic conversion + classification-line addition.
- ~14 symbolic-ref retargets applied across App B entries.
- 12 in-body italic-marker surgical edits applied; zero §-body content changed.

**No new ADR.** PR 10 is presentation/consolidation only; follows PR 2–9 precedent. **Step 3.5 closes with zero new ADRs across the entire 10-PR sequence.**

---

### v1.28 — 2026-05-19

**PR #[TBD] — Phase 1 Step 3.5 PR 9 / §8 (V1 milestone framing) rewrite.** Sixth bulk-closeout PR under Step 3.5 cadence (continues PR 8 / §7 + PR 7 / §6 + PR 6 / §5 + PR 4 / §3 + PR 2 / §1). PM continues as primary author from PR 6–8. **§8 is the last PM-led drafting task in Phase 1 Step 3** — post-§8 lock, only PR 10 (overview / appendices / Appendix B consolidation) remains for Step 3.5 closure, then post-rewrite verify pass gates Step 4 entry. **Third PR to invoke a F/CTO β override at structure gate** (parallel to PR 8 / §7 Q-S6 = β at §7.3 b2 + PR 6 / §5 Q-S2 = β broad shape-discipline sweep; PR 9's β scope is also single-bullet-narrow at §8.3 b3). **First PR to invoke a F/CTO α-extended override at cross-ref retarget gate (Q-S7)** — symbolic conversion of all `PRD.md:NNN` numeric refs in §8 body to future-proof against further line drift in PR 10. **First PR to surface a section-drift cross-ref correction** (§1.3 → §1.4 V1-correctness content relocation during PR 2 / §1 rewrite, surfaced and corrected at PR 9 / §8 Q-S7 audit — would have propagated into Step 4 Architect consult if missed).

**Section rewritten**

- **§8** (V1 milestone framing) — 3 sub-sections preserved (§8.1 V1 sub-version convention / §8.2 Drop-replace migration pattern / §8.3 V1-done cross-reference and Phase 4 handoff) per Q-S1 = α source-order parity.
- Source: `docs/archive/PRD-v1.18-source.md` §8 (lines 1039–1084; 46 inclusive body lines including 0 blockquote lines).
- Rewritten: `PRD.md` §8 (L1145–1181, 37 lines including foot markers; ~28 visible body content lines excluding markers + blank padding; net body-line compression of **-39%** under α-for-α/N-A/α/α/α/β/α-extended structure-gate ratify with §8.3 b3 β extraction adding ~4 sub-bullet lines).

**Structure-gate decisions (Q-S1 through Q-S7)**

| Q | Locked answer | PM recommendation |
|---|---|---|
| Q-S1 | **α** — bulk-closeout cadence | α |
| Q-S2 | **N/A** — no blockquotes in §8 source (convention trivially satisfied) | N/A confirmation |
| Q-S3 | **α** — §8 prelude tightened (process-record drop + ADR-rationale compress); §8.1 prelude tightened (ADR-004 rejected-alternatives compress); §8.2 + §8.3 sub-§ preludes verbatim | α |
| Q-S4 | **α** — 5 routing flags (a)–(e) → App B; all boundary-notes (4 resolved-closure-trace + 1 forward-operative handoff anchor) | α |
| Q-S5 | **α** — 6 process-record acceptance flags (b2–b7) → WORKFLOW.md `Acceptance-flag recap (PR 9 / §8)` block; b1 dropped as redundant with routing flag (d) | α |
| Q-S6 | **β** (F/CTO override) — extract §8.3 b3 (Phase 4 handoff) into 4 sub-bullets (i)–(iv); §8.1 b3 / §8.1 b4 / §8.2 b2 / §8.3 b1 surfaced as candidates but preserve verbatim per single-bullet-narrow scoping (mirrors PR 8 Q-S6 = β shape) | α |
| Q-S7 | **α-extended** (F/CTO override) — symbolic conversion of all `PRD.md:NNN` numeric refs in §8 body (4 distinct refs × 10 instances: `PRD.md:689` × 3 → "§3.4 closing line" / "§3.4 → §8 forward-pointer" / dropped where redundant; `PRD.md:47` × 3 → "§1.4 V1 existing-system-replacement test bullet" / "§1.4 → §8 forward-pointer" **with §1.3 → §1.4 section-drift correction**; `PRD.md:808` × 2 → dropped, "§4.6 shadow-workflow tear-down cross-reference" carries pointer; `PRD.md:805` × 2 → dropped, "§4.6 availability posture" carries pointer). DECISIONS.md numeric refs preserved verbatim per F/CTO scope ruling | α (numeric retargets only) |

**5-for-7 PM acceptance; 2 F/CTO overrides at Q-S6 + Q-S7.**

**Q-S7 convention divergence flag.** PR 9 is the first PR to convert PRD.md numeric refs to fully symbolic form within a §-body. Prior PRs (PR 4–8) kept PRD.md numerics verbatim and accepted post-rewrite drift as bookkeeping. F/CTO chose Q-S7 α-extended to future-proof against further line drift in PR 10 / overview consolidation; future PRs touching cross-ref-dense surfaces may continue this convention or revert to numeric form at F/CTO discretion. **DECISIONS.md numerics remain in body verbatim** — DECISIONS.md is a stable append-only ADR ledger; numeric drift is structurally constrained.

**β extraction sweep — 1 extraction (single-bullet scope)**

- Systematic sweep across 10 source body bullets. 4 strong candidates surfaced at structure proposal (§8.1 b3 V1.final 3-criteria; §8.1 b4 "shippable in framing terms" 3-element; §8.2 b2 §4.6 tear-down 4 quoted commitments; §8.3 b1 §3.4 3-criteria restated; §8.3 b3 §8 → Phase 4 (i)–(iv)).
- **1 bullet extracted per F/CTO Q-S6 = β override:** §8.3 b3 (§8 → Phase 4 handoff boundary). 4 Phase 4 territory items lifted into 4 sub-bullets: (i) Criterion-to-sub-version mapping; (ii) Per-sub-version capability boundaries; (iii) Dependency ordering across §2 / §4 / §7 surfaces; (iv) Per-sub-version acceptance criteria at one-session-granularity per Linear issue convention. Lead bullet framing (§8 → Phase 4 handoff boundary + ADR-004 `DECISIONS.md:353` verbatim cite) preserved.
- **9 bullets preserved verbatim** per F/CTO single-bullet-narrow scoping.

**App B running total post-PR 9 = 19 entries**

- PR 9 adds 5: (a) §3.4 → §8 forward-pointer closure at §8.3 + (b) §1.4 → §8 forward-pointer closure at §8.3 (with §1.3 → §1.4 section-drift correction noted) + (c) ADR-002 §7.0 gap #4 milestone-framing dimension closure at §8.3 + (d) §8 → Phase 4 / Linear backlog handoff anchor + (e) §8 ↔ §4.6 cross-reference shape.
- Running total: 14 (post-PR 8) + 5 (PR 9) = 19.

**Q7 verify-pass queue total post-PR 9 = 17**

- No PR-9-VP candidates added (VP-§8-1 wording-fidelity check resolved inline by Q-S7 α-extended scope).
- Running queue: 17 (post-PR 8) + 0 (PR 9) = 17.

**Acceptance-flag recap (PR 9 / §8)**

- **§8 locked 2026-05-19** (per PR 9 merge). Per-sub-§ locks: §8.1 (1 framing paragraph + 4 bullets covering V1.0 / V1.x / V1.final / "shippable in framing terms"; illustrative V1.0 = Plaid+balances and V1.1 = full manual transaction entry examples preserved as illustrative-not-normative per ADR-004); §8.2 (1 framing paragraph + 3 bullets covering drop-replace mechanic / §4.6 tear-down cross-reference / §4.6 availability + §2.4.4 non-silent-staleness cross-reference); §8.3 (1 framing paragraph + 3 bullets covering §3.4 criteria reciprocation / §1.4 forward-pointer closure / §8 → Phase 4 handoff with (i)–(iv) sub-bullet extraction per Q-S6 = β). No Sec at-lock pass required (no credential / auth / new posture surface). No Architect at-lock pass required (framing-shaped, no V1 architecture surface). Five boundary-note routing flags (a)–(e); zero Architect flags; zero Sec flags; zero V1-block flags either side. Smallest routing-flags block of any locked PRD section to date (5 boundary notes).
- **No new ADR for §8 lock.** All §8 content is verbatim-derivable from ADR-004 (`DECISIONS.md:353`); the sub-version convention, drop-replace mechanic, and §3.4 V1-done cross-reference are explicit ADR-004 commitments. §8 is the PRD-side surfacing of ADR-004's milestone framing, not a new scope decision. Joins §3 / §6 / §7 in the "no-new-ADR lock" pattern; §8 is the fourth such instance.
- **No cross-section surgical edits at §8 lock.** §3.4 closing line and §1.4 V1 existing-system-replacement test bullet are already correctly forward-shaped; §8.3's reciprocation closes both forward-pointers without requiring upstream body edits. §4.6 cross-references at §8.2 are one-way (§8 → §4.6); no §4.6 body revision required. §8 is purely additive to upstream sections. **Section-drift correction note:** source-§8 referenced §1.3 V1-correctness; the V1-correctness content moved to §1.4 during PR 2 / §1 rewrite. Section-drift correction applied at §8.3 + routing flag (b) per PR 9 Q-S7 α-extended override; no §1.4 body revision required (§1.4 already correctly forward-shaped).
- **Forward-pointer closures at §8 lock:** (a) §3.4 → §8 closes at §8.3; (b) §1.4 → §8 closes at §8.3 (corrected from source §1.3 ref per Q-S7 α-extended cross-ref retarget); (c) ADR-002 §7.0 gap #4 milestone-framing dimension closes at §8.3 (§3.4 already closed the criteria dimension at §3 lock). Three forward-pointer closures + §8 → Phase 4 handoff anchor established at routing flag (d).
- **PM-lean track now 23-for-30** post-§8 structure gate + body bundle acceptance. **Sixth confirmed bulk-closeout-from-structure-proposal pattern** (§3 → §5 → §6 → §7 → §8 — PR 9 / §8 is the sixth in the bulk-closeout sequence and the fifth in the PM-author-from-PR-6 series). **Smallest realized PRD section by body line count to date** post-relocation (~28 body lines + 4 sub-bullets from §8.3 b3 β extraction; vs §7's 35 body lines, §6's 35).
- **§8 is the last PM-led drafting task in Phase 1 Step 3.** Post-§8 lock, PR 10 (overview / appendices / App B consolidation) remains for Step 3.5 closure. Then post-rewrite verify pass (Q7 queue 17 entries) gates Step 4 entry. All PM-led PRD sections (§1 substantively drafted; §2.1–§2.6 locked; §3 locked; §5 locked; §6 locked; §7 locked; §8 locked) are complete; §4 Sec-primary-author locked at PR 5; PRD substantive content surface is complete pending Phase 1 Step 4 architectural overview consult. **PM hand-off to Architect for Step 4 follows post-rewrite verify-pass closure.**

**Team-mode operational note (third dispatch under v1.25 convention)**

- `pm-pr9-structure@phase-1` teammate handled both structure proposal and body draft turns. Second consecutive idle-before-deliverable timing event surfaced (idle notification arrived without sign-off; `ls` showed empty); resolved via diagnostic ping (per `memory/feedback_team_mode_idle_before_deliverable.md` saved earlier this session) rather than corrective re-poke. PM responded with case (4) — done, signals out-of-order — and full sign-off message arrived shortly after. Memory pattern validated on second exercise.

**Substance preservation**

- 0 substance amendments beyond the authorized §1.3 → §1.4 content-correctness fix (Q-S7 α-extended scope; would have propagated incorrect cross-ref into Step 4 Architect consult if missed). All locks preserved (ADR-002 / ADR-004 / ADR-005 / ADR-006 / §3.3 / §3.4 / §1.4 / §2.1 / §2.4.4 / §4.1 / §4.6).
- 10 cross-ref retargets applied (Q-S7 α-extended scope; 4 distinct PRD.md:NNN refs × 10 instances). Zero PRD.md numerics remain in §8 body post-rewrite.
- 7 DECISIONS.md numeric refs preserved verbatim (`:353` × 3 + `:484` × 2 + `:644` shorthand × 2) per F/CTO Q-S7 scope ruling.

**No new ADR.** PR 9 is presentation-only; all content grounded in already-locked ADRs (ADR-004 primarily). Follows PR 2 / 3 / 4 / 5 / 6 / 7 / 8 precedent. Joins §3 / §6 / §7 in "no-new-ADR lock" pattern.

---

### v1.27 — 2026-05-19

**PR #[TBD] — Phase 1 Step 3.5 PR 8 / §7 (Constraints) rewrite.** Fifth bulk-closeout PR under Step 3.5 cadence (mirrors PR 7 / §6 + PR 6 / §5 + PR 4 / §3 + PR 2 / §1). PM continues as primary author from PR 6 + PR 7. **Second PR to invoke a F/CTO β override at structure gate** — Q-S6 = β narrowly scoped to §7.3 b2 (parallel to PR 6 / v1.24 invoking β at Q-S2 across the broader shape-discipline sweep; PR 8's β scope is single-bullet-narrow). **First PR to exercise the Acceptance-flag recap block convention** at the dedicated WORKFLOW.md location per PR 4 / v1.22 explicit precedent.

**Section rewritten**

- **§7** (Constraints) — 3 sub-sections preserved (§7.1 Cost / §7.2 Scale / §7.3 Usage model) per Q2 = β source-order parity.
- Source: `docs/archive/PRD-v1.18-source.md` §7 (lines 994–1037; 43 inclusive body lines including 0 blockquote lines).
- Rewritten: `PRD.md` §7 (35 body lines; net line-count compression of -8 lines / -19% under α-for-α/α/α/α/β structure-gate ratify).

**Structure-gate decisions (Q-S1 through Q-S6)**

| Q | Locked answer | PM recommendation |
|---|---|---|
| Q-S1 | **α** — bulk-closeout cadence | α |
| Q-S2 | **N/A** — no blockquotes in §7 source (convention trivially satisfied) | N/A confirmation |
| Q-S3 | **α** — §7 prelude tightened by single-phrase drop (cross-§-pattern meta phrase); sub-§ preludes verbatim | α |
| Q-S4 | **α** — 5 routing flags (a)–(e) → App B; mix of closing-trace + forward-operative entries | α |
| Q-S5 | **α** — 4 process-record acceptance flags → WORKFLOW.md `Acceptance-flag recap (PR 8 / §7)` block; bullet 1 dropped as prelude-duplicate | α |
| Q-S6 | **β** — §7.3 b2 extracted (4 V2+ deferred surfaces lifted into sub-bullets); other 9 bullets preserved verbatim | α (F/CTO override) |

**5-for-6 PM acceptance; 1 F/CTO override at Q-S6 = β.**

**β extraction sweep — 1 extraction (single-bullet scope)**

- Systematic sweep of all 10 source body bullets across §7.1–§7.3 for three β triggers per PR 6 precedent. 3 multi-clause candidates surfaced at structure proposal (§7.2 b1 Historical-data depth; §7.2 b3 Plaid sync throughput; §7.3 b2 Invite-only forward-compat).
- **1 bullet extracted per F/CTO Q-S6 = β override:** §7.3 b2 (Invite-only forward-compat). 4 V2+ deferred surfaces (friends-and-family onboarding, invite-flow UI, multi-user auth gates, per-user data-access boundary checks) lifted from inline list into 4 indented sub-bullets. Lead bullet's primary commitment (V1 forward-compat + closed-and-invite-controlled framing + cross-refs to §5.7 / §6.1) preserved verbatim. Bold-inline `Invite-only forward-compat — V2 adds the second user without data migration.` preserved on lead bullet.
- **9 bullets preserved verbatim.** §7.2 b1 + §7.2 b3 surfaced as β candidates but preserved verbatim per F/CTO scoping (single-bullet-narrow override).

**Line-count outcome under α/α/α/α/α/β**

- PM α target at structure proposal: -32% compression (-12 lines).
- CoS β-reset estimate post-Q-S6 ratify: -25% to -28% compression.
- **Realized: -8 lines net / -19%** — below both projections. Compression source: routing-flags-block collapse + acceptance-flags-block lift to WORKFLOW.md + §7 prelude tightening. Offset: β extraction expansion on §7.3 b2 (+4 net lines: 1 source bullet → 1 lead + 4 sub-bullets). **Not a problem; net compression remains substantial; reset reported honestly per PR 6 / v1.24 precedent.**

**App B running total post-PR 8 = 14 entries**

- PR 8 adds 5: Sec V2-implementation closure-trace (flag (a); resolved at §4.6 V2-ship-gate inventory (iv) + closure at §4 (k)(iv)/(m)) + Architect Phase 3 forward-pointer (flag (b)) + §7.2 ↔ §6.4 cross-reference (flag (c)) + §5 flag (e) closure (flag (d); resolved-at-§7.3-lock process-record) + §7 ↔ §4 routing closure (flag (e); hybrid).
- Running total: 9 (post-PR 7) + 5 (PR 8) = 14.

**Q7 verify-pass queue total post-PR 8 = 17**

- PR-8-VP-§7-1 surfaced: §7's §4 forward-pointers cite §4's locked-content scope but do not explicitly cross-reference §4.6 V2-ship-gate Sec-consult inventory item (k)(iv); evaluate at Q7 = γ whether explicit `§4.6(k)(iv)` anchor citation is warranted. Marginal; not joint-mergeable with prior candidates.
- Running queue: 16 (post-PR 7 merged) + 1 (PR 8) = 17.

**Acceptance-flag recap (PR 8 / §7)**

- **§7 is locked as of 2026-05-18.** No Security Reviewer at-lock pass required — §7 has no credential-handling surface, no auth-flow surface, no multi-tenant-isolation primitive ratification, no Plaid integration surface ratification, no money-flow surface, and no financial-calculation-integrity claim; §7.1's spend-cap forward-consult is a V2-implementation flag (landed at §4.6 V2-ship-gate inventory item (iv)); §7.2's multi-tenant isolation-at-scale routing is a forward-pointer to §4 (landed at §4.1–§4.6).
- **Per-sub-section locks:**
  - **§7.1** — 1 target-ceiling commitment + 1 cost-shape at-risk flag + 1 per-line-item-out-of-scope boundary; ADR-002 §6.0 verbatim, no itemized vendor pricing.
  - **§7.2** — 3 Architect Phase-3 scale dimensions + 1 RLS query-shape forward-pointer + 1 §4-routed isolation-at-scale posture pointer.
  - **§7.3** — 1 single-user-V1-multi-tenant-day-one commitment + 1 invite-only-forward-compat commitment (lead bullet preserved verbatim; 4 V2+ deferred surfaces extracted under Q-S6 = β override); ADR-002 §1.4 + §5.7 verbatim.
- **Five routing flags (a)–(e) added** (1 Sec V2-implementation closure-trace, 1 Architect Phase 3 forward-pointer, 3 boundary notes — all relocated to App B per Q-S4 = α).
- **No new ADR for §7 lock.** §7 introduces no new scope decisions; all content is grounded in already-locked ADRs (ADR-002 §6.0 for §7.1; ADR-002 §1.4 + §5.7 for §7.3) or forward-points to Architect Phase 3 (§7.2). **No cross-section surgical edits** — §7's content is purely additive to upstream sections; no §1.4-line-58-style alignment required at §7 lock.
- **Closure-trace summary:** The Sec routing flag (a) closed at §4.6 lock (PR 5 / v1.23); the Architect routing flag (b) resolves at Phase 3 (ARCHITECTURE.md cost reconciliation + scale-dimension implementation), does not block §7 lock at the PRD level. Boundary notes (c), (d), (e) are documentation markers; (d) closes §5 routing flag (e) at this lock (PR 8 / §7.3); (e) is largely closed at §4 lock with residual forward-operative boundary-note semantics for post-hoc cross-§ navigation.

**Team-mode operational continuation**

- `pm-pr8-structure@phase-1` teammate handled both structure proposal and body draft turns under one continuous teammate (vs PR 7's structure-as-subagent + body-as-teammate split). Sync-mismatch pattern surfaced after Q-S ratify relay (teammate went idle without producing body deliverables on first turn); re-poke with "Not a re-fire" framing per `memory/feedback_pm_sync_mismatch_pattern.md` unblocked cleanly.

**Substance preservation**

- 0 substance amendments. Presentation-only rewrite. All locks preserved (ADR-002 §1.4 + §6.0 + Finding (a) + Finding (f) + §5.7 + §6.1 + §6.4 + §4.6 + §2.1.3 + §2.1 + §3).
- 1 cross-ref retarget (`PRD.md:820` → `§5 routing flag (e)` inside App B entry for flag (d); body itself has zero retargets — cleanest-sweep parallel to PR 3 + PR 6 + PR 7).
- 3 DECISIONS.md numeric refs preserved verbatim (`:275`, `:534`, `:541`).

**No new ADR.** PR 8 is presentation-only; all content grounded in already-locked ADRs. Follows PR 2 / 3 / 4 / 5 / 6 / 7 precedent.

---

### v1.26 — 2026-05-19

**PR #[TBD] — Phase 1 Step 3.5 PR 7 / §6 (Out-of-scope for this PRD lifecycle) rewrite.** Fourth bulk-closeout PR under Step 3.5 cadence (mirrors PR 6 / §5 + PR 4 / §3 + PR 2 / §1). PM continues as primary author from PR 6. Smallest section under rewrite — 39 source body lines (including blank padding + routing-flags block) vs §5's 107. **First team-mode dispatch under v1.25 operating-model convention** — `pm-pr7-body@phase-1` teammate spawned for body draft, rendered in split-pane visible to F/CTO live.

**Section rewritten**

- **§6** (Out-of-scope for this PRD lifecycle) — 5 sub-sections preserved (§6.1 / §6.2 / §6.3 / §6.4 / §6.5) per Q2 = β source-order parity.
- Source: `docs/archive/PRD-v1.18-source.md` §6 (lines 953–992; 39 inclusive body lines including 0 blockquote lines).
- Rewritten: `PRD.md` §6 (35 body lines; net line-count *compression* of -4 lines / -10.3% under α-for-α structure-gate ratify).

**Structure-gate decisions (Q-S1 through Q-S5)**

| Q | Locked answer | PM recommendation |
|---|---|---|
| Q-S1 | **α** — bulk-closeout cadence | α |
| Q-S2 | **N/A** — no blockquotes in §6 source (convention trivially satisfied) | N/A confirmation |
| Q-S3 | **α** — §6 prelude ADR-citation compresses to ID-only; per-sub-§ axis-framing preludes preserved verbatim | α |
| Q-S4 | **α** — §6 prelude §5/§6 + §3.5/§6 distinction preserved verbatim; VP-§6-1 joint-merged with VP-§5-2 at Q7 | α |
| Q-S5 | **α** — 3 routing flags (a)/(b)/(c) → App B; flag (a) as resolved-at-§6-lock process-record | α |

**4-for-4 PM acceptance** (Q-S2 = N/A trivially satisfied). No F/CTO override at structure gate. Cleanest ratify pass since PR 4.

**β extraction sweep — 0 extractions**

- Systematic sweep of all 6 source body bullets across §6.1–§6.5 for three β triggers per PR 6 precedent.
- **0 bullets extracted.** §6.3 b2 TLH bullet (strongest β candidate; 4 clauses jointly applying the information-vs-prescription axis to TLH-specific case) preserved verbatim per PM α default; F/CTO ratified α at Q-S2 = N/A bypass + Q-B1 = α body gate.
- All 6 bullets preserved verbatim. All 5 per-sub-§ axis-framing preludes preserved verbatim. Bold-inline emphasis preserved verbatim across 4 carve-out anchors (§6.2 b1 estimated-tax-payment + §6.3 axis-prelude information-vs-prescription + §6.3 b2 ADR-007 / information-vs-prescription / remain V2+ trajectory + §6.5 axis-prelude Explicit non-§6 carve-out).

**Line-count outcome under α**

- PM α target at structure proposal: -10% to -20% mild compression.
- Realized: **-4 lines net / -10.3%** — within projected range. Compression source: routing-flags-block collapse (-4 lines, 5-line `#### Open routing flags affecting §6` block → 1-line italic App B marker) + §6 prelude ADR-citation compression (~no net line, denser sentence 1). No β-driven expansion.

**App B running total post-PR 7 = 9 entries**

- PR 7 adds 3: §6 ↔ §1.4 framing alignment (resolved-at-§6-lock process-record per Q5-a; parallel to PR-4-App-B flag (f)) + §6 ↔ §5 distinction (forward-operative boundary note; mirrors §5's routing flag (d) TLH boundary note) + §6 ↔ §3.5 distinction (forward-operative boundary note).
- Running total: 6 (post-PR 6) + 3 (PR 7) = 9.

**Q7 verify-pass queue total post-PR 7 = 16**

- VP-§6-1 (§6 prelude — §5/§6 distinction symmetric mirror) joint-merged with VP-§5-2 (PR 6 candidate — §5 prelude's §6 contrast list partial-stale post-ADR-007/TLH) into a single bidirectional Q7 = γ candidate; single disposition resolves both sides post-PR 10.
- **No net growth from PR 7.** PR 6 carried 16; PR 7 surfaces 1 candidate merged with existing.

**Team-mode operational confirmation**

- `pm-pr7-body@phase-1` teammate dispatch worked as v1.25 convention specified: split-pane visible to F/CTO; async run; idle notification at turn end; rendered file extracted proactively + opened in One Markdown for Q-B1 review.
- Forward implication: PR 8 / §7 PM dispatch (next in Step 3.5 source order) follows same team-mode pattern.

**Substance preservation**

- 0 substance amendments. Presentation-only rewrite. All locks preserved (ADR-002 §3.0 + ADR-007 + ADR-002 Finding (c) relabel + §5 / §6 / §3.5 cross-§ distinction architecture + §1.2 archetype-attribute-#4 + §2.5.3 estimated-tax-payment cross-ref + §5.5 lot-level-cost-basis V2+ narrowness + §5.7 invite-only V2 expansion + §1.4 surgical-edit closing-trace).
- 0 cross-ref retargets (cleanest sweep — parallel to PR 3 / §2 + PR 6 / §5).

**No new ADR.** PR 7 is presentation-only; all content grounded in already-locked ADRs (ADR-002 §3.0 + ADR-007). Follows PR 2 / PR 3 / PR 4 / PR 5 / PR 6 precedent.

---

### v1.25 — 2026-05-19

**PR #[TBD] — Team-mode operational convention for agent dispatches.** Operating-model addendum locking forward execution-agent dispatches to Claude Code team-mode with `team_name` matching the active phase identifier (`phase-1` for Phase 1). Prior PRs (Step 3.5 PRs 1–6) ran with plain `Agent` subagent calls — work rendered in the orchestrator's pane, no split-pane visibility for the Founder/CTO. Convention shift surfaced mid-PR-7 when the PR 7 / §6 structure-proposal PM was dispatched as an inline subagent and Founder/CTO noted the missing pane against an earlier same-session split-pane test that had verified team-mode rendering works.

**Mechanic.** `team_name: phase-1` on `Agent` tool calls spawns the teammate into the `phase-1` team (created locally at `~/.claude/teams/phase-1/`), where it gets its own split-pane and runs asynchronously while the orchestrator stays free to handle other work. Teammates send idle notifications when their turn ends; F/CTO can watch progress live and intervene without waiting for the orchestrator to relay.

**Scope.** Convention applies to all execution-agent dispatches in the active phase — Product Manager, Architect, Security Reviewer, UX Designer, Visual Designer, and any future Phase 5+ roles when they activate. New phases create their own team under `phase-<N>` naming when phase entry locks; team creation is a one-time setup step per phase. ADR-003 already establishes phase teams conceptually; this is operational reinforcement, not a new ADR.

**Changes.**

- `WORKFLOW.md` — added "Team-mode for agent dispatches" paragraph at end of Operating model section (after Task tracking via Linear, before Agent roster); version bump v1.24 → v1.25.
- No PRD / DECISIONS.md / per-directory CLAUDE.md changes — purely operating-model surface.
- No header revision — line 6's existing "Team-mode (`phase-1` team) per ADR-003 active" wording is now genuinely operational.

**Forward implications.** PR 7 / §6 PM body draft (next dispatch in Step 3.5) is the first team-mode dispatch under this convention. All subsequent Phase 1 execution-agent dispatches use team-mode. When Phase 2 (UX/Visual) opens after Step 4 ratifies, a `phase-2` team gets created at phase entry; the same convention applies.

---

### v1.24 — 2026-05-19

**PR #[TBD] — Phase 1 Step 3.5 PR 6 / §5 (V2 deferred candidates) rewrite.** Third bulk-closeout PR under Step 3.5 cadence (mirrors PR 2 / §1 + PR 4 / §3). PM resumes as primary author after PR 5 / Sec-primary-author. First PR to exercise **β shape-discipline aggressively** under F/CTO Q-S2 = β override — net line-count expansion (+61 lines vs. source / +57%) by design, distinct from the line-count-compression trajectory of prior bulk-closeout PRs.

**Section rewritten**

- **§5** (V2 deferred candidates) — 7 sub-sections preserved (§5.1 / §5.2 / §5.3 / §5.4 / §5.5 / §5.6 / §5.7) per Q2 = β source-order parity.
- Source: `docs/archive/PRD-v1.18-source.md` §5 (lines 846–952; 107 source body lines including 0 blockquote lines).
- Rewritten: `PRD.md` §5 (168 lines; net line-count *expansion* of +61 lines / +57% under β extraction).

**Pattern divergence declaration**

- **Bulk-closeout** per Q3 = γ inheritance (mirrors PR 2 + PR 4). Two F/CTO ratify gates: structure (5 Q-S) + body (Q-B1). Zero sub-section gates.
- **β shape-discipline applied aggressively** per F/CTO Q-S2 override — bullet-extraction within dense §5.4 / §5.5 / §5.6 / §5.7 bullets that contain inline `(a)/(b)/(c)` enumerations or multi-clause V2+ lists. 20 lead bullets extracted into 77 new sub-bullets across 7 sub-sections.

**Structure-gate decisions (Q-S1 through Q-S5)**

| Q | Locked answer | PM recommendation |
|---|---|---|
| Q-S1 | **α** — bulk-closeout cadence | α |
| Q-S2 | **β** — apply shape-discipline aggressively (bullet-extraction in dense §5.5 / §5.6 bullets) | α (F/CTO override) |
| Q-S3 | **α** — §5 prelude ADR-citation compresses to ID-only | α |
| Q-S4 | **α** — §5 prelude §6-contrast list preserved verbatim; VP-§5-2 carried to Q7 = γ | α |
| Q-S5 | **α** — routing flag (e) carries as resolved-at-§7.3-lock process-record (parallel to PR 4 flag (f)) | α |

**4-for-5 PM acceptance; 1 F/CTO override at Q-S2 = β.**

**β extraction-plan operationalization**

- Systematic sweep of all 65 source body bullets across §5.1–§5.7 for three β triggers: (A) inline (a)/(b)/(c) enumerations; (B) multi-clause V2+ lists separated by `;` or `/` each naming distinct V2+ commitments; (C) nested clauses with sub-deliverables.
- **20 bullets extracted:** §5.4 (b3 pre-emptive notification; b4 manual transaction entry; b6 Plaid product expansions; b7 Plaid coverage & instrument mechanics); §5.5 (b1 auto-cat + CRUD; b2 multi-year tax; b5 lot-level tax features incl. TLH carve-out; b7 live tax-data API; b13 quarterly-due-date reminders; b16 quarterly-installment-sizing; b18 bracket-aware Unrealized refinements); §5.6 (b1 section ordering; b4 Rebalancing editor; b5 generation-cadence; b8 alternative output formats; b11 snapshot retention; b13 staleness-marker); §5.7 (b1 multi-user expansion; b2 multi-currency).
- **45 bullets preserved verbatim** (β triggers not warranted — single-V2+-commitment shape integral to inline structure; splitting would dilute the unit-of-deferral).
- Bold-inline emphasis preserved verbatim across all extractions: `Sec consult required before V2 ship` (§5.4); `Tax-loss harvesting recommendations are NOT included…` (§5.5 — promoted to its own sub-bullet); `Forward-Sec-consult flag (carry-forward to V2 scoping):` (§5.6 × 2 — bullets not β-extracted; flags preserved as-is).

**Line-count expectations reset under β**

- PM α target at structure proposal: ~5–10% net compression (~95–100 rewritten lines).
- F/CTO Q-S2 = β override produced **+61 line net expansion** (168 rewritten lines, +57% vs. source). **Not a problem; expected under β; reset explicitly at body gate per F/CTO override caveat.**
- Word-count remains near-neutral (ADR-citation compression in prelude offsets bullet-extraction sub-bullet leads).

**PR 6 totals (§5)**

| Metric | §5 |
|---|---|
| Source body lines | 107 (lines 846–952) |
| Rewritten body lines | 168 |
| Line-count delta vs. source | **+61 lines / +57% (β expansion under Q-S2 override)** |
| Word-count compression | near-neutral (slight expansion) |
| Sub-sections preserved | 7 |
| Title rewrites | 0 |
| Blockquote lines | 0 → 0 (source has none) |
| Lead bullets preserved | 65 |
| Bullets extracted under β | 20 → 77 new sub-bullets |
| App B entries | 6 (5 forward-looking + 1 process-record resolved-at-§7.3-lock) |
| App C entries | 0 |
| First-person cleanups | 0 |
| §-prefix normalizations | 0 |
| Cross-ref retargets | **0** (cleanest sweep across PR 3 / PR 4 / PR 5 / PR 6) |
| In-body §-anchor retargets | 0 |
| ADR re-narration drops | 1 (§5 prelude per Q-S3 = α) |
| Substance amendments | **0** (presentation-only) |
| VP candidates surfaced | 3 (VP-§5-1, VP-§5-2, VP-§5-3 — all Q7 = γ deferred) |
| Q7 verify-pass queue total | **16** |
| Ratify gates | 2 (structure + body) |

**Acceptance-flags relocation (per Q1 = β)**

- §5 body has **no `#### Acceptance flags` block** in rewritten form.
- §5 body has **no `#### Open routing flags affecting §5` block** — replaced by italic Appendix B marker at §5 foot.
- §5 lock metadata preserved across: WORKFLOW.md v1.14 changelog (§5 lock + ADR-007) + this v1.24 entry.
- 6 App B entries (5 forward-looking + 1 process-record) carried forward in PR 6 body deliverable for PR 10 consolidation.

**VP candidates surfaced (Q7 = γ deferred)**

3 new VP candidates from PR 6, bringing Q7 verify-pass queue to **16 total** (7 from v1.19 + 3 from PR 4 + 3 from PR 5 + 3 from PR 6):

1. **PR-6-VP-§5-1** (§5.1 b4) — "user-driven historical correction workflows" may collide with §4.6 audit-log integrity posture (ADR-008 Decision 4 immutable audit-log retention).
2. **PR-6-VP-§5-2** (§5 prelude) — §6 contrast inline list duplicates §6 canonical enumeration and is already partially stale (ADR-007 added TLH but list does not include TLH); revisit after PR 8 §6 rewrite.
3. **PR-6-VP-§5-3** (§5.6 b5) — "in-app cron-failure notification to the user" V2+ commitment may overlap §4.6 V1 incident-handling baseline ("incident-log file at the F/CTO level").

**F/CTO ratification status**

- Structure gate (Q-S1 / Q-S2 / Q-S3 / Q-S4 / Q-S5): **5-for-5 ratified** with 1 F/CTO override at Q-S2 = β.
- Body gate (Q-B1): **α — accept body as drafted**.

**Patterns established / extended during PR 6**

- **β shape-discipline operationalization at bulk-closeout cadence.** First time an entire bulk-closeout PR ratifies β at structure-gate; sets precedent for future PRs where F/CTO wants to override PM α default on shape discipline.
- **β extraction-plan preamble as body-deliverable shape.** PM body draft for β PRs leads with the systematic sweep + bullet-by-bullet classification table before the rewritten body. Distinct from α PRs (which lead with the rewritten body directly).
- **Bold-inline emphasis preserved verbatim across extractions.** Bold-inline flags (Sec consult, TLH-not-in-V2+, Forward-Sec-consult prelude) preserve in extracted sub-bullets, not collapsed.
- **PR 6 cleanest cross-ref retarget sweep** (zero retargets, parallel to PR 3 §2; cleaner than PR 4 / PR 5).
- **Working artifacts to `temp/` from creation** (per `memory/feedback_working_artifacts_temp_not_docs.md`) — zero `docs/prd-rewrite*` files added by PR 6.
- **Body-gate standalone rendered file convention applied proactively** (per `memory/feedback_body_gate_rendered_extract.md`) — PM extracts to `temp/prd-rewrite-pr6-section5-rendered.md` before surfacing the body gate.
- **CoS-side typo correction at integration.** PM body deliverable carried 4 sweep-arithmetic / metadata typos (78→77 sub-bullets count; 62→65 source-body-bullet count; 42→45 preserved-bullet count; v1.17→v1.14 §5-lock citation). CoS corrected all four at transcription; rewritten §5 body content itself was unaffected. Pattern: CoS verifies sweep arithmetic + version citations against ground truth before transcribing PM-drafted changelog entries.

**Engagement notes**

- **PM workhorse** across 2 stages (structure proposal + body deliverable). 5 structure-gate Qs surfaced; 4 PM α accepted + 1 F/CTO β override.
- **Sec untouched** (no V1 Sec-at-lock surface in §5; routing flags (a)/(b)/(c) are forward-Sec-consult V2-ship gates, not V1 commitments — preserved as-is in App B carry-forward).
- **Architect untouched** (no architecture surface in PR 6; flag (f) carries to App B for V2-scoping-phase consumption, not Phase 3).
- **CoS bookkeeping** + 2 ratify gates with F/CTO via AskUserQuestion (5 structure-gate Qs + Q-B1 body gate, all one-question-at-a-time) + integration pass (PRD.md §5 swap + this v1.24 entry; **zero cross-ref retargets**) + 4 sweep-arithmetic/metadata typo corrections from PM body deliverable.

**Next thread:** **PR 7 — §6 (Out-of-scope for this PRD lifecycle) rewrite.** Bulk-closeout cadence per Q3 = γ (mirrors PR 6 + PR 4 + PR 2); §6 has 5 sub-sections (§6.1–§6.5) plus 3 routing flags (a)/(b)/(c) plus the lock-metadata block; low-density permanent-non-goal inventory. PM continues as primary author. PR 7 inherits PR 6's β operationalization precedent if F/CTO wants β again; PM α default if not pre-empted. Closes VP-§5-2 (§5 prelude §6-contrast list re-evaluation after §6 canonical list stabilizes).

### v1.23 — 2026-05-19

**PR #[TBD] — Phase 1 Step 3.5 PR 5 / §4 (Security and compliance posture) rewrite.** Second sub-section-gates PR (mirrors PR 3 / §2 cadence). **First Sec-as-primary-author PR since PR 1 kickoff.** ADR-008-locked canonical-reference content (6 Sec axes; 14×8 SD classification matrix; 15×7 RLS test catalog; V1 retention/availability/incident-handling baseline; 2 pattern divergences) preserved verbatim by construction.

**Section rewritten**

- **§4** (Security and compliance posture) — 6 sub-sections preserved (§4.1 / §4.2 / §4.3 / §4.4 / §4.5 / §4.6) per Q2 = β source-order parity.
- Source: `docs/archive/PRD-v1.18-source.md` §4 (lines 720–845; 126 source lines including 0 blockquote lines).
- Rewritten: `PRD.md` §4 (lines 803–901; ~99 lines; ~21% net line-count compression).

**Pattern divergence declaration**

- **Sub-section-gates** per Q3 = γ. 1 structure gate (6 sub-Qs Q-S1–Q-S6) + 6 body gates (1 per §4.N) = 7 ratify touchpoints.
- **Zero bulk-closeout, zero per-bullet gates.**

**Structure-gate decisions (Q-S1 through Q-S6)**

| Q | Locked answer |
|---|---|
| Q-S1 | **α** — 1 structure + 6 body gates (mirror PR 3 §2 cadence) |
| Q-S2 | **α** — aggressive Shape-P compression (framing-prelude + bullet-tail rationale-trace) |
| Q-S3 | **α** — §4.4 matrix preserved verbatim; framing compress only |
| Q-S4 | **β** — §4.5 RT-07 orphan-ref `acceptance flag (ii) below` → `ADR-008 Decision 3 — reserved-vacant row consolidation rationale` |
| Q-S5 | **γ** — §4.2 line-ref retarget + redundant parenthetical drop + first-person voice conversion (F/CTO override of Sec β recommendation; rationale: §2.4.1 already rewritten to product-voice at PR 3, so verbatim-re-citation rationale no longer holds; γ maintains citation consistency rather than preserving stale citation form) |
| Q-S6 | **α** — §4.6 V2-ship-gate inventory preserved as nested bullets |

**PR 5 totals across §4.1–§4.6**

| §4.N | Source lines | Rewritten | Compression |
|---|---|---|---|
| §4.1 | ~9 | ~9 | minor |
| §4.2 | ~12 | ~11 | ~10% |
| §4.3 | ~11 | ~10 | minor |
| §4.4 | ~20 | ~20 | minor (table verbatim) |
| §4.5 | ~21 | ~21 | minor (table verbatim + Q-S4 RT-07 cell update) |
| §4.6 | ~46 | ~18 | **~60%** (largest single compression) |
| §4 prelude | ~3 | ~3 | preserved verbatim |
| **Total** | **126** | **~99** | **~21% net** |

**ADR-008 canonical-reference preservation (per Decisions 1 + 2 + 3 + 4 + 5)**

- **Decision 1** (6 canonical Sec axes i–vi): all preserved verbatim across §4.1 + §4.3.
- **Decision 2** (14×8 SD classification matrix): all 112 cells preserved verbatim character-for-character (cell-level verification performed at body-gate-4). Closed-enum values preserved verbatim (sensitivity-tier 3 / storage-protection 4 / retention-posture 4 incl. N=90). SD-13 `—` cross-cutting placeholder preserved across 3 cells.
- **Decision 3** (15×7 RLS test catalog): 104 of 105 cells preserved verbatim; 1 cell (RT-07 Surface) updated per documented Q-S4=β closure (orphan-ref → canonical-reference anchor). Closed-enum values preserved verbatim. V1-block threshold (`critical` severity only; RT-02 + RT-05) preserved.
- **Decision 4** (V1 retention/availability/incident-handling baseline): all preserved verbatim including "best-effort uptime, no SLO" / "incident-log file at the F/CTO level" / "No user-facing delete-my-data control as a V1 surface" / V2-trajectory ramp items (a)–(d).
- **Decision 5** (pattern divergences from PM-led default): preserved at WORKFLOW.md changelog + ADR-008 itself (no §4.6 body action required).

**Q-S5 = γ F/CTO override at §4.2 (single F/CTO override; treated as presentation-only)**

F/CTO chose γ over Sec's β recommendation at structure-gate Q-S5:

- Retarget `PRD.md:269` → `PRD.md §2.4.1` (§4.2 bullet 1).
- Drop redundant parenthetical re-narrating §2.4.1 content.
- **Convert first-person voice fragment** `the institution credentials I enter` → `the institution credentials the user enters`.

Rationale: §2.4.1 has already been rewritten to product-voice at PR 3 on `main`; the verbatim-re-citation rationale for Sec's β recommendation no longer holds. F/CTO override maintains citation consistency with the rewritten §2.4.1 rather than preserving a stale citation form. Treated as presentation-only (voice-cleanup to match upstream rewrite), not a substance amendment.

**Cross-reference retargeting (per Q4 = α)**

| File | Old | New |
|---|---|---|
| PRD.md (§4.2 bullet 1) | `` `PRD.md:269` `` | `` `PRD.md §2.4.1` `` |
| WORKFLOW.md (line 478, v1.X §7.3 changelog) | `` `PRD.md:820` `` | `` `PRD.md §5.7` `` |

2 retargets total: 1 in-body (§4.2) + 1 WORKFLOW.md. Zero DECISIONS.md retargets. Zero §1.N renumber retargets in §4 body. Zero §-prefix normalizations in §4 body (already clean).

**Acceptance-flags relocation (per Q1 = β)**

- §4 body has **no `#### Acceptance flags` block** in rewritten form.
- §4 body has **no `#### Open routing flags affecting §4` block** — replaced by italic Appendix B marker at §4 foot.
- §4 lock metadata preserved across: WORKFLOW.md v1.17 changelog (§4 lock) + ADR-008 + this v1.23 entry.
- 16 App B entries (11 forward-looking + 5 process-record) carried forward in PR 5 body deliverable for PR 10 consolidation.

**VP candidates surfaced (Q7 = γ deferred)**

3 new VP candidates from PR 5, bringing Q7 verify-pass queue to **13 total** (7 from v1.19 + 3 from PR 4 + 3 from PR 5):

1. **PR-5-VP-§4-1** (§4.2) — credential-error states (c)/(d) observational distinguishability at V1 user-facing surface (depends on Plaid webhook event taxonomy).
2. **PR-5-VP-§4-2** (§4.3 + §4.5 RT-13) — RT-13 staleness severity (high) vs. §2.6.5 account-name exposure dimension; potential revision to critical (would amend ADR-008 Decision 3 + raise V1-ship-blocker count to 3).
3. **PR-5-VP-§4-3** (§4.6) — V1 indefinite audit-log retention vs. V2 incident-handling-ramp clause-level tension.

**F/CTO ratification: 12-for-12 acceptance across structure + body gates** (5 Sec-recommended + 1 F/CTO override at Q-S5=γ + 6 body-gates accepted as drafted):

- Structure gate: Q-S1 = α / Q-S2 = α / Q-S3 = α / Q-S4 = β / Q-S5 = γ (override) / Q-S6 = α.
- Body gates: Q-B1 = α / Q-B2 = α / Q-B3 = α / Q-B4 = α / Q-B5 = α / Q-B6 = α.

**Patterns established / extended during PR 5**

- **Sec-as-primary-author cadence pattern established** for sub-section-gates. ADR-008 Decision 5 pattern-divergence-from-PM-led default exercised at PR 5 ship.
- **Default-to-source-shape = §2/§3 rewritten shape on `main`** convention (per `memory/feedback_rewrite_convention_drops_blockquotes.md`) — N/A for §4 since source had 0 blockquote lines, but convention applied at briefing.
- **Working artifacts to `temp/` from creation** (per `memory/feedback_working_artifacts_temp_not_docs.md`) — zero `docs/prd-rewrite*` files added by PR 5.
- **Body-gate standalone rendered file convention established** (per `memory/feedback_body_gate_rendered_extract.md`) — CoS proactively extracts each rewritten §4.N body to `temp/prd-rewrite-pr5-section4-N-rendered.md` and opens in One Markdown for F/CTO body-gate review. Established at body-gate-3 (F/CTO surfaced same need that appeared at PR 4 / §3); applied proactively at body-gates 4 / 5 / 6; retroactively extracted §4.1 + §4.2 at integration.
- **F/CTO γ-override at structure gate is presentation-only when matched by upstream rewrite** — Q-S5 γ override on first-person voice conversion was treated as presentation-only because §2.4.1 (the source-of-citation) had already been converted to product-voice at PR 3; γ on §4.2 maintains citation consistency, not substance amendment.

**Engagement notes**

- **Sec workhorse** across 7 stages (structure proposal + 6 body-gate deliverables). First Sec primary-author PR since PR 1 kickoff.
- **PM untouched** (PM not consulted for §4 body content per ADR-008 Decision 5 Sec-primary-author pattern; PM resumes at PR 6 / §5).
- **Architect untouched** (no architecture surface in PR 5; PR 5 routing flags carried forward to App B for Phase 3 consumption).
- **CoS bookkeeping** + 12 ratify gates with F/CTO via AskUserQuestion (6 structure-gate Qs + 6 body-gate Qs, all one-question-at-a-time) + integration pass (PRD.md §4 swap + WORKFLOW.md `PRD.md:820` retarget + this v1.23 entry).
- **Sec agentId-based SendMessage continuation succeeded** across all 7 stages on the same agentId.

**Next thread:** **PR 6 — §5 (V2 deferred candidates) rewrite.** Bulk-closeout cadence per Q3 = γ (mirrors PR 2 / §1 + PR 4 / §3); §5 has 7 sub-sections (§5.1–§5.7) but is a low-density V2-trajectory inventory (not a high-density per-sub-§ lock content like §2 or §4). PM resumes as primary author. PR 6 inherits PR 5's ratification patterns (sub-section-gates is not the default for low-density sections).

---

### v1.22 — 2026-05-19

**PR #[TBD] — Phase 1 Step 3.5 PR 4 / §3 (Success metrics) rewrite.** Second bulk-closeout PR under Step 3.5 cadence (mirrors PR 2 / §1). First PR to inherit the **default-to-source-shape = §2 rewritten shape on `main`** correction (logged as feedback memory at structure-gate ratify — see "Pattern correction" below).

**Section rewritten**

- **§3** (Success metrics) — 5 sub-sections preserved (§3.1 / §3.2 / §3.3 / §3.4 / §3.5) per Q2 = β source-order parity.
- Source: `docs/archive/PRD-v1.18-source.md` §3 (lines 639–718, 80 source lines including 20 blockquote lines).
- Rewritten: `PRD.md` §3 (~95–115 lines; net line growth from bullet-extraction despite ~5% word-count compression).

**Pattern divergence declaration**

- **Bulk-closeout** per Q3 = γ (low-risk small section; 5 sub-sections / 80 source lines). Two F/CTO ratify gates only: structure + body.
- **Zero sub-section gates, zero per-bullet gates.** Matches PR 2 cadence.

**Structure-gate decisions (Q-S1 / Q-S2 / Q-S3)**

| Q | Locked answer |
|---|---|
| Q-S1 | **α** — aggressive bullet-extraction across §3.2 (Binary test) + §3.3 (Cells/panels compared + Tolerance class triplets) |
| Q-S2 | **α** — no §3.3.N sub-sub-numbering; §3.3 preserved as one anchor; §2.N reference inside each parity-test lead clause is the navigation hook |
| Q-S3 | **α** — ADR-004 Decision-name strings preserved verbatim at §3.4(b); VP-§3-2 carried to Q7 = γ verify pass |

**PR 4 totals (§3)**

| Metric | §3 |
|---|---|
| Source lines | 80 |
| Rewritten (est) | ~95–115 |
| Word-count compression | ~5% net |
| Line-count delta vs. source | +15 to +35 lines (bullet-extraction expansion; word-count still compressed) |
| Sub-sections preserved | 5 |
| Title rewrites | 0 |
| Blockquote lines | 20 source → 0 rewritten |
| App B entries | 6 routing flags (a)–(f); 5 forward-looking + 1 process-record (resolved-at-§4-lock) |
| App C entries | 0 (§3 has no story-trace surface) |
| First-person cleanups | 0 (source already product-voice) |
| §-prefix normalizations | 0 (source already §-prefixed throughout) |
| Cross-ref retargets (in WORKFLOW.md) | 1 (`PRD.md:689` → `PRD.md §3.4`) |
| In-body §-anchor retargets (§1.N renumber) | ~13 (presentation-pointer-only per Q4 = α; silently applied) |
| ADR re-narration drops | 1 (§3.1 ¶1 ADR-002 §8) |
| Substance amendments | **0** (presentation-only) |
| VP candidates surfaced | 3 (VP-§3-1, VP-§3-2, VP-§3-3 — all Q7 = γ deferred) |
| Ratify gates | 2 (structure + body) |

**Pattern correction: default-to-source-shape = §2 rewritten shape on `main` (not v1.18 source shape)**

- PM's initial PR 4 structure proposal at structure-gate round 1 proposed preserving blockquote shape across §3.1–§3.4. F/CTO surfaced precedent inconsistency: PR 3 §2 dropped 234 source blockquote-lines to 0 in rewritten form; PR 4 inherits the convention.
- Re-proposed structure (round 2) drops all 20 §3 source blockquote-lines; ratify accepted 3-for-3 α at structure gate.
- **Feedback memory logged for PR 5–10:** "default-to-source-shape" now means "default to the most-recently-rewritten section on `main`," not v1.18 source. Future structure proposals (PR 5 onward) pre-empt the constraint.

**§3 lock status: STRICTLY PRESENTATION-ONLY**

- No §3 β override per WORKFLOW.md v1.18 lock; §3 not in §1's still-mutable carve-out.
- **Zero substance amendments. Zero new commitments. Zero dropped commitments.**
- 3 VP candidates surfaced and routed to Q7 = γ post-rewrite verify pass:
  - **VP-§3-1** — §3.1 ¶1 quotation/anchor mismatch (v1.18 §1.1 quote text not verbatim in post-PR 2 §1; anchor retargeted to §1.2 — new home of parity commitment substance — but quote preserved verbatim).
  - **VP-§3-2** — §3.4(b) ADR-004 Decision-name strings preserved verbatim per Q-S3 = α; Q7 = γ re-evaluates whether names are presentation re-narration or load-bearing traceability.
  - **VP-§3-3** — §3.5-vs-§6 boundary clause may need re-examination post-PR 8 §6 rewrite.

**In-body §-anchor retargets (silent, presentation-pointer-only per Q4 = α)**

§3 body had ~13 v1.18-numbered §1.N anchors (§1.1 / §1.2 / §1.3 / §1.4) that retarget to post-PR 2 §1 numbering (§1.2 / §1.3 / §1.4 / §1.5 respectively). Distribution:

- §1.2 archetype → §1.3 archetype (10+ occurrences across §3 framing prelude + §3.2 sub-section title + §3.2 Metric 1–6 lead clauses + §3.2 closing attribute-#4 note).
- §1.1 quotation anchor → §1.2 (1 occurrence at §3.1 ¶1).
- §1.3 ("V1 success means...") → §1.4 (1 occurrence at §3.1 ¶2).
- §1.4 ("what this PRD section is not addressing about the user") → §1.5 ("Deferred user-shape questions") (1 occurrence at §3.1 ¶2).

**Cross-reference retargeting (per Q4 = α)**

| File | Line | Old | New |
|---|---|---|---|
| WORKFLOW.md | (per current sweep) | `` `PRD.md:689` `` | `` `PRD.md §3.4` `` |

- **1 retarget** in WORKFLOW.md; 0 in DECISIONS.md (DECISIONS.md `§3` refs already in section-anchor form).
- Retargets are presentation-pointer-only per `docs/archive/README.md` Q4 = α carve-out.

**Acceptance-flags relocation (per Q1 = β)**

- §3 body has **no `#### Acceptance flags` block** in rewritten form.
- §3 body has **no `#### Open routing flags affecting §3` block** — replaced by italic Appendix B marker at §3 foot.
- §3 lock metadata preserved across: WORKFLOW.md v1.18 changelog (§3 at-lock recap) + this v1.22 entry.
- 6 App B entries (5 forward-looking + 1 process-record) carried forward in PR 4 body deliverable for PR 10 consolidation.

**F/CTO ratification: 4-for-4 acceptance across structure + body gates** (zero substance amendments, all "α — accept as drafted"):

1. Structure gate Q-S1 (bullet-extraction depth) = α
2. Structure gate Q-S2 (no §3.3.N sub-sub-numbering) = α
3. Structure gate Q-S3 (preserve ADR-004 Decision names verbatim) = α
4. Body gate Q-B1 = α — accept body as drafted

**Engagement notes**

- **PM workhorse** across 3 stages (initial structure proposal + revised structure proposal post-blockquote-correction + body deliverable).
- **Sec untouched** (no Sec surface in §3 — §3 has no credential-handling surface; Sec is §4 primary author at PR 5).
- **Architect untouched** (no architecture surface in §3; PR 4 routing flags carried forward to App B for Phase 3 consumption).
- **CoS bookkeeping** + 4 ratify gates with F/CTO via AskUserQuestion + integration pass (PRD.md §3 swap + WORKFLOW.md `PRD.md:689` retarget + this v1.22 entry).

**Feedback memory landed mid-PR**

- **Default-to-source-shape = §2 rewritten shape on `main`** (logged 2026-05-19 at structure-gate revise round).

**Next thread:** **PR 5 — §4 (Security and compliance posture) rewrite.** Second sub-section-gates PR under Q3 = γ (mirrors PR 3 cadence; §4 has 6 sub-sections: §4.1 / §4.2 / §4.3 / §4.4 / §4.5 / §4.6). First PR where Sec re-engages as primary author per ADR-008 framing. PR 5 cadence: structure gate (likely 6+ sub-Qs) + 6 body gates (1 per §4.N). PR 5 inherits the default-to-source-shape correction landed at PR 4.

---

### v1.21 — 2026-05-18

**PR #[TBD] — Phase 1 Step 3.5 PR 3 / §2 (V1 user stories) rewrite.** Largest single PR in the rewrite sequence. First sub-section-gates PR under Q3 = γ. First exercise of Appendix C (Story Trace Index extraction); created in PR 3 with 32 per-story trace entries across §2.1–§2.6. Completes §2.x archetype rename (32 instances via opener-prelude-removal per Q-S4 = β + Option-2 capability-statement-extraction).

**Section rewritten**

- **§2** (V1 user stories) — 6 sub-sections preserved (§2.1 / §2.2 / §2.3 / §2.4 / §2.5 / §2.6) per Q2 = β source-order parity.
- Source: `docs/archive/PRD-v1.18-source.md` §2 (569 lines across §2.1–§2.6).
- Rewritten: `PRD.md` §2 (~439 lines body; ~23% overall compression).

**Pattern divergence declaration**

- **Sub-section-gates** per Q3 = γ. 1 structure gate (6 sub-Qs Q-S1–Q-S6) + 6 body gates (1 per §2.N) = 7 ratify gates + 1 structure-followup Q-B2 = 8 ratify touchpoints.
- **Zero bulk-closeout, zero per-bullet gates.** Body-gates 1–6 each ratified at α (PR 3 6-for-6 acceptance).

**Structure-gate decisions (Q-S1 through Q-S6 + Q-B2)**

| Q | Locked answer |
|---|---|
| Q-S1 | **α** — one body gate per §2.N (6 body gates) |
| Q-S2 | **α** — Appendix C in PRD.md |
| Q-S3 | **γ** — hybrid format (bold-prefix story ID + blockquote trace content) |
| Q-S4 | **β presentation-only** — opener-prelude removed; capability-statement-extraction (Option-2) preserved capability content |
| Q-S5 | **α** — structure accepted |
| Q-S6 | **(ii)** — routing-flag blocks extract to App B at PR 3 with bridge marker |
| Q-B2 | **β** — one-line §2-top framing line re-anchoring archetype (closes VP-5) |

**PR 3 totals across §2.1–§2.6**

| §2.N | Source lines | Rewritten | Compression | App C entries | App B entries |
|---|---|---|---|---|---|
| §2.1 | 53 | ~35 | 34% | 7 | 5 |
| §2.2 | 37 | ~22 | 40% | 4 | 7 |
| §2.3 | 49 | ~32 | 35% | 5 | 11 |
| §2.4 | 68 | ~50 | 26% | 5 | 12 |
| §2.5 | 164 | ~145 | 12% | 5 | 17 |
| §2.6 | 198 | ~155 | 22% | 6 | 21 |
| **Total** | **569** | **~439** | **~23%** | **32** | **73** |

**Archetype rename completion (per Q-2 = α bounded reading from PR 2)**

- 32 source instances of "self-directed multi-account owner" renamed across §2.1–§2.6 via opener-prelude-removal pattern (Q-S4 = β).
- **Zero "Independent Investor" occurrences in §2 body** — Q-B2 = β resolution at body-gate-1 added one-line §2-top framing line carrying archetype reference.
- Per VP-1 closure at body-gate-4: 16 silent `§`-prefix normalizations applied (5 at §2.4 + 5 at §2.5 + 6 at §2.6).

**§2 lock status: STRICTLY PRESENTATION-ONLY**

- No §2 β override per WORKFLOW.md v1.18 lock; substance candidates routed to Q7 = γ post-rewrite verify pass.
- **Zero substance amendments. Zero new commitments. Zero dropped commitments.**

**Patterns established during PR 3 (for PR 4–10 inheritance)**

- **Shape-A / Shape-B / Shape-C per-story shape categorization** — apply per-story shape pattern based on inspected source structure, not broad-stroke sub-section categorization.
- **Voice-cleanup of first-person references in preserved shape-B sub-blocks** — "I/me/my" → "the user / the user's" + product-voice; attested as presentation-only.
- **`§`-prefix normalization at first encounter** — VP-1 closure at body-gate-4.
- **"Mine/my → the user's" supporting-story title rewrite** — 6 consecutive instances across §2.1.7 / §2.2.4 / §2.3.5 / §2.4.5 / §2.5.5 / §2.6.6.
- **Shape-B-Supporting story shape** — §2.6.6 first instance (Supporting story with sub-blocks when elevating new Sec axes).
- **Inline structures preserved in story bodies** — markdown tables (§2.5.2 + §2.6.1); inline `(1)(2)(3)` numbered-step paragraphs (§2.5.3); fenced code blocks (§2.5.4); ordered lists (§2.6.1).
- **Cross-reference no-new-flag entries in App B** — §2.3-(j) CPI-U precedent; preserves Phase 3 traceability without duplication.
- **Process-records vs. forward-looking-flags in App B** — App B contains both entry types (12 process records across §2.5 + §2.6); PR 10 consolidation strategy will distinguish.

**Substance-flag candidates (VP-set, 14 total)**

- **Closed during body gates (6):** VP-1 (§-prefix normalization, body-gate-4); VP-3 (σ-1/σ-2/σ-3 framing preserved as shape-B sub-block, body-gate-6); VP-4 (V1/V2 boundary block confirmed standard shape-B structure, body-gate-6); VP-5 (zero-archetype-name-in-§2-body resolved via Q-B2 = β framing line, body-gate-1); VP-13 (markdown-table precedent confirmed at body-gate-6); VP-14 (code-block precedent confirmed at body-gate-6).
- **Verify-pass-deferred (8):** VP-2 + VP-11 (Sec-verdict-vs-story-trace duplication across §2.4 / §2.5 / §2.6); VP-12 (process-records in App B — broader consolidation strategy for PR 10); VP-7 + VP-9 (§3.3 parity-test framework interactions: §2.2.2 Liabilities Cat extension + §2.3.4 PDF-inspection-discovered surface); VP-6 + VP-8 + VP-10 (light trace editorial cleanup).

**Cross-reference retargeting (per Q4 = α)**

- **Zero `PRD.md:NNN` retargets in PR 3.** §2 source was drafted with section-anchor cross-references (§2.1.5, §2.4.4, etc.) rather than line refs. Clean Q4 = α sweep.

**Acceptance-flags relocation (per Q1 = β)**

- All 6 `#### Acceptance flags` blocks removed from §2.1–§2.6 rewritten bodies.
- §2.1–§2.6 lock metadata preserved across WORKFLOW.md v1.10–v1.15 entries + v1.18 §8-lock-time recap + this v1.21 entry.

**F/CTO ratification: 8-for-8 acceptance across structure + body gates** (zero substance amendments, all "α — accept as drafted"):
1. Structure gate Q-S1–Q-S6 (6 sub-questions): 5 PM-recommendation-accepted + 1 PM-override (Q-S4 from α to β with presentation-only followup confirmation)
2. Q-B2 sub-question at body-gate-1: F/CTO β = one-line §2-top framing line (VP-5 closure)
3. Body-gates Q-B1 / Q-B3 / Q-B4 / Q-B5 / Q-B6 / Q-B7: 6-for-6 α — accept as drafted

**Engagement notes**

- **PM workhorse** across 7 stages (structure proposal + 6 body-gate deliverables + PR 3 closure summary).
- **Sec untouched** (no Sec surface ratification in PR 3 — §2 already locked; presentation-only rewrite). Sec re-engages at §4 primary author per the Phase 1 Step 4 closure path.
- **Architect untouched** (no architecture surface in PR 3; PR 3 routing flags carried forward to App B for Phase 3 consumption).
- **CoS bookkeeping** + 8 ratify gates with F/CTO via AskUserQuestion + integration pass per body-gate (6 commits on `phase/1-step-3-5-section-2` branch — including 1 fix-up commit at body-gate-3 for integration error).
- **PM agentId-based SendMessage continuation** succeeded across all 7 stages on the same agentId.

**CoS integration error during body-gate-3 (transparency note)**

- Body-gate-3 (§2.3) integration produced a broken state — CoS's first Edit replaced only through the §2.3.2 heading, leaving orphaned source content; a follow-up Edit failed to find its target. Committed broken state as `9b8f293`; fix-up commit `91793a7` completed the §2.3 body swap. Pattern saved as a lesson: large multi-section Edits with content boundaries need verified before commit; sed-delete-then-Edit-insert pattern (used subsequently at body-gates 4 + 5 + 6) is more reliable than single-Edit replacement on long source blocks. Content unchanged from F/CTO-ratified deliverable; the fix was purely structural.

**Next thread:** **PR 4 — §3 (Success metrics) rewrite.** Low-risk shape-A section (80 source lines, 5 sub-sections); bulk-closeout cadence per Q3 = γ (mirrors PR 2). 2 ratify gates (structure + body). PR 4 cross-reference handling: `PRD.md:689` → `PRD.md §3.4` (1 retarget). PR 5 (§4) is the second sub-section-gates PR.

---

### v1.20 — 2026-05-18

**PR #[TBD] — Phase 1 Step 3.5 PR 2 / §1 (Vision and target user) rewrite. §1 β override EXERCISED.** First body-rewrite PR under Step 3.5 cadence; establishes patterns PR 3–9 inherit; landed 4 substance amendments per WORKFLOW.md v1.19 R6 carve-out (§1 still-mutable scope).

**Section rewritten**

- **§1** (Vision and target user) — **now 5 sub-sections** (was 4): §1.1 Problem statement / §1.2 Vision / §1.3 Target-user archetype / §1.4 Why an archetype, not the F/CTO by name / §1.5 Deferred user-shape questions.
- Source: `docs/archive/PRD-v1.18-source.md` §1 (lines 17–58, ~47 lines, 4 sub-sections).
- Rewritten: `PRD.md` §1 (~75 lines including NEW §1.1 + presentation reshape; line delta reflects content addition + bullet expansion).

**Pattern divergence declaration**

- **Bulk-closeout** per Q3 = γ (low-risk small section; in §1 / §3 / §5 / §6 / §7 / §8 bulk-closeout-permissible scope). Two F/CTO ratify gates: structure (Q1=α, round 1) + body re-round (Q-3=α, round 2 absorbing 4 substance amendments).
- Zero sub-section gates, zero per-bullet gates.

**§1 β override status: EXERCISED**

Four substance amendments landed (full enumeration in PR 2 body Part 8):

- **Amendment A** — NEW §1.1 Problem Statement sub-section. F/CTO direction with PM redraft. PM shifted three of F/CTO's source-paraphrase wordings: (i) "tax compliance" → "estimated-tax obligations" to avoid §6.3 advisor/fiduciary axis brush, (ii) "calculating cash flows" → "manual mechanics of compiling their financial picture" to cover stock concepts at §2.1 (NAV) + §2.2 (allocation), (iii) "suite of tools and dashboards" → singular "streamlined personal financial observatory" to avoid scope overstatement vs. V1's single Finance Report deliverable. F/CTO ratified γ at Q-1: PM shifts kept; closing foreshadowing paragraph removed; "Independent Investor" bolded in opening framing paragraph.
- **Amendment B** — Renumbering §1.1 → §1.2 / §1.2 → §1.3 / §1.3 → §1.4 / §1.4 → §1.5 (cascade from Amendment A).
- **Amendment C** — Archetype rename "self-directed multi-account owner" → "Independent Investor" (deliberately NOT "Independent accredited investor" — F/CTO ratified non-legal framing to avoid SEC Reg D Rule 501 legal-threshold inheritance). Sweep scope per Q-2 = α (bounded): PR 2 = §1 only (2 instances); §2.x rename (32 story-opener instances) defers to PR 3 as part of opener-compression pattern.
- **Amendment D** — Cross-reference retargets per renumbering (cascade from Amendment B): 3 line-anchored refs in WORKFLOW.md updated to section-anchor form.

**No ADR amendment.** DECISIONS.md has zero occurrences of the renamed archetype term (ADRs use "the V1 instance" / "the F/CTO" / "the user"); Amendment C is therefore a PRD-internal substance amendment that does NOT require an ADR-009 entry. Section-β-override path is currently §1-only per WORKFLOW.md v1.19 R6 carve-out; PR 3–10 remain strictly presentation-only.

**Cross-reference retargeting (per Q4 = α)**

| File | Pattern | Old | New |
|---|---|---|---|
| WORKFLOW.md | §8.3 forward-pointer closure | `` `PRD.md:47` `` | `` `PRD.md §1.4` `` |
| WORKFLOW.md | §8 forward-pointer closures list | `` `PRD.md:47` `` | `` `PRD.md §1.4` `` |
| WORKFLOW.md | §1.4 line-58 surgical edit reference | `` `PRD.md:58` `` | `` `PRD.md §1.5` `` |

3 retargets in WORKFLOW.md; 0 in DECISIONS.md (DECISIONS.md `§1.X` refs are to ADR-002 internal numbering, not PRD §1.x).

**Archetype-name rename-sweep scope (per Q-2 = α bounded reading)**

| Surface | Occurrences | Scope |
|---|---|---|
| `PRD.md` §1 | 2 | **IN — PR 2 (this PR)** |
| `PRD.md` §2.x story openers | 32 | IN at PR 3 (integrated into opener-compression) |
| `DECISIONS.md` | 0 | N/A — zero occurrences |
| `WORKFLOW.md` (line 383, v1.9-era changelog) | 1 | OUT — historical changelog; immutability convention |
| `docs/v1-parity-matrix.md` | 1 | OUT — historical artifact |
| `docs/prd-rewrite-proposal-v1.md` + `docs/prd-rewrite-pr2-proposal.md` + `docs/prd-rewrite-pr2-body-preview.md` | 6 total | OUT — historical artifacts |
| `docs/archive/PRD-v1.18-source.md` | 34 | OUT — frozen archive by construction |

Forward convention from v1.20 onward: new artifact text uses "Independent Investor."

**In-body marker conventions established (for PR 3–9)**

- **Appendix B marker** (when Appendix B does not yet exist): `*Routing flags affecting §N: see Appendix B (created in PR 10; pending consolidation).*` §1 has zero routing flags so convention is declared but first exercised at PR 3.
- **Appendix C marker** (first exercised PR 3): `*Traces: see Appendix C → N.M.K.*`
- **ADR citation convention:** drop ADR re-narration in PRD body; keep ID-level pointer inline as `(ADR-NNN [Decision X])` or `(ADR-NNN §M.N)`.

**Acceptance-flags relocation (per Q1 = β)**

- §1 body has **no `#### Acceptance flags` block** in rewritten form.
- §1 lock metadata preserved across: WORKFLOW.md v1.6 (§1.2-source attribute #5 strengthening), v1.15 (§1.4-source line-58 surgical edit), v1.20 (this entry — §1 rewrite + 4 substance amendments).
- Pattern: no Acceptance-flags block in any rewritten PRD body. PR 3–9 inherit.

**Structural-fidelity attestation summary**

- §1.1 (NET-NEW substance) — attested consistent with locked §1.2–§1.5 commitments; no ADR-002 §3.0 product-identity non-goal contradiction; no ADR-007 information-vs-prescription axis crossing.
- §1.2 (was §1.1) — preserved verbatim from PR 2 round 1; no rename touchpoint.
- §1.3 (was §1.2) — preserved + 1 rename instance in framing sentence; all 7 attribute bullets verbatim; "Independent Investor" replaces "*self-directed multi-account owner*" (bold replaces italic to reflect proper-noun shape).
- §1.4 (was §1.3) — preserved + 1 rename instance in numbered-point #2.
- §1.5 (was §1.4) — preserved verbatim; zero rename touchpoints.
- Zero dropped commitments across all 5 sub-sections.

**F/CTO ratification: 4-for-4 acceptance across 2 rounds**, with Q1 PM-recommendation accepted at round 1 + 3 explicit revision-or-accept calls at round 2:

1. Round 1 Q1 structure = α (sub-section preservation + bullet plan + in-body marker conventions + Q1=α-locked §1.4/§1.5 title rewrites; PM-recommendation accepted).
2. Round 2 Q-1 = γ (per-clause revisions on §1.1: PM shifts #1/#2/#3 kept; closing paragraph removed; "Independent Investor" bolded in opening — F/CTO editorial direction).
3. Round 2 Q-2 = α (rename-sweep bounded reading: PR 2 = §1 only; §2.x defers to PR 3 — PM-recommendation accepted).
4. Round 2 Q-3 = α (full body re-round acceptance — PM-recommendation accepted).

**Engagement notes — PR 2 across two rounds**

- PM workhorse: round 1 target-shape proposal + structure gate + initial body draft; round 2 substance-amendment redraft + repo-wide rename-sweep occurrence scan + cross-ref-cascade + updated attestations + v1.20 changelog draft.
- Sec untouched (no Sec surface in §1).
- Architect untouched (no architecture surface in §1).
- CoS bookkeeping + ratify-gate sequencing across 2 rounds + integration pass (PRD.md §1 swap + WORKFLOW.md 3-line retarget + WORKFLOW.md header + this v1.20 entry).
- **PM agentId-based SendMessage continuation succeeded** for round-1-to-round-2 transition; pattern fully reliable for mid-task PM re-engagement.

**Pattern implications for PR 3–10**

- **Substance amendments are demonstrated as exercisable mid-rewrite via section-β-override path.** Currently scoped to §1 only per WORKFLOW.md v1.19 R6 carve-out; PR 3–10 remain strictly presentation-only per Step 3.5 constraint.
- **Rename-sweep precedent established:** repo-wide grep + per-surface scope decisions (PRD body = in; ADRs = N/A here, would be case-by-case if non-zero; historical changelog / artifacts = out; forward convention from new version onward). Applies forward if any future term-evolution amendment lands.
- **Bulk-closeout pattern absorbed substance amendments cleanly** under §1's low-risk surface AND across a round-1 → round-2 re-iteration. PR 3 + 4 (§2 + §4 sub-section gates) test whether sub-section-gates cadence carries similar flexibility.
- **CoS-inline editorial revision pattern** — F/CTO's `§1.1 close-paragraph removal + bolding` revision applied directly by CoS without round-3 PM re-run (presentation-only edit on PM round-2 draft). Available for future PRs where F/CTO surfaces small editorial revisions that don't warrant a PM round-trip.

**Working artifacts (transient; remove or archive at Step 3.5 closure):**

- `docs/prd-rewrite-pr2-proposal.md` — PM round-1 target-shape proposal (round-2 deliverable preserved in PM task notification; round-2 wasn't saved as a separate artifact since the body preview and v1.20 changelog capture the relevant content).
- `docs/prd-rewrite-pr2-body-preview.md` — Standalone §1 body preview used for F/CTO body-gate review (incorporates Q-1=γ revisions).

**Next thread:** **PR 3 — §2 (V1 user stories) rewrite.** First sub-section-gates PR under Q3 = γ — §2 is high-risk (largest section, 6 sub-sections, ~580 lines). Cadence: structure gate + 6 sub-section body gates (one per §2.1 / §2.2 / §2.3 / §2.4 / §2.5 / §2.6). First exercise of Appendix C Story Trace Index extraction pattern. First exercise of Appendix B in-body marker convention (§2.x sub-sections all have routing flags). PR 3 also completes the §2.x archetype-rename (32 story-opener instances) integrated into the opener-compression pattern.

---

### v1.19 — 2026-05-18

**PR #26 — Phase 1 Step 3.5 declared and kicked off.** Editorial rewrite of `PRD.md` for scannability without altering locked substance. (Changelog entry deliberately modeled in the target scannable shape the rewrite is producing — bullets, tables, sub-headers; compare to v1.18 wall-of-prose to see the pattern shift.)

**Why Step 3.5 exists**

- F/CTO surfaced **late-phase rubber-stamp risk** post-§8 lock: by end of Phase 1 Step 3, F/CTO was accepting recommendations without engaging nuance because `PRD.md` (~37k tokens, 1,090 lines) had become too dense to read substantively.
- Step 3's "44-for-44 teammate-lean track" (per v1.18 changelog) reflects acceptance, not necessarily considered ratification. Highest-risk surfaces: §6 / §7 / §8 framing; parts of §4 posture.
- Memory captured: `~/.claude/projects/-Users-mosko-Projects-mosko-fintech/memory/feedback_late_phase_density_overload.md` — pace ratify gates smaller on dense late-phase work; treat N-for-N teammate-lean tracks as metric-to-watch not virtue-signal; editorial restructure passes are legitimate Phase sub-steps.

**Step 3.5 plan — presentation-only restructure with locked substance preserved**

- Source `PRD.md` archived at `docs/archive/PRD-v1.18-source.md` (frozen this PR).
- `docs/archive/README.md` documents historical line-ref resolution and the Q4 = α retargeting carve-out.
- Working artifact: `docs/prd-rewrite-proposal-v1.md` carries full PM target-shape proposal + R1–R8 risks/mitigations + §9 substance-flag detail. Will be archived or removed at Step 3.5 closure.

**Plan ratified 7-for-7 at per-question engagement (no bulk-closeout — explicit pattern divergence from Step 3):**

| Q | Topic | Locked answer |
|---|---|---|
| Q1 | Appendix scope | **β** — Appendix B (routing flags consolidated) + Appendix C (Story Trace Index for §2.x); per-section Acceptance flags content relocates entirely to WORKFLOW.md changelog |
| Q2 | Section order | **β** — Source order (§1 → §2 → §3 → §4 → §5 → §6 → §7 → §8 → overview/appendices) |
| Q3 | Gate pattern | **γ** — Hybrid: bulk-closeout for §1/§3/§5/§6/§7/§8; sub-section gates for §4 + §2 |
| Q4 | Cross-refs | **α** — Retarget `PRD.md:NNN` → `PRD.md §N.M.K` at rewrite time (each rewrite PR sweeps WORKFLOW.md + DECISIONS.md) |
| Q5 | (Process record shape) | Auto-skipped under Q1 = β |
| Q6 | Archive PR | **α** — Standalone kickoff PR (this PR) |
| Q7 | Substance flags | **γ** — Defer all 7 PM-flagged rubber-stamp candidates to dedicated post-rewrite verify pass before Step 4 entry |

**PM-recommendation track: 5-for-7.** Two deliberate F/CTO overrides:

- **Q2** — Source order over PM's smallest-first. F/CTO weighted predictability over PM's pattern-discovery sequencing.
- **Q4** — Retarget at rewrite over PM's accept-as-historical. F/CTO read the DECISIONS.md immutability convention as applying to ADR substance, not pointer form; per-PR retargeting is treated as presentation-pointer-only.

**7 substance flags deferred to post-rewrite verify pass** (full reasoning: `docs/prd-rewrite-proposal-v1.md` §9). Verify pass walks each flag sub-section-by-sub-section before Phase 1 Step 4 opens; any substance issue lands as ADR amendment:

1. **§4.2** credential-error states (c)/(d) — observational distinguishability at V1 user-facing surface
2. **§4.3** RT-13 staleness severity (high, not critical) — does it account for §2.6.5 account-name exposure dimension?
3. **§4.6** incident-handling V2-trajectory ramp vs. audit-log V1 commitment (potential clause-level tension)
4. **§6.3** TLH information-vs-prescription axis — elevate from TLH-clause-tail to explicit axis-level commitment?
5. **§7.2** single-tenant scale dimensions — V1 RLS verification scope (single-user-only vs. V2-cohort scale)
6. **§8.1** V1.0/V1.1 "illustrative-not-normative" — is this implicitly relaxing ADR-004's actual commitment?
7. **§8.2** drop-replace transition vs. §4.6 cutover commitment (could conflict)

**PR sequence — 11 PRs:**

- **PR 1 (this PR)** — kickoff: archive source + README + WORKFLOW.md v1.19 header + this changelog
- **PR 2–9** — §1 → §2 → §3 → §4 → §5 → §6 → §7 → §8 rewrites (source order per Q2)
- **PR 10** — document overview + reading guide + section index + Appendix B (routing flags consolidated)
- After PR 10 ships: **post-rewrite verify pass** (7 substance flags above)
- After verify pass: **Phase 1 Step 3.5 closes; Phase 1 Step 4** (Architectural overview consult; Architect lead; Phase 3 entry gate) **opens**

**Pattern divergence vs. Step 3** (deliberate; enforced by Q3 = γ):

- Per-PR ratify cadence is structure gate + per-sub-section body gates for §4 + §2 (high-risk).
- Bulk-closeout permissible only on low-risk small sections (§1/§3/§5/§6/§7/§8).
- Each rewrite PR includes a structural-fidelity attestation (per R1 mitigation in `docs/prd-rewrite-proposal-v1.md`).
- Each rewrite PR explicitly declares its gate pattern in the PR body ("this PR uses [bulk-closeout | sub-section gates]; rationale: …") — pattern-divergence-check is a first-class PR convention to prevent silent relapse to bulk-closeout.

**Engagement notes — Step 3.5 kickoff session:**

- **CoS-led** ratify gate sequencing (one-question-at-a-time per memory `feedback_one_question_at_a_time.md`).
- **PM workhorse** on the target-shape proposal (single bulk deliverable per task brief, returned as scannable structured markdown for F/CTO walkthrough); PM continues as primary author for PR 2–9 section rewrites.
- **Sec / Architect untouched** at kickoff (presentation-only rewrite; no posture or scope decisions); they re-engage at the post-rewrite verify pass (if flags raise substance) and at Phase 1 Step 4 (Architect overview consult against the polished + verified PRD).
- **No new ADRs at Step 3.5 kickoff.** Step 3.5 may produce an ADR if the post-rewrite verify pass surfaces a substance change; presentation-only restructure does not produce ADRs by construction.

**Next thread:** **PR 2 — §1 (Vision and target user) rewrite.** PM-led; first body rewrite under the new Step 3.5 cadence. Establishes the rewrite *pattern* — how to compress paragraph-bullets; how to handle routing-flag pointers to Appendix B which doesn't exist yet at PR 2 (in-body marker should bridge with "Routing flags affecting §1: see Appendix B (created in PR 10; pending consolidation)"); how to express the lock-status-block-relocated-to-WORKFLOW.md convention.

---

### v1.18 — 2026-05-18

**PRD §8 LOCKED** (2026-05-18) — sixth and smallest non-§2 PRD section locked; **last PM-led drafting task in Phase 1 Step 3**; closes PRD substantive content surface for Phase 1 Step 3. §8 (V1 milestone framing) drafted from no-stub to a 3-sub-section content section across PM tasks (structure proposal + bulk-closeout body draft) and the integration pass (PRD.md + this WORKFLOW.md entry). Smallest PRD section by content surface to date (3 framing paragraphs + 10 bullets + 5 boundary-note routing flags; matches §7's 3 sub-section count but smaller by routing-flag-mix and per-section bullet density). Post-§8 lock, **Phase 1 Step 4 (Architectural overview consult)** opens — Architect lead, Phase 3 entry gate.

**Structure: 3 sub-sections — §8.1 V1 sub-version convention / §8.2 Drop-replace migration pattern / §8.3 V1-done cross-reference + Phase 4 handoff.** Convention / mechanic / cross-reference grouping; matches §7's smallest-section shape (3 sub-sections); closes §3.4 + §1.3 forward-pointers cleanly at §8.3. **Format: bulleted enumeration + short framing paragraph per sub-section** (mirrors §5 / §6 / §7 / §4.6 inventory-section default; quintuple-confirms the bulleted-with-framing shape across §3 → §5 → §6 → §7 → §8).

**§8 framing paragraph** establishes milestone-sequencing-not-single-event framing per ADR-004 (the expanded post-ADR-004 V1 scope made single-event ship impractical); cites §3.4 ↔ §8 boundary (§3.4 owns V1-done criteria, §8 owns milestone-framing scaffolding); notes §8 as last PM-led Phase 1 Step 3 PRD section.

**§8.1** (1 framing paragraph + 4 bullets) — V1.0 → V1.x → V1.final naming convention + lifecycle framework. V1.0 = first shippable backend (data-plane foothold for drop-replace); V1.x = intermediate sub-versions; V1.final = sub-version at which all §3.4 criteria pass; "shippable in framing terms" anchored at §3.3 parity-testability + §4.1 RLS-enforced multi-tenant infrastructure + §4 V1 Sec posture commitments. Illustrative ADR-004 examples (V1.0 = Plaid + manual balances; V1.1 = full manual transaction entry) preserved as **illustrative-not-normative** — specific per-version capability boundaries are Phase 4 / Linear-backlog territory.

**§8.2** (1 framing paragraph + 3 bullets) — Drop-replace migration pattern as user-continuity guarantee during V1 data-plane transition. V1.x backend as data source for residual Google Sheets views during transition per ADR-004 verbatim (data-plane shifts underneath; presentation-plane migration is incremental as V1-native surfaces supersede residuals); §4.6 shadow-workflow tear-down cross-reference (drop-replace makes §4.6 tear-down user-survivable; §4.6 tear-down is what makes drop-replace terminate cleanly at §3.4(c) retirement); §4.6 availability + §2.4.4 non-silent-staleness cross-reference (stale-data surfacing applies symmetrically across residual Google Sheets views + V1-native surfaces during transition).

**§8.3** (1 framing paragraph + 3 bullets) — V1-done cross-reference to §3.4 + §1.3 forward-pointer closure + §8 → Phase 4 handoff boundary. Reciprocates §3.4's three migration-completion criteria + N=2-months commitment without re-litigating (§3.4 owns criteria definition; §8 owns milestone-framing scaffolding). Closes §1.3 V1-correctness forward-pointer (`PRD.md §1.4`) by anchoring V1-done at §3.4. Establishes §8 → Phase 4 (Scoping) / Linear-backlog handoff: Phase 4 owns criterion-to-sub-version mapping + per-sub-version capability boundaries + dependency ordering across §2 / §4 / §7 surfaces + one-session-granularity Linear acceptance criteria. **§8 does not pre-commit milestone-sequencing decisions** — the milestone-framing scaffolding is intentionally separated from the milestone-sequencing decisions to keep Phase 1 (PRD) and Phase 4 (Scoping) territorially clean.

**Routing-flags block: 5 boundary notes (a)–(e); zero Architect flags; zero Sec flags; zero V1-block flags either side.** Smallest routing-flags block of any locked PRD section to date by content type (pure boundary-note). Boundary notes: (a) §3.4 → §8 forward-pointer closure at §8.3; (b) §1.3 → §8 forward-pointer closure at §8.3; (c) ADR-002 §7.0 gap #4 milestone-framing dimension closure at §8.3 (the criteria dimension closed at §3.4 at §3 lock); (d) §8 → Phase 4 / Linear backlog handoff anchor; (e) §8 ↔ §4.6 cross-reference shape (one-way at §8 lock; §4.6 already commits to the posture, §8.2 names the transition mechanic that consumes it). Closure-documentation pattern for ADR-002 §7.0 gap #4 follows §4.6's closure-doc convention from §4 lock; Appendix A absorption deferred per §4 routing flag (o) housekeeping convention.

**No new ADR for §8 lock** per gate-1 forecast confirmed. All §8 content is verbatim-derivable from ADR-004 (`DECISIONS.md:353`); sub-version convention + drop-replace mechanic + §3.4 V1-done cross-reference are explicit ADR-004 commitments. §8 is the PRD-side surfacing of ADR-004's milestone framing, not a new scope decision. **Fourth instance** of the "no-new-ADR lock" pattern (joins §3 / §6 / §7). **No cross-section surgical edits** — §3.4 closing line and §1.3 V1-correctness line are already correctly forward-shaped; §8.3's reciprocation closes both forward-pointers without requiring upstream body edits; §4.6 cross-references at §8.2 are one-way (no §4.6 body revision required).

**No Sec at-lock pass for §8** — no credential-handling surface, no auth-flow surface, no new Sec posture by construction; §8.2's cross-references to §4.6 are reciprocations of already-locked §4.6 posture commitments, not new Sec surface. **No Architect at-lock pass for §8** — §8 is framing-shaped, no V1 architecture surface; specific milestone-sequencing decisions are Phase 4 / Linear territory by explicit §8 → Phase 4 handoff at routing flag (d).

**F/CTO ratification: 2-for-2 PM-lean acceptance at structure gate + 1-for-1 section-level body acceptance**, zero overrides:
1. **Q1 structure** = 3 sub-sections (PM-lean over flat-single-section and 2-sub-section-collapse alternatives);
2. **Q2 format** = bulleted enumeration + short framing paragraph per sub-section (PM-lean over pure-prose alternative);
3. **Body-bundle as-drafted** accepted at section-level review; zero overrides on content or per-bullet professional-judgment calls (V1.0/V1.1 illustrative-not-normative framing; §8 → Phase 4 handoff boundary at (d); ADR-002 §7.0 gap #4 milestone-framing-dimension closure at (c)).

**PM-lean track now 23-for-23 across §3 + §5 + §6 + §7 + §8** (PM-led sections). Combined with Sec-lean 21-for-21 from §4: **44-for-44 teammate-lean record** across all locked Phase 1 Step 3 PRD sections (5 PM-led + 1 Sec-led), zero F/CTO overrides on PM- or Sec-led recommendations across the entire Phase 1 Step 3 lock work. **Fifth confirmed instance of bulk-closeout-from-structure-proposal pattern** (§3 → §5 → §6 → §7 → §8); pattern is stably the default for PM-led PRD inventory + framing sections of any scope.

**Forward-pointer closures at §8 lock:** §3.4 → §8 (`PRD.md §3.4`); §1.3 → §8 (`PRD.md §1.4`); ADR-002 §7.0 gap #4 milestone-framing dimension. Three forward-pointer closures + §8 → Phase 4 handoff anchor established at routing flag (d).

**Engagement notes:** PM workhorse across 2 tasks (structure proposal — Q1/Q2 + cross-section reference scan + ADR forecast + cross-section surgical-edit forecast + pattern-divergence check; bulk-closeout body draft — opening framing + 3 sub-section bodies + 5 boundary-note routing flags + acceptance flags in one bundle). Sec untouched (no credential-handling surface, no V1 Sec posture; §4.6 cross-references at §8.2 are reciprocations of locked content). Architect untouched (no V1 architecture surface; §8 → Phase 4 handoff makes milestone-sequencing decisions Linear-backlog territory). CoS bookkeeping + 3 ratify gates with F/CTO via AskUserQuestion (Q1 standalone → Q2 standalone → body-bundle section-level acceptance). **PM agentId-based SendMessage continuation succeeded for the sixth confirmed time** (after v1.13 §3, v1.14 §5, v1.15 §6, v1.16 §7 structure + body, this session's §7 + §8); pattern is fully reliable for recently-completed PM agents across multiple session-spanning instances.

**Patterns extended this session** for forward sections: (a) **Quintuple-confirmed bulk-closeout-from-structure-proposal pattern** — now the durable default for PM-led PRD sections of any scope (§8 is smallest, §5 was largest; pattern fits both). (b) **Fourth instance of "no-new-ADR lock" pattern** (§3 / §6 / §7 / §8) — PM-led sections that close pre-committed forward-pointers without novel scope decisions or substantive ADR amendments do not produce ADRs; pattern is now reliably distinguishable from the ADR-producing locks (§5 → ADR-007; §4 → ADR-008). (c) **Closure-documentation pattern for ADR-002 §7.0 gap-closure** — §8 closes gap #4 milestone-framing dimension at §8.3 + routing flag (c), parallel to §4 closing gaps #4 + #6 + partial-#5 at §4.6 + routing flag (o); both follow the "closure documentation at locking-section's routing-flag-block; Appendix A absorption deferred to future housekeeping PR" convention. Lightweight pattern for downstream sections closing upstream gaps without amending the upstream ADR body. (d) **Section-to-Phase handoff anchor pattern** — §8 → Phase 4 handoff at routing flag (d) explicitly anchors the boundary between PRD-locked framing (Phase 1) and Linear-backlog-owned sequencing (Phase 4); future Phase-to-Phase handoffs at section locks can use the same anchor-as-routing-flag pattern.

**PR #[TBD]** to be shipped via `/ship-branch` after this WORKFLOW.md changelog lands — **thirteenth real use** of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005, PR #17 §2.4 lock, PR #18 §2.5 lock + ADR-006, PR #19 §2.6 lock, PR #20 §3 lock, PR #21 §5 lock + ADR-007, PR #22 §6 lock, PR #23 §7 lock, PR #24 §4 lock + ADR-008, PR #[TBD] §8 lock).

**Next thread:** **Phase 1 Step 4 — Architectural overview consult** (Architect lead). First Architect primary-author engagement in the project (prior Architect engagements were Phase 1 Step 2 ratification of ADR-002 + Phase 1 Step 3 cross-section feasibility consults). Step 4 consumes the accumulated routing-flag payload from §2 + §3 + §4 + §7 (11 §4 routing flags + 4 §3 routing flags + 6 §2.x Architect routing flags + §7.2 scale dimensions + §7.1 cost-shape at-risk flag + §8 → Phase 4 milestone-sequencing handoff) and produces the Phase 3 entry payload (ARCHITECTURE.md scoping decisions, migration design framing, RLS implementation strategy per §4.5 RT-NN catalog, snapshot-store + cron + PDF worker implementation framing, cost reconciliation per ADR-002 §6.0 / `DECISIONS.md:275` at-risk flag). After Phase 1 Step 4 ratifies, **Phase 2** (UX/Visual design) becomes available; Phase 1 closes. Expected: Architect-led structure-proposal-shape consult with PM + Sec joint-consult at relevant touchpoints (Sec joint on RLS implementation strategy; PM joint on any V1 scope ambiguities surfaced during architectural-feasibility review). Team-mode (`phase-1` team) per ADR-003 active throughout; team transitions to a phase-3-or-2 team upon Phase 1 closure (team mode decision deferred to Phase 1 closure thread).

### v1.17 — 2026-05-18

**PRD §4 LOCKED + ADR-008 ACCEPTED** (2026-05-18) — fifth and largest non-§2 PRD section locked; first Sec primary-authored PRD section in Phase 1 Step 3 (prior Sec engagements were six pass-with-comments at-lock verdicts on PM-authored §2 sections). §4 (Security and compliance posture) drafted from a 3-line stub to a six-sub-section content section across Sec tasks (gate 1 structure proposal + gate A §4.4 column shape + gate B §4.5 column shape + stage 2 row drafting + stage 3 posture bulk-closeout + stage 4 ADR-008 confirm + surgical-edit proposals) and the integration pass (PRD.md §4 + PRD.md §7.1 (a) surgical reciprocation + DECISIONS.md ADR-008 + this WORKFLOW.md entry). **Largest single Phase 1 Step 3 task by content size** (24 posture bullets + 14 SD matrix rows × 8 columns + 15 RT catalog entries × 7 columns + 11 active routing flags + 5 boundary notes + ADR-008 production-ready text).

**Structure: 6 sub-sections under Option A axis-grouped + dedicated consolidation pattern** (§4.1 Tenant isolation posture — axes i–iv / §4.2 Credential + external-API posture / §4.3 Derivative-persistence + staleness posture — axes v + vi / §4.4 Sensitive-data classification matrix / §4.5 Phase 3 RLS test catalog / §4.6 Cross-cutting posture commitments). Uses the six canonical Sec axes (earned through six §2.x at-lock passes) as the organizing principle; two dedicated consolidation sub-sections (§4.4 + §4.5) as deliberate forward-payloads for Phase 3 / Phase 6 consumption. **Format: hybrid F-A + F-B** — bulleted-with-framing for posture sub-sections (mirrors §5 / §6 / §7); markdown tables for consolidation sub-sections.

**§4.1** (5 bullets) — four canonical-clause posture commitments per axes i–iv (tenant_id isolation boundary / multi-scope as data attribute not boundary / tax_treatment as inclusion filter not boundary / write-path RLS symmetry) + isolation-at-scale forward-pointer landing per §7 routing flag (e). Sixth-consecutive-instance canonical formulation across §2.1.7 → §2.6.6 consolidated.

**§4.2** (7 bullets) — Plaid OAuth flow integrity + SD-03 credential-class storage + RT-05 webhook signature verification hard-line + four credential-error states + SD-01 credential-adjacent surface + no-third-party-security-master-API V1 posture + spend-cap V2-implementation Sec-consult forward-pointer. **Sec hard-line preserved**: V1 cannot ship with RT-05 webhook signature verification failing or unimplemented.

**§4.3** (6 bullets) — axes v (staleness-live-read cross-tenant signal leak, verified at RT-13) + vi (snapshot store SD-12 as derivative-persistence surface; SD-13 cross-cutting derivative-persistence axis with forward-applicability to V2+ derivative surfaces) + non-silent staleness as V1 user-facing availability commitment + snapshot regeneration race condition (RT-14) preserving staleness-marker coupling + PDF/cron worker tenant isolation (RT-09 + RT-10).

**§4.4** (14 rows × 8 columns sensitive-data classification matrix; 109 populated + 3 `—` annotation cells on SD-13) — Class ID / Class name / Source-§ / Sensitivity tier / Storage protection class / Retention posture / V1-acceptable disclosure surfaces / Phase 3 forward-pointer ID. SD-00 baseline (transactions/holdings/cost-basis) + SD-01 through SD-12 concrete classes + SD-13 cross-cutting derivative-persistence axis annotation (uses `—` cell convention). Three closed-enum columns (sensitivity tier 3-value: credential / high / medium; storage protection class 4-value: credential-class / tenant-scoped-with-app-encryption / tenant-scoped / tenant-scoped-derivative; retention posture 4-value: indefinite / bounded-Item-active-only / bounded-N-day-rolling / indefinite-with-V2-cold-storage-rollover with N = 90 days for SD-02 Plaid Item-state metadata).

**§4.5** (15 rows × 7 columns RLS test catalog; 14 active populated + RT-07 reserved-vacant per stage-2 consolidation rationale) — Test ID / Surface / Test description / Test category / Source-§ / Severity if violated / Related Class IDs. Source-§ traceability ordering: §2.4-elevated RT-01 through RT-05; §2.5-elevated RT-06 (+ RT-07 vacant); §2.6-elevated RT-08 through RT-14; §3-elevated cross-cutting RT-15. **V1-block threshold: `critical` severity only** — 2 critical-severity = V1-ship-blockers (RT-02 Plaid Item table RLS + RT-05 webhook signature verification); 10 high-severity = release-blockers for V1.x patch on regression; 3 medium-severity = V1-final-targeted with known-issue tickets acceptable at ship. Two closed-enum columns (test category 6-value: read-path-RLS / write-path-RLS / worker-context-isolation / input-sanitization / race-condition / test-environment-posture; severity 3-value: critical / high / medium). **Catalog-completion scan at gate B revised the count from 7 to 14** — original §2.6-lock running tally was the §2.6-elevated subset; gate-B scan surfaced 4 §2.4-elevated + 2 §2.5-elevated + 1 §3-elevated cross-cutting tests not folded into the §2.6 tally; webhook signature verification added at Q-Special-Cases-a as critical-severity row (catalog 14 → 15 with RT-07 vacant).

**§4.6** (6 bullets) — data retention class-by-class per §4.4 column (Q3a Option α, closes ADR-002 §7.0 gap #5 jointly with §2.6.4 χ-1) + availability/uptime best-effort no-SLO with §2.4.4 non-silent-staleness as V1 user-facing availability story (Q3b Option α, closes gap #6) + incident-handling V1 incident-log-file at F/CTO level with V2-trajectory ramp per §7.3 invite-only forward-compat (Q3c Option α, closes gap #4) + parity-fixture access-controlled storage + RT-15 test-environment posture (closes §3 (e) + §3 (b)) + shadow-workflow tear-down with read-only archive posture (closes §3 (d)) + V2-ship-gate Sec-consult inventory consolidating 4 items (pre-emptive Plaid re-auth / email-SMS delivery / shared-link delivery / spend-cap V2-implementation).

**Routing-flags block: 11 active flags (a)–(k) + 5 boundary notes (l)–(p)** — 6 pure Architect ((a) RLS implementation across §4.5; (d) encryption-at-rest evaluation; (e) Item-state 90-day prune mechanism; (f) audit-log architecture; (g) cron worker tenant-context binding; (h) PDF worker tenant isolation) + 3 Architect/Sec joint ((c) webhook sig verification; (i) snapshot regeneration race; (j) parity-fixture test-environment plumbing) + 2 Sec-led ((b) Plaid access-token storage shape; (k) V2-ship-gate Sec-consult inventory). Boundary notes document cross-reference closures: (l) §4.4 ↔ §4.5 bidirectional cross-reference validated; (m) §4 ↔ §7 reciprocation closes §7 (e); (n) §4.6 ↔ §2.6.4 χ-1 retention; (o) ADR-002 §7.0 gaps #4 + #6 + partial-#5 closed; (p) §3 (b) + (d) + (e) all close at §4 lock. **Zero V1-block flags beyond the existing Sec hard-line on RT-05** (carried as routing flag (c) with sign-off-before-V1-ship requirement). Largest routing-flags block of any locked PRD section to date (vs §7's 5, §6's 5, §5's 6, §3's 6, §2.6's 12+6).

**ADR-008 — V1 security posture canonical reference (pattern divergence (iii) confirmed; net-new ADR).** First Sec-authored ADR; consolidative-net-new shape (parallel to ADR-002 / ADR-003 / ADR-004 consolidation pattern, distinct from ADR-005 / ADR-006 / ADR-007 surgical-amendment pattern). 5 Decisions: (1) Six canonical Sec axes as V1-authoritative set; (2) Fourteen-entry sensitive-data classification matrix as V1 canonical classification with 3 closed-enum columns; (3) Fifteen-entry RLS test catalog with 2 closed-enum columns and critical-only V1-block threshold; (4) V1 retention / availability / incident-handling posture as baseline closing ADR-002 §7.0 gaps #4 + #6 + partial-#5; (5) Two pattern divergences from PM-led default ratified (hybrid format + two-stage hybrid drafting). **Establishes immutability boundary** for canonical-reference material — six axes / 14 classes / 15 tests / closed-enum values / N = 90 day Item-state retention window / three posture commitments are immutable once accepted; bullet-level posture commitments at PRD §4.1–§4.6 remain mutable through future PRD revisions if canonical references hold steady. **No supersession of any prior ADR**; ADR-002 §1.4 + §1.6 + §1.7 + §3.0 + §6.0 + §7.0 + §8.0 all stand and operationalize at §4 surfaces; ADR-003 / ADR-004 / ADR-005 / ADR-006 / ADR-007 all stand and operationalize at §4 surfaces.

**Three pattern divergences from quadruple-confirmed PM-led bulk-closeout pattern ratified at §4 drafting:**
1. **(i) Hybrid format** — markdown tables for §4.4 + §4.5; bulleted-with-framing for §4.1–§4.3 + §4.6. Tables are grep-able, diffable at V2-expansion, structurally cross-referenceable by ID.
2. **(ii) Two-stage hybrid drafting pattern** — per-table ratify gates for §4.4 + §4.5 column shape + severity rubric (gates A + B before stage-2 row drafting); bulk-closeout for posture sub-sections (stage 3). Matrix column-shape decisions are upstream-of-row-drafting (78/105 cells per table) and warrant explicit ratification.
3. **(iii) ADR-008 net-new** — V1 security posture canonical reference. §4 lands material consumed at Phase 3 / 5 / 6 / 7 implementations + reviews; ADR-grade citability matters in a way it didn't for §6 / §7 (which forward-pointed to existing ADRs).

**F/CTO ratification: 21-for-21 Sec-lean acceptance across four stages**, zero overrides:
- Gate 1 (6-for-6): Q3a retention mixed-α / Q3b availability best-effort-no-SLO-α / Q3c incident-log-V2-ramp-α / Q1 structure Option A / Q4 drafting D-A two-stage hybrid / Q2 format F-A+F-B hybrid.
- Gate A (5-for-5): Q-Col1 Col-A 8-column / Q-Class-ID 14-entries-with-SD-00-baseline-α / Q-Tier 3-tier credential-high-medium / Q-Storage 4-value enum / Q-Retention-N N=90-days.
- Gate B (6-for-6): Q-Catalog-Count 14-entries-full-V1-catalog (revising the §2.6-tally 7-count) / Q-RT-Ord source-§-traceability / Q-RT-Col1 RT-Col-A 7-column / Q-RT-Cat 6-value enum / Q-Sev Sev-α 3-tier critical-only-V1-block / Q-Special-Cases-a webhook-as-critical-§4.5-row + Q-Special-Cases-b parity-fixture-medium-severity.
- Stage 2 body bundle (§4.4 14-row × 8-col + §4.5 15-entry × 7-col + revised routing-flags block) accepted as-drafted; 7 per-row professional-judgment calls accepted (RT-01/06/08 consolidations + RT-07 vacant slot + RT-11/12 medium severity + SD-03 bounded-Item-active retention + SD-12 V2-cold-storage forward-compat + SD-13 cross-cutting annotation convention).
- Stage 3 posture bulk-closeout bundle (§4.1 5-bullet + §4.2 7-bullet + §4.3 6-bullet + §4.6 6-bullet = 24 posture bullets total) accepted as-drafted.
- Stage 4 ADR-008 + §4-whole content acceptance accepted as-drafted.

**Sec-lean track 21-for-21** — first non-PM-lean track in Phase 1 Step 3; pattern is now PM-lean 20-for-20 across §3 + §5 + §6 + §7 (PM-led sections) + Sec-lean 21-for-21 on §4 (Sec-led section). Combined teammate-lean track for Phase 1 Step 3 lock work: 41-for-41 across 5 non-§2 sections with zero F/CTO overrides on PM- or Sec-led recommendations.

**Engagement notes:** Sec workhorse across 6 tasks (gate-1 structure proposal — full framing + Option A 6-sub-section proposal + Q3 self-flag identification + Q1/Q2/Q4 + pattern-divergence flagging + ADR forecast; gate-A column-shape proposal — 5 sub-ratify questions + Class ID convention + N-day proposal; gate-B column-shape proposal — 6 sub-ratify questions + catalog-completion scan revising 7→14 + special-cases bundle; stage-2 row drafting — 217-cell two-table bundle + cross-reference validation pass + revised routing-flags block; stage-3 posture bulk-closeout — 24 bullets across 4 sub-sections; stage-4 ADR-008 confirm + production-ready ADR text + §7.1 (a) surgical edit text + content-readiness check). PM untouched (no PM-scope-shape consults surfaced; Q3a/b/c surfaces stayed within Sec posture territory; §4 didn't reveal V1 product-scope ambiguities). Architect untouched (no V1 architecture surface; §4 enumerates Sec posture and forward-points to Architect Phase 3 across 6 routing flags). CoS bookkeeping + 4 ratify-gate batches with F/CTO via AskUserQuestion (gate-1 6-question serialized; gate-A 5-question serialized; gate-B 6-question serialized; stages 2/3/4 single-acceptance gates each). **Sec agentId-based SendMessage continuation succeeded across all 6 stages** from CoS context; pattern is fully reliable for recently-completed agents regardless of agent type (PM or Sec).

**Patterns established or extended this session** for forward sections: (a) **First Sec primary-authored PRD section drafting pattern** — four-stage two-stage-hybrid pattern (gate-1 structure + retention/availability/incident self-flags → gate-A first-consolidation-table column-shape + sub-enums → gate-B second-consolidation-table column-shape + severity-rubric + catalog-completion scan → stage-2 row drafting → stage-3 posture bulk-closeout → stage-4 ADR confirm + integration prep) captured at ADR-008 Decision 5 as available for future Sec-primary-author sections (Phase 3 ARCHITECTURE.md, Phase 6 PR review). (b) **Pattern divergence (i) hybrid format** — markdown tables for structured-data consolidation surfaces; bulleted-with-framing for posture/narrative surfaces. Available to future sections whose content is mixed structured-data + posture-narrative. (c) **Pattern divergence (ii) two-stage hybrid drafting** — per-table ratify gates for content whose column-shape decisions are upstream of row-drafting (matrices, catalogs, indexes); bulk-closeout for content whose framing is upstream of bullets (posture sub-sections). Available to future sections with similar mixed-content shape. (d) **Pattern divergence (iii) ADR-008-grade canonical-reference layer** — ADR-grade material captured at ADR layer; bullet-level posture at PRD layer; the immutability boundary is named explicitly at ADR Decision 5 / Consequences. Available to future Sec-authored or Architect-authored ADRs that establish canonical reference layers. (e) **Catalog-completion scan during gate B** — Sec re-scanned upstream §2 + §3 with fresh §4.4 context and surfaced 7 additional V1-mandatory test surfaces not in the carried-forward running tally. Pattern surfaces that catalog-style sub-sections should include an explicit catalog-completion scan as part of their column-shape ratify gate; the upstream running tally may be partial. (f) **Closure-documentation-at-routing-flag pattern for ADR-002 §7.0 gap closures** — §4 closes gaps #4 + #6 + partial-#5 without amending ADR-002's body; closure documentation lives at §4 routing flag (o) + the corresponding §4.6 bullets; ADR-002 §7.0 traceability surface absorption (Appendix A) deferred to future housekeeping PR. Lighter-weight pattern than ADR-amendment for downstream sections that close upstream gaps.

**PR #[TBD]** to be shipped via `/ship-branch` after this WORKFLOW.md changelog lands — **twelfth real use** of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005, PR #17 §2.4 lock, PR #18 §2.5 lock + ADR-006, PR #19 §2.6 lock, PR #20 §3 lock, PR #21 §5 lock + ADR-007, PR #22 §6 lock, PR #23 §7 lock, PR #[TBD] §4 lock + ADR-008). **Largest PR diff to date** by content size (§4 body + ADR-008 body + §7.1 (a) reciprocation + WORKFLOW.md header + v1.17 changelog).

**Next thread:** **§8 V1 milestone framing draft** (PM-led, brief). §8 references §3.4 V1-done criteria (three migration-completion criteria including the N = 2 consecutive months parity-passing threshold on §3.4(c)); expected: brief structure proposal (likely 1-2 sub-sections or flat content) + body draft + integration pass. PM workhorse; Sec untouched (no §8 Sec surface — §8 is milestone framing, not a posture statement); Architect untouched (no V1 architecture surface at §8). After §8 lock, **Phase 1 Step 4** (Architectural overview consult) opens — Architect lead, Phase 3 entry gate; consumes the accumulated 11 §4 routing flags + 4 §3 routing flags + 6 §2.x routing flags + §7.2 + §7.1 cost-shape at-risk flag as Phase 3 entry payload. After Phase 1 Step 4 ratifies, **Phase 2** (UX/Visual design) becomes available; Phase 1 closes. Team-mode (`phase-1` team) per ADR-003 active throughout.

### v1.16 — 2026-05-18

**PRD §7 LOCKED** (2026-05-18) — fourth non-§2 PRD section locked; closes the operating-envelope section and **closes all PM-led inventory sections in Phase 1 Step 3**. §7 (Constraints) drafted from a bare 4-line stub to a 3-sub-section content section across PM tasks (structure proposal + bulk-closeout body draft) and the integration pass (PRD.md + this WORKFLOW.md entry). Smallest PRD section locked to date (vs §6's 5 sub-sections, §3's 5, §5's 7); **§4 (Sec primary author) is the natural next thread now that all PM-led inventory sections are complete**.

**Structure: flat 3-sub-section enumeration** (§7.1 Cost / §7.2 Scale / §7.3 Usage model). Heterogeneous-constraint shape (financial / capacity / population-shape) — lightest grouping principle correct for the smallest section. Mirrors PRD stub one-to-one; rejected single "Operating envelope" axis collapse as artificial (§6's axis-grouping pattern works because product-identity boundaries are the *same kind of thing* per axis; §7's constraints are categorically distinct). **Format: bulleted enumeration + short framing paragraph per sub-section** (Format A — mirrors §5 / §6 / §3.5). Quadruple-confirms the bulleted-inventory shape.

**§7.1** (3 bullets) — target ceiling ≤ ~$50/month per ADR-002 §6.0 verbatim + cost-shape at-risk flag per `DECISIONS.md:275` (expanded V1 Plaid product mix changes architectural cost shape; target stays, bill reconciles at Architect Phase 3) + per-line-item out-of-PRD-scope boundary (Plaid product pricing / VPS / Coolify pricing live in ARCHITECTURE.md, not PRD). Honors dollar-figure redaction posture — ≤ $50/month target preserved verbatim (PRD-side locked commitment, not parity-evidence); no Plaid product pricing breakdowns or VPS line items.

**§7.2** (5 bullets) — historical-data depth (Dec-2015-forward NAV import per §2.1.3) + snapshot-store growth under daily-snapshot data shape (cross-reference §6.4) + Plaid sync throughput across two products on single tenant (per `DECISIONS.md:534`) + RLS query-shape forward-pointer (per `DECISIONS.md:541`) + multi-tenant isolation-at-scale posture forward-pointer to §4. V1 single-user by construction; "scale" is single-tenant scale dimensions, not multi-user-cohort scale. PRD commits to the posture (scale dimensions are first-class from day one even at single-user V1); implementation shapes are Architect Phase 3.

**§7.3** (2 bullets) — single-user V1 + multi-tenant infrastructure from day one per ADR-002 §1.4 verbatim + invite-only forward-compat per §5.7 (V2 adds second user without data migration of V1 user data). Reciprocates §5.7 cross-reference; closes §5 routing flag (e) (`PRD.md §5.7`).

**Routing-flags block: 5 items (a)-(e)** — one Sec V2-implementation forward-consult ((a) §7.1 spend-cap / API-quota alerting posture as cost-protection control: fires only if/when a runtime cost-protection mechanism is proposed); one Architect Phase-3 forward-pointer ((b) §7.2 scale dimensions + RLS query-shape resolve at ARCHITECTURE.md); three boundary notes ((c) §7.2 ↔ §6.4 daily-snapshot cross-reference, (d) §5 routing flag (e) closed at §7.3 lock, (e) §7 ↔ §4 routing for 3 forward-pointers). **Zero V1-block flags on either side.** Smallest routing-flags block to date alongside §6 (5 vs §6's 5; §3 and §5 both had 6).

**No new ADR for §7 lock.** §7 introduces no new scope decisions; all content is grounded in already-locked ADRs (ADR-002 §6.0 for §7.1; ADR-002 §1.4 + §5.7 for §7.3) or forward-points to Architect Phase 3 (§7.2). Follows §6 / §3 shape (lock without new ADR), not §5 / §2.3 / §2.5 shape (lock with amendment ADR). **Second consecutive section to lock without a new ADR** (after §6); pattern is settling that PM-led inventory sections that close pre-committed forward-pointers without introducing novel scope decisions do not produce ADRs.

**No cross-section surgical edits for §7 lock.** §7's content is purely additive to upstream sections; no §1.4-line-58-style alignment required (gate-1 PM scan confirmed). First section in the §3 → §5 → §6 → §7 sequence to lock without any cross-section edit (§5 had ADR-007 surgical amendment to ADR-002; §6 had §1.4 line-58 surgical edit).

**No Sec at-lock pass for §7** — §7 has no credential-handling surface, no auth-flow surface, no multi-tenant-isolation primitive ratification, no Plaid integration surface ratification, no money-flow surface, and no financial-calculation-integrity claim by construction (§7 enumerates the V1 operating envelope as declarative constraints). §7.1's spend-cap forward-consult is a V2-implementation flag, not a V1 surface; §7.2's multi-tenant isolation-at-scale routing is a forward-pointer to §4, not a §7 posture statement. Sec is **§4 primary author next**; §7's three forward-pointers to §4 (per routing flag (e)) consolidate into the §4 drafting scope.

**§7 / §4 boundary established as parallel pattern** to §5 / §6 (trajectory-vs-non-goal) and §3.5 / §6 (capability-vs-measurement): **§7 enumerates *constraints* (declarative envelope statements); §4 owns *postures* (incident handling, isolation posture, availability/uptime commitments)**. Spend-cap mechanism shape, availability commitments, and isolation-at-scale posture surface at §7 as forward-pointer flags for §4 to land. Q3 boundary lock makes this explicit at the section level; available as a clarifying lens at §4 drafting time.

**F/CTO ratification: 3-for-3 PM-lean acceptance at structure gate + 1-for-1 section-level body acceptance**, zero overrides:
1. **Q3 boundary** = §4 owns postures, §7 = constraints only (PM-lean over §7.4 availability-expansion alternative). Eliminated §7.4 from Q1 options.
2. **Q1 structure** = flat 3-sub-section enumeration (PM-lean over single "Operating envelope" axis collapse).
3. **Q2 format** = bulleted enumeration + short framing paragraph per sub-section (PM-lean over §7.1-blockquote-hybrid alternative).
4. **Body-bundle as-drafted** accepted at section-level review; zero overrides on content or routing-flags wording.

**PM-lean track now 20-for-20** across §3 (4-for-4) + §5 (6-for-6) + §6 (5-for-5 structure + 1-for-1 body) + §7 (3-for-3 structure + 1-for-1 body). Bulk-closeout-from-structure pattern **quadruple-confirmed** (§3 → §5 → §6 → §7); pattern is now the durable default for PM-led inventory sections of any scope.

**Engagement notes:** PM workhorse across 2 tasks (structure proposal — Q1/Q2/Q3 + forward-consult flag assessment + cross-section disposition scan + ADR forecast; bulk-closeout body draft — all 3 sub-section bodies + 5-item routing-flags block + acceptance flags in one bundle). Sec untouched (no credential-handling surface, no V1 surface). Architect untouched (no V1 architecture surface; §7.2 forward-pointers to Phase 3 only). CoS bookkeeping + 4 ratify gates with F/CTO via AskUserQuestion (Q3 standalone → Q1 standalone → Q2 standalone → body-bundle section-level acceptance). **Question-pacing precedent established**: interlocked gating questions can serialize cleanly with PM-recommended order (Q3 first as boundary settle → Q1 follows since boundary eliminates one option → Q2 standalone as format-independent decision), avoiding the §5 Q3b / §6 Q5-cluster aligned-bundle pattern when the interlock is one-way-elimination-shaped rather than aligned-disposition-shaped. **PM agentId-based SendMessage continuation succeeded a fourth time from CoS context** (after v1.13 §3, v1.14 §5, v1.15 §6 §7-structure-gate-spawn, this session's §7 body-draft continuation); pattern is fully reliable for recently-completed PM agents.

**Patterns established or extended this session** for forward sections: (a) **Quadruple-confirmed bulk-closeout-from-structure-proposal pattern** — now the durable default for PM-led inventory sections regardless of size. (b) **Two-consecutive-section no-ADR-lock pattern** (§6 → §7) — PM-led inventory sections that close pre-committed forward-pointers without novel scope decisions do not produce ADRs; ADR-producing locks (§5 → ADR-007) require novel scope decisions or substantive ADR amendments. (c) **Constraint-vs-posture §7/§4 boundary as third explicit boundary pattern** in Phase 1 Step 3 (alongside §5/§6 trajectory-vs-non-goal and §3.5/§6 capability-vs-measurement); each boundary clarifies what content belongs at which section, available as a lens at adjacent section drafting time. (d) **Question-pacing precedent extended** — three-way interlocked decisions can serialize with PM-recommended order when the interlock is one-way-elimination-shaped (Q3 elim'd Q1 option C without forcing Q1 itself), distinct from the aligned-bundle pattern where dispositions are genuinely coupled by content (§5 Q3b / §6 Q5-cluster).

**PR #[TBD]** to be shipped via `/ship-branch` after this WORKFLOW.md changelog lands — **eleventh real use** of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005, PR #17 §2.4 lock, PR #18 §2.5 lock + ADR-006, PR #19 §2.6 lock, PR #20 §3 lock, PR #21 §5 lock + ADR-007, PR #22 §6 lock, PR #[TBD] §7 lock).

**Next thread:** **§4 Security and compliance posture drafting** (Sec primary author). §4 is the largest single Phase 1 Step 3 task; lands the 7 Phase 3 RLS test candidates + 13-class sensitive-data matrix + 6 canonical Sec axes accumulated from §2.4 → §2.6 lock entries + 3 §7-side forward-pointers from §7 routing flag (e): §7.1 (a) spend-cap mechanism Sec-consult at V2-implementation time, §7.2 isolation-at-scale posture, and availability/uptime commitments per Q3 boundary lock. Sec primary engagement begins; PM consults on scope-shape questions if surfaced. Expected: substantially heavier structure-gate than any PM-led section (multi-axis Sec content with explicit §2-series surface dependencies); body-drafting pattern likely diverges from the quadruple-confirmed PM-led bulk-closeout shape. After §4 lock, **§8 V1 milestone framing** (PM-led, brief; references §3.4 V1-done criteria). After §8 lock, **Phase 1 Step 4** (Architectural overview consult) opens — Architect lead, Phase 3 entry gate. Team-mode (`phase-1` team) per ADR-003 active throughout.

### v1.15 — 2026-05-17

**PRD §6 LOCKED** (2026-05-17) — third non-§2 PRD section locked; closes the smallest of the §3–§7 inventory sections. §6 (Out-of-scope for this PRD lifecycle) drafted from a bare stub to a 5-axis content section across PM tasks (structure proposal + bulk-closeout body draft including §1.4 line-58 surgical edit) and the integration pass (PRD.md + this WORKFLOW.md entry). **F/CTO chose to continue sequencing (a)** — drive lighter PM-led inventory sections before §4; §7 Constraints queued next.

**Structure: 5 axis sub-sections grouped by §3.0 product-identity axis** (§6.1 public-distribution / §6.2 money-movement / §6.3 advisor-fiduciary / §6.4 real-time-quote / §6.5 mobile-native). Mirrors ADR-007's axis-as-product-identity-boundary lock; each axis sub-section opens with a short axis-rationale paragraph + bullets per non-goal under the axis. **Format: §5-mirror bulleted enumeration** (Format A) with one-sentence "what specifically excluded" elaboration per item where the boundary is non-obvious (contested-axis items like TLH carry heavier elaboration; obvious items like public sign-up carry lighter elaboration). Section title preserved per ADR-002 Finding (c) verbatim relabel ("Out-of-scope for this PRD lifecycle"); epigraph rewritten to lock the permanent-non-goal-under-product-identity-axis framing per §5 + §3.5 + ADR-007.

**§6.1** (1 item) — public sign-up; ADR-002 §3.0 verbatim. Anchors public-distribution axis: KYC/fraud/identity-verification regulatory boundary; multi-tenant data model + V2 invite-only expansion are not stepping stones to public sign-up.

**§6.2** (1 item) — money movement; ADR-002 §3.0 verbatim. Light back-reference to §2.5.3's locked estimated-tax-payment recording-only surface (per Q5-b ratify) as the most-recently-pressure-tested example of the axis.

**§6.3** (2 items) — advisor/fiduciary role + TLH recommendations per ADR-007. Information-vs-prescription axis locked as the operative test; axis description carries general framing for shared-output-with-fiduciary-implication surfaces (per Q5-d ratify) without preemptively listing specific V2+ items (e.g., the §5.6 shared-link-delivery re-litigation flagged in §5 routing flag (c) lands here for future re-litigation, not as automatic V2 trajectory). §5.5 lot-level-features-stay-V2+ cross-reference preserved per ADR-007 narrowness; wash-sale auto-detection clarified as informational-annotation (V2+ trajectory) not prescriptive-recommendation.

**§6.4** (1 item) — real-time price quotes; ADR-002 §3.0 verbatim. Boundary framed as "data shape is daily snapshots," not "live data forbidden."

**§6.5** (1 item) — mobile-native application; ADR-002 §3.0 verbatim. Explicit non-§6 carve-out for mobile-responsive web as expected V1 behavior; specific responsive commitments queued for Phase 2 (UX/Design).

**§1.4 line-58 surgical edit** — `PRD.md §1.5` rewritten to align with §6 + ADR-007 framing: the advisor/fiduciary role carved out as the one §1.4 deferral that is a permanent §6 non-goal; geographic/multi-currency, life-stage/goal-tracking, and accountant read-only-export remain V2+ trajectory or future-PRD-revision per existing §1.4 prose. Terminology alignment to already-locked decisions, parallel to the surgical-amendment pattern of ADR-005/006/007; no new ADR (no novel scope decision; just alignment of pre-ADR-007 §1.4 framing).

**Routing-flags block: 3 boundary notes only** — (a) §6 ↔ §1.4 framing alignment (resolved at §6 lock per Q5-a surgical edit); (b) §6 ↔ §5 distinction (V2+ trajectory vs permanent non-goal; re-routes via surgical ADR amendment under §5/§6 axis-as-product-identity-boundary pattern; mirrors §5 flag (d) TLH boundary note from §5-side); (c) §6 ↔ §3.5 distinction (capability-shaped vs measurement-shaped; disjoint by construction). **Zero Sec V1-block flags, zero Architect V1-block flags, zero new V2-ship-gate forward-Sec-consult flags** (V2-ship-gate flags live at §5.6 + §5.4 per §5 lock). Smallest routing-flags block of any locked PRD section to date (vs §5's 6-item, §3's 6-item, §2.6's 12-Architect + 6-Sec).

**No new ADR for §6 lock.** ADR-007 (drafted alongside §5 lock) already lands the only structurally-novel addition (TLH reclassification). The §1.4 line-58 surgical edit per Q5-a is terminology-alignment, not a new scope decision (parallel to the pattern of surgical PRD edits at section locks that fold into existing ADRs without warranting their own ADR). First non-§2 section to lock without producing a new ADR amendment (§5 produced ADR-007; §3 produced no ADR — §6 follows §3's no-ADR shape, not §5's).

**No Sec at-lock pass for §6** — §6 has no credential-handling surface, no auth-flow, no multi-tenant-isolation primitive, no Plaid integration surface, no money-flow, no financial-calculation-integrity claim by construction (the section enumerates capabilities V1 does not build). Sec entries that touch axis territory (advisor/fiduciary axis description carries general framing for shared-output-with-fiduciary-implication V2-ship-gate items) are forward-pointers to §5's existing forward-Sec-consult flags, not new V1 Sec surfaces. Sec is **§4 primary author next** per the §2.6 / §3 / §5 lock framing.

**F/CTO ratification: 5-for-5 PM-lean acceptance at structure gate + 1-for-1 section-level body acceptance**, zero overrides at structure gate or body review:
1. **Q1 structure** = grouped by §3.0 product-identity axis (PM-lean over flat-enumeration / hybrid-tag alternatives);
2. **Q2 format** = §5-mirror bulleted enumeration (PM-lean over blockquote-per-item / hybrid alternatives);
3. **Q3 framing** = Q3-A epigraph rewrite + Q3-C section title preserved (PM-lean over keeping-stub-framing / rewriting-section-title alternatives);
4. **Q5-cluster** = accept all 4 PM-leans bundled (parallel to §5 Q3b 4-reroute pattern) — (a) surgical §1.4 line-58 edit no-new-ADR; (b) light back-reference to §2.5.3 in §6.2; (c) multi-owner data model stays at §1.4; (d) no preemptive shared-link listing at §6.3;
5. **Q7 bulk-closeout cadence** accepted per §3 / §5 scaling pattern (third instance);
6. **Body-bundle as-drafted** accepted at section-level review (including PM-default §6.3 axis-description language); zero overrides on content or §1.4 edit.

**PM-lean track now 16-for-16** across §3 (4-for-4) + §5 (6-for-6) + §6 (5-for-5 structure + 1-for-1 body acceptance). Bulk-closeout-from-structure pattern triple-confirmed (§3 → §5 → §6); pattern is now the default for PM-led inventory sections of comparable scope.

**Engagement notes:** PM workhorse across 2 tasks (structure proposal — full framing + 5-axis sub-section proposal + Q1/Q2/Q3 + Q5-cluster of 4 cross-section dispositions + Q7 cadence; bulk-closeout body draft — all 5 axis sub-sections + 3 boundary notes + §1.4 surgical edit + acceptance flags in one bundle). Sec untouched (no credential-handling surface, no V1 surface). Architect untouched (no V1 architecture surface; §6 enumerates non-built capabilities). CoS bookkeeping + 4 ratify gates with F/CTO via AskUserQuestion (Q1 standalone → Q2 + Q3 bundled → Q5-cluster + Q7 bundled → body-bundle section-level acceptance). **PM agentId-based SendMessage continuation succeeded again from CoS context** — third confirmed instance (after v1.13 §3 lock and §6 structure gate this session); pattern now reliable for recently-completed PM agents, full-brief re-spawn remains the fallback for finished-and-cleared agents.

**Patterns established this session** for forward sections: (a) **Triple-confirmed bulk-closeout-from-structure-proposal pattern** — pinned as default for PM-led inventory sections; §7 (next, smallest yet at 3 sub-sections) is the natural fourth instance. (b) **§6-shape sections lock without new ADRs** when the §6 inventory's only novel addition (TLH from §5 → §6 per ADR-007) was already covered in an upstream lock's ADR; the §1.4 line-58 surgical edit precedent shows section-locks can carry terminology-alignment edits to upstream sections without warranting their own ADR (parallel to the running pattern of fold-into-existing-ADR for non-scope-decision alignments). (c) **Axis-grouped structure for product-identity-boundary sections** (vs §5's §2.x-capability-area grouping for V2+ trajectory sections) — structure grouping follows what makes the section's organizing axis navigable; §5 needed source-section traceability, §6 needed axis-traceability. (d) **Q5-cluster bundle precedent extended** — §5's Q3b 4-reroute bundle is now joined by §6's Q5-cluster 4-disposition bundle; aligned-bundles can ratify in one question while genuinely-distinct decisions serialize one-question-at-a-time (preserves the pacing pin without over-serializing). (e) **Forward-pointer axis-description pattern** — §6.3 axis description carries general framing for shared-output-with-fiduciary-implication surfaces; future V2-scoping decisions land at the axis sub-section for re-litigation rather than at the V1 PRD; pattern available for §6.x sub-sections where V2+ items in adjacent §5 sub-sections may push against the axis at V2-scoping time.

**PR #[TBD]** to be shipped via `/ship-branch` after this WORKFLOW.md changelog lands — tenth real use of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005, PR #17 §2.4 lock, PR #18 §2.5 lock + ADR-006, PR #19 §2.6 lock, PR #20 §3 lock, PR #21 §5 lock + ADR-007, PR #[TBD] §6 lock).

**Next thread:** **§7 Constraints drafting** per F/CTO sequencing choice (a). §7 is the last PM-led inventory section before §4 (Sec primary author). Three sub-sections per current PRD stub: §7.1 Cost / §7.2 Scale / §7.3 Usage model (references §5.7 multi-user V2 expansion). Expected: structure proposal (likely flat 3-sub-section or grouped-by-constraint-class) + bulk-closeout body (fourth instance of the triple-confirmed pattern) + acceptance flags. Sec consult on §7.1 / §7.2 may surface (cost/scale axes may touch §4 Sec posture surfaces — Plaid quota costs, multi-tenant RLS scale implications, etc.); to be assessed at structure-proposal time. Architect may have a forward-pointer flag for §7.2 Scale (Phase 3 territory). After §7 lock, **§4 Security and compliance posture** (Sec primary author, largest single Phase 1 Step 3 task — lands the 7 Phase 3 RLS test candidates + 13-class sensitive-data matrix + 6 canonical Sec axes from §2.4 → §2.6 lock entries). After §4 lock, §8 V1 milestone framing draft (references §3.4 V1-done criteria), then Phase 1 Step 4 (Architectural overview consult) opens. Team-mode (`phase-1` team) per ADR-003 active throughout.

### v1.14 — 2026-05-17

**PRD §5 LOCKED + ADR-007 ACCEPTED** (2026-05-17) — second non-§2 PRD section locked; closes the V2 deferred candidates consolidation. §5 drafted from a bare stub to a 7-sub-section pure-inventory section across PM tasks (structure proposal + bulk-closeout body draft including ADR-007) and the integration pass (PRD.md + DECISIONS.md + this WORKFLOW.md entry). **F/CTO chose to continue sequencing (a)** at session open — drive lighter PM-led inventory sections before §4.

**Structure: 7 sub-sections grouped by §2.x capability area** (§5.1 net-worth / §5.2 allocation / §5.3 cash-flow / §5.4 cross-cutting onboarding-entry-re-auth / §5.5 estimated-tax / §5.6 monthly-report / §5.7 cross-cutting V2+). Mirrors PRD navigation model; one-step traceability from V2+ entry back to source §2.x V1/V2 clause; symmetric with §3 sub-section structure. **Format: bulleted enumeration per sub-section** (mirrors §3.5 non-metrics shape) — each V2+ item gets one bullet with capability summary + source-section/ADR trace + (optional) brief deferral rationale; no per-item blockquote paragraphs.

**§5.1** (4 net-worth deferrals) — user-configurable time-axis controls on NAV surfaces; per-scope NAV reporting + filtering UI (ADR-004 Decision B V2+); per-tenant CPI-U source override; historical NAV import beyond V1 Dec-2015-forward parity import.

**§5.2** (6 allocation deferrals) — asset-taxonomy CRUD UI (ADR-004 Decision C V2+); auto-generated rebalance suggestions (ADR-004 Decision A V2+); Ex-US sub-allocation drill-down; per-scope allocation views; per-account taxonomy overrides; general drill-down view capability.

**§5.3** (8 cash-flow deferrals) — cash-flow-taxonomy CRUD UI; budget tracking mechanics (variance + alerts + rolling budgets + per-category targets); rule-based auto-categorization beyond recurring-vendor; per-account taxonomy overrides; per-scope cash-flow rendering; income time-series + multi-year income recordkeeping ((α) lock); Historical Expenditures chart extensions; non-monthly + custom periods.

**§5.4** (8 cross-cutting deferrals) — auto-classification of new symbols; onboarding workflow extensions; pre-emptive notification surfaces (incl. **pre-emptive Plaid re-auth reminders with Sec consult required before V2 ship**); manual transaction entry extensions; external valuation integrations; Plaid Liabilities + Plaid Income product expansions; Plaid coverage / instrument-level mechanics (derivative Greeks / bond YTM / REIT-MLP K-1 / off-exchange crypto / DRIP-pair detection / per-security configurable classification); HSA "tax-free conditional" tax-treatment refinement.

**§5.5** (23 estimated-tax deferrals) — **TLH excluded per ADR-007**; preserves ADR-002 Finding (b) "possibly a separate tool" hedge verbatim on stock screening. Auto-categorization + user-editable CRUD on Sub-Cat tax attributes; multi-year tax surfaces; full Federal AGI-line decomposition (ζ-3); wash-sale + Section 1256 auto-detection; **lot-level tax features (FIFO/LIFO/specific-ID)** — explicitly carries forward MINUS TLH per ADR-007; in-state-vs-out-of-state municipal-bond differentiation; live tax-data API ingestion; multi-jurisdiction tax expansion (multi-state + non-US); filing-status enum; bracket-aware tax credits + above-the-line deductions; separate California LT CG schedule (if existing-system divergence surfaces); quarterly-installment-sizing refinements (safe-harbor floor + μ-1 + μ-3 + annualized-income method); withholding tracking; pre-emptive quarterly-payment reminders; refund/overpayment surfacing extensions (ν-2); penalty + prior-tax-year computation; bracket-aware Unrealized Tax Liability refinements (ο-b + ο-c + Federal-ordinary-top alternative); per-jurisdiction split rendering of Realized + Unrealized (ρ-2); tax-deferred withdrawal-tax-liability as fourth NAV-subtraction; REIT/MLP K-1 splits on unrealized G/L; multi-state Unrealized Tax Liability sourcing; Monte Carlo longevity modeling; stock screening with hedge.

**§5.6** (13 monthly-report deferrals) — user-configurable section ordering + composition (ω-2/ω-3); multi-scope reports; auto-generated + hybrid Rebalancing Targets commentary (σ-2/σ-3); Rebalancing Targets editor extensions (sub-section CRUD + markdown + auto-pre-populate + late-edit revision tracking); generation-cadence + trigger extensions; revision history for regenerated months (resolves §2.6.2-vs-§2.6.3 persistence-tension); **email/SMS delivery** with **forward-Sec-consult flag**; **shared-link delivery to external viewers** with **forward-Sec-consult flag + possible ADR re-litigation against §6 advisor-role boundary**; alternative output formats (Google Doc υ-3 / markdown / HTML email / JSON-CSV / scheduled storage export); drill-down from sections to source surfaces; live-rendered date-filtered views of historical months (φ-2/φ-3); snapshot-store retention + management extensions; owner-identification header extensions (ψ-2/ψ-3); staleness-marker extensions.

**§5.7** (2 cross-cutting V2+) — multi-user invite-only V2 expansion (ADR-002 §1.4 V1-to-V2 transition; data model carries V1, UI/auth gates V2+; §7.3 references this); multi-currency (ADR-002 §3.0 reclassification from non-goal to V2+ deferral).

**Routing-flags block: 6 items (a)-(f)** — three Sec forward-consult flags for V2-ship gates ((a) pre-emptive Plaid re-auth reminders carry-forward from §2.4.4; (b) email/SMS delivery; (c) shared-link delivery with possible ADR re-litigation); two boundary notes ((d) TLH home is §6 pending §6 body drafting; (e) §5 → §7.3 cross-reference); one Architect general flag ((f) V2+ schema/migration scope decisions at V2-scoping). Smaller routing-flags block than §3's 6-item block on Architect/Sec axes — §5 has zero V1 Architect blocks (V2-scoping defers all schema work).

**ADR-007 — Amendment to ADR-002 Finding (b): TLH reclassified from V2+ to permanent non-goal under advisor-role axis.** First amendment exercising the §5/§6 axis-as-product-identity-boundary pattern. The §5/§6 distinction is V1's mechanism for keeping product-identity decisions sharp; ADR-007 establishes the precedent that V2+ candidates from earlier ratifications can move to §6 when on-inspection they cross the §3.0 advisor / fiduciary / money-movement / public-distribution / real-time-quote / mobile-native axis. **Information-vs-prescription axis** locked as the operative distinction: TLH-as-prescriptive-recommendation crosses advisor-role boundary; observational tax-tool extensions (lot-level features, wash-sale auto-detection as informational annotation) remain V2+. ADR-007 narrowness: only the "recommend tax-actions against unrealized losses" framing moves; lot-level features and wash-sale auto-detection stay V2+ in §5.5. ADR-002 Finding (b)'s remaining V2+ enumeration (Monte Carlo longevity, stock screening with hedge, tax planning already promoted to V1) unchanged. Parallel to ADR-005 + ADR-006 surgical-amendment pattern (no supersession of ADR-002 as a whole).

**F/CTO ratification: 6-for-6 PM-lean acceptance, zero overrides**:
1. **Q1 structure** = grouped by §2.x capability area (PM-lean over flat / V2-release-cohort alternatives);
2. **Q2 format** = bulleted enumeration per sub-section (PM-lean over blockquote-per-item / hybrid alternatives);
3. **Q3a TLH home** = §6 (PM-lean — advisor-role boundary; required ADR-007 amendment to ADR-002 Finding (b));
4. **Q3b 4-reroute bundle** = accept all PM-leans — (a) category alerts → §5; (c) Monte Carlo → §5; (d) stock screening → §5 with hedge preserved verbatim; (e) email/SMS + shared-link → §5 with forward-Sec-consult flag;
5. **Bulk-closeout drafting cadence accepted** per §3 / §2.6 scaling pattern;
6. **Bulk-closeout body bundle + ADR-007 accepted as-drafted** at section-level review — zero overrides on content or ADR-007 scope.

**No Sec at-lock pass for §5** — §5 has no credential-handling surface, no auth-flow, no multi-tenant-isolation primitive, no Plaid integration surface, no money-flow, no financial-calculation-integrity claim. Sec entries that touch territory ((a) / (b) / (c) routing flags) are forward-Sec-consult flags for V2-ship gates, not V1 Sec at-lock surfaces. Sec is **§4 primary author next** per §2.6 lock framing.

**Engagement notes:** PM workhorse across 2 tasks (#55 structure proposal — comprehensive sweep of §2.x V1/V2 boundary clauses + ADR-002 Finding (b) consolidation + 3 ratify questions with 5 §5/§6 reroute candidates; #56 bulk-closeout body draft — all 7 sub-sections + 6 routing flags + acceptance-flags + ADR-007 in one bundle). Sec untouched (no credential-handling surface). Architect untouched (V2-scoping routing only). CoS bookkeeping + 6 ratify gates with F/CTO (Q1 / Q2 / Q3a / Q3b / bulk-closeout cadence / section-level review acceptance). **Bulk-closeout-from-structure-proposal pattern** reused successfully (second instance after §3) — F/CTO PM-lean tracking signal at structure gate triggers bulk closeout for body draft; no per-sub-section serialization needed.

**Patterns established this session** for forward sections: (a) **§5/§6 axis-as-product-identity-boundary pattern** — when a V2+ candidate crosses the §3.0 permanent-non-goal axis on inspection, the resolution is §6 reclassification via ADR amendment rather than carry-forward as a V2+ trajectory item; (b) **Surgical-amendment ADR precedent extended** — ADR-007 follows ADR-005 / ADR-006's narrow-scope amendment pattern (parent ADR's other clauses unchanged, no supersession of the parent ADR as a whole); fourth ADR amendment since Phase 1 Step 3 opened; (c) **Information-vs-prescription axis as scope-boundary mechanism** — explicit framing locked in ADR-007 rationale; available for future §5/§6 reroute decisions (e.g., if AI-assisted features surface at V2-scoping, the information-vs-prescription axis is the test); (d) **Bulk-closeout-from-structure-proposal pattern** — second instance after §3; pinned as default for PM-led inventory sections (§6 / §7 candidates given comparable scope + smaller-than-§2 footprint); (e) **Composite Q3 routing decisions** can be split — Q3a (contentious item with ADR consequences) surfaced separately, Q3b (4-item bundle of aligned reroutes) bundled as one ratify question; preserves one-question-at-a-time for genuinely-distinct decisions while avoiding over-serialization for aligned bundles.

**PR #[TBD]** to be shipped via `/ship-branch` after this WORKFLOW.md changelog lands — ninth real use of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005, PR #17 §2.4 lock, PR #18 §2.5 lock + ADR-006, PR #19 §2.6 lock, PR #20 §3 lock, PR #[TBD] §5 lock + ADR-007).

**Next thread:** **§6 Out-of-scope for this PRD lifecycle drafting** per F/CTO sequencing choice (a). §6 is the smaller-still cousin of §5 — pure inventory of permanent non-goals from ADR-002 §3.0 + the new TLH addition per ADR-007. Expected: structure proposal (likely flat or short-grouped) + bulk-closeout body (likely shorter than §5 given §6's narrower scope) + acceptance flags. No new ADR expected (ADR-007 already lands TLH). Sec untouched. After §6 lock, **§7 Constraints** (7.1 Cost / 7.2 Scale / 7.3 Usage model — references §5.7 multi-user V2 expansion), then closing with **§4 Security and compliance posture** (Sec primary author, largest single Phase 1 Step 3 task — lands the 7 Phase 3 RLS test candidates + 13-class sensitive-data matrix + 6 canonical Sec axes from §2.4 → §2.6 lock entries). After §4 lock, §8 V1 milestone framing draft (references §3.4 V1-done criteria), then Phase 1 Step 4 (Architectural overview consult) opens. Team-mode (`phase-1` team) per ADR-003 active throughout.

### v1.13 — 2026-05-17

**PRD §3 LOCKED** (2026-05-17) — **first non-§2 PRD section locked**; closes the smallest of the five §3–§7 sections queued at §2.6 lock. §3 (Success metrics) drafted from a bare stub to a five-sub-section content section via Tasks #55 (structure proposal) and #56 (bulk-closeout body draft + integration). **F/CTO chose sequencing (a) at session open** — drive lighter PM-led inventory sections (§3 → §5 → §6 → §7) before closing with §4 (Sec primary author).

**Structure: 5 sub-sections** (§3.1 framing / §3.2 capability-delivery / §3.3 parity / §3.4 migration-completion / §3.5 explicit non-metrics) — neither the §2-series Primary/Supporting split nor the §1-series flat-paragraph shape; the section is uniformly content sub-sections with no inter-sub-section role distinction. **Three-axis V1 success framing** (§3.1) — V1 success is the conjunction of (i) capability delivery against the §1.2 archetype, (ii) output parity against the existing manual-spreadsheet system, (iii) migration completion (F/CTO retires the existing system); failure on any axis means V1 is not done. Single-user calibration explicit per ADR-002 §1.4 + §1.3; SaaS-pattern measurement frames enumerated as explicit non-metrics in §3.5.

**§3.1** *Framing* — three blockquote paragraphs (three-axis success + single-user calibration + parity-grounded-not-aspirational); cites §1.1 V1-done bar + ADR-002 §8 no-fallback-to-existing-system; commits §3.3 hybrid-tolerance framing as the "matches the existing system" definition.

**§3.2** *Capability-delivery metrics (§1.2 attribute coverage)* — **6 binary-testable metrics + 1 non-metric note**, one per §1.2 archetype attribute with **observational-tool (#4) deliberately excluded** as non-goal-shape (measuring would be category error; §6 owns the surface). Metric 4 (§1.2 attribute #5 strengthened at v1.6 — two-level taxonomies on holdings AND cash-flow, user-assigned, user-defined grammar) is the **high-bar metric** — six-part binary test (a)-(f) including both holdings + cash-flow taxonomy + user-editable assignment UIs + no-coarser-bucket-only-fallback aggregation surfaces. Each metric names the §2.x story(ies) it exercises.

**§3.3** *Parity metrics* — **6 per-§2-story sub-blocks**, each defining (i) comparison fixture from F/CTO existing system (`Finance_Report_2026_04.pdf` + Asset Summary workbook sheets + per-account workbooks), (ii) cells/panels/charts compared, (iii) tolerance class from Q3 hybrid framing. **§2.6 parity test elevated as canonical end-to-end V1-replaces-existing-system test** — passing §2.6 parity for a given month is the strongest single signal that V1 reproduces the F/CTO's monthly Finance_Report workflow; transitively applies §2.1 / §2.2 / §2.3 / §2.5 numeric tolerances on every rendered cell. **Hybrid tolerance** locked: strict equality for categorical (taxonomy structure, account names, labels, `tax_character` enum, four §2.4.4 credential-error states); **≤ $1 absolute OR ≤ 0.01% relative, whichever is greater** numeric tolerance for derived dollar values (NAV / NAV-delta / unrealized-G/L / cash-flow rollups / Realized + Unrealized Tax Liability / quarterly est-payments / rendered report cells); structural equivalence for layout / panel-set / chart-presence (no pixel match required).

**§3.4** *Migration-completion ("V1 done" definition)* — **3 conjunctive criteria**: (a) every parity-matrix "V1 preserve" line has §2 story locked + §3.3 parity test passing; (b) every ADR-004 amendment (Decisions A/B/C/D + ADR-005 + ADR-006) has capability delivered and parity-tested; (c) F/CTO has run monthly review cycle on V1 alone, without consulting existing manual-spreadsheet system, for **N = 2 consecutive months** (calibrated as: long enough for one month of green to not be a fluke + second month surfaces month-boundary edge cases; short enough that V1-final isn't gated on a six-month soak). **§3.4 is home for "V1 done" definition** per F/CTO Q2 lock — answers ADR-002 §7.0 open content gap #4; **§8 V1 milestone framing references §3.4** + adds milestone-sequencing scaffolding (V1.0 → V1.x → V1.final per ADR-004); §3.4 commits to criteria, §8 sequences them.

**§3.5** *Explicit non-metrics for V1* — 7 enumerated measurement-frame exclusions (MAU/WAU/DAU; NPS/CSAT; conversion/sign-up funnel; D1/D7/D30 retention/churn; viral coefficient/K-factor/referral; ARR/MRR/ARPU/LTV/CAC; engagement-proxy time-on-page/session-length/feature-adoption %), each with one-line rationale anchored to single-user-V1 calibration. **§3.5-vs-§6 distinction explicit**: §6 is capability-shaped (surfaces V1 doesn't build); §3.5 is measurement-shaped (frames V1 doesn't apply); disjoint by construction.

**Routing-flags block: 6 items (a)-(f)** — three Architect-led ((a) §2.6 render latency thresholds; (b) parity-fixture test-environment plumbing Architect/Sec joint; (c) §3.2 binary-test data-model verification), two Sec-led for §4 ((d) shadow-workflow tear-down posture for existing-system retirement; (e) parity-fixture sensitive-data handling), and one boundary-marker (f) confirming §3 does NOT enumerate the 13-class sensitive-data inventory (§4 territory per §2.6 lock). Smaller routing-flags block than §2.6's 12-Architect + 6-Sec, reflecting §3's smaller scope.

**F/CTO ratification: 4-for-4 PM-lean acceptance, zero overrides**:
1. **Q1 structure** = 5 sub-sections (PM-lean over 4-section / 3-section alternatives);
2. **Q2 V1-done definition home** = §3.4 (PM-lean; §8 references §3.4 + adds milestone sequencing);
3. **Q3 parity tolerance framing** = hybrid (PM-lean; strict equality categorical + numeric tolerance dollars + structural equivalence layout, over strict-across-the-board / fuzzy-no-PRD-tolerance alternatives);
4. **Bulk-closeout drafting cadence accepted** at body-drafting gate per §2.6 scaling pattern (mirrors §2.6.4-§2.6.6 bulk closeout). **Bulk-closeout body bundle accepted as-drafted** at section-level review — zero overrides on the two explicit PM-lean numerics (§3.3 ≤ $1 / ≤ 0.01% tolerance and §3.4(c) N=2 months) and zero overrides on content.

**No ADR for §3 lock** — locks fold cleanly into PRD body + routing-flags per §2.6 precedent. §3.4's "V1 done" definition home in §3.4 (vs §8) is a PRD-internal scope clarification, not an ADR-grade decision; ADR-002 §7.0 item 7 framing remains satisfied via §3.4 + §8 cross-reference. §3 introduces no genuinely new V1 capability surface (vs ADR-005's §2.3.2 planning-targets settings UI which warranted dedicated ADR) — §3 measures delivery of surfaces already PRD-locked in §1.2 / §2.x.

**No Sec at-lock pass for §3** — §3 has no credential-handling surface, no auth flow, no multi-tenant-isolation primitive, no Plaid integration, no money-flow, no financial-calculation-integrity claim. Sec is **§4 primary author next** per §2.6 lock framing — largest single Sec task in Phase 1 where the 7 Phase 3 RLS test candidates + 13-class sensitive-data matrix + 6 canonical Sec axes land. Sec consult on §3 collapses into the Phase 1 Step 4 architectural-overview consult flagged at §2.6 lock (no separate Sec spawn for §3).

**Engagement notes:** PM workhorse across 2 tasks (#55 structure proposal — full framing + 5 sub-section proposal + 3 ratify questions; #56 bulk-closeout body draft — all 5 sub-sections + routing flags + acceptance flags). Sec untouched per "no credential-handling surface" rationale; Architect untouched (routing flags route to Phase 3, not Phase 1). CoS bookkeeping + 4 ratify gates with F/CTO (Q1 / Q2 / Q3 sub-decisions + bulk-closeout drafting cadence + bulk-closeout body section-level review). **Bulk-closeout from structure proposal directly to lock-quality bundle** (no per-sub-section serialization) — second instance of the §2.6 bulk-closeout pattern; first time used from structure-proposal forward rather than mid-section pivot. **Pattern pinned for forward sections** (§5 / §6 / §7 candidates given comparable scope + smaller-than-§2 footprint): if PM-leans track 2+ consecutive ratifications at structure gate, propose bulk-closeout-from-structure for body draft.

**PM agentId-based SendMessage continuation succeeded from CoS context** — counter-evidence to the prior memory pin asserting agentId continuation isn't addressable. The pin may apply only to finished-and-cleared agents (auto-cleanup state) rather than recently-completed ones; not updating memory until cross-session confirmation. Continued PM via `to: 'a77de9defd7482f87'` after `to: 'pm'` (name) failed.

**Patterns established this session** for forward sections: (a) **bulk-closeout-from-structure-proposal** as a scaling release valve when PM-leans track at structure gate (vs §2.6's bulk-closeout-mid-section pivot); (b) **PM agentId-based SendMessage continuation** addressable from CoS context for recently-completed PM agents (overrides prior memory pin's blanket non-addressable assertion; full-brief re-spawn remains the recovery path for finished-and-cleared agents); (c) **§3-shape non-§2 PRD sections** use flat 5-sub-section structure with no Primary/Supporting role distinction (vs §2.x's Primary/Supporting split); (d) **routing-flag (f) boundary-marker pattern** — when a §X section deliberately does not enumerate content that's owned by another section §Y, capture the boundary as a routing-flag entry rather than silence to prevent territorial drift at body-review.

**PR #[TBD]** to be shipped via `/ship-branch` after this WORKFLOW.md changelog lands — eighth real use of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005, PR #17 §2.4 lock, PR #18 §2.5 lock + ADR-006, PR #[prior] §2.6 lock, PR #[TBD] §3 lock).

**Next thread:** **§5 V2 deferred candidates drafting** per F/CTO sequencing choice (a). §5 is a PM-led inventory section drawing from the V2+ items surfaced across §2.1 → §2.6 V1/V2 boundary clauses (per-account taxonomy overrides; multi-user invite-only; auto-rebalance-suggestions per ADR-007 boundary; lot-level tax features per ADR-002 §1.7 + ADR-004 Decision D; user-editable taxonomy CRUD per ADR-004 Decision C V2+; revision history on monthly reports; etc.). Then **§6 Out-of-scope** (permanent non-goals from ADR-002 §3.0 + this-PRD-lifecycle deferrals), then **§7 Constraints** (7.1 Cost / 7.2 Scale / 7.3 Usage model), then closing with **§4 Security and compliance posture** (Sec primary author, largest single Phase 1 Step 3 task — lands the 7 Phase 3 RLS test candidates + 13-class sensitive-data matrix + 6 canonical Sec axes from §2.4 → §2.6). After §4 lock, §8 V1 milestone framing draft, then Phase 1 Step 4 (Architectural overview consult) opens. Team-mode (`phase-1` team) per ADR-003 active throughout.

### v1.12 — 2026-05-17

**PRD §2.6 LOCKED** (2026-05-17) — sixth locked PRD section; closes the §2 V1 user stories series. §2.6 (Monthly Report — canonical V1 deliverable, Finance_Report-shape) drafted from a bare stub to a 5-Primary + 1-Supporting parity-grounded section across Tasks #45 (structure proposal), #46 (§2.6.1 body), #47 (§2.6.2 body), #48 (§2.6.3 body), #49 (§2.6.4 body v1), #50–#53 (bulk §2.6 closeout — §2.6.4 v1.1 reformatted + §2.6.5 + §2.6.6 + routing-flags + acceptance-flags), #54 (Sec at-lock pass), and the integration pass (this WORKFLOW.md + PRD.md write).

**Structure: 5 Primary + 1 Supporting** (vs §2.4 / §2.5 4-Primary-1-Supporting pattern; §2.6 carries one additional Primary because the report-as-artifact has more genuinely-distinct V1 surfaces — composition + section ordering, Rebalancing Targets free-text capture, generation cadence/format, snapshot/retention/identity, and staleness-marker rendering are five non-overlapping content surfaces).

**§2.6.1** *Monthly report composition and section ordering* — ω-1 V1-fixed six-section sequence (Account Holdings → NAV Performance → Asset Allocation → Rebalancing Targets → Cash Flow → Estimated Taxes) parity-exact with existing Finance_Report layout; Historical Expenditures inline within Cash Flow (resolves parity-matrix line 105-106 placeholder ambiguity); owner-identification trust-name header at top; six-section composition map names §2.1.5 (Account Holdings), §2.1.2 + §2.1.3 + §2.1.4 (NAV Performance), §2.2.2 + §2.2.3 (Asset Allocation), §2.6.2 (Rebalancing Targets), §2.3.2 + §2.3.4 (Cash Flow inline), §2.5.1 + §2.5.3 (Estimated Taxes); §2.5.4 NAV-component lines render on Account Holdings via §2.1.5, not as separate Estimated Taxes rows; Big Ticket Fund / Amortized Expenses dropped per Phase 0.5 call; user-configurable section ordering (ω-2 / ω-3) deferred V2+.

**§2.6.2** *Rebalancing Targets free-text commentary* — σ-1 free-text user-authored (preserves ADR-004 Decision A V2+-only auto-rebalance-suggestions boundary; σ-2 auto-generated and σ-3 hybrid both rejected as ADR-007-triggering V2+ paths); V1-fixed four sub-sections (Cash / Bonds / Equity / Alternatives) parity-exact with parity-matrix line 102; §2.2.2 `$ ReAlloc` side-by-side reference data during authoring (rendering shape Architect Phase 3); plain text editor with line breaks preserved (markdown / rich-text V2+); blank-by-default new-month editor with explicit per-sub-section and global "copy from prior month" affordance (auto-pre-population V2+); author-before-generate capture timing as part of §2.6.3 generation flow; per-report persistence commitment; **write-path RLS commitment carried directly in §2.6.2 body** per §2.4.5 precedent (tenant-scoped commentary authoring; sixth instance of scope-attribute-not-isolation-boundary canonical clause); read-path covered by §2.6.6 Supporting.

**§2.6.3** *Report generation cadence, trigger, and output format* — τ-1 monthly cron + user-on-demand dual-trigger; υ-1 in-app rendered web page (canonical) + PDF export on demand (PDF generation server-side vs client-side = Architect Phase 3); cron schedule fixed at 1st-of-month-for-prior-month with last-day-prior-month data-as-of; user-on-demand target-month selection (prior-month default + current-month-in-progress as-of-today); pending-monthly-report in-app notification + queue affordance (parallel to §2.4.1 iv-1 notification queue pattern); author-before-generate honored under both trigger paths (§2.6.2 commentary editor opens first, blocks finalization); three-state `not-yet-triggered` / `pending` / `generated` lifecycle; overwrite-semantics regeneration with commentary pre-populated from prior snapshot (revision history V2+); PDF as transient download (not server-side persisted artifact; no PDF caching V1); cron failures logged at system level with on-demand trigger as manual fallback (in-app cron-failure notification V2+); per-tenant cron under ADR-002 §1.4. Deliberate §2.6.2-vs-§2.6.3 persistence-tension acknowledged in body: §2.6.2 "historical-month commentary survives unchanged" holds **between regenerations**, not absolutely permanently; revision-history V2+ resolves the tension fully.

**§2.6.4** *Snapshot, historical retention, and report identity* — φ-1 frozen-at-generation snapshot (parity-exact with existing-system PDF freeze-on-export behavior; φ-2 live-rendered and φ-3 toggle both V2+); χ-1 indefinite retention of every generated report (no V1 cleanup / archival / user-deletion; χ-2 current-month-only and χ-3 V2+-archive both rejected); ψ-1 single per-tenant owner-identification config string (multi-named-owner ψ-2 and per-report-override ψ-3 V2+); rendered-value-level snapshot shape (not source-data-level — snapshot does not re-compute when source data changes; detailed table/column shape Architect Phase 3); **owner-identification snapshot-not-live at render time** — historical reports keep the name as-of-generation; settings changes apply forward not retroactively, parallel to §2.5.2 bracket-schedule forward-not-retroactive analog; overwrite-semantics regeneration honoring §2.6.3; in-app reads snapshot directly + PDF re-generates per export (no PDF caching V1); **staleness-marker live-read carve-out** — §2.6.5 staleness markers read LIVE at render time from §2.4.4 credential-error state, NOT from snapshot (deliberate carve-out preserving §2.4.4 non-silent-staleness contract; analog of §2.3.2's "render the data but never lie about its provenance" discipline). ADR-005 settings store extension is the **third additive field** after §2.3.2 planning targets + §2.5.2 bracket schedules; dedup-vs-split is Architect Phase 3 parallel to §2.5.2 dedup flag.

**§2.6.5** *Staleness markers on report surfaces* — α′-1 generate-with-markers, not block-with-warning (preserves operational + integrity contracts: report renders, marker is per-section, user has full information; α′-2 block-with-warning and α′-3 generate-with-banner-only both rejected); marker visual shape = inline per-section indicator + report-level summary banner naming stale-contributing accounts (additive, not substitute; UX detail Architect/Design Phase 2/3); all four §2.4.4-distinguished credential-error states trigger markers uniformly (V1 no per-class subdivision); §2.6.2 Rebalancing Targets and §2.6.4 owner-identification header excluded from marking (non-account-derived); PDF export carries same markers as in-app view at click moment (live-read at export time per §2.6.4 carve-out); historical reports viewed today show CURRENT staleness state at view time (per §2.6.4 carve-out); cron-generated + user-on-demand reports identical marker behavior. **§2.6.5 is §2.4.4's contract enforced one layer up** — closes the §2.4.4 non-silent-staleness commitment §2.6 surface.

**§2.6.6** *Monthly report is mine, not anyone else's* (Supporting; sixth instance of named-surface-scoped tenant-isolation pattern across PRD §2: §2.1.7 + §2.2.4 + §2.3.5 + §2.4.5 + §2.5.5 + §2.6.6); read-path-shape framing (write-path RLS for §2.6.2 commentary carried in §2.6.2 itself, parallel to §2.5.2 settings-UI write-path excluded from §2.5.5); names §2.6.1 + §2.6.2 + §2.6.3 + §2.6.4 explicitly; §2.6.5 not named separately (its read path is §2.4.4 credential-error state, tenant isolation carried by §2.4.5, inherited here); **sixth instance of scope-attribute-not-isolation-boundary canonical clause** (verbatim-equivalent to §2.5.5 / §2.4.5 / §2.3.5 / §2.2.4 / §2.1.7); multi-scope V1 full-household-default per ADR-004 Decision B (closes parity-matrix line 180 per-scope reports V2+); **NEW — snapshot store as persisted derivative surface** of §2.5-grade sensitive-data classes flagged for §4 Sec attention (first derivative-surface persistence layer joining §2 surface inventory at lock; tri-axis tenant_id × scope × tax_treatment framing inherited where underlying classes carry tax-treatment, collapses to tenant_id × scope where no tax-treatment dimension).

**Routing-flags block: 12 Architect items (a)-(l) + 6 Sec items (i)-(vi) + 4 carry-forward bullets** (Sec product-disclaimer ratified PM-default; no new ADR for §2.6; Sec at-lock verdict recorded; PR # placeholder). Architect items densest §2 block to date (vs §2.4's 11 and §2.5's 13). Six Sec items mostly Sec-led (snapshot store tenant-scoping; owner-identification settings-store write-path validation; snapshot row as derivative-surface annotation; commentary write-path RLS; staleness-marker live-read cross-tenant signal-leak; cron job tenant-scoping).

**Sec Task #54 verdict: pass-with-comments, no veto, no required revisions** — sixth at-lock Sec pass + **first six-axis pass** with NEW derivative-surface-persistence axis elevated (axis (d) snapshot store as persisted derivative surface; Sec recommends §4 carries a dedicated "Derivative persistence surfaces" sub-section rather than annotating per-class). Five prior Sec axes hold: (a) tenant-isolation read-path framing (sixth instance); (b) multi-scope-ownership-as-data-attribute-not-isolation-boundary canonical clause (sixth verbatim-equivalent instance); (c) `tax_treatment`-attribute-as-inclusion-filter (where §2.6 inherits §2.5-grade classes); (e) write-path-RLS shape extended to §2.6.2 commentary per §2.4.5 precedent; (f) staleness-live-read cross-tenant-signal-leak as new verification surface at §2.6.5. **Sensitive-data classes update for §4 matrix:** §2.6 adds two new classes — (1) Rebalancing Targets free-text commentary (medium-to-high sensitivity; F/CTO strategy reasoning + actionable financial decisions; tenant-scoped; XSS surface on rendered commentary) + (2) owner-identification trust-name string (low individual sensitivity but identity-correlate when aggregated; rendered on every PDF; XSS surface on rendered header) — plus one cross-cutting derivative-surface annotation across multiple existing classes (snapshot store denormalizes Realized + Unrealized Tax Liability + marginal-rate scalars + tax-character categorization + aggregate unrealized G/L by tax_treatment + NAV + allocation deltas + cash flow into single rows; retention sprawl + blast-radius widening + render-time staleness join compound the per-class isolation requirements). Running total entering §3 / §4: thirteen entries (twelve effective classes plus the cross-cutting derivative-surface annotation). **Seven Sec forward-looking comments** for §4 drafting + Phase 3 RLS surfaces (vs §2.5's 5): cross-tenant snapshot store leak; cross-tenant staleness-state read leak verification (most subtle in §2.6 suite — render-time join from snapshot's account_id to §2.4.4 credential-error state must enforce tenant_id); cross-tenant cron worker context isolation; owner-identification settings-store write-path input sanitization (XSS / SQL injection / oversize PDF-OOM / Unicode control / RTL / homoglyph); commentary write-path input sanitization (same battery + copy-from-prior-month must re-validate not bypass); PDF-generation worker-process tenant-isolation (shared Puppeteer / wkhtmltopdf worker pool must not leak fonts / DOM / auth headers / metadata across tenant renders); snapshot regeneration race condition (concurrent regenerations on same (tenant_id, target-month) must produce exactly one row with last-writer-wins or transactional rejection; cross-tenant concurrency must not mix). **Sec product-disclaimer decision:** ratify PM-default — §2.6.5 marker IS the disclaimer; no additional static financial-product disclaimer on every report (would train banner-blindness + dilute marker signal value). Revisit if share-report affordance ever lands.

**F/CTO product-decision locks this session** (8 substantive headline + multiple sub-decision PM-defaults all accepted): (1) ω-1 V1-fixed six-section order + Historical Expenditures inline; (2) σ-1 free-text user-authored + V1-fixed four sub-sections + `$ ReAlloc` side-by-side reference + plain text editor + blank+copy + author-before-generate; (3) τ-1 monthly cron + user-on-demand + cron schedule + target-month + idempotency overwrite + 3-state lifecycle + cron failure handling; (4) υ-1 in-app + PDF export + PDF transient download + render-from-snapshot; (5) φ-1 frozen-at-generation snapshot; (6) χ-1 indefinite retention; (7) ψ-1 single per-tenant owner-ID + snapshot-not-live owner-ID at render + ADR-005 third additive field; (8) α′-1 generate-with-markers + all four §2.4.4 states trigger + §2.6.2/§2.6.4 excluded + live-read on historical + PDF live-read. **Zero PM-lean overrides across all six stories** — PM-lean acceptance rate 3-for-3 on per-story §2.6.1/§2.6.2/§2.6.3 ratification triggered the **bulk-section-review scaling pivot at §2.6.4** per F/CTO direction (mid-session process change documented below).

**Bulk-section-review scaling pivot surfaced this session** — F/CTO direction at §2.6.4 ratify gate: "PM-leans tracking 3-for-3 with zero overrides; the per-story serialization is finding nothing, just adding turns." Process change adopted mid-section: PM bulk-drafts §2.6.4 reformat + §2.6.5 + §2.6.6 + routing-flags + acceptance-flags as a single bundle; F/CTO reviews as a section-level pass; v2 revision only if overrides surface. Bulk closeout succeeded — F/CTO accepted bundle as-drafted, zero overrides triggered. **Pattern pinned for future sections:** when PM-leans track well (2+ consecutive per-story ratifications with zero overrides), CoS proposes bulk closeout for the remainder; F/CTO can redirect to per-story if surface-specific signal warrants. The one-question-at-a-time pacing memory pin remains the *default* for exploratory turns + sections where overrides are likely; bulk closeout is the *scaling release valve* when PM-lean acceptance signals consistency.

**PM body-format normalization required** — §2.6.4 v1 emitted as single continuous paragraph rather than multi-paragraph blockquote with `>` blank-line separators (the §2.6.1/§2.6.2/§2.6.3 + §2.5.x pattern). CoS flagged at relay; PM reformatted as §2.6.4 v1.1 during bulk closeout. **Pattern pinned for future sections:** PM bodies must use multi-paragraph blockquote format with `>` blank-line separators between bold heading-phrases. PM-spawn retry occurred at bulk closeout when initial response emitted meta-statement without content — `agentId` continuation via SendMessage not addressable from CoS context; re-spawn with full brief was the recovery path.

**ADR-005 settings store now carries three additive fields** (§2.3.2 planning targets + §2.5.2 bracket schedules + §2.6.4 owner-identification config); each ADR-005-extending field accumulated additively without ADR amendment. Architect Phase 3 routing flag (e) at §2.6 dedupes or splits this store; Sec re-engagement on the settings-UI plumbing surface triggered at §2.3.2 lock per Sec Task #23 forward-looking comment #3 is the canonical re-engagement framing, with each subsequent additive field treated as an extension within scope rather than a new Sec trigger.

**Engagement notes:** PM workhorse across 9 tasks (#45 structure, #46-#49 §2.6.1-§2.6.4 v1 bodies, #50-#53 bulk closeout reformat + §2.6.5 + §2.6.6 + routing-flags + acceptance-flags; PM-spawn retry at #50-#53 for content emission); Sec single-touch at-lock pass #54 per spawn-on-need framing (no two-touch needed — no mid-draft credential-handling surface emerged; α′-1 staleness-marker decision was operationally substantial but not credential-handling-novel); CoS bookkeeping + 4 ratify gates with F/CTO (structure, §2.6.1, §2.6.2, §2.6.3 individually; §2.6.4-§2.6.5-§2.6.6 + routing + acceptance as bulk bundle per F/CTO direction). Multi-version-body-revision pattern from §2.5 did NOT surface at §2.6 — every PM-lean was ratified first-pass, no v2 body revisions needed. Format-normalization v1.1 (§2.6.4) is the only non-content revision pass.

**Patterns established this session** for forward sections: (a) **bulk-section-review scaling pivot** — process change when PM-leans track 2+ consecutive ratifications with zero overrides; CoS proposes bulk closeout; F/CTO can redirect; one-question-at-a-time remains default for exploratory turns; (b) **PM body-format normalization** as a CoS responsibility — multi-paragraph blockquote with `>` blank-line separators is the canonical PRD body format; flag and request reformat if PM emits continuous-paragraph variant; (c) **PM-spawn retry pattern** — agentId-based SendMessage continuation not addressable from CoS context; full-brief re-spawn is the recovery path when initial PM response emits meta-statement without content; (d) **Sec axis elevation criteria** — when an axis is "substantial enough to track as its own axis rather than fold into [prior axis]," elevate to first-class Sec axis rather than annotation (snapshot-store-as-derivative-surface at §2.6 is the precedent); (e) **§2-series structural completion** — six PRD §2 stories locked closes the V1 user-stories series; next thread is §3 (Success metrics) / §4 (Security and compliance posture, Sec primary author per Task #54 framing) / §5 (V2 deferred candidates) / §6 (Out-of-scope) / §7 (Constraints).

**PR #[TBD]** to be shipped via `/ship-branch` after this WORKFLOW.md changelog lands — seventh real use of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005, PR #17 §2.4 lock, PR #18 §2.5 lock + ADR-006, PR #[TBD] §2.6 lock).

**Next thread:** **§3 / §4 / §5 / §6 / §7 drafting** to close Phase 1 Step 3. Most substantial: **§4 Security and compliance posture (Sec primary author per Task #54 mandatory-next-engagement framing)** — Sec lands the seven Phase 3 RLS test candidates + thirteen-class sensitive-data matrix + six canonical Sec axes as §4 body content. **§3 Success metrics** is a smaller PM-led section; **§5 V2 deferred candidates** and **§6 Out-of-scope** are PM-led inventory sections drawing from prior §2.X V2+ lists; **§7 Constraints** has three sub-stubs (7.1 Cost / 7.2 Scale / 7.3 Usage model). After §3–§7 lock, **Phase 1 Step 4 (Architectural overview)** opens — Sec conditional consult per Task #54 framing. Team-mode (`phase-1` team) per ADR-003 active throughout.

### v1.11 — 2026-05-17

**PRD §2.5 LOCKED** (2026-05-17) — fifth locked PRD section; first locked under the team-mode-with-multi-version-revision pattern that surfaced this session. §2.5 (Estimated taxes — Federal + California FTB primitive form per ADR-004 Decision D) drafted from a bare stub to a 5-story parity-grounded section across Tasks #35 (structure v1), #36 (structure v2 — bracket-aware correction), #37 (§2.5.1 body), #38–#41 (§2.5.2 / §2.5.3 / §2.5.4 / §2.5.5 body drafts + multiple v-revisions integrating F/CTO sub-decision locks one at a time per memory pacing), #42 (Sec at-lock pass), #43 (routing-flags + acceptance-flags block), and #44 (this PRD.md / DECISIONS.md / WORKFLOW.md integration). **Structure: 4 Primary + 1 Supporting**, mirroring §2.4 / §2.3 precedent. §2.5.1 *Tax-relevant income decomposition (Income / ST CG / LT CG)* — three-column current-tax-year decomposition at Sub-Cat granularity; user-marked Sub-Cat `tax_relevant` boolean + `tax_character` enum (5 V1 values: `ordinary` / `qualified_dividend` / `tax_exempt_interest` / `long_term_capital_gain_eligible` / `short_term_only`) per ζ-2 F/CTO lock; Federal routing rules embedded in body (qualified_dividend → Federal LT CG; tax_exempt_interest → excluded; others → ordinary); holding-period via existing-system `calculateSales`-equivalent L-Term? mechanism per η-1; calendar-year V1 scope per θ-1; live recompute. §2.5.2 *Tax-bracket inputs (Federal + California FTB parallel)* — V1 settings UI holds per-jurisdiction bracket schedules + standard deduction; Federal carries two schedules (ordinary + separate LT CG) per λ-default; CA single ordinary schedule per κ-default (CA treats LT CG as ordinary income); single-filing-status V1 per ι-default; settings store extends §2.3.2 planning-targets store per ADR-005 with richer field shape; δ-2 brief echo lock — each §2.5.3 tax table carries one-line applied-rate caption ("Federal ordinary: X% / Federal LT CG: Y%"; "California: Z%") paralleling §2.3.2 planning-targets caption-text pattern. §2.5.3 *Quarterly estimated payment computation + IRS/FTB account tracking* — densest §2.5 story; per-jurisdiction parallel tables (Federal + CA) structured per Finance_Report §11/§12 with Tax Balance Prior Year informational row + four quarterly Estimated Tax Payments + Sub-Total + YTD Paid + Estimated Funds Due gap; **progressive bracket math with standard deduction** as the computation engine (Federal ordinary schedule + Federal LT CG schedule + CA ordinary schedule, routed per §2.5.1 tax_character enum); μ-2 F/CTO lock — V1 ships bracket-derived expected-annual ÷ 4 quarterly installments only; **no safe-harbor floor computation in V1** (Tax Balance Prior Year row informational-only; safe-harbor refinement V2+); ν-1 overpayment-as-negative-single-line + ξ-1 reactive due-date surfacing carry as PM-defaults; IRS + FTB accounts as V1 instances of §2.4.2 manual non-Plaid accounts with §2.4.3 manual-transaction payment recording. §2.5.4 *Realized + Unrealized Tax Liability line items (NAV components)* — closes the §2.1.1 NAV definition + §2.1.5 composition buildup cross-reference contract; Realized = Federal + CA Estimated Funds Due gaps summed (single combined scalar per ρ-default); **Unrealized via ο-a F/CTO-locked simplified marginal × aggregate G/L** (`Federal_LT_CG_top_bracket_rate × aggregate_unrealized_G/L_taxable + CA_top_marginal_rate × aggregate_unrealized_G/L_taxable`) preserving F/CTO Task #2 close verification 2026-05-14 verbatim; **F/CTO 2026-05-17 override on Federal_top_marginal_rate sourcing = Federal LT CG top-bracket rate** (less-conservative parity choice over PM-default ordinary-top; aligns with F/CTO existing Est Taxes sheet treatment); π-default tax-advantaged-account exclusion (V1 includes only `taxable` accounts in Unrealized aggregation per ADR-002 §1.6 three-way tagging; `tax-deferred` + `tax-free` excluded); ρ-default single-line-per-NAV-component rendering; Sec product-disclaimer integrated at V1 boundary clause ("This estimate may understate actual tax owed if any portion of unrealized gain would be realized at short-term rates (ordinary income); users should treat the Unrealized Tax Liability as an LT-aware floor estimate, not a precise tax forecast"). §2.5.5 *Tax surfaces are mine, not anyone else's* (Supporting; γ read-path lock) — fifth instance of named-surface-scoped tenant-isolation pattern across PRD §2 (§2.1.7 + §2.2.4 + §2.3.5 + §2.4.5 + §2.5.5); fourth consecutive read-path-shape framing (§2.4.5 was write-path divergence); names §2.5.1 / §2.5.3 / §2.5.4 explicitly (NOT §2.5.2 — settings-UI write surface stays out of Supporting per γ rationale); **new clarity axis surfaced — three orthogonal query-layer attributes at V1** (`tenant_id` isolation + `scope` data label + `tax_treatment` inclusion filter on §2.5.4 Unrealized aggregation); scope-attribute-not-isolation-boundary clause verbatim-equivalent to §2.3.5 / §2.4.5 canonical formulation per Sec Task #23 endorsement. **Routing-flags block: 13 Architect items (densest §2 block to date — vs §2.4's 11) + 1 dropped flag (n §2.5.3-engine-reuse-for-Unrealized) + 1 PDF-verify-resolved bullet + 1 ADR-006-queued bullet + 1 Sec product-disclaimer-integration bullet + 1 Sec at-lock verdict bullet.** Carry-forward Architect flags (e) bracket-table-update cadence + (f) §2.5.2 settings-store dedup + (g) bracket-schedule routing logic location + (h) filing-status handling; new Architect flags (i) §2.5.3 computation engine storage/caching shape (PM lean i-2 on-demand under μ-2 simpler scope) + (j) IRS/FTB account semantics (PM lean j-1 standard-account-with-overlay) + (l) aggregate unrealized G/L computation surface + (m) tax-advantaged exclusion mechanism; §2.5.1 origin flags (a) Sub-Cat tax_character schema + (b) cross-source join (cash-flow + Sales) + (c) tax-year boundary + (d) holding-period source-of-truth. **F/CTO 2026-05-17 bracket-aware correction surfaced during structure-proposal v2** — ADR-004 Decision D's "Federal marginal rate input" / "separate marginal rate input" wording was audit-derived re-narration of incomplete reading; F/CTO direct workflow knowledge revealed existing Est Taxes sheet uses marginal bracket tables + standard deduction (bracket-aware progressive computation). **ADR-006 drafted alongside §2.5 lock** — two-axis amendment to ADR-004 Decision D input-layer characterization: Axis 1 (§2.5.2-scope) bracket schedules + standard deduction; Axis 2 (§2.5.1-scope) Sub-Cat `tax_character` enum with 5 V1 values + Federal routing rules. Both axes operationalize Decision D's "Primitive means" rather than expanding it (multi-state, non-US, lot-level features stay V2+ unchanged). Sec one-line sensitivity note woven into ADR-006: "data class #1 sensitivity incrementally higher post-amendment; storage / access-control posture unchanged." ADR-006 supersedes nothing; amends ADR-004 specifically (parallel to ADR-005's amendment of ADR-002 §1.2). **Sec Task #42 verdict: pass-with-comments, no veto, no required revisions** — fifth dual-axis Sec pass + **first tri-axis Sec pass** (axis (c) `tax_treatment`-as-inclusion-filter-not-isolation-boundary clarification NEW this section; endorsed as canonical for §4 verbatim promotion). **Six sensitive-data classes for §4 matrix** at Sec primary-author engagement: (1) tax-bracket-revealing data (§2.5.2 — upgraded sensitivity per F/CTO 2026-05-17 bracket-aware correction from original scalar form); (2) tax-character categorization patterns (§2.5.1 Sub-Cat enum); (3) marginal-rate scalars (Federal LT CG top-bracket + CA ordinary top-bracket — §2.5.4 inputs); (4) Realized + Unrealized Tax Liability scalar values (§2.5.4 NAV-components); (5) aggregate unrealized G/L by tax_treatment (§2.5.4 input); (6) NEW sub-class — §2.5.3 quarterly est-payment ledger + IRS/FTB account ledger state (class-1 derivative + behavioral correlate). **Five Sec forward-looking comments** for §4 drafting + Phase 3 RLS surfaces (see PRD §2.5 routing-flags block). **PDF-verify pass skipped per F/CTO 2026-05-17 direction** — nine items originally surfaced as parity-verify-against-Finance_Report-PDF-and-Est-Taxes-sheet candidates (ε / ι / κ / λ / ν / ξ / π + Federal LT CG sourcing parity + California quarterly cadence) resolved as F/CTO PM-default acceptance via direct-workflow-knowledge; verification deferred to V1 implementation if divergence surfaces against existing-system behavior. **F/CTO product-decision locks this session** (7 substantive sub-decisions + 2 v-revision-driven overrides): (1) **bracket-aware correction** (structure proposal v2) — overrode PM's audit-derived "marginal-rate input" framing; (2) ζ-2 Sub-Cat tax-character enum with 5 V1 values + Federal routing; (3) η-1 holding-period source = existing `calculateSales`-equivalent L-Term?; (4) θ-1 calendar-year tax-year V1; (5) δ-2 brief echo on §2.5.3 tables; (6) μ-2 bracket-only quarterly installments (NOT PM-lean μ-1 max-with-safe-harbor — F/CTO chose simpler V1); (7) ο-a simplified marginal × aggregate G/L preserving Task #2 verification; (8) **Federal LT CG top-bracket sourcing override on §2.5.4** (rejected PM-default Federal ordinary top — F/CTO chose less-conservative parity over PM's conservative default); (9) PDF-verify skip per F/CTO 2026-05-17 direct-workflow-knowledge acceptance. **No ADR-006-superseding scope expansion** — both axes operationalize Decision D "Primitive means" rather than expanding it; μ-2 + ο-a + PDF-verify-skip are within-Decision-D-scope simplifications, not amendments. **Engagement notes:** PM workhorse across 9 tasks (#35 structure v1, #36 structure v2, #37 §2.5.1 body v1, #38 §2.5.2 body v1, plus mid-task v-revisions of §2.5.1/§2.5.2/§2.5.3/§2.5.4 integrating F/CTO sub-decision locks one at a time per one-question-at-a-time memory pacing — §2.5.4 reached v3 with the Federal LT CG sourcing override); Sec spawn-on-need for Task #42 at-lock pass — single touch (no two-touch consult anticipated absent mid-draft credential-handling surfaces, per §2.4 Task #33 framing for §2.5; framing held); CoS bookkeeping across all 9 tasks plus the §2.5-lock cleanup pass orchestration. **Multi-version-revision pattern surfaced** as a recurring §2.5 workflow shape — F/CTO sub-decision lock turns triggered v2 / v3 body revisions of already-sent bodies (vs §2.3 / §2.4 pattern where most body drafts landed in single-version form). Memory pinned: when F/CTO over-rides PM-defaults at body lock turns, expect mechanical-override-pass v-revision; full-revised-body-for-self-contained-F/CTO-confirmation is the working pattern. **Audit-derived-ADR-text feedback applied retroactively** — ADR-006 documents that the original ADR-004 Decision D "marginal rate input" wording was audit-derived re-narration, not a deliberate F/CTO scope decision; future ADRs re-narrating audit findings should be verified against direct artifact inspection at body-drafting time. **Patterns established this session** for forward sections: (a) multi-version body-revision shape when F/CTO sub-decision locks chain mid-section (PM workflow: full-revised-body-for-each-revision with deltas-vs-prior-version section at end); (b) PDF-verify-skip-via-F/CTO-direct-workflow-knowledge as a §2.5-lock cleanup variant (vs prior §2.X pattern of F/CTO PDF inspection during body drafting); (c) tri-axis Sec verdict shape (tenant_id + scope + tax_treatment as three orthogonal query-layer attributes); (d) Sec product-disclaimer routing as a §2.5-lock-cleanup integration item separate from at-lock Sec pass; (e) audit-derived-ADR-text-correction-via-amendment as an ADR pattern (parallel to ADR-005 amendment of ADR-002 §1.2 but motivated by audit-derived-wording rather than parity-evidence). **PR #[TBD]** to be shipped via `/ship-branch` after this WORKFLOW.md changelog lands — sixth real use of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005, PR #17 §2.4 lock, PR #[TBD] §2.5 lock + ADR-006). **Next thread:** §2.6 (Monthly Report — canonical V1 deliverable, Finance_Report-shape) drafting. §2.6 is the home of the monthly Finance_Report generation surface that consumes §2.1 / §2.2 / §2.3 / §2.5 rendering data into the canonical PDF-equivalent deliverable F/CTO produces monthly today; per ADR-004 Decision D consequences §2.6 was queued as a new §2 section to formalize the Finance_Report-shape V1 deliverable as a first-class product surface; Sec re-engagement standard at-lock per Sec Task #42 framing; §4 Security and compliance posture remains Sec primary author surface and may interleave with §2.6 drafting given the running data-class set is now 6 + Plaid + write-path classes from §2.4.

### v1.10 — 2026-05-15

**PRD §2.4 LOCKED** (2026-05-15) — fourth locked PRD section; first to lock on 2026-05-15 (§2.1/§2.2/§2.3 all locked 2026-05-14). §2.4 (Cross-cutting stories — account onboarding, manual entry, re-auth) drafted from a bare stub to a 5-story parity-grounded section in one extended session via Tasks #26 (structure), **#27 (Sec early consult — NEW two-touch pattern)**, #28/#29/#30/#31/#32 (4 Primary + 1 Supporting story bodies), #33 (Sec at-lock verdict), and #34 (routing-flags + acceptance-flags block). **Structure: 4 Primary + 1 Supporting**, no renumbering required mid-section (vs §2.3's option-(A) renumbering). §2.4.1 *Plaid account onboarding and new-symbol surfacing* (OAuth flow with server-side `/link/token/create` + `/item/public_token/exchange`; tenant-scoped access-token persistence; account-share-decision authoritative storage with **Sec-(b)-2 explicit opt-in for newly-available institution accounts**; per-account scope/tax-treatment/account-type attribute setting with Plaid metadata as recommendation; **(iv) iv-1 notification queue + iv-3 sync-time Unsorted-Sub-Cat default + Plaid-metadata-as-recommendation-at-assignment-time** for new-symbol surfacing; symbol-registry-maintenance folded here per structure proposal). §2.4.2 *Manual non-Plaid account onboarding* (guided flow with no Plaid Link / OAuth / credential prompt; scope/tax-treatment/account-type/initial-value-as-of-date/Sub-Cat attribute setting; **inactive-flag V1 inclusion per existing-system parity**; bulk-import V2+; initial-value entry implemented as synthetic AcctSetup-flagged transaction to keep data model uniform with §2.3.1's transaction-to-bucket-assignment shape). §2.4.3 *Manual transaction entry (cash and AcctSetup non-cash events)* — **densest §2.4 body**; three sub-flows (cash transaction entry + AcctSetup non-cash event entry + Plaid-vs-manual reconciliation) with all **(i) locks** applied (Axis A2 silent dedup + on-demand audit log; **Axis B1+B2 V1 reconcile with B3 V2+** — closes parity-matrix open product decision #7 "Reconciled $ running balance" as V1-capability; Axis C1 implicit skip via delete with deleted/skipped view; Axis D hash composition Architect-flagged with PM-rec embedded — Plaid `transaction_id` primary + content hash secondary, splits as parent-child) and **(iii) locks** applied (iii-A-1 generic AcctSetup mode in same manual transaction UI with event subtype enumeration; iii-B-3 Plaid-surfaced and user-entered AcctSetup events as peers via hash + reconcile pattern); data-model expansion (6 additive sibling fields to §2.3.1's Sub-Cat assignment: `plaid_transaction_id`, `content_hash`, `skip_flag`, `reconciled_flag`, `reconciled_at`, `event_subtype`); lot-level tax features explicitly routed to §2.5 not §2.4. §2.4.4 *Plaid re-authentication and credential lifecycle* — closes ADR-002 §7.0 item 9 V1 PRD gap; **(ii) reactive cadence + Sec-recommended persistent in-app banner UI**; all six Sec Task #27 early-consult body clauses landed (three veto-eligible: server-side token lifecycle, access-token credential-class protection, **non-silent staleness across every consuming surface — headline V1 product commitment naming §2.1.2 / §2.1.5 / §2.2.2 / §2.3.2 / §2.3.4 / §2.6 explicitly**); four credential-error states distinguishable at data-model level; per-account connection-state UI surface with last-successful-sync timestamp + banner re-auth affordance. §2.4.5 *Onboarding, entry, and re-auth write paths are mine, not anyone else's* (Supporting) — **first write-path-shape Supporting story across PRD §2** (vs §2.1.7 / §2.2.4 / §2.3.5 read-path framing); shape divergence intentional and parity-justified (§2.4 is write-heavy); names §2.4.1–§2.4.4 explicitly per named-surface-scoping pattern; **write-path RLS symmetry clause as PRD-locked product commitment** (closes Sec Task #23 forward-looking comment #3 for entire §2.4 write surface, not just the §2.3.2 settings-UI plumbing it was originally scoped to); multi-scope-attribute clause verbatim-equivalent to §2.3.5 canonical formulation (fourth consecutive continuity instance); manual-entry write-path elevated-integrity-risk acknowledged with concrete example (5-year-ago `buy` at arbitrary price → cost-basis cascade). **Routing-flags block: 11 Architect/Sec-joint items + 1 Sec pass-recorded bullet — densest §2 routing-flags block to date** (vs §2.1's 6, §2.2's 6, §2.3's 9+1). Five flags carry explicit Sec-joint or Sec-led tags (#2 account-share-decision joint; #7 access token storage shape Sec-led; #8 credential-error state model joint; #10 manual-entry write-path integrity joint; **#11 Plaid webhook signature verification Sec-led** — new from Sec Task #33 verdict, not surfaced in Task #27 consult or any body draft, mandatory before V1 ship) — first instance of Sec-led routing flags in PRD §2 alongside the established Architect-led pattern, reflecting §2.4's credential-handling + write-path density. **NEW two-touch Sec engagement pattern adopted for §2.4** at F/CTO acceptance of PM structure proposal — Task #27 was the first non-verdict Sec consult in Phase 1 (Task #8 / Task #14 / Task #23 were all standard at-lock verdicts). Sec consult input shaped §2.4.1 + §2.4.4 + §2.4.5 body drafts before they were authored; Task #33 at-lock verdict verified all twelve consult clauses (six veto-eligible + six non-veto) landed correctly. Sec Task #33 explicitly endorsed two-touch pattern as "tightest yet" — engagement pattern carried forward as available-on-demand for future sections (not mandatory; §2.5 will use standard spawn-on-need at lock unless mid-draft surfaces warrant earlier consult per Sec Task #33 framing). **Sec Task #33 verdict: pass-with-comments, no veto, no required revisions** — fourth dual-axis Sec pass with axis (a) tenant isolation extended for write-path framing (§2.4.5 elevates RLS-on-writes from inferred architectural detail to explicit PRD-locked product commitment, names §2.4.1 / §2.4.2 / §2.4.3 / §2.4.4 mutation paths) and axis (b) multi-scope-attribute clause continuity confirmed verbatim-equivalent to §2.3.5 canonical formulation. **Three new sensitive data classes** for running §4 matrix: Plaid access tokens (credential class, distinct from data class); Plaid Item-state metadata (low sensitivity individually, behavior-correlate when aggregated — sync patterns reveal financial-activity timing); Plaid account-share-decision data. **New Phase 3 RLS test surfaces**: write-path RLS tests on §2.4.1 / §2.4.2 / §2.4.3 / §2.4.4 mutation paths; per-tenant Plaid Item table RLS (access tokens + Item-state metadata); per-tenant account-share-decision table RLS; tenant-scoped read on §2.4.3 sync-history audit log. **F/CTO product-decision locks this session** (6 substantive + sub-decisions): (1) (i) Plaid-vs-manual conflict resolution four-axis compound — substantive workflow context F/CTO surfaced reshaped PM's original A/B/C framing into a mechanism-rich hash-skip-reconcile model, PM re-framed as four product-surface axes A/B/C/D, F/CTO locked PM-rec across all axes; (2) (ii) reactive re-auth cadence + persistent banner UI; (3) (iii) AcctSetup UX two-axis compound — iii-A-1 generic mode + iii-B-3 both paths peers; (4) (iv) new-symbol surfacing three-piece compound — iv-1 notification queue + iv-3 sync-time Unsorted + Plaid-metadata-as-recommendation-at-assignment-time (F/CTO-originated compound, not PM-proposed; "having Unsorted assets probably breaks a few of the widgets" + "a recommendation would be helpful... when the user goes through the notifications to assign the fields" shaped the recommendation-at-assignment-time framing); (5) Sec-(b)-2 explicit opt-in for newly-available institution accounts (per Sec recommendation); (6) §2.4.2 inactive-account V1 inclusion. **No ADR-006 needed** — all §2.4 locks fold cleanly into PRD body + routing-flags per CoS + PM concurrence: (i) data-model expansion is additive to §2.3.1 (no §1.4/§1.5/§1.7 displacement); (iii) AcctSetup operationalizes ADR-004 Decision C additively (no §1.8 / Decision C displacement); (iv) operationalizes Decision C's hybrid clause with Unsorted bootstrap addition; Sec-(b)-2 + (ii) close ADR-002 §1.3 / §7.0 item 9 framings without amendment surfaces. ADR-005 precedent for dedicated-ADR-over-section-lock-absorption was the §1.2 non-goal amendment introducing a genuinely new V1 user-facing capability (settings UI); §2.4 introduces no parallel surface. **Engagement notes**: PM workhorse across 8 tasks (#26 structure, #28/#29/#30/#31/#32 story bodies, #34 routing-flags + acceptance-flags); Sec engaged twice (Task #27 early consult + Task #33 at-lock verdict) — first §2 section with two Sec touches per ADR-003 spawn-on-need extended for the two-touch pattern; CoS bookkeeping for the F/CTO (iv) compound that PM re-constructed mid-flow. **Patterns established this session** for forward sections: (a) two-touch Sec engagement available on-demand for high-credential-density sections (§2.4 prototype; §2.5+ use spawn-on-need at lock as default); (b) write-path-shape Supporting story alongside the established read-path-shape pattern (§2.4.5 is the prototype); (c) Sec-led routing flags alongside the established Architect-led pattern (§2.4 flags #7 + #11); (d) **F/CTO-originated compound product decisions** (the (iv) iv-1+iv-3+Plaid-metadata-as-recommendation compound was F/CTO-authored not PM-proposed; future sections may surface similar compounds and PM/CoS should be ready to re-frame). **PR #17** shipped via `/ship-branch` — fifth real use of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005, PR #17 §2.4 lock). **Next thread**: §2.5 (Estimated taxes — Federal + California FTB primitive form per ADR-004 Decision D) drafting. §2.5 is the home of estimated quarterly tax payment computation, parallel Federal + California FTB marginal-rate inputs, IRS / FTB account tracking, Realized + Unrealized Tax Liabilities line items (already referenced from §2.1.1 NAV definition), and the V1/V2 boundary on lot-level tax features (FIFO/LIFO/specific-ID, wash-sale detection, Section 1256 60/40 — V2+ per ADR-002 §1.7 + ADR-004 Decision D "Primitive means" clause). Sec re-engagement: standard at-lock pass (no two-touch anticipated unless external tax-data API surfaces during drafting per Sec Task #33 framing); §4 Security and compliance posture remains Sec primary author surface and may interleave with §2.5 drafting given the three §2.4-contributed data classes need landing in §4 matrix.

### v1.9 — 2026-05-14

**PRD §2.3 LOCKED** (2026-05-14) — third locked PRD section. §2.3 (Spending and income categorization) drafted from a bare stub to a 5-story parity-grounded section in one session via Tasks #16 (structure), #17/#18/#20/#21/#22 (4 Primary + 1 Supporting story bodies), #19 (page-3 re-inspection), #23 (Sec pass), #24 (routing-flags + acceptance-flags block), and #25 (ADR-005 draft + this changelog + PR). **Structure: 4 Primary + 1 Supporting** after option-(A) renumbering (per §2.1.4-insertion precedent at v1.6) when §2.3.5 Historical Expenditures was added mid-section: original 3+1 (§2.3.1/§2.3.2/§2.3.3 Primary + §2.3.4 isolation Supporting) became 4+1 (§2.3.1/§2.3.2/§2.3.3/§2.3.4 Primary + §2.3.5 Supporting); chart story moved into §2.3.4 slot and isolation Supporting renumbered to §2.3.5 to preserve "all Primary then all Supporting" ordering matching §2.1/§2.2. §2.3.1 *Two-level cash-flow taxonomy and transaction-to-bucket assignment* (Decision C cash-flow half parallel to §2.2.1's asset half; V1 data model + F/CTO-seeded Master.CashFlowCategories at bootstrap + V1 per-transaction Sub-Cat assignment UI + recurring-vendor inference V1 with Plaid-category-as-default; user-editable taxonomy CRUD V2+). §2.3.2 *Cash flow categorization across accounts by multi-period* (canonical Finance_Report page-6 surface — Income + Expenses two-section rendering with flat Sub-Cat rows; 7-column Category/Month/Q1-Q4/YTD shape with Month visual emphasis; OtherCF omitted from cross-account rollup but renders in §2.3.3 — asymmetry intentional per existing-system parity; **planning-targets static reference-value rendering V1 (per ADR-005)** as inline caption text under section titles with no variance/alert mechanic + V1 user-editable settings UI). §2.3.3 *Per-account cash-flow drill-down* (per-account-scoped peer of §2.3.2; **3 Cat sections** Income/OtherCF/Expenses adding OtherCF vs §2.3.2's 2-section; **as-of-date toggle V1** per F/CTO (a) lock with backend-replacement rationale; replacement-not-layered framing — §2.3.3 is V1 replacement for the existing per-account Cash Flow sheets, not a layered alternative). §2.3.4 *Historical Expenditures* (**expenses-only time-series chart** caught via PDF inspection during §2.3.2 work — rolling 5-year window of monthly bars + 12-month rolling-average overlay inflation-normalized to today's $ matching §2.1.2's chart-overlay convention; **F/CTO asymmetry rationale woven into V1/V2 clause** — capital-gains-from-rebalancing partially fund expenses → expense time-series isolates the expense signal cleanly while income mirror would entangle with realization decisions; **income time-series + multi-year historical income recordkeeping V2+** per (α) lock; cross-section structural parallel: §2.3.4 is to §2.3.2 what §2.1.2 is to §2.1.1). §2.3.5 *Cash flow categorization is mine, not anyone else's* (Supporting; third instance of named-surface-scoped tenant-isolation + multi-scope-aggregation pattern across §2 after §2.1.7 + §2.2.4; names §2.3.2 + §2.3.3 + §2.3.4 explicitly; **scope-attribute-not-isolation-boundary clause endorsed by Sec Task #23 as canonical for §4 verbatim**). **Routing-flags block:** 9 Architect items (cash-flow taxonomy data model with §2.2.1 overlap; transaction-classification heuristic mechanism per inference V1 lock; cross-account per-period cash-flow aggregation query path; V1 settings UI plumbing for planning targets — Sec re-engagement triggered; planning-targets storage shape; **as-of-date as system-wide query-time parameter — Phase 3 RLS test obligation attached**; per-account scoping query path; drill-down view capability paralleling §2.2.3 flag; V1 expense-transaction data retention horizon ≥ 5 years with differential retention by Cat) plus 1 CPI-U cross-ref (no new flag — four V1 surfaces now share one CPI-U source decision: §2.1.2 + §2.1.3 + §2.1.4 + §2.3.4) plus 1 Sec pass-recorded bullet. **Sec Task #23 verdict: pass-with-comments, no veto, no required revisions** — third dual-axis Sec pass, tightest yet; §2.3.5's scope-attribute clause endorsed verbatim for §4 promotion. New axis vs §2.1.7 + §2.2.4: §2.3.3 as-of-date toggle as first user-supplied query-time parameter on multi-tenant data path in V1 — product-level pass with Phase 3 RLS test obligation. **Three new sensitive data classes** added to running §4 matrix: (1) per-transaction merchant/vendor identifier data — highest-sensitivity addition (PII-adjacent + behavior-revealing); (2) user-authored planning targets per ADR-005; (3) derived cash-flow categorization patterns / assignment-history layer. **Three forward-looking comments captured**: Phase 3 explicit RLS test surface for as-of-date-parameterized query path (joins §2.1.5 composition-view + §2.2.1 per-tenant taxonomy registry test surfaces from prior passes); Architect storage-shape decision on merchant/vendor access controls beyond tenant RLS; Sec re-engagement when §2.3.2 settings-UI plumbing surfaces. Sec re-engagement mandatory at §2.4 + §4; Sec is primary author at §4. **ADR-005 — single ADR-002 §1.2 amendment** formalized: planning-targets V1 static reference-value rendering as parity-preserve with existing Finance_Report (no variance/alert/budget-tracking mechanics — those remain V1 non-goals) + V1 user-editable settings UI (first concrete V1 surface needing a user-editable settings store). CoS chose dedicated-ADR over section-lock-absorption for (a) DECISIONS.md discoverability and (b) consistency with ADR-004's amendment-by-ADR pattern. **Scope note on §1.2 amendments NOT in ADR-005**: §2.3.1 inference layer V1 and §2.3.4 expenses-only chart V1 are both technically §1.2 amendments in shape ("recurring-transaction detection" and "category-level trend charts" listed as V1 non-goals in original §1.2) — not consolidated because §2.3.1's inference is a sub-decision within a V1-required surface (not a stand-alone expansion) and §2.3.4 was caught via PDF inspection as parity-grounded existing-system surface (not a V1 expansion). Both documented in §2.3 PRD traces + routing-flags; ADR-005 covers only planning-targets because that introduces a genuinely new V1 user-facing capability (the settings UI). **Three PDF-inspection-first course-corrections in §2.3** — fourth/fifth/sixth instances of the lesson pattern across §2.1/§2.2/§2.3: (1) OtherCF rendering discrepancy between parity-matrix line 60 (3 Cats per-account) and lines 103-104 (only Income + Expenses enumerated as Finance_Report sections) resolved at §2.3.2 v1 via PM PDF inspection — OtherCF absent from page 6, present on §2.3.3 per-account drill-down; (2) F/CTO-surfaced page-3 income chart that didn't exist — PM full-PDF sweep ruled out income time-series in the canonical Finance_Report (page 3's "Category Totals" chart is §2.1.2 NAV-by-Cat asset-side with legend names Real Estate / Cash / Bonds / Equities / Alternatives / Liabilities; "Category" overloaded between asset Cat and cash-flow Cat mental models); F/CTO confirmed scenario (i) + (α) on follow-up clarification; (3) $30k Y-axis figure caught by CoS in §2.3.4 trace and redacted to structural framing per v1.8 redaction policy. **CoS-side learning captured**: page-range-scoped briefs miss cross-page topic content — my §2.3.2 brief scoped PDF inspection to pages 6+ (because §2.3 territory was understood as starting after §2.2 on pages 4-5) and missed the page-7 Expense Totals chart at first scan (caught at §2.3.2's PDF-inspection-first pass anyway, surfaced as §2.3.5 → §2.3.4 after F/CTO call). Forward briefs scope PDF inspection by topic, not by sequential page range. **Minor invention caught**: PM introduced "V2 user-editable per-account taxonomy overrides" V1/V2 boundary clause in §2.3.3 not parity-grounded (existing system soft-links Master.CashFlowCategories into all per-account workbooks; no per-account taxonomy variation in active use). CoS flagged for removal; F/CTO chose to keep as benign V2 boundary clause. Pattern: CoS scrutiny role caught non-parity-grounded scope drift; F/CTO retained editorial authority on the call. **F/CTO product-decision locks this session** (5 substantive): (1) planning-targets (a)(i) — V1 static reference rendering + V1 user-editable settings UI (formalized via ADR-005); (2) inference layer V1 — Plaid-category-as-default + recurring-vendor inference (per §2.3.1 accept-as-drafted); (3) as-of-date toggle V1 on §2.3.3 — with backend-replacement rationale (V1 replaces parts of Master / Per-Account Workbooks / Asset Summary per §8 drop-replace migration pattern → year-end reconciliation can't fall back to existing system in V1); (4) Historical Expenditures = §2.3.4 V1 Primary via option-(A) renumbering — F/CTO-confirmed scenario (i)/(α) ruled out income time-series chart in V1 with substantive rebalancing-realization-funds-expenses asymmetry rationale; (5) per-account-taxonomy-override V1/V2 sentence kept in §2.3.3 trace per F/CTO editorial call. **Engagement notes**: PM workhorse across 8 tasks (#16 structure, #17/#18/#20/#21/#22 story bodies, #19 page-3 re-inspect, #24 routing-flags + acceptance-flags block); Sec spawn-on-need for Task #23 only — Sec teammate spawned fresh in this session (vs §2.2's Task #14 where Sec was already-spawned-and-woken-via-SendMessage from §2.1's Task #8) reflecting fresh-session implication of in-process team store; engagement pattern (PM workhorse + Sec spawn-on-need-at-section-lock) per ADR-003 continues to scale. **PR #16** shipped via `/ship-branch` — fourth real use of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005). **Next thread**: §2.4 (Cross-cutting stories — account onboarding, manual entry, re-auth, AcctSetup non-cash events, Plaid-pulled-vs-manual transaction reconciliation, Plaid re-auth credential lifecycle, manual transaction entry mechanics) drafting. §2.4 has a heavier security surface than §2.1-§2.3 — touches authentication, OAuth/credential handling, and write paths — Sec re-engagement is mandatory at §2.4 lock per Sec Task #23 forward-looking note; Sec may need to engage earlier than section-lock if Plaid credential-handling sub-decisions surface during drafting.

### v1.8 — 2026-05-14
**PRD §2.2 LOCKED** (2026-05-14) — second locked PRD section. §2.2 (Asset allocation) drafted from a bare stub to a 4-story parity-grounded section in one session via Tasks #9 (structure), #10/#11/#12/#13 (4 story bodies), #15 (routing-flags + acceptance-flags drafting), and #14 (Sec Reviewer pass). PR #14 (`8272613`). **Structure: 3 Primary + 1 Supporting.** §2.2.1 *Two-level asset taxonomy and holding-to-bucket assignment* per ADR-004 Decision C (V1 taxonomy data model + F/CTO-seeded at bootstrap + V1 holding-assignment UI for per-symbol securities and per-account manual assets; V2 user-editable CRUD UI). §2.2.2 *Non-RE allocation table* per ADR-004 Decision A (5-column structure `% Target / % Alloc / $ Target / $ Alloc / $ ReAlloc`; sign convention positive = underweight; Sub-Cat granularity grouped under Cat-group headers per existing-system parity; Real Estate excluded per F/CTO's non-liquid-asset rationale; **Liabilities Cat group flagged as intentional V1 extension** with F/CTO "leverage options" rationale — not in existing Finance_Report's table; auto-suggestions V2+). §2.2.3 *US Equity sub-allocation* (drill-down into §2.2.2's "US - Sector Diversified" Sub-Cat row; 12 rows = 10 US sectors `[01] Basic Materials` through `[10] Utilities` plus 2 non-sector US Sub-Cats `Index Non-Sector` and `Growth Non-Sector`; denominator is Total US Equity; ex-US sub-allocation V2). §2.2.4 *Allocation is mine, not anyone else's* (Supporting, parallel to §2.1.7: tenant isolation per ADR-002 §1.4 + multi-scope full-household aggregation default per ADR-004 Decision B; per-scope reporting + scope-aware filtering UI V2+; references §2.2.2 + §2.2.3 by name in body — Sec verdict flagged this named-surface scoping as a positive tightening vs. §2.1.7's generic "net worth view" framing). **Routing-flags block:** 6 Architect items (multi-level user-scoped taxonomy data model from §2.2.1; Sub-Cat-aware holdings aggregation query path from §2.2.2 + §2.2.3; target allocation storage shape from §2.2.2 — bidirectional architectural-overlap note with the taxonomy flag; Real Estate / non-liquid Cat semantics from §2.2.2; Liabilities-as-Cat semantics from §2.2.2 — asymmetric data flow with §2.1.5 Debt subtotal; drill-down view capability from §2.2.3) plus 1 Security Reviewer pass-recorded bullet. **Sec Task #14 verdict: pass-with-comments, no veto, lighter than Task #8** as predicted; dual-axis assessment from Task #8 (tenant isolation per ADR-002 §1.4 + scope-attribute-not-isolation-boundary per ADR-004 Decision B) carried forward as precedent; both axes confirmed. Three cross-section notes (no flags) extend Task #8's forward-looking comment set: (1) §2.2.1 AssetDB-style symbol→Sub-Cat registry must be per-tenant in V1 — adds a second explicit Phase 3 RLS test surface alongside §2.1.5 composition-view query path; (2) target allocations per Sub-Cat are a new sensitive data class for PRD §4 data-sensitivity matrix — matrix now includes account balances + holdings/tickers/quantities + marginal tax rates + target allocations / portfolio strategy; (3) §2.2.2 Liabilities Cat group leverage-management surface exposes leverage strategy alongside current debt position — useful callout for §4 matrix. Sec's existing §2.4 / PRD §4 re-engagement triggers cover §2.2's data-class extensions; no new re-engagement triggers. **Mid-section PDF-inspection course-correction:** §2.2.2 v1 and §2.2.3 v1 proposals had three parity drifts (Cat-level vs Sub-Cat granularity; sectors-only vs US-Equity scope; sector-total vs Total-US-Equity denominator) plus a Liabilities-parity-claim drift (PM had presented Liabilities Cat as parity-grounded when it's an intentional V1 extension). F/CTO direct read of `Finance_Report_2026_04.pdf` pages 4-5 surfaced all four; v2 revisions of both stories landed before commit. Second instance of "PDF inspection-first" lesson after §2.1.3 v3; captured in task metadata for future reference. **New project-wide policy adopted in-session:** PRD parity-evidence redacts concrete $ figures from versioned artifacts (PRD.md is committed to GitHub; $s from F/CTO's existing personal financial data don't live in committed history). Structural detail (column structure, row names, %s, Cat/Sub-Cat names) retained. Memory-pinned at CoS for forward sessions. Applied retroactively (§2.2.2 v2 traces stripped of cell-level $ values during application); §2.1 verified clean. **Engagement notes:** PM as workhorse across 7 tasks (#9 structure, #10/#11/#12/#13 story bodies, #15 routing-flags block; plus v2 revisions of #11/#12 mid-flow); Sec re-engaged for Task #14 only (already-spawned teammate from Task #8 woken via SendMessage rather than re-briefed). Engagement pattern (PM workhorse + Sec spawn-on-need at section-lock) continues to scale per ADR-003. **PR #14** shipped via `/ship-branch` — third real use of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2). **Next thread:** §2.3 (Spending and income categorization) drafting — structurally similar to §2.2 with a parallel two-level taxonomy (Income / Expenses / OtherCF / AcctSetup per parity-matrix line 121) but cash-flow framing instead of allocation. Likely faster than §2.2 given the pattern is now established.

### v1.7 — 2026-05-14
**PRD §2.1 LOCKED** (2026-05-14) — first locked PRD section. Final-lock checklist from v1.6 cleared via Tasks #6/#7/#8 landing in PR #12 (`414a82d`). **Task #6 (§2.1.2 chart-overlay extension):** body extended from 1 sentence to 4 (granularity hybrid preserved + inflation-adjusted overlay clause added + combined rationale + V1/V2 boundary on rolling-window dimension). Overlay specifics: second NAV line on the same chart, normalized to today's $ value using CPI-U, visually distinct from the nominal line, 60-month rolling window, drawn simultaneously not toggled — direct parity with the existing Finance_Report Category Totals chart on page 3. Today's-$ basis explicitly distinguished from §2.1.3 / §2.1.4 prior-Year-End basis in traces: two different inflation surfaces, two different normalization points, both intentional in the existing system. Single CPI-U series feeds all three surfaces (§2.1.2 chart, §2.1.3 panel, §2.1.4 reference-values table); one Architect CPI-U sourcing decision serves all three. **Task #7 (§2.1.5 composition NAV-buildup extension):** §2.1.5 restated as a single integrated table matching the existing Finance_Report Account Holdings layout (parity-matrix line 99) — six-subtotal buildup sequence (Total Non-RE → Gross Total → Debt → Realized Tax Liabilities → Unrealized Tax Liabilities → Net Assets Value (NAV) at the foot); per-row format adds current value + unrealized gain/loss columns (parity-grounded V1 surface elevation, accepted into scope by F/CTO); Real Estate as distinct group within asset half (required for the Total Non-RE subtotal transition); drill-down preserved (collapsed-by-default, expand-on-demand) over strict-parity all-accounts-visible per F/CTO SaaS-UX justification. Makes the four-component NAV definition from §2.1.1 visually traceable from its parts. **Task #8 (Security Reviewer pass on §2.1.7):** first real Security-Reviewer-as-teammate exercise post-ADR-003 smoke-test. Verdict: **pass-with-comments, no veto, no required revisions.** Dual-axis assessment captured: (a) tenant-isolation language ("no possibility of another user's data appearing") holds against ADR-002 §1.4's tenant_id + RLS commitment when read as user-facing product expectation — the system must back the claim, which is Architect Phase 3 work; (b) multi-scope-attribute-not-isolation-boundary confirmed via three independent pieces of prose evidence — aggregation-as-default + ownership-label examples + explicit data-attribute framing. No conflation of scopes with tenants anywhere in §2.1 or §1.4 deferrals. **Three cross-section notes (no flags, no veto):** §2.1.1 Decision D marginal-rate storage as new sensitive-data class under standard RLS posture; §2.1.5 per-account drill-down + unrealized-G/L exposure under same tenant-isolation treatment; CPI-U series public reference data, no security surface. **Three forward-looking comments captured in Task #8 close metadata** for downstream phases: (1) §2.1.5 composition-view query path on the explicit test surface in Phase 3 (ARCHITECTURE.md RLS policy design per ADR-002 §8.0, not happy-path single-tenant smoke test only); (2) Decision D marginal-rate storage as an explicit callout in PRD §4 (Security & Compliance posture) when it drafts — "tax-bracket-revealing data" sub-class warrants explicit mention; (3) Sec re-engages for §2.4 (cross-cutting Plaid + manual entry) / PRD §4 (Security & Compliance posture) drafting; no re-review needed for §2.1.2 chart-overlay or §2.1.5 composition extensions unless drill-down semantics change. **Routing-flags block updates:** PM-follow-up bullet for §2.1.2 chart-overlay removed (obviated by Task #6). Security Reviewer bullet refreshed with dual-axis pass-recorded language (tenant isolation + scope-attribute-not-isolation-boundary; pass-with-comments stamp). Block stands at 4 Architect items + 1 Security Reviewer pass-recorded stub. **Acceptance flag** flipped from "draft, not locked" to "locked as of 2026-05-14 (Security Reviewer pass-with-comments per Task #8)" — Architect routing flags still resolve during Phase 3 and surface in Appendix B before Architect sign-off; they don't block §2.1 lock at the PRD level. **§2.1 section state at lock:** 7 stories (5 Primary: §2.1.1 NAV definition, §2.1.2 trajectory + chart overlay, §2.1.3 multi-horizon delta panel, §2.1.4 reference values, §2.1.5 composition NAV-buildup; 2 Supporting: §2.1.6 market value, §2.1.7 isolation + multi-scope aggregation). All stories parity-grounded to existing Finance_Report surfaces (with explicit V1/V2 boundaries on §2.1.2/§2.1.3/§2.1.4/§2.1.7) and to ADR-004 Decisions A/B/C/D where applicable. **Engagement notes:** Security Reviewer first real exercise as a teammate in the `phase-1` team — joined for Task #8 only, produced verdict in a single turn with comprehensive cross-section read. Engagement pattern (PM as workhorse + Sec spawn-on-need-at-section-lock) per ADR-003 worked cleanly. **PR #12** (`414a82d`) shipped via `/ship-branch`. Second §2.1-scoped PR in this two-PR pair (PR #10 = Tasks #1–#5 cross-check; PR #12 = Tasks #6–#8 final lock); v1.7 bump (this entry) is the v1.6-pattern companion. **Next thread:** §2.2 (asset allocation) drafting — the section whose original drafting attempt triggered the script-audit pivot back in v1.5. With ADR-004 grounding + parity-matrix authority + §2.1 lock pattern established, §2.2 should run smoother.

### v1.6 — 2026-05-14
Phase 1 Step 3 PM cross-check Tasks #1–#5 landed in a single PR (PR #10, `6955d73`); §2.1 expanded from 6 to 7 stories with renumbering; §2.1 final-lock checklist down to three parked items. **§1.2 attribute #5 strengthened** for ADR-004 Decision C user-side grounding — two-level Cat × Sub-Cat taxonomy made explicit with concrete examples (Equity → US-Index_Non_Sector; Bonds → T-bill; Alternatives → REIT), both asset and cash-flow taxonomies named, new active-assignment clause ("they assign holdings and transactions to their buckets themselves … the categorization grammar is theirs to define and theirs to apply") grounding the V1 holding-to-bucket assignment UI as an archetype property. F/CTO option-(a) routed Decision C grounding to attribute #5 (categorization) rather than attribute #4 (decisional posture), preserving #4 unchanged. **§2.1.1 NAV definition** extended to full tax-adjusted per Decision D: `Gross Asset Value − Debt − Realized Tax Liabilities − Unrealized Tax Liabilities`. NAV introduced as formal term in the story title; "net worth" retained as casual reading throughout §2.1. Parity verified against existing Google Sheet — Unrealized Tax Liab = marginal-rate × aggregate-unrealized-G/L primitive form; Realized Tax Liab = accrued Federal + California estimated-tax obligation net of payments already made. **§2.1.3 multi-horizon NAV-delta panel** landed after three revisions and one mid-task parity course-correction. Final shape: five fixed horizons (Month / YTD / 1-Year / 3-Year / 5-Year); both dollar and percent per horizon (V1 expansion beyond strict existing-system parity, F/CTO option-(b); existing system shows percent only); Inflation Adjusted column side-by-side for 1Y/3Y/5Y horizons only, prior-Year-End reference basis matching the existing panel footnote. **Parity course-correction:** PM v2 proposed dropping the panel inflation column entirely on the basis that parity-matrix line 100 looked like an audit-phrasing slip; F/CTO direct PDF inspection of `Finance_Report_2026_04.pdf` page 3 confirmed line 100 was accurate and PM's read was the error. Lesson noted: when ground-truth artifacts are available, prefer direct inspection over abstract reading of secondary descriptions. **§2.1.4 NEW Primary story** — *NAV at three reference dates* — landed. Three rows (This Month / Prior Month / Prior Year-End) × two dollar columns (`NAV` nominal + `NAV — Prior Yr $` inflation-adjusted to prior YE); all six cells populated. Surfaced as a candidate sibling during Task #3, queued as Task #5 after F/CTO confirmed sibling warrant rather than V2 deferral. **Option-(A) renumbering** applied: current §2.1.4 (composition) → §2.1.5; §2.1.5 (market value) → §2.1.6; §2.1.6 (isolation) → §2.1.7; two reference numbers updated in Open-routing-flags and Acceptance-flags blocks. Adjacency rationale: §2.1.3 and §2.1.4 are sub-surfaces within the same Finance_Report "NAV Performance" section and pair as deltas-over-horizons + values-at-anchor-dates. **§2.1.7** (was §2.1.6) extended for Decision B multi-scope full-household aggregation: V1 default = single full-household NAV across all ownership scopes the user holds (e.g., Rich / RichMoskoTrust / IRA / HSA); per-scope reporting and scope-aware filtering UI explicitly V2+; data model carries scope on each account from V1 so the V2 expansion ships without a data migration. Body split into four sentences (tenant isolation + multi-scope aggregation + combined rationale + V1/V2 boundary) for legibility post F/CTO density tweak. Security Reviewer flag scope expanded to additionally confirm scopes are treated as user-owned data labels, not as V1 isolation boundaries (scopes are not tenants). **Open routing flags block expanded** with three new items: Architect — historical NAV depth in V1 (whether locked V1 = yes — V1 imports the existing Google Sheet's monthly NAV history Dec-2015 forward so the 5-Year horizon is meaningful at launch; how routed to Architect Phase 3); §2.1.2 chart-overlay inflation-adjusted PM follow-up (single line normalized to today's $, 60-month rolling window per parity-matrix line 77); CPI-U source decision (live API vs. manual entry, parity-matrix open product decision #10, Architect). One CPI-U series feeds both §2.1.2 chart-overlay and §2.1.3 panel — one Architect decision serves both surfaces. **Conceptual axis division accepted** between Decision D (= §2.1.1 NAV-calculation jurisdiction, Federal + California) and Decision B (= §2.1.7 tenant/household scope); different axes, do not merge. **Engagement pattern:** first real team-mode exercise post-ADR-003 smoke-test. `TeamCreate phase-1` (generic name, persistent across remaining Phase 1 steps per F/CTO preference, not step-scoped); PM as workhorse teammate with persistent context across all five tasks; peer messaging via SendMessage; CoS as main-session team lead. Pattern worked as designed; relay format `[CoS]:` / `[PM]:` per memory feedback preserved. **§2.1 final-lock checklist** now stands at three parked items: (1) §2.1.2 chart-overlay extension (PM follow-up in PRD block), (2) §2.1.5 (renumbered composition) extension — Gross → Debt → Realized Tax Liab → Unrealized Tax Liab → NAV intermediate subtotals matching the existing Finance_Report Account Holdings layout (currently in Task #2 close metadata; promotes to PRD block at §2.1 lock per F/CTO confirmation), (3) Security Reviewer pass on §2.1.7 (mandatory before §2.1 locks; covers tenant isolation + scope-attribute-not-isolation-boundary review). **PR #10** shipped via the `/ship-branch` skill — first real use post-codification (PR #9, v1.5 bump cycle).

### v1.5 — 2026-05-13
Phase 1 Step 3 in progress with a mid-Step-3 script-audit pivot landed; re-orient infrastructure upgraded. **Script-audit pivot:** §2.2 (asset allocation) drafting under the preliminary-findings-grounded model exposed a drift when F/CTO surfaced an existing two-level asset-categorization taxonomy in active use as a hard V1 backend requirement, revealing that abstract-from-findings drafting was generating requirements F/CTO already had concrete system-grounded answers for. CoS-led functional audit of five existing-system artifacts (MoskoFinance Apps Script, Master Sheet, representative per-account workbook, Asset Summary aggregator, Finance_Report Google Doc) produced **`docs/v1-parity-matrix.md`** — 275-line authoritative V1 capability scope mapping every existing-system capability to V1 preserve / V1 new-decision / V2 defer / drop with rationale. **ADR-004** consolidated four amendments to ADR-002: Decision A (rebalance-target visualization — % target vs % actual + `$ ReAlloc` dollar-delta — is V1; auto-generated rebalance *suggestions* remain V2+); Decision B (multi-scope ownership Rich/Trust/IRA/HSA within a single tenant is a V1 data attribute; per-scope reporting V2+; default report scope full-household); Decision C (two-level user-meaningful asset taxonomy Cat × Sub-Cat in V1 via hybrid operationalization — backend-correct + F/CTO taxonomy seeded + V1 bucket-assignment UI + V2 CRUD UI); Decision D (estimated quarterly tax payments V1 in primitive form — Federal + California FTB parallel marginal-rate inputs, quarterly payment computation, IRS/FTB account tracking). **PRD draft state on disk:** §1 vision + 7-attribute *self-directed multi-account owner* target-user archetype + 4-subsection deferrals locked; §2.1 net worth six user stories drafted (§2.1 draft-not-locked pending Security Reviewer pass on multi-tenant isolation in story 2.1.6); §§2.2–§7 stubbed; §8 V1 milestone framing with drop-replace migration pattern queued per ADR-004 forward reference as the answer to ADR-002 §7.0 item 7 ("V1 done" definition). **PM cross-check queued** for resumption: §1.2 attribute #4 reframe (Decision C user-side grounding); §2.1 NAV-with-tax-liability definition extension, multi-horizon headline-delta × inflation-adjusted extension, scope-awareness on 2.1.6 (Decisions B / D). **Re-orient prompt v2** (`docs/handoff-prompts.md`, PR #7): main-anchored summary; reads `CLAUDE.md` → `WORKFLOW.md` → `DECISIONS.md` → `PRD.md` / `ARCHITECTURE.md` in CLAUDE.md's prescribed order; `git worktree list` + `git log --all --not main` scan with "list discrepancies and ask before merging" instruction. Motivated by a real miss earlier this session where the prior short-form prompt failed to surface the unmerged `claude/nice-bohr-80d2ec` branch containing PRD.md + ADR-004 because `git status` was clean on `main`. **Operational notes:** PM resumes section-by-section pacing post-audit; the script audit was CoS-orchestrated (not PM-led) within the same Phase 1 work; team-mode initialization (`TeamCreate phase-1` — generic per F/CTO preference for persistence across remaining Phase 1 steps, not step-scoped) deferred to the next session resuming §1/§2.1 cross-check.

### v1.4 — 2026-05-11
Phase 1 Step 2 closed; engagement pattern shifted for Step 3 onward. Step 2 ratification of preliminary product findings completed across 2026-05-09 through 2026-05-11; F/CTO-signed-off verdicts for all six findings plus twelve sub-decisions captured in ADR-002. Notable Step 2 expansions vs. PM's tighter scope recommendations: transaction-tracking expanded to cover Plaid Investments alongside Transactions across depository / credit / investment / loan-balance / crypto accounts (ADR-002 §1.3); manual non-Plaid accounts and manual transaction entry added as V1-initiative scope with V1.0/V1.1 sequencing deferred to Phase 4 (§1.5); cost basis and unrealized G/L pulled into V1 with average-cost-fallback realized G/L marked "estimated" (§1.7); securities general principle treating all Plaid-surfaced investment activity uniformly at the transaction level with type as a categorization attribute (§1.8); multi-tenant data model from day one (§1.4). Terminology refinement: "permanent non-goals" relabeled "out-of-scope for this PRD lifecycle" (§3.0). Subagent engagement pattern shifted for Step 3 onward: **ADR-003 adopts Claude Code Agent Teams** (experimental, gated behind `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) as the multi-agent coordination primitive. Smoke-tested in Claude Desktop (in-process backend; SendMessage works; TaskList not surfaced; teammates default to non-1M-context model — mitigations captured in ADR-003 §3). Five teammate-eligible agent files (PM, Architect, Security Reviewer, UX Designer, Visual Designer) received a "team-mode preamble" instructing them to load SendMessage via ToolSearch as first action when spawned as a teammate. Chief of Staff agent file unchanged — CoS-as-main-session is always the lead, never a teammate. The "Subagent invocation pattern" subsection in Phase 1 detailed steps revised to reference team mode for Step 3.

### v1.3 — 2026-05-09
SessionStart hook for automatic re-orientation. Added `.claude/settings.json` with a SessionStart hook that injects the *Subsequent sessions* re-orient prompt from `docs/handoff-prompts.md` as additional context at session start — so Claude performs the four-step orient (phase, role, next deliverable, changelog deltas, plus git status if a feature branch is active) before responding to the user's first message of each session, no manual prompt-pasting required. The hook re-reads `docs/handoff-prompts.md` at fire time; editing the prompt source changes auto-orient behavior without touching `settings.json`. Includes adaptive flagging: when WORKFLOW.md's header indicates a phase transition is pending, Claude appends a one-liner pointing at the phase-transition workflow prompt — detection happens in Claude's response, not in shell, so it's robust to header-format drift. `settings.json` is project-shared (committed); personal overrides belong in `.claude/settings.local.json` (gitignored). Operational gotcha discovered during validation and worth flagging for future-self: worktrees are materialized from the local `main` checkout's current commit, so failing to `git pull` main locally before opening a new Claude Code session means the new worktree won't include recently-merged `.claude/settings.json` or `.claude/agents/` files, and the hook can't fire — pull main locally before relying on settings or agents from a recent merge. Bookkeeping note: this entry is being added post-hoc — the SessionStart hook landed in PR #3 alongside the residual phase/1-prep branch but missed its WORKFLOW.md changelog companion at the time; v1.3 closes that gap.

### v1.2 — 2026-05-09
Phase 1 prep + agent wiring fix. Phase 0.5 produced six well-drafted agent definitions at `/agents/*.md`, but the location and format were wrong for Claude Code's project-scoped subagent system: files needed to live at `.claude/agents/*.md` with YAML frontmatter to be invokable as `subagent_type` values. Documentation existed; wiring did not. Phase 1 prep applied the smallest fix: prepended minimal frontmatter (`name`, `description`) to each of the six files and `git mv`'d them into `.claude/agents/`. Mechanical tool scoping (`tools:` allowlists matching the prose Tool scope sections) deliberately deferred to Phase 5, per the original Phase 5 plan. Path references updated repo-wide (WORKFLOW.md and chief-of-staff.md); two historical references in the v1.1 changelog and Phase 0.5 "as executed" steps preserved as `/agents/` for accuracy. Phase 0.5 lessons-learned amended retroactively with the documentation-vs-wiring lesson. Phase 1 "Detailed steps" subsection fleshed out, including an explicit subagent invocation pattern for the phase (Product Manager as workhorse; Architect surgical; Security Reviewer at section-lock; Chief of Staff at phase boundaries). **After committing this version, Claude Code must be restarted before Phase 1 work begins** — the subagent registry loads at session start, so newly added agents are not callable mid-session.

### v1.1 — 2026-05-09
Phase 0.5 complete. Six agent definition files committed to `/agents/`: Chief of Staff, Product Manager, Architect, Security Reviewer, UX Designer, Visual Designer. Each follows the template locked in ADR-001. Chief of Staff smoke-tested (orchestration-shaped response confirmed). DECISIONS.md carries ADR-001 (Phase 0.5 process resolutions). Header pointer advanced to Phase 1. Phase 0.5 status, detailed steps, and lessons learned filled in.

### v1.0 — 2026-05-08
First repo commit. Per WORKFLOW.md's own versioning rule ("First repo commit: v1.0"), bumped from v0.5 to v1.0 on landing in git. Content unchanged from v0.5 except for this changelog entry, the header version/date, and the footer (which had stalled at "End of WORKFLOW.md v0.1" through four revisions). `.gitignore` and `CLAUDE.md` committed alongside this version bump — the previous commit (`5e65712`) listed them in its message but did not actually include them. Phase 0.5 detailed steps now planned in `/Users/mosko/.claude/plans/i-m-starting-claude-delegated-scott.md`; phase entry is imminent.

### v0.5 — 2026-04-25
Backlog tooling cleanup. Linear was locked as the task tracker in v0.3 but `TASKS.md` references lingered in Phase 7 outputs and in the Open Questions section. Resolved: backlog lives **entirely in Linear**, no `TASKS.md` artifact exists. Added **`docs/linear-setup.md`** to the artifact list as the operational companion to WORKFLOW.md's Linear policy — installation steps, OAuth flow, label and milestone conventions, troubleshooting. WORKFLOW.md remains the single source of truth for the *decision and policy* around Linear; `docs/linear-setup.md` covers *how to actually set it up and use it*. Phase 5 outputs updated to include drafting `docs/linear-setup.md`. Phase 7 reference to `TASKS.md` corrected. Open Questions entry for backlog tooling marked resolved.

### v0.4 — 2026-04-25
Resolved a chicken-and-egg dependency in the original phase ordering: Phases 1–4 listed agents (PM, Architect, Security Reviewer, designers) as leads, but agent definition files were not produced until Phase 5. Inserted **Phase 0.5 — Agent Roster Definition** between Phase 0 and Phase 1, with scope limited to the agents active in Phases 1–4 plus formalization of the Chief of Staff role. Build-time agents (Backend Engineer, Frontend Engineer, QA, DevOps) remain deferred to Phase 5, where their context is real. Updates: Phase overview table inserts Phase 0.5; new Phase 0.5 section added with full detail; Phase 1 inputs now explicitly note that PM, Architect, and Security Reviewer agent definitions exist; Phase 5 outputs scoped down to build-time agent definitions plus workshop infrastructure; agent roster section adds a "Definition timing" note per agent.

### v0.3 — 2026-04-25
Two operating-model refinements. **(1)** Owner role retitled from "CTO" to **"Founder/CTO"** throughout, reflecting authority over both business and technical decisions, not just technical. **(2)** **Linear** locked as the project tracking tool, with agents granted scoped Linear access via the official Linear MCP server. Updates: Linear added to artifact list (replacing the deferred `TASKS.md`/Issues choice); Phase 4 outputs now reference Linear epics/projects/issues; Phase 5 adds Linear MCP setup as a deliverable; Phase 6 includes agents updating Linear status as part of the build loop; Glossary entry added; corresponding `[OPEN]` question resolved.

### v0.2 — 2026-04-24
Refocused Phase 0 on **discovery and operating model only** (mini-business / startup framing). Product-scope content (V1 features, Plaid choice, lots-vs-positions, multi-tenant schema) moved out of Phase 0 outputs and into Phase 1 inputs as **preliminary findings to be ratified**, not locked decisions. Phase 0 renamed from "Vision & Discovery" to "Discovery & Operating Model." Phase 1 stub expanded with explicit inherited inputs and a ratification step. Tone shift across Phase 0 and operating-model sections toward "small organization, founding-team agreement" rather than corporate process documentation.

### v0.1 — 2026-04-24
Initial draft. Captures discovery outcomes, nine-role agent roster (incl. Chief of Staff as meta-role), eight-phase structure with Phase 4.5 inserted between scoping and workshop setup, full detail on Phase 0, stubs for Phases 1–7. Open questions noted inline as `[OPEN]`.
