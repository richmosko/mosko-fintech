# `api/` — scoped context for Claude Code

> **Per-directory `CLAUDE.md`** (WORKFLOW.md Phase 5 Step 5). Scoped conventions for working inside `api/`. The root [`CLAUDE.md`](../CLAUDE.md) + canonical artifacts ([ARCH](../docs/ARCH/index.html) · [SECURITY](../docs/SECURITY/index.html) · [DECISIONS](../DECISIONS.md) · [DESIGN](../docs/DESIGN/)) stay source-of-truth; this file is the surface-local quick reference. **Scaffolded in Phase 6 (SELF-185 — SvelteKit + Svelte 5 + Vite + TS, adapter-node).**

**Owner roles:** **Backend Engineer** (server-source surfaces — see [§Backend conventions](#conventions) below) **and** **Frontend Engineer** (browser-shipped non-`server` surfaces — see [§Frontend Engineer — browser-shipped surfaces](#frontend-engineer--browser-shipped-surfaces) below). Per WORKFLOW.md Agent Roster. The SvelteKit app is a single `src/` tree, so **both roles work inside `api/`** (F/CTO-ratified `web/`→`api/` fold, SELF-185). The server/browser split is by **file-glob** ([ARCH §4.1](../docs/ARCH/index.html#sec-4-1) allowlist), not by directory: anything matching `*.server.ts` / `src/lib/server/**` / `+server.ts` is Backend's; everything else ships to the browser and is Frontend's.

## What lives here

The V1 web-app container — **SvelteKit (Svelte 5)** per [ADR-015](../DECISIONS.md#adr-015) — the third container in the [Lock 13](../DECISIONS.md#adr-011) 3-container topology. Built via Vite; deployed as a small Node server in its Coolify container on cax21. Backend's scope is the **server-source surfaces only**; everything else ships to the browser and belongs to Frontend.

## Conventions

- **Server-source surface allowlist** ([ARCH §4.1](../docs/ARCH/index.html#sec-4-1) — the canonical file-glob enumeration, locked at framework ratify; SECURITY §4.1 is tenant-isolation *posture*, not the allowlist): server code lives ONLY in `src/routes/**/+server.ts`, `src/routes/**/+page.server.ts`, `src/routes/**/+layout.server.ts`, `src/hooks.server.ts`, and `src/lib/server/**/*.ts` (Vite-enforced server-only modules). **Never** put server logic in `+page.svelte` / `+layout.svelte` / `src/lib/components/` / `src/lib/**` (non-`server`) — those ship to the browser.
- **`SUPABASE_SERVICE_ROLE_KEY` confinement** ([RT-26](../docs/SECURITY/index.html#rt-26) / [ADR-016](../DECISIONS.md#adr-016)): referenced ONLY in allowlisted surfaces, and only in the **three locked allowlist endpoints** — the Plaid webhook handler (`/api/plaid/webhook`), `/item/public_token/exchange`, and `/item/remove`. The RT-26 CI grep fence checks this on every PR; it's **allowlist-shaped (fail-closed)**. If you want service_role outside the allowlist, the answer is "use the anon key with RLS"; if RLS won't allow it, Sec-consult before bypassing. Adding a fourth surface requires Sec-consult + ADR amendment.
- **Zod `.strict()` server-side input validation** at every input boundary (request body, query params, form data, Plaid webhook payload). `.passthrough()` is forbidden on user-facing inputs ([Lock 14](../DECISIONS.md#adr-011) V1-SHIP-BLOCK Sec mods #1 typed-input validation + #2 mass-assignment prevention). Numeric inputs go through the shared sanitization battery (NaN/Inf/currency-string/scientific-notation rejection).
- **SECURITY INVOKER read-composition**: call the Architect-authored read-composition helpers — `fn_compute_nav` ([Lock 11](../DECISIONS.md#adr-011)), `fn_compute_tax_liability` (Lock 14), `fn_render_monthly_report` (Wave 6) — which run `SECURITY INVOKER` so the caller's RLS context propagates. **Do not bypass RLS. Never write `SECURITY DEFINER`** (the DEFINER allowlist is a narrow **4-entry** set per [ADR-011 Decision 9](../DECISIONS.md#adr-011) — `fn_refresh_updated_at` + `fn_grant_creator_access` + `fn_reclass_history_insert` + the reserved general audit-log insert helper; **3 authored so far** (the audit-log helper is reserved/unauthored); Architect owns all DB functions).
- **`src/hooks.server.ts` is the session chokepoint** ([ADR-015](../DECISIONS.md#adr-015) Decision 1): it owns centralized Supabase session forwarding + JWT refresh under the `authenticated` tier. **Don't duplicate** session handling anywhere else.
- **Same-transaction audit-log**: every state-changing write emits its audit-log row in the same transaction (TypeScript-side analogue of the worker discipline). No retry queues, no fire-and-forget.

## Canonical references

- [ADR-015](../DECISIONS.md#adr-015) — SvelteKit + no-Tailwind lock; the canonical server-source surface enumeration.
- [ADR-016](../DECISIONS.md#adr-016) — RT-26 service_role 3-surface allowlist enumeration + the durable allowlist-addition convention.
- [SECURITY §4.1](../docs/SECURITY/index.html#sec-4-1) (tenant-isolation posture) / [§4.2](../docs/SECURITY/index.html#sec-4-2) (credential posture); [RT-26](../docs/SECURITY/index.html#rt-26) — the service_role allowlist CI grep fence design.
- [ARCH §4.1](../docs/ARCH/index.html#sec-4-1) — the canonical server-source allowlist file-glob table; [§7.1](../docs/ARCH/index.html#sec-7-1) — Plaid endpoint behavioral contracts.
- [ADR-011](../DECISIONS.md#adr-011) Decision 1 (privileged-context-write) / Lock 14 (settings write-path hardening) / Decision 3 (cross-tenant FK-bypass family).

## Fail-closed / gotchas

- **Every new `SECURITY DEFINER` need routes to Architect + Sec** — it's Sec-veto territory + a ratify gate. You implement call sites, not DB functions.
- **Every new `SECURITY INVOKER` helper ships a per-Wave RLS verification battery test** (QA-authored) proving cross-tenant access **fails closed** — flag QA when a new helper lands.
- **Plaid SDK** (web-app side) lives in `src/lib/server/plaid/` ([ARCH §7.1](../docs/ARCH/index.html#sec-7-1) two-tier posture); sandbox tier in V1.0, production post-`SELF-212` (F/CTO-gated).
- **`/internal/pdf-render`** is the signed-JWT render endpoint the PDF worker hits (Lock 13 mod #1) — it's the only path the zero-DB PDF worker reaches data through.
- Any new cross-tenant FK reference is a [Decision 3](../DECISIONS.md#adr-011) family instance — Sec-consult + ARCH §10 ledger update, even when the parent FK is RLS-protected.
- **Account closure CONTRACT (ADR-042; migrations `058` + `059`). This REPLACES the `is_active` soft-delete contract that stood here, and it is a REPLACEMENT rather than a rewording — the old contract was wrong in a way that re-wording preserves.** An account is retired by being **closed as of a date**: `pfin.account.closed_at` (NULL = open), written **only** through the `fn_close_account` / `fn_reopen_account` INVOKER RPCs. **`pfin.account.is_active` no longer exists** — dropped at `059`. Do not re-add it, do not synthesize a derived `is_active` into a query result, and do not reach for one because a boolean "feels simpler": a boolean cannot answer an as-of question, which is the whole defect the three-concept model removes.
  - **WHICH PREDICATE YOU NEED DEPENDS ON WHICH QUESTION YOUR SURFACE ASKS. Establish that first — the two forms are not better and worse, they answer different questions, and picking by shape is how you get the wrong one.**
    - **VALUATION surfaces — NAV, aggregation, counts, any presence-check paired with a NAV read — ask "which accounts were open AS OF this date". Use the as-of form:** `closed_at is null or closed_at > <as_of>`, and use **the same `as_of` the NAV used** — two reads that must describe one population must not read two different dates.
    - **RENDER surfaces — a detail page's status pill, a list partition, "is this account closed right now" — ask a CURRENT-STATE question, and `closed_at !== null` is the correct and complete answer.** The as-of form there is not merely heavier, it is **wrong**: it would need an `as_of` the surface has no business choosing, and would answer a question nobody asked.
    - **THE ASYMMETRY IS ABOUT RISK, NOT CORRECTNESS, AND THIS IS THE PART TO CARRY.** The as-of form is mandatory on valuation surfaces **because that is where the silent-flip risk lives** — there, `closed_at is null` alone is behaviourally identical to the correct form until a closed account exists, so no test on today's data separates them and the wrong re-point passes review (`059`'s own `fn_compute_nav` comment names this as its dependency "with no footprint"). On a render surface there is no such trap: the current-state answer is the one being asked for, and it is verifiable by looking at the screen. **A rule stated without its risk gets applied by shape** — which is exactly how a render surface ends up carrying an `as_of` it cannot justify.
  - **⛔ THE OLD TEMPORAL FENCE IS STRUCK, NOT RELAXED.** The retired contract forbade the active-only NAV path at any date but `current_date`, because `is_active` was current-state and filtering it into a past `as_of` rewrote history. `closed_at` **is** temporal, so `fn_compute_nav(d, true)` is now sound at **any** `d`. Any comment still forbidding it is FALSE — fix it where you find it. A stale prohibition is undetectable by construction: nobody tests the path they were told not to take, so its absence leaves no artifact to trip over.
  - **Management views do not filter at all.** The connections surfaces and the accounts list show closed accounts *as closed*; only current-state / NAV / aggregation scopes narrow.
  - Closed accounts RETAIN their `account_trans` history (schema-guaranteed: `ON DELETE RESTRICT`, no cascade/skip-flag) — never hard-delete or skip-flag them. A closed account is additionally **frozen**: `058`'s transfer-in fence rejects INSERTs on the position-determining tables, so the correction path is reopen → correct → re-close, which re-proves the zero invariant instead of assuming it survived.
- Migrations are **Architect-owned** (`/supabase/migrations/`); `api/` consumes them (apply locally + in CI test-fixture), never authors them. Schema changes → flag Architect.

---

# Frontend Engineer — browser-shipped surfaces

**Owner role:** Frontend Engineer. Per WORKFLOW.md Agent Roster. Merged from the former `web/CLAUDE.md` at the `web/`→`api/` fold (SELF-185).

## What lives here (Frontend)
The SvelteKit V1 web-app — **browser-shipped (non-`server`) source only**:

- `src/routes/**/+page.svelte`, `+layout.svelte` — route-level UI.
- `src/lib/components/**` — reusable UI primitives (component inventory in [design-system-spec.md](../docs/DESIGN/design-system-spec.md) §4).
- `src/lib/**` (non-`server`) — browser-side state (Svelte 5 runes), formatters, client-side Zod validators.
- `src/lib/styles/**` — global styling; `tokens.css` (copied from [docs/DESIGN/tokens.css](../docs/DESIGN/tokens.css) as a build asset) is `@import`-ed by `src/app.css`, which the root `+layout.svelte` imports so `var(--c-*)` is globally available.
- `src/app.html`, `src/app.css`, `static/**` — shell + global stylesheet + static assets.

**NOT yours — never touch from here:** `*.server.ts` / `*.server.js`, `src/lib/server/**`, `src/routes/**/+server.ts`, `+page.server.ts`, `+layout.server.ts`, `hooks.server.ts`. Those are **Backend's** server-source surfaces ([ARCH §4.1](../docs/ARCH/index.html#sec-4-1) allowlist). You **consume** their exports via SvelteKit's `data` prop / form-action interface; you do not author them.

## Conventions (Frontend)
- **Tokens only, via `var(--c-*)`.** Consume the locked two-tier token system ([tokens.css](../docs/DESIGN/tokens.css) / [ADR-014](../DECISIONS.md#adr-014) Decision 3). Semantic aliases: `--c-canvas` / `--c-surface[-alt|-alt2]` / `--c-border[-strong]` / `--c-text-{primary|secondary|muted}` / `--c-accent[-hover|-active|-soft|-tint]` / `--c-accent-2` / `--c-attn-{solid|text|bg|border}` / `--c-pos` / `--c-neg` / `--c-viz-{nominal|infl|fill}`; spacing `--space-0..7`; radius `--radius-{sm|md|lg|pill}`; type `--fs-*` / `--font-{ui|num}` / `--weight-*`; elevation `--shadow-1..3` / `--focus-ring`. **Never hardcode** a hex / px-spacing / font value inline — a raw value in a `.svelte` file is an [ADR-013](../DECISIONS.md#adr-013)-P5-class design-system violation. New token needed → route to Visual Designer; do not add hex to component source.
- **`--c-pos` / `--c-neg` fence:** value-color is scoped to ACTUAL performance only (NAV Δ, unrealized G/L). Never on `$ReAlloc` / `%Target` / target captions ([design-system-spec.md](../docs/DESIGN/design-system-spec.md) §5 fence 1). Attention hue (`--c-attn-*`, canary) is reserved for staleness/re-auth only — never decoration, never a value.
- **No inline editing of planning values** ([ADR-013](../DECISIONS.md#adr-013) Decision 7 / P5). The four user-authored planning values (§2.2 `%Target`, §2.3.2 income/expense targets, §2.5.2 tax brackets, §2.6 owner-id) are **read-only on data surfaces**; editing lives ONLY in the Settings `planning-target-editor`. `target-sum-readout` is informational — never an alert, never blocks save.
- **No Tailwind** ([ADR-015](../DECISIONS.md#adr-015)). Component styles use `var(--c-*)` tokens directly in `<style>` blocks; no utility-class framework.
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

## Canonical references (Frontend)
- [DESIGN](../docs/DESIGN/) — locked design system: [tokens.css](../docs/DESIGN/tokens.css), [screen.css](../docs/DESIGN/screen.css), [design-system-spec.md](../docs/DESIGN/design-system-spec.md) (component inventory §4 + load-bearing fences §5), `index.html` visual proof, `wireframes/`, `flows/`.
- [ADR-014](../DECISIONS.md#adr-014) — design-system foundation + two-tier tokens + `docs/DESIGN/` home.
- [ADR-013](../DECISIONS.md#adr-013) — D1 staleness-marking (Decision 1) · P5 no-inline-edit (Decision 7) · INV-1 plain-text commentary (Consequences).
- [ADR-015](../DECISIONS.md#adr-015) — SvelteKit + no-Tailwind lock; `hooks.server.ts` session chokepoint.
- [ARCH §4.1](../docs/ARCH/index.html#sec-4-1) — server-source surface allowlist (your *exclusion* list).
- [SECURITY §4.1–§4.2](../docs/SECURITY/index.html#sec-4-1) — tenant-isolation + credential posture (the browser boundary you keep server code out of).

## Fail-closed / gotchas (Frontend)
- **Never import secrets into browser code.** No `src/lib/server/**`, no `$env/static/private`, no `$env/dynamic/private` from any surface here — these ship to the browser; a leaked `SUPABASE_SERVICE_ROLE_KEY` from a stray import is an [ARCH §4.1](../docs/ARCH/index.html#sec-4-1) / RT-26 violation. SvelteKit's compiler refuses the build, but the discipline is yours. Public config via `$env/static/public` / `$env/dynamic/public` is fine.
- **INV-1 plain-text invariant** ([ADR-013](../DECISIONS.md#adr-013) Consequences / [design-system-spec.md](../docs/DESIGN/design-system-spec.md) §5 fence 4). User-authored free-text (monthly-report commentary, owner-id) renders as **plain text** — no rich-text/markdown/HTML affordance in the editor or the render path. Rich-text is a V1 security-surface expansion requiring a Sec re-touch (RT-11 / RT-12), NOT a harmless refinement.
- **API contracts are Backend's source of truth.** When a response/request shape changes, coordinate at the boundary — don't unilaterally re-derive it.
- **Config lives in `vite.config.ts`, not `svelte.config.js`.** This SvelteKit version (kit 2.63 / vite-plugin-svelte 7) holds the adapter + `compilerOptions` (runes mode) inside the `sveltekit()` Vite plugin; there is no separate `svelte.config.js`.
