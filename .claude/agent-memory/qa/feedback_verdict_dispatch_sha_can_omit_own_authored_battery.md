---
name: verdict-dispatch-sha-can-omit-own-authored-battery
description: A close-gate verdict GO can name a sha whose merge premise-check missed that the close-gate FILE ITSELF (authored on a separate feature branch) was never merged — confirm the file exists at the named sha (git show/ls-tree, not memory of having written it) before running any of the verdict steps that assume it.
metadata:
  type: feedback
---

Dispatched a P10 (SELF-362) close-gate VERDICT GO at `main = eda1179`, framed as "P6 merged;
every V1.5 surface and migration 106–115 is on it." Ran steps 1–2 of the verdict brief cleanly
(scratch DB rebuild + clone, full pg_prove battery — 109 files, 2886 tests, exactly the two
expected pre-existing local-only reds and nothing else). Step 3 ("run
`self362_v15_close_gate.sql` standalone") is where it broke: the file does not exist ANYWHERE in
`eda1179`'s tree.

**Root cause**: I (this same QA identity, earlier in the same session) authored that file on
`feature/self-362` across 7 commits — but that branch was never opened as a PR at all
(`gh pr list --head feature/self-362` returns empty), let alone merged. The verdict dispatch's
own premise-check evidently verified the SEVEN OTHER V1.5 feature branches (P2/P3/P4/P5/P6/P7/P8)
merged, but not the close-gate file's own branch — an easy thing to miss precisely because it is
QA's OWN authored artifact, not one of the seven walked surfaces, so it doesn't appear on the
same checklist.

**Did NOT do to route around it** (both would have been wrong): (a) copy the file from my own
worktree onto the scratch clone — that verifies different bytes than what the named sha actually
contains, defeating the entire point of a single-sha verdict measurement; (b) merge
`feature/self-362` myself to unblock — a merge decision belongs to whoever owns that call, not to
an agent mid-verification-run.

**What I did instead**: stopped immediately at the point of discovery, reported the completed
steps (1–2, still valid — they never touched the missing file) plus the STOP with the concrete
evidence (`git show <sha>:<path>` exit code, `git ls-tree -r <sha>` grep, the empty `gh pr list`
result), and held for redirection rather than guessing at a resolution.

**How to apply**: before running ANY verdict/close-gate step that assumes a specific file or
battery exists at a named sha — especially one you personally authored earlier in the session —
positively confirm it's present at THAT sha (`git show <sha>:<path>` or `git ls-tree -r <sha> |
grep`), never from memory of having written it. A file you know you wrote is not evidence it
landed on the branch someone else is about to verdict. This generalizes
[[feedback_signature_change_invalidates_catalog_assertions]] (hash the committed blob, not the
worktree file) one level up: confirm the blob is reachable from the named ref at all before
trusting any claim about its content.
