---
name: feedback-returning-clause-needs-select-on-every-returned-column
description: An INSERT/UPDATE ... RETURNING <col> requires SELECT privilege on <col> even for the row the SAME statement just wrote — a column-level SELECT grant scoped to arbiter columns silently breaks a RETURNING clause naming any other column. Same family — a bare UPDATE/DELETE ... WHERE <col> = ... needs SELECT on <col> too, to evaluate the predicate, distinct from the UPDATE/DELETE grant itself. Found authoring SELF-353/107 (RETURNING) and SELF-345/111 (WHERE), 2026-09-05.
metadata:
  type: feedback
---

`INSERT ... ON CONFLICT ... DO NOTHING RETURNING <col>` needs SELECT privilege on
`<col>` for the executing role — Postgres checks this exactly as it would for a
plain read, with **no exception for a column the same statement just inserted**.
Measured directly (not inferred): granting a role only INSERT on a table, then
`insert ... returning id` as that role, throws `permission denied for table
<t>`, hint `GRANT SELECT ON <t> TO <role>`.

This bit migration 107 (`pfin.nav_component_daily`, SELF-353/A9): the header's
own worker contract (W3) specifies `insert into pfin.nav_daily (...) on
conflict (...) do nothing returning nav_id`, run as `service_role` — but 054's
column-level grant on `nav_daily` is `select (users_id, nav_date)` only, added
for the `ON CONFLICT` arbiter (054's own B9 lesson). Nobody had granted SELECT
on `nav_id`, so the verbatim W3 statement is rejected today. My own pgTAP test
helper (`pg_temp.qa_scalar_insert`, mirroring 054's `qa_rc`) hit the identical
error the first time I wrote it with `returning nav_id into v_id` — and its
`exception when others then return null` swallowed the real cause, so the
symptom looked like "the scalar insert silently didn't happen" three
assertions downstream, not like a permission error.

**Why this generalizes:** any table whose writer holds a *narrowed*
column-level SELECT grant (the B9 arbiter-column pattern, now used at both 054
and 107) is a trap for a *future* RETURNING clause naming a column outside
that narrowed set — including the primary key, which is exactly the column a
caller most wants back to decide "did this insert happen."

**A WHERE predicate needs the same grant, no RETURNING involved:** SELF-345/111
(`pfin.audit_log`) test-only-granted `service_role` UPDATE and DELETE to prove
an immutability trigger fires for that role too — no SELECT, since the leg
never reads a column value. `update ... where audit_id = %s` as service_role
still threw `permission denied for table audit_log`, hint `GRANT SELECT ON
audit_log TO service_role`, instead of the expected trigger message — Postgres
needs SELECT on `audit_id` to evaluate the WHERE clause, the write verb's own
grant doesn't cover it. Confirmed by isolated repro (UPDATE+DELETE alone →
denied; add SELECT → the immutability trigger fires as expected). Generalizes
the rule beyond RETURNING: **any DML that reads a column's value at all — in
RETURNING, in a WHERE predicate, in a subquery — needs SELECT on that column,
full stop, regardless of which write privilege the statement's verb needs.**

**How to apply:**
- Before writing (or reviewing) a worker-contract clause that says `RETURNING
  <col>`, check the writer's column-level grant covers `<col>` — don't assume
  INSERT privilege is enough.
- `GET DIAGNOSTICS ... = ROW_COUNT` after a bare `on conflict ... do nothing`
  INSERT is the row-existence/did-it-insert signal that needs NO additional
  grant — prefer it over `RETURNING <pk>` whenever the only thing needed is
  "did a row land," which is 054's own established idiom (`qa_rc`) and now
  107's too (my `qa_scalar_insert`).
- Never let a `when others then return null` pgTAP helper swallow an
  exception without a paired assertion that would surface a different cause
  (the 054 (h11)/(h10) lesson, generalized) — a permission error on the
  wrong column reads identically to "the row didn't insert" until you strip
  the exception handler and run the raw statement by hand.
- Flag a mismatch like this to Architect rather than silently reworking the
  worker's real statement to dodge it — the grant vs. RETURNING pairing is a
  cross-artifact invariant of exactly the same shape as the ON-CONFLICT
  arbiter-column pairing 107's own header already calls out.
