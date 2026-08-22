---
name: layers-green-seam-absent
description: Unit-tested layers each pass while the connection between them is missing — a green suite proves each piece works alone, never that the feature works
metadata:
  type: feedback
---

**A full green suite over stub-tested layers says nothing about whether the layers are
CONNECTED.** Twice on one branch (SELF-325, 2026-08-21), every layer was individually complete
and green while the seam between them was absent:

1. **No browser-facing endpoint existed.** Three rounds shipped an admission client, a worker
   route and a query module — with no way for a page to reach any of them. Backend caught it
   themselves in round 3.
2. **A query module had ZERO callers.** `selectableAssets.ts` shipped in round 1 and nothing
   ever called it; `load()` never returned it, so the picker it fed rendered empty. Four rounds
   passed. **1355 tests green throughout.**

**Why:** each layer unit-tests against stubs, so nothing exercises `load() → component` or
`route → client → worker`. **The seam is the one thing no layer's tests can see, because it is
by definition not inside any layer.**

**How to apply:**
- ⚠ **"The suite is green" and "the feature works" are different claims.** Never report the
  first as evidence of the second. State which one you measured.
- **Grep for CALL SITES of any new module before believing it is wired** —
  `grep -rn '<exportName>' <src> | grep -v '<its own file>'`. Zero callers is a shipped module
  that does nothing, and it looks identical to a finished one in every review and every suite.
- **Walk the feature end-to-end in a browser before the PR opens.** On this branch it was the
  only instrument that caught either seam — and it caught both by accident, from whoever
  happened to be standing at the seam.
- **The person on the far side of a seam has the view.** Frontend flagged both instances; the
  layer authors could not see them from inside their own layers. Treat a seam report from a
  downstream consumer as high-signal, and verify it from the tree rather than relaying it.
- **A defensive default (empty array, null) keeps the page rendering — and hides the gap.**
  Correct for robustness, but it converts a loud failure into a silent one. Pair it with a
  report, never rely on it alone.

Related: [[feedback_spot_check_the_contract_at_its_consumer]] ·
[[feedback_assertion_with_no_watcher]] ·
[[feedback_instrument_cannot_observe_the_property]]


---

**⚠ THE VARIANT THAT CAUGHT ME: I APPLIED THIS RULE DOWNSTREAM AND NOT TO MY OWN SPEC.**

Same branch (SELF-325, 2026-08-21), two drains after writing the rule above. I ruled that a
signal must render on *"the account-detail holding view"* — **and no holding view existed.**
`heldSecurities` was loaded on that page and had exactly one consumer: a stock-split picker.

⚠ **I had measured `loadHeldSecurities` closely** — established it returns quantity-only, and
that it had one production caller. **I checked that the data was LOADED and never that it was
RENDERED.** That is the identical defect I had just reported in someone else's code.

**The generalisation worth keeping: a CATCH CRITERION is a spec, and a spec asserts that its
surface exists.** *"The user must see X on screen Y"* silently claims screen Y exists and
renders that class of thing. **Verify the render site the same way you verify a call site** —
`grep` the component for the data, not just the route's `load()` for the field.

⚠ **Being the one who wrote the rule is not protection.** I authored the call-sites lesson and
then violated it in the next artifact I produced, because I was checking a teammate's layer and
not my own instruction. **Apply your own rules to your own output first — the person most
convinced a rule is handled is the one who just wrote it down.**

Found, again, by the teammate standing at the seam.


---

**⚠ THREE WAYS A GREEN TEST WAS THE PROBLEM, ALL ON ONE BRANCH (SELF-325, 2026-08-21).**
Collect them together — separately each looks like bad luck; together they are one argument.

1. **Two suites either side of an untested wire.** Both sides passed against their own declared
   contract; neither serialized. A totally broken production path shipped green.
2. **Mocks encoding the type's false belief.** Every `assetId` mock was a `number` because the TS
   type said so. **The mocks and the type were wrong in the same direction**, so they agreed
   perfectly and the suite confirmed the error.
3. ⚠ **An expectation asserting the defect.** A regression test asserted the *wrong* error message
   — green, and **locking the false behaviour in place.** Worse than no test: no test leaves a bug
   findable; a test asserting the bug makes the CORRECT fix look like a regression, so the next
   person to notice reds a test and concludes they were wrong.

**Why (3) happens, and it is not carelessness:** the test was written *after* the code, asserting
what the code did. **A test derived from observed behaviour cannot distinguish intended from
accidental — it records both faithfully.** The only defence is deriving the expectation from what
*should* happen, which requires someone to decide that separately from the implementation.

**The counter that worked:** assert that the OTHER branch's message does **not** appear. A test
checking only for its expected string passes just as happily when both render — so "the right
thing happened" and "only the right thing happened" are different assertions, and only the second
proves branches are distinct.

⚠ **Corollary for reviewing a fix:** when someone fixes a bug and the test count does not change,
ask whether an existing expectation was *corrected*. If so, that expectation was previously
asserting the defect — worth knowing, because it means the suite was defending it.
