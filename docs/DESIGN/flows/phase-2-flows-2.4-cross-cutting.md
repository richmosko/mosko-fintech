# Phase 2 — UX Flow Document: §2.4 Cross-Cutting Cluster

**Cluster:** §2.4 — Account onboarding (Plaid), manual account/transaction entry, Plaid re-auth & credential lifecycle.
**Author:** UX Designer (`phase-2-ux-design` team).
**Status:** DRAFT — flows only. Pre-wireframe. Pre-PM-traceability-consult.
**Phase 2 step:** Step 2 (flow drafting per cluster, dependency order — §2.4 is the FIRST/foundation cluster).
**Date:** 2026-05-27.
**Working artifact** — lives in `temp/` (gitignored) per `feedback_working_artifacts_temp_not_docs`; committed home for Phase 2 flow diagrams is a pending F/CTO phase-entry decision.

---

## 0. Scope, inputs, and load-bearing constraints

### 0.1 PRD stories in this cluster
- **2.4.1** — Plaid account onboarding (and new-symbol surfacing).
- **2.4.2** — Manual non-Plaid account onboarding.
- **2.4.3** — Manual transaction entry (cash + AcctSetup non-cash events) + Plaid-vs-manual reconciliation.
- **2.4.4** — Plaid re-authentication and credential lifecycle.
- **2.4.5** — Onboarding/entry/re-auth write paths are the user's (tenant-scoping). *Supporting story — a cross-cutting non-functional constraint, not a screen. Applied to every write path in this cluster; see §8.*

### 0.2 Load-bearing constraints (do not violate downstream)
- **Single-user V1 (PRD §7.3 / ADR-011 Decision 6).** Flows assume ONE owner. **No team / sharing / invite / per-account-ACL UI anywhere.** The V1-dormant `account_users` scaffolding does NOT surface in V1 UI. No "share this account," no "granted by," no "who can see this" affordances.
- **Density-first archetype (PRD §1.3).** The owner is technically literate, does monthly finance reviews, maintains deliberate two-level taxonomies, and accepts substantial manual curation. Flows assume familiarity with financial concepts (cost basis, holding period, reconciliation, tax-treatment). No hand-holding, no progressive-disclosure tutorials, no "what is net worth?" explainers. Precision and density are features.
- **Non-silent staleness (PRD §2.4.4 — headline V1 commitment).** No aggregation is ever presented as fresh when a constituent account is pending re-auth or stale beyond threshold. This is authored in this cluster and threaded out to every consuming surface (§2.1/§2.2/§2.3/§2.6).
- **Credentials stay at the institution.** mosko-fintech never holds institution credentials. The client never holds the long-lived Plaid access token. Re-auth and connect happen only inside the authenticated app session via Plaid Link. No re-auth emails/SMS (V1).
- **Manual entry is ground-truth-authoritative.** The owner can author/edit/delete transactions (including Plaid-sourced ones) and assert authority over Plaid. The ledger never silently loses a user edit on resync.

### 0.3 Appendix B §2.4 — what's already routed to Phase 3 (NOT my surface)
All eleven active §2.4 routing flags are **Architect / Sec Phase-3 implementation flags** (storage shape, hash composition, RLS, webhook signature verification, error-code→state mapping mechanics). Two are explicitly handed back to Phase 2 UX:
- **(h)** the four credential-error states "must remain distinguishable for Phase 2 UX-finer-grained work" → I own the *presentation* of the four states (see F-2.4.E).
- **(i)** per-surface staleness signal *threading* is Architect's; the *visual marking* on each surface is mine (authored here, applied per-cluster).

No open *product* (PM) decisions remain on §2.4 from Phase 1 — the cluster is locked. Flags I raise below are flow-level ambiguities and UX-decision options, not re-litigation.

---

## 1. Navigational container (derived structure)

> **Note for PM traceability:** the two screens in this section are **navigational structure derived from explicitly-granted §2.4 capabilities** (account attribute editing, mark-inactive, per-account connection-state view, "add account," sync-history/dedup audit log). They are not new capabilities. Confirm they map to existing stories rather than extending scope.

These anchor every §2.4 flow. The **app-level navigation model** (how you *reach* "Accounts" — tab vs. sidebar vs. drill-down) is **deferred to the Step 3 walk-through** (see §7, Open Decision 1). §2.4 only needs the assumption that an **Accounts** destination exists.

### SCREEN: `Accounts Hub` *(full screen)*
The home of account management and the V1 realization of the §2.4.4 "per-account connection-state view" at overview granularity.
- Lists **all** accounts (Plaid-connected + manual), grouped by account-type category (depository / investment / retirement / crypto / manual-other / real-estate / liabilities) — same grouping vocabulary as §2.1.5 composition.
- Each **`account-row`** shows: name, account-type, scope label, tax-treatment, current value, and a **`connection-status-chip`** (see status vocabulary in §6).
- Inactive accounts collapsed into a separate "Inactive" group (excluded from current-state by default; §2.4.2).
- Entry points: **`+ Connect institution`** (→ F-2.4.A), **`+ Add manual account`** (→ F-2.4.B).
- Drill into any row → `Account Detail`.

### SCREEN: `Account Detail` *(full screen)*
Single-account home. Composed of named panels:
- **`account-attributes-panel`** — name, account-type, scope, tax-treatment, (manual: Sub-Cat + initial value/as-of-date). Actions: **Edit**, **Mark inactive** (the inactive action **branches by account source** — manual = the simple retire per F-2.4.B; Plaid = the distinct disclosure + sync-pause flow per **F-2.4.F**, §6A).
- **`connection-status-panel`** *(Plaid accounts only)* — last-successful-sync timestamp, current credential/error state (one of the four §2.4.4 states), **`Re-authenticate this account`** affordance (→ F-2.4.E). This panel is the per-account detail half of the §2.4.4 connection-state view.
- **`transaction-list`** — the account's transactions; entry point to `Transaction Entry` (F-2.4.C) and to per-transaction reconcile (F-2.4.D, B1). *(The cash-flow analytic rendering of these transactions is §2.3.3, a different cluster — Account Detail links to it, doesn't reproduce it.)*
- **`sync-history-panel`** *(Plaid accounts only)* — list of past syncs; each opens the **`Sync / Dedup Audit Log`** ("what was deduped this sync"; §2.4.3).
- Entry point to **`Deleted / Skipped Transactions`** view (§2.4.3).

---

## 2. FLOW F-2.4.A — Connect a Plaid Institution
**Traces:** PRD 2.4.1. **Entry:** `Accounts Hub` → `+ Connect institution`.

### Screen list
| Screen | Type | Role |
|---|---|---|
| `Connect Institution — Launch` | transient/modal | Server mints Link token; hands off to Plaid Link. |
| `Plaid Link` | **external (Plaid-hosted)** | Institution auth + account-share selection. Not our UI. |
| `Account Setup — Attributes` | full screen / multi-row form | Per shared account: set scope, tax-treatment, account-type. |
| `Initial Sync — Progress` | full screen / inline state | Initial pull running; assets/symbols ingesting. |
| `New-Symbol Classification Queue` | full screen / panel | Pending `Unsorted` symbols awaiting Cat+Sub-Cat. |
| `Symbol Classification` | panel / modal | Classify one symbol; Plaid metadata shown as hint. |
| `Newly-Available Account Prompt` | modal / inline notice | Opt-in for an institution account detected on a later resync. |

### Steps — user actions → system responses → decision points

1. **Launch.** User clicks `+ Connect institution`.
   - *System:* calls `/link/token/create` (short-TTL token), opens `Plaid Link`. Redirect URI is allowlist-bound.
   - **Error — Link token mint fails** (network / Plaid API down): inline error on `Accounts Hub` ("Couldn't start the connection. Retry."); no Plaid Link opens; user stays put. *(No partial account created.)*

2. **Institution auth + account selection (inside Plaid Link).** User authenticates at the institution's own portal and selects which accounts to share.
   - *System (on success):* Plaid Link returns a `public_token` to `onSuccess`; server exchanges via `/item/public_token/exchange` for the long-lived access token, persists it tenant-scoped under credential-class protection. **Client never holds the access token.** The set of accounts the user selected becomes the **authoritative share decision**.
   - **Decision point — Link outcome:** `onSuccess` → step 3 · `onExit` (user abandoned) → return to `Accounts Hub`, no account created, no token stored · institution auth failed inside Link → Plaid Link surfaces its own error; on exit we return to Hub cleanly.
   - **Error — exchange fails** after a successful Link (rare): show recoverable error; the connection is not persisted; user can retry from Hub. No half-connected account.

3. **Per-account attributes.** `Account Setup — Attributes` lists each shared account as a row. For each, the user sets **scope** (per ADR-004 Decision B), **tax-treatment** (taxable / tax-deferred / tax-free), **account-type** (Plaid's metadata pre-fills the account-type as a *recommendation the user confirms or overrides*).
   - *System:* persists attributes (tenant-scoped write, §2.4.5). Proceeds to initial sync.
   - **Decision point:** investment account → symbols will be pulled (step 5 may trigger) · depository/loan/other → no symbol surfacing; flow ends after sync.
   - **Validation:** scope + tax-treatment + account-type are required per account before continuing. Missing → inline field error; cannot proceed for that row.

4. **Initial sync.** `Initial Sync — Progress` shows the first pull running.
   - *System:* pulls balances/holdings/transactions; sets last-successful-sync timestamp; transitions account to `Fresh` status.
   - **Error — initial sync fails / partial:** account is created (attributes saved) but lands on `Accounts Hub` with a non-`Fresh` status chip (`Sync error` or `Re-auth required` per the failure); never silently shown as complete. User can retry sync or re-auth from `Account Detail`.

5. **New-symbol surfacing** *(investment accounts only).* When the pull returns symbols not yet in the user's AssetDB:
   - *System:* assigns each new symbol **`Unsorted` Sub-Cat under an `Uncategorized` Cat at sync time** (rollups are never blocked by missing assignments), then raises a **`notification-queue badge`** for the pending assignments.
   - The §2.2.2 allocation table will render the `Unsorted` Sub-Cat as its own row until cleaned (provenance is never hidden) — *that rendering lives in the §2.2 cluster; flagged here as a downstream dependency.*

6. **Classify a pending symbol.** User opens `New-Symbol Classification Queue` (from the badge) → selects a symbol → `Symbol Classification`.
   - *System:* shows Plaid's security metadata (`security_type`, `description`, `ticker`) **as a recommendation hint — never auto-applied** (V1 boundary). User chooses Cat + Sub-Cat.
   - *On save:* symbol moves out of `Unsorted`; badge count decrements; the symbol's assignment applies across **all accounts** holding it (per-symbol, not per-account — §2.2.1).
   - **Edge — user defers:** symbol stays `Unsorted`; remains in queue + as the allocation `Unsorted` row. No forced classification (rollups still work).

7. **Newly-available account on a later resync** *(asynchronous, not part of first connect).* If a resync detects an institution-side account not in the stored share decision:
   - *System:* raises a **`Newly-Available Account Prompt`** ("newly available — opt in?"). The account does **not** auto-flow into NAV / allocation / cash-flow until the user explicitly approves.
   - **Decision point:** Opt in → runs `Account Setup — Attributes` for that one account, then it joins aggregations · Dismiss → account stays excluded; can be opted in later.

### Out of scope (do NOT design in) — V1/V2 boundary per 2.4.1
Auto-classification of new symbols from metadata (V2+); bulk-connect-multiple-institutions (V2+); pre-emptive push/email notification of pending assignments (V2+ — in-app queue only); manual un-share of an already-shared Plaid account (V2+ — *but see Flag PM-1 re: inactive-flag overlap*). **No third-party security-master API enrichment** — metadata is Plaid-delivered only (privacy commitment).

---

## 3. FLOW F-2.4.B — Add a Manual Account
**Traces:** PRD 2.4.2. **Entry:** `Accounts Hub` → `+ Add manual account`.

### Screen list
| Screen | Type | Role |
|---|---|---|
| `Add Manual Account` | full screen / single-pass form | Capture all defining attributes in one pass. |

### Steps
1. User opens `Add Manual Account`. **This flow never touches Plaid Link, establishes no OAuth token, surfaces no credential prompt** — manual creation is a non-credential surface by construction.
2. User enters, in one pass: **name**, **account-type**, **scope**, **tax-treatment**, **initial value + as-of-date it represents**, **Sub-Cat assignment** (asset taxonomy, so it contributes to allocation + net worth from day one).
   - *System:* on save, creates the account tenant-scoped (§2.4.5). *(Initial value is recorded as a synthetic AcctSetup-flagged transaction per Appendix B flag (c) — Architect Phase-3 mechanism; from the UX side it's a single "initial value as of date" field.)*
3. Account appears on `Accounts Hub` with a `Manual` status chip (no connection state — manual accounts don't sync).
4. **Post-creation lifecycle** (on `Account Detail`):
   - **Edit attributes** — all attributes editable after creation.
   - **Mark inactive (manual accounts — the simple path).** When the asset is closed/sold; inactive accounts retain transaction history for historical accuracy but are excluded from current-state surfaces by default. A manual account has no Plaid Item or token, so retiring it is a **plain display state — no disclosure step**. **Plaid-connected accounts take the distinct F-2.4.F path (§6A) — do NOT reuse this simple state for them.**
   - All transactions on the account thereafter come through F-2.4.C manual entry.

### Decision points
- Asset class Plaid surfaces vs. doesn't → user chose this path because Plaid doesn't cover it (house, vehicle, private equity, etc.). No branch — manual is manual.

### Error / edge states
- **Validation failure** — required: name, account-type, scope, tax-treatment, initial value, as-of-date, Sub-Cat. Bad value (non-numeric value, future as-of-date, missing Sub-Cat) → inline field-level error; save blocked until resolved.
- **Manual-entry integrity** — historical/initial values feed cost basis and NAV time-series; the integrity mechanism (validation/audit/versioning) is Architect/Sec Phase-3 (Appendix B flag (j)). UX surfaces the *fields*; backend enforces integrity.

### Out of scope — V1/V2 per 2.4.2
Bulk import of manual accounts (V2+). V1 is single-account-at-a-time. **No account-delete affordance** — "mark inactive" is the V1 lifecycle end-state (see Flag PM-1).

---

## 4. FLOW F-2.4.C — Enter / Edit a Transaction (cash + AcctSetup)
**Traces:** PRD 2.4.3. **Entry:** `Account Detail` → `transaction-list` → `+ Add transaction` (or select an existing transaction → Edit). Works on **any** account — Plaid-connected or manual.

### Screen list
| Screen | Type | Role |
|---|---|---|
| `Transaction Entry` | panel / modal | Add/edit one transaction. Mode toggle: **Cash** vs **AcctSetup**. |
| `Transaction Split` | panel / sub-mode | Split one Plaid transaction into multiple user-created children. |
| `Deleted / Skipped Transactions` | full screen / panel | Skip-flagged records; un-skip recovery. |
| `Sync / Dedup Audit Log` | panel | Per-account "what was deduped this sync" (read-only). |

### Mode A — Cash transaction
1. User enters: **amount**, **date**, **vendor**, **description**, **Sub-Cat** (per §2.3.1 two-level cash-flow taxonomy: Income / Expenses / OtherCF).
   - *Recurring-vendor inference:* same merchant → system suggests the Sub-Cat last assigned to it (suggestion only).
2. **Edit existing transaction — including Plaid-sourced.** Editing a Plaid-sourced transaction **preserves its `plaid_transaction_id` linkage** — a re-download finds the existing record by ID and does not re-create it, no matter how the content diverged (vendor rename, amount tweak, date correction, Sub-Cat re-classification all stick).
   - *Decision point — source:* manual transaction → fully editable, plain save · Plaid-sourced transaction → editable, save preserves the ID linkage (the edit is authoritative over the next resync).

### Mode B — AcctSetup non-cash event
1. User sets transaction type = **AcctSetup**, then picks an **event subtype** from a generic enumeration:
   - **split** — ratio + ex-date; system propagates quantity adjustments across affected positions.
   - **transfer-in-kind** — source account + destination account + position + cost-basis carry-over (preserves original basis).
   - **other** — free-text non-cash event with per-event fields.
2. *Generic AcctSetup mode is V1; event-type-specific wizards are V2+.*
3. Plaid-surfaced and user-entered AcctSetup events are **peers** — neither path canonical; the `reconciled_flag` elevates whichever the user designates as ground truth.

### Sub-flow — Transaction Split
- User splits one Plaid transaction (e.g., grocery charge → Groceries + Home Goods).
  - *System:* original Plaid transaction marked **split-and-skip-flagged** — retained for audit, **excluded** from aggregations and from re-creation on resync. User-created children are independent records with **no `plaid_transaction_id`**.

### Sub-flow — Delete (implicit skip, Axis C1)
- User deletes a transaction.
  - *System:* record retained server-side with **`skip_flag=true`** so the next Plaid resync does **not** re-create it. Surfaces under `Deleted / Skipped Transactions`.
  - **Recovery:** user can **un-skip** from that view if deleted in error.

### Sub-flow — Dedup on resync (silent, with audit)
- *System (on Plaid resync):* **silent dedup** — Plaid `transaction_id` (primary key) matched against existing records; **content hash** as secondary key for splits / absent-or-reassigned IDs. Matched records silently skipped.
- An **on-demand `Sync / Dedup Audit Log`** under the account's sync-history exposes "what was deduped this sync" for inspection. *(Silent in the stream; never silent on demand.)*

### Sub-flow — Sell-transaction tax attribute: wash-sale flag *(BACK-ANNOTATION added 2026-05-27 to reconcile §2.5.1 wash-sale commitment, via §2.5 PM-2 — this locked doc was edited post-lock; not silent)*
- On a **sell transaction's** edit, the user can mark a **wash-sale flag** and enter a **disallowed-loss-amount** field (the loss disallowed under wash-sale rules). PRD 2.5.1 specifies this as "user-marked on the underlying sale transaction" (V1 — marking, NOT auto-detection); §2.4 originally omitted it only because §2.4 didn't drill tax.
  - *System:* the flag + amount **travel with the sell transaction**; **§2.5.1 consumes them** (F-2.5.B) to exclude the disallowed-loss amount from that transaction's ST/LT column. §2.5 surfaces live-recompute.
  - **Validation:** disallowed-loss amount **≤ the realized loss on that transaction**; tenant-scoped (ARCH handoff A4).
  - **Scope:** user-**MARKED** only — wash-sale **auto-detection** stays V2+/§2.5. *(Section 1256 60/40 is marked via the §2.2.1 `Volatility-60/40` Sub-Cat, not here.)*

### Error / edge states
- **Manual-entry validation failure** — required fields per mode (cash: amount/date/Sub-Cat; AcctSetup: subtype + subtype-specific fields). Bad value → inline field error; save blocked.
- **Manual-entry conflict with synced data** — handled two ways and never destructively: (a) editing a Plaid transaction is *authoritative* (ID-linkage preserved — no conflict, the edit wins); (b) genuine balance divergence between user-computed and Plaid-reported state is surfaced through **reconciliation** (F-2.4.D), not silently overwritten.
- **AcctSetup cost-basis cascade** — transfer-in-kind basis carry-over and split-quantity propagation have downstream cost-basis effects (Appendix B flag (f), Architect Phase-3). UX surfaces the input fields; the cascade is computed server-side.

### Out of scope — V1/V2 per 2.4.3
Event-type-specific AcctSetup wizards (V2+); auto-reconcile-on-balance-match B3 (V2+); CSV bulk-import of historical transactions (V2+); free-text rules-engine auto-categorization beyond recurring-vendor inference (V2+). **Lot-level tax features and wash-sale / Section-1256 _auto-detection_** (FIFO/LIFO/specific-ID, automatic wash-sale detection, automatic 1256) route to **§2.5** and are V2+, not here. *(Distinct from the user-**marked** wash-sale flag input added in the sub-flow above — that input field lives here per the §2.5.1 commitment; only auto-detection is deferred/§2.5.)*

---

## 5. FLOW F-2.4.D — Reconcile an Account
**Traces:** PRD 2.4.3 (reconciliation, Axes A/B/C/D). **Two firing modes** — per-transaction (B1) and bulk (B2). **B3 auto-reconcile is V2+.**

### Screen list
| Screen | Type | Role |
|---|---|---|
| `Reconcile-Through` action | inline action + confirm | B1 — reconcile through a specific transaction. |
| `Balance Mismatch Diff` | panel | Surfaces the user-computed vs Plaid-reported diff to investigate. |
| `Reconcile Mode` | full screen / mode | B2 — walk anchor-date balance checks across accounts (monthly cadence). |

### Mode B1 — Per-transaction reconcile
1. From `Account Detail` → `transaction-list`, user clicks **"reconcile through this transaction"** on a specific row.
   - *System:* runs the **balance-consistency check** through that transaction's date — compares the user's computed balance (or position state, for investment accounts) up to date X against Plaid's reported balance at date X.
   - **Decision point — check result:** **match** → sets `reconciled_flag=true`, `reconciled_at=now`; row shows reconciled marker · **mismatch** → surfaces `Balance Mismatch Diff` for the user to investigate before re-running. *Reconcile is not forced through on mismatch.*

### Mode B2 — Bulk reconcile mode
1. User enters **`Reconcile Mode`** (monthly cadence matching the existing-system workflow).
   - *System:* walks anchor-date balance checks across accounts.
2. User resolves mismatches as a **batch**; the `reconciled_flag` is set on the transactions anchoring each successful check.
   - **Decision point per account:** clean check → flagged reconciled · mismatch → held in the batch's unresolved list with its `Balance Mismatch Diff` until the user resolves (edit a transaction via F-2.4.C, add a missing one, or accept and re-run).

### Error / edge states
- **Mismatch (the core edge case)** — never auto-resolved; always surfaced as a diff. The owner investigates (this is the "manual-entry conflict with synced data" surface in its analytic form).
- **Stale source** — if the account is pending re-auth or stale beyond threshold, its Plaid-reported balance may itself be stale; the reconcile surface must carry the staleness marker (§6) so the user doesn't reconcile against stale truth.
- **Balance-check tolerance threshold** — TBD by Architect Phase-3 (Appendix B flag (d)). UX shows match/mismatch as a binary state driven by that threshold.

### Out of scope — V1/V2 per 2.4.3
Auto-reconcile-on-balance-match (B3, V2+). V1 keeps reconcile manual-anchored.

---

## 6. FLOW F-2.4.E — Re-authenticate a Plaid Connection (credential lifecycle)
**Traces:** PRD 2.4.4. **Cadence: reactive only** — prompt to re-auth only *after* Plaid surfaces an authentication error on a sync attempt. **No pre-emptive reminders (V2+).**

### Screen list
| Screen | Type | Role |
|---|---|---|
| `Re-Auth Banner` | **global chrome** | Persistent, state-driven, idempotent in-session banner; visible until re-auth completes. |
| `connection-status-panel` | panel (in `Account Detail`) | Per-account state + last-successful-sync + re-auth affordance. |
| `Re-Auth (Plaid Link update mode)` | external (Plaid-hosted) | Credential re-entry — in-session only, at the institution's portal via Plaid Link. |

### Connection-state vocabulary (the four §2.4.4 data-model states — Appendix B flag (h) hands UX the *presentation*)
| State | What happened | User action | UX presentation |
|---|---|---|---|
| `ITEM_LOGIN_REQUIRED` | Institution credentials invalid | User re-auths via Plaid Link | **Actionable** — "Re-authenticate" affordance; banner + chip. |
| `INSTITUTION_DOWN` | Plaid reached institution; it's offline | **None** | **Informational** — "Institution temporarily unavailable"; no action button; not a credential failure. |
| Institution-side grant revoked | Institution withdrew Plaid's grant | User acts at the institution side | **Actionable-elsewhere** — "Re-authorize at [institution]"; explains the action is at the institution. |
| User-side grant revoked at institution | User revoked Plaid on institution's portal | User re-authorizes there, *then* re-auth here | **Two-step** — "Re-authorize at [institution] first, then re-authenticate here." |

> The **data-model distinction holds in V1** (Appendix B flag (h)); these four presentations are the V1 "finer UX presentation" the PRD assigned to Phase 2. `ITEM_LOGIN_REQUIRED` is the only one that completes entirely in-app via Plaid Link; the other actionable two require an institution-side step first.

> **Inactive Plaid accounts (Sec V1-SHIP-BLOCK item 3) — distinct from the four credential states above.** Inactive is an account-lifecycle state orthogonal to credential state. An inactive Plaid account's `connection-status-panel` persists **read-only**, displaying **"Still connected to Plaid — sync paused," NOT "disconnected"** — the Plaid Item + access token are retained server-side per the locked SD-03 `bounded-Item-active-only` posture (the connection genuinely still exists; only sync is paused). Last-successful-sync timestamp is retained for reference. The panel shows in the Inactive group on `Accounts Hub` and on `Account Detail`. **Full disconnect is not a V1 capability** (un-share = V2+; see F-2.4.F §6A + ARCH handoff A3).

### Steps
1. **Trigger.** A sync attempt returns a Plaid auth error.
   - *System:* sets the account's connection state to the matching state above; raises the **`Re-Auth Banner`** (persistent, idempotent — one banner regardless of how many syncs fail); marks the `connection-status-panel` on `Account Detail`; **threads the staleness marker** to every consuming aggregation surface.
2. **User notices.** Banner is visible app-wide until resolved. Banner → deep-links to the affected account's `connection-status-panel`.
3. **User initiates re-auth** (`ITEM_LOGIN_REQUIRED` path): clicks "Re-authenticate this account."
   - *System:* opens **Plaid Link in update mode**, in-session only. Credentials entered only at the institution's portal inside Plaid Link. On success, server exchanges the returned token via `/item/public_token/exchange`; **client never holds it**; stored server-side, credential-class protection.
   - **Decision point — re-auth outcome:** success → state returns to `Fresh`, banner clears, staleness markers clear on next sync · user exits Plaid Link without completing → state unchanged, banner persists · grant-revoked states → user must complete the institution-side step first; "Re-authenticate here" stays disabled/secondary until that's done.

### Cross-cutting: Non-silent staleness (headline V1 commitment — authored here)
- **`stale-data-marker`** *(component, not a screen)* — every aggregation that consumed data from an account currently pending re-auth (or stale beyond the freshness threshold) **visually marks the stale-account contribution.** Consuming surfaces (downstream clusters; dependency flagged): §2.1.2 NAV trajectory, §2.1.5 composition table, §2.2.2 allocation table, §2.3.2 cash-flow rollup, §2.3.4 Historical Expenditures, §2.6 monthly report.
- **The contract:** aggregations are NEVER silently presented as fresh when a constituent account is pending re-auth or stale. This is the single most important cross-cluster UX commitment from §2.4. Every other cluster's flows must accept the `stale-data-marker` as an input.
- **Freshness threshold** ("sync stale beyond threshold") is governed by the Lock 11 cron cadence (Architect Phase-3); UX presents stale-vs-fresh as a state, threshold value set by backend.
- **Inactive Plaid accounts contribute NO `stale-data-marker` and raise NO `Re-Auth Banner` (Sec V1-SHIP-BLOCK item 2).** Transitioning a Plaid account to inactive **clears any `Re-Auth Banner` it was currently raising**. An inactive account that later accumulates a credential error stays **silent on the user-facing surface** — no banner, no marker (it's excluded from current-state aggregations anyway). The error is still recorded backend-side (ARCH handoff A2) and surfaces only if/when the account is reactivated (F-2.4.F §6A). **Sec rationale:** suppressing re-auth prompts for a retired account keeps the phishing-training surface narrow — this is security-positive, not a gap.

### Error / edge states
- **Re-auth abandoned** — banner persists; no partial state; user can retry anytime.
- **`INSTITUTION_DOWN`** — explicitly NOT a re-auth prompt; informational only; no banner action button (avoid teaching the user to enter credentials when nothing is wrong — narrower phishing surface, the V1 trade-off).
- **Re-auth completes but next sync still errors** — state re-evaluates on the next sync; if still failing, banner re-raises (idempotent, not duplicated).

### Out of scope — V1/V2 per 2.4.4
Pre-emptive re-auth reminders (V2+); re-auth via email/SMS (never — in-session only); webhook-driven credential-state mutation requires signature verification before V1 ship (Appendix B flag (k), Sec hard-line — backend gate, not UX).

---

## 6A. FLOW F-2.4.F — Mark a Plaid Account Inactive / Reactivate (account lifecycle)
**Traces:** PRD 2.4.1 + 2.4.2 (inactive-flag pattern). **Resolves Flag PM-1** — F/CTO ratified **Option 1** (2026-05-27): mark-inactive **applies to Plaid accounts in V1 as a display + sync-pause flag**; genuine un-share / disconnect stays **V2+**. Sec confirmed **no veto** — the locked **SD-03 `bounded-Item-active-only`** posture already anticipated this — **conditioned on the flow making the credential-retention non-misleading**, which this flow does. *(All four sub-items below are Sec V1-SHIP-BLOCK.)*

> **Why a distinct flow from F-2.4.B's manual mark-inactive (V1-SHIP-BLOCK item 1):** a manual account has no Plaid Item and no token, so retiring it is a plain display state. A Plaid account's Item + access token **stay live server-side** after going inactive (sync merely pauses), so the user must never be led to believe they've "disconnected." This flow carries a **mandatory disclosure step** and a connection-state display that tells the truth.

### Screen list
| Screen | Type | Role |
|---|---|---|
| `Mark Plaid Account Inactive — Confirm` | modal | Disclosure + confirm; **distinct from** the manual retire. |
| `connection-status-panel` (inactive variant) | panel (read-only) | "Still connected to Plaid — sync paused." |
| `Reactivate Plaid Account` action | inline action + confirm | Resume sync; re-auth only if a credential error accumulated. |

### Sub-flow — Mark a Plaid account inactive (V1-SHIP-BLOCK item 1)
1. From `Account Detail` (a Plaid account) → **Mark inactive**.
   - *System:* opens `Mark Plaid Account Inactive — Confirm` carrying the **mandatory disclosure**: **"Hides this account and pauses sync. Does NOT disconnect from Plaid — the connection and access token are retained server-side. Full disconnect is not available in V1."**
2. User confirms.
   - *System:* sets the account inactive → moves it to the Inactive group on `Accounts Hub`; **pauses the scheduled poll** for the Item (ARCH handoff A1); **clears any `Re-Auth Banner` this account was raising** (item 2); removes its contribution from current-state aggregations and **stops contributing any `stale-data-marker`** (item 2). Transaction history retained read-only.
   - **Decision point:** confirm → inactive · cancel → no change, account stays active.

### Inactive connection-state display (V1-SHIP-BLOCK item 3)
- The `connection-status-panel` persists **read-only** for the inactive Plaid account, showing **"Still connected to Plaid — sync paused," NOT "disconnected."** Last-successful-sync timestamp retained.
- An inactive account that later hits a credential error does **NOT** raise a banner and does **NOT** surface a `stale-data-marker` (item 2). The error is recorded backend-side (ARCH handoff A2); the user-facing surface is suppressed until reactivation.

### Sub-flow — Reactivate (V1-SHIP-BLOCK item 4)
1. From `Accounts Hub` Inactive group or `Account Detail` → **Reactivate**.
   - *System:* because the Plaid Item is still live, **resumes the scheduled poll**; the account rejoins current-state aggregations.
   - **Decision point — accumulated credential error?** If a credential error accumulated while the account was inactive (recorded backend-side per A2), reactivation lands the account in the matching §6 credential state and raises the `Re-Auth Banner` as normal — so **re-auth is needed only in that case**. Otherwise reactivation needs no re-auth; sync simply resumes.

### Error / edge states
- **Confirm dismissed** — no state change; account stays active.
- **Reactivate into an accumulated error** — handled as above; routes into F-2.4.E rather than failing the reactivation.
- **No full-disconnect path** — intentional V1 boundary; the flow never offers a "disconnect / remove" affordance.

### Out of scope — V1/V2
Genuine un-share / disconnect (Plaid `/item/remove` + token deletion) is **V2+** (ARCH handoff A3). V1 inactive = display + sync-pause only, token retained per SD-03.

---

## 7. Open decisions to surface to F/CTO (NOT decided unilaterally)

### Open Decision 1 — App-level navigation model *(TIMING: recommend defer to Step 3)*
§2.4 does **not** force the global navigation model. It needs only the assumption that an "Accounts" destination exists. Picking tabs-vs-sidebar-vs-drill-down now, off one cluster, risks rework once the read-heavy clusters (§2.1/§2.2/§2.3/§2.5/§2.6) reveal their navigational weight.
- **Recommendation:** defer the nav-model decision to the **Step 3 F/CTO walk-through**, once all six clusters are drilled and the full screen set is visible. Carry "Accounts hub exists" as a working assumption until then.
- *(Options A/B/C — tabs / sidebar / drill-down — to be presented with full tradeoffs at Step 3 against the complete screen inventory, not now.)*

### Open Decision 2 — New-symbol classification surfacing pattern *(info-hierarchy; §2.4.1)*
The PRD names both a **notification-queue badge** and the §2.2.2 allocation table's **`Unsorted` row**. Where the classification *task* primarily lives is a legitimate UX choice:
- **Option A — Notification-queue inbox (dedicated `New-Symbol Classification Queue`).** Badge → queue → classify one at a time. *Pro:* a clear, single task home; discoverable; matches PRD's "notification-queue badge" language. *Con:* a second place to look beyond the allocation table.
- **Option B — Inline-in-allocation-table.** Classify directly by expanding the §2.2.2 `Unsorted` row. *Pro:* contextual — you classify where you see the gap; fewer screens. *Con:* buries an onboarding task inside an analytic surface; entangles §2.4 with the §2.2 cluster; easy to miss at first connect.
- **Option C — Hybrid (RECOMMENDED).** Badge + queue is the canonical task surface; the allocation `Unsorted` row deep-links into the queue. *Pro:* discoverable from both the post-connect moment and the analytic surface; honors both PRD mentions. *Con:* slight redundancy (two entry points to one task).
- **Recommendation: Option C.** Can be confirmed at the Step 3 walk-through alongside the §2.2 cluster (the allocation-table half lives there).

### Open Decision 3 — Re-auth banner placement in global chrome *(couples to Open Decision 1)*
The banner's *existence* is PRD-locked (§2.4.4: "persistent in-app banner... remains visible until re-auth completes"). What's open is its **placement/persistence style** in the app chrome — which depends on the nav model.
- **Recommendation:** the banner is locked; defer its *placement* (top-of-viewport global bar vs. docked notification region vs. per-screen header slot) to the Step 3 nav-model decision, since it's global chrome. Both the global banner **and** per-surface `stale-data-marker`s ship (PRD mandates both); this is not an either/or.

---

## 8. Scope-creep / ambiguity flags for PM *(route to PM, not designed around)*

### Flag PM-1 — Does "mark inactive" apply to Plaid-connected accounts? — ✅ **RESOLVED (F/CTO ratified Option 1, 2026-05-27)**
**Resolution:** F/CTO ratified **Option 1** — mark-inactive **applies to Plaid accounts in V1** as a **display + sync-pause flag**; genuine un-share / disconnect stays **V2+**. Sec confirmed **no veto** (the locked SD-03 `bounded-Item-active-only` posture already anticipated this), conditioned on the flow making credential-retention non-misleading. **Folded into the flows as:** new flow **F-2.4.F (§6A)** + the §6 inactive⇄staleness/re-auth interaction (banner-clear, no marker while inactive) + the inactive connection-state display ("still connected — sync paused") + ARCH handoffs **A1–A3**. The original ambiguity + my tentative lean (which matched the ratified outcome) are retained below for decision-history.
- *Original ambiguity:* PRD 2.4.1 says "manual un-share of an already-shared Plaid account is V2+ **unless §2.4.2's inactive-flag pattern covers the use case.**" PRD 2.4.2 described "mark inactive" in the **manual-account** context ("closed or sold"). The flow-level question was whether the owner could mark a *Plaid-connected* account inactive in V1, or whether Plaid accounts had no V1 lifecycle-end affordance.
- *Tentative lean (now ratified):* extend "mark inactive" to Plaid accounts (read-only retention, excluded from current-state, token retained), keeping genuine "un-share" (revoking Plaid's grant) as V2+.

### Flag PM-2 — No account-delete; confirm "mark inactive" is the only V1 lifecycle-end. *(confirmation)*
PRD grants "mark inactive" but not account deletion. My flows include **no account-delete affordance** (inactive retains history for accuracy). Confirm this is the intended V1 posture (vs. a hard-delete being an unstated expectation).

### Flag PM-3 — `Accounts Hub` / `Account Detail` as derived navigational containers. *(traceability confirmation)*
These two screens are structure derived from explicitly-granted capabilities (edit attributes, mark inactive, connection-state view, add account, sync/dedup audit). Confirm they map to existing §2.4 stories and don't read as scope extension. *(Low risk — listed for completeness in the traceability pass.)*

---

## 9. Consolidated screen inventory (for the eventual Visual handoff — NOT final until Step 3 lock)
*Provisional. Names are the proposed shared vocabulary across PM / Visual / Frontend.*

| # | Screen / surface | Type | Flow | Traces |
|---|---|---|---|---|
| 1 | `Accounts Hub` | full screen | container | 2.4.1/2.4.2/2.4.4 (derived) |
| 2 | `Account Detail` | full screen | container | 2.4.2/2.4.3/2.4.4 (derived) |
| 3 | `Connect Institution — Launch` | transient | F-2.4.A | 2.4.1 |
| 4 | `Plaid Link` | external | F-2.4.A | 2.4.1 |
| 5 | `Account Setup — Attributes` | full screen | F-2.4.A | 2.4.1 |
| 6 | `Initial Sync — Progress` | full screen/state | F-2.4.A | 2.4.1 |
| 7 | `New-Symbol Classification Queue` | full screen/panel | F-2.4.A | 2.4.1 |
| 8 | `Symbol Classification` | panel/modal | F-2.4.A | 2.4.1 |
| 9 | `Newly-Available Account Prompt` | modal | F-2.4.A | 2.4.1 |
| 10 | `Add Manual Account` | full screen | F-2.4.B | 2.4.2 |
| 11 | `Transaction Entry` | panel/modal | F-2.4.C | 2.4.3 |
| 12 | `Transaction Split` | panel/sub-mode | F-2.4.C | 2.4.3 |
| 13 | `Deleted / Skipped Transactions` | full screen/panel | F-2.4.C | 2.4.3 |
| 14 | `Sync / Dedup Audit Log` | panel | F-2.4.C | 2.4.3 |
| 15 | `Reconcile Mode` | full screen/mode | F-2.4.D | 2.4.3 |
| 16 | `Balance Mismatch Diff` | panel | F-2.4.D | 2.4.3 |
| 17 | `Re-Auth Banner` | global chrome | F-2.4.E | 2.4.4 |
| 18 | `Re-Auth (Plaid Link update mode)` | external | F-2.4.E | 2.4.4 |
| 19 | `Mark Plaid Account Inactive — Confirm` | modal | F-2.4.F | 2.4.1/2.4.2 |
| 20 | `Reactivate Plaid Account` action | inline action | F-2.4.F | 2.4.1/2.4.2 |

Cross-cutting components authored here (not screens): `connection-status-chip`, `connection-status-panel` (incl. **inactive read-only variant** — "still connected, sync paused"), `stale-data-marker`, `account-row`, `notification-queue badge`.

---

## 10. PRD §2.4 story → flow traceability (for the PM consult)
| PRD story | Covered by | Notes |
|---|---|---|
| 2.4.1 Plaid onboarding + new-symbol surfacing | F-2.4.A (+ screens 3–9) **+ F-2.4.F** | Share decision, attributes, sync, Unsorted, classification queue, newly-available opt-in; **Plaid mark-inactive/reactivate lifecycle**. |
| 2.4.2 Manual account onboarding | F-2.4.B (+ `Account Detail` edit/inactive) **+ F-2.4.F (Plaid inactive-flag pattern)** | Single-pass; non-credential surface; manual lifecycle = edit + simple mark-inactive; **Plaid lifecycle takes the distinct F-2.4.F path**. |
| 2.4.3 Manual transaction entry + reconciliation | F-2.4.C + F-2.4.D | Cash + AcctSetup + split + delete/skip + dedup audit; reconcile B1/B2. |
| 2.4.4 Re-auth + credential lifecycle | F-2.4.E + `connection-status-panel` + `Re-Auth Banner` + `stale-data-marker` | Four-state vocabulary; reactive cadence; non-silent staleness; **inactive⇄banner/staleness interaction (F-2.4.F)**. |
| 2.4.5 Write paths are the user's | §0.2 + §8 (constraint, all flows) | Tenant-scoping on every write; no cross-tenant UI; no sharing UI. Not a screen. |

**No flow exceeds its PRD story.** All V1/V2 boundaries from §2.4 are respected (out-of-scope items enumerated per flow). **Flag PM-1 RESOLVED** (F/CTO Option 1 → folded in as F-2.4.F + Sec V1-SHIP-BLOCK items 1–4 + ARCH handoffs A1–A3); Flags PM-2/PM-3 remain isolated for the traceability pass rather than designed in.

---

## Phase 3 ARCH handoffs
Captured for cross-team routing when Phase 3 spins up (per ADR-012). Backend / architecture concerns, **not UX surfaces**. **A1–A3** are from the **Sec PM-1 consult** (mark-inactive-on-Plaid) and constrain F-2.4.F; they compose with **ADR-011 Decision 8 / Lock 4** + the **§6 privileged-context-write discipline**. **A4** is a later **back-annotation from the §2.5 PM-2** cross-cluster reconciliation.

- **A1 — Scheduled-poll suspension.** Marking a Plaid account inactive **suspends the scheduled-poll (`pfin_back_etl`) for that Item.**
- **A2 — Backend recording continues for inactive Items.** **Webhook signature verification (RT-05) + SD-14 state-history recording CONTINUE for inactive Items** — only the user-facing surface is suppressed, not the backend recording. *(This is why a credential error can "accumulate while inactive" and surface on reactivation — see F-2.4.F reactivate sub-flow.)*
- **A3 — Token retained on inactive; revoke-on-inactive is NOT V1.** **Inactive does NOT delete the SD-03 token** (retain per `bounded-Item-active-only`). **Revoke-on-inactive is explicitly NOT V1.** **V2 un-share = Plaid `/item/remove` + token deletion.**
- **A4 — Wash-sale flag immutability + validation** *(added 2026-05-27 via §2.5 PM-2; Architect / Sec under Appendix B §2.4 flag (j) manual-entry write-path integrity).* The §2.4.3 sell-transaction **wash-sale flag + disallowed-loss-amount**: whether it is a **mutable-annotation field** vs. **part of the Lock 5 reverse-and-replace immutable record** is Architect/Sec's call under the **Lock 10 immutability mechanism**. **Validation wrinkle:** disallowed-loss amount **≤ the realized loss on that transaction** + tenant-scoped.

---

## 11. Status / next
- **✅ §2.4 LOCKED** (PM traceability PASS + PM-1 resolved Option 1 + Sec re-verify PASS). All five required error/edge states covered (Plaid Link failure → F-2.4.A; item disconnected/re-auth → F-2.4.E; sync stale beyond threshold → §6 + F-2.4.E; manual-entry conflict with synced data → F-2.4.C + F-2.4.D; manual-entry validation failure → F-2.4.B / F-2.4.C).
- **Sec fold-in (2026-05-27):** F/CTO ratified PM-1 Option 1; 4 Sec V1-SHIP-BLOCK items folded (F-2.4.F §6A + §6 inactive⇄banner/staleness + inactive connection-state display); ARCH handoffs A1–A3.
- **POST-LOCK BACK-ANNOTATION (2026-05-27, via §2.5 PM-2):** added the user-marked **wash-sale flag + disallowed-loss-amount** field to the F-2.4.C sell-transaction edit (reconciles the PRD 2.5.1 "user-marked wash-sale flag on the sale transaction" commitment §2.4 had omitted) + the §2.4.3 out-of-scope clarification (marked-flag here vs. auto-detection V2+/§2.5) + ARCH handoff **A4** (immutability mechanism + validation). F/CTO heads-up given; edit is PRD-locked scope, marked traceably.
- **Next:** §2.6 monthly report is the final cluster; then the Step 3 F/CTO walk-through gate; then wireframing (Step 4).
- **No wireframing** until the Step 3 gate confirms the flow set.
