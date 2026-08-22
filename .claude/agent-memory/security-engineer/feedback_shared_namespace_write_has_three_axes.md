---
name: shared-namespace-write-has-three-axes
description: A user-reachable write into a SHARED/global namespace has three independent axes — overwrite, first-write squatting, and repairability; a rate-limit framing covers none of them
metadata:
  type: feedback
---

A write path into a namespace that is **readable by every tenant and owned by none**
(`pfin.asset` where `users_id IS NULL`) must be reviewed on **three independent axes**.
Clearing one says nothing about the other two.

1. **Overwrite** — can a caller mutate an EXISTING shared row? Read the conflict clause.
   `on conflict … do nothing` clears this axis cleanly.
2. **First-write squatting** — can a caller CLAIM an unclaimed key, with content of their
   choosing? `do nothing` does **not** clear this. Ask what the row carries besides its
   key: free-text `name`, a second identity column (a real CUSIP paired with a novel
   symbol), a type that drives a downstream mapping. Each is attacker-chosen content that
   every other tenant will later bind to.
3. **Repairability** — measure the GRANTS, not the policies. `grant select, insert … to
   service_role` with no UPDATE/DELETE, plus RLS that scopes `authenticated`'s UPDATE to
   *owned* rows, means **no shipped code path can ever correct the row**. Irreversibility
   is the property that removes "flag it and fix it later" — it is what turns a flag into
   a blocking condition.

**Why:** SELF-325's `/api/asset/resolve` (2026-08-21). The mint mechanism was pre-existing
and provider-driven; the branch made it browser-reachable with user-chosen inputs.
Architect recorded the escalation honestly and framed the missing control as
**"the absent rate-limit control."** That framing is a **volume** control, and axes 2 and
3 each need **exactly one request**. A correct, well-documented escalation notice can still
name the wrong control.

**How to apply:** when a review surface writes into anything global/shared/all-tenant-
readable, run the three axes before ruling. Measure the repair path with `grep -n
"grant\|revoke" <migration>` on the table's OWN migrations — not from the write path's
comments, which describe the write and are silent about repair. If axis 3 is closed
(no repair path), the axis-2 finding blocks; if a repair path exists, it can book.
Also: the cheapest sufficient fix is usually at the **outer boundary** (drop the
attacker-controlled field before it reaches the mint — the endpoint already hard-coded
`currency: 'USD'` by exactly that reasoning), not a redesign of the shared resolver.

**Corollary — where the response validator sits relative to the COMMIT.** When the
privileged write happens in a remote service, the caller's `safeParse` of the response
runs *after* that transaction has already committed. So **"the caller got a 5xx" does not
mean "no row exists."** Measured on this same route: the worker commits the mint, logs
`200`, and returns; the app's response schema rejects the payload and returns 502 with
**no log line on that path at all** (`callWorker` logs only `if (res.status !== 200)`,
which never fires). A committed privileged write with no acknowledgment anywhere — and
if clause (d)'s audit log is deferred, no attribution either. Ask, on any remote
privileged write: *what is the trace when the response fails to parse?*

Related: [[feedback_measure_the_fence_regex_not_its_comment]] ·
[[feedback_a_red_whose_message_names_the_wrong_defect]] ·
[[feedback_hazard_mechanism_vs_reachability]] ·
[[feedback_verify_the_stated_correctness_mechanism]]
