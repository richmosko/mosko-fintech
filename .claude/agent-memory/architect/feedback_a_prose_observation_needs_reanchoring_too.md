---
name: prose-observation-needs-reanchoring-too
description: The re-read-before-you-relay rule applies to observations about CONTENT, not only to shas, md5s and counts — a prose finding measured on mid-edit bytes ships as a false accusation
metadata:
  type: feedback
---

Re-read the artifact in the same turn you relay a finding about it — **including
when the finding is about wording rather than about an identifier.**

**Why:** at SELF-330 I sampled a teammate's file three times while they were
mid-edit, observed that a doc-comment paragraph "still opens with the superseded
quote", and carried that into a report as though it described their delivery. It
described a draft that existed for about a minute. **They caught it; I had to
retract.** All session I had rigorously re-read shas and md5s in the same turn as
relaying them — and exempted a *prose observation*, because a statement about
wording does not feel like the kind of claim that goes stale.

It is exactly the kind that does. Worse, it is the kind nobody can cheaply
re-check: a wrong sha is caught by the next command, a wrong characterisation of
someone's comment sits in the record until they happen to read it.

**How to apply:** before reporting "file X says Y", re-read X — from the
**committed bytes** (`git show HEAD:path`) when it is committed, since that is
what actually ships. If the observation came from a worktree read while the
owner was active, it has no standing at all: treat it as a draft note, not a
finding. And when a teammate pushes back with a specific claim about their own
bytes, **measure before defending** — twice on that branch a teammate's
correction was narrower and better-evidenced than my original claim.

⚠ The irony worth remembering: the paragraph I mis-reported was itself being
fixed because it quoted a source that had since been corrected. Same failure,
one level up.

Related: [[feedback_relay_from_the_tree_not_the_report]],
[[feedback_reread_the_ref_before_dispatching]],
[[feedback_incoming_message_is_not_newer_state]],
[[feedback_cited_precedent_transmits_its_retracted_half]].
