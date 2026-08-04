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
