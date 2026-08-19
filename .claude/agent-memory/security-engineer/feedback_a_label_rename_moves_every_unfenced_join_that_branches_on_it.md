---
name: a-label-rename-moves-every-unfenced-join-that-branches-on-it
description: A "data-only, no function edited" rename still changes derived output wherever a consumer branches on that column through a join missing the discriminator predicate — find those joins before accepting "nothing else changes".
metadata:
  type: feedback
---

**Rule: for any label/value rename, grep every consumer that BRANCHES on that column, and check
whether the join reaching it carries the discriminating predicate. A rename edits no function body
and still moves that function's output.**

**Why.** Measured on the 2026-08-19 `082` rename review (asset-domain Cat `'Equity'` →
`'Marketable Securities'`). The migration header was excellent and stated, truthfully, *"It edits no
function body, no CHECK, no policy and no cashflow row"* and *"It does not touch the cashflow
domain."* Both true. Together they tell the reader that `fn_gl_entries` output is invariant — and it
is not. `fn_gl_entries` joins `pfin.user_taxonomy` **with no `domain` predicate** (on the annotation's
`sub_cat_id`, and again on the split child's), then branches on `ut.cat` against the cashflow-class
literals. `023` and `029` both record in their own DOMAIN NOTEs that matched-DOMAIN is **app-layer
only in V1** — the matched-TENANT trigger fires, the domain does not. So an asset-domain row is a
permissible target at the DB layer, and its contra routing moved from the `Equity` account to
`Suspense`.

**The tell that generalises: two columns spelled the same in one table, discriminated by a third
column, with a consumer that joins on id and branches on the spelled column.** The discriminator is
enforced at *write* time (a CHECK on the row) and absent at *read* time (the join). A CHECK
constraining which rows may exist is not a constraint on which rows a join may reach.

**Judge by DIRECTION, and say so.** Here the post-rename value matches no branch, so it falls to the
`else` → `Suspense`: fail-safe, balanced, and strictly more correct. That made it a **flag with
commit-ready header text**, not a veto. But the identical unfenced join fails the other way — rename
an asset label *into* a cashflow-class name and it silently acquires that class's posting routing,
no error, no failing test. **The reusable half is the inverse case, and the migration header is where
the next renamer will look for it.** Ask which direction the specific instance takes before choosing
severity; write the header note for the other direction.

**How to apply.** When reviewing any rename of a value that other code compares against:
1. `git grep` the OLD literal across migrations, app source, workers (under both quote styles) — but
   that only finds sites that *name* it.
2. Separately, find the sites that *reach* it: every join on the renamed row's `id`, and check each
   for the discriminating predicate. A site can be affected while never containing the literal.
3. Check whether the discriminator is DDL-enforced or app-layer-only. "App-layer only in V1" written
   in a DOMAIN NOTE is a live gap, not a resolved one.
4. Say plainly whether a later structural change closes it (here: ADR-058 Decision 1's split re-targets
   the referents, closing it by construction) — that is what turns a veto question into a scheduling one.

Related: [[a-grep-over-comments-measures-intent-not-data]] (a grep over text measures who NAMES the
thing, never who REACHES it) · [[the-merge-key-is-a-tenant-fence]] (the join key decides the failure
direction) · [[replacement-control-name-the-losing-side]].
