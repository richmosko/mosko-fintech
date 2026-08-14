---
name: feedback-vitest-tohavelength-dom-array-crash
description: expect(domElementArray).toHaveLength(0) crashed with an unrelated Svelte-internals error ("$state rune is only available inside .svelte files") instead of a clean assertion failure, ONLY on the failing (non-zero) case — cost significant time to isolate. Root cause: the failure-message pretty-printer tries to serialize a raw SVG <path> element inside a plain JS array, and that serialization path is what throws, not the test logic. A NodeList (e.g. from querySelectorAll passed directly, unwrapped) printed fine on an identical failure shape.
metadata:
  type: feedback
---

Authoring a Vitest + `@testing-library/svelte` (Svelte 5, jsdom) DOM test that
asserted zero matching SVG `<path>` elements: `Array.from(container.querySelectorAll(...)).filter(...)`
then `expect(filtered).toHaveLength(0)`. On the PASSING case (empty array) this
worked. On the FAILING case (array had 1 real `<path>` element — the actual
RED-proof scenario I needed) it crashed instead of failing cleanly:

```
Svelte error: rune_outside_svelte
The `$state` rune is only available inside `.svelte` and `.svelte.js/ts` files
```

with a stack trace bottoming out inside Svelte's own internals
(`node_modules/svelte/src/internal/client/errors.js`), giving no hook back
into my test code at all — looked exactly like an environment/tooling
problem, not something my test caused.

**Wasted significant time on wrong hypotheses first:** tried a different query
method (`queryAllByRole` → plain `querySelector`), tried removing a `:not()`
CSS compound selector in favor of JS `.filter()`, tried isolating the test
with `-t`, tried a fully clean `node_modules/.vite` + `.svelte-kit` cache
wipe — none of these were the cause, though ruling each out was legitimate
diagnostic work, not wasted per se.

**What actually isolated it:** a standalone throwaway test file reproducing
the identical render + query + filter, but with a NON-FAILING assertion
(`toBeGreaterThanOrEqual(0)`) — that passed cleanly. Only when I put the
REAL failing assertion (`toHaveLength(0)` against a length-1 array) back did
it crash. That pinned the trigger to **the assertion library's failure-path
serialization of a raw DOM element inside a plain JS array**, not the query,
not the selector, not accumulated render() state across other tests in the
file (confirmed it crashes even fully isolated via `-t`).

**Fix:** assert on `.length` (a number) instead of the array itself —
`expect(filtered.length).toBe(0)` rather than `expect(filtered).toHaveLength(0)`.
Same property, same quality of failure message ("expected 1 to be 0"), and the
pretty-printer never touches the DOM element because there's nothing to
serialize. A `NodeList` passed directly to `toHaveLength` (not wrapped in
`Array.from`/`.filter()`) printed fine on an identical shape of failure in a
different test in the same file — so the trigger is specifically an ARRAY of
raw elements reaching a matcher that tries to diff/print it, not DOM elements
in assertions generally.

**How to apply:** when a DOM/component test needs to assert "zero matching
elements" (or any array-length check) over a JS array built from
`Array.from(querySelectorAll(...)).filter(...)`, prefer asserting on
`.length` directly rather than the array itself, in this Svelte 5 + Vitest +
jsdom stack specifically. If a DOM-array assertion crashes with a Svelte
"$state rune" or similar internals error that has no application-code frame
in its stack, suspect the pretty-printer over the test logic — write a
minimal standalone repro with a non-failing assertion first to confirm the
query itself is fine, then swap in the real failing assertion to catch the
crash at the actual pretty-print boundary, matching the diagnostic sequence
that worked here.
