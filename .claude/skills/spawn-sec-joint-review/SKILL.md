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
| **D2** | Immutable + INSERT-new-version audit-class | Any audit-class surface — D2's own scope clause is *"all audit-class surfaces (financial-correctness data + compliance-attestation-bearing tables)"*. Append-only at RLS + trigger layer; corrections via INSERT-new-version with predecessor FK. ⚠ **Ratified-at is not extent.** Locks 9 (`reconciliation_event` **+ `reconciliation_event_trans`**) / 10 (`account_trans`) / 11 (`monthly_report`) are where the pattern was **ratified** — they are not the list of surfaces it governs. A later table adopting the posture is in scope (e.g. `pfin.cpi_u_nonpublication` per [ADR-049](../../../DECISIONS.md#adr-049) D1, ruled in-scope at Sec joint-review 2026-08-11). ⚠ **And D2 is two clauses.** A surface can inherit the immutable half while structurally not admitting INSERT-new-version at all — where correction is impossible by construction, there is no predecessor to relate to. A bare *"D2 applies"* over-claims; name which half. |
| **D3** | Cross-tenant FK-bypass family | Any FK-shaped reference column (single FK, self-FK, INTEGER[] array element) crossing an isolation boundary. Requires explicit matched-tenant validation — WITH CHECK (single columns) or BEFORE INSERT/UPDATE trigger (array elements). **This skill states no count, deliberately — see the note below.** The family size must be read from live [ADR-011](../../../DECISIONS.md#adr-011) D3 text before any dispatch, not from memory. |
| **D4** | §10 catalogued-instance ledger | Any change to the defense-in-depth fencing ledger. **This skill states no count and no ordering, deliberately — same reason as D3 above.** The ledger **grows**: it went 2→3 when RT-27 was catalogued (SELF-212 / v1.83), and the superseded two-entry figure outlived that change by a fortnight in artifacts that read as current. Read the enumeration **and its ordering** from live [ADR-011](../../../DECISIONS.md#adr-011) D4 text before any dispatch — not from memory, and not from this table. Any change to count or layer-attribution is Sec joint-review-mandatory. |

## Additional mandatory-trigger surfaces

Per `supabase/CLAUDE.md` convention 2 + Security Reviewer agent definition:

- **New SECURITY DEFINER function** — routes to Sec joint-review before finalize. The V1 DEFINER allowlist is deliberately narrow, and **this skill states no size** — it has grown before (3→4 at SELF-293/`031`), so a figure here would drift the same way D3's and D4's did. Read the canonical entries from live [ADR-011](../../../DECISIONS.md#adr-011) D9. Any addition to this allowlist is a merge gate.
- **§10 ledger change (count or layer-attribution)** — even if not directly an ADR-011 D4 amendment. Path B discipline (drop-enumeration-let-link-carry) does NOT waive the joint-review gate.
- **Auth / money flows / secrets** — any route touching `service_role`, Vault/pgsodium, JWT shape, or `SUPABASE_SERVICE_ROLE_KEY` allowlist.
- **Plaid integration surfaces** — webhook handler, `/item/public_token/exchange`, `/item/remove` (the three V1 allowlist entries per [ADR-016](../../../DECISIONS.md#adr-016)).
- **Financial calculations** — NAV computation, tax-liability calculation, monthly report generation.
- **Audit-class write-surface changes in APP CODE** — any change to how app code writes an ADR-011 D2 table (`pfin.account_trans` above all: `reverseAndReplaceTrans`, the classify/recategorize/split writers, any future writer), **even when no DDL moves**, per [ADR-064](../../../DECISIONS.md#adr-064) Decision 5. Origin: a reverse-and-replace change was offered to Sec as a courtesy look and drew a veto on what mandatory review would have caught pre-offer — the ledger's write mechanics are the D2 surface, not just its schema. These reviews auto-route; they are never opt-in.
- **Multi-tenant isolation** — any RLS policy, WITH CHECK constraint, or BEFORE INSERT/UPDATE trigger touching tenant-isolation logic.
- **The `/api/asset/resolve` posture controls** — any change to that route's boundary handling (the forced `name: null` mint-content strip) or its per-user rate limiter. These are the compensating controls the [ADR-060](../../../DECISIONS.md#adr-060) posture decision RESTS on (V1 ships the global `pfin.asset` registry with no repair path); weakening, descoping or refactoring either does not merely change a route — it **reopens that ratified decision**, which is why the trigger fires here rather than being discovered at the next audit. The ADR carries the rationale; this line exists so the review fires.

## How to dispatch

Spawn the `security-engineer` agent with a brief that includes all three required blocks. Never omit any block.

**Required brief blocks:**

**(a) Surface + anchor.** Name the specific surface and its canonical anchor: which Decision (D1/D2/D3/D4), which RT catalog entry, which Lock number, which file path. Vague surface descriptions ("it touches auth") are the dispatch failure mode.

**(b) Self-checking verify-hook.** Embed verbatim: *"Read the cited canonical text verbatim before reviewing (brief-drift-catch Discipline 1) — including ADR-011 Decision 4's catalogued-instance list, read live from the ADR body, never from this brief, because the ledger grows. Cross-check three axes: (i) instance-numbering — the reference's enumeration and ordering against Decision 4's live list, (ii) layer-attribution — against Decision 4's class composition as its own text words it, (iii) verbatim-vs-paraphrase for any quoted Lock text. Surface drift inline before verdict."*

⚠ **The verify-hook must name no ledger figure or ordering of its own.** It said *"the RT-22/RT-26 canonical ordering"* until 2026-08-11 — a two-entry ordering, stale since RT-27 was catalogued, sitting in the one block every dispatch copies verbatim. A reviewer checking axis (i) against the brief instead of against D4 would have verified CLEAN against a ledger missing its third entry. **This block is the highest-fan-out text in the file: an error here is re-injected into every future review.** Sec caught it from the outside; nothing in the file was watching it.

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
Read [ADR-011](../../../DECISIONS.md#adr-011) Decision [N] verbatim. Read Decision 4's
catalogued-instance list live from the ADR body — never from this brief; the ledger
grows and this brief names no enumeration. Cross-check three axes:
(i) instance-numbering — the reference's enumeration and ordering against D4's live list.
(ii) layer-attribution — against Decision 4's class composition as its own text words it.
(iii) verbatim-vs-paraphrase — are Lock quotations exact?
Surface any drift inline before verdict.

Return: GREEN (proceed) / RED (veto) / AMBER (conditional). State the specific finding. If RED, name the failure clause (e.g., "D3 matched-tenant validation missing on INTEGER[] column at line N"). If AMBER, state the blocking condition.
```

## Interpreting the verdict

- **GREEN** — proceed to merge. Run `brief-drift-catch` Discipline 1 over the Sec finding before forwarding to F/CTO: read the cited Locks verbatim and verify Sec's citation-attribution is accurate (the team-lead Sec-Lock cross-check per memory `feedback_team_lead_sec_ratify_lock_cross_check` — a standing check with a long application record; **the tally is deliberately not stated here**, for the same reason the ledger figures above are not). Compose `brief-drift-catch` Discipline 2 (2-teammate independent verification) for genuinely load-bearing one-way-door surfaces.
- **RED** — veto. Do NOT merge. Sec's veto on these surfaces is not advisory; it is a merge gate. Route the specific failure clause to Architect (DDL fix) or Backend (app-layer fix) as appropriate. Re-dispatch Sec after fix is applied.
- **AMBER** — conditional. Merge is blocked pending the named condition. Treat as RED until condition clears and Sec upgrades to GREEN.

## Where this gates

- **Every Phase 4 Wave** — mandatory at every Wave gate, per Phase 4 track record (23+ CLEAN §10 surfaces across 13-PR Phase 3 ARCH streak; 20 Wave gate ratifies across Phase 4 with Sec joint-review on load-bearing surfaces).
- **Every Phase 5–7 V1-SHIP-BLOCK PR** — any PR carrying a V1-SHIP-BLOCK posture obligation (any catalogued §10 instance — read the enumeration live from [ADR-011](../../../DECISIONS.md#adr-011) D4 — or any HIGH-severity SD or RT) requires Sec joint-review before merge.
- **Milestone-rotation** — when BACKLOG.md §7 entries promote to Linear at milestone-rotation (per [ADR-017](../../../DECISIONS.md#adr-017) Decision 2), new issues touching the mandatory-trigger surfaces above require Sec joint-review before the first implementation PR merges.

This is a **merge gate** — not optional peer review, not a post-merge annotation. Sec joint-review must COMPLETE and return GREEN before the merge commit lands.

## Failure modes

- **Skipping because "it looks low-risk"** — the trigger list is mechanical for a reason. D3 FK-bypass surfaces consistently look benign at the schema level and still require the gate; Sec's catch rate across Phase 1 Step 4 (it grew materially between ADR drafting and Phase 4 close, and has grown again since — read the current body) demonstrates that surface-level risk estimates are not reliable.
- **Verifying the D3 family against a recalled number** — **this skill states no figure, deliberately.** The count has changed **repeatedly and materially**, and *labeled* vs *DDL-realized* are two counts that diverge. **Read [ADR-011](../../../DECISIONS.md#adr-011) D3's body live before every dispatch.** ⚠ This bullet previously listed a progression of three figures; the trailing one anchored low and read as current, and one of them — the *"7"* — is a tally **D3's own text repudiates as un-reconciled and NOT canonical** (contaminated by conflation with the Lock-14 settings family). **A repudiated figure does not become safe by being placed in the past — it becomes harder to catch, because it then reads as a record rather than as a claim.**
- **Omitting the verify-hook from the dispatch brief** — without an embedded verify-hook, Sec's own finding may carry paraphrase drift; the verify-hook makes the review self-checking at source.
- **Treating AMBER as proceed** — AMBER is a blocked state, not a caution. Only GREEN proceeds.
- **Dispatching without naming the specific anchor** — vague briefs produce vague verdicts; name the Decision number, Lock number, and file path.

## Notes

- Composes with `brief-drift-catch` (the Sec-Lock cross-check is Discipline 1 applied to Sec findings; run it over every Sec verdict before forwarding to F/CTO).
- The §10 3-axis cross-check (instance-numbering / layer-attribution / verbatim-vs-paraphrase per memory `feedback_decision_4_instance_ledger_cross_check`) is the concrete application of `brief-drift-catch` Discipline 1 to §10-adjacent Sec findings — reference it explicitly in the verify-hook when the surface touches §10.
- **PM owns the routing decision** (flag + dispatch); Sec owns the verdict; F/CTO owns the merge ratify. PM does not make the security call.
- Origin: Phase 1 Step 4 Sec joint-review pattern (16-lock arc, 23+ V1-ship-blockers caught); Phase 3 ARCH streak (13-PR Sec joint-review; §10 discipline CLEAN streak); Phase 4 Wave decomposition (20 gate ratifies); Phase 5 Step 6 skill codification.
