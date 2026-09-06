// reports/monthly/[target_month]/pdf/+server.ts — the §2.6.3.c PDF export (SELF-358 / P6).
//
// DIRECTION (R2 (C), docs/records/v15-preflight/sitting-log.md § R2 — STRUCTURAL, not a
// discipline this route could opt out of): the user's Download click hits THIS user-session app
// route. The worker credential (`renderClient.ts`'s signing key) never reaches the browser — it
// is minted and used entirely server-side, inside `renderReportHtml()`. This route composes the
// report under the CALLER'S OWN session (`locals.supabase`, RLS-scoped — RT-13, never
// service_role), renders the SAME Svelte template the in-app page mounts
// (`MonthlyReportView.svelte`, via Svelte 5's `render()` from `svelte/server`), and pushes the
// resulting HTML to the PDF-render worker (A4/A5). The worker holds no DB/tenant knowledge and no
// Supabase credential of any kind — see `renderClient.ts`'s own header, UNTOUCHED by this file.
//
// AC 2 — REFUSAL: available only from a `final` report. A `draft` is refused with 409 (the report
// exists, but its current state does not support this operation — the button-side disabled state
// + tooltip is Frontend's own AC2 concern; this is the server-side backstop for direct
// navigation). `loadMonthlyReportForRender` itself already 404s when no report row exists at all
// for `targetMonth`, and 500s on a genuine read failure — this route adds nothing on top of those,
// only the NEW final-vs-draft business rule (the shared loader deliberately does not own this —
// see that module's own header).
//
// AC 3 — ONE TEMPLATE: this route passes MonthlyReportView.svelte the EXACT SAME prop set
// `+page.server.ts`'s `load()` return threads to it (header/payload/taxCharacters/
// seedDeltaMigration/staleness/cashflowRowStaleness/staleAccountNames) — sourced from the SAME
// `loadMonthlyReportForRender()` call, so the two surfaces cannot silently diverge (R2 (C) makes
// this structural, not a discipline).
//
// AC 4 — TRANSIENT: the PDF bytes are streamed straight back in the HTTP response and never
// written to any table, bucket, or disk path this route owns. Nothing here persists them.
//
// AC 5 — FILENAME: `mosko-monthly-{YYYY-MM}-{generated_at}.pdf` — NEVER the owner string (PM:
// "a PDF name travels further than its contents"). `generated_at` is reformatted to a filename-
// safe compact form (colons are not portable in a filename); `target_month` supplies YYYY-MM.
//
// AC 6 — STALENESS READ LIVE: `loadMonthlyReportForRender` re-derives `staleness` /
// `cashflowRowStaleness` / `staleAccountNames` on every call (P8/R1 rider 2) — this route makes no
// second, independent staleness read of its own; it inherits the shared loader's live-read
// discipline for free by calling the SAME function the page loader calls.
//
// AC 7 — ESCAPING PROOF (INV-2): see `pdf.escaping.test.ts` alongside this file. The CONTROL is
// discharged structurally by Svelte's own default `{...}` interpolation inside
// MonthlyReportView.svelte and everything it composes (INV-1, already proven per-component in
// `MonthlyReportView.ssr.test.ts`) — this route adds no template of its own and interpolates
// nothing user-controlled into the document shell (see `composeReportDocument` below: every
// per-report value it touches directly — `header.target_month`, `header.generated_at` — is a
// server-derived, fixed-shape value, never free text). The PROOF owed HERE (Sec R-5 / rederived-
// acs.md § SELF-358 AC7) is that this holds through the FULL document this route actually builds
// and pushes, not just the bare component render — see that test file for why `schedule_label`
// is flagged OUT of scope here rather than silently included or silently dropped.
//
// RT-25 (by signature): no `as_of` / `data_as_of` parameter of any kind crosses this route's
// boundary. The as-of this report used was resolved entirely inside `loadMonthlyReportForRender`
// (`row.data_as_of`), under that module's own RT-25 discipline.
//
// ⚠⚠ BLOCKING GAP FOR PDF FIDELITY — FLAGGED AT HAND-OFF, NOT SILENTLY SHIPPED, NOT YET RULED ON:
// `render()` from `svelte/server` emits ZERO scoped CSS. Verified empirically (not assumed)
// against a real merged component: `head` came back empty, and the returned `body` carries
// Svelte's compiled `.svelte-xxxxxx` scoped-class markers on every element, but there is no
// accompanying `<style>` block anywhere in the render output defining what those classes DO.
// This route inlines the two GLOBAL, UNSCOPED stylesheets (`$lib/styles/tokens.css` + `src/
// app.css`, plain CSS files, safe to inline verbatim via a Vite `?raw` import — no hash-matching
// risk, since they were never Svelte-scoped to begin with) plus a minimal system-font print base
// below — but has NO source for the ~14 individual components' own SCOPED `<style>` rules (the
// ones that actually apply `display:flex`, spacing, color, etc. — i.e. everything that makes the
// six report sections look like anything). Without them, the PDF this route currently produces is
// STRUCTURALLY and ESCAPING-CORRECT (every AC this route owns other than visual fidelity holds)
// but renders as an unstyled, unformatted wall of text — a real fidelity defect, not a cosmetic
// one, BLOCKING for shipping this feature as a usable export.
//
// Svelte compiles each component's scoped CSS into a Vite chunk that browsers load via a normal
// page's `<link>` tag — a mechanism this route's bare `render()` call never goes through (there is
// no browsable "PDF page," only this endpoint). Reproducing that CSS here needs either
// (a) reading SvelteKit/adapter-node's build manifest at runtime to locate the exact chunk the
// live `/reports/monthly/[target_month]` page already ships to browsers (reuses existing build
// output, zero new build step, but couples this route to SvelteKit/Vite build-manifest internals
// that are not a stable public API and that this codebase has never read at runtime before —
// grepped: zero precedent anywhere under `api/src`), or (b) a new, purpose-built build step
// producing a standalone CSS bundle for this component tree (decoupled from SvelteKit's page-
// manifest internals, but is genuinely new build/deploy infrastructure — a new script, a new
// invocation point in `npm run build`/the Dockerfile, a new staleness risk if it isn't
// regenerated in lockstep with the components). BOTH are one-way-door-adjacent build/deploy-shape
// decisions per BACKEND CLAUDE.md ("new build-pipeline component," "options with tradeoffs"), not
// a "just decide" — escalated to team-lead/Architect at hand-off rather than picked unilaterally.
// DO NOT wire either option in without that ruling landing first.
//
// SEPARATE, ALREADY-SOLVED FINDING (no Architect call needed, kept here for the same reader):
// the LayerCake chart inside `HistoricalExpendituresChart.svelte` normally auto-sizes itself via
// browser-only container measurement (`bind:clientWidth`/`clientHeight`, no `ResizeObserver` — see
// that component; either way it is browser-DOM-dependent and inert during `render()`). LayerCake
// (v10.0.3, verified against the published source) ships built-in `ssr` (boolean) and `width!`/
// `height!` override props for EXACTLY this case — passing them makes LayerCake compute scales
// synchronously from the given dimensions with no DOM measurement at all, so the chart needs no
// external hydration bundle and no client JS to render correctly in this context. The only
// remaining work is a small, additive, backward-compatible prop-thread through two Frontend-owned
// files (`HistoricalExpendituresChart.svelte` forwarding `ssr`/`width`/`height` to `<LayerCake>`;
// `MonthlyReportView.svelte` accepting and passing down an optional print-sizing prop) — flagged
// to Frontend rather than touched here, per this dispatch's own file-ownership boundary.

import { error } from '@sveltejs/kit';
import { render } from 'svelte/server';
import { parseTargetMonth } from '$lib/monthly-report';
import { INVENTORY_SEED_DELTA_MIGRATION } from '$lib/server/queries/taxLiability';
import { loadMonthlyReportForRender } from '$lib/server/monthly-report/loadMonthlyReport';
import { renderReportHtml } from '$lib/server/pdf/renderClient';
import MonthlyReportView from '$lib/components/MonthlyReportView.svelte';
import tokensCss from '$lib/styles/tokens.css?raw';
import appCss from '../../../../../app.css?raw';
import type { RequestHandler } from './$types';

// Sec F3(B)-style discipline (mirrors renderClient.ts's own entropy floor comment style): named
// constants, not magic literals, for the two document-shell decisions this file itself makes.
const PRINT_FONT_STACK =
	'-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif';

/** `2026-09-02T14:00:00Z` -> `20260902T140000Z` — filename-safe (no `:`), still sortable,
 *  still traceable back to the exact ISO instant by a human who needs to. Never the owner
 *  string (AC5) — this function's only input is a machine timestamp. */
function filenameSafeGeneratedAt(generatedAtIso: string): string {
	return generatedAtIso.replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z');
}

/** Assembles the COMPLETE, self-contained HTML document pushed to the PDF-render worker (R2 (C)
 *  — the worker fetches nothing else; every byte it needs is in this string). Interpolates
 *  exactly two per-report values, both server-derived and fixed-shape (never free text; INV-2
 *  is not at stake here — see this file's own header): `header.target_month` (already validated
 *  `YYYY-MM-01` by `parseTargetMonth`) for the `<title>`, and the rendered component `head`/
 *  `body` from Svelte's OWN escaping (proven per-component, re-proven end-to-end in
 *  `pdf.escaping.test.ts`). */
export function composeReportDocument(componentHead: string, componentBody: string, targetMonth: string): string {
	return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title>Monthly Report — ${targetMonth.slice(0, 7)}</title>
<style>${tokensCss}</style>
<style>${appCss}</style>
<style>
	/* Print-document base — system fonts only (worker fetches no font resource; RT-22-adjacent
	   posture: this route asks the worker for nothing beyond the one POST body). Component-level
	   layout/color rules are NOT yet inlined here — see this file's own header "BLOCKING GAP". */
	body { font-family: ${PRINT_FONT_STACK}; margin: 0; }
</style>
${componentHead}
</head>
<body>
${componentBody}
</body>
</html>`;
}

export const GET: RequestHandler = async ({ locals, params }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw error(401, 'Not authenticated.');

	const targetMonth = parseTargetMonth(params.target_month);
	if (targetMonth === null) {
		throw error(400, 'Invalid target month.');
	}

	const { header, payload, taxCharacters, staleness, cashflowRowStaleness, staleAccountNames } =
		await loadMonthlyReportForRender(locals.supabase, targetMonth);

	// AC2 — the business rule this route owns on top of the shared loader: no PDF of a pending
	// report. `generated_at` is also guaranteed non-null here (108's own CHECK: set once, at
	// finalization, never before) — the AC5 filename below depends on that guarantee.
	if (header.generation_status !== 'final' || header.generated_at === null) {
		throw error(409, 'This report is still a draft. Finalize it before exporting a PDF.');
	}

	const { head, body } = render(MonthlyReportView, {
		props: {
			header,
			payload,
			taxCharacters,
			seedDeltaMigration: INVENTORY_SEED_DELTA_MIGRATION,
			staleness,
			cashflowRowStaleness,
			staleAccountNames
		}
	});

	const html = composeReportDocument(head, body, header.target_month);

	const outcome = await renderReportHtml(user.id, html);
	if (!outcome.ok) {
		// Status only — renderClient.ts's own redaction discipline; nothing further to add here.
		throw error(502, 'Could not generate the PDF. Please try again.');
	}

	const filename = `mosko-monthly-${header.target_month.slice(0, 7)}-${filenameSafeGeneratedAt(header.generated_at)}.pdf`;

	// `renderReportHtml`'s `pdfBytes` types as `Uint8Array<ArrayBufferLike>` (its backing buffer
	// could, per the ambient lib types, be a `SharedArrayBuffer`) — neither `BodyInit` nor
	// `BlobPart` accept that generic directly. Re-copying into a fresh `Uint8Array` (never a
	// cast) always allocates a plain `ArrayBuffer`-backed view, which both accept — this file
	// does not touch `renderClient.ts` (A5 is GREEN) to fix this on the other side.
	const pdfBytes = new Uint8Array(outcome.pdfBytes);
	return new Response(new Blob([pdfBytes]), {
		status: 200,
		headers: {
			'content-type': 'application/pdf',
			'content-disposition': `attachment; filename="${filename}"`
		}
	});
};
