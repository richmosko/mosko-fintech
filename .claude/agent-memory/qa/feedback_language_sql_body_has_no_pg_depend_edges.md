---
name: language-sql-body-has-no-pg-depend-edges
description: Sec FLAG (099, 2026-09-03) — a `language sql` function's body is stored as opaque TEXT; PostgreSQL records NO pg_depend edges for functions/relations it calls from that text, so a `not exists (select ... from pg_depend ...)` "no reference to X" leg is vacuously true for EVERY body and can never fail. Read prosrc directly (regexp) for a callee-identity pin instead.
metadata:
  type: feedback
---

Wrote a 099 pgTAP leg (X1b) asserting `not exists (select 1 from pg_depend d where d.objid =
'pfin.fn_cashflow_contributors(date)'::regprocedure and d.refobjid = <two specific pfin.fn_*/view
oids>)`, labeled "the catalog-level proof, not merely a text-absence proof" — i.e. claimed as
STRONGER than the sibling text-grep leg (X1a). Sec measured on a scratch chain-apply that this is
backwards: `fn_cashflow_items` itself (a `language sql` function that reads FOUR relations) shows
**zero** `pg_depend` rows. Unlike a VIEW (whose defining query IS parsed into a stored rule, giving
real dependency edges) or a C-language function's fmgr call, a plain SQL-language function's body
is just a string in `pg_proc.prosrc` — Postgres never parses it at CREATE time to register which
objects it references, so there is **no dependency-tracking mechanism at all** for what a
SQL-language function calls. The leg's `not exists (...)` predicate was therefore true for every
conceivable body, honest or not — a leg that cannot fail, which is worse than useless: it
implicitly overstates the sibling text-based leg's own strength by implying a second,
stronger, catalog-level check backs it up.

**Fix pattern (Sec Option A, applied): read `prosrc` directly with a regex, not `pg_depend`.**
`select array_agg(distinct m[1] order by m[1]) from pg_proc p, regexp_matches(p.prosrc,
'fn_[A-Za-z0-9_]+', 'g') as m where p.oid = '<target>'::regprocedure` — asserted equal to the
exact expected callee set. This is STRICTLY STRONGER than a substring-denylist check (catches ANY
second callee, not just three named forbidden tokens) and correctly reads the one thing Postgres
actually stores for a SQL-language function: its source text.

**How to apply:** for any future "this function does not call X" pgTAP leg on a `language sql`
function, do NOT reach for `pg_depend` — it will pass vacuously. Use a `prosrc`/`pg_get_functiondef`
text check (ideally a positive allowlist-pin via regex over the full identifier set, not just a
few denylisted substrings) and say so in the leg's own description, so a future reader doesn't
"upgrade" it back to a pg_depend check believing that's the stronger route.

**Inversion-verify this class of leg specifically**, not just trust that it "looks catalog-level":
doctor a scratch copy of the function to genuinely call a second helper (savepoint, rollback after)
and confirm the leg goes RED. A `pg_depend`-based "no reference" leg will stay green through that
doctoring — that IS the tell that it can't fail, and is the check that would have caught this
before Sec did. [[feedback_inversion_test_the_rationale_not_the_presence]] — same discipline,
now with a concrete Postgres-catalog mechanism behind it.
