# Production stand-up (SELF-386 / B.5 — Phase 7 entry; V1.final month-1 precondition)

DevOps-owned. This record is the single authority `docs/records/v1final/self365-protocol.md` §B.5 names for **deploy date**, **deployed sha**, **tenant-accounts-live date**, and the two derived months (**M0**, **M1**) — B.1 and B.3 read these fields, nothing else derives them. This session (RESEARCH + PLAN only, per team-lead brief) resolves the three `⟨OPEN⟩ DevOps` markers and produces the stand-up plan. **No deploy has happened.** The table and log below are opened empty and filled at first deploy / first tenant-accounts-live event.

---

## Authority table (empty — fill at events)

| Field | Value |
|---|---|
| Deploy date (repo clock, `-0700`) | *(not yet deployed)* |
| Deployed sha | *(not yet deployed)* |
| Tenant-accounts-live date | *(not yet live)* |
| M0 (deploy month; never counts) | *(derived from deploy date)* |
| M1 (first full calendar month after tenant-accounts-live date) | *(derived from tenant-accounts-live date)* |

## Deploy log (one line per deploy — empty; opens at first deploy)

| Date (`-0700`) | Sha | Components (health) | Notes |
|---|---|---|---|
| — | — | — | — |

---

## 1. OPEN-1 resolved — which Coolify record DevOps reads the running sha from

**Recommendation: the Coolify API's per-application `git_commit_sha` field, cross-checked against the deployment-history endpoint's per-deployment commit field, both read at each deploy and transcribed into the log above — never held as a memory.**

Two candidate mechanisms exist:

1. **Coolify's own deployment record (API or UI).** Coolify persists the resolved git commit for each deployment ( `GET /api/v1/applications/{uuid}` → `git_commit_sha` field on the application resource; `GET /api/v1/deployments/applications/{uuid}` → per-deployment commit history). The UI's Deployments tab shows the same data. **Recommended primary.** It is Coolify's own resolution of what it built and pushed to the running container — an observable of the deploy action, not a build-time artifact V1's own Dockerfiles would need to carry.
2. **A container label / image tag baked at build time** (e.g. an `org.opencontainers.image.revision` `LABEL`, or a build-arg embedding the sha, set from a Coolify build variable and inspectable via `docker inspect`). Requires adding a build-arg + `LABEL` line to all four Coolify-managed Dockerfiles (`api/`, `workers/etl/`, `workers/pdf-render/`, `workers/provider-sync/`) and confirming Coolify actually populates the build-arg it document (Coolify names this `COMMIT_SHA` or similar depending on version — unconfirmed until read on the real instance).

**Why (1) over (2):** Coolify tracks and exposes the deployed commit for every managed application natively — no per-Dockerfile change, no risk of one of the four containers being wired and the others forgotten, and no dependency on a Coolify build-arg name that is version-specific and currently unverified against this instance. (2) is a reasonable defense-in-depth addition later (a label surviving inside the running container even if the Coolify record were ever wrong or unavailable), but it is not the primary mechanism — flagged as a Phase-7-or-later hardening item, not a stand-up blocker.

**Verify at first deploy:** for each of the four Coolify-managed services, read `git_commit_sha` via the API (or the Deployments tab) immediately after deploy and confirm it equals `git rev-parse HEAD` of the `main` tip that triggered the auto-deploy (per ARCH §6, Coolify auto-deploys on push to `main` after CI green). Record the confirmed sha in the deploy log above — the log line is a transcription of this read, never typed from memory. If the four services ever report different shas (a partial deploy), the log records each service's sha separately and the AC1 "all healthy at one sha" bar is not met until they converge.

**Source could not fully settle this in-tree** — the runbook (`docs/deployment-runbook.md` §3, §7) names Coolify as the control plane and documents zero of its API surface; this recommendation is sourced from Coolify's public docs/API behavior (see PR body / Linear comment for citations — not restated here per hand-off convention), not from anything already committed to this repo.

---

## 2. OPEN-2 resolved (as far as public information allows) — Plaid production-access lead time and product-tier coverage

**Confirmed, from Plaid's own current public materials (dated 2026; direct fetch of `support.plaid.com` pages returned HTTP 403 — Cloudflare-gated — so these are sourced via search-engine synthesis of Plaid's docs/support content, not a directly-fetched quote; treated as confirmed only where corroborated across independent results):**

- **Plaid retired "Limited Production" self-serve signups for new US/Canada developers as of 2026-04-15.** New developer teams (any created on or after that date) instead get a **Trial plan**: free, real production data, auto-approved for most applicants, up to **10 Production Items**, and — this is the material fact for V1's product set — **both Transactions and Investments are included** among the Trial plan's supported products, alongside Auth/Balance/Identity/Assets/Liabilities/Statements. Existing Limited Production customers (teams created before the cutover) keep their existing access.
- **The Trial plan also grants access to most OAuth institutions** (Bank of America, Chase, Wells Fargo named explicitly in Plaid's materials) without first completing full Production registration.
- **Moving from Trial to a paid Production plan** is done from the Dashboard's Plans page ("upgrade to a paid plan to create more Production Items… at any time") — no evidence of a lengthy approval gate for that upgrade path specifically.
- **Full (non-Trial) Production access application** — the older, general path — asks for company/use-case information; pricing for Pay-as-you-go/Growth plans is shown at application submission, Custom plans go through sales. **No authoritative lead-time figure could be confirmed** from a directly-fetched Plaid page (both attempted `support.plaid.com` fetches 403'd); one search-engine synthesis surfaced "a couple of business days" but that number is **unconfirmed** — do not commit to it as a planning input.

**Unconfirmed / must be checked against the actual Plaid dashboard, not this document:**

- **Whether the mosko-fintech Plaid developer team was created before or after 2026-04-15.** Nothing in the tree records this. If created before, the team may still sit on the older Limited-Production framing the runbook/B.5 spec assumes; if after (more likely, since ADR-027's empirical testing dates to 2026-07-08, after the cutover), the team is almost certainly on the **Trial plan**, and the spec's "limited-production tier" language should be read as "Trial plan" going forward — **the B.5 AC-2 wording is stale terminology, not a wrong outcome**: Trial admits Transactions + Investments, which is what the AC actually needs.
- **Whether every one of the F/CTO tenant's real institutions is reachable under Trial/Plaid at all.** Per ADR-027 (2026-07-08 empirical test), **Fidelity is already routed to SimpleFIN, not Plaid** — general aggregators (Plaid included) do not reliably return Fidelity transactions; this is a known, already-designed-around limitation, not new risk. The remaining institutions (Schwab, Capital One, Wells Fargo, Synchrony per the ADR-002 Items pricing worksheet) are the ones that need to work under Plaid Trial/Production. Wells Fargo is explicitly named as Trial-OAuth-supported in Plaid's public materials. **Schwab's status could not be confirmed** — one 2025-11 industry piece (not a Plaid primary source) describes an active dispute between several large banks (including Schwab and Fidelity) and data aggregators over account-data-access terms; whether this affects Plaid's ability to serve Schwab data by V1's stand-up window is **unconfirmed** and is a genuine external risk, not something DevOps can resolve from documentation. **Surfaced to F/CTO as a scope fact per the AC's own instruction ("if the tier gates any V1 product, that is an F/CTO scope fact, surfaced, not worked around") — recommend a Plaid Link smoke test against the F/CTO's actual Schwab login be run early in the stand-up sequence (step 6 below), not deferred to the tenant-accounts-live step, so a gap surfaces while there is still schedule slack.**
- **Citation correction:** the team-lead brief and (following it) casual usage attribute "Plaid PRIMARY, SimpleFIN SECONDARY" and the Transactions+Investments product set to **ADR-027**. Checked against the tree: **ADR-027** (2026-07-08) built the provider-agnostic abstraction and *explicitly deferred* provider selection to a later gate; **ADR-037** (2026-07-28) is the ADR that actually **ratifies** Plaid-primary/SimpleFIN-secondary (its own title says so) and resolves ADR-027's gate (i). The Transactions+Investments product-set commitment traces to **ADR-002 §6.0 / PRD §1.3** (Phase 1), not to ADR-027. This is a citation-attribution drift worth fixing wherever "ADR-027 (Plaid PRIMARY)" is repeated — the *conclusion* used in this record is correct, only the ADR number is wrong in the inherited phrasing.

---

## 3. OPEN-3 resolved — every gate the runbook's STUB sections need beyond §7.15 / §7.6 S5 / S10

**§7.6 S10 status check:** already ✅ DISCHARGED 2026-08-09 (capability-verify of `compute_and_checkpoint_user` under a real `pfin_etl` login) — not an open gate. Its one named residual (TLS transport never exercised end-to-end, S11 cross-ref) is a real gap but is TLS-transport verification, which is subsumed by this checklist's item 9 below (the stand-up's first real TLS-terminated deploy).

Checklist (✓ = already satisfied by a shipped migration/mechanism and only needs a deploy-time confirmation; ⚠ = genuinely new work or a decision the runbook flags as unresolved):

| # | Gate | Owner | Status |
|---|---|---|---|
| 1 | §7.15 NAV-chart render-latency (800ms/1.5s p95) | QA (measure) + DevOps (environment) | Deploy blocker for the chart surface only, not the whole stand-up |
| 2 | §7.15 NAV-delta-panel latency (200ms p95) | QA + DevOps | Deploy blocker for the panel surface only |
| 3 | §7.6 S5 — `pfin_provider_sync` dedicated NOINHERIT login role (supersedes `pfin_worker`), provisioned in the same pass as `pfin_etl` | Architect (role migration) + DevOps (secrets-manifest/.env.example/runbook) + **Sec joint-review mandatory** | ⚠ Not yet built — role migration does not exist on the tree today (grep-verified: `055_pfin_etl_role.sql` exists; no `pfin_provider_sync` migration does). **Blocks AC1** (`provider-sync` cannot run off `authenticator` under the S5-superseded posture without re-opening the shared-credential finding S5 exists to close) |
| 4 | §5 Secrets-provisioning procedure + rotation | DevOps + **Sec joint-review mandatory at lock** | ⚠ STUB — procedure not written; this is standing work, not new to this record |
| 5 | §6.1 `pfin_etl` two-step credential handoff (`\password` then `ALTER ROLE … LOGIN`, in that order) + the `rolcanlogin`/`rolinherit` read-back | DevOps (executes) | ✓ Fully specified and Sec-ruled already (flag #10 resolved); needs execution + read-back at deploy, not new design |
| 6 | §7 provider-sync **CA-1** — deploy-time verification that the admission-endpoint's env-var prefix regex actually matches this Coolify version's real injected FQDN/URL var names | DevOps | ⚠ Named "at first deploy, and after any Coolify upgrade" — must run every time, not a one-shot |
| 7 | §7 provider-sync **CA-4** — api/ and provider-sync MUST be co-located in the same Coolify project (internal DNS dependency) | DevOps | ⚠ A deploy-config discipline with no automated guard other than the §10 CA-2 smoke below |
| 8 | §7 `PDF_WORKER_SIGNING_KEY` length (≥32 chars) + same-value-on-both-containers precondition, verified BEFORE the PDF worker's first deploy | DevOps | ⚠ Manual pre-deploy check; asymmetric failure mode is already documented, not yet gated by tooling |
| 9 | §10 **CA-2** — admission-endpoint external-reachability NEGATIVE smoke (provider-sync `:8081` unreachable from outside the project network) + the positive internal-reach control | DevOps (infra-reachability) + QA (RLS/cross-tenant legs of the same gate family) | ⚠ Named ship-block; unexecuted (no deployment exists yet) |
| 10 | §10 **TZ-1** — DB TimeZone pin read-back (`source = database`, not `configuration file`), run as each login role (`authenticator`, `pfin_etl`), plus the provenance limb (`schema_migrations` row for `061`) | DevOps | ✓ Migration `061_pin_database_timezone_utc.sql` **already exists on the tree** (verified — see finding below; the runbook's own Open-flags row #11 is stale, claiming the migration "needs to be authored") — this gate is a deploy-time read-back of an already-shipped mechanism, not new design |
| 11 | §10 **TZ-1b** — wire the R3 TimeZone-drift-sweep Coolify Scheduled Task (ratified 2026-08-06, deliberately deferred to Phase 7) and confirm one run reports to Discord, before declaring stand-up complete | DevOps | ⚠ Ratified design, unbuilt — "a decided thing awaiting a box" per the runbook's own words. Also confirm the α premise (does a non-zero exit from a Coolify post-deploy command actually fail the deployment, or only log?) — the runbook flags this as answerable **today**, independent of the new box, and unresolved |
| 12 | §10 end-to-end smoke checklist (TLS reachability; auth login; two-tenant RLS isolation; a migration-backed query; PDF render round-trip via signed JWT; ETL runs one poll; Discord notification fires) | DevOps (infra) + QA (RLS/isolation) | ⚠ STUB — no explicit pass/fail criteria written yet; needed before this AC's item 3 ("deploy gates walked") can be marked pass |
| 13 | §11 GDPR/user-deletion detach-then-cascade erasure routine (journal-grouping `ON DELETE RESTRICT` interaction) | Backend (build) + Sec (joint-review at build) | Not a month-1 precondition (no erasure will be run against the F/CTO's own tenant at stand-up) — recorded so it is not silently assumed built; **not scoped into this AC** |
| 14 | Container Dockerfile status reconciliation | DevOps | Finding, not a gate: the runbook (§7) still describes the PDF worker Dockerfile as "currently a placeholder" — the tree shows a 108-line Dockerfile with lock-anchored comments, marked "EXTENDED, not scaffolded" per SELF-348. Runbook text is stale; no action blocks stand-up, but the runbook should be corrected at the same time §5/§6/§7 STUBs are filled in |

**Explicitly excluded from this AC (per B.5's own scoping), not omitted by oversight:** §9 cutover/teardown of `pfindash.com` and backup/restore validation are Phase-7 **exit** criteria, not month-1 preconditions.

**Finding — B.5 AC1's deployed-component enumeration is incomplete.** AC1 lists "the app, the ETL worker (`nav_daily`), the PDF worker, and the monthly-report cron container" as the four things Coolify must run at one sha. This **omits the `provider-sync` worker** — the 4th Coolify unit per the ADR-019 amendment, and per ARCH §5 the **sole code-layer holder of `PLAID_CLIENT_ID`/`PLAID_SECRET`**. AC2 ("Plaid production credentials obtained and applied… one Link session against a real institution succeeds") is structurally unsatisfiable without provider-sync deployed and healthy — the web-app reaches Plaid only by relaying through provider-sync's internal admission surface. Recommend AC1's component list be corrected to five: app, ETL worker (incl. `nav_daily` + the monthly-report cron Scheduled Task run against it), PDF worker, and provider-sync worker (incl. the daily-poll Scheduled Task + the admission endpoint). Also, "the monthly-report cron container" is imprecise — per the runbook's own "Pattern A" convention, the monthly-report cron is a Scheduled Task executed against the resident **ETL** container, not a separate container; there is no 4th "cron container" distinct from the ETL and provider-sync units.

---

## 4. The stand-up plan

**Ordered steps, today (2026-09-08) → tenant accounts live in production.** Each row: owner, artifact produced, what blocks it.

| # | Step | Owner | Artifact | Blocked by |
|---|---|---|---|---|
| 1 | F/CTO decides hosting target (§5 options below) | F/CTO | Decision recorded in this file + runbook §1 | Nothing — decidable today |
| 2 | Author `pfin_provider_sync` role migration (S5) | Architect | New migration; Sec joint-review | Step 1 not required first; can run in parallel |
| 3 | Provision VPS + install Coolify (runbook §1, §3) | DevOps | Running Coolify instance | Step 1 |
| 4 | DNS / domain decision + records (§2) | F/CTO (decision) + DevOps (execution) | DNS records live | Step 1 (needs the box's IP) |
| 5 | Stand up self-hosted Supabase; apply migrations incl. `061` TimeZone pin + `055`/S5's new role migration; run the `pfin_etl` + `pfin_provider_sync` two-step credential handoffs (§6/§6.1) | DevOps | Migrated DB; both dedicated login roles live | Steps 2, 3 |
| 6 | Deploy the four Coolify services (app, ETL, PDF worker, provider-sync) from one `main` sha; inject secrets (§5); run CA-1/CA-4/PDF-key preconditions | DevOps | First deploy-log line in this record (OPEN-1 mechanism) | Step 5; Sec joint-review of §5 secrets-provisioning procedure |
| 7 | Apply Plaid production credentials via Coolify env vars; confirm Plaid environment = `production`; run one Plaid Link session against a real F/CTO institution (Schwab first, per the unconfirmed-coverage risk in OPEN-2) | F/CTO (owns the real credentials/login) + DevOps (wiring) | AC2 satisfied | Step 6; **Plaid dashboard state** — confirm whether the team is Trial or full Production and whether Schwab connects, before assuming AC2 is a formality |
| 8 | Run §10 smoke checklist (TLS, auth, RLS two-tenant, migration-backed query, PDF round-trip, ETL poll, Discord notify) + CA-2 negative/positive reachability + TZ-1/TZ-1b (incl. wiring the drift-sweep Scheduled Task) | DevOps (infra) + QA (RLS legs) | Recorded pass/fail per gate in this file | Step 6 |
| 9 | Sec pre-production sign-off (WORKFLOW Phase 7 agents list) | Sec | Sign-off attached/cited in this file | Steps 3–8's Sec-mandatory sub-gates all green |
| 10 | F/CTO signs up in production (ADR-036 open-signup + email-confirmation), connects every Plaid/SimpleFIN account, enters every manual account the monthly review depends on | F/CTO | Tenant-accounts-live date recorded; M0/M1 derived | Steps 1–9 all closed |
| 11 | Handoff: liaison fills B.3's month placeholders from step 10's date; Backend runs the M0 historical-completeness check | Backend + liaison | `docs/records/v1final/a-m0-completeness.md` | Step 10 |

**Critical path to the earliest M1 (per §D's calendar):** the chain is steps 1→10 above, then §D's own downstream chain (M1 whole → cron fires 1st of M1+1 → same-day authoring/export). Reading §D's table against today (2026-09-08): if steps 1–10 complete by **2026-09-30**, M1 = 2026-10, second cron fires 2026-12-01, earliest V1.final close is early **2026-12** (§D row 1) — a ~3-week window from today, which §D itself flags as tight ("needs the skeleton runbook executed end-to-end in ~3 weeks"). Missing that date rolls the whole chain to §D's next row (deploy+accounts by 2026-10-31 → close pushes to early 2027-01), i.e. **every month steps 1–10 slip, the close slips a month** (per §D's own statement, restated here because it is the plan's actual cost of delay, not a new claim).

**Secrets that must exist in Coolify at deploy (names only, per `secrets-manifest.yml` `production_only`, never values in this record or anywhere else):** `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `PDF_WORKER_SIGNING_KEY`, `PLAID_CLIENT_ID`, `PLAID_SECRET`, `SIMPLEFIN_TOKEN`, `WORKER_ADMISSION_SHARED_SECRET`, `DISCORD_WEBHOOK_URL`, `PFIN_DB_PASSWORD` (two distinct values, one per login role — `pfin_etl` and `authenticator` — same secret name, container-scoped different value, per the manifest's own note), `FMP_API_KEY`, `BLS_API_KEY`. Non-secret companion env vars needed alongside: `PFIN_DB_USER` (differs per container: `pfin_etl` vs `authenticator`), `PLAID_ENV=production`.

**Sec-consult points (mandatory, not optional, per the routing already established in the tree — listed so nothing is missed at execution):**

- §5 secrets-provisioning procedure + rotation, at lock (runbook flag #5).
- The `pfin_provider_sync` role migration (S5) — Sec joint-review mandatory per ADR-019 C2's condition, unchanged by the rename.
- The Coolify auto-deploy webhook configuration lock (ARCH §6 item (f)) — watches-main-only + admin-bypass-disabled verification.
- Any RT-26/RT-27-surface change touching the admission endpoint's env-signal heuristic (CA-1) if the Coolify version's actual FQDN/URL var names turn out to differ from what the worker's regex expects — that is a live tripwire-shape change, not a pure ops task.
- Pre-production sign-off itself (WORKFLOW Phase 7, named agent).
- The GDPR-erasure routine (§11) at build time — not a stand-up blocker, listed so it is not silently skipped when it does get built.

---

## 5. Options for F/CTO (2–3 each, no unilateral pick)

### Hosting target

ARCH §5 commits only to *"a new greenfield VPS provisioned from scratch at deploy time"* — it explicitly does **not** name Hetzner cax21 as the deploy target, calling cax21 *"the reference-precedent sizing baseline… not the deploy target."* **Nothing is provisioned today** — no VPS, no Coolify instance, no DNS records exist anywhere in the tree or in Linear. **Finding, not a gate:** ARCH §6 (CI/CD) contradicts ARCH §5 on this point three times, stating flatly "V1 production-only on Hetzner cax21 per §5" — §5 itself says the opposite. This is a live internal ARCH inconsistency, not resolved by this record; flagged to Architect/F/CTO for correction independent of which option below is chosen.

- **Option A — new Hetzner box, same `cax21` class (8 ARM vCores / 16GB / 160GB, Germany, ~€9.50/mo).** *Why:* matches the sizing reference exactly; ARM architecture continuity with the incumbent's container images; familiar Hetzner billing/console for F/CTO. *Losing side:* same headroom as the incumbent — if the GL-feature-set growth or V2 onboarding needs more before a planned resize, a resize is a real (if routine) Hetzner operation, not zero-cost.
- **Option B — new Hetzner box, a larger class** (headroom sized for V1.final's cron/worker count — 4 Coolify units vs the incumbent's fewer — and near-term V2 multi-tenant onboarding). *Why:* avoids a near-term resize. *Losing side:* pays for capacity V1 single-user scale does not need yet; a specific class number is not chosen here — this option is a direction, not a number, pending F/CTO's read of expected near-term growth.
- **Option C — a non-Hetzner VPS provider.** *Why it's listed:* the DevOps charter defaults to Hetzner+Coolify with "no third deployment surface… without a forcing function," and no forcing function is visible anywhere in the tree — no cost, compliance, or capability gap that Hetzner can't meet. *Losing side, stated plainly:* introduces a new billing relationship, a new region/hardening posture, and provider-specific quirks with nothing in the record to justify the switch. **Not recommended** absent a forcing function F/CTO can name.

### Deploy-then-accounts sequencing

- **Option 1 — deploy, then connect real accounts immediately (fastest path to close).** Once stand-up step 9 (Sec sign-off) clears, F/CTO connects every real Plaid/SimpleFIN/manual account the same week. M0 starts immediately; per §D's calendar this is the path that reaches the earliest close date. *Losing side:* any defect the smoke checklist (step 8) didn't catch is discovered against **live financial data** on the F/CTO's actual accounts, not a rehearsal.
- **Option 2 — a dry-run interval before connecting real accounts.** After stand-up, run the production stack for some days/weeks (F/CTO exercises login, the UI, maybe one low-stakes real account) to build confidence in cron reliability, notification delivery, and the TZ drift sweep firing at least once, **before** connecting every account. *Losing side:* every day of dry-run before the tenant-accounts-live date pushes M0/M1/M2 by the same amount — per §D, a full month's slip if the dry-run crosses a month boundary before conversion. This is the direct tradeoff against Option 1's speed.

Both options are compatible with the checklist in §4 — the dry-run choice only affects **when** step 10 (F/CTO connects every account) happens relative to step 9 (Sec sign-off), not whether any gate above is skipped.

---

## Findings surfaced by this research pass (not resolved here — F/CTO / Architect / Sec action)

1. **ARCH §5 vs §6 self-contradiction** on whether Hetzner cax21 is the production target (§5: no; §6: yes, three times). See hosting-target section above.
2. **B.5 AC1's component enumeration omits the `provider-sync` worker**, making AC2 (Plaid production credentials + a successful Link session) structurally unsatisfiable as the AC is currently scoped — provider-sync is Plaid's sole credential holder per ARCH §5.
3. **"ADR-027 (Plaid PRIMARY)" is a citation-attribution drift.** The provider-primacy ruling is ADR-037; ADR-027 explicitly deferred it. The Transactions+Investments product-set commitment traces to ADR-002 §6.0 / PRD §1.3, not to ADR-027 either. The *substance* everyone has been citing it for is correct; the ADR number attached to it is not.
4. **Runbook Open-flags row #11 is stale** — it claims the TimeZone-pin migration still needs authoring; migration `061_pin_database_timezone_utc.sql` already exists on the tree (and the runbook's own §4.1/§10 sections assume it exists and build rich verification procedure on top of it).
5. **Runbook §7 still describes the PDF worker Dockerfile as "a placeholder."** The tree shows a substantial, lock-annotated 108-line Dockerfile marked "EXTENDED" per SELF-348. No stand-up impact; a doc-accuracy item for whoever next touches the runbook.
6. **Plaid's institution-access landscape for the F/CTO's actual accounts (Schwab in particular) carries genuine, currently-unconfirmable external risk** — recommend an early Plaid Link smoke test (stand-up step 7) rather than discovering a coverage gap at the tenant-accounts-live step, where it would cost real schedule.
7. **The Plaid tier terminology in B.5 AC2 ("limited-production tier") is stale relative to Plaid's 2026-04-15 product change** — the operative tier for a team likely created after that date is "Trial plan," which does admit Transactions + Investments. The AC's *outcome* concern is answered; its *wording* should be corrected wherever it is repeated (this record does so; the live Linear issue is F/CTO's or PM's to correct, not touched here per this session's no-Linear-writes instruction).
