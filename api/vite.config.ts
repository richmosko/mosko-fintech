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
			adapter: adapter()
		})
	]
});
