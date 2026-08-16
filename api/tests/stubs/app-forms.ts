// tests/stubs/app-forms.ts
//
// Test-only stand-in for SvelteKit's `$app/forms` virtual module (mirrors the existing
// `$app/navigation` / `$app/state` / `$env/dynamic/*` stub convention in this directory).
// Unresolvable under the standalone api/ vitest harness for the same reason as those —
// no `svelte-kit sync`, no SvelteKit Vite plugin (vitest.config.ts's own header explains why
// the harness stays standalone). Added for SELF-235's SymbolClassifyRow.svelte, the first
// dom-tested component to import `use:enhance` — no prior *.dom.test.ts target needed it, so
// this gap in the alias map went unnoticed until a submit-level test was written (QA).
//
// `enhance` is a minimal no-op Svelte action: it satisfies the `use:enhance={handler}` call
// site (so the component mounts under jsdom without throwing) but does NOT drive the real
// fetch/submit pipeline — it never invokes the caller's SubmitFunction. This is sufficient for
// DOM tests that assert on the FORM'S OWN STATE (e.g. `new FormData(formElement)`, which the
// browser/jsdom constructs from live DOM regardless of whether a submit ever fired) rather than
// on what a submission POSTs over the network. A future spec that needs to exercise the actual
// submit callback (result.type === 'success' branches etc.) should extend this stub to invoke
// the passed-in SubmitFunction and its returned callback — not fake a network response here.
//
// Never used in the real build — the SvelteKit plugin supplies the genuine virtual module there.

export function enhance(_form_element: HTMLFormElement, _submit?: unknown): { destroy(): void } {
	return { destroy() {} };
}
