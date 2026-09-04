# SELF-269 — Security joint-review: the V1.4 close-gate battery

**V1-SHIP-BLOCK.** Mandatory joint-review per AC 10 and [ADR-066](../../../DECISIONS.md#adr-066)
Decision 1 (c). AC 10: *"Where Sec's §4 catch-criteria and this AC set overlap, Sec's text
governs."*

---

## Review at `e20906b`

**Verdict: AMBER.** No veto. **Four findings (F-1 … F-4)**, all cheap, none touching the battery's
substance — three are defects in what the file *says about itself*, which on a
composition-by-citation gate is where the evidence actually lives. **Four notes.** Both of the
rulings team-lead asked for are given in §3.

**Reviewed at** `origin/feature/self-269` **`e20906b`**, with `feature/self-268` **`0a26bed`**
verified an **ancestor**.

⚠ **RE-ANCHORED to `29f9a83` (2026-09-04), and it costs nothing to re-derive because the trees
are IDENTICAL.** `origin/feature/self-269` moved to **`29f9a83`** when PR #618 (SELF-268) merged
to `main` at **`c8b02d5`**. Measured rather than assumed: `git rev-parse e20906b^{tree}` and
`git rev-parse 29f9a83^{tree}` are **the same object** (`2f9b54ff…`), and
`git diff --name-only e20906b 29f9a83` is **empty**. `origin/main` `c8b02d5` is an ancestor of
`29f9a83`. **Every finding, every cited leg label and every measurement below therefore describes
`29f9a83` byte-for-byte**, with no re-derivation — which is a stronger statement than moving the
sha would have been, and it is why the anchor moves for free.

Delta vs `origin/main` = **one new file**, `supabase/tests/rls/self269_v1_4_close_gate.sql`,
643 lines, blob md5 **`a1e6ff19ed126838d949d835aa4be092`** (measured; matches the dispatch). Nothing
else changed — no migration, no source, no workflow, no ADR.

### 0. Verify-hook — read live at this ref

Read verbatim from `DECISIONS.md` **at `e20906b`** (not from the earlier reads in this session, since
the file moved):

- **ADR-011 Decision 2** — audit-class immutability. Relevant because BLOCK ND **INSERTs into
  `pfin.nav_daily`**; see the non-objection in §5.
- **ADR-011 Decision 3** — *"Canonical family = eighteen labeled instances (#1–#18), fifteen
  DDL-realized"*, unchanged at this ref. This battery authors no schema, so the family is untouched;
  it **exercises** #18 rather than extending it.
- **ADR-011 Decision 4** — *"**§10 catalogued-instance count = 3** — RT-22 first / RT-26 second /
  RT-27 third."* Unchanged.
- **ADR-011 Decision 9** — the SECURITY DEFINER allowlist. Unchanged: the battery creates no
  function, and its single `security definer` string is a **ledger note naming the allowlist**, not
  an assertion (the ASSERTS-vs-NAMES distinction Decision 4's own CHANGELOG records).

**Three-axis cross-check over the battery's own ledger statements — CLEAN.** Instance-numbering: the
file makes one Decision-3 claim, *"canonical #18, grain (C)"*, which matches Decision 3's live entry
for `tax_bracket_row.schedule_id`. Layer-attribution: no layer claim. Verbatim-vs-paraphrase: every
quoted Sec finding (D-5, §3 trap 1, §10.2 item 5) matches my own text.

**Read live, not carried:** CI-fenced set measured this turn
(`grep -rhoE 'RT-[0-9]{2}' .github/workflows/ | sort -u`) = **RT-05 RT-22 RT-26 RT-27**. Catalogued =
RT-22/26/27. **Different sets, not reconciled anywhere in this file.**

---

## 1. Findings

### F-1 (blocking, mechanical) — `AC4C-1` uses `isnt()`, the one verb AC 11 names as fail-open

AC 11 verbatim: *"**`isnt()` PASSES on NULL** (`IS DISTINCT FROM`), so a negative isolation assertion
over a subquery is **fail-open**. Use `ok()`; prove three states."*

`isnt(` appears **exactly once** in the file (measured: `grep -cE "^select isnt\(" ` → 1), at
`(AC4C-1)` — the reconciliation watcher, which is the leg R3 rider 0 depends on:

```
select isnt(
  (pfin.fn_compute_nav(:'d_as_of'::date))::numeric,
  (pfin.fn_nav_composition(:'d_as_of'::date) ->> 'nav')::numeric, …
```

If **either** side is NULL, `IS DISTINCT FROM` is TRUE and the leg **passes**. The NULL that matters
is not hypothetical: `105`'s contract states *"`nav` is NEVER NULL"*, and this leg — on the
V1-SHIP-BLOCK gate — is the one that would have to observe a regression of exactly that promise. It
cannot. **A watcher that passes on the failure of the invariant it watches is the leg-that-cannot-
fail class.**

**And the file's own AC 11 coverage note stops one short of its own code**: it claims
*"`ok()`/not `isnt()` on every NULL-able negative (BLOCK AC7-3, BLOCK AC4D-composed)"* — naming two
places the rule was applied, and not naming the one place it was not.

**Fix (mechanical, no fixture change):**

```sql
select ok(
  (pfin.fn_compute_nav(:'d_as_of'::date))::numeric is not null
  and (pfin.fn_nav_composition(:'d_as_of'::date) ->> 'nav')::numeric is not null
  and (pfin.fn_compute_nav(:'d_as_of'::date))::numeric
      <> (pfin.fn_nav_composition(:'d_as_of'::date) ->> 'nav')::numeric,
  '(AC4C-1) …'
);
```

The three conjuncts are AC 11's *"prove three states"* on this leg: both sides present, and unequal.

### F-2 (blocking, one sentence) — AC 8a's second half is not in the header

AC 8a is a conjunction, and only the first half shipped:

> *"R1 selects the structural branch: assert the STRUCTURAL fact … **and** state in the battery
> header that row-level CG isolation is **deferred to the sale-writer milestone**."*

The structural half is composed correctly (`104` L3a/L3b + L16g). The header half is **absent** —
measured: `grep -i "sale.writer\|row-level CG"` over the file returns **zero** hits. The AC 8a entry
names the vacuity (*"is VACUOUS, marked as such"*) but never says what remains unproven or when it
becomes provable.

**Why this is a finding and not pedantry.** The coverage map is what a future reader consults, and it
currently reads `AC8a — … COMPOSED … No new SQL`, which is indistinguishable from *covered*. AC 8a
exists precisely to stop *"a green leg that reads as isolation evidence"*; without the deferral
sentence the same misreading is available one level up, in the map instead of in a leg. On a
close-gate this is the artifact that will be cited as proof the milestone was verified.

**Commit-ready text, for the AC8a header entry:**

> ⚠ **ROW-LEVEL CG ISOLATION IS NOT PROVEN BY THIS GATE AND IS DEFERRED TO THE SALE-WRITER
> MILESTONE.** No `pfin.lot_match` row can exist in V1 (no sale writer, no `lot_match` writer), so
> any *"tenant A cannot see tenant B's realized gains"* leg would pass on both tenants having none.
> What is asserted here is the **structural** fact only — the CG surface reads `unavailable` for
> both tenants on a capability, never on a row count. The first milestone that lands a sale writer
> owes the row-level isolation legs this gate cannot write.

### F-3 (flag, message-only) — `AC9-2` says *"the 8 swept"* over a **seven**-name list that `AC9-1` pins at 7

`AC9-1` asserts the swept `proname IN`-list resolves to **exactly 7** functions, and enumerates seven
names. `AC9-2` runs `bool_and(...)` over the **same seven names** and its message reads *"NONE of the
8 swept V1.4 functions grant EXECUTE to `service_role`."* The predicate is correct; the record of
what it swept is not. A reader reconciling the two either hunts for an eighth function that does not
exist or concludes one was dropped from the fence — and this is the **forward fence**, the leg that
carries my SELF-262 N-3 standing condition.

**Fix:** `8` → `7` in the `(AC9-2)` message.

### F-4 (flag) — `AC4d` cites `102` **`L3a`**, which does not exist

Measured by sweeping every cited leg label against the file it is cited from. `102`'s battery carries
`L3b … L3j` and **no `L3a`**.

**The pointer is wrong; the content is covered** — which is the distinction ADR-011 Decision 4's own
CHANGELOG records as two independently-falsifiable halves of a citation. AC 4d's two halves both have
homes: *(ii) present in the §2.1.5 buildup* is `(L3b)` *"STATE 1: a_walk (undesignated) is PRESENT in
fn_nav_composition"*; *(i) absent from YTD Paid* is `(L3h)` *"STATE 3 (reverted to NULL): YTD Paid is
NULL again"* — the same undesignated state, reached by reversion.

**Why it still matters here more than it would elsewhere:** on a battery whose method is *composition
by citation*, **the citation IS the evidence**. A dangling pointer in the coverage map is the
close-gate's equivalent of a missing leg, and it is the one defect this method is uniquely exposed
to. **Fix:** `102 L3a/L3b` → `102 L3b` (buildup half) `+ L3h` (YTD-Paid half), naming which half each
carries.

**⚠ Every other cited label resolves.** I swept `100` (ISO-PRE/ISO1/ISO5), `101` (W1/W4/W6/D1/X1/
AAL-X/CHK1/CHK3/CHK5/CHK6/CHK7/SF-Z1/SF-Z4/RA11a/RA11d), `102` (L1b/L1c/L2a/L2b/L3b/L3j), `104`
(L3a/L3b/L11/L12/L16a/L16g/L16h/L1a/L1b) and `105` (X1/X2/BOOT1/BOOT2/PI1/PI4/R9-pin/R9/DES-pin/DES/
NAV1/NAV2). `L3a` is the only miss, plus the prefix case in N-1.

---

## 2. Notes

**N-1 — `AAL-S` is a family PREFIX cited beside an exact leg, and the row-table family is not cited
at all.** `101` has no `(AAL-S)` leg; it has eight — `AAL-S-{SEL,INS,UPD,DEL}{1,2}` — plus a real
`(AAL-X)`. Citing the family by prefix is legitimate and it resolves, so this is **not** a dangling
pointer; the mixed form (`AAL-S/AAL-X` = prefix / exact leg) is just mildly confusing. The more
substantive half: `101` also carries `AAL-R-*`, the aal2 family on **`tax_bracket_row`** — the very
table this gate pins for #18 — and the coverage map cites only the schedule family. Worth adding for
completeness; nothing is unproven.

**N-2 — `BLOCK CONTROL0` detects the hazard it names, but cannot distinguish working RLS from
deny-all.** Traced the helper: `expect_cross_tenant_read_empty` → `_visible_owner_rows` →
`set_tenant(intruder)`, which sets `role=authenticated` plus the JWT claims transaction-locally. Under
the AC-11 hazard (a silent `set_config` no-op) the session stays `postgres`, the owner is RLS-exempt,
the count reads **1** and the leg **fails first in the file**. ✅ Its stated job is done.

What it cannot see: if `101`'s policies were ever accidentally deny-all, the intruder count is also 0
and the leg passes for the wrong reason. In practice non-vacuous today — `101`'s policies gate on
`users_id = auth.uid() AND (… OR aal = 'aal2')` and the fixture users carry no `mfa_policy` row, and
`101`'s own W-legs are green through the same helper — but **nothing in this file pins it**. One
line closes it: `select _rls.expect_owner_reads('pfin.tax_bracket_schedule'::regclass, :'ta'::uuid,
1);` — the helper already exists. Would raise the plan to 21.

**N-3 — `AC4C-3`'s *"both 0"* is asserted in prose only.** The leg is `is(fn_compute_nav, nav)`, which
under pgTAP is `IS NOT DISTINCT FROM` and therefore passes on a **double NULL** as well as on a
double zero. Its message claims *"both 0"*. Since it is the non-vacuity companion for F-1's leg, it
is worth pinning the value: `is((pfin.fn_compute_nav(…))::numeric, 0::numeric, …)` alongside the
agreement assertion.

**N-4 — the `fn_tax_authority_ledgers()` self-reference is real but narrower than it looks, and the
header's stated mitigation does not hold as written.** `AC4C-2` reconstructs the expected difference
using `fn_tax_authority_ledgers()` — the same helper the function under test anti-joins against — so
a regression inside that helper moves both sides together and the leg stays green. The header names
this honestly and points to *"105's DES-pin"* as the independent watcher. **Measured: `105`'s `DES`
and `DES-pin` legs also reconstruct via `fn_tax_authority_ledgers()`**, so they are not independent of
it either, and no leg anywhere reconstructs the designated set from the raw
`account.tax_jurisdiction` column (measured: zero occurrences of that predicate in any test SQL —
the only hit is a header comment in `102`).

**Why this is a note and not a flag:** `102`'s `(L2b)` asserts the helper returns **only `a_idx2`**
for tenant A — an expectation stated as a *named fixture account*, not as a re-run of the predicate.
An inverted or widened predicate changes that answer and reds `L2b`. So the family **is** watched
against the failure modes that matter; the residual is a regression that preserves `a_idx2`'s
membership while changing some other account's, which is narrow. **The header's mitigation sentence
should name `102 L2b` rather than `105 DES-pin`** — that is the leg actually doing the work.

---

## 3. The two rulings asked for

### (1) The single fresh forgery pin — **ACCEPT the composition.** Do not require six more.

The criterion I am applying, so it is reusable rather than a preference: **a close gate owes a fresh
pin where it would otherwise rest on citation alone for a NOVEL isolation SHAPE; composition is
sufficient where the shape is one already pinned exhaustively elsewhere.**

V1.4 ships exactly one novel shape — Decision 3 **#18** under R4 grain (C), a child carrying its
**own** `users_id` beside a cross-tenant-reachable FK, where two tenant facts can disagree. Every
other AC-1 surface is either direct-owner RLS (`tax_bracket_schedule`, `account.tax_jurisdiction`,
`nav_daily`) or a parameterless INVOKER read composing on direct-owner tables. Those shapes are
pinned many times over across `100`–`105`, and six more copies here would add assertions without
adding a discriminator — the *"pins for their own sake"* end of the same axis as a leg that cannot
fail.

**The self257 precedent does not point the other way**, and I checked rather than assumed the
framing: its pins were over surfaces that were novel **at that gate**. The precedent is *"pin the
novel shape"*, not *"pin every surface"*, and this battery applies it correctly.

**The pin itself is well built** and I want that on the record: `(AC1/AC5a-1)` is the ownership-forge
shape (the caller's **own real** `schedule_id` with a forged `users_id`), paired with
`(AC1/AC5a-2)`, a `lives_ok` control differing in **exactly one field**, with a distinct
`bracket_floor` so it cannot pass as a duplicate-key artifact. That is the boundary pair one step
apart, and it is what makes the rejection a *forged-identity* discriminator rather than a blanket
refusal.

**One standing condition attaches to accepting composition**, because it is the method's own failure
mode and F-4 is an instance of it: **the composed citations are load-bearing evidence, so a rename of
any cited leg label in `100`–`105` silently degrades this gate.** Whoever renames a leg in those
files owes a sweep of this file's coverage map. Cheapest durable form is a leg in this battery that
asserts each cited label still resolves — but that is not something I am requiring now; the condition
recorded here is enough for V1.4.

### (2) The AC 8 struck-leg — **reads as the AC requires.** The AC 8a vacuity statement — **does not** (F-2)

**AC 8 — clean.** Measured: `to_regclass` appears **zero** times, so the *"skip silently and report
green"* form the AC forbids is not present. `transaction_annotation` appears **once**, in the SCOPE
CORRECTION note that explains the strike and contrasts it with the real
`pfin.account_trans_annotation` (`023`). That is **naming, not asserting** — the distinction ADR-011
Decision 4's CHANGELOG records — and it is the right way to leave a permanently-struck leg behind, so
nobody re-derives it. No leg was authored. Correct.

**AC 8a — the structural half is right, the header half is missing.** See F-2. The composed legs
(`104` L3a/L3b + L16g) do assert the structural fact, and no green leg here reads as row-level
isolation evidence *at the leg level*. The gap is at the **map** level, and the AC's *"and state in
the battery header…"* is not satisfied.

---

## 4. Carried forward as asked

- **The `jur_def` mechanism note is the right thing for this gate to hold, and it is NOT yet held.**
  `104`'s `realized` envelope reaches `unavailable` for a tenant with no schedules only because
  `jur_def` is a literal two-row `VALUES` list (`104:635–645`); were it ever to range over a
  **stored** set, an empty set would fall through the `case` to `{status:'computed', amount: null}` —
  a confident *computed* with no value, at the top of the money path. `105` depends on this and does
  not provide it. **No leg in this battery pins it.** Not a blocker for V1.4 (the shape is a literal
  today and `105`'s `BOOT2` observes the *consequence* for the zero-tenant), but it is the natural
  home for the pin and I record it here so the booking has a technical statement to point at.
- **`P-2`'s five re-aimed identity legs and `105`'s `(ONE)` call-shaped regex** are load-bearing
  controls with subtle predicates. This battery neither duplicates nor contradicts them — checked:
  it adds no identity leg of its own beyond `AC4C`, which asserts **in**equality with an
  independently reconstructed difference, and it makes no `prosrc` claim about `fn_nav_composition`.

## 5. Non-objections, stated explicitly

- **`BLOCK ND` INSERTs into `pfin.nav_daily`, an ADR-011 Decision 2 audit-class table, and I do NOT
  object.** It is an INSERT only (append-only permits it), it sets `app.nav_computed_for` correctly
  per row so `054`'s BEFORE-INSERT tenant-binding fence evaluates rather than being bypassed, it
  performs no UPDATE or DELETE, and the whole file runs inside `begin … rollback`. This is a fixture,
  not a write surface, and it does not touch P-1's veto territory.
- I do **NOT** object to the plan arithmetic. `plan(20)`; 18 assertions appear at statement start and
  the two `expect_cross_tenant_read_empty` helper calls (CONTROL0, ND) each emit one — 18 + 2 = 20.
  It is stated in the header *"so a silent plan-edit shows as an arithmetic change"*, which is the
  right reason to state it.
- I do **NOT** require any new leg for AC 2, AC 4, AC 4a, AC 4b, AC 5b, AC 6 or AC 8a's structural
  half. The compositions are accurate and the cited legs exist.
- I do **NOT** require the struck AC 6 SERIALIZABLE parenthetical to be tested. It is a false claim;
  a false claim has no positive leg, and recording rather than testing it is correct.
- No §10 ledger change, no Decision 3 extension, no SECURITY DEFINER addition, no CI-fence change, no
  `secrets-manifest` change. This battery authors no schema.

## 6. My own error in this review, named here

**My first citation sweep was broken and produced 47 false `*** MISSING ***` lines** — a shell
function whose command substitution failed under `zsh`, emitting `bad substitution` on every
iteration while still printing the failure branch. Every line of that output was an artifact of the
instrument, not a measurement, and it read as a catastrophic finding: *every* cited leg dangling.

I caught it because the `bad substitution` noise was visible on the same lines. **Had the shell been
quieter I would have forwarded a uniform false positive against five green batteries.** The re-run
with a plain loop returned the two real results in §1 F-4 and §2 N-1. Recorded because a probe whose
failure mode is *"report everything as failing"* is as dangerous as one that reports everything as
passing, and this one had no control leg of its own — the fix was to make the sweep print only
misses, so a broken sweep prints nothing rather than everything.
