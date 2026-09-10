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
| 3 | Provision VPS + install Coolify | DevOps + F/CTO | ✅ **DONE 2026-09-09** — VPS provisioned, §1 hardening applied, Coolify `4.3.18` healthy |
| 4 | DNS / domain decision + records | F/CTO + DevOps | 🟡 Domain RULED (`pfindash.com` reuse) — records not yet cut over |
| 5 | Stand up self-hosted Supabase; apply migrations | DevOps | 🟡 **Stack LIVE 2026-09-10** — 5 services healthy, verified. Migrations NOT applied (that is step 6 / runbook §6) |
| 5a | Production signup OFF (`GOTRUE_DISABLE_SIGNUP=true`) | DevOps | ✅ **DONE 2026-09-10** — hardcoded in the compose, verified on the running `auth` container |
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

### 3a. VPS provisioned — 2026-09-09

Provisioned by `scripts/provision-vps.sh --apply`, F/CTO having chosen scripted provisioning over the console so the box is a function of a versioned file rather than of what someone clicked.

| | |
|---|---|
| Server | `pfin-prod-1` · id `165377820` |
| Type | `cax21` · arm · 4 cores · 8 GB · 80 GB |
| Location | `fsn1` (Falkenstein) · `fsn1-dc14` |
| Image | `ubuntu-24.04` (arm) · id `161547270` |
| IPv4 | **188.245.166.206** — primary IP `pfin-prod-ipv4`, id `148918358`, `auto_delete=false` |
| IPv6 | `2a01:4f8:c012:57f8::/64` — primary IP `pfin-prod-ipv6`, id `148919739`, **`auto_delete` flipped to false 2026-09-09** (see §3f) |
| Firewall | `pfin-prod-fw` id `11600487` — inbound 22 / 80 / 443 only |
| SSH keys | 2 — `mosko-fintech-id_ed25519` (`SHA256:sbjUXz5Mvzi3lyr5cfgCLZ/LSHBa6mtJ73bwFxrS3pA`, passphrase-protected, human use) and `mosko-fintech-id_ed25519_claude_mosko-fintech` (`SHA256:R2q4NlrUXwEyeoqqX6Z4Yv4hu/cjBb7q8WolntiviH4`, passphrase-free, automation) |
| Cost | EUR 12.49/mo server + EUR 0.60/mo primary IP, gross |

**Runbook §1 verification block — run, not assumed:**

```
cores: 4          mem: 7.5Gi        disk: 75G
arch:  aarch64    os:  Ubuntu 24.04.4 LTS
keys:  2 in authorized_keys
```

`aarch64` is the one that matters. An `x86_64` box boots, runs Docker, and looks entirely healthy while every image in this repo fails to build.

**Port exposure, probed from outside the box by TCP behaviour:**

| Port | Result | Reading |
|---|---|---|
| 22 | service answered | correct |
| 80, 443 | reachable, nothing listening | correct — Coolify's proxy is not installed yet |
| 8000 | **filtered** | correct — dashboard is tunnel-only by ruling |
| 8081 | **filtered** | correct — the CA-4 regression this check exists to catch |

⚠ **A first probe reported every port filtered, including 22, seconds after SSH had succeeded over port 22.** The probe was broken, not the firewall. Recorded because a port scan that fails uniformly looks exactly like a firewall that blocks everything, and believing it would have sent someone to debug a healthy box.

**Coolify dashboard access** (§3, when installed) — the installer prints `http://<box-ip>:8000` and **that URL will not resolve, which is correct**:

```sh
ssh -L 8000:localhost:8000 root@188.245.166.206
# then browse http://localhost:8000
```

**Still outstanding on this box:** §1's hardening beyond key-only auth — password authentication off, root SSH login restricted, non-root operator user. Coolify itself (§3) is not installed.

### 3c. §1 hardening applied — 2026-09-09

Applied over SSH as `root`, verified by probing rather than by reading the config back.

**sshd** — written as a drop-in at `/etc/ssh/sshd_config.d/99-pfin-hardening.conf` so a package upgrade of the main file cannot silently revert it. `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PubkeyAuthentication yes`, and **`PermitRootLogin prohibit-password` — deliberately not `no`**, because Coolify connects to this box as `root` over key-based SSH and a flat `no` breaks its server connection.

| Probe | Result |
|---|---|
| password auth, pubkey disabled | `Permission denied (publickey)` — refused |
| key auth as `root` | works |
| key auth as `deploy` | works |

**Operator user `deploy`** created with sudo and both public keys copied in.

⚠ **One thing I got wrong, fixed the same minute.** I created `deploy` with `--disabled-password` to avoid an interactive prompt, which left it unable to authenticate to `sudo` at all — `sudo: a password is required` for an account that has no password. Granted `NOPASSWD` at `/etc/sudoers.d/90-deploy` instead. **The reasoning, stated so it can be challenged:** the same keys already grant *direct* `root` login (required by Coolify, above), so `NOPASSWD` sudo for `deploy` grants no capability those keys do not already have. It removes a prompt that cannot be satisfied. If `PermitRootLogin` is ever tightened, revisit this — the argument depends on it.

### 3d. Coolify installed — 2026-09-09

**Version `4.3.18`, pinned.** Read from `cdn.coollabs.io/coolify/versions.json` (`coolify.v4`) immediately before installing, per runbook §3 — the runbook deliberately does not hardcode a version, since a stale pin in a doc is worse than no pin.

```
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash -s 4.3.18
```

All six containers healthy: `coolify`, `coolify-db`, `coolify-redis`, `coolify-proxy`, `coolify-realtime`, `coolify-sentinel`. `curl http://localhost:8000` **from the box** returns `302 → /login`.

**Port 8000 re-probed from outside after installation: still filtered.** Installing a service that listens on a port is exactly when a firewall regression would appear, so the check was repeated rather than assumed to still hold from provisioning time.

**Access is tunnel-only.** The installer prints `http://188.245.166.206:8000`; that URL will not resolve and that is correct.

```sh
ssh -L 8000:localhost:8000 root@188.245.166.206
# then browse http://localhost:8000
```

⚠ **Not yet done, and it is F/CTO's:** the first-run admin account has not been created. Until it is, the instance is unclaimed.

⚠ **`/data/coolify/source/.env` on the box holds Coolify's own secrets** and the installer recommends backing it up off-server. It belongs in a password manager, **never in this repo**.

### 3f. IPv6 was NOT protected by the primary IP — found by a login banner

**The record was wrong and the box was right.** This log recorded IPv6 as `2a01:4f8:c013:4348::/64`; the box reports `2a01:4f8:c012:57f8::/64`. Both were true — of *different servers*. The first value belonged to the box destroyed at §3b.

**The cause.** Hetzner creates the IPv6 primary IP **for you** at server-creation time with **`auto_delete = true`**, so unlike the IPv4 one it dies with its server. The rebuild preserved IPv4 exactly as designed and **silently changed IPv6**. The design worked for the address it was pointed at and said nothing about the one nobody had thought about.

**How it surfaced:** F/CTO pasted the box's SSH login banner into the session and its `IPv6 address for eth0` line disagreed with this file. Nothing in the provisioning flow would have caught it — every check written so far reads IPv4.

**Fixed, and the fix is free.** IPv6 primary IPs carry no charge (the pricing feed lists a monthly price for `ipv4` only), so there was never a cost argument for leaving it disposable. The existing IPv6 was renamed `pfin-prod-ipv6` and flipped to `auto_delete = false`. `scripts/provision-vps.sh` now does this on every run: it reads the server's IPv6 primary IP, and flips it if it is still disposable. Verified idempotent — a re-run reports *already persistent* and changes nothing.

**What this actually cost, stated:** nothing, because no AAAA record exists yet. Had DNS been cut over before the rebuild, IPv6 clients would have been sent to a dead address while IPv4 clients were fine — a partial outage affecting only some visitors, which is materially harder to diagnose than a total one.

### 3g. Security patching — 2026-09-09

The login banner reported **51 updates, 49 of them security**. Applied: **46 security updates**, 0 remaining upgradable, **no reboot required**, and all six Coolify containers verified still healthy afterwards.

Done now deliberately: nothing is serving yet, so the blast radius of a bad patch is zero. The same 46 updates applied after cutover would be a change to a live system.

### 3e. Key custody — a single point of failure, named

Both keys on this box exist only on one laptop. Recorded because the recovery path is not obvious:

- **Hetzner injects SSH keys only at server creation.** Adding a key in the Hetzner console does **nothing** to an existing box — it stores it for future ones. This is the same fact that forced a destroy-and-recreate at §3b.
- **To add a machine:** append its public key to `~/.ssh/authorized_keys` on the box from a machine that already has access (`ssh-copy-id`). Both `root` and `deploy` carry copies, so both need updating.
- **If no machine has access:** Hetzner's browser console (VNC) bypasses SSH entirely — reset the root password there, log in, add the key. Rescue mode is the heavier fallback. **So the real dependency is the Hetzner account, not any laptop** — which relocates the risk to wherever that account's 2FA lives.
- **The two keys are not equally safe to copy.** The personal key is passphrase-protected, so the file alone is useless and it is reasonable to store in a password manager. **The automation key has no passphrase — anyone holding that file has root.** It should not be copied between machines; generate a separate key per machine instead.

### 3b. The first box was destroyed and rebuilt — the failure is the point

The first server (`165377261`) came up **correct in every respect**: right spec, right image, sshd listening, firewall exactly as specified. It was also **unreachable by automation**, because the only key on it was `id_ed25519`, which is passphrase-protected. A script has no terminal to type a passphrase into.

**A key you cannot use is indistinguishable from a key that is not there, and you find out after provisioning.** The box was deleted and recreated carrying both keys.

Two things came out of it. `scripts/provision-vps.sh` now takes a **list** of keys and **refuses to provision** unless at least one private half is passphrase-free, naming which key is which. And the rebuild proved the primary IP's whole purpose for real: the address survived the delete and re-attached to the new server, so DNS pointed at it would never have moved.

## Step 4 — DNS / domain

**RULED 2026-09-09 (F/CTO): reuse `pfindash.com`.** Runbook §2 is written.

⚠ **This is a live-traffic change, not a greenfield write.** `pfindash.com` may still resolve to the incumbent box. Check the current records before changing them; §9 cutover timing is entangled with it.

**When cut over, point the A record at 188.245.166.206** — the primary IP, not any address a future rebuild might hand out. That is what the primary IP is for.

**No subdomain split** (DevOps call, verified): nothing in the browser bundle talks to Supabase directly — the only consumer of the Supabase URL is server-side — so Supabase stays fully internal with no public DNS record.

---

## Step 5 — Stand up self-hosted Supabase

**LIVE 2026-09-10.** Five services healthy on the production box, verified end to end. Repo half is `infra/supabase/` (PR #703); the live half took **three deploy attempts**, each blocked by a distinct defect, all three now fixed in the tree.

**What is running.** Coolify application `pfin-supabase-stack`, uuid `eepvlmaq4uortakmido7jgvn`, build pack `dockercompose`, `base_directory: /infra/supabase`, branch `main`. Trimmed to five services — `db`, `auth`, `rest`, `api-gw`, `supavisor`. `studio`, `meta`, `storage`, `imgproxy`, `realtime`, `analytics`, `vector`, `functions` are OUT (see the reopening below).

**Verified after the final deploy** (`agxzitre3a8zvrcustzih6qb`, status `finished`, `main` at `af2c1696`):

| Check | Measured |
|---|---|
| Containers | `db` · `auth` · `rest` · `api-gw` · `supavisor` — all healthy |
| Postgres | `17.6` |
| Init scripts | all 7 vendored files executed on first init, zero errors |
| Service roles | `authenticator` · `pgbouncer` · `supabase_auth_admin` · `supabase_functions_admin` — all passwords SET |
| JWT | `app.settings.jwt_secret` PRESENT |
| Envoy | `lds: add/update listener 'supabase'` + `all dependencies initialized. starting workers` |
| Signup | `GOTRUE_DISABLE_SIGNUP=true` on the running container (Q5) |
| Internal reachability | `db` → `http://api-gw:8000/auth/v1/health` = `401` |
| Host ports | none published by our services. Host `:8000` belongs to Coolify itself |
| External | `5432` · `6543` · `8000` all **filtered**; auto-assigned `sslip.io` fqdn returns `404` |

**Secrets.** 8 minted on the box at `/root/.pfin/supabase.env`, mode `600`: `ANON_KEY`, `SERVICE_ROLE_KEY`, `JWT_SECRET`, `POSTGRES_PASSWORD`, `SECRET_KEY_BASE`, `VAULT_ENC_KEY`, `DASHBOARD_USERNAME`, `DASHBOARD_PASSWORD`. 38 environment variables set on the Coolify resource, stored encrypted at rest.

### §5a — Env vars read back as empty, and were

Setting the 38 variables with per-key `POST /applications/{uuid}/envs` appeared to succeed. A direct DB read then showed **no value on any key**. The cause: Coolify had already created all 44 keys when it first parsed the compose, so every create collided with an existing key and no-opped — and the responses were discarded rather than checked. `PATCH .../envs/bulk` fixed it in one call.

Two measurement traps here, both nearly misread:
- `length(content)` on Coolify's stored rows returns **ciphertext** length (Laravel `encrypted` cast, `eyJpdiI6...` envelope), ~1.8× the plaintext. A row that looks oversized is normal.
- The production and preview rows are separate copies. 44 keys × 2 explains an 88-vs-44 count that first read as duplication.

### §5b — First deploy: every file bind pre-created as an empty directory

`docker compose up` failed with `not a directory: Are you trying to mount a directory onto a file?` on `docker-entrypoint.sh`.

Coolify's compose parser rewrites every **relative** bind mount to an absolute host path under `/data/coolify/applications/<uuid>/` — **discarding `base_directory`** — and does not copy the git clone there. On first parse it creates a `local_file_volumes` row per mount defaulting `is_directory=true`, because it has no prior row to read the shape from, then pre-creates each as an empty host directory. All 12 file-shaped mounts hit this identically. `saveStorageOnServer()`, the method that would write real content, only runs when `is_preserve_repository_enabled` is on — it is off by default for this build pack.

Fixed by `scripts/coolify-materialize-supabase-mounts.sh`, which materializes the real files from `infra/supabase/volumes/**` and syncs Coolify's bookkeeping **through its own Eloquent model** — never raw SQL, because `content` is an `encrypted`-cast column and a plaintext write corrupts it. Runbook §4 (1c).

A second, quieter bug surfaced in the same parse: the two-flag volume mode `:ro,z` bled into the recorded `mount_path` (`/etc/pooler/pooler.exs:ro,z`). Single-flag forms parse cleanly. Fixed at source by dropping the redundant `:z` — this box runs Ubuntu with no SELinux.

### §5c — The `db-data` volume was poisoned, and reported healthy

The failed first deploy got far enough to **start Postgres**, which initialized against the empty-directory mounts. Postgres runs `/docker-entrypoint-initdb.d` exactly once, on first init of an empty data directory — so the mount fix could not reach it, and a redeploy would not have helped.

The container reported **`healthy`** throughout. What it actually looked like:

```
psql: .../98-webhooks.sql: error: could not read from input file: Is a directory
pg_authid:  authenticator|NULL   pgbouncer|NULL   supabase_auth_admin|NULL
show app.settings.jwt_secret  ->  ERROR: unrecognized configuration parameter
```

Only the image's own baked-in scripts had run, which is why `anon`/`authenticated`/`service_role` existed — **their presence is not evidence `roles.sql` ran.** Remedy is `down -v` and re-init, never a bare redeploy. The materialize script now refuses to say "redeploy" while a `db-data` volume exists. Runbook §4 (1c).

### §5d — Second deploy: `api-gw` collided with Coolify's own dashboard

`Bind for 0.0.0.0:8000 failed: port is already allocated`. Upstream's compose publishes `api-gw` on host `8000`; so does Coolify. The gateway never started.

Probing then found the quieter half: `supavisor` had come up bound to `0.0.0.0:5432` and `0.0.0.0:6543` — a multi-tenant Postgres's wire protocol and pooler proxy on the public interface, unreachable only because the cloud firewall happened to filter those ports.

**Sec ruled (2026-09-10): VETO — all three published mappings removed, `expose:`-only, not a `127.0.0.1` bind.** The cloud firewall stays primary but is not acceptable alone; the second layer is de-publishing, not `ufw` (Docker's `DOCKER` nat chain DNATs published ports from `0.0.0.0/0`, so a `ufw` rule sits in a chain those packets never traverse — a control that reads as protection and provides none). A CI fence is required, on the CI-fenced side only, with its own script and sentinel rather than RT-27's. Runbook §4 (1d), PR #707.

⚠ **Do not "fix" a future collision by repointing `${POSTGRES_PORT}`** — that variable feeds five internal DSNs. Delete mapping lines; leave the variable alone.

### §5e — `auto_deploy=true` is inert without a webhook

The resource reads `auto_deploy=true`, so merging to `main` was expected to deploy. It queued nothing and started nothing. No GitHub webhook is configured (ARCH §6 item (f), deliberately deferred), so nothing tells Coolify a push happened. **The setting reads as a live trigger to anyone who does not know the webhook is missing.** Deploys must be triggered explicitly. Runbook §4.

### §5f — `rest` is unhealthy until §6, and that is correct

PostgREST reports `Up (unhealthy)` with `schema "pfin" does not exist`. `PGRST_DB_SCHEMAS=pfin` is right; the `pfin` schema is created by migrations, which run at **step 6**. It retries with backoff and clears itself once they land. A real failure would be a different error code, or still-unhealthy *after* §6.

This is the third instance of one pattern: **runbook §4's verifications assume a post-§6 world.** The other two are §4.1's TimeZone read-back (asserts migration `061`) and §5's Sec gate appearing to block §4 (Sec ruled it does not — the boundary is minting vs. app-facing injection).

### §5g — Reopened: `studio` back IN

Runbook line 322 carried `studio` as **OUT by default, "unless F/CTO names a concrete reason to keep it."** F/CTO named it 2026-09-10: the Supabase dashboard should be reachable the same way Coolify's is — **by SSH tunnel**, not a public Domain. `meta` comes with it by line 321's rule; Studio has no other data source. Sec has the exposure ruling; the mechanics are not obvious, because `expose:`-only leaves `ssh -L` no stable `localhost` target and container IPs move across redeploys.

**Migrations have NOT been applied to production.** Nothing has run `supabase db push` against `188.245.166.206`.

---

## Departures from plan

*Every place reality and the plan disagreed. Empty until the first one — and an empty section here is a claim, so do not leave a real departure out of it.*

| Date | Step | Expected | Actual | Runbook corrected? |
|---|---|---|---|---|
| 2026-09-08 | 7 | Adopt F/CTO's 9 existing Plaid Items | Old Plaid team deleted; its Items were already orphaned with tokens lost. Step struck; replaced by the step 8 attach-at-Link build against a fresh 10-Item Trial team. | n/a — plan record updated |
| 2026-09-09 | 3 | Follow runbook §1/§3 | Both sections were STUBs; no procedure existed to follow. | ✅ Authored, PR #684 |
| 2026-09-09 | 3 | Provision once, cleanly | First box carried only a passphrase-protected key — correct in every other respect and unreachable by automation. Destroyed and recreated with both keys. | ✅ Script now validates key usability and refuses to provision without an automation-usable key |
| 2026-09-09 | 3 | Script runs clean | Five bugs, each found only by running against the live API: shell brace expansion mangled the SSH-key JSON; an unassigned primary IP is created against a `location`, not a `datacenter`; `public_net` takes `ipv4:<id>` while `enable_ipv4` is a bool; key lookup must be by **fingerprint** (Hetzner 409s on duplicate material whatever you name it); and the server delete returns **before** the primary IP detaches, so creating into that window 422s with nothing about timing. | ✅ All five fixed; the race now waits and refuses rather than creating into it |
| 2026-09-09 | 3 | `adduser deploy` per runbook §1 step 3 | Created with `--disabled-password` to avoid an interactive prompt, which left the account unable to authenticate to `sudo` at all. | ✅ `NOPASSWD` granted; reasoning recorded at §3c — the same keys already grant direct root |
| 2026-09-09 | 3 | The primary IP preserves the box's addresses across a rebuild | It preserved **IPv4 only**. Hetzner creates the IPv6 primary IP with `auto_delete=true`, so the rebuild silently changed the `/64`. Caught only because F/CTO pasted the box's login banner and it disagreed with this record. | ✅ IPv6 flipped to persistent; the script now enforces it every run |
| 2026-09-09 | 3 | Verify ports from outside | First probe reported **every** port filtered, including 22, seconds after SSH had succeeded on 22. The instrument was broken, not the box. | n/a — re-probed by TCP behaviour |
| 2026-09-10 | 5 | 38 env vars set via per-key POST | Coolify had already created all 44 keys when it parsed the compose, so every create collided and no-opped; responses were discarded rather than checked. Values read back empty. | n/a — `PATCH .../envs/bulk` used instead |
| 2026-09-10 | 5 | Relative bind mounts resolve against `base_directory` | Coolify's parser discards `base_directory`, does not copy the clone to the host path, and pre-creates all 12 file-shaped mounts as empty directories (`is_directory=true` by default on first parse). Deploy failed loudly. | ✅ §4 (1c) + `scripts/coolify-materialize-supabase-mounts.sh` |
| 2026-09-10 | 5 | Two-flag volume mode `:ro,z` parses | Coolify bled the flags into `mount_path` itself. Single-flag forms parse cleanly. | ✅ `:z` dropped at source (no SELinux on this box) |
| 2026-09-10 | 5 | Fixing the mounts is enough | The failed deploy had already started Postgres against the empty mounts, consuming its one-shot init. Container reported **healthy** with NULL service-role passwords and no `jwt_secret`. Volume had to be destroyed. | ✅ §4 (1c); script now refuses to suggest a bare redeploy while `db-data` exists |
| 2026-09-10 | 5 | Upstream's `ports:` mappings are safe to carry over | `api-gw` collided with Coolify's own dashboard on host `8000`; `supavisor` published a multi-tenant Postgres on `0.0.0.0:5432`/`6543`, filtered only by the cloud firewall. | ✅ Sec VETO — all three removed, `expose:`-only. §4 (1d), PR #707 |
| 2026-09-10 | 5 | `auto_deploy=true` deploys on merge | Queued nothing. Inert without a GitHub webhook, which is deliberately not configured. Reads as a live trigger to anyone who does not know. | ✅ §4 — explicit manual trigger documented |
| 2026-09-10 | 5 | All services healthy after a good deploy | `rest` is `unhealthy` because schema `pfin` does not exist until step 6's migrations. Correct behaviour, not a fault. Third instance of §4's checks assuming a post-§6 world. | 🟡 Flagged; structural fix outstanding |
| 2026-09-10 | 5 | Container names come from the compose | Coolify overrides every `container_name`. Verification commands addressing `supabase-db` / `supabase-envoy` would have read as mount failures. | ✅ §4 (1b) uses `docker compose --project-name <uuid> logs <service>`, PR #704 |
