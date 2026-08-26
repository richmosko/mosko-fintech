---
name: an-unblocking-fix-unmasks-every-input-class
description: When a fix makes a universally-failing path start succeeding, the old failure was acting as a fence over EVERY input class — re-check each one, because the fix un-masks whatever the block was hiding
metadata:
  type: feedback
---

When a fix turns a path that **always failed** into one that **succeeds**, the old failure was an
accidental fence over *every* input class that path accepted. Enumerate those classes and walk each
one through the new success path. The fix is validated against the class it was written for; the
others ride along unexamined.

**Why:** PR #567 fixed `reverseAndReplaceTrans`'s batch insert (PostgREST's union-of-keys sent an
omitted `quantity` an explicit NULL against a `NOT NULL` column, so **every** Edit failed — a real,
month-old P0). The fix declared a full matching key set on both rows, hardcoding `corrected` to
`security_id: null, quantity: 0`. Correct for cash rows, which is what it was written for and what
the walk gate drove. But a **securities** original reversed `−Q` shares of asset `S` and the
corrected row added nothing back: **the position silently vanished, and the call returned
`{ok: true}`.** Pre-fix that same row hit the `NOT NULL` violation and hard-failed. The NOT NULL
violation had been fencing securities rows for free. Un-masked, the path was reachable in one click
(`TransactionRow.svelte` gates Edit on `!frozen` **only**), unrecoverable (immutable ledger; the
double-edit guard blocks re-editing the original; the edit schema has no field to restore quantity),
and reported success. That is a VETO, not a flag — money-critical **and** silent **and** no
user-reachable repair.

**⚠ The paired test asserted the defect, on a premise that reads like verification.** It pinned
`ok: true` for a security-linked original and commented *"This is documented/existing behavior, not
new to this fix."* Measurably false: pre-fix that case **threw**. What was documented was the CODE
SHAPE (via a stale `quantity 0 default` comment naming a DB default a batch insert never reaches);
the OUTCOME had never once occurred. **"Existing behavior" is a claim about what the system DID, not
about what the code said it would do — and on a universally-failing path there IS no existing
behavior to preserve.** Whenever a test comment says "pre-existing, asserted so we don't change it",
check whether that branch was ever reachable before. Related:
[[hazard-mechanism-vs-reachability]].

**The generalisation worth carrying.** A defect that blocks a path is also a control over it. Before
clearing an unblocking fix, ask: *what did the failure prevent that the success now permits?* Enumerate
by the path's own input dimensions (here: cash vs securities; also worth checking `transaction_type`
∈ acct_setup / basis_adjust / corp_action, and split-parent — which this PR did separately catch).
Then check each against the fences that remain: I walked the `017` cash CHECK
(`quantity = 0 OR security_id IS NOT NULL` — the degenerate row **passes**), the `017`
global-OR-owned security fence (**no-op** when `security_id` is NULL), `004`'s matched-account fence
and `006` RLS (both satisfied), and grepped for a position-nonnegativity trigger (**none exists**).
Every one of those is a fence that does not fire on the un-masked class — which is exactly why the
old accidental one was load-bearing.

**Second-order tell, free to check:** a walk gate that went GREEN *twice* still only drove the class
the author had in mind. A green walk bounds the classes it exercised, never the classes the path
accepts. Ask which inputs the walk used before treating GREEN as coverage — and say so without
implying QA erred, because they did not.

**How to apply:** on any PR whose summary says "X was broken for everyone / always failed / since
<date>", treat the fix as a **capability grant**, not a repair. List the input classes, walk each,
and name explicitly the ones the change newly permits. Related:
[[measure-the-fence-regex-not-its-comment]],
[[read-decisions-from-the-pr-branch-when-the-pr-edits-it]].
