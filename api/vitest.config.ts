// api/vitest.config.ts
//
// OQ-3 — api/ test harness (SELF-212 build support). Stands up Vitest as the api/
// test runner so Frontend's SELF-198 tests, the Option-C relay-leg tests, and QA's
// api-tier tests have a runnable target.
//
// TWO TEST MODALITIES → TWO VITEST PROJECTS (SELF-226, QA; team-lead + F/CTO-approved
// Option A jsdom dep-add). The two modalities need DIFFERENT resolve conditions and can
// NOT share one environment:
//   • 'node'  — pure-TS server tests (src/lib/server/**, hooks, relay legs, utils) AND
//               `svelte/server` SSR-render tests (component → HTML string, no DOM). Svelte
//               resolves to its SERVER build here. This is the original, unchanged posture.
//   • 'jsdom' — DOM component-interaction tests (*.dom.test.ts): @testing-library/svelte
//               `mount` needs Svelte's BROWSER build → the svelteTesting() plugin puts
//               `browser` ahead of `node` in resolve.conditions + wires DOM auto-cleanup.
// Keeping them as separate projects means the browser resolve-condition is SCOPED to the
// jsdom project ONLY — the SSR/node tests keep server resolution and are byte-for-byte
// unaffected. (A single global `browser` condition would break `svelte/server` render.)
//
// DELIBERATELY STANDALONE (does NOT import vite.config.ts / the SvelteKit plugin): pure-TS
// server tests run without `svelte-kit sync` / a browser env.
//
// `node` project: `css: true` (SELF-358 / P6, DevOps-c's live-verified triage) — vitest
// defaults `test.css` to `false`, which short-circuits BEFORE Vite's own `?raw`/`?inline` CSS
// pipeline ever runs, unconditionally (vitest-dev/vitest#10788; reproduced on 3.2.4 / 4.1.9 /
// this repo's 4.1.10 — no version bump fixes it). Without this, a `.css?raw` import inside a
// `node`-environment test resolves to an EMPTY STRING, silently — it affected the two
// PRE-EXISTING `tokens.css`/`app.css` imports in the PDF route identically, not just the new
// `report.css`. Scoped to `node` only: the `dom` project never hit this (its component tests
// don't `?raw`-import CSS), and both projects are measured green after this change.
import { defineConfig } from 'vitest/config';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import { svelteTesting } from '@testing-library/svelte/vite';
import { fileURLToPath } from 'node:url';

// Shared TEST-ONLY alias resolution (both projects): the app's `$lib` convention + a
// process.env-backed stub for the SvelteKit `$env/dynamic/{private,public}` virtual modules
// (unavailable without svelte-kit sync). The real build resolves these via the SvelteKit
// Vite plugin. `import type ... from './$types'` needs NO alias (erased).
const alias = {
	$lib: fileURLToPath(new URL('./src/lib', import.meta.url)),
	'$env/dynamic/private': fileURLToPath(
		new URL('./tests/stubs/env-dynamic-private.ts', import.meta.url)
	),
	'$env/dynamic/public': fileURLToPath(
		new URL('./tests/stubs/env-dynamic-private.ts', import.meta.url)
	),
	// SELF-220: NavHistoryChart.svelte calls `goto()` / reads `page.url` from
	// `$app/navigation` / `$app/state` — likewise unresolvable without `svelte-kit
	// sync`. Same stub convention as the `$env/dynamic/*` aliases above.
	'$app/navigation': fileURLToPath(new URL('./tests/stubs/app-navigation.ts', import.meta.url)),
	'$app/state': fileURLToPath(new URL('./tests/stubs/app-state.ts', import.meta.url)),
	// SELF-235: SymbolClassifyRow.svelte is the first dom-tested component to import
	// `use:enhance` from `$app/forms` — likewise unresolvable without `svelte-kit sync`. Same
	// stub convention as the other `$app/*` aliases above.
	'$app/forms': fileURLToPath(new URL('./tests/stubs/app-forms.ts', import.meta.url))
};

// Discovery excludes shared by both projects.
const baseExclude = ['node_modules/**', 'build/**', '.svelte-kit/**'];

export default defineConfig({
	test: {
		projects: [
			{
				// ── node: pure-TS server + `svelte/server` SSR-render tests ──────────────
				// @sveltejs/vite-plugin-svelte (already-installed; pulled by the SvelteKit
				// plugin) so `.svelte` imports compile for SSR render. Server resolution.
				plugins: [svelte()],
				resolve: { alias },
				test: {
					name: 'node',
					environment: 'node',
					// SELF-358 / P6 — see this file's own header (vitest#10788).
					css: true,
					include: ['src/**/*.{test,spec}.ts', 'tests/**/*.{test,spec}.ts'],
					// The DOM project owns *.dom.test.ts — keep them out of the node project.
					exclude: [...baseExclude, 'src/**/*.dom.test.ts']
				}
			},
			{
				// ── jsdom: DOM component-interaction tests (*.dom.test.ts) ────────────────
				// svelteTesting() adds `browser` before `node` in resolve.conditions (Svelte's
				// browser build for mount) + a DOM auto-cleanup setup file. SCOPED here only.
				plugins: [svelte(), svelteTesting()],
				resolve: { alias },
				test: {
					name: 'dom',
					environment: 'jsdom',
					include: ['src/**/*.dom.test.ts'],
					exclude: baseExclude
				}
			}
		]
	}
});
