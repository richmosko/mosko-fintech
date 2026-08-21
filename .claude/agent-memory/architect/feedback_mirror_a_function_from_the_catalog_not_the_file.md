---
name: mirror-a-function-from-the-catalog-not-the-file
description: When authoring a sibling of an existing function, rebuild its skeleton from pg_get_functiondef, never from the newest migration file that names it — a CREATE OR REPLACE chain leaves every earlier file greppable and superseded
metadata:
  type: feedback
---

Authoring a function that mirrors an existing one? **Read the body from the live
catalog (`pg_get_functiondef`), not from a migration file.**

**Why:** at SELF-330 I mirrored `fn_subcat_market_value`. Grep named `076`, `078`
and `081`; I correctly picked the newest, `081` — and it was still wrong. `084`
had re-emitted the function as a side effect of dropping
`pfin.user_taxonomy.domain`, so the live body carries **two fewer join
conjuncts** than any file whose subject line names the function. The copied
skeleton did not even parse. Nothing in the file names, the ordering, or the
commit subjects would have surfaced this — `084`'s subject is about the GL split.

The general shape: **a `CREATE OR REPLACE` chain leaves every superseded body
greppable and gives you no signal about which is live**, and the replacing
migration is frequently named after something else entirely. "The newest file
that mentions it" is a heuristic that fails silently and looks careful.

**How to apply:** before mirroring, copying, or asserting anything about a
function body — including a claim that two copies of a kernel are textually
identical — apply the chain to a scratch DB and read
`pg_get_functiondef(oid)`. State the mirrored source as *the live catalog body*
and name the migration that most recently emitted it, so the next author does not
re-derive it from the file that merely bears the function's name.

Corollary that also bit here: a same-migration side effect (`drop column`) can
invalidate a **schema** fact stated in a still-greppable header — `009`'s
`unique (users_id, domain, cat, sub_cat)` reads authoritative and is dead.

Related: [[feedback_consequence_list_inherits_its_authors_instrument]] (the same
instrument-choice failure at ADR scope), [[reference_create_or_replace_resets_volatility]]
(the other thing a silent re-emission destroys), [[feedback_a_ratified_name_is_not_a_built_table]].
