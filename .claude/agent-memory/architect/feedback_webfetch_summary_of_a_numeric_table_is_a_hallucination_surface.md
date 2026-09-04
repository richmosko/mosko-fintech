---
name: webfetch-summary-of-a-numeric-table-is-a-hallucination-surface
description: WebFetch's summarizer returned 2023/2024 IRS figures from a 2026 Rev. Proc. PDF — plausible, correctly formatted, wrong. Pull the primary bytes (pdftotext -layout) before any number reaches committed SQL.
metadata:
  type: feedback
---

**A WebFetch answer about a NUMERIC TABLE is a summarizer's recollection, not a
read. Never let one reach committed bytes — extract the primary source and read
the table yourself.**

**Why:** measured at SELF-260 / `103` (2026-09-04). WebFetch on
`https://www.irs.gov/pub/irs-drop/rp-25-32.pdf` — the tax-year-2026 Revenue
Procedure — was asked for the §.03 capital-gains thresholds and returned
`$47,025 / $518,900` (the **2024** figures), a `$11,000 / $44,725 / …` ordinary
table (the **2023** one), and a `$14,600` standard deduction (**2024**). Every
number was correctly shaped, internally consistent, and attributed to the right
sections of the right document. The small model answered from its own weights
instead of the PDF, and nothing in the response signals that.

It was caught only because the SAME session had already fetched the IRS newsroom
HTML page directly and had `$16,100 / $12,400 / $50,400 / …` in hand — i.e. by a
second source, not by anything visible in the fetch itself. **A single WebFetch of
a figures table is unfalsifiable from inside the answer.**

**How to apply:**
- WebFetch on an HTML page whose figures are IN the prose is comparatively safe —
  the newsroom page was correct. The failure mode concentrates in **PDFs and
  tabular layouts**, where the summarizer cannot see the table structure.
- WebFetch saves a fetched PDF to a local path and **names it in the result**.
  `pdftotext -layout <path> out.txt` is available on this machine and preserves
  the column alignment; then `grep -n` the section headings and `sed -n` the rows.
  That is a read of the primary bytes and is what belongs in a migration header.
- ⚠ `WebFetch` returns HTTP 403 on some government hosts (ftb.ca.gov did, twice).
  `curl -L -A "Mozilla/5.0 …"` succeeded on the identical URL. **A 403 from
  WebFetch is not evidence the document is unavailable** — and a 404 from curl,
  which is what established that the FTB had not published its 2026 schedule,
  *is* a measurement worth citing in a header.
- Search-result summaries drift the same way and in a more seductive direction:
  a search said "$5,706 is the CA 2026 standard deduction"; the FTB 2025 Form 540
  booklet says $5,706 is the **2025** figure. The number was right and the YEAR
  was wrong — which no check on the number alone can catch.

Related: [[feedback_prove_derived_text_against_its_source]] (a byte-exact quote of
a wrong figure passes every fidelity check — so **measure what you quote**),
[[feedback_verifying_a_measurement_is_not_verifying_a_claim]].

**Second, smaller thing from the same session:** the `supabase db reset` guard
hook matches the **literal string anywhere in the command**, including inside a
`cat > file <<'EOF'` heredoc that is only *describing* the ban. Writing "no
`supabase db reset` was used" into a report file is itself blocked. Reword the
prose ("the banned local-reset CLI path was not used") rather than fighting the
hook — it is behaving correctly.
