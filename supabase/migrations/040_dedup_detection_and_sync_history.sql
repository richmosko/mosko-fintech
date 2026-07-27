-- ============================================================================
-- Migration: SELF-204 manual↔provider dedup DETECTION + per-account sync-history read.
--   Four surfaces, all per ADR-034 (landed) + ADR-034 Amendment 1 (this PR):
--     (i)   RELAX account_trans_hash_dedup_idx: UNIQUE → plain non-unique lookup index.
--     (ii)  fn_create_manual_trans gains an additive p_import_hash param (stores it;
--           stays SECURITY INVOKER; does NOT compute the hash — shared TS does, ADR-034 D4).
--     (iii) pfin.manual_provider_dup_candidate — a DETECTION-ONLY security_invoker view
--           surfacing manual↔provider candidate pairs by shared import_hash.
--     (iv)  pfin.linked_source_sync_history — a per-account sync-history curated view over
--           the service_role-only linked_source_sync_audit (015).
--   Phase 6 Build Loop. F/CTO-ratified: ADR-034 (2026-07-27) + option X (2026-07-27, the
--   index relaxation). Design memo temp/self-204-reconciliation-design.md; ADR-034 + Amdt 1.
--   surface:plaid + sec-joint-review — Sec joint-review MANDATORY before merge (esp. the
--   final create-view text of surface iv).
--
-- Numbering: 040 follows 039 (stock-split entry). Depends on 004 (account_trans immutable
--   ledger — the hash index host + the import_hash column + source_provider/is_reverse the
--   detection view reads), 017 (source_provider / provider_txn_id / import_hash cols), 015
--   (linked_source_sync_audit — the sync-history source + its users_id/detail cols), 038
--   (fn_create_manual_trans — the RPC widened), 006 (account_trans rd_access-JOIN RLS the
--   detection view composes under), 003 (account), 001 (pfin schema). No downstream depends
--   on 040.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NO new SECURITY DEFINER (allowlist STAYS 4 = 3 authored + 1 reserved).
--   (ii) fn_create_manual_trans stays SECURITY INVOKER (adds a param, no posture change; it
--        STORES the caller-supplied hash, computes nothing → no elevated privilege).
--   (iii) manual_provider_dup_candidate is a security_invoker=true VIEW — it exposes
--        account_trans data the caller ALREADY reads under its own RLS (rd_access-JOIN, 006);
--        both self-join legs are RLS-scoped to the caller. No column-hiding needed (the caller
--        owns both rows). INVOKER is correct + sufficient.
--   (iv) linked_source_sync_history is an OWNER-SEMANTICS security_barrier VIEW
--        (security_invoker = FALSE) — DELIBERATE MECHANISM CHOICE, flagged for Sec:
--        ADR-034 Decision 3's binding ruling is that the user may read ONLY provider + source
--        + created_at + named scalar COUNT keys extracted from `detail`, and MUST NOT read the
--        `detail` blob or `event_type`. A security_invoker view would require granting the
--        caller SELECT on the base table → the caller could then `select detail …` DIRECTLY,
--        defeating the projection. And a JSONB scalar-key (detail->'result'->>'…') cannot be
--        exposed via column-level GRANT without granting the whole `detail` column. Therefore
--        the ONLY mechanism that satisfies "expose count-keys, hide the blob" WITHOUT a new
--        SECURITY DEFINER function is an owner-semantics (security_invoker=false) +
--        security_barrier view that reads the base table with the view owner's privilege,
--        scopes rows itself (WHERE users_id = auth.uid()), and exposes ONLY the projected
--        expressions. The base table linked_source_sync_audit is NOT granted to authenticated
--        (stays service_role-only per 015). A non-invoker VIEW is not a SECURITY DEFINER
--        FUNCTION → the DEFINER allowlist is UNCHANGED at 4; but this IS a privileged-read
--        surface → Sec joint-review of the final view text is mandatory (surface:plaid).
--        PER-CONNECTION (F/CTO ratify 2026-07-27; ADR-034 Amdt 1): the view also resolves +
--        projects the caller's OWN linked_source_id (via an OWNER-SCOPED join of the audit's
--        (provider, external_connection_id) → pfin.linked_source WHERE users_id = auth.uid())
--        so Backend can filter per-account. This re-opens the Sec-verified projection (adds
--        linked_source_id) → Sec RE-REVIEW: linked_source_id is the user's OWN connection FK
--        (owner-safe, = account.linked_source_id); the added join is owner-scoped on BOTH sides
--        (fail-closed, cannot widen); the raw external_connection_id stays UN-projected.
--   (i) the index relaxation authors no function (pure DDL). See below.
--
-- ----------------------------------------------------------------------------
-- (i) INDEX RELAXATION — account_trans_hash_dedup_idx UNIQUE → non-unique (ADR-034 Amdt 1;
--   F/CTO option X, 2026-07-27). The 004 hard-UNIQUE (account_id, import_hash) WHERE
--   import_hash IS NOT NULL is INCOMPATIBLE with ADR-034's DETECTION-ONLY model: once
--   import_hash is populated on manual rows, (a) two legitimately-identical manual entries
--   (same account/date/amount/vendor → same canonical hash, ADR-034 D4) would be REJECTED by
--   uniqueness, and (b) a manual row and its provider echo could not COEXIST (the provider
--   sync would abort on the unique collision) — but detection-as-a-read REQUIRES the pair to
--   coexist so the user can reconcile. The hard content-hash dedup fence is VESTIGIAL today
--   (import_hash NULL everywhere) and REDUNDANT for providers (they dedup on the separate
--   account_trans_provider_dedup_idx (source_provider, provider_txn_id)). Relaxed to a plain
--   non-unique lookup index (serves the detection self-join). MILD ONE-WAY DOOR: re-adding
--   uniqueness later fails if duplicate hashes already exist. DDL on the index only — NOT row
--   DML → the 004 immutability triple-fence is untouched (same as 017 dropping the plaid idx).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list. Decision 4 read verbatim before drafting.) 040 introduces ZERO
--   catalogued §10 instances; the ledger STAYS at 3 (RT-22 + RT-26 + RT-27).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — unchanged.
--   (ii)  Layer-attribution: an index relax + an INVOKER RPC param + two authenticated-tier
--         read views. NO service_role grant is added (linked_source_sync_audit stays
--         service_role-only for its base ACL; the owner-semantics view is the read path). No
--         infrastructure-credential-presence (RT-22), no SUPABASE_SERVICE_ROLE_KEY code fence
--         (RT-26), no network-exposure/config admission (RT-27) surface is touched. Nothing
--         becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 040 is not the anchor.
--   DE-CONFLATION GUARD: the sync-history owner-semantics view is a privileged-READ surface
--   (Sec-reviewed), NOT a §10 catalogued instance and NOT a Decision-3 instance.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — family delta = +0 (UNCHANGED). 040 adds NO
--   FK-shaped reference column: the index relax removes a uniqueness property (no FK); the
--   p_import_hash param stores a text value (no FK); the detection view READS existing FKs;
--   the sync-history view keys on users_id (015's resolved-tenant SOLE anchor — direct-owner,
--   not a matched-tenant two-anchor FK). Family count UNCHANGED; verify the live count against
--   ADR-011 Decision 3 at joint-review — 040 contributes none.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (confirmed): §10 catalogued instances = 3 (unchanged) · SECURITY DEFINER
--   allowlist = 4 (unchanged — fn_create_manual_trans stays INVOKER; the two views are not
--   DEFINER functions) · Decision-3 family = unchanged (no new FK-shaped column).
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   account_trans_hash_dedup_idx — now a PLAIN non-unique index on (account_id, import_hash)
--     WHERE import_hash IS NOT NULL (was UNIQUE; ADR-034 Amdt 1 / option X). Lookup only.
--   pfin.fn_create_manual_trans(p_account_id bigint, p_transaction_date date, p_amount
--     numeric, p_vendor text=null, p_description text=null, p_sub_cat_id bigint=null, p_note
--     text=null, p_import_hash text=null) RETURNS bigint — SECURITY INVOKER, unchanged
--     behavior + stores p_import_hash into account_trans.import_hash (the caller/Backend
--     computes the canonical hash in shared TS, ADR-034 D4 — the RPC does NOT compute it;
--     NULL = no hash, the pre-040 behavior). 7-arg callers still resolve (p_import_hash
--     defaults NULL). set search_path=''.
--   pfin.manual_provider_dup_candidate — security_invoker=true VIEW. For the caller's own
--     accounts (RLS rd_access-JOIN), one row per (manual row, provider row) sharing
--     (account_id, import_hash), both is_reverse=false. Columns: account_id, manual_trans_id,
--     manual_date, manual_amount, manual_vendor, manual_description, provider_trans_id,
--     provider, provider_txn_id, provider_date, provider_amount, import_hash. DETECTION-ONLY:
--     it WRITES nothing, SKIPS nothing, LINKS nothing — it surfaces candidates for the user to
--     reconcile (link via reconciliation_event_trans, or reverse-and-replace). Whether a pair
--     is ALREADY reconciled is SELF-205's interpretation, NOT filtered here (clean boundary).
--   pfin.linked_source_sync_history — OWNER-SEMANTICS security_barrier VIEW (see POSTURE).
--     PER-CONNECTION sync history for the caller (F/CTO per-connection ratify 2026-07-27; ADR-034
--     Amdt 1). Columns (BINDING Sec-verified allowlist): linked_source_id, provider, source,
--     created_at, transactions_inserted (detail->'result'->>'transactionsInserted'),
--     transactions_skipped (detail->'result'->>'transactionsSkipped'). linked_source_id = the
--     caller's OWN pfin.linked_source.source_id, RESOLVED via an owner-scoped join of the audit's
--     (provider, external_connection_id) → pfin.linked_source WHERE users_id = auth.uid() — the
--     per-account filter discriminator (Backend: WHERE linked_source_id = account.linked_source_id).
--     Owner-safe (same value as account.linked_source_id); the raw provider-internal
--     external_connection_id is NOT projected (Sec default-exclude). INNER join → an unresolvable
--     (NULL/foreign) connection is excluded (fail-closed; correct for a per-connection view).
--     HARD RULE (enforced by the view text): NEVER selects `detail` (blob) or `detail->'result'`
--     (sub-object) — only named scalar keys; `detail.corrections` NOT exposed (unverified shape);
--     event_type, external_connection_id, provider_event_id, errlist, error, ok, syncedAt,
--     audit_id excluded. (Optional owner-safe count keys holdingsLanded/balancesLanded/
--     pricesUpserted are Sec-allowlisted additions if AC #4 retains them — omitted here pending
--     the PM AC re-write, which also decides the stale "skip-flagged" third count.)
--   Security-load-bearing edges: detection is caller-scoped + read-only (INVOKER); the
--     sync-history view exposes ONLY the projected owner's-own rows/keys (base table ungranted
--     to authenticated → no direct blob read); the index relax removes a dedup guarantee that
--     detection-only deliberately supersedes. Sec joint-review MANDATORY (surface:plaid).
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- (i) Relax the hash dedup index: UNIQUE → plain non-unique lookup (ADR-034 Amdt 1 / X).
--   Drop the 004 unique index explicitly, recreate non-unique, same columns + partial WHERE.
-- ----------------------------------------------------------------------------
drop index if exists pfin.account_trans_hash_dedup_idx;

create index if not exists account_trans_hash_dedup_idx
  on pfin.account_trans (account_id, import_hash)
  where import_hash is not null;

comment on index pfin.account_trans_hash_dedup_idx is
  'Non-unique lookup index on (account_id, import_hash) WHERE import_hash IS NOT NULL '
  '(SELF-204 / 040; ADR-034 Amendment 1 — RELAXED from UNIQUE per F/CTO option X, 2026-07-27). '
  'The 004 hard-UNIQUE content-hash dedup fence was INCOMPATIBLE with ADR-034 detection-only: '
  'it would reject legitimately-identical manual entries and prevent a manual↔provider pair '
  'coexisting to be surfaced. Vestigial (import_hash NULL pre-040) + redundant (providers dedup '
  'on account_trans_provider_dedup_idx). Now serves the manual_provider_dup_candidate detection '
  'self-join. One-way door: re-adding uniqueness fails if duplicate hashes exist.';

-- ----------------------------------------------------------------------------
-- (ii) fn_create_manual_trans — add the additive p_import_hash param (stores it). DROP the
--   7-arg signature + CREATE the 8-arg (p_import_hash appended, default NULL → 7-arg callers
--   still resolve). SECURITY INVOKER; the RPC does NOT compute the hash (shared TS does, D4).
-- ----------------------------------------------------------------------------
drop function if exists pfin.fn_create_manual_trans(bigint, date, numeric, text, text, bigint, text);

create or replace function pfin.fn_create_manual_trans(
  p_account_id       bigint,
  p_transaction_date date,
  p_amount           numeric,
  p_vendor           text    default null,
  p_description      text    default null,
  p_sub_cat_id       bigint  default null,
  p_note             text    default null,
  p_import_hash      text    default null
)
returns bigint
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_trans_id bigint;
begin
  -- (1) The manual cash row on the immutable audit-class ledger (004 / 017 / 030).
  -- transaction_type='standard' (a cash flow — class comes from the Cat overlay, 030). CASH
  -- SHAPE: security_id NULL + quantity defaults 0 (017 CHECK satisfied). source_provider /
  -- provider_txn_id stay NULL (manual origin — no provider dedup identity). import_hash is now
  -- STORED from p_import_hash (SELF-204 / 040): the shared-TS canonical content hash (account +
  -- date + amount + normalized descriptor, ADR-034 D4) — the RPC does NOT compute it; NULL =
  -- no hash (pre-040 behavior). Populating it feeds the manual_provider_dup_candidate detection
  -- read; the 040-relaxed non-unique hash index means an identical manual entry no longer
  -- aborts. is_reverse defaults false; replaces_trans_id NULL. account_trans carries no own
  -- users_id; tenant scope derives via account_id → account_users wr_access-JOIN (006),
  -- evaluated as the caller (INVOKER) + aal2-gated (025). Cross-tenant p_account_id fails closed.
  insert into pfin.account_trans
    (account_id, transaction_date, amount, vendor, description, transaction_type, import_hash)
  values
    (p_account_id, p_transaction_date, p_amount, p_vendor, p_description, 'standard', p_import_hash)
  returning trans_id into v_trans_id;

  -- (2) The category / note overlay on the 023 MUTABLE annotation (1:1, PK=trans_id). Only
  -- when the caller supplied a category or a note. The #10 chain-resolved matched-tenant fence
  -- + the 030 trade-constraints fence fire BEFORE INSERT WHEN sub_cat_id IS NOT NULL (defense
  -- in depth even through this RPC). ata_insert wr_access-JOIN (023, aal2-claused) is satisfied
  -- in THIS same txn by the row (1) just created under the caller's wr_access.
  if p_sub_cat_id is not null or p_note is not null then
    insert into pfin.account_trans_annotation (trans_id, sub_cat_id, note)
    values (v_trans_id, p_sub_cat_id, p_note);
  end if;

  return v_trans_id;
end;
$$;

revoke execute on function pfin.fn_create_manual_trans(bigint, date, numeric, text, text, bigint, text, text) from public;
grant execute on function pfin.fn_create_manual_trans(bigint, date, numeric, text, text, bigint, text, text) to authenticated;

comment on function pfin.fn_create_manual_trans(bigint, date, numeric, text, text, bigint, text, text) is
  'SECURITY INVOKER manual cash-entry write-composition RPC (Lock 11; SELF-201/202, widened '
  'SELF-204 / 040). Inserts a standard cash account_trans row (+ optional 023 category/note) '
  'under the caller''s RLS. 040 adds the additive p_import_hash param (appended, default NULL): '
  'stores the shared-TS canonical content hash (ADR-034 D4 — the RPC does NOT compute it) into '
  'account_trans.import_hash, feeding manual↔provider dedup detection. NULL = pre-040 behavior '
  '(no hash). 7-arg callers still resolve (param defaults). set search_path='''' — NOT a DEFINER '
  'allowlist entry (INVOKER; allowlist stays 4). EXECUTE authenticated only.';

-- ----------------------------------------------------------------------------
-- (iii) manual_provider_dup_candidate — DETECTION-ONLY security_invoker view. Self-joins
--   account_trans within the caller''s own accounts (RLS rd_access-JOIN applies as caller):
--   a manual leg (source_provider NULL, import_hash set) paired to a provider leg
--   (source_provider set) sharing (account_id, import_hash), both live (is_reverse=false).
--   Surfaces candidate duplicates for the USER to reconcile — no write, no skip, no link.
-- ----------------------------------------------------------------------------
create or replace view pfin.manual_provider_dup_candidate
  with (security_invoker = true) as
  select
    m.account_id,
    m.trans_id          as manual_trans_id,
    m.transaction_date  as manual_date,
    m.amount            as manual_amount,
    m.vendor            as manual_vendor,
    m.description       as manual_description,
    p.trans_id          as provider_trans_id,
    p.source_provider   as provider,
    p.provider_txn_id,
    p.transaction_date  as provider_date,
    p.amount            as provider_amount,
    m.import_hash
  from pfin.account_trans m
  join pfin.account_trans p
    on p.account_id = m.account_id
   and p.import_hash = m.import_hash
  where m.import_hash is not null
    and m.source_provider is null       -- manual leg
    and p.source_provider is not null    -- provider leg
    and m.is_reverse = false
    and p.is_reverse = false;

grant select on pfin.manual_provider_dup_candidate to authenticated;

comment on view pfin.manual_provider_dup_candidate is
  'DETECTION-ONLY candidate-duplicate read (SELF-204 / 040; ADR-034 Decision 2). '
  'security_invoker = true → composes under the caller''s account_trans RLS (rd_access-JOIN, '
  '006); both self-join legs are the caller''s own rows. One row per (manual row, provider row) '
  'sharing (account_id, import_hash), both is_reverse=false — i.e. "this manual row looks like a '
  'synced provider row." WRITES NOTHING, SKIPS NOTHING, LINKS NOTHING: it surfaces candidates '
  'for the user to reconcile (link via reconciliation_event_trans, or reverse-and-replace). '
  'Whether a pair is already reconciled is SELF-205''s interpretation — NOT filtered here (clean '
  'boundary). Matches within an account (the canonical hash includes the account, ADR-034 D4).';

-- ----------------------------------------------------------------------------
-- (iv) linked_source_sync_history — per-account sync-history read over the service_role-only
--   linked_source_sync_audit (015). OWNER-SEMANTICS security_barrier view (security_invoker
--   omitted → false): reads the base table with the view owner''s privilege, scopes rows to the
--   caller (WHERE users_id = auth.uid()), and exposes ONLY the projected columns + named scalar
--   count keys. The base table is NOT granted to authenticated (stays service_role-only, 015) →
--   the caller CANNOT read `detail`/`event_type` directly. BINDING Sec-verified projection; the
--   view text NEVER references `detail` (blob) or `detail->'result'` (sub-object) as a selected
--   value — only the two named scalar keys. Sec joint-review of THIS view text is MANDATORY.
-- ----------------------------------------------------------------------------
create or replace view pfin.linked_source_sync_history
  with (security_barrier = true, security_invoker = false) as
  select
    ls.source_id      as linked_source_id,   -- resolved OWN connection FK (per-connection discriminator; owner-safe)
    lsa.provider,
    lsa.source,
    lsa.created_at,
    (lsa.detail -> 'result' ->> 'transactionsInserted')::int as transactions_inserted,
    (lsa.detail -> 'result' ->> 'transactionsSkipped')::int  as transactions_skipped
  from pfin.linked_source_sync_audit lsa
  join pfin.linked_source ls
    on ls.provider = lsa.provider
   and ls.external_connection_id = lsa.external_connection_id
   and ls.users_id = auth.uid()             -- owner-scoped join: resolves ONLY the caller's own connection (fail-closed; cannot widen)
  where lsa.users_id = auth.uid();

grant select on pfin.linked_source_sync_history to authenticated;

comment on view pfin.linked_source_sync_history is
  'PER-CONNECTION sync-history read (SELF-204 / 040; ADR-034 Decision 3 + Amendment 1; AC #4/#5; '
  'F/CTO per-connection ratify 2026-07-27). OWNER-SEMANTICS security_barrier view '
  '(security_invoker=false): the base linked_source_sync_audit (015) is service_role-only and is '
  'NOT granted to authenticated — this view is the SOLE authenticated read path, exposing ONLY '
  'linked_source_id + provider + source + created_at + the two named scalar count keys '
  'transactions_inserted (detail->''result''->>''transactionsInserted'') + transactions_skipped '
  '(detail->''result''->>''transactionsSkipped''). PER-CONNECTION discriminator: linked_source_id '
  '= the caller''s OWN pfin.linked_source.source_id, RESOLVED by joining the audit''s (provider, '
  'external_connection_id) to pfin.linked_source WHERE users_id = auth.uid() — owner-safe (it is '
  'the same value on account.linked_source_id) and lets Backend filter WHERE linked_source_id = '
  '<the account''s linked_source_id>. The raw provider-internal external_connection_id is NOT '
  'projected (Sec default-exclude); only our own resolved FK is. The join is OWNER-SCOPED on BOTH '
  'sides (lsa.users_id + ls.users_id = auth.uid()) → fail-closed, cannot widen; an audit row with '
  'no caller-owned connection (NULL/unresolvable external_connection_id) is EXCLUDED (INNER join) '
  '— correct for a per-connection view. (provider, external_connection_id) is partial-unique on '
  'linked_source → no fan-out. Owner-semantics is REQUIRED (not security_invoker) so the caller '
  'cannot read the raw `detail` blob or `event_type` directly. Rows scoped WHERE users_id = '
  'auth.uid(). HARD RULE: never selects `detail` or `detail->''result''`; `detail.corrections` '
  '(unverified) + errlist/error/ok/syncedAt/event_type/external_connection_id/provider_event_id/'
  'audit_id all excluded. NOT a SECURITY DEFINER function → DEFINER allowlist stays 4; IS a '
  'privileged-read surface → Sec joint-review of this view text mandatory (surface:plaid). AC #4 '
  '"skip-flagged" third count is likely stale (append-only model, ADR-032) — PM decides at the AC '
  're-write.';
