---
name: verify-the-stated-correctness-mechanism
description: When a file names its own correctness mechanism ("textual identity across N copies", "STABLE", "verbatim kernel"), MEASURE it — the claim is usually true and unwatched, and a fence added while it holds locks in a real invariant rather than codifying drift
metadata:
  type: feedback
---

**When an artifact states the mechanism that makes it correct, treat that sentence as a testable
claim, not as reassurance.** Migration `076` said it outright: *"The house treats textual identity as
the correctness mechanism: five copies that read identically can be diffed; five that read
differently cannot."* Nothing verified it — an assertion with no watcher, sitting behind every
financial figure in the product.

**Measure it before deciding what to do about it.** Extracted the price-pick kernel from every copy
(`019` `049` `050` `056` `059`×2 `076`) and hashed. **All identical — the claim was true.** That is the
more useful outcome than finding drift, because **a fence added while the invariant HOLDS locks in a
real property; added after drift it codifies the drift.** Say that when proposing the control; it is
the argument for doing it now rather than "sometime".

⚠ **The measurement detail that would have broken the fence:** raw hashes differed across copies and
looked like drift. The difference was **leading whitespace only** — the copies sit at different
nesting depths, legitimately. Normalize leading whitespace (`sed 's/^[[:space:]]*//'`) before
comparing, and **tell the fence author**, or the fence fails on day one and gets disabled. A
first-pass "drift found!" here would have been a false finding delivered with hashes attached.

**Companion pattern — a stated modifier is also a testable claim.** The same review surfaced CONTRACT
text claiming `STABLE` on three financial functions whose DDL omits the modifier, leaving them
**VOLATILE** (`grep -A4 'CREATE OR REPLACE FUNCTION'` for `LANGUAGE sql` with no volatility keyword).
**Find the concrete hook rather than filing it as tidiness:** ADR-038's foot-to-NAV invariant compares
two of them in one statement, and VOLATILE gives no statement-level snapshot guarantee for that
comparison. Remediation shape: fix all instances in one migration **plus a structural pin**
(`pg_proc.provolatile = 's'`) — the mismatch survived because nothing asserted it, so the fix must
include the assertion. ⚠ Also: the reporting agent named two instances; measuring found a third.
**Re-measure the population, don't inherit its size.**

**And when a brief tells you a function has no `limit 1`, check.** `076` has two selectors: a
`GROUP BY` aggregation (isolation path — a leak ADDS to a sum, so the #474 displacement class does not
apply and a corrupt-the-control fails LOUD) and a price-pick `limit 1` with a non-total ordering
(value nondeterminism). **One function, both kinds.** Correct the framing precisely rather than
accepting or rejecting it wholesale — "no limit-1 selector" was false, "no limit-1 on the isolation
path" was the true and load-bearing claim.

**How to apply:** grep any reviewed artifact for sentences of the form *"X is what makes this
correct"* / *"copied verbatim"* / *"identical to"* / a declared modifier, and ask (1) what command
falsifies it, (2) run that command, (3) if it holds, is anything watching it, (4) if not, propose the
fence now and hand over the normalization detail. Related:
[[measure-the-fence-regex-not-its-comment]] and
[[corrupt-the-control-canary-boundary-tie]].

⚠ **The posture TRIPLE is the family convention, and a battery can pin one third of it.** `096`'s
battery pinned `prosecdef` alone; `062`/`064`/`067`/`069`/`070`/`071`/`073`/`079`/`089` pin all three in
ONE leg — `is((select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
… ), array['false','s','search_path=""'], …)`. `093`/`094` pin none, so **check which sibling convention a
new battery inherited before calling it a regression** (`grep -l "proconfig" supabase/tests/rls/*.sql`).
Converting `ok()` → `is()` is one leg out, one leg in, so `plan(N)` and the header's leg breakdown both
stay valid — a free fix, which is the argument for asking at review rather than booking it. **Why it
bites:** it fails closed on BOTH removal paths — dropping `set search_path = ''` makes `proconfig` NULL,
and Postgres array equality uses btree semantics (a NULL element opposite a non-NULL one is NOT-equal,
not NULL), so the leg REDs instead of passing on a NULL comparison. Verify that property before
accepting an array-shaped assertion as a watcher; the SQL-three-valued intuition predicts the opposite.

⚠ **`pg_depend` records NOTHING for a string-bodied `language sql` function — a "catalog-level"
dependency leg over one is VACUOUS.** SELF-258's `099` battery paired a text-absence pin (X1a,
`pg_get_functiondef !~* 'connection_status|linked_source|has_stale'` — real, discriminating) with
X1b, a `not exists (select 1 from pg_depend … refobjid = fn_aggregation_has_stale_constituent …)`
whose own description called it *"the catalog-level proof, not merely a text-absence proof."*
**Measured on the scratch DB: `pfin.fn_cashflow_contributors(date)` has exactly ONE `pg_depend` row
— `pg_namespace | n` — and zero `pg_proc`/`pg_class` refs, despite its body calling
`pfin.fn_cashflow_items(date)` and reading `pfin.account`;** `fn_cashflow_items` likewise has zero.
A `$$…$$` body is stored as TEXT and never parsed into the dependency graph, so the predicate is
true for every possible body, including one that inlines the very rule the leg exists to forbid.
Only a **SQL-standard body** (`BEGIN ATOMIC`, PG14+) records those edges. **The strength claim was
exactly inverted, and that is the harm** — a vacuous leg labelled as the stronger proof makes the
one real leg look like a redundant belt someone later drops. Free tell: run
`select count(*) from pg_depend where classid='pg_proc'::regclass and objid=<fn>::regprocedure
and refclassid in ('pg_proc'::regclass,'pg_class'::regclass)` against a function you KNOW calls
something. Remediation to prefer: a **positive** pin over the denylist — assert the set of
`pfin.fn_*` identifiers in `prosrc` is exactly `{fn_cashflow_items}` (catches an inlined rule that
dodges all three tokens), or drop the leg and re-plan.

⚠ **The FIX reproduced the defect one iteration later — check the replacement's OWN strength claim.**
QA landed the positive pin correctly (measured: it returns `{fn_cashflow_items}`, and a doctored
body redded it), but its note called it *"strictly stronger than X1a's three denylisted tokens."*
False: `regexp_matches(prosrc,'fn_[A-Za-z0-9_]+')` cannot see a body that inlines the rule by
reading the **view** directly — `linked_source_connection_state` contains no `fn_` (measured) —
which is exactly the route X1a catches. They are **complementary, not nested.** A false strength
claim in one leg's note is what makes the neighbouring leg look droppable; that is the whole harm
of the original defect, so the remediation must be re-read for the same sentence pattern. **When a
finding is "this control's self-description overstates it," re-audit the fix's self-description
before signing.** Related: [[replacement-control-name-the-losing-side]].

**Companion — a ONE-TIME mechanism offered as a PERMANENT invariant.** The GL-split ADR draft
(2026-08-18) wrote: *"the new table's identity sequence is set past the maximum so no id is ever
reused on either side"*, concluding *"every historical snapshot remains resolvable against exactly
one table."* The mechanism delivers the conclusion **only at the migration instant** — two
independent identity sequences both advanced past a shared max then run forward in parallel and
collide on the very next insert each. **Ask of every stated mechanism: does it hold at t=0 only, or
by construction forever?** The tell is a mechanism phrased as an ACTION ("is set past…") supporting a
claim phrased as a STATE ("remains resolvable"). Remediation shape is always the same: replace the
action with a construction (one shared sequence, or disjoint reserved ranges) and make the battery
assert the **construction**, not a point-in-time count. ⚠ And the point-in-time battery leg the draft
proposed was **vacuous on a fresh CI stack**, where the property holds by construction rather than by
verification — the "fresh-stack CI is clean by construction" trap in
[[a-red-whose-message-names-the-wrong-defect]].

⚠ **A WARRANT is a stated mechanism too — and a verified universal can be verified over the WRONG
OBJECT CLASS.** I refused to sign *"every Decision 3 fence is a BEFORE ROW trigger"* unmeasured.
Architect came back having measured it twice (catching their own name-based-vs-body-based miss) and
**added a warrant** to make it true of future instances: *"a matched-tenant test must read the
referenced row, and a CHECK constraint cannot subquery."* The enumeration was fine. **The warrant
forecloses the wrong object.** Decision 3's own opening sentence sanctions *"DB-level **WITH CHECK**
constraint (single columns) or BEFORE INSERT/UPDATE trigger (array elements PostgreSQL can't express
declaratively)"* — and a `WITH CHECK` is an RLS **policy** clause, not a table CHECK constraint: it
subqueries freely and **survives `session_replication_role = replica`**, which is the exact property
the universal was carrying. Measured: 20+ `pfin` policies use subquerying `WITH CHECK`.
**Three transferable pieces:**
- **Two names one word apart can be different objects.** `CHECK constraint` / `WITH CHECK`;
  `session_user` / `current_user`; `setrole=0` / `setdatabase=0`. When a warrant turns on a
  near-homonym, read the source's own sentence rather than the warrant's paraphrase.
- **The warrant's supporting quote had lost its scope limiter** — rendered *"where PG cannot express
  the constraint declaratively"*, source *"array elements PostgreSQL can't express declaratively"*.
  Dropping **"array elements"** converted a narrow carve-out into a general licence. Dropped-clause-
  inside-a-quote is how a false universal acquires a true-looking citation.
- **A warrant added to future-proof a claim fails hardest where it was meant to help.** Ask
  specifically: *what does this warrant say about the NEXT instance?* — that is the case it was
  written for and the case nobody tests.
**Remediation shape that beat both options:** don't soften the universal and don't keep it — make
the artifact carry the **discriminator** (*"inert iff trigger-realized; check which form this
instance uses"*) plus the **dated** empirical inventory. Stronger than the universal, and it cannot
rot. ⚠ Also note whose method could see what: their enumeration searched trigger *functions*, so a
policy-realized instance was invisible to **both** passes — not a claim one exists, a statement
about the instrument. Related: [[applied-vs-demonstrated-discharge]].

⚠ **CORRECTION TO THE ENTRY ABOVE, and it is the more useful record.** I diagnosed Architect's
warrant quote as a *mangling* of Decision 3's sentence with "array elements" dropped. Wrong
mechanism. **The string was verbatim — from a DIFFERENT ADR.** It lives in ADR-025's `012`
component discussion: *"A single-row CHECK cannot subquery the referenced row; Decision 3 permits a
trigger where PG cannot express the constraint declaratively."* So it was **right content, wrong
pointer** — the false-composite form — not a dropped clause. **Why that is worse:** a mis-attributed
verbatim string passes every verbatim check and fails only an attribution check. My own two-halves
rule (verify the POINTER and the CONTENT, every time) exists for exactly this, and I still checked
only the content half — concluded "mangled" and never asked whether the string was verbatim
*somewhere else*. **Substance-first reading caught it only because the substance happened to be
wrong too; had ADR-025's claim been sound, I would have waved through a mis-attributed quote.**
When a quote looks subtly off, grep the string across the whole corpus before calling it a mangling.
**And the upstream source was itself unowned** — the same conflation sits on `main` in ADR-025 and
had just propagated into a draft amendment to a higher-authority document. **A defective sentence
that has demonstrably transmitted once is a source to correct, not a curiosity.**

⚠ **Diff SHAPE can be a reviewable property — and it can outrank folding a fix in.** I had required
"do not touch the Catalogued-§10 bullet or the numbered list." Architect delivered the amendment as
a **pure insertion (26 insertions, 0 deletions** — the diff's only `^-` line being the `---` file
header), which makes that constraint checkable in one command instead of by reading. So when the
follow-on ADR-025 correction came up, I **booked it rather than folding it into the same PR**: the
edit would introduce deletions and destroy the one PR where the pure-insertion property was the
proof. **Ask for a diff shape that makes your constraint mechanically checkable, then protect it** —
and say explicitly that this is a tradeoff (more PRs, better verifiability), not caution.
