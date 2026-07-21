-- ============================================================================
-- Migration: pfin.account_trans_annotation — the R-17 per-transaction MUTABLE
--   annotation overlay (§2.3 transaction-level expense category + #3 user note) over
--   the immutable account_trans ledger. The user's editable layer above WHAT-HAPPENED.
-- Phase 6 Build Loop (ADR-027 ingest/valuation substrate; Linear SELF-283). LAST of
--   the 015–021[→023] substrate slices. Design CLOSED + Sec-cleared (v1.71):
--   temp/015-ingest-substrate-design.md §6A (Rev 7 — the annotation overlay supersedes
--   the Rev-6 standalone note table; §2.3 expense categorization un-deferred INTO V1) +
--   the §6A C-note fence-shape open call; temp/015-architect-design-spec.md PART B
--   (the account_trans_annotation row, line 114) + PART C (Pattern 1 #10 + the C-note,
--   line 168). JOINT-REVIEW-MANDATORY — Decision-3 matched-tenant fence extension (#10)
--   + the C-note fence-shape ruling is Sec's design call (see C-NOTE below).
--
-- WHAT THIS DOES:
--   Creates pfin.account_trans_annotation — a MUTABLE 1:1 overlay on pfin.account_trans
--   (PK = trans_id enforces the 1:1). Splits WHAT-HAPPENED (immutable ledger: date /
--   amount / vendor / description / provider_category hint) from the USER's editable
--   layer (this table): sub_cat_id (the §2.3 expense category, cashflow-domain) + note.
--   Both the category and the note are user-re-assignable, so they hit the same
--   immutable-ledger wall — the overlay is the reversible layer that keeps the audit
--   ledger clean (no reverse-and-replace pollution for a re-categorization). Full
--   authenticated CRUD; RLS via the parent account_users FK-chain (the annotation
--   carries NO own users_id). C5 user-write surface.
--
-- Numbering: 023 follows 022 (user_asset_category allocation junction). Depends on 004
--   (pfin.account_trans immutable ledger — the trans_id FK target), 006 (account_trans
--   rd/wr_access-JOIN RLS + the account_users grant-chain this table's RLS mirrors),
--   009 (pfin.user_taxonomy — the sub_cat_id FK target), 003 (pfin.account — the
--   users_id anchor the fence resolves via the chain), and 001 (pfin schema +
--   fn_refresh_updated_at, reused for the updated_at trigger). config.toml already
--   exposes pfin to [api] (ADR-023) — this table is internet-facing the moment it is
--   granted, so C6 exposure-gating binds (see EXPOSURE / C6 below). No downstream
--   migration depends on 023 landing first (it is the last substrate slice).
--
--   §16 RENUMBER NOTE (mirrors 022): the annotation overlay moved 021→023 in the
--   original PART C map (021 took the account-linked_source dedup index; 022 took the
--   allocation junction; migrations are append-only). The design's "@021" references to
--   this table (PART C #10; ADR-027 (g) "[#10, 021]") mean THIS migration.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list. Read Decision 4 verbatim before drafting.) This
--   migration introduces ZERO catalogued §10 instances; the ledger STAYS at 3
--   (RT-22 + RT-26 + RT-27 per ADR-011 Decision 4 — RT-27 appended third at SELF-212,
--   F/CTO-ratified 2026-07-19; earlier 015–021 migration headers that read "stays 2"
--   predate that move — the current canonical count is 3, as 022 recorded).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — unchanged
--         (not touched).
--   (ii)  Layer-attribution: no infrastructure-credential-presence surface (RT-22 =
--         PDF-worker container), no code-layer SUPABASE_SERVICE_ROLE_KEY allowlist
--         surface (RT-26 = web-app/worker SOURCE grep fence), and no network-
--         exposure/config surface (RT-27 = the SELF-212 admission-app inbound fence)
--         is touched. This is authenticated-tier RLS/FK/trigger DDL only — full
--         authenticated CRUD, NO service_role grant (see GRANTS below): there is no
--         service_role annotation writer in V1 (R-18 lazy model — §6A Option B). So
--         008's DB-ACL posture is unchanged, and no admission channel is opened. No
--         surface becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 023 is not the
--         canonical §10 anchor.
--   DE-CONFLATION GUARD: the Decision-3 matched-tenant fence below (the sub_cat_id
--   chain-resolved fence) is a Decision-3 mechanism, NOT a §10 catalogued instance —
--   the same separation 012 / 017 / 022 drew (and the SELF-187 DEFINER-allowlist 2→3
--   drew against §10).
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — CANONICAL INSTANCE #10 (+1); the LAST
--   label of the ADR-027 (g) 5→10 BATCH (#6–#10). NOT the last label of the family:
--   #11 (holdings_checkpoint.security_id @ 019) is a distinct-provenance label per
--   ADR-027 (p), OUTSIDE this batch. This table carries TWO reference columns;
--   the ledger moves on ONE:
--     - trans_id → pfin.account_trans(trans_id): the SOLE tenant anchor (the annotation
--       has NO own users_id; tenancy derives via trans_id → account_trans.account_id →
--       account_users, the parent-FK-chain). No second anchor to mismatch → NOT D3.
--       (Same class as account_trans.account_id @ 004 and reconciliation_event_trans's
--       parent-chain @ 005.)
--     - sub_cat_id → pfin.user_taxonomy(id): the annotation's owning tenant (resolved
--       via the account chain) and the taxonomy row's users_id are BOTH per-user →
--       CANONICAL INSTANCE #10, a GENUINE matched-tenant fence (the 012 Pattern 1
--       shape) — a PG FK is existence-only and would let a user tag a transaction with
--       ANOTHER tenant's Sub-Cat, the exact chain attack Decision 3 fences.
--
--   ENUMERATION — already recorded; NO new DECISIONS.md ADR/amendment in this PR.
--     The ADR-027 atomic amendment (g) (landed in the 015 PR) ALREADY enumerates the
--     whole Decision-3 canonical 5→10 family delta and maps #10 to THIS migration
--     ("matched-tenant ×3: … account_trans_annotation.sub_cat_id [#10, 021→023]").
--     Per that amendment's "per-migration Decision-3 evaluation + Sec joint-review at
--     each of 015–021[→023]" instruction, 023's obligation is this in-header evaluation
--     (the pre-enumerated instance #10 is REALIZED here) + Sec numbering sign-off at
--     joint-review — NOT a new ADR. This mirrors 015 (#6) / 017 (#7) / 022 (#8+#9)
--     exactly. Canonical running enumeration for Sec to verify (11 labeled instances;
--     realized/unrealized status per label — the family is NOT a contiguous run):
--       #1  reconciliation_event_trans (event_id, account_trans_id)     [Lock 9]  REALIZED
--       #2  account_trans.replaces_trans_id self-FK                      [004]     REALIZED
--       #3  monthly_report.included_reconciliation_event_ids INTEGER[]   [Lock 11] UNREALIZED (V1.3+)
--       #4  monthly_report_account_snapshot.account_id                   [Lock 12] UNREALIZED (V1.3+)
--       #5  account.sub_cat_id → user_taxonomy(id)                       [012 / ADR-025] REALIZED
--       #6  account.linked_source_id → linked_source                     [015]     REALIZED
--       #7  account_trans.security_id → pfin.asset (novel fence, site 1) [017]     REALIZED
--       #8  user_asset_category.sub_cat_id → user_taxonomy (matched)     [022]     REALIZED
--       #9  user_asset_category.asset_id → pfin.asset (novel, site 2)    [022]     REALIZED
--       #10 account_trans_annotation.sub_cat_id → user_taxonomy  ← THIS  (matched-tenant) REALIZED
--       #11 holdings_checkpoint.security_id → pfin.asset (novel fence)   [019 / ADR-027 (p)] REALIZED
--         (#11 was deferred at design time but realized EARLY at 019 — see 019's header
--          "8 realized: baseline 5 + #6[015] + #7[017] + #11[019]"; ADR-027 (p),
--          DECISIONS.md. It sits OUTSIDE the (g) 5→10 batch — a distinct-provenance label.)
--     With #10 REALIZED, the LAST canonical label of the (g) 5→10 batch lands here, so
--     all 11 canonical labels #1–#11 now carry a STABLE assignment with locking
--     provenance. DDL-realization status after 023: DDL-realized = 9 of 11
--     (#1,#2,#5,#6,#7,#8,#9,#10,#11); UNREALIZED = #3 + #4 (monthly_report family,
--     canonically-locked but DDL-deferred to V1.3+). The family is therefore NOT "fully
--     realized" — do NOT propagate the 022 "7→9 realized" contiguous-run framing (that
--     line also silently omitted #11). Per the brief, task #13 (fold the canonical
--     enumeration into the DECISIONS.md ADR-011 Decision-3 BODY list) is cleanly runnable
--     NOT because "everything is realized" but because all canonical labels #1–#11 are
--     now stably assigned with locking provenance (the last, #10, lands here): the body
--     list (#1–#5 today) folds to #1–#11 WITH per-instance realized/unrealized status
--     (#3 + #4 = pending V1.3+).
--
--   OPERATIONAL-vs-CANONICAL DUAL-COUNT (Sec OQ-2; ADR-011 D3 enumeration mid-
--     reconciliation, task #13 — both figures stated cleanly so Sec/QA have a hook):
--       • CANONICAL family = 11 LABELED instances (#1–#11), NOT 10. 023 realizes #10
--         (+1 DDL-realized). DDL-realized goes 8 → 9 of 11 after 023
--         (#1,#2,#5,#6,#7,#8,#9,#10,#11); UNREALIZED = #3 + #4 (monthly_report +
--         monthly_report_account_snapshot — canonically-locked, DDL-deferred to V1.3+).
--         Canonical-realized does NOT equal canonical-total: 9 of 11. This is NOT a
--         convergence-to-completion point — it is the point where all 11 LABELS are
--         stably assigned (the last, #10, lands here).
--       • OPERATIONAL running tally (the pre-reconciliation count the 015/022 slices
--         carried, which runs +1 over canonical-realized due to the historical Lock-14
--         settings-family count-grain conflation flagged in the 012 header + the
--         2026-07-02 annotation): +1.
--     Sec pins the authoritative figure at joint-review; the canonical anchor is
--     "11 labeled instances; 9 DDL-realized after 023; #3 + #4 pending V1.3+."
--
--   REALIZATION MECHANISM — ONE BEFORE INSERT OR UPDATE trigger (mirrors the one-
--     function-per-fence precedent of 012 / 017 / 022). Covers UPDATE as well as INSERT
--     because account_trans_annotation is MUTABLE (the user re-categorizes: sub_cat_id
--     is the primary editable field) — matches 012 (mutable pfin.account) / 022
--     (mutable junction); contrast 017's INSERT-only fence on the immutable ledger. A
--     single-row CHECK cannot subquery the referenced row (let alone JOIN the account
--     chain), so Decision 3's "trigger where PG cannot express the constraint
--     declaratively" applies.
--
-- ----------------------------------------------------------------------------
-- ⚠️ C-NOTE — THE ONE OPEN SUB-DECISION (SEC RULES): the sub_cat_id matched-tenant
--   fence SHAPE. The annotation row carries NO own users_id — its tenant derives via
--   trans_id → account_trans.account_id → account.users_id. So the matched-tenant fence
--   for sub_cat_id CANNOT use a local new.users_id (there isn't one). Two shapes (design
--   line ~168):
--     (a) CHAIN-RESOLVED trigger — the fence JOINs trans_id → account_trans → account to
--         resolve the owning users_id, then matches user_taxonomy.users_id (mirrors
--         017's chain-JOIN tenant resolution). Load-bearing regardless of writer;
--         authoritative under a hypothetical service_role annotation writer.
--     (b) RLS-COMPOSITION belt-and-suspenders — annotations are authenticated-CRUD only
--         (R-18 lazy; NO service_role annotation writer in V1), so account_users.wr_access
--         RLS + user_taxonomy_select's auth.uid()-scoping already make a cross-tenant
--         sub_cat_id invisible; the explicit fence is belt-and-suspenders (like 012/022).
--   ARCHITECT RECOMMENDATION = (a), authored below as concrete SQL. Rationale:
--     (1) SAFER MIRROR OF 017 / FUTURE-PROOF. §6A left the auto-seed→override flow open
--         (Option A eager-seed-at-ingest vs Option B lazy). Option A, IF ever chosen,
--         introduces a service_role annotation writer (the aggregator-sync path seeding
--         provider_category → a cashflow Sub-Cat) — at which point (b)'s RLS composition
--         is bypassed and only an explicit chain-resolved fence holds, exactly as 017's
--         security_id fence is the SOLE gate under service_role. (a) makes the fence
--         durable across that possible future WITHOUT a re-migration.
--     (2) DISCIPLINE CONSISTENCY. Every matched-tenant instance in the family (012 / 022
--         #8) is authored explicit + fail-closed + authoritative-regardless-of-RLS. 022
--         authored even its belt-and-suspenders novel fence (#9, no service_role writer)
--         identically "because OWD-B is the ratified precedent for EVERY FK." Shape (b)
--         would make #10 the FIRST matched-tenant instance in the family with NO explicit
--         DB fence — a discipline exception.
--     (3) DECISION 3 IS NON-NEGOTIABLE. "Matched-tenant validation in the DDL is
--         mandatory; it does not skip even when the surface looks safe." Shape (b) is
--         precisely "skip the explicit DDL validation because it's safe under
--         authenticated-only" — which cuts against the core discipline.
--   (b) is defensible ONLY IF Sec judges the authenticated-only invariant durable enough
--     AND accepts making #10 the family's first RLS-composition-only matched-tenant
--     instance. This is Sec's call at joint-review — if Sec rules (b), DROP the fence
--     function + its trigger below and rely on the RLS composition; the RLS + FK stay
--     as-is. I lean (a) and have authored it.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — the fence function is SECURITY INVOKER (NOT DEFINER); the
--   SECURITY DEFINER allowlist STAYS 3 (ADR-011 Decision 9: fn_refresh_updated_at +
--   fn_grant_creator_access + the still-unauthored audit-log helper). ZERO new SECURITY
--   DEFINER in 023. The fence reads referenced rows and needs no elevated privilege →
--   INVOKER → not an allowlist entry. The updated_at trigger reuses the EXISTING
--   pfin.fn_refresh_updated_at (001, allowlist entry #1) — no new entry. set
--   search_path = '' on the authored function (injection fence).
--
--   fn_account_trans_annotation_matched_sub_cat (Pattern 1, #10) — SECURITY INVOKER.
--     Under authenticated, user_taxonomy_select (users_id = auth.uid(), 009) scopes the
--     taxonomy read to the caller's own rows AND the account-chain JOIN is RLS-scoped to
--     the caller's accounts — a cross-tenant sub_cat_id is INVISIBLE → NOT EXISTS →
--     raise (the desired fence); the explicit ut.users_id = acc.users_id predicate makes
--     it authoritative regardless of RLS (the (a) load-bearing property). NULL-safe
--     fail-closed.
--
-- ----------------------------------------------------------------------------
-- DOMAIN NOTE (mirrors the 012 / 022 DOMAIN NOTE): matched-DOMAIN (user_taxonomy.domain
--   = 'cashflow' — a transaction category is a cashflow-domain categorization, verified
--   009) is NOT enforced in the trigger for V1; it is left to the app-layer Sub-Cat
--   dropdown filter (the annotation UI offers only cashflow-domain rows). The matched-
--   TENANT check is non-negotiable + DB-enforced; the matched-DOMAIN check is a value-
--   correctness constraint left flexible in V1 (a one-line `and domain = 'cashflow'`
--   addition later if desired).
--
-- ----------------------------------------------------------------------------
-- ONE-WAY DOORS: none new. R-17 (the overlay shape) was ratified in the v1.71 design
--   close; 023 realizes the pre-ratified design. The auto-seed→override flow (§6A
--   Option A eager vs Option B lazy) is an APP-LAYER write-path choice (Backend), NOT a
--   schema one-way-door — this migration is compatible with either (the C-NOTE shape (a)
--   is the future-proof-for-A choice at the DB layer). The sub_cat_id ON DELETE
--   disposition (RESTRICT) is reversible via ALTER while greenfield/empty.
--
-- ----------------------------------------------------------------------------
-- EXPOSURE / C6 RLS-COVERAGE NOTE (ADR-023 C6 standing obligation — pfin is in [api]
--   schemas, so this table is internet-facing the moment it is granted):
--   - RLS ENABLED on pfin.account_trans_annotation (below).
--   - POLICIES PRESENT: ata_select (rd_access-JOIN) / ata_insert (wr_access-JOIN WITH
--     CHECK) / ata_update (wr_access-JOIN USING + WITH CHECK) / ata_delete (wr_access-
--     JOIN USING). PARENT-FK-CHAIN posture (the 006 account_trans / 005 reconciliation_
--     event_trans shape) — tenancy resolves via trans_id → account_trans.account_id →
--     account_users, since the annotation has no own users_id. SELECT keys on rd_access;
--     all WRITES key on wr_access (mod #3 discipline).
--   - GRANT: authenticated SELECT/INSERT/UPDATE/DELETE (full V1 CRUD — the user edits
--     their own annotation; MUTABLE, contrast 004/005 append-only ledgers). anon
--     ZERO-grant (schema-usage-layer denial — anon holds no USAGE on pfin per ADR-023
--     C2). service_role UNGRANTED (no service_role annotation writer in V1 — R-18 lazy;
--     the C-NOTE (a) fence future-proofs the DB layer if that ever changes).
--   - This table does NOT ship without the paired QA two-tenant pgTAP battery
--     (SECURITY §4.5, EXPOSURE-gating per C6). The battery must assert: (a) owner
--     reads/writes own annotations (via a wr_access account) PASS; (b) tenant B reads 0
--     of tenant A's annotations (rd_access-JOIN RLS) PASS; (c) tenant B cannot
--     INSERT/UPDATE/DELETE an annotation on tenant A's transaction (wr_access-JOIN) PASS;
--     (d) the #10 matched-tenant fence — a user cannot annotate with ANOTHER tenant's
--     sub_cat_id (cross-tenant taxonomy → raise) PASS; (e) NULL sub_cat_id (Unsorted-
--     pending) INSERT PASS. QA authors the battery (Architect does not edit tests/);
--     Sec sign-off gates merge. Not a vacuous green — the fixture must populate two
--     tenants with a transaction + a taxonomy row each.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.account_trans_annotation — per-transaction MUTABLE annotation overlay (R-17).
--     - trans_id (bigint PK → pfin.account_trans(trans_id) ON DELETE RESTRICT): the
--       annotated transaction. PK enforces the 1:1 (one annotation per transaction).
--       SOLE tenant anchor (tenancy via the account chain). NOT D3. ON DELETE RESTRICT
--       is fail-loud + moot (account_trans is immutable — no DELETE path exists).
--     - sub_cat_id (bigint NULL → pfin.user_taxonomy(id) ON DELETE RESTRICT): the §2.3
--       expense category (cashflow-domain). NULL = Unsorted-pending (SELF-200).
--       Decision-3 CANONICAL #10, matched-tenant fence (chain-resolved; C-NOTE (a)).
--     - note (text NULL): the user's free-text note (folds in the Rev-6 #3 note table).
--     - created_at / updated_at (timestamptz): updated_at auto-refreshed via
--       fn_refresh_updated_at BEFORE UPDATE trigger.
--   pfin.fn_account_trans_annotation_matched_sub_cat() — BEFORE INSERT OR UPDATE WHEN
--     (new.sub_cat_id IS NOT NULL); SECURITY INVOKER; set search_path=''; NULL-safe
--     fail-closed; rejects a sub_cat_id whose user_taxonomy.users_id != the annotation's
--     owning tenant (resolved via trans_id → account_trans → account.users_id).
--   Security-load-bearing edges: the matched-tenant fence fails-closed (NOT EXISTS →
--     raise) + is NULL-safe + INVOKER-composes-with-RLS + chain-resolves the tenant
--     (authoritative regardless of writer, C-NOTE (a)); RLS parent-FK-chain bounds every
--     verb to an account the caller holds the matching access flag on; the PK enforces
--     the 1:1 overlay invariant.
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- pfin.account_trans_annotation — the R-17 per-transaction MUTABLE annotation overlay.
-- ----------------------------------------------------------------------------
create table if not exists pfin.account_trans_annotation (
  trans_id    bigint primary key
                references pfin.account_trans (trans_id) on delete restrict,
  sub_cat_id  bigint
                references pfin.user_taxonomy (id) on delete restrict,
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table pfin.account_trans_annotation is
  'Per-transaction MUTABLE annotation overlay (ADR-027 R-17 / §6A Rev 7; SELF-283). The '
  'user''s editable layer over the immutable account_trans ledger (004): sub_cat_id (the '
  '§2.3 expense category, cashflow-domain) + note. PK = trans_id enforces the 1:1 (one '
  'annotation per transaction). Editing a category/note is an overlay UPDATE — it does '
  'NOT pollute the append-only ledger with reverse-and-replace rows. Full authenticated '
  'CRUD. RLS via the PARENT account_users FK-chain (trans_id → account_trans.account_id '
  '→ account_users rd/wr_access-JOIN — the 006/005 parent-chain shape) since the '
  'annotation carries NO own users_id. Carries ONE Decision-3 fence: sub_cat_id → '
  'user_taxonomy = CANONICAL #10 (matched-tenant, chain-resolved per the §6A C-NOTE (a) '
  'recommendation — tenant resolved via the account chain, NOT a local users_id which '
  'this table lacks). trans_id is the sole anchor (NOT D3). Matched-DOMAIN '
  '(user_taxonomy.domain=''cashflow'') is app-layer in V1 (012 DOMAIN NOTE); matched-'
  'TENANT is DB-enforced. anon zero-grant; service_role ungranted (no service_role '
  'annotation writer in V1 — R-18 lazy). DEFINER allowlist unchanged at 3; §10 ledger '
  'unchanged at 3 (RT-22 + RT-26 + RT-27).';

comment on column pfin.account_trans_annotation.trans_id is
  'PK + FK → pfin.account_trans(trans_id) ON DELETE RESTRICT. The annotated transaction; '
  'PK enforces the 1:1 overlay (one annotation per transaction). SOLE tenant anchor — '
  'the annotation has no own users_id; tenancy derives via trans_id → '
  'account_trans.account_id → account_users (parent-FK-chain). NOT a cross-tenant '
  'reference → Decision 3 does not apply (same class as account_trans.account_id @ 004). '
  'ON DELETE RESTRICT is fail-loud and moot (account_trans is immutable — no DELETE).';
comment on column pfin.account_trans_annotation.sub_cat_id is
  'FK → pfin.user_taxonomy(id) ON DELETE RESTRICT — the §2.3 expense category (cashflow-'
  'domain). NULLABLE: NULL = Unsorted-pending (SELF-200; a txn lands uncategorized and '
  'the user assigns later). Decision-3 CANONICAL #10: matched-tenant fence (012 Pattern '
  '1), but CHAIN-RESOLVED — the referenced user_taxonomy row must share the annotation''s '
  'owning tenant, resolved via trans_id → account_trans → account.users_id (this table '
  'has no local users_id; contrast 012/022 which match a local new.users_id). Fenced by '
  'fn_account_trans_annotation_matched_sub_cat (BEFORE INSERT OR UPDATE). §6A C-NOTE '
  'shape (a) [chain-resolved] — Sec rules (a) vs (b) at joint-review. Matched-DOMAIN '
  '(domain=''cashflow'') is app-layer in V1.';
comment on column pfin.account_trans_annotation.note is
  'Free-text user note on the transaction (folds in the Rev-6 #3 standalone note table). '
  'Nullable. The user''s editable layer — never touches the immutable ledger.';

alter table pfin.account_trans_annotation enable row level security;

-- Parent-FK-chain RLS (the 006 account_trans / 005 reconciliation_event_trans shape).
-- The annotation has no own users_id: every policy resolves tenancy via trans_id →
-- account_trans.account_id → account_users. SELECT keys on rd_access; all WRITES key on
-- wr_access (mod #3). Full CRUD (MUTABLE overlay — contrast the append-only ledgers,
-- which carry only SELECT + INSERT).

-- SELECT: rd_access-JOIN. A user sees an annotation only for a transaction on an account
-- they hold rd_access on.
create policy ata_select on pfin.account_trans_annotation
  for select to authenticated
  using (exists (
    select 1
    from pfin.account_trans t
    join pfin.account_users au on au.account_id = t.account_id
    where t.trans_id = account_trans_annotation.trans_id
      and au.users_id = auth.uid()
      and au.rd_access
  ));

comment on policy ata_select on pfin.account_trans_annotation is
  'Parent-FK-chain SELECT policy (006/005 shape): rd_access-JOIN via trans_id → '
  'account_trans.account_id → account_users. A user reads an annotation only for a '
  'transaction whose account they hold an account_users grant with rd_access on. The '
  'annotation carries no own users_id — this chain IS its tenancy.';

-- INSERT: wr_access-JOIN WITH CHECK. A user creates an annotation only for a transaction
-- on an account they hold wr_access on.
create policy ata_insert on pfin.account_trans_annotation
  for insert to authenticated
  with check (exists (
    select 1
    from pfin.account_trans t
    join pfin.account_users au on au.account_id = t.account_id
    where t.trans_id = account_trans_annotation.trans_id
      and au.users_id = auth.uid()
      and au.wr_access
  ));

comment on policy ata_insert on pfin.account_trans_annotation is
  'Parent-FK-chain INSERT policy: wr_access-JOIN WITH CHECK via trans_id → '
  'account_trans.account_id → account_users (mod #3 — writes key on wr_access, not '
  'rd_access). A user creates an annotation only for a transaction whose account they '
  'hold wr_access on.';

-- UPDATE: wr_access-JOIN USING + WITH CHECK. Re-categorization / note edit — the primary
-- mutable path. Both clauses key on wr_access so a row cannot be repointed to a
-- transaction on an account the caller lacks wr_access on.
create policy ata_update on pfin.account_trans_annotation
  for update to authenticated
  using (exists (
    select 1
    from pfin.account_trans t
    join pfin.account_users au on au.account_id = t.account_id
    where t.trans_id = account_trans_annotation.trans_id
      and au.users_id = auth.uid()
      and au.wr_access
  ))
  with check (exists (
    select 1
    from pfin.account_trans t
    join pfin.account_users au on au.account_id = t.account_id
    where t.trans_id = account_trans_annotation.trans_id
      and au.users_id = auth.uid()
      and au.wr_access
  ));

comment on policy ata_update on pfin.account_trans_annotation is
  'Parent-FK-chain UPDATE policy: wr_access-JOIN USING + WITH CHECK. The re-categorize / '
  'edit-note path (the overlay''s reason for existing — a mutable layer that keeps the '
  'ledger clean). Both clauses gate on wr_access via the account chain; the matched-'
  'tenant fence (fn_account_trans_annotation_matched_sub_cat) additionally blocks '
  're-pointing sub_cat_id to another tenant''s Sub-Cat.';

-- DELETE: wr_access-JOIN USING. Clearing an annotation.
create policy ata_delete on pfin.account_trans_annotation
  for delete to authenticated
  using (exists (
    select 1
    from pfin.account_trans t
    join pfin.account_users au on au.account_id = t.account_id
    where t.trans_id = account_trans_annotation.trans_id
      and au.users_id = auth.uid()
      and au.wr_access
  ));

comment on policy ata_delete on pfin.account_trans_annotation is
  'Parent-FK-chain DELETE policy: wr_access-JOIN USING. A user clears an annotation only '
  'for a transaction whose account they hold wr_access on.';

-- ACL-before-RLS (PR #106 gotcha): the role needs table-level GRANTs even with RLS on.
-- Full V1 CRUD (MUTABLE overlay — the user edits their own annotation). No service_role
-- grant (no service_role annotation writer in V1 — R-18 lazy). anon zero-grant.
grant select, insert, update, delete on pfin.account_trans_annotation to authenticated;

-- updated_at auto-refresh via the existing DEFINER allowlist entry #1 (001). Adds NO new
-- DEFINER entry (allowlist stays 3).
create trigger account_trans_annotation_set_updated_at
  before update on pfin.account_trans_annotation
  for each row execute function pfin.fn_refresh_updated_at();

-- ----------------------------------------------------------------------------
-- Decision-3 CANONICAL #10 — matched-tenant fence on sub_cat_id (012 Pattern 1),
-- CHAIN-RESOLVED (§6A C-NOTE shape (a) — the Architect recommendation; SEC RULES (a) vs
-- (b) at joint-review). The annotation has NO own users_id, so the owning tenant is
-- resolved via trans_id → account_trans.account_id → account.users_id (mirrors 017's
-- chain-JOIN tenant resolution), then matched against user_taxonomy.users_id. BEFORE
-- INSERT OR UPDATE (MUTABLE table — the user re-categorizes). SECURITY INVOKER.
--
-- IF SEC RULES (b) [RLS-composition belt-and-suspenders]: DROP this function + its
-- trigger; the RLS parent-chain + user_taxonomy_select's auth.uid()-scoping fence the
-- authenticated-only path. See the C-NOTE for why (a) is recommended (future-proof for a
-- possible service_role annotation writer under §6A Option A; family-discipline
-- consistency; Decision-3 non-negotiability).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_trans_annotation_matched_sub_cat()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Trigger WHEN clause guarantees new.sub_cat_id IS NOT NULL.
  -- CHAIN-RESOLVED matched-tenant: resolve the annotation's owning tenant via
  -- trans_id → account_trans.account_id → account.users_id, then require the referenced
  -- user_taxonomy row to share it.
  -- NULL-SAFE FAIL-CLOSED: a missing taxonomy row, a missing/unreadable transaction, a
  -- missing account, OR a users_id mismatch yields NOT EXISTS → raise. (Never
  -- `(subquery) <> ...` — that returns NULL on a missing row, the IF is skipped, and the
  -- write would leak.)
  -- LOAD-BEARING regardless of writer (C-NOTE (a)): the explicit ut.users_id =
  -- acc.users_id predicate is authoritative even if RLS is bypassed (a hypothetical
  -- service_role annotation writer under §6A Option A). Under authenticated it composes
  -- with user_taxonomy_select + the account-chain RLS as belt-and-suspenders.
  if not exists (
    select 1
    from pfin.user_taxonomy ut
    join pfin.account_trans t on t.trans_id = new.trans_id
    join pfin.account acc on acc.account_id = t.account_id
    where ut.id = new.sub_cat_id
      and ut.users_id = acc.users_id
  ) then
    raise exception
      'cross-tenant Sub-Cat rejected: sub_cat_id % is not a taxonomy row owned by the tenant of trans_id % (ADR-011 Decision 3 canonical instance #10 / matched-tenant fence, chain-resolved)',
      new.sub_cat_id, new.trans_id;
  end if;
  return new;
end;
$$;

revoke execute on function pfin.fn_account_trans_annotation_matched_sub_cat() from public;

comment on function pfin.fn_account_trans_annotation_matched_sub_cat() is
  'BEFORE INSERT OR UPDATE matched-tenant fence on pfin.account_trans_annotation.sub_cat_id (ADR-011 Decision 3 canonical instance #10 / 012 Pattern 1, CHAIN-RESOLVED; ADR-027 R-17; SELF-283). The last label of the ADR-027 (g) 5→10 batch (#6–#10); NOT the last of the family (#11 holdings_checkpoint.security_id @ 019 is a distinct-provenance label per (p), outside this batch). Rejects annotating a transaction with another tenant''s Sub-Cat: the referenced user_taxonomy row must share the annotation''s OWNING tenant — resolved via trans_id → account_trans.account_id → account.users_id (this table has NO own users_id; contrast 012/022 which match a local new.users_id, and mirroring 017''s chain-JOIN tenant resolution). NULL-safe fail-closed (NOT EXISTS → raise). SECURITY INVOKER + set search_path = '''' — the explicit ut.users_id = acc.users_id predicate is authoritative regardless of RLS (§6A C-NOTE (a): load-bearing if a service_role annotation writer is ever added under §6A Option A eager-seed); under authenticated it composes with user_taxonomy_select (auth.uid()-scoped) + the account-chain RLS as belt-and-suspenders. Covers UPDATE (re-categorization — the overlay''s primary edit path), not just INSERT. Trigger (not a bare CHECK) because it subqueries + JOINs the referenced taxonomy + account chain — Decision 3 permits a trigger where PG cannot express the constraint declaratively. Not a DEFINER allowlist entry (INVOKER); allowlist stays 3. Matched-DOMAIN (domain=''cashflow'') is app-layer in V1 (012 DOMAIN NOTE). SEC RULES (a) chain-resolved vs (b) RLS-composition-only at joint-review — if (b), this function + its trigger are dropped.';

create trigger account_trans_annotation_matched_sub_cat
  before insert or update on pfin.account_trans_annotation
  for each row
  when (new.sub_cat_id is not null)
  execute function pfin.fn_account_trans_annotation_matched_sub_cat();
