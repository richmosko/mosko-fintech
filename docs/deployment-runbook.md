# Deployment Runbook — V1 greenfield stand-up

> **Status: SKELETON (Phase 6 entry, 2026-06-29).** This is a stub we fill in incrementally as Phase 6 reveals requirements — **not** a finished runbook. Each section carries a one-line scope note and a `> **STUB —**` marker naming what fills it in and when. Placeholders over fabrication: where a value isn't decided yet, it's flagged, not invented.
>
> **Doc convention:** Markdown (consistent with [`docs/linear-setup.md`](linear-setup.md) — an operational how-to that "answers *how*" per WORKFLOW.md). Not an HTML artifact (those are the canonical reference layer — PRD / ARCH / SECURITY); a runbook is an operational procedure, so Markdown is the right home.
>
> **Owner:** DevOps. **Security-sensitive sections** (§5 Secrets, plus any fence-touching content) gate on Security Reviewer joint-review before lock.

---

## Overview & principles

Scope: what this runbook is, and the non-negotiable principles that shape every step below.

- **Greenfield.** V1 is stood up from scratch on a **new virtual server** at deploy time. No step may assume a pre-existing, working deployment.
- **Reproducible.** The end state is a from-scratch stand-up that can be re-run. Prefer documented, scriptable steps over one-off manual fixes.
- **Incumbent is reference-only.** The existing `pfindash.com` deployment (incumbent self-hosted Supabase on Coolify on the Hetzner **cax21** box, alongside `pfin_back_etl`) is a **reference, not a dependency**. It may be torn down at deploy time. Do **not** query, mirror, or rely on the live incumbent (per memory: `feedback_greenfield_no_existing_deployment_dependency`).
- **Don't depend on the existing deployment.** Postgres 17 is the forward target **by choice** (`supabase/config.toml` `major_version = 17`), not because it matches prod.

> **STUB —** Tighten the principle list and add a "definition of done" once §1–§10 are fleshed out. Cross-reference the greenfield-deployment [ADR-021](../DECISIONS.md#adr-021) (authored in parallel by Architect) as the canonical decision record for this posture.

---

## Prerequisites

Scope: accounts, CLI tooling, and the domain you need in hand before starting.

> **STUB —** Enumerate as each step below is exercised. Known candidates (confirm at first real deploy): Hetzner Cloud account + API token; a domain registrar account; `ssh` keypair for the new box; Coolify (installed in §3, no local CLI required — UI-driven per ARCH §5); Supabase CLI (`supabase`) for migrations (§6); GitHub account with repo access (CI runs there). Pin exact versions when the deploy is rehearsed.

---

## 1. Provision the VPS

Scope: stand up a fresh virtual server to host Coolify + all V1 containers.

- **Reference class (starting point, NOT the target box):** Hetzner **cax21** — 8 ARM vCores / 16 GB RAM / 160 GB disk, Germany, ~€9.50/mo (per memory `reference_hetzner_cax21`). The incumbent runs on this class with substantial headroom; it's a sane *starting reference* for sizing the new box, not the box we deploy onto.
- The new box is provisioned clean — fresh OS, no carried-over state from cax21.

> **STUB —** Fill in: chosen provider/region/instance (F/CTO decision — cax21-class is a reference, not a commitment), OS image + initial hardening (SSH key-only, firewall, non-root user), and any base packages. Confirm ARM-vs-x86 (incumbent is ARM; container images must match). **Flag for F/CTO:** is the new box also Hetzner, and is it the same cax21 class or resized?

---

## 2. DNS / domain

Scope: point the production hostname(s) at the new VPS.

- Incumbent hostname `pfindash.com` is **reference-only** — its disposition (reuse vs. new domain) is an open F/CTO decision, entangled with §9 cutover timing.

> **STUB —** Fill in: the V1 production hostname(s), DNS records (A/AAAA → new box IP), TLS/cert approach (Coolify-managed Let's Encrypt is the likely default — confirm in §3), and any subdomain split (app vs. Supabase vs. Coolify dashboard). **Flag for F/CTO:** reuse `pfindash.com` or stand up a new domain? This decision gates §9 cutover.

---

## 3. Install & configure Coolify

Scope: install Coolify on the fresh box; it is the deployment control plane for all V1 containers (per ARCH §5 — config lives in the Coolify UI; this repo holds only source-of-truth `Dockerfile`s + env-var contracts).

- Deploys go through the **Coolify UI**, not from chat or CI (per ARCH §5). This repo's job is to make the repo-side artifacts (Dockerfiles, `.env.example` contracts) deploy cleanly when F/CTO triggers a deploy.

> **STUB —** Fill in: Coolify install method + pinned version, initial admin setup, GitHub source connection (so Coolify pulls this repo per Base Directory), TLS/proxy config, and the project/service topology skeleton (one Coolify "project" → the V1 services in §6–§7). **Flag:** pin the Coolify version actually used; "latest" is not reproducible.

---

## 4. Stand up Supabase from scratch

Scope: bring up a fresh self-hosted Supabase stack (Postgres 17) on the new box — the data layer for all V1 surfaces.

- **Postgres 17** is the forward target (`supabase/config.toml` `major_version = 17`), by choice.
- **Carried follow-up (open):** PG-17 confirm-vs-prod — the `config.toml` comment notes `major_version = 17` is a best-guess match to the incumbent and should be confirmed before Phase 6 base-table RLS work where version-skew bites harder. In the greenfield posture this is **forward-by-choice**, so the "match prod" framing is reference-only; still confirm 17 is the version actually deployed.

> **STUB —** Fill in: self-hosted Supabase bring-up procedure (Coolify one-click vs. compose), which Supabase services are in scope for V1 (db / auth / storage / realtime / studio — cross-check against `supabase/config.toml` enabled sections), the from-scratch DB init, and how `config.toml` settings map onto the self-hosted stack. **Note:** `supabase/config.toml` is owned elsewhere — this runbook *consumes* it, does not edit it.

---

## 5. Secrets provisioning · 🔒 SECURITY-SENSITIVE (Sec joint-review gates this section)

Scope: inject production secrets into Coolify, honoring the CI/production non-overlap discipline. **This section is security-sensitive — Security Reviewer joint-review is mandatory before it locks** (secrets-manifest + ARCH §4.1 allowlist + Lock 13 territory).

Real artifacts this section binds to (all verified present):

- [`secrets-manifest.yml`](../secrets-manifest.yml) — the CI/production **non-overlap commitment**. Two disjoint sets:
  - `ci_only` (reserved distinct names; no production reach): `PLAID_SANDBOX_CLIENT_ID`, `PLAID_SANDBOX_SECRET`, `PDF_WORKER_SIGNING_KEY_TEST`.
  - `production_only` (Coolify-injected on the box; never in CI): `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `PDF_WORKER_SIGNING_KEY`, `PLAID_CLIENT_ID`, `PLAID_SECRET`, `WORKER_ADMISSION_SHARED_SECRET`, `DISCORD_WEBHOOK_URL`, `PFIN_DB_PASSWORD`, `FMP_API_KEY`, `BLS_API_KEY`.
  - **`WORKER_ADMISSION_SHARED_SECRET` (SELF-212 Option-C, C6-2) provisioning:** generate 256-bit (`openssl rand -hex 32`); inject as a Coolify **project-scoped SHARED variable** referenced by BOTH the api/ web-app service and the provider-sync worker service — one edit point, so rotation updates a single value. **Rotation:** update the shared var → **coordinated restart of BOTH** services (the constant-time compare mismatches mid-rotation, failing admission closed until both restart — a brief onboarding-only outage; acceptable). NOT the service_role key → RT-26 allowlist unchanged. This secret's SAME-value-on-both-tiers shape mirrors `PDF_WORKER_SIGNING_KEY` (web-app + PDF worker per SD-20).
  - **Fail-closed fence:** `scripts/ci/check-secrets-nonoverlap.py` runs as the `secrets-nonoverlap` job in `.github/workflows/security-scan.yml` on every PR + push to `main`; fails closed if the sets intersect, a set is missing/malformed, or a name is duplicated. The **distinct-naming rule** (any CI/test analogue takes a `*_SANDBOX` / `*_TEST` name) is the mechanism that keeps the sets disjoint.
- Per-surface `.env.example` files (each enumerates ONLY its container's permitted secrets — the enumeration *is* the confinement property):
  - [`.env.example`](../.env.example) — V1 web-app container (anon + service_role + PDF signing key + Plaid creds + webhook secret + Discord URL).
  - [`workers/etl/.env.example`](../workers/etl/.env.example) — `pfin_back_etl` container (discrete `PFIN_DB_*` + FMP + BLS + Plaid creds).
  - [`workers/pdf-render/.env.example`](../workers/pdf-render/.env.example) — PDF worker container (**exactly one** secret: `PDF_WORKER_SIGNING_KEY` — zero-DB-isolation per Lock 13 mod #2; RT-22 enforces no DB credential ever appears here).

> **STUB —** Fill in: the actual Coolify secret-injection procedure (per-service env-var entry), the generation/rotation procedure for each production secret (esp. `PDF_WORKER_SIGNING_KEY` — the SAME value on web-app + PDF worker per SD-20; and `SUPABASE_SERVICE_ROLE_KEY` — RT-26 ARCH §4.1-allowlist-confined), and the order of injection vs. first deploy. **Sec joint-review REQUIRED at lock.** Open discrepancies flagged in the artifacts to resolve here: (a) ARCH §5 frames the ETL DB secret as a single conn-string while incumbent code consumes discrete `PFIN_DB_*` — representation difference, reconcile deliberately; (b) ARCH §5 frames BLS as "free/open" (no key) while incumbent code requires `BLS_API_KEY` — reconcile with ARCH/Sec.

---

## 6. Apply migrations

Scope: apply the repo's `supabase/migrations/` against the fresh Postgres 17 instance, in order.

- Present migrations (verified): [`001_pfin_foundation.sql`](../supabase/migrations/001_pfin_foundation.sql), [`002_fn_mask_acct_number.sql`](../supabase/migrations/002_fn_mask_acct_number.sql).
- Phase 6 base-table migrations (SELF-187+) land incrementally — append them here as they're authored.
- **Ownership note:** migrations are **Architect-authored**; DevOps operates on CI's *consumption* of them (test-fixture spin-up per RT-15) and, here, on the production *apply* step. This runbook does not author migration content.

> **STUB —** Fill in: the apply mechanism against self-hosted Supabase (`supabase db push` / `supabase migration up` vs. a CI/Coolify-driven apply), the idempotency/ordering guarantees, and how to verify each migration landed (e.g., RLS policies present, `fn_mask_acct_number` callable). Keep the migration list current as Phase 6 adds tables.

---

## 7. Workers

Scope: deploy the background-worker containers. Per ARCH Lock 13, the V1 runtime is a **hybrid 3-container topology** on Coolify: (1) V1 web-app, (2) `pfin_back_etl` ETL, (3) Node PDF worker — plus the Phase-6/V1.5 cron + scheduled-poll additions.

- **`pfin_back_etl` (ETL)** — `workers/etl/`, Coolify **Base Directory** `workers/etl/`; Dockerfile [`workers/etl/Dockerfile`](../workers/etl/Dockerfile) (DevOps-owned). Python ETL (BLS CPI + FMP financials → Supabase). **Forward discipline:** all `pfin` DB access binds `users_id` via TenantBoundConnection (Lock 13 mod #3) — TBC + `fence-tbc` coverage land Wave 6; incumbent currently uses SQLAlchemy `create_engine`.
- **Node PDF worker** — `workers/pdf-render/`, Dockerfile [`workers/pdf-render/Dockerfile`](../workers/pdf-render/Dockerfile) (currently a placeholder; Backend adds Puppeteer app code at Wave 6). **Zero DB reach by design** (Lock 13 mod #2) — NO database libraries, credentials, or network reach; reaches data only via the web-app's `/internal/pdf-render` endpoint under a short-lived signed JWT. RT-22 fence enforces the Dockerfile credential/Postgres-client absence.
- **`provider-sync` (Plaid/SimpleFIN ingest)** — `workers/provider-sync/`, Coolify **Base Directory** `workers/provider-sync/`; Dockerfile [`workers/provider-sync/Dockerfile`](../workers/provider-sync/Dockerfile) (DevOps-owned). The 4th Coolify unit (ADR-019 amendment) — the FIRST DB-touching **Node** worker. **Direct-Postgres** transport (`PFIN_DB_*`, login role `authenticator`, writes AS `service_role` via `SET LOCAL ROLE` per ADR-023) via **TenantBoundClient** (Lock 13 mod #3; `fence-tbc-node` enforces at PR-time). **OFF the RT-26 allowlist by design** — no `SUPABASE_SERVICE_ROLE_KEY`, no `@supabase/supabase-js`. Env contract: [`workers/provider-sync/.env.example`](../workers/provider-sync/.env.example).
- **`provider-sync` SELF-212 admission endpoint (Option C, internal-only) — deploy config:**
  - **Build pack = Compose (b-i).** Coolify consumes the committed [`workers/provider-sync/docker-compose.yaml`](../workers/provider-sync/docker-compose.yaml) (not the bare Dockerfile build pack). This is what makes the admission endpoint's exposure surface **committed + lintable** (the `fence-admission-bind` CI job / RT-27 network-exposure layer). The admission port (`8081`) is `expose:`-only — **NEVER add a published `ports:` mapping and NEVER assign a Coolify Domain / Traefik `Host()` label to this service.**
  - **CA-4 — SAME Coolify project (hard prerequisite):** the api/ web-app service and the provider-sync service **MUST** live in the **same Coolify project** so internal DNS `http://provider-sync:8081` resolves (Coolify's internal network is per-project). Cross-project placement breaks internal reach **and** tempts a public-Domain "fix" — the exact silent-exposure regression RT-27 / §10 fences. Verified at §10 smoke.
  - **CA-1 — deploy-time public-route env verification:** at first deploy (and after any Coolify upgrade), dump the admission container's actual env and confirm the worker's limb-(a) prefix regex (`^(COOLIFY_FQDN|COOLIFY_URL|ADMISSION_PUBLIC_URL)$` or `^SERVICE_(FQDN|URL)_`) would match Coolify's real injected FQDN/URL var names for that version — because those names are Coolify-version-dependent, and a rename must not silently slip a Domain past the tripwire. Var-name set + rationale: [`temp/self212-devops-ca1-coolify-route-envvars.md`](../temp/self212-devops-ca1-coolify-route-envvars.md).
- **Cron containers (Phase 6 / V1.5):** the `monthly_report` worker (V1.5), the Plaid scheduled-poll worker (Wave 6), and the **`provider-sync` daily poll** (ADR-027 slice-3b) run as **native Coolify cron** (Wave 6 Gate F Option α, F/CTO-ratified), not an in-app scheduler.

- **V1 worker cron convention (Pattern A — resident container + Coolify Scheduled Task):** scheduled worker runs use Coolify's native cron primitive, which is a **Scheduled Task** (`docker exec` of a command into a **resident** service on a cron). The container's `CMD` is a resident keepalive (`tail -f /dev/null`, per [`workers/etl/Dockerfile`](../workers/etl/Dockerfile)); the scheduled work is a separate Coolify UI-configured command. **Not** a one-shot container: Coolify has no one-shot-cron primitive, and an exited Application container restart-loops under Coolify's restart policy. This is a DevOps-owned in-repo convention (distinct from the cax21 Coolify config, which is reference-only per ADR-021).
  - **`provider-sync` daily poll** — Scheduled Task, cron **`@daily`** (cadence lean per DevOps; SimpleFIN flat-fee + Plaid bills per-Item/month so cadence ≈ cost-neutral; F/CTO may adjust at deploy — reversible dashboard config), command **`node dist/cli/poll.js`** (design memo §1). Fleet-fatal (can't enumerate / DB unreachable) → **exit 1** → Scheduled-Task failure routes **Coolify→Discord** (§8); a completed run **exits 0 even with per-source failures** — each is isolated, captured in a `scheduled_poll` `linked_source_sync_audit` row + emitted as a structured `FAILED source_id=…` log line (Coolify-log-routable, never a page). A gappy/revoked institution never exits non-zero.
    - **Poll env (required subset — confirmed against `loadConfig()`):** `PFIN_DB_*` (login role `authenticator`) **+ `PLAID_CLIENT_ID` / `PLAID_SECRET` / `PLAID_ENV`**. Plaid creds are **required at boot** — `loadConfig()` throws on absence *even for a SimpleFIN-only source set* (Plaid is a live V1 provider, so this is fine for V1; making Plaid optional is a small `env.ts` change if a Plaid-less container is ever wanted). **NOT** `SIMPLEFIN_TOKEN` (the poll reads each source's stored Access URL from `decrypted_source_credential`; the bridge token is only the `admit` entrypoint's concern), **NOT** a Discord webhook secret (Discord is Coolify-side, §8), **NEVER** `SUPABASE_SERVICE_ROLE_KEY` (off-RT-26 posture; `fence-tbc-node` LEG 2 zero-hit). All are `production_only` secrets (§5) — non-overlap fence unaffected.

> **STUB —** Fill in per container: Coolify service config (Base Directory, build pack = Dockerfile, ports/networking), env-var wiring (→ §5), the cron schedule expressions for `monthly_report` + Plaid poll (the `provider-sync` daily-poll Scheduled Task is captured above), and resource limits. Note the web-app container (the 3rd of the 3) is owned at `api/` — its deploy config slots in here once the SvelteKit scaffold lands in Phase 6.

---

## 8. Observability

Scope: wire deploy + health/failure notifications.

- **Coolify → Discord** is the **incumbent, working** notification routing (F/CTO has this configured on cax21; per memory `reference_coolify_discord_notifications`). Coolify supports 6 mechanisms (Email/Slack/Discord/Telegram/Pushover/Generic Webhooks); **Discord is incumbent** — do not propose Slack/PagerDuty/Email without a forcing function. `DISCORD_WEBHOOK_URL` is a `production_only` secret (§5).

> **STUB —** Fill in: re-establish the Coolify→Discord webhook on the new box (the incumbent config does not carry over — greenfield), which events route (deploy success/failure, container health), and any per-service notification routing. Reference ARCH §4 Observability row.

---

## 9. Cutover & teardown of `pfindash.com`

Scope: switch production traffic to the new box and retire the incumbent.

- The incumbent `pfindash.com` deployment is reference-only and **may be torn down at deploy time**. There is no migration-of-data dependency on it (greenfield); teardown is a clean retirement, not a hand-off.

> **STUB —** Fill in: the cutover sequence (DNS flip from §2, verification gate from §10 *before* teardown), any data the F/CTO wants to export from the incumbent first (decision — greenfield posture implies none required, confirm), and the teardown steps for the cax21 incumbent stack. **Flag for F/CTO:** cutover timing + whether `pfindash.com` is reused (links to §2) + go/no-go gate (teardown only after §10 smoke-test passes). This is a **one-way door** once teardown executes — present as such.

---

## 10. Verification / smoke-test

Scope: prove the from-scratch stand-up actually works before declaring V1 deployed (and before §9 teardown).

- Anchors to the existing test posture: the SELF-186 V1.0 smoke-test pattern (PASSED in Phase 5), the RLS verification battery (QA-owned), and the per-surface fences (RT-22 / RT-26 / TBC) which gate at PR-time, not deploy-time.

- **CA-2 — admission-endpoint external-reachability NEGATIVE smoke (SELF-212 Option-C; ship-block; DevOps-owned deploy assertion):** post-deploy, empirically assert the provider-sync admission endpoint (`:8081`) is **NOT** reachable from outside the private Docker network. This is the empirical backstop the limb-(a) env-signal heuristic is only a proxy for (and which covers the Coolify FQDN-var non-update fail-open — see [`temp/self212-devops-ca1-coolify-route-envvars.md`](../temp/self212-devops-ca1-coolify-route-envvars.md)).
  - **NEGATIVE assertion (must FAIL to connect):** from a host *outside* the Coolify project network (e.g. the public internet / a non-project host), an HTTP request to any candidate public FQDN + the admission path must be **refused / unreachable / non-routable** — never a 2xx/4xx *from the admission app* (a 4xx from the app means it was reached). Test both (a) any assigned Coolify Domain for the service (there must be none) and (b) the raw host IP on `:8081` (must be closed — `expose:` does not host-publish).
  - **POSITIVE control (must SUCCEED):** from a sibling container *inside* the same Coolify project, `http://provider-sync:8081` health path returns 2xx — proves internal reach works (so the negative result above is "correctly private," not "app simply down").
  - **CA-4 same-project check:** the positive control passing IS the same-project-internal-DNS assertion — if `http://provider-sync:8081` does not resolve from the api/ container, api/ and provider-sync are not co-located in one project (fix before proceeding; do NOT "fix" by assigning a public Domain).
  - Wire this as a go/no-go gate item alongside the §9 teardown gate. QA owns the cross-tenant/RLS assertions; DevOps owns this infra-reachability assertion.

> **STUB —** Fill in: the end-to-end smoke checklist (web-app reachable over TLS; auth login; a seeded user sees only their own rows — RLS isolation; a migration-backed query returns; PDF render round-trips via the signed-JWT path; ETL container runs one poll; Discord notification fires). This gates §9 teardown — define the explicit pass/fail go/no-go criteria here. QA owns the RLS/isolation assertions; DevOps owns the infra-reachability assertions.

---

## 11. User deletion / GDPR erasure — FK cascade considerations

Scope: operational-completeness ordering for deleting a user (GDPR erasure / account closure). **This is NOT an isolation concern** — RLS + the Decision-3 matched-tenant fences enforce isolation independently. It documents an FK-cascade *ordering* requirement so a user delete does not fail loud partway through.

**Canonical erasure routine (unchanged):** per [ADR-011](../DECISIONS.md#adr-011) Decision 8's GDPR-erasure forward-note, the routine enumerates the user's linked Items → `/item/remove` each (revoke-at-provider + `service_role` secret-delete, under `service_role`, **never** a DEFINER trigger) → **then** delete `auth.users`. The `auth.users` delete then cascades to the tenant's `pfin.*` rows.

**Journal-grouping cascade interaction (M2 / migration `033` — the new step):** the double-entry grouping layer introduces a cascade that can **block** the `auth.users` delete:

- `pfin.journal.users_id → auth.users(id)` is **`ON DELETE CASCADE`** — deleting a user cascade-deletes that user's `journal` rows.
- `pfin.account_trans_annotation.journal_id → pfin.journal(journal_id)` has **no explicit `ON DELETE` → `NO ACTION` (fail-loud)** — a `journal` that still has legs attached (annotation rows carrying a non-NULL `journal_id`) **cannot be deleted**, so its cascade aborts.

Net effect: **deleting a user who has grouped legs FAILS** (the `journal` cascade-delete is blocked by the still-attached annotation legs) **unless the legs are detached first.** Before the `auth.users` delete, the erasure routine must **NULL/detach `pfin.account_trans_annotation.journal_id`** for the tenant's rows (or remove those annotation rows) so the `journal` cascade can complete. Detach (`SET NULL`) is the lighter option — the `journal_id` column is nullable (NULL = unattached, the default), and detaching does not touch the immutable ledger.

**Also in dependency-order teardown:** the mutable `023` annotation overlay and the `029` `account_trans_split` children both hang off the immutable `account_trans` ledger via **`ON DELETE RESTRICT`** FKs, so they must be torn down (or the parent rows left in place per retention policy) in dependency order as part of the same routine — the `journal_id` detach above is the one *new* fail-loud edge M2 adds on top of that existing shape.

> **Note (Architect / Sec):** this section records the ordering obligation; the concrete erasure implementation (a `service_role` routine or admin procedure) is not yet built — when user-facing deletion lands, it MUST run the detach-then-cascade sequence above and MUST NOT reach for a `SECURITY DEFINER` trigger to auto-clean (per [ADR-011](../DECISIONS.md#adr-011) Decision 8, that would reintroduce the un-revocable-grant regression Sec ruled against). Sec joint-review gates the erasure routine at build time.

---

## Open flags (roll-up)

| # | Flag | Owner | Section |
|---|---|---|---|
| 1 | New VPS provider/region/class — cax21 is a *reference*, not a committed target | F/CTO | §1 |
| 2 | Reuse `pfindash.com` vs. new domain (gates cutover) | F/CTO | §2 / §9 |
| 3 | Pin Coolify version (reproducibility) | DevOps | §3 |
| 4 | PG-17 confirm-vs-deployed (carried follow-up; greenfield = forward-by-choice) | DevOps / Architect | §4 |
| 5 | Secrets provisioning procedure + rotation — **Sec joint-review mandatory at lock** | DevOps + Sec | §5 |
| 6 | ETL secret shape: discrete `PFIN_DB_*` vs. ARCH §5 conn-string — reconcile | DevOps / Architect / Sec | §5 |
| 7 | BLS key: code requires `BLS_API_KEY` vs. ARCH §5 "free/open" — reconcile | Architect / Sec | §5 |
| 8 | Cutover timing + teardown go/no-go (**one-way door**) | F/CTO | §9 |
| 9 | ✅ Cross-ref greenfield-deployment ADR-021 (resolved) | DevOps | Overview |

> **STUB —** This runbook is a skeleton. Each `> **STUB —**` marker above is a fill-in point as Phase 6 reveals the operational detail. Do not treat any section as complete until its STUB marker is removed and (for §5 + fence-touching content) Sec joint-review has signed off.
