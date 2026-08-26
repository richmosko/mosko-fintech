---
name: suspense-branch-absorbs-the-divergence
description: A Σ=0 trial balance cannot observe a GL/holdings divergence that a catch-all Suspense branch absorbs; holdings read `quantity`, the GL reads `cost_basis`, and a writer that touches one is invisible to every fence on the other.
metadata:
  type: reference
---

**`pfin.account_trans` is read by TWO consumers over DIFFERENT columns.** `fn_holdings_as_of`
(`019`) sums `quantity`; `fn_gl_entries` (`084`) books position value from `cost_basis`.
`amount` is the cash leg. `price` is read by **nothing** in V1 (`049`/`050` value from
`pfin.eod_price`). A writer that sets one and omits the other produces a row that is legal,
balanced, and **wrong in two directions at once**.

**Why nothing catches it.** `084` has catch-all Suspense branches (P8 for a security non-buy
with no `lot_match`, P10 for a standard BUY residual). When a real leg loses its counterpart,
a Suspense branch absorbs the difference and **Σ=0 still holds**. So "the double-entry ledger
is reconciled by construction" is true and useless here: the invariant that would fire is not
the trial balance, it is an equality between two *different reads* that nobody asserts.

**Why:** measured at SELF-340. `reverseAndReplaceTrans` never selects or writes `cost_basis`,
so a security reversal removes `−Q` shares from holdings while `trade_position` keeps the book
value permanently. P2 skips on null `cost_basis`; P8 parks the amount in Suspense; the trial
balance is clean. Same divergence for an `087` opening position by a different route — there the
reversal emits **zero GL rows at all** (P1 skips `amount=0`, P2 skips null `cost_basis`, the P5
contra evaluates to 0 and is dropped by the `amount_book <> 0` filter).

**How to apply:** when a change touches `account_trans`, enumerate which of `{quantity,
security_id, cost_basis, amount}` it writes and evaluate **every** `fn_gl_entries` branch
predicate against the resulting row — the predicates are `cost_basis is not null`, `quantity <= 0`,
`quantity > 0`, and `transaction_type`, so an omitted column silently *re-routes the branch*
rather than zeroing it. A watcher for this class asserts **no `suspense` row is emitted**, never
that the postings sum to zero. Related: [[reference_manual_valuation_outranks_feeds_in_price_pick]]
(the F4 hazard on the same table), [[feedback_watcher_not_fence_for_by_construction_properties]],
[[feedback_structural_fence_must_cover_the_same_class]].

⚠ **The corollary that generalizes past this table:** a fence placed AFTER the irreversible write
is not a fence. `084` s2a (`security_id IS NOT NULL ⟺ cat='Trade'`) observes this exact defect and
raises — but the edit path runs it as a best-effort annotation upsert *after* the ledger INSERT and
`console.warn`s the failure while returning success.

**Third instance, same table, same absorber — and it is a BOOKED SEAM, not a defect.** A row's GL
class comes from **its own annotation** (`fn_gl_entries`' `txn` CTE: `ann.trans_id = t.trans_id
→ pp.cat`), reversal rows get **no special-casing** (`035` says so verbatim), and
`reverseAndReplaceTrans` annotates **only the corrected row**. So a reversal's contra has a NULL
`flow_class` and falls to P3's `else` → **Suspense** on the GL route.

⚠ **This is `BACKLOG` §7.28 item 1** — *"§2.3-vs-GL reversal-netting disagreement — both correct,
not equal"* — booked 2026-08-22, evidence at `docs/records/v13-preflight/architect-findings.md`
E1(a). **The §2.3 route nets the pair via the `replaces_trans_id` join and needs no category on
the reversal**, so PRD §2.3.1's *"nets structurally against its original"* is scoped to §2.3 and
is TRUE there. The absent annotation is **ruled design intent** (E1(a); sitting item 8a's rider
confirmed the shipped flow matches) — **annotating the reversal would violate the ruling** and
create the double-handling join-netting exists to avoid. The §7.24 item 3 watcher asserts the
reconciliation identity (§2.3 total + Suspense-offset = GL total), never bare equality.

**The reusable shape survives the retraction: "nets structurally" is a claim about a SPECIFIC leg
and a SPECIFIC reader.** A reversal that negates `amount` cancels everything keyed on `amount` and
nothing keyed on a column it does not carry — `cost_basis` (the §2 instance) or an annotation
(this one). Enumerate what the original contributes, then ask which of those the reversal
reproduces negated **and by which reader**. A catch-all Suspense branch keeps the trial balance
clean while the two readers disagree — by design, here.
