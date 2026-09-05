-- =====================================================================
-- Per-Wave battery — pfin.owner_identification: FIFTH and LAST Lock-14
--   per-domain settings table (ADR-011 Decision 18, as amended 2026-08-16 —
--   the family is FIVE, not four). Single-scalar owner-header settings row:
--   one nullable TEXT column (owner_id_header_text), UNIQUE(users_id), full
--   authenticated CRUD RLS + the 025 aal2 step-up backstop (Sec F-9) on
--   every policy, NOT a Decision-3 instance (no label), NO JSONB (Lock-14
--   forward-compat fence). Canonical test label: RT-12 (SECURITY §4.1 axis
--   iv, Sec D-3) (SELF-352 AC1-AC10; V1.5; V1-SHIP-BLOCK; JOINT-REVIEW-
--   MANDATORY per Lock-14 membership, Sec R-6).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/106_owner_identification.sql
--   (feature/self-352 @ e8867f4, blob md5 91a67bfb4da3e08eb8b0092d605269f9 —
--   verified against the committed file, not the relay, before drafting this).
--   - pfin.owner_identification (id, users_id NOT NULL DEFAULT auth.uid() ->
--       auth.users ON DELETE CASCADE, owner_id_header_text text NULL,
--       created/updated_at, unique(users_id)). Six constraints total: PK, FK,
--       UNIQUE(users_id), and THREE NAMED CHECKs (all `is null or (...)`,
--       so NULL always passes):
--         owner_identification_header_len_check       — length(...) <= 120,
--           CODE POINTS not bytes (multibyte leg below).
--         owner_identification_header_not_blank_check — `~ '[^[:space:]]'`,
--           NOT IN THE SELF-352 AC — Architect addition (migration header),
--           refuses '' and whitespace-only so blank cannot become a THIRD
--           unset state (row-absent and NULL are the only two). Team-lead is
--           keeping it by default-and-notify; F/CTO may strike it at PR
--           review — its legs are in their OWN labelled BLOCK BLANK below so
--           they can be removed cleanly if so.
--         owner_identification_header_single_line_check -- `!~ '[...]'`,
--           the class written as the Unicode ARE regex escapes for LF, VT,
--           FF, CR, NEL, LINE SEPARATOR, PARAGRAPH SEPARATOR, the FULL Unicode
--           line-boundary class (LF/VT/FF/CR/NEL/LS/PS), not LF alone — the
--           migration's own header calls out CR as the trap a naive LF-only
--           fence would miss.
--       ⚠ NAME-ORDER TRAP (migration's own header): a value violating MORE
--       THAN ONE check is reported in constraint-NAME order (len < not_blank <
--       single_line, alphabetically), NOT authoring order. Every probe below
--       is constructed to violate its OWN targeted check ALONE — verified per
--       leg in this file's own header comments, not assumed.
--   - RLS direct-owner (users_id = auth.uid()) ANDed with the ADR-029/025
--       aal2 backstop clause on ALL FOUR policies (select/insert/update/
--       delete), copied byte-faithfully from 025 (COALESCE null-safe,
--       INLINED not a helper function — 025's own ratified posture, since
--       `set search_path = ''` disables SQL-function inlining, which would
--       make a helper evaluate per row); full authenticated CRUD; anon
--       zero-grant; service_role UNGRANTED.
--   - trigger owner_identification_set_updated_at (reuses the 001 DEFINER
--       allowlist entry, fn_refresh_updated_at). This migration authors NO
--       function of its own kind, and the one BEFORE trigger it attaches
--       (updated_at refresh, BEFORE UPDATE) raises nothing, so no trigger
--       SHADOWS this table's WITH CHECK on any verb (Decision 3: +0, no
--       label — the sole reference column is users_id itself, the tenant
--       anchor).
--   - DELETE POLICY carries its OWN tenant+aal2 clause and is never trimmed
--       (SECURITY §4.6 Lock-14 settings-family DELETE-policy fence, named
--       for this table). The migration's own header states the exact SD-22
--       trap this file must dodge: "a cross-tenant DELETE assertion written
--       WITH a column filter is satisfied by EITHER policy" (Postgres
--       consults SELECT during a DELETE only when the statement reads or
--       filters by a column) — QA measured this at 074/(M12), 2026-08-20.
--       BLOCK DEL below runs the cross-tenant probe as an UNQUALIFIED
--       `delete from pfin.owner_identification;` (no WHERE, no column
--       reference) so the SELECT policy is never consulted, per the 090
--       AC12 instrument, with the complementary corrupt-the-control pair.
--   - UNSET has exactly TWO representations that must read identically:
--       row-absent, and a NULL column. `''` is refused (the not_blank
--       CHECK), not a third state. BLOCK NUL asserts NULL is a genuine,
--       accepted write (not merely "not yet tested").
-- Prereqs exercised (already on main / applied by Backend on the reset
--   stack): 001 (pfin schema + fn_refresh_updated_at), 024
--   (pfin.user_settings.mfa_policy — the aal2 backstop's own subquery
--   target; NOT this table, so no recursion risk here), 025 (the aal2
--   backstop clause shape this migration reuses byte-faithfully), auth.users.
-- Reuses the 090/101 idiom: \ir verbs, ALL-LOWERCASE \gset literals,
--   MESSAGE-precise throws_like / SQLSTATE-precise throws_ok, role restored
--   to postgres between blocks (PR #121 root-cause), savepoint/rollback
--   around every exception-raising probe and every ALTER POLICY corruption.
--
-- ┌─ AC10 — the aal2 leg is a SEPARATE leg from the cross-tenant leg ───────────┐
-- │ BLOCK M (aal2 backstop, tenant D/totp) is entirely independent of BLOCK W/  │
-- │ BLOCK DEL (cross-tenant, tenant B intruding on tenant A). Neither block's   │
-- │ fixture nor assertions depend on the other; D builds its OWN row via       │
-- │ authenticated INSERT (not a service_role pre-seed) so the INSERT leg of    │
-- │ the backstop is genuinely exercised, per the 090/(M1-M2) precedent.        │
-- └───────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ AC12-SHAPE — the DELETE-policy leg isolates that policy's OWN clause ──────┐
-- │ (DEL1) REAL WORLD: B (owns no row) issues an unqualified                    │
-- │ `delete from pfin.owner_identification;` -> owner_identification_delete's  │
-- │ OWN USING clause is the SOLE gate (no WHERE for SELECT's policy to ever be │
-- │ consulted through) -> A's real row SURVIVES. (DEL2)/(DEL3) are the         │
-- │ complementary corrupt-the-control pair: break DELETE's clause alone (open) │
-- │ and SELECT's clause alone (open), independently, to show WHICH corruption  │
-- │ moves the result — per §8's "when a control fails closed, corrupt it — do  │
-- │ not delete it" rule (a dropped policy default-denies and would pass on the │
-- │ nothing).                                                                   │
-- └───────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ MULTIBYTE LENGTH — code points, not bytes (Architect's own header note) ──┐
-- │ length() counts CODE POINTS. (LEN3)/(LEN4) prove the 120-bound applies     │
-- │ identically to a 120/121 EMOJI-code-point string (480/484 bytes) as to a   │
-- │ 120/121 ASCII string — a byte-counting rewrite of the CHECK would flip     │
-- │ (LEN3) from lives_ok to throws_ok, going RED where a code-point-counting   │
-- │ CHECK stays GREEN.                                                         │
-- └───────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ BLOCK X — the SELECT fence's own inversion, encoded permanently ───────────┐
-- │ Structural presence (BLOCK S) and behavioural fail-closed (BLOCK R) are     │
-- │ each individually provable-green-vacuously if the OTHER half regressed.    │
-- │ (X1) corrupts owner_identification_select open (`using (true)`) and        │
-- │ asserts the cross-tenant read STOPS being empty (B now sees A's row) — the │
-- │ fence's own control, kept in the suite, not just run once by hand at       │
-- │ authoring time.                                                            │
-- └───────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 catalogued ledger — read ADR-011 Decision 4 live,
--   never from here; this migration adds ZERO catalogued §10 instances.
--   ⚠ RT-12 is NOT one of them: the §10 CATALOGUED set and the Sec-owned RT
--   CATALOG are DIFFERENT REGISTERS and must never be reconciled. RT-12
--   (Sec D-3, AC8) is this surface's canonical test label and already exists
--   in the RT catalog — this file creates no RT entry and moves no ledger.
--   Decision-3 family: +0, NO LABEL — the sole reference column is the
--   direct users_id owner anchor; no other FK-shaped column exists on this
--   table (migration's own header confirms).
--
-- ⚠ SCOPE NOTE: RT-12 also names an adversarial-input battery at the WRITE
--   ENDPOINT (XSS / SQLi / oversize / Unicode control / RTL override /
--   homoglyph) plus render-time no-executable-content — the migration's own
--   header states its CHECKs are "necessary rather than sufficient" for
--   RT-12 and does not discharge it. That endpoint-level battery belongs to
--   the API write-path surface (SELF-359 / P7), not this DB-layer RLS
--   battery; not attempted here.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from
--   _rls.tenant_a()/_rls.tenant_b(), plus a raw literal for the totp tenant
--   (D, suffixed '06' for migration 106 to keep this file's fixture
--   diffable against other batteries' fixed literals in the same cluster —
--   each file's txn rolls back independently so collision is not actually
--   live). NO PII / NO real account numbers / NO prod data. All inside one
--   rolled-back transaction.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to
--   authenticated, so NO `_rls.*` call runs under authenticated. Tenant
--   UUIDs are resolved to psql LITERALS via \gset at role=postgres; every
--   _rls.set_tenant(_aal) call happens at role=postgres and each block
--   restores role=postgres before the next. \gset var names are
--   ALL-LOWERCASE. `_rls.expect_cross_tenant_write_blocked` is deliberately
--   NOT used (it does not self-restore role on return — 090/101 precedent
--   is the manual set_tenant/savepoint/throws_ok/rollback/set_config shape
--   used throughout this file).
--
-- ⟦WIRE-VALIDATE⟧ authored against 106's committed contract (e8867f4);
--   verified against a hand-built scratch DB — `createdb` + auth/extensions/
--   vault schemas dumped from the live local Supabase container, `pgtap`
--   installed in `public` (not `extensions`), migrations 001->106 applied
--   SEQUENTIALLY in order as `postgres` (never a TEMPLATE clone — that drops
--   per-database `ALTER DATABASE ... SET` rows silently), verified via
--   `pg_prove` (never bare `psql` — a plan under-run exits 0 there).
--   `supabase db reset` is mechanically banned and was not used; F/CTO's
--   local dev DB was not touched.
--   plan(47): 5 structural (S1-S5) + 2 structural aal2 split, EACH now also
--   pinning BOTH 'totp' and 'passkey' present in the expression text
--   (S6a-S6b) + 4 grants (GR1-GR4) + 1 no-JSONB fence (NEG1) + 1
--   fresh-insert round-trip (INS1) + 1 unique-per-user (UQ1) + 4
--   length/multibyte (LEN1-LEN4) + 3 not-blank (BLANK1-BLANK2, BLANKC) + 4
--   single-line (CATLINE1, LINE1-LINE3) + 2 NULL-is-unset (NUL1-NUL2) + 3
--   UPSERT-in-place (UPS1-UPS3) + 2 two-tenant read isolation (R1-R2) + 3
--   cross-tenant write blocked (W1-W2 forge/no-op, W3 the Lock 14 mod #1
--   UPDATE tenant-move forge) + 3 DELETE-policy isolation +
--   corrupt-the-control pair (DEL1-DEL3) + 1 corrupt-SELECT exact-value leak
--   (X1) + 8 aal2 backstop, all four verbs (M1-M8) = 47.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(47);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
\set td '00000000-0000-0000-0000-000000000d06'

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed seed path).
--  - Three tenants in auth.users: A/B (plain 'none' mfa_policy — the
--    two-tenant cross-read/write/delete baseline), D (totp — the aal2
--    backstop subject; builds its OWN row via authenticated INSERT in BLOCK
--    M so the INSERT leg of the backstop is genuinely exercised).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb'), (:'td');

insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'), (:'tb', 'none'), (:'td', 'totp');

-- =====================================================================
-- BLOCK S (postgres — pg_policy catalog) — STRUCTURAL tenant presence,
--   each of the four verbs' policies, plus the aal2 backstop split by
--   clause half (090/101's S6a/b masking lesson).
-- =====================================================================
select ok(
  (select pg_get_expr(polqual, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy
    where polrelid = 'pfin.owner_identification'::regclass and polname = 'owner_identification_select'),
  '(S1) STRUCTURAL: owner_identification_select carries a USING expression referencing users_id = auth.uid() (pg_policy catalog)'
);
select ok(
  (select pg_get_expr(polwithcheck, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy
    where polrelid = 'pfin.owner_identification'::regclass and polname = 'owner_identification_insert'),
  '(S2) STRUCTURAL: owner_identification_insert carries a WITH CHECK expression referencing users_id = auth.uid() (pg_policy catalog)'
);
select ok(
  (select pg_get_expr(polqual, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy
    where polrelid = 'pfin.owner_identification'::regclass and polname = 'owner_identification_update'),
  '(S3) STRUCTURAL: owner_identification_update carries a USING expression referencing users_id = auth.uid() (pg_policy catalog)'
);
select ok(
  (select pg_get_expr(polwithcheck, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy
    where polrelid = 'pfin.owner_identification'::regclass and polname = 'owner_identification_update'),
  '(S4) STRUCTURAL: owner_identification_update carries a WITH CHECK expression referencing users_id = auth.uid() (pg_policy catalog)'
);
select ok(
  (select pg_get_expr(polqual, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy
    where polrelid = 'pfin.owner_identification'::regclass and polname = 'owner_identification_delete'),
  '(S5) STRUCTURAL: owner_identification_delete carries its OWN USING expression referencing users_id = auth.uid() (pg_policy catalog) — never trimmed on the reasoning that SELECT already covers it (SECURITY §4.6)'
);

select is(
  (select count(*)::bigint from pg_policy
    where polrelid = 'pfin.owner_identification'::regclass
      and coalesce(pg_get_expr(polqual, polrelid), '') ilike '%aal2%'
      and coalesce(pg_get_expr(polqual, polrelid), '') ilike '%totp%'
      and coalesce(pg_get_expr(polqual, polrelid), '') ilike '%passkey%'),
  3::bigint,
  '(S6a) STRUCTURAL — USING half: select/update/delete all carry the ADR-029/025 aal2 backstop (Sec F-9) in polqual, WITH BOTH ''totp'' and ''passkey'' present in the pinned mfa_policy IN-list — RED if any USING-side aal2 clause were dropped, OR if a regression narrowed the IN-list to ''totp'' alone (bare ''%aal2%'' alone would still pass that narrowing; this does not)'
);
select is(
  (select count(*)::bigint from pg_policy
    where polrelid = 'pfin.owner_identification'::regclass
      and coalesce(pg_get_expr(polwithcheck, polrelid), '') ilike '%aal2%'
      and coalesce(pg_get_expr(polwithcheck, polrelid), '') ilike '%totp%'
      and coalesce(pg_get_expr(polwithcheck, polrelid), '') ilike '%passkey%'),
  2::bigint,
  '(S6b) STRUCTURAL — WITH CHECK half: insert/update both carry the ADR-029/025 aal2 backstop in polwithcheck, WITH BOTH ''totp'' and ''passkey'' present in the pinned mfa_policy IN-list — RED if owner_identification_update''s WITH CHECK lost its aal2 clause while USING kept it, OR if a regression narrowed the IN-list to ''totp'' alone'
);

-- =====================================================================
-- BLOCK GR (postgres — grants) — anon/service_role zero-grant,
--   authenticated full CRUD and nothing wider, PLUS one behavioral proof.
-- =====================================================================
select ok(
  not has_table_privilege('anon', 'pfin.owner_identification', 'SELECT')
  and not has_table_privilege('anon', 'pfin.owner_identification', 'INSERT')
  and not has_table_privilege('anon', 'pfin.owner_identification', 'UPDATE')
  and not has_table_privilege('anon', 'pfin.owner_identification', 'DELETE'),
  '(GR1) anon holds ZERO table-level privileges, all four verbs (pg_catalog has_table_privilege)'
);
select ok(
  not has_table_privilege('service_role', 'pfin.owner_identification', 'SELECT')
  and not has_table_privilege('service_role', 'pfin.owner_identification', 'INSERT')
  and not has_table_privilege('service_role', 'pfin.owner_identification', 'UPDATE')
  and not has_table_privilege('service_role', 'pfin.owner_identification', 'DELETE'),
  '(GR2) service_role holds ZERO table-level privileges, all four verbs — 008 establishes no default privileges, this records rather than effects that'
);
select ok(
  has_table_privilege('authenticated', 'pfin.owner_identification', 'SELECT')
  and has_table_privilege('authenticated', 'pfin.owner_identification', 'INSERT')
  and has_table_privilege('authenticated', 'pfin.owner_identification', 'UPDATE')
  and has_table_privilege('authenticated', 'pfin.owner_identification', 'DELETE')
  and not has_table_privilege('authenticated', 'pfin.owner_identification', 'TRUNCATE')
  and not has_table_privilege('authenticated', 'pfin.owner_identification', 'REFERENCES'),
  '(GR3) authenticated holds EXACTLY the four CRUD verbs — all present, TRUNCATE/REFERENCES absent (grant statement names select/insert/update/delete only)'
);
select set_config('role', 'anon', true);
select throws_ok(
  'select count(*) from pfin.owner_identification',
  '42501', null,
  '(GR4) BEHAVIORAL: anon holds no USAGE on schema pfin -> SELECT is denied at the ACL layer (42501), before RLS is ever consulted'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK NEG (postgres — pg_attribute) — Lock-14 forward-compat fence: NO
--   JSONB column exists on this table.
-- =====================================================================
select is(
  (select count(*)::bigint from pg_attribute a
     join pg_type t on t.oid = a.atttypid
    where a.attrelid = 'pfin.owner_identification'::regclass
      and not a.attisdropped
      and t.typname in ('jsonb', '_jsonb')),
  0::bigint,
  '(NEG1) Lock-14 forward-compat fence: pfin.owner_identification carries ZERO jsonb columns'
);

-- =====================================================================
-- BLOCK 1 (authenticated A) — seed A's real committed row (fresh INSERT,
--   row was absent). INS1 proves the round-trip.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.owner_identification (owner_id_header_text) values ('Mosko Household');
select set_config('role', 'postgres', true);

select is(
  (select owner_id_header_text from pfin.owner_identification where users_id = :'ta'),
  'Mosko Household',
  '(INS1) fresh INSERT (row was ABSENT for A): owner_id_header_text round-trips as given'
);

-- =====================================================================
-- BLOCK UQ (authenticated A) — unique(users_id): a second row for the
--   SAME tenant is refused (23505), independent of column value.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
savepoint sp_uq1;
select throws_ok(
  $$ insert into pfin.owner_identification (owner_id_header_text) values ('Second Row Attempt') $$,
  '23505', null,
  '(UQ1) unique(users_id): A''s second INSERT (users_id defaults to auth.uid()=A again) is refused (23505 unique_violation) — one row per user by construction'
);
rollback to savepoint sp_uq1;
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK LEN (authenticated A) — owner_identification_header_len_check:
--   length() counts CODE POINTS, not bytes (LEN3/LEN4 prove this on an
--   emoji string). Each probe is single-line and non-blank, so it violates
--   ONLY this check, per the migration's own name-order warning.
-- =====================================================================
savepoint sp_len1;
select throws_like(
  format($$ update pfin.owner_identification set owner_id_header_text = %L where users_id = auth.uid() $$, repeat('x', 121)),
  '%owner_identification_header_len_check%',
  '(LEN1) a 121-ASCII-character owner_id_header_text is REJECTED BY NAME by owner_identification_header_len_check — one past the 120 bound'
);
rollback to savepoint sp_len1;

savepoint sp_len2;
select lives_ok(
  format($$ update pfin.owner_identification set owner_id_header_text = %L where users_id = auth.uid() $$, repeat('y', 120)),
  '(LEN2) CONTROL: a 120-ASCII-character owner_id_header_text (the bound, exactly) is ACCEPTED'
);
rollback to savepoint sp_len2;

-- (LEN3) 120 EMOJI code points (480 bytes, U+1F600 x120) -> ACCEPTED —
--        length() counts code points, so this is the SAME bound as LEN2,
--        not a stricter one for multibyte text.
savepoint sp_len3;
select lives_ok(
  format($$ update pfin.owner_identification set owner_id_header_text = %L where users_id = auth.uid() $$, repeat(E'\U0001F600', 120)),
  '(LEN3) MULTIBYTE: a 120-CODE-POINT emoji string (480 bytes) is ACCEPTED — length() counts code points, not bytes; a byte-counting CHECK would reject this at 480 > 120'
);
rollback to savepoint sp_len3;

-- (LEN4) 121 EMOJI code points -> REJECTED BY NAME — the SAME bound applies
--        per-code-point to multibyte text, proving LEN1/LEN2's bound is not
--        an ASCII-only artifact.
savepoint sp_len4;
select throws_like(
  format($$ update pfin.owner_identification set owner_id_header_text = %L where users_id = auth.uid() $$, repeat(E'\U0001F600', 121)),
  '%owner_identification_header_len_check%',
  '(LEN4) MULTIBYTE: a 121-CODE-POINT emoji string is REJECTED BY NAME by owner_identification_header_len_check — the 120 bound is code-point-exact, not byte-exact, on multibyte text too'
);
rollback to savepoint sp_len4;

-- =====================================================================
-- BLOCK BLANK (authenticated A) — owner_identification_header_not_blank_
--   check. ⚠ NOT IN THE SELF-352 AC (Architect addition, migration header
--   flags it explicitly) — kept by team-lead default-and-notify pending
--   F/CTO PR-review disposition. Isolated in its OWN block so it can be
--   removed cleanly without touching any other leg if F/CTO strikes it.
-- =====================================================================
savepoint sp_blank1;
select throws_like(
  format($$ update pfin.owner_identification set owner_id_header_text = %L where users_id = auth.uid() $$, ''),
  '%owner_identification_header_not_blank_check%',
  '(BLANK1) an EMPTY STRING owner_id_header_text is REJECTED BY NAME by owner_identification_header_not_blank_check — blank cannot become a third unset state alongside row-absent and NULL'
);
rollback to savepoint sp_blank1;

savepoint sp_blank2;
select throws_like(
  format($$ update pfin.owner_identification set owner_id_header_text = %L where users_id = auth.uid() $$, '   '),
  '%owner_identification_header_not_blank_check%',
  '(BLANK2) a SPACES-ONLY (three ASCII spaces) owner_id_header_text is REJECTED BY NAME — length() alone would pass a length-3 value; the not-blank conjunct (`~ ''[^[:space:]]''`) catches an all-whitespace value with no non-whitespace character present'
);
rollback to savepoint sp_blank2;

savepoint sp_blankc;
select lives_ok(
  format($$ update pfin.owner_identification set owner_id_header_text = %L where users_id = auth.uid() $$, 'x'),
  '(BLANKC) CONTROL: a single non-whitespace character (''x'') is ACCEPTED — proves (BLANK1)/(BLANK2) are non-whitespace-content-driven, not a blanket rejection of short values'
);
rollback to savepoint sp_blankc;
select set_config('role', 'postgres', true);

-- BLOCK LINE (authenticated A) -- owner_identification_header_single_line_
--   check: the FULL Unicode line-boundary class (LF/VT/FF/CR/NEL/LS/PS),
--   not LF alone. CATLINE1 is a STRUCTURAL pin on the constraint's own
--   definition (catches a regression that silently drops one codepoint
--   from the class without needing one behavioral leg per codepoint);
--   LINE1/LINE2 are behavioral, including CR specifically (the migration's
--   own header names CR as the trap an LF-only fence would miss).
-- =====================================================================
-- The migration's CHECK is a PLAIN-quoted string carrying regex-level
-- Unicode escapes (Postgres ARE regex engine interprets them AT MATCH
-- TIME, not at string-literal-parse time, since the source uses a plain
-- string not an E'' string), so pg_get_constraintdef's returned text
-- carries the LITERAL ASCII ESCAPE SEQUENCE for each codepoint (backslash,
-- lowercase u, four hex digits), never a raw control character. This leg
-- builds that literal ASCII substring at runtime via chr(92) (backslash)
-- concatenation, so this FILE never carries the escape notation itself
-- (which risks silent reinterpretation by editors/tools) or a raw control
-- character.
select ok(
  (select pg_get_constraintdef(oid) ilike '%' || chr(92) || 'u000A%'
    and pg_get_constraintdef(oid) ilike '%' || chr(92) || 'u000B%'
    and pg_get_constraintdef(oid) ilike '%' || chr(92) || 'u000C%'
    and pg_get_constraintdef(oid) ilike '%' || chr(92) || 'u000D%'
    and pg_get_constraintdef(oid) ilike '%' || chr(92) || 'u0085%'
    and pg_get_constraintdef(oid) ilike '%' || chr(92) || 'u2028%'
    and pg_get_constraintdef(oid) ilike '%' || chr(92) || 'u2029%'
     from pg_constraint
    where conname = 'owner_identification_header_single_line_check'),
  '(CATLINE1) STRUCTURAL: owner_identification_header_single_line_check''s own definition names ALL SEVEN Unicode line-boundary codepoints (LF/VT/FF/CR/NEL/LINE-SEP/PARA-SEP), by their literal backslash-u regex-escape text -- RED if a future edit silently narrowed the class to LF alone'
);

savepoint sp_line1;
select throws_like(
  format($$ update pfin.owner_identification set owner_id_header_text = %L where users_id = auth.uid() $$, E'Line One\nLine Two'),
  '%owner_identification_header_single_line_check%',
  '(LINE1) an owner_id_header_text carrying an embedded LF is REJECTED BY NAME -- non-blank, well within the length bound, so this is NOT the len or not-blank conjunct firing'
);
rollback to savepoint sp_line1;

savepoint sp_line2;
select throws_like(
  format($$ update pfin.owner_identification set owner_id_header_text = %L where users_id = auth.uid() $$, E'Line One\rLine Two'),
  '%owner_identification_header_single_line_check%',
  '(LINE2) an owner_id_header_text carrying a BARE CR is REJECTED BY NAME -- the migration''s own header names this as the trap an LF-only fence would miss; this proves the class covers CR too, not just LF'
);
rollback to savepoint sp_line2;

savepoint sp_line3;
select lives_ok(
  format($$ update pfin.owner_identification set owner_id_header_text = %L where users_id = auth.uid() $$, 'Line One Line Two'),
  '(LINE3) CONTROL: the SAME content as (LINE1)/(LINE2) with the line-boundary character replaced by a plain space is ACCEPTED -- proves those legs are driven by the embedded line-boundary character specifically, not by content or length'
);
rollback to savepoint sp_line3;
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK NUL (authenticated A) — PRD §2.6.4 ψ-1 UNSET SEMANTICS: NULL is a
--   genuine, ACCEPTED write (one of the two reachable unset representations,
--   the other being row-absent, per BLOCK UQ/INS1). Runs LAST among the
--   savepoint-wrapped probes and is itself rolled back so A's row still
--   carries 'Mosko Household' entering BLOCK UPS below.
-- =====================================================================
savepoint sp_nul1;
select lives_ok(
  $$ update pfin.owner_identification set owner_id_header_text = null where users_id = auth.uid() $$,
  '(NUL1) UPDATE to NULL is ACCEPTED — all three CHECKs are `is null or (...)`, so NULL always passes; this is unset-via-NULL, distinct from row-absent (BLOCK UQ) and refused from blank (BLOCK BLANK)'
);
select ok(
  (select owner_id_header_text is null from pfin.owner_identification where users_id = auth.uid()),
  '(NUL2) after the NULL write, owner_id_header_text reads back NULL — the row SURVIVES (still exists, per UNSET SEMANTICS: a DELETE and a NULL-write reach the same state, but this leg proves the NULL-write route specifically, without touching the row count)'
);
rollback to savepoint sp_nul1;
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK UPS (AC4) — UPSERT-in-place updates the existing row (no second
--   row) and updated_at advances. `now()` is transaction-constant across
--   this file, so a wall-clock compare is a false negative — force a
--   sentinel first (privileged, bypassing the trigger), per 101/(UPD1).
--   A's row is still 'Mosko Household' entering this block (every probe
--   since BLOCK 1 rolled back to a savepoint).
-- =====================================================================
update pfin.owner_identification set updated_at = '2000-01-01'::timestamptz where users_id = :'ta';
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.owner_identification (owner_id_header_text) values ('Mosko Household — Primary')
  on conflict (users_id) do update set owner_id_header_text = excluded.owner_id_header_text;
select set_config('role', 'postgres', true);

select is(
  (select count(*) from pfin.owner_identification where users_id = :'ta')::bigint,
  1::bigint,
  '(UPS1) UPSERT-in-place: the row SURVIVES as exactly 1 row — no second row created for the same tenant'
);
select is(
  (select owner_id_header_text from pfin.owner_identification where users_id = :'ta'),
  'Mosko Household — Primary',
  '(UPS2) UPSERT-in-place: owner_id_header_text is now the NEW value'
);
select ok(
  (select updated_at > '2000-01-01'::timestamptz from pfin.owner_identification where users_id = :'ta'),
  '(UPS3) UPSERT-in-place: updated_at was forced to a 2000-01-01 sentinel (privileged, bypassing the trigger), then A''s authenticated UPSERT reset it away from that sentinel — fn_refresh_updated_at fires on the UPDATE arm of the UPSERT'
);

-- =====================================================================
-- BLOCK R (postgres — _rls verbs) — two-tenant read isolation. A owns
--   exactly 1 row at this point ('Mosko Household — Primary', per BLOCK UPS).
-- =====================================================================
-- (R1) owner-reads-own: A sees exactly its 1 row (guards an over-restrictive policy).
select _rls.expect_owner_can_read('pfin.owner_identification'::regclass, :'ta'::uuid, 1::bigint);

-- (R2) cross-tenant read fails closed: B sees 0 of A's rows.
select _rls.expect_cross_tenant_read_empty('pfin.owner_identification'::regclass, :'ta'::uuid, :'tb'::uuid);

-- =====================================================================
-- BLOCK W (authenticated B) — cross-tenant WRITE fails closed: INSERT
--   forge (direct WITH CHECK 42501, no trigger shadows this table — AC6),
--   UPDATE no-op. BLOCK W3 immediately below is the companion Lock 14
--   mod #1 UPDATE tenant-move forge, run as A rather than B. The DELETE
--   leg is BLOCK DEL below, per the AC12-shape isolation the migration's
--   own header requires (see header box).
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- (W1) B forges users_id=A on an INSERT -> RLS WITH CHECK requires
--      users_id = auth.uid() = B -> mismatch -> rejected (42501).
savepoint sp_w1;
select throws_ok(
  format($$ insert into pfin.owner_identification (users_id, owner_id_header_text) values (%L, 'Forged Row') $$, :'ta'),
  '42501', null,
  '(W1) cross-tenant INSERT forge: B inserts claiming users_id=A -> RLS WITH CHECK rejects (42501) — directly behaviourally reachable (no trigger shadows this table''s WITH CHECK)'
);
rollback to savepoint sp_w1;

-- (W2) B's UPDATE targets A's row by users_id -> USING filters it to 0
--      rows (silently, no exception) -> A's row is UNCHANGED.
update pfin.owner_identification set owner_id_header_text = 'Overwritten By B' where users_id = :'ta';
select set_config('role', 'postgres', true);
select is(
  (select owner_id_header_text from pfin.owner_identification where users_id = :'ta'),
  'Mosko Household — Primary',
  '(W2) cross-tenant UPDATE: B''s update where users_id=A matches 0 rows under RLS (USING filters it out) — A''s row UNCHANGED'
);

-- =====================================================================
-- BLOCK W3 (authenticated A) — Lock 14 mod #1 mass-assignment, the
--   UPDATE tenant-move forge: A owns its OWN row (USING passes on the
--   pre-update row) and attempts to retarget users_id to B on the SAME
--   UPDATE. WITH CHECK evaluates the NEW row and must reject, because the
--   post-update users_id (B) no longer equals auth.uid() (A). This is the
--   behavioural pair to (S4)'s structural pin — S4 only proves the WITH
--   CHECK clause is PRESENT, never that it actually fires on this route.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
savepoint sp_w3;
select throws_ok(
  format($$ update pfin.owner_identification set users_id = %L where users_id = auth.uid() $$, :'tb'),
  '42501', null,
  '(W3) UPDATE tenant-move forge: A owns the row (USING passes) and attempts to retarget its OWN row''s users_id to B in the same UPDATE — WITH CHECK rejects (42501) because the post-update row''s users_id (B) no longer equals auth.uid() (A); Lock 14 mod #1 mass-assignment route, behaviourally pairing (S4)''s structural pin'
);
rollback to savepoint sp_w3;
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK DEL (authenticated B, then corrupted) — the DELETE-policy leg,
--   isolated per the migration's own AC12-shape warning: a cross-tenant
--   DELETE assertion written WITH a column filter is satisfied by EITHER
--   policy and proves nothing about the DELETE policy specifically. Every
--   probe below is an UNQUALIFIED `delete from pfin.owner_identification;`
--   — no WHERE, no column reference — so the SELECT policy is never
--   consulted at all.
-- =====================================================================
-- (DEL1) REAL WORLD: B (owns no row of its own) issues an unqualified
--        delete -> owner_identification_delete's OWN USING clause is the
--        SOLE gate -> 0 rows match B's tenant -> A's real row SURVIVES.
select _rls.set_tenant(:'tb'::uuid);
delete from pfin.owner_identification;
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.owner_identification where users_id = :'ta')::bigint,
  1::bigint,
  '(DEL1) unqualified cross-tenant DELETE (no WHERE) issued by B — A''s real row SURVIVES. Non-vacuous: A''s row genuinely exists when B''s blanket delete runs, so survival is the DELETE policy''s own USING clause actively filtering it out, not an empty match by construction'
);

-- (DEL2) CORRUPT-THE-CONTROL, half 1: break owner_identification_delete's
--        OWN clause open. The IDENTICAL unqualified delete now REMOVES
--        A's row — proving (DEL1)'s survival really is DELETE's own
--        clause at work.
savepoint sp_del2;
alter policy owner_identification_delete on pfin.owner_identification using (true);
select _rls.set_tenant(:'tb'::uuid);
delete from pfin.owner_identification;
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.owner_identification where users_id = :'ta')::bigint,
  0::bigint,
  '(DEL2) CORRUPT-THE-CONTROL (DELETE clause broken OPEN): the SAME unqualified delete by B now REMOVES A''s row — proves owner_identification_delete''s own USING clause is what gated (DEL1), not RLS default-deny on an empty match'
);
rollback to savepoint sp_del2;

-- (DEL3) CORRUPT-THE-CONTROL, half 2 (the complementary half): restore
--        DELETE's real clause (done by the rollback above); instead break
--        owner_identification_select open ALONE. The unqualified delete
--        STILL leaves A's row untouched — proving SELECT's clause is
--        IRRELEVANT to an unqualified delete.
savepoint sp_del3;
alter policy owner_identification_select on pfin.owner_identification using (true);
select _rls.set_tenant(:'tb'::uuid);
delete from pfin.owner_identification;
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.owner_identification where users_id = :'ta')::bigint,
  1::bigint,
  '(DEL3) COMPLEMENTARY CONTROL (SELECT clause broken open ALONE, DELETE''s own clause real): the unqualified delete by B STILL leaves A''s row untouched — proves SELECT''s clause plays NO role in an unqualified delete''s outcome; (DEL1) isolates DELETE''s OWN clause'
);
rollback to savepoint sp_del3;

-- =====================================================================
-- BLOCK X (authenticated A, owner_identification_select corrupted) —
--   general corrupt-the-control: prove RLS, not application logic,
--   confines cross-tenant reads. Asserts B's visibility FLIPS from 0 to 1
--   under the corrupted policy — the inversion result for (R2).
-- =====================================================================
savepoint sp_leak;
alter policy owner_identification_select on pfin.owner_identification using (true);
select is(
  _rls._visible_owner_rows('pfin.owner_identification'::regclass, :'ta'::uuid, :'tb'::uuid),
  1::bigint,
  '(X1) CORRUPT-THE-CONTROL: with owner_identification_select broken OPEN (using (true)), B NOW SEES A''s 1 row — proves (R2)''s cross-tenant-empty result was owner_identification_select''s own clause at work, not a vacuous match'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_leak;

-- =====================================================================
-- BLOCK M (aal2 backstop, ADR-029/025 shape, all FOUR verbs, Sec F-9) — a
-- SEPARATE leg from BLOCK W/DEL (AC10). D (totp) builds its own row via
-- authenticated INSERT (not a service_role pre-seed) so the INSERT leg of
-- the backstop is genuinely exercised.
-- =====================================================================
-- (M1) INSERT: totp-declared D at aal1 -> WITH CHECK's aal2 conjunct
--      rejects (42501) — directly reachable (no trigger shadows this
--      table's WITH CHECK).
select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
savepoint sp_m1;
select throws_ok(
  $$ insert into pfin.owner_identification (owner_id_header_text) values ('D Household') $$,
  '42501', null,
  '(M1) INSERT: totp-declared D at aal1 — the aal2 WITH CHECK conjunct rejects (42501), directly (no trigger shadows this table''s WITH CHECK)'
);
rollback to savepoint sp_m1;
select set_config('role', 'postgres', true);

-- (M2) INSERT: SAME totp D at aal2 -> succeeds — proves (M1) non-vacuous,
--      and creates D's row for the remaining M-block legs.
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
select lives_ok(
  $$ insert into pfin.owner_identification (owner_id_header_text) values ('D Household') $$,
  '(M2) INSERT: SAME totp D at aal2 — the identical insert now SUCCEEDS — proves (M1) is non-vacuous and the backstop does not over-block aal2 writes'
);
select set_config('role', 'postgres', true);

-- (M3) SELECT: totp D at aal1 -> 0 of its OWN rows (backstop blocks the
--      read even though D genuinely owns one, per (M2)).
select is(_rls.count_as(:'td'::uuid, 'aal1', format('select count(*) from pfin.owner_identification where users_id = %L', :'td')),
  0::bigint,
  '(M3) SELECT: totp D at aal1 sees 0 of its OWN rows — the aal2 backstop blocks a direct read even though D genuinely has a row (from M2)');

-- (M4) SELECT: SAME totp D at aal2 -> row VISIBLE (proves M3 non-vacuous).
select is(_rls.count_as(:'td'::uuid, 'aal2', format('select count(*) from pfin.owner_identification where users_id = %L', :'td')),
  1::bigint,
  '(M4) SELECT: SAME totp D at aal2 sees its 1 own row — proves (M3) is non-vacuous and the backstop does not over-block aal2');

-- (M5) UPDATE: totp D at aal1 -> USING hides the row -> 0 rows affected,
--      value unchanged (still 'D Household' from M2).
select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
update pfin.owner_identification set owner_id_header_text = 'D Overwrite Attempt' where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select owner_id_header_text from pfin.owner_identification where users_id = :'td'),
  'D Household',
  '(M5) UPDATE: totp D at aal1 — the UPDATE USING aal2 backstop hides D''s own row (0 rows affected); value UNCHANGED — RED if the backstop were dropped from owner_identification_update USING'
);

-- (M6) UPDATE: SAME totp D at aal2 -> succeeds, value changes.
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
update pfin.owner_identification set owner_id_header_text = 'D Household Updated' where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select owner_id_header_text from pfin.owner_identification where users_id = :'td'),
  'D Household Updated',
  '(M6) UPDATE: SAME totp D at aal2 — the UPDATE now APPLIES — proves (M5) is non-vacuous'
);

-- (M7) DELETE: totp D at aal1 -> USING hides the row -> 0 rows affected,
--      row still present.
select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
delete from pfin.owner_identification where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.owner_identification where users_id = :'td')::bigint,
  1::bigint,
  '(M7) DELETE: totp D at aal1 — the DELETE USING aal2 backstop hides D''s own row (0 rows affected); the row STILL EXISTS — RED if the backstop were dropped from owner_identification_delete USING'
);

-- (M8) DELETE: SAME totp D at aal2 -> succeeds, row gone.
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
delete from pfin.owner_identification where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.owner_identification where users_id = :'td')::bigint,
  0::bigint,
  '(M8) DELETE: SAME totp D at aal2 — the DELETE now APPLIES — proves (M7) is non-vacuous'
);

select * from finish();
rollback;
