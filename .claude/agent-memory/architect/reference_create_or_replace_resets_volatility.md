---
name: create-or-replace-resets-volatility
description: CREATE OR REPLACE FUNCTION replaces the WHOLE definition including volatility, so it silently erases an ALTER … STABLE pin — with every test still green.
metadata:
  type: reference
---

`ALTER FUNCTION … STABLE` changes only `pg_proc.provolatile`; it preserves the
body, the ACL and the catalog comment (so it does **not** hit the `072`
DROP+recreate trap where grants vanish and the function lands PUBLIC-executable).

⚠ But **`CREATE OR REPLACE FUNCTION` replaces the entire definition, volatility
included.** A body-fix migration issued after a pin migration erases the pin. A
body-fix migration issued *before* it is fine. This makes the two
order-dependent in a way nothing in the SQL reveals.

**It is invisible to value assertions.** Volatility changes no output for any
input, so a battery that compares numbers passes identically whether the pin is
present, absent, or was applied and then silently reverted. The only leg that
discriminates is structural: assert `pg_proc.provolatile = 's'` **per signature**.

**Two more traps met at `079`:**
- One *named* function can be several catalog signatures. `fn_compute_nav` is
  `(date, boolean)` and `(date)`; pinning only one leaves the surface most
  callers reach declared VOLATILE. Pin per signature, and say so.
- A STABLE function calling a VOLATILE one is a promise its own callee does not
  back: in READ COMMITTED the VOLATILE callee re-establishes a snapshot instead
  of inheriting the calling statement's. So pinning the outer functions does
  **not** by itself deliver a statement-snapshot guarantee — name the unpinned
  callee closure rather than implying the pin is the whole answer. A *partial*
  closure is worse than none; it looks complete and moves the seam somewhere
  less obvious.

Related: [[feedback-watcher-not-fence-for-by-construction-properties]],
[[feedback-assertion-with-no-watcher]].
