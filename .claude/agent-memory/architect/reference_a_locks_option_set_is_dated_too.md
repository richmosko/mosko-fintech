---
name: a-locks-option-set-is-dated-too
description: Before framing an amendment to a locked placement as a reversal, check whether the option set changed — a container/table/service that did not exist at lock time means the lock was never weighed against it.
metadata:
  type: reference
---

A Lock that **allocates work across a named set** (containers, tables, workers) is a
choice among the options that existed **on its lock date**. When a new option appears
later, re-allocating is **not** overturning the lock — its allocation was never weighed
against that option at all.

**Measured instance (2026-09-09, ADR-011 D17 / Lock 13, PR #699).** Lock 13 locked
`pfin_back_etl` as host of the Plaid scheduled-poll on 2026-05-26. `workers/provider-sync/`
did not exist until **ADR-019's topology amendment, 2026-07-17** (3 → 4 containers). So
F/CTO's ruling moving the poll there is a **placement change against a changed option
set**, not a reversal of a considered choice.

**How to apply.** Before drafting any amendment to a locked placement:
1. Date the lock. Date the receiving option's introduction. If the option is younger, say so — it reframes the whole amendment.
2. Grep the ADR that introduced the newer option for a **rationale that already separated the concerns**. At D17 that was ADR-019 rationale (5)(i), which had already ruled per-user provider sync distinct from batch ETL — far stronger support than the lock's own text.
3. ⚠ **Do not borrow the lock's own "load-bearing catch" as support without reading its SUBJECT.** D17 credits *"infrastructure-credential-absence as defense-in-depth"* — whose subject is Sec mod #2, **no Supabase creds in the PDF worker**, not anything Plaid. It supports a Plaid relocation by *principle*, never by precedent. Collapsing those is sound-quote drift.

**Where the amendment lives — the reconciliation ruled here.** ADR-019 sub-decision 1
**rejected** in-line amendment of D17 ("don't reopen a closed anchor"). ADR-011 **D18's
2026-08-16 amendment** later ruled that *a change to a LOCKED ENUMERATION must amend the
ADR holding it*. Reading landed at #699: **ADR-019's rejection stands for topology
EXTENSIONS; D18's rule governs MEMBERSHIP changes** — so a member leaving a locked list
lands in-line against the lock. F/CTO ruling pending; if reversed, the home is a **new
short-pattern ADR, never ADR-019**.

Related: [[reference_lock_join_lists_are_dated_artifacts]] · [[feedback_cited_precedent_transmits_its_retracted_half]] · [[feedback_sound_quote_false_gloss_drift]]
