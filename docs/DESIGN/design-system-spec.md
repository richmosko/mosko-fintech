# mosko-fintech — Design System Spec (Phase 2 Step 8)

**Status:** Step 7 foundation LOCKED (F/CTO). This doc is the canonical written spec; the visual proof is `index.html` (Foundations → Component gallery → Shell → §2.1), and the code is `tokens.css` + `screen.css`.
**Scope:** finalized token taxonomy + component visual specs with states + token references + the load-bearing fences. Tokens-as-code in a framework format (Step 10) waits on the Phase-3 frontend-framework choice.

---

## 1. Locked foundation
- **Palette B refined** — pure-white `#ffffff` canvas; the "cooler" read comes from cool-tinted borders/surface fills/shadows, not a tinted canvas.
- **Accents (chrome only):** vivid blue `--c-accent #2563eb` + indigo secondary `--c-accent-2 #7c5cff`.
- **Typography:** Inter (UI + hero NAV) + JetBrains Mono (tabular numerics) — Type 3 Hybrid.
- **Attention = Canary-Yellow** `--c-attn-solid #ffef00` (stale/re-auth ONLY).
- **Dark = plan-for** (token block proves it; ship light-first; toggle `data-theme`).

## 2. Token architecture — TWO TIERS (Step 9)
The color system is explicit and two-tiered so every value is discoverable and no semantic token carries a raw hex:

- **Tier 1 — Primitives (`--color-*`):** named raw values; the **only** place hexes live, once each. A cool-neutral ramp (`--color-white`, `--color-neutral-25 … -955`, light→dark), plus accent blue, indigo, canary, green/red ramps, and alpha tokens (`--color-overlay-*`, `--color-vizfill-*`).
- **Tier 2 — Semantic aliases (`--c-*`):** every role is `var(--color-*)` — **no bare hex on any `--c-*`**. Light set on `:root`; the **dark theme re-aliases** the same semantic names to dark-side primitives under `[data-theme="dark"]` (no new hexes in the dark block).

Examples: `--c-canvas: var(--color-neutral-25)` (barely-cool `#fafcfe`); `--c-surface: var(--color-white)`; `--c-border: var(--color-neutral-150)`; `--c-attn-solid: var(--color-canary-500)`.
- **Naming:** semantic roles describe purpose, not value. Color roles: `canvas / surface / surface-alt[2] / border[-strong] / text-primary|secondary|muted / accent[-hover|active|soft|tint] / accent-2 / attn-{solid|text|bg|border} / pos / neg / disabled-{bg|text|border} / overlay / viz-{nominal|infl|fill}`.
- **State modelling:** live via `:hover` / `:focus-visible`; static demo via modifier classes `.is-hover/.is-focus/.is-pressed/.is-disabled/.is-loading/.is-error/.is-empty/.is-stale`.

## 3. Foundation tokens
**Canvas/cards:** canvas = barely-cool `#fafcfe` (reads essentially white — not gray, not beige); card surfaces are pure `#ffffff`; cards (`.region`) get a 1px cool border + `--shadow-1` elevation so they read as distinct "windows" via gentle fill-contrast + elevation. (Resolves the pure-white-canvas ⟷ card-distinction tradeoff in favor of card distinction without any warm tint.)
**Spacing:** `--space-0..7` = 2 / 4 / 8 / 12 / 16 / 24 / 32 / 48.
**Radius:** sm 3 · md 5 · lg 8 · pill 999.
**Type scale:** hero 32 · h1 22 · h2 16 · h3/body/num 13 · small 11 · micro 10; line-heights tight 1.18 / body 1.45; weights 400/500/600/700.
**Elevation:** `--shadow-1` (cards) · `--shadow-2` (menus/popovers) · `--shadow-3` (modal) · `--hero-glow` (focal surface) · `--focus-ring`.
**Color:** full light + dark via the two tiers above. Dark re-aliases every semantic role to dark-side primitives; canary identity brightens to `--color-canary-300` `#ffef33`.

## 4. Component inventory (visual spec · states · token refs)

| Component | States | Key tokens |
|---|---|---|
| **btn** (primary / secondary / link-style / attn) | default · hover · pressed · loading (spinner) · disabled | accent[-hover/active], surface, border-strong, disabled-*, attn-* |
| **field-input** (text/number/date) | default · hover · focus · disabled · error (+msg) | border-strong, accent, accent-soft, neg, disabled-* |
| **select** (seeded lists; no "+ new") | default · hover · open · disabled · error | border-strong, accent, accent-soft, neg, text-muted |
| **chip** (filter/selected/muted/attn) | default · hover · pressed(where clickable) · muted | border-strong, accent-soft, attn-* |
| **connection-status-chip** | fresh · re-auth(actionable) · institution-down(info) · grant-revoked · manual · inactive—sync-paused | pos(dot only), attn-solid/border, text-muted, border-strong |
| **table.tbl** (dense financial) | header · numeric cell · subtotal · foot(NAV/totals) · emphasis-col · row hover · stale · empty | surface-alt[2], border[-strong], accent-soft, attn(stale) |
| **breadcrumb** *(INV-3)* | link · separator · current | link, text-secondary/muted/primary |
| **action/overflow-menu** *(INV-3)* | trigger · trigger-hover · open(menu) · item-hover · danger-item · separator | surface, border, shadow-2, surface-alt, neg |
| **chart-granularity chip-group** *(INV-3)* | segmented · selected · hover | border, accent-soft, surface-alt |
| **account-row** | default · hover · pressed(→Detail) · stale · inactive · loading | surface-alt, attn-bg(stale tint), text-secondary |
| **modal / panel-card / drawer** + scrim | container; modal dims + blocks beneath | overlay, surface, shadow-3/1/2, accent(drawer edge) |
| **tooltip** | hover→tip | text-primary(bg), surface(fg), shadow-2 |
| **planning-target-editor** (Settings, P5) | default · editing(dirty) · saving · disabled(no valid change) · error(per-field) · empty(bootstrap) · saved | field-input states, accent(Save), target-sum-readout |
| **target-caption** *(§2.3 FENCE)* | static reference value ONLY | text-secondary, font-num ref-value — **no comparative state exists** |
| **stale-data-marker (D1)** | present — tag + **disclosure** (when the marker carries an interactive affordance, e.g. Re-authenticate) OR tag + faint row tint (informational, on aggregation rows) · absent(zero-footprint) · hover→tooltip (informational-only instances) | attn-solid(edge), attn-bg/text, radius-sm/md, shadow-2(panel), focus-ring |
| **reauth-staleness-banner (P4)** | absent(healthy, zero footprint) · present-N · institution-down(no CTA) | attn-bg/border/solid(stripe), attn-text — non-dismissible |
| **notification-queue-item** | default · hover · pressed | surface-alt, border |
| **chart-placeholder** | default · loading(skeleton) · empty(insufficient history) · cpi-unavailable(nominal-only) · stale-segment | viz-nominal/infl/fill, text-muted |
| **freshness-stamp** (`nav-asof` / `report-generation`) | default — quiet, distinct from stale-marker | text-muted |
| **informational-marker-badge** *(SELF-220; §2.4.4 informational tier, first UI instantiation)* | present(quiet chip: surface-alt bg, border, text-secondary, text-muted dot) · absent(zero-footprint) — no other states per §2.4.4 | surface-alt, border, text-secondary/muted. **Deliberately NOT `--c-attn-*`** — outside the actionable family by construction (not a recolor); mirrors freshness-stamp's quiet register. Anchors at the inflation-adjusted legend entry. Full spec: flows/phase-2-flows-2.1-net-worth.md §12.4 + the SELF-220 token deliverable. |
| **chart-basis-line family** *(SELF-220)*: `cpi-basis-line` (always-on) + `resolution-disclosure` (strictly pre-boundary; D7 (b) RATIFIED 2026-08-12) | plain prose, no chrome — non-badge shape IS the disclosure-vs-marker cue; static/dated/no-hover/PDF-safe; CPI line first, resolution line second | text-secondary/muted. Boundary date architecture-exposed only, never client-inferred. Full spec: flows §12.3/§12.6. |
| **sparse-history density indicator** *(SELF-220; chart-placeholder empty-insufficient-history, partial extreme)* | hatch region on the LEFT (today−60mo → tracking-start; window is ROLLING, right edge = today; line right-anchored, never extrapolated) · calibration label ("N of 60 months") right-aligned in hatch at the boundary | diagonal `--c-border` hatch on `--c-surface-alt` — **deliberately NOT `--c-viz-fill`** (that token means "area under a real value"); truncation edge distinct from CPI/NULL open-stub break. Full spec: flows §12.9. |
| **sidebar / nav-item** | default · hover · active(current) · attention-dot · collapsed rail | accent-soft, accent, attn-solid(dot) |
| **hero (nav-headline)** | default · stale · incomplete-NAV | accent-tint surface, accent kicker, text-primary value |
| **count-badge** *(SELF-200)* | default(count>0, solid-accent pill) · zero-footprint(count≤0, renders nothing) · parent-hover(bg→accent-hover) | accent (bg), accent-contrast (text), accent-hover (via parent), radius-pill, fs-small, font-num, weight-semi. **Not `--c-attn-*`** — a count-notification, not staleness (§5 fence 8). `min/height 1.25rem` is a deliberate component-intrinsic constant (like `radius-pill` 999), not a `--space-*` value. |
| **metadata-hint / info-callout** *(SELF-200)* | present(caption + `<dl>` key/value list) — read-only, non-preselected hint (never auto-applied) | surface-alt (bg), border, radius-md, space-3 (pad); caption text-muted/fs-small; dt text-muted/weight-semi; dd text-secondary; all fs-small |

## 5. Load-bearing fences — how the system enforces them
1. **§2.3 non-goal (HIGHEST RISK):** `--c-pos/--c-neg` are scoped to ACTUAL performance only (NAV $Δ/%Δ, unrealized G/L). `.val-target` keeps target/`$ReAlloc`/`%Target` cells neutral. **No** progress/gauge/fill-line/over-under/%-of-target/arrow/target-line component or token exists. `target-caption` has no comparative state by construction.
2. **D1 stale-marker** = inline `.stale-tag` + faint row tint — visually distinct from the **P4 banner** (full-width chrome bar). Both use the canary attention hue but different shapes/placement; the marker never hides the value.
3. **P4 banner** = conditional (zero footprint when healthy), persistent, **non-dismissible** (no close affordance), institution-down variant has no CTA.
4. **INV-1 plain-text commentary / owner-id** — rendered as plain text; no rich-text/markdown affordance in the editor styling.
5. **P5 no inline editing** — data-surface planning values are read-only; editing only in the Settings `planning-target-editor`. The `target-sum-readout` is informational (never an alert; never blocks save).
6. **gross-total ≠ NAV** — Accounts Hub gross total is a labeled footer (`.foot`), never given the `nav-hero` treatment (hero reserved for the Net Worth surface).
7. **3 distinct freshness signals** kept separate: input-staleness (D1 marker) · materialization recency (`freshness-stamp`) · tax-incomplete (`incomplete-note`).
8. **Attention hue reserved** for staleness/re-auth only — never decoration, never a value; distinct from `--c-neg` red and the blue/indigo accents.

## 6. Dark mode & delivery
- **Dark = plan-for:** every role re-defined under `[data-theme="dark"]`; shipping light-first, dark a token-block swap (no re-style). Toggle in the review page.
- **Cache strategy (review):** CSS via versioned links `?v=N` from canonical `tokens.css`+`screen.css` (single source; bump N per change).
- **Step 10 (tokens-as-code):** emit framework-format tokens once the Phase-3 frontend framework is locked; the semantic names here are the contract.

## 7. Open items / next
- Style remaining clusters §2.2 / §2.3 / §2.5 / §2.6 after the checkpoint (same system).
- Step 9: formalize the abstract token taxonomy (this doc is the seed).
- Confirm with Frontend Engineer (Phase 5) the token output format.
