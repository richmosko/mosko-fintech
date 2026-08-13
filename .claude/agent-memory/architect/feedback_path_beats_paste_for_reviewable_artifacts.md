---
name: path-beats-paste-for-reviewable-artifacts
description: For an artifact the receiver must verify, hand over a readable path — a paste adds a transcription surface and cannot be grepped
metadata:
  type: feedback
---

When handing a teammate an artifact they are expected to **verify** rather than
merely read, give them a path they can open and grep. Do not paste the file.

**Why:** SELF-218, 2026-08-12. QA sent a 594-line pgTAP battery by path, then
apologised for it and re-sent the full text "as requested." The path was the better
channel and the apology was aimed at the wrong thing. A path let me run mechanical
checks the paste could not support — regex-measuring the battery's zone fence against
the migration's actual `prosrc`, and checking the fixture's `063` insert against that
table's two CHECK constraints. A paste of that size also introduces a transcription
surface the path does not have: to compare the two I had to fingerprint distinctive
phrases rather than diff, precisely because re-typing it would have manufactured
differences that were mine.

**How to apply:**
- Hand over a path for anything the receiver will verify, diff, or grep. Paste only
  short excerpts, or content that has no file yet.
- ⚠ **Location matters as much as format.** QA wrote into the shared checkout, which
  is team-lead's read anchor and should stay clean — their own worktree or `temp/`
  gives the same readable artifact without leaving an untracked file in the anchor.
  Say *which* path, not just "by path."
- If you receive both a path and a paste and must confirm they agree, **fingerprint
  distinctive phrases rather than re-typing to diff**. Re-typing to compare is
  measuring your own transcription.
- Corollary for reviewers: when a teammate apologises for a good practice, say so.
  An apology that hardens into a convention makes future handoffs worse.
