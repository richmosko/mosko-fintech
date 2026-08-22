---
name: reference-app-forms-stub-extended-submit
description: api/tests/stubs/app-forms.ts's `enhance` stub was a pure no-op; extended 2026-08-21 (SELF-325) to actually invoke a component's SubmitFunction synchronously on a real submit event, so DOM tests can exercise client-side Zod cancel() paths from a real button click.
metadata:
  type: reference
---

`api/tests/stubs/app-forms.ts` stands in for SvelteKit's `$app/forms` under the standalone
api/ vitest harness (no `svelte-kit sync`). It originally (SELF-235, QA) made `enhance` a pure
no-op — mounted the component without throwing but never called the `SubmitFunction`, so a DOM
test could only assert on raw `new FormData(form)` shape, never on what a `cancel()`-triggered
client-side validation error actually rendered.

Extended (SELF-325, Frontend, 2026-08-21) per that file's own "future spec" invitation comment:
`enhance` now attaches a real `submit` listener that calls the `SubmitFunction` synchronously
with a `FormData` built from the live form, so `cancel()` and any state a handler sets before
calling it (e.g. field errors) are observable from `fireEvent.click(submitButton)` in a DOM test.

Still NOT implemented: the async callback a `SubmitFunction` may return (the
`({result, update}) => {...}` half a real submission invokes after a fetch resolves) — there is
still no fetch/network pipeline in this stub. A spec that needs that half needs a further
extension or a mocked `fetch` (see PurchaseEntryForm.dom.test.ts's `vi.stubGlobal`-style mock of
`globalThis.fetch` for the resolve-step tests, which don't go through `enhance` at all since that
call is a plain fetch, not a form action).

Verified no regression when changed: full dom-project suite green before and after (152 tests at
the time). Read the file's own header before touching it again — it's shared test infra, not
scoped to one component.
