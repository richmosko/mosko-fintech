---
name: plain-text-response-invisible-to-teammates-in-team-mode
description: In team mode, a plain-text turn (not a SendMessage call) is invisible to teammates even when it looks like a direct reply to their request — confirmed by a real miss handing off a PR body.
metadata:
  type: feedback
---

Team-lead asked for the full drafted PR body "inline in your reply." I answered with a plain-text
message (not a SendMessage tool call) — it rendered fine to the user/session transcript but never
reached team-lead. They had to send a diagnostic ping ("your idle notification arrived but the PR
body text didn't") before I caught it and resent via SendMessage.

**Why:** this is the exact rule already in the system prompt ("Just writing a response in text is
not visible to others on your team") — but it's easy to slip on when a teammate's phrasing ("send
me X inline in your reply") reads like an instruction to answer directly rather than to invoke a
tool. The phrasing is about *content*, not *channel*.

**How to apply:** any time a teammate (not the user) asks for text, data, or a deliverable, the
answer is a SendMessage call to that teammate — never a bare text turn — regardless of how the
request is phrased. If the turn also needs to say something to the user/session, that's a separate
concern; it doesn't substitute for the SendMessage. Idle/task-complete notifications firing without
a corresponding SendMessage delivery is the tell that this slipped.
