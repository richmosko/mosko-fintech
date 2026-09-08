# Stand-up preconditions — direct Plaid Item registration + historical categorized-transaction backfill (PM scope draft)

**Status:** PM draft for F/CTO ruling · **Baseline:** `main` @ `bd7b5987` · **Date:** 2026-09-08 (repo clock, `-0700`) · **Author:** PM · **Inputs:** PRD §2.3 / §2.4 / §3.4 / §6 / §7.3, SECURITY §4.2 / §4.6, ADR-027 / ADR-034 / ADR-036 / ADR-037 / ADR-053, BACKLOG §5.1 / §5.4 / §7, `docs/records/self217-nav-seeding-run.md`, `docs/records/v1final/self365-protocol.md` §B.1 / §B.5 / §G, and the Backend read-only capability audit (scratchpad `backend-audit-plaid-backfill.md`, same baseline — cited below as **Backend audit §A–§D**; it is a `temp/`-class artifact, so every capability fact this record relies on is restated here, not pointed at).

**Assumed-ratify hook:** nothing below is ratified. Both items are F/CTO-ruled **V1** (2026-09-08); the *shape* of each — posture, ordering, Linear form — is what this record asks F/CTO to rule (§F). Post-ratify: surgical-fix deltas here, then the PRD amendment PR (§A.3) and the Linear creation (§D) — no Linear writes precede the ruling.

**The two rulings, F/CTO verbatim (2026-09-08):**

> "Plaid allows 10 'free' Items, and I am already at 9. I don't get those back... So we need a flow built in that allows an advanced setup where we can enter the Item credentials directly."

> "Before we do that Plaid connection, I want to walk through backfilling more than just the NAV data. I do have a few years of already categorized transactions that I want populated for my accounts."

Sequencing ruled: **deploy → backfill walk → Item registration → month-1 clock.** (§C.5 and §D.1 show where this order collides with account identity on the tree and offer the fix.)

---

## 0. Drift catches (read before the substance)

Read against the tree at `bd7b5987` before drafting. None is load-bearing on the rulings; two change where a reader should look.

| # | Brief says | Tree says | Effect |
|---|---|---|---|
| D-1 | "SECURITY §4.1 / §4.6 (Plaid + credential posture)" | §4.1 is *Tenant isolation posture*; the credential + external-API posture is **§4.2** ("Credential and external-API posture" — SD-03, RT-02 / RT-05, the Plaid OAuth-integrity bullet). §4.6 holds the V2-ship-gate inventory. | §4.2 is the section Item 1 collides with; cited as §4.2 throughout. |
| D-2 | "BACKLOG §7 for SELF-201 import follow-ups" | SELF-201 shipped **§2.4.2 manual account onboarding** (CHANGELOG: PRs #141–#143; migration `013` `fn_create_manual_account`). Its §7 deferred list is audit-log infra / UX copy / visual-fidelity — **no import follow-ups**. **There is no CSV/OFX import on the tree** (Backend audit §B: zero `csv`/`ofx` matches in `api/src` + `workers/provider-sync`; adapters are Plaid + SimpleFIN only). ADR-027's sentence "CSV/OFX import + manual entry (SELF-201, shipped) as first-class providers" is a **false composite** — SELF-201 is the manual half only; the import half was never built. PRD §2.4.1's "CSV/OFX import or manual entry where none does" is therefore half-true on the tree. | Item 2 has **no** loader to walk; the loader is BUILD (§C.4). ADR-027 wording debt noted for Architect (§E). |
| D-3 | "the 'restore/bulk-load runbook' booking in §7" | Not in BACKLOG §7 (grep `runbook` / `bulk-load`: two unrelated hits). It is in the **MILESTONES head** "Open for F/CTO" list, verbatim; `docs/deployment-runbook.md` is a stub. | Cited from MILESTONES, not §7. |
| D-4 | "SELF-386 / SELF-387 / SELF-383" | None of the three appears anywhere in the tree at `bd7b5987`; the protocol record's §H names them by letter (B.1–B.5). Read here as: **SELF-386 = B.5** production stand-up; **SELF-387 = the Backend M0 completeness check** (B.1 Dependency 2 — the brief says "SELF-387's M0 completeness check"); **SELF-383 = unresolved** (a SELF-365 sub-issue — B.2 or B.3 month-1 — team-lead to confirm). | §D's relations are written against the letters; the liaison substitutes IDs at creation. |
| D-5 | "byte-identity check like SELF-217" | SELF-217's record carries an **identity-agreement** line (CLI-supplied vs DB-resolved uid **AGREED**, 8-char prefix), not a byte-identity check. | §C.6 asks for the identity-agreement line **plus** an input-file sha256 — which is the closest thing to byte identity a run can record. |
| D-6 | (context) "Plaid allows 10 'free' Items" | An F/CTO-stated external fact; nothing on the tree verifies the number or the error Plaid returns at the limit. | §B.7 treats the cap as a provider quota of **unknown exact size**: the app must *render* Plaid's refusal, never *count to 10* itself. DevOps confirms tier + limit at B.5 AC 2's `⟨OPEN⟩`. |
| D-7 | (context) SECURITY §4.2 text | still names `pfin.plaid_items` / `pfin.decrypted_plaid_access_token` — both **dropped at migration `015`** (ADR-037 fact 1; live homes `pfin.linked_source` / `pfin.decrypted_source_credential`). BACKLOG §7 already notes §4.2's stale RT-26 composition. | Sec-owned wording debt; the Item 1 §4.2 amendment (§A.3) is the natural vehicle. |

---

## A. V1 / V2 / never — first

### A.1 Item 1 — direct Plaid Item registration ("advanced setup")

**Ruled V1 (F/CTO 2026-09-08).** PM concurs on the *narrow* form: the ruling is a stand-up precondition (the F/CTO's own institutions cannot all be Link-connected with one free Item left), not a general onboarding feature. The wide form (every tenant, always) is not required by the ruling and is where the V2 creep lives (§E).

**Story trace.** Two stories, and a gap between them:
- **§2.4.1 Connection initiation** — "hands off to the provider's authorization step … On success the system persists whatever access credential the provider issues … the client never holds a long-lived access credential." Link-only framing; no path admits a credential that already exists.
- **§2.4.4 Credential lifecycle** — "Any long-lived access credential a provider issues on successful re-auth is exchanged and stored server-side; the client never holds it." Same commitment, lifecycle side.
- **SECURITY §4.2 Plaid OAuth flow integrity** — "the access token never touches the client." Sec-owned restatement.
- **Gap:** no §2 story admits an Item whose access credential was issued outside this deployment's connect flow. Item 1 is a **new sub-story under §2.4.1** ("credential adoption"), not a re-reading of an existing one.

**§6 check:** no §6 axis covers it (not public distribution, money movement, advisory, real-time, or mobile). **§5 check:** not listed in §5.4; not a deferred item being pulled forward. **Not** a permanent non-goal being re-litigated.

**PRD amendment needed: YES.** (i) §2.4.1 — add a "Credential adoption path" paragraph after "Connection initiation" (Item 1's story, §B.1, at V1 scope with the gate F/CTO rules in §B.2); (ii) §2.4.1 + §2.4.4 — qualify "the client never holds a long-lived access credential" to "the client never *retains* …; the adoption path is the single, [gated] exception where the user *supplies* one, transiently, and the server stores it under §2.4.4's credential-class protection"; (iii) SECURITY §4.2's OAuth-integrity bullet — **Sec authors** the parallel qualification (PM does not edit §4.2). (iv) Appendix B §2.4 — a new routing flag (Sec-led / Architect joint) for the adoption surface. (v) Appendix C — a 2.4.1 trace row.

### A.2 Item 2 — historical categorized-transaction backfill

**Ruled V1 (F/CTO 2026-09-08) — as a supervised operator run, NOT as the §2.4.3 product surface.** The distinction is the same one the tree already draws for NAV: PRD §2.1 / Appendix C 2.1.3 commit V1 to importing the incumbent NAV history ("F/CTO has locked the *whether*; the *how* is routed to Architect"), SECURITY §4.6 shadow-workflow tear-down says that import "is a one-time event, not an ongoing sync", and SELF-217 delivered it as a dry-run-default script run by the F/CTO and recorded. Item 2 is that pattern applied to transactions.

**Story trace.**
- **§2.3.1** — the taxonomy "derives from the founding user's existing categorization" (ADR-036 / ADR-057); the categories the F/CTO's history carries are, by construction, near-identical to the seeded set. The rows Item 2 lands are §2.3.1 classifiable items with an assignment already known.
- **§2.4.3 V1/V2 boundary** — "CSV bulk-import of historical transactions V2+ (V1 ships single-transaction-at-a-time entry)"; mirrored at BACKLOG §5.4. **This is the PRD text that currently forbids Item 2 as a product feature.** It stays. The operator run is not that feature: no upload route, no form, no per-tenant surface.
- **§3.4(a) via A-3** (protocol record §G.2 / §B.1 AC 4) — the M0 manual §2.6 comparison needs V1 to *hold* the history the §2.6 clauses read; B.1 Dependency 2 (Backend M0 completeness check) is the gate that Item 2 exists to pass.
- **§4.6 shadow-workflow tear-down** — the precedent that a one-time import from the incumbent is inside V1's universe.

**§6 check:** none. **§5 check:** §5.4 "CSV bulk-import of historical transactions" stays V2+; Item 2 does not promote it. §5.1 "Historical NAV import beyond Dec-2015 parity import … bulk CSV import of NAV history for new tenants" stays V2+ (Item 2 is transactions, founding tenant only).

**PRD amendment needed: YES, one sentence.** §2.4.3 V1/V2 boundary, after the CSV-bulk-import clause: "A one-time supervised import of the founding user's categorized transaction history — the §2.1 NAV-import pattern, run by the operator and recorded at `docs/records/v1final/backfill-run.md` — is a V1 stand-up step, not this product surface." Plus Appendix C 2.4.3 trace row. Nothing else moves.

### A.3 Amendment vehicle

One PRD PR, after the ruling, folded with the already-booked P-1 / P-2 / P-3 (protocol record §H) as **P-4** (Item 1: §2.4.1 / §2.4.4 / App. B / App. C) and **P-5** (Item 2: §2.4.3 / App. C). Sec's §4.2 edit is a separate Sec-owned PR or a joint one — Sec's call.

---

## B. Item 1 — direct Plaid Item registration

### B.1 User story

> As the owner of a tenant who already holds a live Plaid Item minted under **this deployment's** Plaid `client_id` — an Item that Link cannot re-create because the free-Item quota is spent — I can register that Item by supplying its `access_token` and `item_id` directly, so its accounts flow into the app exactly as a Link-connected Item's would, without consuming another Item.

Vocabulary (precise, per the tree): an **Item** is Plaid's connection object; **`item_id`** is its public identifier and becomes `linked_source.external_connection_id` (ADR-037 D1); the **`access_token`** is the SD-03 credential-class secret stored as a Vault handle in `linked_source.credential_secret_id`. **Adoption** = admitting a pre-existing Item; **connection** = the Link path. The user-facing label F/CTO used is "advanced setup"; the app copy should say *Register an existing Plaid Item* — "advanced" describes the audience, not the action.

### B.2 Who can reach it — options (posture is Sec's; PM states product need + the losing side)

The ruling's wording — "a flow built in", "we can enter" — is satisfied by O1 and O3 below. O2 is wider than the ruling.

| | Option | What it is | Losing side |
|---|---|---|---|
| **O1** | **Operator-gated in-app surface** | An in-app form on the connections page, reachable only for tenants on an operator allowlist (deploy-time env, e.g. the F/CTO's `users_id`), otherwise absent from the DOM and refused server-side. | Introduces a *privilege concept the app does not have* — §7.3 / ADR-036 have tenants, not roles; an allowlist is a new auth surface Sec must posture (where it lives, who edits it, how it is audited). The gate is by identity, not by tier: a second operator means a second env edit. |
| **O2** | **Every tenant, behind an "advanced" disclosure** | The same form, visible to all under an expander with copy explaining what an access_token is. | The widest credential-entry surface: it trains every tenant to paste a live credential into a browser form (inverts §4.2's "never touches the client" for the whole population, not one operator), and every mistaken paste (wrong environment, someone else's token) becomes a support event. Not required by the ruling. |
| **O3** | **No UI — operator CLI on the worker** | Extend `workers/provider-sync/src/cli/admit.ts` with an *adopt* mode (`--access-token` read from **stdin or a file, never argv**; `--owner <users_id>`), lifting the SC3-C2 sandbox gate **only** for that mode under an explicit flag. Run by the F/CTO on the production worker, like SELF-217. | Strains "flow built in" (it is a shell command, not a screen); the credential transits an operator shell (history / `ps` exposure unless stdin-only); the C2 sandbox gate is "load-bearing" per its own header and would acquire an exception. No account-selection UI — the post-adoption attribute capture (§2.4.1 per-account attributes, SELF-199) still needs the app. |

**PM product note (not a posture call):** O1 and O3 both satisfy the ruling; O2 is scope creep and PM would not spend V1 on it. Between O1 and O3 the *product* difference is only the entry screen; the *posture* difference (browser credential ingress vs. operator shell ingress) is Sec's to weigh. **Sec must read this section before it is posture** — see §B.8.

### B.3 What is entered

- `access_token` (secret; SD-03 class from the moment it is typed) and `item_id` (public), for an Item minted under **the same Plaid `client_id` / environment** the provider-sync worker runs against in production. Nothing else: no institution id, no account list — those come from Plaid.
- **Config precondition (Backend audit §C gap 5, UNVERIFIED):** the F/CTO's 9 existing Items must have been minted under that same `client_id`. Tokens are client-bound; a token from another Plaid app fails at verification, and no adoption code changes that. **F/CTO question Q1 (§F).**
- **A second, harder precondition the ruling assumes:** the F/CTO must *hold* those Items' `access_token`s. Plaid has no token-recovery path — an Item whose token was not kept is not registrable by any flow, and Link would re-mint it as a *new* Item (quota-consuming). **F/CTO question Q2 (§F).**

### B.4 What the app verifies before adopting (from the Backend audit §A; capability facts, not design)

1. **Token liveness + ownership:** `/item/get` with the supplied token (**BUILD** — `itemGet` is not on `PlaidClientLike` today). A token from another client or environment fails here; that failure *is* the ownership check.
2. **`item_id` agreement:** the `item_id` Plaid returns must equal the one entered; on disagreement the app refuses ("token and Item ID do not belong together") rather than trusting the pasted id — the caller is a human, not Plaid's exchange response.
3. **Accounts enumerable:** `/accounts/get` succeeds with ≥ 1 account (already the admit path's first step).
4. **Product coverage:** `/item/get` reports the Item's products; if Transactions or Investments (ADR-027's V1 set) is absent, the app **surfaces** it ("this Item does not carry X; its data will be partial") and lets the user proceed or stop — it does not silently degrade. Whether to *block* is an F/CTO scope fact at ruling time (§F Q3).
5. **Uniqueness / tenant:** `(provider, external_connection_id)` unique (`015`); an Item already registered **to this tenant** re-admits in place (credential rotation via `vault.update_secret` — the shipped path); an Item registered **to another tenant** fails closed (SC3-C8, shipped) with a **non-disclosing** error ("this Item cannot be registered here").
6. **No revoke-on-failure.** The shipped `connect()` C6-4 guard calls `/item/remove` when admission fails after exchange. For an adopted, live, production Item — one of the nine — that guard is destructive and **must not be inherited** (Backend audit §A). Failure leaves the Item untouched at Plaid and nothing written here.
7. **Webhook target (BUILD, product-required):** an Item minted outside this deployment may carry no webhook URL or a stale one. For "identical to a Link-created Item" (B.6) to be true, adoption must set the Item's webhook to this deployment's endpoint (`/item/webhook/update` — not on the adapter today). Until it is set the Item is poll-only (SimpleFIN-shaped), which the connection-state view must not present as healthy-push.

### B.5 What the user sees

- **Success:** the same post-connect screen Link lands on — account selection + per-account attributes (§2.4.1; SELF-199) — then the Item in the §2.4.4 connection-state view as `healthy` with "registered (not via Link)" provenance visible somewhere the user can find it (an audit fact, not a badge of shame).
- **Failure states the UI must name (each a distinct message; none echoes the token):**
  - *token rejected by Plaid* (invalid / wrong environment / wrong client) — "Plaid did not accept this access token for this app";
  - *Item ID mismatch* (B.4.2);
  - *already registered — yours* → offered as re-registration (rotation), not an error;
  - *already registered — not yours* → non-disclosing refusal (B.4.5);
  - *needs re-authentication* (`ITEM_LOGIN_REQUIRED` at adoption) → **adopt anyway**, land in `login_required`, show the §2.4.4 banner — a needs-re-auth Item is still the user's Item and update-mode Link (shipped) repairs it without a new Item;
  - *partial products* (B.4.4);
  - *transport / unknown* → generic, scrubbed (SC3-C4), with the token-free diagnostic in the worker log.

### B.6 How the adopted Item behaves afterwards — identical to a Link-created one

Same `linked_source` row shape, same `connection_status` machine (ADR-037 D1), same webhook handler (keys on `item_id` → `external_connection_id`, `045`), same scheduled poll (`cli/poll.ts` enumerates by provider, not by origin), same update-mode re-auth (`mintUpdateModeLinkToken` takes the stored token — origin-blind), same revoke (`/item/remove` → Vault destroy). **Product fact the copy must carry:** removing an adopted Item destroys it at Plaid and **does not return the quota slot** (F/CTO: "I don't get those back") — the remove confirmation for *any* Item should say so once production is on the free tier.

### B.7 The Item cap as a product fact

- The cap is **per Plaid `client_id` — per deployment — not per tenant.** Under ADR-036 open signup, *any* tenant's Link session consumes the shared quota. With 9 of 10 used, one signup by anyone else spends the F/CTO's last free Item. **Scope flag for F/CTO (§E-3):** gate Link (not adoption) behind the same operator allowlist until the production tier is on, or accept the exposure.
- **At Item 10:** Link succeeds; nothing in the app knows it was the last.
- **At Item 11:** Plaid refuses — *where* (link-token mint vs. exchange) and *with what code* is not on the tree (D-6). Product requirement: the connect flow renders that refusal as a **named state** — "Plaid's Item limit for this deployment is reached. Existing Items can be registered under *Register an existing Plaid Item*; removing an Item does not free a slot." — never the generic 5xx. `⟨OPEN⟩ Backend/DevOps`: the exact Plaid error code, confirmed at B.5 AC 2 against the production tier.
- The app does **not** count Items (it only knows its own `linked_source` rows) and must not hardcode "10". A quota surface (count / remaining) is V2 and Plaid-API-dependent (§E-6).

### B.8 Sec joint-review triggers (every one; Sec reads before any of this is posture)

1. **Credential-class ingress from the user** — inverts §4.2's "never touches the client": transport (POST body over TLS only; never query string, never logged, never in an error), process lifetime, no persistence outside Vault. New channel, not a reuse (Backend audit §A).
2. **RT-27 admission channel re-grade** — a new leg on the app→worker admission server carrying a long-lived credential where today only a short-TTL, single-use `public_token` transits; SELF-212's C6 conditions were argued on the public_token's properties.
3. **Decision 1 privileged-context write** — the admission transaction under `service_role` from user-supplied input; SC3-C8 cross-tenant fail-closed must hold verbatim.
4. **Revoke-on-failure divergence** (B.4.6) — a deliberate departure from the shipped C6-4 pattern.
5. **`/item/webhook/update`** — a new outbound call that changes where Plaid pushes for an Item this deployment did not mint.
6. **The gate itself** (O1 allowlist / O3 C2-gate exception) — a new auth or operator surface.
7. **Audit row** — the shipped `connect()` writes no audit row on admission; a production credential adoption arguably should (`fn_emit_audit_log`, ADR-011 D9 amendment / E46). **Coordination fact:** SELF-375 M-3's battery leg REDs when `audit_log_surface_name_vocab` grows past its one value — a new `surface_name` is a deliberate, coordinated vocabulary change, not a side effect.
8. **RT-26** — no new surface *if* the api/src relay stays credential-less (Backend audit §A); a Plaid credential in `api/src` would be a 5th RT-26 surface and an ADR-016 D2 gate.
9. **DEFINER allowlist** — untouched (app-level TS under `service_role`, as `connect()`); stated so it is checked, not assumed.

### B.9 Acceptance criteria (Linear grade)

1. **Reachability per the ruled option** (§B.2): under O1, the surface renders and accepts only for allowlisted tenants and the server refuses others with a non-disclosing 404-class response; under O3, the CLI refuses outside its explicit adopt flag and reads the token from stdin/file only. A pgTAP/vitest leg asserts the refusal case.
2. **Verification before write** (§B.4 1–5) — each check has a test that would fail if skipped: wrong-client token, mismatched `item_id`, foreign-tenant Item, same-tenant re-admission.
3. **No revoke on failure** — a test that an admission failure after a successful `/item/get` issues **no** `/item/remove` (the C6-4 inversion is asserted, not assumed).
4. **Webhook set** — after adoption the Item's webhook equals this deployment's endpoint, verified by `/item/get` read-back; if `/item/webhook/update` fails the Item is still adopted and the connection-state view shows "push not configured — polling".
5. **Post-adoption parity** — one Plaid sandbox Item adopted via this path then exercised through: webhook receipt (SELF-206 battery), scheduled poll, update-mode re-auth, remove. Same tests the Link path passes, run against an adopted Item.
6. **Token hygiene** — no test, log, error body, or audit row contains the token (C6-5 grep fence extended to the new files).
7. **Failure copy** (§B.5) — each named state renders its message; the Item-limit state (§B.7) renders on the Plaid code DevOps records at B.5.
8. **Sec joint-review** attached; posture option recorded in the PR body with the losing side.
9. **PRD P-4 merged** before close (§A.3).

---

## C. Item 2 — historical categorized-transaction backfill (supervised walk)

### C.1 Framing — the SELF-217 precedent, applied to transactions

SELF-217 seeded `pfin.nav_daily` from the incumbent sheet: dry-run by default, `--commit` explicit, an explicitly bounded date range with no defaults, **one transaction** (all rows or none), a structural refusal boundary (nothing on/after the tenant's `first_cron_checkpoint`), `ON CONFLICT DO NOTHING` re-runnability, dollars printed in dry-run, a **tracked-safe summary** (no `$`, uid prefix only) pasted into a record, and `pfin_etl` re-disarmed after (ADR-053 D5–D8; `docs/records/self217-nav-seeding-run.md`). Item 2 reproduces every one of those properties against `pfin.account_trans` + `pfin.account_trans_annotation`.

**What the F/CTO holds:** "a few years of already categorized transactions" — the incumbent per-account workbooks (§2.3.3 parity text). Format unknown to the tree; **the loader's input format is whatever the F/CTO exports, normalized once** (§C.2 input 1).

### C.2 Inputs

1. **The transaction file(s).** One row = one transaction: incumbent account label, date, amount (signed, dollars), vendor, description, incumbent category label(s). Format: CSV (the only reader precedent, `parse_baseline_csv`); the loader states the exact header contract in its usage text. Input file **sha256 recorded** (§C.6).
2. **The account map** — incumbent account label → `pfin.account.account_id` for the target tenant. Authored by the F/CTO, checked into the record (labels only; no numbers). Every incumbent label must map; an unmapped label **refuses the run** (fail-closed, like SELF-217's "refused rows"), never lands on a guessed account.
3. **The category map** — incumbent category label → `pfin.user_taxonomy (cat, sub_cat)` for the tenant's **cashflow** domain. Because the seeded taxonomy "derives from the founding user's existing categorization" (§2.3.1 / ADR-057), the map should be near-identity; the loader prints the unmapped set on dry-run. **Options for unmapped categories:** (i) **refuse the run until the map is complete** — PM lean: the run exists to give M0 *categorized* history, and §2.3.2's loud-unclassified banner over thousands of rows is noise, not signal; (ii) land unmapped rows unclassified and let the §2.3.2 banner count them (the V1.2 loud posture; correct for ordinary use, wrong for a deliberate import). Taxonomy CRUD stays V2+ (§2.3.1): a category with no seeded home is resolved by **mapping** it to an existing Sub-Cat in the map, not by creating one.
4. **Trades and non-cash events are out.** Rows in the mechanical posting vocabulary (ADR-058: trades, splits, transfers-in-kind, their instrument legs) are **refused** by the loader — Item 2 lands cash-flow rows (§2.3.1 classifiable items) only. Security-bearing history for investment accounts is a separate question the ruling did not raise (§E-5).

### C.3 The classification model the rows land in (capability facts, Backend audit §B)

- A landed row is an `account_trans` row plus a **023 annotation** row (`sub_cat_id → user_taxonomy`). GL / `tax_character` posting is **derived** downstream (`fn_gl_entries` `035`, `084` / `092` posting prototype) — the loader writes category, never postings.
- Write primitives on the tree: (a) **`pfin.fn_create_manual_trans(p_account_id, p_transaction_date, p_amount, p_vendor, p_description, p_sub_cat_id, p_note, p_import_hash)`** — SECURITY INVOKER, one row + its annotation atomically, under the caller's own RLS (aal2-gated); no bulk variant. (b) **`pfin.fn_ingest_transactions(p_rows jsonb)`** — SECURITY INVOKER bulk insert granted to `authenticated`, provider-key dedup `ON CONFLICT (source_provider, provider_txn_id) DO NOTHING`, **writes no annotation**. Which primitive (or a new annotation-aware bulk RPC — Architect, new migration) is Backend/Architect's design call; the product requirements are §C.4–§C.5.
- **The incumbent categories are the user's own** (§2.3.1: "the user's two-level taxonomy is authoritative"); a landed assignment is a user assignment, history-preserving under Lock 10 / ADR-031 like any other.

### C.4 WALK vs BUILD (Backend audit §C, PM-sorted)

| | Item | Who |
|---|---|---|
| **BUILD** | **The loader** — one-shot script reproducing the SELF-217 contract (§C.1) against transactions: input contract, account + category maps, refusal set (unmapped label, unmapped category, mechanical-vocabulary row, **any date on/after the account's refusal boundary** §C.5), dry-run report (row counts per account, per-category counts, date span, refused rows with reasons, dollars totals per account for the eyeball check), one transaction on `--commit`, tracked-safe summary. Node, to reuse the canonical `computeImportHash` (Backend audit §C gap 1) — a third hash copy in Python is the ADR-034 D4 one-way door's failure mode. | Backend (+ Architect if a bulk RPC is authored) |
| **BUILD (decide, then maybe build)** | **`backfill_cutover_date` arbitration** — the column exists on `pfin.account` (`015`), documented as "arbitrates import (≤) vs aggregator (>)", **read by no code** (Backend audit §B). Either wire it (Plaid's initial pull drops rows dated ≤ cutover — a new privileged-write filter, Sec joint) or leave it inert and rely on §C.5's refusal boundary + the detection view. PM lean: **do not wire it for this run** — the refusal boundary makes the overlap empty by construction; wiring a filter into the sync path for one operator run is the wrong side of the walk/build line. Revisit if a second tenant ever imports. | Architect ruling |
| **WALK** | Producing the export + the two maps; dry-run locally against a scratch DB (`supabase db reset` discipline; Backend audit §D step 2), reviewing the printed figures; `--commit` against production; pasting the tracked-safe summary into the record; the reconciliation pass (§C.5) if any overlap survives. | F/CTO with Backend at the keyboard |
| **WALK** | The restore/bulk-load runbook section that describes this run (MILESTONES open item; `deployment-runbook.md` stub) — written from the run, not before it. | DevOps + Backend |
| **CONFIG** | Scratch-DB load check at the real row count before trusting a loop-of-RPC loader (Backend audit §C gap 8 — untested, not known-slow). | Backend |

### C.5 Idempotency against the later Plaid initial pull — the load-bearing finding

**Facts (ADR-034 D2/D3 + migration `040`, Backend audit §B):** manual↔provider dedup on this tree is **DETECTION-ONLY**. The `004` hard-unique `(account_id, import_hash)` index was **relaxed to non-unique** (option X, F/CTO 2026-07-27) precisely so a manual row and its later provider echo **coexist**; `pfin.manual_provider_dup_candidate` surfaces exact-hash pairs for the user to reconcile **one pair at a time** (SELF-205). The hash is exact over normalized `vendor + description`, so an incumbent descriptor that differs from Plaid's `name` / `merchant_name` text is **not even a candidate** — silent double-count. Nothing auto-suppresses. The tree sets no `days_requested` on Link, so how far back Plaid's initial pull reaches for an adopted Item was fixed when that Item was minted — unknown here.

**Consequence:** any backfilled date range that overlaps the Plaid pull double-counts §2.3 and cash-NAV for the overlap, detectably only where text happens to match. "Dedup expectations" cannot be met by dedup; they are met by **making the overlap empty**.

**Product requirement (PM):** the loader **structurally refuses any row dated on or after the account's refusal boundary**, where the boundary is — per account — **the earliest provider-sourced `account_trans.transaction_date` for that account** (read from the DB at run time; `source_provider IS NOT NULL`), or, for accounts with no provider rows, no boundary (manual accounts backfill in full). This is SELF-217's `first_cron_checkpoint` refusal, one level down. The record states the boundary per account. **Re-runnability:** rows carry `source_provider='import'` (in the `015` vocabulary) and a **deterministic `provider_txn_id`** (a stable key derived from the source row) so a re-run is a no-op through the `017` provider-key arbiter — idempotent by construction, not by operator care. `import_hash` is still computed and stored (the canonical field-set) so the detection view keeps working for whatever the F/CTO later enters by hand.

**Which is why the ruled order collides with account identity.** Plaid-served accounts **do not exist in `pfin.account` until their Item is registered** (accountMapper creates them keyed `(linked_source_id, provider_account_id)`). Backfilling "before the Plaid connection" therefore means one of:

| | Option | Losing side |
|---|---|---|
| **S1** | Backfill into manual accounts created for the purpose, then register Items. | Two `pfin.account` rows per real account forever: history on the manual one, live data on the Plaid one. Re-link does not exist (`linked_source_id` is never written by any app path — BACKLOG §7's four-symptom entry), and ADR-042 forbids closing an account that holds anything. §2.3.3's account selector shows both. NAV double-counts across the seam unless the manual account is drained by hand. |
| **S2 (PM lean)** | **Register Items first**, let the first sync land, **then** backfill each Plaid-served account **below its refusal boundary**; manual / non-Plaid accounts backfill in full at any time. | Inverts the ruled order for Plaid-served accounts. The *reason* for the ruled order — M0's comparison needs populated history — is preserved: M0's check (SELF-387) runs after both. The overlap is empty by construction; the only reconciliation left is where the incumbent and Plaid disagree on a transaction's *existence*, which is a finding, not a dedup. |
| **S3** | Build re-link first (the BACKLOG §7 four-symptom control), then S1 with a re-link at the end. | Largest build; re-link is a Sec-joint D3 #6 surface with its own ADR; not a stand-up precondition by any reading of the ruling. |

**Escalation (F/CTO):** S2 changes the ruled sequence to **deploy → register Items → first sync → backfill (all accounts, each below its boundary) → M0 check → tenant-live date**. PM asks for that re-ruling rather than building S1 to the letter (§F Q4).

### C.6 The record — `docs/records/v1final/backfill-run.md`

Same shape as `self217-nav-seeding-run.md`, with:
- run date (repo clock) and environment (production; deployed sha from the B.5 deploy log);
- input file name + **sha256** + row count (the nearest thing to byte identity — D-5);
- the account map and category map (labels only);
- **per account:** refusal boundary, requested date span, rows admitted / refused (with reason classes), rows per category (counts only — **no `$`**, PRD public-tier discipline);
- the tracked-safe summary block verbatim: identity-agreement line (CLI-supplied vs DB-resolved uid, 8-char prefix — ADR-053 D5's writer obligation, which the loader must implement, not inherit), `--commit` / ack flags, one-transaction confirmation;
- post-run verification by team-lead from the tree (row counts read back; boundary respected: zero import rows on/after any boundary);
- whether any `manual_provider_dup_candidate` pairs exist after the first post-backfill sync (expected 0 under S2).

### C.7 What it unlocks

- **SELF-387 / B.1 Dependency 2** — the Backend M0 completeness check can now find "the tenant's transactions for the whole of M0 [and] the §2.3 cash-flow rollup inputs" *and the prior-period columns those surfaces read* (Q1–Q4 / YTD in §2.3.2, the 5-year window in §2.3.4) — without this run, every multi-period cell in the M0 comparison is structurally N/A.
- **A-3** — the per-cell checklist over §3.3's §2.6 clauses gets a populated left-hand side for the cash-flow cells.
- **The Historical Expenditures chart** (§2.3.4) becomes meaningful at launch — the transaction analogue of the §2.1 NAV-import commitment.

### C.8 Acceptance criteria (Linear grade — the loader issue; the walk is the record)

1. Dry-run is the default; `--commit` writes; every run prints the §C.4 dry-run report and the tracked-safe summary.
2. Bounded input: explicit date range per run, no defaults; account map and category map are required inputs; an unmapped account label or category **refuses the run** (per the option ruled at §C.2.3).
3. Refusal boundary per account (§C.5) is computed from the DB, printed, and enforced — a test loads one provider row and asserts a same-date import row is refused.
4. One transaction: a failure at row N leaves zero rows (test: inject a bad row at the end; assert count unchanged).
5. Idempotent re-run: running `--commit` twice yields identical row counts (provider-key arbiter; test).
6. Every landed row has its annotation (`sub_cat_id` non-null) in the same transaction; a mechanical-vocabulary row is refused.
7. Tenant identity: impersonation binding + DB-resolved `auth.uid()` read-back; the summary carries the agreement line (ADR-053 D5).
8. Token/secret hygiene as SELF-217: the writer role is armed for the run and re-disarmed after, recorded.
9. Sec joint-review attached (money flows / Lock 14 write paths; plus Architect if a bulk RPC is authored).
10. The run record (§C.6) exists and is cited by SELF-387's completeness record.

---

## D. Ordering + Linear shape

### D.1 Ordering (with the S2 correction from §C.5)

```
SELF-386 (B.5) AC 1–3   deploy at a named sha · Plaid production creds · gates walked
      │
      ├─ Item 1 BUILD (adopt path)          ─┐  parallel; both Sec-joint
      ├─ Item 2 BUILD (loader)              ─┘
      │
      ▼
SELF-386 AC 4, part 1   F/CTO tenant signs up; manual accounts created (§2.4.2)
      │
      ├─ Item 2 WALK — manual / non-Plaid accounts (no boundary)
      ▼
Item 1 WALK             register the existing Items (Link only for any institution with a free slot)
      │                 first sync lands → per-account refusal boundaries now exist
      ├─ Item 2 WALK — Plaid-served accounts, below boundary
      ▼
backfill-run.md         recorded
      ▼
SELF-387                Backend M0 completeness check → a-m0-completeness.md
      ▼
SELF-386 AC 4, part 2   tenant-accounts-live date written → M0 / M1 derived → month-1 clock
```

If F/CTO keeps the ruled order verbatim (S1), the two WALK rows swap and the manual-account seam (§C.5 S1 losing side) is accepted knowingly.

### D.2 Linear shape — options

| | Shape | Losing side |
|---|---|---|
| **L-1 (PM lean)** | **Two feature issues + the walk carried on the loader issue.** (i) *Register an existing Plaid Item (adoption path)* — project **Onboarding / Plaid / Manual entry**, milestone tag **V1.final**, label `role:backend` + `role:sec-review` (+ `role:frontend` under O1); *blocks* SELF-386 (its AC 4 cannot complete without it). (ii) *Historical categorized-transaction loader + supervised backfill run* — project **Platform / Cross-cutting** (it is substrate + an operator run, like B.5), milestone **Platform / Cross-cutting V1.x** with tag **V1.final**, label `role:backend` + `role:sec-review`; *blocks* SELF-387 and, through it, B.1; *blocked by* SELF-386 AC 1–3 (nothing to backfill before production exists). | The walk has no issue of its own — its evidence is the record, and "Done" on the loader issue means *run and recorded*, which stretches one-session granularity (ADR-017 D2) for the loader issue. Two projects for two preconditions of one stand-up. |
| **L-2** | **One parent "Stand-up preconditions" issue with the two as children**, under Platform / Cross-cutting, V1.final tag. | A parent with no work of its own; Linear's parent/child is not a blocking relation, so the real edges (→ SELF-386, → SELF-387) still have to be drawn on the children. Adds an object to keep in sync. |
| **L-3** | **Fold both into SELF-386 as AC items.** | SELF-386 is DevOps-owned; these are Backend/Frontend + Sec work with their own joint-reviews and PRs — a single issue would hide two role hand-offs and two Sec gates behind one Done. Rejected by the one-issue-one-PR convention. |

**Milestone call:** these exist because of the month-1 clock, so **V1.final** tag on both; the adoption path outlives V1.final as a product capability, hence its home in the Onboarding project rather than Platform. Linear holds current + next only (ADR-017 D2) — V1.final is current, so both are created directly, no §7 staging.

**Not created until ruled:** nothing here is written to Linear before F/CTO rules §F; the liaison creates from §B.9 / §C.8 verbatim afterwards.

---

## E. Scope flags

- **E-1 V2 creep — O2 (every-tenant advanced setup).** Not required by the ruling; widest credential surface. Stays out unless F/CTO says otherwise.
- **E-2 V2 creep — the product import surface.** §2.4.3 / §5.4 "CSV bulk-import of historical transactions" stays V2+; the loader is an operator script with no route, no form, no per-tenant reachability. If the loader grows an upload endpoint, it has become the V2 feature and needs its own scoping.
- **E-3 Product risk — open signup × shared Item quota.** ADR-036 open signup + a per-`client_id` quota with one free slot left means any stranger's Link session spends it. Options: gate Link behind the operator allowlist until the production tier is on; or accept. **F/CTO rules (§F Q5).** Not on the tree anywhere.
- **E-4 PRD currently forbids.** "The client never holds a long-lived access credential" (§2.4.1, §2.4.4; §4.2) — Item 1 amends (§A.1). "CSV bulk-import … V2+" (§2.4.3) — Item 2 does *not* amend it; it adds the one-time-run sentence beside it (§A.2).
- **E-5 Unasked: security-bearing history.** The ruling says "categorized transactions" — cash-flow rows. Investment-account trade history from the incumbent is a different import (mechanical vocabulary, positions, cost basis; §2.4.3's securities-edit deferral at BACKLOG §7.3 G3 is the adjacent open surface). Not scoped here; named so its absence is a decision.
- **E-6 V2 — Item-quota telemetry** (count / remaining / which tenant spent one). Plaid-API-dependent; `BACKLOG §5.4` candidate if F/CTO wants it findable.
- **E-7 Tree wording debts surfaced, not fixed:** ADR-027's "CSV/OFX import … (SELF-201, shipped)" false composite (D-2); SECURITY §4.2's dropped-table names (D-7); `api/CLAUDE.md` "three locked allowlist endpoints" vs ADR-016's live four (Backend audit §A). Each routes to its owner (Architect / Sec / Backend).
- **E-8 `backfill_cutover_date`** — inert schema with a documented purpose nobody reads. Either wire it (Architect) or annotate it as reserved so the next reader does not assume it arbitrates anything (§C.4).

---

## F. What F/CTO is asked to rule (one line each; PM lean where PM has one)

1. **Q1** — Were the 9 existing Items minted under the `client_id` production will run with? (Config fact; no lean.)
2. **Q2** — Do you hold those Items' `access_token`s? If not, adoption cannot register them and the ruling's premise changes (Link would re-mint, quota-consuming).
3. **Q3** — Partial-products Item (§B.4.4): proceed-with-warning (PM lean) or block?
4. **Q4** — Sequence: keep "backfill → register" verbatim (S1, two-account seam) or re-rule to S2 "register → first sync → backfill below boundary" (PM lean, §C.5)?
5. **Q5** — Open signup × shared quota (E-3): gate Link behind the operator allowlist until production tier, or accept?
6. **Q6** — Reachability option for Item 1 — O1 / O3 (O2 not recommended); **after Sec reads §B.2 / §B.8**.
7. **Q7** — Unmapped categories: refuse the run (PM lean) or land unclassified under the banner?
8. **Q8** — Linear shape L-1 (PM lean) / L-2 / L-3.

**Routing before ruling:** §B (all) and §C.3–§C.5 → **Security Engineer** (credential ingress, RT-27 re-grade, Decision 1 write, money-flow bulk write); §C.4 bulk-RPC / `backfill_cutover_date` / re-link question → **Architect**; §B.4 / §B.7 Plaid facts + `⟨OPEN⟩`s → **Backend / DevOps** at B.5.
