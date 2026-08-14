-- ============================================================================
-- Migration: pfin.fn_server_today — ADR-044 R2, the database-derived as-of date.
--   ONE function, one statement. This is a CLOCK PRIMITIVE, not a policy surface,
--   and it is deliberately the smallest thing that can discharge R2.
--   Linear SELF-221 (V1.1; PRD §2.1.3). R2 pulled forward into this slice at
--   F/CTO ratify 2026-08-13 — ADR-044 recorded the DECISION but explicitly did
--   not schedule the build ("Scope note … It does not schedule the R2 build").
--   apply-migration procedure applied. JOINT-REVIEW-MANDATORY (Sec veto
--   surface): a new clock primitive on the as-of comparison path.
--
-- ----------------------------------------------------------------------------
-- ⚠ WHAT R2 GUARANTEES, AND — MORE IMPORTANTLY — WHAT IT DOES NOT.
--   ADR-044 states both in a table, and the non-guarantees are the half that
--   gets lost in re-telling. Reproduced here as the reason this function stays
--   one line:
--     GUARANTEES : that BOTH SIDES OF ONE COMPARISON use the SAME day.
--     DOES NOT   : WHICH day that is; and NOTHING ACROSS CONTAINERS.
--
--   ⚠⚠ THE CORRECTION ADR-044 CALLS "most likely to be lost in re-telling":
--   `current_date` IS ITSELF SESSION-TimeZone-EVALUATED. **R2 DOES NOT MAKE THE
--   AS-OF DATE ZONE-INDEPENDENT.** It makes both sides of the comparison use the
--   SAME zone, whatever that zone is. Anyone reading this function as "the
--   zone-safe way to get today" has inverted its purpose: the safety is in
--   SHARING one derivation, not in escaping the zone.
--
--   CONSEQUENCE, STATED SO NO CONSUMER INFERS OTHERWISE: a comparison between a
--   value derived HERE and a value derived in a DIFFERENT CONTAINER is NOT
--   covered. ADR-044's own finding is the model — pfin.nav_daily.nav_date is
--   `current_date` in the ETL WORKER's session, a different container and login
--   role from the web app. Reading nav_date against this function's answer
--   spans two clocks, and R2 says so explicitly.
--
-- ----------------------------------------------------------------------------
-- ⚠ AND R2 DOES NOT RELIEVE THE ADR-043 PIN. The correction owed to `060` / the
--   runbook / asOf.ts when R2 lands is quoted verbatim from ADR-044, because a
--   paraphrase loses it:
--     >> "the pin is no longer the app's within-comparison guarantee." <<
--     NEVER "the pin is no longer load-bearing."
--   `061`'s database pin stays load-bearing for everything outside a single
--   comparison — including the hard-pinned-UTC rendering path ADR-043 governs.
--   THIS MIGRATION RE-POINTS NOTHING. It authors the primitive; the `060` /
--   runbook / asOf.ts corrections are separate work and are NOT discharged here.
--
-- ----------------------------------------------------------------------------
-- ⚠ DO NOT "HARMONIZE" THE ETL WORKER ONTO THIS FUNCTION. ADR-044 names this as
--   the natural sweep that would be wrong: the worker already derives
--   `current_date` in SQL in its own session, so routing it through this helper
--   adds a round trip and buys nothing. "Make it consistent" is exactly the
--   instinct to resist here.
--
-- ----------------------------------------------------------------------------
-- Numbering: 070 follows 069 (fn_first_cron_checkpoint), taken at authoring time
--   and verified against the tree at 8fd9f8e. Depends on 001 (the pfin schema)
--   and nothing else — it reads no relation. 071 in this same PR is its first
--   consumer. Order-independent beyond `create schema`.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER, as ADR-044's own cross-reference records
--   ("R2's fn_server_today() is INVOKER"). It reads no relation and needs no
--   elevated privilege; DEFINER would buy nothing and would detach the answer
--   from the caller's session, which is the one thing this function must not do
--   — its entire value is that the caller and the function share a session.
--   THE SECURITY DEFINER ALLOWLIST IS NOT TOUCHED. Read ADR-011 Decision 9 live;
--   no count is restated here.
--
-- ----------------------------------------------------------------------------
-- NOT A ONE-WAY DOOR — recorded because clock decisions attract more caution
--   than this one deserves. ADR-044 lists it explicitly among the reversible
--   items: "fn_server_today() reverses with `drop function`." The genuine
--   one-way door in this area is a DIFFERENT thing — WHICH ZONE
--   pfin.nav_daily.nav_date derives in, which closes once production checkpoints
--   accumulate. THIS FUNCTION DOES NOT TOUCH THAT DOOR: it writes nothing and
--   imprints no convention on nav_date.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_server_today() RETURNS date
--     — SECURITY INVOKER, STABLE, set search_path = ''.
--   · Returns the database's own current date, in the CALLER'S SESSION zone.
--   · STABLE, not VOLATILE: `current_date` is fixed for the duration of a
--     transaction, so two calls in one transaction agree BY CONSTRUCTION. That
--     is the mechanism behind R2's guarantee, not an incidental property.
--   · Takes no argument and reads no relation, so it has no tenant surface and
--     no RLS interaction of any kind.
--   · Security-load-bearing edges: none of the usual ones apply — no tenant
--     scoping, no financial value, no write path. The load-bearing property is
--     SHARED DERIVATION: a consumer that computes its own date instead of
--     calling this re-opens the two-clock hazard, and nothing in the database
--     can detect that. It is held by review.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; the catalogued
--   numbered list is NOT restated here and no count is stated. Decision 4 read
--   VERBATIM at the canonical anchor before drafting, 2026-08-13, at 8fd9f8e.)
--   (i)   Instance-numbering: nothing appended, reordered, or renumbered.
--   (ii)  Layer-attribution: an INVOKER helper reached by `authenticated`. NOT
--         the PDF-worker container credential audit, NOT the code-layer
--         SUPABASE_SERVICE_ROLE_KEY allowlist fence, NOT the app→worker
--         credential-admission network surface. No catalogued instance's layer
--         attribution moves; no surface becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is REFERENCED, not restated.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS and are
--   NOT reconciled here.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — +0. No table, no column, no
--   FK-shaped reference of any kind. AUTHORING-TIME PROVENANCE (dated, not live
--   state — read Decision 3's body live): read verbatim at the canonical anchor
--   on 2026-08-13 at 8fd9f8e, the family stood at SIXTEEN LABELED INSTANCES
--   (#1–#16), THIRTEEN DDL-REALIZED. Recorded as a dated observation ONLY.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (all FLAT): §10 catalogued +0 · SECURITY DEFINER allowlist +0 ·
--   Decision 3 family +0 · SD matrix NO expansion · no grants on existing
--   objects change · no RLS, no triggers. Sec joint-review MANDATORY anyway: a
--   new clock primitive on the as-of comparison path.
--
-- ----------------------------------------------------------------------------
-- QA TEST-PAIRING (QA-owned). Ships SAME-PR.
--   1. Returns a `date` and is non-NULL.
--   2. SAME-TRANSACTION STABILITY — two calls inside one transaction return the
--      SAME value. This is R2's guarantee in its testable form; assert it
--      directly rather than trusting the STABLE marker.
--   3. AGREES WITH THE SESSION'S OWN `current_date` in the same session. ⚠ This
--      leg exists to pin that the function does NOT try to be clever — a future
--      "improvement" hard-pinning UTC inside it would BREAK R2 by making the
--      function and its caller disagree, which is the exact inversion the header
--      warns about.
--   4. PST1-SHAPE POSTURE LEG, read declaratively from the catalog: prosecdef
--      false (INVOKER), provolatile 's' (STABLE), proconfig pins search_path
--      empty. Behaviour alone cannot distinguish INVOKER from DEFINER.
--   5. ACL: EXECUTE revoked from PUBLIC, granted to `authenticated`. Assert on
--      pg_proc.proacl, not on a successful call.
--   ⚠ NOT TESTABLE HERE, and stated so it is not assumed: that CONSUMERS use
--   this instead of deriving their own date. That is R2's actual value and it is
--   held by review — nothing in the database can observe a consumer computing
--   its own `current_date`.
--   ⚠ `supabase db reset` is PROHIBITED — it destroys F/CTO's local test data.
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- pfin.fn_server_today — the database's own current date, shared by every
-- consumer so that both sides of a comparison use the same day. One statement;
-- see the header for why it must stay that way.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_server_today()
returns date
language sql
stable
security invoker
set search_path = ''
as $$
  -- `current_date` is a reserved SQL keyword, not a schema-qualified call, so
  -- the empty search_path does not affect it. It is STABLE within a transaction,
  -- which is precisely what makes two calls in one comparison agree.
  select current_date;
$$;

revoke execute on function pfin.fn_server_today() from public;
grant  execute on function pfin.fn_server_today() to authenticated;

comment on function pfin.fn_server_today() is
  'ADR-044 R2 — the database-derived as-of date. Returns the database''s own current_date, evaluated in the CALLER''S '
  'SESSION zone. SECURITY INVOKER, STABLE, set search_path = ''''. Reads no relation; no tenant surface, no RLS '
  'interaction. '
  '⚠ WHAT THIS GUARANTEES: that BOTH SIDES OF ONE COMPARISON use the SAME day. ⚠ WHAT IT DOES NOT: WHICH day that is, '
  'and nothing ACROSS CONTAINERS. '
  '⚠⚠ THE CORRECTION ADR-044 SINGLES OUT AS MOST LIKELY TO BE LOST: current_date is ITSELF session-TimeZone-evaluated, '
  'so this function DOES NOT make the as-of date zone-independent — it makes both sides use the same zone, whatever '
  'that zone is. Reading it as "the zone-safe way to get today" inverts its purpose: the safety is in SHARING one '
  'derivation, not in escaping the zone. A comparison against a value derived in a DIFFERENT CONTAINER is therefore '
  'NOT covered — pfin.nav_daily.nav_date is current_date in the ETL worker''s session, a different container and login '
  'role, and reading it against this function spans two clocks. '
  '⚠ THIS DOES NOT RELIEVE THE ADR-043 PIN. Quoted verbatim because a paraphrase loses it: "the pin is no longer the '
  'app''s within-comparison guarantee" — NEVER "the pin is no longer load-bearing". 061''s database pin stays '
  'load-bearing outside a single comparison, including the hard-pinned-UTC rendering path. '
  'STANDING REQUIREMENT — a consumer needing today''s date on the as-of comparison path CALLS THIS FUNCTION rather than '
  'deriving its own; a consumer that derives its own re-opens the two-clock hazard, and NOTHING IN THE DATABASE CAN '
  'DETECT THAT. It is held by review. ⚠ The ETL worker is the documented EXCEPTION, not a target: it already derives '
  'current_date in its own session, and ADR-044 explicitly warns against "harmonizing" it onto this helper — that adds '
  'a round trip and buys nothing. '
  'STABLE rather than VOLATILE is load-bearing, not cosmetic: current_date is fixed for the duration of a transaction, '
  'so two calls within one comparison agree BY CONSTRUCTION. That is the mechanism behind the guarantee above. '
  'NOT a one-way door — ADR-044 lists it among the reversible items ("reverses with drop function"). The genuine '
  'one-way door nearby is a DIFFERENT thing: which zone pfin.nav_daily.nav_date derives in. This function writes '
  'nothing and imprints no convention on nav_date. '
  'SECURITY INVOKER — NOT a DEFINER allowlist entry, and this migration authors no DEFINER function; read ADR-011 '
  'Decision 9 live. §10 catalogued ledger UNCHANGED BY THIS OBJECT and NO COUNT IS STATED HERE. Read ADR-011 '
  'Decision 4 live. Decision-3 unchanged (no table, column, or FK-shaped reference). EXECUTE revoked from PUBLIC, '
  'granted to authenticated. Sec joint-review-mandatory (new clock primitive on the as-of comparison path); first '
  'consumer is pfin.fn_nav_delta_panel (071), same PR.';
