---
name: brief-drift-catch
description: Mandatory pre-reading before forwarding a teammate brief, a Sec/QA finding, or a v1 draft to F/CTO ratify. Codifies the verbatim-source cross-check (read the cited Lock/ADR/§-anchor VERBATIM before relaying — catches paraphrase / citation-attribution / quote-completeness / count drift) + the 2-teammate independent verification pattern for high-stakes brief-vs-canonical boundaries. CoS/team-lead-owned meta-skill.
user-invocable: true
allowed-tools:
  - Read
  - Bash
  - Agent
  - SendMessage
---

# brief-drift-catch — catch drift between a brief and its canonical source

Use when you are about to **forward** something that cites a canonical source to the next boundary: a teammate's brief/dispatch, a Sec/QA finding, or a v1 draft headed to F/CTO ratify. The skill is two composable disciplines that turn "trust the relay" into "verify at the boundary."

mosko-fintech meta-skill (net-new; not a template adaptation). It operationalizes the memories `feedback_team_lead_sec_ratify_lock_cross_check`, `feedback_decision_4_instance_ledger_cross_check`, `feedback_post_ratify_v1_cross_check`, and `feedback_async_mismatch_boundary_hooks` into one pre-reading checklist. 7+ application track record at authoring time.

## The core principle

**Every async-ordering or relay mismatch surfaces at a boundary IF the discipline has a hook to verify against.** So build a verification hook into every dispatch and every sign-off. A claim that cites a canonical source (a Lock, an ADR decision, a `§`-anchor, an instance count, a mod number) is a hook: read the source verbatim before the claim crosses the boundary.

## Discipline 1 — verbatim-source cross-check

Before forwarding any claim that cites canonical wording, **read the cited source verbatim** (don't trust the paraphrase, even your own). Grep the anchor, open the Lock, count the instances. Then compare against the claim. This catches five drift classes:

| Drift class | What it looks like | Live example |
|---|---|---|
| **Paraphrase drift** | Canonical content restated inexactly | PR #74 §8.5 four-layer paraphrase |
| **Citation-attribution drift** | Wrong `§`/ADR/Lock anchor | Step 5: server-source allowlist cited as SECURITY §4.1; it's anchored at **ARCH §4.1** (SECURITY §4.1 is tenant-isolation posture) |
| **Quote-completeness drift** | Dropped word/phrase from a verbatim quote | PR-B dropped prepositional phrase from a PR #66 quote |
| **Header/TOC-vs-body drift** | Stale TOC or count vs the body it summarizes | row #7 SECURITY HTML stale TOC |
| **Count / number drift** | Wrong instance count or mod number | Step 5: `api/` labeled Lock-14 mass-assignment as mod #1; canonical is #1 typed-input / #2 mass-assignment |

**Procedure:**
1. Identify every canonical citation in the brief/finding/draft (Lock N, ADR-NN Decision M, `§x.y`, "K instances", "mod #N").
2. For each, read the source verbatim — `grep -n` the anchor; open the DECISIONS.md Lock; count the catalogued instances. Don't rely on memory or a recalled count (memories reflect what was true when written — verify the live value).
3. Compare. On a mismatch, **fix at source before forwarding** (surgical edit), and note the fix at the boundary so the next reviewer has a hook.
4. When no drift exists, the cross-check still adds confidence — say so ("cross-checked X verbatim; accurate").

## Discipline 2 — 2-teammate independent verification

For a **high-stakes brief-vs-canonical boundary** (a one-way door, a §10 ledger change, a Lock-family count, a security-load-bearing claim), have **two independent teammates** verify the same claim without seeing each other's verdict.

- **Convergence** (both reach the same verdict) = strong validation — promote with confidence.
- **Divergence** = the boundary surfaced real drift — reconcile against canonical before forwarding.
- Live example: Wave 5 — PM caught a team-lead Lock-14 `5→7` dispatch drift; Architect v2 **independently** caught the same drift ~30 sec later. Two-teammate convergence validated the discipline extends beyond Sec-load-bearing surfaces to architectural housekeeping.

Reserve this for genuinely load-bearing boundaries — most claims need only Discipline 1. Use the cost (a second dispatch) only where a wrong promotion is expensive to unwind.

## Where to apply (the boundary hooks)

- **At every dispatch** — embed the verify hook in the brief ("read X verbatim; cross-check the 3 axes; surface drift inline before SendMessage") so the teammate's reply is self-checking.
- **At every ratify / sign-off** — before relaying a finding or v1 to F/CTO, run Discipline 1 over its citations.
- **At v1-drafted-against-assumed-ratify** — add an explicit ratify-assumption flag at the top of the v1 (per `feedback_post_ratify_v1_cross_check`) so the post-ratify cross-check has something to verify against.

## Failure modes

- **Trusting Edit-success as structural confirmation** — a successful edit doesn't prove the surrounding content is correct; re-grep the result.
- **Verifying against a recalled number** — recalled counts (DEFINER allowlist size, Decision 3 instance count, RT-catalog size) drift; read the live source, not the memory.
- **Self-triggered task_assignment echo** — a teammate self-claiming a task emits an async echo ~70% of the time; instruct teammates to silently drop self-triggered notifications (pre-brief block).
- **Skipping the cross-check because the claim "looks right"** — the citation-attribution and count classes specifically defeat eyeballing; the discipline is mechanical for a reason.

## Notes

- Composes with `spawn-sec-joint-review` (the Sec-Lock cross-check is Discipline 1 applied to Sec findings) and the §10 3-axis cross-check (instance-numbering / layer-attribution / verbatim-vs-paraphrase per `feedback_decision_4_instance_ledger_cross_check`).
- This is **CoS/team-lead-owned** (the CoS role is absorbed into the main session per [ADR-009](../../../DECISIONS.md#adr-009) Decision 1). It is mandatory pre-reading at any ratify/relay boundary, not a push-button skill.
- Origin: Phase 4 lessons-learned ("brief-vs-canonical-ADR cross-check new boundary class") + the 7-application team-lead Sec-Lock cross-check track record; Phase 5 Step 5 added two fresh applications (anchor-drift + mod-number-drift catches).
