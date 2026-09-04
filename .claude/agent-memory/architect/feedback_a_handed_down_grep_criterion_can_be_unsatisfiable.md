---
name: a-handed-down-grep-criterion-can-be-unsatisfiable
description: An acceptance criterion of the form "grep -c X = 0" is a claim about the whole corpus, and correct content can hold X as a substring — report the residual, never edit the content to satisfy the count.
metadata:
  type: feedback
---

A dispatch brief may hand you a verification criterion like `grep -c '500,000\|500000' <file>` **= 0**.
Treat it as a hypothesis about the corpus, not as a target to hit.

**Why:** at SELF-260 that exact criterion was unsatisfiable. `500000` occurs as a
substring of two *correct* seeded rate literals — `0.35000000` and `0.15000000` —
so the count was 2 with every trace of the false claim already struck. Forcing
the number to 0 would have meant editing published tax figures to satisfy a grep.
The mirror case landed in the same file: `grep -c 'Mental Health' = 0` **was**
reachable, but only by dropping the superseded name from the sentence that
*records the rename* — trading a supersession-visible note for a clean instrument.
That trade was fine only because the file was unmerged.

**How to apply:** when a handed-down count does not come out, first ask whether
the pattern can match content that is supposed to survive. If it can, run the
predicates that actually target the finding (`$500`, `500,000`, and the claim's
own words) and report **both** — the specified count with its cause, and the
tight ones at 0. Say plainly which lines produce the residual so nobody
"fixes" them. If the count *is* reachable but only by weakening the text, name
the trade in the report rather than taking it silently.

⚠ Also run the criterion **case-insensitively** before reporting 0: an all-caps
header occurrence (`MENTAL HEALTH SERVICES TAX`) is invisible to the literal
pattern the brief hands you, and reporting the literal count as clean would have
been wrong.

Related: [[clean-sweep-claim-is-a-claim-about-the-filter]],
[[failed-grep-looks-like-a-clean-result]],
[[count-over-history-vs-live-definitions]].
