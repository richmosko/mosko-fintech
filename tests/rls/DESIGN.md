# Per-Wave RLS verification battery — framework-body design (W3-B)

**Status:** Phase 5 Step 4 W3-B. This is the **design rationale** doc. The scaffold has landed
and the battery now lives at **`supabase/tests/`** (`_fixtures/rls_verbs.psql` + `00_rls_inversion_
self_test.sql` + `sd15_fn_mask_acct_number.sql` + `README.md`). Framework shape **locked: pgTAP
via `supabase test`** (per W3-A routing). Helper-placement **Option C confirmed**, realized via
`\ir` textual include. SD-15 test **verified against authored `002_fn_mask_acct_number.sql`**.
Remaining: first live `supabase test` run (post-Sec-clear of 002 + DevOps CI job) + per-Wave
cross-tenant cases as RLS base tables land in Phase 6.

This doc is the reviewable plan for the framework body. It defines: the two-tenant fixture
shape, the reusable cross-tenant assertion verbs, the inversion self-test (harness self-proof),
the per-Wave case pattern, and the SD-15 first-target test. **Assumptions flagged `⟦A?⟧`** are
sync-points with Architect/DevOps before wiring.

---

## 1. Two-tenant fixture shape (SECURITY §4.5)

Two **synthetic, deterministic** tenants with **fixed** UUIDs (no `gen_random_uuid()` — fixed
so assertions are deterministic and diffable):

```
TENANT_A = '00000000-0000-0000-0000-00000000000a'
TENANT_B = '00000000-0000-0000-0000-00000000000b'
```

- Seeded into `auth.users` (test DB only) as the two JWT-`sub` identities.
- Tenant A **owns** rows; Tenant B's RLS context **attempts** read/write; the battery asserts
  B sees nothing it shouldn't and cannot modify what it doesn't own.
- **NO production data / NO PII / NO real account numbers** — synthetic only, per the central
  parity governance (`tests/fixtures/parity/README.md`). The two-tenant seed is **Sec
  joint-review-mandatory** when it lands.

⟦A?-1⟧ **RLS policy column convention.** Confirm policies are `users_id = auth.uid()` (post
`001_users_id_rename`). The tenant-context helper sets `request.jwt.claims.sub`; the assertion
verbs assume `auth.uid()` resolves from it. If policies key off a different claim, the helper
adjusts.

## 2. Tenant-context + assertion verbs (the reusable framework)

pgTAP-in-Supabase runs each test file as `begin; select plan(N); …; select * from finish();
rollback;`. RLS context is set per-assertion via:

```sql
-- set the active tenant for subsequent statements (within the test txn)
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', :tenant)::text, true);
```

Reusable verbs (names provisional):

| Verb | Asserts |
|---|---|
| `_rls.set_tenant(uuid)` | switches RLS context to a tenant (role + jwt.claims) |
| `_rls.expect_cross_tenant_read_empty(tbl regclass, intruder uuid)` | intruder tenant sees **0** of owner's rows |
| `_rls.expect_cross_tenant_write_blocked(tbl, intruder, payload)` | intruder INSERT/UPDATE into owner's row **fails closed** (RLS/WITH CHECK rejects) |
| `_rls.expect_owner_can_read(tbl, owner uuid, n int)` | owner sees exactly its **n** rows (guards over-restrictive policy — fail-closed both ways) |

⟦A?-2⟧ **Helper placement** — see the options below; chosen option determines whether these
verbs live in a shared test-seed or are inlined per file.

## 3. Inversion self-test (harness self-proof — mirrors W1 inversion-mode)

W1's fences fail closed if they do **not** catch the golden violation. The RLS battery needs the
same property: prove the cross-tenant assertion **has teeth** — that it actually fails when
isolation is absent, so a green battery is never vacuous.

```
00_inversion_self_test.sql:
  - create a throwaway canary table `_rls_canary(users_id uuid, val text)` with RLS DISABLED
  - seed one Tenant-A row + one Tenant-B row
  - set tenant = B
  - ASSERT the canary LEAKS A's row  (i.e. the same isolation assertion the battery uses,
    run against an unprotected table, MUST report a violation)
  → if the assertion *passes* (reports isolated) against an unprotected table, the harness
    is broken and the self-test fails. This is the battery testing the battery.
```

This file ships with the framework and runs every battery invocation. A regression here = a QA
fence gap, exactly like a W1 fence that stops catching its golden fixture.

## 4. Per-Wave case pattern (populated as migrations land)

One file per RLS-bearing table: `NN_<table>_rls.sql`. Each:
1. seeds Tenant-A-owned + Tenant-B-owned rows for that table (inside the test txn),
2. `expect_cross_tenant_read_empty` + `expect_cross_tenant_write_blocked` for B-vs-A,
3. `expect_owner_can_read` for A-sees-own (fail-closed both directions),
4. for any **SECURITY INVOKER helper** the migration adds → a cross-tenant-asserts-fails-closed
   case (per the QA agent-def).

**Today main has no RLS base tables** — so this folder starts with the inversion self-test + the
SD-15 test only; real per-table cases land per-Wave with their migrations (same PR).

## 5. SD-15 — first real per-§10-instance target (distinct test class)

`fn_mask_acct_number(p_acct TEXT) → TEXT IMMUTABLE` is a **pure transformer** — no base table,
no RLS. So its test is **not** a cross-tenant test; it is a per-§10-instance **behavioral +
no-full-disclosure** test (SD-15's first test, per the per-§10-instance discipline):

```
sd15_fn_mask_acct_number.sql:
  - is( fn_mask_acct_number('123456789'), <masked form ⟦A?-3⟧>, 'masks to last-4 only' )
  - ok( fn_mask_acct_number('123456789') NOT LIKE '%12345%', 'never discloses full value' )
  - is( fn_mask_acct_number(''), <edge ⟦A?-3⟧>, 'empty input handled' )
  - is( fn_mask_acct_number(fn_mask_acct_number(x)), fn_mask_acct_number(x), 'idempotent' )
  - the "full-value-disclosure fence" Architect's migration forward-points to is authored here
    as the mechanical assertion that the function output never contains the full input.
```

⟦A?-3⟧ **Masking contract** — confirm with Architect the exact masked format (e.g. `****6789`
vs `•••6789` vs `XXXXX6789`) + last-N digits + empty/short-input behavior, so the assertions
match the migration, not my guess.

---

## 6. Proposed file layout (post-scaffold, in `supabase/tests/`)

```
supabase/
  config.toml                ⟦A?-4⟧ DevOps/Architect: test-DB seed paths + ports
  migrations/<ts>_sd15_fn_mask_acct_number.sql   (Architect)
  seed.test.sql              (my test-only seed; helper verbs + two-tenant baseline — Option B/C)
  tests/
    00_inversion_self_test.sql
    helpers/…                (if Option A/C: inlined/partial)
    rls/NN_<table>_rls.sql   (per-Wave, populated as migrations land)
    sd/sd15_fn_mask_acct_number.sql
```

⟦A?-4⟧ **`config.toml` test settings** — coordinate with DevOps/Architect on `supabase test`
seed-path + test-DB port so the pgTAP job is deterministic in CI (ties into the task #4 ETL CI
job + the broader CI fence shape DevOps owns).

## 7. Helper-placement decision (the one real framework sub-decision) — needs a call

Where do the reusable assertion verbs + two-tenant baseline live?

- **Option A — self-contained per-test-file.** Verbs + seed declared inside each test's
  `begin…rollback`. *Pro:* total isolation, every file standalone, zero cross-file state. *Con:*
  boilerplate repetition.
- **Option B — shared test-seed.** Verbs + two-tenant baseline in `supabase/seed.test.sql`,
  loaded once into the test DB; test files call them. *Pro:* DRY, single home for tenant UUIDs.
  *Con:* helpers persist outside the per-test txn (fine for read-only verbs); prod DB must never
  load the test seed (already disciplined in the parity README).
- **Option C — hybrid (recommended).** Assertion **verbs** in the shared test-seed (DRY); the
  two-tenant **data** seeded **per-test-file** inside the rolled-back txn (no data bleed across
  tests). *Pro:* DRY verbs + isolated data. *Con:* two places to look.

**Recommendation: C.** Reusable verbs shouldn't be copy-pasted; per-test data shouldn't bleed.
Sec-relevant because it touches where synthetic seed data lives — flagging for the joint-review.

---

## 8. Battery-design rules (ADR-042 close-gate review, 2026-08-03)

Seven rules, from a single review. They are not seven lessons — **six are one sentence at
different layers**, and rule 0 generates rule 1.

### 0. A test's fixture is the thing it cannot test  *(the generator)*

A battery that seeds its own rows has **by construction substituted for the production
path**, so it can never detect that path's absence — however thorough it is. A fixture
supplying an `fx_feed` rate cannot detect that production never sets one; one creating a
non-USD account cannot detect that production never creates them; one seeding a checkpoint
cannot detect that nothing writes checkpoints.

> **The more complete the fixture, the more of production it conceals.**

Found via `pfin.account_event`: its battery inserts its own rows and checks RLS, the
matched-tenant fence, the vocabularies and immutability — **all green forever against a
table nothing in the system writes.** Reachability can only be asserted in the *would-be
writer's* battery, never the table's.

### 1. A battery must state what it structurally cannot prove

The disclosure. **Rule 0 is how you know what to disclose** — start from what the fixture
supplies, because that is the list. Without it, *"what can't this prove?"* is a question
with no method.

Corollary found the hard way: coverage can be correct while **discoverability** fails. The
`account_event` reachability assertion existed and was independently re-derived as missing,
because anyone auditing that table reads its own battery and finds only property tests.

### 2. Count raise sites in the subject against raises asserted — not assertions against `plan()`

A plan count proves the **file** is internally consistent. It says nothing about coverage of
the **thing under test**, and stays correct while a fence goes untested. This is the only
method in the review that found a *missing* fence rather than a broken one.

### 3. Assert the precondition separately from the result

For any operation that can silently no-op. Three instances in one day, all reporting success
by not doing the work:

| mechanism | reported success by |
|---|---|
| `EXPLAIN` without `ANALYZE` | never executing |
| `count(*)` over an unconsumed projection | never evaluating (the call is elided) |
| `str.replace` with a stale anchor | never matching |
| `\|\|` fallback on a verification command | turning an error into a plausible answer |

`assert anchor in s` before the replace. Consume the projection. No `||` on a verification
command. **Check the operation had something to operate on.**

### 4. Print the pair — and check the pair is independent

**None of the rule-3 instances was caught by a check.** Each was caught by an implausible
number visible only because two figures were printed adjacent — a plan count against an
assertion count, a raise count against zero, a NAV that did not move.

Adjacency is not the property; **independence is.** Two numbers from one source agree by
construction and detect nothing.

> **Validity test: what would have to be wrong for these two numbers to disagree?**
> If the answer is *"nothing — they come from the same place,"* it is not a check.

That test is what stops rule 4 becoming ritual.

**Sub-rule — the artifact-state ladder (Sec).** The same independence test applies to claims
about an artifact's own state. Not a pair but a ladder, and **each rung protects against a
different failure**, which is what makes it actionable rather than ceremony:

| rung | protects against |
|---|---|
| **written** | *nothing* — a `checkout` loses it |
| **committed** | checkout loss; visible to every worktree (shared object store) |
| **pushed** | **machine loss** — otherwise there is one copy, on one machine |
| **merged** | **discoverability** — reachable from `main` without knowing a branch name |

Each adjacent pair is independently derived and can disagree — a commit can fail, a push can
be rejected, a merge can be blocked — so each junction is a real check. **"Written" names one
rung and implies three.** This section was itself reported as "written, not queued" while
uncommitted: the rule that would have caught it was in the file that wasn't committed.

### 5. A false assertion is worse than a vacuous one

A **vacuous** assertion gets fixed by strengthening the test. A **false** one gets "fixed" by
weakening the code.

Concrete: asserting `actor = 'system:remediation'` ever appears would fail on *correct*
behaviour under a model where the operator dispositions as a user session — and the natural
response to that red is to make the writer emit a value the model says should not exist.
**Assert that what is written matches its context; never that a particular context is
reachable.**

### 6. A failing assertion is a gate; the same fact as a note is a hope

A red that resolves when a writer lands belongs in the suite, not in a TODO. Anyone can mark
a note done.

### Anchoring (a sub-rule of 0, learned over four iterations on one assertion)

**Anchor on the subject, not on a token that co-occurs with it.** Each "cleaner" version was
weaker: a shared idiom collided with an unrelated function; a bare table name matched
routines *named* for the table; excluding trigger functions would have blinded the check to
an inline copy in the close gate — the single worst case it could catch. And prefer a
**behavioural** assertion over a textual one where both are available: text inspection has no
natural failure mode to calibrate against, which is why it took four tries and the
behavioural form took one.

### The rename trap (a sub-rule of 3, and the same precondition shape)

**Two identical adjacent literals can belong to different vocabularies.** When
`reason_code` was renamed `closed` → `no_longer_used`, every fixture row read
`('closed', 'closed')` — `event_type` then `reason_code`, adjacent, both the same literal,
and **`event_type` still legitimately uses `'closed'`.** A blind find-and-replace would have
silently broken the vocabulary that did *not* change.

What prevented it was not care: it was **counting the sites and asserting the count before
replacing** — the same precondition shape as `assert anchor in s` and as refusing a `||`
fallback on a verification command. **Three tools, three people, one pattern: check the
operation had the right thing to operate on.**

Generalises to any rename where a value collides with a sibling column's vocabulary.

### Provenance: three coordinates, re-derived at use

A result is uninterpretable without **database state · artifact ref · fixture reach**. All
three are provenance records, not guarantees — **cite at rest, re-derive at use.** A pinned
ref goes stale exactly as silently as an unpinned file, only more slowly. And record what the
fixture can *reach*, not merely what it contains: a EUR account with no `fx_feed` price looks
complete and exercises nothing.
