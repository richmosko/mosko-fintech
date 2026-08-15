// StaleConstituentBadge.type-contract.test.ts — Sec F3(B) watcher (AMBER round, F/CTO-ruled
// option B, landed 0d6dc2c): isStale/staleItems lost their default and became REQUIRED props.
// Sec's ask verbatim: "a leg (or documented reliance on svelte-check failing) proving a mount
// WITHOUT the prop cannot pass the gate — the compiler is the watcher, verify it actually fails."
//
// This is deliberately NOT a runtime assertion — the component happens to render nothing for
// `undefined` props today (same output as the healthy case), which is exactly why a runtime
// check here would be worthless: it can't distinguish "correctly required" from "silently
// defaulted." The type layer is the only fence that can, so svelte-check IS the assertion.
//
// MECHANISM NOTE (found the hard way while authoring this): `@testing-library/svelte`'s own
// `render()` type signature tolerates an omitted `props` object regardless of the component's
// required-prop shape (its ComponentOptions union has a `Partial<MountOptions<C>>` branch) — so
// a `@ts-expect-error` leg written against THAT render would report "Unused" even on a genuinely
// required prop. `svelte/server`'s `render()` does not have this hole, hence the node-env import
// below instead of the DOM-test idiom used elsewhere in this file's siblings.
//
// SECOND MECHANISM NOTE: the literal marker string TypeScript's scanner looks for must appear
// EXACTLY ONCE in this file as the real suppression comment. This paragraph avoids repeating it —
// see the single occurrence directly above the render() call below.

// @vitest-environment node
import { describe, it } from 'vitest';
import { render } from 'svelte/server';
import StaleConstituentBadge from './StaleConstituentBadge.svelte';

describe('StaleConstituentBadge — Sec F3(B): staleness props are REQUIRED; the compiler is the watcher', () => {
	it('⭐ mounting WITHOUT isStale/staleItems is a compile error — the type layer is the assertion, not a runtime check', () => {
		// @ts-expect-error — F3(B): isStale and staleItems have NO default; omitting them must fail
		// svelte-check. This comment's own "unused directive" failure mode IS the fence against a
		// future regression that quietly re-adds a default (see the module header for why this is
		// the file's only such comment). No runtime assertion follows — see the header for why.
		render(StaleConstituentBadge, { props: {} });
	});
});
