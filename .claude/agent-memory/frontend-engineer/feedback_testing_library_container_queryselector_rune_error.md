---
name: feedback_testing_library_container_queryselector_rune_error
description: Destructuring `container` alongside query helpers from @testing-library/svelte's render() in this repo's LayerCake-based chart components can throw a spurious "$state rune outside svelte" error — use the query helpers (queryByText/getByRole/etc.) only, never container.querySelector, in this codebase's DOM tests.
metadata:
  type: feedback
---

While adding a DOM test to `NavHistoryChart.dom.test.ts` (SELF-229), destructuring
`const { container, queryByText } = render(NavHistoryChart, {...})` and then calling
`container.querySelector(...)` threw `Svelte error: rune_outside_svelte — The $state rune
is only available inside .svelte and .svelte.js/ts files`, reproducibly, in isolation
(`vitest run -t "..."` on just that one test) and in the full suite. Dropping `container`
entirely and using only `queryByText`/`getByText` (the pattern every other test in this
file and its siblings already use) made the error disappear with no other change.

**Why:** not root-caused (didn't chase further — the working idiom was already the
codebase norm), but empirically confined to this repo's Svelte 5 + `@testing-library/svelte`
+ LayerCake combination in `NavHistoryChart.dom.test.ts` specifically. Every pre-existing
passing test in that file already avoids raw `container.querySelector` in favor of the
testing-library query methods, which in hindsight was the tell.

**How to apply:** in this repo's `.dom.test.ts` files (jsdom environment,
`@testing-library/svelte`), never destructure `container` off `render()` for a DOM query —
use `getByText`/`queryByText`/`getByRole`/`findByRole`/etc. instead, matching the existing
convention in every sibling test file. If a structural (class-based) assertion is genuinely
needed where no accessible-text/role query fits, try it first — this may be narrower than
"never use container," but the safe default in this codebase is to avoid it.
