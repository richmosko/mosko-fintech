# RULING — SELF-358 / P6: PDF HTML self-containment (component CSS) + LayerCake SSR sizing

Architect, 2026-09-06. Evidence file for the ruling sent to team-lead + backend.

## NOT a one-way door

Nothing recommended below needs a data migration, a vendor commitment, or a breaking change to
reverse. The recommended option adds a generated artifact + a CI diff fence; deleting the script,
the artifact and the fence returns the tree to today's state. The one candidate that WOULD have
been one-way-door-adjacent — a project-global Svelte compiler-option change — is rejected on a
measured defect, not on reversibility.

## Measured facts (these decide it)

M1. SvelteKit passes the component's `head` payload through VERBATIM.
    `node_modules/@sveltejs/kit/src/runtime/server/page/render.js:302` — `new Head(rendered.head, …)`.
    The CSP nonce is attached ONLY to the style element Kit itself emits (`render.js:325–327`:
    `if (csp.style_needs_nonce) attributes.push(nonce)` / `csp.add_style(style)`).
    `rendered.css` IS destructured from the root render (`render.js:264`) and then never used.
    ⇒ a Svelte-`injected` `<style>` in a component's head reaches the browser WITHOUT a nonce.

M2. `api/vite.config.ts` sets `csp: { mode: 'nonce', directives: { 'style-src': ['self'],
    'style-src-elem': ['self'], 'style-src-attr': ['none'] } }`; `kit.inlineStyleThreshold` is
    unset (grepped: zero hits in `vite.config.ts` and `src/`), so today every page stylesheet is a
    `<link>` and there is no inline style anywhere.
    ⇒ combined with M1: `css: 'injected'` would emit a CSP-BLOCKED inline style plus a console
    violation on EVERY `/reports/monthly/[target_month]` page load. The page would still look
    right (the `<link>` chunk still applies), so the defect is silent-but-permanent on a
    Sec-reviewed surface.

M3. `dynamicCompileOptions` is a public, typed API in the installed
    `@sveltejs/vite-plugin-svelte@7.1.2` (`types/index.d.ts:85`), and this project's
    `vite.config.ts` ALREADY uses a function-valued `compilerOptions.runes: ({filename}) => …`.
    So per-file compiler-option divergence has precedent here.
    ⚠ But it CANNOT separate the PDF route from the SSR page: both are served by the same server
    build, and a query-suffixed import (`…View.svelte?pdf`) would not propagate the suffix to the
    ~14 child components, which compile once. Per-route scoping of `css:'injected'` is not
    achievable with this toolchain.

M4. The report component subtree imports no `$app/*` and no `$env/*` — grepped over
    `MonthlyReportView.svelte` plus its 9 direct children (NavCompositionTable, NavDeltaPanel,
    NavReferenceDatesPanel, TaxDecompositionTable, TaxQuarterlyTables, CashflowRollupTable,
    HistoricalExpendituresChart, StaleConstituentBadge, MonthlyReportStaleBanner). Zero hits.
    ⇒ the tree compiles outside SvelteKit; a standalone Vite lib build over it is viable.

M5. ⚠ PARTIAL, honestly reported. A standalone Vite lib build
    (`root=api`, `$lib` alias, `cssCodeSplit:false`, entry = `MonthlyReportView.svelte`,
    `layercake` handled as external/stub) EMITTED `report.css` (37,300 bytes) and `report.js`
    (131,113 bytes) on ONE run in my scratchpad harness. On re-run the harness broke on
    `UNRESOLVED_ENTRY` (a cwd/root interaction in my hand-rolled config, not a property of the
    approach) and I did NOT inspect the emitted rules.
    ⇒ Treat M5 as strong evidence, NOT as a green build. The spike's first job is a reproducible
    emit and an inspection of the emitted selectors. I am not claiming the extraction is proven.

## The failure mode that must become a test, not a hope

The PDF's `body` is produced by the SvelteKit SERVER build; under the recommended option the CSS is
produced by a SEPARATE build. Svelte's `.svelte-XXXXXX` scoping hash derives from the component's
CSS content, so the two SHOULD agree — but if they ever diverge, the PDF renders completely
unstyled, i.e. byte-identical in symptom to today's bug, and every value assertion still passes.

Required assertion (cheap, deterministic, subsumes staleness):
> extract every `svelte-[a-z0-9]+` token from the rendered `body`; assert each one appears in at
> least one selector in the extracted CSS.

A rule change changes the CSS text, which changes the hash, which reddens this leg — so this single
assertion catches drift AND a stale artifact. The CI regenerate-and-diff fence is belt-and-braces
on top of it, not the primary control.

## Options as presented

- **A (recommended)** — build-time CSS extraction to a committed generated artifact, inlined by the
  PDF route via the `?raw` mechanism it already uses for `tokens.css` / `app.css`.
- **B (rejected, measured)** — `css: 'injected'` via `dynamicCompileOptions`. Killed by M1+M2.
- **C (rejected)** — runtime read of SvelteKit/adapter-node build-manifest internals. No public API,
  no precedent under `api/src`, re-breaks on every Kit/Vite major, and adds a request-time
  filesystem read inside a §4.1 server surface.
- **D (rejected)** — de-scope the ~14 components' styles into a global print CSS file. Preserves
  `?raw` trivially but destroys scoping across Frontend-owned components and replaces a mechanism
  with a convention ("remember to update the global file"), which this project has repeatedly
  ruled against.
- **E (named, rejected)** — the PDF route server-fetches its own page HTML with
  `inlineStyleThreshold` raised. Maximal fidelity to "one template", but it prints the interactive
  chrome (Download button, Regenerate control, live staleness banner) into the PDF, and it
  reintroduces an internal self-call shape adjacent to the `/internal/pdf-render` route R2 (C)
  retired.

## LayerCake

Backend's shape is confirmed with one addition: the sizing must be ONE named, enumerated
render-context prop threaded route → MonthlyReportView → HistoricalExpendituresChart, and it may
affect layout/sizing ONLY. Any conditional CONTENT behind that prop (a section shown or hidden, a
value formatted differently) breaks SELF-358 AC3's structural one-template guarantee. AC3's
"exact same prop set" is not violated by a render-context prop: it carries no report data and no
user-controlled text.
