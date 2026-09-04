# `src/lib/server/validation/` — shared server-side sanitization

Backend-owned server surface (ARCH §4.1 allowlist). One battery, many DDL-shaped adapters —
this directory exists so a new numeric or string boundary is a new thin wrapper, never a new
copy of the adversarial rejection logic.

## `numeric.ts` — the numeric-sanitization battery (Lock 14 V1-SHIP-BLOCK mod #2)

`sanitizeDecimal(raw, shape)` is the parameterized core (not exported). It rejects, in order:

1. non-string / non-finite-number input
2. empty string
3. input longer than `MAX_INPUT_LENGTH` (64 chars) — checked **before** any regex runs
4. scientific / exponential notation (`1e5`, `1E-3`)
5. thousands separators (`,`)
6. any character outside `[\d.\-]` — this is what refuses currency symbols AND
   locale-formatted input (a non-en-US decimal comma, a grouped `1.234,56`, etc.): the rule
   is not "detect the locale and reject it," it is "the input is not already a plain
   `-?digits(.digits)?` string," which subsumes every locale variant without enumerating them.
   **This step is also what DELIVERS the literal-`NaN`/`Infinity`-text rejection** — every
   spelling of `NaN`/`Infinity` (any case) contains a letter outside `[\d.\-]`, so step 7
   below never actually fires against them; step 6 is the active check for that category
7. literal `NaN` / `Infinity` text — an INTENTIONAL BACKSTOP (Sec-confirmed 2026-08-17), not
   the delivering check: unreachable under the current step ordering, since step 6 already
   catches every case. Kept because unreachability is a property of today's step order, not
   an invariant the function guarantees — see the inline comment at the call site
8. digit-shape (integer-digit count / decimal-place count) against the caller's `shape`
9. — for shapes that supply one — a two-sided `min`/`max` value range, mirroring a DB CHECK

Two further backstops exist past step 9 in the implementation (not in this numbered list
because they aren't independent rejection categories): a digit-count re-check right after
step 8's regex, and a `Number.isFinite` re-check after the numeric conversion. Both are also
unreachable under the current composition — see their inline comments — and preserved for
the same reason as step 7.

Every exported function is a named, DDL-shaped call into that core — never call
`sanitizeDecimal` directly from outside this file; add a new named export instead, so a call
site can't invent a shape inline that drifts from the table it's validating against.

**Current consumers:**

| Export                   | DDL shape                                   | First consumer                                   |
| ------------------------- | -------------------------------------------- | ------------------------------------------------- |
| `sanitizeCurrencyAmount`  | `numeric(20,4)`, no range check              | SELF-201 — `pfin.account` / `pfin.account_trans`   |
| `sanitizePercent`         | `numeric(5,2)`, `CHECK (0 <= x <= 100)`      | SELF-233 — `pfin.planning_target.target_percent`   |
| `sanitizeQuantity`        | `numeric(28,8)`, no range check              | SELF-325 — `pfin.account_trans.quantity` (088)     |
| `sanitizeFractionRate`    | `numeric(12,8)`, `CHECK (0 <= x <= 1)` (fraction)  | SELF-259 — `pfin.tax_bracket_row.bracket_rate` (101) |

**Adding a numeric consumer (e.g. V1.4 tax-bracket amounts, RT-24):**

1. Read the target column's DDL (precision/scale, and any `CHECK` range) live from its
   migration — never assume it matches an existing shape.
2. Add ONE new exported function here: a thin call into `sanitizeDecimal` with that shape's
   `maxIntDigits` / `maxDecimalPlaces` (and `min`/`max` if the DDL carries a `CHECK` range).
   Do not touch the core or any existing export — this is additive by construction.
3. The Zod adapter belongs in `schemas/`, one file per surface (see `schemas/account.ts`,
   `schemas/planning-target.ts`) — a `z.any().transform(...)` that calls the new function and
   maps a rejection to a `ZodIssueCode.custom` issue. Do not import Zod into this file.
4. The six adversarial categories (NaN, Infinity, currency-string, regex-overflow,
   scientific-notation, locale-formatted) are already covered by the shared core — a new
   consumer's adversarial test only needs to assert the *shape*-specific boundary (its own
   digit/decimal/range limits), not re-prove the six categories from scratch.

## Why this file has no Zod import

Kept framework-agnostic so it is unit-testable in isolation (`numeric.test.ts`) without a
SvelteKit/Zod harness. The Zod adapter is a few lines per surface in `schemas/` — see
`sanitizeCurrencyAmount`'s adapter (`schemas/account.ts`'s `currencyAmount()`) or
`sanitizePercent`'s (`schemas/planning-target.ts`'s `percentValue()`) for the pattern to copy.

## `../schemas/asOf.ts` — the shared as-of range/shape battery (Lock 15 / ADR-011 Decision 19)

Lives in `schemas/`, not here, because it IS a Zod schema factory (`asOfSchema(maxAsOf)`) rather
than a framework-agnostic core with a thin Zod adapter — it doesn't carry the "why this file has
no Zod import" constraint above. Documented in this README anyway because it is this
directory's sibling convention applied to a second boundary class: ONE constant (`AS_OF_FLOOR`)
+ ONE range-bound schema factory serves every V1 as-of surface — §2.2 today (SELF-238/240), §2.3
threading next (SELF-250/253) — never a second copy of the range fence, the same one-battery-
many-adapters shape `numeric.ts` uses above.

**Server-derived-only convention for §2.6 paths.** [ADR-011](../../../../../DECISIONS.md#adr-011)
Decision 19 (Lock 15) states the fence VERBATIM (quoted, not paraphrased — re-read it live before
citing, per this project's standing discipline):

> "server-derived-only fence for §2.6 paths (NO client-asserted `data_as_of` for cron + on-demand
> monthly_report; §2.3.3 drill-down is the ONLY surface where client toggle is legitimate)"

**Scope of the "ONLY surface" clause**, per Decision 19's 2026-08-22 amendment (Sec-reviewed at
the V1.3 pre-flight sitting, no behavior change): that clause is a statement about the PRD's V1
as-of-**toggle** inventory specifically — §2.3.3 is still the only V1 story carrying a
user-facing historical as-of control (`story-2-3-3`) — and does NOT speak to other, non-toggle
client-supplied dates that are already live elsewhere (a chart window; a manual account's
opening-balance date). Read the amendment in full at DECISIONS.md before relying on either
clause for a new surface — do not paraphrase from this README, and do not treat this quote as a
substitute for reading the live amendment.

**What this means for `§2.6` paths (cron + on-demand `monthly_report`):** neither may EVER accept
a client-supplied as-of / `data_as_of` value, full stop — the DB clock (`pfin.fn_server_today()`,
ADR-044 Decision 2) is the only legitimate source, resolved once per request and threaded
through, never re-derived per consumer. `asOfSchema`'s `as_of` field exists for §2.2/§2.3
read-path surfaces where a client-supplied as-of IS legitimate (or, for §2.2 today, validated but
not yet wired to any route) — importing this schema into a §2.6 endpoint to accept a client value
would be a NEW instance of exactly the hole this fence exists to close, not a reuse of it.
