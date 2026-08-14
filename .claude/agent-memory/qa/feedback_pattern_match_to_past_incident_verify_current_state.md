---
name: feedback-pattern-match-to-past-incident-verify-current-state
description: Found pfin_etl NOLOGIN-but-password-set on the shared cluster and concluded it was residue from my own earlier incident this session — plausible, wrong. Team-lead corrected it: F/CTO had deliberately reissued the credential afterward for a pending seeding run. The signal pattern-matched the incident; the cause was different, current, and legitimate.
metadata:
  type: feedback
---

Ran `supabase test db` against a scratch DB and got a real, unexpected failure:
migration 054's h14 leg (pfin_etl must be NOLOGIN with NO password) failed —
`pg_authid.rolpassword is not null` was true on the shared cluster. I had a
strong, specific memory of an earlier incident THIS SAME SESSION where I set a
password on this exact role and only partially disarmed it (LOGIN off, password
never cleared). The shape matched exactly, so I diagnosed it as residue from
that incident, reported it precisely, and — correctly per
[[feedback_postgres_roles_are_cluster_level_not_per_db]]'s own lesson — did NOT
act unilaterally, asked team-lead for sign-off before touching the role.

**The diagnosis was wrong.** Team-lead: *"the password on the cluster is NOT
residue from the incident. After your disarm, F/CTO deliberately REISSUED a
fresh pfin_etl credential... for the pending production seeding run. The
operational convention for this role is: password SET, LOGIN OFF between uses...
The signal pattern-matched your incident; the cause is different."* Had I been
approved and run `ALTER ROLE pfin_etl PASSWORD NULL`, I would have destroyed a
legitimate, deliberately-issued credential and forced a second real reissue —
recreating the exact failure class the sign-off gate exists to prevent, just
one layer downstream of where I'd already stopped myself.

**Why this is a distinct lesson from the original incident, not a restatement
of it.** The original lesson is about ACTING (don't ALTER a shared role from
what looks like a sandbox). This one is about DIAGNOSING: having a strong,
specific prior memory of causing a particular signal is not evidence that THIS
occurrence of the same signal has the same cause. A past incident makes a
matching signal MORE available to recall, not more likely to share the cause —
availability is not likelihood. The correct move when a current observation
matches a known-incident shape is to check current state that would
distinguish "leftover from then" (nothing since disarm) from "legitimate now"
(a deliberate change since, e.g. `workers/etl/.env`, a recent commit, a
teammate's own recent action) — not to report the pattern-match as a
root cause. I reported it as a conclusion ("root-caused it") rather than as a
hypothesis, which is the part to fix.

**How to apply:** when a current finding resembles a past incident I personally
caused, treat the resemblance as a hypothesis to check against current state
(what changed since, who else touches this surface, is there a legitimate
reason), not as the explanation — and say "this looks like X, checking for a
more recent cause" rather than "root-caused: this is X" until that check is
actually done. The sign-off-before-acting discipline from
[[feedback_postgres_roles_are_cluster_level_not_per_db]] is what kept a wrong
diagnosis from becoming a second real incident — keep asking before mutating a
shared credential even when the cause seems obvious, ESPECIALLY when it seems
obvious because it matches something already in memory.
