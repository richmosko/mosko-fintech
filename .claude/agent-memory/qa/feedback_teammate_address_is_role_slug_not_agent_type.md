---
name: teammate-address-is-role-slug-not-agent-type
description: SendMessage to:"security-engineer" failed with "no agent reachable" — the live teammate name is "sec", not the agent-type/subagent_type string. ListAgents gives the real address.
metadata:
  type: feedback
---

Sent the SELF-257 AC11 diff to `to: "security-engineer"` (the subagent_type / role name
used everywhere in prose, ADRs, and the system prompt) and got `success: false` — "No
agent named 'security-engineer' is reachable." `ListAgents` showed the actual roster
entry is named `sec` (`security-engineer · roster · joined ...`). Same shape likely
applies to other roles: the prose name ("architect", "backend-engineer") may not be the
live teammate's short name in THIS session's roster.

**How to apply:** before a `SendMessage` to a teammate whose exact live name you haven't
used yet this session, call `ListAgents` first (or reuse a name you've already
successfully sent to) rather than assuming the role/agent-type string is the address. A
failed send is silent-looking but recoverable — the tool result says `success: false`
with the real error; don't retry the same string twice, resolve the name and resend.

Related: [[feedback_liaison_report_first_protocol]] — a different silent-failure shape
(delivered but swallowed) vs. this one (never delivered, but the tool tells you so
immediately if you check the result).
