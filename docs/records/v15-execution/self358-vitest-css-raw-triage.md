# Triage: `.css?raw`/`?inline` → empty string under vitest `node` project

Reported by Backend at `api/src/routes/reports/monthly/[target_month]/pdf/pdf.css-inline.test.ts` header. Triage only — no pin changed.

**Known upstream issue, and it's Vitest's, not Vite's.** vitest-dev/vitest#10788: with the default `test.css: false`, Vitest's own `vitest:css-disable` pre-transform short-circuits to `{ code: "" }` before Vite's `?raw`/`?inline` raw-asset handling ever runs — `vitest:css-empty-post` then emits `export default ""`. Reproduced upstream on vitest 3.2.4, 4.1.9, **and 4.1.10** (this repo's resolved version) — it is default-config behavior across the whole line, not a regression a bump would clear.

**Pins:** `vitest: ^4.1.0` resolves to `4.1.10` (already the version the upstream issue reproduces on) — **no vitest bump fixes this.** `vite: ^8.0.16`→`8.1.3` and `@sveltejs/vite-plugin-svelte: ^7.1.2`→`7.1.2` are uninvolved; the defect is in vitest's CSS-handling plugin layer, not theirs.

**The fix is a config change, not a pin:** set `test.css: true` (repo-wide or scoped to the `node` project in `api/vitest.config.ts`) so Vitest's raw-pipeline stops short-circuiting before Vite's own `?raw`/`?inline` handling.

**`npm run dev` does NOT share this path** — verified live: spun up a real `vite` dev server (`createServer` + `ssrLoadModule`, no vitest in the loop) against a throwaway module importing `report.css?raw`; it returned the full 37,352-byte real content, not empty. The test header's guess that this is Vite's own `serve`-command `vite:css-post` transform is not what's firing here — the empty-string path is specific to vitest's css-disable plugins, which only exist inside the vitest runner. `vite build` (already verified clean by Backend) and `vite dev` both resolve `?raw` correctly; only the vitest `node` project is affected.
