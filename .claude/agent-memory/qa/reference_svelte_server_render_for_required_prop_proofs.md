---
name: svelte-server-render-for-required-prop-proofs
description: Use svelte/server's render() (not @testing-library/svelte's) to prove a component's required prop is actually required at compile time; and the @ts-expect-error literal-marker-uniqueness gotcha that goes with it.
metadata:
  type: reference
---

`@testing-library/svelte`'s `render()` type signature is a union `ComponentOptions<C> = Props<C> | Partial<MountOptions<C>>` (see `node_modules/@testing-library/svelte-core/types.d.ts`). The `Partial<MountOptions<C>>` branch tolerates an omitted `props` object regardless of the component's own required-prop shape — so a `@ts-expect-error` leg written against THAT `render()`, mounting with `{ props: {} }` to prove a required prop is enforced, reports "Unused '@ts-expect-error' directive" even when the prop genuinely has no default. It's a real gap in that library's types, not a mistake in the leg's intent.

`svelte/server`'s `render()` does NOT have this hole — it correctly flags missing required props. Use it (a `// @vitest-environment node` file, not the usual jsdom `.dom.test.ts` idiom) for any "the compiler is the watcher" / required-prop-enforcement proof.

Second, compounding gotcha found while debugging the above: TypeScript's `@ts-expect-error` scanner can misattribute "Unused" even on a genuinely-suppressed error if the literal string `@ts-expect-error` appears MORE THAN ONCE in the same file (e.g. once as the real directive, again in a nearby header comment discussing the directive in prose). The fix is mechanical: the exact marker string must appear EXACTLY ONCE in the file. Word around it in any explanatory prose ("the directive", "the suppression comment") rather than repeating the literal token.

See `StaleConstituentBadge.type-contract.test.ts` (SELF-229 Sec F3(B) watcher leg) for a worked, verified example of both fixes together.
