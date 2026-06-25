# `web/` — scoped context for Claude Code

> **Per-directory `CLAUDE.md`** (WORKFLOW.md Phase 5 Step 5). Scoped conventions for working inside `web/`. The root [`CLAUDE.md`](../CLAUDE.md) + canonical artifacts ([ARCH](../docs/ARCH/index.html) · [SECURITY](../docs/SECURITY/index.html) · [DECISIONS](../DECISIONS.md) · [DESIGN](../docs/DESIGN/)) stay source-of-truth; this file is the surface-local quick reference. **Forward-looking — `web/` is scaffolded in Phase 6 (SvelteKit); these conventions are locked now and get a light refine at scaffold time.**

**Owner role:** Frontend Engineer. Per WORKFLOW.md Agent Roster.

## What lives here
The SvelteKit V1 web-app — **browser-shipped (non-`server`) source only**:

- `src/routes/**/+page.svelte`, `+layout.svelte` — route-level UI.
- `src/lib/components/**` — reusable UI primitives (component inventory in [design-system-spec.md](../docs/DESIGN/design-system-spec.md) §4).
- `src/lib/**` (non-`server`) — browser-side state (Svelte 5 runes), formatters, client-side Zod validators.
- `src/app.html`, `static/**` — shell + static assets.

**NOT yours — never touch from here:** `*.server.ts` / `*.server.js`, `src/lib/server/**`, `src/routes/**/+server.ts`, `+page.server.ts`, `+layout.server.ts`, `hooks.server.ts`. Those are **Backend's** server-source surfaces ([ARCH §4.1](../docs/ARCH/index.html#sec-4-1) allowlist glob `src/routes/**/+server.ts`). You **consume** their exports via SvelteKit's `data` prop / form-action interface; you do not author them.

## Conventions
- **Tokens only, via `var(--c-*)`.** Consume the locked two-tier token system ([tokens.css](../docs/DESIGN/tokens.css) / [ADR-014](../DECISIONS.md#adr-014) Decision 3). Semantic aliases: `--c-canvas` / `--c-surface[-alt|-alt2]` / `--c-border[-strong]` / `--c-text-{primary|secondary|muted}` / `--c-accent[-hover|-active|-soft|-tint]` / `--c-accent-2` / `--c-attn-{solid|text|bg|border}` / `--c-pos` / `--c-neg` / `--c-viz-{nominal|infl|fill}`; spacing `--space-0..7`; radius `--radius-{sm|md|lg|pill}`; type `--fs-*` / `--font-{ui|num}` / `--weight-*`; elevation `--shadow-1..3` / `--focus-ring`. **Never hardcode** a hex / px-spacing / font value inline — a raw value in a `.svelte` file is an [ADR-013](../DECISIONS.md#adr-013)-P5-class design-system violation.
- **`--c-pos` / `--c-neg` fence:** value-color is scoped to ACTUAL performance only (NAV Δ, unrealized G/L). Never on `$ReAlloc` / `%Target` / target captions ([design-system-spec.md](../docs/DESIGN/design-system-spec.md) §5 fence 1). Attention hue (`--c-attn-*`, canary) is reserved for staleness/re-auth only — never decoration, never a value.
- **No inline editing of planning values** ([ADR-013](../DECISIONS.md#adr-013) Decision 7 / P5). The four user-authored planning values (§2.2 `%Target`, §2.3.2 income/expense targets, §2.5.2 tax brackets, §2.6 owner-id) are **read-only on data surfaces**; editing lives ONLY in the Settings `planning-target-editor`. `target-sum-readout` is informational — never an alert, never blocks save.
- **Client-side Zod `.strict()` mirrors Backend.** Every form mirrors Backend's server-side `.strict()` + numeric-sanitization schema (Lock 14). Client check = UX fast-feedback; **server check is the security boundary**. Never ship a client schema looser than the server's; when Backend updates the schema, you update the mirror (Backend owns the source of truth).
- **Forms go through SvelteKit form actions** (`<form method="POST">` + `+page.server.ts` `actions`). `fetch`+JSON only for genuinely client-initiated ops (chart-axis toggle, sort-order change).
- **Boring Svelte 5.** Runes (`$state` / `$derived` / `$effect`) over store hacks; data-loader `data` prop over client fetch when the data is server-known at render time. Novel UI / new component patterns / chart-lib choices → present 2–3 options + route to Visual Designer; don't invent.
- **Accessibility is a discipline, not polish.** Every interactive element: label, focus state (`--focus-ring`), keyboard path, ARIA role where needed.

## Staleness-marker framework ([ADR-013](../DECISIONS.md#adr-013) D1 · PRD §2.4.4)
**Silent staleness is a V1 ship-block.** Every derived aggregation that consumes data from an account pending re-auth must visually mark the stale contribution — D1 is illustrative-not-exhaustive (the enumerated list is a floor, not a ceiling). Surfaces include: NW trajectory + composition table, allocation table, cash-flow rollup + Historical Expenditures chart, tax tables, monthly-report sections, headline NAV / delta panel / `nav-asof` reference dates.

Two distinct canary-hued signals, kept separate ([design-system-spec.md](../docs/DESIGN/design-system-spec.md) §5 fences 2–3, 7):
- **`stale-data-marker` (D1):** inline `.stale-tag` + faint row tint on the aggregation surface. **Never hides the value.** `--c-attn-{solid|bg|text}`.
- **`reauth-staleness-banner` (P4):** full-width top-chrome bar — conditional (zero footprint when healthy), persistent, **non-dismissible**; institution-down variant has no CTA.

Keep these distinct from the third signal — `freshness-stamp` (materialization recency; quiet `--c-text-muted`). The "when is stale?" *semantic* is **Backend's** (you render it); per-surface *visual treatment* with >1 defensible shape → **Visual Designer**.

## Canonical references
- [DESIGN](../docs/DESIGN/) — locked design system: [tokens.css](../docs/DESIGN/tokens.css), [screen.css](../docs/DESIGN/screen.css), [design-system-spec.md](../docs/DESIGN/design-system-spec.md) (component inventory §4 + load-bearing fences §5), `index.html` visual proof, `wireframes/`, `flows/`.
- [ADR-014](../DECISIONS.md#adr-014) — design-system foundation + two-tier tokens + `docs/DESIGN/` home.
- [ADR-013](../DECISIONS.md#adr-013) — D1 staleness-marking (Decision 1) · P5 no-inline-edit (Decision 7) · INV-1 plain-text commentary (Consequences).
- [ARCH §4.1](../docs/ARCH/index.html#sec-4-1) — server-source surface allowlist (your *exclusion* list).
- [SECURITY §4.1–§4.2](../docs/SECURITY/index.html#sec-4-1) — tenant-isolation + credential posture (the browser boundary you keep server code out of).

## Fail-closed / gotchas
- **Forward-looking file.** `web/` is scaffolded in Phase 6; exact SvelteKit paths above are confirmed at scaffold time and this file gets a light refine then.
- **Never import secrets into browser code.** No `src/lib/server/**`, no `$env/static/private`, no `$env/dynamic/private` from any surface here — these ship to the browser; a leaked `SUPABASE_SERVICE_ROLE_KEY` from a stray import is an [ARCH §4.1](../docs/ARCH/index.html#sec-4-1) / RT-26 violation. SvelteKit's compiler refuses the build, but the discipline is yours. Public config via `$env/static/public` / `$env/dynamic/public` is fine.
- **INV-1 plain-text invariant** ([ADR-013](../DECISIONS.md#adr-013) Consequences / [design-system-spec.md](../docs/DESIGN/design-system-spec.md) §5 fence 4). User-authored free-text (monthly-report commentary, owner-id) renders as **plain text** — no rich-text/markdown/HTML affordance in the editor or the render path. Rich-text is a V1 security-surface expansion requiring a Sec re-touch (RT-11 / RT-12), NOT a harmless refinement.
- **API contracts are Backend's source of truth.** When a response/request shape changes, coordinate at the boundary — don't unilaterally re-derive it.
