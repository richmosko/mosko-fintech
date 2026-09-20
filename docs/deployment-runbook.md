# Deployment Runbook — V1 greenfield stand-up

**Owner:** DevOps. §5 and §6 are Sec joint-review-gated. Production is Coolify on Hetzner cax21 — no other deploy surface.

## How to use this sheet

1. **Prereqs:** an operator Mac with this repo checked out; a filled-in `.env` per [`scripts/provision.env.example`](../scripts/provision.env.example); `BOX_IP` (set once §1 completes); the automation SSH key (`~/.ssh/id_ed25519_claude_mosko-fintech`, passphrase-free, per §1).
2. **Every step is: preflight first (no flag — read-only), then `--apply`, paste the output.** Scripts are idempotent; a preflight against an already-done step reports "already satisfies."
3. **Stop on any non-zero exit or a STOP/FAIL/VIOLATION line.** Do not proceed to the next numbered step.
4. **Status column:** SCRIPTED = run the named script. BY-HAND = no wrapper exists yet; the "why" column names the reason (an interactive-credential moment, a one-time measurement, a classifier-blocked property, or NOT YET SCRIPTED with a BACKLOG cite).
5. **The "why" behind any step — MEASURED findings, incident history, Sec dispositions, design rationale — lives in the cited script's own header comment, in [`DECISIONS.md`](../DECISIONS.md), or in [`docs/archive/deployment-runbook-rationale-2026-09-20.md`](archive/deployment-runbook-rationale-2026-09-20.md).** This sheet is the execution path only.
6. **§7 (Workers) has not yet been converted to this shape** — a second, concurrent PR (W-3) owns it; it remains prose until that lands.
7. One-command spine: `scripts/standup.sh --apply` runs §1+§3 (`provision-vps.sh`), §4 (`provision-supabase-stack.sh`), and the JWT-key mint as one invocation. It does not cover §2 (DNS), §5 (secrets entry), §6 (migrations + role handoffs), or §7 (worker resources).
8. Record every by-hand measurement's output in `docs/records/v1final/standup-log.md` (the as-executed chronicle) — this sheet is the reusable procedure, that log is the dated record.
9. 🔒 = security-sensitive; Sec joint-review gates lock.
10. Open, unscripted items and ship-block gates stay visible below as PENDING rows — they are execution facts, not rationale.

---

## Overview & Prerequisites

| # | What | Command / where | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 | F/CTO creates Hetzner account + payment method | Hetzner Cloud Console | account active | BY-HAND | interactive-credential moment |
| 2 | F/CTO mints `HETZNER_API_TOKEN` (Read & Write), sets it in root `.env` | Hetzner Console → project → Security → API Tokens | token in `.env` | BY-HAND | interactive-credential moment |
| 3 | F/CTO sets `COOLIFY_ADMIN_EMAIL`/`_NAME`/`_PASSWORD` in `.env` | edit `.env` per [`scripts/provision.env.example`](../scripts/provision.env.example) | values present | BY-HAND | interactive-credential moment — human-chosen password, not generated |
| 4 | F/CTO confirms registrar access for the production domain | registrar console | access confirmed | BY-HAND | interactive-credential moment |
| 5 | F/CTO's SSH keypair, public half ready for §1 | local `~/.ssh` | pubkey path known | BY-HAND | interactive-credential moment |
| 6 | Production secret **values** (`SUPABASE_SERVICE_ROLE_KEY`, `PLAID_CLIENT_ID`/`PLAID_SECRET`, etc.) go in `.env`, names only per [`secrets-manifest.yml`](../secrets-manifest.yml) | edit `.env` | values present, never in repo/chat | BY-HAND | interactive-credential moment |

Everything else (Coolify itself, the `supabase` CLI, GitHub source connection) is DevOps-preparable with no F/CTO-only credential and is covered by the scripted steps below.

---

## 1. Provision the VPS

Ruled spec: Hetzner **CAX21** (4 ARM vCPU / 8 GB / 80 GB NVMe), region `fsn1` (fallback `hel1`), Ubuntu 24.04 LTS arm64. [ADR-021](../DECISIONS.md#adr-021).

| # | What | Command | Expected (last line) | Status | Reason |
|---|---|---|---|---|---|
| 1 | Provision box + harden (SSH key-only, non-root `deploy` user, firewall, security updates) + install Coolify + admin bootstrap | `scripts/provision-vps.sh --apply` | `BOX_IP=<ip>` printed, write it to `.env` | SCRIPTED | |
| 2 | Confirm box matches ruled spec | `ssh deploy@<box-ip> 'nproc; free -h; df -h /; uname -m; lsb_release -ds'` | `4` · `~8Gi` · `~80G` · `aarch64` · `Ubuntu 24.04.x LTS` | BY-HAND | one-time measurement |
| 3 | Confirm password auth is off | `ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no deploy@<box-ip> echo should-fail` | connection refused/denied | BY-HAND | one-time measurement |
| 4 | Confirm firewall — only 22/80/443 reachable | `nmap -Pn -p 22,80,443,5432,6543,8000,8081 <box-ip>` (from outside the box's network) | `22,80,443` open; rest filtered/closed | BY-HAND | one-time measurement |
| 5 | Confirm IPv6 `/64` matches the recorded value | `ssh deploy@<box-ip> "ip -6 addr show scope global \| awk '/inet6/{print \$2}'"` | matches `docs/records/v1final/standup-log.md` | BY-HAND | one-time measurement |

Firewall never opens `:8081` (provider-sync admission) or `:5432`/`:6543` (Postgres/pooler) — those stay `expose:`-only, verified downstream at §10 CA-2/CA-7. Dashboard (`:8000`) is reached over an SSH tunnel, never opened.

---

## 2. DNS / domain

Ruled: reuse `pfindash.com` — domain only, not the incumbent box/config.

| # | What | Command | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 | Snapshot live records before touching anything | `dig +short pfindash.com A/AAAA/MX/TXT; dig +short www.pfindash.com` | recorded in standup-log.md | BY-HAND | one-time measurement |
| 2 | Set A/AAAA/www at registrar | registrar UI: `A @ → <box-ipv4>`, `AAAA @ → <box-ipv6>` (if any), `www` alias of apex | records saved | BY-HAND | interactive-credential moment |
| 3 | Lower TTL ≥ one cycle before cutover | registrar UI, TTL → 300s | TTL updated | BY-HAND | interactive-credential moment |
| 4 | Confirm propagation from ≥2 independent resolvers | `dig +short @8.8.8.8 pfindash.com A; dig +short @1.1.1.1 pfindash.com A` | both return `<box-ipv4>` | BY-HAND | one-time measurement |

Leave MX/TXT/other existing records untouched unless F/CTO names one to change. TLS is automatic (Coolify's Traefik + Let's Encrypt) once the A/AAAA record resolves and the Domain is assigned in Coolify (§3).

---

## 3. Install & configure Coolify

| # | What | Command | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 | Install Coolify (pinned version), bootstrap admin, mint API token | `scripts/provision-vps.sh --apply` (same run as §1) | six containers healthy | SCRIPTED | |
| 2 | Persistent local tunnel to dashboard/API/MCP (`:8000`/`:3000`) | `scripts/mac-tunnel.sh install --box-ip <box-ip> --apply` then `scripts/mac-tunnel.sh verify` | `:8000` → `302` | SCRIPTED | |
| 3 | Enable Coolify MCP (optional, one-time) | Dashboard → Settings → Advanced → enable, or `tinker` one-liner (see script header) | `/mcp` no longer 404s | BY-HAND | interactive-credential moment — one-time F/CTO preference toggle |
| 4 | Connect GitHub source (GitHub App or deploy key) | Dashboard → Sources → add | this repo authorized | BY-HAND | interactive-credential moment |
| 5 | Create the 4 non-Supabase `dockercompose` resources (`app`/`etl`/`pdf-render`/`provider-sync`), each with an `external:` network attachment to its peers per [ADR-073](../DECISIONS.md#adr-073) | `scripts/provision-app.sh --apply` / `scripts/provision-worker.sh --apply` (§7, not this PR's scope) | resources exist, networks attached | SCRIPTED | — |

Do **not** configure the `main`-watching auto-deploy webhook yet (ARCH §6 item (f) — its own Sec-consult-mandatory step, not part of install). Coolify project/environment placement has no connectivity meaning — only a compose's own `networks:` block decides reachability; verify attachment explicitly, never infer it from project co-location.

---

## 4. Stand up Supabase from scratch

Bring-up: a Coolify `dockercompose` resource sourced from Supabase's own reference self-hosting compose (trimmed at [`infra/supabase/docker-compose.yml`](../infra/supabase/docker-compose.yml)) — **not** Coolify's one-click Supabase service (pins PG 15, wrong major version). Resource must be created with `base_directory: /infra/supabase`, `docker_compose_location: /docker-compose.yml`, and **"Source commit availability" = "Available during build"** (Advanced tab) — both asserted by the script on every run.

| # | What | Command | Expected (last line) | Status | Reason |
|---|---|---|---|---|---|
| 1 | Provision the stack: mint secrets, materialize file-shaped mounts, deploy, run the verification battery | `BOX_IP=<box-ip> scripts/provision-supabase-stack.sh --apply` | verification battery passes | SCRIPTED | |
| 2 | Confirm Postgres major version | `psql "$PROD_DB_URL" -Atc "show server_version;"` | `17.x` | BY-HAND | one-time measurement |
| 3 | Confirm signup is disabled at the endpoint (not by config read) | `curl -s -o /dev/null -w '%{http_code}\n' -X POST "$PUBLIC_SUPABASE_URL/auth/v1/signup" -H "apikey: $SUPABASE_ANON_KEY" -H 'Content-Type: application/json' -d '{"email":"probe-'"$(date +%s)"'@example.invalid","password":"probe-password-1234"}'` | non-2xx (signup refused) | BY-HAND | one-time measurement |
| 4 | Invite the founding tenant (never via signup) | `supabase.auth.admin.inviteUserByEmail(...)` with the production `SUPABASE_SERVICE_ROLE_KEY` (see script header for the one-off snippet) | invite sent | BY-HAND | interactive-credential moment |
| 5 | Apply migrations to the fresh instance | (§6 below — not this section) | — | — | — |
| 6 | Mint real `ANON_KEY`/`SERVICE_ROLE_KEY` (placeholders → signed JWTs), redeploy, verify | `BOX_IP=<box-ip> scripts/mint-supabase-jwt-keys.sh --apply --verify-live` (add `--app-name <name>` once `app` exists) | `VERIFIED` | SCRIPTED | |
| 7 | If a bind-mount landed as an empty directory (gateway/db config missing) | `scripts/coolify-materialize-supabase-mounts.sh --apply`, then redeploy | mounts show `is_directory=false` | SCRIPTED | |
| 8 | Stack-level health + version check | `docker compose -f <compose> ps; psql "$PROD_DB_URL" -Atc "show server_version;"; curl -s -o /dev/null -w '%{http_code}\n' "$PUBLIC_SUPABASE_URL/rest/v1/"` | all healthy, `17.x`, gateway returns a `4xx` refusal (no `apikey`) | BY-HAND | one-time measurement |

`rest` reporting unhealthy with `{"code":"3F000","message":"schema \"pfin\" does not exist"}` is expected until §6's migrations land — not a defect. `api-gw` and `supavisor` stay `expose:`-only; never restore upstream's `ports:` mappings (§10 CA-7 verifies this post-deploy). `PGRST_DB_SCHEMAS` example (verified against the ruled literal — [ADR-023](../DECISIONS.md#adr-023)): `PGRST_DB_SCHEMAS=public,graphql_public,pfin` — flipped at §6.9, not here (production ships `public,graphql_public` until then).

### 4.1 Database TimeZone — pinned to UTC (financial-correctness dependency)

Invariant: the production session `TimeZone` is `UTC` **by declaration** ([`061`](../supabase/migrations/061_pin_database_timezone_utc.sql)), verified by `source`, never by `value` alone — an unpinned image already defaults to UTC, so a value-only check passes vacuously. Never set `PGTZ` anywhere (overrides the pin; `TZ` alone does not). Run all three checks **after §6's migrations**, before §10 sign-off.

| # | What | Command | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 | Verify the pin, per LOGIN role (never as `postgres`) | see block below | `<role>\|UTC\|database` for every role | BY-HAND | one-time measurement |
| 2 | Disambiguate "not applied" from "stale session" via the catalog (session-independent) | see block below | a row with `TimeZone=UTC` | BY-HAND | one-time measurement |
| 3 | Sweep — no role may carry its own `TimeZone` | see block below | zero rows | BY-HAND | one-time measurement |
| 4 | Recycle app/worker containers after the pin lands | redeploy `app`, `etl`, `provider-sync` | fresh sessions report the pin | BY-HAND | one-time measurement |

Step 1:
```sh
for URL in "$PROD_URL_AUTHENTICATOR" "$PROD_URL_PFIN_ETL"; do
  psql "$URL" -Atc "select current_user, setting, source from pg_settings where name='TimeZone'"
done
```

Step 2 (⚠ selects only the anchored `c`, never `s.setconfig` wholesale — that row also carries the live JWT signing secret):
```sh
psql "$PROD_DB_URL" -At -c "select c from pg_db_role_setting s join pg_database d on d.oid = s.setdatabase cross join lateral unnest(s.setconfig) as c where s.setrole = 0 and d.datname = current_database() and c ilike 'timezone=%'"
```

Step 3 (⚠ CI-fenced verbatim query — `scripts/ci/check-tz-sweep-identical.py` keeps this token-identical to (T3) in `supabase/tests/01_session_timezone.sql`; do not reword):
```sh
psql "$PROD_DB_URL" -Atc \
  "select r.rolname, d.datname, c as setting
     from pg_db_role_setting s
     join pg_roles r on r.oid = s.setrole
     left join pg_database d on d.oid = s.setdatabase
     cross join lateral unnest(s.setconfig) as c
    where s.setrole <> 0
      and c ilike 'timezone=%'"
```
Clear a violation with `alter role <role> reset timezone` — never `reset all` (roles carry other load-bearing settings).

---

## 5. Secrets provisioning 🔒

Non-overlap commitment: [`secrets-manifest.yml`](../secrets-manifest.yml) — `ci_only` (6 names) and `production_only` (20 names) are disjoint sets, checked fail-closed on every PR by `scripts/ci/check-secrets-nonoverlap.py`. Counts are load-bearing — if the job's printed `N ci_only + M production_only` disagrees with the manifest, the manifest wins; fix this sheet, not the fence.

| # | What | Command | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 | Push all mapped `production_only` secrets (values from operator `.env`) to their Coolify resources | `BOX_IP=<box-ip> scripts/push-production-secrets.sh --apply` (`--skip-missing-resource` for a deliberate partial run) | names-only report, grouped by resource | SCRIPTED | |
| 2 | Redeploy every resource the push touched (env only takes effect at deploy time) | Coolify UI Deploy, or `POST /deploy?uuid=<uuid>` | resource healthy on redeploy | BY-HAND | one-time measurement |
| 3 | Set non-secret runtime config (`PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY`, `PFIN_DB_SSLMODE=disable`) on `app`/workers | Coolify UI env, per-service | values present | BY-HAND | NOT YET SCRIPTED — BACKLOG §7.36 (follow-up, no item number assigned yet) |

Excluded from the script by design: the Supabase stack's own 9 names (minted by `provision-supabase-stack.sh`) and `PFIN_DB_PASSWORD` (generated at the §6.1/§6.2 handoff, different value per container). This section runs functionally **after** §7 (resources must exist first) despite its number — F/CTO-ratified divergence.

---

## 6. Apply migrations

Mechanism: the dedicated `migrator` service ([ADR-072](../DECISIONS.md#adr-072) Option E). Migrations: [`supabase/migrations/`](../supabase/migrations/), applied in order via `supabase db push`, tracked in `supabase_migrations.schema_migrations` (idempotent, re-runnable). Architect-authored; DevOps operates the apply step only.

### 6.0 Before §6.1/§6.2/§6.3 — prepare credentials, know the privilege shape

`postgres` is **not** superuser on this image (`rolsuper=f`); the true superuser is `supabase_admin`. Every interactive vehicle below needs `ssh -t`, not a bare `ssh`.

| # | What | Command | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 | Generate `pfin_etl` + `pfin_provider_sync` passwords | `openssl rand -hex 32` (×2) | two values held for §5 push | BY-HAND | interactive-credential moment |
| 2 | Look up the already-minted `migrator` password | `scripts/db-shell.sh --migrator-url --i-am-a-human` | credential printed to an operator terminal only | BY-HAND | interactive-credential moment — OPERATOR-ONLY, an agent must never run this |
| 3 | Preflight role state (exists? LOGIN? password set?) | `scripts/db-role-handoff.sh <pfin_etl\|pfin_provider_sync>` (no `--apply`) | current state printed | SCRIPTED | |
| 4 | Generate credential, deliver to box (0600 seed over SSH stdin), run `\password`+`ALTER ROLE...LOGIN`, verify by live connect, push `PFIN_DB_PASSWORD` to the worker's Coolify resource, confirm push landed | `BOX_IP=<box-ip> scripts/db-role-handoff.sh <role> --apply [--rotate]` | verified handoff, `PFIN_DB_PASSWORD` presence confirmed | SCRIPTED | |
| 5 | Restart/redeploy the affected worker only | Coolify UI Deploy, or `POST /deploy?uuid=<worker-uuid>` | worker healthy on the new credential | BY-HAND | NOT YET SCRIPTED — BACKLOG §7.36 (W-3 follow-up) |

### 6.1 `pfin_etl` role provisioning 🔒 — REQUIRED one-time deploy step

Ordering: **migrations applied (§6) → `pfin_etl` password set, then LOGIN flipped → `PFIN_DB_*` env injected (§5) → ETL container started (§7).** Covered end-to-end by §6.0's `db-role-handoff.sh`.

| # | What | Command | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 | Full handoff (see §6.0 rows 3–5) | `scripts/db-role-handoff.sh pfin_etl --apply` | verified handoff | SCRIPTED | |
| 2 | Verify role state directly | `select rolcanlogin, rolinherit, rolsuper, rolbypassrls from pg_catalog.pg_roles where rolname = 'pfin_etl';` | `t, f, f, f` | BY-HAND | one-time measurement |

Rotation: `\password pfin_etl` + restart the ETL container only (no coordinated redeploy — the point of the dedicated role). Revocation: `ALTER ROLE pfin_etl NOLOGIN` stops the ETL and nothing else.

### 6.2 `pfin_provider_sync` role provisioning 🔒 — REQUIRED one-time deploy step

Same two-step shape as §6.1, in the **same Phase-7 deploy pass** as `pfin_etl`.

| # | What | Command | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 | Full handoff | `scripts/db-role-handoff.sh pfin_provider_sync --apply` | verified handoff | SCRIPTED | |
| 2 | Verify role state directly | `select rolcanlogin, rolinherit, rolsuper, rolbypassrls from pg_catalog.pg_roles where rolname = 'pfin_provider_sync';` | `t, f, f, f` | BY-HAND | one-time measurement |
| 3 | Post-cutover: confirm the CONTAINER's effective identity, not just the role catalog | `select distinct usename from pg_stat_activity where application_name = 'provider-sync';` | `pfin_provider_sync` | PENDING | NOT YET SCRIPTED — worker does not yet set `application_name` (BACKLOG §7.36 item 2) |

### 6.3 `pfin_owner` + `migrator` provisioning and first bootstrap

Ownership-by-construction: `pfin_owner` (NOLOGIN group role) owns every `pfin` object; every applier enters it via paired `set role`/`reset role` ([ADR-072](../DECISIONS.md#adr-072) Amendment 5). Three supervised phases, in order.

| # | What | Command | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 | Check whether `migrator` already has a working credential on this box (Sec-required before touching it) | `select r.rolcanlogin, a.rolpassword is not null as password_set from pg_catalog.pg_roles r join pg_catalog.pg_authid a on a.rolname = r.rolname where r.rolname = 'migrator';` | `t\|t` → skip step 2 below | BY-HAND | one-time measurement |
| 2 | PHASE 1 (pre-step), as `supabase_admin`: roles, auth grants, `pfin` schema + engine backstop, `migrator` credential (fresh-box branch only), role-comment files | `psql -U supabase_admin -d <app_db> -f supabase/roles.sql` then `-f supabase/auth-grants.sql`; `revoke create on schema pfin from migrator, public;`; `\password migrator` + `alter role migrator login;` (fresh-box only); then run `055`/`116`/`117`/`118`/`119` migration files directly | `has_schema_privilege('pfin_owner','auth','USAGE')` = `t` | BY-HAND | interactive-credential moment |
| 3 | PHASE 2 (main pass), as `migrator`, from its own container | `docker compose --project-name <supabase-stack-app-uuid> exec -T migrator sh -c 'supabase db push --yes --db-url "$PROD_DB_URL" --workdir /workspace'` | `"Finished supabase db push"`, `bootstrap_complete = t` | BY-HAND | interactive-credential moment — steady-state via §6.4/§6.5 once live |
| 4 | Verify Phase 2 — the ownership census | see [`DECISIONS.md`](../DECISIONS.md#adr-072) Amendment 5 Decision E / archive for the full 9-query block | every `pfin` object owned by `pfin_owner`; zero `postgres`/`migrator` rows | BY-HAND | one-time measurement |
| 5 | PHASE 3 (post-step), as `supabase_admin`, AFTER Phase 2 and BEFORE §7 | `psql -U supabase_admin -d <app_db> -f supabase/post-step-vault-view.sql` | assertion block passes (exactly one decrypt view, `pfin_owner`-owned, `security_invoker=true`) | BY-HAND | interactive-credential moment |
| 6 | Verify Phase 3 | `select count(*), pg_get_userbyid(c.relowner), ... from pg_class c ... where c.relname like 'decrypted%' group by 2,3;` | `1 \| pfin_owner \| true` | BY-HAND | one-time measurement |

§7 container bring-up must not proceed until both Phase 2 and Phase 3 pass. Do not hand-patch a failed census with `ALTER … OWNER TO` — stop and route to Sec.

### 6.4 CI trigger provisioning 🔒 — `ci-migrate` + GitHub Actions

Makes §6's steady-state path (push → SSH → Scheduled Task → app deploy) live.

| # | What | Command | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 | Generate the `ci_only` keypair | `ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519_ci_migrate` | keypair created, never committed | BY-HAND | interactive-credential moment |
| 2 | Set `.env`: `CI_MIGRATE_SSH_PUBKEY`, `MIGRATOR_SERVICE_UUID`, `MIGRATOR_TASK_UUID`, `APP_UUID`, `DEPLOY_ON_SUCCESS=0` | edit `.env` per [`scripts/provision.env.example`](../scripts/provision.env.example) | values present | BY-HAND | interactive-credential moment |
| 3 | Materialize `ci-migrate` user, forced command, orchestration script, scoped Coolify token | `scripts/provision-vps.sh --apply` | idempotent apply completes | SCRIPTED | |
| 4 | Add `CI_MIGRATE_SSH_PRIVATE_KEY` GitHub Actions secret | repo Settings → Secrets and variables → Actions | secret saved | BY-HAND | interactive-credential moment |
| 5 | Add `PROD_SSH_HOST` GitHub Actions repository *variable* | repo Settings → Secrets and variables → Actions → Variables | variable saved | BY-HAND | interactive-credential moment |
| 6 | Create `production-migrator` GitHub Environment, F/CTO as required reviewer | repo Settings → Environments | environment gated | BY-HAND | interactive-credential moment — F/CTO !-step |
| 7 | Verify: push a no-op change touching `supabase/migrations/**` | GitHub Actions | `migrator-trigger.yml`'s SSH step succeeds | BY-HAND | one-time measurement |

### 6.5 Migrator bring-up — operator execution order

Consolidation index only; every command is owned by the section it cites (§6.3/§6.4). Phase order: A (Coolify resources) → B (supervised bootstrap, §6.3) → C (CI trigger, §6.4) → D (integration test).

| # | What | Command | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 | Phase A: create V1 web-app + migrator Scheduled Task resources | see §3 row 5 / `scripts/migrator-scheduled-task.sh --apply` | UUIDs recorded | SCRIPTED | |
| 2 | Phase B: run §6.3 in full | see §6.3 | Phase 3 passes | BY-HAND | interactive-credential moment |
| 3 | Phase C: run §6.4 in full | see §6.4 | trigger verified live | SCRIPTED (mostly) | — |
| 4 | Phase D: merge a migration, watch the trigger fire end-to-end | GitHub Actions | `"migration apply SUCCEEDED — app deploy SUPPRESSED"`, exit 0 | BY-HAND | one-time measurement |
| 5 | Positive/negative transport control | see §6.7 `fail-probe` recipe | hops (d)/(e) both confirmed | BY-HAND | one-time measurement |

### 6.6 Re-bootstrap execution plan — box-specific wipe-and-redo

Only for a box that already has a partial/stale bootstrap. **STOP and route to Sec if any gate below is non-zero.**

| # | What | Command | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 | Gate: zero non-seed `pfin` rows, zero `auth.users`, zero `postgres`-owned objects outside `pfin` | see archive §6.6 for the 4-query block | all zero | BY-HAND | one-time measurement |
| 2 | Gate: migrator image freshness + post-sweep | `docker compose ... exec -T migrator cat /workspace/.build-sha`; `grep -c 'set role pfin_owner' /workspace/supabase/migrations/001_pfin_foundation.sql` | sha matches target; grep non-zero | BY-HAND | one-time measurement |
| 3 | Wipe | `drop schema pfin cascade; drop schema supabase_migrations cascade;` as `supabase_admin` | schemas dropped | BY-HAND | interactive-credential moment |
| 4 | Redeploy migrator resource before re-applying | `scripts/provision-migrator-app.sh --apply` | fresh build confirmed (re-run gate 2) | SCRIPTED | |
| 5 | Re-run §6.3 Phases 1–3 | see §6.3 | Phase 3 passes | BY-HAND | interactive-credential moment |
| 6 | Phase D suppressed fire | see §6.5 row 4 | exit 0, deploy suppressed | BY-HAND | one-time measurement |
| 7 | Post-apply ownership assertion | see §6.3 row 4/6 queries | `pfin_owner` everywhere | BY-HAND | one-time measurement |
| 8 | Re-materialize the box before any real Phase D fire | `BOX_IP=<box-ip> scripts/provision-vps.sh --apply` | idempotent re-materialization, no `sshd -t` rejection | SCRIPTED | |

### 6.7 `fail-probe` positive-control recipe — hops (d)/(e)

Exercises the real SSH → forced-command → GitHub Actions path with a deliberately-failing Scheduled Task (UUID `hffv8um6zruwslmndqc5su2l`, permanent, keep it). Config-only — never touches the credential file.

| # | What | Command | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 | Read + save current `MIGRATOR_TASK_UUID` | `ssh <admin>@<box-ip> "sudo cat /etc/pfin/migrator-trigger.conf" > /tmp/migrator-trigger.conf.orig` | value noted | BY-HAND | one-time measurement |
| 2 | Swap to `fail-probe`'s UUID | `ssh <admin>@<box-ip> "sudo sed -i 's/^MIGRATOR_TASK_UUID=.*/MIGRATOR_TASK_UUID=hffv8um6zruwslmndqc5su2l/' /etc/pfin/migrator-trigger.conf"` | line confirms swap | BY-HAND | one-time measurement |
| 3 | Fire via the real forced-command path | `ssh -i <ci_only key> -o BatchMode=yes ci-migrate@<box-ip> true; echo "exit code: $?"` | non-zero exit recorded | BY-HAND | one-time measurement |
| 4 | Assert the GitHub Actions STEP goes red | Actions tab → `Run workflow` on `migrator-trigger.yml` | "SSH to ci-migrate" step shows failed (red X) | BY-HAND | one-time measurement |
| 5 | Record pass/fail | `docs/records/v1final/standup-log.md` or the tracking Linear issue | logged | BY-HAND | one-time measurement |
| 6 | Restore original conf, by name | `sudo sed -i 's/^MIGRATOR_TASK_UUID=.*/MIGRATOR_TASK_UUID=<original>/' ...; grep -c '^MIGRATOR_TASK_UUID=<original>$' ...` | prints `1` | BY-HAND | one-time measurement |
| 7 | Confirm the credential file was never touched | `ls -l` mtime before/after | unchanged | BY-HAND | one-time measurement |

Sha-mismatch strike (exercises exit 18): `gh workflow run migrator-trigger.yml --ref <commit after eea2fdab, before the image's current build sha>`, approve at the `production-migrator` gate. Expect the job RED at exit 18 before any `db push` runs.

### 6.8 Migrator standalone-resource CUTOVER PROCEDURE — [ADR-072](../DECISIONS.md#adr-072) Amendment 4

Who: F/CTO, on the box, supervised. When: after §6.3/§6.5 Phase C completes against the current topology.

| # | What | Command | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 | Land the PR (no live change) | GitHub merge | merged to `main` | BY-HAND | — merge action, not a probe |
| 2–3 | Measure network mechanism viability + create migrator resource, fresh credential | `BOX_IP=<box-ip> scripts/provision-migrator-app.sh --apply` | env carries `MIGRATOR_DB_*`/`PROD_DB_URL`/`PGSSLMODE`, none of the stack's secrets | SCRIPTED | judgment call on which of two measured branches Coolify's own deploy output landed in |
| 4 | Re-create Scheduled Task under the new application, record UUIDs | `scripts/migrator-scheduled-task.sh --apply` then `scripts/record-coolify-uuids.sh --apply` | task fields read back byte-exact | SCRIPTED | |
| 5 | Supervised credential handoff — set the new resource's credential as the role's real password | `scripts/db-shell.sh --as supabase_admin`, paste at `\password migrator` prompt (value from `ssh root@<box-ip> "grep -m1 '^MIGRATOR_DB_PASSWORD=' /root/.pfin/migrator-app.env"`) | handoff complete | BY-HAND | interactive-credential moment — OPERATOR-ONLY, an agent must never run the grep hop |
| 6 | Prove the apply verb from inside the new container, before touching the stack's store | `docker compose --project-name <uuid> exec -T migrator sh -c 'supabase migration list --db-url "$PROD_DB_URL"'` | clean list, no `SQLSTATE` error | SCRIPTED | read-only probe, fixed command |
| 7 | Delete `MIGRATOR_DB_*` from the stack's store, redeploy | `BOX_IP=<box-ip> scripts/coolify-env.sh delete pfin-supabase-stack MIGRATOR_DB_USER MIGRATOR_DB_PASSWORD --apply --deploy` | names confirmed ABSENT before redeploy | SCRIPTED | |
| 8 | Measure delete-vs-blank rendering, record the count | `ssh root@<box-ip> "grep -c '^MIGRATOR_DB_' /data/coolify/applications/<uuid>/.env"` | `0` | BY-HAND | one-time measurement |
| 9–11 | Proof: confinement, stack-side absence, old credential fails | `BOX_IP=<box-ip> scripts/migrator-cutover-verify.sh --migrator-app pfin-migrator --stack-app pfin-supabase-stack` | PASS on all three legs | SCRIPTED | |
| 12 | Re-materialize the box with the new UUIDs | `scripts/provision-vps.sh --apply` | idempotent, no `sshd -t` rejection | SCRIPTED | |
| 13 | Next real trigger fire re-exercises the sha/delivery assertions against the new resource | a migration merge, or §6.7 | same shape as any clean fire | BY-HAND | one-time measurement |

This cutover does not touch `supabase_migrations` ownership (unchanged: the `migrator` role) or BACKLOG §7.36 item 28 (stack-wide `env_file:` exposure — remains open).

### 6.9 `pfin` Data-API exposure flip PROCEDURE — BACKLOG §7.36 item 22

F/CTO-ruled 2026-09-19, Sec joint-review. Flips `PGRST_DB_SCHEMAS` from `public,graphql_public` to the ratified `public,graphql_public,pfin` ([ADR-023](../DECISIONS.md#adr-023)).

| # | What | Command | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 (B-1) | VETO — `anon` zero-grant fence against PRODUCTION | `select has_schema_privilege('anon','pfin','USAGE');` + the per-relation enumeration (archive §6.9) | both clean — STOP and do not proceed if not | BY-HAND | one-time measurement |
| 2 (B-2) | Applied migration count matches ruling baseline | `select count(*) from supabase_migrations.schema_migrations;` | `120` (re-count if `main` advanced) | BY-HAND | one-time measurement |
| 3 (B-3) | `025` present | `select version from supabase_migrations.schema_migrations where version like '025%';` | exactly one row | BY-HAND | one-time measurement |
| 4–5 | Flip the store value, redeploy, run the live fence | `BOX_IP=<box-ip> scripts/coolify-env.sh set pfin-supabase-stack PGRST_DB_SCHEMAS=public,graphql_public,pfin --apply --deploy --post-check '...'` (full post-check string in script header) | exit 0 | SCRIPTED | |
| 6 | PGRST106-goes-away smoke | `scripts/smoke-pfin-exposure.sh pfin-app --compose-service app --jwt <user-jwt>` | `200` with a JSON array, never `PGRST106`/`3F000` | SCRIPTED | operator still supplies the JWT (0600 seed over SSH stdin) |
| 7 (B-4) | Re-affirm the item-26 `sslmode=disable` ruling, dated | `docs/records/v1final/standup-log.md` | sentence recorded | BY-HAND | — human authorship action |

Does not touch `secrets-manifest.yml` or any RT/SD-matrix entry (Sec confirmed).

---

## 7. Workers

> **§7 has not yet been converted to this scripts-driven shape** — a concurrent PR (W-3) owns that conversion; leaving this section's prose byte-identical to `main` until it merges.

Scope: deploy the background-worker containers. Per ARCH Lock 13, the V1 runtime is a **hybrid 3-container topology** on Coolify: (1) V1 web-app, (2) `pfin_back_etl` ETL, (3) Node PDF worker — plus the Phase-6/V1.5 cron + scheduled-poll additions.

- **`pfin_back_etl` (ETL)** — `workers/etl/`, Coolify **Base Directory** `workers/etl/`; Dockerfile [`workers/etl/Dockerfile`](../workers/etl/Dockerfile) (DevOps-owned). Python ETL (BLS CPI + FMP financials → Supabase). **Direct-Postgres** transport (`PFIN_DB_*`, login role **`pfin_etl`** — its OWN dedicated identity, *not* provider-sync's `authenticator`; writes AS `service_role` via `SET ROLE`) via **TenantBoundConnection** (Lock 13 mod #3). **`PFIN_DB_USER=pfin_etl`** (non-secret username) + `PFIN_DB_PASSWORD` (the `pfin_etl` credential, `production_only`). **This container cannot start successfully until §6's role-provisioning step has run** — see the ordering dependency there. **Forward discipline:** all `pfin` DB access binds `users_id` via TenantBoundConnection — TBC + `fence-tbc` coverage land Wave 6; incumbent currently uses SQLAlchemy `create_engine`.
  - **`PFIN_DB_SSLMODE=disable`** — non-secret, set explicitly in production (§5; Sec ruling, §7.36 item 26). The code default (`utils.py`, S11) is `require`, unchanged — this is the override, not a code change. Rationale in one sentence: plaintext is acceptable only because `db` is `expose:`-only per RT-32.
- **Node PDF worker** — `workers/pdf-render/`, Dockerfile [`workers/pdf-render/Dockerfile`](../workers/pdf-render/Dockerfile) (a real Puppeteer + system-Chromium render pipeline, **not** a placeholder — landed at SELF-348 A4, superseding the Phase-5 placeholder this line previously described). **Zero DB reach by design** (Lock 13 mod #2) — NO database libraries, credentials, or network reach. **Direction corrected in place:** this line previously said the worker "reaches data only via the web-app's `/internal/pdf-render` endpoint" — backwards. Per the R2 (C) ruling (`api/CLAUDE.md`; `workers/pdf-render/Dockerfile` + `docker-compose.yaml` headers), **`/internal/pdf-render` is RETIRED and does not exist as an app route.** The **web-app** composes and renders HTML server-side, then **PUSHES** the finished HTML to **this worker's own `/render` endpoint** under a short-lived, app-minted signed JWT (SD-20); the worker verifies the JWT and returns PDF bytes, never reaching the data layer itself. The worker's `/render` is the RT-27 internal-only admission surface (reachable only from `app` over the Coolify project network, `http://pdf-render:8080` — see §7.1 below); the app is the caller, never the reverse. RT-22 fence enforces the Dockerfile credential/Postgres-client absence.
  - **`PDF_WORKER_SIGNING_KEY` length precondition (A5 follow-up (3)) — verify BEFORE the worker's first deploy.** The web-app fails closed when `PDF_WORKER_SIGNING_KEY` is under 32 characters; the PDF worker itself enforces no minimum-length floor. That asymmetry means a short value is caught on the web-app side only — if the web-app container happens to start first, or if the two containers are ever given different values, the PDF worker can come up and accept requests under a key too weak for the web-app's own check to have allowed. Before the worker's first deploy: confirm the Coolify-injected `PDF_WORKER_SIGNING_KEY` value is **at least 32 characters**, and confirm it is the **SAME value on both the web-app and PDF worker containers** (per SD-20 — this is the shared-secret pair the signed-JWT handshake depends on).
- **`provider-sync` (Plaid/SimpleFIN ingest)** — `workers/provider-sync/`, Coolify **Base Directory** `workers/provider-sync/`; Dockerfile [`workers/provider-sync/Dockerfile`](../workers/provider-sync/Dockerfile) (DevOps-owned). The 4th Coolify unit (ADR-019 amendment) — the FIRST DB-touching **Node** worker. **Direct-Postgres** transport (`PFIN_DB_*`, login role `authenticator`, writes AS `service_role` via `SET LOCAL ROLE` per ADR-023) via **TenantBoundClient** (Lock 13 mod #3; `fence-tbc-node` enforces at PR-time). **OFF the RT-26 allowlist by design** — no `SUPABASE_SERVICE_ROLE_KEY`, no `@supabase/supabase-js`. Env contract: [`workers/provider-sync/.env.example`](../workers/provider-sync/.env.example).
  - **`PFIN_DB_SSLMODE=disable`** — set per Sec's ruling (§5; §7.36 item 26), same rationale as `pfin_back_etl`. **⚠ Measured to be currently INERT for this worker, flagged rather than silently set:** `TenantBoundClient.ts`'s `#connect()` (`workers/provider-sync/src/db/TenantBoundClient.ts:89-100`) builds its `postgres.js` connection from `host`/`port`/`database`/`username`/`password` only — no `ssl` option, and no code anywhere in this worker reads `PFIN_DB_SSLMODE` (`grep -rn "SSLMODE" workers/provider-sync/` → zero hits, confirmed against both `src/` and `.env.example`). **`postgres.js`'s own documented default, cited not assumed:** the package is pinned `^3.4.5` (`workers/provider-sync/package.json:19`); reading `src/index.js` at tag `v3.4.5`, the library's own `defaults` object sets `ssl: false` (line 449) when no `ssl` option is passed. So this worker does not merely happen to connect in plaintext today — `postgres.js` **explicitly defaults off**, a stronger and more deliberate property than libpq's `prefer` (which the earlier draft of this line incorrectly implied by omission — corrected here). Setting `PFIN_DB_SSLMODE` is harmless (an unused Coolify var) and keeps the two workers' env parity, but **it does not currently do anything** — unlike `pfin_back_etl`, there is no S11-shaped override mechanism here to point it at. Not fixed in this PR (out of scope; no code touched).
- **`provider-sync` SELF-212 admission endpoint (Option C, internal-only) — deploy config:**
  - **Build pack = Compose (b-i).** Coolify consumes the committed [`workers/provider-sync/docker-compose.yaml`](../workers/provider-sync/docker-compose.yaml) (not the bare Dockerfile build pack). This is what makes the admission endpoint's exposure surface **committed + lintable** (the `fence-admission-bind` CI job / RT-27 network-exposure layer). The admission port (`8081`) is `expose:`-only — **NEVER add a published `ports:` mapping and NEVER assign a Coolify Domain / Traefik `Host()` label to this service.**
  - **CA-4 — SAME DOCKER NETWORK ATTACHMENT (hard prerequisite), RESTATED CORRECTLY (ADR-073):** the api/ web-app service and the provider-sync service **MUST** be attached to the same Docker network — declared in each compose's own top-level `networks:` block (`external:`, naming the shared network) — so internal DNS `http://provider-sync:8081` resolves. **Coolify project membership grants no attachment at all** (§3); an unattached placement, same-project or not, breaks internal reach **and** tempts a public-Domain "fix" — the exact silent-exposure regression RT-27 / §10 fences. Verified at §10 smoke.
  - **CA-1 — deploy-time public-route env verification:** at first deploy (and after any Coolify upgrade), dump the admission container's actual env and confirm the worker's limb-(a) prefix regex (`^(COOLIFY_FQDN|COOLIFY_URL|ADMISSION_PUBLIC_URL)$` or `^SERVICE_(FQDN|URL)_`) would match Coolify's real injected FQDN/URL var names for that version — because those names are Coolify-version-dependent, and a rename must not silently slip a Domain past the tripwire.
- **Cron containers (Phase 6 / V1.5):** the `monthly_report` worker (V1.5), the Plaid scheduled-poll worker (Wave 6), and the **`provider-sync` daily poll** (ADR-027 slice-3b) run as **native Coolify cron** (Wave 6 Gate F Option α, F/CTO-ratified), not an in-app scheduler.

- **V1 worker cron convention (Pattern A — resident container + Coolify Scheduled Task):** scheduled worker runs use Coolify's native cron primitive, which is a **Scheduled Task** (`docker exec` of a command into a **resident** service on a cron). The container's `CMD` is a resident keepalive (`tail -f /dev/null`, per [`workers/etl/Dockerfile`](../workers/etl/Dockerfile)); the scheduled work is a separate Coolify UI-configured command. **Not** a one-shot container: Coolify has no one-shot-cron primitive, and an exited Application container restart-loops under Coolify's restart policy. This is a DevOps-owned in-repo convention (distinct from the cax21 Coolify config, which is reference-only per ADR-021).
  - **`provider-sync` daily poll** — Scheduled Task, cron **`@daily`** (cadence lean per DevOps; SimpleFIN flat-fee + Plaid bills per-Item/month so cadence ≈ cost-neutral; F/CTO may adjust at deploy — reversible dashboard config), command **`node dist/cli/poll.js`** (design memo §1). Fleet-fatal (can't enumerate / DB unreachable) → **exit 1** → Scheduled-Task failure routes **Coolify→Discord** (§8); a completed run **exits 0 even with per-source failures** — each is isolated, captured in a `scheduled_poll` `linked_source_sync_audit` row + emitted as a structured `FAILED source_id=…` log line (Coolify-log-routable, never a page). A gappy/revoked institution never exits non-zero.
    - **Poll env (required subset — confirmed against `loadConfig()`):** `PFIN_DB_*` (login role `authenticator`) **+ `PLAID_CLIENT_ID` / `PLAID_SECRET` / `PLAID_ENV`**. Plaid creds are **required at boot** — `loadConfig()` throws on absence *even for a SimpleFIN-only source set* (Plaid is a live V1 provider, so this is fine for V1; making Plaid optional is a small `env.ts` change if a Plaid-less container is ever wanted). **NOT** `SIMPLEFIN_TOKEN` (the poll reads each source's stored Access URL from `decrypted_source_credential`; the bridge token is only the `admit` entrypoint's concern), **NOT** `DISCORD_WEBHOOK_URL` — it is `z.string().optional()` in `loadConfig()`, so the poll boots without it. ⚠ **Not because "Discord is Coolify-side"** — an earlier revision of this line said that, and it is false: `workers/provider-sync/src/notify/discord.ts` POSTs to the webhook URL **directly** from the worker (its first direct outbound POST that is not to a provider), and `secrets-manifest.yml` names **three** consumers — V1 web-app / Coolify control plane / provider-sync worker. The correct reading: the Coolify→Discord routing in §8 covers the **Scheduled-Task exit-1 fleet-fatal path** without the worker holding anything, so the poll does not *require* the URL; supply it only to enable the worker's own direct dispatch, **NEVER** `SUPABASE_SERVICE_ROLE_KEY` (off-RT-26 posture; `fence-tbc-node` LEG 2 zero-hit). All are `production_only` secrets (§5) — non-overlap fence unaffected.

- **TimeZone drift sweep (R3) — Scheduled Task · ⏸ RATIFIED, NOT YET ACTIVE · DevOps-owned.**
  **This is a decided thing awaiting a box, not an open question.** F/CTO-ratified 2026-08-06; **build deferred to Phase 7** for one reason only — a Scheduled Task needs a Coolify instance to attach to, and V1's is not stood up yet (§1). **Wire it at first deploy.** It is recorded here rather than in a note because a runbook step gets *executed*; a note gets *recalled*.
  - **What it runs:** the §4.1 catalog sweep (limb 2) on a cron, exiting non-zero when any role carries a `TimeZone` override, so the failure routes **Coolify→Discord** (§8) on the incumbent notification path. Cadence `@daily` to start; it is a dial, see the latency note below.
  - **⚠ It is DETECTION WITH BOUNDED LATENCY, NEVER PREVENTION.** Nothing stops a privileged human running `ALTER ROLE … SET timezone` on production. At `@daily` that is **up to 24h of silently-wrong as-of dates** (§4.1: the NAV headline and open-account count are wrong, and nothing errors). Tightening the cron tightens the window; it never closes it. **Do not describe this as a gate** — overclaiming here is the same failure §4.1 documents, one layer up.
  - **Why a recurring sweep and not a deploy-time check:** the vector is **drift-shaped, not deploy-shaped**. The override that motivated all of this arrived on a stack nobody was deploying, and a deploy-time gate samples only at deploys — it would not have caught the real instance. *(Measured 2026-08-04: `authenticator` carrying `TimeZone=Asia/Tokyo` while a `postgres`-session read-back showed a clean `UTC | database`.)*
  - **Needs NO new credential.** Capability-verified: `pg_db_role_setting` is readable by an unprivileged login role (`authenticator` sees every row), so the sweep runs over a connection the deployment already has. **The script is repo-versionable and testable against a local stack today** — none of it is gated on cutover.
  - **⚠ TWO INSTRUMENTS AT TWO PRIVILEGE LEVELS — do not merge them.** The *provenance* limb (`select 1 from supabase_migrations.schema_migrations where version = '061'`, which distinguishes our declaration from a hand-run `alter database … set timezone` — see §10 TZ-1b for what it does and does not prove) requires the migration-applying identity: **`authenticator` gets `permission denied for schema supabase_migrations`** (measured). So that limb belongs to **deploy time (§6/§10)**, and the recurring sweep stays unprivileged. Least privilege for the thing that runs forever on a timer.
  - **⚠ WHY THIS IS NOT A CI JOB — do not re-propose one.** Two independent blockers, either sufficient alone. **(a)** `PFIN_DB_PASSWORD` is `production_only` in [`secrets-manifest.yml`](../secrets-manifest.yml); putting it in the CI store is exactly what the non-overlap discipline prevents — and worse, **the fence would stay green while the discipline was broken**, because `check-secrets-nonoverlap.py` validates the *manifest declaration*, not GitHub's secret store. **(b)** GitHub runners have no fixed egress, so reaching production Postgres means publishing `5432` or allowlisting GitHub's entire IP space — while §10 CA-2 spends real effort proving the admission endpoint is *not* externally reachable.
  - **Options considered, so nobody re-opens a closed one:** **γ (this)** chosen — the only shape that catches post-deploy drift. **β** (container healthcheck) **HELD, not rejected**: it fails closed to an *outage* on a live single-user app, buying detection γ already provides — easy to add later if γ's latency proves too loose. **δ** (leave it a human step) rejected: it is the posture that failed. **α** below.
  - **⚠ α's PREMISE IS STILL UNVERIFIED, AND TESTING IT IS *NOT* GATED ON CUTOVER.** α was a Coolify **post-deploy command**; it rests on whether a **non-zero exit from one actually FAILS the deployment** rather than merely logging. That is a question about **Coolify's behaviour, not about V1's box** — the F/CTO already runs Coolify on cax21 with Discord notifications working, so it is answerable today. **If it merely logs, α is worth ~nothing.** Everything else in this bullet waits for Phase 7; this one does not, and it is the item most likely to be wrongly assumed blocked because everything around it is.

### 7.1 Per-container Coolify deploy config

**De-stubbed 2026-09-13.** ⚠ **This is the deploy RECIPE, not a "deploy now" instruction** — Phase 6 is still building toward V1.final; every block below is executable once the app is V1-ship-ready and §6 (migrations + role handoffs) has run, per §6.5's Phase A step 1 (which points back here for the Coolify-resource-creation detail it was missing). **State correction carried in from the prior STUB:** that marker said the web-app config waits "until the SvelteKit scaffold lands" — stale. Verified on `main` at authoring time: `api/` carries a `Dockerfile` + `package.json` + `vite.config.ts` and 126 route files under `src/routes/`; all three workers carry a `Dockerfile` **and** a committed `docker-compose.yaml`. The four blocks below are grounded in those real artifacts, §3's already-ratified topology table, §5's secret-injection mechanics, and §6's role-provisioning ordering — not invented.

**⚠ Build-pack correction against this section's own originating brief.** §3's topology table documents **all four fleet services as Coolify build pack = Compose**, not Dockerfile: `pdf-render` moved off the plain-Dockerfile pack at SELF-348 A4 item 4c / Sec N-4 (superseding what it shipped with at Phase 5), `etl` has carried two Compose-defined Coolify units (nightly-ingest + monthly-report) since its own docker-compose header was authored, and `app` itself moves off the plain Dockerfile+Base-Directory pack **in this PR** (ADR-073, 2026-09-19) — retiring what had been the **one** fleet service still on it. The blocks below follow §3's table and the compose files actually on disk, not a Dockerfile-build-pack assumption for any of the four — flagged in the hand-off below as a correction, not silently reconciled.

---

**1. `app` — V1 web-app**

⚠ **Build pack corrected 2026-09-19 (F/CTO topology ruling, Open Flags #12, option A).** Superseded a prior draft of this table that stated a plain-Dockerfile build pack — MEASURED (team-lead, same date) that `pfin-app` and `pfin-supabase-stack` sit in DIFFERENT Coolify projects/environments with `connect_to_docker_network` FALSE on both, so a plain-Dockerfile `pfin-app` never had a working path to `api-gw:8000`. `app` now recreates as a `dockercompose` resource with an `external:` network attachment to the stack — the migrator's own proven shape (ADR-072 Amendment 4). **§3's own topology table text has been corrected in this same PR (Architect, ADR-073): the "one Coolify project, connect_to_docker_network" premise is replaced with the DECLARED-NETWORK-ATTACHMENT model, not project membership.**

| Field | Value | Grounding |
|---|---|---|
| Base Directory | `/api` | [`scripts/provision-app.sh`](../scripts/provision-app.sh) `BASE_DIRECTORY` |
| Build pack | **Compose** — [`api/docker-compose.yaml`](../api/docker-compose.yaml) (new, this ruling) | F/CTO ruling 2026-09-19; `scripts/provision-app.sh` creates it as `dockercompose`, `docker_compose_location=/docker-compose.yaml` |
| Container port | `3000` (`EXPOSE 3000`, `CMD ["node","build"]` — adapter-node default), `expose:`-only in the compose file, never published | `api/Dockerfile` lines 35–36; `api/docker-compose.yaml`'s own `expose:` block |
| Domain | `pfindash.com` (+ `www.pfindash.com` alias) — the **only** intended public-Domain resource in the project | §2 "Subdomain split: app only" |
| Domain assignment status | **Blocked on §2's DNS cutover** — not yet assignable. ⚠ **UNMEASURED whether the Dockerfile-pack→compose recreation keeps the SAME Coolify-assigned sslip.io placeholder fqdn or mints a new one** — a resource recreation (delete + create, `scripts/provision-app.sh`) is not guaranteed to preserve a prior auto-assigned fqdn even though the resource NAME is unchanged; not independently verified against the live box (DevOps does not touch it). Step (v)'s `--health-path` reports the live fqdn read at execution time — a changed fqdn is new information, not evidence the procedure is wrong. | — |
| Networking | **Is created** in the **same Coolify project/environment** as `pfin-supabase-stack` **by convention** ([`scripts/provision-app.sh`](../scripts/provision-app.sh) resolves the environment from the stack's own live resource rather than hard-coding it) — but **the reach does not come from that placement.** Per [ADR-073](../DECISIONS.md#adr-073): *"Inter-service reach is a property of declared network attachment, never of project membership"*, and *"Coolify project/environment membership becomes an organizational convenience with no security or connectivity meaning."* The reach comes from the `external:` Docker-network attachment to the stack's own network (`scripts/provision-app.sh` resolves and sets `APP_STACK_NETWORK_NAME`) — **not** the `connect_to_docker_network` toggle (option B, rejected: widens `api-gw`'s reachable-from set to every other resource on that predefined network, same reasoning ADR-072 Amendment 4 applied to the migrator). `app`'s original `provider-sync` CA-4 dependency (the SELF-212 admission handshake, `http://provider-sync:8081`) is **unaffected** by this change and still applies once `provider-sync` exists. ⚠ **UNMEASURED UNTIL THE FIRST DEPLOY (a):** whether Coolify 4.3.18 renders the `external:` network block the same way for a ONE-SERVICE compose as it did for the migrator's own (also one-service, but a separately-created resource) — the migrator's equivalent was measured working (§6.8 step 2), which is evidence about that deploy, not a guarantee for `app`'s own. **The measurement is step (v)'s `--resolve-host api-gw` probe** (`deploy-app.sh`'s `docker exec ... getent hosts api-gw`, run post-deploy against the real container) — record what it shows here once run, not assumed from the migrator's precedent alone. | `api/docker-compose.yaml`; `scripts/provision-app.sh` |
| Health check | No `/healthz`-shaped route exists under `api/src/routes/` (checked: none found). Until Backend adds one, configure Coolify's HTTP health check against `/` (root) — SvelteKit adapter-node answers 200 there once the app boots. **Flagged to Backend**, not invented here. ⚠ **UNMEASURED UNTIL THE FIRST DEPLOY (b):** whether Coolify's Traefik routes a request to a `dockercompose`-pack service correctly on `expose:` alone, or needs an explicit port label/setting this compose file does not carry — this is exactly the mechanism a public Domain (and the sslip.io placeholder) depends on. **The measurement is step (v)'s `--health-path /` probe** (curls the resource's live fqdn from the operator's machine) — record what it shows here once run: a `200` confirms `expose:`-alone routing works; a non-200/timeout is new information about what Traefik actually needs, not evidence this procedure is wrong. | `find api/src/routes -iname '*health*'` → empty |
| Resource limits | No repo-side precedent exists for any container's CPU/mem ceiling. See "Resource limits — genuinely open" below rather than a per-container number here. | — |

**Env-var wiring (→ §5; values never re-enumerated here):**

- **Non-secret compose env** (NOT in `secrets-manifest.yml` — §5's non-secret runtime-config carve-out): `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY` (mint-owned — see below), `PLAID_ENV`. Plus `APP_STACK_NETWORK_NAME` — new for this ruling: [`api/docker-compose.yaml`](../api/docker-compose.yaml)'s own `networks.default.name` interpolation, set by [`scripts/provision-app.sh`](../scripts/provision-app.sh) (unconditional overwrite, non-secret, environment-specific — same discipline as `MIGRATOR_STACK_NETWORK_NAME`). Not part of the `coolify-env.sh` `SET_ALLOWLIST` flow — `provision-app.sh` writes it directly as part of resource provisioning, not per-deploy env wiring.
- **Secrets** (`production_only`, injected by [`scripts/push-production-secrets.sh`](../scripts/push-production-secrets.sh)'s `SECRET_RESOURCE_MAP → app`): `SUPABASE_SERVICE_ROLE_KEY` (RT-26 §4.1 allowlist — `app` is the sole holder in the fleet), `PDF_WORKER_SIGNING_KEY` (SD-20 — **same value** as the PDF worker, ≥32 chars, verify before `pdf-render`'s first deploy per the existing PDF-worker bullet above), `WORKER_ADMISSION_SHARED_SECRET` (**same value** as `provider-sync` — §5's ratified deviation: pushed as an ordinary per-application env var to both, never a Coolify "shared variable"; rotation only via re-running the script, never a hand-edit to one side), `DISCORD_WEBHOOK_URL`.
- **Real JWT mint** — [`scripts/mint-supabase-jwt-keys.sh --apply --app-name <app-resource-name> --verify-live`](../scripts/mint-supabase-jwt-keys.sh) mints the stack's real `ANON_KEY`/`SERVICE_ROLE_KEY` (HS256, derived from the deployed `JWT_SECRET`) and, when `--app-name` resolves an existing `app` resource, propagates them onto `app` as `PUBLIC_SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` — the script's own step name is "overwriting the placeholders" (its line ~387), so it is built to run **after** any placeholder value is already in place, not before.
- ⚠ **Two writers of `SUPABASE_SERVICE_ROLE_KEY` on `app` — RULED (Sec joint-review, 2026-09-13).** `push-production-secrets.sh`'s `SECRET_RESOURCE_MAP` maps it `→ app` from the operator's local `.env`; `mint-supabase-jwt-keys.sh --apply --app-name` *also* overwrites it, unconditionally, with the real HS256 JWT derived from the deployed `JWT_SECRET`. **`mint-supabase-jwt-keys.sh` is authoritative** — the correct value is *derived* from the on-box `JWT_SECRET` and cannot be authoritatively sourced from a local `.env` (any value there is a placeholder or a hand-copied stale value). **Required ordering: run `push-production-secrets.sh` FIRST, `mint-supabase-jwt-keys.sh --apply --app-name` LAST** — because mint overwrites unconditionally, running it last guarantees the real key wins; the reverse order clobbers the real key with a `.env` value and the app comes up holding a wrong `service_role` key (fail-closed 403s on privileged ops, not an exposure — but a live-app break). **Durable fix (tracked separately, DevOps): drop `SUPABASE_SERVICE_ROLE_KEY` from `push-production-secrets.sh`'s `SECRET_RESOURCE_MAP`**, mirroring how that script already excludes the stack-side `SERVICE_ROLE_KEY`/`ANON_KEY` as mint-owned (`EXCLUDED_SUPABASE_STACK`) — the app-side name is the same mint-derived class and the exclusion was simply not extended to it. That removes the double-writer and the ordering hazard entirely.
- **Never hand-`coolify-env.sh set pfin-app PUBLIC_SUPABASE_ANON_KEY=...`** (Sec N1, PR #833 joint review) — it is in `SET_ALLOWLIST` for the manifest-refusal's own belt-and-braces reasons, not as an invitation to write it there; the mint step above is its sole authoritative writer.
- **A redeploy is required after any of these injections** — Coolify only applies env at container-recreate time (§5).

**First-deploy PROCEDURE — numbered, stranger-runnable (F/CTO gate, 2026-09-19: "this should be a procedure that can be run by a stranger with minimal by-hand intervention"; same gate that produced §6.9 and `scripts/coolify-env.sh`).** This is the procedure the bullets above ground — it does not restate their reasoning, it sequences them. Preconditions: `pfin-supabase-stack` already exists and is deployed (§4/§6); §6's migrations + role handoffs have run. `pfin-app` itself does NOT need to pre-exist in its final shape — step (i) recreates it.

**SCRIPTED / BY-HAND audit.**

| Step | Status | Detail |
|---|---|---|
| (i) | SCRIPTED | `provision-app.sh --apply` — deletes the stale plain-Dockerfile `pfin-app` (asserting zero on-box containers + zero on-box images + zero env-store names for its uuid first, refusing otherwise — **MEASURED (team-lead, 2026-09-20): `GET /applications/<uuid>/deployments` is 404 on this Coolify (4.3.18); `GET /deployments?uuid=<uuid>` returns 200 `[]` even for an app with 4 completed deployments the same day, since that route lists only in-flight/queued deployments — neither is usable as history evidence, hence the on-box `docker ps -a`/`docker images` reads**; a FAILED on-box read — daemon down, permission error — also refuses, reported as `unknown` and treated as non-zero, never silently treated as empty), creates it fresh as `dockercompose` in the stack's own project/environment, and sets `APP_STACK_NETWORK_NAME`. **MEASURED (team-lead, 2026-09-20, first live --apply): the create leg 422'd — `POST /applications/public` requires `project_uuid`, which the original create body omitted; fixed (both project/environment resolution paths now resolve a real `project_uuid`, sent alongside `environment_uuid`).** A failed create leaves NO `pfin-app` resource behind (the delete leg had already succeeded and removed the stale shell before the create call failed) — the script is safely re-runnable from that exact state: re-running finds `pfin-app` absent, skips the delete leg entirely, and goes straight to create. **MEASURED (team-lead, 2026-09-20, second live --apply, after create succeeded): the "Setting APP_STACK_NETWORK_NAME" leg 400'd under macOS bash 3.2 (an argument-position brace-expansion defect, fixed) — see this section's own prose below for the full mechanism and for the SEPARATE compose-parse pre-population finding (Coolify pre-fills the env store with 7 placeholder rows on create; `deploy-app.sh --require-env` fixed, on a separate branch/PR, to detect placeholder values, not just key presence — not yet due, since step 6 runs after steps 2–5 overwrite the placeholders).** Does NOT deploy. |
| (ii) | SCRIPTED | `push-production-secrets.sh` preflight, then `--apply --skip-missing-resource` — **read the preflight's `MISSING from local .env` line before `--apply`** (Sec N2): the four names this step's own text names as "pushed" are conditional on all four being present in the operator's local `.env`; the script skips (prints, does not fail) any that are absent. **MEASURED (team-lead, 2026-09-20): `GET /applications?name=X` ignores the `name` filter entirely on this Coolify — every resource silently resolved to the same wrong uuid; fixed (single unfiltered fetch, exact-name match locally, real Coolify names as defaults) — see step 2's own prose below for the full incident.** |
| (iii) | SCRIPTED | `coolify-env.sh set pfin-app PUBLIC_SUPABASE_URL=http://api-gw:8000 --apply` — a fixed literal, no read needed (the network PRECONDITION is now structural — step (i)'s `external:` attachment — not a pre-deploy declared-settings check). |
| (iv) | SCRIPTED | `mint-supabase-jwt-keys.sh --apply --app-name pfin-app --verify-live` — mints and propagates the real `PUBLIC_SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` onto `pfin-app`, LAST. |
| (v) | SCRIPTED | `deploy-app.sh pfin-app --expect-base-directory /api --expect-build-pack dockercompose --compose-service app --require-env PUBLIC_SUPABASE_URL,PUBLIC_SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY --require-network <value from step (i)'s own output> --resolve-host api-gw --apply --health-path /` — identity guard (name + base_directory + build_pack), names-only env presence, deploy+poll, on-box running-container read via the compose-ps mechanism (refuses on >1 match — Sec F4, both container-resolution mechanisms independently struck), POST-DEPLOY network-attachment check, POST-DEPLOY `getent hosts api-gw` resolve check, and the external health probe — all fold into this one command. Supersedes an earlier `--require-network-with` pre-deploy declared-settings guard, now irrelevant to this topology (Sec F3 fix, superseded again by this ruling). |
| (vi) | SCRIPTED | `smoke-pfin-exposure.sh pfin-app --compose-service app` — the pre-invite anon-bearer `pfin`-exposure smoke, runs unattended, exits non-zero on anything but the expected 401/42501 (exit 2 on a precondition the smoke itself can't attempt under, e.g. a connection failure). |
| (vii) | SCRIPTED (`.env` edit + `provision-vps.sh --apply`) then BY-HAND (the flag-flip authorship + the merge that re-exercises the trigger) | flip `DEPLOY_ON_SUCCESS` + re-exercise the trigger — §7 step 7 below. **MEASURED, stage B, 2026-09-20: the "SCRIPTED" half of this row is scripted in the sense of "a command exists," not "an agent session can run it unattended."** The Claude Code auto-mode classifier blocked team-lead's own invocation of both `provision-vps.sh --apply` and `gh workflow run` here, classifying each as a `[Production Deploy]`-class action requiring a human hand on the keyboard — F/CTO ran the identical commands from the operator Mac instead. The BY-HAND fallback for a blocked SCRIPTED step is always the same command, typed by a human, never a different procedure — this is a property of the invoking session, not of the script. |

1. **Recreate `pfin-app` as a `dockercompose` resource — deletes the stale shell, does not deploy.**
   ```sh
   BOX_IP=<box-ip> scripts/provision-app.sh          # preflight
   BOX_IP=<box-ip> scripts/provision-app.sh --apply
   ```
   [`scripts/provision-app.sh`](../scripts/provision-app.sh) (new, this ruling; sibling to `scripts/provision-migrator-app.sh`) resolves `pfin-supabase-stack`'s own live project/environment identity (never hard-coded — see the script's own header for the exact field-path mechanism and its stated provenance uncertainty), asserts the existing `pfin-app` resource is a genuinely empty shell before deleting it — **zero on-box containers ever created for its uuid (`docker ps -a`), zero on-box images ever built for it (`docker images`), and zero env-store names** — refusing otherwise, naming whichever predicate is non-zero (this script never destroys a resource that turns out to hold real state); **a FAILED on-box read (daemon down, permission error) also refuses** — reported as `unknown` and treated as non-zero, never silently treated as an empty/zero read. **MEASURED (team-lead, 2026-09-20):** this replaced an earlier `GET /applications/<uuid>/deployments`-count predicate after that route was found to 404 on this Coolify (4.3.18); the seemingly-plausible alternative `GET /deployments?uuid=<uuid>` was also ruled out — it returned 200 `[]` for `pfin-migrator` despite that resource having four completed deployments earlier the same day, because it lists only in-flight/queued deployments, not history. Creates it fresh as `dockercompose` (`base_directory=/api`, `docker_compose_location=/docker-compose.yaml`, branch `main`), and reads the stack's live Docker network to set `APP_STACK_NETWORK_NAME` on the new resource (unconditional overwrite, non-secret — same discipline as the migrator's `MIGRATOR_STACK_NETWORK_NAME`). **Record the printed `APP_STACK_NETWORK_NAME` value** — step 5 needs it as the literal argument to `--require-network`.
   **Idempotent**: re-running against an already-`dockercompose` `pfin-app` skips the delete and only re-asserts/re-sets the network var. **Idempotent from a failed-create state too**: re-running while `pfin-app` is absent (a prior `--apply` deleted the stale shell but never got as far as a successful create) finds no existing resource, skips the delete leg entirely, and goes straight to create — **MEASURED (team-lead, 2026-09-20)**: this is the exact state the first live `--apply` left the box in, after `POST /applications/public` 422'd on a missing required `project_uuid` field (fixed — the create body now sends `project_uuid` alongside `environment_uuid`, both resolved as real uuids regardless of which project/environment-resolution path fired).
   **Step 1 landed in TWO separate live runs, 2026-09-20 (team-lead).** Run 1 (`main` `0a935732`) fixed the `project_uuid` 422 above and got as far as a successful create; run 2 (`main` `27578ec7`, `pfin-app` = `7frkiyqnetb4bgev7j7sw5eg`, `build_pack=dockercompose`, `base_directory=/api`) hit two NEW findings — the bash-3.2 fix lands in this PR; the `deploy-app.sh --require-env` placeholder-value fix lands separately (a second branch/PR, since step 6 is not yet due — steps 2–5 overwrite the compose-parse placeholders described below before step 6 ever runs `deploy-app.sh`):
   - **MEASURED — bash 3.2 argument-position brace expansion.** The "Setting APP_STACK_NETWORK_NAME" leg built its PATCH body inline as an ARGUMENT to `api()` (`api PATCH "..." "$(python3 -c "...")"`); under macOS `/bin/bash` 3.2.57 (what `#!/usr/bin/env bash` resolves to on the operator's Mac, confirmed by `which bash`/`bash --version` — CI's `ubuntu-latest` runs bash 5, so no fence run before this ever exercised it) that shape mis-parses, splitting the python dict literal's braces at the comma and producing TWO `SyntaxError`s. The result was an EMPTY body argument, which `api()`'s own remote helper then treats as `body=None` — skipping `--data-binary` AND the `Content-Type` header entirely — and Coolify 4.3.18 responded `400 {"message":"Content-Type must be application/json"}`. Reproduced locally (isolated the exact three lines under `/bin/bash`: 2 `SyntaxError`s) and confirmed the SAME lines do NOT reproduce under bash 5.2.15 (Debian container, measured, not assumed). Fixed: the body is now built into a variable FIRST (same shape `CREATE_BODY` already used, which is why creation itself was never affected), then passed as a plain argument — the only call site in the script using the inline-argument shape (swept, confirmed no others). `scripts/ci/fence-provision-app-strikes.sh`'s fake-curl now also validates this leg's PATCH body structurally and 400s with Coolify's own measured error text on an empty/malformed one, strike-verified against the reverted code under bash 3.2.
   - **MEASURED — Coolify's own compose-parse pre-populates the env store on create.** Creating the `dockercompose` resource queued a compose parse of `api/docker-compose.yaml` that pre-populated `pfin-app`'s env store with all 7 names its `environment:` block declares, as TWO rows each (`is_preview=false` and `is_preview=true`, `is_build_time=null`): the three `${VAR:?message}`-guarded names (`PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`) carry the `:?` MESSAGE TEXT itself as their value (Coolify's compose parser does not distinguish "`:?` = required, error if unset" from a shell default) — lengths 76/84/85, matching each message string; `PLAID_ENV` carries its `:-sandbox` default; `PDF_WORKER_SIGNING_KEY` / `WORKER_ADMISSION_SHARED_SECRET` / `DISCORD_WEBHOOK_URL` (no default) are empty. Consequences checked: (1) `coolify-env.sh` and `deploy-app.sh` already filter `is_preview` on every read — confirmed, no change needed. (2) `push-production-secrets.sh` and `mint-supabase-jwt-keys.sh` never `GET .../envs` before writing at all (by design — both scripts' own stated purpose is unconditional overwrite: `push-production-secrets.sh`'s header calls this out explicitly, `mint-supabase-jwt-keys.sh`'s own step name is literally "overwriting the placeholders"), so "do they filter is_preview on read-back" does not apply structurally; **UNMEASURED**, and stated as such rather than guessed: whether Coolify's `PATCH .../envs/bulk` (body carries no `is_preview` field, matching every existing call site in this repo) correctly resolves to updating the pre-populated `is_preview=false` row in place, versus some other outcome — a live-box-only question steps 2–4's own re-run will answer; if step 5's `--require-env` (below) passes clean, the values landed correctly. (3) `deploy-app.sh --require-env` was a NAMES-only presence check — a `:?`-message placeholder value would have satisfied it. **Fixed separately** (not this PR — tracked on its own branch/PR since step 6 is not yet due): `--require-env` now also refuses a value that is empty or contains the substring `must be set`, distinguishing "key absent" from "key present but a compose-parse placeholder," fence-strike-verified. (4) The `is_preview=true` duplicate rows are **harmless to the production container, by Coolify's own documented mechanism, not deleted**: per [Coolify's GitHub-preview-deploy docs](https://coolify.io/docs/applications/ci-cd/github/preview-deploy) ("Production Environment Variables apply to the main deployment. Preview Deployment Environment Variables apply to pull-request and merge-request deployments."), `is_preview=true` rows are only ever injected into a PR/MR **preview** deployment — a Coolify feature this project does not use for `pfin-app` (single manually-triggered production deploy, no GitHub PR-preview wiring anywhere in this repo). They sit inert unless that feature is ever turned on for this resource.

2. **Push the production_only secrets already mappable to `pfin-app`.**
   ```sh
   BOX_IP=<box-ip> scripts/push-production-secrets.sh --skip-missing-resource                  # preflight
   BOX_IP=<box-ip> scripts/push-production-secrets.sh --apply --skip-missing-resource
   ```
   **MEASURED (team-lead, 2026-09-20, stage A preflight):** a live run printed `resolved 'app' -> <pfin-app's uuid>` and the SAME uuid for `'etl'`, `'pdf-render'`, and `'provider-sync'` — none of which exist. Two compounding causes, both fixed: (a) `GET /applications?name=X` on this Coolify (4.3.18) **ignores the `name` query parameter entirely** — `?name=etl`, `?name=app`, `?name=pfin-app`, and `?name=does-not-exist` all returned the SAME unfiltered application list, so the script's per-resource query-string lookup always resolved to whichever application sorted first; (b) the script's own resource-name defaults were the CONCEPTUAL manifest keys (`app`/`etl`/`pdf-render`/`provider-sync`), not Coolify application NAMES. Had `--apply` run before this fix, this would have pushed `provider-sync`'s and ETL's secrets onto the web-app container once `PLAID_CLIENT_ID`/`PLAID_SECRET`/`FMP_API_KEY`/`BLS_API_KEY` were present in the operator's `.env` — the confinement violation `secrets-manifest.yml`'s own `PLAID_CLIENT_ID`/`PLAID_SECRET` entries say has **no CI fence**; `scripts/ci/fence-push-secrets-strikes.sh` is that fence now, and its own strike-verify reproduced this exact push (ETL's `FMP_API_KEY` landing on `pfin-app`'s uuid) against the reverted code. Fixed: the script fetches `/applications` ONCE and matches each resource by EXACT `name ==` locally (dying on >1 match, never picking one), and its own `*_RESOURCE_NAME` defaults are now the real Coolify names — `pfin-app` (confirmed, created) and `pfin-back-etl` (confirmed, runbook §3's own topology table) are sourced; `pfin-pdf-render`/`pfin-provider-sync` are a **stated best guess** (no resource exists yet under either name) — safe to guess wrong, since a wrong guess now resolves to ABSENT, never to the wrong resource. `APP_RESOURCE_NAME=pfin-app` is therefore no longer a required override (harmless if still passed). `--skip-missing-resource` is still required at this stage: `etl`/`pdf-render`/`provider-sync` don't exist yet, so a bare `--apply` would abort naming them. Expect **exit 3** (a partial run) — that is the CORRECT outcome here, not a failure; treat only exit 1/2 as real errors (see the script's own `--help` for the code table). **Scope of this fix, stated explicitly (Sec review, PR #840):** this sweep and its fence cover **only the Coolify-API `?name=` defect** (`GET /applications?name=X` in this script). `scripts/provision-vps.sh` makes the SAME shape of call against Hetzner's API (`?name=` on `/servers` and `/primary_ips`) at ten sites — lines 317, 332, 339, 360, 472, 488, 527, 557, 617, 637 (339 feeds a delete/recreate path; 557 sets `BOX_IP`) — **not touched by this PR.** Booked as a follow-up: measure whether Hetzner's `?name=` filter actually filters (unlike Coolify's), and if not, add the same unfiltered-fetch-plus-local-exact-match idiom or a uniqueness assertion there.
   **Pushed to `pfin-app` this run — conditional on presence in the operator's local `.env` (Sec N2, PR #833 joint review):** `SUPABASE_SERVICE_ROLE_KEY` (RT-26 allowlist, sole app-side holder), `PDF_WORKER_SIGNING_KEY` (also targeted at `pdf-render`, skipped — that resource doesn't exist yet), `WORKER_ADMISSION_SHARED_SECRET` (also targeted at `provider-sync`, skipped), `DISCORD_WEBHOOK_URL` (also targeted at `etl`+`provider-sync`, skipped). **Read the preflight's own `MISSING from local .env` line before `--apply`** — this script skips (prints, does not fail) any `production_only` name with no value in the operator's `.env`, so "pushed" above is a claim about the mapping table, not a guarantee any one of these four actually lands; `WORKER_ADMISSION_SHARED_SECRET` absent fails **closed** at the admission endpoint by the manifest's own ruling (no exposure), but the other three should be confirmed present before trusting step 5's `--require-env` to be checking a value this step actually supplied.
   **Excluded from this script entirely, every run, by its own design** (never pushed to any resource by this vehicle): the Supabase stack's own 10 `production_only` names (`EXCLUDED_SUPABASE_STACK` — minted by `provision-supabase-stack.sh`/`mint-supabase-jwt-keys.sh`) and `PFIN_DB_PASSWORD` (`EXCLUDED_DEFERRED` — §6.1/§6.2's role-handoff, never this script). `FMP_API_KEY`/`BLS_API_KEY`/`PLAID_CLIENT_ID`/`PLAID_SECRET`/`SIMPLEFIN_TOKEN` map only to `etl`/`provider-sync` and are skipped this run (not excluded — they'll push automatically once those resources exist and this command is re-run for their own first deploys).

3. **Set the one non-secret app env var this step needs.**
   ```sh
   BOX_IP=<box-ip> scripts/coolify-env.sh set pfin-app PUBLIC_SUPABASE_URL=http://api-gw:8000 --apply
   ```
   `http://api-gw:8000` is a **fixed literal**, not derived per-deploy — `api-gw`'s Coolify-internal service DNS name and port (§4 (1d)). The network PRECONDITION this literal depends on is now **structural** (step 1's `external:` attachment), not a pre-deploy declared-settings check — superseding an earlier revision of this procedure's `--require-network-with` guard, built before the F/CTO topology ruling made `settings.connect_to_docker_network` irrelevant to `pfin-app`'s new shape.
   **`PUBLIC_SUPABASE_ANON_KEY` is deliberately NOT set here, and never should be by hand** (Sec N1) — step 4's mint is its sole and authoritative writer and overwrites it unconditionally regardless of what (or whether) it was set beforehand.

4. **Mint the real keys onto `pfin-app` — LAST, always.**
   ```sh
   BOX_IP=<box-ip> scripts/mint-supabase-jwt-keys.sh --apply --app-name pfin-app --verify-live
   ```
   Quoting the ruled ordering verbatim (§5, "Two writers of `SUPABASE_SERVICE_ROLE_KEY` on `app`", Sec joint-review 2026-09-13): **"Required ordering: run `push-production-secrets.sh` FIRST, `mint-supabase-jwt-keys.sh --apply --app-name` LAST — because mint overwrites unconditionally, running it last guarantees the real key wins; the reverse order clobbers the real key with a `.env` value and the app comes up holding a wrong `service_role` key."** The same two-writer shape applies to `PUBLIC_SUPABASE_ANON_KEY` — this is mint's OWN write of that name (not a second writer racing step 3, which never touches it), so this step is the sole and authoritative source for both values on `pfin-app`.

5. **Assert the required names, deploy, poll, read back the running container, verify network attachment + hostname resolution, and probe health — one command.**
   ```sh
   BOX_IP=<box-ip> scripts/deploy-app.sh pfin-app --expect-base-directory /api --expect-build-pack dockercompose \
     --compose-service app \
     --require-env PUBLIC_SUPABASE_URL,PUBLIC_SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY \
     --require-network <APP_STACK_NETWORK_NAME from step 1's output> \
     --resolve-host api-gw \
     --apply --health-path /
   ```
   [`scripts/deploy-app.sh`](../scripts/deploy-app.sh) (extended, this ruling) resolves `pfin-app`, refuses unless its live `base_directory` equals `/api` **and** its live `build_pack` equals `dockercompose` (the identity guard — Sec's own `--expect-build-pack` ask, PR #833 joint review), THEN refuses unless all three named env vars are present in the store BY NAME (`--require-env`) — both guards strike-proven to refuse BEFORE any `/deploy` call, offline (`scripts/ci/fence-deploy-app-strikes.sh`). Only then does it `POST /deploy`, poll to a terminal state, and resolve the running container via `--compose-service app` (`docker compose --project-name <uuid> ps -q app`, the correct primitive for a `dockercompose`-pack resource — refuses on >1 RUNNING match, Sec F4, struck independently from the non-compose mechanism). POST-DEPLOY (there is no running container to inspect before this point): `--require-network` asserts the container's actual Docker network membership includes the named network (the DEPLOYED reality of the `external:` attachment, not a declared-config guess); `--resolve-host api-gw` `docker exec`s `getent hosts api-gw` inside the container — the same probe used for the migrator's own cutover verification (§6.8 step 2) — proving the container can actually resolve its dependency's hostname over that network, one level short of "the request succeeds" (step 6's job). `--health-path /` additionally curls the resource's own Coolify-assigned fqdn from the operator's machine — best-effort, not fatal on a non-200 (see the UNMEASURED flags on the field table above: fqdn continuity and Traefik-to-compose-service routing are both open questions this probe answers empirically, not assumed).

   **MEASURED (team-lead, stage A execution, 2026-09-20 — first real deploy of `pfin-app`: deployment `b7yorzel3eyicegqkzucbnku`, commit `75368e19`, QUEUED → FINISHED).** The script itself hit two local-shell defects on this exact run (a Go-template literal-`\t`-vs-real-tab mismatch that made the container-resolve step refuse a container that was actually running, and a heredoc backtick/dollar-brace comment that corrupted the `--require-env` guard's own diagnostic output without affecting its PRESENT/PASS result) — both root-caused and fixed at PR #841; `--require-network`/`--resolve-host`/`--health-path` did not run this pass because the script died before reaching them (full incident: [`standup-log.md`](../docs/records/v1final/standup-log.md) §7.1 step 6). What was measured BY HAND in their place that same day: container `app-7frkiyqnetb4bgev7j7sw5eg-193901004789` Up, compose project/service labels correct, attached to BOTH its own network and `nz7mbexygw9lesjlazcxeltn` (the stack's), `getent hosts api-gw` resolves inside the container, in-container `GET http://127.0.0.1:3000/` → `200`. **Traefik answers but routes nowhere yet:** `http://<uuid>.<box-ip>.sslip.io/` → `404` — Traefik itself is up, but `expose:` alone registers no router; a router needs an actual Domain, not assigned until the §2/§9 DNS cutover. `http://<box-ip>:3000/` → `000`, correctly unpublished by design (Lock 13 / this section's own `expose:`-only convention). **Do not read the `404` as a deploy failure** — it is the expected shape for an `expose:`-only resource with no Domain yet, the same reasoning already applied to `rest`/`supavisor` elsewhere in this runbook. **Re-run after #841 merged (`main` `2619ab3f`), D-3:** the SAME three legs, now measured by the script itself, not by hand — deployment `omxgopni1mqizfxhmxwzkvrd` QUEUED → FINISHED, exit `0`; `--require-network` confirms both networks attached; `--resolve-host api-gw` resolves; `--health-path /` reports the same non-fatal `404` as the hand measurement above. The D-2 stderr noise is gone.

6. **`pfin`-exposure smoke through the deployed app's own Data-API path (BACKLOG.md §7.36 item 64).**
   ```sh
   BOX_IP=<box-ip> scripts/smoke-pfin-exposure.sh pfin-app --compose-service app
   ```
   [`scripts/smoke-pfin-exposure.sh`](../scripts/smoke-pfin-exposure.sh) (extended, this ruling) resolves `pfin-app`, `docker exec`s into its running container via the SAME `--compose-service app` mechanism `deploy-app.sh` uses (kept in sync deliberately — both scripts must target the identical container), and issues an anon-bearer request against a `pfin` relation with `Accept-Profile: pfin` — the anon key crosses via the container's OWN env, never the wire, never printed. No user has ever signed up (Q5: signup off, invite-only), so this default mode is the only one available pre-invite; it exits **0** on the expected `401 {"code":"42501",...}` (per [`standup-log.md:695`](../docs/records/v1final/standup-log.md): proves `pfin` **is** exposed — not `PGRST106` — **and** the B-1 anon-zero-grant fence holds) and **non-zero** on anything else, including a `200` (treated as a security anomaly, not a pass — strike-proven, `scripts/ci/fence-smoke-pfin-exposure-strikes.sh`). Once an authenticated user JWT exists (post-invite), re-run with `--jwt <user-jwt>` and it instead expects `200` per §6.9 step 6 — the two modes do **not** accept each other's success shape (a `401` that passes anon-mode FAILS jwt-mode, and vice versa). **MEASURED (team-lead, stage A execution, 2026-09-20):** run against the same `pfin-app` deploy as step 5's record above — container found, `HTTP 401` `code=42501`, exit `0` — `pfin` is exposed through the deployed app's own Data-API path and the anon-zero-grant fence holds.

7. **§7 step 7 — flip the `DEPLOY_ON_SUCCESS` gate, then re-exercise the trigger once.** Once `app`'s first (manual) deploy above is confirmed healthy and the migrate-only leg of §6.5 Phase D step 12 has passed (the `DEPLOY_ON_SUCCESS=0` suppression line, green job): set `DEPLOY_ON_SUCCESS=1` in `.env`, re-run `BOX_IP=<box-ip> scripts/provision-vps.sh --apply` (idempotent — rewrites only `/etc/pfin/migrator-trigger.conf`), then **push a second no-op migration and watch the trigger fire again**, confirming the orchestration script's `api GET "/deploy?uuid=$APP_UUID"` call actually fires this time. ⚠ **Do not skip the re-exercise** — Sec's condition on this gate: the deploy leg must not ship unexercised; flipping the flag without a second live fire is a qualifier nobody checked.

   **MEASURED (F/CTO + team-lead, stage B execution, 2026-09-20, `main` `6ec8f426`) — the re-exercise happened; this leg is CLOSED, not merely flagged.** `DEPLOY_ON_SUCCESS=1` appended to `.env`; `provision-vps.sh` preflight reported every step "already matches" except `/etc/pfin/migrator-trigger.conf` ("missing or differs -- would write it"). **Operator note, not a script gap:** the Claude Code auto-mode classifier denied team-lead's own invocation of both `provision-vps.sh --apply` and `gh workflow run` as a `[Production Deploy]`-class action — F/CTO ran both by hand from the operator Mac instead; see §7.1's own SCRIPTED/BY-HAND table below for how this is now recorded as a standing property of this step, not a one-off. Conf read back on the box: `MIGRATOR_SERVICE_UUID=anz4uzfdumcfgc92wnfpov4i`, `MIGRATOR_TASK_UUID=ib18uei5cmlrisypa5mv1qpj`, `APP_UUID=7frkiyqnetb4bgev7j7sw5eg` (was `nzfkslmj8cm6ba86bdizuvd8`, the deleted plain-Dockerfile shell — this conf now names the CURRENT `pfin-app`), `DEPLOY_ON_SUCCESS=1`, `MIGRATOR_TASK_COMMAND=sh /workspace/pfin-task.sh`, `MIGRATOR_APP_NAME=pfin-migrator`; file mode `-rw-r-----` `root:ci-migrate`, unchanged. `gh workflow run migrator-trigger.yml --ref main` dispatched by F/CTO, environment-gate approved by F/CTO: run `35537705094` (created `2026-09-20T21:07:24Z`) — job "Trigger migrator (SSH -> forced command -> apply + deploy)" **success**. Orchestrator: pre-fire execution-uuid snapshot → bound to execution `qzxfnipaljpls8zzlx4rs775` by set difference → **"migration apply SUCCEEDED — triggering app deploy (uuid 7frkiyqnetb4bgev7j7sw5eg)"** → **"app deploy triggered."** Box: `pfin-app` deployment `in_progress` at `21:09`, finished within ~30s; new container `app-7frkiyqnetb4bgev7j7sw5eg-210940757290` Up, image `7frkiyqnetb4bgev7j7sw5eg_app:6ec8f4265c09ae6065d3729be971349b5c1947e5` (= `main` at fire time; the prior container had run `2619ab3f`), networks `7frkiyqnetb4bgev7j7sw5eg` + `nz7mbexygw9lesjlazcxeltn`, in-container `GET /` → `200`. Exactly one `pfin-app` container — no stale sibling left running. Full record: [`standup-log.md`](../docs/records/v1final/standup-log.md) §7 step 7.

**Flags found while writing this procedure (none block it, all stated plainly, not papered over):**

- **Cookies are NOT `Secure`-flagged, so auth over the pre-DNS plain-HTTP sslip.io placeholder is not broken by this app's own defaults.** Measured against `api/node_modules/@supabase/ssr`'s `DEFAULT_COOKIE_OPTIONS` (`{path:"/", sameSite:"lax", httpOnly:false, maxAge:...}` — no `secure` key at all) and `hooks.server.ts`'s `cookies.set(name, value, {...options, path:'/'})`, which never adds one. `sameSite: 'lax'` also does not block a same-origin request. This is a measured absence, not an inference from the library's docs.
- **`hooks.server.ts`'s env guard does not block PROCESS BOOT, and needs nothing pre-DNS-specific.** `supabaseEnv()` is a memoized-on-first-REQUEST guard (`let cached`, populated inside the exported `authHandle`), not a module-load-time throw — the container starts and stays up with no env at all; the guard only fires when a request actually arrives without `PUBLIC_SUPABASE_URL`/`PUBLIC_SUPABASE_ANON_KEY` already set (which step 5's `--require-env` asserts before this sequence ever deploys, so it is never hit in this sequence). No `ORIGIN`/public-URL env var is read anywhere in `hooks.server.ts` or `vite.config.ts` — SvelteKit's own CSRF check compares the request's `Origin` header against its own `Host`, not an env-declared public origin, so nothing here needs a value this record cannot supply pre-DNS.
- **`api/Dockerfile` does not need `include_source_commit_in_build`.** Confirmed by grep: no `SOURCE_COMMIT`/`GIT_SHA` reference anywhere in `api/Dockerfile` (unlike the migrator Dockerfile, which FATALs without it — `scripts/provision-migrator-app.sh`'s own preflight). Unaffected by the compose recreation (the Dockerfile itself is unchanged) — `scripts/provision-app.sh` reports this setting's live value for visibility but does not force it either way, unlike the migrator's own script.
- **Coolify's sslip.io fqdn is NOT the same "pre-DNS" blocker as the §2/§9 `pfindash.com` cutover.** A sslip.io-style fqdn (`<anything>.<box-ip>.sslip.io`) is a public wildcard-DNS service that resolves to `<box-ip>` universally, no manual DNS action needed — it may already be externally reachable over plain HTTP the moment the container is healthy, independent of whether Coolify's Traefik has issued it a TLS cert. ⚠ **The specific uuid this was measured against (`nzfkslmj8cm6ba86bdizuvd8`) no longer exists after step 1's recreation** — a fresh resource may carry a different auto-assigned fqdn (see the field table's own UNMEASURED note above). **Not independently verified against the live box in this PR** (DevOps does not touch the box) — `deploy-app.sh --health-path /`'s external check will report the real answer, against whatever fqdn the NEW resource actually carries, at execution time; if it 000s/timeouts, that is new information about Traefik/Domain config, not evidence this procedure is wrong.

---

**2. `etl` — `pfin_back_etl`**

| Field | Value | Grounding |
|---|---|---|
| Base Directory | `workers/etl/` | §3 topology table |
| Build pack | **Compose** — [`workers/etl/docker-compose.yaml`](../workers/etl/docker-compose.yaml), **two Coolify units** sharing one image/build: `pfin-back-etl` (nightly ingest, resident) and `pfin-back-etl-monthly-report` | §3 table; compose file itself |
| Container port / Domain | None — no `expose:`/`ports:` on either service in the compose file; pure batch workers that connect **out** (Postgres, Discord), accept no inbound connections | `workers/etl/docker-compose.yaml` header comment |
| Cannot start until | §6.1's `pfin_etl` role provisioning (two-step `\password`/`LOGIN` handoff) has run — starting first fails at connect (loud, safe, not an exposure) | §6.1; existing ETL bullet above |
| Health check | No HTTP endpoint (batch worker) — Coolify's container-running check is the only mechanism available; correctness is asserted by the Scheduled Task's own exit-code semantics (§6's "fail-closed lives in the Scheduled Task's own exit status" framing), not a health probe | `workers/etl/Dockerfile` (`CMD ["tail","-f","/dev/null"]`) |
| Resource limits | Open — see below | — |

**Scheduled Tasks (Pattern A — resident container + `docker exec`, per the existing Pattern-A bullet above):**

- **`pfin-back-etl-monthly-report` unit** — cron **`0 6 1 * *`** (06:00 UTC, 1st of the month), command **`python run_monthly_report.py`**. Both the expression and the command are already committed as comments in `workers/etl/docker-compose.yaml` (lines 36–42) — not invented here, just surfaced into the deploy config. Known residual: UTC-pinned boundary fires ~7h early relative to a Pacific-timezone user's local month-end (BACKLOG §7.34 item 3, owner unnamed).
- **`pfin-back-etl` unit (nightly ingest) — ⚠ GAP, flagged rather than fabricated.** No cron expression for a nightly NAV/CPI/FMP ingest is ratified anywhere in this tree. [`workers/etl/run_nav_daily.py`](../workers/etl/run_nav_daily.py)'s own docstring states: *"Phase-7 Coolify cron scheduling is DEFERRED (F/CTO-ratified) — this file is the worker entry point the scheduler will eventually invoke, not the schedule."* Compounding this: the `pfin-back-etl` service block in the compose file declares **no** `PFIN_DB_*` / `FMP_API_KEY` / `BLS_API_KEY` environment references at all (only `PYTHONUNBUFFERED=1`) — per the migrator-role provisioning note elsewhere in this runbook, *"Coolify runs plain, interpolation-only `docker compose`, so a shared-store var reaches only the service whose block references `${VAR}`"* — meaning as currently committed, this service has **no wired access** to the credentials a nightly ingest would need, regardless of what cron expression is later chosen. **This blocks the nightly-ingest Scheduled Task from being creatable, not just its schedule from being decided.** Flagged to F/CTO (cadence ratify) + Backend (which script(s) — `run_nav_daily.py` alone, or also `run_cpi_backfill.py`/`run_nav_backfill.py`'s non-backfill siblings — the nightly entrypoint actually runs, and the missing `environment:` block).

**Env-var wiring (→ §5 + §6.1):** `PFIN_DB_USER=pfin_etl` (non-secret) + `PFIN_DB_PASSWORD` (the `pfin_etl` credential, `production_only`, set by §6.1's handoff — **not** `push-production-secrets.sh`, which explicitly excludes `PFIN_DB_PASSWORD`) + `FMP_API_KEY` / `BLS_API_KEY` (`production_only`, pushed by `push-production-secrets.sh`) — once the missing `environment:` block above is added. `DISCORD_WEBHOOK_URL` is already wired (compose file, monthly-report unit) and documented as a fourth consumer in §5's mapping table.

---

**3. `provider-sync`**

| Field | Value | Grounding |
|---|---|---|
| Base Directory | `workers/provider-sync/` | §3 topology table |
| Build pack | **Compose** — [`workers/provider-sync/docker-compose.yaml`](../workers/provider-sync/docker-compose.yaml) (SELF-212 Option C b-i; not the bare Dockerfile pack) | §7 existing bullet; §3 table |
| Admission port | `8081`, **`expose:`-only — NO published `ports:`, NO Coolify Domain / Traefik `Host()` label (RT-27)** | compose file `expose: ["8081"]`; RT-27 fence |
| Networking / CA-4 | **MUST** be attached to the **same Docker network** as `app` (`external:` declared in each compose's own top-level `networks:` block, RESTATED CORRECTLY per ADR-073 — §3) — internal DNS `http://provider-sync:8081` resolves across that attachment; Coolify project membership grants no attachment at all | compose file header; §7 CA-4 bullet; §10 CA-2 |
| Deploy-time check | CA-1 — dump the admission container's actual env and confirm the limb-(a) public-route regex would match Coolify's real injected FQDN/URL var names for the running Coolify version (existing CA-1 bullet) | §7 existing CA-1 bullet |
| Health check | `GET /healthz` on `:8081` — unauthenticated liveness, `{status:'ok'}`, internal-only (same port the admission surface is on; not published) | `workers/provider-sync/src/http/admissionServer.ts` line 337, 375 |
| Cannot cut over until | §6.2's `pfin_provider_sync` role handoff (same deploy pass as §6.1) | §6.2 |
| Resource limits | Open — see below | — |

**Scheduled Task:** `@daily`, command **`node dist/cli/poll.js`** — already fully specified in the existing "provider-sync daily poll" bullet above (cadence, exit-code semantics, required env subset). Not re-derived here; this block only adds the Base-Directory/build-pack/networking/health-check facts the STUB was missing.

**Env-var wiring (→ §5 + §6.2):** `PFIN_DB_USER` (`authenticator` pre-cutover → `pfin_provider_sync` post-§6.2-cutover, non-secret) + `PFIN_DB_PASSWORD` (`production_only`, per-role value, §6.2) + `PLAID_CLIENT_ID`/`PLAID_SECRET`/`PLAID_ENV` (`production_only`, sole holder per ADR-011 D17/Lock 13 amendment) + `WORKER_ADMISSION_SHARED_SECRET` (same value as `app`, per §5's ratified deviation) + optional `SIMPLEFIN_TOKEN` + optional `DISCORD_WEBHOOK_URL` (worker's own direct dispatch — not required for the Coolify→Discord Scheduled-Task-failure path, per the existing poll-env bullet). All pushed by `push-production-secrets.sh`'s `SECRET_RESOURCE_MAP → provider-sync`, except `PFIN_DB_PASSWORD` (§6.2, excluded from that script).

---

**4. `pdf-render` — Node PDF worker**

| Field | Value | Grounding |
|---|---|---|
| Base Directory | `workers/pdf-render/` | §3 topology table |
| Build pack | **Compose** — [`workers/pdf-render/docker-compose.yaml`](../workers/pdf-render/docker-compose.yaml), adopted at SELF-348 A4 item 4c / Sec N-4, **superseding** the plain-Dockerfile pack this container shipped with at Phase 5 | §3 table; compose file header |
| Render port | `8080`, `expose:`-only (compose file; matches `EXPOSE 8080` in the Dockerfile and `server.js`'s `PORT` default) — never `ports:`, never a Domain | compose file lines 87–88 |
| Dockerfile status | Not a placeholder — [`workers/pdf-render/Dockerfile`](../workers/pdf-render/Dockerfile) is Puppeteer + system Chromium + app code (SELF-348 A4, real render pipeline). The existing bullet above previously said "currently a placeholder; Backend adds Puppeteer app code at Wave 6" — corrected in place in this PR. | `workers/pdf-render/Dockerfile` (Chromium install, `npm ci`, `CMD ["node","src/server.js"]`) |
| DB reach | **Zero, by design** (Lock 13 mod #2) — no `SUPABASE_*` env, no Postgres client; enforced by RT-22 + RT-22-manifest on every PR | existing bullet; Dockerfile comments |
| Health check | `GET /healthz` on `:8080` | `workers/pdf-render/src/server.js` line 110 |
| Container hardening | `cap_drop: [ALL]`, `security_opt: [no-new-privileges:true]` (Sec F-17) — already in the compose file, not something this de-stub adds | compose file lines 93–96 |
| Resource limits | Open — see below. Headless Chromium is the fleet's most memory-hungry process; flagged explicitly rather than left implicit in the general "open" note. | — |

**Env-var wiring (→ §5):** exactly one — `PDF_WORKER_SIGNING_KEY` (`production_only`, **same value** as `app`, ≥32 chars — see the existing SD-20 length-precondition bullet above, verify **before** this worker's first deploy). Pushed by `push-production-secrets.sh`'s `SECRET_RESOURCE_MAP → app, pdf-render`.

---

### Resource limits — genuinely open, not fabricated

No CPU/memory ceiling for any Coolify service appears anywhere in this repo — this runbook, ARCH, or any script. CAX21 is 4 vCPU / 8 GB RAM total, shared across the self-hosted Supabase stack (multiple containers), Coolify's own 6 control-plane containers, the `migrator` resource (⚠ its own standalone Coolify application since ADR-072 Amendment 4 / `BACKLOG.md` §7.36 item 29 — still one more container on the SAME box, so the contention risk this paragraph names is unchanged by that move), and all four units above — real contention risk on an 8 GB box that this section cannot resolve by assertion. **Flagged to F/CTO** (capacity/cost is an escalation item per DevOps's own remit, not a DevOps unilateral call) rather than shipping invented numbers. If a starting point is wanted before real usage is measured: `pdf-render` (headless Chromium) is the one unit worth ring-fencing first, since an unbounded worker there can starve the Supabase stack on the same box — measure actual RSS after first deploy and set ceilings from that, not from a guess.

---

### 7.2 Worker first-deploy procedure — `etl` / `pdf-render` / `provider-sync`

**New 2026-09-20 (BACKLOG.md §7.36 item 68 / PR W-1; F/CTO ruled 2026-09-20: workers before the §2/§9 Domain assignment, because §10's smoke gate needs the workers up first).** Mirrors §7.1's numbered-procedure shape: preconditions named, then a SCRIPTED/BY-HAND audit table, sequenced across three PRs. **W-1** landed the compose network-attachment pattern (§3/§7's own text above) and `scripts/provision-worker.sh`, closing step (i) below for all three workers. **W-2** lands `scripts/db-role-handoff.sh` and the non-secret env wiring below, closing steps (ii)/(iii). **W-3** (deploy vehicle, reachability smoke, §10 checklist, Scheduled Task creation) remains **PENDING** — not built yet — marked as such per this runbook's own SCRIPTED/BY-HAND convention (a step without a named script is a gap, not an assumption of "by hand is fine").

**Non-secret worker env — `scripts/coolify-env.sh`, W-2.** `PFIN_DB_HOST` / `PFIN_DB_PORT` / `PFIN_DB_NAME` / `PFIN_DB_USER` / `PLAID_ENV` / `ADMISSION_PROBE_PUBLIC_URLS` join `PFIN_DB_SSLMODE` on that script's `SET_ALLOWLIST` (the credential itself, `PFIN_DB_PASSWORD`, stays OFF this allowlist — it is a `secrets-manifest.yml` `production_only` name, delivered only by step (iii)'s `db-role-handoff.sh`, never by this script). Intended values — the STACK's own internal service DNS (§4/§6), not each worker's local-dev `.env.example` default:

| Name | `etl` | `provider-sync` | Source |
|---|---|---|---|
| `PFIN_DB_HOST` | `db` | `db` | the stack's own internal Postgres service name — `infra/supabase/migrator/docker-compose.yaml`'s `PROD_DB_URL` uses the identical literal (`@db:5432`) |
| `PFIN_DB_PORT` | `5432` | `5432` | same source |
| `PFIN_DB_NAME` | `postgres` | `postgres` | the actual DATABASE name — `pfin` is the SCHEMA, not the database (do not confuse the two) |
| `PFIN_DB_USER` | `pfin_etl` | `pfin_provider_sync` (post-§6.2-cutover; `authenticator` pre-cutover) | §6.1/§6.2 |
| `PFIN_DB_SSLMODE` | `disable` | `disable` | BACKLOG.md §7.36 item 26 ruling (already wired, unchanged by this PR) |
| `PLAID_ENV` | — | `sandbox` (V1.0) / `production` (post-SELF-212) | `workers/provider-sync/.env.example` |
| `ADMISSION_PROBE_PUBLIC_URLS` | — | comma-separated public https FQDNs, unset = fail-safe no-op | `workers/provider-sync/.env.example` Note N4 |

Set via `BOX_IP=<box-ip> scripts/coolify-env.sh set <resource-name> NAME=VALUE [NAME=VALUE...] --apply` — one invocation per worker, after step (i) creates the resource and before step (iv)'s deploy.

Preconditions: `pfin-supabase-stack` already exists and is deployed (§4/§6); for `etl` and `provider-sync`, §6.1/§6.2's role provisioning must run before that worker can connect (below). `pdf-render` holds no database credential and no Postgres client by design (Lock 13 mod #2 — a credential-absence fence, not a network one; it is attached to the stack network like every other fleet service) and needs no role handoff at all.

**SCRIPTED / BY-HAND audit.**

| Step | Status | Detail |
|---|---|---|
| (i) | **SCRIPTED — W-1 (this PR)** | `provision-worker.sh <resource-name> --apply`, run once per worker (`pfin-back-etl`, `pfin-pdf-render`, `pfin-provider-sync`) — recreates the resource as `dockercompose` (same delete-if-empty-shell guard as `provision-app.sh`), and sets that resource's own uniquely-named network var (`ETL_STACK_NETWORK_NAME` / `PDF_RENDER_STACK_NETWORK_NAME` / `PROVIDER_SYNC_STACK_NETWORK_NAME`) from the stack's live Docker network. Does NOT deploy. |
| (ii) | **SCRIPTED (W-2)** | Push the `production_only` secrets already mappable to each worker: `push-production-secrets.sh --apply --skip-missing-resource` (same script §7.1 step 2 uses — its `RESOURCE_IDENTITY_MAP` carries the F/CTO-RULED names `pfin-back-etl` / `pfin-pdf-render` / `pfin-provider-sync`, landed at W-1). `pdf-render` gets `PDF_WORKER_SIGNING_KEY` only; `provider-sync` gets `WORKER_ADMISSION_SHARED_SECRET` + `PLAID_CLIENT_ID`/`PLAID_SECRET` + `SIMPLEFIN_TOKEN` + `DISCORD_WEBHOOK_URL`; `etl` gets `FMP_API_KEY`/`BLS_API_KEY` (nightly unit) + `DISCORD_WEBHOOK_URL` (monthly-report unit). No code change needed — the script already excludes `PFIN_DB_PASSWORD` (`EXCLUDED_DEFERRED`, step (iii)'s own province). |
| (iii) | **SCRIPTED (W-2)** | **DB role handoff + `PFIN_DB_PASSWORD` delivery — `scripts/db-role-handoff.sh <role> --apply`**, same two-statement discipline as §6.1/§6.2 (`\password <role>` piped over stdin then `ALTER ROLE <role> LOGIN;`, never a single atomic statement — see §6.0's own new SCRIPTED/BY-HAND table above, and the script's own header, for the full mechanism). `etl`: `scripts/db-role-handoff.sh pfin_etl --apply` (§6.1). `provider-sync`: `scripts/db-role-handoff.sh pfin_provider_sync --apply` (§6.2; pre-cutover, `authenticator`'s own credential applies instead — see the existing `workers/CLAUDE.md` note on the rotation-coupling distinction; this script targets the POST-cutover dedicated-role state). `pdf-render`: **N/A — no DB credential of any kind, skip this step** (zero-DB-isolation by design; do not add one to "complete the table"). |
| (iv) | **PENDING — W-3** | Deploy. Needs a `deploy-worker.sh` sibling to `scripts/deploy-app.sh` (identity guard on name/base_directory/build_pack; `--require-env` names-only presence; post-deploy `--require-network` + `--resolve-host`; health/poll) — **not built in this PR**, named here as the next scripted gap, not assumed to already exist. |
| (v) | **PENDING — W-3** | Per-worker reachability smoke: `provider-sync`'s CA-2 admission-endpoint negative smoke (§7's existing CA-1/CA-4 text; §10 CA-2), an ETL poll smoke, and a PDF round-trip smoke (`app` → `pdf-render:8080/render` → PDF bytes back) — the two named explicitly in MILESTONES.md's Active Feature row as what §10's smoke checklist needs before the §9 DNS cutover can proceed. |
| (vi) | **PENDING — W-3** | `docs/deployment-runbook.md` §10's own verification checklist items for the ETL poll and the PDF round-trip — closing the gate F/CTO's 2026-09-20 ruling names (§10 smoke gates §9). |
| (vii) | **PENDING — W-3** | Scheduled Task creation (Coolify UI — no API-scriptable equivalent named anywhere in this repo yet, so this step is BY-HAND, not a scripted gap): `provider-sync`'s `@daily` poll (existing bullet above), `etl`'s monthly-report cron (`0 6 1 * *`, existing bullet above). **`etl`'s own nightly-ingest cron remains the pre-existing gap this runbook already flags above** (no cadence ratified, no `PFIN_DB_*`/`FMP_API_KEY`/`BLS_API_KEY` wired to that service block) — unchanged by this PR, not silently folded into W-3's scope. |

---

## 8. Observability

| # | What | Command | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 | Re-establish Coolify → Discord webhook on the new box | Dashboard → Notifications | webhook saved, test event received | PENDING | NOT YET SCRIPTED — no BACKLOG item booked yet; STUB |

`DISCORD_WEBHOOK_URL` is `production_only` (§5). Discord is incumbent — no Slack/PagerDuty without a forcing function.

---

## 9. Cutover & teardown of `pfindash.com`

**One-way door — F/CTO go/no-go required.**

| # | What | Command | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 | Confirm §10 smoke-test gate is green | see §10 | all ship-block rows pass | BY-HAND | one-time measurement |
| 2 | DNS flip (already mechanically covered by §2) | §2 rows 2–4 | traffic resolves to new box | BY-HAND | interactive-credential moment |
| 3 | Tear down incumbent cax21 stack | Hetzner/Coolify console on the incumbent box | incumbent retired | PENDING | NOT YET SCRIPTED — F/CTO timing decision; STUB |

No data-migration dependency (greenfield) — teardown is a clean retirement, not a hand-off.

---

## 10. Verification / smoke-test

Gate before §9 teardown. QA owns RLS/isolation assertions; DevOps owns infra-reachability assertions below.

| # | What | Command | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 | **CA-2** (ship-block) — admission endpoint (`:8081`) NOT externally reachable; positive control from an attached sibling container | external probe + `http://provider-sync:8081` from an attached container | negative: refused/unreachable; positive: `2xx` | BY-HAND | one-time measurement |
| 2 | **CA-7** (ship-block) — `api-gw`/`supavisor` NOT externally reachable; positive control from an attached sibling | `nmap -Pn -p 5432,6543,8000 <box-ip>` + attached-container probe | negative: filtered/closed; positive: resolves + responds | BY-HAND | one-time measurement |
| 3 | **TZ-1** (ship-block) — TimeZone pin, per login role, never as `postgres` | §4.1 rows 1–3 | `UTC\|database` everywhere; zero role-level rows | BY-HAND | one-time measurement |
| 4 | **⏸ TZ-1b** — wire the R3 drift sweep (recurring, §7 Scheduled Task) before sign-off | §7 (not this PR) | one run reported to Discord | PENDING | NOT YET SCRIPTED — ratified 2026-08-06, not yet built |
| 5 | **⏸** Provenance limb — `061` in the ledger | `select 1 from supabase_migrations.schema_migrations where version = '061';` | one row | BY-HAND | one-time measurement |
| 6 | End-to-end smoke (TLS reachable, auth login, RLS isolation, PDF round-trip, ETL poll, Discord fires) | see script header / QA battery | all pass | PENDING | NOT YET SCRIPTED — STUB, explicit pass/fail criteria not yet defined |

Any deviation on rows 1–3 → STOP, do not cut over (§9).

---

## 11. User deletion / GDPR erasure — FK cascade considerations

Not an isolation concern (RLS + Decision-3 fences handle that independently) — this is FK-cascade *ordering* so a delete does not fail loud partway through.

| # | What | Command | Expected | Status | Reason |
|---|---|---|---|---|---|
| 1 | Enumerate the user's linked Plaid/SimpleFIN Items, `/item/remove` each (revoke-at-provider + `service_role` secret-delete) | erasure routine (not yet built) | Items revoked | PENDING | NOT YET SCRIPTED — routine not yet built; Sec joint-review gates it at build time |
| 2 | Detach grouped legs before the user delete: `NULL` `pfin.account_trans_annotation.journal_id` for the tenant's rows | erasure routine | legs detached | PENDING | NOT YET SCRIPTED — same routine |
| 3 | Delete `auth.users` (cascades to `pfin.*`) | erasure routine | cascade completes | PENDING | NOT YET SCRIPTED — same routine |

Never a `SECURITY DEFINER` trigger for auto-clean ([ADR-011](../DECISIONS.md#adr-011) Decision 8 — reintroduces an un-revocable-grant regression).

---

## Open flags (roll-up)

| # | Flag | Owner | Section |
|---|---|---|---|
| 1 | New VPS provider/region/class — cax21 is reference-only | F/CTO | §1 |
| 2 | Reuse `pfindash.com` vs. new domain (gates cutover) | F/CTO | §2/§9 |
| 3 | Pin Coolify version (reproducibility) | DevOps | §3 |
| 4 | PG-17 confirm-vs-deployed (greenfield = forward-by-choice) | DevOps/Architect | §4 |
| 5 | Secrets provisioning + rotation — Sec joint-review mandatory | DevOps+Sec | §5 |
| 6 | ETL secret shape: discrete `PFIN_DB_*` vs. ARCH §5 conn-string | DevOps/Architect/Sec | §5 |
| 7 | BLS key: code requires `BLS_API_KEY` vs. ARCH §5 "free/open" | Architect/Sec | §5 |
| 8 | Cutover timing + teardown go/no-go (one-way door) | F/CTO | §9 |
| 9 | ✅ resolved — greenfield-deployment [ADR-021](../DECISIONS.md#adr-021) | DevOps | Overview |
| 10 | ✅ resolved — `ALTER ROLE … PASSWORD` plaintext handling; two-step handoff (§6.1) | DevOps+Sec | §6.1 |
| 11 | ✅ resolved — DB TimeZone pin (`061` on `main`); §4.1 read-back applies after §6 | Architect/DevOps | §4.1/§10 |
| 12 | ✅ resolved — `pfin-app`/`pfin-supabase-stack` cross-project topology; declared-network-attachment model ([ADR-073](../DECISIONS.md#adr-073)) | F/CTO/DevOps/Architect | §3/§7.1 |

---

Full rationale, MEASURED findings, incident history, and Sec dispositions for every row above: [`docs/archive/deployment-runbook-rationale-2026-09-20.md`](archive/deployment-runbook-rationale-2026-09-20.md), organized by the same section numbering this sheet used before the 2026-09-20 conversion.
