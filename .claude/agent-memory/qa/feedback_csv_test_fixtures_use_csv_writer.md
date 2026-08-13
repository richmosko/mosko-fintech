---
name: feedback-csv-test-fixtures-use-csv-writer
description: Building synthetic CSV test fixtures with naive f-string joins instead of csv.writer produced an unquoted internal comma that csv.DictReader silently mis-split, reading as a 10x-class scaling defect in the code under test rather than a fixture bug. Caught by Backend's traced-by-hand repro, SELF-217 nav_backfill tests, 2026-08-12.
metadata:
  type: feedback
---

Wrote a pytest CSV fixture helper as `lines.append(f"{d},{v}")` — plain string
joining — instead of using Python's `csv` module to write it. One test's `v`
was `"$1,234.5"` (a thousands-comma-and-cents case, deliberately chosen to
exercise that formatting), which contains an internal comma. Written naively,
that comma is indistinguishable from the field DELIMITER, so
`csv.DictReader` reading it back split it into two fields — the `NAV ($K)`
column bound to `"$1"` instead of `"$1,234.5"`, and the test failed with
`Decimal('1000') == Decimal('1234500')`, which reads exactly like a 10x/1000x
scaling defect in the parser under test rather than what it actually was: a
malformed fixture.

**Why this is dangerous specifically:** the failure mode LOOKS like precisely
the class of bug these tests exist to catch (a units-scaling error), so a
reader (including me, initially) can spend real time suspecting the
implementation before suspecting the fixture. Backend caught it by tracing
their own function BY HAND against the same input and getting a different,
correct answer — which is what actually surfaced that the fixture, not the
code, was wrong.

**How to apply:** any time a test fixture is HAND-CONSTRUCTED text in a
format that has its own escaping/quoting rules (CSV, JSON via string
concatenation, shell command lines, SQL literals built by hand instead of
parameterized) — use the real serializer for that format (`csv.writer`,
`json.dumps`, `shlex.quote`, a parameterized query) rather than string
interpolation, even for "obviously simple" fixture values. A fixture value
chosen specifically to exercise an edge case (a comma, a quote, a special
character) is exactly the value most likely to break naive string assembly of
the format meant to contain it. [[feedback_verify_causal_mechanism_before_stating]]
— the general form: when a result looks like it confirms the hypothesis you
were testing for, check whether the INSTRUMENT (here, the fixture writer) is
sound before trusting what it reported.
