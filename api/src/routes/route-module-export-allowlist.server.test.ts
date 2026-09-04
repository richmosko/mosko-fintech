// route-module-export-allowlist.server.test.ts — SELF-264/266 hotfix watcher (QA live walk:
// GET /taxes/decomposition 500'd on every request — "Invalid export
// 'INVENTORY_SEED_DELTA_MIGRATION' in src/routes/taxes/decomposition/+page.server.ts (valid
// exports are load, prerender, csr, ssr, trailingSlash, config, actions, entries, or anything
// with a '_' prefix)"). SvelteKit's route-module loader validates every export of a
// `+page.server.ts` at REQUEST time against its own allowlist and throws (500) on anything
// outside it. Neither `svelte-check` nor a normal vitest run exercises that validator — a
// route module can carry a stray value export and the rest of the suite stays green while the
// route is dead. This file is the missing watcher: eagerly import every `+page.server.ts`
// under src/routes and assert every exported NAME is allowlisted, so this class cannot recur
// silently again.
//
// `export type X = {...}` is erased by esbuild before this glob's eager import ever runs (Vite
// strips type-only exports at compile time) — it never becomes a key on the runtime module
// object, so this test correctly never flags a type export. Only VALUE exports reach the
// module object at runtime, which is exactly what SvelteKit's own validator inspects — this
// test's predicate mirrors that validator's, not a broader one.

import { describe, it, expect } from 'vitest';

/** SvelteKit's own +page.server.ts route-module export allowlist. */
const ALLOWED_EXPORTS = new Set([
	'load',
	'prerender',
	'csr',
	'ssr',
	'trailingSlash',
	'config',
	'actions',
	'entries'
]);

const modules = import.meta.glob('/src/routes/**/+page.server.ts', { eager: true }) as Record<
	string,
	Record<string, unknown>
>;

describe('+page.server.ts route modules export only SvelteKit-allowlisted names', () => {
	const paths = Object.keys(modules).sort();

	it('discovered at least one +page.server.ts module (glob is not silently empty)', () => {
		expect(paths.length).toBeGreaterThan(0);
	});

	for (const path of paths) {
		it(`${path} has no export outside the allowlist`, () => {
			const disallowed = Object.keys(modules[path]).filter(
				(name) => !ALLOWED_EXPORTS.has(name) && !name.startsWith('_')
			);
			expect(disallowed).toEqual([]);
		});
	}
});
