// route-module-export-allowlist.server.test.ts — SELF-264/266 hotfix watcher (QA live walk:
// GET /taxes/decomposition 500'd on every request — "Invalid export
// 'INVENTORY_SEED_DELTA_MIGRATION' in src/routes/taxes/decomposition/+page.server.ts (valid
// exports are load, prerender, csr, ssr, trailingSlash, config, actions, entries, or anything
// with a '_' prefix)"). SvelteKit's route-module loader validates every export of a route module
// at REQUEST time against its own allowlist and throws (500) on anything outside it. Neither
// `svelte-check` nor a normal vitest run exercises that validator — a route module can carry a
// stray value export and the rest of the suite stays green while the route is dead. This file is
// the missing watcher: eagerly import every route module under src/routes and assert every
// exported NAME is allowlisted, so this class cannot recur silently again.
//
// `export type X = {...}` is erased by esbuild before this glob's eager import ever runs (Vite
// strips type-only exports at compile time) — it never becomes a key on the runtime module
// object, so this test correctly never flags a type export. Only VALUE exports reach the module
// object at runtime, which is exactly what SvelteKit's own validator inspects — this test's
// predicate mirrors that validator's, not a broader one.
//
// Extended per Sec N-7 (SELF-264/266 review, docs/records/v14-execution/self264-266-sec-findings.md):
//
// N-7(a) — every leg below this file originally had asserted `[]` against a tree that ALREADY
// satisfied the predicate, so nothing proved the predicate itself could go RED. The filter is now
// a named exported function (`disallowedExportNames`), and the last `describe` block below applies
// it directly to a synthetic module object rather than to anything under src/routes.
//
// N-7(b) — the glob covered only `+page.server.ts`. `+layout.server.ts` and `+server.ts` carry
// their OWN, narrower SvelteKit allowlists and 500 at request time on a stray export exactly the
// same way — a stray export on the ROOT `+layout.server.ts` is worse than one on a single page,
// since it kills every route in the tree, not one. All three allowlists below are copied verbatim
// from `node_modules/@sveltejs/kit/src/utils/exports.js` (`valid_page_server_exports` /
// `valid_layout_server_exports` / `valid_server_exports`) at this sha — read live, not recalled —
// rather than from SvelteKit's docs, since the source is the actual runtime validator this watcher
// exists to pre-empt.

import { describe, it, expect } from 'vitest';

/** SvelteKit's `valid_page_server_exports` (`exports.js`) — `+page.server.ts`'s own allowlist. */
const PAGE_SERVER_ALLOWED_EXPORTS = new Set([
	'load',
	'prerender',
	'csr',
	'ssr',
	'trailingSlash',
	'config',
	'actions',
	'entries'
]);

/**
 * SvelteKit's `valid_layout_server_exports` (`exports.js`) — `+layout.server.ts`'s own allowlist.
 * Deliberately NARROWER than `+page.server.ts`'s: no `actions`, no `entries` — a layout cannot own
 * form actions or prerender-entry generation, only a page/leaf can.
 */
const LAYOUT_SERVER_ALLOWED_EXPORTS = new Set(['load', 'prerender', 'csr', 'ssr', 'trailingSlash', 'config']);

/** SvelteKit's `valid_server_exports` (`exports.js`) — `+server.ts`'s own allowlist (HTTP verbs, not `load`). */
const SERVER_ALLOWED_EXPORTS = new Set([
	'GET',
	'POST',
	'PUT',
	'PATCH',
	'DELETE',
	'OPTIONS',
	'HEAD',
	'fallback',
	'prerender',
	'trailingSlash',
	'config',
	'entries'
]);

/**
 * N-7(a) — the predicate itself, extracted to a named export so it can be exercised directly
 * against a SYNTHETIC module (see the last `describe` block below), not only against a tree that
 * already satisfies it. Mirrors SvelteKit's own validator (`exports.js`'s `validate`): a
 * `_`-prefixed name is always exempt (SvelteKit's own escape for private helpers colocated in a
 * route module), anything else must be in `allowed`.
 */
export function disallowedExportNames(
	moduleObject: Record<string, unknown>,
	allowed: Set<string>
): string[] {
	return Object.keys(moduleObject).filter((name) => !allowed.has(name) && !name.startsWith('_'));
}

/** One `describe` block per route-module shape: not-silently-empty guard, then one leg per module. */
function describeAllowlistedTree(
	label: string,
	modules: Record<string, Record<string, unknown>>,
	allowed: Set<string>
) {
	describe(label, () => {
		const paths = Object.keys(modules).sort();

		it(`discovered at least one module (glob is not silently empty)`, () => {
			expect(paths.length).toBeGreaterThan(0);
		});

		for (const path of paths) {
			it(`${path} has no export outside the allowlist`, () => {
				expect(disallowedExportNames(modules[path], allowed)).toEqual([]);
			});
		}
	});
}

const pageServerModules = import.meta.glob('/src/routes/**/+page.server.ts', {
	eager: true
}) as Record<string, Record<string, unknown>>;

const layoutServerModules = import.meta.glob('/src/routes/**/+layout.server.ts', {
	eager: true
}) as Record<string, Record<string, unknown>>;

const serverModules = import.meta.glob('/src/routes/**/+server.ts', {
	eager: true
}) as Record<string, Record<string, unknown>>;

describeAllowlistedTree(
	'+page.server.ts route modules export only SvelteKit-allowlisted names',
	pageServerModules,
	PAGE_SERVER_ALLOWED_EXPORTS
);

describeAllowlistedTree(
	'+layout.server.ts route modules export only SvelteKit-allowlisted names',
	layoutServerModules,
	LAYOUT_SERVER_ALLOWED_EXPORTS
);

describeAllowlistedTree(
	'+server.ts route modules export only SvelteKit-allowlisted names',
	serverModules,
	SERVER_ALLOWED_EXPORTS
);

describe('disallowedExportNames — N-7(a): the predicate itself can go RED', () => {
	// Applied against the REAL PAGE_SERVER_ALLOWED_EXPORTS constant (not a copy) — this is the
	// exact leg N-7(a) names: a boundary pair one step apart (`load` allowlisted, `STRAY` not),
	// which would also red on its own if this constant were ever loosened to include 'STRAY'.
	it('flags a stray export on a synthetic module, leaving the allowlisted export alone', () => {
		expect(disallowedExportNames({ load: 1, STRAY: 2 }, PAGE_SERVER_ALLOWED_EXPORTS)).toEqual([
			'STRAY'
		]);
	});

	it('does not flag a `_`-prefixed export, mirroring SvelteKit\'s own escape', () => {
		expect(disallowedExportNames({ load: 1, _internal: 2 }, PAGE_SERVER_ALLOWED_EXPORTS)).toEqual(
			[]
		);
	});
});
