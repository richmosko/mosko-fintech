---
name: feedback-getbylabeltext-required-asterisk-no-space
description: This repo's TextField/SelectField render a required field's label as "Label*" with no separating space — @testing-library/dom's getByLabelText does exact textContent matching (not ARIA accname computation) and fails on an exact string match against a required field's label.
metadata:
  type: feedback
  score: n/a
---

TextField.svelte / SelectField.svelte render `{label}{#if required}<span aria-hidden="true"
class="req">*</span>{/if}` — no space between the label text and the asterisk. A required
field's rendered label textContent is therefore `"Quantity*"`, not `"Quantity"`.

`@testing-library/dom`'s `getByLabelText('Quantity')` does a plain exact-string match against the
label's `textContent` — it does NOT run the ARIA accessible-name algorithm, which would exclude
the `aria-hidden="true"` span. So an exact `getByLabelText('Quantity')` call fails with "Unable to
find a label with the text of: Quantity" on any REQUIRED field, even though the field renders
correctly and is genuinely associated via `<label for>`.

`getByRole(role, { name: 'Quantity' })` does NOT have this problem — it uses proper ARIA accname
computation (via `dom-accessibility-api`), which correctly excludes `aria-hidden` content. This is
why SymbolClassifyRow.dom.test.ts's `getByRole('combobox', { name: 'Category' })` against a
required select passed without needing any adjustment.

**How to apply:** For a required TextField/SelectField in this codebase, either query it via
`getByRole` (preferred where the role is unambiguous — inputs, comboboxes) or pass
`{ exact: false }` to `getByLabelText`/`queryByLabelText`/`findByLabelText` (substring match,
correctly finds `"Quantity*"` against the query `"Quantity"`). Don't "fix" TextField/SelectField
to add a space or drop the asterisk to make exact matching work — the rendered label is
intentional (required-field marker convention across every form in this codebase).
