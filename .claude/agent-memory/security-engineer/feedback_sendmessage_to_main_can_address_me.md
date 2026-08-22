---
name: sendmessage-to-main-can-address-me
description: A brief saying "return via SendMessage to main" can fail with "you ARE the main conversation" — fall back to the sender's teammate_id, not to plain text
metadata:
  type: feedback
---

When a task brief says *"return via SendMessage to `main`"*, that address is not guaranteed to resolve
to the dispatcher. Depending on how the session was spawned, `to: "main"` returns
`You are the main conversation — "main" addresses you. Send to a named agent instead.`

**Why:** at the SELF-332 / ADR-061 review I hit exactly this, fell back to plain-text output, and only
the idle-notice **summary** reached team-lead — the entire AMBER verdict, the file:line, the clearance
condition, and the verify-hook results were invisible. Team-lead had to ask for it a second time. Plain
text is not a fallback channel; it is a dropped message that *looks* delivered.

**How to apply:** if `to: "main"` errors, immediately re-send to the **`teammate_id` on the inbound
`<teammate-message>`** (here, `team-lead`) — that is the address that actually works, and it is already
in the transcript. Say in one line that you rerouted and why, so the recipient knows the address in the
brief is wrong for next time. Never conclude "I am main, so I'll just answer in prose" — verify by
sending, not by inferring, and treat a failed send as an undelivered finding until a `success: true`
comes back.

Related: [[temp-handoff-paths-are-per-worktree]] (a relay may forward a pointer rather than the text —
same class: the finding is not recorded until it lands somewhere the reader will look).
