---
name: a-filtered-grep-is-a-claim-about-the-filter
description: A sweep's completeness is bounded by its filter — and the FILE filter is a filter too. Also: anchor a finding list by CONTENT, never by line number.
metadata:
  type: feedback
---

Two halves of one lesson, both measured on the ADR-068 D5 direction reversal
(2026-09-05).

**1. The file filter is a filter.** I swept `docs/ARCH/index.html` for the superseded
PDF-worker direction and found twelve sites where a reviewer's list named seven —
because I grepped the **endpoint identifier** rather than the phrases anyone had
noticed. Good. But the sweep was **file-scoped**, and the same identifier was live in
`DECISIONS.md`, including **ADR-015's RT-26 canonical server-source audit-scope
enumeration** — a security surface, where deleting the entry at the naming PR would
have silently shrunk an audit scope. Sec caught what my filter excluded.

**Why:** completeness claims inherit every dimension of the filter — pattern, path,
file type, ref. Naming one dimension ("I grepped the identifier, not the prose") makes
the others feel handled.

**How to apply:** when a ruling reverses or renames something, grep the identifier
**repo-wide** before claiming a sweep is complete; then say which dimensions the sweep
covered. A reviewer's list of sites is a **lower bound**, and so is your own.

**1b. A COUNT is a claim about what counting can DISTINGUISH — and the number can be
right while the conclusion is wrong.** One sizing estimate was corrected three times:
diff-stat → grep counts → reading the file. **None was wrong at the level it was
measured at.** "Seven references to the old predicate" and "two structural assertions
that will go RED, plus five incidentals" are the *same number*. The under-scope and the
over-scope both came from a correct count answering a question its instrument could not
see.

**How to apply:** before drawing a scope or effort conclusion from a count, **read
enough of the hits to know what kind they are**. Grep to find; read to conclude. And
when you report a count, say what the instrument could not distinguish.

**2. A finding list anchored by LINE NUMBER goes stale the moment the file changes
length.** Sec's FLAG-1 list was line-anchored; my fix shifted every line by one to
three; their re-review then read the numbers against an older ref and reported already-
fixed sites as live, adding *"no owner action that I have seen"* — a false claim about
diligence, which cost a report to refute. **Anchor findings by content**, the same rule
already held for ADR citations ([[feedback_fix_the_citation_not_the_referent]]).

⚠ **The free tell that a list is stale before you check the tree: its count disagrees
with its own enumeration.** Sec's said "five sites" and listed seven numbers.

**How to refute one cleanly** — cheaper than arguing: read the *committed* bytes
(`git show <ref>:<path>`), give a **mechanical negative** (`grep -nE '<pattern>'`
returning nothing), the **md5** of the committed file, the new content-anchored
locations, and — the part that ends it in one round — **name the ref their numbers DO
resolve against**. See [[feedback_incoming_message_is_not_newer_state]].

**3. Corollary met the same day:** `git merge` echoes what it merged and never which
branch it merged *into*. After a sequence of switches I merged a teammate's doc branch
onto the wrong branch; it succeeded silently. Read
`git rev-parse --abbrev-ref HEAD` in the same call as any merge, rebase, or reset.
