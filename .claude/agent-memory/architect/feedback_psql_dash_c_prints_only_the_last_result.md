---
name: psql-dash-c-prints-only-the-last-result
description: psql -c with several statements prints ONLY the final result set — intermediate SELECTs vanish silently and read as empty tables
metadata:
  type: feedback
---

`psql -c "stmt1; stmt2; stmt3"` sends the whole string as one simple query and **prints
only the last result**. Earlier `SELECT`s produce no output at all — no error, no empty
table, nothing.

**Why:** it bit me twice inside ten minutes on 2026-09-04 while fixturing `104`. An
`insert …; select …;` came back showing only a `count`, and a
`begin; set local role authenticated; select …; select …; rollback;` came back showing only
`ROLLBACK`. Both times my first reading was *"the insert failed"* / *"the role switch
killed the query"* — I was about to debug a fence that was working fine. **A suppressed
result is indistinguishable from a failed one.**

**How to apply:** the moment more than one statement is involved — and always for a
`begin; set local role …; …; rollback;` RLS probe — write the block to a file and run
`psql -f`, which prints every result in order. Reserve `-c` for a single statement. Same
class as [[feedback_failed_grep_looks_like_a_clean_result]]: the instrument's silence is
being read as the world's answer.
