---
name: measure-null-coalesce-fixes-dont-reason-them
description: A coalesce(col, fallback) fix for a "silent pass on NULL" bug must be verified against a live fixture of the exact shape — the column may hold empty string, not NULL, and coalesce doesn't catch that.
metadata:
  type: feedback
---

When a catalog-introspection CI fence has a silent-pass hazard because some
`pg_catalog` column can be absent for a given object shape (e.g. `pg_proc.prosrc`
is documented as NULL for PG14+ SQL-standard-body functions, which store their
body in `prosqlbody` instead), the fix is usually `coalesce(col, fallback_expr)`.

**Do not ship that fix on reasoning alone.** `coalesce` only substitutes when the
column is literal SQL NULL. Verify what the column ACTUALLY holds for the target
shape by building a real fixture of it and querying directly (`select col,
col is null, length(col)`). On this project's pinned PG17, a `language sql begin
atomic ... end` function's `prosrc` measured as an EMPTY STRING (length 0), not
NULL — so `coalesce(p.prosrc, pg_get_functiondef(p.oid))` never fell through, and
the "fix" would have shipped looking correct while remaining exactly as blind as
the bug it claimed to close. The real fix needed `coalesce(nullif(p.prosrc, ''),
fallback_expr)`.

**Why:** documentation/community knowledge about a catalog column's NULL-ness for
an edge-case object shape can be wrong or version-specific. A reviewer (or a
reviewer's own bug report) naming "NULL" as the mechanism is a hypothesis, not a
measurement — and the failure mode (a fix that doesn't fix anything) is invisible
to a code read; it only surfaces when you actually run the fixed query against
the fixture and see the row appear.

**How to apply:** whenever a coalesce/nullif-style NULL-handling fix is the
answer to a fence's own blind spot, add the golden fixture FIRST (or at the same
time), run the exact query against it, and inspect the raw column value before
trusting the fix. This is the same "measure the tree, don't reason from the
report" discipline this project applies everywhere else, aimed at Postgres's own
catalog instead of a teammate's claim.
