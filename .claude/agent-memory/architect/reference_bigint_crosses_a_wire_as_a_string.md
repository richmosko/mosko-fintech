---
name: bigint-crosses-a-wire-as-a-string
description: A bigint crossing a serialization boundary arrives as a string while TypeScript claims number — both sides' unit tests pass because neither crosses the wire
metadata:
  type: reference
---

**A `bigint` crossing a serialization boundary arrives as a STRING while TypeScript claims
`number`. Both sides' unit tests pass, because neither test crosses the wire.**

Measured 2026-08-21 (SELF-325), found by a live browser walk-through and nothing else.
`POST /asset/resolve` returned 502 for **every** symbol, **every** time — a totally broken
production path that shipped through a full green suite.

**The chain, and note that no single link is a mistake:**
1. `postgres()` built with no `bigint`/`transform` option → postgres.js's **documented default**
   returns `int8` as a JS **string** (precision safety — `int8` exceeds `Number.MAX_SAFE_INTEGER`).
2. The resolver declared `Promise<number | null>` — **a compile-time annotation over a runtime
   string.** TypeScript asserted a fact about a driver that the driver does not honour.
3. The HTTP handler passed the value through with no coercion.
4. The client's Zod schema demanded `z.number()`, failed, and returned 502 **on the one failure
   branch with no `console.error`** — the other two branches logged.

⚠ **Why every instrument missed it: each side is unit-tested against its OWN declared contract,
and neither test serializes.** The type system did not merely fail to catch it — **it actively
concealed it**, because every layer agreed on `number` for the same reason: they had all been
*told* so by the same annotation.

**How to apply:**
- ⚠ **A TS return type on a value that came from a driver is a CLAIM ABOUT THE DRIVER, not a
  fact.** Verify it at the first boundary, or coerce there.
- **Suspect every `bigint`/`int8`/`numeric` that crosses a process boundary.** `numeric` is the
  better-known case (PostgREST returns it as a string to preserve precision); `int8` is the one
  people forget. **They are different types with different rules — proving one says nothing
  about the other.**
- **Test ACROSS the seam, not on both sides of it.** Two green suites either side of a wire are
  not evidence about the wire.
- ⚠ **A silent failure branch turns a total outage into "nothing appears to happen."** If a
  handler has three failure branches and two log, the third is where you will lose a day.
- **Look for the partially-guarded file:** in the same codebase, one field had `Number(...)` with
  a comment naming the hazard while two sibling `bigint` fields had none. **Someone knowing the
  class is not the same as having applied it — check the siblings.**

Related: [[feedback_layers_green_seam_absent]] ·
[[feedback_instrument_cannot_observe_the_property]] ·
[[feedback_spot_check_the_contract_at_its_consumer]]
