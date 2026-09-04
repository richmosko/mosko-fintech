---
name: feedback-independent-reconstruction-shares-blindspot-with-shared-helper
description: An "independently reconstructed" pgTAP leg (assert two derivations of the same fact are equal) is NOT independent of a bug inside a helper function BOTH derivations call — verify what each side actually calls before trusting the pattern.
metadata:
  type: feedback
---

The 105/self257 "independently reconstruct the expected value via a second SQL path, tie it
to the function's own output" idiom (DES-pin, AC5-1 etc.) is only as independent as the two
SQL paths actually are. SELF-269's AC4C leg computed the expected `fn_compute_nav -
fn_nav_composition` gap via `sum(...) from pfin.fn_tax_authority_ledgers() tal join
fn_account_unrealized_gl(...) g ...` — but `fn_nav_composition` ALSO calls
`fn_tax_authority_ledgers()` internally. Inversion-testing (strike the helper's predicate to
`where false`) proved this: the composer's leaf set and my "independent" reconstruction both
lost the SAME term simultaneously, so the equality held and the leg stayed GREEN through a
real regression. 105's own DES-pin caught the same strike — not because it was more
independent (it calls the identical helper), but because it compares the helper's sum against
a HARDCODED LITERAL, not against a second derivation of the same helper.

**Why:** verified by direct inversion test (strike function on a scratch clone, re-run
pg_prove, observe which legs go red) while authoring SELF-269 (2026-09-04) — this session's
own recorded inversion-verification narrative caught it, not inspection.

**How to apply:** before trusting an "independent reconstruction" leg as a real watcher for a
SHARED PRIMITIVE the function-under-test composes on, check whether the reconstruction ALSO
calls that primitive. If it does, it's independent of bugs in the composer's OWN wiring
(the anti-join, the arithmetic) but blind to bugs INSIDE the shared primitive — that primitive
needs its own leg comparing against a literal or a hand-written predicate, not a second call to
itself. [[feedback_verify_causal_mechanism_before_stating]]
