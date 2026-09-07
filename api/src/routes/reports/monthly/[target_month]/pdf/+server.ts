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
// AC 3 — ONE TEMPLATE: this route passes MonthlyReportView.svelte the EXACT SAME REPORT-DATA prop
// set `+page.server.ts`'s `load()` return threads to it (header/payload/taxCharacters/
// seedDeltaMigration/staleness/cashflowRowStaleness/staleAccountNames) — sourced from the SAME
// `loadMonthlyReportForRender()` call, so the two surfaces cannot silently diverge (R2 (C) makes
// this structural, not a discipline). SELF-358 / P6 adds exactly one more prop, `renderContext:
// 'print'` (the in-app page passes none, defaulting to `'browser'`) — per the CSS ruling's own
// LayerCake note, this is SIZING ONLY: it carries no report data and no user-controlled text, and
// must never gate rendered content, so it does not weaken this AC's "cannot silently diverge"
// guarantee.
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
// nothing user-controlled into the document shell (see `$lib/server/pdf/composeReportDocument.ts`:
// every per-report value it touches directly — `header.target_month`, `header.generated_at` — is a
// server-derived, fixed-shape value, never free text). The PROOF owed HERE (Sec R-5 / rederived-
// acs.md § SELF-358 AC7) is that this holds through the FULL document this route actually builds
// and pushes, not just the bare component render — see that test file for why `schedule_label`
// is flagged OUT of scope here rather than silently included or silently dropped.
//
// RT-25 (by signature): no `as_of` / `data_as_of` parameter of any kind crosses this route's
// boundary. The as-of this report used was resolved entirely inside `loadMonthlyReportForRender`
// (`row.data_as_of`), under that module's own RT-25 discipline.
//
// PDF FIDELITY — RULED (Architect, `docs/records/v15-execution/self358-css-ruling.md`, Option A;
// escalated at the prior hand-off per BACKEND CLAUDE.md "options with tradeoffs" — see git
// history on this file's earlier revision for the full options analysis this replaced):
// `render()` from `svelte/server` emits ZERO scoped CSS (`head` comes back empty; `body` carries
// Svelte's `.svelte-xxxxxx` scoped-class markers with no accompanying `<style>` block). Option B
// (`css: 'injected'`) is STRUCK on a measured CSP defect — Kit passes a component's `head` through
// verbatim and nonces only the style IT emits, so an injected inline style is silently CSP-blocked
// under this app's `style-src: ['self']` on every report page load. Option C (reading SvelteKit's
// build manifest at runtime) is rejected — no public API, no precedent under `api/src`, a
// request-time filesystem read on a §4.1 server surface.
//
// SHIPPED (Option A): a STANDALONE Vite lib build (`vite.report-css.config.mjs`, run by
// `npm run build:report-css`, wired as a `build` prebuild step — NEVER SvelteKit's own build) over
// the SAME `MonthlyReportView.svelte` tree this route renders, `cssCodeSplit: false`, emitting ONE
// committed, plain CSS file (`$lib/generated/report.css`) inlined below via the SAME `?raw`
// mechanism as `tokens.css`/`app.css`. `layercake`/`d3-scale`/`d3-shape` are externalized in that
// build — it only needs Svelte to compile each component's template + `<style>` block, never to
// execute the chart. Reproducibility verified (3 clean builds, byte-identical). Backend's spike
// census (fixture render vs. extracted CSS): every `svelte-[a-z0-9]+` token in the rendered body
// had ≥1 matching selector in `report.css` (zero missing) — the failure mode this mechanism must
// not silently produce (build drift → an unstyled PDF that still passes every value assertion).
// QA owns the committed version of that assertion; DevOps owes the regenerate-and-diff CI fence
// (the `052` shape) so a stale `report.css` reds a PR instead of shipping quietly wrong.
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
// SELF-358 / P6 fix (hand-off flag, see that file's own header): `composeReportDocument` moved to
// `$lib/server/pdf/composeReportDocument.ts` — it was a named export directly off this
// `+`-prefixed route module, which `route-module-export-allowlist.server.test.ts` already forbids
// (a PRE-EXISTING defect, not introduced by this dispatch) and which fails `npm run build`
// outright (SvelteKit's postbuild `analyse` step rejects any export outside its own allowlist).
import { composeReportDocument } from '$lib/server/pdf/composeReportDocument';
import type { RequestHandler } from './$types';

/** `2026-09-02T14:00:00Z` -> `20260902T140000Z` — filename-safe (no `:`), still sortable,
 *  still traceable back to the exact ISO instant by a human who needs to. Never the owner
 *  string (AC5) — this function's only input is a machine timestamp. */
function filenameSafeGeneratedAt(generatedAtIso: string): string {
	return generatedAtIso.replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z');
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
			staleAccountNames,
			// SELF-358 / P6: `render()` has no DOM, so LayerCake's normal ResizeObserver-based
			// auto-sizing never fires — `'print'` makes HistoricalExpendituresChart pass LayerCake
			// fixed ssr/width/height props instead. SIZING ONLY (see MonthlyReportView.svelte's
			// own header) — no other branch of this template reads this value.
			renderContext: 'print'
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
