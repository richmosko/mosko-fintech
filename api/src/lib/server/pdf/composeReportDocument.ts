// composeReportDocument.ts — SELF-358 (P6) fix, hand-off flag: this function used to be a named
// export directly off `reports/monthly/[target_month]/pdf/+server.ts`. `route-module-export-
// allowlist.server.test.ts` (the watcher `api/CLAUDE.md` itself documents — "a `+`-prefixed route
// module exports ONLY SvelteKit's own allowlist for that module shape") already existed and was
// ALREADY RED on `origin/feature/self-358` @ `169f4c8` before this fix — verified: `git diff
// origin/feature/self-358 -- '.../pdf/+server.ts'` shows no export added/removed by this dispatch.
// Worse than the watcher test: `npm run build` (real `vite build` + SvelteKit's postbuild
// `analyse` step) FAILS OUTRIGHT on this — `Error: Invalid export 'composeReportDocument' in
// /reports/monthly/[target_month]/pdf (valid exports are GET, POST, ... or anything with a '_'
// prefix)` — a genuine, pre-existing, PRODUCTION-BUILD-BREAKING defect, not merely a watcher-test
// red. Fixed here (in scope: this is a boring idiom translation inside a Backend-owned server
// surface, and it was blocking THIS dispatch's own `npm run build` verification requirement) by
// moving the function — and the three module-scope `?raw` CSS imports + `PRINT_FONT_STACK`
// constant it closes over — into `$lib/server/**`, the allowed non-route location, exactly the
// convention this file's own watcher test enforces elsewhere ("a plain value a loader needs to
// export... belongs in `$lib/server/**` and gets imported, never exported directly off a
// `+`-prefixed module" — api/CLAUDE.md).
import tokensCss from '$lib/styles/tokens.css?raw';
import appCss from '../../../app.css?raw';
// SELF-358 / P6 CSS ruling (`docs/records/v15-execution/self358-css-ruling.md`, Option A):
// `render()` from `svelte/server` emits ZERO scoped CSS (M1) — this is the ~14-component report
// tree's scoped `<style>` rules, captured build-time by the STANDALONE `vite.report-css.config.mjs`
// build (never SvelteKit's own build; `npm run build:report-css`, wired as a `build` prebuild
// step) into ONE committed, plain CSS file — inlined the SAME way as the two stylesheets above. If
// this import ever 404s, run `npm run build:report-css` to regenerate it.
import reportCss from '$lib/generated/report.css?raw';

// Sec F3(B)-style discipline: named constants, not magic literals.
const PRINT_FONT_STACK =
	'-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif';

/** Assembles the COMPLETE, self-contained HTML document pushed to the PDF-render worker (R2 (C)
 *  — the worker fetches nothing else; every byte it needs is in this string). Interpolates
 *  exactly two per-report values, both server-derived and fixed-shape (never free text; INV-2
 *  is not at stake here): `targetMonth` (already validated `YYYY-MM-01` by `parseTargetMonth` at
 *  the route) for the `<title>`, and the rendered component `head`/`body` from Svelte's OWN
 *  escaping (proven per-component in `MonthlyReportView.ssr.test.ts`, re-proven end-to-end in
 *  `pdf.escaping.test.ts`, alongside the route this function used to live in). */
export function composeReportDocument(componentHead: string, componentBody: string, targetMonth: string): string {
	return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title>Monthly Report — ${targetMonth.slice(0, 7)}</title>
<style>${tokensCss}</style>
<style>${appCss}</style>
<style>${reportCss}</style>
<style>
	/* Print-document base — system fonts only (worker fetches no font resource; RT-22-adjacent
	   posture: this route asks the worker for nothing beyond the one POST body). */
	body { font-family: ${PRINT_FONT_STACK}; margin: 0; }
</style>
${componentHead}
</head>
<body>
${componentBody}
</body>
</html>`;
}
