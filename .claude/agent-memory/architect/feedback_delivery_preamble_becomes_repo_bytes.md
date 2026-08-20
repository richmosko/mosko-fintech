---
name: delivery-preamble-becomes-repo-bytes
description: When you are the commit owner, a teammate's file arrives with a header addressed to YOU — and that header becomes repo bytes, often asserting a status that the delivery itself has already falsified
metadata:
  type: feedback
---

**Read the first ~15 lines of every teammate-authored file before committing it, as
repo content rather than as a message to you.** A delivery wrapper is written at the
moment of hand-off and is addressed to the integrator; committed unchanged, it becomes
a permanent claim in a file whose readers are not you.

**Why:** QA delivered a pgTAP battery they had just run to **20/20 PASS**, having fixed
three real bugs the run caught. Its first twelve lines read
`DELIVERY (QA -> Architect …)` and `Status: DRAFT … UNVERIFIED — 084 has not been applied
anywhere I can run pg_prove against. Recommend a joint scratch-DB dry run before this
lands.` Every word was true when written and false by the time it was delivered. Shipped,
it would have told the next reviewer the battery was never executed — and a status line
is the one comment a reviewer trusts without checking. The comparable landed battery
(`082`) starts straight at its `=====` box with no preamble: **that shape is the tell.**

**How to apply.** Diff the incoming file's opening against a landed sibling of the same
kind. Anything of the form *delivery / status / recommend / pending / TODO-before-landing*
is wrapper, not content. ⚠ **Route it back rather than fixing it** when the file is in
someone else's ownership zone (`supabase/tests/` is QA's; Architect neither authors nor
edits there) — and say precisely which lines and why, because "fix your header" reads as
style and "your file asserts it was never run" reads as the defect it is.

⚠ **Check the wrapper for substance before it is stripped.** That same preamble was the
only place carrying a *critical-path* item — that `084` drops the CHECK `009`'s battery
asserts, so `009` goes RED on merge unless its legs are dropped. Telling someone to
delete a block without first mining it is how a real obligation leaves with the packaging.

Related: [[verify-the-bytes-you-commit]] · [[an-incoming-message-is-not-newer-state]] ·
[[a-self-authored-label-hardens-into-fact]]
