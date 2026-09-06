---
name: sveltekit-head-passthrough-defeats-css-injected
description: SvelteKit nonces only the style IT emits; a Svelte `css:'injected'` <style> reaches the browser un-nonced and is CSP-blocked under style-src 'self' — silently, because the linked chunk still applies.
metadata:
  type: reference
---

`render()` from `svelte/server` emits **zero** component-scoped CSS by default — `head` empty, `body`
carrying `.svelte-XXXXXX` markers with nothing defining them. The tempting one-line fix is Svelte's
`css: 'injected'` compiler option (reachable per-file via `dynamicCompileOptions`, a public typed API
in `@sveltejs/vite-plugin-svelte` 7.x — and this repo's `vite.config.ts` already uses a
function-valued `compilerOptions.runes`, so per-file divergence has precedent).

**It does not work here, and the failure is silent.** Measured 2026-09-06 at
`@sveltejs/kit` 2.63 / svelte 5.56:

- `src/runtime/server/page/render.js:302` — `new Head(rendered.head, …)`: the component's head
  payload is passed through **verbatim**.
- The CSP nonce is attached **only** to the style element Kit itself emits (`render.js:325–327`).
- `rendered.css` **is** destructured from the root render at `render.js:264` and then **never used**.
- `api/vite.config.ts` sets `csp: { mode:'nonce', 'style-src': ['self'], 'style-src-attr': ['none'] }`
  and leaves `kit.inlineStyleThreshold` unset, so today every stylesheet is a `<link>` and there is
  no inline style anywhere.

⇒ an injected `<style>` is CSP-blocked on every SSR page load, with a console violation — but the
page still **looks correct**, because the linked CSS chunk applies anyway. A visual check cannot see
this. Only the console (or `style-src` reasoning) can.

**Why it cannot be scoped to one route.** The PDF endpoint and the SSR page share the same server
build. A query-suffixed import (`Foo.svelte?pdf`) does not propagate the suffix to child components,
which compile once. Per-route `css:'injected'` is not achievable with this toolchain.

**Ruled alternative (SELF-358 / P6):** a build-time Vite lib build over the component tree emitting
one plain CSS file, inlined by the server route via `?raw`. ⚠ Its own hazard: `body` comes from the
SvelteKit server build while the CSS comes from a separate build — if the `.svelte-XXXXXX` hashes
ever diverge the output is **fully unstyled and symptom-identical to the original bug**, while every
value assertion still passes. The catching leg: extract every `svelte-[a-z0-9]+` token from the
rendered body, assert each matches ≥1 selector in the extracted CSS. Related:
[[feedback_layers_green_seam_absent]], [[feedback_a_check_i_ran_is_not_a_check_that_exists]].
