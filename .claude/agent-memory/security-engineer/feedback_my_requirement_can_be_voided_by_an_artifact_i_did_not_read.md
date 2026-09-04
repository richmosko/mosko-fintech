---
name: my-requirement-can-be-voided-by-an-artifact-i-did-not-read
description: A round-1 Sec REQUIREMENT ("the escaping control lives in the PDF worker") was made wrong by ARCH §3.2's ratified render direction, which I had not read. A finding that is merely absent costs a re-read; a REQUIREMENT that is wrong sends a builder to build the wrong control.
metadata:
  type: feedback
---

**Before writing a requirement about WHERE a control lives, read the artifact that fixes the data
direction through that surface.** For any cross-container or cross-process control, that artifact is
usually a sequence diagram or a flow section in ARCH, not the ADR that locks the component.

**Why:** at the V1.5 pre-flight I flagged that user free-text reaches two renderers and required
*"the escaping control lives in the PDF worker."* `docs/ARCH/index.html` §3.2's sequence diagram —
which I had not opened — has the worker **pulling rendered HTML from the app** (`PW->>V1: GET
/internal/pdf-render`; `V1-->>PW: Rendered HTML`). Under the ratified direction the worker composes
no HTML at all, Svelte's default escaping is the control, and my requirement would have had Backend
build a control the architecture makes unnecessary. The drafted ACs had inverted the direction, and
I had reasoned from the drafts rather than from the ratified artifact.

**The asymmetry that makes this its own class.** A finding I merely *miss* costs a later re-read.
A **requirement I state wrongly is executed** — it is the output of this role that other agents act
on directly, and it carries my authority. The same reasoning error therefore has two very different
prices depending on whether it lands in a "flag" or in a "requirement". **Requirements need the
higher evidence bar, and the bar is: which ratified artifact fixes this, and did I open it.**

**The tell I should have caught unaided:** I was writing about a hazard *created by the drafts*
(app→worker JSON push) without having checked whether the drafts matched the architecture. When
three drafts agree with each other and I have not checked them against a ratified artifact, their
agreement is evidence of a **shared source**, not of correctness — the same fan-out tell that catches
copied claims. Here all three (A4/A5/P6) inverted the direction identically, which should have read
as one author's assumption propagating, not as three confirmations.

**Second-order lesson from the same pass, and it generalises further: a direction ruling REDISTRIBUTES
risk rather than removing it.** When I backed the option that dissolved the impersonation surface, it
created a new inbound admission channel and put a browser engine in front of network-supplied HTML
(`<iframe src="file:///proc/self/environ">` exfiltrating the container's only secret). **Whenever a
proposed option "makes a hazard disappear", ask what it makes the surface newly reachable BY** — and
check whether the existing fence for that class actually covers the new instance. It did not: the
private-bind fence was written over a *different* worker's compose manifest and located its target by
an in-file sentinel, so the new channel would have come up unfenced.

⚠ **SHARPER VARIANT — I cited a locked constraint AS SUPPORT for an option that the same constraint
FORBIDS, in one sentence.** Recommending "derive supersession instead of storing it", I wrote: *"the
locked partial-UNIQUE already makes 'the current final' unambiguous; `superseded` becomes a
presentation label computed from `(target_month, generated_at)` ordering."* `UNIQUE (users_id,
target_month) WHERE generation_status = 'final'` makes it unambiguous **by permitting exactly one such
row** — so there is never a set to order and never anything to label. Architect caught it. This is
worse than the "artifact I did not read" case above: **I had read the constraint, quoted it, and
leaned on it — I just never evaluated my proposal AGAINST it.**

- **The mechanical check: whenever I cite a constraint as SUPPORT, run my own proposal through it as
  if it were someone else's.** Citing and testing are different acts and the citation feels like the
  test. A constraint quoted in favour of an option is the one place nobody re-checks, because it
  reads as already-checked.
- **Both escape hatches were disqualifying, and one was invisible.** Retiring the index = the
  amendment I claimed the option avoided. Inserting every row in the non-final state = the index
  **never fires on any row** — a locked uniqueness constraint reduced to a dead one, which is the
  *constraint that cannot fail* shape I flag in others, reached by my own proposal. ⚠ **A dead
  constraint looks identical to a working one**, so this route is strictly worse than a recorded
  amendment. When an option preserves a constraint's TEXT, ask whether it preserves the constraint's
  ability to REJECT anything.
- **The reframe worth keeping, because it dissolved the problem:** I was defending a blanket phrasing
  (*"UPDATE/DELETE blocked"*) that the lock's own vocabulary (`draft → final → superseded`) already
  contradicted — a stored state machine needs an UPDATE to move. **When a lock's blanket rule and its
  own mechanism disagree, the mechanism is the binding fact.** The question was never how to avoid an
  UPDATE; it was *where the mutability window closes and what fences it*.
- **Concede straight when the objection is mechanical.** Hedging a wrong lean costs more than the
  lean did — and having conceded, look HARDER at the winning shape, not less: a restatement of a
  two-verb rule (`UPDATE/DELETE`) had quietly become one-verb, which is the enumeration-stops-one-short
  class landing inside the option I had just agreed to.

**How to apply:**
- Before a where-does-the-control-live requirement: grep ARCH for the endpoint/route name and read
  the flow section, not only the ADR that locks the component. `grep -n 'PW->>\|-->>' docs/ARCH/*.html`
  finds direction in seconds.
- Before recommending a mechanism on a table, enumerate the table's locked constraints and walk the
  mechanism's SECOND invocation through each — the first invocation almost always passes, and
  regeneration/retry is where a uniqueness constraint bites.
- When retracting, **say "retracted" and say which artifact voided it**, in the same message as the
  new findings — a requirement quietly dropped between rounds is indistinguishable from one still
  live, and a teammate may already be building against it.
- Keep the direction-independent half. Mine survived intact: *"every free-text field is escaped by
  whatever composes the HTML, and it is asserted on the RENDERED OUTPUT."* Separating the invariant
  from the placement is what makes a retraction cheap — state controls as invariants plus a placement,
  so a direction ruling only invalidates the placement.
- When backing an option, name the risk it CREATES as well as the one it removes, and check the
  covering fence's actual target — a generic fence script invoked against one path is not coverage of
  a second path.

Related: [[hazard-mechanism-vs-reachability]] · [[replacement-control-name-the-losing-side]] ·
[[verify-the-cited-source-subsection-not-the-headline]] · [[adding-vs-qualifying-verification-asymmetry]] ·
[[clearance-conditions-must-absorb-my-own-recommendations]]
