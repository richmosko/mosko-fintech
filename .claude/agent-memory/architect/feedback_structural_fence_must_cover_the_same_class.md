---
name: structural-fence-must-cover-the-same-class
description: Replacing a deny-list with a structural property is only an upgrade if it covers the SAME class — otherwise it silently removes a watcher while looking like a strengthening
metadata:
  type: feedback
---

"An enumeration is exhortation wearing a regex" is true, and it is **not** a licence
to replace any deny-list with the nearest structural property. **Check that the
structural property covers the same class first, and if it does not, add it
ALONGSIDE rather than instead.**

**Why:** SELF-218, 2026-08-12 — my own error, caught by Sec at joint-review. QA's
`067` battery had a token leg asserting the function body contained no clock read
(`current_date` / `now()` / …). I recommended replacing it with a structural leg
asserting **no date arithmetic** (`date_trunc` / `interval` / `::timestamp`), and
called the replacement stronger.

It was stronger *for its own class* and **absent** for the other. A body containing
only `where x <= current_date` has no date arithmetic and no `timestamptz` — it
passes both legs cleanly. The migration header explicitly instructs a future editor
not to introduce those tokens, and my change left that instruction **with no
watcher** — which is precisely what the deny-list existed to be.

**How to apply:**
- Before swapping a fence, write down the set the old one caught and the set the new
  one catches. If they are not the same set, the swap is a **coverage change wearing
  a refactor**.
- The failure is hard to see because the structural form genuinely *is* the better
  instrument for its class. **That local superiority is what makes the substitution
  look like an upgrade** rather than a trade.
- Two classes → two legs. The structural leg still earns its place; it just does not
  inherit the other's job.
- ⚠ Related asymmetry: a **removed** watcher fails silently and forever, while a
  redundant watcher costs one assertion. The cost is not symmetric, so bias toward
  additive.
- Same principle in the other direction: when a hazard is currently prevented by a
  fence in a **different file**, a spec requirement telling a future author to
  preserve it is exhortation. Prefer a guard clause that makes the dependency moot —
  fold it into whichever migration touches that fence, rather than standing alone.

Related: [[fixture-is-shared-state]] · [[rls-qual-privilege-semantics]]
