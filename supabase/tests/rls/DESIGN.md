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

> **CALIBRATION DATA — read before trusting any rule below.**
>
> **A rule that only ever catches other people is a rule shaped around its author's blind
> spots** (Sec). That test is only runnable if the catches are attributed, and in six months
> none of it is recoverable from the rules themselves — so it is recorded here as data, not
> as credit.
>
> | rule | applications | self-catches |
> |---|---|---|
> | route by shape, not by confidence | 3 | **2** |
> | build to the risk, not the shape of diligence | 2 | **2** |
> | a caveat is a claim | 1 | **1** |
> | confidence has a timestamp | 1 | **1** |
> | regenerate from the catalog and diff | 1 | **1** |
> | the rename trap | 1 | **1** (prevented) |
> | absence reads as recency | 1 | 0 |
> | a battery cannot prove it is reached | 1 | 0 |
>
> **THE COUNT IS LOAD-BEARING — without it the test conflates two opposite failures** (Sec):
>
> - **MISCALIBRATED** — many applications, no self-catch. **The shape is the problem; reshape it.**
> - **UNTESTED** — few applications, so no self-catch has had the chance. **Nothing is wrong; it needs use.**
>
> Same cell, opposite remedies — and **reshaping an untested rule is how a good rule gets
> damaged by its own audit.**
>
> **Applying it: both zero-catch entries sit at ONE application. Neither is miscalibrated;
> both are young.** The first recording of this table flagged them "re-examine first,"
> which was the wrong disposition for the right observation. **Leave them alone and use
> them.** Revisit if either reaches ~5 applications still at zero.
>
> Nothing here is flagged for reshaping. The table's value is that it can be re-run: a rule
> drifting toward many-applications-zero-self-catches is shaped around its author's blind
> spots, and that is only visible if the counts are kept.



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

**Confidence has a timestamp and does not display it.** A binding is a claim about a ref —
and so is *a memory of having checked one*. "These batteries are bound to current refs" was
true when verified and silently false six commits later; nothing about holding the belief
changed when the underlying file moved. **Re-derive at use applies to your own prior
verification, not only to other people's claims.**

**And there is a rung BELOW `written`, which is the one that bit us:** **decided.** A
decision that lives only in a conversation has exactly the durability of the conversation —
and from the next person's position it is **indistinguishable from a decision never made.**
This document's own relocation was settled, the objection to it measured and withdrawn, and
then not executed for a full session; the stale path went on producing silent empty results
the whole time. **The rung with no artifact to inspect is the one with no way to notice the
gap except by hitting it.**

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

### A caveat is a claim (sub-rule of 3, and the most expensive form)

**A caution about instrument conditions is itself an assertion about state, and needs the
same treatment as the claim it qualifies.** It is easy to exempt because it is the careful
half of the message.

Instance: a request to measure an index-ordering defect carried the caveat *"the table is
empty, so the planner will seqscan regardless and the comparison may show nothing."* **The
table was not empty — it was absent.** The caveat was structurally right and premised wrong,
**and the wrong premise pointed at "don't bother."**

> **A well-formed caution built on an unmeasured premise licenses skipping the test.**
> That is worse than no caution at all, because a caution carries authority.

The measurement was only possible because the instrument was built to conditions the premise
argued against — a synthetic table with 20,000 rows, `ANALYZE`d, `enable_seqscan = off`,
inside a rolled-back transaction. **Two index shapes with real statistics, rather than a plan
against a degenerate plan.**

### Route by shape, not by confidence (sub-rule of 3; same defect as the caveat rule)

> **The shape is "a derivation that has not been run." Confidence is not an input to the
> decision.**

Confidence is *produced by* the same reasoning under evaluation, so it cannot also referee
it. Three derivations of identical shape in one review — an arithmetic decomposition, a
negative existential about the schema, and an index-ordering claim. **Two wrong, one right,
and nothing available at the time separated them.** The only variable was whether each got
run before it got recorded.

**A discipline gated on doubt is gated on the one signal the failure mode disables.** The
wrong ones did not feel wrong; that is what made them propagate.

Pairs with *a caveat is a claim* — same defect at different scopes. One says **your hedge is
a claim**; this one says **your confidence is not evidence**.

### Absence reads as recency (a variant of "absence must not become a value")

Two separate mechanisms can make *unknown* present itself as *newest*, and removing one
leaves the other:

- a **defaulted date** (`current_date` on an event of unknown date) makes unknown look like
  **today's** event;
- **`NULLS FIRST`** — Postgres's default under `DESC` — makes the resulting NULL sort as the
  **latest** event in `order by <date> desc limit 1`, the query everyone writes.

Removing the fabricated date so absence stops masquerading as information leaves it
masquerading as *the most recent* information. **Fixing the value without fixing the
ordering fixes nothing at the point of use.**

### Regenerate from the catalog and diff — never retype a body you are re-pointing

When changing a predicate inside an existing function, take the body from
`pg_get_functiondef()`, substitute only the predicate lines, and **prove by diff that
nothing else moved.** A body written from recall is accepted by `create or replace` and
applies clean — wrong return types, wrong column counts, invented logic and all.

**And the diff earns its keep twice.** It prevents fabrication, and it **exposes semantics
that exist only in the difference.** Instance: a securities-leg predicate read
`coalesce(acc2.is_active, false)`. That `coalesce` was doing **fail-closed work on a LEFT
JOIN miss** — invisible in the new text, because the natural replacement
`(acc2.closed_at is null)` reads correctly and **inverts it**: a missing account row yields
NULL `closed_at`, `NULL is null` is TRUE, and an orphan holding gets **counted** in an
active-only NAV. Only the before/after pair shows it.

> **A correct-looking new body cannot reveal what the old one was doing.**

Same family as *a caveat is a claim*: both are about not trusting the careful-looking half
of your own work.

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

---

## 9. Three more, from the ADR-042 Sec-review round (2026-08-04)

All three were **measured in the batteries, not reasoned into them** — each is recorded with
the observation that produced it, per §8's calibration rule.

### A trigger's NAME is its firing ORDER — renaming one re-points every message-matched assertion

Postgres fires row-level triggers on one event **alphabetically by trigger name**. So a rename
with no behavioural intent silently changes *which fence a given write meets first*, and every
assertion that matched on a raise message re-points with it.

**What makes this worse than an ordinary rebind: the assertions do not break, they LIE.** The
write is still refused, a raise still fires, the SQLSTATE is still `P0001` — only the
*diagnosis* changed. A bare SQLSTATE or "any exception" match would have stayed green through
the whole reordering while testing a different mechanism.

Measured: `account_event_origin_fence` → `account_event_block_direct_insert` sorts from after
`m` to before it, and `(D1c)`/`(D2a)` flipped from the `#16` matched-tenant fence to the
wrong-origin fence **mid-session, with no edit to either the battery or any fence body.**

> **The consequence was not a rename. `#16` stopped being reachable at `authenticated` at all.**

That is a coverage change wearing a rename's clothes, and the battery's standing prose ("the
fence is the SOLE gate at authenticated") became false while every assertion still passed.
**When a trigger is renamed, re-derive which mechanism each assertion now targets** — and if a
fence has become unreachable at a tier, say so where the old claim was, rather than deleting it.

Related to §8's *rename trap* but a distinct mechanism: that one is two identical literals in
different vocabularies; this one is a name that is also an ordering key.

### A BEFORE-trigger fence makes every WITH CHECK conjunct behind it behaviourally unfalsifiable

Architect's generalisation, and it is worth stating once as a rule because it has now been
re-derived three separate times on one table.

Postgres evaluates a policy's `WITH CHECK` **after** BEFORE ROW triggers. So on any table where
a BEFORE INSERT fence refuses a class of writes, **every policy conjunct sitting behind that
fence is unreachable by any behavioural probe of that class** — not untested, *unfalsifiable*.

> **On `pfin.account_event`, no `WITH CHECK` conjunct can be proven behaviourally at
> `authenticated`. They must be proven DECLARATIVELY, from `pg_policies`.**

Three cases, one cause:

| conjunct | why unreachable | proven by |
|---|---|---|
| `users_id = auth.uid()` | `#16` intercepts every forged pair first | `(D1d)` |
| the `025` aal2 step-up | same — an aal1 session cannot see its own account | `(D1d2)` |
| `actor = 'user:' \|\| auth.uid()` | the wrong-origin fence refuses the POST first | `(D1g)` |

**The trap is that a behavioural probe still goes GREEN.** It is refused — by the fence in
front — so the assertion passes while the conjunct it names is never consulted, and would keep
passing if that conjunct were deleted. Any such probe kept for corroboration **must say in its
own message that it is corroborating**, or it becomes the load-bearing-looking assertion and
the declarative one reads as redundant. That is the `(S4b)` defect, one file over.

Corollary for reviewers: *"the fence covers it"* is not a reason to drop the conjunct. A policy
survives `ALTER TABLE … DISABLE TRIGGER` and `session_replication_role = replica`; a trigger
does not.

### An "any exception" assertion cannot tell its fence from a fence that refuses everything

A self-catch, and the cleanest available instance of §8 rule 4.

`(D1e)` — the Sec-veto assertion for the matched-tenant actor forge — was first written
deliberately mechanism-agnostic (`throws_ok(sql, null, null, …)`), reasoning that naming a
SQLSTATE would encode whichever fix landed rather than the requirement. **It passed on its
first run, and for the wrong reason:** a separate fence had already landed that refuses *every*
direct authenticated INSERT whatever the actor says.

Nothing about the green distinguished those two worlds. What exposed it was its **non-vacuous
companion going red in the same run** — two independently-derived results that disagreed.

> **Mechanism-agnosticism buys independence from the fix and pays for it in vacuity.**
> It is the right instrument only where the companion is strong enough to price it.

The general rule is unchanged — *write against the catch criterion, not the fix* — but the
criterion has to be sharp enough to fail against the wrong mechanism. Here that meant binding
to the fence's own message once the fence was readable, which is also what this suite's
distinct-message discipline already required.

### A battery organised around one axis reports coverage of the TIER

Sec's F1 veto — any tenant could POST `actor = 'system:remediation'` for their **own** account —
survived a file that was **15/15 green**, had a LAYER MAP, and carried authenticated-tier
assertions.

Why it was invisible: **every authenticated-tier assertion in that file probed the
CROSS-TENANT axis.** `(D1c)` forges `users_id`; `(D2a)` forges `account_id`. Both are caught,
and their green reads as *"the authenticated tier is covered."* The forge needing no
cross-tenant step — a tenant, its own account, a false actor — had no assertion at any tier.

The LAYER MAP did not prevent this; **its completeness concealed it.** A map that accounts for
every mechanism looks exhaustive, and a reader checking "is this mechanism covered?" gets yes
every time.

> **Before adding a case, name the AXIS it probes as well as the MECHANISM it targets.**
> One-axis coverage of a tier is what a single-axis map cannot show you is missing.

Same family as *a battery cannot prove it is reached* (§8 rule 0): the missing case is
invisible from inside the set of cases that exist.

### Harness note — a rolled-back savepoint rewinds pgTAP's plan counter, not its numbering

Measured, because it produces **a false instance of this suite's own abort alarm**.

pgTAP's TAP *numbering* comes from a sequence (non-transactional); the counter `finish()`
compares against `plan()` is a temp-table value (**transactional**). So `rollback to savepoint`
rewinds the counter while the emitted numbering marches on — and only the **last** rolled-back
savepoint's rewind survives, because any later assertion re-sets the counter to its own number.

Observed in `058`: 47 emitted results, **every one `ok`**, and
`# Looks like you planned 47 tests but ran 45` — because the trailing inversion block (G1/G2)
runs inside savepoints that are rolled back.

That message is the exact shape the inversion block's own header cites as proof an aborted run
cannot pass quietly (`053` reported *"planned 19 but ran 0"*). **A fully-green file emitting it
trains the reader to discount the one signal that distinguishes a real abort.**

- **Fix structurally: keep a non-savepoint assertion LAST.** In `058` that is `(G3)`, which
  independently earns its place by asserting the inversion block's sabotage was actually undone.
- **Never lower `plan()` to the reported figure.** That hides the rewind and silently re-breaks
  the moment a savepoint is added or moved.

### Calibration table — updated at this round

Applications and self-catches from this review, appended to §8's table rather than replacing it:

| rule | +applications | +self-catches |
|---|---|---|
| print the pair — and check the pair is independent | 1 | **1** (the `(D1e)`/`(D1f)` disagreement) |
| anchoring: anchor on the subject, not a co-occurring token | 2 | **1** (`'%closed%'` matched `037`'s freeze-closed trigger) |
| a trigger's name is its firing order *(new)* | 1 | 0 |
| one-axis coverage reports the tier *(new)* | 1 | 0 |
| an "any exception" assertion cannot identify its fence *(new)* | 1 | **1** |

Both new zero-catch rules sit at ONE application. Per §8's own reading rule that is **UNTESTED,
not MISCALIBRATED** — leave them alone and use them; revisit at ~5 applications still at zero.

---

## 10. From the ADR-042 `059` round (2026-08-04)

Five, all found by RUNNING files that were green or believed green. Four are one sentence at
different scopes: **the thing a test says about itself is not evidence.**

### A test's claim that it detects something is itself an assertion — and it is usually unrun

The sharpest instance this project has produced.

`050`'s `(A4)`/`(A7)` carried explicit prose: *"RED if 059 re-points to the CURRENT-STATE
predicate instead of the AS-OF one"*, naming the exact defect, citing the BACKLOG entry that
records why it leaves no footprint. **Measured: re-point `059` to the naive current-state
predicate and `049`, `050` and `051` all pass, zero failures.** The assertions were at a
*post-closure* as-of, where both predicate forms agree and the account is worth zero either way.

> **A whole battery agreed with the defect its own comments described.**

The prose was not wrong about the danger. It was wrong that these assertions saw it — and that
claim had never been run, because *running the detector* means running it **against the defect**,
not against a correct implementation.

**Method: to believe an assertion detects X, build X and watch it go red.** Anything less is a
claim about a test, in a file whose entire purpose is to replace claims with tests. Same family
as *a caveat is a claim*, applied to a test's self-description.

### An assertion can compare an expression to itself

`(X7)` in the `059` battery — the ⭐-marked fail-closed guard, carrying the longest
justification block in the file, with a verified before/after diff of the exact fail-open it
protects against — read:

```sql
is( pfin.fn_compute_nav('2026-07-31', true),
    pfin.fn_compute_nav('2026-07-31', true) )   -- the SAME expression, both sides
```

It could not fail for any implementation, fixture, or predicate.

> **A rich justification block is not evidence that the assertion beneath it is wired up — and
> it actively discourages reading the two lines that are.**

Pairs with rule 4: print the pair, *and check the pair is independent*. Here the two "sides"
were not merely dependent, they were **textually identical**, which is the degenerate case the
independence test exists to catch. It survived review by everyone who read the prose.

### Absence assertions are vacuous whenever the subject never existed

`(R5)`/`(R6)` asserted `fn_assert_closure_reconciled` was absent and ungranted. Both **passed**.
`059` as merged never creates that function — the design changed to a plain
`ALTER TABLE … VALIDATE CONSTRAINT` and the battery predated it.

`(R5)`'s own comment records being caught once already for vacuity and being *conjoined* against
it. The conjunction stopped it passing pre-`059`; it did nothing about passing because the
subject was never built.

> **No conjunction rescues an absence assertion whose subject does not exist. Only anchoring it
> to a subject that DOES exist does.**

The replacement asserts the decommission of things that were genuinely there (the CHECK, the
sync trigger, its function), conjoined with something only true *after* the migration
(`closed_at` present **and** the as-of comparison live in `fn_compute_nav`) — verified by
running the block against a pre-`059` stack and watching it go red.

### Anchoring, again: a check matched the warning label written to prevent its own defect

`(X6)` asserted `fn_nav_composition`'s definition does not contain `is_active`. It went RED
against a **correct** function, because `059` had added an in-body comment reading *"If you came
looking for `where acc.is_active` in 049 because an older comment sent you…"*.

**The check tripped on the prose that exists to prevent the mistake it checks for.** Strip SQL
comments and match executable text only. Second self-catch of the anchoring rule; it keeps
arriving as *"my pattern matched something that merely mentions the subject."*

### Two predicates need two fixtures — one date guards one leg

`059` re-points **two** predicates: the securities leg (`acc2`, via LEFT JOIN) and the cash leg
(`acc`). Different lines, different subqueries — so flipping *one* is a realistic partial edit.

A single as-of catches it only if that date happens to exercise that leg. The fixture's
wind-down separates them by construction: at `2026-06-10` the closed account is
securities-only (1500), at `2026-06-25` cash-only (1000).

**Verified by flipping each leg alone:** `acc2` reds the securities pair and leaves the cash pair
green; `acc` does the exact inverse.

> **Count the predicates in the subject, then check each has a fixture that reaches it** —
> the fixture-side twin of rule 2 (count raise sites in the subject, not assertions against
> `plan()`).

### Calibration table — this round

| rule | +applications | +self-catches |
|---|---|---|
| a claim that an assertion detects X is itself an assertion *(new)* | 1 | **1** |
| an assertion can compare an expression to itself *(new)* | 1 | **1** |
| absence is vacuous when the subject never existed *(new)* | 1 | **1** |
| anchoring: anchor on the subject, not a co-occurring token | 1 | **1** |
| count the predicates, then check each has a fixture *(new)* | 1 | 0 |
| print the pair — and check the pair is independent | 1 | **1** |

Every new rule here arrived as a self-catch except the last, which is at one application and is
therefore **untested, not miscalibrated** — leave it and use it.

### A mocked chain shape pins nothing — the residue no token-classification reaches

Backend's finding at the §7.9 AC-4 sweep, carried here because it names a gap in **AC 1's own
method** and this file is where that method lives.

AC 1 says: classify a test by the TABLE it targets, not by the token it contains — because
`is_active` means different things on `pfin.account` and on `linked_source`. Sound, and it
found real instances.

**But `netWorth.test.ts` had no token to classify.** It stubbed `.eq()` and asserted nothing
about the predicate — no column name, no value, no `is_active` anywhere in the file. It would
have gone on passing while the production query 400'd against a dropped column.

> **A test that mocks a chain's SHAPE without pinning what the chain ASKS FOR is invisible to
> every method that works by reading tests for what they mention.**

It surfaced only because the suite was actually run. Generalises past this migration: any
fluent-builder mock (`.from().select().eq().order()`) asserts the calls happened in a shape,
which is exactly the part that does not break when the schema moves underneath it.

Practical form: **when a mock stands in for a query, assert the ARGUMENTS, not just the call.**
`expect(eq).toHaveBeenCalledWith('closed_at', null)` survives a rename by failing; `expect(eq)
.toHaveBeenCalled()` survives it by passing.

Same family as rule 0 — the fixture (here, the mock) substitutes for the production path and
therefore cannot detect that path's absence — but sharper, because the substitution is
invisible to a text sweep rather than merely undetectable by the test.

### An inversion result stated without its condition reads as a live failure

Mine, from this round, and it cost a teammate a real decision point.

I committed the detector work under the subject **"the pre-closure re-point detector — 7 reds
where there were 0"**. Against `059` as authored the suite is **0 failures**; the seven reds
exist only under a deliberate sabotage of the predicate, and are the proof the detector has
teeth. The subject line stated a red count with no database state attached, and the team lead
correctly stopped to ask whether `059` was broken.

This is this file's own ⟦EXPECTED STACK⟧ rule — *a result is uninterpretable without the
migration set it ran against* — broken by me, in a commit subject, in the same session I
extended that rule twice.

> **The three-coordinates rule applies to every surface a result is quoted on, and a commit
> subject is the surface most likely to be read alone.**

Fix is one clause: *"7 reds UNDER SABOTAGE, 0 against `059` as authored."* Say what the number
was measured against, or do not quote the number.

---

## 11. Standing cautions (Sec-requested, 2026-08-04)

### "A whole battery agreed with the defect its own comments described"

Sec asked for this in the file as a standing caution, not as a war story. The full instance is
§10; what follows is the part that generalises.

`050` carried prose naming a specific defect — a current-state re-point where an as-of one was
required — citing the BACKLOG entry recording why it leaves no footprint. **Re-pointing the
migration to that exact defect left `049`, `050` and `051` all passing, zero failures.**

**Sec's addition, which is the load-bearing half and was not in my finding:** the
undetectability is **STRUCTURAL, not an oversight**. Under V1, with no closed account in
existence, the two predicates are **extensionally identical** — they select the same rows for
every input. No data-driven test can separate expressions that agree on all reachable data.

> So the instrument is not "test harder". It is to find the **one input where the two must
> agree for a reason other than emptiness**, and assert there.

Concretely: `fn_compute_nav(d, true) ≡ fn_compute_nav(d, false)` at a **pre-closure** date with
a **non-zero shared contribution**. Both predicates include the account there — but only the
as-of one includes it *because it was open then*; the current-state one excludes it and the
equivalence breaks. The non-zero contribution is what makes the agreement meaningful rather
than a comparison of two empty sets.

**The general rule:**

> **When two candidate implementations agree on all currently-reachable data, no amount of
> coverage distinguishes them. Construct the input where they must agree for DIFFERENT
> reasons, and assert the agreement there.**

And the meta-rule the episode is really about:

> **Prose in a test file that says "this catches X" is an untested claim about a test.**
> Verify it the only way a detector can be verified: **build X and watch it go red.**

### An assertion on a filter STRING cannot distinguish a correct predicate from a consistent pair of wrong ones

The app-layer twin of the above, from the same review.

`netWorth.ts` filtered `closed_at.gt.<asOf>` while the SQL filtered `closed_at::date > p_as_of`.
PostgREST promotes the bare form to midnight, so the count and the NAV described **different
populations for up to 24 hours after every app-initiated close** — a user closing their last
account at 14:00 saw a real `$0` instead of the empty state.

It survived every check because the test asserted the **string**. A string assertion is only as
correct as the string someone typed into it, and it goes green the moment the code and the test
are edited together — which is precisely what "update the test to match" means.

> **A string assertion pins agreement between a test and an implementation. It says nothing
> about whether either is right.**

The instrument: **evaluate the emitted predicate against a fixture and assert the resulting
population** (`netWorth.boundary.test.ts`). With the precondition that every clause must be
*recognised* — a parser that silently returns "no match" on an unknown operator converts a
predicate change into a passing test over an empty population.

Note the layer split, because neither file substitutes for the other: the DB battery proves the
SQL is right; the app test proves the app asks the SQL **the same question**. **The bug lived in
the gap between two green suites.**

---

## 12. Rule 0 at the system boundary — when the fixture is the other half of the system

§8 rule 0 says **a test's fixture is the thing it cannot test**. That was written about fixtures
*inside* a battery — seeded rows standing in for a production writer. It has a larger form, and
the ADR-042 timezone defect is the instance that made it visible.

### The defect

`+page.server.ts` computes the NAV as-of as `new Date().toISOString().slice(0,10)` —
unconditionally **UTC, in the Node process**. Postgres evaluates `closed_at::date` in the
**session's `TimeZone`**. Two clocks in two processes; they agree only if the session is UTC.

Measured, session `Asia/Tokyo`, instant `2026-03-01 23:00Z`: `closed_at::date` is `2026-03-02`
while Node says `2026-03-01`, so `closed_at::date > '2026-03-01'` is TRUE and **a just-closed
account stays in the NAV headline for ~9 hours.** Under `America/Los_Angeles` it is FALSE —
west of UTC fails *safe*, which is worse than failing loudly, because the defect becomes
hemisphere-dependent and a US-based reviewer cannot reproduce it.

### Why no test catches it, and why that is structural rather than an oversight

> **No test at any layer can see this defect, and the reason is structural — each layer's tests
> stub the other.** The pgTAP batteries never involve Node, so they cannot observe the app's
> UTC-derived as-of. The vitest tests mock the database, so they cannot observe the session
> TimeZone. **The defect lives in the disagreement *between* two processes, and every test we
> have replaces one of them with a fixture.**

That is rule 0 one level up: the fixture is not a seeded row, it is **the other half of the
system**. Each suite is complete and correct about its own half, and the invariant is a
*relation between the halves* that neither can express.

### The detector

> **For any invariant that spans two processes, ask which process each test replaces with a
> fixture. If every test replaces one of them, the invariant is untested — however many tests
> there are, and however green.**

Symptom worth recognising, because it presents as reassurance: **a suite that passes under every
value of a variable is not robust to that variable — it is blind to it.** `049`'s boundary
battery returns 33/33 under UTC, Asia/Tokyo *and* America/Los_Angeles. That reads as
zone-independence. It is zone-*blindness*: the fixtures use naive timestamps interpreted in the
session zone and compare in that same zone, so both shift together and cancel. Invariance to an
input is evidence the input is not reaching the assertion.

### The consequence, which is the part that must not be lost

**The database TimeZone pin and Backend's as-of branding are not belt-and-braces. They are the
only two controls** — because no test will ever catch a regression in either.

That changes how both must be treated. Neither may be removed as redundant on the strength of
the other, and neither may be justified by "the tests would catch it." Any future proposal to
simplify one of them has to be argued on its own, against the fact that nothing downstream is
watching.

### What would actually close it

Only a test in which **both halves are real**: the app's date derivation and a live database
session, in one assertion. That is an integration test, and `api/` has no integration harness
today (all query tests mock the client). Naming that as the gap is more honest than adding more
tests on either side, which would raise the count and change nothing.

Until such a harness exists, the honest posture is the one above: two sole controls, documented
as such, plus `01_session_timezone.sql` — which asserts the CI stack's zone and **says in its
own message that it cannot observe the deployment.** A narrow true claim beats a broad one that
reads as covering production.

---

## 13. From the SELF-219 `062` round (2026-08-07) — what confident prose is worth

Six corrections across one issue, **every one of them found by running something** — and several
had survived repeated careful reading by three parties. That distribution is the finding; the
individual rules below are downstream of it.

> ⚑ **CORRECTED — the original opener said "not one was found by reading," and that was FALSE.**
> A seventh correction arrived later in the same issue and came from reading. See the correction
> immediately below; it is placed here, where the false claim was, rather than at the end of the
> section.

### Correction: measurement and failure-history pattern-matching catch different things

The claim *"not one was found by reading"* held over the six rows above and **was falsified by
the seventh**. A reviewer pre-flagged a defect in a sentence **that did not yet exist**, from the
failure history of the surface alone: *"demoting `(N2)` to corroborating is a good reason to
restate `(N1)`'s strength, and restating a fence's strength is exactly where the round-1
Condition 2 defect came from."* No measurement, no diff. By the time it landed the sentence had
already shipped, unqualified, exactly as predicted.

> **Measurement catches defects that EXIST. Failure-history pattern-matching catches defects
> BEFORE they exist — and it is cheaper, because there is nothing to build. Neither substitutes
> for the other:** measurement cannot fire on a line not yet written, and pattern-matching cannot
> tell you whether the thing it predicted actually happened.

**The cost asymmetry is the practical part.** A pre-flag's cost scales with the *surface's
history*, not its *content* — so it is the only technique here that gets **cheaper as a file
accumulates scars**, while every measurement-based check gets more expensive as the artifact
grows.

**Consequence, stated because the naive reading points the other way:** *"fresh eyes catch more"*
is true for **content** and false for **history**. On a surface with accumulated scars, a
reviewer's model of *where this file has already been bitten* is the cheapest catch available and
**is destroyed by rotation.** The instance: three specifics — mechanism, surface, precedent — all
correct, from a reviewer who had them only because it had been bitten there before.

### How the false claim got in: a headline over your own data is a relay

Worth separating from the §14 relay corollary, because the verbatim-relay rule **would not have
prevented this and nobody violated it.**

The six-row table above never made the universal claim. It appeared only in the **headline
written over that table by its own author.** Then it was compressed again — into a finding
relayed upward, and from there into durable session memory, which is the copy that outlives the
branch and loads into the next session as established fact.

1. author compresses his own table into a headline → scope dropped
2. lead compresses the headline into a finding → dropped further, **authority added**
3. it lands in the persisted record as fact

> **A headline over your own data is a relay. The verbatim-relay discipline does not exempt you
> from it because the source is yours.**

And the compounding: **compression toward higher authority strips qualifiers and adds weight
simultaneously**, so the effects multiply rather than merely co-occur. The furthest copy from the
data carried the highest standing and the longest half-life — which is why the persisted one was
the worst instance and why correcting *it* mattered more than correcting the section.

**Structural note with a real consequence:** the author cannot see the durable memory. Any
overstatement shipped in an artifact can only be corrected there by whoever relays it — which is
an argument for relaying findings **with their qualifiers** rather than as headlines.

### What the re-measure discipline actually costs *(Security Reviewer)*

Recorded because it is the honest accounting, and it is the reviewer's own note about churn it
had itself caused — the fifth ref-move on this branch was its own pre-flag landing:

> *"The churn came from the channel being responsive, not from anyone being sloppy. Cheap to
> absorb when the receiver re-measures; expensive exactly once, if they don't."*

That is the whole trade. A responsive review channel **moves the ref repeatedly**, and every
move is harmless to a receiver who re-derives state and silently fatal to one who quotes a
remembered hash. The discipline is not defensive bookkeeping; it is what makes responsiveness
affordable.

### Confident prose is not weak evidence of correctness — it is NO evidence, and it correlates with error

The headline, and it indicts this document as much as anything else.

Every correction in this round that cost a commit sat underneath **confident, specific,
well-reasoned prose** — and in several cases the prose was the *reason* nobody looked:

| what the prose said | what measurement said |
|---|---|
| `(G3)` "exactly 4 of the 6 points are stale", with the dates enumerated | **5** — the author counted the pre-checkpoint side and forgot carry-forward continues after |
| `(V8)` "the sabotaged policy is BACK", asserted on `pg_policies` | `count(*)` is **1 in both the corrupted and restored worlds** — it could not tell them apart |
| `(E3)` "names the specific wrong answer" a `$0` chart would show | asserted over a set `(E2)` already proved empty — **it cannot fail unless `(E2)` fails first** |
| `062` item 10: fence "the zone-aware timestamp type's **name**" | `timestamp with time zone` and `timestamptz` are two names for one type — the fence passed over the canonical spelling |
| `(B1)` "a LEFT JOIN would emit fabricated NULL/0 leading points" | after the clamp landed, **cross→left produces byte-identical output** — the claim had silently become false |
| `(V10)` sabotage built to make the zone fence fire | `'today'::date` is **const-folded into the plpgsql plan cache** — it did not fire |

> **A rich justification block is not evidence that the assertion beneath it is wired up**
> (§10 already says this). The stronger claim this round supports: **confidence is
> ANTI-correlated with having measured**, because the cases that feel obvious are exactly
> the ones that get written down instead of run.

Operationally: **when reviewing an assertion, read its message LAST.** Read the predicate,
predict the result, then run it. The message is the author's hypothesis, and reading it first
recruits you into it.

### The better instrument does not subsume the cruder one

`(Z4)` measures zone-invariance directly — run the function under two extreme session
TimeZones against one fixture, assert byte-identical output. It is immune to evasions nobody
has enumerated, and it looked like it retired `(Z3)`'s token deny-list entirely.

**It does not.** `'today'::date` inside a plpgsql body is const-folded into the cached plan,
so both probes return the same date and `(Z4)` is **structurally blind to it** — while `(Z3)`'s
literal arm catches it outright. The defect is real: the plan cache is per-session, so it
drifts across restarts and deploys while looking stable in any single test.

> **A property test and an enumeration fence fail in DIFFERENT directions. Neither subsumes
> the other, so neither may be deleted as redundant** — and the "better" test is exactly the
> one that makes deleting the cruder one feel safe.

Found only because the sabotage was **built and watched** rather than assumed to fire. Asserted
in-file as `(V10c)`, which asserts the blindness, so the limit is a test rather than a caveat.

### Re-derive what an assertion targets after ANY change that adds an early bound

§9 records this for BEFORE-triggers in front of `WITH CHECK` conjuncts. It is more general,
and this round produced a second mechanism with no trigger in sight.

A clamp was added ahead of the day expansion, starting it at the caller's first visible
checkpoint. Consequence: every generated period end now has a checkpoint at-or-before it, so
the inner `CROSS JOIN LATERAL` **can never miss** — its inner-join semantics became
extensionally identical to a LEFT JOIN on all reachable input, and `(B1)`'s stated negative
became false while staying green. `(B2)` kept passing for an entirely different reason than
the one its message gave.

> **Any change that bounds an input EARLIER can silently move a downstream assertion's
> mechanism. Green is not evidence the mechanism survived.**

Remedy is §9's: prove it **declaratively** from `prosrc` (`(B6)`), and give the declarative
leg its own teeth control (`(V13)`), since text assertions have no natural failure mode.

### When a control fails CLOSED, corrupt it — do not delete it

"Remove the control and see if the test notices" is valid falsification **only where removal
fails open.** Postgres RLS fails closed: drop the policy and RLS default-denies, so every
tenant including the owner sees zero rows, and a cross-tenant negative passes **on the
nothing**. An absent fence cannot demonstrate a leak.

Break it OPEN instead (`using (true)`). And keep the deleted-fence world as its own leg,
**labelled as the vacuity it is** — it is the counter-example that stops the obvious method
being re-derived later.

Corollary measured the same round: the two modes are caught by **different halves** of a
battery. Corruption fires the cross-tenant negatives; deletion fires only the positive
"owner sees its own rows" legs. **The pairing is load-bearing** — deleting either half as
redundant reopens one mode as undetectable.

### An agent mid-write owes the tree a coherent state

Shared-worktree concurrency, and the fourth diagnostic question to sit alongside the three in
`062`'s header: **"is the thing I'm measuring even finished being written?"**

Two agents partitioned by path (one owning `migrations/`, one owning `tests/`) cannot clobber
each other — and that safety is precisely what removes any signal that intermediate states are
public. A combined run against a half-written battery returned a hard error, and the natural
reading was that the *other* agent's change had broken it. Both readings were true at once:
the body change was innocent **and** the red was a genuine defect, already fixed in the window
being measured.

> **A red from a mid-edit artifact is indistinguishable from a red you caused.** Commit at
> green — not at "green once the next leg lands."

And the handoff form that makes this cheap: **state the ref AND the expected plan count in the
same message.** A re-measurement that derives its own expected value from its own run cannot
detect a plan-count drift. This is §8 rule 4 — print the pair, and check the pair is
independent — applied to the channel between agents rather than inside a file.

### Calibration table — this round

| rule | +applications | +self-catches |
|---|---|---|
| build X and watch it go red (§10) | 4 | **4** (`G3`, `V8`, `E3`, and `V10`'s non-firing) |
| absence is vacuous when the subject never existed (§10) | 2 | **2** (`V8`, `E3`) |
| anchoring: anchor on the subject, not a co-occurring token | 1 | **1** (the `timestamptz` / `time zone` alias gap) |
| print the pair — and check the pair is independent | 2 | **1** (the handoff ref+count form is the new application) |
| count the predicates, then check each has a fixture | 1 | **1** (`L6`'s raise-site count, which held across a body change) |
| confident prose is anti-correlated with measurement *(new)* | 6 | **5** |
| the better instrument does not subsume the cruder one *(new)* | 1 | **1** |
| re-derive the target after an early bound is added *(new)* | 1 | **1** |
| corrupt a fail-closed control, do not delete it *(new)* | 1 | 0 — arrived as a **correction from the team lead**, not a self-catch |
| an agent mid-write owes the tree a coherent state *(new)* | 1 | **1** |

Note the one zero, and that it is honest: *corrupt-don't-delete* was **not** self-caught — it
came in as a correction and is recorded that way. Per §8's own reading rule it sits at ONE
application, so it is **UNTESTED, not miscalibrated**; leave it and use it.

The load-bearing row is *build X and watch it go red* at 4/4. Every one of those four was an
assertion its author had already written a confident explanation for. **That is the whole
content of this section.**

---

## 14. From the SELF-219 delta round (2026-08-07) — instruments, labels, and who caught what

Five more, and **only one of them is a self-catch.** Three arrived as corrections from the team
lead, one from Sec. Recorded with that provenance intact, because §8's calibration test is
worthless if "I found this" and "someone told me this" blur together.

### A hash over a whole artifact cannot tell a safe edit from an unsafe one *(team lead)*

The instruction was *"comment-only — `prosrc` must not move."* **Those two halves contradict
each other**, and the contradiction was invisible because the condition named a concrete hash
and therefore looked rigorous.

`prosrc` is the text between the `$$` delimiters. **Header comments sit outside it; body
comments do not.** A raw `prosrc` hash had agreed with the intended property across three
prior passes — but only because those happened to be header-only edits. It diverged on the
first pass where a body comment moved, going `b735bdc7…` (6926) → `5cf0cb19…` (7290).

> **If the property you care about is invariance of a SUBSET, hash the subset.** A whole-artifact
> hash is a change-detector, not an invariance-checker, and the two are indistinguishable until
> the first edit that is safe but not byte-identical.

Remedy: strip comment and blank lines from `prosrc`, then hash. Executable text was invariant
across the change, which is what "comment-only" was actually claiming.

**And a refinement found by re-deriving it rather than accepting the reported number:** two
independent strip normalisations produced **two different digests** for the same invariant
executable text — `086a9067…` and `81cb97b4…`. The *invariance* reproduced; the *number* did
not, because it is method-dependent.

> **A normalised hash is only a usable baseline if the normalisation is published beside it.**
> Otherwise the next person derives a different digest from correct code and concludes the
> artifact moved. Same defect as an unlabelled check: the number looks self-describing and isn't.

### A check's label must describe what was RUN, not what it is expected to SHOW *(team lead + QA, jointly)*

Both of us had been printing `(empty = clean)` after `git status --short` in verification
commands — **including a run whose output was `M supabase/migrations/062_fn_nav_series.sql`
followed immediately by the line `(empty = clean)`.** A skimmer reads the label, not the output.

> **A label printed unconditionally is a prediction. `git status --short` printed alone is a
> measurement. The first survives being wrong.**

**The strongest instance is a convention, not a habit:** a commit subject-prefixed `docs(…)`
moved `prosrc` by 364 bytes, because the edit was a comment *inside* the body. The change was
correct and the fences stayed green — but a reviewer who reads `docs(…)` and skips fence
re-verification is trusting a label over a measurement, and in this file the in-body comment is
**exactly where fence-defeating prose has historically landed** (three recorded instances).
Conventional prefixes will keep being emitted correctly-by-convention and wrongly-by-implication.

**The three label defects this round form a set, and they ESCALATE BY SCOPE** — which is what
makes this an entry rather than a list:

| defect | scope | how it ends |
|---|---|---|
| `(empty = clean)` printed after `git status` | **one agent's habit** | dropped when its owner notices |
| *"comment-only ⇒ `prosrc` must not move"* | **one lead's malformed condition** | dropped at the first case that separates its two halves |
| `docs(…)` as a commit-subject prefix | **a project-wide convention** | **never** — it is emitted *correctly* by everyone, indefinitely, while implying something false |

> **Blast radius grows with how many people emit the label CORRECTLY.** A habit has one owner
> who can notice it. A convention has no owner, and every correct use reinforces the false
> implication.

**The actionable half, and the reason to re-verify on every commit touching this file whatever
its subject prefix:** the fences were green through that `docs(…)` commit **because the added
prose happened to avoid every fenced token. That is luck, not design.** The argument is not that
`docs(…)` commits are usually dangerous — they usually are not. It is that the check is cheap
and the label is load-bearing **in the wrong direction**: it points attention away from the one
place this file has repeatedly been bitten.

### "I asked a question that could not return the roles I hadn't thought of, and read its silence as absence" *(Security Reviewer, verbatim, at its own request)*

The purest statement anyone produced of the instrument-cannot-observe-the-property family. Sec
generalised `service_role` to *"the only role with `rolbypassrls`"* from a probe run over a
role list Sec itself had chosen. Measurement found **five**.

> The instrument did not malfunction. **It answered exactly what it was asked, and what it was
> asked was the wrong question.** Silence is the most persuasive wrong answer available, because
> it reads as a clean bill of health rather than as an error.

Diagnostic form: **"could this query have returned the thing I am about to claim is not there?"**

**This applies to `(Z3)` in this project's own battery, and that is the honest entry.** `(Z3)`
is a token deny-list — an enumeration that cannot return the tokens its author did not think
of, whose silence reads as absence. It was written while its author believed the trap had been
escaped, and it is non-vacuous only because `(Z4)` covers a different axis and `(V10c)` proves
the gap between them. **Not a rule that caught us; a rule we applied to someone else's artifact
while an instance of it sat in our own.**

Second thing to carry, and it is the load-bearing half: **authority is not evidence.** Two of
Sec's four round-1 claims were wrong, and that was established by measuring them rather than
deferring to the reviewer who raised them — on a surface where that reviewer holds veto. Had
they been accepted, two false findings would have been remediated into the migration **and the
remedies would have looked like diligence.** A review channel where findings flow only downhill
cannot catch this; it degrades silently while everyone behaves impeccably.

### A wrongly-scoped fence is negative value, not neutral *(team lead)*

"Add the obvious extra assertion" is not free. `(A5)` fences `service_role` from EXECUTE.
Extending it to the other four `rolbypassrls` roles looks obviously right and is wrong:
`postgres`/`supabase_admin` are owner and superuser, so the negative is **unassertable** — it
could never pass, and "fixing" the red means revoking from the owner and breaking migrations.
The other two **already read `nav_daily` cross-tenant with `nav_value` visible**, so fencing
the function against them is a door beside an open wall.

> **The aggravating factor is what makes it worse than absence: a wrongly-scoped fence shows up
> in a coverage review as GREEN.** An assertion that cannot fail, whose presence implies
> protection it does not provide, is the same defect as a vacuous one — arriving from the
> opposite direction.

Same shape as `(E3)`, which asserted "no point carries 0" over a set already proved empty. Both
landed in the same session, one found in our own work and one corrected in someone else's.

### During an in-flight review at a named ref, freeze the WHOLE tree *(team lead)*

The conditional form — *"commits are fine if they don't touch the reviewed surface"* — is
correct and needs its condition evaluated every time. The unconditional form has no evaluation
step to get wrong.

**But the argument that actually settles it is not about verification cost.** A doc-only commit
landed during review; under the conditional rule it would have been unremarkable and unread.
Under the freeze it became a **visible delta someone had to reconcile** — and that reconciliation
is what surfaced that the reviewer was about to re-request work already done one commit above
its review point.

> **The rule earned its keep through the friction that was argued to be unnecessary. A rule whose
> overhead IS its function is a different and better category than a rule with acceptable overhead.**

Concrete cost of the conditional form, invisible from the writer's side: the reviewer reports
*"measured at `<ref>`"* while HEAD reads something later, and someone else pays to reconcile it.

### Calibration table — this round

| rule | +applications | +self-catches | provenance |
|---|---|---|---|
| hash the subset, not the artifact *(new)* | 1 | 0 | **team lead**, self-caught in their own instruction |
| a normalised hash needs its normalisation published *(new)* | 1 | **1** | QA, by re-deriving instead of accepting a reported digit |
| a label must describe the check, not its expected result *(new)* | 2 | **1** | joint — both parties were emitting it |
| could this query have returned what I claim is absent *(new)* | 2 | **1** | **Sec**, verbatim; the `(Z3)` self-application is QA's |
| authority is not evidence *(new)* | 2 | **2** | QA, by measuring a veto-holder's claims |
| a wrongly-scoped fence reads as green *(new)* | 1 | 0 | **team lead** |
| freeze the whole tree during in-flight review *(new)* | 1 | 0 | **team lead** |
| absence is vacuous when the subject never existed (§10) | 1 | **1** | `(E3)`, found by self-audit |
| build X and watch it go red (§10) | 1 | **1** | `(V14)` — `(E3)` could not be made red at all |

**Four zero-self-catch rows, and every one of them arrived as a correction from someone else.**
Per §8's reading rule they sit at ONE application each: **UNTESTED, not miscalibrated** — leave
them and use them. But note what the column is really showing: *this round, the corrections
mostly ran toward us rather than from us.* That is the expected shape when the work is being
reviewed properly, and it is only visible because the provenance column exists. A table that
recorded these as plain applications would show a flattering nine-for-nine.

### Overreach from proximity — *"I had it right one line up"* is the mechanism, not the mitigation

The last correction of the round, and it is a distinct failure from not knowing.

`(E3)`'s message stated the accurate diagnosis: *"it could not fail unless `(E2)` failed
first."* The neighbouring leg `(V14)`, **in the same commit**, generalised past it into
something false: *"could not be made to fail by ANY implementation."* Sec measured the
difference — a body fabricating a 0-valued point reds the old anchor — and the true form is
**subsumption**, which settles by construction: `(E2)` asserts `count = 0`, and where there are
no rows there is no row for a zero to sit in, so the old leg was green **whenever** `(E2)` was
green. Never fired alone; added no independent detection.

> **A correct formulation sitting one line away makes the incorrect generalisation feel DERIVED
> rather than INVENTED — so it skips the scrutiny a fresh claim would have received.**

That is why "I had it right next to it" is not mitigation. Proximity to a true statement is the
*delivery mechanism* for the false one: the reasoning feels like a restatement, and restatements
do not get checked.

**And the severity is in the portability, not the wrongness.** Three other candidate
overstatements were identified in the same message and none was the one that mattered; each
would have cost a single correction. The clause Sec flagged encodes a **rule a reader carries to
other legs** — *"an absence assertion over an empty subject can never be red"* — which is wrong
and would mis-classify assertions elsewhere in the file.

> **A wrong claim about THIS assertion costs one message. A wrong claim about ASSERTIONS IN
> GENERAL costs every future one.** When triaging narration defects, rank by how far the claim
> travels, not by how wrong it is locally.

Corollary on relaying, learned the same turn: the team lead's summary — *"`(V14)`'s overstated
clause"* — was itself the drift source, and led to three wrong guesses at which sentence was
meant. **Relay a reviewer's finding verbatim; a compression of a finding is a new claim.**

| rule | +applications | +self-catches | provenance |
|---|---|---|---|
| overreach from proximity *(new)* | 1 | 0 | **Sec**, measured; QA reproduced before accepting |
| rank narration defects by portability *(new)* | 1 | 0 | **Sec** |
| relay a finding verbatim, never compressed | 1 | 0 | **team lead**, self-caught in their own summary |
| a redundant layer that cannot fail alone is mistaken for coverage | 1 | **1** | QA, applying Sec's stripper finding to `(N2)` |

### A reviewer's model of a surface's scars is the cheapest catch available *(Security Reviewer)*

Logged as its **own** entry rather than folded into *overreach from proximity*, deliberately: a
rule whose only catches are its author's neighbours reads as self-validating, and §8's
calibration test exists to expose exactly that. Keeping them separate is what makes the table
worth having.

**What happened.** While `(N2)` was being demoted to corroborating-only, Sec pre-flagged that the
natural way to write that demotion — restating `(N1)`'s strength — was where a **blocking**
round-1 condition had already come from once. It named three specifics: the **mechanism**
(demote-then-restate), the **surface** (`(N1)`'s reach), and the **precedent** (near-miss (8),
the sound-quote defect). All three correct. The sentence had in fact already shipped, reading
*"(N1) … is therefore STRICTLY STRONGER"* — unqualified, and false as a general claim, since both
`(N)` legs grep the prosrc of **one** function and structurally cannot observe a transitive call.

**The author's process could not have caught it.** The line was written, the suite run 68/68,
commit isolation verified, and committed. **Nothing in that sequence examines a scope qualifier on
a true sentence.** That is not a lapse — it is the boundary between what an author can check and
what only a second reader can, and it is why the correct fix restates the boundary affirmatively
rather than merely omitting the overstatement: *a future editor tightening the prose cannot delete
a qualifier whose reason is visible.*

> **Same principle as pointing at the instrument instead of restating the assertion: make the
> reason visible, so the shortcut is unavailable.**

**Related disclosure, and the ordering matters.** Two defects in `(N2)`'s own stripper were
self-disclosed and then independently verified rather than accepted — a string literal containing
`--` makes the token **vanish** (a genuine false-pass for `(N2)` alone), a block comment makes it
**survive**. Both real; neither can bite, because `(N1)` reads raw `prosrc` and fires first.
**Finding your own fence's flaw and then proving it cannot bite is the right order** — the reverse
(proving safety first, disclosing the flaw after) is how a known defect becomes a footnote.

Sec also recorded — explicitly *not* as a request — that `(N2)` is now subsumed by `(N1)` in the
same structural sense old-`(E3)` was subsumed by `(E2)`, and that a future reviewer may reasonably
re-open whether it should exist. That question is already answered **in the leg, with an exit
condition attached**. Its reason for logging rather than asking generalises: *"manufacturing work
at a merge gate over a fully-disclosed choice would be the wrong use of this seat."*

| rule | +applications | +self-catches | provenance |
|---|---|---|---|
| a reviewer's scar-model is the cheapest catch *(new)* | 1 | 0 | **Sec** — predicted the defect in a commit it had not seen |
| restate a boundary affirmatively, don't merely omit the overstatement *(new)* | 1 | 0 | **Sec**'s flag; wording is QA's |
| disclose a fence's flaw BEFORE proving it cannot bite *(new)* | 1 | **1** | QA, applying Sec's stripper finding to `(N2)` |
| a headline over your own data is a relay *(new)* | 2 | **1** | QA on §13's opener; the lead self-caught the second compression |

---

## 15. From the RT-31 leg (i) round (2026-08-09) — isolating the disjunct under test

Leg (i) of RT-31 (the bypass-capable role-set fence, `054_nav_daily_rls.sql`) is a fence over
`pg_authid`, authored to Sec's mandated set-complement shape. Three things came out of building
it that generalise past this leg.

### A differential whose witness satisfies BOTH branches proves nothing about either

The fence's predicate is a disjunction: `rolbypassrls OR pg_has_role(…,'pg_read_all_data',…)`.
A plausible "simplification" replaces the second disjunct with a `pg_auth_members` join, and the
question is whether that changes anything. The first attempt to answer it ran both variants
against `supabase_admin` and got **the same answer from both** — so the simplification looked
safe, and the differential looked like confirmation.

It was worthless. `supabase_admin` carries `rolbypassrls = t`, so **the first disjunct caught it
under both variants** and the second was never load-bearing in either run. The witness could not
discriminate, and a non-discriminating witness returns a clean-looking result no matter which
way the truth falls.

The correct witness had to satisfy **exactly one** disjunct — a *bare* superuser
(`rolsuper = t`, `rolbypassrls = f`, not a member of `pg_read_all_data`, `pg_has_role` true
anyway). Against that witness the mandated shape **catches** and the membership-join variant is
**blind**, and the role can read `nav_value`. Same two queries, same tree, opposite conclusion —
the only thing that changed was the witness.

> **When you are testing which of N branches is load-bearing, the witness must isolate the
> branch under test.** A witness that satisfies several makes the run uninformative *whatever it
> returns* — and it fails in the reassuring direction, because agreement between the variants
> reads as evidence they are equivalent. This is the disjunctive form of the vacuity problem
> already catalogued at §14: there the query could not return the answer, here the *witness*
> cannot distinguish the answers.

Related but distinct from *"a fence that cannot fail reads as GREEN"*: that one is about the
instrument, this one is about the specimen. Both produce a green you cannot bank.

### The same failure on the mutant side — test the edit you fear, not a stronger one *(Security Reviewer, self-reported)*

The witness problem above has a twin, and Sec found it in **its own review instrument** rather than
in the artifact under review. Its mutation test of leg (i) **deleted** the `pg_has_role` disjunct
and observed the probe leg go RED, which it read as coverage. But the edit actually being guarded
does not delete that disjunct — it **substitutes** a `pg_auth_members` join for it.

The two are not the same strength, and the gap runs the wrong way:

| mutant | `(i2)` BYPASSRLS probe | `(i3)` `pg_read_all_data` probe |
|---|---|---|
| disjunct **deleted** (what was tested) | green | **RED** — looks like coverage |
| disjunct **substituted** (what is feared) | green | **green** — the probe is a *real member*, so the join catches it too |

Deletion is visible to a probe that holds real membership; substitution is visible only to a
**non-member superuser**, which this battery cannot mint. So the mutation test established that
the disjunct is load-bearing, and said nothing about whether the *specific replacement* is weaker
— which was the actual question.

> **A mutant that is easier to catch than the edit you fear produces a green you cannot bank.**
> Mutation testing answers *"is this clause doing work?"*. It does not answer *"is the change
> someone will actually make weaker than this clause?"* unless the mutant **is** that change.
> Derive mutants from the edits you are trying to prevent, not from the syntax that is easiest to
> break.

Same shape as the witness problem, arriving through the **instrument** instead of the specimen —
and it produced a confident RED rather than a confident green, which is why it survived: a fence
going red on cue is the last place anyone looks for a measurement error.

### Some consequences are not assertable in-battery — pin the premise, ship the method

The bare-superuser measurement cannot become an assertion in this battery: `postgres` is **not**
a superuser on this stack (`rolsuper = f`), and only a superuser may create one. So `(i6)`
asserts the *premise* it can reach (`supabase_admin` is a superuser, is not a member, and
`pg_has_role` says true anyway) and carries the out-of-band method for the consequence
**verbatim, as a runnable command**, not as a summary of a result.

An earlier draft of `(i6)` asserted the consequence in its message as though the assertion
covered it. Every fact in that message was true; the *scope* was not, and a reader would have
credited the assertion with coverage it does not have.

**Stated here for the first time, not cited** — a draft of this paragraph attributed it to §13
as *"§13's standing rule about findings that ship without their method"*, in bold, which reads
as a quotation. §13 contains no such rule; it was coined here and dressed as a citation. Sec
caught it at the PR #343 review, and the way it got in is worth more than the rule: the idea
*came from* a prior session's finding about veto-holders asserting things with no re-runnable
method, so it felt remembered rather than invented, and a half-remembered provenance reaches
for the nearest plausible anchor. **A citation is a claim about a location, and it is checkable
in one grep** — which is exactly what the surrounding section is about, missed on its own page:

> Where a method cannot live in the battery, it lives adjacent to it, executable — a finding
> whose method cannot be re-run is the expensive kind.

### The corollary Sec measured, which the leg had backwards

`(i6)` pins the premise so the fence's mechanism is re-measured where an editor would stand.
It does **not** stop the edit, and an earlier draft said it did. Measured 2026-08-09: applying
the membership-join swap passes **the entire battery — all 74 assertions, `(i6)` included**.
`(i6)` reads `pg_authid` directly and never calls the fence, so no edit to the fence can red it;
and the `pg_read_all_data` probe is a *real member*, so the membership join catches it too. Only
a non-member superuser separates the variants, and the battery cannot mint one.

> **An assertion sited next to a hazard is not thereby a fence against it.** Proximity to the
> edit is a real benefit — the premise is re-measured where the edit gets made — but it is a
> different property from *failing when the edit lands*, and the two are easy to conflate
> precisely because the assertion is in the right place. Ask which one you have, and answer it
> by applying the edit and running the suite.

### Check the exclusion, not just the inclusion

The fence excludes `rolname like 'pg\_%'` on the grounds that those are PostgreSQL's predefined
roles. That is only sound if the prefix is *reserved* — otherwise the exclusion is a hiding
place, and the fence would be blind to anything named `pg_…` by an attacker or by accident.
Measured rather than assumed: PostgreSQL refuses such a name with **SQLSTATE `42939`**
(`reserved_name`), and `(i5)` now asserts it, so the day that stops being true the fence's own
battery says so.

Worth stating because the reflex on reviewing a fence is to ask *does the WHERE clause catch
everything it should* — the exclusion list is part of the predicate too, and nothing about a
green run examines it.
