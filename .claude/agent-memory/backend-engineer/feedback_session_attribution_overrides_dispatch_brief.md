---
name: session-attribution-overrides-dispatch-brief
description: A dispatch brief's named commit trailers (Co-Authored-By / Claude-Session) can be stale — the system-reminder issued at session start is the live source of truth and explicitly says it replaces earlier guidance.
metadata:
  type: feedback
---

When a team-lead dispatch brief names specific commit trailers (e.g. "Co-Authored-By: Claude Fable 5.1" + a `Claude-Session` URL), check the session's own system-reminder first — it carries the current attribution block and states verbatim that it "replaces any earlier attribution guidance." The two can disagree (observed: brief said Fable 5.1 + session_01Tb…, system-reminder said Sonnet 5 + session_01Sk…) because the brief was written by an earlier session whose reminder has since rotated.

**Why:** the system-reminder is regenerated per-session and is authoritative for *that* session's commits; a brief is a snapshot from whenever team-lead wrote it and can carry a prior session's identity forward by copy-paste.

**How to apply:** always use the live system-reminder's trailers for actual commits, not the brief's. Flag the mismatch in the hand-off's "Bubble up" section (one line) rather than silently overriding without mention — team-lead may want to know its brief template is stale.
