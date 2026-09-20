---
name: an-accepted-residual-must-not-silently-widen
description: A change elsewhere can make a previously-accepted residual carry a threat it was explicitly graded as not covering — re-grade it in the same change
metadata:
  type: feedback
---

When a design change moves something *behind* an already-accepted control, check what that control's acceptance was **explicitly scoped to**. An acceptance is a ruling about a named threat, not a blanket endorsement of the mechanism.

**Why:** ADR-072 Amendment 7 (D)(C)(2) accepted the `.build-sha` self-report on stated grounds — *"a stale image honestly reports its stale sha and is caught; it fails only against a container that LIES, which is not this assertion's threat model."* A later proposal moved the task's whole instruction into the image, behind that same self-report. **A stale image reports honestly; a tampered one does not — and the acceptance turned on exactly that difference.** The proposal was still net stronger (reachability improved: the instruction left the reach of the `[write]` token that could rewrite it), but the record would have said the self-report was accepted for staleness while it had become load-bearing for tampering.

**How to apply:** ask two questions of any "move X behind Y" change — (1) what threat was Y's acceptance *scoped to*, in its own words; (2) does X bring a threat outside that scope. If yes, **require the original acceptance be re-graded in the SAME change**, even when you expect the conclusion to hold. Grade the change by REACHABILITY (who can actually touch the surface, and do they gain a capability they lacked) separately from EVIDENCE CLASS (external comparison vs self-report) — they can move in opposite directions, and reachability usually dominates. Related: [[feedback_replacement_control_name_the_losing_side]], [[feedback_hazard_mechanism_vs_reachability]], [[feedback_a_disposition_without_a_mechanism]].

**Sibling rule from the same review:** *a change made to fit a budget that removes a ratified control's ONLY evidence is a control removal wearing a formatting change's clothes.* Counter-offer a re-encoding (merge three tagged lines into one anchored line) before accepting a deletion.
