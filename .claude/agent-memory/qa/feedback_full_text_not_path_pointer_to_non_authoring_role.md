---
name: feedback-full-text-not-path-pointer-to-non-authoring-role
description: When handing commit-ready content to a teammate who commits on my behalf, send the complete text unprompted for a first/small hand-off — but for a large file under repeated revision, set up my own worktree and hand off a path + self-verified `git diff --no-index`, so the receiver can check mechanically instead of transcribing.
metadata:
  type: feedback
---

QA doesn't commit to item branches (architect/backend own them; QA sends
commit-ready text via SendMessage per the dispatch ground rules). After editing
a test file in the shared checkout, I told architect "it's at this path, let me
know if you want it pasted" instead of just sending the full text. Architect
correctly refused to hand-apply edits from a path description (would make them
a second, unreviewed author of my file) and asked for the full paste — a round
trip that cost time.

**Why:** the hand-off rule ("send commit-ready file text — full paths + complete
contents") exists precisely because the receiving party cannot commit on trust;
they need the literal content to either apply it themselves or (as architect did
here) fingerprint it against what's already committed. A path is not
commit-ready text, even when accurate, because it asks the receiver to either
trust an unread description or go read a file in a workspace that isn't theirs.

**How to apply:** whenever handing off content to a role that will commit or act
on it and does not read/write the same worktree I do, send the complete text
unprompted on the first message — never a location + an offer to paste on
request. This applies every time, not just when explicitly asked.
[[feedback_subagent_relay_format]] [[feedback_credential_redaction_in_subagent_prompts]]

**⚠ UPDATE, same session, same file, four rounds later: paste stops being the
right channel once the file is large and gets revised more than once.** Once
this hand-off went through several correction rounds on a ~600-line file, both
architect and team-lead redirected me to a different channel: create my OWN
worktree (`git worktree add <path> --detach <ref>`, sibling to the other
per-agent worktrees), write the corrected file there at its repo-relative
path, self-verify with `git diff --no-index <their-committed-file>
<my-worktree-file>` BEFORE handing off, and send the ABSOLUTE PATH plus that
diff output — not a paste. Architect's stated reason: "I cannot verify delta-
confinement from a paste without transcribing the whole file, which measures
my typing rather than your change." A path lets them run one mechanical `git
diff` against the real committed sha instead of re-reading 600 lines by eye
every round.

**Reconciling the two rules:** paste (full text, unprompted) is still correct
for a FIRST hand-off, or any file small/stable enough that transcription risk
is negligible. Once a file is large AND under active back-and-forth revision,
switch to worktree+path+self-verified-diff — set up the worktree once, reuse
it for every later round on that item. The failure mode either way is the
same shape: making the receiving party do work (ask for a paste, or
transcribe one) that a five-minute setup on my side would have avoided.
