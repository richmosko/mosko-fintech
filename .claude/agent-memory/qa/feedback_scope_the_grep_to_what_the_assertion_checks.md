---
name: feedback-scope-the-grep-to-what-the-assertion-checks
description: A "no token X anywhere" verification claim must be scoped to exactly what the pgTAP assertion checks (prosrc only) — a file-wide grep will hit the migration header's own prohibition prose and either false-fail or, worse, pass clean by luck while proving nothing. Caught by architect on the SELF-218 ZN3 leg, 2026-08-12.
metadata:
  type: feedback
---

While restoring a token-based deny-list leg (ZN3, `pfin.fn_nav_series_inflation_adjusted`
zone fence), I verified "no occurrence of these clock tokens" by grepping the whole
migration file — header comments and function body together — and reported it as
checking "both header prose and body." That method is wrong in general, and it only
produced a correct-looking result by luck: the specific tokens I was checking that
round (`statement_timestamp`, `clock_timestamp`, `transaction_timestamp`, `timezone(`)
happened not to appear in the header's own prose. A different token set would not have
been so lucky — this migration's `comment on function` explicitly discusses
`current_date`, `now()`, `localtimestamp` at length, BECAUSE it is the standing
instruction telling a future editor not to introduce them. A file-wide grep for those
same tokens hits that sentence and either false-fails (if you're checking presence-is-
bad) or falsely reports "checked and clean" when what actually happened is you matched
the prohibition, not an evasion — proving nothing about the thing under test.

**Why:** the pgTAP assertion itself only ever inspects `pg_proc.prosrc` — the text
between the function's `$$ ... $$` delimiters — never the migration file's header
comments. A verification claim that says "grepped the file" is checking a superset of
what the assertion checks, and the extra territory (header prose explaining or citing
the very tokens being fenced) is exactly where those tokens are most densely present,
by design. [[feedback_verify_causal_mechanism_before_stating]] names the general
discipline (verify before stating); this is the concrete, mechanical instance of it for
"absence of a token" claims specifically — 062's own header records the same trap under
a different name ("a file that forbids a token will contain that token most densely in
the prose explaining the prohibition").

**How to apply:** before claiming "no occurrence of X anywhere," identify exactly what
the assertion under test reads (a specific catalog column, a specific extracted region,
a specific file section) and scope the verification grep/search to that region only —
never the whole file, the whole migration, or "the codebase." For a plpgsql function
body specifically: extract only the text between the `$$` delimiters (e.g.
`awk '/^as \$\$$/{flag=1;next} /^\$\$;$/{flag=0} flag'` over the migration file, or
read `pg_proc.prosrc` directly from a live catalog) before grepping for evasion tokens.
