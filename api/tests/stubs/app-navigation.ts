// tests/stubs/app-navigation.ts
//
// Test-only stand-in for SvelteKit's `$app/navigation` virtual module (mirrors the
// existing `$env/dynamic/*` stub convention in this directory). The standalone api/
// vitest harness (vitest.config.ts) does NOT run `svelte-kit sync` and does not load
// the full SvelteKit Vite plugin, so `$app/navigation` is unresolvable without an
// alias; components that call `goto()` (e.g. NavHistoryChart.svelte, SELF-220) are
// aliased to this stub under test.
//
// `goto` is a real `vi.fn()` so a spec can assert on calls/args directly via the
// import (`import { goto } from '$app/navigation'` inside the test file resolves to
// THIS SAME instance under the shared alias) — no `vi.mock()` needed, and no import
// path is being faked, since the alias IS the resolution. Reset between tests with
// `goto.mockClear()` if a spec needs isolation from a prior call.
//
// Never used in the real build — the SvelteKit plugin supplies the genuine virtual
// module there.

import { vi } from 'vitest';

export const goto = vi.fn(async (_url: string | URL, _opts?: unknown) => {});
