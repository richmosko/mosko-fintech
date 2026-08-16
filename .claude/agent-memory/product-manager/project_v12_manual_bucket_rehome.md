---
name: v12-manual-bucket-rehome
description: PRD §2.2.1 manual clause is per-ASSET (junction-compatible); post-048 nothing carries a manual account's bucket — pending F/CTO A-vs-B ruling
metadata:
  type: project
---

PRD §2.2.1's manual clause reads "each MANUAL ASSET's bucket is set when the account is created or edited" — **per-asset, not per-account**. The retired per-account `account.sub_cat_id` (012/013, removed v1.132, dropped at 048) was the Wave-3 drafts' interpretation, not the PRD's wording. The 016 per-user asset + 022 user_asset_category junction substrate already represents the story's data model; what's missing (as of 2026-08-15 recon at 907adfe) is connective flow — manual-account create/edit creates/links no asset row and writes no junction row, and the classify surface derives pending from security_id-bearing transactions, so manual accounts never surface there. **Nothing carries a manual account's bucket post-048.**

**Why:** V1.2 reconciliation found 048 removed the only carrier without re-homing the clause; §2.2.1 AND §2.4.2 both pin Sub-Cat capture AT the create flow.

**How to apply:** Pending F/CTO ruling: (A) restore create-time capture against the junction — no PRD change (PM-recommended) — vs (B) amend PRD to classify-after-create (touches ratified §2.2.1 + §2.4.2 text). Second pending V1.2 ruling from the AC-amendment pass (2026-08-15): NO seeded "US - Sector Diversified" Sub-Cat exists in 041 — the §2.2.2/§2.2.3 reconciliation anchor must be a COMPUTED aggregate over the twelve seeded US-equity Sub-Cats (PM rec: collapsed-with-drill-down) or twelve individual rows; touches SELF-238/239/240 ACs. Also: SELF-234 closed superseded per F/CTO Option C (R1/R2 split to new issues); dated closure predicate canonical form lives at 059 (not 049). Do not spec the SELF-236 successor or SELF-244 coverage until ruled. SELF-236 stays Done with a built-then-retired clarifying comment (SELF-217 precedent), never re-opened. Related: [[ac-signatures-copied-not-composed]] — five V1.2 drafts (237/238/240/243/244) carried the `p_users_id`/`p_scope pfin.scope[]` family ratified out at 049/051.
