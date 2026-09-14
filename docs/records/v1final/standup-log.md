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
| 6 | Deploy the four services from one `main` sha | DevOps | 🟡 **Phase A DONE 2026-09-14** (`APP_UUID`, migrator Scheduled Task, `migrator` container confirmed `Up`, `supabase-go` + `templates/` confirmed present on `main` `0fe09afa`); Phase B step 4 ⛔ **blocked**, 4th attempt — CLI refuses to connect to `db` (`tls error (server refused TLS connection)`), reported to Sec per standing condition, NOT auto-fixed |
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

### §5h — 2026-09-14 retrospective: what did the unquoted-heredoc bug drop from the `ANON_KEY`/`SERVICE_ROLE_KEY` mint?

Booked by BACKLOG.md §7.36 item 23 (Sec's execution gate on `mint-supabase-jwt-keys.sh`, PR #754 at `6c5128b0`/`bc8fc661`): identify the exact committed sha that produced the live production `ANON_KEY`/`SERVICE_ROLE_KEY`, and what — if anything — the unquoted-heredoc bug (the same mechanism as #754's item 19, present in this script's ~:395 heredoc since it was authored) dropped from that run.

**Finding: no recorded live `--apply` execution of `mint-supabase-jwt-keys.sh` exists in this repo. Nothing to have dropped anything from — measured, not assumed.**

- This section's own line above (`Secrets. 8 minted...`) and the table above it record only `provision-supabase-stack.sh`'s initial mint — deliberately inert `secrets.token_hex(32)` placeholder hex for `ANON_KEY`/`SERVICE_ROLE_KEY`, landed at `main` `af2c1696`, 2026-09-10. That is a different script and a different (unaffected) heredoc.
- PR #731 (merged `c73cfdbd`, 2026-09-10T22:35:59Z, added `mint-supabase-jwt-keys.sh`): its own body states "Prep only — this PR does not touch prod" and lists the live SSH/Coolify-API mint path, the `tinker`-based decrypt assertion, and `--verify-live` as explicitly **not tested** ("no live box").
- PR #734 (merged `aa051afd`, 2026-09-11T00:12:11Z, fixed the uuid-by-name resolution + argv-token leak): test plan explicitly checks "Not run: `--apply` against the real box/prod (prod is mid-rebuild ... prep-only ... for team-lead/Sec to run once approved)."
- PR #736 (merged `91c63a18`, fixed the `--verify-live` stdin-drain bug and added the redeploy-after-mint step): ran the **read-only verify probes** live against `188.245.166.206` (uuid `nz7mbexygw9lesjlazcxeltn`) and read back both keys via the tinker decrypt path (never printed) to confirm they were already JWT-shaped at that point — but its own "Validation performed" section states **"Not run: the live `--apply` / `--apply --verify-live` acceptance pass against prod — blocked by the agent tool boundary,"** and explicitly hands that one step to F/CTO ("please run the live `--apply --verify-live` acceptance pass ... that's the only step this PR could not itself execute").
- No later PR, and no other section of this file, records that F/CTO acceptance run happening, its result, or which committed sha was live at the time. `grep`-checked: `mint-supabase-jwt-keys`, `ANON_KEY`, `SERVICE_ROLE_KEY`, `verify-live`, `JWT-shaped`, and `VERIFIED` appear nowhere else in this file.

**Reading this correctly:** PR #736's own verify-probe run found the keys *already* JWT-shaped and passing all four gateway probes before that PR's `--apply` fix even existed — meaning *some* mint had already succeeded by then (consistent with a manual F/CTO `--apply` run per PR #731/#734's hand-off, just not logged here). The retrospective cannot identify that run's exact sha because it left no record in this repo — only that it must have been at or before `main`'s state when PR #736's live probes ran. Whether the unquoted-heredoc bug corrupted anything in that specific unlogged run is **unknowable from repo evidence** — not "nothing dropped," but "no measurement exists to check." **Measured, and it narrows the unknown:** the one live run this repo does record — PR #736's `--verify-live` probes — executes the `REMOTE2` heredoc, which also carried the unquoted delimiter. At `381c2b4c` that heredoc's body contains **zero** backtick characters (the `--apply`-only `:395` body contains three), so that run had no backtick span to delete and nothing could have been dropped from it. The deletion risk was confined to the `--apply` path, and no `--apply` run is recorded.

**Action taken:** the fix (this PR) closes the bug going forward regardless of whether the gap above is ever resolved. Separately flagged for F/CTO: whichever `--apply` run actually produced the live keys should be logged here after the fact if it's still reconstructable (Coolify's own audit log / deployment history for `nz7mbexygw9lesjlazcxeltn`, if retained) — this is an operator-log gap, not a code defect, and outside this PR's scope to fix.

---

## Step 6 — Apply migrations (migrator bring-up)

**2026-09-13/14 · DevOps · Phase A steps 1–3 DONE; Phase A migrator container BLOCKED; Phase B step 4 NOT YET RUN (blocked on the same thing).** Executed §6.5's Phase A/B ordering against the live box, per `docs/deployment-runbook.md` §6.5.

**Phase A.1 — V1 web-app Coolify resource.** Created via `POST /applications/public` (same endpoint/pattern `scripts/provision-supabase-stack.sh` already uses for the Supabase-stack resource; Coolify 4.3.18 rejects `/applications/private-github-app` for a public repo with no GitHub App installed — `/applications/public` is the correct endpoint, confirmed from the controller source, not guessed). New project `pfin-v1` (uuid `orbfcpdufhmmd5qotec8ogld`), environment `production` (uuid `6uqwvfiusyhd1vei9jbwnirv`, Coolify auto-created), application `pfin-app` — **`APP_UUID = nzfkslmj8cm6ba86bdizuvd8`**. `build_pack=dockerfile`, `base_directory=/api`, `ports_exposes=3000`, `health_check_path=/`, `instant_deploy=false` — matches §7.1's table. **Not deployed** (status `exited:unhealthy`, the resource's default never-deployed state) — correct per this step's own instruction; deploy is a later step. No Domain assigned (blocked on §2's DNS cutover, per §7.1).

**Phase A.2 — migrator Scheduled Task.** `POST /applications/{migrator-service-uuid}/scheduled-tasks` **exists** in Coolify 4.3.18's API (`routes/api.php`: `ScheduledTasksController::create_scheduled_task_by_application_uuid`) — confirmed by reading the route table and controller source directly on the box, not assumed. Created against the Supabase-stack application (the `migrator` service's parent — **`MIGRATOR_SERVICE_UUID = nz7mbexygw9lesjlazcxeltn`**), fields per `scripts/migrator-scheduled-task.md`: name `migrator-db-push`, container `migrator`, command `supabase db push --db-url "$PROD_DB_URL" --workdir /workspace`. **`MIGRATOR_TASK_UUID = y6wn3s9yjqqg8tuchd0i3k6w`**.

⚠ **Departure, corrected in this PR:** the runbook's inert-cron trick (`0 0 31 2 *`, betting on Feb 31 never occurring) is **rejected by this Coolify version's own cron validator** — measured live via `artisan tinker`: `validate_cron_expression('0 0 31 2 *')` → `false` (it checks the date is real, not just syntactically shaped); `'0 0 1 1 *'` and `'@yearly'` → `true`. The create call 422'd on first attempt. Used `frequency: "0 0 1 1 *"` + **`enabled: false`** instead — source-verified sufficient: `app/Jobs/ScheduledJobManager.php`'s `scheduledTaskQuery()` selects tasks with `->where('enabled', true)` (the production timer path; `app/Console/Commands/ScheduledJobDiagnostics.php` carries the same filter but is a diagnostics-only artisan command and is not load-bearing), and the explicit `.../execute` call (the actual trigger path, per ADR-072 Decision 2) addresses the task by UUID without consulting that flag or the `enabled` column at all. `scripts/migrator-scheduled-task.md` corrected in place.

**Phase A.3 — redeploy so `migrator` comes up.** `BOX_IP=188.245.166.206 scripts/provision-supabase-stack.sh --apply` run from this branch's worktree. Preflight matched the live resource; secrets step succeeded — **`MIGRATOR_DB_PASSWORD` and `MIGRATOR_DB_USER` minted and confirmed present by name** in the stack's env store (script's own assert-non-empty pass: `MIGRATOR_DB_USER: OK` / `MIGRATOR_DB_PASSWORD: OK`, alongside all other required keys). The script's `db-data`-exists guard fired (expected — this stack has been live since Step 5); independently verified the volume is the good one, not poisoned, before proceeding past the guard by hand: `authenticator`/`pgbouncer`/`supabase_auth_admin` all show `SET` in `pg_shadow`, and `current_setting('app.settings.jwt_secret')` returns a non-empty value. Triggered the deploy directly (`POST /api/v1/deploy?uuid=<supabase-stack-uuid>`, the same explicit-trigger mechanism §4 already documents for this resource).

⚠ **Deploy FAILED — a real compose bug, not a flake.** The `migrator` service's `build.context: .` in `infra/supabase/docker-compose.yml` resolves relative to that compose file's own directory. Coolify clones the **full repo**, then runs `docker compose --project-directory <clone>/infra/supabase`, so `context: .` landed on `infra/supabase/` — which has no `supabase/` subdirectory of its own. The Dockerfile's `COPY supabase/config.toml supabase/config.toml` / `COPY supabase/migrations/ supabase/migrations/` steps need the repo's **top-level** `supabase/` (Architect-authored migrations), two levels up. Measured failure: `failed to calculate checksum of ref ...: "/supabase/migrations": not found`. **Fixed** — `context: ../..` (repo root), `dockerfile: infra/supabase/migrator/Dockerfile` (path now relative to the new context) — committed on this branch (`cecbd3b`), **not yet on `main`**.

**Existing stack containers were unaffected by the failed deploy** — verified all seven (`api-gw`/`auth`/`db`/`meta`/`rest`/`studio`/`supavisor`) still `Up ... (healthy)` afterward; Coolify's build-then-swap sequencing means a build failure never touches the running set.

**Why this stops here.** The fix lives only on `feat/standup-step6-migrator-bringup` — this task's own scope explicitly keeps that PR unmerged until later phases, and production deploys off a non-`main` branch are correctly outside this role's lane (attempting to point the live resource's `git_branch` at the fix branch, even temporarily, to unblock testing, was refused by the session's own auto-mode guardrail — treated as the right call, not worked around). **The `migrator` container cannot come up, and Phase B step 4's bootstrap apply has no reachable vehicle (no other container on the box bundles the `supabase` CLI + baked migrations), until this fix reaches `main` and the stack is redeployed.** Both remain outstanding, blocking on F/CTO: merge this PR (or land the one-file fix ahead of it) → redeploy the Supabase-stack resource → re-attempt A.3's tail (confirm `migrator` container `Up`) → Phase B.4's bootstrap apply, using the `$PROD_DB_URL` construction now documented at runbook §6.

**Phase B step 4 — NOT RUN.** Blocked on the above. The exact command, and the §6.1/§6.2/§6.3 verify-block SQL for the interactive handoffs at Phase B step 5 (F/CTO's, unattempted, per this task's own stop-before boundary), are in the hand-off below.

### Phase B.4 — bootstrap apply attempt, 2026-09-14

**A.3's tail — DONE.** PR #752 merged to `main` at `2107f7e7`. Confirmed `git_branch=main` on the Supabase-stack resource (unchanged — the earlier off-branch test attempt was refused and never applied). Redeployed explicitly (`POST /api/v1/deploy?uuid=nz7mbexygw9lesjlazcxeltn`, deployment `gvvsdh0dw2mnehmchvx3efck`) — `finished`. All eight services present and running: `api-gw`/`auth`/`db`/`meta`/`rest`/`studio`/`supavisor` `healthy`, **`migrator` `Up`** (no healthcheck defined — Pattern-A `tail -f /dev/null`, matches `etl`/`provider-sync` convention). Confirmed `pfin`/`supabase_migrations` schemas do not yet exist (migrations not yet applied).

⚠ **Note:** `rest` reported `healthy` (`docker inspect .State.Health.Status`) almost immediately after this redeploy, before any migration had run — earlier in this log (§5f) `rest` was recorded unhealthy until the `pfin` schema exists. **⚠ Treat this as evidence against §5f's stated cause, not around it:** §5f asserts `PGRST_DB_SCHEMAS=pfin`, while `scripts/provision-supabase-stack.sh:622`'s `NONSECRET_DEFAULTS` sets `public,graphql_public` — `pfin` absent. That block is check-if-absent, so the live value could have been set by hand and differ. **Resolved by direct measurement (Sec joint-review PR #753 C-1, taken 2026-09-14):** both the live Coolify env-store value (`php artisan tinker`, `Application::environment_variables()->where('key','PGRST_DB_SCHEMAS')`) and the running `rest` container's actual env (`docker compose exec -T rest printenv PGRST_DB_SCHEMAS`) read **`public,graphql_public`** — `pfin` is absent on both. **What follows:** §5f's stated cause, this file's own Departures row for it, runbook `:484`'s `PGRST_DB_SCHEMAS=pfin` claim, and `provision-supabase-stack.sh:849-854`'s "expected unhealthy" branch all rest on a false premise as currently deployed — `rest` was healthy here because it never needed `pfin` at all, not because the schema race resolved. None of those four are corrected in this PR (Sec-booked reconciliation, `BACKLOG.md` §7.36) except a one-line flag added at runbook `:484`.

**Phase B step 4 — attempted, BLOCKED on a second real bug.** Ran the exact stdin-piped bootstrap form now documented at runbook §6 (`set -a; . /root/.pfin/supabase.env; set +a` then `printf '%s' "$POSTGRES_PASSWORD" | docker compose ... exec -T migrator sh -c 'IFS= read -r PGPW; supabase db push --db-url "postgres://postgres:${PGPW}@db:5432/postgres" --workdir /workspace'`). Failed:

```
Could not find the `supabase-go` binary.
The Supabase CLI ships as two co-located binaries: `supabase` (this shim)
and `supabase-go` (the Go CLI that the shim forwards to)...
```

**Root cause, measured:** the pinned CLI release tarball (`supabase_linux_arm64.tar.gz`, v2.107.0) contains **two** binaries — confirmed by downloading and listing it (`tar -tzf`): `supabase` and `supabase-go`. `infra/supabase/migrator/Dockerfile`'s extraction step took only `supabase`; `supabase --version` (the build-time self-check) doesn't need the companion and passed, masking the gap until a DB-affecting subcommand (`db push`) was actually run. CI's `.github/actions/supabase-cli-setup` is unaffected — it uses the official `supabase/setup-cli@v2` action, not a manual tarball extraction, so this is isolated to the migrator image.

**Fixed** — Dockerfile now extracts and `chmod`s both `supabase` and `supabase-go` — committed on `feat/standup-step6-phase-b` (`94a8b1f`), **not yet on `main`**. Same shape as the build-context blocker in Phase A.3: fixing it requires a merge, which is out of this step's scope; deploying off a non-`main` branch to test is correctly outside this role's lane per the same guardrail that held before.

**Phase B step 4 remains NOT RUN.** Blocked on `94a8b1f` (or equivalent) landing on `main` and a redeploy. `schema_migrations` head-row/count, `pfin` schema existence, role `rolcanlogin` checks, and `rest`'s post-migration health could not be confirmed this pass — for reference, `main` currently carries **118** migration files (`ls supabase/migrations/*.sql | wc -l`), so a clean apply's expected `schema_migrations` row count is 118 with head version `118`.

### Phase B.4 — bootstrap apply, second attempt, 2026-09-14

PR #753 merged to `main` at `4774189d`. Redeployed explicitly (deployment `u4xbmfivokrlumjicdgnlxgf`) — `finished`. All 8 services present; **`docker compose exec -T migrator test -x /usr/local/bin/supabase-go` confirmed present and executable** — the prior blocker is closed.

**Ran the bootstrap apply again, exact form.** Failed on a **third** real bug:

```
Invalid config for auth.email.template.magic_link.content_path: open supabase/templates/magic_link.html: no such file or directory
```

**Root cause, measured:** `supabase db push` validates `supabase/config.toml`'s **full** path set before running any command — including `[auth.email.template.*].content_path`, which `db push` never functionally reads. The migrator Dockerfile deliberately excluded `supabase/templates/` (prior comment: "can carry local-only interpolation this container must never see"). Reviewed the three referenced files (`confirmation.html`, `recovery.html`, `magic_link.html`, SELF-290/Auth-1) at fix time: all static, system-authored HTML using only GoTrue's own template vars (`{{ .ConfirmationURL }}`, `{{ .Token }}`) — no secrets, no environment-specific values. Safe to bake in.

**Fixed** — Dockerfile now `COPY`s `supabase/templates/` alongside `config.toml` — committed on `feat/standup-step6-phase-b4-apply` (`12e1831`), **not yet on `main`**. Same shape as the two prior blockers: unblocking requires a merge, out of this step's own scope to perform.

**Phase B step 4 remains NOT RUN — third consecutive bootstrap-apply attempt blocked, each time on a bug invisible until the actual apply verb ran.** No migration file itself has been touched or is implicated in any of the three failures; none required Architect involvement. Verification checks (schema_migrations head/count, `pfin` schema, role `rolcanlogin` states, database-owner unchanged) remain unconfirmed pending the next merge + redeploy cycle.

### Phase B.4 — bootstrap apply, third attempt, 2026-09-14

PR #755 merged to `main` at `0fe09afa`. Redeployed explicitly (deployment `g0zncjes0dhmx13oy6sr5miv`) — `finished`. All 8 services present. **Confirmed both prior fixes live**: `docker compose exec -T migrator test -x /usr/local/bin/supabase-go` → present; `docker compose exec -T migrator sh -c "ls supabase/templates/"` → `confirmation.html` / `magic_link.html` / `recovery.html` present.

**Ran the bootstrap apply again, exact form.** Failed on a **fourth**, categorically different bug — this time before any migration or config-validation step, at the connection itself:

```
Connecting to remote database...
failed to connect to postgres: failed to connect to `host=db user=postgres database=postgres`: tls error (server refused TLS connection)
```

**Stopped here, per this task's explicit instruction: a CLI failure before connecting, for a new reason, is not something to fix unilaterally — reported for Sec to see before the next migrator PR, rather than patched blind.** No migration file was touched, reached, or implicated. Confirmed no state changed: `select schema_name from information_schema.schemata where schema_name in ('pfin','supabase_migrations')` on `db` returns **zero rows**, same as before this attempt.

**Not diagnosed further here, named for whoever picks this up:** the Supabase CLI's Go driver (`supabase-go`, per PR #753) appears to default to or prefer a TLS connection, and `db` (this self-hosted stack's Postgres) is not configured to offer TLS on its internal-network socket — consistent with every other worker (`pfin_etl`, `pfin_provider_sync`) connecting to it in plaintext over the same Docker network without issue. The shim-based CLI (pre-#753, the version that never got far enough to hit this) may have used a different underlying driver/negotiation path that didn't hit this; not verified. Candidate fixes, **not evaluated or chosen here**: an explicit `sslmode=disable` (or `?sslmode=disable`) on the `--db-url`, a CLI flag, or a driver-level default change — Sec should see whichever is proposed before it lands, per this task's own condition.

**Read-only measurements taken for Sec (no config changed, no retry of the push):**

- **(a) `db`'s own TLS posture, measured directly:** `exec -T db psql -U postgres -d postgres -Atc "show ssl;"` → `off`. `show ssl_cert_file;` → empty (no cert configured). `db` genuinely offers no TLS — the earlier "server refused TLS connection" is consistent with this, not a probe artifact.
- **(b) No `sslmode` anywhere in the URL construction or config.** `infra/supabase/docker-compose.yml:322`'s `PROD_DB_URL` (the container's own steady-state value, built from `${MIGRATOR_DB_USER}:${MIGRATOR_DB_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}`) carries no `sslmode` parameter. `supabase/config.toml` has no active `[db.ssl_enforcement]` block (present only as a commented-out stanza at line 89). Neither the runbook §6 bootstrap form nor the container's baked value sets `PGSSLMODE` or any CLI sslmode flag.
- **(c) The other in-network consumers set no SSL-related env at all.** `docker compose exec -T {rest,auth,supavisor} env`, filtered to variable **names** only (`grep -ioE '^[A-Z_]*(SSL|PGSSL)[A-Z_]*='`) — zero matches in all three. Source-confirmed too: `infra/supabase/docker-compose.yml:167` (`GOTRUE_DB_DATABASE_URL`) and `:208` (`PGRST_DB_URI`) are both bare `postgres://…` with no `sslmode`. Every existing in-network consumer relies on whatever the default negotiation behavior is, and none of them hit this failure — only the newly-added Go-driver CLI does.
- **(d) The compiled `supabase-go` binary itself contains the literal string `sslmode=require`** — measured via `grep -a -o` against `/usr/local/bin/supabase-go` inside the `migrator` container (bounded pattern match against the six valid pgx sslmode values, to rule out a truncated/spurious match). **Not conclusively traced to the exact `db push` code path in the v2.107.0 source** (shallow-cloned `github.com/supabase/cli` at that tag for this check): the only Go-source occurrences of `sslmode=require` are in `apps/cli-go/internal/gen/types/{types.go,pgdelta_conn.go}` — the `gen types` command, unrelated to `db push`. The underlying Postgres driver (`jackc/pgx/v5`)'s own documented default is `sslmode=prefer`, not `require` (`pgconn/config.go` lines 631-632, fetched from `github.com/jackc/pgx` tag `v5.5.5`) — `prefer` should fall back to plaintext on a TLS refusal rather than hard-fail, so something in `db push`'s specific connection path is overriding that default to `require`, but the exact line was not found in the time spent. **Citing what was measured, not guessing past it.**

⚠ **Credential-hygiene note, disclosed rather than repeated:** the first attempt at measurement (c) used an unfiltered `docker compose exec -T migrator env`, which printed `PROD_DB_URL` — including the live `MIGRATOR_DB_PASSWORD` in cleartext — into this session's own tool output. Every subsequent check in this measurement set was redone with a names-only filter (`grep -ioE '^[A-Z_]*(SSL|PGSSL)[A-Z_]*='`) specifically to avoid repeating this. The value itself is not written anywhere in this repo or record. Flagged for F/CTO/Sec to judge whether `MIGRATOR_DB_PASSWORD` warrants rotation given it surfaced in an agent session transcript.

**Phase B step 4 remains NOT RUN — fourth consecutive bootstrap-apply attempt blocked, first time NOT fixed same-session.** Verification checks remain unconfirmed.

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
| 2026-09-10 | 3 | The runbook's §3 install instructions call for browsing to `http://<box-ip>:8000` (over the tunnel) to complete Coolify's first-run admin registration | Reconstructed with F/CTO: this was the **only** human/browser step in the entire stand-up — every other step, before and since, was executed by an agent over SSH or the API. It was manufactured, not load-bearing: the runbook transcribed the installer's own printed instruction without asking whether a browser was actually required. It is not — `database/seeders/RootUserSeeder.php`, read directly on the box, is Coolify's own official non-interactive first-user bootstrap (env-var driven, idempotent by construction), and a Sanctum API token is mintable the same way via `php artisan tinker`. | ✅ `scripts/provision-vps.sh --apply` now runs the seeder + mints the token on the box; §3's browser-registration instruction deleted, not softened |
| 2026-09-10 | 5 | 38 env vars set via per-key POST | Coolify had already created all 44 keys when it parsed the compose, so every create collided and no-opped; responses were discarded rather than checked. Values read back empty. | n/a — `PATCH .../envs/bulk` used instead |
| 2026-09-10 | 5 | Relative bind mounts resolve against `base_directory` | Coolify's parser discards `base_directory`, does not copy the clone to the host path, and pre-creates all 12 file-shaped mounts as empty directories (`is_directory=true` by default on first parse). Deploy failed loudly. | ✅ §4 (1c) + `scripts/coolify-materialize-supabase-mounts.sh` |
| 2026-09-10 | 5 | Two-flag volume mode `:ro,z` parses | Coolify bled the flags into `mount_path` itself. Single-flag forms parse cleanly. | ✅ `:z` dropped at source (no SELinux on this box) |
| 2026-09-10 | 5 | Fixing the mounts is enough | The failed deploy had already started Postgres against the empty mounts, consuming its one-shot init. Container reported **healthy** with NULL service-role passwords and no `jwt_secret`. Volume had to be destroyed. | ✅ §4 (1c); script now refuses to suggest a bare redeploy while `db-data` exists |
| 2026-09-10 | 5 | Upstream's `ports:` mappings are safe to carry over | `api-gw` collided with Coolify's own dashboard on host `8000`; `supavisor` published a multi-tenant Postgres on `0.0.0.0:5432`/`6543`, filtered only by the cloud firewall. | ✅ Sec VETO — all three removed, `expose:`-only. §4 (1d), PR #707 |
| 2026-09-10 | 5 | `auto_deploy=true` deploys on merge | Queued nothing. Inert without a GitHub webhook, which is deliberately not configured. Reads as a live trigger to anyone who does not know. | ✅ §4 — explicit manual trigger documented |
| 2026-09-10 | 5 | All services healthy after a good deploy | `rest` is `unhealthy` because schema `pfin` does not exist until step 6's migrations. Correct behaviour, not a fault. Third instance of §4's checks assuming a post-§6 world. | 🟡 Flagged; structural fix outstanding |
| 2026-09-10 | 5 | Container names come from the compose | Coolify overrides every `container_name`. Verification commands addressing `supabase-db` / `supabase-envoy` would have read as mount failures. | ✅ §4 (1b) uses `docker compose --project-name <uuid> logs <service>`, PR #704 |
| 2026-09-13 | 6 | `scripts/migrator-scheduled-task.md`'s inert far-future cron (`0 0 31 2 *`) is accepted by Coolify's create-task API | Rejected, 422, `"Invalid cron expression or frequency format."` — Coolify 4.3.18's validator checks the date is a real calendar date, not just syntactically well-formed (measured via `artisan tinker`: `validate_cron_expression('0 0 31 2 *')` → `false`). | ✅ `enabled: false` used instead (source-verified: the automatic scheduler's own selection query filters on it; the explicit `.../execute` trigger path does not) — `scripts/migrator-scheduled-task.md` corrected in place |
| 2026-09-13 | 6 | `infra/supabase/docker-compose.yml`'s `migrator` service builds with `context: .` | Failed live: Coolify clones the full repo but runs compose with `--project-directory <clone>/infra/supabase`, so `context: .` resolved to `infra/supabase/` — no `supabase/` subdirectory there for the Dockerfile's `COPY supabase/migrations/` to find. `failed to calculate checksum ...: "/supabase/migrations": not found`. | ✅ Fixed (`context: ../..`, repo root), merged to `main` at `2107f7e7` (PR #752); redeploy confirmed `migrator` container `Up` |
| 2026-09-13 | 6 | `$PROD_DB_URL` is a defined shell variable somewhere an operator can read it | §4/§6 use it throughout with no definition. Only the `migrator` container's own baked env defines it, and only with the `migrator` role's credential — not usable for the first bootstrap apply, which must run as `postgres` before that role exists. | ✅ Runbook §6 now defines both forms (container steady-state vs. `postgres`-override bootstrap via `docker compose exec migrator`) |
| 2026-09-14 | 6 | The pinned Supabase CLI (v2.107.0) release tarball is self-contained — `supabase --version` succeeding at build time proves `supabase db push` will work at runtime | `supabase db push` failed: `Could not find the `supabase-go` binary`. The tarball ships two binaries (`supabase` + `supabase-go`, confirmed via `tar -tzf`); the CLI shim forwards DB-affecting subcommands to the co-located Go binary, which `--version` doesn't need. `infra/supabase/migrator/Dockerfile`'s extraction step took only `supabase`. | ✅ Fixed (`94a8b1f`, extracts+chmods both binaries), merged to `main` at `4774189d` (PR #753); confirmed `supabase-go` present post-redeploy |
| 2026-09-14 | 6 | `supabase db push` only needs `config.toml` + `migrations/**` — the migrator Dockerfile's own comment asserted `templates/` "is never read" by `db push` | `supabase db push` failed: `Invalid config for auth.email.template.magic_link.content_path: open supabase/templates/magic_link.html: no such file or directory`. The CLI validates config.toml's FULL path set before running any command, not just the paths the invoked verb touches — `db push` never functionally uses email templates, but still fails if their declared paths don't resolve. | ✅ Fixed (`12e1831`, baked in the 3 reviewed templates), merged to `main` at `0fe09afa` (PR #755); confirmed present post-redeploy |
| 2026-09-14 | 6 | The `db` service accepts a plain (non-TLS) `postgres://` connection from a sibling container on the same Docker network, matching every other worker's direct-connect pattern (`pfin_etl`/`pfin_provider_sync`) | `supabase db push --db-url "postgres://postgres:<pw>@db:5432/postgres"` failed before touching any migration: `failed to connect to postgres: failed to connect to \`host=db user=postgres database=postgres\`: tls error (server refused TLS connection)`. The Supabase CLI's Go driver apparently prefers/requires TLS by default and `db` isn't configured to offer it. **Stopped per this task's own instruction — a fourth packaging-class defect, not fixed here; reported for Sec to see before the next migrator PR (BACKLOG §7.36 item 21 condition).** | ⛔ Not fixed — booked, see BACKLOG §7.36 (item 26; renumbered from 23 to avoid collision with PR #756's items 23–25) |
