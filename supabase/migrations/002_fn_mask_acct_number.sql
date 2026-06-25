-- ============================================================================
-- Migration: pfin.fn_mask_acct_number — SD-15 masked-rendering helper
-- Phase 5 Step 4 W2. Closes the SD-15 implicit gap (temp/phase-4-sd-rt-coverage.md)
-- per ADR-011 Decision 9 / Lock 5 (SECURITY §4.4 SD-15).
--
-- Numbering: 002 reserves 001 for the foundational users_id_rename migration
-- (SELF-186 Phase 5 close-gate, authored later); fn_mask is order-independent.
--
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT SECURITY DEFINER.
--   fn_mask_acct_number is a PURE string transform (TEXT in -> masked TEXT out). It reads
--   no tables and needs no elevated privilege, so it carries the default INVOKER posture and
--   is NOT a V1 SECURITY DEFINER allowlist entry (allowlist corrected 3->2 at W2: only
--   fn_refresh_updated_at + the audit-log insert helper remain DEFINER). The "full value
--   never user-facing" / masked-only guarantee is enforced at the app-layer rendering +
--   the Phase-6 PR-review fence on full-value-disclosure surfaces per ADR-011 Decision 9
--   Sec mod #2 (QA authors the disclosure-fence test in W3). This DB function is the
--   masking PRIMITIVE, not the privilege boundary. (Ratified Option A.)
--
-- CONTRACT
--   pfin.fn_mask_acct_number(p_acct TEXT) RETURNS TEXT — IMMUTABLE, STRICT (NULL -> NULL).
--   - length > 4  -> fixed mask token '••••' + last 4 chars (original length NOT leaked).
--   - length <= 4 -> fully masked '••••' (no partial-suffix leak; full value never shown
--                    even for short numbers — at exactly 4, "reveal last-4" would expose
--                    the whole value, so <=4 is fully masked).
-- ============================================================================

create schema if not exists pfin;

create or replace function pfin.fn_mask_acct_number(p_acct text)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select case
    when length(p_acct) <= 4 then '••••'
    else '••••' || right(p_acct, 4)
  end;
$$;

comment on function pfin.fn_mask_acct_number(text) is
  'SD-15 masked-rendering helper (ADR-011 Decision 9 / Lock 5). Pure IMMUTABLE/STRICT transform: reveals last-4 with fixed ''••••'' mask token (length not leaked); length<=4 -> fully masked; NULL -> NULL. SECURITY INVOKER (default; NOT a DEFINER allowlist entry) — masked-only enforcement is app-layer + Phase-6 PR-review fence per Decision 9 Sec mod #2.';
