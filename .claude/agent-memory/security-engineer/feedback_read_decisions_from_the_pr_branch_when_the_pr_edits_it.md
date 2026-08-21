---
name: read-decisions-from-the-pr-branch-when-the-pr-edits-it
description: A citation has THREE independently-falsifiable axes — POINTER (bracketing ## ADR- header; DECISIONS.md is not in ADR-number order), CONTENT (read the decision's AMENDMENTS, not only its body), and EXTENT (a verbatim quote can license a false inference about what it omits); plus run the D4 hook against the PR BRANCH and enumerate defects with the bare label, not a filtered grep
metadata:
  type: feedback
---

**Two mechanics that decide whether a §10 / Decision-3 verify-hook is even pointed at the right
text.** Both bit on the SELF-324 / `074` joint review.

**1. If the PR touches `DECISIONS.md`, read Decision 4 from the PR BRANCH.** The hook says "read D4
verbatim and live"; *live* means the ref under review, not `origin/main`. A PR that adds an ADR near
the top shifts every line below it, and a PR extending Decision 3's enumeration is editing the very
document the hook consults. Use `git show <ref>:DECISIONS.md` and cite the branch line number. On
`074` D4 was textually identical to main's — but that is a *result*, not something to assume.

**2. `DECISIONS.md` is NOT in ADR-number order** (hybrid consolidation format; newest ADRs go near
the top), so a line number tells you nothing about which ADR owns a passage. To attribute a ruling,
find the nearest **preceding** `^## ADR-` header:

```
awk -v L=<line> 'NR<=L && /^## ADR-/ {h=$0} NR==L {print h}' DECISIONS.md
```

This is how I caught a **false-composite citation**: three sites asserted *"class membership is not a
catalogued instance (ADR-047's ruling for the `058` fences)"*. Both halves are real — ADR-047 exists,
the `058` ruling exists — but the ruling is **ADR-042's**, which says so itself two paragraphs on
(*"the identical ruling THIS ADR's Consequences already made for the `058` fences"*). ADR-047 sits at
a *lower* line number than ADR-042 despite the higher number, so eyeballing position would have
confirmed the wrong answer.

**Why it was worth blocking on rather than flagging:** one of the three sites was inside **ADR-011
Decision 3's canonical enumeration** — the document every agent is required to read live. A false
provenance pointer there is the highest-leverage place in the repo to be wrong. **The tell that it
was a slip, not a misunderstanding: the same PR cited ADR-042 correctly twice elsewhere**, and the
wrong pointer had already fanned out to three sites in one PR — copying, not reasoning
([[conditional-rearmed-by-transcription]] in the project index names fan-out as the free tell).

**Also confirmed here, worth reusing:** when a new Decision-3 label collides *textually* with an
older bullet that records a discarded draft of the same number, **leave the old bullet unedited** —
it NAMES a never-allocated label, the new one ASSERTS an allocation, and D4's own CHANGELOG draws
exactly that distinction. A consistency sweep "fixing" the collision would destroy the record of why
the label was free. Say so in the review so a later tidy-up doesn't.

**⚠ I then broke this rule inside the same message that stated it — twice.** (a) I read D4 from the
branch (right) and ran the **attribution grep against the worktree's `main` copy** (wrong), so my line
citations were stale by exactly the +45 the new ADR's own insertion introduced. *Consistency within a
single review is not automatic — if one probe is aimed at the branch, aim them all there.* (b) I
enumerated the bad citation at **three** sites using `grep ADR-047 | grep -i "058\|class member"`;
Architect found a **fourth** by grepping the **bare label**, in a Cross-references list where neither
filter string appears. **A filtered grep is a claim about the filter, not about the tree** — so
enumerate a defect with the broadest pattern that identifies it, and prefer handing a reviewer *"grep
this label across branch-authored text"* over a list of sites to visit, which caps them at my recall.

**⚠ THERE IS A THIRD AXIS: EXTENT** (Architect's, offered at the D18 amendment and accepted). **A quote
can be verbatim and still license a false inference about what it OMITS.** There, both pointer and
content were right — right ADR, right words — and the *extent* was wrong: a locked sentence was quoted
up to its first semicolon and declared false, while its tail carried a live standing Sec obligation
about a different surface. **Extent is invisible to every check that verifies the quoted text, because
the quoted text is true.** It surfaces only by opening the source and reading past the closing
quotation mark. So: **verifying a quotation is not verifying its scope.** Where a retraction is
clause-scoped, require the scope stated — and fix it **at the HEADING**, not only in the body, since a
skimmer who stops at *"a second locked claim is now false"* voids the whole sentence regardless of
what the paragraph says.

**The unifying rule, worth more than any single half — a citation has THREE independently-falsifiable
axes, POINTER · CONTENT · EXTENT, and verifying one does not verify the others.** The same branch produced
one of each: a *right-pointer/stale-content* defect (ADR-042 D5a cited faithfully **without the
retraction its own Amendment had attached**) and a *right-content/wrong-pointer* defect (ADR-042's
ruling attributed to ADR-047). Checking one is exactly the habit that lets the other through. So:
locate the pointer by bracketing header, **and** read that decision's AMENDMENTS in the same pass.

**⚠ THE CONCRETE CASE THAT LOOKS LIKE A WRONG POINTER AND IS NOT: ADR-011 Decision 9.** Its title is
`Lock 5 / Flag E2: acct_number storage class`. Every brief that says "read the V1 SECURITY DEFINER
allowlist at ADR-011 Decision 9" is **correct**, but the body is about `acct_number` masking — the
allowlist lives entirely in D9's **three Amendments** (2026-06-25 `3→2`, dropping the pure transform
`fn_mask_acct_number`; 2026-06-29 `2→3`, adding `fn_grant_creator_access`; 2026-07-24 `3→4`, adding
`fn_reclass_history_insert`). Current shape: **committed 4, authored-in-migrations 3** — the reserved
general-audit-log helper is unauthored — but read it live; it grows. A reviewer who checks the title
and stops will report a citation defect that does not exist. **The reverse of the usual failure: here
the body contradicts the pointer and the AMENDMENTS vindicate it.** Same instrument either way — read
the amendments in the same pass, every time.

⚠ Related but do **not** merge them: **Lock 11 is ADR-011 Decision 15** (`monthly_report` snapshot
store), whose Sec mod reads *"V1-SHIP-BLOCK SECURITY INVOKER on read-time composition (no DEFINER
bypass)"*. Lock N and Decision N do not correspond in ADR-011 — Decision 9 is Lock 5, Decision 15 is
Lock 11, Decision 17 is Lock 13. Resolve a "Lock N" citation through the decision headings, never by
treating N as the decision number.

Related: [[sec-lock-cross-check-catches-my-own-misreads]] (read the source the text CITES),
[[measure-the-fence-regex-not-its-comment]], and [[which-ref-the-probe-was-aimed-at]] in the project
index.
