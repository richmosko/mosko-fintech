---
name: bare-numeric-admits-infinity
description: A bare `numeric` column accepts ±Infinity and the repo's two-sided NaN CHECK does not catch it — the TYPMOD is what refuses Infinity, so the two halves close different values and neither alone closes the non-finite surface
metadata:
  type: reference
---

**`numeric` with no typmod ACCEPTS `'Infinity'::numeric`. The repo's rider-8 /
`090` two-sided NaN CHECK does not refuse it.** Measured at `101`
(SELF-259) on a scratch DB:

- `bracket_floor numeric(20,4)` + `'Infinity'` → `numeric field overflow —
  A field with precision 20, scale 4 cannot hold an infinite value` (refused at
  **coercion**, before any CHECK runs).
- The same value in a **bare** `numeric` column coerces fine, and then
  `Infinity >= 0` is TRUE and `Infinity <> 'NaN'::numeric` is TRUE — so the
  canonical idiom `check (x >= 0 and x <> 'NaN'::numeric)` **admits it**.

**The two halves close different values and neither alone is sufficient:**

| value | refused by |
|---|---|
| `NaN` | the explicit `<> 'NaN'::numeric` literal (a one-sided `>= 0` admits it — NaN sorts ABOVE every non-NaN numeric) |
| `±Infinity` | the **typmod**, at coercion |

**Why:** `090`'s header states the reasoning correctly — *"the typmod refuses
±Infinity at coercion … so the non-finite value that still reaches a CHECK is
NaN"* — but that sentence is **conditional on a typmod being present**, and the
condition travels badly. The SELF-259 AC carried the CHECK forward while writing
the columns as bare `numeric`, which silently voids the Infinity half. The
premise got dropped and only the conclusion was copied.

**How to apply:**
- Any new `numeric` money/rate column: **declare a typmod**, and say in the
  header that the typmod is carrying the Infinity half. Do not let it read as
  cosmetic precision — a later "simplify to `numeric`" removes a fence.
- When an AC or a sibling migration hands you the NaN CHECK, **check the column
  type in the same glance.** The idiom is only half a control.
- ⚠ **A typmod that is too tight moves the rejection to the wrong fence.** At
  `101` a `bracket_rate numeric(9,8)` would have refused a mis-typed `22` as a
  numeric overflow — correct, but with a message that never mentions the unit.
  Declared `(12,8)` deliberately so the value coerces and the **domain CHECK**
  refuses it. *The fence that fires should be the one that can explain itself.*

Related: [[watcher-not-fence-for-by-construction-properties]] ·
[[check-violation-reported-in-constraint-name-order]] ·
[[scope-the-invariant-before-writing-it]]
