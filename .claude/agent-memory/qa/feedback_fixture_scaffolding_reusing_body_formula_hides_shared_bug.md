---
name: feedback-fixture-scaffolding-reusing-body-formula-hides-shared-bug
description: When a function under test derives dates/values internally (no test-controllable parameter), the fixture MUST compute where to seed data using the SAME expressions the function's body uses — that's legitimate scaffolding. But if the arithmetic-correctness legs stop there, a shared mistake in that formula is invisible to the whole battery. Architect caught this on SELF-221's 071 battery; I added independent-arithmetic legs to close it, proven with a corrupt-the-control run before finalizing.
metadata:
  type: feedback
---

Authored the pgTAP battery for `pfin.fn_nav_delta_panel` (071), which takes NO
parameters and derives "today"/anchor dates internally via
`date_trunc`/interval arithmetic. Since the battery can't pin an arbitrary
fixed date, I computed the SAME anchor dates in the fixture-setup SQL using
literally the same expressions the migration body uses, to know where to seed
checkpoints — reasonable, since knowing WHICH date is the anchor isn't itself
the thing under test (the CPI/NAV arithmetic and NULL-cause logic are).

**What I missed:** the crux arithmetic legs then asserted `delta_inflation_adjusted`
against hand-computed values using checkpoints placed at those
formula-derived dates. If the migration's month-end formula had a shared
bug (e.g., a leap-year or year-boundary off-by-one), BOTH my fixture
placement and the function's own anchor resolution would use the SAME wrong
date — the checkpoint I placed would still be exactly where the function
looked for it, and the arithmetic leg would pass, having verified nothing
about whether the anchor date itself was objectively correct.

Architect named this precisely in the migration header before I'd have found
it myself: *"Do NOT compute the expected anchor with the body's own
expression — a shared mistake in month-end derivation would then be
invisible, which is testing the implementation against itself."*

**Fix:** added three separate legs verifying `anchor_date` (read from the
function's OWN output, not predicted) using `extract()`-based integer
arithmetic on year/month/day components — a genuinely different code path
from the body's `date_trunc`/interval construction, not just a re-typed copy
of it. **Proved they weren't vacuous before finalizing**: temporarily swapped
in a throwaway copy of the function with the YTD anchor deliberately off by
one day, re-ran the battery — exactly the new anchor leg failed, all others
stayed green. Restored, re-confirmed clean.

**How to apply:** whenever a battery's fixture-setup has to replicate a
function body's own date/value-derivation formula to know where to place
data (true for any parameterless function deriving state internally), treat
that replication as scaffolding ONLY — then add a SEPARATE set of legs that
verify the derived values using independently-chosen arithmetic (different
built-ins, different reasoning path), checked against what the function
itself reports, not against a value computed from the same formula. This is
the general form of [[feedback_verify_causal_mechanism_before_stating]] and
the zone-invariance-inversion-control pattern (062/069's `(V)` legs) applied
to date-derivation formulas specifically. Corrupt-the-control before calling
it done — an un-exercised "independent" leg is not proven independent.

**Round 2, same item — my first fix was still incomplete.** I closed the gap
with `extract()`-based checks (reading year/month/day components and
comparing to literals). Architect re-reviewed and found `cpi_basis_period`
— a SEPARATE output column, fed by the single most convoluted expression in
the function (`date_trunc('year') - 1 year + 11 mon`) — had NO independent
leg at all; I'd covered `anchor_date` but missed a whole other field derived
by different, harder-to-get-right arithmetic. Also: Architect wanted
`make_date()` specifically over `extract()`-based comparison for the two
date-reconstruction checks, reasoning that `make_date` *builds* a date from
components and shares zero machinery with the body's `date_trunc`/interval
chain, where my `extract()` approach — while independent in spirit — was a
less clean demonstration of that independence. **Two lessons stack here:**
(1) "I added an independent check" is a claim about ONE field; audit EVERY
output field a formula feeds, not just the most obvious one (the field name
in the RETURNS TABLE, not just the one named in the header's worked
example). (2) When a reviewer names a SPECIFIC alternate primitive
(`make_date` vs `extract`), matching it exactly closes the review faster
than defending a functionally-similar-but-differently-shaped substitute —
the second round of back-and-forth here was avoidable by using their literal
suggestion the first time.
