---
name: feedback-data-modifying-cte-must-be-top-level-not-nested-in-is
description: A WITH clause containing UPDATE/INSERT...RETURNING cannot be nested inside a pgTAP is() scalar-subquery argument — Postgres rejects it; promote to a top-level WITH...SELECT + \gset, then a separate is() call.
metadata:
  type: feedback
---

Drafting an idempotency leg for SELF-263's `100` battery, the natural shape was
`select is((with u as (update ... returning 1) select count(*) from u), 0::bigint, '...')`
— a data-modifying CTE nested inside `is()`'s first argument. pg_prove rejected
every leg written this way: `ERROR: WITH clause containing a data-modifying
statement must be at the top level`.

**Why:** Postgres only allows a data-modifying CTE (UPDATE/INSERT/DELETE ...
RETURNING inside a WITH) when the WITH is the TOP-LEVEL clause of the query sent
to the server — not when the whole `WITH ... SELECT` is itself a scalar subquery
nested inside another statement's argument list (here, `is()`'s first arg).

**How to apply:** when a leg needs to count rows a data-modifying statement
affects (an idempotency check, a "this write touched exactly N rows" proof),
issue the `WITH ... SELECT ... AS foo_affected \gset` as its OWN top-level psql
statement, then a SEPARATE following `select is(:foo_affected::bigint, 0::bigint,
'...')` call. Cast the `\gset`-captured variable explicitly (`::bigint`) —
psql's substitution is untyped text, so an uncast `:var` defaults to `integer`
and `is()` then fails to resolve against a `0::bigint` expected value
(`function is(integer, bigint, unknown) does not exist`).

Caught by pg_prove, not by reading — never verify a battery locally with bare
psql alone ([[feedback_scratch_db_pgtap_harness_gotchas]] item 7's sibling
gotcha: another psql-vs-server-parsing mismatch that only a real run surfaces).
