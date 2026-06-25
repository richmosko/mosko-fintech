# `api/` — scoped context for Claude Code

> **Per-directory `CLAUDE.md`** (WORKFLOW.md Phase 5 Step 5). Scoped conventions for working inside `api/`. The root [`CLAUDE.md`](../CLAUDE.md) + canonical artifacts ([ARCH](../docs/ARCH/index.html) · [SECURITY](../docs/SECURITY/index.html) · [DECISIONS](../DECISIONS.md)) stay source-of-truth; this file is the surface-local quick reference. **Forward-looking — `api/` is scaffolded in Phase 6 (SvelteKit); these conventions are locked now and get a light refine at scaffold time.**

**Owner role:** Backend Engineer (server-source surfaces). Per WORKFLOW.md Agent Roster. Frontend Engineer owns the non-`server` surfaces (`+page.svelte`, `+layout.svelte`, `src/lib/components/**`, `src/lib/**` non-`server`).

## What lives here

The V1 web-app container — **SvelteKit (Svelte 5)** per [ADR-015](../DECISIONS.md#adr-015) — the third container in the [Lock 13](../DECISIONS.md#adr-011) 3-container topology. Built via Vite; deployed as a small Node server in its Coolify container on cax21. Backend's scope is the **server-source surfaces only**; everything else ships to the browser and belongs to Frontend.

## Conventions

- **Server-source surface allowlist** ([ARCH §4.1](../docs/ARCH/index.html#sec-4-1) — the canonical file-glob enumeration, locked at framework ratify; SECURITY §4.1 is tenant-isolation *posture*, not the allowlist): server code lives ONLY in `src/routes/**/+server.ts`, `src/routes/**/+page.server.ts`, `src/routes/**/+layout.server.ts`, `src/hooks.server.ts`, and `src/lib/server/**/*.ts` (Vite-enforced server-only modules). **Never** put server logic in `+page.svelte` / `+layout.svelte` / `src/lib/components/` / `src/lib/**` (non-`server`) — those ship to the browser.
- **`SUPABASE_SERVICE_ROLE_KEY` confinement** ([RT-26](../docs/SECURITY/index.html#rt-26) / [ADR-016](../DECISIONS.md#adr-016)): referenced ONLY in allowlisted surfaces, and only in the **three locked allowlist endpoints** — the Plaid webhook handler (`/api/plaid/webhook`), `/item/public_token/exchange`, and `/item/remove`. The RT-26 CI grep fence checks this on every PR; it's **allowlist-shaped (fail-closed)**. If you want service_role outside the allowlist, the answer is "use the anon key with RLS"; if RLS won't allow it, Sec-consult before bypassing. Adding a fourth surface requires Sec-consult + ADR amendment.
- **Zod `.strict()` server-side input validation** at every input boundary (request body, query params, form data, Plaid webhook payload). `.passthrough()` is forbidden on user-facing inputs ([Lock 14](../DECISIONS.md#adr-011) V1-SHIP-BLOCK Sec mods #1 typed-input validation + #2 mass-assignment prevention). Numeric inputs go through the shared sanitization battery (NaN/Inf/currency-string/scientific-notation rejection).
- **SECURITY INVOKER read-composition**: call the Architect-authored read-composition helpers — `fn_compute_nav` ([Lock 11](../DECISIONS.md#adr-011)), `fn_compute_tax_liability` (Lock 14), `fn_render_monthly_report` (Wave 6) — which run `SECURITY INVOKER` so the caller's RLS context propagates. **Do not bypass RLS. Never write `SECURITY DEFINER`** (the DEFINER allowlist is 2 entries — the shared `fn_refresh_updated_at` trigger + the audit-log insert helper; Architect owns all DB functions).
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
- Migrations are **Architect-owned** (`/supabase/migrations/`); `api/` consumes them (apply locally + in CI test-fixture), never authors them. Schema changes → flag Architect.
