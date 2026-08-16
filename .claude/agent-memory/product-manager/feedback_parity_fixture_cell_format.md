---
name: parity-fixture-cell-format
description: For V1-preserve parity surfaces, the §3.3 fixture's actual cell FORMAT (unit) is the requirement — read the PDF cells, not just the structural trace.
metadata:
  type: feedback
---

When drafting or ruling on ACs for a V1-preserve parity surface, verify the required cell format against the actual fixture (`temp/Finance_Report_2026_04.pdf`) — the Appendix C trace records structure (columns/rows/population), not units, and the two can diverge.

**Why:** SELF-222 AC3 (2026-08) — the §2.1.3 Inflation Adjusted column shipped dollar-only on the assumption the incumbent showed dollars; the PDF's panel is percent-only in BOTH columns. §3.3's parity metric compares against the fixture's cells at numeric tolerance, so a missing percent silently fails a ratified gate while an extra (superset) column is harmless. F/CTO ratified the fix as a 072 amendment (real-terms percent, deflated prior-YE anchor base).

**How to apply:** (1) Before locking an AC's rendering format on any §3.3-fixtured surface, read the fixture page directly (redact $ when writing anything down). (2) Frame gaps as "superset = safe, missing fixture cell = parity-gate failure." (3) An option pitched as "just an AC edit" that would leave a fixture cell unrendered is actually a §3.3 metric amendment — escalate it as a parity exception, not a wording fix. Related: [[component-history-option-c]].
