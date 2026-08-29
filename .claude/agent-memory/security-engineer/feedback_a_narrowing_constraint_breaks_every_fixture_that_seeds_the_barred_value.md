---
name: a-narrowing-constraint-breaks-every-fixture-that-seeds-the-barred-value
description: A new CHECK narrows the legal value space, so every merged battery that SEEDS the now-barred value breaks — and a migration's blast-radius analysis over dependent FUNCTIONS is not a clearance for their BATTERIES
metadata:
  type: feedback
---

When a migration adds a constraint that narrows a column's legal value space, grep every battery in the
tree for writes of the values it now bars — `insert`/`update` of that column — not just for reads of the
dependent functions. Bare DML inside a pgTAP savepoint raises and **aborts the enclosing transaction
through to the `rollback to savepoint`**, taking every leg in between with it, so one poison seed reds a
whole block, not one assertion.

**Why:** at the SELF-343 review of migration `095` (finite-and-strictly-positive CHECK on
`pfin.cpi_u_index.cpi_value`) the migration's own BLAST RADIUS section enumerated the three dependent
functions (`067` / `071` / `073`) and concluded each guard was *"sound, unchanged"* — **true of the
FUNCTIONS and false of their BATTERIES.** All three batteries seed `cpi_value = 0` / `-50` to exercise the
`<= 0` deflator guard, six poison writes across three merged files, every one now a 23514. The migration's
QA block prescribed the corrupt-the-control repair for `067` only, so QA had no instruction covering the
other two. Nothing in the diff showed it — the branch changed one file.

**The reason it is a SECURITY finding and not just a CI red:** the tempting repair is deleting the legs as
unreachable. Those legs are the ONLY watchers on the `<= 0` clauses in three live financial read surfaces;
delete them and a future editor stripping the clauses goes unobserved. `067`'s own file header already
rules on this — *"why this leg must SURVIVE a future positivity CHECK on 053 rather than be retired by
it"* — which is the general rule: **unreachable-by-construction is a reason to KEEP a leg.** The correct
repair is corrupt-the-control (drop the new constraint inside the EXISTING savepoint before the poison
write), never `throws_ok` on the write — that asserts the CHECK, which a different leg already covers, and
retires the guard assertion.

⚠ **I attached an EXECUTABILITY caveat to this repair that was FALSE, and the refutation was one grep from
where I already was.** I forwarded `095`'s claim that `postgres` does not own `pfin.cpi_u_index` (owner
`supabase_admin`), flagged as unverified — but `supabase/tests/rls/085_taxonomy_element_rls.sql:262`/`:282`
already do this exact shape (`set_config('role','postgres')` → savepoint → `alter table … drop constraint`
→ `lives_ok` → rollback), merged and green in the same lane. `supabase start` builds the local stack and
CI alike with the table owned by `postgres`, and NO `owner to` statement exists anywhere in the chain; the
`supabase_admin` reading was a scratch-harness artifact. **Grepping the existing battery applies to the
CONDITIONS I attach, not only to the remediation options I offer** —
[[grep-the-existing-battery-before-scoping-a-remediation]]. Flagging a claim as unverified is honest and is
not a substitute for the thirty-second grep. The generalisable half survives: ordering ≠ executability, so
check it — just check it against the tree, where an in-tree precedent beats anyone's probe because CI
re-verifies it every run. See [[clearance-conditions-must-absorb-my-own-recommendations]].

**Plan-count rider:** adding a `drop constraint` inside a savepoint that ALREADY exists and already rolls
back adds no pgTAP leg and no rollback boundary, so `plan(N)` is unchanged. `085`'s header documents the
plan-drift artifact that CAN arise from rolled-back legs (a `#`-prefixed TAP comment; `pg_prove` unaffected)
— read it there rather than re-deriving the mechanism.

⚠ **Rider — constraint-name order decides which constraint reports.** PostgreSQL evaluates a table's CHECK
constraints in constraint-NAME order. Sibling constraints overlapping on a value class therefore have a
deterministic-but-invisible reporter, and any battery leg asserting rejection **by constraint name** is
silently coupled to that ordering. A rename that sorts ahead flips attribution and reds legs that never
changed. When two overlapping CHECKs land on one column, say which name sorts first and why it matters.

⚠ **Phrase the condition in WATCHER terms, not LABEL terms.** I wrote *"no leg deleted"*. QA delivered a
repair where two labels vanished — `(ZC2)`/`(ZCn2)` — because the old triple (`lives_ok` + scalar
`is(x, null)` + `ok(...)`) collapsed into a pair (`lives_ok` + `results_eq` over the FULL row), which
asserts strictly MORE: everything the three did, plus row existence, plus an extra column. Correct work
that trips a literal reading of my own condition. **Ask "what property loses its watcher", never "which
labels survive"** — and when a label disappears, diff what the replacement asserts before calling it a
deletion. Related: [[replacement-control-name-the-losing-side]] in the project index.

⚠ **A claim I supply can be TRUE at handover and falsified by the very work it instructs.** My QA-block
text asserted *"plan(N) is UNCHANGED in every file named above"* — sound as a derivation (the repair adds
no leg and no rollback boundary) and confirmed in two of the three files, but the third also gained
brief-mandated NEW legs, so the sentence read false in the shipped artifact. This is a distinct arrival
from ordinary handover drift at [[supplied-verbatim-text-ships-unfiltered]]: nothing was mis-transcribed
and nothing went stale with time — **the delivery I asked for is what falsified my own prose.** So
re-read supplied text against the DELIVERED state, not only against the state it was written for, and
prefer wording that separates the mechanism from any figure the delivery could move.

**How to apply:** on any constraint-narrowing migration, grep the value the constraint bars across
`supabase/tests/` before verdict, enumerate the exact file:line + leg labels, and require the migration's
QA block to name EVERY affected battery — a QA block naming one file reads as a complete instruction.

Related: [[grep-the-existing-battery-before-scoping-a-remediation]] ·
[[corrupt-the-control-canary-boundary-tie]] · [[cpi-positivity-check-must-be-additive]] ·
[[verify-the-stated-correctness-mechanism]].
