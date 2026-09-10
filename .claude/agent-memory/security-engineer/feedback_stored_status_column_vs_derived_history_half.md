---
name: stored-status-column-vs-derived-history-half
description: When a view composes a STORED mutable status column with a DERIVED latest-history column, the two halves can disagree — and the security affordance keys off the mutable half. Find which half the affordance reads.
metadata:
  type: feedback
---

**A view that projects BOTH a stored mutable status column AND a "latest transition" derived
from an append-only history is TWO sources of truth in one row. Ask which half the security
affordance reads — that is the one that can go silently wrong.**

**Why:** PR #699 side-measurement, 2026-09-10. `pfin.linked_source_connection_state` (`043`)
projects `ls.connection_status` (STORED column on `pfin.linked_source`) alongside `sh.status_class`
(derived by LATERAL `order by detected_at desc, history_id desc limit 1` over the append-only
`linked_source_state_history`). The view's own comment sets the rule: *"Re-auth affordance rule:
show when connection_status IN (login_required, revoked, disconnected)"* — **the banner keys off
the MUTABLE half.** So a lost update on that column suppresses the reauth prompt while the
history half still records the truth. Dead credential presents as healthy; user reads stale
balances as current; nothing errors.

**The mechanism that gets it there — an unlocked read-modify-write inside ONE plpgsql function
still races.** `fn_plaid_webhook_commit` (`045`) does `select ... connection_status into v_cur_status`
with **no `FOR UPDATE`**, decides `if v_status is distinct from v_cur_status`, then UPDATEs. One
transaction is NOT one atomic decision when the read is unlocked: two concurrent callers both read
the old value, both pass the guard, both write, second wins. ⚠ An `ON CONFLICT (event_id) DO NOTHING`
idempotency gate does **not** cover this — it dedups REPLAYS OF ONE EVENT, never two distinct events.

**How to apply:**
1. In any `_latest` / connection-state / health view, **diff the two halves' provenance** before
   ruling it clean. Stored-vs-derived in one projection is the tell.
2. Read the artifact's own comment for **which column the affordance keys off**. It is usually
   written down and it is usually the mutable one.
3. For every status write, grep the SELECT that feeds its guard for `FOR UPDATE`. A guard reading
   an unlocked row is decoration — see [[feedback_a_check_chained_to_its_action_is_decoration]].
4. **State the property, not the mechanism, as the AC:** *"the view cannot return a row whose
   `connection_status` and `status_class` disagree about reauth"* — not *"an advisory lock exists."*
   A lock fixes the lost update and NOT the ordering; last-*committer* ≠ latest *event*.
5. ⚠ **pgTAP is single-session and cannot observe a two-transaction interleave** — route this class
   of leg to the live-DB integration lane. See [[feedback_savepoint_wrapped_pgtap_legs_cannot_fail]].

**The path that was CLEAN, recorded so I do not re-flag it:** `poll.ts markUnhealthy` writes only
unhealthy classes, returns early for non-SimpleFIN, and guards
`and connection_status is distinct from <target>` with the history row appended only on
`flipped.length === 1`. Overlapping poll runs are idempotent there. **The hazard was on the
webhook path, not the path I was asked to check** — see
[[feedback_hazard_mechanism_vs_reachability]].
