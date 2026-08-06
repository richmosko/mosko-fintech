---
name: apply-migration
description: Invoke when authoring a new Supabase migration — adding a base table, extending an RLS surface, writing a new SECURITY INVOKER helper, or proposing any function with SECURITY DEFINER posture. Codifies the Architect-owned procedure: migration file shape (POSTURE RATIONALE + CONTRACT blocks + `comment on function` + `set search_path = ''` + idempotent schema creation), mandatory §10 3-axis cross-check before drafting, Decision 3 matched-tenant validation rule for every FK-shaped column, Sec joint-review routing triggers, and QA pgTAP test-pairing requirement. Also invoke when evaluating whether a new column or array type activates the cross-tenant FK-bypass family, when deciding what a `comment on` may claim (present-tense/checkability, counts, forward-references, naming where sufficiency comes from), and when correcting a comment on an already-merged migration (the comment-only `052` shape — regenerate-and-diff, containment proof, render-verify). Do NOT invoke for Backend `supabase migration up` execution (Backend role) or pgTAP test authorship (QA role).
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Agent
  - SendMessage
---

# apply-migration — author a Supabase migration under V1 discipline

Architect-owned procedure for authoring migrations in `supabase/migrations/`. Operationalizes [`supabase/CLAUDE.md`](../../../supabase/CLAUDE.md) (primary source) + [ADR-011](../../../DECISIONS.md#adr-011) Decisions 3 / 4 / 9 / Lock 11.

## Role split — who does what

| Role | Owns |
|---|---|
| **Architect** | Authors migration SQL files + `config.toml` edits |
| **Backend** | Applies (`supabase migration up`) after CI fixture-seed verification — read-only on the file |
| **QA** | Authors `tests/` pgTAP battery — Architect does NOT edit `tests/` |
| **DevOps** | Wires CI test-fixture seeding around the migration |

## Step 0 — §10 3-axis cross-check (MANDATORY before drafting)

Before writing a single line of SQL, read [ADR-011 Decision 4](../../../DECISIONS.md#adr-011) **verbatim, live, every time — never from recall and never from this file.** Cross-check the draft against three axes:

1. **Instance-numbering** — do not reorder, renumber, or silently add a catalogued instance.
2. **Layer-attribution** — do not re-attribute which layer a catalogued instance operates at.
3. **Verbatim-vs-paraphrase** — the catalogued list is **not** restated in migration files; link to Decision 4 (**Path B: drop-enumeration-let-link-carry**). Restate verbatim only if the file IS the canonical anchor — a migration never is.

> **⚠ This section deliberately states NO count and NO enumeration, and that is the point.** It previously named both. The ledger **grew** (2→3 when RT-27 was catalogued), the restatement went stale, and it went on reading as authoritative. **A derived surface that copies a count acquires a maintenance obligation it will not honour.** The only instruction that cannot rot is *go read the canonical list*. **Applies to your draft too:** a `comment on …` that references the ledger should **link, not enumerate**.

**Any ledger change (count or layer-attribution) is Sec joint-review-mandatory** before the migration is finalized.

⚠ **The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS.** Measure the fence set when you need it — `grep -rhoE 'RT-[0-9]{2}' .github/workflows/` — it is **not** a copy of the catalogued ledger. **Do not "tidy" either one to match the other**; that cleanup destroys a real distinction.

## Step 1 — Migration file shape

Model file: `supabase/migrations/002_fn_mask_acct_number.sql`. Numbering note: `001` is reserved for the foundational `users_id_rename` migration (SELF-186 Phase 5 close-gate, authored later); `fn_mask` is order-independent so it lands at `002`.

Every migration file carries this header structure:

```sql
-- ============================================================================
-- Migration: pfin.<name> — <one-line description>
-- <Phase / Linear issue reference>. Closes / extends <SD-NN / RT-NN / Lock N>.
--
-- Numbering: <why this number; what precedes / what this depends on>
--
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT SECURITY DEFINER.
--   <why INVOKER is correct here — "reads no tables and needs no elevated privilege">
--   OR
-- POSTURE RATIONALE — SECURITY DEFINER — Sec joint-review required; see DEFINER allowlist.
--   <why DEFINER is required; which allowlist entry this is>
--
-- CONTRACT
--   <function signature> — <brief behavior description>
--   <security-load-bearing edges: NULL handling, immutability invariants, tenant-binding>
-- ============================================================================
```

Every function also carries:
- `set search_path = ''` — prevents search_path injection
- `comment on function <name>(<args>) is '...'` — self-documenting; include ADR anchor + posture + SD/RT refs
- Schema creation is idempotent: `create schema if not exists pfin`

**Sequencing:** pure helpers (no table dependencies) are order-independent. Base-table migrations and RLS policies are order-dependent — sequence them deliberately; note the dependency in the header.

**Numbering:** take the next free number **at authoring time**, never reserve one ahead. A reserved number in a shared, growing namespace goes wrong silently when slices split (the `058`→`059` slip).

## Step 1.5 — What a comment may CLAIM

A `comment on …` is a **database object**. It ships into the catalog, is read at `\d+` by someone with **no repo in front of them**, and can only be corrected by a **new comment-only migration** (the `052` shape — never an edit to a merged file). That asymmetry is what makes the rules below sharper for catalog comments than for `--` header comments.

**(a) No present-tense claim about state the reader cannot check from where they are standing.** The discriminator is *checkability*, not tense. *"Nothing sets one today"*, *"no override exists"*, *"each names the other"* — all true when written, all false within days, and **five such claims appeared in one branch**. A repo-state claim in a repo file is fine; **the same sentence in a catalog comment is not**, because the reader cannot verify it.

Durable rewrites — prefer either:
- a **past-tense event**: *"the constraint was struck at `059`"* (dated, stays true), or
- a **standing requirement**: *"each MUST name the other"* (converts a fact into a check).

**(b) No counts, no enumerations.** Same reason as Step 0 — a copied count is a maintenance obligation the copy will not honour. Link to the canonical anchor.

**(c) Do not cite an artifact that does not exist yet.** ***A document may forward-reference a document; a CORRECTNESS CLAIM must not forward-reference the mechanism that makes it true.*** A comment asserting *"this is safe because ADR-NNN / migration `0NN` establishes X"* — where that artifact is unmerged — puts a ratified-sounding claim in the catalog with its support absent. **State the dependency as the PROPERTY, naming the artifact as its current instrument** (*"…holds iff the session TimeZone is UTC, declared by `061`"*) — true before and after the other half lands, and it survives the instrument being renumbered or replaced. *(The general form of this rule lives in `brief-drift-catch`; the catalog-comment case is here because the cost of being wrong is a migration.)*

**(d) Name where your sufficiency comes from — and what makes it verifiable.** A fence whose sufficiency depends on something outside itself must say so. **A confidently-wrong dependency is worse than none**: an absent dependency invites a check, a wrong one answers it in advance and stops people looking. If a fence is necessary-but-not-sufficient, **say so in the comment** rather than implying it is the whole answer.

**(e) Ask the dual of every MEASURED reassurance.** *"This is safe because X"* — now ask **what does X make UNSAFE for a reader elsewhere?** A live case: a migration header measured *"`ALTER DATABASE … SET` is ADDITIVE; the row already carries `app.settings.jwt_secret`"* as a **reassurance** that the pin would not clobber existing settings. That same measured fact was the **hazard notice** for a deploy-runbook sweep that selected the whole `setconfig` array — and the pin is what made that row match, leaking the JWT secret into deploy logs. **Both artifacts read as complete alone; the defect lived only in the seam between them.**

**(f) If the migration removes or weakens a fail-closed mechanism, name it — in the header AND the commit subject.** A default that flips from fail-closed to fail-open is behaviourally invisible while the two coincide, so the change leaves no footprint at review time. The header must say what was removed and what now holds the line.

## Step 1.6 — Correcting a comment on a MERGED migration

Never edit a merged migration file. Emit a new **comment-only** migration (the `052` shape). While a migration is still **unmerged**, edit in place — the merged-history guard does not apply.

Catalog comments are frequently multi-KB single-quoted string literals, where a botched edit is a **syntax error**, not a wording problem. **Regenerate and diff; never retype** — retyping a comment of that size is how the correct halves get silently altered alongside the wrong one.

1. **One anchored substitution, asserted to match EXACTLY ONCE.** More than one match means your anchor is not unique; zero means the source drifted.
2. **Containment proof** — prove the prefix before the replaced span and the suffix after it are **byte-identical** to the original, with **one contiguous replaced span**. ⚠ **Prefer this to counting diff regions:** a region count only characterises what *changed*; the containment proof makes a positive claim about everything that **did not**.
3. **Parse-in-rollback** — apply inside a transaction and roll back, so the literal is proven to parse.
4. **Render-verify via `col_description` / `obj_description`** — read the comment back **as the catalog renders it**. The catalog string is what actually ships, and a doubled `''` leaking into rendered text is **invisible in source**.

⚠ **Where step 3 does not earn its keep:** for a comment-only migration, *"the non-comment SQL body is byte-identical to the previous file"* is a **stronger** claim than re-running the parser — it proves no behaviour changed at all, which parsing does not.

## Step 2 — INVOKER vs DEFINER decision

**Default posture: SECURITY INVOKER** ([Lock 11](../../../DECISIONS.md#adr-011)). The canonical V1 read-composition path (`fn_compute_nav` / `fn_compute_tax_liability` / `fn_render_monthly_report`) is entirely INVOKER — functions run as the calling user, inheriting their RLS context.

**SECURITY DEFINER allowlist — 4 entries** ([ADR-011 Decision 9](../../../DECISIONS.md#adr-011); grew 2→3 at SELF-187/`003`, 3→4 at SELF-293/`031`):
1. `fn_refresh_updated_at` — trigger helper for `updated_at` refresh (@`001`)
2. `fn_grant_creator_access` — Lock 3 / Decision 7 mod #2 creator-grant trigger (@`003`)
3. `fn_reclass_history_insert` — the reclass-history capture helper (@`031`)
4. The reserved general same-transaction audit-log insert helper (still unauthored — SELF-201 Task #7)

`fn_mask_acct_number` is NOT a DEFINER entry — it is a pure `IMMUTABLE`/`STRICT` string transform that reads no tables and needs no elevated privilege (DEFINER allowlist corrected 3→2 at Phase 5 Step 4 W2 per Decision 9 amendment).

**Any new SECURITY DEFINER function → Sec joint-review before finalizing.** Route via `spawn-sec-joint-review` (compose with this skill).

## Step 3 — Decision 3 matched-tenant validation

Any FK-shaped reference column — single FK, self-FK, or `INTEGER[]` array element — that crosses a tenant isolation boundary requires **explicit matched-tenant validation** ([ADR-011 Decision 3](../../../DECISIONS.md#adr-011)). PostgreSQL FK constraints validate existence, not tenant scope. Without matched-tenant validation, FK-shaped columns create chain-attack surfaces that defeat RLS protection at the schema layer.

**Required validation shape:**
- Single FK column → `WITH CHECK` constraint matching tenant anchor
- `INTEGER[]` array → `BEFORE INSERT/UPDATE` trigger validating every array element's `users_id` equals row's `users_id` (PostgreSQL cannot express this declaratively)

**Family size: read [ADR-011 Decision 3](../../../DECISIONS.md#adr-011)'s body live — this file deliberately does not carry the number.** The family **grows**, the labels are **non-contiguous**, and at least one has been **dropped** (a third status class, distinct from DDL-deferred), so *labeled* and *DDL-realized* are two different counts that diverge. ⚠ **This line previously read "7 instances at Phase 4 close" and was stale by more than half** — anyone sizing the discipline from it would have badly under-read it. **Verify the SHAPE of the instance you are adding against the canonical body, not just the count.**

This is a **non-negotiable** discipline — matched-tenant validation in the DDL is mandatory; it does not skip even when the surface "looks safe."

Decision 3 extensions are **Sec joint-review triggers** — every new FK-shaped reference column that joins the family routes to Sec before the migration lands.

## Step 4 — Base-table migration checklist

When introducing or modifying a base table:

- **`grant`-then-RLS shape** (durable root-cause, PR #106): Postgres checks table ACL before RLS. A table needs `grant select, insert, … to authenticated` even with RLS enabled — RLS filters rows; the GRANT lets the role reach the table at all. Pair every base-table migration's RLS policy with a matching table-level GRANT. Missing GRANT = ACL denial before RLS is consulted, producing misleading test failures.
- **`users_id` predicate**: RLS policies key on `users_id = auth.uid()`. After the SELF-186 migration (`001_users_id_rename.sql`), the renamed column is the isolation anchor; all downstream V1.0 RLS work depends on it.
- **Immutability triggers** for audit-class tables (Decision 2 / Lock 10): block UPDATE + DELETE across both `authenticated` AND `service_role` via DB trigger. Append-only at the policy layer is not sufficient — service_role bypasses RLS but not DB triggers.
- **aal2 step-up backstop inheritance** (C3 standing obligation; [ADR-029](../../../DECISIONS.md#adr-029) / `025_aal2_step_up_backstop.sql`): any **new sensitive tenant-owned `pfin` table** MUST inherit the per-user-conditional aal2 backstop clause on its `authenticated` policies when it lands — AND-ed into the read `USING` and the write `WITH CHECK`/`USING`, exactly as `025` does for the current 14 tables. The clause (COALESCE null-safe, inline — no helper): `(coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp','passkey') or (auth.jwt() ->> 'aal') = 'aal2')`. Without it, a new sensitive table silently ships un-claused and opens an **aal1 read/write gap on the direct PostgREST API** (Sec's C2 threat — a stolen password reaches the data before TOTP step-up). **Exclusions** (do NOT clause; state the reason in-header per `025`): (i) **global shared-read** tables (`using(true)`, e.g. `tax_character`); (ii) **service_role-only / default-deny** tables (RLS on, zero `authenticated` policy, e.g. `026`/`027`/`linked_source_sync_audit`); (iii) the **`user_settings` substrate itself** (clausing it = infinite RLS recursion — the clause's subquery reads `user_settings`). **Corollary — new `user_settings` *columns* are already covered:** the MB-1 downgrade guard (`fn_user_settings_block_mfa_downgrade`, `025`) fires only on an `mfa_policy` *weakening*, so unrelated column edits (e.g. future SELF-232 settings) are unaffected — but a **new sensitive *table* is not automatically covered** and must be claused per this bullet.

## Step 5 — QA test-pairing requirement

A new RLS policy or new SECURITY INVOKER helper **ships in the same PR** with a per-Wave two-tenant pgTAP battery (SECURITY §4.5 posture; RT-15 parity fixture). The battery must:

- Cross-tenant read → fail closed
- Cross-tenant write → fail closed
- Owner reads own rows → pass
- INVOKER helper cross-tenant invocation → asserts-fails-closed

QA authors the tests (Architect does not edit `tests/`). Sec sign-off gates V1-SHIP-BLOCK merge. A vacuous green (e.g., fixture only populates one tenant) does not satisfy the requirement.

## Routing summary

| Trigger | Route to |
|---|---|
| Any new SECURITY DEFINER function | Sec joint-review (mandatory before finalize) |
| §10 ledger change — count or layer-attribution | Sec joint-review (mandatory) |
| New FK-shaped column joining Decision 3 family | Sec joint-review (Decision 3 extension trigger) |
| Migration extends RLS surface | QA test-pairing same-PR |
| Migration ready to apply | Backend (`supabase migration up` after CI verification) |
| Migration requires CI fixture changes | DevOps |

## Gotchas

- **`major_version = 17` is PROVISIONAL** in `config.toml` — confirm against prod (`SHOW server_version;` or Studio → Settings → Infrastructure) before Phase 6 base-table work, where version-skew bites harder. Today's pure-function migrations are PG 15/17-identical.
- **Migrations live in code, not the Supabase dashboard.** Any dashboard-applied change that doesn't have a migration file is invisible to CI and is a discipline violation.
- **`supabase/tests/` is QA-owned.** Architect does not author or edit there; QA does not edit `supabase/migrations/`.
- **`BEFORE INSERT` fires BEFORE conflict detection.** With `ON CONFLICT … DO NOTHING`, a BEFORE INSERT fence **still fires** on the conflicting row — so a tenant-binding check is *not* bypassed by a same-key re-run (verified at `054`). ⚠ **The trap is the other direction:** a BEFORE INSERT trigger with a **side effect** (audit row, GUC set, sequence bump) also runs for rows that are then **silently discarded**. Do not put side effects in a BEFORE trigger on an `ON CONFLICT DO NOTHING` path without deciding you want them on discarded rows.
- **A change that is value-neutral is NOT free.** *"NAV is identical either way"* only means the defect is **invisible to value assertions** — it can still move **row sets and counts**. Say which surface a change is neutral on, and pair it with an assertion on the surface it is *not* neutral on, or the test battery will go green over it.
- **`ALTER DATABASE … SET` reaches NEW SESSIONS ONLY.** A warm connection pool (dev server, worker) keeps reporting the old value until it reconnects — which looks **exactly** like the setting having failed to apply. Distinguish *recorded* from *effective*: a catalog read-back proves it was recorded; only a **new session** proves it is effective.
- **Capability-verify at the real POST-migration state, not merely "against a real database."** ADR/Lock-named DB primitives are unrun assumptions until executed as the deploying role. **`post-` is the load-bearing half:** a deploy-runbook query was genuinely safe on `main` and became unsafe the instant a migration landed, because the migration added a row the query then matched. ⚠ And **apply onto a clean state** — a migration applied on top of its own prior outcome demonstrates nothing and looks identical to success.

## Notes

- Composes with `spawn-sec-joint-review` (Sec routing for DEFINER / Decision 3 / §10 ledger changes).
- Composes with `brief-drift-catch` (verbatim-source cross-check on Lock/ADR citations before forwarding a draft to F/CTO ratify).

### Deliberately NOT in this skill

Recorded so they are not re-added by someone who notices the gap. **A skill that absorbs everything discriminates nothing** — the same argument that keeps the §10 ledger small.

- **The general forward-reference rule** (*a document may forward-reference a document; a correctness claim must not forward-reference its mechanism*) — it governs ADRs, briefs and merge order far beyond migrations. **Home: `brief-drift-catch`.** Only the catalog-comment case is here (Step 1.5c), because there the cost of being wrong is a migration.
- **"Describe a pattern, don't quote it"** — any check that scans a corpus will eventually scan the prose written *about* the check, since that prose is the densest concentration of the tokens it hunts. **Real, and not migration authoring**: it belongs wherever grep-shaped fences are authored (CI fences = DevOps; battery-level invariant greps = QA). Not routed here.
- **`git commit --only <path>` takes the whole file**, so two edits to one file cannot become two commits — plan *"one commit describing both"* rather than promising a granularity the tool cannot deliver. **Git mechanics, not migration authoring.** Home: the commit-hygiene memory and the `finish-*` skills.
- Origin: [`supabase/CLAUDE.md`](../../../supabase/CLAUDE.md) (Step 5 canonical) + [ADR-011](../../../DECISIONS.md#adr-011) Decisions 3 / 4 / 9 / Lock 11 + PR #106 grant-then-RLS root-cause. Track record: `002_fn_mask_acct_number.sql` is the first V1 migration exercising this procedure end-to-end.
