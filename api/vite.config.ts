import adapter from '@sveltejs/adapter-node';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [
		sveltekit({
			compilerOptions: {
				// Force runes mode for the project, except for libraries. Can be removed in svelte 6.
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},

			// adapter-node: the web-app deploys as a small Node server in its Coolify
			// container on cax21 (per api/CLAUDE.md + ARCH §5 / Lock 13 3-container topology).
			// Emits a runnable `build/` server; container entrypoint is `node build`.
			adapter: adapter(),

			// ── APP-GLOBAL strict CSP (ADR-028 CSP-1/CSP-2) ────────────────────────────
			// This is the STRICT BASE policy for EVERY route — it carries NO Plaid origin.
			// `mode: 'nonce'` makes SvelteKit mint a per-response nonce and stamp it on the
			// scripts/styles it injects (so `script-src 'self'` doesn't break hydration) —
			// that satisfies CSP-2 (nonce, never 'unsafe-inline' on script-src).
			// In SSR, SvelteKit emits this as the `content-security-policy` RESPONSE HEADER;
			// the Plaid connect route ALONE is widened to the ADR-028 blessed set by the
			// `hooks.server.ts` handle (see src/lib/plaid/csp.ts `applyPlaidConnectCsp`).
			// Keep Plaid origins OUT of here — an app-global Plaid relaxation is a Sec veto.
			//
			// No browser-side third-party fetch exists today (all data is SSR via
			// +page.server.ts; no browser Supabase client; fonts are system-stack, self-
			// hosted). If a browser-side Supabase client or external font is ever added, its
			// origin must be allowlisted HERE (global connect-src / font-src), not per-route.
			csp: {
				mode: 'nonce',
				directives: {
					'default-src': ['self'],
					'script-src': ['self'],
					'style-src': ['self'],
					'style-src-elem': ['self'],
					'style-src-attr': ['none'],
					'img-src': ['self', 'data:'],
					'font-src': ['self'],
					'connect-src': ['self'],
					'frame-src': ['self'],
					'object-src': ['none'],
					'base-uri': ['self'],
					'form-action': ['self'],
					'frame-ancestors': ['none']
				}
			}
		})
	]
});
