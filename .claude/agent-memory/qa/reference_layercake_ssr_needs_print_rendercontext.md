---
name: layercake-ssr-needs-print-rendercontext
description: A LayerCake-based chart (HistoricalExpendituresChart, NavHistoryChart) renders its chart-canvas EMPTY under svelte/server SSR unless renderContext='print' is passed explicitly — the default 'browser' context waits on a ResizeObserver that never fires without a DOM. Also documents the layercake-container/layercake-layout-svg third-party class exclusion needed when doing report.css hash-coverage checks.
metadata:
  type: reference
---

Discovered authoring P10 item (e)'s report.css hash-coverage leg (SELF-362, 2026-09-06).

**The gotcha:** `HistoricalExpendituresChart.svelte` (and any other LayerCake-based chart in this
tree) accepts a `renderContext: 'browser' | 'print'` prop. `'browser'` (the default) is byte-
identical to pre-P6 behavior — LayerCake auto-measures its container via `ResizeObserver`. Under
`svelte/server`'s `render()` (no DOM, so `ResizeObserver` never fires), the chart-canvas renders
functionally EMPTY (`<!--[-1--><!--]-->` — Svelte 5's zero-count SSR marker) regardless of how much
real data is in the fixture. `'print'` draws from a fixed `PRINT_CHART_HEIGHT` constant instead,
producing real SVG geometry (`layercake-layout-svg`, `.bar`, `.gridline`, etc.) even under SSR —
this is why the PDF export route (P6, always SSR) passes `renderContext="print"` explicitly.

**How to apply:** any SSR-based test (`svelte/server`'s `render()`) that needs to exercise a
LayerCake chart's actual drawn content — not just its legend/caption chrome — must pass
`renderContext: 'print'` (or the equivalent prop on whichever chart component it's driving).
Passing nothing (`'browser'`) silently produces an empty chart subtree with no error, which reads
as "the chart isn't there" rather than "the chart needs a different render mode."

**Related, same investigation — third-party wrapper classes in a report.css hash-coverage check:**
LayerCake's own `<LayerCake>`/`<Svg>` components (imported directly from the `layercake` npm
package) stamp their OWN scoped classes (`layercake-container`, `layercake-layout-svg`) under a
Svelte-compiler hash that belongs to LayerCake's own compiled source, not this app's. A report.css
build (a standalone Vite lib build over ONLY this app's `src/lib/components`) correctly does not
carry selectors for these — the app never styles library-internal wrapper markup it doesn't own.
If asserting "every rendered `svelte-hash` token must match a report.css selector," exclude these
BY CLASS NAME (`layercake-` prefix), not by hash — excluding by name still catches a REAL future
gap (an app-owned class report.css genuinely dropped), while excluding by hash would blind the leg
to a real regression that happened to reuse one of those two hash values.

**A related, useful fact for cross-build hash comparisons generally:** report.css (built via a
SEPARATE `vite.report-css.config.mjs` standalone lib build) and a vitest SSR render (the normal
dev/test Vite pipeline) DO produce the SAME `svelte-hash` per component in practice — 12 of 14
groups matched byte-for-byte on first try in this investigation, so a literal-hash comparison
between the two build contexts is a reasonable design, not inherently broken. The only mismatches
were the two library-owned hashes above; app-owned component hashes were stable across both
pipelines. Don't assume hash instability across builds without measuring it first.
