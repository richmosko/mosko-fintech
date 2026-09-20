---
name: grade-a-posture-reversal-by-which-artifact-carries-it
description: Before agreeing a change "reverses a ratified security decision," read the sources and separate the artifact carrying the POSTURE from the one carrying the MECHANISM — and name the single measurement that would invert the ruling.
metadata:
  type: feedback
---

**A proposal framed as "this reverses ratified Decision N" is usually a claim about a MECHANISM sentence, not
about the posture. Read both sources before grading, and say which one carries which.**

**Why:** flipping `007`/`015`'s decrypt views to `security_invoker = true` was presented as reversing ADR-011
Decision 8 / Lock 4 mod #1, because `015`'s header says *"Not security_invoker (owner-semantics required to
resolve the vault join)."* But **both migration headers carry the posture in Sec's own recorded words —
*"the service_role-only grant gives the identical security property"*.** The ratified posture is **the grant**;
the `security_invoker` sentence is a **mechanism** claim written for a `postgres` owner, before the grantee's own
reach was measured. The flip touches no grant, so RT-02 containment and the battery's `authenticated`-negative
leg are unaffected — and it **strengthens** isolation by making the view RLS-subject instead of owner-exempt.
Grading it as a posture reversal would have cost the team the better option.

**How to apply:**
- **Name the single measurement that would INVERT the ruling, and check whether the tree records it.** Here:
  `has_table_privilege('service_role','vault.decrypted_secrets','SELECT')`. The battery asserts the negative for
  `authenticated` and says **nothing** about `service_role`, and **schema USAGE is not a table privilege** — do
  not let the two be conflated. If FALSE, the "reduction" inverts into a VETO, because making it work would
  require granting the grantee the whole-vault surface the design exists to refuse.
- Owner-semantics buys a property **only while the grantee lacks the reach**. Re-derive that premise whenever
  the owner changes — see [[uniform-response-rationale-vs-built-predicate]].
- When approving, require three artifacts: the stale header **corrected in place** (keep-and-annotate), an ADR
  amendment recording that **the mechanism moved and the posture did not**, and a **new test leg pinning the
  measurement**, because the flip makes a previously-incidental privilege load-bearing with no watcher.
- Say plainly when the re-read makes the change **smaller** than proposed. An agent asking "grade the reversal
  rather than treating the re-read as licence" is doing the right thing and should get a real grade back.
