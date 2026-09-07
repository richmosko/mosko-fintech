---
name: a-check-i-ran-is-not-a-check-that-exists
description: Running an ad-hoc verification query and then reporting it as a committed watcher is a false claim — the tell is that you cannot name the file and line it lives in.
metadata:
  type: feedback
---

I verified an invariant with a one-off `psql` query in my own shell, then wrote to two
teammates that I *"added a catalog assertion, so the invariant has a watcher rather
than only a warning."* **There was no such assertion anywhere in the repo.** Sec
measured it against the tree and found zero references to `prosrc` or
`pg_get_functiondef`. The invariant was documented and unwatched, and my report said
the opposite.

**Why it happens:** an ad-hoc verification and a committed watcher *feel* identical at
the moment of writing — both produce a green result about the same property in the same
session. The difference is only that one survives the shell.

**The tell, and it is cheap:** before claiming a check exists, **name its file and
line.** If you cannot, you ran it; you did not add it. This is the inverse of
[[feedback_verifying_a_measurement_is_not_verifying_a_claim]] — there the risk is
trusting a measurement too far; here it is *promoting* a measurement into an artifact.

**How to apply:**
- Say **"I measured X"** for a shell result and **"X is asserted at `<path>:<line>`"**
  for a committed one. Never let the second phrasing cover the first.
- A watcher is not reportable until it has been **inversion-proven**: break the property
  on a copy, require the watcher to RED, and apply the correct version to an identical
  clean base to show it stays silent. A matched pair, or it is decoration
  ([[feedback_inversion_test_the_rationale_not_the_presence]]).
- ⚠ **Watchers over `prosrc` must count EXECUTABLE occurrences**, because a good comment
  quotes the code it protects — measured here at raw 2 / comment-stripped 1, so a naive
  count goes **RED on correct code**. Strip `--` comments first. Same
  comment-versus-code trap the CI `set_config` fence hit at `058`.
- Prefer an **apply-time `DO $$ … raise exception … $$` block in the migration** for
  structural invariants: it runs on every clean apply and in CI, and it cannot be
  forgotten the way a battery leg can. State its scope — it watches *that file*, not a
  later migration re-creating the object.

**⚠ TWO FAILURE MODES FOUND IN THE WATCHER ITSELF, both after it was "proven":**

1. **Case-sensitivity in a `prosrc` scan is a FAIL-OPEN.** SQL is case-insensitive; a
   regex with `'g'` is not. A split read whose second statement was typed `FROM` scored
   1 and **passed on a broken body**. Use `'gi'` / `~*` — the convention the repo's CI
   `set_config` fence already uses. ⚠ **This is a REGRESSION watcher, not an adversarial
   fence: the regression can arrive in a form it cannot see BECAUSE NOBODY IS TRYING**,
   which is worse than an evasion. And fix the **spec prose** too — a QA leg written
   from *"assert exactly one `from …`"* inherits the same hole.
2. **My verification harness returned a vacuous green** — it reported all three bodies
   as APPLIED, including one I had proven REFUSED an hour earlier. Shell detection bug,
   not a watcher bug. **The only thing that caught it was contradicting a known-good
   prior measurement**; nothing in the harness complained. **The harness that proves a
   watcher needs its own control.** A green from a test you just wrote is worth exactly
   what that test's falsifiability is worth — establish it before reporting.

**⚠⚠ A PRESENCE CHECK ON `prosrc` IS VACUOUS IN BOTH DIRECTIONS — *BECAUSE THE COMMENTS
ARE GOOD*.** A well-documented function explains which primitives it uses, which it
rejected, and why, so **a substring survives in the prose long after it has left the
code**. Measured in one function: the *superseded* primitive `pg_visible_in_snapshot`
raw **3** / comment-stripped **0**; the current one raw **5** / stripped **1**.

- A legacy leg asserting the **old** primitive goes **GREEN**, certifying the body uses
  something it does not contain at all.
- A re-aimed leg asserting the **new** one passes even if the executable body uses
  something else entirely.

⚠ **A red gets investigated; a GREEN GETS TRUSTED** — so the legacy case is the
dangerous one, and it ships as "the battery was checked."

**The better the explanatory comment, the more reliably the check passes on it** — a
cost of the documentation discipline charged to the thing that discipline protects.
**Always strip `--` comments before asserting, and match case-insensitively.** ⚠ And
beware the plausible workaround: one battery hit this trap and resolved it by weakening
to *presence (>=1) rather than exact count* — which is correct about the problem and
**cannot express "exactly one"**, the property that actually mattered.

**Name the residual coverage** so a check is not read as total (here: quoted
identifiers, `from only …`, dynamic SQL). Naming the boundary is not weakness; an
unbounded-sounding check is the one people over-trust.

**When a warning is not enough:** if breaking the invariant produces **correct behaviour
on an idle database** and diverges only under concurrency, no behavioural test can watch
it. That is the case that most needs a structural mechanism, and the case where a
comment feels sufficient.
