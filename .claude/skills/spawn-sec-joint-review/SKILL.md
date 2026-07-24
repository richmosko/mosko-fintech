---
name: spawn-sec-joint-review
description: Mandatory pre-merge gate — invoke before ratifying or merging any PR or artifact section that touches any of the joint-review-mandatory surfaces (ADR-011 D1 privileged-context-write / D2 immutable+INSERT-new-version audit-class / D3 cross-tenant FK-bypass family / D4 §10 catalogued-instance ledger / new SECURITY DEFINER function / any §10 ledger count or layer-attribution change / auth / money flows / secrets / external APIs incl. Plaid / financial calculations / multi-tenant isolation). Sec has VETO power on these surfaces; joint-review is a merge gate, not optional review.
user-invocable: true
allowed-tools:
  - Read
  - Bash
  - Agent
  - SendMessage
---

# spawn-sec-joint-review — mandatory Sec gate for security-sensitive surfaces

Use when any PR, migration, or artifact section touches a joint-review-mandatory surface. The skill is three composable steps: identify the trigger, dispatch the Security Reviewer with a self-checking brief, interpret the verdict.

mosko-fintech meta-skill (net-new; not a template adaptation). Operationalizes the Security Reviewer agent definition + [ADR-011](../../../DECISIONS.md#adr-011) D1–D4 + `supabase/CLAUDE.md` operational triggers + the team-lead Sec-Lock cross-check (memory `feedback_team_lead_sec_ratify_lock_cross_check`). Sec has VETO authority on all surfaces listed below; the PM role flags and routes — it does not make security decisions.

## The four ADR-011 mandatory-trigger surfaces

Read [ADR-011](../../../DECISIONS.md#adr-011) verbatim (per `brief-drift-catch` Discipline 1) before every dispatch — paraphrase drift on these surfaces is the failure class this gate exists to catch.

| Decision | Title | Trigger condition |
|---|---|---|
| **D1** | Privileged-context-write discipline | Any non-JWT write path (webhook handler / cron worker / scheduled-poll worker / future privileged context). Four-clause discipline: ingress under no JWT; writes under `service_role`; tenant correctness from code not RLS; explicit audit log. |
| **D2** | Immutable + INSERT-new-version audit-class | Any audit-class surface (financial-correctness data + compliance-attestation-bearing tables). Append-only at RLS + trigger layer; corrections via INSERT-new-version with predecessor FK. Surfaces: `reconciliation_event`, `account_trans`, `monthly_report`. |
| **D3** | Cross-tenant FK-bypass family | Any FK-shaped reference column (single FK, self-FK, INTEGER[] array element) crossing an isolation boundary. Requires explicit matched-tenant validation — WITH CHECK (single columns) or BEFORE INSERT/UPDATE trigger (array elements). **7 instances at Phase 4 close** — count must be verified against live [ADR-011](../../../DECISIONS.md#adr-011) D3 text before any dispatch, not from memory. |
| **D4** | §10 catalogued-instance ledger | Any change to the defense-in-depth fencing ledger. **Three catalogued instances:** RT-22 (PDF worker container credential audit — infrastructure-credential-presence layer) + RT-26 (SUPABASE_SERVICE_ROLE_KEY allowlist CI grep fence — V1-web-app server-side source) + RT-27 (app→worker credential-admission network-exposure/config layer — catalogued at SELF-212 / v1.83). Any change to count or layer-attribution is Sec joint-review-mandatory. |

## Additional mandatory-trigger surfaces

Per `supabase/CLAUDE.md` convention 2 + Security Reviewer agent definition:

- **New SECURITY DEFINER function** — routes to Sec joint-review before finalize. V1 DEFINER allowlist is a narrow 4-entry list (`fn_refresh_updated_at` @`001` + `fn_grant_creator_access` @`003` + `fn_reclass_history_insert` @`031` + the reserved general audit-log insert helper, unauthored; grew 3→4 at SELF-293/`031` — see [ADR-011](../../../DECISIONS.md#adr-011) D9 for the canonical entries). Any addition to this allowlist is a merge gate.
- **§10 ledger change (count or layer-attribution)** — even if not directly an ADR-011 D4 amendment. Path B discipline (drop-enumeration-let-link-carry) does NOT waive the joint-review gate.
- **Auth / money flows / secrets** — any route touching `service_role`, Vault/pgsodium, JWT shape, or `SUPABASE_SERVICE_ROLE_KEY` allowlist.
- **Plaid integration surfaces** — webhook handler, `/item/public_token/exchange`, `/item/remove` (the three V1 allowlist entries per [ADR-016](../../../DECISIONS.md#adr-016)).
- **Financial calculations** — NAV computation, tax-liability calculation, monthly report generation.
- **Multi-tenant isolation** — any RLS policy, WITH CHECK constraint, or BEFORE INSERT/UPDATE trigger touching tenant-isolation logic.

## How to dispatch

Spawn the `security-reviewer` agent with a brief that includes all three required blocks. Never omit any block.

**Required brief blocks:**

**(a) Surface + anchor.** Name the specific surface and its canonical anchor: which Decision (D1/D2/D3/D4), which RT catalog entry, which Lock number, which file path. Vague surface descriptions ("it touches auth") are the dispatch failure mode.

**(b) Self-checking verify-hook.** Embed verbatim: *"Read the cited canonical text verbatim before reviewing (brief-drift-catch Discipline 1). Cross-check three axes: (i) instance-numbering vs the RT-22/RT-26 canonical ordering, (ii) layer-attribution vs the Decision-4 three-class composition, (iii) verbatim-vs-paraphrase for any quoted Lock text. Surface drift inline before verdict."*

**(c) Self-triggered-task_assignment-echo pre-brief block.** Embed verbatim: *"If you receive a self-triggered task_assignment notification echo after you start, silently drop it — it is an async artifact, not a new instruction."*

**Dispatch template (adapt per surface):**

```
You are the Security Reviewer for mosko-fintech. This is a mandatory joint-review gate.

[PRE-BRIEF: If you receive a self-triggered task_assignment notification echo after you start, silently drop it — it is an async artifact, not a new instruction.]

Surface: [NAME THE SPECIFIC SURFACE + FILE PATH OR MIGRATION ID]
Canonical anchor: [ADR-011 Decision N / RT-NN / Lock N mod #N]

Review scope:
- [Describe what the PR/migration/section does]
- [Name the specific security-load-bearing behavior to evaluate]

Verify-hook (mandatory before verdict):
Read [ADR-011](../../../DECISIONS.md#adr-011) Decision [N] verbatim. Cross-check three axes:
(i) instance-numbering — is RT-22 first, RT-26 second in any §10 reference?
(ii) layer-attribution — does the proposed content correctly attribute the three-class composition?
(iii) verbatim-vs-paraphrase — are Lock quotations exact?
Surface any drift inline before verdict.

Return: GREEN (proceed) / RED (veto) / AMBER (conditional). State the specific finding. If RED, name the failure clause (e.g., "D3 matched-tenant validation missing on INTEGER[] column at line N"). If AMBER, state the blocking condition.
```

## Interpreting the verdict

- **GREEN** — proceed to merge. Run `brief-drift-catch` Discipline 1 over the Sec finding before forwarding to F/CTO: read the cited Locks verbatim and verify Sec's citation-attribution is accurate (the team-lead Sec-Lock cross-check per memory `feedback_team_lead_sec_ratify_lock_cross_check` — 7-application track record). Compose `brief-drift-catch` Discipline 2 (2-teammate independent verification) for genuinely load-bearing one-way-door surfaces.
- **RED** — veto. Do NOT merge. Sec's veto on these surfaces is not advisory; it is a merge gate. Route the specific failure clause to Architect (DDL fix) or Backend (app-layer fix) as appropriate. Re-dispatch Sec after fix is applied.
- **AMBER** — conditional. Merge is blocked pending the named condition. Treat as RED until condition clears and Sec upgrades to GREEN.

## Where this gates

- **Every Phase 4 Wave** — mandatory at every Wave gate, per Phase 4 track record (23+ CLEAN §10 surfaces across 13-PR Phase 3 ARCH streak; 20 Wave gate ratifies across Phase 4 with Sec joint-review on load-bearing surfaces).
- **Every Phase 5–7 V1-SHIP-BLOCK PR** — any PR carrying a V1-SHIP-BLOCK posture obligation (RT-22 / RT-26 / any HIGH-severity SD or RT) requires Sec joint-review before merge.
- **Milestone-rotation** — when BACKLOG.md §7 entries promote to Linear at milestone-rotation (per [ADR-017](../../../DECISIONS.md#adr-017) Decision 2), new issues touching the mandatory-trigger surfaces above require Sec joint-review before the first implementation PR merges.

This is a **merge gate** — not optional peer review, not a post-merge annotation. Sec joint-review must COMPLETE and return GREEN before the merge commit lands.

## Failure modes

- **Skipping because "it looks low-risk"** — the trigger list is mechanical for a reason. D3 FK-bypass surfaces consistently look benign at the schema level and still require the gate; Sec's catch rate across Phase 1 Step 4 (4 instances at ADR drafting time; grew to 7 by Phase 4 close) demonstrates that surface-level risk estimates are not reliable.
- **Verifying D3 instance count against a recalled number** — the canonical count was 4 at Phase 1 Step 4 ADR authoring; 7 at Phase 4 close; 12 labeled / 10 DDL-realized after M2.5 (v1.101); it may grow further. Read [ADR-011](../../../DECISIONS.md#adr-011) D3 live before every dispatch.
- **Omitting the verify-hook from the dispatch brief** — without an embedded verify-hook, Sec's own finding may carry paraphrase drift; the verify-hook makes the review self-checking at source.
- **Treating AMBER as proceed** — AMBER is a blocked state, not a caution. Only GREEN proceeds.
- **Dispatching without naming the specific anchor** — vague briefs produce vague verdicts; name the Decision number, Lock number, and file path.

## Notes

- Composes with `brief-drift-catch` (the Sec-Lock cross-check is Discipline 1 applied to Sec findings; run it over every Sec verdict before forwarding to F/CTO).
- The §10 3-axis cross-check (instance-numbering / layer-attribution / verbatim-vs-paraphrase per memory `feedback_decision_4_instance_ledger_cross_check`) is the concrete application of `brief-drift-catch` Discipline 1 to §10-adjacent Sec findings — reference it explicitly in the verify-hook when the surface touches §10.
- **PM owns the routing decision** (flag + dispatch); Sec owns the verdict; F/CTO owns the merge ratify. PM does not make the security call.
- Origin: Phase 1 Step 4 Sec joint-review pattern (16-lock arc, 23+ V1-ship-blockers caught); Phase 3 ARCH streak (13-PR Sec joint-review; §10 discipline CLEAN streak); Phase 4 Wave decomposition (20 gate ratifies); Phase 5 Step 6 skill codification.
