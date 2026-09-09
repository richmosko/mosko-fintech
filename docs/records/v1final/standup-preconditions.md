# Stand-up preconditions — attach-at-Link + historical categorized-transaction backfill (PM scope, Round 3)

**Status:** PM draft, Round 3 — every §F question is ruled (Q5 / Q7 / Q8 at §G.4); the three Linear blocks (§B.3 / §C.8 / §C.6) are **FINAL** for the liaison (§H); the operator allowlist is booked at BACKLOG §7.36 · **Baseline:** `main` @ `2387ae74` (Round 2 merged at PR #665) · **Date:** 2026-09-08, 21:00 (repo clock, `-0700`; = 2026-09-09 UTC, the date the brief carries) · **Author:** PM · **Round 1:** `bf026480` · **Round 2:** `5277d14f` (superseded sections are named, not deleted from history) · **Inputs:** PRD §2.3 / §2.4 / §3.4 / §6 / §7.3, SECURITY §4.2 / §4.6, ADR-027 / ADR-034 / ADR-036 / ADR-037 / ADR-053, BACKLOG §5.4 / §7, migrations `015` / `021` / `042`, `workers/provider-sync/src/ingest/accountMapper.ts`, `docs/records/self217-nav-seeding-run.md`, `docs/records/v1final/self365-protocol.md` §B.1 / §B.5 / §G, Linear (read-only) SELF-383 / SELF-386 / SELF-387, and the team-lead's Plaid-dashboard measurements of 2026-09-08 evening (§G.1).

**Ratify state — nothing assumed.** Round 2 applied **Q4 → S1**, **Item 1 struck** (Q1 / Q2 / Q3 / Q6 moot) and **Item 1 replaced** by the attach-at-Link build (§B). Round 3 applies **Q5 / Q7 / Q8** (§G.4). What follows the merge of this round, in order: the liaison creates I-1 / I-2 / I-3 from §H (**no Linear write precedes that merge**); the PRD amendment PR (§A.3, with P-3 re-worded by Q5); the operator allowlist (BACKLOG §7.36) is built before production signup is switched on. The `⟨OPEN⟩` markers are facts a named role confirms at stand-up, not decisions.

**Round 3 change log (from `5277d14f`):** header re-based · §0 D-11 / D-12 / D-13 added · §A.3 P-3 re-worded · §B.3 / §C.8 / §C.6 made self-contained Linear blocks (fields + AC) · §C.2 item 3, §C.4 loader row, §C.8 AC 2 apply Q7 · §D.2 applies Q8 and corrects the label + milestone names · §E-3 closed · §F marked ruled · §G.4 added · §H added.

**Round 2 change log (from `bf026480`):** §0 D-4 resolved, D-6 superseded, D-8 / D-9 / D-10 added · §A.1 struck and replaced · §B rewritten for the attach build · §C.4 / §C.5 / §C.8 folded (refusal boundary = cutover date; S1 ruled) · §D rewritten for three issues with Linear IDs · §E re-cut · §F reduced to three · §G added.

**The ruled sequence (F/CTO, 2026-09-08 evening):** **deploy → backfill walk (SELF-217 shape, into manual accounts) → attach-capable Link → Plaid connection → month-1 clock.**

---

## 0. Drift catches (read before the substance)

Read against the tree at `bd7b5987`. D-8 is load-bearing on the §B AC; the rest change where a reader should look.

| # | Brief says | Tree says | Effect |
|---|---|---|---|
| D-1 | "SECURITY §4.1 / §4.6 (Plaid + credential posture)" | §4.1 is *Tenant isolation posture*; the credential + external-API posture is **§4.2**. §4.6 holds the V2-ship-gate inventory. | Cited as §4.2 throughout. |
| D-2 | "BACKLOG §7 for SELF-201 import follow-ups" | SELF-201 shipped **§2.4.2 manual account onboarding** (migration `013` `fn_create_manual_account`); no import follow-ups. **There is no CSV/OFX import on the tree.** ADR-027's "CSV/OFX import + manual entry (SELF-201, shipped)" is a **false composite**. | The loader is BUILD (§C.4). ADR-027 wording debt → Architect (§E-7). |
| D-3 | "the 'restore/bulk-load runbook' booking in §7" | In the **MILESTONES head** "Open for F/CTO" list, not §7; `docs/deployment-runbook.md` is a stub. | Cited from MILESTONES. |
| D-4 | "SELF-386 / SELF-387 / SELF-383" | **Resolved (Linear, read-only, 2026-09-08 evening):** SELF-386 = *Production stand-up (Phase 7 entry; V1.final month-1 precondition)*, `role:devops`, Platform / Cross-cutting, blocks SELF-383 + SELF-387. SELF-387 = *V1.final (a) precondition: Backend M0 completeness check*, parent SELF-365. SELF-383 = *V1.final (c) month N: calendar month M counts under the R12 six-clause definition*, parent SELF-365, blocks SELF-384 / SELF-385. None appears in the tree. | §D.2 relations use the IDs. |
| D-5 | "byte-identity check like SELF-217" | SELF-217's record carries an **identity-agreement** line, not a byte-identity check. | §C.6 asks for the agreement line **plus** an input-file sha256. |
| D-6 | "Plaid allows 10 'free' Items … already at 9" | **Superseded by §G.1:** the old team is deleted; the new team is a **Trial plan with 10 free Production Items**, none spent. The number is now a measured dashboard fact, not an F/CTO recollection. | The app still must not *count to 10* (§E-10); the quota exposure moves from "1 slot left" to "10 shared slots" (Q5). |
| D-7 | (context) SECURITY §4.2 text | Still names `pfin.plaid_items` / `pfin.decrypted_plaid_access_token`, both dropped at `015`. | Sec-owned wording debt. **Round 1 offered the Item 1 §4.2 amendment as the vehicle; that vehicle is gone** — the debt stands on its own (§E-7). |
| **D-8** | "the matched-tenant trigger `fn_account_matched_linked_source` is BEFORE INSERT only, so an attach-by-UPDATE bypasses it" | **FALSE.** Migration `015` creates `account_matched_linked_source` as **`before insert or update on pfin.account … when (new.linked_source_id is not null)`**, and its `comment on function` says "Covers UPDATE (re-link path), not just INSERT." (The "BEFORE INSERT" phrasing in `accountMapper.ts`'s header comment describes the INSERT path it uses; it is not the trigger's definition.) | The §B AC does **not** extend the trigger. It **asserts** the existing fence on the new UPDATE path (a pgTAP leg: a cross-tenant `linked_source_id` set by UPDATE is rejected). Sec joint-review stays mandatory — Decision-3 instance #6 is *exercised on a new write path*, not extended. |
| **D-9** | "`accountMapper.ts` only INSERTs new rows on `(linked_source_id, provider_account_id)`" | True for the **worker** path. The **app's** landing path at `bd7b5987` is `pfin.fn_land_linked_accounts(p_linked_source_id, p_accounts jsonb)` (`042`, SECURITY INVOKER) called from `api/src/routes/api/plaid/exchange` + `accounts/connect/attributes` (SELF-199 account selection + attributes). It is also INSERT … `ON CONFLICT (linked_source_id, provider_account_id) DO UPDATE SET is_active = true` — **insert-only in effect; no path attaches to an existing row.** | The conclusion holds (schema yes / code no). The attach build lands in the **`042` RPC family on the api side** — the screen the user already meets — with `accountMapper.ts` as the worker-side consumer that must resolve attached rows (§B.4). |
| D-10 | "removals do not restore slots" (Plaid billing docs + help article) | External fact; nothing on the tree verifies it. | Carried as F/CTO-confirmed (§G.1); the remove-confirmation copy states it (§E-10). |
| **D-11** | (Round 3 brief) I-1 labels "`role:architect` + `role:backend` + `role:frontend` + `role:sec-review`" | `docs/linear-setup.md` § Label taxonomy names **`role:arch`** — there is no `role:architect`; the role set is `role:backend` · `role:frontend` · `role:arch` · `role:migration` · `role:sec-review` · `role:worker` · `role:fcto` · `role:pm`, and the doc states `role:qa` / `role:devops` **do not exist**. | §B.3 / §D.2 / §H use `role:arch`. The liaison does not invent a label; if a name in §H is absent live, it reports and leaves the label off. |
| **D-12** | (Round 3 brief) "Supabase Auth `enable_signup = false` in production (config; the local `supabase/config.toml` `[auth] enable_signup` shows the switch)" | `supabase/config.toml` `[auth] enable_signup = true` (and `[auth.email] enable_signup = true`) governs the **local CLI stack only**. Production is **self-hosted Supabase on Coolify** (ARCH §4); nothing on the tree — `secrets-manifest.yml` included, no `GOTRUE_*` anywhere — carries the production switch. | The intent is right, the file is not the mechanism. The production knob (GoTrue's disable-signup setting on the auth container, or its Coolify equivalent) is a **DevOps CONFIG fact named at SELF-386**, and whether an admin invitation still creates the F/CTO's user with signup disabled is `⟨OPEN⟩ DevOps` there — not asserted here. |
| **D-13** | (Round 3 brief) "a check in `api/src/routes/api/plaid/link-token/+server.ts` and the re-auth start route" | Both exist: the link-token route (SELF-197 relay leg 1; mints via the worker's `/admission/link-token`, holds no Plaid secret) and **`api/src/routes/api/reauth/start/+server.ts`** (with `reauth/complete`) — under `api/reauth/`, not `api/plaid/`. | §7.36 names both paths. Where the check sits (api route before the relay, or the worker admission endpoint) is Architect/Sec's call inside §7.36; the AC fixes the behavior, not the layer. |

---

## A. V1 / V2 / never — first

### A.1 Item 1 — direct Plaid Item registration ("advanced setup") — **STRUCK from V1 (F/CTO 2026-09-08 evening)**

The premise is gone: the Items the ruling wanted to adopt were minted under a Plaid team that **no longer exists** (§G.1); their `access_token`s were never held; a new team starts at 0 of 10 free Production Items. There is nothing to adopt, so there is nothing for an adoption path to do at stand-up.

**Disposition: V2 candidate at most.** One-line booking at **BACKLOG §5.4** ("Register an existing Plaid Item by credential"), landed in this PR so the idea is findable without re-litigating it. It is *not* a permanent non-goal — the product need ("an Item Link cannot re-mint") can recur under any quota — but it has no V1 trigger. **Q1 / Q2 / Q3 / Q6 close as moot** (§F).

**Round 1 §B (adoption story, posture options O1–O3, verification steps, nine Sec triggers, nine ACs) is retired with it.** It is in history at `bf026480`; whoever scopes the V2 candidate starts there, not from zero.

### A.1′ Replacement — **attach a provider account to an existing manual account at Link time** (V1-required, F/CTO 2026-09-08 evening)

**Why it exists.** Q4 ruled **S1**: the categorized history backfills **first**, into **manual** accounts, before any Plaid connection. Round 1's S1 losing side was "two `pfin.account` rows per real account forever, history on one and live data on the other, no re-link path". F/CTO asked whether an existing manual account can later gain Plaid data; the tree's answer (§G.3) is **yes by schema, no by code.** The attach build removes S1's losing side — it *is* the re-link path, scoped to the moment it is needed (Link completion) and nowhere else.

**V1 / V2 / never:** **V1**, by ruling and by dependency — without it the ruled sequence leaves the founding tenant with a split ledger on day one, which the A-3 M0 comparison would then read as a defect. Not a §6 axis. Not a §5 item pulled forward (§5.4's "manual un-share of an already-shared Plaid account" is the *opposite* direction and stays V2+). It is the **first app path that writes `linked_source_id` on an existing row** — the "re-link does not exist" fact BACKLOG §7 records (four-symptom entry) is partially discharged by it and must be re-read at ratify.

**Story trace.**
- **§2.4.1** — "Account selection now happens **at connect time**, where an unwanted institution-side account is simply never imported." The attach choice is a third outcome of that same selection step: *import as new* / *don't import* / **attach to an existing manual account**. Same screen, same tenant-scoped write.
- **§2.4.2** — "Once created, all transactions on the account come through §2.4.3 manual entry." **This is the sentence the build amends:** an attached manual account's transactions come through the provider **from its cutover date forward**, and through §2.4.3 before it (and still by hand after it, as today for any provider account).
- **§2.4.3** — unchanged; the boundary sentence gains the one-time-run clause from A.2 only.
- **§2.4.4 / SECURITY §4.2** — **unchanged.** No credential is entered by anyone; Link mints and exchanges exactly as shipped. Round 1's P-4 (ii)–(iv) qualifications of "the client never holds a long-lived access credential" are **withdrawn**.

**PRD amendment needed: YES — P-4 re-purposed.** (i) §2.4.1 connect-time selection paragraph: add the attach outcome and the cutover rule in one sentence; (ii) §2.4.2: qualify the "all transactions … through §2.4.3" sentence as above; (iii) Appendix B §2.4: routing flag (Architect-led, Sec joint) for the attach write path; (iv) Appendix C: 2.4.1 + 2.4.2 trace rows. Nothing in §2.4.4 or §4.2 moves.

### A.2 Item 2 — historical categorized-transaction backfill — **stands as scoped (Round 1 §A.2), one fold**

**Ruled V1 as a supervised operator run, NOT as the §2.4.3 product surface** — the SELF-217 pattern applied to transactions (§C). **Fold (F/CTO 2026-09-08 evening):** the loader's per-account refusal boundary and `pfin.account.backfill_cutover_date` are **the same fact** (§C.5). The loader **writes** the column; the attach build **honors** it. Round 1's E-8 ("wire it or annotate it as reserved") resolves to **wire it**.

**PRD amendment needed: YES, P-5 as before plus one clause.** §2.4.3 V1/V2 boundary, after the CSV-bulk-import clause: "A one-time supervised import of the founding user's categorized transaction history — the §2.1 NAV-import pattern, run by the operator and recorded at `docs/records/v1final/backfill-run.md` — is a V1 stand-up step, not this product surface; each imported account carries the import's last date as its provider cutover (§2.4.1)." Plus Appendix C 2.4.3 trace row.

### A.3 Amendment vehicle

One PRD PR after this round merges, folded with the booked P-1 / P-2 / P-3 (protocol record §H; BACKLOG §7.35 item 2) as **P-4** (attach: §2.4.1 / §2.4.2 / App. B / App. C) and **P-5** (backfill: §2.4.3 / App. C). No Sec-owned §4.2 edit rides with it any longer.

**P-3 re-worded by Q5 (§G.4).** The protocol record booked P-3 as "§7.3 *single user (the F/CTO) … closed and invite-controlled* → open signup + email confirmation per ADR-036". It now reads: **§7.3 states a single tenant, created by invitation, for the V1.final soak (production signup off), and open signup + email confirmation per ADR-036 once the operator allowlist on the Link-token and re-auth start routes lands (BACKLOG §7.36).** Reconciliation with ADR-036: its open-signup ruling stands as the *product shape* and is not re-opened; the soak narrows the *deployment posture* for a stated reason (the per-`client_id` Item quota, §E-3) with a named exit. The §5.7 cross-reference and the §2.1 / §2.2 / §2.3 "single user" story sentences are swept in the same PR as booked. Sec read-only on P-3 as before.

---

## B. Attach a provider account to an existing manual account at Link time

### B.1 User story

> As a tenant who created manual accounts and populated their history before connecting the institution, when Link completes I can, **for each account the provider surfaces**, choose an existing manual account to attach it to — or "new" — so the provider's data lands on the account that already holds my history, from the day after my history ends, and my ledger never has two rows for one real account.

Vocabulary (per the tree): a **provider account** is one `AccountRef` in the adapter's post-Link enumeration (`provider_account_id` = Plaid's `account_id`); a **manual account** is a `pfin.account` row with `linked_source_id IS NULL` (`021`'s partial-index exemption); **attach** = setting `linked_source_id` + `provider_account_id` on that row by UPDATE; the **cutover** is `pfin.account.backfill_cutover_date`, documented at `015` as "arbitrates import (≤) vs aggregator (>)" and read by no code today.

### B.2 What the user sees (§2.4.1 connect-time selection, extended)

- The shipped post-Link screen (SELF-199: account selection + per-account attributes) gains, **per provider account**, a third choice beside *import* / *skip*: **attach to …** with a picker over the tenant's manual accounts that are (a) not already linked, (b) not closed (ADR-042), (c) of a compatible `account_type` (compatibility rule: Architect/Backend; the picker filters, the server re-checks).
- An attached account **keeps its name and attributes** — the picker is choosing the row the history lives on; the provider's name is shown beside it for confirmation, never applied silently. (Whether the provider's `scope` / `tax_treatment` may overwrite the manual row's values: **no** — those were user-set; the screen shows both and the user keeps theirs unless they edit.)
- The screen states the cutover it will apply — "provider transactions dated on or before ⟨cutover⟩ will not be imported; your existing entries stand" — and, when the account has **no** rows, that the cutover is empty (the provider history lands in full).
- **Failure states, each named:** *manual account already attached to another provider account* (the `021` unique index would fire — refuse before it does); *closed account* (ADR-042: refuse; reopen first); *incompatible type*; *cross-tenant* — the `015` #6 fence raises; the surface renders a non-disclosing refusal and the picker never lists another tenant's accounts in the first place (RLS).
- The §2.4.4 connection-state view shows the attached account like any provider account, with its cutover visible somewhere the user can find it (an audit fact).

### B.3 Linear issue I-1 — FINAL (the liaison copies this block verbatim; §H)

- **Title:** §2.4.1 Attach a provider account to an existing manual account at Link time (backfill_cutover_date honored on ingest)
- **Project:** Onboarding / Plaid / Manual entry · **Native milestone:** none on the tree for this project beyond *V1.0 — Onboarding minimal path (full §2.4)* (`docs/linear-setup.md` §3); leave unset unless a V1.final milestone exists live in the project, and report either way · **Labels:** `V1.final` · `role:arch` · `role:backend` · `role:frontend` · `role:sec-review` (D-11) · **Parent:** none (Q8 ruled — a product capability that outlives V1.final)
- **Relations:** **blocks SELF-386** (AC 4 part 2 cannot complete without it). No relation to I-2 / I-3 (parallel builds).
- **Source:** this record §B.1 (story) · §B.2 (what the user sees) · §B.4 (Sec triggers) · §B.5 (losing side) — the description is those four sections copied · PRD §2.4.1 / §2.4.2 (amended by P-4, §A.3) · ADR-034 D2/D3 · migrations `015` (`backfill_cutover_date`, trigger `account_matched_linked_source`) / `021` (partial unique index) / `042` (`fn_land_linked_accounts`) · `workers/provider-sync/src/ingest/accountMapper.ts`.
- **Dependencies:** upstream — SELF-386 AC 1–3 (deployed target; stated here, not drawn: SELF-386 is the issue this one blocks); the Architect primitive (AC 2) is authored inside this issue; PRD P-4 (AC 11). Downstream — SELF-386 AC 4 part 2 (attach-capable Link); the post-connection seam section of `backfill-run.md` (I-3, §C.6).
- **Acceptance criteria:**

1. **Choice per provider account.** At Link completion, for each provider account, the user selects an existing eligible manual account or "new"; "new" behaves exactly as today (`042` INSERT path). A test drives the screen with two provider accounts, attaches one and creates one, and asserts the resulting `pfin.account` row count is +1, not +2.
2. **Attach is an UPDATE on the chosen row** setting `linked_source_id` + `provider_account_id`, under the caller's RLS (`account_update` policy, `003` + `025` aal2 clause), in the **same transaction** as the sibling INSERTs — one landing, all or nothing. Architect authors the primitive (extend `fn_land_linked_accounts` with an optional `attach_account_id` per entry, or a sibling RPC — Architect's call; either way SECURITY INVOKER, no DEFINER growth, allowlist unchanged — stated so it is checked).
3. **Cutover set.** On attach, `backfill_cutover_date` := the account's latest existing `transaction_date` at attach time (NULL when the account has no rows). When the loader already stamped it (§C.5) the two agree by construction; a disagreement is refused, not resolved silently.
4. **Ingest discards on/before cutover.** Provider transaction rows for an account whose cutover is non-NULL and whose `transaction_date ≤ cutover` are **not landed** (filter in the worker ingest path `mapper.ts` → `fn_ingest_transactions`, or in the RPC — Architect/Backend; Sec joint because it is a privileged-write filter). A test loads a manual row at date D, attaches, ingests provider rows at D−1 / D / D+1 and asserts only D+1 lands. Rows the filter discards are **counted in the sync summary** ("N rows before cutover skipped"), never silently.
5. **The #6 fence fires on the UPDATE path.** A pgTAP leg attaches a manual account to a `linked_source_id` owned by the other fixture tenant by UPDATE and asserts the `015` trigger raises (per D-8: the trigger already covers UPDATE; this leg proves it on the new path, and would RED if anyone ever narrowed the trigger to INSERT).
6. **`021` uniqueness on the UPDATE path.** Attaching a second provider account to an already-attached row is refused before the unique index fires, with the named message; a test asserts the refusal and that no partial write occurred.
7. **Closed / incompatible / foreign accounts never appear in the picker** and are refused server-side if submitted (defense in depth; a test submits a closed account's id directly).
8. **Post-attach parity.** An attached account then passes the same battery a Link-created account passes: webhook-driven sync (SELF-206), scheduled poll, update-mode re-auth, close-gate behavior — run against an *attached* row.
9. **`accountMapper.ts` / `resolveAccountIds` resolve attached rows** — the worker's provider→account map must find a row that was attached (not inserted) by `(linked_source_id, provider_account_id)`; a test asserts a sync after attach resolves every provider account and reports zero `unresolvedAccounts`.
10. **Sec joint-review attached** (§B.4); posture recorded in the PR body with the losing side.
11. **PRD P-4 merged** before close (§A.3).

### B.4 Sec joint-review triggers (mandatory — every one)

1. **Decision-3 canonical instance #6 exercised on a new write path** (UPDATE of `pfin.account.linked_source_id` from the app). Not an extension (D-8) — but the first app path that sets the column on an existing row; the fence's UPDATE arm has had no caller until now.
2. **Multi-tenant isolation** — the picker (RLS-scoped read), the attach write (RLS `account_update` + #6), and the ingest filter (a privileged-context write under `service_role` that now *drops* rows on a per-account column value — a wrong cutover silently loses provider data; a NULL-vs-non-NULL confusion loses all of it).
3. **Plaid** — account selection semantics change on the exchange path; `/item/remove` on failure (the shipped C6-4 guard) must still fire for a failed landing that includes attaches, and must **not** leave a half-attached row (AC 2's one-transaction property).
4. **Money flows** — the cutover decides which provider transactions exist in the ledger; §2.3 and cash-NAV read the result.
5. **`fn_land_linked_accounts` signature change** — a PostgREST `/rpc` API contract (per its `comment on`); Sec grades whether the p_accounts object-key growth is a new surface.
6. **DEFINER allowlist untouched** — asserted, not assumed.

### B.5 Losing side of the attach design (recorded, not asked)

- **A cutover is a hole-maker as well as a dedup.** If the history file's last date per account is **earlier** than the provider's earliest available transaction, the gap between them is a hole no path fills; if it is **later**, the provider rows in the overlap are dropped and the manual rows stand. The walk (§C.6) records the file's last date per account; `⟨OPEN⟩ Backend`: how far back the production Plaid initial pull reaches for a fresh Item (`transactionsSync` has no `days_requested` on the tree; `investmentsTransactionsGet` takes an explicit `start_date` range) — the walk names any hole per account.
- **The attach choice is one-way in V1.** Detaching (UPDATE back to NULL) is not built; the `015` trigger is WHEN `new.linked_source_id IS NOT NULL`, so a detach would not even be fenced. Named so its absence is a decision; BACKLOG §5.4 candidate if F/CTO wants it findable.
- **The ADR-042 close gate composes.** An attached account that is later closed accepts no provider rows (shipped behavior); nothing new.

---

## C. Historical categorized-transaction backfill (supervised walk) — stands, with the cutover fold

### C.1 Framing — the SELF-217 precedent, applied to transactions

SELF-217 seeded `pfin.nav_daily` from the incumbent sheet: dry-run by default, `--commit` explicit, an explicitly bounded date range with no defaults, **one transaction** (all rows or none), a structural refusal boundary, `ON CONFLICT DO NOTHING` re-runnability, dollars printed in dry-run, a **tracked-safe summary** (no `$`, uid prefix only) pasted into a record, and `pfin_etl` re-disarmed after (ADR-053 D5–D8; `docs/records/self217-nav-seeding-run.md`). The loader reproduces every one of those properties against `pfin.account_trans` + `pfin.account_trans_annotation`.

**What the F/CTO holds:** "a few years of already categorized transactions" — the incumbent per-account workbooks (§2.3.3 parity text). Format unknown to the tree; the loader's input format is whatever the F/CTO exports, normalized once. **Under S1, every target account is a manual account** the F/CTO creates on the deployed app (§2.4.2, SELF-201) before the run — one per real account, named for the institution account it will later be attached to.

### C.2 Inputs

1. **The transaction file(s).** One row = one transaction: incumbent account label, date, amount (signed, dollars), vendor, description, incumbent category label(s). CSV (the only reader precedent, `parse_baseline_csv`); the loader states the exact header contract in its usage text. Input file **sha256 recorded** (§C.6).
2. **The account map** — incumbent account label → `pfin.account.account_id` (the manual account) for the target tenant. Authored by the F/CTO, checked into the record (labels only). Every incumbent label must map; an unmapped label **refuses the run**.
3. **The category map** — incumbent category label → `pfin.user_taxonomy (cat, sub_cat)` for the tenant's **cashflow** domain; near-identity by construction (§2.3.1 / ADR-057); the loader prints the unmapped set on dry-run. **Unmapped categories — Q7 ruled (i): the run is refused until the category map is complete** (§G.4). The dry-run prints every unmapped label with its row count so the map can be finished; the long tail of one-off incumbent labels is **mapped or folded** into an existing Sub-Cat before `--commit`. Not taken: landing unmapped rows unclassified under the §2.3.2 banner. Taxonomy CRUD stays V2+; a category with no seeded home is **mapped** to an existing Sub-Cat, not created.
4. **Trades and non-cash events are out.** Mechanical-vocabulary rows (ADR-058: trades, splits, transfers-in-kind, instrument legs) are **refused** — the loader lands cash-flow rows (§2.3.1 classifiable items) only. Security-bearing history is a separate, unasked import (§E-5).

### C.3 The classification model the rows land in (capability facts)

- A landed row is an `account_trans` row plus a **`023` annotation** row (`sub_cat_id → user_taxonomy`). GL / `tax_character` posting is **derived** downstream; the loader writes category, never postings.
- Write primitives on the tree: (a) `pfin.fn_create_manual_trans(p_account_id, p_transaction_date, p_amount, p_vendor, p_description, p_sub_cat_id, p_note, p_import_hash)` — SECURITY INVOKER, one row + annotation atomically, aal2-gated, no bulk variant; (b) `pfin.fn_ingest_transactions(p_rows jsonb)` — SECURITY INVOKER bulk insert, provider-key dedup `ON CONFLICT (source_provider, provider_txn_id) DO NOTHING`, **no annotation**. Which primitive (or a new annotation-aware bulk RPC — Architect) is Backend/Architect's design call.
- **The incumbent categories are the user's own** (§2.3.1); a landed assignment is a user assignment, history-preserving under Lock 10 / ADR-031.

### C.4 WALK vs BUILD (PM-sorted; Round 2)

| | Item | Who |
|---|---|---|
| **BUILD** | **The loader** — one-shot script reproducing the SELF-217 contract against transactions: input contract, account + category maps, refusal set (unmapped account label, unmapped category label — Q7 ruled: refuse, print the unmapped set with counts — mechanical-vocabulary row, any date on/after an existing provider row for that account — the S1 case has none), dry-run report (rows per account, per-category counts, date span, **last date per account**, refused rows with reasons, dollar totals per account for the eyeball check), one transaction on `--commit`, tracked-safe summary, and **`backfill_cutover_date` stamped per account = that account's last landed `transaction_date`** (§C.5). Node, to reuse the canonical `computeImportHash` — a third hash copy in Python is the ADR-034 D4 one-way door's failure mode. | Backend (+ Architect if a bulk RPC is authored) |
| **BUILD** | **Cutover honored on ingest** — the read side of the same fact; lives in the attach issue (§B.3 AC 4), not here. Round 1's "decide, then maybe build" is decided: **wire it.** | Architect + Backend (attach issue) |
| **WALK** | Creating the manual accounts (§2.4.2) on the deployed app; producing the export + the two maps; dry-run locally against a scratch DB (`supabase db reset` discipline); reviewing the printed figures; `--commit` against production; pasting the tracked-safe summary into the record. | F/CTO with Backend at the keyboard |
| **WALK** | The restore/bulk-load runbook section describing this run (MILESTONES open item; `deployment-runbook.md` stub) — written from the run. | DevOps + Backend |
| **CONFIG** | Scratch-DB load check at the real row count before trusting a loop-of-RPC loader (untested, not known-slow). | Backend |

### C.5 The refusal boundary and the cutover date are one fact — the load-bearing finding, folded

**Facts (ADR-034 D2/D3 + migration `040`):** manual↔provider dedup on this tree is **DETECTION-ONLY** — the `004` hard-unique `(account_id, import_hash)` index was relaxed so a manual row and its provider echo coexist; `pfin.manual_provider_dup_candidate` surfaces exact-hash pairs one at a time; an incumbent descriptor that differs from Plaid's text is not even a candidate. Nothing auto-suppresses. "Dedup expectations" are met by **making the overlap empty**, not by dedup.

**Under S1 (ruled):** at backfill time the target accounts are manual and hold no provider rows, so the Round 1 refusal boundary ("earliest provider-sourced date") is vacuous in the forward direction — the loader refuses nothing on that axis. The boundary that matters is the **reverse** one: the provider must not land what the backfill already holds. That is exactly what `backfill_cutover_date` was documented to arbitrate at `015` ("import (≤) vs aggregator (>)"). So:

- **The loader writes the cutover** — per account, `backfill_cutover_date := max(transaction_date)` of the rows it lands, in the same transaction (a `pfin.account` UPDATE under the impersonated tenant's RLS; the `015` trigger does not fire — `linked_source_id` stays NULL).
- **The attach path reads/reconciles it** (§B.3 AC 3) and **ingest honors it** (§B.3 AC 4).
- **Re-runnability:** rows carry `source_provider='import'` (in the `015` vocabulary) and a **deterministic `provider_txn_id`** derived from the source row, so a re-run is a no-op through the `017` provider-key arbiter; `import_hash` is still computed and stored so the detection view keeps working for hand-entered rows. A re-run with a *longer* date range moves the cutover forward — allowed before attach, **refused after attach** (the cutover is then load-bearing on the provider path; moving it is a different operation the walk does not need).

**S2 / S3 (Round 1) are retired:** F/CTO ruled S1 and the attach build removes S1's losing side. Recorded, not re-asked.

### C.6 Linear issue I-3 — the backfill walk and its record `docs/records/v1final/backfill-run.md` — FINAL (the liaison copies this block verbatim; §H)

- **Title:** Backfill walk — founding tenant's categorized transaction history into manual accounts (backfill-run.md)
- **Project:** Platform / Cross-cutting · **Native milestone:** *V1.final — §3.4 close mechanism* (the SELF-365 children's milestone per the protocol record §B common fields; Round 2's "V1.x — Cross-cutting infra" is corrected) · **Labels:** `V1.final` · `role:backend` (Backend at the keyboard; the F/CTO drives) · **Parent:** SELF-365 (Q8 ruled; sibling of SELF-387)
- **Relations:** **blocked by I-2** (the loader); **blocks SELF-387** (and through it SELF-383). Its deploy dependency on SELF-386 AC 1–3 is stated in the description, **not** drawn — SELF-386 already blocks SELF-387, and I-3 → SELF-386 → I-3 would be a cycle.
- **Source:** this record §C.1 (the SELF-217 precedent) · §C.2 (inputs; Q7 ruled at item 3) · §C.5 (the cutover fold) · the record shape below — the description is those sections copied · `docs/records/self217-nav-seeding-run.md` · ADR-053 D5–D8.
- **Dependencies:** upstream — I-2 merged and deployed; SELF-386 AC 1–3 (deployed target) and AC 4 part 1 (the F/CTO tenant exists, one manual account per real account, §2.4.2); the export + the two maps (F/CTO). Downstream — SELF-387 (M0 completeness), SELF-383 (month-1 clock); the seam section needs SELF-386 AC 4 part 2 (the Plaid connection through I-1).
- **Acceptance criteria:**
  1. Before any run: the manual accounts exist on the deployed app, one per real account; the account map names each; the category map is complete (Q7 — a dry-run listing zero unmapped labels is the evidence).
  2. Dry-run on a scratch DB at the real row count (`supabase db reset` discipline), figures reviewed by the F/CTO; then `--commit` against production with Backend at the keyboard; the writer role armed for the run and re-disarmed after, recorded (SELF-217 shape).
  3. The record below is merged with every pre-connection section filled (run date + deployed sha, input sha256 + row count, both maps labels-only, per-account admitted / refused / per-category counts — no `$` — and the cutover written, the tracked-safe summary verbatim, team-lead's read-back).
  4. **Done only after the Plaid connection** (SELF-386 AC 4 part 2): the post-connection seam section is appended — per attached account the provider's earliest landed date, rows skipped at the cutover, any hole, and the `manual_provider_dup_candidate` count (expected 0).
  5. Nothing in this issue writes code: a loader defect found during the walk is filed against I-2 (or a follow-up), never patched in-run.

**The record's shape** — same as `self217-nav-seeding-run.md`, with:
- run date (repo clock) and environment (production; deployed sha from the SELF-386 deploy log);
- input file name + **sha256** + row count (D-5);
- the account map and category map (labels only);
- **per account:** requested date span, rows admitted / refused (reason classes), rows per category (counts only — **no `$`**), and the **cutover written**;
- the tracked-safe summary verbatim: identity-agreement line (CLI-supplied vs DB-resolved uid, 8-char prefix — ADR-053 D5's writer obligation, which the loader implements), `--commit` / ack flags, one-transaction confirmation;
- post-run verification by team-lead from the tree (row counts read back; every backfilled account's cutover equals its max landed date);
- **after the Plaid connection:** per attached account, the provider's earliest landed date, the count of provider rows skipped at the cutover, and any **hole** between cutover and earliest provider date (§B.5) — the seam is a finding to name, not a dedup;
- whether any `manual_provider_dup_candidate` pairs exist after the first sync (expected 0).

### C.7 What it unlocks

- **SELF-387** — the Backend M0 completeness check finds the tenant's transactions for the whole of M0 *and the prior-period columns those surfaces read* (§2.3.2 Q1–Q4 / YTD; §2.3.4's 5-year window); without the run every multi-period cell is structurally N/A.
- **A-3** — the per-cell checklist over §3.3's §2.6 clauses gets a populated left-hand side for the cash-flow cells.
- **§2.3.4 Historical Expenditures** becomes meaningful at launch — the transaction analogue of the §2.1 NAV-import commitment.

### C.8 Linear issue I-2 — the loader — FINAL (the liaison copies this block verbatim; §H)

- **Title:** Historical categorized-transaction loader — SELF-217 shape; writes backfill_cutover_date
- **Project:** Platform / Cross-cutting · **Native milestone:** *V1.final — §3.4 close mechanism* (as I-3; Round 2's "V1.x — Cross-cutting infra" is corrected) · **Labels:** `V1.final` · `role:backend` · `role:sec-review` · plus `role:arch` if a bulk annotation-aware RPC is authored (§C.3; the liaison adds it only when Architect confirms) · **Parent:** SELF-365 (Q8 ruled; sibling of SELF-387)
- **Relations:** **blocks I-3** (the walk). No relation to I-1 (parallel build).
- **Source:** this record §C.1 · §C.2 (input contract, both maps, Q7 ruled at item 3, the mechanical-vocabulary refusal) · §C.3 (write primitives on the tree) · §C.4 BUILD row · §C.5 (the cutover fold) — the description is those sections copied · `docs/records/self217-nav-seeding-run.md` · ADR-053 D5–D8 · ADR-034 D2–D4 (`computeImportHash` canonical copy) · migrations `015` (`backfill_cutover_date`, `source_provider` vocabulary) / `017` (provider-key arbiter) / `023` (annotation) / `040` (detection-only dedup).
- **Dependencies:** upstream — none on the tree (a scratch-DB load check at the real row count is CONFIG inside this issue, §C.4). Downstream — I-3 (the walk); I-1 reads the column this writes (AC 3 / AC 4 there).
- **Acceptance criteria:**

1. Dry-run is the default; `--commit` writes; every run prints the §C.4 report (incl. last date per account) and the tracked-safe summary.
2. Bounded input: explicit date range per run, no defaults; account map + category map required; **an unmapped account label or an unmapped category label refuses the run** (Q7 ruled (i)); the dry-run report lists every unmapped label with its row count so the map can be completed (test: one unmapped category label → no write, the label and its count printed).
3. Every landed row has its annotation (`sub_cat_id` non-null) in the same transaction; a mechanical-vocabulary row is refused (test).
4. One transaction: a failure at row N leaves zero rows and no cutover written (test: bad row at the end; assert counts and `backfill_cutover_date` unchanged).
5. Idempotent re-run: `--commit` twice yields identical row counts and the same cutover (provider-key arbiter; test).
6. **Cutover stamped** per account = max landed `transaction_date`; a test asserts it; a run against an account whose `linked_source_id` is non-NULL is **refused** (post-attach runs are out of scope; test).
7. Tenant identity: impersonation binding + DB-resolved `auth.uid()` read-back; the summary carries the agreement line (ADR-053 D5).
8. Secret hygiene as SELF-217: the writer role armed for the run and re-disarmed after, recorded.
9. Sec joint-review attached (money flows / Lock 14 write paths; plus Architect if a bulk RPC is authored).

---

## D. Ordering + Linear shape

### D.1 Ordering (the ruled sequence, with Linear IDs)

```
SELF-386  AC 1–3   deploy at a named sha · NEW Plaid production creds (Trial, 10 Items) · gates walked
      │
      ├─ I-2  loader BUILD          ─┐  parallel; both Sec-joint
      ├─ I-1  attach BUILD          ─┘  (I-1 also Architect-authored primitive)
      │
      ▼
SELF-386  AC 4, part 1   F/CTO tenant signs up; manual accounts created (§2.4.2), one per real account
      │
      ▼
I-3   backfill WALK      loader dry-run → --commit → cutovers stamped → backfill-run.md
      │
      ▼
SELF-386  AC 4, part 2   attach-capable Link → Plaid connection; each provider account attached
      │                  to its manual account; first sync lands ABOVE each cutover
      ▼
backfill-run.md          post-connection seam section (holes / skipped counts) appended
      ▼
SELF-387                 Backend M0 completeness check → a-m0-completeness.md
      ▼
SELF-386  AC 4, part 3   tenant-accounts-live date written → M0 / M1 derived → month-1 clock (SELF-383)
```

The sequence is the ruled one verbatim: **deploy → backfill walk → attach-capable Link → Plaid connection → month-1 clock.** Both builds must be merged and deployed before AC 4 part 2; I-2 before I-3.

### D.2 Linear shape — three issues (Q8 ruled: as drafted; §G.4)

| | Title (proposed verbatim) | Project · milestone · labels | Relations |
|---|---|---|---|
| **I-1** | **§2.4.1 Attach a provider account to an existing manual account at Link time (backfill_cutover_date honored on ingest)** | Onboarding / Plaid / Manual entry · no native V1.final milestone on the tree (§B.3) · tag **V1.final** · `role:arch` + `role:backend` + `role:frontend` + `role:sec-review` (D-11) | **blocks SELF-386** (AC 4 part 2 cannot complete without it). **No parent** (ruled). Full block at §B.3. |
| **I-2** | **Historical categorized-transaction loader — SELF-217 shape; writes backfill_cutover_date** | Platform / Cross-cutting · **V1.final — §3.4 close mechanism** milestone · tag **V1.final** · `role:backend` + `role:sec-review` (+ `role:arch` if a bulk RPC) | **blocks I-3**. Parent: **SELF-365** (ruled; sibling of SELF-387). Full block at §C.8. |
| **I-3** | **Backfill walk — founding tenant's categorized transaction history into manual accounts (backfill-run.md)** | Platform / Cross-cutting · same milestone · tag **V1.final** · `role:backend` (Backend at the keyboard; F/CTO drives) | **blocked by I-2**; **blocks SELF-387** and, through it, SELF-383. Parent **SELF-365** (ruled). Full block at §C.6; "Done" = record merged with the post-connection seam section. Its *deploy* dependency on SELF-386 AC 1–3 is stated in the description, **not** drawn as a relation — SELF-386 already blocks SELF-387, and I-3 → SELF-386 → I-3 would be a cycle. |

**Why three, not Round 1's two:** the walk is a dated operator event with its own evidence (the record) and its own "Done"; carrying it on the loader issue stretched one-session granularity (ADR-017 D2) and hid the F/CTO's keyboard time behind a Backend issue. **Alternatives (losing side):** L-2′ — a parent "Stand-up preconditions" issue over all three (an object with no work of its own; parent/child is not blocking, so the edges above are drawn anyway); L-3′ — fold I-3 into SELF-386 as an AC (hides the F/CTO's walk and the Sec gate on I-2 behind a DevOps Done).

**Milestone call:** all three exist because of the month-1 clock → **V1.final** tag. Linear holds current + next only (ADR-017 D2); V1.final is current, so all three are created directly, no §7 staging. I-2 / I-3 take the SELF-365 children's native milestone (*V1.final — §3.4 close mechanism*, protocol record §B common fields) — Round 2's "V1.x — Cross-cutting infra" was the wrong shelf for SELF-365 children and is corrected. **Created only after this round merges;** the liaison creates from §H.

---

## E. Scope flags (Round 2)

- **E-1 (Round 1 O2 creep) — moot** with Item 1.
- **E-2 V2 creep — the product import surface.** §2.4.3 / §5.4 "CSV bulk-import of historical transactions" stays V2+; the loader is an operator script with no route, no form, no per-tenant reachability. If it grows an upload endpoint it has become the V2 feature.
- **E-3 → Q5 RULED (§G.4) — open signup × shared Item quota.** ADR-036 open signup + a **per-`client_id`** quota (10 free Production Items on the Trial plan; removals do not restore) means any tenant's Link session spends a slot the F/CTO's own institutions (≈ 4–6 Items) also draw on. **Ruled:** production signup stays **off** until an operator allowlist on the Link-token and re-auth start routes exists (BACKLOG §7.36); the F/CTO tenant is created by invitation; the N=2 soak runs with a sole tenant. The PRD carries it as the re-worded P-3 (§A.3).
- **E-4 PRD currently forbids.** "CSV bulk-import … V2+" (§2.4.3) — not amended; the one-time-run clause sits beside it (A.2). "Once created, all transactions on the account come through §2.4.3 manual entry" (§2.4.2) — amended by P-4 (A.1′). **The credential sentences (§2.4.1 / §2.4.4 / §4.2) no longer move.**
- **E-5 Unasked: security-bearing history.** "Categorized transactions" = cash-flow rows. Incumbent trade history for investment accounts is a different import (mechanical vocabulary, positions, cost basis; BACKLOG §7.3 G3 adjacent). Not scoped; named so its absence is a decision. **Under S1 this has a new edge:** an investment account attached at Link with a cutover gets provider *transactions* only after the cutover, and its positions from Plaid's holdings snapshot as-of connection — the pre-cutover position history stays absent unless E-5 is ever scoped.
- **E-6 V2 candidates booked at BACKLOG §5.4 (this PR, one line each):** *Register an existing Plaid Item by credential* (the struck Item 1); *Item-quota telemetry* (count / remaining / which tenant spent one); *detach a provider account from a manual row* (§B.5). Findable, not scheduled.
- **E-7 Tree wording debts surfaced, not fixed:** ADR-027's "CSV/OFX import … (SELF-201, shipped)" false composite (D-2 → Architect); SECURITY §4.2's dropped-table names (D-7 → Sec; **no PM vehicle any more**); `api/CLAUDE.md` "three locked allowlist endpoints" vs ADR-016's live four (→ Backend); `accountMapper.ts` header's "BEFORE INSERT" gloss on the #6 trigger (D-8 → Backend, one-line comment fix when the file is next touched).
- **E-8 `backfill_cutover_date` — resolved: wire it** (Architect authors the ingest filter in I-1; the loader writes it in I-2). Its `015` column comment already says what it does; after I-1 it is true.
- **E-9 CONFIG — Plaid credentials.** The old team's `client_id` in `workers/provider-sync/.env` (gitignored; present on disk at `bd7b5987`) is **stale and F/CTO's to replace**; `.env.example` says `PLAID_CLIENT_ID` is "shared with api/ + workers/etl/", so **three local surfaces plus the Coolify production env** take the new pair. Values are never recorded anywhere in the repo, this record, or chat. Lands as an AC on **SELF-386** ("new Plaid production creds"), not a new issue. `PLAID_ENV` production is gated by SELF-212 as before.
- **E-10 The Item cap as a product fact (compact; Round 1 §B.7 carried).** Per `client_id`, not per tenant; **removals do not restore** (D-10) — the remove confirmation for any Item says so; the app never counts to 10 (it knows only its own `linked_source` rows); at the limit Plaid refuses somewhere on the connect path — `⟨OPEN⟩ DevOps/Backend`: where and with what code, confirmed at SELF-386 against the production tier — and the connect flow renders that as a **named state** ("Plaid's Item limit for this deployment is reached; removing an Item does not free a slot"), never the generic 5xx. With Item 1 struck the message no longer points at an adoption path.

---

## F. What F/CTO was asked to rule — all three RULED (2026-09-08 late evening; §G.4)

The Round 2 leans and their losing sides stay as written, for the record; the **Ruling** column is what governs.

| # | Question | PM lean (Round 2) | Losing side of the lean | **Ruling** |
|---|---|---|---|---|
| **Q5** | Open signup × shared 10-Item quota (E-3): (a) gate Link behind an operator allowlist until the paid tier; (b) accept the exposure and watch; (c) close signup (ADR-036 inversion). | **(b) now, (a) before a second tenant exists** — no second tenant is planned inside the V1.final window, and (a) introduces a privilege concept the app does not have (§7.3 / ADR-036 have tenants, not roles), which is Sec posture work with no V1.final payoff. | If a stranger signs up during the window, their Link session spends a shared free slot and nothing in the app knows; (b) is a bet on the window's quiet, and the allowlist becomes urgent the day the bet loses. (c) is a one-way door on ADR-036 and is listed only so its rejection is explicit. | ✅ **A fourth option:** production signup **off** until an operator allowlist on the Link-token + re-auth start routes exists (§7.36); sole tenant by invitation through the soak. Not (a), (b) or (c) as posed. |
| **Q7** | Unmapped categories at backfill: refuse the run until the map is complete, or land unmapped rows unclassified under the §2.3.2 banner? | **Refuse.** The run exists to give M0 *categorized* history; a thousand-row unclassified banner is noise, and the map is the F/CTO's own vocabulary — completing it is minutes, not a build. | A stubborn label with no seeded home blocks the whole run until it is mapped somewhere; "map it to Suspense/Other" is the escape hatch, and it is a user assignment like any other. | ✅ **(i) Refuse** until the category map is complete. |
| **Q8** | Linear shape: three issues as §D.2 (I-1 no parent, I-2 / I-3 under SELF-365)? Or all three under a new parent (L-2′)? Or I-3 folded into SELF-386 (L-3′)? | **§D.2 as drafted.** I-2 / I-3 are V1.final protocol children like SELF-387; I-1 is a product capability with a life after V1.final and belongs with §2.4.1's issues. | Two parents for three issues of one stand-up; a reader following SELF-365 does not see I-1. L-2′ fixes that at the cost of an empty parent. | ✅ **§D.2 as drafted:** I-1 parentless in Onboarding; I-2 / I-3 under SELF-365; relations as drawn. |

**Closed in Round 2 (§G.2):** Q1 / Q2 / Q3 / Q6 — moot with Item 1; **Q4 — ruled S1** (backfill first, into manual accounts; attach at Link). **Closed in Round 3 (§G.4):** Q5 / Q7 / Q8. Nothing remains open for F/CTO in this record.

**Routing (still owed, now at build time):** §B (all) → **Security Engineer** (Decision-3 #6 on a new UPDATE path, ingest filter as a privileged-write drop, Plaid landing-path change, `042` signature); §B.3 AC 2 / AC 4 primitive + §C.3 bulk-RPC question → **Architect**; §B.5 / §E-10 `⟨OPEN⟩`s → **Backend / DevOps** at SELF-386.

---

## G. Rulings and facts (2026-09-08 evening)

### G.1 Facts (team-lead measured in F/CTO's Plaid dashboard; external to the tree)

- The **old** Plaid team ("Richard Mosko", Pay As You Go, Master Agreement 2026-07-14) held **6 Transactions / 4 Investments-Holdings / 3 Investments-Transactions** Items at Schwab, Fidelity, Capital One, Wells Fargo. Their `access_token`s were **lost** — the quickstart kept them in memory and the probe scripts are gone. No Item-listing API exists; Logs (14-day) and Link Analytics held nothing; Plaid Portal did not show them (no verified phone identity).
- F/CTO removed one Item created that day via `/item/remove` with a recovered token, then **deleted the team and created a new one**: a fresh **Trial plan, 10 free Production Items, new `client_id` + `secret`** (values never in the repo or chat). **The orphan-Item problem is closed.**
- **The 10-Item Trial cap is live again and removals do not restore slots** (Plaid billing docs + the help article "How do I stop billing…"). F/CTO's own four institutions ≈ **4–6 Items**.
- The stale `client_id` in `workers/provider-sync/.env` is F/CTO's to replace — a CONFIG item (§E-9), values never recorded.

### G.2 Rulings

- **Item 1 (direct Item registration / "advanced setup") — STRUCK from V1.** Nothing to adopt. V2 candidate at most (BACKLOG §5.4 one line). Q1 / Q2 / Q3 / Q6 close as moot.
- **Q4 → S1: backfill FIRST, into manual accounts, BEFORE the Plaid connection.** Item 1 is **replaced** by a new V1-required build: **attach a provider account to an existing manual account at Link time** (§B) — Architect authors the primitive; **Sec joint-review mandatory** (Decision-3 instance #6 on a new write path, multi-tenant isolation, Plaid).
- **Item 2 (loader + walk) stands as scoped**; the loader's per-account refusal boundary and `backfill_cutover_date` are **the same fact** (§C.5).
- **Q5 (open signup × shared quota)** — left open in Round 2; **ruled in Round 3 (§G.4)**.
- **Q7 / Q8** — left open in Round 2; **ruled in Round 3 (§G.4)**.
- **Ordering:** deploy → backfill walk (SELF-217 shape) → attach-capable Link → Plaid connection → month-1 clock (§D.1).

### G.3 The tree's answer to "can an existing manual account later gain Plaid data?" (verified at `bd7b5987`)

- **Yes by schema:** `pfin.account.linked_source_id` / `provider_account_id` / `backfill_cutover_date` (`015`) are nullable and purpose-built; the `021` partial unique index exempts unlinked rows; the `003` `account_update` RLS policy (+ `025` aal2 clause) permits the owner's UPDATE; the `015` `account_matched_linked_source` trigger is **`before insert or update`** and would fence the attach (D-8 — the brief's "INSERT only" is false).
- **No by code:** both landing paths — `fn_land_linked_accounts` (`042`, api side, the live SELF-199 screen) and `accountMapper.ts` (worker side) — INSERT new rows keyed `(linked_source_id, provider_account_id)`; nothing UPDATEs an existing row's link columns; nothing reads `backfill_cutover_date` (the only reference in app code is a comment in `accountMapper.ts`).
- **So:** the attach build is an app-path build over an existing, already-fenced schema — no new column, no Decision-3 family growth, no DEFINER growth (each asserted in §B.3, none assumed).

### G.4 Rulings (F/CTO, 2026-09-08 late evening — 2026-09-09 UTC; Round 3)

- **Q5 → a fourth option, not one of the three posed: production signup stays OFF until an operator allowlist on the Link-token route exists.**
  - *Taken:* Supabase Auth signup disabled in production (the production knob is a DevOps CONFIG fact, D-12); the F/CTO tenant is created **by invitation**; the N=2 months run with a **sole tenant**; the allowlist — a check on `api/src/routes/api/plaid/link-token/+server.ts` and `api/src/routes/api/reauth/start/+server.ts`, a small operator config surface, one copy string for a non-allowlisted tenant, a Sec read — is **built before** signup is switched on. Booked at **BACKLOG §7.36** (owner Backend + Frontend; Sec-visible; blocks "public signup on"). PRD §7.3 (P-3) re-worded accordingly and reconciled with ADR-036 (§A.3).
  - *Not taken:* (a) allowlist now — Sec posture work with no V1.final payoff while there is one tenant; (b) accept the exposure and watch — a bet on the window's quiet with no watcher; Pay-As-You-Go (lift the cap by paying) — trades a product control for a bill and still leaves the app blind to who spent a slot; (c) close signup permanently — an ADR-036 inversion, rejected.
  - *Losing side:* **the open-signup story is not exercised during the V1.final soak** — a confirmed-email public signup was walked at V1.0 and is not re-walked under the deployed sha until the allowlist lands; the first stranger's signup after that is a post-soak event with no soak evidence behind it. The invitation path is exercised instead (D-12's `⟨OPEN⟩` covers its behavior with signup disabled).
- **Q7 → (i): refuse the run until the category map is complete.**
  - *Taken:* an unmapped category label refuses the run (as an unmapped account label already did); the dry-run prints the unmapped set with row counts; the map is finished before `--commit`. Applied at §C.2 item 3, the §C.4 loader BUILD row, and §C.8 AC 2.
  - *Not taken:* land unclassified rows under the §2.3.2 banner.
  - *Losing side:* **the long tail of one-off incumbent labels must be mapped or folded before commit** — every stray label is a decision the F/CTO makes by hand, and the run cannot start until the last one is made; folding into an existing Sub-Cat is the escape hatch and is a user assignment like any other (Lock 10 / ADR-031).
- **Q8 → §D.2 as drafted (option 1).**
  - *Taken:* I-1 parentless in Onboarding / Plaid / Manual entry; I-2 and I-3 under SELF-365 (siblings of SELF-387); relations as drawn in §D.1 / §D.2.
  - *Not taken:* L-2′ one new parent over all three (an object with no work of its own); L-3′ fold the walk into SELF-386 (hides the F/CTO's keyboard time and the Sec gate on I-2 behind a DevOps Done).
  - *Losing side:* two parents for three issues of one stand-up; a reader following SELF-365 does not see I-1 — mitigated by the I-1 → SELF-386 blocking edge and this record.

---

## H. Liaison dispatch list (after this round merges; three issues, copied verbatim by heading)

Create in this order (I-2 before I-3 so the blocking edge has a target; I-1 in either position). Each block is self-contained: title, project, native milestone, labels, parent, relations, Source, Dependencies, AC. Every label name below was checked against `docs/linear-setup.md` § Label taxonomy at `2387ae74`; **if a label or milestone named in a block does not exist live, leave it off and report it — never create one** (label creation is F/CTO-owned). Return the three IDs and the read-back (title / project / milestone / labels / parent / relations) for the pre-merge ID audit.

1. **§B.3 Linear issue I-1 — FINAL** — *§2.4.1 Attach a provider account to an existing manual account at Link time (backfill_cutover_date honored on ingest)* — Onboarding / Plaid / Manual entry · labels `V1.final` `role:arch` `role:backend` `role:frontend` `role:sec-review` · no parent · **blocks SELF-386**. Description = §B.1 + §B.2 + §B.4 + §B.5.
2. **§C.8 Linear issue I-2 — FINAL** — *Historical categorized-transaction loader — SELF-217 shape; writes backfill_cutover_date* — Platform / Cross-cutting · milestone *V1.final — §3.4 close mechanism* · labels `V1.final` `role:backend` `role:sec-review` (`role:arch` only on Architect's word) · parent SELF-365 · **blocks I-3**. Description = §C.1 + §C.2 + §C.3 + §C.4 BUILD row + §C.5.
3. **§C.6 Linear issue I-3 — FINAL** — *Backfill walk — founding tenant's categorized transaction history into manual accounts (backfill-run.md)* — Platform / Cross-cutting · milestone *V1.final — §3.4 close mechanism* · labels `V1.final` `role:backend` · parent SELF-365 · **blocked by I-2**, **blocks SELF-387**. Description = §C.1 + §C.2 + §C.5 + the record shape in §C.6.

Not for the liaison: the operator allowlist (BACKLOG §7.36) is **staged, not created** — it has no milestone yet and gates a post-soak switch; PM promotes it when F/CTO names the milestone.
