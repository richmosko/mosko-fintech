// tests/stubs/app-state.ts
//
// Test-only stand-in for SvelteKit's `$app/state` virtual module (mirrors the
// existing `$env/dynamic/*` / `app-navigation` stub convention in this directory).
// Unresolvable under the standalone api/ vitest harness for the same reason as
// app-navigation.ts — no `svelte-kit sync`, no SvelteKit Vite plugin.
//
// `page` is a plain mutable object, not a genuine Svelte-reactive one — sufficient
// for a component that reads `page.url` once per render/derivation (the real usage
// shape in this codebase, e.g. NavHistoryChart.svelte's reset-breadcrumb visibility
// and its own-URL-mutation navigation calls). A test that needs to vary the URL
// mid-test can reassign `page.url` directly before triggering a re-render; this stub
// does not attempt to reproduce SvelteKit's actual mid-navigation reactivity.
//
// `params` added for SELF-254 (cash-flow/[account_id]/+page.svelte, the first dom-tested
// component to read `page.params`) — empty by default, same "reassign before triggering a
// re-render" convention as `url` above.
//
// Never used in the real build — the SvelteKit plugin supplies the genuine virtual
// module there.

export const page = {
	url: new URL('http://localhost/'),
	params: {} as Record<string, string>
};
