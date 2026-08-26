---
name: sec-lock-cross-check-catches-my-own-misreads
description: Read the source the text CITES before forwarding a drift finding — plus: a relay of my own prior words is still a relay, non-repo canonical homes exist (Linear/DESIGN flows), quote an interior span of a bold-delimited line so no normalization is possible, and MY OWN ROLE BRIEF's gloss of a Lock can be narrower than the live ADR and scope a surface OUT
metadata:
  type: feedback
---

Before forwarding any paraphrase-drift finding, read **the source the text actually cites** — not the
source you assume it paraphrased. A quotation can be verbatim-false against the neighbouring artifact
and verbatim-exact against the cited one.

**Why:** reviewing migration `067`, I flagged its quotation `"consults no clock at all"` as added-words
drift, because migration `066`'s header reads *"it consults no clock"*. `067` attributed the phrase to
the **ADR-049 amendment**, not to `066` — and `DECISIONS.md` carries *"`period_was_due` therefore
consults no clock at all"* verbatim. My finding was wrong; the Sec-Lock cross-check caught it at the
boundary, before it went to team-lead. Forwarding it would have cost a round trip and, worse, would
have pushed a correct quotation toward being "fixed".

**Third instance, and the sharpest — the CANONICAL ANCHOR can be the stale one.** Reviewing SELF-220,
migration `069`'s catalog comment cited a *ratified* ADR-053 Decision 7 disposition while
`DECISIONS.md` still read *"Routed to PM with UX; the Architect lean is…"*. Following the standing
read-DECISIONS.md-live discipline yields "built on an unratified premise" — false. The ratify was real
and recorded in `docs/DESIGN/flows/phase-2-flows-2.1-net-worth.md` §12.1, titled `RATIFIED`. **Product
and UX dispositions get ratified in the DESIGN flow docs, not always folded back into `DECISIONS.md`.**
Before filing an unratified-premise finding, check `docs/DESIGN/flows/` for a `RATIFIED` section. The
finding that survives is the missing *pointer* in the ADR, not the missing ratify.

**The same shape, second instance:** grepping for a promised deliverable across the test files I already
knew about returned zero hits — the tests were in a NEW file added by the same commit. I was one step
from reporting a missing deliverable that was present. **A zero-hit grep is a claim about the SEARCH
SCOPE, not about the tree.** Before concluding "absent", re-run against the commit's own file list
(`git show --stat`) or the whole tree, never against the file set you had in mind.

**⚠ A relay of MY OWN prior words is still a relay, and it can be the thing with no tracked source.**
Asked to supply commit-ready ADR-047 amendment text carrying a gate condition **I authored** in an
earlier session, team-lead handed me the sentence to quote. `grep -rn` over `DECISIONS.md` /
`BACKLOG.md` / `MILESTONES.md` / `CHANGELOG.md` / `docs/` found it in **no** tracked artifact — the only
survivor was an *elided* quotation at `CHANGELOG.md` v1.177, in different case and hyphenation, of the
`MILESTONES.md` block **as it read before that same entry corrected it**. Authorship does not make a
sentence citable; the reason the amendment was requested at all was that the condition had no tracked
home, so of course the wording could not be verified — **the request's own premise implied the quote
would be unverifiable, and that is the tell to watch for.** Remedy: write it as an **attributed
restatement**, say so *inside* the artifact ("faithful restatement, NOT a verbatim quotation, must not
be re-quoted as one"), cite the elided quote as the only tracked one, and tell the pen-holder that the
provenance sentence is load-bearing rather than tidy-up-able. A byte-exact quote of an unverifiable
source passes every downstream verbatim check and becomes canonical — this is the sound-quote failure
arriving through a friendly channel.

**⚠ Sequel, same session — the relay was recoverable, and then I normalized a quote in the very
paragraph warning against normalizing.** The 2026-08-07 wording WAS retrievable: my grep covered
repo-tracked artifacts, and the routing record was a **Linear comment** — so "not in the tree" meant
"not in the tree", never "does not exist". Check the non-repo canonical homes (Linear comments,
`docs/DESIGN/flows/`) before concluding a source is unrecoverable. Then, drafting the ADR paragraph
that quoted it, I rendered the comment's **first line** in italics without its stored `**` delimiters
and introduced it with *"whose first line reads"* — three lines below my own instruction *"STORED
SOURCE … do not normalize them."* **The rule and its example shared my frame; only asking the liaison
for the first line RAW separated them.** Two durable pieces: (1) when quoting from a bold-delimited
stored line, quote an **interior span** — it is delimiter-free, so an exact quotation needs no
normalization and the trap cannot fire; (2) the drift in this relay chain was three-for-three a **lost
delimiter or label** (capitalized `Before`, dropped `Condition: `, dropped line-level `**`), never a
changed word. Substance-preserving drift is the dangerous kind because it always reads fine — so ask
for delimiters and labels explicitly, as literal yes/no checks, not for "the text".

**The transport fix that closed it, worth asking for by name.** Prompt relays drift; a **file the
executor copies mechanically** does not. Team-lead wrote the block to a session scratchpad Architect
copies verbatim (not a prompt relay) and briefed a **fourth independent liaison pull + byte-diff of the
quoted sentence against the staged hunk, mismatch stops the commit**. That is the first actual *watcher*
this quotation ever had. When text must land byte-exact, ask for both: mechanical transport, and a
byte-diff gate at the commit boundary. ⚠ Residual to state out loud rather than leave implicit: once
committed, the only thing guarding the quote is a **prose** guard ("STORED SOURCE … do not normalize")
with no watcher against a future `DECISIONS.md` copy-edit — acceptable for one quotation, but say so
rather than let the byte-diff gate read as permanent protection.

**⚠ The DISPATCH BRIEF is a cited source too, and it is the one I am least likely to check.** The
SELF-242 brief named the canonical anchors as *"Lock 14 … Sec mods #1 typed-input / #2
mass-assignment"*. Measured against `docs/SECURITY/index.html` §4.5 RT-23 and ADR-011 D18 verbatim:
**mod #1 is `.strict()` typed-input validation + mass-assignment prevention — ONE mod — and mod #2 is
the numeric-input sanitization battery.** The branch's own code numbering was right and the brief's
was wrong, so reviewing "branch against brief" would have produced a finding against correct code.
**Read the brief's own citations against canon before using them as the yardstick**, and report brief
drift back in the verdict — a mis-numbered mod in a dispatch is how a fence gets attributed to the
wrong layer three artifacts downstream. Related:
[[uniform-response-rationale-vs-built-predicate]].

**⚠ One level further in: MY OWN ROLE BRIEF is a cited source, and its gloss can be NARROWER than
canon — narrow in the direction that scopes a surface OUT.** My role brief lists the joint-review
surface as *"Lock 14 — user-facing settings write-paths"*. ADR-011 Decision 4's live text reads
**"User-facing direct DB write surfaces (Lock 14)"**. On the brief's gloss, `POST
/api/transactions/:id/classify` — user input landing a direct DML upsert on
`pfin.account_trans_annotation` — reads as out of scope because it is not a *settings* path; on the
live text it is squarely a class member (caught at the SELF-249 / PR #564 review, where the brief
asked me to state in/out and why). **A dispatch brief drifting is someone else's error I catch; my
own role brief drifting is an error I will reproduce every session until I read past it.** The role
brief itself says to read the live ADR *"never from this file and never from recall"* — that
instruction is scoped to D3/D4/allowlists by name, and the Lock-14 gloss sits outside that scope
while reading exactly as authoritative. Treat every Lock/ADR name in my own brief as a **pointer with
a lossy label**: resolve the label against the ADR body before using it to decide scope, and report
the gloss drift in the verdict alongside the branch findings.

**How to apply:** on every verbatim-vs-paraphrase axis check, flatten the cited file
(`sed 's/^--*//' | tr '\n' ' ' | tr -s ' '`) so SQL-comment and string-concatenation line wrapping
doesn't produce false negatives, then grep the quoted fragment in **the cited artifact first**. A zero
hit means "check the other candidate sources", not "drift found". Name my own error in the same
message as the findings, never in a follow-up. Related:
[[measure-the-fence-regex-not-its-comment]].
