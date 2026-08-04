-- ============================================================================
-- 057_account_event.sql — pfin.account_event: the audit surface for account
--   open/closed state transitions (ADR-042 Decision 5 + 5a).
--
-- Numbering: 057 follows 056. MUST precede 058 — 058's close gate writes a row
--   here on every closed_at transition, so the table has to exist first.
--
-- ----------------------------------------------------------------------------
-- WHY A SIBLING TABLE AND NOT COLUMNS ON pfin.account (ADR-011 Decision 2):
--   the TRANSITION is audit-class; pfin.account itself is NOT and must not
--   become so (updateAttributes is a correct mutable path). Precedents:
--   015 linked_source_state_history, 031 reclass_history — append-only siblings
--   over a mutable entity.
--
-- NAMED FOR THE GENERAL CLASS, NOT `closure_history`. event_type's CHECK admits
--   only the closure values today and widens by a one-line ALTER (the 030
--   transaction_type CHECK-widen precedent under the ADR-022 code-coupled->CHECK
--   rule). A currency restatement is not a closure; a second near-identical
--   audit table later would duplicate RLS + grants + immutability triggers AND
--   add a Decision-3 instance.
--
--   *** WIDENING event_type IS SEC-JOINT-REVIEW-MANDATORY, NOT A ROUTINE ALTER. ***
--   Every downstream posture here was calibrated FOR CLOSURE EVENTS: the SD tier,
--   the read posture (SELECT policy + grant + the 025 aal2 conjunct), and
--   `indefinite` retention per SECURITY §4.6. A widening silently re-scopes all
--   three, and the SD tier rates WHAT THE CHECK ADMITS, not what the table is
--   named. Convention precedent: ADR-016's webhook-allowlist annotation.
--   A widening may also require NEW TYPED COLUMNS (see the column rule below) —
--   each its own review surface; an FK-shaped one extends the Decision-3 family.
--
-- ----------------------------------------------------------------------------
-- EVERY COLUMN HAS A NAMED WRITER, AND THE CRITERION IS NOT "HAS A WRITER"
--   (Sec, at the 057 concurrence — the criterion that keeps `actor` would kill
--   it under the weaker test):
--
--     >> Does the column ever take MORE THAN ONE VALUE across the writers that
--        exist? <<
--
--   `actor` YES — two values across the table's history: `user:<uid>` and the
--     migration identity. Remediation is one-time, so the VARIETY stops growing;
--     the DISTINCTION is permanent. A transient writer leaves a permanent record.
--   `matched_on` / `decided` NO — ZERO distinguishing values, ever. They were
--     provenance for the sync-path reactivation writer, and the ratified model
--     removed that writer (042 must not clear closed_at; sync writes are refused
--     by 058's transfer-in fence and record to linked_source_sync_audit). Every
--     row would carry the same NULL or the same constant. DROPPED, with
--     `provider_event_id` (no provider event drives a closure) and
--     `linked_source_id` (no system path resolves tenant via a connection —
--     so Decision-3 instance #17 IS NEVER CREATED; the family stays 16/13).
--
--   Do NOT re-add a column on the strength of a hypothetical writer. An unused
--   fenced column is an attractive nuisance: it exists, it looks authoritative,
--   someone eventually populates it BECAUSE IT IS THERE — at which point the
--   fence validates tenant-match but not MEANING.
--
-- NO FREE TEXT ANYWHERE ON THIS SURFACE (F/CTO-ratified 2026-08-03). reason_code
--   is a closed vocabulary; there is NO `other` + "please specify" companion
--   field — an escape-hatch free-text column reintroduces unredactable PII while
--   PRESENTING as a closed vocabulary. This table is audit-class immutable and
--   retained indefinitely, so ADMISSION IS THE ONLY CONTROL: there is no
--   redaction path after the fact, for anyone, including the row's own tenant.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE
--   No SECURITY DEFINER anywhere. The #16 fence is a SECURITY INVOKER trigger
--   (set search_path = ''), as are both immutability fences. DEFINER allowlist
--   STAYS 4 (3 authored). Writers: the user's own close/reopen (a session write
--   under RLS — NOT an ADR-011 Decision 1 privileged-context surface, so clause
--   (d) does not apply to this table) and the one-time remediation, which runs
--   as the migration role and is RLS-exempt — which is exactly why #16 is
--   load-bearing rather than decorative.
-- ============================================================================

create schema if not exists pfin;

create table if not exists pfin.account_event (
  event_id       bigint generated always as identity primary key,
  users_id       uuid not null default auth.uid()
                   references auth.users (id) on delete cascade,
  account_id     bigint not null
                   references pfin.account (account_id) on delete restrict,
  event_type     text not null
                   check (event_type in ('closed', 'reopened')),
  -- VOCABULARY: PM-proposed, F/CTO-ratified 2026-08-03 (ADR-042 Amendment 1 A6).
  --   'closed' RENAMED to 'no_longer_used'. The sense is grounded in PRD §2.4.2
  --   and worth keeping; the NAME collided with event_type='closed', and a value
  --   that reads as a tautology against its own event_type becomes the
  --   safe-looking dumping ground — worse than 'other', because it looks
  --   informative.
  --   'institution_closed' is NEW: bank merges and product discontinuations are
  --   common, are NOT the user's decision, and were previously unrepresentable,
  --   so they landed in 'other' or were misfiled as a user-initiated closure.
  --
  -- ⚠ 'other' IS A BARE VOCABULARY MEMBER. NO COMPANION FREE-TEXT FIELD — no
  --   "please specify", not here, not in the UI, nowhere on this surface
  --   (F/CTO-ratified; ADR-042 Decision 5). An escape-hatch text box
  --   reintroduces the unredactable-PII problem while LOOKING like a closed
  --   vocabulary, and this table is append-only with no redaction path for
  --   anyone, including the row's own tenant. Stated here because a "please
  --   specify" box is how anyone would build an Other option by default, and
  --   THE PROHIBITION IS INVISIBLE FROM THE CHECK.
  --
  -- ⚠ 'other' IS NOT A WEAKENING. Requiredness below is MANDATORY, and 'other'
  --   is what makes mandatory safe: without it, mandatory FORCES
  --   misclassification, and this ADR ruled wrong classification is worse than
  --   absent classification on a row that can never be corrected.
  --   A HIGH 'other' RATE IS EVIDENCE THE VOCABULARY IS WRONG, NOT THAT THE
  --   MANDATE IS WRONG — revisit the values; do not relax the requirement, or
  --   the first signal of a bad taxonomy is lost along with the data.
  --
  -- ONE AXIS, PERMANENTLY (Amendment 1 A7; F/CTO-ratified). These values mix
  --   "why the account ended" with "where the value went", and that conflation
  --   is DECIDED, not pending. No `disposition` column, now or later — one
  --   added later is NULL for every prior row, unbackfillable. Do NOT reopen
  --   this if account_trans later gains transfer-pairing: the rows written
  --   before that change still cannot carry the distinction.
  reason_code    text
                   check (reason_code in
                     ('no_longer_used', 'sold', 'transferred_out',
                      'duplicate', 'institution_closed', 'other')),
  -- ENUMERATED, NOT OPEN-ENDED (Sec, 057 review). `system:[a-z_]+` would let a
  -- NEW SYSTEM WRITER APPEAR SILENTLY — and the whole matched_on/decided removal
  -- rests on there being exactly one non-session writer. An open pattern admits a
  -- second without firing anything. Enumerated, a new system identity FAILS THIS
  -- CHECK and forces the review that would re-examine the column set.
  actor          text not null
                   check (
                     actor ~ '^user:[0-9a-f-]{36}$'
                     or actor in ('system:remediation')
                   ),
  -- NULLABLE BY DECISION, requiredness enforced per event type below (Sec flag,
  -- ADR-042 Amendment 1 A5). A closure takes its date from the DATA
  -- (new.closed_at); a REOPEN has no carrier — the reopen path is a bare
  -- `closed_at = null` UPDATE with nowhere to say WHEN. The rejected fix was to
  -- default it to current_date. That is a GUESSED DATE, permanent and
  -- unredactable, in the same function that already prohibits a guessed
  -- reason_code — and worse, a real same-day reopen and an unknown-date reopen
  -- would produce BYTE-IDENTICAL rows. Not lossy: INDISTINGUISHABLE, forever,
  -- because this table has no redaction path.
  --
  -- This is ADR-011 D4's third bullet (Lock 15 catch on Lock 9) INVERTED, which
  -- is the harder shape: Lock 9 lost insertion-time by OMISSION, so the gap was
  -- visible. Defaulting here would lose the distinction BY VALUE — both columns
  -- present, effective_date === created_at::date on every reopen row, and the
  -- orthogonality collapsed while nothing looks missing.
  -- AN OMISSION ANNOUNCES ITSELF; A COLLAPSE LOOKS LIKE DATA.
  effective_date date,
  created_at     timestamptz not null default now(),

  -- Requiredness is PER EVENT TYPE, so it is a CHECK and NOT a column-level
  -- NOT NULL — a global NOT NULL would fail for the types that do not need it.
  constraint account_event_reason_required
    check (event_type <> 'closed' or reason_code is not null),

  -- SAME SHAPE, SAME REASON, deliberately mirroring the constraint above rather
  -- than inventing a mechanism: the table already had this pattern for exactly
  -- this problem. A closure must carry its date; a reopen may leave it NULL,
  -- and NULL means "not recorded" rather than "today".
  constraint account_event_effective_date_required
    check (event_type <> 'closed' or effective_date is not null)
);

comment on table pfin.account_event is
  'Append-only audit of pfin.account open/closed transitions (ADR-042 Decision 5 + 5a; ADR-011 Decision 2 audit-class). The TRANSITION is audit-class; pfin.account is not and must not become so. Named for the general class, NOT closure_history: event_type widens by one-line ALTER (030 precedent) rather than by a second near-identical table — but WIDENING IS SEC-JOINT-REVIEW-MANDATORY, because the SD tier, the read posture and indefinite retention were all calibrated for closure events, and the tier rates what the CHECK admits, not what the table is named. NO free text anywhere: this table is immutable and retained indefinitely, so admission is the ONLY control — there is no redaction path for anyone, including the row''s tenant. Every column takes more than one value across the writers that exist (Sec''s criterion); matched_on/decided/provider_event_id/linked_source_id were DROPPED because the ratified model removed their only writer, and #17 is therefore never created (Decision-3 family stays 16 labeled / 13 DDL-realized). Writers: the user''s own close/reopen (session write under RLS — NOT a Decision 1 privileged-context surface, so clause (d) does not apply) and the one-time remediation as the migration role, which is RLS-exempt and is why #16 is load-bearing.';

comment on column pfin.account_event.effective_date is
  'WHEN THE TRANSITION TOOK EFFECT — deliberately SEPARATE from created_at (row-insertion time), per ADR-011 Decision 4''s third bullet (the Lock 15 catch on Lock 9: conflating event-date with insertion-time is the documented schema-orthogonality failure). A backdated closure has effective_date < created_at and that is CORRECT, not drift. NULLABLE, and NULL means NOT RECORDED — never "today": a reopen has no date carrier unless the caller sets pfin.effective_date, and defaulting to current_date would make a real same-day reopen BYTE-IDENTICAL to an unknown-date one, indistinguishable forever on a table with no redaction path. Requiredness is asymmetric and enforced by account_event_effective_date_required: a closure MUST carry a date (it comes from the data, new.closed_at), a reopen MAY be NULL. ⚠ QUERY HAZARD, MEASURED — AND IT IS A PROPERTY OF THE QUERY, NOT OF THE INDEX: Postgres DESC defaults to NULLS FIRST, so a naive `order by effective_date desc limit 1` returns a NULL-dated reopen AHEAD OF EVERY DATED EVENT — REGARDLESS OF HOW ANY INDEX IS DECLARED. Verified: with a closure dated 2026-01-15 and a NULL-dated reopen, the naive query returns the reopen and `desc nulls last` returns the closure. account_event_account_idx IS declared `desc nulls last`, but that only means the CORRECT query is served without a sort — IT DOES NOT MAKE THE NAIVE QUERY SAFE. Do not read the index declaration as the remedy. ANY latest-event lookup MUST use `nulls last` or filter explicitly. The nullability is deliberate and correct; this ordering consequence rides with it.';

comment on column pfin.account_event.actor is
  'Discriminated: `user:<uuid>` or `system:<source>`. NEVER a bare uid that silently means "system" when null — the discrimination is the point. Justified by the REMEDIATION path (the one non-session writer, running as the migration role), where users_id (tenant) and the acting identity genuinely diverge. Without that path this column would be redundant with users_id and should have been dropped with the others.';

alter table pfin.account_event enable row level security;

-- Owner-scoped read + insert. INSERT is needed because 058's gate trigger is
-- SECURITY INVOKER and therefore writes AS THE CALLING USER. No UPDATE/DELETE
-- policy and no grant: audit-class, and the triggers below fence it for every
-- role regardless of grant state.
-- ⚠ DELIBERATELY NOT `if not exists` — DO NOT ADD ONE, AND DO NOT "TIDY" THE
--   GUARDS IN THIS FILE FOR CONSISTENCY.
--   The table (`create table if not exists`, above) and both indexes ARE
--   guarded. So against a database already holding a stale pfin.account_event
--   from an earlier revision of 057, the table creation would silently no-op
--   and the database would keep `effective_date NOT NULL` with NO
--   account_event_effective_date_required — THE ENTIRE A′ FIX ABSENT, WITH
--   NOTHING FAILING. This unguarded CREATE POLICY is the ONLY statement that
--   catches that case. Making the guards consistent looks like a cleanup and
--   is the removal of the only protection.
--
--   ⚠ AND IT REPORTS THE WRONG SYMPTOM. If this fires as
--     `ERROR: policy "account_event_select" ... already exists`
--   the likely condition is NOT a policy problem — it is a stale
--   pfin.account_event from an earlier 057. CHECK THE TABLE'S effective_date
--   NULLABILITY FIRST. Undocumented, the protection is also a red herring that
--   sends the next person to the wrong file.
create policy account_event_select on pfin.account_event
  for select to authenticated
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- ⚠ THE `actor` CONJUNCT IS A SEC VETO FIX (F1, joint-review 2026-08-04). DO NOT
--   DROP IT AS REDUNDANT WITH THE actor CHECK — the CHECK constrains SHAPE, this
--   constrains VALUE-TO-IDENTITY, and only the second closes the forgery.
--   WHAT WAS OPEN: `pfin` is Data-API-exposed (config.toml) and this table grants
--   `insert` to authenticated, so a tenant could POST a row directly, bypassing
--   the writer entirely. #16 passes (the pair is genuinely matched — their own
--   account), the old WITH CHECK passed (users_id IS their uid), and the actor
--   CHECK passed because it admits 'system:remediation' UNCONDITIONALLY. A
--   forged system-attributed row then landed PERMANENTLY in an append-only table
--   with no redaction path for anyone, including its own tenant.
--   >> 058's longest passage argues this forgery is "unreachable rather than
--      merely discouraged". That argument is TRUE ABOUT THE TRIGGER and was
--      defeated by a route that never enters it. A fence's reachability argument
--      must be made over EVERY path to the table, not over the path it guards. <<
--   COMPATIBILITY, verified rather than assumed: the writer is SECURITY INVOKER
--   and emits exactly `'user:' || auth.uid()` on its auth.uid() branch; its GUC
--   branch is reachable only when auth.uid() IS NULL, which cannot occur under a
--   `to authenticated` policy; and the migration-role remediation writer is
--   RLS-exempt, so this conjunct never applies to it.
create policy account_event_insert on pfin.account_event
  for insert to authenticated
  with check (
    (users_id = auth.uid())
    and (actor = 'user:' || auth.uid()::text)
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

comment on policy account_event_insert on pfin.account_event is
  'INSERT WITH CHECK for authenticated (ADR-042; the actor conjunct added at Amendment 3 F1, Sec VETO fix 2026-08-04). THREE conjuncts, and each closes something the others do not. (1) users_id = auth.uid() — tenant binding. (2) actor = ''user:'' || auth.uid()::text — IDENTITY binding, and it is NOT redundant with the actor CHECK: the CHECK constrains the column''s SHAPE and admits ''system:remediation'' UNCONDITIONALLY, so before this conjunct any authenticated tenant could POST a system-attributed row for their own account directly over the Data API — #16 passes (the pair really is matched), the tenant conjunct passes (it really is their uid), and the row lands PERMANENTLY in an append-only table with no redaction path. The trigger''s auth.uid()-first precedence made the forgery unreachable THROUGH THE TRIGGER; this closes the route that never enters it. (3) the 025 aal2 step-up conjunct, inherited. Compatible with the writer by construction: it is SECURITY INVOKER and emits exactly this string on its auth.uid() branch, its GUC branch is unreachable when auth.uid() is non-null, and the migration-role remediation path is RLS-exempt so no policy applies to it.';

comment on policy account_event_select on pfin.account_event is
  'Direct-owner read (users_id = auth.uid()) AND the 025 aal2 step-up conjunct, INHERITED not re-argued — a closure history exposes account existence, names, closure dates and reasons, which is at least as sensitive as the account rows it describes. Character-identical conjunct to account_select (025:201) by construction.';

-- ACL-before-RLS (PR #106 gotcha): the role needs table-level GRANTs even with
-- RLS on. SELECT + INSERT only — never UPDATE or DELETE.
grant select, insert on pfin.account_event to authenticated;

-- RLS-predicate index + the per-account history read path.
create index if not exists account_event_uid_idx on pfin.account_event (users_id);
-- NULLS LAST IS NOT AN OPTIMIZATION — IT COMPLETES THE NULL-DATE FIX (Sec ruling).
--   Postgres DESC defaults to NULLS FIRST. Since effective_date became nullable,
--   a plain `desc` index sorts an UNKNOWN-DATE reopen AHEAD OF EVERY DATED EVENT,
--   which partially reintroduces the harm the nullability removed:
--     current_date  made an unknown date look like TODAY'S event;
--     NULLS FIRST   makes an unknown date sort as the LATEST event.
--   Both make ABSENCE READ AS RECENCY. Measured with rows (2026-01-10 closed),
--   (2026-02-20 closed), (NULL reopened): `order by effective_date desc limit 1`
--   returns the NULL row; `desc nulls last` returns 2026-02-20.
--
--   And telling consumers to write `nulls last` is NOT sufficient — measured on
--   20k rows, ANALYZEd: the correct query against a plain `desc` index acquires a
--   Sort node, while against `desc nulls last` it is an Index Only Scan. The
--   index declaration IS the choice of which ordering is intended.
--
--   INTENDED CONSUMER: latest-event-per-account lookups
--     (order by effective_date desc nulls last limit 1).
--   This index serves exactly ONE of the two orderings. Anyone adding an
--   `order by` on this table should find that written here rather than infer it.
create index if not exists account_event_account_idx
  on pfin.account_event (account_id, effective_date desc nulls last);

-- ----------------------------------------------------------------------------
-- Decision-3 canonical instance #16 — account_event.account_id -> pfin.account.
--   P1 matched-tenant, LOCAL ANCHOR: this row carries its own resolved users_id,
--   validated equal to the referenced account's users_id (the 012 shape, and the
--   #15 shape at 044 which this copies).
--   BEFORE INSERT ONLY — the table is immutable audit-class, so UPDATE/DELETE
--   are trigger-blocked below and an UPDATE fence would be dead code (019/044
--   precedent).
--   LOAD-BEARING, not decorative: the remediation writer runs as the migration
--   role and is RLS-EXEMPT, so it could write a mismatched (account_id, users_id)
--   pair that no policy would catch. This fence is the only thing that does.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_event_matched_account()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not exists (
    select 1 from pfin.account a
    where a.account_id = new.account_id
      and a.users_id = new.users_id
  ) then
    raise exception
      'cross-tenant account_event rejected: account_id % is not owned by users_id % (ADR-011 Decision 3 #16 matched-tenant fence)',
      new.account_id, new.users_id;
  end if;
  return new;
end;
$$;

comment on function pfin.fn_account_event_matched_account() is
  'BEFORE INSERT matched-tenant fence on pfin.account_event.account_id (ADR-011 Decision 3 CANONICAL INSTANCE #16; P1 local-anchor, copying the #15 shape at 044). The row carries its own resolved users_id; the referenced pfin.account row must share it. NULL-safe fail-closed (NOT EXISTS -> raise). SECURITY INVOKER + set search_path = '''' — NOT a DEFINER allowlist entry, allowlist stays 4. BEFORE INSERT only: the table is immutable audit-class so UPDATE/DELETE are trigger-blocked and an UPDATE fence would be dead. LOAD-BEARING for the one RLS-exempt writer — the migration-role remediation path could otherwise write a mismatched (account_id, users_id) pair that no policy would catch. ⚠ THIS FENCE BORROWS PART OF ITS SUFFICIENCY FROM RLS, AND THE DEPENDENCY IS ASYMMETRIC — stated here because the catalog comment is where the next author will be standing, and because ADR-042''s symmetric rule (every exemption names its dependency; every fence states what makes it necessary) needs a third clause: a fence must also state what makes it SUFFICIENT when that comes from elsewhere. It runs SECURITY INVOKER, so `not exists` is true both when the pair genuinely mismatches and when the referenced row is merely INVISIBLE under the caller''s RLS. The two forge directions are NOT equally protected. Forging (account_id = another tenant''s, users_id = MY OWN) still raises on DATA — no account row carries that pair regardless of who is looking — so it survives any widening of read visibility, and the tenant conjunct in account_event_insert is a second independent layer. Forging (account_id = another tenant''s, users_id = THEIRS) is the fragile direction: the pair genuinely matches in the data, so ONLY invisibility makes `not exists` true here, with the WITH CHECK tenant conjunct as the remaining layer. So if account_select ever widens (V2 sharing / the rd_access read path), this fence stops contributing on that direction and the policy carries it alone — a silent narrowing of defense-in-depth, with no DDL change in this file to mark it. Whoever widens account_select should re-derive this comment rather than re-read it. Composition note, and it SHARPENS this fence''s justification rather than weakening it: account_event_block_direct_insert sorts alphabetically BEFORE this trigger and therefore fires FIRST, so a direct POST — matched pair or not — is refused THERE and never reaches #16. What remains reaching #16 is (a) trigger-originated inserts, where the writer derives users_id from the account row itself and so is always matched, and (b) THE MIGRATION-ROLE REMEDIATION, which the direct-insert fence exempts by ownership and which is RLS-exempt. So #16''s live blast radius is now almost exactly the writer Decision 5a justified it by — the RLS-exempt one that could write a mismatched pair no policy would catch. ⚠ DO NOT read "#16 rarely fires" as "#16 is redundant": the two fences cover DISJOINT writers, and the one #16 covers is precisely the one the other must let through. The messages are deliberately distinct so a battery can assert which fired.';

create trigger account_event_matched_account
  before insert on pfin.account_event
  for each row execute function pfin.fn_account_event_matched_account();

-- ----------------------------------------------------------------------------
-- ORIGIN FENCE — only the trigger writes this table (ADR-042 Amendment 3 F2;
--   F/CTO ratified OPTION B, 2026-08-04). Sec finding: even with F1's identity
--   binding, a tenant could still POST *fabricated* `closed` / `reopened` rows
--   for their OWN accounts — correctly attributed, correctly tenanted, and
--   describing transitions that never happened. F1 closes WHO the row claims to
--   be; this closes WHETHER THE EVENT OCCURRED. Different questions.
--
--   WHY THIS EXISTS AT ALL — [ADR-011](DECISIONS.md#adr-011) Decision 9 already
--   ruled this exact shape on a structurally identical surface, and 057 inverted
--   it WITHOUT NAMING IT. D9, verbatim, on the reclass-history table:
--     >> "an INVOKER+grant path would let a user POST forged history rows —
--        defeating the tamper-evidence." <<
--   That is precisely what `grant insert … to authenticated` on an append-only
--   audit table does. The precedent was not argued against; it was not noticed.
--   ⚑ A ratified precedent inverted SILENTLY is worse than one overruled loudly:
--     an overruled precedent leaves an argument someone can check.
--
--   WHY B (origin fence, INVOKER) AND NOT A (DEFINER writer + no INSERT grant,
--   D9's own remedy): A is the stronger fence and costs the allowlist 4 -> 5,
--   putting the closure path inside the elevated set. B keeps every write
--   evaluating under the caller's RLS — so #16, the tenant conjunct and the aal2
--   conjunct all still bind — while removing the direct route. B is weaker in
--   exactly one respect, stated so nobody discovers it later: it authenticates
--   the CALL PATH, not the caller, so it rests on there being no other trigger
--   on pfin.account that inserts here. There is one writer; a second would need
--   a migration, therefore a review.
--
--   *** THE EXEMPTION IS ROLE-BASED AND MUST NEVER BECOME GUC-KEYED. ***
--     (Sec's ratify condition, and it is the load-bearing half.) A GUC-keyed
--     exemption — `current_setting('pfin.remediation')` or any cousin — would
--     REINTRODUCE F1'S ENTIRE CLASS one fence over: `set local` is available to
--     ANY session, so the exemption would be self-issuable and the fence would
--     check a claim the attacker writes. Ownership is not self-issuable.
--
--   THE EXEMPTION IS "YOU OWN THIS TABLE", NOT a hardcoded role name. The
--   migration role owns what it created, so the predicate names the property
--   rather than the identity and does not rot when the role is renamed or
--   differs between local / CI / production. `authenticated` and `service_role`
--   are not owners.
--
--   *** pg_trigger_depth() IS A DEPTH FENCE, NOT AN ORIGIN FENCE, AND THE
--       ARITHMETIC IS A MEASURED FACT — NOT SOMETHING TO REASON ABOUT. ***
--   MEASURED (live DB, rolled-back txn; the authenticated path reproduced with
--   `set local role authenticated`, which is exactly what PostgREST does —
--   authenticator connection + SET LOCAL ROLE — so nothing about the transport
--   adds nesting):
--     direct INSERT (incl. PostgREST)     -> this fence sees 1
--     INSERT from inside account_event_write -> this fence sees 2
--   Hence `< 2` refuses.
--   ⚠ THE NAIVE FORMS BOTH FAIL OPEN, AND THAT IS WHY THE NUMBERS ARE HERE:
--     `pg_trigger_depth() > 0` ADMITS EVERY WRITE THIS FENCE EXISTS TO REFUSE —
--     a direct insert presents 1, not 0, because THE FENCE IS ITSELF A TRIGGER.
--     `= 0` refuses nothing, for the same reason. Either way the legitimate path
--     keeps working and nothing looks wrong. >> A SILENTLY INERT FENCE IS WORSE
--     THAN NO FENCE, BECAUSE IT IS CLAIMED. << Re-measure before changing this
--     predicate; do not derive it.
--
--   ⚑ THE TRIGGER NAME IS LOAD-BEARING — IT IS ORDERING, NOT LABELLING.
--     Triggers on one event fire ALPHABETICALLY. `account_event_block_direct_
--     insert` sorts BEFORE `account_event_matched_account`, so a direct POST
--     meets THIS fence first rather than #16. That is deliberate: #16 is a
--     Decision-3 cross-tenant fence and should not be what a direct POST hits
--     first — it would report a tenant defect for what is really a wrong-origin
--     write. Renaming this trigger to sort after `m` would silently re-order
--     the diagnosis. >> DESIGNED RED, PRE-ANNOUNCED: `057`'s (D1c) and (D2a)
--     are authenticated-tier and will now raise THIS message instead of the #16
--     pattern. That red is this fence, not a regression in #16. (D2b)/(D2c) are
--     migration-role and exempt, so unaffected. The expectations get renamed,
--     NOT this trigger — ordering the DDL around a test's convenience is
--     backwards. <<
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_event_block_direct_insert()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- current_user, NEVER session_user. Under PostgREST current_user is
  -- `authenticated` (set via SET LOCAL ROLE) while session_user stays
  -- `authenticator` for EVERY request — so a session_user-keyed exemption would
  -- exempt the entire Data API in one stroke, which is the whole attack surface.
  if pg_catalog.pg_trigger_depth() < 2
     and current_user <> (
       select pg_catalog.pg_get_userbyid(c.relowner)
         from pg_catalog.pg_class c
         join pg_catalog.pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'pfin' and c.relname = 'account_event'
     )
  then
    raise exception
      'pfin.account_event rejects direct INSERT: rows are written ONLY by the account_event_write trigger on pfin.account (ADR-042 Amendment 3 F2). A state transition is RECORDED BY THE TRANSITION, never asserted by a caller — close or reopen the account and the row follows. The only exempt writer is the table OWNER (the one-time migration-role remediation), and that exemption is deliberately role-based: a GUC-keyed one would be self-issuable by any session.';
  end if;
  return new;
end;
$$;

comment on function pfin.fn_account_event_block_direct_insert() is
  'BEFORE INSERT origin fence on pfin.account_event (ADR-042 Amendment 3 F2; F/CTO-ratified option B, 2026-08-04). Admits ONLY trigger-originated rows plus the table owner. CLOSES A DIFFERENT HOLE FROM F1''s WITH CHECK conjunct and neither substitutes for the other: F1 binds WHO the row claims to be, this binds WHETHER THE EVENT OCCURRED — without it a tenant could POST fabricated but correctly-attributed closed/reopened rows for their own accounts. Exists because [ADR-011](DECISIONS.md#adr-011) Decision 9 already ruled this shape on the structurally identical reclass-history surface — "an INVOKER+grant path would let a user POST forged history rows, defeating the tamper-evidence" — and 057 inverted that precedent SILENTLY; a precedent inverted without being named is worse than one overruled, because an overruled one leaves a checkable argument. Option B (origin fence, INVOKER) over option A (DEFINER writer + no INSERT grant, D9''s own remedy): A is stronger and costs the DEFINER allowlist 4 -> 5, putting the closure path inside the elevated set; B keeps every write under the caller''s RLS so #16, the tenant conjunct and the 025 aal2 conjunct all still bind. B''s one weakness, stated rather than left to be discovered: it authenticates the CALL PATH, not the caller, so it rests on there being exactly one trigger on pfin.account that inserts here — a second would require a migration, therefore a review. ⚠ THE EXEMPTION IS ROLE-BASED AND MUST NEVER BECOME GUC-KEYED (Sec ratify condition): set local is available to ANY session, so a GUC-keyed exemption would be self-issuable and the fence would be checking a claim the attacker writes — F1''s exact class, one fence over. It is expressed as OWNERSHIP of pfin.account_event rather than a hardcoded role name, so it names the property instead of the identity and does not rot across local / CI / production. pg_trigger_depth() < 2 is MEASURED (direct INSERT sees 1; an INSERT from inside account_event_write sees 2) — NOT = 0 and NOT > 0, since this fence is itself a trigger and the depth is never 0 when it runs: > 0 would ADMIT EVERY WRITE THIS FENCE EXISTS TO REFUSE while the legitimate path kept working, and a silently inert fence is worse than none because it is claimed. Re-measure before changing the predicate; do not derive it. ⚠ IT KEYS ON current_user, NEVER session_user: under PostgREST current_user is `authenticated` (SET LOCAL ROLE) while session_user stays `authenticator` for every request, so a session_user-keyed exemption would exempt the entire Data API in one stroke. ⚠ service_role IS NOT EXEMPT, and that is DECIDED rather than incidental: the predicate keys on OWNERSHIP, so service_role is refused like any other non-owner. This is deliberately tighter than a `current_user <> ''authenticated''` phrasing, which would have exempted service_role as a SIDE EFFECT of how it was written. No service_role path writes account_event today; if one is ever needed it must be added explicitly, as a reviewed exemption rather than an inherited one. ⚠ THE FENCE CARRIES ITS OWN LIMIT: depth proves the insert happened inside SOME trigger, not inside fn_account_event_write. That is adequate ONLY because that is the sole trigger writer today, and it would ADMIT A SECOND ONE SILENTLY the moment one appeared — verbatim the argument 057 already makes for ENUMERATING actor rather than pattern-matching it ("an open pattern admits a second without firing anything"). Depth is a PROXY FOR ORIGIN. ADDING ANY SECOND TRIGGER THAT INSERTS INTO THIS TABLE IS SEC-JOINT-REVIEW-MANDATORY. The tighter alternative — a sentinel proving WHICH function — is the shape ADR-042 Amendment 1 A5 already rejected and is not reopened here. ⚠ TWO CONSOLIDATIONS TO REFUSE, both of which will read as cleanups later. (1) THIS DOES NOT MAKE #16 REDUNDANT: they cover DISJOINT writers — #16 exists for the migration-role remediation, which is precisely the writer this fence must EXEMPT — so two BEFORE INSERT triggers on one small table look like duplication and neither covers the other''s case. (2) THIS DOES NOT MAKE F1''s account_event_insert actor conjunct REDUNDANT: a policy survives ALTER TABLE ... DISABLE TRIGGER and session_replication_role = replica; a trigger does not. ADR-011 Decision 4 commits to fencing at MULTIPLE layers simultaneously, and "the new fence covers it" is exactly the argument that would reopen F1 as a cleanup six months out. SECURITY INVOKER; DEFINER allowlist stays 4.';

-- ⚑ NAME SORTS BEFORE `account_event_matched_account` ON PURPOSE — triggers on
--   one event fire alphabetically, and this fence must be what a direct POST
--   meets FIRST. See the section header for the designed (D1c)/(D2a) red.
create trigger account_event_block_direct_insert
  before insert on pfin.account_event
  for each row execute function pfin.fn_account_event_block_direct_insert();

-- ----------------------------------------------------------------------------
-- Immutability, Lock 10 mod #8 CROSS-TIER (the 004 / 054 pattern reproduced).
--   Blocks UPDATE + DELETE for ALL roles including service_role — which bypasses
--   RLS but NOT triggers — and TRUNCATE at statement level, because row-level
--   triggers do NOT fire on TRUNCATE. Messages are DELIBERATELY DISTINCT so a
--   battery can assert WHICH fence fired (the 054 distinct-message precedent);
--   an assertion that cannot identify the fence proves less than it appears to.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_event_block_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.account_event is immutable (append-only audit-class; ADR-011 Decision 2 / ADR-042 Decision 5). % blocked — a state transition is a historical fact and is never revised; record a new event instead.', tg_op;
end;
$$;

comment on function pfin.fn_account_event_block_mutation() is
  'BEFORE UPDATE OR DELETE immutability fence on pfin.account_event (ADR-011 Decision 2 / Lock 10 mod #8). SECURITY INVOKER (touches nothing; not a DEFINER allowlist entry). raise, NOT return null — return null would silently no-op the row and read as success. Blocks UPDATE + DELETE for ALL roles incl. service_role (bypasses RLS, not triggers) — the privileged-context immutability fence RLS-default-deny alone cannot provide. Message distinct from the TRUNCATE fence for test-matching.';

create trigger account_event_block_mutation
  before update or delete on pfin.account_event
  for each row execute function pfin.fn_account_event_block_mutation();

create or replace function pfin.fn_account_event_block_truncate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.account_event is immutable (append-only audit-class; ADR-011 Decision 2 / ADR-042 Decision 5). TRUNCATE blocked — the closure-history retention path is not a wipe surface.';
end;
$$;

comment on function pfin.fn_account_event_block_truncate() is
  'BEFORE TRUNCATE (statement-level) immutability fence on pfin.account_event. Row-level triggers do NOT fire on TRUNCATE, so this statement-level fence plus the absent TRUNCATE grant close the audit-retention-wipe path for ALL roles regardless of grant state. SECURITY INVOKER. Message distinct from the row-level fence for test-matching.';

create trigger account_event_block_truncate
  before truncate on pfin.account_event
  for each statement execute function pfin.fn_account_event_block_truncate();
