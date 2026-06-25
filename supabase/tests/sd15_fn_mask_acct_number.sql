-- =====================================================================
-- SD-15 — fn_mask_acct_number per-§10-instance test (behavioral + no-disclosure)
-- =====================================================================
-- SD-15's function is a PURE transformer (text->text IMMUTABLE STRICT) — no
-- table / no RLS — so this is NOT a cross-tenant test. It is the per-§10-instance
-- discipline made real: SD-15's first test, proving the storage-class rule (acct
-- numbers render masked-only) is mechanically enforced. The "full-value-
-- disclosure fence" Architect's migration forward-points to IS the no-disclosure
-- assertion below.
--
-- BINDS TO MIGRATION: pfin.fn_mask_acct_number at `supabase/migrations/002_fn_mask_
-- acct_number.sql`. The migration file EXISTS on disk (W2); these vectors were
-- verified line-by-line against its authored SQL (not a relayed guess). Process
-- gate: 002 finalizes when Sec clears the W2 joint-review (in flight). This test
-- is RED until 002 is APPLIED to the test DB (function absent), GREEN once applied
-- — expected, not a failure.
--
-- VERIFIED AGAINST AUTHORED 002 SQL (2026-06-25):
--   pfin.fn_mask_acct_number(p_acct TEXT) -> TEXT  (language sql, IMMUTABLE, STRICT,
--     set search_path = '')
--   body: case when length(p_acct) <= 4 then '••••'
--              else '••••' || right(p_acct, 4) end
--   => length > 4 : '••••' + last-4 (length not leaked); length <= 4 : '••••'
--     (security-load-bearing edge — at exactly 4, "reveal last-4" = whole value);
--     NULL -> NULL (STRICT). Every assertion below matches this body exactly.
-- =====================================================================

begin;
select plan(8);

-- standard case: ••••+last4
select is( pfin.fn_mask_acct_number('123456789'), '••••6789',
  'len>4: masks to ••••+last-4' );

-- another len>4 vector (5 chars -> reveal last-4)
select is( pfin.fn_mask_acct_number('12345'), '••••2345',
  'len 5: reveals exactly last-4' );

-- SECURITY-LOAD-BEARING EDGE: len == 4 -> FULLY masked (no whole-number leak)
select is( pfin.fn_mask_acct_number('1234'), '••••',
  'len==4: fully masked (revealing last-4 would expose the whole value)' );

-- empty string (len 0 <= 4) -> fully masked
select is( pfin.fn_mask_acct_number(''), '••••',
  'empty string: fully masked' );

-- length must NOT leak: 12-char input yields the SAME output as the 9-char above
select is( pfin.fn_mask_acct_number('000123456789'), '••••6789',
  'original length is not leaked (fixed token, not length-preserving)' );

-- STRICT: NULL -> NULL
select is( pfin.fn_mask_acct_number(NULL), NULL,
  'NULL input -> NULL output (STRICT)' );

-- idempotent: masking a masked value is stable
select is( pfin.fn_mask_acct_number(pfin.fn_mask_acct_number('123456789')),
           pfin.fn_mask_acct_number('123456789'),
  'idempotent: re-masking a masked value is stable' );

-- NO-DISCLOSURE FENCE: output never contains the full input value
select ok( pfin.fn_mask_acct_number('123456789') NOT LIKE '%123456789%'
       and pfin.fn_mask_acct_number('123456789') NOT LIKE '%12345%',
  'no-disclosure fence: masked output never contains the full account number' );

select * from finish();
rollback;
