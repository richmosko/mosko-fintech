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
// EXTENDED (SELF-325, Frontend) exactly along the line the original comment invited: "A future
// spec that needs to exercise the actual submit callback ... should extend this stub to invoke
// the passed-in SubmitFunction and its returned callback — not fake a network response here."
// `enhance` now attaches a REAL `submit` listener that calls the caller's SubmitFunction
// synchronously with a `FormData` built from the live form (so a client-side Zod mirror's
// `cancel()` path — and any state it sets, e.g. field errors — is now observable from a DOM
// test that clicks a real submit button). It deliberately STOPS THERE: the async callback a
// SubmitFunction may RETURN (the `({ result, update }) => {...}` half, which a real submission
// would invoke after a fetch resolves) is intentionally NOT invoked — there is still no
// fetch/network pipeline here, and fabricating a fake `ActionResult` would be "faking a network
// response," exactly what the original comment ruled out. A spec that needs THAT half still
// needs a further-extended stub (or a mocked `fetch`) — not assumed by this one.
//
// Never used in the real build — the SvelteKit plugin supplies the genuine virtual module there.

import type { SubmitFunction } from '@sveltejs/kit';

export function enhance(form_element: HTMLFormElement, submit?: SubmitFunction): { destroy(): void } {
	const listener = (event: SubmitEvent) => {
		event.preventDefault(); // no real navigation/fetch in this stub
		if (!submit) return;
		const formData = new FormData(form_element);
		let cancelled = false;
		const action = new URL(
			form_element.getAttribute('action') || '',
			window.location.href || 'http://localhost/'
		);
		// Cast: this stub supplies only the fields a client-side-validation SubmitFunction
		// actually reads (formData/cancel/action/formElement) — see the header note above for
		// why the async result-callback path is out of scope here.
		const maybeAsyncCallback = submit({
			action,
			formData,
			formElement: form_element,
			controller: new AbortController(),
			cancel: () => {
				cancelled = true;
			},
			submitter: null
		} as unknown as Parameters<SubmitFunction>[0]);
		void maybeAsyncCallback; // see header note — intentionally never invoked
		void cancelled; // observable via the handler's own side effects (e.g. `errors` state), not read here
	};
	form_element.addEventListener('submit', listener as EventListener);
	return {
		destroy() {
			form_element.removeEventListener('submit', listener as EventListener);
		}
	};
}
