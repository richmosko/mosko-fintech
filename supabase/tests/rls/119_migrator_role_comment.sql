-- =====================================================================
-- 119_migrator_role_comment.sql — catalog-text battery for the `migrator`
--   role comment as re-cited by
--   supabase/migrations/119_migrator_role_comment_amendment3_recitation.sql.
--   ADR-072 Amendment 3 (2026-09-14) + Amendment 4 (2026-09-16).
--   BACKLOG.md §7.36 items 27 / 29 / 31 / 32. Sec-joint-review-mandatory surface.
-- =====================================================================
-- WHAT THIS FILE IS, AND WHAT IT DELIBERATELY IS NOT
--   It is a CATALOG-TEXT battery, not an RLS battery: 118 and 119 create no
--   table, no column, no policy and no function, so there is no two-tenant
--   read/write surface to fence and a two-tenant fixture would be decoration.
--   It lives under tests/rls/ because that directory is where
--   migration-number-paired batteries are discoverable and `pg_prove -r`
--   collects it either way. It is the 116 (r11) leg's counterpart for
--   `migrator`, widened: 116 asserts only that a comment EXISTS, which cannot
--   see a comment that exists and is WRONG.
--
--   ⚠ WHY A TEXT BATTERY EARNS ITS KEEP HERE, when a comment is only
--   documentation: `comment on role` writes to pg_shdescription, a SHARED
--   CLUSTER catalog, and 118 and 119 both write the SAME key. Any apply that
--   runs 118 after 119 — a chain replay, a partial re-run, a restore — silently
--   reinstates the WITHDRAWN Amendment-1 confinement claim and the falsified
--   "as postgres" bootstrap instruction, with no error and no diff. The legs
--   below are the only thing that observes that. Every negative leg here
--   (c3)/(c5) is exactly a 118-reinstatement detector.
--
--   Decision 3 family unchanged (+0) and §10 catalogued ledger unchanged: this
--   file and the migration it pairs with create no table, column or FK-shaped
--   reference of any kind, and catalogue no §10 instance.
--
--   FAIL-CLOSED SHAPE: every leg reads shobj_description() through a scalar
--   subquery, so a MISSING `migrator` role yields NULL. `ok(NULL)` is RED.
--   pgTAP's isnt() PASSES on NULL and is therefore forbidden in this file.
-- =====================================================================

begin;

select plan(8);

-- ---------------------------------------------------------------------
-- (c0) DEPENDENCY GUARD — must come first and must be LEGIBLE.
-- ---------------------------------------------------------------------
select ok(
  (select count(*) = 1 from pg_roles where rolname = 'migrator'),
  '(c0) DEPENDENCY: migration 118 is applied and the role `migrator` exists. If this is the only RED in the file, 118 has not been applied to this cluster — apply it rather than editing (c1)-(c6), every one of which reads this role'
);

-- ---------------------------------------------------------------------
-- (c1) The comment exists at all. The 116 (r11) shape, and the weakest
--      leg here on purpose: it is the one that stays meaningful if the
--      wording is deliberately revised later.
-- ---------------------------------------------------------------------
select ok(
  (select shobj_description(oid, 'pg_authid') is not null
     from pg_authid where rolname = 'migrator'),
  '(c1) `comment on role migrator` is present. It carries the supervised four-statement bootstrap, the B10 prohibition on the single-statement `ALTER ROLE … WITH LOGIN PASSWORD` form, and the Decision-4 tripwire — all of which an operator reads from the catalog rather than from the repository. Asserted with ok(… is not null) rather than isnt(…, null) because pgTAP''s isnt() PASSES on NULL and would fail open here'
);

-- ---------------------------------------------------------------------
-- (c2) POSITIVE: the citation is 119's, not 118's.
-- ---------------------------------------------------------------------
select ok(
  (select position('re-cited by migration 119' in shobj_description(oid, 'pg_authid')) > 0
     from pg_authid where rolname = 'migrator'),
  '(c2) citation currency: the comment carries 119''s re-citation to ADR-072 Decision 4 + Amendments 3-4. RED means the catalog is still carrying 118''s "Decision 4 + Amendment 1" citation, whose confinement claim Amendment 3 WITHDREW — i.e. 118 was applied after 119, or 119 never applied'
);

-- ---------------------------------------------------------------------
-- (c3) NEGATIVE: the WITHDRAWN confinement claim is GONE.
--      This is the leg that matters most — a false reassurance about a
--      standing DDL credential, read by an operator with no repo.
-- ---------------------------------------------------------------------
select ok(
  (select position('confined to the migrator service by non-reference' in shobj_description(oid, 'pg_authid')) = 0
     from pg_authid where rolname = 'migrator'),
  '(c3) WITHDRAWN claim absent: the catalog must NOT assert that MIGRATOR_DB_PASSWORD is confined to the migrator service by non-reference. ADR-072 Amendment 3 measured that false on the running stack — every service in the Supabase-stack Coolify application receives the whole env store via env_file. RED means an operator reading `\du+` is being told a standing DDL credential is confined when it is not'
);

-- ---------------------------------------------------------------------
-- (c4) POSITIVE: the bootstrap names the image's TRUE superuser.
-- ---------------------------------------------------------------------
select ok(
  (select position('TRUE SUPERUSER' in shobj_description(oid, 'pg_authid')) > 0
     from pg_authid where rolname = 'migrator'),
  '(c4) bootstrap identity: the comment sends the operator to the image''s TRUE superuser (supabase_admin on the Supabase Postgres image). BACKLOG §7.36 item 31 — `postgres` measures rolsuper = f on that image and fails `ALTER DATABASE … OWNER TO migrator` with "must be able to SET ROLE migrator"'
);

-- ---------------------------------------------------------------------
-- (c5) NEGATIVE: the falsified "as postgres" instruction is GONE.
--      Paired with (c4) deliberately: (c4) alone would stay green if the
--      new sentence were ADDED beside the old one rather than replacing it.
-- ---------------------------------------------------------------------
select ok(
  (select position('first bootstrap, as postgres,' in shobj_description(oid, 'pg_authid')) = 0
     from pg_authid where rolname = 'migrator'),
  '(c5) falsified instruction absent: the catalog must NOT tell an operator to run the supervised first bootstrap "as postgres". Measured live 2026-09-14 — that run fails on this image. Separate from (c4) on purpose: adding the correct sentence without removing the wrong one greens (c4) and leaves the operator two conflicting instructions'
);

-- ---------------------------------------------------------------------
-- (c6) POSITIVE: the fourth supervised statement is present.
--      §7.36 item 32 — the ADR-072 D4 tripwire firing against the
--      migration-ledger schema, fixed by ownership transfer in the same
--      supervised pass. Absent from 118's comment entirely.
-- ---------------------------------------------------------------------
select ok(
  (select position('ALTER SCHEMA supabase_migrations OWNER TO migrator' in shobj_description(oid, 'pg_authid')) > 0
     from pg_authid where rolname = 'migrator'),
  '(c6) fourth supervised statement: the comment carries the supabase_migrations owner transfer (BACKLOG §7.36 item 32). Owning the DATABASE does not extend to owning the migration-ledger SCHEMA, which the bootstrap created before this role existed; without this statement `supabase db push` fails 42501 under the migrator''s own credential. RED means the catalog still describes a three-statement handoff that leaves the unsupervised apply path broken'
);

-- ---------------------------------------------------------------------
-- (c7) POSITIVE: the ADMIN-option limit is framed as an INSTANCE of the
--      general object-ownership gap, not a property of role comments.
--      Sec's one condition on PR #775. Without this clause a reader
--      concludes role comments are the only affected class and
--      rediscovers the gap at the first ALTER TABLE.
-- ---------------------------------------------------------------------
select ok(
  (select position('INSTANCE OF A GENERAL GAP' in shobj_description(oid, 'pg_authid')) > 0
     from pg_authid where rolname = 'migrator'),
  '(c7) generality of the gap: the comment states that owning the DATABASE confers no ownership of any object inside it, so ALTER / COMMENT / DROP fail for `migrator` on tables, views, sequences, types and functions exactly as they do on this role comment — role comments are only where the gap was met first. RED means the catalog presents the ADMIN-option refusal as a special case, which is how the next reader rediscovers the whole gap at the first ALTER TABLE'
);

select * from finish();

rollback;
