# Phase 2 — Wireframes: §2.4 Cross-Cutting (onboarding / manual entry / re-auth)

**Scope:** layout realization for the §2.4 cluster — the foundation surface. Flows LOCKED (`temp/phase-2-flows-2.4-cross-cutting.md`); this is placement + states, not flow design.
**Author:** UX Designer. **Step:** Phase 2 Step 4. **Date:** 2026-05-28.
**Inherits the SHELL** (`temp/phase-2-wireframes-shell.md`) — sidebar (P1), conditional re-auth banner (P4), notifications-inbox, `stale-data-marker` (D1). Terminology + state vocabulary defined there (esp. `stale`, modal-vs-panel, persistent-vs-conditional).
**Decisions applied:** P1 (Accounts = sidebar destination 1) · P3 (hybrid classification — queue is the task home; §2.2's Unsorted row deep-links in) · P4 (re-auth banner is shell chrome, not redrawn here) · D1 (per-aggregation stale markers). §2.4 has **no planning-value surface** (P5 n/a here) and **no info-hierarchy decision** (P2/P6 n/a).

---

## 0. How §2.4 sits in the shell
- **Accounts** is sidebar destination #1 → its content region is the **Accounts Hub** (§1).
- The **P4 re-auth banner** (shell chrome) is driven by §2.4.4 credential state; the **`notifications-inbox`** (shell) surfaces the `New-Symbol-Classification-Queue` (§4) + `pending-report-queue` (§2.6).
- Account-level destinations (Account Detail, Transaction-Entry, Reconcile, etc.) render in the content region; modals overlay it.

---

## 1. `Accounts Hub` (content region — sidebar destination #1)
The account list + the per-account connection-state overview (§2.4.4) + the entry points to onboarding.

```
┌─ CONTENT: Accounts Hub ───────────────────────────────────────────────┐
│ Accounts                        [ + Connect institution ] [ + Add manual ]│
│ ──────────────────────────────────────────────────────────────────── │
│ DEPOSITORY                                                            │
│  ◰ Chase Checking      personal · taxable     $12,4xx  [⟳ Re-auth] ⚠ │ ← stale row
│  ◰ Ally Savings        personal · taxable     $ 8,0xx  [● Fresh]      │
│ INVESTMENT                                                            │
│  ◰ Fidelity Brokerage  trust · taxable        $3xx,xxx [● Fresh]      │
│ RETIREMENT / CRYPTO / MANUAL-OTHER / REAL ESTATE / LIABILITIES …      │
│ ──────────────────────────────────────────────────────────────────── │
│ Gross total (pre-tax-adjustment): $X,xxx,xxx   → See Net Worth for NAV │ ← P PM-2: NOT NAV
│ ▸ Inactive (3)                                                        │ ← collapsed group
└───────────────────────────────────────────────────────────────────────┘
```
**Regions:** header (title + add affordances) · grouped account list · footer (gross-total + inactive group).
**Components & states:**
- `connect-institution-action` / `add-manual-action` — `default`/`hover`/`pressed`/`loading` (while launching).
- `account-row` (grouped by account-type category — the §2.1.5 vocabulary): shows name · scope · tax-treatment · **current gross value** · `connection-status-chip`.
  - states: `default`/`hover`/`pressed`(→Account Detail) · **`stale`** (row shows `stale-data-marker` + a re-auth `connection-status-chip`) · `loading` (initial sync in progress) · `empty` (no accounts yet → onboarding nudge) · `inactive` (in the collapsed Inactive group, "sync paused" chip).
- `connection-status-chip` states (the four §2.4.4 classes + lifecycle): `Fresh ●` · `Re-auth required ⟳` (actionable) · `Institution down` (informational) · `Grant revoked` (act-at-institution) · `Manual` (no sync) · `Inactive — sync paused`.
- **`gross-total-readout`** — labeled **"Gross total (pre-tax-adjustment)"** with a link to Net Worth. **States:** `default` · **must NOT render as NAV / a hero number** (PM-2 / value-semantics pin; Visual constraint carried). `stale` if any contributing account is stale.
- `inactive-group` (collapsible): `collapsed`(default)/`expanded`.
**Empty state:** no accounts → centered "Connect your first institution or add a manual account" with the two actions.

---

## 2. `Account Detail` (content region)
Single-account home; composed of the named panels from the flow doc.

```
┌─ CONTENT: Account Detail — Fidelity Brokerage ────────────────────────┐
│ ‹ Accounts    Fidelity Brokerage          [● Fresh]      [ ⋯ ]        │
│ ┌ account-attributes-panel ─────────────────────────────────────────┐ │
│ │ Type: Investment   Scope: trust   Tax-treatment: taxable          │ │
│ │                              [ Edit ]   [ Mark inactive ]          │ │ ← Plaid → F-2.4.F modal
│ └───────────────────────────────────────────────────────────────────┘ │
│ ┌ connection-status-panel  (Plaid accounts only) ───────────────────┐ │
│ │ Last successful sync: 2026-05-27 06:00                             │ │
│ │ State: ● Connected      (or: ⟳ Re-auth required [Re-authenticate]) │ │
│ └───────────────────────────────────────────────────────────────────┘ │
│ ┌ transaction-list ─────────────────────────────────────────────────┐ │
│ │ [ + Add transaction ]  [ Reconcile ▾ ]  [ Deleted / skipped ]     │ │
│ │ date        vendor/desc        amount    Sub-Cat       ✓recon      │ │
│ │ 2026-05-20  …                  -$xx      Expenses→…    [recon ▸]   │ │
│ │ …                                                                  │ │
│ └───────────────────────────────────────────────────────────────────┘ │
│ ┌ sync-history-panel  (Plaid only) ─────────────────────────────────┐ │
│ │ 2026-05-27  4 new · 2 deduped   → [ audit log ]                    │ │
│ └───────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────┘
```
**Components & states:**
- `account-attributes-panel` — read view + `Edit` (→ inline edit or `Add-Manual-Account`-shaped form for manual) + **`Mark inactive`** (Plaid → opens the F-2.4.F confirm **modal**, §10; manual → simple confirm). `Edit` states: `default`/`editing`/`saving`/`error`.
- `connection-status-panel` (Plaid only) — last-sync timestamp + current state; `Re-authenticate` action appears in `Re-auth required`/`Grant revoked` states. **States mirror the four §2.4.4 classes** + `Inactive — sync paused` (read-only variant for inactive Plaid accounts: "Still connected to Plaid — sync paused," NOT "disconnected").
- `transaction-list` — row-level: `default`/`hover`/`pressed`(→edit) · `stale` (Plaid-sourced row from a stale sync) · `skipped` (struck/greyed, in the deleted view) · `split-parent` (marked split-and-skip) · `reconciled ✓`. Row action `reconcile-through ▸` (B1).
- `sync-history-panel` (Plaid only) — entries `default`/`hover`/`pressed`(→`Sync/Dedup-Audit-Log`); `empty` (no syncs yet).

---

## 3. Connect-Institution flow (Plaid onboarding — F-2.4.A)
A guided sequence; Plaid Link itself is **external** (Plaid-hosted), bracketed by our screens.

**3a. `Connect-Institution-Launch`** — transient (a brief loading state, not a full screen): user clicks `+ Connect institution` → `loading` ("Opening secure connection…") → hands off to Plaid Link. **`error`** (token mint fails): inline error on Accounts Hub ("Couldn't start the connection. Retry."), no Plaid Link opens.

**3b. `Plaid Link`** — **EXTERNAL (Plaid-hosted), not our UI.** Wireframe note only: institution auth + account-share selection happen here; on success returns to **3c**; on exit returns to Accounts Hub cleanly (no partial account).

**3c. `Account-Setup-Attributes`** — per shared account, set scope / tax-treatment / account-type:
```
┌─ CONTENT: Account Setup — 3 shared accounts from Fidelity ─────────────┐
│ Account            Scope ▾     Tax-treatment ▾    Account-type ▾       │
│ Brokerage …1234   [ trust ]   [ taxable ]        [ investment * ]     │ ← * Plaid recommendation
│ Roth IRA …5678    [ personal ][ tax-free ]       [ retirement * ]     │
│ …                                                                     │
│                                              [ Continue → sync ]      │
└───────────────────────────────────────────────────────────────────────┘
```
- per-account `scope`/`tax-treatment`/`account-type` selects: `default`(Plaid-recommended for account-type, editable) · `error` (required-field empty → inline; Continue disabled).
- `continue-action`: `disabled` until all rows valid · `loading` (→ initial sync).

**3d. `Initial-Sync-Progress`** — `loading` state ("Pulling balances & holdings…"); on success → Accounts Hub with the new account(s) `Fresh`. **`error`/partial:** account created but lands `Sync error`/`Re-auth required` on the Hub (never silently "complete"); retry from Account Detail.

---

## 4. `New-Symbol-Classification-Queue` + `Symbol-Classification` (P3 — hybrid)
**P3 = hybrid:** this queue is the **canonical task home** (reached via the `notifications-inbox`, and after initial sync), AND the §2.2 `alloc-unsorted-row` **deep-links here**. The Unsorted row stays visible in-context on Allocation; classification happens here (or inline from that row per the §2.2 wireframe).

```
┌─ CONTENT: New-Symbol-Classification-Queue ────────────────────────────┐
│ Unclassified symbols (5)            (currently aggregating as Unsorted)│
│ symbol   Plaid hint                              assign               │
│ VTI      ETF · Vanguard Total Stock Market       [ Classify → ]       │
│ XYZ      equity · (sparse metadata)              [ Classify → ]       │
│ …                                                                     │
└───────────────────────────────────────────────────────────────────────┘
```
`Symbol-Classification` (panel):
```
┌ Symbol-Classification — VTI ─────────────────┐
│ Plaid hint: ETF · Vanguard Total Stock Market │ ← recommendation, NEVER auto-applied
│ Category ▾:     [ Equity ]                     │ ← seeded list only (no "+ new")
│ Sub-Category ▾: [ US-Index_Non_Sector ]        │
│ Applies to VTI across ALL accounts holding it. │
│                        [ Cancel ]  [ Assign ]  │
└────────────────────────────────────────────────┘
```
**States:** queue rows `default`/`hover`/`pressed` · `empty` ("No symbols need classification" — the common steady state) · badge feeds the inbox count. `Symbol-Classification`: Cat/Sub-Cat selects `default`/`error`(none chosen) · `Assign` `disabled` until both chosen · `loading`(saving) · on assign → row leaves queue, badge decrements, aggregations recompute. **No "+ new bucket"** (taxonomy CRUD is V2+).

---

## 5. `Newly-Available-Account-Prompt` (modal)
On a resync detecting an institution account not in the stored share decision.
```
┌ Newly available account (modal — blocking) ──────────────┐
│ Fidelity surfaced a new account: "529 Plan …9012".       │
│ Add it to your aggregations?                             │
│              [ Not now ]   [ Opt in → set up ]           │
└──────────────────────────────────────────────────────────┘
```
**States:** `default` · `opt-in` → runs `Account-Setup-Attributes` for that one account · `dismiss` → stays excluded (re-offerable later). Account does NOT auto-flow into NAV/allocation/cash-flow until opted in.

---

## 6. `Add-Manual-Account` (F-2.4.B)
Single-pass, non-credential surface (no Plaid, no token prompt).
```
┌─ CONTENT: Add manual account ─────────────────────────────────────────┐
│ Name [                 ]   Account-type ▾ [ Real Estate ]             │
│ Scope ▾ [ personal ]       Tax-treatment ▾ [ taxable ]               │
│ Initial value [          ]  as of [ 2026-05-01 ]                      │
│ Sub-Category ▾ [ Real Estate → Primary Residence ]  (asset taxonomy)  │
│                                            [ Cancel ]  [ Create ]      │
└───────────────────────────────────────────────────────────────────────┘
```
**States:** each field `default`/`hover`/`error` (required: name, type, scope, tax-treatment, initial value, as-of-date, Sub-Cat; `error` examples — non-numeric value, future as-of-date, missing Sub-Cat) · `Create` `disabled` until valid · `loading`(saving). Post-create → Accounts Hub with a `Manual` chip. No staleness (manual accounts don't sync).

---

## 7. `Transaction-Entry` (+ `Transaction-Split`) (F-2.4.C)
One surface, mode toggle Cash / AcctSetup; sell transactions carry the back-annotated wash-sale fields.
```
┌ Transaction-Entry  (add / edit) ──────────────────────────────────────┐
│ Type:  ( • Cash )   ( AcctSetup )                                     │
│ ── Cash ──                                                            │
│ Amount [        ]   Date [ 2026-05-27 ]                               │
│ Vendor [             ]   Description [                ]               │
│ Sub-Cat ▾ [ Expenses → Groceries ]    (recurring-vendor suggestion ⓘ)│
│ ── if this is a SELL (realizes a position) ──                        │
│ ☐ Wash sale    Disallowed loss [         ]     ← §2.5.1 back-annotation│
│ ⓘ Editing a Plaid transaction preserves its link — your edit wins on  │
│   the next sync.                                                      │
│                          [ Cancel ]   [ Split… ]   [ Save ]          │
└───────────────────────────────────────────────────────────────────────┘
```
**AcctSetup mode** (when toggled): `event-subtype ▾` (split / transfer-in-kind / other) → reveals subtype fields (split: ratio + ex-date; transfer-in-kind: source + dest + position + basis-carry; other: free-text).
**`Transaction-Split`** (sub-mode/panel): original Plaid txn → N child rows (amount + Sub-Cat each); on save the original is marked **split-and-skip** (retained, excluded), children are independent.
**States:** fields `default`/`hover`/`error` (cash required: amount/date/Sub-Cat; AcctSetup: subtype + subtype fields; **wash-sale**: disallowed loss ≤ realized loss → `error` if exceeded) · `Save` `disabled` until valid · `loading` · editing-Plaid-source variant (shows the ID-link note) · split `default`/`add-child`/`remove-child`/`error`(children don't sum).

---

## 8. `Deleted/Skipped-Transactions` + `Sync/Dedup-Audit-Log`
- **`Deleted/Skipped-Transactions`** (panel/screen): list of `skip_flag=true` records (struck/greyed) with an **`un-skip`** action per row. States: `default`/`hover`/`pressed`(un-skip)/`empty` ("Nothing deleted"). Un-skip → record returns to the ledger; next resync won't re-create duplicates.
- **`Sync/Dedup-Audit-Log`** (panel, read-only): per-sync "what was deduped" — matched-by-id vs matched-by-hash; `default`/`empty`. *(Silent in the stream; never silent on demand — this is the on-demand surface.)*

---

## 9. `Reconcile-Mode` + `Balance-Mismatch-Diff` (F-2.4.D)
**B1 (per-transaction):** the `reconcile-through ▸` action on a `transaction-list` row → runs the check through that date → `match`(sets reconciled ✓) or `mismatch`(opens `Balance-Mismatch-Diff`).
**B2 (bulk Reconcile-Mode):**
```
┌─ CONTENT: Reconcile — anchor date [ 2026-04-30 ] ─────────────────────┐
│ account              computed     Plaid-reported    status            │
│ Chase Checking       $12,4xx      $12,4xx           ● match           │
│ Fidelity Brokerage   $3xx,xxx     $3xx,xyz          ✗ mismatch [diff] │
│ …                                                                    │
│                                              [ Reconcile matched → ]  │
└───────────────────────────────────────────────────────────────────────┘
```
`Balance-Mismatch-Diff` (panel): "Fidelity — computed $X vs Plaid $Y, Δ $Z" + pointer to investigate (edit a txn via Transaction-Entry, add a missing one, or accept & re-run).
**States:** anchor-date picker `default`/`error`(invalid date) · row `match`/`mismatch`/`loading`(checking) · **`stale`** (if the account is pending re-auth, the Plaid-reported side is marked stale so the user doesn't reconcile against stale truth) · `Reconcile matched` `disabled` until ≥1 match. **No auto-reconcile** (B3 is V2+).

---

## 10. `Mark-Plaid-Account-Inactive-Confirm` + Reactivate (F-2.4.F)
The **distinct** Plaid inactive path (NOT the manual simple-retire) — mandatory disclosure.
```
┌ Mark "Fidelity Brokerage" inactive?  (modal — blocking) ─────────────┐
│ Hides this account and pauses sync.                                  │
│ Does NOT disconnect from Plaid — the connection and access token are │
│ retained server-side. Full disconnect is not available in V1.       │
│                                       [ Cancel ]  [ Mark inactive ]  │
└──────────────────────────────────────────────────────────────────────┘
```
- On confirm: account → Inactive group (Accounts Hub); sync paused; **any P4 banner it raised clears**; it contributes **no** `stale-data-marker`; history retained read-only; `connection-status-panel` shows **"Still connected to Plaid — sync paused."**
- **Reactivate** (from the Inactive group / Account Detail): `default`/`loading` → resumes sync; if a credential error accumulated while inactive, it lands in the matching §2.4.4 state and raises the P4 banner (re-auth only then); else sync just resumes.
**States:** confirm modal `default`/`pressed`/`cancel`. Reactivate `default`/`loading`/(→`error` routes into re-auth).

---

## 11. Re-authenticate (F-2.4.E) — handoff
- Entry: P4 banner `[Review →]` or `connection-status-panel [Re-authenticate]`.
- `Re-Auth (Plaid Link update mode)` is **EXTERNAL (Plaid-hosted)** — credentials entered only there, in-session; on success the state returns to `Fresh`, the P4 banner clears, stale markers clear on next sync. `INSTITUTION_DOWN` shows informational text with **no** re-auth action.

---

## 12. Status / next
- **§2.4 wireframes complete** — all key screens with layout regions, named components (locked vocabulary), per-component states (incl. `stale`), and ASCII for the pattern-setters (Accounts Hub, Account Detail, Account-Setup-Attributes, classification queue, Transaction-Entry, Reconcile, inactive-confirm).
- **Decisions realized:** P1 (Accounts = sidebar dest #1, in the shell), P3 (hybrid — queue is the task home + the §2.2 Unsorted row deep-links in), P4 (banner is shell chrome), D1 (`stale-data-marker` + stale row/value states throughout). PM-2 honored: Accounts Hub shows a labeled **gross total**, **never NAV**.
- **No NEW flow questions surfaced** by the wireframes (flows hold as locked). One shell-level confirm pending: `global-search` omission (shell §8).
- **CHECKPOINT:** shell + §2.4 ready for your relay to F/CTO. On confirmation of the pattern, I continue §2.1 → §2.2 → §2.3 → §2.5 → §2.6.
- **No Visual styling** (Step 5).
