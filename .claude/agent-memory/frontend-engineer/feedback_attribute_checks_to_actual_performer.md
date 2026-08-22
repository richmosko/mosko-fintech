---
name: feedback-attribute-checks-to-actual-performer
description: A commit-message or file-header claim about "who verified X" must name whoever actually ran the check, not whoever is being generous or whoever happens to be relaying the summary — a wrong attribution gives a check an owner who never performed it, and nobody can then audit it.
metadata:
  type: feedback
  score: n/a
---

On SELF-325, I wrote the `app-forms.ts` stub-change header note as "Full dom-project suite
verified green both before and after (Architect review, same date)." I was the one who actually
ran that check (before/after the `enhance` no-op → real-submit change); Architect had not yet
reviewed anything at the point I wrote that line. I meant it generously — crediting the eventual
reviewer — but it was factually wrong.

Architect caught it and corrected the commit before landing, with the reasoning stated explicitly:
"a file header is a durable record of who verified what, and crediting a check to whoever happens
to be relaying it is how a verification acquires an owner who never performed it — and then nobody
can audit it, because the person named doesn't remember doing it." On a Sec-reviewed branch,
provenance accuracy of a check matters more than graciousness.

**Why this matters beyond the one file:** the real division of labor turned out to be three-way
(I ran the check; QA enumerated which existing dom tests could shift meaning; Architect widened
the check after finding `$app/forms` is aliased globally in `vitest.config.ts`, not dom-scoped,
which put route files outside a component-level enumeration). A single generous "Architect
reviewed this" line would have erased that whole chain and made none of it re-derivable later.

**How to apply:** when writing a commit message, code comment, or handoff note that claims a
check was performed, name the actual performer — including when the performer is yourself. Don't
default to crediting a reviewer, a teammate, or "the team" as a courtesy; that's the same failure
shape as a paraphrase drifting from its source, just aimed at attribution instead of content. If
multiple people contributed different halves of a verification (as happened here), name each
half's owner rather than collapsing to one name.
