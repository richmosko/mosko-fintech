---
name: a-grep-hit-in-a-comment-is-not-a-call-site
description: A symbol's name appearing in a file does not mean the file calls it — the densest place a symbol appears is often the comment explaining why it is NOT used.
metadata:
  type: feedback
---

Before claiming a surface is **live**, check that the reference is a **call**, not prose about the
call. Grep for the symbol, then read the line's context — and prefer a positive test ("what does
this route actually pass?") over an occurrence test ("does this file mention it?").

**Why:** measured 2026-08-22. I claimed a client-supplied `as_of` was live on the merged §2.2
allocation route because `resolveAllocationAsOf` appeared in `routes/allocation/+page.server.ts`.
It appears there **inside the comment explaining why it is deliberately not wired** — the line
above it reads *"NO `as_of` QUERY-PARAM SUPPORT YET."* Sec measured the routes properly
(`grep -rn "serverTodayAsOf|userSuppliedAsOf" api/src/routes` → four loaders, **all**
`serverTodayAsOf()`) and the claim collapsed. **I had repeated it in four places**, and it was
the load-bearing word in a "did a merged surface exceed a ratified fence?" question.

⚠ **A stale doc comment can seed the same error.** `asOf.ts`'s header called that path *"the
FIRST live path"* — true of intent, false of wiring — and I inherited the word from it. **A
comment is a claim about the world at authoring time**, held to the same standard as any other
(see [[feedback_consequence_list_inherits_its_authors_instrument]]).

**How to apply:** the discriminating query is over the CONSUMER, not the definition — ask "what
do the routes pass?" rather than "where does this name appear?". Then state the finding in terms
of wiring: *built but unreached* is a different claim from *live*, and only one of them supports
a fence-exceeded conclusion. Related: [[feedback_clean_sweep_claim_is_a_claim_about_the_filter]],
[[feedback_spot_check_the_contract_at_its_consumer]].
