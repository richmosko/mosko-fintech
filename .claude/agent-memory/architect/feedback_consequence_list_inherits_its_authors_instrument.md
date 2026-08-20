---
name: consequence-list-inherits-its-authors-instrument
description: A ratified ADR's consequence list is only as wide as the instrument its author used — re-measure over the instruments it did NOT use before executing it, and record any obligation whose referent does not exist
metadata:
  type: feedback
---

Before executing a ratified consequence list, **re-measure the blast radius with an
instrument the ADR did not use.** A consequence list is a claim bounded by how its
author looked, not by what is out there.

**Why:** ADR-058 measured the four FK-shaped referents (over migration *text*) and Sec
F7 measured the battery files (over `supabase/tests/`). **Neither measured the live
function catalog**, and three live consumers were sitting there — one that would have
rejected every categorized annotation write (`030`'s fail-closed class read), one on the
§2.2.2 money surface carrying three predicates on the column being dropped (`076`/`081`),
and one needing comment-only correction (`022`). All three fail LOUDLY, so they would
have surfaced at the first battery run — *after* authoring, when the cost of a
scope-change judgement is highest.

**How to apply.** The cheap sweep is the catalog, not the tree:
`pg_proc.prosrc` across the schema for the table name **and** for the column being
dropped, plus `pg_policy` quals, `pg_constraint` defs and `pg_index` defs. Cross-check
against the source tree for anything the measured instance is behind on — and check
whether it *is* behind: an instance whose `schema_migrations` maximum is lower than the
objects it carries has drift, so a pass there can be a pass on drift rather than on the
chain. ⚠ Report the clean result too (*"zero RLS policies reference X"*) — an unstated
negative reads later as unmeasured.

**The same failure in its other direction: an obligation whose referent does not exist.**
Sec's numbering pin directed dropping a `Matched-DOMAIN … is app-layer in V1` clause from
ADR-011 D3's `#10`/`#13` entries. **Neither entry ever carried it** — the clause lives in
the migrations' catalog comments. Doing nothing silently and inventing an edit are both
wrong; **write down that the obligation had no referent and where the text actually
lives**, or it reads at the next review as an obligation missed.

Related: [[instrument-cannot-observe-the-property]] · [[a-clean-sweep-is-a-claim-about-your-filter]] ·
[[gl-taxonomy-split-ratified]]
