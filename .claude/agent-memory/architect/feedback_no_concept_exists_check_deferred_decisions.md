---
name: no-concept-exists-check-deferred-decisions
description: Before writing "the schema has no X concept today", grep the ADRs for X — a ratified-but-DEFERRED decision is not visible in the DDL and will silently pre-empt your options list.
metadata:
  type: feedback
---

Never write *"the schema has no <concept> today to extend"* from a DDL sweep alone. A **ratified-but-deferred** decision leaves **zero trace in `supabase/migrations/`** and will pre-empt an option you are about to present as novel. Grep `DECISIONS.md` for the concept — and for the build-order sequence names (e.g. ADR-031 Decision 9's `M1 → M1-evt → M2.5 → M2 → M3-basis → M4-GL → C+ → M-hier`) — before framing options.

**Why:** I authored BACKLOG §7.13 (2026-08-12) on the schema-direction question and wrote *"no ledger-account concept exists today."* Two things falsified it, both invisible to a `grep` of the live DDL:
- **ADR-031 Decision 2** had already ratified `parent_account_id` on `pfin.account` as the deferred chart-of-accounts escape hatch (`M-hier`), gated on *"only if the account count ever warrants it"*.
- `fn_gl_entries` (`035`/`037`) already emits ledger accounts at read time — the real side IS the `pfin.account` row, the contra side is a `CASE` over `user_taxonomy.cat` into string literals.

So my option (B) *"a first-class CoA table alongside"* would have been the **third** classification spine, not the second — a materially different cost than the one I wrote down.

**How to apply:** at the framing step of any options memo, run two passes, not one — (1) the DDL sweep, (2) a `DECISIONS.md` grep for the concept noun AND for any milestone/sequence label that would carry it. State deferred decisions explicitly in the current-state map, flagged as *ratified, unbuilt*. ⚠ Related and distinct: [[feedback_ratified_name_is_not_a_built_table]] is the **inverse** error (treating a ratified name as built). Both come from reading only one of the two sources; the check is the same — read both, and label which side each fact came from.

Second, narrower catch from the same pass: a read-time helper's **string literals ARE a schema surface**. `fn_gl_entries`' `entry_account` CASE is a chart of accounts; it just has no table. Grep function bodies, not only `create table`, when asking "does the concept exist?"
