---
name: pdf-worker-test-silently-skips-render-battery-without-chrome-path
description: workers/pdf-render's `npm test` (node --test) reports "26 passed, 0 fail" even when PUPPETEER_EXECUTABLE_PATH is unset — it silently SKIPS the entire real-Chromium render battery (the resource-loading fence legs) rather than erroring, so a clean-looking run can be verifying almost nothing.
metadata:
  type: feedback
---

During the SELF-362 P10 close-gate verdict (2026-09-07), a first `npm test` run in
`workers/pdf-render/` reported "tests 12, pass 12, fail 0" — looked clean. Reading the
output closely showed: `[render.test.js] PUPPETEER_EXECUTABLE_PATH is unset — skipping
the render battery. Set it to a local Chrome/Chromium binary to run these tests` followed
by a single `✔ SKIPPED — PUPPETEER_EXECUTABLE_PATH not set locally` line counted as ONE
passing test. The entire render battery this run needed to verify (the AC8
resource-loading-fence legs: `file://`, `http://` positive control, `data:` negative
control, the metadata-IP payload) never executed at all — a near-empty "pass" count
would have been reported as a real verification.

Setting `PUPPETEER_EXECUTABLE_PATH` to a local Chrome-for-Testing binary (see
[[reference_pdf_worker_local_run_recipe]]) before re-running jumped the count from 12 to
26 tests, ~11 seconds of real headless-Chromium work, and is what actually exercises the
cited legs.

**How to apply**: `npm test` / `node --test` output that shows a suspiciously LOW test
count for a suite you know is larger, or a line containing "SKIPPED" counted as a pass,
is a signal to read the full output text, not just the pass/fail tally — a skip dressed
as a pass is the same false-green shape as [[feedback_permissive_harness_vacuous_green]].
For this specific worker, always export `PUPPETEER_EXECUTABLE_PATH` before trusting its
test count.
