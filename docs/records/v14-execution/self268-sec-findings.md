# SELF-268 — Security joint-review findings (§2.5.4 NAV composition flip)

Joint-review-mandatory: the definition of NAV changes on two live surfaces. One-way door, ruled at
sitting-log **R3 (A′)**.

---

## Pre-ruling re-read of R3 at `524d273`

**Verdict: PROCEED, with 19 pre-conditions (P-1 … P-19). No veto.** *(P-1 … P-15 at the original
pass; P-16 … P-19 added in §2a below after the E41 / E42 dispositions.)* No tenant-isolation defect, no
privilege-boundary defect, no `SECURITY DEFINER` addition, no §10 ledger movement, no
[ADR-011](../../../DECISIONS.md#adr-011) Decision 3 obligation. **Five drifts found (D-1 … D-5)** —
three in the verbatim-vs-paraphrase axis, two premise drifts — all in the AC block rather than in
the ruling itself.

**Read at** `origin/main` **`524d273`** (`git rev-parse origin/main`), worktree
`feature/self-268-sec` at the same sha. This section discharges the drift-check condition recorded
at the foot of `docs/records/v14-preflight/sitting-log.md`: *"Sec re-reads at the SELF-268
pre-ruling."*

---

### 0. Verify-hook — read verbatim before verdict

Read verbatim from `DECISIONS.md` at `524d273`, each located by bracketing `## ADR-` heading, never
by line number:

- **ADR-011 Decision 2** — immutable + INSERT-new-version discipline for audit-class surfaces.
- **ADR-011 Decision 3** — the cross-tenant FK-bypass family, read live including the #18/`101`
  allocation and the DROP resolution. No tally carried into this document.
- **ADR-011 Decision 4** — body, the numbered *Catalogued §10 instances at V1* list, the
  Privileged-context-surfaces bullet, the three-layer composition definitions, the full attribution
  CHANGELOG, and the 2026-09-03 `session_replication_role` amendment.
- **Lock 11** = Decision 15 (`monthly_report` snapshot store, Option B — minimal + read-time
  composition). **Lock 15** = Decision 19 (as-of semantics, Option A — app-layer parameter
  threading) plus its Lock 9 amendment.
- **ADR-067 Decision 5** (the `104` payload contract and its Consequences) and
  `docs/records/v14-execution/log.md` **E26** / **E36**.

Also read verbatim: sitting-log **R3** with riders 0, 0b, 0c, 1–7, its Consequences block, **R9**,
**R12**, and the post-sitting Sec brief-drift-catch table; my own
`docs/records/v14-preflight/sec-findings.md` **M-2**, **M-3**, **M-11**.

**Sec-Lock cross-check.** Every Lock and ADR citation below was read at its source before being
forwarded. One note from doing so, raised as a note and not a finding: the repo-wide shorthand
*"Lock 11 read-composition"* used in `051` / `102` / `104` glosses two things — Lock 11's *read-time
composition* (Decision 15) and the SECURITY INVOKER default, which is stated at Lock 15 /
Decision 19 (*"SECURITY INVOKER composition helper signature extends with `p_data_as_of DATE`"*).
The shorthand is consistent across the tree and I am **not** asking anyone to change it; recorded
so a future reader who checks Decision 15 for the word INVOKER and does not find it does not
conclude the migrations are miscited.

**§10 three-axis cross-check over R3's text and the AC block.**

- **Instance-numbering — CLEAN.** Neither R3 nor the AC block makes a §10 catalogued-instance
  claim. `102`'s and `104`'s `comment on function` both state *"§10 catalogued ledger UNCHANGED BY
  THIS OBJECT"* with no count, which is the correct form.
- **Layer-attribution — CLEAN.** Neither makes a layer claim.
- **Verbatim-vs-paraphrase — TWO DRIFTS**, carried at P-9 and P-14 below, plus a third
  (dropped-clause) at P-3. None is a §10 attribution.

**Read live for the record, not carried from any brief.** ADR-011 Decision 4's catalogued list
reads **RT-22 first / RT-26 second / RT-27 third**. The CI-fenced set, measured this turn —
`grep -rhoE 'RT-[0-9]{2}' .github/workflows/ | sort -u` — is **RT-05 RT-22 RT-26 RT-27**. These
are **different sets**; the fenced set adds RT-05. They coincide on three labels and **must not be
reconciled**: two coincidentally-overlapping descriptions are indistinguishable from one set, and
ledger changes and fence-boundary changes carry different triggers.

---

### 1. What is already on the tree — E3 verified

**E3 verified.** `102_tax_jurisdiction_ytd_paid.sql:465` re-issues `pfin.fn_nav_composition` with
the designated-ledger exclusion **already landed in the leaf set**: a `left join
pfin.fn_tax_authority_ledgers() tal … where tal.account_id is null` anti-join inside the `leaf`
CTE. The predicate is not restated in the body — `fn_tax_authority_ledgers()` is its single home
(`102:324`), per R3 rider 1 / ADR-063 Decision item 2. `fn_compute_nav` is untouched and pinned
byte-unchanged by the battery's L10 leg.

**The identity break is also already landed and already documented.** `102:567`'s replacement
`comment on function` states *"THE IDENTITY WITH `fn_compute_nav` IS DELIBERATELY BROKEN AND MUST
NOT BE 'RESTORED'"* and names the divergence as exactly the designated ledgers' balances. This
matters for P-8: **AC 9b's stated defect is discharged**, and the residual is a different set of
sentences.

**What `105` actually owns, measured.** `102`'s body still carries **four** `0::numeric` literals —
two in `buildups` (`realized_tax_liab`, `unrealized_tax_liab`, each tagged `-- Option A V1.1
(AC#5); V1.4 ramp`) and two inside the `nav` expression: `'nav', (s.total_non_re + s.real_estate) -
(-s.liability_signed) - 0::numeric - 0::numeric`.

**The app layers, measured.**

- `api/src/lib/server/queries/netWorth.ts:160` — `.rpc('fn_compute_nav', { p_as_of: asOf,
  p_active_only: true })`. One hit; this is the §2.1.1 headline's read source and the site rider 0
  moves.
- `api/src/lib/nav-composition.ts:118` — `{ key: 'debt', … displayValue: -b.debt, … }`. Lines
  `:119` / `:120` carry the two tax rows **unnegated**, both `isTaxPlaceholder: true`.
- `api/src/lib/components/NavCompositionTable.svelte:176` —
  `{row.isTaxPlaceholder ? usd.format(0) : usd.format(row.displayValue)}`. This **discards**
  `displayValue`. Leg 3, the silent layer.
- `supabase/migrations/054_nav_daily.sql:406` — `nav_value numeric not null`; append-only
  audit-class, UPDATE/DELETE blocked at the trigger layer across `authenticated` **and**
  `service_role`; **no definition-version column**. R3's back-fill VETO stands unchanged.

---

### 2. Pre-conditions for the build (P-1 … P-15)

*(P-16 … P-19 follow in §2a.)*

Ordered by what fails worst if missed, not by AC order.

**P-1 — `nav_daily` is not written, not amended, not versioned. (Veto trigger.)**
`fn_compute_nav` keeps its gross definition and keeps writing `nav_daily`; the checkpointed series
stays gross pre-tax **permanently**. Any statement in `105` or its battery that UPDATEs, DELETEs or
re-INSERTs a `pfin.nav_daily` row, or that adds a definition-version column, is a veto — `054` is
audit-class under ADR-011 Decision 2, the tax state for a past date is not recoverable, and a
back-fill would be a fabrication with the shape of a measurement. R3 records this as Sec VETO
reached independently by Architect, Sec and PM; nothing on the tree has changed it.

**P-2 — the five landed identity legs are disposed of EXPLICITLY, not left green.**
Five legs across three batteries assert `fn_nav_composition(as_of)->>'nav' == fn_compute_nav(as_of,
…)`:

| Battery | Leg |
|---|---|
| `supabase/tests/rls/051_fn_nav_composition_rls.sql:312` | (F1) `nav == fn_compute_nav(…, TRUE)` exactly |
| `supabase/tests/rls/051_fn_nav_composition_rls.sql:329` | (F2) `nav == fn_compute_nav(…, FALSE)` as well |
| `supabase/tests/rls/102_tax_jurisdiction_ytd_paid.sql:230` | (L3c) STATE 1 equality |
| `supabase/tests/rls/102_tax_jurisdiction_ytd_paid.sql:269` | (L3i) STATE 3 equality restored |
| `supabase/tests/rls/self227_investment_mv_verification.sql:214` | (12) three-surface agreement |

Under option (A) all five stay **GREEN** after `105` lands — not because the invariant holds, but
because their fixtures seed no bracket schedule, so both `nav_components` scalars come back
`unavailable` and `051` subtracts 0. That is green **by fixture accident** on a control the ruling
deliberately broke: the "leg that cannot fail" class. Each of the five is either re-aimed at the
new invariant — `nav == fn_compute_nav − designated ledgers − realized − unrealized`, with the
availability state of **both** scalars stated in the fixture — or retired with the retirement
recorded in `105`'s header. A leg left green by an absence is not a passing control.

**P-3 — sign convention, and M-3's two paired requirements which AC 7 drops.**
`debt` is today the ladder's only sign flip. Removing `isTaxPlaceholder` alone makes both tax rows
render as **positive** numbers while `051`'s `nav` **subtracts** them: the ladder stops footing
visually while every number is correct. Both rows take `displayValue: -b.realized_tax_liab` /
`-b.unrealized_tax_liab`, giving exactly three flips against three subtractions.

⚠ **Drift (verbatim-vs-paraphrase).** AC 7 cites M-3 and drops both of M-3's operative
requirements. M-3 verbatim: *"The V1.4 migration header must state, in one sentence, which value is
signed which way at the boundary"* and *"the battery must carry a **boundary pair** — an overpaid
tenant and an underpaid tenant, one step apart, all else identical."* Both are conditions on this
build. The boundary pair is the leg that catches the double-negation route: an overpaid tenant
yields a negative Realized (per `104`'s `funds_due` which is deliberately **not** clamped), and if
any layer sign-flips for display and the §2.5.4 feed reads the display-shaped value, the
overpayment is counted twice with the wrong sign.

**P-4 — the availability block is not optional under (A), and the NAV FIGURE carries a state
marker, not only the two rows.**
Under (A), `051` subtracts 0 for an `unavailable` scalar, so the `nav` number is **byte-identical**
to a NAV whose tax lines are genuinely $0. M-11 verbatim: *"A `0` result and an `absent` result
must arrive as **distinguishable shapes** at the reader."* The `nav` scalar cannot carry that
shape — a number is a number. Distinguishability therefore has to live in **both**:

- **(a)** each ladder row rendering its `{status, reason}` as a reason, **not** `$0` and **not**
  `—`; and
- **(b)** a state marker on the **NAV foot** and on the **§2.1.1 headline** themselves.

Without **(b)** the surface presents a **gross** figure under the tax-adjusted NAV's label — M-11's
violation moved one layer up, and invisible. This is the **bootstrap default**, not an edge case:
no ledger is designated at signup and no bracket schedule is seeded per user, so it is the state
every user is in on day one.

**P-5 — three availability states, not two. The two scalars are enveloped INDEPENDENTLY.**
Measured at `104:846–864`: `realized` gates on `exists (… not jj.computed)` then `exists (…
jj.ytd_paid is null)`; `unrealized` gates on `r.fed_ltcg_top is null or r.ca_top is null`.
**Different predicates over different inputs — they can disagree.** So the surface has three
states: fully tax-adjusted / **partially** adjusted (one scalar computed, one not) / unadjusted.
Copy reading *"pre-tax"* in the partial state is **false** — the figure is net of one tax line. The
label must be derived from the pair, never from an `any-unavailable` boolean. A build that treats
availability as one flag will ship a true label for two states and a false one for the third, and
the false one is the silent one.

**P-6 — one reader, ONE call.**
Rider 0: *"the headline and the foot read ONE composed value from ONE reader … no surface composes
its own."* The mechanically strongest realization is one `fn_nav_composition` RPC per request, with
both `data.netWorth` and the foot projected from that single payload. Two RPCs at the same `asOf`
are two statements in two snapshots, and *"agree by construction"* degrades to *"agree in
practice."* `netWorth.ts:160`'s `fn_compute_nav` call leaves the §2.1.1 path.

**P-7 — same-as-of threading, and AC 4b's literal wording is not satisfiable as written.**
⚠ AC 4b / rider 4 say *"the one `fn_server_today()` value threaded through the request."* That is
not how this request works. `api/src/routes/+page.server.ts:38` mints `serverTodayAsOf()`, which
derives from the **Node process clock in UTC** — `api/src/lib/server/time/asOf.ts`'s own header
says *"TWO CLOCKS IN TWO PROCESSES. They agree today only because the DB TimeZone is pinned to UTC
… and the app's producer is UTC by construction."* `grep -rn "fn_server_today" api/src` returns
comment references and `schemas/asOf.ts` only; **no §2.1 loader calls it.**

The property that matters is **sameness**, and the shape that gives it by construction is: `051`
passes its **own** `p_as_of` into `fn_compute_tax_liability(p_as_of)` inside the SQL body — zero
app-level threading, one date, one snapshot. Requirement: no second app-level date is minted for
the tax call, and neither `current_date` nor `fn_server_today()` is re-derived at the call site.

I do **not** require the §2.1 path to switch to `fn_server_today()` in this issue — that is a
broader question and M-4's UTC year-boundary flag remains unowned per R8. But **AC 4b's wording
should be amended to name the property**, because a builder satisfying it literally will add an
`fn_server_today()` RPC beside the existing `serverTodayAsOf()` and thereby mint the second clock
the rider exists to prevent.

**P-8 — the comment rewrite: its stated defect is already discharged, and the residual is
different and larger.**
AC 9b's premise — *"The current comment asserts `nav = … = fn_compute_nav(p_as_of, true)`"* — is
**false at `524d273`**. `102:567` already rewrote it and already recorded the deliberate break.
What `105` actually owes:

1. the two inline `-- Option A V1.1 (AC#5); V1.4 ramp` literals in the body;
2. the comment clause *"TAX PLACEHOLDERS … are STILL `0::numeric` literals here … and SELF-268 is
   where `fn_compute_tax_liability`'s values replace them"* — true today, false the moment `105`
   lands;
3. the clause *"until it does, an unmarked ledger has no observer here"*, which AC 10a discharges.

All three are falsified by the same migration that lands the change, and a `comment on` is
corrected only by emitting a new one — the fix window is pre-merge.

**And a fourth site class the AC does not enumerate, in app code:**
`api/src/lib/server/queries/navComposition.ts:110` asserts *"the composition foots to the §2.1.1
headline's `fn_compute_nav(asOf, true)` by construction"* — **already false since `102`**, doubly
false after `105`. Also `api/src/lib/nav-composition.ts:111` (*"Tax rows are flagged placeholders
(value 0, V1.4)"*) and the foot-echo claims at `NavCompositionTable.svelte:24` / `:69` and
`NavCompositionTable.ssr.test.ts:12`. **Require a grep-driven sweep over the tree, not a sweep
over the AC's enumeration** — the AC enumerates the DB sites only.

**P-9 — the exclusion rendered, including the unmarked-ledger observer.**
`102:567` states the gap in its own words: *"it becomes visible on the §2.1.5 surface only where
that surface renders the exclusion (SELF-268 AC 10a), and until it does, an unmarked ledger has no
observer here."* An unmarked tax-authority ledger therefore has **no observer anywhere on the tree
today** — rider 0b's default-state failure, live. The rendering must make "which accounts were
excluded, and that none were" a visible **state**, not an absence.

⚠ **Drift (verbatim-vs-paraphrase).** AC 10a cites **[ADR-049]** for the rendered-not-applied
principle. That attribution is **retracted**: sitting-log R3 rider 6 was corrected to *"non-silent
staleness per PRD §2.4.4 / [ADR-013]"*, per execution-log **E36**, which records *"ADR-049 Decision
5 disowns that attribution in its own text."* `104` and ADR-067 carry the corrected citation; the
AC block was not updated. Correct it before it propagates into `105`'s header — E36 exists because
it propagated once already, faithfully, from a wrong source.

**P-10 — the four-layer single walk covers TWO states, not one.**
Leg 3 is live and silent: `NavCompositionTable.svelte:176` discards `displayValue`. The walk must
assert a **non-zero helper value reaching the rendered cell** (not that `$0` is absent). It must
**also** walk an `unavailable` scalar reaching a rendered **reason** — not a `$0`, not a `—`. A
walk covering only the happy path leaves the bootstrap default, which is the state every new user
is in, undemonstrated on all four layers.

**P-11 — SELF-226's foot-to-headline reconciliation is named as the watcher and DOES NOT EXIST.**
R3 rider 0 and AC 1a both rest on it: *"SELF-226's foot-to-headline reconciliation is the watcher
that goes red if the headline is left behind; it stays in the battery."* Measured: `grep -rn
"composition.nav" api/src` returns **one** hit — `NavCompositionTable.svelte:182`, a render. No
test anywhere compares `data.netWorth` to `composition.nav`. The nearest candidate,
`NavCompositionTable.ssr.test.ts:110` — *"renders the NAV foot whole-dollar (echoes the §2.1.1
headline, D9)"* — renders a **fixture** and asserts the string `$350,000`; it never reads the
headline value. It is a **formatting** assertion and it cannot go red on a re-pointed headline.

**Require the watcher be BUILT in this issue**: a route-level test that drives both surfaces from
one payload and asserts the two rendered figures are the same number, and that goes red if
`netWorth.ts` is re-pointed at `fn_compute_nav`. Until it exists, AC 1a's stated safety net is an
assertion with no watcher, and the one-way door's most consequential rider is unguarded.

**P-12 — the §2.5.4 disclaimer readable without hover (9a).**
Rendered text in the row's left cell, following the precedent the current placeholder caption
already sets at `NavCompositionTable.svelte:170–174` (`<span class="tax-note">` prose inside the
`<th>`, not a `title=` attribute), so it survives PDF export, print and assistive technology. It
must **not** reuse the `(from §2.5) · full estimate arrives in V1.4` string, which AC 3 removes.

**P-13 — the checkpointed chart labelled gross, with BOTH terms of the gap (4a / rider 2).**
Verified the trajectory carries no definitional step: `054` freezes `fn_compute_nav(current_date,
true)`, `fn_compute_nav` is untouched, and `102`'s L10 leg pins it byte-unchanged. The §2.1.2 basis
sentence names the gap as **both tax lines PLUS the designated ledgers' balances** — never *"tax
only"*, which is the pre-rider-0 framing and describes a discrepancy that no longer exists.
§2.1.3 / §2.1.4 carry it **by pointer**, not by a second copy.

**P-14 — posture re-emitted in the replacing migration.**
`create or replace` preserves an existing function's ACL, but a from-scratch `CREATE` takes the
PUBLIC default. `105` re-emits `revoke execute … from public` + `grant execute … to authenticated`
(the `102:564–565` shape) and re-declares `stable` **in the body**, since `create or replace`
**resets** volatility and `079`'s V4 leg pins `provolatile = 's'` on four signatures — it would go
red with no value anywhere changing.

⚠ **Drift (verbatim-vs-paraphrase).** AC 4c's premise — *"`051` and `049` carry no declaration
today and default VOLATILE"* — is **false on the tree**. `079_volatility_pin_stable.sql:136–139`
pins `fn_account_unrealized_gl(date)`, both `fn_compute_nav` signatures and
`fn_nav_composition(date)` `stable` by `ALTER FUNCTION`, and `102:469` re-declares `stable` in the
body. Already corrected at execution-log **E26** (*"Premise correction"*) and at ADR-067's rider-7
line and Decision 5 Consequences; the AC block still carries the falsified premise. **The
instruction stands; the reason does not.** Confirmed as the brief asked.

**P-15 — any post-apply smoke in `105` asserts non-raising, never values.**
A migration-time `DO` block runs as the **owner**, which is RLS-exempt, so a value assertion there
aggregates every tenant. `059:753–768` is the correct shape (call, catch, raise on
`undefined_column`). Value assertions belong in the two-tenant pgTAP battery.

---

### 2a. Addendum — E41 / E42 dispositions folded in (2026-09-04)

**Anchor note, because the base moved under this document.** §0 – §2 above were measured at
`origin/main` **`524d273`**. `origin/main` is now **`7c81dda`** (PR #615, SELF-264 ∥ SELF-266).
Re-measured this turn: `git diff --stat 524d273 origin/main` is **21 files, 4046 insertions, 3
deletions**, and it touches **none** of the sites §1 measures — no `supabase/migrations/*`, no
`supabase/tests/*`, and none of `nav-composition.ts` / `netWorth.ts` / `navComposition.ts` /
`NavCompositionTable.svelte` / the root `+page.server.ts` / `+page.svelte`. The only pre-existing
file it edits is `api/src/routes/+layout.svelte`. **Every measurement in §0 – §2 therefore still
holds at `7c81dda`**, and it is stated here rather than assumed.

**What E41 / E42 settled, recorded so this document is not read against the superseded question.**
Q1 is **not re-opened** — E26 (1) and ADR-067 Decision 5 stand (subtract 0; the row renders
unavailable-with-reason), which closes §6 escalation 1 as raised. Q2 ruled **option (2)**: the two
`buildups` tax keys become `104`'s envelopes **verbatim**, and `nav` subtracts
`coalesce(amount, 0)` **once, in the DB**. AC 3a confirmed already on `main` via `102` — matching
§1's own E3 verification. P-5 taken as option **(C)**. D-1 … D-5 taken. P-11 built inside this
issue; P-2's five legs re-aimed by QA.

**Q2 is the right call, and it extends ADR-067 Decision 5(a)'s enforcement property to `051`** — a
consumer writing `… ?? 0` now meets an object at the §2.1.5 boundary as well as at `104`'s. Four
conditions follow from it.

**P-16 — ONE call to `104` per `051` invocation, into a CTE; `nav` and `buildups` read the same CTE
row.**
If `105` calls `fn_compute_tax_liability(p_as_of)` once for the `buildups` keys and again inside the
`nav` expression, the coalesced figure and the rendered envelopes are **two evaluations** and can
disagree — the foot stops footing, and a suite that stubs `104` cannot observe it. `104` is
`stable`, so the planner *may* fold two identical calls; **"may" is not a control.** Require it by
construction: one CTE, both readers.

**P-17 — the `coalesce` reads a key that does not exist on the unavailable branch. That is correct;
say so in the header.**
Measured at `104:805–813`: an `unavailable` envelope is
`jsonb_build_object('status','unavailable','reason', …)` with **no `amount` key at all**, so
`(env->>'amount')::numeric` is SQL NULL and `coalesce(…, 0)` resolves correctly. Two conditions:

- **(i)** the coalesce is written against `->>'amount'`, **never** against a `status` string test, so
  a future third status is handled by absence rather than by an unbranched `case` — the fail-open
  shape recorded against `greatest(<case with no ELSE>, 0)` elsewhere in `104`'s own history.
- **(ii)** `105`'s header states in one sentence that this `coalesce` is the **only** place a zero is
  minted for an absent scalar, and that it is why P-4's label is load-bearing. Otherwise the next
  reader meets a bare `coalesce(…, 0)` on a money path and either removes it or trusts it.

**P-18 — the envelope change breaks `nav-composition.ts`'s types, and P-3's sign fix must land in
the same edit. Follow the SHIPPED discriminated-union precedent.**
Measured: `api/src/lib/nav-composition.ts:82–84` declares `realized_tax_liab: number` /
`unrealized_tax_liab: number`, and `:119–120` build `displayValue: b.realized_tax_liab`. Once those
keys are objects, P-3's negation `-b.realized_tax_liab` yields **`NaN`**, not a wrong sign — louder,
and better. So **P-3 and P-4 collapse into one edit**: `displayValue` becomes
`status === 'computed' ? -amount : null`, and the row carries `status` + `reason`.

⚠ **Do not invent a second spelling of "envelope".** SELF-264 / SELF-266 landed the convention at
`7c81dda` — `api/src/lib/tax-quarterly.ts:39–46`:

```ts
export type FundsDueEnvelope =
	| { status: 'unavailable'; reason: string }
	| { status: 'computed'; amount: number };
```

A **discriminated union** is materially stronger than the required-`status`-field shape I asked for
in the message that preceded this addendum: it makes `amount` **unreachable without narrowing**, so
`-b.realized_tax_liab` fails to compile rather than producing `NaN` at runtime. `051`'s two keys
take that same shape. `tax-quarterly.ts:112` is also the shipped instance of P-4's discipline —
*"Verbatim `funds_due` envelope … unavailable stays unavailable, never 0."*

**P-19 (Architect's pen) — the ADR-067 Decision 5 amendment must state that `104`'s payload is
UNCHANGED.**
Decision 5 is the canonical home SELF-264 and SELF-266 resolve their citations against, and both are
now merged consumers of it. What Q2 adds is **`051`'s re-emission contract**, not a change to
`104`'s. A reader who concludes their contract moved goes looking for a change that is not there;
the likelier failure is the reverse — a 264/266 reviewer skips the amendment as *"not mine"* and
misses that the envelope shape is now load-bearing in a **second** place. One sentence naming which
payload moved and which did not.

---

**P-11 refinement — the built shape needs a CALL-SHAPE half, not only a value half.**
E42 describes *"a loader-level leg with mocked RPCs holding different values; inversion proven."*
That gives a leg that **can** fail, which was my objection — but **mocked RPCs holding different
values cannot observe what rider 0 is about**: whether the two surfaces read *one* value. If both
RPCs are mocked and the leg asserts the two rendered figures are equal, a future author who re-adds
a `fn_compute_nav` call that **happens to agree in the fixture** passes it.

The discriminating assertion is **call shape**, and the precedent is already in the file —
`api/src/lib/server/queries/netWorth.test.ts:60`:
`expect(rpc).toHaveBeenCalledWith('fn_compute_nav', { p_as_of: AS_OF, p_active_only: true })`.

So the leg needs both halves:

1. `fn_nav_composition` called **exactly once**, and `fn_compute_nav` called **never** on the §2.1.1
   path. **This leg goes red the moment the headline is re-pointed** — which is precisely what rider
   0 names, and it is the half that survives a fixture that coincidentally agrees.
2. Both rendered figures derive from that one payload, with the differing-value mock as the
   **inversion** fixture proving (2) can fail.

⚠ `netWorth.test.ts:60` is itself an assertion this issue must **delete or invert**: it currently
pins the call rider 0 removes, so it will go red, and **that red is correct rather than a
regression.** Recorded here so nobody repairs it by restoring the call.

---

**Note on P-2's disposition — not an objection.** The five legs live in **three** batteries, and two
of them are other issues' shipped controls: `051_fn_nav_composition_rls.sql` (F1 / F2) and
`self227_investment_mv_verification.sql` (leg 12). Re-aiming a leg in `self227` changes a control
SELF-227 shipped. Fine to do — `105`'s header should record **which foreign batteries it re-aimed
and why**, so the next reader of `self227` finds the reason in the tree rather than in a thread.

**Unchanged by this addendum.** P-1 (the `nav_daily` veto trigger), P-6, P-7, P-9, P-10, P-12, P-13,
P-14 and P-15 stand exactly as written above. I do **NOT** require anything further on Q1, on
AC 3a, or on the §10 ledger: the Q2 ruling touches no privileged-context surface, no CI fence, no
FK-shaped column and no catalogued instance, and `7c81dda` moved none of those either.

---

### 3. Pre-ruling on the UNAVAILABLE-scalar case: (A) vs (B)

**Recommendation: (A) — and it is not an open question.**

**Measured first, because it changes what the memo is.** Execution-log **E26** ruling (1) reads:
*"when a `nav_components` scalar is `unavailable` (the BOOTSTRAP default — no ledger designated),
`051` subtracts 0 and §2.1.5 renders the row unavailable-with-reason — a new SELF-268 AC."*
**ADR-067 Decision 5**'s Consequences carries the same, headed *"Ruled at E26 (1)."* And
`104_fn_compute_tax_liability.sql:449–458` — a **merged migration header** — states it as the
ruling and marks it *"not discharged here."*

So the (A)/(B) memo presents as open a question that is **ruled, recorded in `DECISIONS.md`, and
cited in merged migration text**. If (B) is genuinely being re-opened that is an **ADR amendment
and an F/CTO call**, not a design-memo choice decided inside SELF-268. I am escalating it as a
re-opening rather than answering it as a fresh question. My substantive view follows regardless.

**(A) — subtract 0, carry a `tax_components` availability block. RECOMMEND, conditional on P-4 and
P-5.**

- M-11 is satisfiable under (A), but **only** by the block. M-11's own words are *"distinguishable
  shapes at the reader."* (A) puts the zero in the **arithmetic** while the shape lives in the
  **envelope beside it** — a legitimate reading, because the $0 is never presented as a
  determination, **provided the NAV figure itself is also marked** (P-4(b)). Drop the block and (A)
  becomes exactly the M-11 violation, one layer up.
- **Fail-direction, stated plainly rather than buried: (A) fails OPEN on the money.** NAV reads
  **high** by the un-subtracted tax. Same direction as rider 0b's unmarked ledger, same direction
  as the rollover hazard `102:433` documents. I am recommending an option that fails open, and I
  want that on the record.
- What buys it: under P-4/P-5 the failure is **visible by construction**, and (B)'s failure is not
  cheaper.

**(B) — NAV NULL when either scalar is unavailable. DO NOT TAKE.**

- It fails closed on the number, which is the honest attraction. But **the state it fails closed on
  is the bootstrap default.** No ledger is designated at signup and no bracket schedule is seeded
  per user, so every new user — and every existing user until they complete §2.4.2 **and** §2.5.2
  setup — gets a blank §2.1.1 headline. A V1.1-shipped surface goes dark for the modal user on a
  V1.4 feature's default state. That is a capability regression presented as a security posture,
  not a fail-closed edge.
- **It overloads a channel that already carries two meanings.** `netWorth.ts:157–165` degrades a
  **failed read** to `null`, and `+page.svelte:102` plus `page-staleness.test.ts:93` build the
  empty-state disambiguation on `netWorth === 0` vs `accountPresence === 'unknown'`. (B) adds a
  third meaning — *"tax inputs incomplete"* — to `null`, and the three are **not distinguishable at
  the reader**. That is M-11's own objection, turned around against (B).
- The one place (B) is better: it turns the five P-2 identity legs **red** rather than vacuous, and
  a NULL is loud. It does not outweigh the two above.

**(C) — named because I am required to present options, and because it is the version of (A) I
would actually sign.** (A)'s arithmetic, with the **NAV foot's own label** carrying the state
(`Net Assets Value (NAV)` / `— partially tax-adjusted` / `— pre-tax`) alongside the two rows'
reasons. I raise it because if the memo's (A) means *"an availability block beside the table"*
without touching the foot's own label, **that** is the version I flag: a block is a caption a
reader skips; the foot's label is not skippable, and P-5's partial state has no other honest home.

---

### 4. Non-objections, stated explicitly

- I do **NOT** require `fn_compute_nav` to change, be dropped, or gain a tax leg. It keeps its
  gross definition, keeps writing `nav_daily`, and ends up read by no live surface. That end state
  is intended (AC 1a) and is not an oversight for anyone to tidy.
- I do **NOT** require a `nav_definition` discriminator on `nav_daily`, nor any `054` change.
  Option (B) at R3 was not taken and I am not re-opening it.
- I do **NOT** require a new `SECURITY DEFINER` function. `051` and `104` are both INVOKER, both
  `set search_path = ''`, both `revoke execute … from public` + `grant … to authenticated`, and
  neither is an ADR-011 Decision 9 allowlist entry. Nothing here changes that.
- I do **NOT** require an ADR-011 Decision 3 fence. `105` as scoped creates no table, no column, no
  FK-shaped reference and no `INTEGER[]`. Read Decision 3 live; the family is unchanged by this
  issue and this document carries no tally.
- I do **NOT** require any §10 ledger change, and none is available here: `105` touches no
  privileged-context surface and no CI fence. `105` should carry `102`'s and `104`'s form —
  *"§10 catalogued ledger UNCHANGED BY THIS OBJECT"*, **no count**.
- I do **NOT** object to `104`'s `greatest(…, 0)` clamp, and I am not asking for it to change.
  **Note only:** `104:834` reads `coalesce(sum(g.unrealized_gl), 0)::numeric as agg`, so a tenant
  with **no taxable accounts** and a tenant whose taxable aggregate is **exactly zero** both yield
  `{status: 'computed', amount: 0}`. `greatest` **ignores NULLs**, so were that `coalesce` ever
  removed the clamp itself would **mint** the zero rather than propagate the NULL. Today the
  coalesce is upstream and the rate NULLs are gated ahead of it, so the guard is sound — recorded
  because its safety comes from a line above it, not from itself.
- I do **NOT** require SELF-269's battery to be pulled forward, **except** P-2 and P-11: those are
  watchers for *this* change and they are vacuous or absent if deferred.
- I do **NOT** object to R12's ordering, to the E-2 exclusion as landed at `102`, or to `102`'s
  deliberate asymmetry between the R9 zero-clamp and `fn_ytd_paid_per_jurisdiction`'s un-clamped
  figure. Those two must not be reconciled, and `104`'s comment already says so.

---

### 5. Drifts found, consolidated

| # | Axis | Where | What |
|---|---|---|---|
| D-1 | verbatim-vs-paraphrase | AC 10a | Cites `ADR-049` for rendered-not-applied. Attribution **retracted** at execution-log **E36**; R3 rider 6 now reads *PRD §2.4.4 / ADR-013*. `104` and ADR-067 carry the correction; the AC block does not. |
| D-2 | verbatim-vs-paraphrase | AC 4c | Premise *"`051` and `049` carry no declaration today and default VOLATILE"* is **false**: `079:136–139` pins four signatures `stable`; `102:471` re-declares it. Corrected at **E26** and in ADR-067; the AC block still carries it. Instruction stands, reason does not. |
| D-3 | verbatim-vs-paraphrase (dropped clause) | AC 7 | Cites M-3 and drops **both** of its operative requirements — the one-sentence boundary statement in the migration header, and the **boundary-pair** battery fixture (overpaid / underpaid tenant, one step apart). |
| D-4 | premise | AC 9b | Its stated defect (*"the current comment asserts the identity"*) was **discharged at `102`**. The real residual is a different and larger set of sentences, including two in app code the AC does not enumerate. See P-8. |
| D-5 | premise | AC 4b / R3 rider 4 | *"the one `fn_server_today()` value threaded through the request"* does not describe this request: the §2.1 path mints `serverTodayAsOf()` (Node UTC). Satisfying the wording literally mints a **second** clock. See P-7. |

None of D-1 … D-5 changes what R3 ruled. D-4 and D-5 are premise drift that would misdirect the
build; D-3 drops two conditions; D-1 and D-2 are citation and rationale drift that would propagate
into a merged migration header if carried forward.

---

### 6. Escalations

1. **The (A)/(B) memo re-opens a ruled question.** E26 ruling (1) + ADR-067 Decision 5 Consequences
   + `104:449–458`. Route to F/CTO as a re-opening with an ADR amendment, or close the memo on (A)
   as ruled. Not a decision for SELF-268 to take inside its own build.
2. **P-11: R3 rider 0's named watcher does not exist.** A one-way door was ruled with a safety net
   that is a formatting assertion on a fixture. This is the finding I would most want F/CTO to see.
3. **The AC block carries five drifts (D-1 … D-5) and is the artifact the builder reads.** It needs
   a correction pass before dispatch, not after.

---

**Escalation status at 2026-09-04, post-E41 / E42.** Item 1 (the re-opened ruling) is **closed** —
E41 confirms Q1 is not re-opened. Item 2 (P-11's absent watcher) is **being built inside this
issue**, subject to the call-shape refinement in §2a. Item 3 (the AC block's five drifts) is **in
progress** via Linear. P-16 … P-19 are forwarded as **blocking at the freeze** to Architect,
Backend and Frontend.
