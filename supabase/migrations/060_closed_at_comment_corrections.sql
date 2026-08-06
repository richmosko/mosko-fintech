-- ============================================================================
-- 060_closed_at_comment_corrections.sql — COMMENT-ONLY. No DDL, no behaviour.
--
-- Numbering: 060 follows 059. It re-emits ONE catalog comment that 059 shipped
--   with a FALSE clause. It is a NEW MIGRATION and NOT an edit to 059, because
--   059 IS MERGED and the §7.6 S3 scoping guard forbids rewriting a merged
--   migration's history. A `comment on ...` is a DATABASE OBJECT, so it is
--   correctable this way without touching the file that created it — the
--   052_self227_audit_trace_comments.sql precedent.
--
-- WHAT WAS WRONG, and it is the uncomfortable kind. 059's closed_at comment
--   measured its hazard CORRECTLY — the session-TimeZone date cast, the
--   off-by-one-day near local midnight, all verified — and then MISIDENTIFIED
--   WHAT WAS PROTECTING AGAINST IT. It claimed "V1 consumers pass CURRENT_DATE,
--   which is evaluated on the same clock in the same session". Measured:
--     · todayIso() is `new Date().toISOString().slice(0,10)` — UTC, in NODE
--     · FOUR call sites derive p_as_of that way; ZERO pass CURRENT_DATE
--     · closed_at::date evaluates in the POSTGRES SESSION TimeZone
--   Two clocks, two processes. Lock 15 mod #2 guarantees the date is SERVER-
--   derived and says nothing about WHICH SERVER — that is the whole gap.
--
--   >> A COMMENT CAN NAME A REAL HAZARD ACCURATELY AND MISIDENTIFY WHAT HOLDS
--      IT, AND THE SECOND ERROR IS THE ONE THAT STOPS PEOPLE LOOKING. <<
--   Distinct from every failure this slice has catalogued: not a stale claim
--   (it was never true), not an unstated dependency (one WAS stated), but a
--   CONFIDENTLY WRONG dependency, which is worse than none — an absent
--   dependency invites a check and a wrong one answers it in advance.
--
--   It held LOCALLY BY ACCIDENT, which is why it survived review: the dev
--   stack's session TimeZone measures UTC, so every test and every read agreed.
--
-- METHOD — REGENERATE AND DIFF, NEVER RETYPE. The replacement was produced by
--   extracting 059's comment verbatim and applying TWO anchored substitutions,
--   each asserted to match exactly once, diff-proved against the original. The
--   surrounding 2.8KB of measured content is byte-identical. Retyping a comment
--   of this size is how the correct halves get silently altered alongside the
--   wrong one.
--
-- PAIRED, NOT INDEPENDENT: this comment now names ADR-043 and ADR-043 names it,
--   per Sec — the two sides of one trigger. ADR-043's accepted cost RESTS on the
--   guarantee corrected here.
-- ============================================================================

create schema if not exists pfin;

comment on column pfin.account.closed_at is
  'THE ONLY representation of open/closed (ADR-042). The boolean flag was retired at 059: it answered "open NOW" where closed_at answers "open AS OF a date" — strictly more information, and the two coexisting was the three-way overloading ADR-042 exists to remove. Readers use (closed_at is null or closed_at::date > p_as_of). ⚠ THE `::date` IS REQUIRED, NOT INCIDENTAL — this column is timestamptz and every as-of parameter in the schema is a date, so a bare `closed_at > p_as_of` promotes the date to MIDNIGHT and an account closed at any time after 00:00 on p_as_of stays INCLUDED for the rest of that day. Since fn_close_account defaults p_closed_at to now(), that is EVERY app-closed account, and it means a just-closed account remains in the §2.1.1 headline until midnight — reading as "the close did not work". NAV VALUE is identical either way (the gate proved zero as of that date), so the defect is invisible to value assertions and shows up only in ROW SETS and COUNTS. Cast to date, matching fn_holdings_as_of / fn_account_cash_as_of / transaction_date / as_of_date and the close gate''s own legs. ⚠ THE CAST IS EVALUATED IN THE SESSION TimeZone, AND THAT IS SAFE ONLY BY A DEPENDENCY OUTSIDE THIS COLUMN — stated per the symmetric rule, since a fence whose sufficiency comes from elsewhere must say so. MEASURED: a user in UTC−5 closing at 20:00 local on Mar 1 records the instant 2026-03-02 01:00Z; under session TimeZone UTC that is closed_at::date = Mar 2 and the account is INCLUDED at p_as_of = Mar 1, while under session −05 it is Mar 1 and EXCLUDED. Same row, same predicate, opposite answers — an off-by-one-DAY for any closure near local midnight. WHAT HOLDS IT TODAY — CORRECTED AT 060; THE EARLIER CLAUSE WAS FALSE IN BOTH HALVES AND IS THE HALF EVERYONE REASONED FROM. It read "V1 consumers pass CURRENT_DATE, which is evaluated on the same clock in the same session". MEASURED: no app caller passes CURRENT_DATE at all — todayIso() is new Date().toISOString().slice(0,10), so p_as_of is UTC-derived IN THE NODE PROCESS (4 call sites across the dashboard and account-detail loaders), while closed_at::date is evaluated in the POSTGRES SESSION TimeZone. TWO CLOCKS IN TWO PROCESSES, not one. Lock 15 mod #2 guarantees the date is SERVER-derived; it says nothing about WHICH SERVER, and that is the precise gap. THE REAL GUARANTEE IS A PINNED DATABASE TIMEZONE: the two sides agree IF AND ONLY IF the Postgres session TimeZone is UTC, matching the application''s unconditional UTC derivation. That pin lands at 061 (ALTER DATABASE ... SET timezone) with a catalog read-back, plus QA''s effective read-back in a NEW session. ⚠ THE PIN IS NECESSARY AND NOT SUFFICIENT, and this clause is deliberately weaker than the one it replaces, which claimed too much in the other direction. MEASURED with the pin ACTIVE: PGTZ in a connecting client''s environment resolves at source=client, which OUTRANKS source=database, so any libpq-backed client (psycopg in workers/etl, psql, anything) can move its own session zone WHILE THE DATABASE STILL READS UTC TO ANYONE INSPECTING IT — a half-pinned deployment that inspects clean. TZ alone is a no-op, which is the reassuring wrong instinct. ALTER ROLE ... SET timezone also outranks the database pin; nothing sets one today. SO THE FULL CONDITION IS: the 061 pin, AND no client supplying PGTZ, AND no role-level override — the first enforced in DDL, the other two by the runbook TZ-1 deploy gate and the .env.example prohibitions — named per the symmetric rule, which this correction extends: a fence must say where its sufficiency comes from AND what makes that verifiable, because the previous clause named a dependency that was never checkable and was therefore never checked. ⚠ IT HELD LOCALLY BY ACCIDENT, WHICH IS WHY IT SURVIVED REVIEW: session TimeZone measures UTC on the dev stack today, so every test and every read agreed. An unpinned deployment in any other zone silently breaks the agreement, and the symptom is an off-by-one-day on closure boundaries with nothing failing. ⚠ THAT DEPENDENCY IS NARROWING, NOT STABLE: 059 STRUCK the ADR-039 sound-only-at-current_date constraint and thereby LEGALISED past as-of dates, so a §2.1.2 trajectory passing a USER-CHOSEN date is now a sanctioned path — and the first caller that supplies p_as_of from a user''s calendar rather than the server''s breaks the agreement, silently, in the user''s favour or against it depending on which side of midnight they closed. Whoever makes p_as_of user-supplied owns resolving the zone explicitly (store or thread the tenant''s zone; do not let the session default decide), and should find this sentence before they do. ⚑ THE DISPLAY SIDE OF THIS SAME TRIGGER IS ADR-043 (closure dates render in UTC, unlabelled, on all three surfaces), AND THE TWO MUST BE READ TOGETHER — each MUST name the other so whoever trips one is handed the other, which covers the author who changes the DISPLAY without touching this as-of path, and the author who changes this path without looking at the display. ADR-043''s accepted cost rests on a claim this comment is what makes true: that the rendered date IS the date the system reasoned with. Rendering pins UTC; the reasoning pins UTC only via the database TimeZone above. UNPIN THE DATABASE AND ADR-043''s justification becomes FALSE — not merely weaker — while every screen keeps rendering and nothing fails. NEVER a bare `closed_at is null` in an as-of context, and never a LEFT-JOINed `closed_at is null` without an accompanying `account_id is not null`, which fails OPEN by asserting "not closed" from no information.';
