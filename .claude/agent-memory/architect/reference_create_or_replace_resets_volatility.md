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

**⚠ And it does not replace at all when the PARAMETER LIST changes — it ADDS AN
OVERLOAD.** A function's identity is its signature, so `create or replace` with a
new argument creates a second function beside the first. On a clean chain apply
only the new one exists and every check is green; on a database where the earlier
version of the same *file* was already applied, both exist. Measured at `101`
(SELF-260 V-2, adding `p_schedule_label`): one overload after a fresh 001→101
apply, which is exactly the state that hides the problem. When an unmerged
migration's function gains or loses a parameter, say so in the apply brief and
name the old signature to drop — a clean-apply verification cannot observe this.

**⚠⚠ WHEN THE DROPPED PARAMETER WAS THE VULNERABILITY, THE SURVIVING OVERLOAD IS
THE UN-FIXED HOLE — and PostgREST reaches it DELIBERATELY, not ambiguously.**
PostgREST resolves an RPC overload **by the request-body KEYS**, so an attacker
who keeps posting the old parameter name is *routed to the old function*. The
source reads as fixed, the review passes, the database is untouched. Met while
preparing the `111` `p_trigger_source` removal (2026-09-05): removing a
caller-supplied provenance argument from a `SECURITY DEFINER` helper granted to
`authenticated` is worthless without an explicit
`drop function if exists <old exact signature>` **before** the CREATE. Pair it
with a catalog assertion that the name resolves to exactly ONE `pg_proc` row —
"the new signature exists" is not the same claim.

⚠ Two sibling edits are easy to miss on a parameter change and both fail *after*
the function is created, so re-running the file reports a misleading
already-exists error from an earlier statement instead of the real one: the
`revoke`/`grant` lines **and the `comment on function` line**, each of which names
the full signature.

⚠ `returns table` is the mirror image: `create or replace` **cannot** change the
returned column list at all and errors instead, so that one fails loudly.

Related: [[feedback-watcher-not-fence-for-by-construction-properties]],
[[feedback-assertion-with-no-watcher]].
