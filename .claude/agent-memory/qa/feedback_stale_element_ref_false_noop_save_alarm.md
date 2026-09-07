---
name: stale-element-ref-false-noop-save-alarm
description: A save-button click via a `find`-derived ref taken before an intervening scroll/find call can silently miss the target, producing a real "POST 200 but DB unchanged" signature that looks like a broken save path but is a scripted-walk artifact — verify the write's own mechanism before reporting.
metadata:
  type: feedback
---

During the P3 commentary-editor walk (SELF-355, 2026-09-06), a real-keystroke Save-draft
attempt via `computer.left_click` on a `find`-derived ref produced: a genuine POST to `?/save`
that returned 200, yet `commentary_cash` and `updated_at` in the DB were completely unchanged
afterward. This has the exact shape of "the save silently no-ops" — a plausible, reportable
defect.

**Before reporting it, I read the RPC's own source** (`pfin.fn_save_monthly_commentary`,
migration 112). Its header states the write is an UNCONDITIONAL literal replace-all with no
equality short-circuit — every call reassigns all four columns and the `updated_at` trigger
fires on ANY update regardless of whether values changed. A genuinely successful call therefore
ALWAYS bumps `updated_at`. Since it didn't move, the RPC almost certainly never ran at all — most
likely my `type` keystrokes landed on nothing because the textarea ref was taken before an
intervening `find` call (for the Save button) that may have shifted the page, and the click
against a stale ref/coordinate missed the field silently.

Re-ran cleanly: fresh screenshot → click precisely at the visible textarea coordinates → type →
screenshot again to CONFIRM the typed text visibly appears BEFORE clicking Save. That attempt
persisted immediately and correctly. The first attempt was a test-tooling artifact, not a
product defect — and I only knew that because I traced the write's actual mechanism instead of
trusting the "200 but unchanged" pattern.

**How to apply**: when a scripted save/submit produces a network 200 but the expected DB write
didn't land, don't report it as a broken save path on pattern alone. (1) Read the write's own
source for an explicit no-op/short-circuit condition — if none exists, a "successful but inert"
call is mechanistically implausible and the click almost certainly never reached its target.
(2) Before trusting ANY scripted click on a text-input field, take a screenshot AFTER typing and
BEFORE submitting, to positively confirm the typed content landed in the DOM — don't infer it
from a stale `find` ref taken several tool calls earlier. This is the same discipline as
[[feedback_verify_causal_mechanism_before_stating]] applied to my OWN test methodology, not just
the code under test.
