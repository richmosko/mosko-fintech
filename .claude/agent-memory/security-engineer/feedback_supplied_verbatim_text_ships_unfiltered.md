---
name: supplied-verbatim-text-ships-unfiltered
description: Commit-ready text I hand another pen-holder is committed byte-for-byte, so MY formatting errors ship — proofread a supplied block against the SURROUNDING FILE's convention, not just for correct content
metadata:
  type: feedback
---

**When I supply commit-ready text under the verbatim protocol, the receiving agent commits it
byte-for-byte — including my mistakes. Proofread the block against the conventions of the file it is
going INTO, not only for correct content.**

**Why:** at SELF-246 / `090_cashflow_target.sql` I supplied a 15-line header-comment replacement whose
second line read `-- FK-shaped reference column.` (one space) where that file's header convention —
and the very line I was replacing — uses `--   ` (three). Architect committed it exactly as written,
which was **correct behaviour**: verbatim commitment is the whole point, and the paraphrase-drift
failure class this role exists to catch is *worse* than a whitespace defect. So the branch now carries
a one-line indentation inconsistency that is **mine**, introduced by the mechanism designed to protect
my text. I did not block on it — a re-freeze of a reviewed sha to fix whitespace costs more than it
buys — but I named it in the same message as the GREEN rather than letting it surface later as
someone else's sloppiness.

**How to apply:** before handing over a commit-ready block, read the lines immediately above and below
the insertion point in the target file and match them — indentation, comment-prefix width, bullet
glyphs, wrap column, quote style. `git show <ref>:<path>` the neighbourhood; do not compose the block
from memory of the file's style. This costs one command and is the only proofread that will ever
happen: the receiving agent is under instruction NOT to fix it, and a reviewer diffing my text against
the commit will find them identical and call it clean.

**The general shape, worth more than the whitespace:** *a protocol that removes someone else's
discretion transfers the entire error budget to me.* Anywhere I say "commit this verbatim," I have also
said "there is no second reader." Corollary for the receiving end — **do not soften this into "commit
verbatim unless something looks off."** A pen-holder who silently corrects my formatting is one who
might silently correct my wording, and I would rather ship a bad space than lose the guarantee.

**⚠ THE SHARPER CASE: MY SUPPLIED TEXT CAN CARRY A FACTUAL CLAIM ABOUT THE TREE — AND ONCE
COMMITTED IT READS AS THE RECEIVING FILE'S OWN ASSERTION.** At SELF-250 / PR #572 the classifier
comment I handed Backend said `pfin.account_trans` *"carries other unique indexes (017's provider
dedup) whose violation means something entirely different."* That is not style — it is a claim, and
the whole reason the guard matches by index NAME instead of by bare `23505` rests on it. If it were
false, the extra conjunct would look like paranoia and the next reader would simplify it away.
It happened to be true (`account_trans_provider_dedup_idx` is `create unique index` at `017`; `040`
relaxes only `account_trans_hash_dedup_idx`) — **but I verified that at the RE-CONFIRM pass, after
it had already shipped, not before I handed it over.** Lucky is not a method.

**Rule: run Sec-Lock on my OWN supplied prose BEFORE handing it over, at the same standard I apply
to a teammate's citations** ([[my-review-measurements-become-quoted-sources]]). Every factual
sentence in a commit-ready block is a claim with an owner, and after commit the owner *looks like*
the file's author. Grep the referent of any noun the justification hinges on.

**And re-read my own landed text at the re-confirm pass, not just the receiver's adaptation of it.**
The natural instinct on a discharge check is to diff *their* changes against *my* text and stop when
they match. Matching proves transcription, not correctness — the block was never reviewed by anyone
but me.

Related: [[clearance-conditions-must-absorb-my-own-recommendations]],
[[read-decisions-from-the-pr-branch-when-the-pr-edits-it]],
[[temp-handoff-path-is-per-worktree]].

**⚠ THE WORST INSTANCE: my supplied text TRIPPED THE CI FENCE IT WAS DESCRIBING.** At SELF-252 I gave
Backend a commit-ready comment reading *"this endpoint references no SUPABASE_SERVICE_ROLE_KEY and adds
no entry to the RT-26 allowlist registry."* The RT-26 fence is
`grep -rEln 'SUPABASE_SERVICE_ROLE_KEY'` over `api/src/` with **no comment awareness**, so naming the
literal *in order to deny holding it* is a violation at a non-allowlisted path. Backend committed it
byte-identical as instructed, the required check went RED and the PR went `BLOCKED`. I had read that
fence's registry and its workflow job in the same review and still never ran its predicate over my own
words. The wording I replaced did not contain the literal — **I introduced the failure while fixing a
different defect in the same sentence.**

**How to apply — a fence's TRIGGER STRING is unsafe to quote anywhere the fence scans, including in
prose that denies it.** Before handing over any text: (1) identify every fence whose scope includes the
target file; (2) run each fence's actual predicate over the proposed text (`grep -Eln '<literal>'` on a
scratch file), not over the file it will land in; (3) prefer the target tree's existing fence-surviving
phrasing — `exchange/+server.ts` already said *"holds NO Plaid secret and NO service_role key"*, which is
what the convention looks like when it has already paid this cost. **And when the fence catches you,
the fix is the prose, never the fence** — allowlisting the file or teaching the grep to skip comments are
both veto-grade, and both look like reasonable cleanups in the moment.

Related: [[measure-the-fence-regex-not-its-comment]] — same lesson from the other side: I measured the
fence's registry and its comment, never its regex against my own artifact.
