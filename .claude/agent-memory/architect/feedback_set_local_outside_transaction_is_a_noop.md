---
name: set-local-outside-a-transaction-is-a-noop
description: "`set local role` does nothing when each statement is its own transaction (psql -c, separate sends) — but it DOES take effect under `supabase db push`, which batches a file into an implicit transaction. Scope the claim by VENUE before relying on it either way."
metadata:
  type: feedback
---

⚠ **THIS MEMORY WAS TOO BROAD AND IS NOW SCOPED. Read the venue line before applying it.**

**Venue A — each statement sent separately (`psql -c`, one-shot sends, an RLS smoke
harness): `set local role authenticated` and `set_config(…, true)` emit only
`WARNING: SET LOCAL can only be used in transaction blocks` and DO NOTHING.** The probe
then runs as the RLS-exempt superuser, every tenant's rows are visible, and every leg
"passes."

**Why:** measured at `074`. My first RLS smoke reported the owner seeing 1 row, tenant B
seeing rows too, and the aal2 clause making no difference at aal1 vs aal2 — all four legs
green-looking, all four meaningless. The tell was a `leaked_from_A = 1` that should have
been a catastrophic finding and was actually just the superuser reading its own fixture.
**A vacuous RLS harness does not look empty — it looks permissive**, which is the reading
that gets reported as a defect or, worse, waved through.

**How to apply (venue A):** wrap every leg in `begin; set local role authenticated; …
rollback;`, and put a **control leg first** that selects `current_user` and asserts it is
`authenticated`.

⚠ **Venue B — `supabase db push` applying a migration FILE: the warning STILL FIRES and the
role change STILL TAKES EFFECT.** Measured 2026-09-16 (CLI v2.105.0, PG 17.6) by writing
`current_user` into a table at three points in one file: `migrator` → **`pfin_owner`** after
`set local role` → `migrator` after `reset role`. **The CLI sends a migration file as ONE
multi-statement simple Query, and Postgres runs that in an IMPLICIT transaction**, so
`SET LOCAL` is legal; the 25P01 warning is about the absent explicit `BEGIN`, not about
being ignored.

**The general lesson, and it is the reason this file was rewritten rather than deleted:**
I measured the WARNING and inferred the EFFECT. *A claim about what a statement DOES must
be measured on the observable the claim is about, through the instrument that will actually
run it.* The first version of this memory was right about its venue and silently wrong about
every other one. ⚠ **It had already fanned out** — into ADR-072 Amendment 5's Decision F1,
ratified by F/CTO, and into 114 migration-file comments — before the second venue was
measured. **Fan-out is the tell that a claim is load-bearing enough to deserve re-measuring.**

**Still prefer the session-scoped `set role …; … reset role;` pair in a migration file**, but
for the honest reasons: it warns on nothing, and it does not depend on the CLI's
undocumented query-batching, which a CLI upgrade could change — landing ownership wrong
**silently**. Pair it with an engine backstop (deny CREATE) so the silent path becomes loud.

Same family as [[diff-of-two-outputs-proves-nothing-until-nonempty]]: the instrument must be
shown to be measuring before its reading means anything.
Venue setup: [[scratch-db-full-chain-recipe]]. Related: [[migrator-lane-privilege-facts]].
