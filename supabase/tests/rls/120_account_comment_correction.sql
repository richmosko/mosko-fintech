-- ============================================================================
-- 120 — pfin.account table comment: the 015-falsified claim is corrected.
--
-- ⚠ AUTHORSHIP NOTE. supabase/tests/ is QA-owned and Architect does not normally
--   author here (apply-migration skill, Role split). This file is authored by
--   Architect under explicit F/CTO-session direction, as 119's battery was, so the
--   Phase D vehicle ships with its assertion. It is QA's to own and extend from here.
--
-- WHAT IT WATCHES. 120 is comment-only, so there is no behaviour to assert — the
--   catalog text IS the deliverable. These legs read pg_description through
--   obj_description, which is what `\d+` shows and therefore what actually shipped;
--   reading the migration file instead would assert the repo, not the database.
--
-- ⚠ (t3) IS THE ONE THAT CAN FAIL FOR THE RIGHT REASON. (t1)/(t2) would also pass
--   against a half-applied comment. (t3) pins the prefix that 120 promised to leave
--   byte-identical, so a regeneration that silently altered the untouched half is
--   caught here rather than by a reader noticing years later.
-- ============================================================================

begin;
select plan(5);

-- (t1) the retired claim is gone
select ok(
  obj_description('pfin.account'::regclass, 'pg_class') !~ 'is DEFERRED',
  '(t1) pfin.account comment no longer claims the linkage column is DEFERRED — 015 added it by ALTER, so the claim has been false since 015'
);

-- (t2) the replacement names the column a reader can actually check
select ok(
  obj_description('pfin.account'::regclass, 'pg_class') ~ 'landed via ALTER at 015 as linked_source_id',
  '(t2) the comment names linked_source_id and dates its arrival — a past-tense durable event the reader can verify at \d+, not a present-tense claim about state they cannot see'
);

-- (t3) the containment promise: the untouched prefix survived regeneration verbatim
select ok(
  obj_description('pfin.account'::regclass, 'pg_class') like
    'Core account entity (ADR-011 Decision 5 / Lock 1; SELF-187). DP-6 = B minimal V1 column set.%',
  '(t3) the prefix 120 promised to leave byte-identical is byte-identical — this is the leg that catches a regeneration which altered the half it was not correcting'
);

-- (t4) and the untouched suffix likewise
select ok(
  obj_description('pfin.account'::regclass, 'pg_class') like
    '%RLS isolation anchor is users_id = auth.uid().',
  '(t4) the suffix 120 promised to leave byte-identical is byte-identical — same containment claim, other end of the span'
);

-- (t5) the object 120 says was dropped is in fact absent
select ok(
  to_regclass('pfin.plaid_items') is null,
  '(t5) pfin.plaid_items is absent, so the comment''s statement that 015 dropped it is true of this database — a comment that named a live table would be a fresh false claim, not a correction'
);

select * from finish();
rollback;
