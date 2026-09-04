---
name: sveltekit-update-reset-defaults-on-success
description: SvelteKit form-action `update()` resets the native form unless called with `{reset:false}` — a success branch that forgets it (while the failure branch has it) blanks a just-saved form even though the write succeeded. Confirmed live, SELF-265.
metadata:
  type: feedback
---

Live-walked SELF-265's `/settings/tax-brackets` editor (real browser, real Postgres):
editing a bracket rate and clicking Save changes made the ENTIRE form blank out with
"Enter an amount" / "A schedule label is required" on every field, immediately after
save — looking exactly like the write failed or the data got wiped. A direct DB read
and a full page reload both confirmed the write was correct and complete; only the
in-page display was corrupted.

**Root cause, generalizable:** `TaxBracketScheduleEditor.svelte`'s `handleSubmit`
success branch called bare `await update();`, while the failure branch (a few lines
below, in the SAME function) correctly called `await update({ reset: false });`.
SvelteKit's `update()` from a `use:enhance` callback resets the underlying native
`<form>` element to its DOM defaults unless told not to — an asymmetry that is easy
to introduce (the failure branch's `{reset:false}` reads like defensive boilerplate,
not a load-bearing option) and easy to miss in review, since `npm run check` and the
whole vitest suite were green (2098/2098) — nothing in the static or unit-test layer
can see this, because the shared `$app/forms` test stub (`tests/stubs/app-forms.ts`)
deliberately never invokes a `SubmitFunction`'s async result-callback at all.

**Why:** the SUCCESS branch is exactly the one where a user is looking at values they
just typed/edited and expects to keep seeing them (edit mode keeps the same editor
instance mounted after save — unlike create mode, which unmounts moments later via
`onSaved()`, masking the same defect there).

**How to apply:** whenever reviewing (or walking) a `handleSubmit`/`SubmitFunction`
with both a success and a failure branch calling `update()`, diff the OPTIONS passed
on each branch — an asymmetry there is a strong defect signal, not stylistic noise.
This class of bug is invisible to `npm run check`, invisible to the existing DOM-test
harness (structurally, by the shared stub's own design), and only surfaces on a real
submit in a real browser. See [[reference_vi_mock_file_scoped_dom_test_technique]] for
how a targeted, isolated test can encode it without extending the shared stub.
