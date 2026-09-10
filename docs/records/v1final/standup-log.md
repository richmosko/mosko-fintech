# Production stand-up — as-executed log

**What this file is.** A chronicle of the V1 production stand-up **as it actually happened** — every step taken, the values it produced, and every place reality departed from the plan. It is written *while* standing the system up, not reconstructed afterwards.

**What this file is NOT.** It is not the procedure. Three companion artifacts own that, and this log cites them rather than restating them:

| Artifact | Owns |
|---|---|
| [`docs/deployment-runbook.md`](../../deployment-runbook.md) | **The procedure.** What to run, in what order, and what a correct result looks like. |
| [`production-standup.md`](production-standup.md) | **The plan.** The 13 ordered steps, their owners, and what blocks each. |
| [`standup-preconditions.md`](standup-preconditions.md) | **The rulings** that shaped the plan (Q5 signup-off, Q7 backfill refusal, Q8 Linear shape). |

**Why a separate log.** The runbook is written to be re-run on a rebuild; it must stay clean of one-time incident detail. This log is the opposite — it keeps the incidents. When the runbook and reality disagree, **this file records what happened and the runbook gets corrected**, so the next rebuild does not re-learn it.

**Rules for entries.**

- **Never record a secret value.** Names only — `HETZNER_API_TOKEN`, `PLAID_SECRET`. This file is version-controlled and public to anyone with repo access. If a value must be referenced, name where it lives, never what it is.
- **Record measurements, not intentions.** *"Ran X, got Y"* — not *"will run X"*. An entry is written after the step, not before.
- **Record the departures.** A step that worked first time is one line. A step that did not is the reason this file exists: what was expected, what happened, what fixed it, and whether the runbook needs correcting.
- **Date every entry** and cite the sha, hostname, or record the step produced.
- **One heading per plan step**, numbered to match `production-standup.md` §4, so the two read side by side.

---

## Status at a glance

| Step | What | Owner | State |
|---|---|---|---|
| 1 | Hosting target decided | F/CTO | ✅ Ruled 2026-09-08 — Hetzner CAX21 |
| 2 | `pfin_provider_sync` login-role migration (S5) | Architect | ✅ Migration `116` on `main` (PR #671) |
| 3 | Provision VPS + install Coolify | DevOps + F/CTO | ⏳ Runbook §1/§3 being authored |
| 4 | DNS / domain decision + records | F/CTO + DevOps | ⛔ Blocked — domain not chosen |
| 5 | Stand up self-hosted Supabase; apply migrations | DevOps | ⛔ Blocked on 3 |
| 5a | Production signup OFF (`GOTRUE_DISABLE_SIGNUP=true`) | DevOps | ⛔ Blocked on 5 · ruled Q5 |
| 6 | Deploy the four services from one `main` sha | DevOps | ⛔ Blocked on 5 |
| 7 | ~~Register 9 existing Plaid Items~~ | — | ❌ Struck 2026-09-08 — Items orphaned, tokens lost |
| 7′ | Historical categorized-transaction backfill walk | Backend + F/CTO | ⛔ SELF-388 / SELF-389 not started |
| 8 | Attach-a-provider-account-at-Link-time build | Backend + Sec | ⛔ SELF-390 not started |
| 9 | Plaid production Link sessions | F/CTO | ⛔ Blocked on 7′ + 8 |
| 10 | §10 smoke checklist + reachability + TZ sweep | DevOps + QA | ⛔ Blocked on 6 |
| 11 | Sec pre-production sign-off | Sec | ⛔ Blocked on 3/5/6/8/10 |
| 12 | F/CTO tenant live — **starts the R12 month-1 clock** | F/CTO | ⛔ Blocked on 1–11 |
| 13 | Handoff: month placeholders + M0 completeness check | Backend | ⛔ Blocked on 12 |

---

## Step 1 — Hosting target

**2026-09-08 · F/CTO · RULED.** Option A, a new Hetzner box of the **CAX21** class, provisioned clean with no carried-over state.

**One correction is load-bearing and is recorded here because it was wrong in this repo first.** CAX21 is **4 ARM vCPU / 8 GB RAM / 80 GB NVMe**, read from Hetzner's own product page on 2026-09-08. An earlier 8 vCPU / 16 GB / 160 GB figure had propagated through the tree; that is the **CAX31** spec, a one-tier shift. Anything sizing against the larger numbers is sizing against a box that was never ordered.

## Step 2 — `pfin_provider_sync` login role

**2026-09-09 · Architect + Sec · LANDED.** Migration `116` created the dedicated `NOINHERIT` login role. PR #671, merged at `9ec1182d`.

Sec joint-review reached no-veto over several rounds (round 1 AMBER; conditions C1–C5 discharged). A 13-leg pgTAP battery ships with it, and the measured minimum grant set was the **empty set** under the `TenantBoundClient` fence.

**Outstanding at deploy time, not here:** the container environment cutover to this role is a *runtime* control and is booked at [`BACKLOG.md`](../../../BACKLOG.md) §7.36 item 2. The DDL exists; nothing yet connects as the new role.

## Step 3 — Provision VPS + install Coolify

**2026-09-09 · Blocked on procedure, not on access.** `docs/deployment-runbook.md` §1 and §3 were found to be **STUBs** — the section headers and the hosting ruling exist, but no executable procedure does. DevOps is authoring Prerequisites, §1 and §3 to the standard §4.1 sets in that file.

**F/CTO-held prerequisites** (confirmed 2026-09-09): Hetzner account **active with a payment method**. Domain registrar access still needed for step 4.

**API token — open decision, not a blocker.** A Hetzner API token is scoped per project (Cloud Console → project → Security → API tokens → Generate, Read & Write, value shown once). It is required only for `hcloud`/Terraform-driven provisioning; a single box can be provisioned through the web console with no token at all. **Decide before generating a credential that then has to be managed.** If one is generated, its name goes in `secrets-manifest.yml`; its value goes nowhere in this repo.

> **Fill in when executed:** region, OS image, hostname, IP, SSH key fingerprint, firewall rules as applied, Coolify version installed, and the verification-block results from runbook §1/§3.

## Step 4 — DNS / domain

**⛔ Blocked on an F/CTO decision.** Reuse `pfindash.com` (reference-only today) or register a new domain. The choice is entangled with cutover timing, so runbook §2 is deliberately left unwritten until it is made.

---

## Departures from plan

*Every place reality and the plan disagreed. Empty until the first one — and an empty section here is a claim, so do not leave a real departure out of it.*

| Date | Step | Expected | Actual | Runbook corrected? |
|---|---|---|---|---|
| 2026-09-08 | 7 | Adopt F/CTO's 9 existing Plaid Items | Old Plaid team deleted; its Items were already orphaned with tokens lost. Step struck; replaced by the step 8 attach-at-Link build against a fresh 10-Item Trial team. | n/a — plan record updated |
| 2026-09-09 | 3 | Follow runbook §1/§3 | Both sections were STUBs; no procedure existed to follow. | In progress |
