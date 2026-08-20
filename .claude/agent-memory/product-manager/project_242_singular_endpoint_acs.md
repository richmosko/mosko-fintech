---
name: self-242-singular-endpoint-acs
description: SELF-242 AC3/AC7 + AC2/AC6 replacement text delivered 2026-08-20 — singular POST+DELETE consumption; unset=DELETE never POST 0.00; N7-A ruled: editor is asset-element-only via loader-supplied element predicate (NOT a CAT_GROUP_ORDER amendment)
metadata:
  type: project
---

Delivered replacement AC3/AC7 for SELF-242 to team-lead 2026-08-20 (drafting-only; lands in Linear post-ratify). The stale PM-draft shape (keyed-array batch payload; `POST /api/settings/allocation`) never shipped — Sec's 2026-08-17 binding: "242's share is the editor consuming SELF-233's hardened endpoint + this DELETE, not re-implementing validation." Shipped shapes (copied from code): `POST /api/settings/planning-target` `{ sub_cat_id, target_percent }` (planningTargetUpsertSchema, .strict(), session-derived users_id) + `DELETE` `{ sub_cat_id }` (planningTargetDeleteSchema); **unset = DELETE, never POST 0.00** (ADR-056: 0.00 is a stored, different fact from row-absent); DELETE returns the same 200 regardless of row existence (no cross-tenant/step-up leak).

**Why:** old AC3 also claimed forged IDs "rejected pre-DB-write" — the Sec-reviewed fence is DB-layer (Decision-3 #17 trigger, 074) with clean 4xx mapping; app layer is shape-only. Layer attribution corrected, H1 substance kept.

**N7-A ruling (F/CTO 2026-08-20):** a Liabilities %Target is NOT meaningful post assets-only — the 242 editor renders asset-element Sub-Cats only, filtered data-driven on loader-supplied `element === 'asset'` (NOT via amending CAT_GROUP_ORDER — that ahead of the denominator rework would create the coverage divergence ADR-058 D3 F4(3) forbids; constant unification completes at SELF-239). AC2/AC6 delta delivered same day: element predicate + separate standing Real Estate exclusion (element='asset' alone ADMITS RE); sum guidance over rendered set only, each stored target counted once (the twelve US-equity targets also compose the derived US - Sector Diversified aggregate — naive Σ double-counts).

**How to apply:** (1) at drafting the DELETE existed only on unmerged `feature/self242-settings-allocation` (d87a62c) — re-verify shapes at promotion if the branch was reworked. (2) AC7's per-row partial-failure semantics are NEW substance vs the batch shape's implied atomicity — F/CTO must have seen it at ratify. (3) Reusable rule: when an AC is amended against a Sec-bound implementation, the endpoint consumption shape (per-row vs batch) silently changes submit atomicity — always name that as a product decision. Related: [[self-239-assets-only-rework]], [[ac-signatures-copied-not-composed]].
