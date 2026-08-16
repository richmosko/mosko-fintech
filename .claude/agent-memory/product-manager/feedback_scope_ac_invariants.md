---
name: scope-ac-invariants
description: An AC stating an invariant must carry its scope clause — ask the construction's owner "which row/case falsifies this?" before finalizing.
metadata:
  type: feedback
---

When drafting an AC that asserts an invariant ("cell A equals cell B", "NULL exactly where…"), explicitly scope it to the cases where it holds, and ask the owning engineer/Architect which case falsifies the unconditional form before finalizing.

**Why:** SELF-223 AC6 (2026-08-14) — my "prior-YE row's two cells are equal by construction" was false on the CPI-unresolvable row (nominal renders, deflated cell NULL). Architect had shipped the same defect class on migration 072 (unscoped biconditional; Sec caught two sites, Architect a third). The failure mode isn't wrong behavior — it's that a future corrector reading the unconditional claim and finding a falsifying row goes hunting in the column that is working correctly. Also from the same exchange: value-equality ACs must specify numeric `=`, not text/display comparison (trailing-zero renders differ), and a well-scoped invariant AC can double as a fence against a plausible future "simplification."

**How to apply:** (1) For every equality/NULL-pattern AC, enumerate the contract's failure cases (unavailable, carried, uncomputable) and check the claim against each. (2) Phrase the scope structurally ("whenever cpi_unavailable is false"), not in prose. (3) I asked "would the construction ever violate it?" — the right question, but I guessed the wrong case (carried, which was safe); let the construction owner answer, don't self-certify. Related: [[parity-fixture-cell-format]].
