# SELF-268 design memo — what the composed NAV does when a tax scalar is UNAVAILABLE

**Architect · 2026-09-04 · `feature/self-268-arch` · baseline `origin/main` @ `524d273` (migrations `001`–`104`).**

Two questions. The first was **already ruled** and is recorded here rather than re-opened. The
second is genuinely open and is where the recommendation lives.

---

## Q1 — subtract 0, or emit `nav` as NULL? · **ALREADY RULED — E26 (1), 2026-09-04**

The brief presents this as open. It is not: **`docs/records/v14-execution/log.md` E26 ruling (1)**
and **[ADR-067](../../../DECISIONS.md#adr-067) Decision 5** ("What SELF-268 still owes") both rule it,
and `104`'s own header block *"WHAT `051` DOES WITH THIS"* states it a third time. The ruling:

> `051` subtracts **0** and §2.1.5 renders the row **unavailable-with-reason**. That is the
> **bootstrap default**, not an edge case — no ledger is designated at signup — so NAV reads
> **high** until the user designates one, the same direction as R3 rider 0b, and the rendered
> reason must be **visible**, not merely present.

That is the brief's option **(A)**. It is built. Option **(B)** — `nav` NULL when either scalar is
unavailable — is the losing side, and the reason it loses is worth keeping: it fails closed on the
*headline*, which is the one figure on the surface a user reads before anything else, for the
**modal** user rather than an edge case. A blank headline at signup is not a safer wrong answer
than a high one; it is a broken product with a correct arithmetic argument behind it. The cost
accepted with (A) is real and is the whole content of rider 0b: **NAV reads high by the tax
lines' worth until a ledger is designated, and nothing but the rendered reason says so.** That
makes the rendering (AC 10a) load-bearing, not decorative.

*No option was invented here. If Q1 is genuinely being re-opened, that is an F/CTO call against a
ratified ADR, not an Architect memo.*

---

## Q2 — HOW does the unavailability travel in `051`'s payload? · **OPEN. Recommendation: (2).**

`104` returns each scalar as an envelope: `{status:'computed', amount:N}` or
`{status:'unavailable', reason:'<machine code>'}`. `051` must subtract a number **and** hand the
surface the status. Two shapes do that.

### Option (1) — numeric keys + a parallel `tax_components` block *(the brief's shape)*

`buildups.realized_tax_liab` / `unrealized_tax_liab` stay **numeric** — the amount actually
subtracted, `0` when unavailable — and a new top-level
`tax_components: {realized: <envelope>, unrealized: <envelope>}` carries `104`'s objects verbatim.

- **Buys:** no type change on two shipped keys. `NavCompositionBuildups`' numeric fields survive;
  the buildup ladder still foots literally off `buildups` alone.
- **Costs:** the amount is represented **twice** in one payload. A consumer reading `buildups`
  alone renders **`$0` as a determination** — the exact M-11 failure — with no error, no failing
  type-check and a green suite. That is the hole `104`'s envelope was built to close, re-opened
  one layer down by omission. And the two keys change **meaning** (placeholder-zero → applied
  amount) while keeping their type, which is inherited **invisibly** — the shape `104` itself
  rejects in writing when it renamed `quarters_elapsed` rather than redefining it: *"a key kept
  under a new meaning is inherited invisibly, a key that disappears is a compile error."*
- **Honest variant, if (1) is taken:** rename the numeric keys `realized_tax_liab_applied` /
  `unrealized_tax_liab_applied`. That repairs the silent-inheritance half. It does not repair the
  double-representation half.

### Option (2) — the envelope IS the key *(RECOMMENDED)*

`buildups.realized_tax_liab` / `unrealized_tax_liab` become the envelope **objects**, carried
verbatim from `104`. `nav` subtracts `coalesce(amount, 0)` — the E26 (1) rule, written **once**,
in the DB.

- **Buys:** one representation of one fact, zero drift surface between them. The type is the
  fence: `usd.format(env)` and `-env` both fail at the first arithmetic instead of rendering a
  plausible `$0`, which is Sec B3's watcher by construction rather than by consumer discipline —
  the same argument [ADR-067](../../../DECISIONS.md#adr-067) Decision 5 already ratified for `104`
  ("two states that must mean one thing belong in the TYPE"). The meaning change arrives as a
  **compile error**, per `104`'s own `quarters_elapsed` precedent.
- **Costs, named:** it is a **breaking contract change** on two shipped keys —
  `NavCompositionBuildups` must change and `buildupRows()` must unwrap `.amount` (both are inside
  AC 2's scope already); every pgTAP leg asserting `buildups->>'realized_tax_liab' = '0'` goes red
  (they go red under AC 1 regardless); and the payload **stops footing literally** off `buildups`
  — `nav = gross_total − debt − realized − unrealized` now needs an unwrap to check.
- **Why that last cost is affordable:** nothing in code re-foots. `NavCompositionTable.svelte`
  renders `nav` directly as the foot; `buildupRows()` renders rows. The self-footing property is a
  DB-side invariant asserted in pgTAP, and pgTAP can unwrap. If a consumer *did* re-foot, it would
  be re-implementing the "unavailable subtracts 0" rule — a second copy of a rule, which is the
  drift class [ADR-063](../../../DECISIONS.md#adr-063) item 2 exists to prevent.

**Recommendation: (2).** It is not a novel shape — it is *this arc's already-ratified* shape,
applied one layer down. Option (1) is the deviation, and it deviates in the direction of the
failure mode the arc has spent two migrations closing.

---

## Sign convention (AC 7 / Sec M-3) — settled, not optional

`104`'s `amount` is carried **verbatim, sign unchanged**. `051`'s `nav` **subtracts** both.

- **Realized is signed and NOT clamped** (`104`, deliberately asymmetric with `102`): an
  overpayment is a genuine receivable → negative `amount` → `nav` **rises** by the excess, which
  is exactly what R3 / E-2 (A) ruled. Do **not** take an absolute value and do **not** clamp it.
- **Unrealized is clamped at ≥ 0 by `104`** (R9 / Sec M-2). `105` re-clamps nothing; the clamp's
  WHY lives in `104`'s `comment on function` and `105` **cites** it rather than restating it.
- **The ladder is the single flip site**, exactly as for `debt`: `051` emits the magnitude, the
  consumer renders it as a subtraction. **Frontend adds no second flip** — three subtractive rows,
  one flip each, at one place.

---

## What `105` does NOT do

`fn_compute_nav` is **untouched** (both overloads; `md5(prosrc)` measured against a control).
`nav_daily` stays the gross pre-tax series permanently. The AC-3a leaf-set exclusion is **already
on `main` at `102`** — `105` does not re-land it. The §2.1.1 headline's read-source move (AC 1a)
is Backend's, in `api/src/lib/server/queries/netWorth.ts`.
