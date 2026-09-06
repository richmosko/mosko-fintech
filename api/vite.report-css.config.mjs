// vite.report-css.config.mjs — standalone build-time CSS extraction for the monthly-report
// component tree (SELF-358 / P6). Architect's ruling, `self358-css-ruling.md`, Option A: the PDF
// route's `render()` call (svelte/server) emits ZERO scoped CSS (M1), and `css: 'injected'` is
// struck on a measured CSP defect (M1+M2 — Kit passes a component's `head` through verbatim and
// nonces only the style IT emits, so an injected inline style is silently CSP-blocked on every
// report page load). This is a SEPARATE Vite build, run standalone (never by SvelteKit's own
// build), over the SAME component tree the SSR page and the PDF route both mount — its only job
// is to emit one plain CSS file capturing the ~14 components' scoped `<style>` rules, which the
// PDF route then inlines via the SAME `?raw` mechanism it already uses for `tokens.css`/`app.css`.
//
// NOT a one-way door (ruling, "NOT a one-way door"): deleting this file, the generated artifact,
// and the CI diff fence (DevOps-owed) returns the tree to today's state.
//
// `layercake`/`d3-scale`/`d3-shape` are marked EXTERNAL (M3's own constraint: this build cannot
// and does not need to execute the chart — it only needs Svelte to compile each component's
// template + `<style>` block so Rollup can concatenate the CSS. The JS chunk this build ALSO
// emits (`report.js`) is a byproduct of Vite's lib-build shape, not the artifact this build is
// for, and is NOT committed or consumed anywhere — see `report.css.gitignore` note in
// `src/lib/generated/`).
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import { defineConfig } from 'vite';

const apiRoot = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
	root: apiRoot,
	plugins: [
		svelte({
			compilerOptions: { runes: true }
		})
	],
	resolve: {
		alias: {
			$lib: path.resolve(apiRoot, 'src/lib')
		}
	},
	build: {
		outDir: path.resolve(apiRoot, 'src/lib/generated'),
		emptyOutDir: false,
		cssCodeSplit: false,
		lib: {
			entry: path.resolve(apiRoot, 'src/lib/components/MonthlyReportView.svelte'),
			formats: ['es'],
			fileName: () => 'report.js',
			cssFileName: 'report'
		},
		rollupOptions: {
			external: ['layercake', 'd3-scale', 'd3-shape']
		}
	}
});
