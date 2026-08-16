---
name: sveltekit-plus-prefix-reserved-in-routes
description: A test file named +<anything>.test.ts inside src/routes/ breaks `svelte-kit sync` (and therefore `npm run check`) — SvelteKit reserves the `+` prefix there for its own route files. vitest alone won't catch it.
metadata:
  type: reference
---

Any file starting with `+` inside `src/routes/` (or a nested route directory) is SvelteKit's own
reserved namespace (`+page.svelte`, `+page.server.ts`, `+layout.*`, etc.). Naming a co-located test
file to mirror the component it tests — e.g. `+page.staleness.test.ts` for `+page.svelte` — throws
`Files prefixed with + are reserved` out of `svelte-kit sync`.

**Why this bites silently:** `vitest run` does NOT invoke `svelte-kit sync` itself, so the test
runs and passes fine in isolation. Only `npm run check` (`svelte-kit sync && svelte-check`) — a
separate command — surfaces the break. A file authored and verified via `vitest run` alone can
look completely clean and still fail CI's type-check step.

**How to apply:** for a route-level test co-located in `src/routes/`, use a topic-named file that
does NOT start with `+` — this repo's own existing convention is `nav-series.server.test.ts`
testing `+page.server.ts` (not `+page.server.test.ts`). Follow the same pattern: drop the `+`,
name by subject matter, keep it in the same directory. Always run `npx svelte-kit sync` (or the
full `npm run check`) at least once for any new file placed directly under `src/routes/`, not just
`vitest run` — this is the one directory in the repo where a passing test run doesn't imply a
passing type-check.
