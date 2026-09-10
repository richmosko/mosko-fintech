---
name: plaid-credential-confinement-contradiction
description: RULED 2026-09-09 (F/CTO + PR #697) — Plaid creds confined to provider-sync; root .env.example declaration removed. One item stays OPEN: workers/etl/ declares them on a falsified ARCH §5 rationale.
metadata:
  type: project
---

**RULED 2026-09-09.** F/CTO ruled: remove the `PLAID_*` credential entries from the root
`.env.example`. Landed as PR #697 (`fix/plaid-confinement-root-env`, tip `74d9a1d5`), which
replaced them with an absent-note in the established `PLAID_WEBHOOK_SECRET` style. I approved
with two conditions (scope-comment corrections in `secrets-manifest.yml` and
`workers/provider-sync/.env.example`) — verify both landed before citing this as closed.

**Settled facts (measured at `74d9a1d5`, re-verify before acting):**
- `provider-sync` is the **sole code-layer holder** — the only container whose code reads
  `PLAID_CLIENT_ID`/`PLAID_SECRET` (`workers/provider-sync/src/config/env.ts`).
- `api/src` holds no Plaid credential; three source comments assert it, and ADR-037's AC1
  reconciliation row says verbatim "sole holder of `PLAID_CLIENT_ID/SECRET`; api/src is
  credential-less". That delegated ES256/JWK fetch is the substantive argument, as predicted.
- `docs/deployment-runbook.md` §5 was **correct in advance** — it described the post-fix state
  and named the tree as the wrong side. No runbook follow-up.
- **Nothing watches this.** `grep -rn 'PLAID' .github/workflows/ scripts/` returns zero (positive
  control: `secrets-manifest` matches 5 files). No script parses root `.env.example`. The only
  fence is that `.env.example` is a Sec-joint-review-mandatory surface. A CI leg asserting root
  `.env.example` declares neither name is a live follow-up candidate; I did not condition on it.

**STILL OPEN — `workers/etl/.env.example` declares both.** Its stated rationale ("ARCH §5 lists
Plaid creds on this container", header quote "verified verbatim 2026-06-28") is falsified three
ways at the tree: ARCH §5 says outbound Plaid comes "not from `pfin_back_etl`"; ARCH §5 says
"Neither holds a Plaid credential today"; and `workers/etl/docker-compose.yaml` passes neither
because "this worker never calls any FMP/BLS/Plaid code path". Team-lead ruled it defensible on
its face; I ruled it a stale-quote-as-authority. Kept out of #697 deliberately — fixing it opens
an Architect/F/CTO design question (does the Wave-6 scheduled-poll worker hold Plaid creds at
all?).

**Why it still matters:** the per-surface `.env.example` enumeration IS the confinement property.
⚠ Beware the citation loop — ARCH §5's per-container enumeration is self-marked "Phase-3 vintage
and has drifted from the tree; … the per-surface `.env.example` files are the source of truth",
so an `.env.example` citing ARCH §5 for its own contents is circular. Rest confinement claims on
ADR-037 and on ARCH §5's "Credential-holding container — corrected against the tree" paragraph.

**How to apply:** `deployment-runbook.md` §5's secrets-provisioning STUB is cleared to lock with
ONE carve-out I stated: **§5 must not instruct injecting `PLAID_CLIENT_ID`/`PLAID_SECRET` into
the `pfin_back_etl` container** — provision to `provider-sync` only until the ETL item is ruled.
Related: [[feedback_correcting_half_a_hand_maintained_mirror]] (the per-surface census misses
scope claims inside correct files — that is how the provider-sync comment survived).
