---
name: vi-mock-file-scoped-dom-test-technique
description: vi.mock() in Vitest is file-scoped — a shared virtual-module test stub (e.g. $app/forms's enhance) can be locally re-implemented in ONE *.dom.test.ts file to test a code path the shared stub deliberately doesn't support, without touching or risking the shared stub other test files rely on. Used SELF-265.
metadata:
  type: reference
---

This repo's `$app/forms` stub (`api/tests/stubs/app-forms.ts`, aliased GLOBALLY in
`vitest.config.ts`) deliberately invokes a `SubmitFunction` synchronously on submit
but never invokes the async `({result, update}) => {...}` callback it may return —
its own header names this as an intentional scope boundary ("a spec that needs THAT
half still needs a further-extended stub — not assumed by this one").

Extending the SHARED stub to close that gap would change behavior for every
`*.dom.test.ts` in the tree that uses `use:enhance` — a wide, risky blast radius for
one issue's regression test, and several component headers explicitly document
reliance on the CURRENT (non-invoking) behavior as an accepted boundary, not a bug.

**The safe alternative, confirmed working (SELF-265, 2026-09-04):** put the new test
in its OWN file and call `vi.mock('$app/forms', () => ({ enhance: ... }))` at that
file's top level with a custom implementation that DOES invoke the returned callback
(with a canned `ActionResult` and a spy `update`). Vitest's module mocks are scoped
per test FILE (the module registry resets between files), so this override never
leaks into other test files that import the real shared stub. Verified: running the
full suite (169 files) after adding one such file showed zero effect on the other
168 files' pass/fail state — only the new file's own test(s) exercised the mock.

**How to apply:** whenever a genuine gap exists between what a shared test stub
supports and what a specific regression needs to prove, prefer a new, narrowly-scoped
file with its own `vi.mock` over widening the shared stub — cheaper, zero blast
radius, and the resulting test's file name/header can carry the full "why this exists
and why it's isolated" context inline. See
[[feedback_sveltekit_update_reset_defaults_on_success]] for the defect this technique
was used to encode.
