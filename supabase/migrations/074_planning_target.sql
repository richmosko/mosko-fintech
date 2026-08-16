-- ============================================================================
-- Migration: pfin.planning_target — per-Sub-Cat %Target planning storage.
-- Phase 6 Build Loop (SELF-324; absorbs SELF-232). Realizes the FIRST member of
-- the ADR-011 Decision 18 / Lock 14 settings store, closes the PRD §2.2.2
-- "% Target" column, and unblocks SELF-238 / SELF-240 / SELF-242. Shape
-- F/CTO-ratified 2026-08-16 (Option A of the SELF-324 options pass); recorded at
-- ADR-056.
--
-- WHAT THIS DOES: creates `pfin.planning_target`, ONE row per (users_id,
-- sub_cat_id), carrying `target_percent numeric(5,2)` — the user's target share
-- of total Non-RE for that Sub-Cat. Owner-only RLS on all four verbs (the editor
-- must be able to DELETE — see UNSET SEMANTICS below), each policy carrying the
-- 025 aal2 step-up clause. Adds Decision-3 canonical instance #17: a
-- matched-tenant + asset-domain fence on sub_cat_id.
--
-- WHY A TABLE AND NOT COLUMNS ON pfin.user_settings: 024's header designates
--   user_settings as the home for deferred SELF-232 settings columns. That note
--   is SUPERSEDED as of this migration (ADR-056): the value here is a per-Sub-Cat
--   VECTOR, which no additive scalar ALTER can express, and the two shapes that
--   could (a jsonb blob, an array column) are barred and hazardous respectively —
--   ADR-011 Decision 18 fences JSONB out of the settings store by name, and a
--   key-set of taxonomy ids inside jsonb is FK-shaped in substance while being no
--   column Decision 3 can fence. Independently: 025 excludes pfin.user_settings
--   from the aal2 backstop as NON-NEGOTIABLE (clausing it recurses into the
--   policy that reads it), so settings columns sited there could never carry the
--   step-up fence that every other tenant-owned pfin table carries. 024's header
--   is corrected in place in this PR (a `--` block has no database
--   representation); its policies, grants and DDL are untouched.
--
-- UNSET SEMANTICS (ratified, and load-bearing for SELF-238 AC-3): "no target set"
--   is represented as ROW ABSENT — never as NULL, and never as a seeded 0. Read
--   paths coalesce a missing row to 0, which is what makes SELF-238 AC-3's
--   "allocation but no %Target renders pct_target = 0" fall out without a special
--   case. An explicit 0.00 IS storable and is a different fact (the user asserted
--   a zero target); both read as 0 today, and the distinction survives at no cost
--   if a later surface wants it. This is why DELETE is granted here and is NOT
--   granted on user_settings: clearing a field must remove the row, or "unset"
--   acquires a second representation.
--
-- NO SEED. taxonomy_default (041) seeds the taxonomy; targets are user-authored
--   and start empty. Seeding a 0-row per Sub-Cat per user would make "unset"
--   unrepresentable and would assert a planning decision the user never made.
--
-- NO SUM-TO-100 CONSTRAINT. PRD §2.2.2 deliberately surfaces gaps rather than
--   forcing a balanced book; the running-sum warning is app-layer and
--   non-blocking. It is also a cross-row predicate, which is not declarable.
--
-- ----------------------------------------------------------------------------
-- Numbering: 074 follows 073 (fn_nav_reference_dates); taken at authoring time
--   against the live listing, not reserved ahead. Depends on 001 (pfin schema +
--   pfin.fn_refresh_updated_at, reused for the updated_at trigger), 009
--   (pfin.user_taxonomy — the sub_cat_id FK target and the fence's read), and
--   024/025 only in the sense that the aal2 clause below reads
--   pfin.user_settings.mfa_policy (created at 024, the clause shape locked at
--   025). No downstream migration depends on 074 landing before it.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT
--   SECURITY DEFINER. The one function authored here
--   (pfin.fn_planning_target_matched_sub_cat) is a Decision-3 fence that reads
--   pfin.user_taxonomy and needs no privilege the writer does not already hold:
--   the write it guards happens under the caller's own JWT, and the fence's
--   explicit users_id equality is authoritative independent of what RLS lets the
--   caller see. `set search_path = ''` is applied. The updated_at trigger reuses
--   the EXISTING pfin.fn_refresh_updated_at (001) rather than defining a new
--   helper. The SECURITY DEFINER allowlist is therefore UNCHANGED by this
--   migration — no entry added, none altered (ADR-011 Decision 9; read the
--   allowlist there, not from here).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; the catalogued
-- list is NOT restated here, and no count is carried, deliberately). Decision 4
-- was read verbatim and live before drafting. This migration introduces ZERO
-- catalogued §10 instances: it is a Lock 14 user-facing-direct-DB-write surface,
-- and CLASS MEMBERSHIP IS NOT A CATALOGUED INSTANCE (the ruling ADR-047 already
-- made for the 058 fences). It touches no infrastructure-credential-presence
-- surface, no service_role-key / code-layer allowlist surface, and no
-- network-exposure/config surface.
--   (i)   Instance-numbering: unchanged — no catalogued instance is added,
--         reordered, or renumbered.
--   (ii)  Layer-attribution: unchanged — no catalogued instance's layer is
--         re-attributed, and no surface becomes "four-layer". service_role is NOT
--         granted here, so 008's DB-ACL posture is unchanged — and that would be a
--         DB-ACL change, not a catalogued-instance change, regardless.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated.
-- SECURITY §4.5 RT-23 (planning_target write-path RLS + input sanitization) is
-- the pre-existing catalog entry that scopes this surface; this migration
-- realizes what RT-23 already describes and adds no RT.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — this migration ADDS
-- ONE instance, and its label is #17. Read ADR-011 Decision 3's numbered list
-- live for the family's shape; the fold-in for #17 lands in THAT list in THIS PR
-- (the rule written after the #15 and #16 fold-ins both slipped — a migration
-- asserting a canonical label whose canon does not yet contain it is shipping a
-- forward reference to a document it does not control).
--   - users_id -> auth.users(id): the tenant anchor ITSELF, not a cross-tenant
--     reference. Carries no matched-tenant obligation (the 009 / 022 / 024
--     shape). NOT a Decision-3 instance.
--   - sub_cat_id -> pfin.user_taxonomy(id): BOTH SIDES PER-USER, referring row
--     has its own users_id => Pattern 1 (matched-tenant, LOCAL ANCHOR), the 012
--     shape, identical in structure to canonical #8 (user_asset_category.sub_cat_id
--     at 022). This is canonical instance #17 — the label ADR-042 Decision 5a left
--     unallocated ("the next instance takes #17"). Realized below as
--     fn_planning_target_matched_sub_cat, BEFORE INSERT OR UPDATE, INVOKER,
--     `set search_path = ''`, NULL-safe fail-closed.
--   - No INTEGER[]/array FK, no self-FK, no other reference column.
--
-- MATCHED-DOMAIN IS DB-ENFORCED HERE — a deliberate DEPARTURE from 012/022, not
--   an oversight, and it does not retroactively change them. 012 and 022 leave
--   `user_taxonomy.domain = 'asset'` to the app layer because on those surfaces a
--   second constraint already narrows the row (022 pairs the Sub-Cat with an
--   asset). This table has no such second side: a cash-flow Sub-Cat id is a
--   perfectly valid, tenant-owned taxonomy id, so tenant-matching alone would
--   admit a %Target on an income category — a nonsense row that every §2.2 read
--   path would then have to filter. The fence therefore carries BOTH predicates,
--   the one-fence-two-predicates precedent set by canonical #14 (lot_match:
--   matched-tenant AND matched-security in a single fence).
--
-- REAL-ESTATE EXCLUSION IS DELIBERATELY *NOT* FENCED. PRD §2.2.2 excludes Real
--   Estate from the rebalance view, but "non-RE" is a rule over user-editable
--   `cat` text evaluated at read time. A constraint over it would have nothing to
--   catch today and would become an outage the moment V2 taxonomy-CRUD renames a
--   Cat. It is a read-layer filter and a test assertion, not a fence.
--
-- ----------------------------------------------------------------------------
-- EXPOSURE / C6 RLS-COVERAGE NOTE (ADR-023 C6 standing obligation — pfin is in
-- [api] schemas, so this table is internet-facing the moment it is granted):
--   - RLS ENABLED on pfin.planning_target (below).
--   - POLICIES PRESENT: SELECT + INSERT + UPDATE + DELETE, each owner-gated
--     (users_id = auth.uid()), each write policy carrying WITH CHECK so a row
--     cannot be created or repointed to another tenant. Full CRUD is the correct
--     shape here (the user authors and clears their own targets) — contrast 009's
--     write-dormancy and 024's no-DELETE posture.
--   - AAL2 STEP-UP BACKSTOP (ADR-029 / 025 C3 standing obligation): every policy
--     below AND-s the per-user-conditional aal2 clause, inline and COALESCE
--     null-safe, in the exact 025 shape. This table is a sensitive tenant-owned
--     pfin table and none of 025's three exclusions apply to it: it is not a
--     global shared-read registry, it is not service_role-only/default-deny, and
--     it is not the user_settings substrate the clause itself reads. 025's own
--     target-set enumeration describes 025's moment and is left untouched.
--   - GRANT: authenticated SELECT+INSERT+UPDATE+DELETE. anon ZERO-grant (pfin
--     schema-usage denial, ADR-023 C2 outer fence). service_role NOT granted —
--     there is no worker or server-role writer to planning_target; the app writes
--     as the user, under the user's own JWT.
--   - Two-layer fence intact: outer = anon zero pfin grant; inner = RLS
--     users_id = auth.uid() on read AND write (WITH CHECK), plus the aal2 clause
--     and the #17 matched-tenant fence beneath both.
--   This table does NOT ship without the paired QA two-tenant pgTAP battery
--   (SECURITY §4.5, EXPOSURE-gating per C6). QA authors the battery (Architect
--   does not edit tests/); Sec sign-off gates merge.
--
--   ⚠ THE WRITE-SIDE WITH CHECK IS NOT INDEPENDENTLY OBSERVABLE FROM AN
--   `authenticated` SESSION, and a battery that does not know this will prove the
--   wrong control. Measured on a scratch apply: a BEFORE trigger fires before RLS
--   WITH CHECK is evaluated, and the #17 fence below reads pfin.user_taxonomy as
--   INVOKER — so under `authenticated`, ANY cross-tenant INSERT is refused by the
--   fence first. Naming another tenant's Sub-Cat trips leg 2; naming one's own
--   users_id-mismatched row trips leg 1, because the referenced taxonomy row is
--   RLS-invisible to the attacker and therefore "unresolvable". Both are correct
--   refusals and both come from the FENCE. A test asserting only "cross-tenant
--   write fails closed" therefore goes green while the policy's WITH CHECK is
--   never exercised. The battery should assert the WITH CHECK's PRESENCE
--   structurally (its expression in pg_policy) in addition to the behavioural
--   fail-closed legs — the two controls are layered, not redundant, and only the
--   outer one is reachable from the tier that matters.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.planning_target — per-user, per-Sub-Cat allocation target. ONE row per
--   (users_id, sub_cat_id); a row EXISTS iff the user has set a target.
--     - id (bigint identity PK): surrogate key.
--     - users_id (uuid): the tenant anchor. DEFAULT auth.uid() so an authenticated
--       INSERT that omits it lands owned and passes the WITH CHECK; REFERENCES
--       auth.users(id) ON DELETE CASCADE.
--     - sub_cat_id (bigint): FK -> pfin.user_taxonomy(id) ON DELETE RESTRICT. The
--       Sub-Cat this target applies to. RESTRICT, not CASCADE: user_taxonomy has
--       no DELETE grant or policy in V1, so RESTRICT costs nothing now and means a
--       future taxonomy-CRUD delete surfaces the orphaning to the user instead of
--       silently discarding a planning value they entered.
--     - target_percent (numeric(5,2) NOT NULL, CHECK >= 0 AND <= 100): target
--       share of total Non-RE for this Sub-Cat, in percent. TWO NON-FINITE
--       VALUES ARE REJECTED BY TWO DIFFERENT MECHANISMS, and the distinction was
--       measured on a scratch apply rather than assumed:
--         · ±Infinity is refused by the TYPMOD — a numeric(5,2) field cannot hold
--           an infinite value ("numeric field overflow"), so it never reaches the
--           CHECK at all.
--         · NaN IS storable in a constrained numeric (NaN carries no precision),
--           so it DOES reach the CHECK — and is caught by the UPPER bound, since
--           NaN sorts above every non-NaN numeric and therefore satisfies
--           `>= 0`. A one-sided `>= 0` would admit NaN.
--       So the bound is two-sided because of NaN, and it stays the durable guard:
--       if the typmod is ever widened to a bare `numeric`, the upper bound is
--       what continues to refuse Infinity. This is the DB half of Lock 14 mod #2;
--       the app-layer numeric adversarial battery is the first line and is not
--       replaced by it.
--     - created_at / updated_at (timestamptz): convention columns; updated_at
--       auto-refreshed by the existing fn_refresh_updated_at trigger.
--     - unique (users_id, sub_cat_id): one target per user per Sub-Cat, and the
--       ON CONFLICT target for the editor's UPSERT-in-place write (ADR-011
--       Decision 18: settings are UPSERTed, not versioned — no edit-history rows).
--       Leading users_id also serves the RLS predicate, so no separate index.
--   Security-load-bearing edges: RLS users_id = auth.uid() fences reads AND writes
--     (WITH CHECK) to the owner; the aal2 clause fences a non-stepped-up session of
--     a user who declared totp/passkey; the #17 fence rejects a target pointing at
--     another tenant's Sub-Cat OR at a non-asset Sub-Cat; the two-sided CHECK
--     rejects NaN / Infinity / out-of-range; ON DELETE CASCADE ties row lifecycle
--     to the user; ON DELETE RESTRICT protects the referenced taxonomy row.
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- pfin.planning_target — per-(user, Sub-Cat) %Target (ADR-011 Decision 18 /
-- Lock 14 first member; shape ratified 2026-08-16, recorded at ADR-056).
-- ----------------------------------------------------------------------------
create table if not exists pfin.planning_target (
  id              bigint generated always as identity primary key,
  users_id        uuid not null default auth.uid()
                    references auth.users (id) on delete cascade,
  sub_cat_id      bigint not null
                    references pfin.user_taxonomy (id) on delete restrict,
  target_percent  numeric(5, 2) not null
                    check (target_percent >= 0 and target_percent <= 100),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (users_id, sub_cat_id)
);

comment on table pfin.planning_target is
  'Per-user, per-Sub-Cat allocation target (PRD §2.2.2 "% Target"; ADR-011 '
  'Decision 18 / Lock 14 settings store, first member realized; SELF-324, which '
  'absorbed SELF-232). ONE row per (users_id, sub_cat_id). UNSET IS REPRESENTED AS '
  'ROW ABSENT — never NULL, never a seeded zero; read paths coalesce a missing row '
  'to 0, and an explicit 0.00 is a storable and different fact (the user asserted a '
  'zero target). That is why DELETE is granted here and is not on user_settings: '
  'clearing a target must remove the row. Targets are user-authored and start '
  'empty — 041 seeds the taxonomy, nothing seeds this. UPSERT-in-place on the '
  '(users_id, sub_cat_id) unique key per Decision 18 (settings are not audit-class; '
  'no edit-history rows). MUTABLE, full authenticated CRUD, RLS direct-owner '
  '(users_id = auth.uid()) with the ADR-029 / 025 aal2 step-up clause on every '
  'policy. Carries ONE Decision-3 fence: sub_cat_id -> user_taxonomy = CANONICAL '
  '#17, matched-tenant AND matched-domain in a single fence (the #14 '
  'two-predicate precedent) — a cash-flow Sub-Cat can no more carry a %Target than '
  'another tenant''s can. users_id is the sole anchor and is NOT a Decision-3 '
  'instance. Real-Estate exclusion is a §2.2.2 READ-LAYER rule over user-editable '
  'cat text and is deliberately not fenced here. anon zero-grant; service_role '
  'ungranted (the app writes as the user, under the user''s own JWT). No JSONB, per '
  'Decision 18''s forward-compat fence.';

comment on column pfin.planning_target.users_id is
  'SOLE tenant anchor (users_id = auth.uid()). DEFAULT auth.uid() so an '
  'authenticated INSERT that omits it lands owned and passes the WITH CHECK; FK -> '
  'auth.users(id) ON DELETE CASCADE with the tenant. NOT a cross-tenant reference '
  '(it IS the anchor) -> ADR-011 Decision 3 does not apply to this column. Lock 14 '
  'mod #1 requires the write path derive this from the session (auth.uid()), never '
  'from the request body.';

comment on column pfin.planning_target.sub_cat_id is
  'FK -> pfin.user_taxonomy(id) ON DELETE RESTRICT — the Sub-Cat this target '
  'applies to. ADR-011 Decision 3 CANONICAL #17: matched-tenant fence in the 012 '
  'Pattern-1 shape (local anchor; the referenced taxonomy row MUST share this '
  'row''s users_id), carrying additionally the matched-DOMAIN predicate '
  '(user_taxonomy.domain MUST be ''asset''). Fenced by '
  'pfin.fn_planning_target_matched_sub_cat (BEFORE INSERT OR UPDATE). RESTRICT '
  'rather than CASCADE: a taxonomy row that a user has targeted MUST NOT be '
  'deletable out from under the target silently — the delete is refused and the '
  'orphaning surfaces. user_taxonomy carries no DELETE grant or policy at the time '
  'this column was authored, so RESTRICT constrains no existing path.';

comment on column pfin.planning_target.target_percent is
  'Target share of total Non-RE for this Sub-Cat, in percent. numeric(5,2) NOT '
  'NULL, CHECK (>= 0 AND <= 100). THE BOUND IS TWO-SIDED FOR A REASON THAT IS NOT '
  'RANGE-CHECKING, and the two non-finite values are refused by two DIFFERENT '
  'mechanisms: ±Infinity is refused by the TYPMOD (a numeric(5,2) field cannot hold '
  'an infinite value) and never reaches the CHECK, while NaN IS storable in a '
  'constrained numeric and reaches it — where the UPPER bound catches it, because '
  'NaN sorts above every non-NaN numeric and so satisfies >= 0. A one-sided lower '
  'bound would admit NaN. The upper bound also remains what would refuse Infinity '
  'if the typmod were ever widened to a bare numeric, which is why it is the '
  'durable half. This is the DB half of the Lock 14 mod #2 numeric-input discipline and does not '
  'replace the app-layer adversarial battery, which remains the first line. There '
  'is deliberately NO sum-to-100 constraint: PRD §2.2.2 surfaces gaps rather than '
  'forcing a balanced book, and a cross-row sum is not declarable anyway — the '
  'running-sum warning is app-layer and non-blocking.';

alter table pfin.planning_target enable row level security;

-- ----------------------------------------------------------------------------
-- RLS — direct-owner, full CRUD, every policy AND-ing the ADR-029 / 025 aal2
-- step-up clause (inline, COALESCE null-safe, no helper — the 025 shape verbatim).
-- The clause FAILS OPEN on a missing/'none' mfa_policy by design (025's
-- layer-posture asymmetry): the universal tenant RLS still fully fences the user,
-- and the backstop enforces only the positive assertion "this user DECLARED
-- totp/passkey". The app-layer step-up guard is the fail-closed complement.
-- ----------------------------------------------------------------------------
create policy planning_target_select on pfin.planning_target
  for select to authenticated
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

create policy planning_target_insert on pfin.planning_target
  for insert to authenticated
  with check (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

create policy planning_target_update on pfin.planning_target
  for update to authenticated
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  )
  with check (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

create policy planning_target_delete on pfin.planning_target
  for delete to authenticated
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- ACL-before-RLS (PR #106 gotcha): the role needs table-level GRANTs even with RLS
-- on. Full V1 CRUD — the user authors, edits and CLEARS their own targets, and the
-- DELETE grant is what makes "unset = row absent" writable. No service_role grant
-- (no service_role writer in V1). anon zero-grant (schema-usage-layer denial).
grant select, insert, update, delete on pfin.planning_target to authenticated;

-- No separate users_id index: the unique (users_id, sub_cat_id) btree leads with
-- users_id and already serves both the RLS predicate (users_id = auth.uid()) and
-- the §2.2.2 read join (which runs with users_id fixed by RLS and matches on
-- sub_cat_id). Mirrors 009 / 022.

-- updated_at auto-refresh via the EXISTING fn_refresh_updated_at (001). Adds no
-- SECURITY DEFINER allowlist entry.
create trigger planning_target_set_updated_at
  before update on pfin.planning_target
  for each row execute function pfin.fn_refresh_updated_at();

-- ----------------------------------------------------------------------------
-- Decision-3 CANONICAL #17 — matched-tenant AND matched-domain fence on
-- sub_cat_id (012 Pattern 1, local anchor; two predicates in one fence per the
-- #14 precedent). BEFORE INSERT OR UPDATE — the table is mutable (the user
-- re-targets), so an INSERT-only fence would leave the repoint path open.
-- SECURITY INVOKER, set search_path = '', NULL-safe fail-closed.
--
-- THREE DISTINCT FAILURE LEGS, deliberately not collapsed into one NOT EXISTS:
-- the diagnostics differ, and so does WHO can reach them.
--   (1) unresolvable — the taxonomy row does not exist, or RLS does not let this
--       caller see it. Under `authenticated`, a cross-tenant sub_cat_id lands
--       HERE, not on leg (2), because user_taxonomy_select filters it away first.
--   (2) cross-tenant — the row resolved and its users_id differs. Reachable only
--       by a writer that is RLS-EXEMPT (the migration role, a superuser, any
--       future service_role path). This is the ADR-042 Decision 5a rationale for
--       #16 restated: the fence earns its keep precisely against the writer no
--       policy catches. It is NOT dead code, and a battery that can only run as
--       `authenticated` cannot exercise it.
--   (3) wrong domain — the row is owned but is a cash-flow Sub-Cat.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_planning_target_matched_sub_cat()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_users_id  uuid;
  v_domain    text;
begin
  -- NULL-SAFE FAIL-CLOSED: resolve first, then test. Never
  -- `(subquery) <> new.users_id` — that yields NULL on a missing row, the IF is
  -- skipped, and the write leaks through.
  select t.users_id, t.domain
    into v_users_id, v_domain
    from pfin.user_taxonomy t
   where t.id = new.sub_cat_id;

  if not found then
    raise exception
      'planning target rejected: sub_cat_id % does not resolve to a taxonomy row readable by users_id % (ADR-011 Decision 3 canonical instance #17 / matched-tenant fence, leg 1 unresolvable)',
      new.sub_cat_id, new.users_id;
  end if;

  if v_users_id is distinct from new.users_id then
    raise exception
      'cross-tenant planning target rejected: sub_cat_id % is owned by another tenant, not by users_id % (ADR-011 Decision 3 canonical instance #17 / matched-tenant fence, leg 2 cross-tenant)',
      new.sub_cat_id, new.users_id;
  end if;

  if v_domain is distinct from 'asset' then
    raise exception
      'non-asset planning target rejected: sub_cat_id % is a % Sub-Cat; %%Target applies only to the asset taxonomy (PRD §2.2.2) (ADR-011 Decision 3 canonical instance #17 / matched-domain predicate, leg 3 wrong domain)',
      new.sub_cat_id, v_domain;
  end if;

  return new;
end;
$$;

revoke execute on function pfin.fn_planning_target_matched_sub_cat() from public;

comment on function pfin.fn_planning_target_matched_sub_cat() is
  'BEFORE INSERT OR UPDATE matched-tenant AND matched-domain fence on '
  'pfin.planning_target.sub_cat_id (ADR-011 Decision 3 canonical instance #17; 012 '
  'Pattern 1, local anchor; SELF-324). Rejects a %Target that points at another '
  'tenant''s Sub-Cat, at a Sub-Cat that does not resolve, or at a non-asset '
  '(cash-flow) Sub-Cat. Carrying BOTH predicates in one fence follows canonical '
  '#14 (matched-tenant AND matched-security) and DEPARTS from 012 / 022, where the '
  'domain check is app-layer because a second constraint already narrows the row; '
  'this table has no second side, so a tenant-owned cash-flow Sub-Cat would '
  'otherwise be admitted. NULL-safe fail-closed: the referenced row is resolved '
  'into locals and tested, never compared inside a subquery expression that returns '
  'NULL on a miss. Three distinct raises (unresolvable / cross-tenant / wrong '
  'domain) because the diagnostics differ AND because the cross-tenant leg is '
  'reachable only by an RLS-EXEMPT writer — under authenticated, RLS filters a '
  'cross-tenant Sub-Cat away before this fence sees it, so that leg guards the '
  'writer no policy catches (the ADR-042 Decision 5a rationale). Covers UPDATE, not '
  'just INSERT, because the table is mutable and the repoint path is the one an '
  'INSERT-only fence would leave open. SECURITY INVOKER + set search_path = '''' — '
  'the read composes with RLS, and the explicit users_id equality is authoritative '
  'regardless of what RLS lets the caller see. Trigger rather than a bare CHECK '
  'because it subqueries the referenced row, which PostgreSQL cannot express '
  'declaratively. INVOKER: adds no SECURITY DEFINER allowlist entry.';

create trigger planning_target_matched_sub_cat
  before insert or update on pfin.planning_target
  for each row
  execute function pfin.fn_planning_target_matched_sub_cat();
