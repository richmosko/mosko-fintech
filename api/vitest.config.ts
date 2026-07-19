// api/vitest.config.ts
//
// OQ-3 — api/ test harness (SELF-212 build support). Stands up Vitest as the api/
// test runner so Frontend's SELF-198 tests, the forthcoming Option-C relay-leg
// tests, and QA's api-tier tests have a runnable target (they were authored
// against the Vitest API but api/ had no runner).
//
// DELIBERATELY STANDALONE (does NOT import vite.config.ts / the SvelteKit plugin):
// keeping the runner decoupled from the SvelteKit Vite plugin means pure-TS server
// tests (src/lib/server/**, hooks, relay legs) run without requiring `svelte-kit
// sync` / a browser env. Default environment = node.
//
// DOM/COMPONENT TESTS (follow-up — needs team-lead sign-off before dep-add):
// Svelte-component tests (e.g. some SELF-198 UI specs) will need a DOM environment
// (`jsdom` or `happy-dom`) + `@testing-library/svelte` as ADDITIONAL devDeps, which
// are BEYOND the sanctioned "test runner only" footprint. Those are optional Vitest
// peers (not pulled by vitest itself). Until they land, a component spec can opt in
// per-file with a `// @vitest-environment jsdom` docblock once the dep is added.
// Flagged to team-lead — do not add jsdom/testing-library without approval.

import { defineConfig } from 'vitest/config';
import { fileURLToPath } from 'node:url';

export default defineConfig({
	// Minimal alias resolution so pure-TS SERVER tests (the Option-C relay legs — this
	// config's stated target) can import via the app's `$lib` convention and stub the
	// SvelteKit `$env/dynamic/private` virtual module (unavailable without svelte-kit
	// sync). These aliases are TEST-ONLY; the real build resolves them via the
	// SvelteKit Vite plugin. `import type ... from './$types'` needs NO alias (erased).
	resolve: {
		alias: {
			$lib: fileURLToPath(new URL('./src/lib', import.meta.url)),
			'$env/dynamic/private': fileURLToPath(
				new URL('./tests/stubs/env-dynamic-private.ts', import.meta.url)
			)
		}
	},
	test: {
		// Node env: server-logic / relay-leg / util tests. Component tests override
		// per-file via `// @vitest-environment jsdom` once the DOM dep is approved.
		environment: 'node',
		// Colocated (src/**/*.test.ts) + a dedicated tests/ tree.
		include: ['src/**/*.{test,spec}.ts', 'tests/**/*.{test,spec}.ts'],
		// Exclude build artifacts + SvelteKit's generated dir from test discovery.
		exclude: ['node_modules/**', 'build/**', '.svelte-kit/**']
	}
});
