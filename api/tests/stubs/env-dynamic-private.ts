// tests/stubs/env-dynamic-private.ts
//
// Test-only stand-in for SvelteKit's `$env/dynamic/private` virtual module. The
// standalone api/ vitest harness (vitest.config.ts) does NOT run `svelte-kit sync`,
// so the virtual module is unavailable; server modules that read runtime private env
// (e.g. src/lib/server/plaid/admissionClient.ts) are aliased to this stub under test.
//
// Backed by process.env so a spec can vary values per-case (set process.env before
// the module reads it, and call the module's __resetConfigForTests() to clear any
// memoized config). Never used in the real build — the SvelteKit plugin supplies the
// genuine virtual module there.

// `process` resolves via @types/node (api devDependency; the extended tsconfig has no
// `types` allowlist, so all @types/* auto-include). The former local `declare const
// process` shim is removed — @types/node is the proper harness fix (DevOps, OQ-3).
export const env = new Proxy({} as Record<string, string | undefined>, {
	get: (_target, key) => (typeof key === 'string' ? process.env[key] : undefined)
});
