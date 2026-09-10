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

Scope: accounts, CLI tooling, and the domain you need in hand before starting. Split by who obtains it — F/CTO-only items gate the box; DevOps-preparable items can happen ahead of time.

**F/CTO-only** (credentials only the account owner can create or hold — never handled by an agent, never placed in the repo):

| Item | What it's for |
|---|---|
| **Hetzner Cloud account + payment method** | Owns the billing relationship for the VPS provisioned in §1. |
| **Hetzner Cloud API token** (or console access, if provisioning by hand through the web console instead of the API) | Creates the CAX21 server. A token is only needed if §1 is scripted via the Hetzner API/CLI; console-driven provisioning needs only login access. Either way, this credential never enters the repo or a Coolify env var — it is used once, at provisioning time, from F/CTO's own machine or the Hetzner console. |
| **Domain registrar access** for the eventual production hostname | §2 (DNS) is an open F/CTO decision (reuse `pfindash.com` vs. a new domain) — out of scope for this PR, but registrar access is F/CTO-only regardless of which way that decision goes. |
| **An SSH keypair F/CTO controls** | The key whose **public** half is installed on the box at creation (§1) for key-only root/operator access. The private half never leaves F/CTO's machine; it is not a repo artifact. |
| **Production secret values** — `SUPABASE_SERVICE_ROLE_KEY`, `PLAID_CLIENT_ID`/`PLAID_SECRET`, etc. (names only, per [`secrets-manifest.yml`](../secrets-manifest.yml) `production_only`) | Entered directly into Coolify's UI at §5 (STUB, not this PR). Never transit chat, a file, or an agent's context. |

**DevOps-preparable** (no F/CTO-only credential required to produce these; can happen before the box exists):

| Item | What it's for |
|---|---|
| This runbook's §1/§3 procedures (this PR) | The executable steps F/CTO runs once the F/CTO-only items above are in hand. |
| Coolify itself | No separate account or license needed — Coolify is **self-hosted**, installed by the §3 script directly onto the box F/CTO provisions in §1. Its own admin account is created during §3's first-run setup (F/CTO does this, since it's the account that then holds every other secret — noted again at §3). |
| Supabase CLI (`supabase`) | Only needed locally/in CI for authoring and dry-running migrations (§6) — not required to provision the box or install Coolify. Not a §1/§3 prerequisite. |
| GitHub repo access for Coolify's source connection (§3) | An existing asset — this repo, on GitHub, with F/CTO's account already having admin access. §3 documents connecting Coolify to it as a step, not a new account to obtain. |

**Not yet enumerable — deferred to their owning sections:** exact secret values (§5, STUB), the DNS registrar's specific hostname (§2, open F/CTO decision), and the Coolify admin credentials themselves (created live during §3, not pre-obtained).

---

## 1. Provision the VPS

Scope: stand up a fresh virtual server to host Coolify + all V1 containers.

- **RULED 2026-09-08 (F/CTO): Option A — a new Hetzner CAX21 box.** Corrected spec, read from Hetzner's own product page/search results the same day: **CAX21 = 4 ARM vCPU / 8 GB RAM / 80 GB NVMe disk, Germany; price unverified** (Hetzner's pricing page did not render a figure to a direct fetch on 2026-09-08 — do not carry forward the €9.50/mo figure without re-reading it live). The previously-recorded "8 ARM vCores / 16 GB RAM / 160 GB disk, ~€9.50/mo" figure was **CAX31's** spec, misattributed to cax21 throughout the tree (a one-tier shift) — see `docs/records/v1final/production-standup.md` §5 for the sizing evidence supporting this class.
- The new box is provisioned clean — fresh OS, no carried-over state from the incumbent cax21 box (whose own actual tier is itself unestablished from anything in this tree — it is referenced by name only, never read back from a live console).

**Region: Falkenstein (`fsn1`), fall back to Helsinki (`hel1`) if capacity-constrained.** Reason, stated: `production-standup.md` §5 finding #9 recorded that a direct fetch of Hetzner's cost-optimized pricing page on 2026-09-08 showed CAX21 as *"currently unavailable"*, unresolved as to whether that was a real regional stock-out or a rendering artifact of the fetch tool. `fsn1` and `hel1` are Hetzner's two ARM (CAX-line) locations; `fsn1` is Hetzner's original, highest-capacity datacenter and the documented default in Hetzner's own tooling, so it is the first thing to try. **Operator action, not a repo-side check:** at provisioning time, confirm CAX21 shows as orderable in `fsn1` in the live Hetzner console before creating the server; if it still reads unavailable, retry in `hel1` — do not reopen the Option A / class ruling over a regional availability blip.

**OS image: Ubuntu 24.04 LTS (arm64).** Coolify's own installation requirements (`coolify.io/docs/get-started/installation`, read 2026-09-09) list Debian-based distros — Ubuntu explicitly, any version, though "non-LTS requires manual installation" — among several supported families, alongside RedHat-based, SUSE-based, Arch, Alpine, and Raspberry Pi OS 64-bit. Ubuntu LTS is chosen over the alternatives for the longest support window on a box that is meant to run unattended for a production single-user deployment, and because it is the distro this tree's Docker images (`FROM node:...`, `FROM python:...` base images across the four Dockerfiles) are built and tested against elsewhere in CI. Confirm `arm64` at image-selection time in the Hetzner console — the CAX line is Ampere ARM only; an `amd64` image will not boot.

**Primary IPs — IPv4 and IPv6 both need to be persistent; they are not persistent the same way.** A Hetzner Primary IP created with `auto_delete=false` survives a server delete-and-recreate and re-attaches to the new box, so a rebuild does not force a DNS change. `scripts/provision-vps.sh` creates the **IPv4** primary IP this way explicitly — a named resource, `auto_delete=false`, created before the server. **IPv6 is different: Hetzner creates the IPv6 primary IP for you, automatically, at server-creation time, with `auto_delete=true`.** Unless something flips it, IPv6 dies with the first server it's attached to, and a rebuild silently hands out a different `/64` — the box otherwise comes up looking entirely correct. This happened once, 2026-09-09: the rebuild at step 3b below preserved IPv4 exactly as designed and silently changed the IPv6 `/64`, and it surfaced only because F/CTO pasted the box's SSH login banner into the session and its `IPv6 address for eth0` line disagreed with the record — **nothing in the provisioning or verification flow read IPv6 at all.** IPv6 primary IPs carry no additional charge (Hetzner's pricing feed lists a monthly price for `ipv4` only), so there was never a cost reason to leave it disposable. `scripts/provision-vps.sh` now reads the server's IPv6 primary IP on every run and flips it to `auto_delete=false` if it is still disposable — verified idempotent, a re-run reports it already persistent and changes nothing. **Do not treat IPv4's persistence as evidence IPv6 is also persistent — they are separate resources with different defaults; verify IPv6 explicitly (see the verification block below).**

**Initial hardening — concrete steps, in order:**

1. **SSH key-only from creation.** Create the server with the intended operator's SSH **public** key attached at Hetzner's server-creation step (cloud-init installs it to `~/.ssh/authorized_keys` for `root` before first boot) — never create the box with a password and harden after, which leaves a real window where a weak/default credential is live on the public internet. Coolify's own docs state the SSH key used for its server connection **"must not have a passphrase or 2FA enabled"** — that constraint is about the key Coolify itself uses to reach the box over SSH (§3), and does not weaken this step: the *key* still gates entry; only its own local unlock is passphrase-free so Coolify's automation can use it non-interactively.

   **Hetzner injects SSH keys only at server creation.** Adding a key in the Hetzner console does **nothing** to a running box — it only stores the key for a *future* server. There is no live-box "add a key" operation at all; the only way to add a machine's access after the fact is to `ssh-copy-id` its public key onto the box from a machine that already has access (to **both** `root` and `deploy` — they carry separate `authorized_keys`), and that path itself requires a machine that already has access. **If no machine has access — the box is genuinely locked out — recovery goes through Hetzner's browser console** (reset the root password there, log in, add a key; rescue mode is the heavier fallback). So the real single point of failure is **the Hetzner account**, not any one laptop holding a key — which relocates the risk to wherever that account's own login/2FA lives. This is not hypothetical: it is the same fact that forced a destroy-and-recreate of the first production box, 2026-09-09 (`docs/records/v1final/standup-log.md` §3b) — it had come up correct in every respect except that its only key was passphrase-protected, so automation could not log in, and there was no way to add a usable key to the running box short of rebuilding it.

   **Provision with at least two keys, and treat them as unequal.** `scripts/provision-vps.sh` installs two: a personal key (passphrase-protected — the file alone is useless without the passphrase, so it's reasonable to store in a password manager) and an automation key (passphrase-free by necessity, since a script has no terminal to unlock a passphrase into). **Whoever holds the automation key's private-key file has root on this box, full stop.** Do not copy that file between machines "for convenience" — generate a separate passphrase-free key per machine that needs automated access instead, so a compromised machine costs one key, not the one key.
2. **Disable password auth, then disable root login over SSH:**
   ```sh
   # /etc/ssh/sshd_config
   PasswordAuthentication no
   PubkeyAuthentication yes
   PermitRootLogin prohibit-password   # Coolify's own documented recommendation
   ```
   `prohibit-password` (not a flat `no`) is Coolify's own recommended setting, not an arbitrary choice — Coolify's server-connection step authenticates as `root` over key-based SSH by default, and a flat `PermitRootLogin no` would break that unless a non-root user with `sudo`/Docker-group access is wired into Coolify's connection config instead (a viable alternative — see the non-root note below — but not the default this runbook assumes).
3. **Create a non-root operator user**, with the same public keys copied to its `~/.ssh/authorized_keys`, for interactive/manual operator work (migrations, the §6.1/§6.2 credential handoffs, verification reads). This is **separate from** the identity Coolify itself connects as (step 2's `root`, per Coolify's default) — conflating the two is a real foot-gun: locking down `root` further "for safety" after Coolify is already configured to use it breaks Coolify's own deploy path.

   **Do not create it as `adduser deploy && usermod -aG sudo deploy`.** `adduser` alone prompts interactively for a password, which a script cannot answer; using `--disabled-password` to dodge that prompt instead leaves the account with **no password at all**, and an account with no password cannot authenticate to `sudo` either — `sudo: a password is required` for an account that has nothing to give. Use this instead:

   ```sh
   adduser --disabled-password --gecos "" deploy
   mkdir -p /home/deploy/.ssh
   cp ~/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
   chown -R deploy:deploy /home/deploy/.ssh
   chmod 700 /home/deploy/.ssh && chmod 600 /home/deploy/.ssh/authorized_keys
   printf 'deploy ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/90-deploy
   chmod 440 /etc/sudoers.d/90-deploy
   ```

   **The reasoning for `NOPASSWD`, stated so it can be challenged:** the same SSH keys copied above already grant *direct* `root` login (step 2 keeps `PermitRootLogin prohibit-password`, required because Coolify itself connects as `root`) — so `NOPASSWD` sudo for `deploy` grants no capability those keys did not already carry directly; it only removes a password prompt an account with no password can never satisfy. **⚠ This argument holds only as long as `PermitRootLogin` stays `prohibit-password`.** If root login is ever tightened to a flat `no` (the non-root-Coolify-connection alternative named in step 2), revisit this grant — at that point `deploy`'s passwordless sudo would be a real escalation the keys no longer carry on their own, and the tradeoff needs re-deciding rather than carried forward unexamined.
4. **Firewall — exact ports, and why each is open:**

   | Port | Direction | Why |
   |---|---|---|
   | `22` (or a custom SSH port, if changed from default) | Inbound | Operator SSH + Coolify's own SSH connection to the box (§3) |
   | `80` | Inbound | Let's Encrypt HTTP-01 challenge + HTTP→HTTPS redirect, via Coolify's built-in reverse proxy (Traefik) |
   | `443` | Inbound | HTTPS traffic to every Coolify-fronted service |
   | ~~`8000`~~ | **NOT opened** | Coolify's dashboard listens here, but it is **not exposed**. See *Why 8000 is closed* below. |

   **Why 8000 is closed — RULED 2026-09-09 (F/CTO).** The Coolify dashboard is the box's most privileged surface. Three options were weighed:

   | Approach | Exposure | Fails when |
   |---|---|---|
   | **SSH tunnel, 8000 closed** ← **CHOSEN** | none | never |
   | Source-restrict to the operator's address | one address | the ISP rotates the lease |
   | Leave open, rely on Coolify's login | the whole internet | a Coolify auth vulnerability lands |

   Source-restriction was the obvious middle option and it does not work here: the operator's connection is a **residential dynamic lease** (F/CTO, 2026-09-09), so a rotation locks the operator out of the dashboard at whatever moment the lease turns over — recoverable through the API, but always at a bad time. The tunnel removes the exposure class instead of narrowing it, costs one command, and is immune to the address changing:

   ```sh
   ssh -L 8000:localhost:8000 root@<box-ip>
   # leave open, then browse http://localhost:8000
   ```

   Coolify's own first-run admin setup works through the tunnel. **The losing side, named:** every dashboard visit needs the tunnel command first, and an operator who forgets it sees a dead port rather than a login page — which reads as an outage if you do not know why.

**Deliberately closed, and why it matters that they stay closed:** the provider-sync admission port `:8081` (§7 CA-2/CA-4) is never firewall-opened at all — it is reached only over the Coolify **project-internal** Docker network by service name, never via the host's public IP. Use the cloud provider's own firewall (Hetzner Cloud Firewall) as the enforcement point, **not** a host-level tool like `ufw` alone — Coolify's own docs note that Docker manipulates `iptables` directly via its NAT rules, which can **bypass `ufw`/host-firewall rules** for published container ports. A cloud-level firewall sits in front of the box entirely and is not subject to that bypass; treat it as the primary control and a host-level firewall (if used at all) as defense-in-depth, never the reverse.
5. **Apply security updates — before Coolify is installed, not after.** Positioned here deliberately: at this point nothing on the box is serving anything, so a bad patch has zero blast radius. The same updates applied *after* cutover are a change to a live system, on the wrong side of that risk trade.

   ```sh
   apt update
   apt list --upgradable 2>/dev/null | grep -i security   # see what's security-flagged before applying
   apt upgrade -y
   # reboot only if apt/needrestart says the kernel or a core library needs it — not on principle.
   ```

   On the first production box (2026-09-09), the fresh Ubuntu 24.04 image came up with 51 pending updates, 49 of them security; 46 applied cleanly, 0 remained upgradable afterward, no reboot was required, and all six Coolify containers verified healthy once installed (§3).

   **Open decision, not made here — flagged rather than silently decided:** whether `unattended-upgrades` is configured for ongoing patching after go-live, or patching stays a manual recurring step. **Not configured as of 2026-09-09.** Owner: F/CTO + DevOps — decide before or shortly after cutover; a box serving live financial data with no patching cadence at all is not an acceptable default-by-omission.
6. **Base packages:** none beyond what Coolify's own installer brings (it installs Docker itself if absent). Do not pre-install a competing reverse proxy, Postgres, or Docker Compose plugin version — let Coolify's installer own that surface, since §3's pinned-version procedure below assumes it is running against the versions Coolify's own installer sets up.

**Confirm ARM-vs-x86 across the fleet:** CAX21 is Ampere ARM (`arm64`); the incumbent cax21 box is also ARM, and every container image in this tree (`api/Dockerfile`, `workers/etl/Dockerfile`, `workers/pdf-render/Dockerfile`, `workers/provider-sync/Dockerfile`) must resolve to `arm64` base images for a clean pull/build on this box. This is a build-time property, not something §1 provisioning changes — flagged here as the check to run if any container fails to start after §6/§7 with an "exec format error" or a base-image pull for the wrong platform.

**Verification block — run after provisioning, before §3:**

```sh
# (1) Reachability + identity — confirm the box is up and matches the ruled spec.
ssh deploy@<box-ip> 'nproc; free -h; df -h /; uname -m; lsb_release -ds'
# EXPECTED: 4 (vCPUs) · ~8Gi total memory · ~80G on / · aarch64 · Ubuntu 24.04.x LTS
```

| Result | Reading |
|---|---|
| `nproc` = 4, `aarch64`, `~8Gi` mem | **Correct** — matches the ruled CAX21 spec. |
| `nproc` = 8, `~16Gi` mem, still `aarch64` | **Wrong-looking-but-actually-wrong**, not a false alarm — this is CAX31's spec, i.e. the exact one-tier misattribution `production-standup.md` §5 already found and corrected elsewhere in this tree. If the Hetzner console handed you this instead of CAX21, the order was placed against the wrong SKU — stop and re-provision against CAX21, don't just note the discrepancy and continue. |
| `nproc` = 4, `~8Gi` mem, but `x86_64` | **Looks fine but is wrong** — Hetzner's console can list both ARM and Intel/AMD lines side by side, and an `x86_64` box will boot, run Docker, and even pull most images successfully (multi-arch tags silently resolve to an `amd64` layer) right up until an ARM-only or single-arch image in this tree fails to run — a failure that surfaces at §6/§7 deploy time, far from this check, unless caught here. Confirm `arm64`/`aarch64` explicitly; do not infer it from "the order said CAX21."
| `df -h /` shows well under 80G (e.g. a resized/undersized volume) | **Wrong** — re-check the disk was attached/sized correctly at creation; do not proceed to §3 with less than the ruled spec. |

```sh
# (2) SSH hardening — confirm password auth is actually off, not just configured.
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no deploy@<box-ip> echo should-fail
# EXPECTED: connection refused/denied — password auth is not accepted.
```

`Permission denied (publickey)` or a closed connection is correct. If this instead **prompts for a password**, `sshd_config`'s `PasswordAuthentication no` either was not applied or `sshd` was not reloaded after editing it (`systemctl reload sshd`) — this is the single most common **looks-fine-but-wrong** case here: the file can read `no` on disk while the running daemon still has the old value in memory, and a login attempt that never gets this far to notice (because the operator always logs in with a key anyway) will not catch it.

```sh
# (3) Firewall — confirm only the intended ports are reachable from outside.
nmap -Pn -p 22,80,443,8000,8081 <box-ip>   # run from OUTSIDE the box's network
```

| Result | Reading |
|---|---|
| `22, 80, 443` open; `8000` **filtered**; `8081` **filtered/closed** | **Correct.** |
| `8000` shows **open** | **Wrong.** The firewall did not apply, or a rule was added by hand. The dashboard is meant to be unreachable from the internet entirely — reach it over the SSH tunnel above. Fix before installing Coolify, not after. |
| `8081` shows **open** | **Wrong, and load-bearing** — this is the exact regression §7 CA-4 / §10 CA-2 exist to catch downstream at the application layer; catching it here, before any service is even deployed, is cheaper. Re-check the cloud firewall rules; nothing at this stage should be publishing that port. |
| Every port shows `filtered` including `22` | **Wrong-looking-but-fine, conditionally** — if this scan is run from a network Hetzner's Cloud Firewall doesn't allowlist yet (e.g. before the operator's own IP is added to the firewall's SSH rule), a fully-filtered result is expected and does **not** mean the box is unreachable to the operator; re-run from the network holding the firewall-allowlisted IP before concluding anything is actually broken. |

```sh
# (4) IPv6 — confirm the persisted /64 actually matches what was recorded, not assumed
#     unchanged. Nothing else in this block reads IPv6 at all.
ssh deploy@<box-ip> "ip -6 addr show scope global | awk '/inet6/{print \$2}'"
```

| Result | Reading |
|---|---|
| Matches the `/64` recorded in `docs/records/v1final/standup-log.md` | **Correct.** |
| Differs from the recorded value — especially right after a `--rebuild` | **Wrong, and easy to miss rather than a false alarm.** Hetzner creates the IPv6 primary IP at server-creation time with `auto_delete=true` by default — unlike IPv4, it does **not** survive a delete-and-recreate unless it was flipped to persistent first. `scripts/provision-vps.sh` does this flip on every run, so a run against this box should already show it persistent; if this check still disagrees, confirm via the API (`GET /primary_ips?name=<name>-v6` → `auto_delete: false`) **before** touching DNS — an AAAA record pointed at a stale `/64` is a silent partial outage (§2), not a loud one, since IPv4 keeps working the whole time. |
| No global-scope IPv6 address at all | **Wrong** — `enable_ipv6` was not set at server creation, or the interface never came up. Check `public_net.ipv6` on the server via the Hetzner API before proceeding. |

---

## 2. DNS / domain

Scope: point the production hostname(s) at the new VPS.

- **RULED 2026-09-09 (F/CTO): reuse `pfindash.com`.** This is the open half of the Overview's "Incumbent is reference-only" principle resolving: the *domain* is reused even though the *box and its configuration* are not — no DB, no containers, no Coolify config transfer carries over (per Overview + `feedback_greenfield_no_existing_deployment_dependency`). Only the DNS records move, and only at §9's cutover.

- **⚠ This is a live-traffic change, not a greenfield write.** `pfindash.com` is reference-only in the sense that nothing else in this repo depends on the incumbent deployment — but the domain itself may still carry live A/AAAA (and possibly MX/TXT/other) records pointing at the incumbent cax21 box. Repointing those records is the literal traffic-switch action §9 exists to gate. **§2 documents the mechanism below; §9 owns the go/no-go and the timing** — do not run the record changes past step 1 (the snapshot) until §9's smoke-test gate says go.

**Before touching anything — snapshot the live state (read-only, safe to run any time ahead of cutover):**

```sh
dig +short pfindash.com A
dig +short pfindash.com AAAA
dig +short pfindash.com MX
dig +short pfindash.com TXT
dig +short www.pfindash.com
```

Record what comes back — the incumbent's A/AAAA (its own cax21 IP), and, load-bearing on a domain that predates this project, **whether any mail (`MX`) or SPF/DKIM (`TXT`) records exist**. This runbook has no email-service scope; a `pfindash.com`-hosted mailbox is exactly the kind of side effect a "just repoint A/AAAA" mental model would silently break. If MX/TXT records exist, name them here at execution time and leave them untouched unless F/CTO explicitly says otherwise — this section only ever touches the records that route web traffic.

**Subdomain split: app only — no public record for the Supabase surface.** Landing, and why:

- Per §3's service table, **`app` is the only Coolify service assigned a public Domain**; `etl`, `pdf-render`, and `provider-sync` are internal-only by construction (Lock 13 mod #2, CA-4). The Supabase surface doesn't break that pattern: the sole verified consumer of `PUBLIC_SUPABASE_URL` is `api/src/hooks.server.ts`'s server-side `createServerClient()` call (`event.locals.supabase`, built per-request from `$env/dynamic/public`) — `grep -rn "createBrowserClient" api/src` returns **zero hits**, so no browser code ever opens a connection to the Supabase URL directly. The browser only ever talks to the SvelteKit app; the app's own server process is the sole thing that needs to reach Supabase, and that reach can stay entirely inside the Coolify project's internal Docker network — the same posture CA-4 already established for `provider-sync`↔`app`.
- **Consequence: one public hostname, for `app` only.** No `api.pfindash.com` / `supabase.pfindash.com` DNS record is provisioned in this pass.
- **Named exception, not resolved here:** §4's own STUB has not yet ruled which self-hosted Supabase services (db / auth / storage / realtime / **studio**) are in V1 scope. If Studio is scoped in and F/CTO wants browser-based remote admin access to it (rather than an SSH tunnel to the box), that is one additional subdomain + Domain assignment, decided when §4 resolves — do not pre-provision it here.

**A/AAAA records — exact steps, IP filled in at execution (§1 doesn't produce it until the box is provisioned):**

1. At §1's provisioning step, record the box's public IPv4 (and IPv6, if Hetzner assigns one to the CAX21 order — confirm in the console; don't assume).
2. At the registrar for `pfindash.com`, set:
   - `A` record, host `@` (apex) → `<box-ipv4>`
   - `AAAA` record, host `@` → `<box-ipv6>` (only if the box has one)
   - `www` → an alias of the apex (`CNAME` to `pfindash.com`, or a matching `A`/`AAAA` pair) — whether Coolify's Domain config for the `app` service carries both `pfindash.com` and `www.pfindash.com` as aliases is a §3 Domain-assignment decision, not a DNS-layer one.
3. **Lower the TTL well before the cutover window, not at it.** A record changed cold at a 3600s registrar default means up to an hour of clients still resolving the incumbent IP during the go/no-go window. Drop TTL to something short (300s is a reasonable target) at least one full TTL-cycle ahead of the planned §9 cutover; do the actual A/AAAA swap at cutover time itself.
4. Leave every other existing record (MX, TXT, any other subdomain) exactly as found in step 0's snapshot, unless F/CTO explicitly names one to change.

**TLS.** Confirmed against §3, not restated here: Coolify's bundled Traefik automates Let's Encrypt issuance per-Domain once a service is assigned one (§3 "TLS/proxy approach" — no external nginx/Certbot layer). §1's firewall already opens `80` (HTTP-01 challenge + redirect) and `443` (issued-cert traffic); nothing new to open for DNS. Certificate issuance is blocked on the A/AAAA record actually resolving to the new box (the HTTP-01 challenge is fetched over the domain's current DNS answer) — the propagation check below must pass **before** assigning the Domain in Coolify, not after.

**Propagation check — run from OUTSIDE any network that might hold a stale cached answer:**

```sh
# Pin at least two independent public resolvers — never rely on the operator's
# own ISP/local resolver, which can already hold a cached answer from an
# earlier lookup of the SAME name and read as "already propagated" when most
# of the internet has not picked up the change yet.
dig +short @8.8.8.8 pfindash.com A
dig +short @1.1.1.1 pfindash.com A
dig +short @8.8.8.8 pfindash.com AAAA   # only if an AAAA record was created
```

| Result | Reading |
|---|---|
| Both resolvers return `<box-ipv4>`; a TLS handshake against `pfindash.com:443` presents a cert for `pfindash.com` | **Correct.** Safe to proceed to Coolify Domain assignment (§3) and, later, §9's cutover checklist. |
| One resolver returns the new IP, the other still returns the incumbent's IP | **Wrong-looking-but-fine, conditionally** — during the TTL window this is expected: resolvers refresh independently, not in lockstep. Not a failure unless it persists past the TTL set in step 3 plus a reasonable margin. Re-check after that window before escalating. |
| Both public resolvers return `<box-ipv4>` immediately after the record change, with no visible delay at all | **Looks fine but is the wrong thing to draw confidence from** — a short TTL (step 3) makes fast propagation *expected*, not a signal that this check can be skipped on a future domain change that wasn't pre-lowered. Don't generalize "it was instant this time." |
| `dig` from the operator's own machine (no `@resolver` pinned) shows the new IP, but both pinned public resolvers above still show the old one | **Wrong, and the case worth naming explicitly** — an unqualified `dig pfindash.com A` uses whatever resolver the operator's OS/network is configured with, which may already be primed from an earlier lookup of the same name. This is exactly the "looks resolved, isn't" failure propagation checks exist to catch. Always pin the resolver as shown above; never trust the ambient default. |
| TLS handshake succeeds over IPv4 (`curl -4`) but times out over IPv6 (`curl -6 https://pfindash.com`), despite an AAAA record resolving correctly | **Wrong, and the AAAA record's presence is not sufficient evidence it's fine** — Hetzner's firewall or the box's own network config can leave IPv6 unreachable even with a published address, a known CAX-line gotcha since IPv6 is enabled by default but not always routed identically to IPv4 at the OS level. If an AAAA record was created, confirm the IPv6 path with an explicit `-6` request — a resolvable-but-unreachable AAAA record is worse than no AAAA record, since some clients will now prefer it and fail outright. |

---

## 3. Install & configure Coolify

Scope: install Coolify on the fresh box; it is the deployment control plane for all V1 containers (per ARCH §5 — config lives in the Coolify UI; this repo holds only source-of-truth `Dockerfile`s + env-var contracts).

**Status (2026-09-09): install and first-run setup DONE.** Coolify `4.3.18` is installed and all six containers (`coolify`, `coolify-db`, `coolify-redis`, `coolify-proxy`, `coolify-realtime`, `coolify-sentinel`) report healthy. The first-run admin account has been created and claimed (F/CTO). A `localhost` server is registered in Coolify — this is Coolify's own auto-created entry for the box it runs on, not a separate provisioning step. A GitHub source row connecting this repo exists. **Not yet done:** Domain assignment for `app` (blocked on §2's DNS cutover), the four-service topology below, and the ARCH §6 item (f) auto-deploy webhook.

- Deploys go through the **Coolify UI**, not from chat or CI (per ARCH §5). This repo's job is to make the repo-side artifacts (Dockerfiles, `.env.example` contracts) deploy cleanly when F/CTO triggers a deploy.

**Install method — pinned, not `latest`.** Coolify's installer is a single script (`coolify.io/docs/get-started/installation`, read 2026-09-09) that supports installing an exact version by passing it as an argument:

```sh
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash -s <version>
```

**How to determine `<version>` at execution time (not fixed in this doc, because the right value changes and a stale pin here would be worse than no pin):** read `https://cdn.coollabs.io/coolify/versions.json` immediately before installing and take the `coolify.v4` value — **as read live on 2026-09-09 while authoring this section, that value was `4.3.18`; treat that as an illustration of the mechanism, not the version to install.** Omitting `<version>` entirely (`bash` with no argument) installs whatever that file currently resolves to, which is exactly the non-reproducible "latest" the prior STUB flagged — passing the version explicitly is what turns the same command into a pinned, repeatable install. **This is what was actually installed on the production box, same day: `4.3.18`, pinned and verified running.**

**Record the pinned version, don't just install it.** Write the exact version string installed into `docs/records/v1final/production-standup.md`'s deploy log (the file this runbook's own hand-off convention already treats as the authority for what got deployed) at the time of install — the version isn't reproducible later if only "whatever `versions.json` said that day" is remembered.

**How to re-check it later:** Coolify's dashboard displays its own running version (Settings/Configuration screen); to check whether a newer release exists, re-read `versions.json`'s `coolify.v4` key and diff against the recorded install-time value. Coolify's docs do not document a CLI "check for updates" command distinct from the dashboard's own update-checker — the dashboard is the source of truth for "what's running," `versions.json` is the source of truth for "what's current."

**Initial admin setup.** The installer's own output prints the first-access URL as `http://<box-ip>:8000`. **That URL will not resolve from your machine, and that is correct** — §1 deliberately leaves 8000 closed. Open the tunnel first (`ssh -L 8000:localhost:8000 root@<box-ip>`), then browse `http://localhost:8000` and complete the first-run admin account creation there. Everything the installer says about the dashboard applies; only the address you type differs.

**GitHub source connection.** From the Coolify dashboard: Sources → add a GitHub App (or a deploy-key-based Git source, if F/CTO prefers not to install a GitHub App on the org) → authorize it against this repo. This is what lets Coolify pull `main` per each service's **Base Directory** setting (already named per-service in §7 — `api/`, `workers/etl/`, `workers/pdf-render/`, `workers/provider-sync/`). **Do not configure auto-deploy-on-push yet** — that is ARCH §6 item (f)'s webhook lock, named as its own later step below, not part of this install pass.

**TLS/proxy approach.** Coolify ships its own reverse proxy (Traefik, per Coolify's own docs) and automates Let's Encrypt certificate issuance per-domain once a service is assigned a domain — this is the default and this runbook does not depart from it (no external nginx/Certbot layer). §1's firewall already opens the ports this depends on (`80` for the HTTP-01 challenge + redirect, `443` for the issued cert's traffic). Concrete domain assignment is blocked on §2 (DNS — open F/CTO decision, out of scope here); this section documents the mechanism, not a hostname.

**Project/service topology skeleton — one Coolify project, four services, per ARCH §6/§7's hybrid topology:**

| Coolify service | Base Directory | Build pack | Notes |
|---|---|---|---|
| `app` (V1 web-app) | `api/` | Dockerfile (`api/Dockerfile`) — the one container in the fleet still on the plain Dockerfile+Base-Directory build pack | The only service assigned a public Domain — everything else stays internal-only on this project's Docker network. |
| `etl` (`pfin_back_etl`) | `workers/etl/` | **Compose** — [`workers/etl/docker-compose.yaml`](../workers/etl/docker-compose.yaml) | One image, **two Coolify units** per the compose file's own header (each entrypoint — the nightly ingest and the monthly-report cron — gets its own deploy/restart/resource ceiling and its own Scheduled Task attached, per §7's Pattern A convention: the `CMD` stays a resident `tail -f /dev/null` and Coolify execs the actual work into it on a cron). No public Domain on either unit. |
| `pdf-render` (Node PDF worker) | `workers/pdf-render/` | **Compose** — [`workers/pdf-render/docker-compose.yaml`](../workers/pdf-render/docker-compose.yaml) (adopted at SELF-348 A4 item 4c / Sec N-4, superseding the plain-Dockerfile pack this container shipped with at Phase 5 — the committed compose is what makes its render-endpoint admission surface lintable by `fence-admission-private-bind.sh`, same reasoning as `provider-sync` below) | Zero-DB-isolation per Lock 13 mod #2 — no public Domain, no DB credential; reachable only from `app` over the internal network. |
| `provider-sync` | `workers/provider-sync/` | **Compose** — [`workers/provider-sync/docker-compose.yaml`](../workers/provider-sync/docker-compose.yaml) (build pack must be Compose, not bare Dockerfile, per §7's own CA-1/CA-4 text: the committed compose file is what makes the admission port's `expose:`-only, no-`ports:`, no-Domain shape lintable rather than a UI setting nothing can check) | **CA-4 hard prerequisite (§7): this service and `app` MUST be created in the same Coolify project** — internal DNS (`http://provider-sync:8081`) only resolves within one project's network. Verify this at creation, not after — a cross-project placement is the exact failure shape §10 CA-2's smoke test exists to catch downstream. |

All four services are created under **one Coolify project** for this reason — the `provider-sync` ↔ `app` internal-DNS dependency (CA-4) requires it, and there is no offsetting reason to split the other two services out. Env-var wiring per service is §5 (STUB — not this PR).

**Carried forward, not configured here: ARCH §6 item (f), the Coolify auto-deploy webhook lock.** Per ARCH §6, deploys are auto-triggered by Coolify watching `main` after CI goes green — but wiring that watch is its own Sec-consult-mandatory step (§6 item (f)), gated on: (i) Coolify configured to watch `main` only — no other branch, no pattern match; (ii) GitHub branch-protection admin-bypass disabled or restricted to F/CTO with an audit trail, so a bypassed direct push can't trigger a deploy that skipped CI; (iii) the webhook URL held as a production secret, never in the repo; (iv) auto-deploy permission boundaries documented. **This PR does not configure that webhook** — it is named here as the next named step after the four services exist, not performed as part of install.

**Where the deployed-sha authority lives.** Per `docs/records/v1final/production-standup.md` §1 (OPEN-1, resolved): the authority for "what sha is actually running" is **Coolify's own API/UI record of the deployed commit** — `GET /api/v1/applications/{uuid}` → `git_commit_sha`, cross-checked against `GET /api/v1/deployments/applications/{uuid}`'s per-deployment history — read and transcribed into that record's deploy log at every deploy, never held as a memory or inferred from `main`'s tip. This runbook does not duplicate that mechanism; it names where it lives so nobody re-derives it differently at execution time.

---

## 4. Stand up Supabase from scratch

Scope: bring up a fresh self-hosted Supabase stack (Postgres 17) on the new box — the data layer for all V1 surfaces.

- **Postgres 17** is the forward target (`supabase/config.toml` `major_version = 17`), by choice.
- **Carried follow-up (open):** PG-17 confirm-vs-prod — the `config.toml` comment notes `major_version = 17` is a best-guess match to the incumbent and should be confirmed before Phase 6 base-table RLS work where version-skew bites harder. In the greenfield posture this is **forward-by-choice**, so the "match prod" framing is reference-only; still confirm 17 is the version actually deployed.

**Bring-up method — a Coolify "Docker Compose" resource sourced from Supabase's own reference self-hosting compose, not Coolify's one-click Supabase service.** The losing side is named below, not glossed over.

| Approach | What it is | Verdict |
|---|---|---|
| Coolify's one-click **Supabase** service — a template Coolify itself curates and maintains | Ships Coolify's own bundled compose | **NOT CHOSEN.** Read live from Coolify's own docs (`coolify.io/docs/services/supabase`, 2026-09-09): the bundled compose pins **`supabase/postgres:15.6.1.146`** — Postgres **15**, not the **17** this project already decided on ([ADR-021](../DECISIONS.md#adr-021); `supabase/config.toml` `major_version = 17`). Using it would mean hand-editing Coolify's own managed template's compose to swap the database image — and Coolify's own docs already resort to exactly that kind of hand-edit for a lesser fix (a documented database-port-exposure workaround). The template does not spare us editing a compose file; it only relocates the edit into a Coolify-managed resource a future Coolify update could silently revert, instead of a file this repo commits and reviews. |
| A Coolify **Docker Compose** custom resource — the same resource type §3's table already uses for `etl` / `pdf-render` / `provider-sync` — pointed at a compose file adapted from Supabase's reference self-hosting compose (`github.com/supabase/supabase` → `docker/docker-compose.yml`) | We supply the compose content | **CHOSEN.** Read live 2026-09-09: the current reference compose already pins `supabase/postgres:17.6.1.136` — PG 17, on target, no override needed. It also gives a committed, reviewable artifact for the `studio`/`meta` trim below — the same lintability argument §3 already makes for `provider-sync`/`pdf-render`'s Compose-over-bare-Dockerfile choice: a UI-only trim is a setting nothing can check; a committed compose file is. |

**Losing side of the chosen option, stated plainly:** Coolify's one-click services get Coolify's own maintained upgrade path and a curated per-service UI panel; a hand-sourced Compose resource gets neither — DevOps, not Coolify, is responsible for periodically re-pulling the upstream reference compose and re-applying the trim below, rather than clicking an "update" button. Accepted because the PG17 mismatch above is not a stale-snapshot fluke of Coolify's template — it is that template's own committed artifact, and leaning on it for a version-sensitive component like the database is exactly the kind of moving-target dependency this runbook's own Coolify-version-pin discipline (§3) argues against.

**Do not fetch the reference compose once and commit it verbatim into this repo.** Its service set and image tags move — the gateway service alone has been renamed and re-implemented since earlier tree references were written (see the `kong` row below). Pull it fresh at execution time, apply the trim below, and record the exact tags actually deployed in `docs/records/v1final/standup-log.md` (the as-executed log, not this file, per its own "records measurements, not intentions" rule).

**Service scope for V1 — decided service by service, evidence-based.** Cross-checked against `supabase/config.toml`'s `enabled` sections and the current reference compose (read live 2026-09-09); the note after the table says why `config.toml`'s flags don't settle this by themselves.

| Service | In/Out | Evidence |
|---|---|---|
| `db` (Postgres) | **IN** | The datastore. The chosen bring-up method's reference compose pins `supabase/postgres:17.6.1.136` — PG 17, matching `config.toml`'s `major_version = 17` with no override needed. |
| `auth` (GoTrue) | **IN** | `api/src/hooks.server.ts`'s `createServerClient()` call is the app's entire session mechanism (`event.locals.supabase`) — no code path works without it. |
| `rest` (PostgREST) | **IN** | The Data API `createServerClient()` talks to for every `pfin`-schema query, per [`supabase/CLAUDE.md`](../supabase/CLAUDE.md)'s RLS-default-trust posture (supabase-js + PostgREST, native RLS). |
| `storage` | **OUT** | Re-grepped 2026-09-09: `grep -rniE "supabase.*storage\|\.storage\.from\(\|createBucket\|getBucket" api/src` and the same over `workers/pdf-render/src` → **zero hits**. Plaid access tokens live in `vault.secrets` (a Postgres extension inside `db`) — a different thing from the Storage service; don't conflate them. **New finding, not previously recorded anywhere in this tree** — revisit if a future PRD story adds file uploads. |
| `realtime` | **OUT** | Re-grepped 2026-09-09, independently reproducing `production-standup.md` §5's finding: `grep -rniE "realtime\|\.channel\(\|supabase\.channel\|postgres_changes\|removeChannel" api/src` → zero genuine hits (only an unrelated `vi.useRealTimers()` fake-timer call). Also confirmed **zero** `createBrowserClient` call sites in `api/src` — no browser-side Supabase client exists to subscribe through even in principle. |
| API gateway (`kong`, historically) | **IN — name drift flagged** | The ingress everything else sits behind; required regardless of name. **Finding:** this tree's prior references (`production-standup.md` §3, runbook §2) call this service `kong`. The **current** reference compose (read live 2026-09-09) no longer ships Kong at all — the gateway is now `api-gw`, built on **Envoy** (`envoyproxy/envoy:v1.39.1`). Supabase has migrated its self-hosted gateway upstream of this tree's prior research. Confirm which gateway actually ships in whatever reference-compose snapshot is pulled at execution time — Kong's plugin config and Envoy's filter config are not interchangeable, so a stale "kong" mental model is a real footgun here, not a naming nicety. |
| `meta` (postgres-meta) | **OUT by default** | Sole known consumer in the reference compose is `studio`'s schema browser — nothing else depends on it. Drop **together with** `studio`, never independently: if `studio` is kept, `meta` must be kept too, since Studio has no other data source. This tightens the compose-trimming finding (`production-standup.md` §5), which flagged dropping `studio` as "unverified whether it breaks anything else" without checking `meta`'s dependents — checked here: nothing else needs `meta`. |
| `studio` | **OUT by default, named exception carried over** | Per the compose-trimming finding and runbook §2's own framing: drop unless F/CTO names a concrete reason to keep it (e.g. browser-based ad-hoc DB inspection without an SSH tunnel). If kept, it needs its own Coolify Domain and the `meta` row above flips to IN with it — a §2/§3-shaped follow-on, not resolved here. |
| `imgproxy` | **OUT** | Sole consumer is Storage's image-transformation feature. `storage` is OUT (above), and `config.toml`'s `[storage.image_transformation]` block is commented out regardless — no consumer at either layer. |
| `supavisor` (pooler) | **IN, with a carve-out** | Fronts `rest`/`auth`'s own database connections by default in the reference compose. `config.toml`'s `[db.pooler] enabled = false` is **local-CLI-only** and isn't evidence either way — the local `supabase start` stack (`production-standup.md` §5's 11-container `docker stats` table) doesn't run a pooler container at all, on or off. **DevOps call, named so it can be revisited:** the two direct-Postgres workers (`workers/etl`'s `pfin_etl` connection, `workers/provider-sync`'s `pfin_provider_sync` connection — both via `TenantBoundConnection`/`TenantBoundClient`, Lock 13 mod #3) connect **straight to `db`**, bypassing `supavisor` — each is a long-lived singleton connection that gains nothing from transaction-mode pooling, and routing through `supavisor` adds an unverified prepared-statement-compatibility unknown for no offsetting benefit at V1's single-tenant scale. Open to Architect/Sec revisit; not F/CTO-locked. |
| `analytics` | **OUT** | Re-confirmed 2026-09-09, reproducing the prior finding independently: absent from the current reference compose entirely — a `supabase start` CLI-only convenience add, never part of the production reference stack. |
| `vector` | **OUT** | Same as `analytics` — confirmed absent from the current reference compose. |

**Not in scope of the above list, noted for completeness:** the reference compose also defines a `functions` service (Edge Runtime). No Edge Function is authored anywhere in this tree (`config.toml`'s `[edge_runtime]` block is a local-CLI default with nothing behind it) — **OUT**, same reasoning as the others, just not itemized since it wasn't asked for.

**On `config.toml` generally.** Every `enabled = true` in `supabase/config.toml` (`api`, `db`, `realtime`, `studio`, `storage`, `auth`, `analytics`, `inbucket`, `edge_runtime`) describes what the **local CLI-managed dev stack** turns on for developer convenience — it is not a production service manifest, and per this runbook's own convention this section does not edit that file. Where the table above disagrees with a `config.toml` `enabled = true` (`realtime`, `storage`, `studio`, `analytics`), that is `config.toml` correctly serving local dev, not evidence either service belongs in production. `inbucket` is the clearest case: it's explicitly local-only email-catching (`config.toml`'s own comment: "not actually sent") — production email is wired separately at the `auth` container's own SMTP env per `config.toml`'s commented `[auth.email.smtp]` block, unrelated to this service-scope decision.

**Postgres major version — 17, and how to know it landed.** The chosen bring-up method sources a reference compose that already pins `supabase/postgres:17.6.1.136` as of the 2026-09-09 read, matching `config.toml`'s `major_version = 17` ([ADR-021](../DECISIONS.md#adr-021), forward-target-by-choice, not by prod-match — the cax21/pfindash.com incumbent measured PG 15.8 and is reference-only). This is what discharges this section's "PG-17 confirm-vs-prod" carried follow-up above — **operationally**, by the check below, not by this sentence alone:

```sh
psql "$PROD_DB_URL" -Atc "show server_version;"
# EXPECTED: 17.x
```

Do not accept a Coolify/`docker compose` "healthy" status as this proof — a health check proves a process is listening, not which major version it's running. A wrong image tag reports exactly as healthy as a right one; this is exactly the silent failure mode Coolify's one-click template (pinned to 15.x) would have produced.

**5a. Disable production signup; found the tenant by invitation.** Set `GOTRUE_DISABLE_SIGNUP=true` in the Coolify Compose resource's environment for the `auth` service — interpolated into that service's env block in the compose file, the same mechanism the stack's `JWT_SECRET`/`ANON_KEY`/`SERVICE_ROLE_KEY` already use. This is a **container env var on the self-hosted `auth`/GoTrue container**, distinct from and unrelated to `config.toml`'s `[auth] enable_signup` / `[auth.email] enable_signup` (both `true`, local-CLI-only, `config.toml:181,228`) — setting one does not touch the other.

**Verify by probing the endpoint, never by reading a config back:**

```sh
curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST "$PUBLIC_SUPABASE_URL/auth/v1/signup" \
  -H "apikey: $SUPABASE_ANON_KEY" -H 'Content-Type: application/json' \
  -d '{"email":"probe-'"$(date +%s)"'@example.invalid","password":"probe-password-1234"}'
# EXPECTED: signup refused (GoTrue's signup-disabled error), never a 2xx with a created session.
```

Record pass/fail in `docs/records/v1final/standup-log.md` — this runbook is the reusable procedure; that log is the as-executed chronicle, per its own convention.

**Founding tenant, by invitation, never by signup.** Run the Auth Admin API's invite path with the production `SUPABASE_SERVICE_ROLE_KEY` — service-role-gated, confirmed runnable standalone with no Studio dependency (relevant since `studio` is OUT by default above — dropping it does not remove this capability, only its point-and-click form):

```js
// one-off, run BY F/CTO from a machine holding the production service_role key —
// never by an agent, never committed
const { createClient } = require('@supabase/supabase-js')
const supabase = createClient(PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
await supabase.auth.admin.inviteUserByEmail('<founding-tenant-email>')
```

(Equivalent REST form if a script runtime isn't handy: `POST {PUBLIC_SUPABASE_URL}/auth/v1/invite` with the service_role key as both the `apikey` and bearer `Authorization` header.)

**This stays off past stand-up completion — a standing gate, not a step that discharges.** `GOTRUE_DISABLE_SIGNUP` stays `true` through the full V1.final soak until the operator allowlist on the Plaid Link-token route ships — [`BACKLOG.md` §7.36 item 1](../BACKLOG.md) — per F/CTO's ruling (`docs/records/v1final/production-standup.md` §5, OPEN-3 gate #16). Do not flip it back on as a byproduct of any later stand-up step reading as "done."

**Applying migrations to the fresh instance.** This names the mechanism only — per-migration specifics (ordering rationale, the `pfin_etl` / `pfin_provider_sync` two-step credential handoffs) are §6 / §6.1 / §6.2 below; this section does not restate them. The fresh `db` container begins empty; there is no separate "init" step beyond bringing it up and then applying the full chain here — every schema and table is created from scratch by the migrations themselves.

Self-hosted Supabase has no "linked Supabase Cloud project" to `supabase link` against — that command binds to Supabase's hosted platform API, not applicable here. Apply with:

```sh
supabase db push --db-url "$PROD_DB_URL"
```

This pushes every migration in `supabase/migrations/` (currently through `117` — read the directory live; this runbook does not pin the count) in numeric order and records each in `supabase_migrations.schema_migrations` — the same tracking table OPEN-3 gate #10 already reads for `061`'s provenance. Safe to re-run: the CLI compares against that table and skips what's already applied, so a retry after a partial failure does not re-apply anything.

**⚠ `055` and `117` write a cluster-wide `comment on role` — what that means for a production apply, specifically.** `pg_shdescription` (the catalog `comment on role` writes to) is **shared across every database in the Postgres cluster**, not scoped to one. [`BACKLOG.md` §7.36 item 9](../BACKLOG.md) records this being tripped for real: applying `117` against a scratch database inside the **shared local dev cluster** left its comment visible from every other database sharing that cluster. **Production does not have that shape, and that is exactly why applying there is safe as designed:** this stack's `db` container is a single-purpose Postgres instance serving only this app — there is no second database in the cluster for the comment to leak into. The hazard is about *reusing this migration file against a shared/scratch cluster*, not about running it once, as intended, against production's own dedicated cluster. The corollary is a constraint worth keeping, not just a fact to note: **if production's Postgres cluster is ever asked to host a second database** (e.g. co-locating a future second app to save resources), the `pfin_etl` / `pfin_provider_sync` role comments become shared state across both — a reason to keep this cluster single-database, named here for whoever next reconsiders Coolify topology. If `117`'s comment text is ever revised again post-deploy, the repair path is the one §7.36 item 9 already names: re-apply `055` then `117` — overwrite is benign, since the new text is the intended end state.

**Verification block — stack-level, run after apply, before §5's secrets lock.** The TimeZone check is §4.1's, by reference — not restated here.

```sh
# (1) Every in-scope service healthy AND on the right artifact — not the same check.
docker compose -f <the compose file used> ps
psql "$PROD_DB_URL" -Atc "show server_version;"
curl -s -o /dev/null -w '%{http_code}\n' "$PUBLIC_SUPABASE_URL/rest/v1/"
```

| Result | Reading |
|---|---|
| All services `running`/`healthy`; `server_version` = `17.x`; the gateway probe returns a `4xx` refusal | **Correct.** The refusal is the *fail-closed* result of hitting the Data API with no `apikey` header — read it as "the gateway is up and enforcing," not as a failure. The exact code (`401` under Kong's key-auth plugin; possibly different under the Envoy-based `api-gw` — see the gateway row above) is not pinned here; confirm what this gateway actually returns and treat any refusal as correct, a `2xx` as not. |
| All services report `healthy` in Coolify/`docker compose ps`, but `server_version` is anything other than `17.x` | **Looks fine but is wrong, and easy to miss** — a container health check proves a process answered, not which image tag it's running. This is exactly the failure mode Coolify's one-click template would have produced silently (see the bring-up-method table above); confirming version by direct query, not by dashboard color, is the point of this row. |
| The gateway probe returns `2xx` with a data response, no `apikey` supplied | **Wrong, and worse than a clean failure** — the Data API is not enforcing its own key check; every `pfin` table's RLS is the *second* layer of a two-layer fence (`config.toml`'s own header comment: anon holds zero grants outer, RLS inner). A gateway that skips key-checking removes the layer meant to stop unauthenticated traffic from ever reaching PostgREST at all. Stop and re-check the gateway config before proceeding. |
| `studio` / `meta` show up in `docker compose ps` when the trim decision above dropped them | **Wrong, and worth checking explicitly rather than inferring** — a stale prior deploy attempt, or a compose file that wasn't actually re-pulled with the trim applied, can leave them running even though *this* execution's compose file omits them. Confirm their absence directly; don't infer it from "I used the trimmed file this time." |

**Secrets this step produces.** Names only — never values, here or anywhere in this repo; most (not all — each row below states whether it is a manifest entry) are drawn from `secrets-manifest.yml`'s `production_only` set. **§5's secrets-provisioning procedure is still a STUB and its Sec joint-review flag is NOT discharged by this section** — this only names where these five land; rotation/injection-order procedure is §5's job.

| Secret | Produced how | Where it goes |
|---|---|---|
| `ANON_KEY` (Supabase compose env) | Minted at Supabase stand-up (signed with the stack's own JWT secret, `role: anon`) — not operator-chosen | The Supabase compose's own env **only** — required so `rest`/the gateway/`auth` recognize it. Not a `secrets-manifest.yml` entry: internal to the self-hosted stack, distinct from the app-facing name below. |
| `PUBLIC_SUPABASE_ANON_KEY` (app-facing) | Same minted value (`role: anon` JWT) — not a separate mint, not operator-chosen | The `app` service's Coolify env, as **non-secret runtime config** — §5's `PUBLIC_`-prefixed injection list, not `secrets-manifest.yml`. Sec ruled the anon key a publishable JWT, not a secret: RLS plus the [ADR-029](../DECISIONS.md#adr-029) aal2 backstop are the controls. Consumed by `api/src/hooks.server.ts`'s boot-time env guard under this exact name. **The naming mismatch previously flagged here is resolved**, by giving the stack-internal consumer and the app consumer two distinct names rather than reconciling one to the other. |
| `SUPABASE_SERVICE_ROLE_KEY` | Same minting step, `role: service_role` | Same two-place pattern as above; consumed under this exact name by `api/src/lib/server/supabase-admin.ts` (verified — no mismatch here). RT-26's §4.1 allowlist confines its **consumption** inside the `app` container to that one file; unaffected by where the value is injected. |
| `PFIN_DB_USER` | Non-secret username, fixed per container (`pfin_etl` / `pfin_provider_sync`) | Coolify env on `workers/etl` / `workers/provider-sync` respectively. |
| `PFIN_DB_PASSWORD` | Generated at the §6.1/§6.2 two-step credential handoff (`openssl rand -hex 32`) — **after** migrations apply, per the ordering dependency §6.1 already states | Coolify env on `workers/etl` / `workers/provider-sync` — **different value per container**, same secret name, per `secrets-manifest.yml`'s own note. |

### 4.1 Database TimeZone — pinned to UTC · NOT a stub · financial-correctness dependency

**The invariant: the production database's session `TimeZone` is `UTC`, by declaration, and that declaration is read back — never inferred from an image default.**

**Why this is a correctness dependency and not a preference.** The app derives every as-of date in the **Node** process as `new Date().toISOString().slice(0,10)` — unconditionally UTC. Postgres evaluates `closed_at::date` in the **database session's** `TimeZone`. Two clocks in two processes; they agree **if and only if** the session zone is UTC. Under a session zone east of UTC, a just-closed account stays in the §2.1.1 NAV headline and the open-account count until the zones re-converge (Sec's construction: `Asia/Tokyo`, close at 08:00 local Mar 2 → instant `2026-03-01 23:00Z` → Node says Mar 1, `closed_at::date` says Mar 2 → the predicate `closed_at::date > p_as_of` is TRUE for ~9 hours). West of UTC fails *safe*, which is worse: the defect becomes hemisphere-dependent and invisible to a single deployment. Migration [`060`](../supabase/migrations/060_closed_at_comment_corrections.sql) records the full analysis on the `closed_at` column comment and names this pin as its declared dependency; [ADR-043](../DECISIONS.md#adr-043)'s accepted cost rests on it.

**Chosen layer: a migration (`ALTER DATABASE … SET timezone = 'UTC'`), Architect-authored.** Rationale — it is the only instrument that reaches **local, CI, and production through one artifact**, is repo-versioned, re-applies on every `supabase db reset`, and outranks the container's `postgresql.conf`. Because CI applies the *same* migration production runs, a green CI is evidence about production's **mechanism** (not merely about CI's own ambient state).

**Why the other layers are wrong as the primary:**

| Layer | Why not primary |
|---|---|
| `postgresql.conf` / container `-c timezone=UTC` | This is the layer whose default we are *already* implicitly trusting, and it is **not visible from this repo** (Coolify holds the compose per ARCH §5). Pinning at the same unversioned layer adds no repo-verifiable claim. Keep as a **belt-and-braces** setting if the compose is ours to edit, never as the guarantee. |
| `ALTER ROLE … SET timezone` | **Outranks** the database pin, so it is the layer that could silently *break* it. Pinning N roles puts the guarantee in N places and still misses role N+1. Correct posture: keep **one** declaration (the database pin) and **assert at catalog level that no role-level `TimeZone` exists at all** — a sweep that covers roles not yet created. See the role-precedence measurement below, which determines *which* role even matters. |
| A manual runbook step only | A human step nobody verifies is the same unmeasured premise in a new costume. The runbook's job here is to state the invariant and its **verification**, not to be the pin. |

**MEASURED precedence ladder** (local stack, `supabase/postgres:17.6.1.132`, 2026-08-04 — recorded because this is what makes the pin sufficient *or not*):

| Condition | Effective zone | `pg_settings.source` |
|---|---|---|
| As shipped, no pin | `UTC` | `configuration file` ← **the unmeasured premise** |
| `ALTER DATABASE … SET timezone='UTC'` | `UTC` | `database` ← the pin, working |
| Client env `TZ=Asia/Tokyo` | `UTC` | `database` (unaffected) |
| **Client env `PGTZ=Asia/Tokyo`** | **`Asia/Tokyo`** | **`client`** ← **the pin is DEFEATED** |
| `ALTER ROLE **authenticated** SET TimeZone='Asia/Tokyo'`, then `SET ROLE authenticated` | `UTC` — **NO-OP** | `database` (unaffected) |
| `ALTER ROLE **authenticator** SET TimeZone='Asia/Tokyo'`, login as `authenticator` | **`Asia/Tokyo`** | **`user`** ← **the pin is DEFEATED**, and it **survives `SET ROLE authenticated`** |

**⚠ The role-level vector is real, but it is on the LOGIN role — and that is not the role people name.** Per-role settings (`ALTER ROLE … SET`) are applied **at login**, from the role actually connected as. `SET ROLE` does **not** re-apply them. PostgREST logs in as **`authenticator`** and then `SET ROLE`s to `authenticated`, so:

- `ALTER ROLE **authenticated** SET TimeZone` is a **no-op** — MEASURED: `current_user` becomes `authenticated`, the setting is visibly present in `pg_db_role_setting`, and the session zone does not move.
- `ALTER ROLE **authenticator** SET TimeZone` is the live vector — MEASURED: it applies at connect (`source = user`) and **persists across the `SET ROLE`**, so every Data API request runs in that zone.

Consequence for anyone hardening this: **pinning or inspecting `authenticated` protects nothing.** The login roles are `authenticator` (Data API / web app), `pfin_etl` (`workers/etl`, direct psycopg login), and `pfin_provider_sync` (`workers/provider-sync`, post-cutover per §6.2 — migration `116`; `authenticator` until then). And a read-back executed as `postgres` — which is how `pg_prove` and a plain `psql` connect — observes **`postgres`'s** login-time settings, so it will read a clean `UTC | database` while every PostgREST request runs in another zone. **Inspect the catalog, or connect as the login role; do not infer from a `postgres` session.**

Three operational consequences, all load-bearing:

1. **⚠ NEVER set `PGTZ` in any container env, Coolify variable, or `.env`.** libpq (and therefore `psycopg` in `workers/etl`, and any libpq-backed client) sends `PGTZ` as a **startup parameter that overrides the database pin**. `TZ` alone does *not* — so the intuitive "just set `TZ=UTC` on the containers" is a **no-op** for the database session and must not be mistaken for this pin. `PGTZ` appears in no `.env.example` today; it must stay that way.
2. **Verify by `source`, not by value.** A read-back asserting only `TimeZone = 'UTC'` passes when the pin is entirely absent (the image default already says UTC) — that assertion can be satisfied without the discipline holding. `source = 'database'` is the one that proves the *declaration* is supplying the value, and it also catches both override vectors above (`client` / `user`).
3. **Sweep the catalog for role-level overrides.** `source` only reports the session you are *in*. The single check that covers every role — including ones created after this was written — is that **no role carries a `TimeZone` setting at all**, which is what makes the database pin authoritative rather than merely present.

**Capability-verified (2026-08-04), not assumed:** `ALTER DATABASE … SET timezone` succeeds under the `postgres` role as it actually ships in the Supabase image — `rolsuper = f`, but `datdba` owner, and ownership is sufficient. The setting lands in `pg_db_role_setting` and new sessions report `source = database`. At the time of that check, no role-level `TimeZone` override existed. One was found on `authenticator` later the same day and cleared on 2026-08-05 — a point-in-time observation, not a standing property, which is why the sweep below exists.

**Deploy-time verification (run after §6 migrations, before §10 sign-off):**

```sh
# (1) THE PIN — run as EACH login role the app actually connects as, not as `postgres`.
#     A `postgres` session reads `postgres`'s login-time settings and will show a clean
#     UTC|database while every PostgREST request runs in another zone.
#
#     ⚠ EVERY psql INVOCATION BELOW OPENS A FRESH CONNECTION, AND THAT IS LOAD-BEARING.
#       `alter database ... set timezone` reaches NEW SESSIONS ONLY. It never reaches a
#       session that was already open — so anything holding a long-lived pooled connection
#       across the migration (PostgREST, the web-app container, workers/etl, a psql left
#       open in another pane) keeps reporting the PRE-migration value indefinitely.
#       MEASURED on a scratch database, with the alter issued from a separate connection:
#         warm session  -> UTC        | configuration file   (unchanged, indefinitely)
#         fresh session -> Asia/Tokyo | database             (same instant, same database)
for URL in "$PROD_URL_AUTHENTICATOR" "$PROD_URL_PFIN_ETL"; do
  psql "$URL" -Atc "select current_user, setting, source from pg_settings where name='TimeZone'"
done
# REQUIRED, for every role: <role>|UTC|database
#   UTC|configuration file  -> TWO CAUSES. This line previously named only the first, and so
#                              instructed the operator to "fix" a pin that had already landed:
#                                (a) the migration did not apply here — value right BY ACCIDENT; or
#                                (b) you are not reading through a fresh session (see 1b).
#   *|user                  -> a role-level override on THIS LOGIN ROLE. See (2).
#   *|client                -> PGTZ is set in that container's environment. Remove it.

# (1b) DISAMBIGUATE (a) FROM (b) WITH THE CATALOG — it is SESSION-INDEPENDENT, so it answers
#      "is the declaration recorded?" without depending on the session that cannot see it.
#      Same move (T3) makes for the role vector: when a runtime probe structurally cannot
#      reach the property, prove it DECLARATIVELY from the catalog.
#
#      ⚠ THE `d.datname = current_database()` FILTER IS LOAD-BEARING. `setrole = 0` alone
#        selects database-level rows for EVERY database on the cluster, so a pin recorded
#        against a DIFFERENT database would satisfy this query and the operator would be
#        told the declaration is recorded when it is not recorded HERE. That is not a
#        theoretical mode: 061's own read-back names it ("applied to a different database
#        than current_database() resolved to"), and by the time anyone reaches §4.1 an
#        entirely unapplied 061 would already have failed the deploy loudly — so
#        wrong-database IS the most plausible surviving form of cause (a), i.e. exactly
#        the one this check exists to catch. Matches 061's read-back shape deliberately.
#
#      ⚠ ALSO LOAD-BEARING: select ONLY the unnested, anchored `c` — never `s.setconfig`.
#        This query reads the `setrole = 0` row, and that row carries
#        `app.settings.jwt_secret`. Selecting the array wholesale would print the LIVE JWT
#        SIGNING SECRET into this terminal and into anything capturing the stream. Same
#        rule as the sweep in (2); it applies here for the same reason.
#
#      ⚠ `-At -c`, NOT `-Atc` — DELIBERATE, do not normalize these flags. They are
#        semantically identical, so this looks like an inconsistency worth tidying. It is
#        not. The R3 anti-drift fence anchors on the SWEEP invocation in (2) below — the
#        `-Atc` spelling followed by a trailing line-continuation — and writing this block
#        that way too would give the fence a SECOND match, which it must not silently
#        resolve. Recorded rather than left to chance: a fence whose correctness depends
#        on the next author happening to pick a different flag spelling is not fenced, it
#        is lucky.
#        (This paragraph deliberately DESCRIBES that anchor instead of quoting it — an
#        earlier draft quoted it verbatim and thereby became the second match itself,
#        which the fence's ambiguity guard caught. Do not "helpfully" quote it here.)
#
#      ⚠ UNTIL THE R3 FENCE LANDS, UNIQUENESS OF THAT SWEEP INVOCATION IS HELD BY REVIEW
#        ALONE — no automated check enforces it on `main` yet. Any change to this file must
#        re-verify BY HAND that the spelling described above still occurs exactly ONCE,
#        AND THAT INCLUDES A PROSE-ONLY CHANGE: this file has already broken that property
#        once, in a comment written to warn about it, by an author who knew. So the usual
#        reassurance — "a careful editor would not do this" — is already disproven here.
#        Describe that invocation; never reproduce it.
psql "$PROD_DB_URL" -At -c "select c from pg_db_role_setting s join pg_database d on d.oid = s.setdatabase cross join lateral unnest(s.setconfig) as c where s.setrole = 0 and d.datname = current_database() and c ilike 'timezone=%'"
# A row (TimeZone=UTC)  -> the declaration IS recorded. The pin landed; the session you read
#                          through is STALE. Do NOT re-run or "fix" the migration. Recycle
#                          the connections — see the note below.
# No row               -> the migration really did not apply. Cause (a). Fix it.
#
# ⚠ AFTER THE PIN APPLIES, RECYCLE THE APP AND WORKER CONTAINERS. Their pooled connections
#   were opened before the pin and hold the pre-migration session zone until they reconnect.
#   A deployment that applies the pin without recycling is pinned AT THE DATABASE and unpinned
#   IN EVERY LONG-LIVED CONNECTION — the half-pinned shape this section exists to prevent,
#   reached from the other direction.
#   SEVERITY, stated honestly rather than inflated: in THIS deployment the pre-pin value is
#   ALSO UTC (the image's postgresql.conf), so a stale pool is MIS-LABELLED, not wrong, and
#   no date is currently computed incorrectly by one. It becomes a CORRECTNESS problem the
#   moment the two values differ — which is precisely what the measurement above shows.

# (2) THE SWEEP — no ROLE may carry a TimeZone at all, so the database pin is authoritative.
#     Covers roles that do not exist yet; catches the `authenticator` vector that a
#     `postgres`-session read-back structurally cannot see.
#
#     ⚠ TWO LOAD-BEARING CLAUSES — do not "simplify" either away. Both were absent in the
#       first version of this sweep, and each defect was found by RUNNING it:
#       * `s.setrole <> 0` scopes this to ROLE-level entries. 061's own database-level pin is
#         itself a `setrole = 0` row whose setconfig contains `TimeZone=UTC` — so without this
#         filter a CORRECTLY pinned database returns one row and this check STOPs the cutover
#         on the very declaration it exists to confirm. Worse than a false positive: the
#         operator learns "that row is always there" and starts eyeballing past it, which is
#         how the real row gets waved through.
#       * the `unnest` + `c ilike 'timezone=%'` form prints ONLY the timezone entry. Selecting
#         `s.setconfig` wholesale prints the entire array — and the `setrole = 0` row carries
#         `app.settings.jwt_secret` (the image provisions it there; /etc/postgresql.schema.sql),
#         i.e. it writes the LIVE JWT SIGNING SECRET to this terminal and into anything
#         capturing the stream: the Coolify deploy log, a Discord notification body, CI output.
#         Never widen the select list back to `s.setconfig`.
#
#     Kept query-identical — token-for-token, modulo indentation — to (T3) in
#     supabase/tests/01_session_timezone.sql, so the two cannot drift.
psql "$PROD_DB_URL" -Atc \
  "select r.rolname, d.datname, c as setting
     from pg_db_role_setting s
     join pg_roles r on r.oid = s.setrole
     left join pg_database d on d.oid = s.setdatabase
     cross join lateral unnest(s.setconfig) as c
    where s.setrole <> 0
      and c ilike 'timezone=%'"
# REQUIRED: zero rows. Any row -> that role's sessions outrank the pin. Clear it with
#   `alter role <role> reset timezone`
# ⚠ NOT `reset all` — these roles carry other load-bearing settings (`authenticator` ships with
#   session_preload_libraries=supautils,safeupdate + statement_timeout + lock_timeout), and
#   dropping them breaks the stack in a way that is not obviously connected to this change.

# Any deviation -> STOP. Do not cut over (§9); the NAV as-of path is wrong by up to a day,
# and nothing will error.
```

---

## 5. Secrets provisioning · 🔒 SECURITY-SENSITIVE (Sec joint-review gates this section)

Scope: inject production secrets into Coolify, honoring the CI/production non-overlap discipline. **This section is security-sensitive — Security Reviewer joint-review is mandatory before it locks** (secrets-manifest + ARCH §4.1 allowlist + Lock 13 territory).

Real artifacts this section binds to (all verified present):

- [`secrets-manifest.yml`](../secrets-manifest.yml) — the CI/production **non-overlap commitment**. Two disjoint sets:
  - `ci_only` (5 names — reserved distinct names; no production reach): `PLAID_SANDBOX_CLIENT_ID`, `PLAID_SANDBOX_SECRET`, `PDF_WORKER_SIGNING_KEY_TEST`, `SIMPLEFIN_TOKEN_TEST`, `BLS_API_KEY_TEST`.
  - `production_only` (10 names — Coolify-injected on the box; never in CI): `SUPABASE_SERVICE_ROLE_KEY`, `PDF_WORKER_SIGNING_KEY`, `PLAID_CLIENT_ID`, `PLAID_SECRET`, `SIMPLEFIN_TOKEN`, `WORKER_ADMISSION_SHARED_SECRET`, `DISCORD_WEBHOOK_URL`, `PFIN_DB_PASSWORD`, `FMP_API_KEY`, `BLS_API_KEY`. **`SUPABASE_ANON_KEY` is deliberately NOT in this set** — see the non-secret runtime-config list immediately below.
  - **Counts are load-bearing — check them, don't skim them.** The two lists above are a **hand-maintained mirror** of [`secrets-manifest.yml`](../secrets-manifest.yml); nothing enforces that they stay in sync, so they drift silently. The failure mode is asymmetric and unpleasant: a secret missing *here* isn't a fence breach (the non-overlap fence still passes — it reads the manifest, not this file), it's a **container that deploys without a secret it needs**. So: the `secrets-nonoverlap` job prints `N ci_only + M production_only` on every PR + push. If those numbers disagree with the `(5 names)` / `(10 names)` above, this enumeration has drifted — **the manifest is source of truth; fix this list.** Comparing two integers CI already emits is the cheap check; diffing two prose lists by eye is the one that fails. *(This is not hypothetical: both halves of the `SIMPLEFIN_TOKEN` / `SIMPLEFIN_TOKEN_TEST` pair were missing here and went unnoticed until SELF-214 — with the fence green throughout.)*
  - **Non-secret runtime config (NOT in `secrets-manifest.yml` — Sec-authorized, 2026-09-09):** two names are boot-required but deliberately absent from both the CI/production non-overlap sets above, because neither is a secret:
    - `PUBLIC_SUPABASE_URL` — the self-hosted Supabase stack's own gateway URL. Not confidential; it's the address the app's server process dials.
    - `PUBLIC_SUPABASE_ANON_KEY` — a `role: anon` JWT, publishable by construction. RLS plus the [ADR-029](../DECISIONS.md#adr-029) aal2 backstop are the controls that gate what an anon-scoped request can do — not keeping this value confidential.
    Both are read by `api/src/hooks.server.ts`'s boot-time env guard via SvelteKit's `$env/dynamic/public`, and both are declared (non-secret) in [`api/.env.example`](../api/.env.example). Inject both as **plain (non-secret) Coolify environment variables** on the `app` service, under these exact `PUBLIC_`-prefixed names — omitting either throws at boot. Do not add either to `secrets-manifest.yml` or root [`.env.example`](../.env.example): those enumerate confidential values, and listing a publishable JWT there would assert a blast radius that does not exist and would put a production-tier name on developer machines that must hold the local stack's own value instead.
  - **`WORKER_ADMISSION_SHARED_SECRET` (SELF-212 Option-C, C6-2) provisioning:** generate 256-bit (`openssl rand -hex 32`); inject as a Coolify **project-scoped SHARED variable** referenced by BOTH the api/ web-app service and the provider-sync worker service — one edit point, so rotation updates a single value. **Rotation:** update the shared var → **coordinated restart of BOTH** services (the constant-time compare mismatches mid-rotation, failing admission closed until both restart — a brief onboarding-only outage; acceptable). NOT the service_role key → RT-26 allowlist unchanged. This secret's SAME-value-on-both-tiers shape mirrors `PDF_WORKER_SIGNING_KEY` (web-app + PDF worker per SD-20).
  - **Fail-closed fence:** `scripts/ci/check-secrets-nonoverlap.py` runs as the `secrets-nonoverlap` job in `.github/workflows/security-scan.yml` on every PR + push to `main`; fails closed if the sets intersect, a set is missing/malformed, or a name is duplicated. The **distinct-naming rule** (any CI/test analogue takes a `*_SANDBOX` / `*_TEST` name) is the mechanism that keeps the sets disjoint.
- Per-surface `.env.example` files (each enumerates ONLY its container's permitted secrets — the enumeration *is* the confinement property):
  - [`.env.example`](../.env.example) — V1 web-app container (service_role + PDF signing key + Discord URL). ⚠ **No `PLAID_WEBHOOK_SECRET`, and no Plaid credential at all.** An earlier revision of this line said "Plaid creds + webhook secret"; both halves are wrong at the tree. The webhook secret was retired at [ADR-037](../DECISIONS.md#adr-037) — Plaid v27 webhook verification is asymmetric ES256/JWK against a PUBLIC key, so there is no shared secret to hold, and `.env.example` says so explicitly rather than merely omitting it. `PLAID_CLIENT_ID`/`PLAID_SECRET` are held by the **provider-sync worker only** (the delegated JWK fetch); keeping `api/src` credential-less is the load-bearing property that makes that delegation work. The variable name never appeared in this runbook — what survived here was a **prose paraphrase describing a secret `.env.example` no longer contains**, which is why a name-grep found nothing to sweep.
  - [`workers/etl/.env.example`](../workers/etl/.env.example) — `pfin_back_etl` container (discrete `PFIN_DB_*` + FMP + BLS + Plaid creds).
  - [`workers/pdf-render/.env.example`](../workers/pdf-render/.env.example) — PDF worker container (**exactly one** secret: `PDF_WORKER_SIGNING_KEY` — zero-DB-isolation per Lock 13 mod #2; RT-22 enforces no DB credential ever appears here).

> **STUB —** Fill in: the actual Coolify secret-injection procedure (per-service env-var entry), the generation/rotation procedure for each production secret (esp. `PDF_WORKER_SIGNING_KEY` — the SAME value on web-app + PDF worker per SD-20; and `SUPABASE_SERVICE_ROLE_KEY` — RT-26 ARCH §4.1-allowlist-confined), and the order of injection vs. first deploy. **Sec joint-review REQUIRED at lock.** Open discrepancies flagged in the artifacts to resolve here: (a) ARCH §5 frames the ETL DB secret as a single conn-string while incumbent code consumes discrete `PFIN_DB_*` — representation difference, reconcile deliberately; (b) ARCH §5 frames BLS as "free/open" (no key) while incumbent code requires `BLS_API_KEY` — reconcile with ARCH/Sec.

---

## 6. Apply migrations

Scope: apply the repo's `supabase/migrations/` against the fresh Postgres 17 instance, in order.

- Present migrations (verified): [`001_pfin_foundation.sql`](../supabase/migrations/001_pfin_foundation.sql), [`002_fn_mask_acct_number.sql`](../supabase/migrations/002_fn_mask_acct_number.sql).
- Phase 6 base-table migrations (SELF-187+) land incrementally — append them here as they're authored.
- **Ownership note:** migrations are **Architect-authored**; DevOps operates on CI's *consumption* of them (test-fixture spin-up per RT-15) and, here, on the production *apply* step. This runbook does not author migration content.

### 6.1 `pfin_etl` role provisioning — REQUIRED one-time deploy step · 🔒 SECURITY-SENSITIVE

**Applying the migrations is not sufficient to start the ETL.** Migration [`055_pfin_etl_role.sql`](../supabase/migrations/055_pfin_etl_role.sql) creates the ETL's dedicated login identity `pfin_etl` **NOLOGIN, with NO password** — deliberately inert, because a credential must never sit in a committed file. An operator switches it on at deploy time. *(SELF-214 Sec finding B8 → option (B), F/CTO-ratified 2026-08-02; ADR-041.)*

> **Precedence.** This procedure is described in three places — here, [`055`](../supabase/migrations/055_pfin_etl_role.sql)'s DEPLOY-TIME CREDENTIAL HANDOFF block, and [`workers/etl/.env.example`](../workers/etl/.env.example). **If they disagree, `055` wins** and the others are the copies to fix. Three artifacts describing one procedure is three chances to leave a retracted claim behind in a secondary copy.

**Ordering dependency — do not reorder:**

> **migrations applied (§6)** → **`pfin_etl` password set, *then* LOGIN flipped (this step — in that order)** → **`PFIN_DB_*` env injected (§5)** → **ETL container started (§7)**

Start the container before this step and it boots and cannot authenticate. That is fail-closed, not an exposure — but it is a guaranteed failed deploy.

**The step.** Run **once** against the target database, in an interactive `psql` session, as an operator (never from a committed file). **Two statements, and the order is load-bearing:**

```
\password pfin_etl           -- prompts; verifier computed CLIENT-SIDE; role still NOLOGIN → inert
ALTER ROLE pfin_etl LOGIN;   -- carries no secret; safe in shell history and server logs
```

`\password` sets **only** the password — it does *not* set `LOGIN`. That is why this is two steps and why the order matters: the credential lands while the role is still `NOLOGIN`, and `LOGIN` then flips onto an already-credentialed role, so **LOGIN-with-no-password never exists at any instant** — the state `055` is built to prevent. Same property the earlier single-statement form aimed at, reached differently.

**The single-statement form `ALTER ROLE pfin_etl WITH LOGIN PASSWORD '…'` is PROHIBITED.** Wherever statement logging is on, it writes the credential to the server log in cleartext. **The prohibition does not depend on any per-stack measurement** — do not measure a target, find logging off, and conclude it lapses. `\password` also keeps the secret out of psql's own `~/.psql_history`, which records typed statements in plaintext by default.

> **What was measured, and where:** `log_statement = ddl` was measured on the **local** stack — so the exposure is established, not theoretical. The V1 production stack does not exist yet and has **not** been measured. Treat statement logging as **enabled** on any target until verified otherwise there; assuming it off is the failure-open direction. (`log_statement` is not the only relevant knob — `log_min_duration_statement` can cause a statement to be logged in full. `show log_statement; show log_min_duration_statement;` is the pair that settles it for a given target.)

**Generate the password with `openssl rand -hex 32`** (256-bit), mirroring the `WORKER_ADMISSION_SHARED_SECRET` convention in §5. This is not incidental: the residual risk below is an *offline attack bounded by the secret's entropy*, so a high-entropy generated value is what makes that residual acceptable. A human-chosen password would not be.

> **⚠ Be precise about what this buys — do not write "nothing is logged."**
> - **Plaintext never leaves the client.** `\password` prompts and computes the verifier client-side per `password_encryption` (`scram-sha-256` here), so the cleartext reaches neither the wire, the server log, nor `.psql_history`.
> - **The verifier IS still logged.** `\password` sends `ALTER USER … PASSWORD 'SCRAM-SHA-256$4096:…'`, which is DDL and is captured under `log_statement = ddl`. But a verifier **is not a usable credential**: it stores `StoredKey` + `ServerKey`, a client proof requires `ClientKey`, and `StoredKey = H(ClientKey)` does not invert — possession of the logged verifier does not let an attacker authenticate as `pfin_etl`.
> - **The residual is an offline attack**, bounded by the secret's entropy and the **4096** iteration count. Acceptable against a high-entropy generated secret, and categorically better than cleartext, which is replayable immediately with zero work.
>
> Claiming the stronger property would be the same failure shape as a test asserting a privilege it never exercised — just pointed at a log instead of a battery.

**Operator privilege:** `\password` is `ALTER USER` underneath, so the operator must be superuser or hold `CREATEROLE` / `ADMIN OPTION` on the role.

The password value is the **`pfin_etl` credential** — a *different value* from provider-sync's `PFIN_DB_PASSWORD` (which is the `authenticator` credential). Same secret **name**, different secret **value**, per container; see [`secrets-manifest.yml`](../secrets-manifest.yml). Then set the ETL container's env (§5): `PFIN_DB_USER=pfin_etl` (non-secret username) + `PFIN_DB_PASSWORD=<same value>` (`production_only`).

**Verify before starting the container** (read-only; expect `t` / `f`):

```sql
select rolcanlogin, rolinherit, rolsuper, rolbypassrls
  from pg_catalog.pg_roles where rolname = 'pfin_etl';
-- expect: rolcanlogin = t, rolinherit = f, rolsuper = f, rolbypassrls = f
```

`rolcanlogin = f` means this step has not run. `rolinherit = t` means the role is misconfigured and the NOINHERIT posture is defeated — stop and fix (`055` raises a `WARNING` for both cases on re-apply, but its idempotency guard deliberately does **not** rewrite attributes on a pre-existing role — auto-repair would flip a *legitimately* `LOGIN` production role back to `NOLOGIN` and take the ETL down on the next migration run. It reports; it does not repair. So this check is the operator's own confirmation).

> **Do not extend this query with `pg_roles.rolpassword`.** That column is the literal constant `'********'` for every role, so `rolpassword is not null` is **always true** and proves nothing — it is a metric that reads like a check. If you need to confirm a password is actually set, read `pg_authid.rolpassword` (superuser-only; it may be unreadable depending on the applying role). **Under the two-step above this check is worth running, not redundant:** `rolcanlogin = t` only proves *step 2* ran, and step 2 without step 1 is precisely the dangerous ordering below.

**Rotation** — `\password pfin_etl` (same prompt-and-hash path; `LOGIN` is already set, so no second statement) **+ restart the ETL container ONLY**. No coordinated PostgREST / provider-sync redeploy: escaping the [ADR-023](../DECISIONS.md#adr-023) C1 rotation coupling is the entire point of the dedicated role. C1 still binds PostgREST + provider-sync to each other; the ETL is out of it.

**Revocation / kill-switch** — `ALTER ROLE pfin_etl NOLOGIN` stops the ETL **and nothing else**. This is the independent-revocability property (B) was chosen for: a compromised batch container is cut off without downing the public Data API.

**Two failure modes — only one of them is safe:**

| what went wrong | result |
|---|---|
| **Step 2 skipped** (`\password` ran, `LOGIN` never set) | Role stays `NOLOGIN` → ETL fails at connect with `role "pfin_etl" is not permitted to log in`. Loud, immediate, **safe** — an outage, never an exposure. |
| **Step 2 run without step 1** (`LOGIN` set, password never set) | ⚠ **The one dangerous ordering.** Succeeds silently and leaves exactly the LOGIN-with-no-password state `055` is shaped to prevent. |

`055`'s `WARNING` branch for a pre-existing LOGIN-with-no-password role was written to catch partial *manual* provisioning, but it catches this mis-ordered deploy too — on the next migration re-apply. Do not remove that guard thinking it only covers the older case.

> **⚠ SUPERSEDED at PR #675 (2026-09-09).** This block previously read: *"Do not follow `055`'s own re-apply warning text. If that `WARNING` branch fires, its message names the **PROHIBITED single-statement form** — `ALTER ROLE pfin_etl WITH LOGIN PASSWORD '<plaintext>'` — as one of the two ways to resolve the state. Do not run it: per Sec B10, statement logging writes the credential to the server log in cleartext. Use the sanctioned two-step handoff above instead — `(1) \password pfin_etl` then `(2) ALTER ROLE pfin_etl LOGIN;` — or disable the role (`ALTER ROLE pfin_etl NOLOGIN`) if that's the intended resolution. The warning text itself is booked for correction at [`BACKLOG.md`](../BACKLOG.md) §7.36 item 6."* `055`'s warning now prescribes the two-step handoff and names the single-statement form as prohibited; this note stays as the record that it once did not.

> **⚠ Flag #10 — RESOLVED 2026-08-02 (Sec joint-review B10); retracted in place.** This block previously read *"Open flag (#10) — secret-in-statement handling, Sec-review before this section locks … I have **not** verified what the self-hosted Supabase stack sets, or whether it redacts."* **Every clause of it is now either false or moot, and it is quoted rather than deleted because the referent moved out from under it.** The `ALTER ROLE … PASSWORD '<literal>'` it points at *"above"* is no longer an instruction in this section — the prescribed step is the `\password` + `ALTER ROLE … LOGIN` two-step, and the single-statement form is **prohibited**. `log_statement = ddl` **was** measured — on the **local** stack; the production stack remains unmeasured, which is precisely why the prohibition above is **measurement-independent** and does not lapse if some target is later found with logging off. The *"or whether it redacts"* half is simply false: Postgres does **not** redact passwords from the statement log. The mitigation the block proposes weighing — *"pass a pre-computed SCRAM-SHA-256 verifier … so no plaintext ever reaches the server"* — **is** what `\password` does; its other suggestion, an interactive session, B10 ruled **insufficient** (it dodges *shell* history and lands in psql's own plaintext `~/.psql_history`). **Residual, unchanged and accepted:** the SCRAM verifier **is** still logged, which is why the secret must be high-entropy and machine-generated (B10 condition). See the step above and the flag-ledger row for #10.

> **STUB —** Fill in: the apply mechanism against self-hosted Supabase (`supabase db push` / `supabase migration up` vs. a CI/Coolify-driven apply), the idempotency/ordering guarantees, and how to verify each migration landed (e.g., RLS policies present, `fn_mask_acct_number` callable). Keep the migration list current as Phase 6 adds tables.

### 6.2 `pfin_provider_sync` role provisioning — REQUIRED one-time deploy step · 🔒 SECURITY-SENSITIVE

**Applying the migrations is not sufficient to cut provider-sync over.** Migration [`116_pfin_provider_sync_role.sql`](../supabase/migrations/116_pfin_provider_sync_role.sql) creates provider-sync's dedicated login identity `pfin_provider_sync` **NOLOGIN, with NO password** — deliberately inert, mirroring [`055`](../supabase/migrations/055_pfin_etl_role.sql)'s `pfin_etl`. An operator switches it on at deploy time, in the **SAME Phase-7 deploy pass that provisions `pfin_etl`** (BACKLOG §7.6 S5 AC — one operation reaches a consistent role-graph rather than carrying a half-applied convention across releases). *(ADR-019 Condition C2, renamed/promoted by ADR-041; Sec joint-review AMBER on PR #671, condition C3.)*

> **Precedence and procedure.** This step follows the **same two-step credential handoff as §6.1's `pfin_etl` step** — see §6.1 above and `116`'s own DEPLOY-TIME CREDENTIAL HANDOFF block, which is canonical for this role if this section and `116` disagree. `055`'s CONTRACT block was corrected in place on 2026-09-08 (Sec C5) and now agrees with its handoff block; `116` remains canonical for this role.

**The step.** Run once against the target database, in an interactive `psql` session, as an operator (never from a committed file):

```
\password pfin_provider_sync          -- prompts; verifier computed CLIENT-SIDE; role still NOLOGIN → inert
ALTER ROLE pfin_provider_sync LOGIN;  -- carries no secret; safe in shell history and server logs
```

Same load-bearing order as §6.1: the credential lands while the role is still `NOLOGIN`, and `LOGIN` then flips onto an already-credentialed role, so LOGIN-with-no-password never exists at any instant. The single-statement `ALTER ROLE pfin_provider_sync WITH LOGIN PASSWORD '…'` form is **PROHIBITED**, for the same reason as §6.1 — statement logging writes the credential to the server log in cleartext, and the prohibition does not depend on any per-stack measurement. Generate the password with `openssl rand -hex 32`.

The password value is **provider-sync's own credential** — a different value from `pfin_etl`'s, and, post-cutover, no longer the `authenticator` credential. Same secret **name** (`PFIN_DB_PASSWORD`), different secret **value**, per container; see [`secrets-manifest.yml`](../secrets-manifest.yml). Then set the provider-sync container's env (§5): `PFIN_DB_USER=pfin_provider_sync` (non-secret username, changed from `authenticator`) + `PFIN_DB_PASSWORD=<this role's value>` (`production_only`).

**Verify before restarting the container** (read-only; expect `t` / `f`):

```sql
select rolcanlogin, rolinherit, rolsuper, rolbypassrls
  from pg_catalog.pg_roles where rolname = 'pfin_provider_sync';
-- expect: rolcanlogin = t, rolinherit = f, rolsuper = f, rolbypassrls = f
```

**⚠ Creating and flipping the role is NOT the same as cutting the container over — the two half-applied states are asymmetric** (Sec joint-review condition C4; `116`'s own header carries the same analysis). Env-switched-but-role-absent fails **loudly**: provider-sync fails at connect (`role "pfin_provider_sync" is not permitted to log in`) — an outage, never an exposure. Role-present-but-env-unswitched is **silent**: provider-sync keeps running as `authenticator`, the rotation coupling stays live, and every catalog read looks finished — `rolcanlogin = t` proves only that this deploy step ran, and proves nothing about which credential the container is actually using. The dangerous half is the silent one, and the query above cannot see it: it reads the role's catalog state, not the container's effective identity.

**Post-cutover check — read the CONTAINER's effective identity, not the role catalog:**

1. **Effective `PFIN_DB_USER`.** From the provider-sync Coolify service's actual injected env (not this repo's `.env.example`), confirm `PFIN_DB_USER=pfin_provider_sync`.
2. **`pg_stat_activity` read of the connected identity** (Sec joint-review C4 option C — composes with, does not substitute for, check 1):
   ```sql
   select distinct usename from pg_stat_activity where application_name = 'provider-sync';
   ```
   This reads the container's *effective* identity from the server side rather than trusting its env file. **Precondition, not yet true: `workers/provider-sync/src`'s `TenantBoundClient` connection does not currently set `application_name`** — this query returns zero rows until that lands. Do not run this check, see an empty result, and read it as "cutover incomplete" — confirm `application_name` is being set before relying on this check at all. Booked at [`BACKLOG.md`](../BACKLOG.md) §7.36 item 2.

**Rotation** — `\password pfin_provider_sync` (same prompt-and-hash path; `LOGIN` is already set, so no second statement) **+ restart the provider-sync container ONLY**. No coordinated PostgREST / `pfin_etl` redeploy.

**Revocation / kill-switch** — `ALTER ROLE pfin_provider_sync NOLOGIN` stops provider-sync **and nothing else**.

**Two failure modes — only one of them is safe** (same shape as §6.1):

| what went wrong | result |
|---|---|
| **Step 2 skipped** (`\password` ran, `LOGIN` never set) | Role stays `NOLOGIN` → provider-sync fails at connect with `role "pfin_provider_sync" is not permitted to log in`. Loud, immediate, **safe** — an outage, never an exposure. |
| **Step 2 run without step 1** (`LOGIN` set, password never set) | ⚠ **The one dangerous ordering.** Succeeds silently and leaves exactly the LOGIN-with-no-password state `116` is shaped to prevent. |

`116`'s `WARNING` branch for a pre-existing LOGIN-with-no-password role catches this mis-ordered deploy on the next migration re-apply, same as `055`'s does for `pfin_etl` — do not remove that guard thinking it only covers the ETL case.

---

## 7. Workers

Scope: deploy the background-worker containers. Per ARCH Lock 13, the V1 runtime is a **hybrid 3-container topology** on Coolify: (1) V1 web-app, (2) `pfin_back_etl` ETL, (3) Node PDF worker — plus the Phase-6/V1.5 cron + scheduled-poll additions.

- **`pfin_back_etl` (ETL)** — `workers/etl/`, Coolify **Base Directory** `workers/etl/`; Dockerfile [`workers/etl/Dockerfile`](../workers/etl/Dockerfile) (DevOps-owned). Python ETL (BLS CPI + FMP financials → Supabase). **Direct-Postgres** transport (`PFIN_DB_*`, login role **`pfin_etl`** — its OWN dedicated identity, *not* provider-sync's `authenticator`; writes AS `service_role` via `SET ROLE`) via **TenantBoundConnection** (Lock 13 mod #3). **`PFIN_DB_USER=pfin_etl`** (non-secret username) + `PFIN_DB_PASSWORD` (the `pfin_etl` credential, `production_only`). **This container cannot start successfully until §6's role-provisioning step has run** — see the ordering dependency there. **Forward discipline:** all `pfin` DB access binds `users_id` via TenantBoundConnection — TBC + `fence-tbc` coverage land Wave 6; incumbent currently uses SQLAlchemy `create_engine`.
- **Node PDF worker** — `workers/pdf-render/`, Dockerfile [`workers/pdf-render/Dockerfile`](../workers/pdf-render/Dockerfile) (currently a placeholder; Backend adds Puppeteer app code at Wave 6). **Zero DB reach by design** (Lock 13 mod #2) — NO database libraries, credentials, or network reach; reaches data only via the web-app's `/internal/pdf-render` endpoint under a short-lived signed JWT. RT-22 fence enforces the Dockerfile credential/Postgres-client absence.
  - **`PDF_WORKER_SIGNING_KEY` length precondition (A5 follow-up (3)) — verify BEFORE the worker's first deploy.** The web-app fails closed when `PDF_WORKER_SIGNING_KEY` is under 32 characters; the PDF worker itself enforces no minimum-length floor. That asymmetry means a short value is caught on the web-app side only — if the web-app container happens to start first, or if the two containers are ever given different values, the PDF worker can come up and accept requests under a key too weak for the web-app's own check to have allowed. Before the worker's first deploy: confirm the Coolify-injected `PDF_WORKER_SIGNING_KEY` value is **at least 32 characters**, and confirm it is the **SAME value on both the web-app and PDF worker containers** (per SD-20 — this is the shared-secret pair the signed-JWT handshake depends on).
- **`provider-sync` (Plaid/SimpleFIN ingest)** — `workers/provider-sync/`, Coolify **Base Directory** `workers/provider-sync/`; Dockerfile [`workers/provider-sync/Dockerfile`](../workers/provider-sync/Dockerfile) (DevOps-owned). The 4th Coolify unit (ADR-019 amendment) — the FIRST DB-touching **Node** worker. **Direct-Postgres** transport (`PFIN_DB_*`, login role `authenticator`, writes AS `service_role` via `SET LOCAL ROLE` per ADR-023) via **TenantBoundClient** (Lock 13 mod #3; `fence-tbc-node` enforces at PR-time). **OFF the RT-26 allowlist by design** — no `SUPABASE_SERVICE_ROLE_KEY`, no `@supabase/supabase-js`. Env contract: [`workers/provider-sync/.env.example`](../workers/provider-sync/.env.example).
- **`provider-sync` SELF-212 admission endpoint (Option C, internal-only) — deploy config:**
  - **Build pack = Compose (b-i).** Coolify consumes the committed [`workers/provider-sync/docker-compose.yaml`](../workers/provider-sync/docker-compose.yaml) (not the bare Dockerfile build pack). This is what makes the admission endpoint's exposure surface **committed + lintable** (the `fence-admission-bind` CI job / RT-27 network-exposure layer). The admission port (`8081`) is `expose:`-only — **NEVER add a published `ports:` mapping and NEVER assign a Coolify Domain / Traefik `Host()` label to this service.**
  - **CA-4 — SAME Coolify project (hard prerequisite):** the api/ web-app service and the provider-sync service **MUST** live in the **same Coolify project** so internal DNS `http://provider-sync:8081` resolves (Coolify's internal network is per-project). Cross-project placement breaks internal reach **and** tempts a public-Domain "fix" — the exact silent-exposure regression RT-27 / §10 fences. Verified at §10 smoke.
  - **CA-1 — deploy-time public-route env verification:** at first deploy (and after any Coolify upgrade), dump the admission container's actual env and confirm the worker's limb-(a) prefix regex (`^(COOLIFY_FQDN|COOLIFY_URL|ADMISSION_PUBLIC_URL)$` or `^SERVICE_(FQDN|URL)_`) would match Coolify's real injected FQDN/URL var names for that version — because those names are Coolify-version-dependent, and a rename must not silently slip a Domain past the tripwire. Var-name set + rationale: [`temp/self212-devops-ca1-coolify-route-envvars.md`](../temp/self212-devops-ca1-coolify-route-envvars.md).
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

- **TZ-1 — database TimeZone pin read-back (§4.1; ship-block; DevOps-owned deploy assertion):** assert `select setting, source from pg_settings where name='TimeZone'` returns exactly **`UTC` / `database`** against the production database, and against the connection *each* container actually uses (web-app and `workers/etl` — a per-container `PGTZ` would override the pin for that container alone, and only that container's reads would be wrong).
  - **`source` is the assertion, not `setting`.** `UTC | configuration file` means the pin never applied and the value is right *by accident* — that is the exact unmeasured premise §4.1 exists to remove, and it reads identical to success if you only check the value.
  - **Run it as each LOGIN role (`authenticator`, `pfin_etl`, `pfin_provider_sync`) — never as `postgres` — and add the catalog sweep.** MEASURED (§4.1): per-role settings apply at login and `SET ROLE` does not re-apply them, so `ALTER ROLE authenticator SET TimeZone` moves every Data API request while a `postgres` session still reads `UTC | database`. A read-back that connects as `postgres` **structurally cannot see the one role-level vector that exists.** Pinning or inspecting `authenticated` protects nothing — it is not the login role. `pfin_provider_sync` is a login role from its §6.2 cutover onward; before cutover it connects as `authenticator` and is already covered by that entry.
  - **Why this is deploy-time and cannot be delegated to CI:** QA's [`supabase/tests/01_session_timezone.sql`](../supabase/tests/01_session_timezone.sql) asserts this property of the **ephemeral CI container**, and says so in its own header — it cannot observe the deployment. Two claims, two instruments; a green CI is never evidence about production here.
  - Gate this **before** §9 teardown. A failure is a silent up-to-one-day error in the §2.1.1 NAV headline and open-account count, with nothing erroring — not a degraded surface.
  - **⏸ TZ-1b — wire the R3 drift sweep before sign-off (ratified 2026-08-06; NOT YET ACTIVE).** TZ-1 is a **one-shot** assertion: it proves the pin is correct *at deploy*, and says nothing about the next six weeks. The vector is **drift-shaped** — the real instance arrived on a stack nobody was deploying — so a deployment that passes TZ-1 and never wires the recurring sweep is verified once and unmonitored thereafter. **Wire the §7 Scheduled Task (R3) as part of this gate**, and confirm one run has reported to Discord (§8) before §9 teardown. Full rationale, options considered, and the two-privilege-level split: **§7, "TimeZone drift sweep (R3)"**. **⚠ It is detection with bounded latency, not prevention** — do not let its presence read as "the pin cannot drift".
  - **⏸ Also at first deploy: the PROVENANCE limb.** Assert `select 1 from supabase_migrations.schema_migrations where version = '061'` returns a row. **What it buys is provenance and nothing else** — it distinguishes *our* declaration from a **hand-run `alter database … set timezone`**, which TZ-1's `source` reading cannot do once a database-level entry exists **by any route**. That is not hypothetical: exactly such an entry was found on a dev stack on 2026-08-05, reporting a clean `UTC | database` while `061` had never been applied there. *(It does **not** separate "by declaration" from "by accident, no declaration" — TZ-1 already does that: `source = database` means a database-level declaration exists, and the no-declaration case reports `configuration file`, which TZ-1 rejects.)*
    - ⚠ **It proves the migration RAN, not that the declaration SURVIVES.** `schema_migrations` is **append-only**: a later `alter database … reset timezone` leaves the `061` row sitting there while the declaration is gone. **Do not read a history row as current state** — that is the recorded-vs-effective conflation [`061`](../supabase/migrations/061_pin_database_timezone_utc.sql)'s own CONTRACT warns about, one layer out and in the opposite direction. *(The limb was originally named "declaration-applied", which invited exactly that reading; renamed for the same reason.)*
    - **Three questions, three instruments — they compose, none substitutes:** **provenance** (`schema_migrations` — did our migration run here?) · **current state** (the §4.1 (1b) catalog read — is a database-level declaration recorded right now?) · **effective value** (TZ-1's `setting` / `source` — what is this session actually resolving?).
    - **This limb needs the migration-applying identity** (`authenticator` gets `permission denied for schema supabase_migrations`), which is why it lives here at deploy time and not in the unprivileged recurring sweep.

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
| 11 | DB TimeZone pin — runbook §4.1 + §10 TZ-1 landed; **the pin itself needs an Architect-authored migration** (`ALTER DATABASE … SET timezone='UTC'`). Until it lands, production's UTC is an image default, not a declaration | Architect (authors) / DevOps (verifies) | §4.1 / §10 |
| 10 | ✅ `ALTER ROLE … PASSWORD` plaintext handling — **resolved**: measured `log_statement = ddl` (exposure real, not theoretical); single-statement form prohibited, replaced by the `\password` + `ALTER ROLE … LOGIN` two-step (§6.1). Sec-ruled | DevOps + Sec | §6.1 |

> **STUB —** This runbook is a skeleton. Each `> **STUB —**` marker above is a fill-in point as Phase 6 reveals the operational detail. Do not treat any section as complete until its STUB marker is removed and (for §5 + fence-touching content) Sec joint-review has signed off.
