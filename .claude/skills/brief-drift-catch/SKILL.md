---
name: brief-drift-catch
description: Mandatory pre-reading before forwarding a teammate brief, a Sec/QA finding, or a v1 draft to F/CTO ratify. Codifies the verbatim-source cross-check (read the cited Lock/ADR/§-anchor VERBATIM before relaying — catches paraphrase / citation-attribution / quote-completeness / count drift) + the 2-teammate independent verification pattern for high-stakes brief-vs-canonical boundaries + sweep-completeness (CP9 — re-grep the file, never read the diff hunk; over-match and filter; bound the claim's predicate not just its location) + the rule that a correctness claim must not forward-reference the mechanism that makes it true. Also invoke when a fix is a sweep across many surfaces rather than a single edit. CoS/team-lead-owned meta-skill.
user-invocable: true
allowed-tools:
  - Read
  - Bash
  - Agent
  - SendMessage
---

# brief-drift-catch — catch drift between a brief and its canonical source

Use when you are about to **forward** something that cites a canonical source to the next boundary: a teammate's brief/dispatch, a Sec/QA finding, or a v1 draft headed to F/CTO ratify. The skill is a set of composable disciplines — it grows, and deliberately carries no total — that turn "trust the relay" into "verify at the boundary."

mosko-fintech meta-skill (net-new; not a template adaptation). It operationalizes the memories `feedback_team_lead_sec_ratify_lock_cross_check`, `feedback_decision_4_instance_ledger_cross_check`, `feedback_post_ratify_v1_cross_check`, and `feedback_async_mismatch_boundary_hooks` into one pre-reading checklist. 7+ application track record at authoring time.

## The core principle

**Every async-ordering or relay mismatch surfaces at a boundary IF the discipline has a hook to verify against.** So build a verification hook into every dispatch and every sign-off. A claim that cites a canonical source (a Lock, an ADR decision, a `§`-anchor, an instance count, a mod number) is a hook: read the source verbatim before the claim crosses the boundary.

## Discipline 1 — verbatim-source cross-check

Before forwarding any claim that cites canonical wording, **read the cited source verbatim** (don't trust the paraphrase, even your own). Grep the anchor, open the Lock, count the instances. Then compare against the claim. The drift classes **in scope** — the table grows and deliberately carries no total:

> ⚠ **Read the last row differently from the others.** Every row above it is a failure of **fidelity**, and the procedure just described catches it. **The last row is a failure of TRUTH, and this procedure does NOT catch it** — it is listed here, inside the method, because **a discipline that can be fully satisfied while the conclusion is wrong must say so about itself or it is a false assurance.**

| Drift class | What it looks like | Live example |
|---|---|---|
| **Paraphrase drift** | Canonical content restated inexactly | PR #74 §8.5 four-layer paraphrase |
| **Citation-attribution drift** | Wrong `§`/ADR/Lock anchor | Step 5: server-source allowlist cited as SECURITY §4.1; it's anchored at **ARCH §4.1** (SECURITY §4.1 is tenant-isolation posture) |
| **Quote-completeness drift** | Dropped word/phrase from a verbatim quote | PR-B dropped prepositional phrase from a PR #66 quote |
| **Header/TOC-vs-body drift** | Stale TOC or count vs the body it summarizes | row #7 SECURITY HTML stale TOC |
| **Count / number drift** | Wrong instance count or mod number | Step 5: `api/` labeled Lock-14 mass-assignment as mod #1; canonical is #1 typed-input / #2 mass-assignment |
| ⚠ **Sound-quote / false-gloss** *(NOT caught by the above)* | A **byte-exact** quote of a source whose **claim is false**, plus a conclusion drawn from it | [ADR-043](../../../DECISIONS.md#adr-043) reason 1 quoted `059` exactly — *"V1 consumers pass CURRENT_DATE"* — and **zero callers did**. Every verbatim check passed |

> **⚠ Sound-quote / false-gloss defeats this discipline as written, which is why it is the row worth reading twice.** The quote matches, the citation resolves, the attribution is right — **and the conclusion is still false.** Catching it requires verifying the **cited source's CLAIM against measurement**, not the quotation against the source. **A verbatim check confirms fidelity, never truth.** Routed here by ADR-043, whose own text names this skill as the durable home.
>
> It also has a second failure axis worth separating: in that case the gloss *"so both sides sit on one clock"* **did not follow even if the quoted clause had been true** — the cited Lock guaranteed the date was *server*-derived and said nothing about *which server*. **Fixing the quotation alone would have produced a fourth false description.** So check the **inference** as well as the **premise**; they fail independently.

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

## Discipline 3 — sweep completeness (CP9)

When a fix is a **sweep** — one claim copied to many places — the thing to verify is not each edit but **that the class is closed.** Two rules, and they are the same failure on different axes.

**CP9 — a reviewed-adjacent line reads as reviewed. Re-grep the file; do not read the diff hunk.**
The lines most likely to escape a sweep are the ones **sitting inside the changed hunk**, because **proximity to a fix is indistinguishable from having been fixed.** Live case: a stale figure survived at `spawn-sec-joint-review` **one bullet below** a line the same PR corrected — it appeared in the diff as *context*, so every reviewer saw it and read it as handled.

**Over-match and filter by hand** (per the CP7 formulation — referenced, not restated). An exact-string sweep **cannot find a claim expressed differently**, and that limitation is **invisible from inside the result**. Live case: an exact sweep returned 5 files / 7 sites; an over-matching probe found **6 files / 11 sites**, the extra being a *growth narrative* whose terminal figure was not the hunted phrase. The over-match returned two false positives, which is the correct trade — **over-matching is auditable by hand; under-matching is not auditable at all, and its silence reads as absence.**

**Then state the sweep's scope as a predicate, not just a location.** *"Complete across these files"* invites the broad reading *"these files no longer carry X"* — which may be false about a file you just edited. **Bound what, not only where**, and name what is deliberately excluded **with the reason**, so the exclusion is a decision rather than a gap.

## What a correctness claim may cite

***A document may forward-reference a document; a CORRECTNESS CLAIM must not forward-reference the mechanism that makes it true.***

Routed here out of `apply-migration`, which keeps only the catalog-comment case. The general form governs ADRs, briefs, and **merge order**: a ratified-sounding claim whose named support is not yet in the repo is right **by accident** until the other half lands, and nothing signals the gap.

- **The fix is not to delay the claim — it is to state the dependency as the PROPERTY, naming the artifact as its current instrument.** *"…holds iff the session TimeZone is UTC, declared by `061`"* is true before and after `061` merges, and survives the instrument being renumbered or replaced.
- **Distinguish this from a dangling link.** A dangling link is a **discoverability** problem that heals on merge; a forward-referenced correctness claim is a **reasoning trap**. Conflating them produces an over-correction — they warrant different responses.

## Authorial proximity — a checkpoint AND an observation, deliberately kept separate

**Ruled by Sec 2026-08-06 as two claims, not one.** They are recorded apart because collapsing them would let the softer half borrow the harder half's authority.

### The checkpoint — ADOPTED, with its domain stated

> **After authoring a rule, DERIVE A GREPPABLE SIGNATURE FOR IT and run that signature over the whole document.**

A specific new rule usually has one — a count, a tense, a citation shape. Running it over the **whole** document beats re-reading the passages you think are relevant, because it **catches violations wherever they sit** rather than relying on the author correctly guessing which passages are "justifying." That is what converts *"be careful"* into *"produce a check."*

⚠ **Domain, stated honestly: this applies only when the rule HAS a greppable signature.** Outside that condition it does not fire at all.

⚠ **It does NOT carry CP9's authority. CP9 is unconditional and mechanical; this is conditional and mechanical only inside its condition.** Do not cite them as equivalent.

### The observation — NOT a checkpoint, and not dischargeable

> **The prose most likely to violate a new rule is the prose written to JUSTIFY it.**

**It names where to look first — nothing more.** It is not satisfied by having thought about it, and it cannot be marked done.

**Four independent arrivals in one day, from four agents** — which is what argues it is a property of *the activity* rather than of any author: an over-correction warning violated by its author's own re-pointing reasoning; a just-added carve-out violated by its author's own exclusion rationale; a demotion rationale checked against its subject but never against the file it was written in; and **a guidance bullet about verifying SSH access that reproduced, in itself, the failure class it was written to prevent.**

⚠ **That fourth arrival is why the observation must NOT be retired into the checkpoint.** It has **no greppable signature**, so the checkpoint above **would not have caught it.** The two are different claims about different territory, and the checkpoint's condition is exactly where the observation still has to do the work.

**Relation to CP9 — the same failure on a second axis:**

| | Deceiving proximity |
|---|---|
| **CP9** | **Spatial** — adjacent-to-fixed reads as fixed |
| **This** | **Authorial** — written-by-the-rule's-author reads as compliant |

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
