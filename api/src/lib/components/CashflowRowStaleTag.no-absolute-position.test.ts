// CashflowRowStaleTag.no-absolute-position.test.ts — SOURCE-LEVEL BY NECESSITY (mirrors
// asOfBrand.invariant.test.ts's own framing, api/src/lib/server/queries/asOfBrand.invariant.test.ts):
// jsdom applies ZERO CSS in this repo's `.dom.test.ts` harness — verified empirically before
// writing this file: a rendered component's own `<style>` block never reaches
// `document.querySelectorAll('style')` (it returns an empty NodeList), and `getComputedStyle` on
// any rendered element returns the browser's INITIAL values regardless of what the component's
// `<style>` block declares. There is therefore no RUNTIME observation, from a `.dom.test.ts`, that
// would catch a `position: absolute` regression on this panel — this is exactly the class
// asOfBrand.invariant.test.ts names: a property of the code's SHAPE, not its behaviour.
//
// WHY THIS MATTERS (QA's SELF-258 live walk, 2026-09-03): `.row-stale-panel` was originally
// `position: absolute`, floating OUTSIDE normal flow. It sits inside CashflowRollupTable's
// `.table-scroll` wrapper, whose `overflow-x: auto` also computes `overflow-y` as `auto` (the CSS
// "one axis non-visible forces both" rule) — and CSS overflow clipping binds ANY
// absolutely-positioned descendant to the nearest scrolling ancestor's content box regardless of
// z-index. The stale account name (`<ul class="row-stale-list">`) and the Re-authenticate link
// were present in the DOM/a11y tree (QA's `read_page` saw them) but never visible to a sighted
// mouse user — a real, reproducible defect a `.dom.test.ts` presence assertion cannot see, since
// presence didn't change; only visual layout did.
//
// FIX: the panel is now NORMAL-FLOW — the SAME shape StaleConstituentBadge's own `.stale-panel`
// already uses (no `position` override at all: it is a flex-column sibling of the toggle button,
// not a floating overlay). Normal-flow content can never escape its ancestor's box the way an
// absolutely-positioned element can, so it can never be invisibly clipped by an `overflow: auto`
// wrapper — opening it simply grows the table row's own height (and the already-scrollable
// `.table-scroll` container, which is exactly what an `overflow: auto` wrapper is FOR). This
// watcher pins that shape at the SOURCE level, the only level available to catch it.
//
// @vitest-environment node

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const SOURCE = readFileSync(
	fileURLToPath(new URL('./CashflowRowStaleTag.svelte', import.meta.url)),
	'utf8'
);

// Match executable CSS text only, never prose ABOUT the rule — asOfBrand.invariant.test.ts's own
// `code()` helper caught itself matching its own header comment on its first run (the header
// literally names the pattern it checks for), and this file's first run caught the SAME trap a
// second time: CashflowRowStaleTag.svelte's own `<style>` block carries an explanatory CSS
// comment (right above `.row-stale-panel`) that names the old `position: absolute` value in
// PROSE, as part of documenting why it was removed — a naive slice-and-match on the raw
// `<style>...</style>` text still matched THAT sentence and stayed red after the real fix landed.
// `code()` strips CSS `/* ... */` comments before matching, same as asOfBrand.invariant.test.ts's
// own helper strips `//`/`/* */` from TS — match executable declarations only.
const code = (css: string) => css.replace(/\/\*[\s\S]*?\*\//g, '');
const styleBlock = code(SOURCE.slice(SOURCE.indexOf('<style>'), SOURCE.lastIndexOf('</style>')));

describe('CashflowRowStaleTag — the disclosure panel is never absolutely positioned (SELF-258 clipping regression watcher)', () => {
	// PRECONDITION (DESIGN.md rule 3 / asOfBrand.invariant.test.ts's own precedent): asserted
	// separately from the real assertion below. If the file move, get renamed, or the `<style>`
	// tag disappears, the walk finds nothing and the assertion below would pass VACUOUSLY over an
	// empty string — silently, not loudly.
	it('the source walk actually found a non-trivial <style> block naming the panel class', () => {
		expect(styleBlock.length).toBeGreaterThan(100);
		expect(styleBlock).toContain('.row-stale-panel');
	});

	it('neither .row-stale-marker nor .row-stale-panel declares `position: absolute` (or `fixed`) anywhere in the component', () => {
		// Widened past the literal defect (Sec, SELF-258 AMBER round): `fixed` escapes an ancestor's
		// overflow clip the SAME way `absolute` does (both are taken out of normal flow relative to
		// a positioned/viewport context rather than participating in the ancestor's own content
		// box) — a future author "fixing" a different symptom by reaching for `position: fixed`
		// would reintroduce the SAME class of invisible-content defect this file exists to catch,
		// not a new one.
		expect(styleBlock).not.toMatch(/position:\s*(absolute|fixed)/i);
	});
});
