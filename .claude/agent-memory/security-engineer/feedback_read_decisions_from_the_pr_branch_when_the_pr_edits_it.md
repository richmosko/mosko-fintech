---
name: read-decisions-from-the-pr-branch-when-the-pr-edits-it
description: A citation has FOUR independently-falsifiable axes — POINTER (bracketing ## ADR- header; DECISIONS.md is not in ADR-number order), CONTENT (read the decision's AMENDMENTS, not only its body), EXTENT (a verbatim quote can license a false inference about what it omits), and ATTACHMENT (an inherited citation re-hung on a narrower proposition supports nothing); plus run the D4 hook against the PR BRANCH and enumerate defects with the bare label, not a filtered grep
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

**⚠ A FOURTH VARIANT — ATTACHMENT: pointer right, content right, extent right, and the citation still
false because THE PROPOSITION IT HANGS ON NARROWED IN TRANSIT.** Caught at SELF-246 / `090`
(`pfin.cashflow_target`). The migration argued Decision-3 **family +0** and supported it with
*"`users_id -> auth.users(id)` IS the tenant anchor ... (the same ground on which `053` / `063` sit
outside the family)."* Both migrations are real, both genuinely sit outside the family, and the
sentence quoting them was inherited **verbatim** from ADR-011 **Decision 18's own forward note** on
this very table. Every axis above passes. It is still wrong: `053` / `063` say in their own table
comments *"NO users_id, NO FK-shaped column"* — they sit outside on the **no-tenant-dimension**
ground and cannot support a claim about a **tenant anchor**, having none. In D18 the citation hung on
the recorded TALL shape's *absence of an FK-shaped reference column*, where it was at least the same
predicate; the build moved to the WIDE row and the author re-hung the same parenthetical on the
narrower *anchor* claim, where it supports nothing.

**The instrument: go read the cited artifact's own words about ITSELF, not the citing text's gloss of
it.** One `grep` of `053`/`063`'s table comments settled it in a single command. The precedent that
actually holds was two greps away and inside the document the hook already requires reading live —
**D3's own body** (*"`pfin.posting_prototype.users_id` is that table's own tenant anchor"*) and **D9's
2026-07-24 amendment** (*"the history table's `trans_id` is the sole anchor / NOT-D3"*).

**Why it earned a block rather than a note, when the CONCLUSION it supported was CORRECT and
independently verified:** migration headers in this repo demonstrably become the model for the next
table in the family (`090`'s own header is `074`'s, reshaped), and this one is the template for the
three unbuilt Lock-14 members. A bad precedent propagates as a *good* one — the next author inherits
it exactly as this one did, which is the whole mechanism. **Grade the citation on its own axis, not
on the truth of what it was offered to prove.** And when the drift is inherited, say where from and
route the correction to the SOURCE too — otherwise the fix is one copy deep and the well is still bad.

Related: [[sec-lock-cross-check-catches-my-own-misreads]] (read the source the text CITES),
[[measure-the-fence-regex-not-its-comment]], and [[which-ref-the-probe-was-aimed-at]] in the project
index.

**⚠ ATTACHMENT axis, fifth instance — CLAUSE-NAME BLEED FROM THE ADJACENT SENTENCE.** At PR #564
the code comment paraphrasing my own binding text wrote *"M1/M4 are inert here (084's **P3 CASE /
txn CTE** never surface those rows)"*. My source said *"M1/M4 inert by **P3's where**"*. Measured at
`084:864–888`: P3 carries BOTH a `CASE` and a `WHERE`, and the exclusion is entirely the `WHERE`
(`transaction_type='standard' and security_id is null and split_count=0 and amount<>0`). **A `CASE`
cannot exclude a row — it maps values, and its `else` arm here is the catch-all `Suspense`.** The
mechanism is visible in the diff: the *preceding* sentence correctly borrows the source's
*"P3 CASE + its txn CTE carry no `is_reverse` term"* — true, and about the **gap** — and the *next*
sentence reused those clause names for a **different proposition** (what makes M1/M4 inert). Every
word was real and sourced; only the attachment moved one sentence over.

**Two durable pieces.** (1) When a paraphrase names a *mechanism* (`WHERE` / `CASE` / CTE / trigger
/ policy), the clause type is falsifiable on its own — go read which clause actually does the work,
because a wrong one tells a future reader to protect the wrong line. (2) **Adjacent sentences in the
source that share vocabulary are the drift vector**: if two neighbouring claims use overlapping
clause names for different propositions, expect the paraphrase to collapse them. Check the
neighbours of any sentence I am asked to verify, not just the sentence.

**Corollary that arrived the same session: the paired TEST can be the correct statement while the
HEADER is wrong, in the same commit.** `isTradeConstraintViolation`'s header claimed the excluded
raise *"mirrors the generic 500"*; measured, its `(sub_cat_id %)` text is claimed by
`isCrossTenantSubCat` first — and the collision-guard test's own title said so correctly. **When a
comment and its test disagree about a fact, the test is usually right** (it was executed) and the
comment is the artifact to fix — but say which one you measured, because "the test says X" is not
itself a measurement of X.
