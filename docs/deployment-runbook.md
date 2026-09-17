# Deployment Runbook — V1 greenfield stand-up

> **Status: SKELETON (Phase 6 entry, 2026-06-29).** This is a stub we fill in incrementally as Phase 6 reveals requirements — **not** a finished runbook. Each section carries a one-line scope note and a `> **STUB —**` marker naming what fills it in and when. Placeholders over fabrication: where a value isn't decided yet, it's flagged, not invented.
>
> **Doc convention:** Markdown (consistent with [`docs/linear-setup.md`](linear-setup.md) — an operational how-to that "answers *how*" per WORKFLOW.md). Not an HTML artifact (those are the canonical reference layer — PRD / ARCH / SECURITY); a runbook is an operational procedure, so Markdown is the right home.
>
> **Owner:** DevOps. **Security-sensitive sections** (§5 Secrets, plus any fence-touching content) gate on Security Reviewer joint-review before lock.

---

## Overview & principles

Scope: what this runbook is, and the non-negotiable principles that shape every step below.

> **One-command scripted spine.** `scripts/standup.sh --apply` runs §1+§3 ([`provision-vps.sh`](../scripts/provision-vps.sh)), §4 ([`provision-supabase-stack.sh`](../scripts/provision-supabase-stack.sh)), and the real-key mint ([`mint-supabase-jwt-keys.sh --verify-live`](../scripts/mint-supabase-jwt-keys.sh)) as one operator invocation, fail-fast, carrying the box's IP from stage 1 into stages 2–3 automatically. Same convention as its siblings: no flag = preflight (read-only); `--apply` executes. It does **not** cover §2 (DNS), §5 (secrets entry), §6/§6.1/§6.2 (migrations + interactive role provisioning), or §7 (worker Coolify resources) — those still need a human decision or a console; `scripts/standup.sh --help` enumerates them. The per-section detail below is the "what/why" the wrapped scripts implement — read it when you need the reasoning, run the one command when you just need the box up.

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
| **Hetzner Cloud API token, named `HETZNER_API_TOKEN`** | Creates the CAX21 server, primary IPs, firewall, and SSH keys — `scripts/provision-vps.sh` needs it; this is the scripted path §1 actually uses now, not an alternative to it. **Where:** Hetzner Cloud Console → the project → Security → API Tokens → Generate — verify that path live, the console moves. **Permission:** Read & Write (the script creates resources; a read-only token can't). Put it in the repo-root `.env` (gitignored) under exactly that name — see `scripts/provision.env.example`. Renamed 2026-09-10 from `HETZNER_API_KEY`; the script does not accept the old name as a fallback, it dies naming both spellings if it finds the old one. **This is the one remaining browser step in the entire stand-up** — every other credential this flow needs is either F/CTO-supplied non-secret input or minted on the box by the scripts themselves. Lifecycle: needed only while `provision-vps.sh` runs; never enters Coolify or this repo; revoke it in the console afterward if you'd rather not leave it live. |
| **Coolify admin email, name, and password**, named `COOLIFY_ADMIN_EMAIL` / `COOLIFY_ADMIN_NAME` / `COOLIFY_ADMIN_PASSWORD` | The credential F/CTO actually logs into the Coolify dashboard with. **Human-chosen, not generated** — everything else these scripts touch is minted on the box, but a random password defeats the point of having a login. Put in the repo-root `.env` (see `scripts/provision.env.example`) or leave unset and `provision-vps.sh --apply` prompts for them (password twice, confirmed) if run from an interactive terminal. `--reset-admin-password` changes just the password later, same source (`.env` or prompt). |
| **Domain registrar access** for the eventual production hostname | §2 (DNS) is an open F/CTO decision (reuse `pfindash.com` vs. a new domain) — out of scope for this PR, but registrar access is F/CTO-only regardless of which way that decision goes. |
| **An SSH keypair F/CTO controls** | The key whose **public** half is installed on the box at creation (§1) for key-only root/operator access. The private half never leaves F/CTO's machine; it is not a repo artifact. |
| **Production secret values** — `SUPABASE_SERVICE_ROLE_KEY`, `PLAID_CLIENT_ID`/`PLAID_SECRET`, etc. (names only, per [`secrets-manifest.yml`](../secrets-manifest.yml) `production_only`) | Entered directly into Coolify's UI at §5 (STUB, not this PR). Never transit chat, a file, or an agent's context. |

**DevOps-preparable** (no F/CTO-only credential required to produce these; can happen before the box exists):

| Item | What it's for |
|---|---|
| This runbook's §1/§3 procedures (this PR) | The executable steps F/CTO runs once the F/CTO-only items above are in hand. |
| Coolify itself | No separate account or license needed — Coolify is **self-hosted**, installed by `scripts/provision-vps.sh` directly onto the box F/CTO provisions in the same run. Its own admin account is created non-interactively by that same script (§3) — no browser step; the credential inputs are the `COOLIFY_ADMIN_*` row above, F/CTO-supplied, never generated. |
| Supabase CLI (`supabase`) | Only needed locally/in CI for authoring and dry-running migrations (§6) — not required to provision the box or install Coolify. Not a §1/§3 prerequisite. |
| GitHub repo access for Coolify's source connection (§3) | An existing asset — this repo, on GitHub, with F/CTO's account already having admin access. §3 documents connecting Coolify to it as a step, not a new account to obtain. |

**Not yet enumerable — deferred to their owning sections:** exact secret values (§5, STUB) and the DNS registrar's specific hostname (§2, open F/CTO decision). The Coolify admin credentials are now pre-obtainable — see the `COOLIFY_ADMIN_*` row above — not created live during §3 as this line previously said.

---

## 1. Provision the VPS

Scope: stand up a fresh virtual server to host Coolify + all V1 containers.

**Execute this section with `scripts/provision-vps.sh` — read the rest of §1 for the rationale, not as a set of hand-run steps.** F/CTO directive 2026-09-10: the stand-up must be a scripted re-run a stranger can execute, not a hand-run sequence. The script covers this entire section (Hetzner provisioning) **and** §1's hardening steps **and** §3's Coolify install and admin bootstrap, over one `--apply` invocation — preflight by default (read-only), idempotent (a re-run against an already-provisioned, already-hardened box reports "already satisfies" rather than re-applying). What follows below is the "what and why" this script implements, kept because the script's own comments cite it and a rebuild years from now needs the reasoning, not just the commands.

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

   **Reload the right unit — it is not `sshd`.** Measured 2026-09-11 on the real box, `--apply`: `systemctl reload sshd` fails with `Unit sshd.service not found.` **Ubuntu 24.04 ships `ssh.service`, not `sshd.service`, and it's socket-activated** — `systemctl list-unit-files --type=service` shows `ssh.service disabled` / `ssh.socket enabled`: `ssh.socket` owns port 22 and spawns a fresh `ssh.service` instance per connection, which reads config fresh every time, so between connections `ssh.service` is normally *inactive*, not just named differently. `scripts/provision-vps.sh` now detects the unit (`sshd.service` if present, else `ssh`) and uses `systemctl try-reload-or-restart <unit>` — reload if running, do nothing if not (a plain `reload-or-restart` would start a second listener fighting the socket for port 22). Doing this by hand: run `sshd -t` first regardless of which command line you copy — a bad drop-in reloaded is how you lock yourself out.
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

`Permission denied (publickey)` or a closed connection is correct. If this instead **prompts for a password**, `sshd_config`'s `PasswordAuthentication no` either was not applied or the running daemon was not reloaded after editing it (`systemctl try-reload-or-restart ssh` — see step 2's unit-name note above, it is not `sshd` on Ubuntu 24.04) — this is the single most common **looks-fine-but-wrong** case here: the file can read `no` on disk while the running daemon still has the old value in memory, and a login attempt that never gets this far to notice (because the operator always logs in with a key anyway) will not catch it.

```sh
# (3) Firewall — confirm only the intended ports are reachable from outside.
nmap -Pn -p 22,80,443,5432,6543,8000,8081 <box-ip>   # run from OUTSIDE the box's network
```

| Result | Reading |
|---|---|
| `22, 80, 443` open; `5432`, `6543`, `8000` **filtered**; `8081` **filtered/closed** | **Correct.** |
| `8000` shows **open** | **Wrong.** The firewall did not apply, or a rule was added by hand. The dashboard is meant to be unreachable from the internet entirely — reach it over the SSH tunnel above. Fix before installing Coolify, not after. |
| `5432` or `6543` shows **open** | **Wrong, and load-bearing for the same reason as `8081` below** — nothing should ever publish the Supabase pooler's ports to the host. At *this* point in the sequence (before §3/§4) neither port has anything to answer on yet, so `filtered` here only proves the firewall rule exists, not that the datastore is actually unpublished later — that load-bearing check is §10's, after §4 deploys the stack and Docker has programmed its own NAT rules. This is a one-time provisioning-stage baseline with **no recurring watcher**: re-verify at §10, don't assume this result still holds by then. |
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
- **Resolved 2026-09-10 — and resolved the OTHER way:** F/CTO scoped `studio` IN but chose the SSH-tunnel form, so **no subdomain and no Domain assignment is provisioned for it, then or ever.** See §4's `studio` row.

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

> This section (install + admin bootstrap) is executed by `scripts/provision-vps.sh`'s Phase 2, the same run as §1 — see the Overview's "One-command scripted spine" note. `scripts/standup.sh --apply` runs it as its stage 1, alongside §4 and the key mint.

**Status (2026-09-09): install and first-run setup DONE.** Coolify `4.3.18` is installed and all six containers (`coolify`, `coolify-db`, `coolify-redis`, `coolify-proxy`, `coolify-realtime`, `coolify-sentinel`) report healthy. The first-run admin account has been created and claimed (F/CTO). A `localhost` server is registered in Coolify — this is Coolify's own auto-created entry for the box it runs on, not a separate provisioning step. A GitHub source row connecting this repo exists. **Not yet done:** Domain assignment for `app` (blocked on §2's DNS cutover), the four-service topology below, and the ARCH §6 item (f) auto-deploy webhook.

- Deploys go through the **Coolify UI**, not from chat or CI (per ARCH §5). This repo's job is to make the repo-side artifacts (Dockerfiles, `.env.example` contracts) deploy cleanly when F/CTO triggers a deploy.

**Install method — pinned, not `latest`.** Coolify's installer is a single script (`coolify.io/docs/get-started/installation`, read 2026-09-09) that supports installing an exact version by passing it as an argument:

```sh
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash -s <version>
```

**How to determine `<version>` at execution time (not fixed in this doc, because the right value changes and a stale pin here would be worse than no pin):** read `https://cdn.coollabs.io/coolify/versions.json` immediately before installing and take the `coolify.v4` value — **as read live on 2026-09-09 while authoring this section, that value was `4.3.18`; treat that as an illustration of the mechanism, not the version to install.** Omitting `<version>` entirely (`bash` with no argument) installs whatever that file currently resolves to, which is exactly the non-reproducible "latest" the prior STUB flagged — passing the version explicitly is what turns the same command into a pinned, repeatable install. **This is what was actually installed on the production box, same day: `4.3.18`, pinned and verified running.**

**Record the pinned version, don't just install it.** Write the exact version string installed into `docs/records/v1final/production-standup.md`'s deploy log (the file this runbook's own hand-off convention already treats as the authority for what got deployed) at the time of install — the version isn't reproducible later if only "whatever `versions.json` said that day" is remembered.

**How to re-check it later:** Coolify's dashboard displays its own running version (Settings/Configuration screen); to check whether a newer release exists, re-read `versions.json`'s `coolify.v4` key and diff against the recorded install-time value. Coolify's docs do not document a CLI "check for updates" command distinct from the dashboard's own update-checker — the dashboard is the source of truth for "what's running," `versions.json` is the source of truth for "what's current."

**Initial admin setup — zero browser steps, `scripts/provision-vps.sh` handles this.** The installer's own output prints the first-access URL as `http://<box-ip>:8000`, and it reads as if a browser is required to claim the instance. It is not. **Source-verified, not assumed** (`database/seeders/RootUserSeeder.php` in the Coolify install, read directly on the box): Coolify ships its own non-interactive first-user bootstrap, driven by `ROOT_USER_EMAIL`/`ROOT_USER_PASSWORD`/`ROOT_USERNAME` env vars and run as `php artisan db:seed --class=RootUserSeeder`. It no-ops if a user with `id=0` already exists (safe to re-run), otherwise creates that user, attaches it to Team 0 as owner, and disables further registration — the same end state the browser form produces.

`scripts/provision-vps.sh --apply` reads `COOLIFY_ADMIN_EMAIL`/`COOLIFY_ADMIN_NAME`/`COOLIFY_ADMIN_PASSWORD` from `.env`, or prompts for whichever is missing if run from a terminal (password entered twice, confirmed) — **the password is human-chosen, never generated**, because a random one is secure and useless: nobody can log in with it later. It then runs the seeder and mints a Sanctum API token (`root` ability — bypasses every route's `read`/`write`/`deploy` check, correct for the box's own root user), writing the token to `/root/.pfin/coolify.env` (mode 600). **The password is never generated by the script, never written to a file, never printed by it or by `tinker` — see the script's own admin-bootstrap comment block for exactly how it crosses the local→SSH→tinker boundary without ever being a command-line argument or a bare expression `tinker` would echo, and the leak check the script runs on its own captured output every time to prove it.** The token likewise never leaves the box. `--reset-admin-password` changes just the password later (same `.env`/prompt source), without touching anything else.

Look at the dashboard whenever you want — `ssh -L 8000:localhost:8000 root@<box-ip>` then browse `http://localhost:8000` — it's just no longer on the path to standing up the stack, and Coolify's own profile page is the normal way to change the admin password after the fact (the `--reset-admin-password` flag exists for when you can't get in to use it). **F/CTO's local `.env` may still carry a `COOLIFY_API_TOKEN` from the hand-run era of this stand-up — delete it once `provision-supabase-stack.sh` has run once; the on-box copy is canonical from that point on, and script 2 never reads the local one.**

**Reaching the dashboard, API, and MCP from F/CTO's Mac — a persistent tunnel, not a command to remember.** F/CTO ruling, 2026-09-11: keep the exposure decision exactly as §1/§4 already made it (8000 and 3000 stay closed at the firewall — nothing on the box or in the firewall changes here) and instead make the *local* end automatic. `scripts/mac-tunnel.sh` installs a macOS LaunchAgent that keeps `ssh -N -L 127.0.0.1:8000:localhost:8000 -L 127.0.0.1:3000:localhost:3000 pfin-prod` running, restarting it if it dies (dead network, box reboot, laptop sleep/wake). Same dry-run-by-default / `--apply` convention as the two provisioning scripts:

```sh
scripts/mac-tunnel.sh install --box-ip <box-ip>        # preflight — prints the plan, touches nothing
scripts/mac-tunnel.sh install --box-ip <box-ip> --apply # writes ~/.ssh/config (Host pfin-prod, only if absent) +
                                                          # ~/Library/LaunchAgents/com.pfin.tunnel.plist, loads it
scripts/mac-tunnel.sh verify                             # curl checks: 8000 should read 302 (redirect to login)
```

**The tunnel runs as the passphrase-free automation key** (`~/.ssh/id_ed25519_claude_mosko-fintech` — the same one `provision-vps.sh`/`provision-supabase-stack.sh` use), not F/CTO's personal identity. Deliberate (F/CTO ruling, 2026-09-11, correcting this design's original personal-key spec): a LaunchAgent is unattended with no terminal to unlock a passphrase-protected key, and a local port-forward is strictly *less* capability than that key already grants — it's already a full root shell on the box, so reusing it for a tunnel adds zero new exposure. No keychain/ssh-agent step is needed as a result — the key loads directly at LaunchAgent boot. **Tradeoff, accepted:** the tunnel dies if that key is ever removed from this Mac; F/CTO's long-term answer for that is **Tailscale** (a private mesh, independent of this key), not reverting to the personal key — not built yet. `verify --kill-test` kills the running tunnel and confirms it's back within ~15s, proving `KeepAlive` actually works rather than just being configured. Failure mode to know: something else already bound to local 8000/3000 makes the tunnel hit `ExitOnForwardFailure` and enter a restart loop — `scripts/mac-tunnel.sh status` shows the log, and `lsof -i :8000` finds the collision.

**Fallback — what a stranger uses before the LaunchAgent is installed, and what the LaunchAgent itself runs under the hood:** the tunnel command in the paragraph above, run by hand.

**MCP.** Source-verified against Coolify `4.3.18`'s own code (`routes/ai.php`, `app/Http/Middleware/EnsureMcpEnabled.php` / `EnsureTeamMcpEnabled.php` / `EnsureTokenBelongsToCurrentTeamMember.php`, read from the tagged release, not guessed): the MCP endpoint is `http://localhost:8000/mcp` (through the tunnel) — no `/api` prefix, registered by the `laravel/mcp` package's own `Route::group([], routes/ai.php)` call with no group-level prefix. It authenticates the same way the REST API does — `Authorization: Bearer <token>` with a Sanctum token (the one minted at admin setup, above, works: it holds `root` ability and the box's own user is Team 0's owner, which satisfies the role gate below). **One real gate, off by default:** `InstanceSettings.is_mcp_server_enabled` defaults to `false` — the endpoint 404s until it's turned on, once, instance-wide (Settings → Advanced in the dashboard; equivalently `php artisan tinker` → `\App\Models\InstanceSettings::get()->update(['is_mcp_server_enabled' => true]);` if a non-browser path is preferred, consistent with this runbook's zero-browser-steps posture elsewhere — not scripted into `provision-vps.sh` itself since it is a one-time F/CTO preference toggle, not a repeatable-idempotent-infra concern). The **team**-level twin of that flag (`teams.is_mcp_server_enabled`) defaults `true` and needs no action. If an elevated-ability token (`root`/`write`/`deploy`/etc.) is ever used from a *non*-admin/owner team role, `EnsureTokenBelongsToCurrentTeamMember` 403s it — not a concern for the box's own root-owner token, worth knowing if a second, more restricted token is minted later.

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

**Execute this section with `BOX_IP=<box-ip> scripts/provision-supabase-stack.sh` (run `scripts/provision-vps.sh` first — it writes the Coolify API token this script reads from the box, and prints the exact `BOX_IP=... scripts/provision-supabase-stack.sh --apply` line to copy), or run `scripts/standup.sh --apply`, which runs both in order and carries `BOX_IP` between them for you (see the Overview's "One-command scripted spine" note) — followed by the real-key mint below.** `BOX_IP` is **required, not defaulted** — a 2026-09-11 incident (a scratch-box test run whose materialize step fell through to an un-overridden sibling-script default and wrote inert files onto prod's filesystem) is why: no default means no silent fall-through to the wrong box. Preflight by default; `--apply` creates/adopts the project+environment+application, mints the stack's own secrets on the box (never printed, never local), materializes the compose's file-shaped mounts **before** the first deploy (see (1c) below for why that ordering is the whole fix), refuses to deploy onto a poisoned `db-data` volume, deploys, and runs the full verification battery. What follows is the "what and why" — read it for the reasoning and the failure modes it was written to prevent; the script is what actually runs it.

- **Postgres 17** is the forward target (`supabase/config.toml` `major_version = 17`), by choice.
- **Carried follow-up (open):** PG-17 confirm-vs-prod — the `config.toml` comment notes `major_version = 17` is a best-guess match to the incumbent and should be confirmed before Phase 6 base-table RLS work where version-skew bites harder. In the greenfield posture this is **forward-by-choice**, so the "match prod" framing is reference-only; still confirm 17 is the version actually deployed.

**Bring-up method — a Coolify "Docker Compose" resource sourced from Supabase's own reference self-hosting compose, not Coolify's one-click Supabase service.** The losing side is named below, not glossed over.

| Approach | What it is | Verdict |
|---|---|---|
| Coolify's one-click **Supabase** service — a template Coolify itself curates and maintains | Ships Coolify's own bundled compose | **NOT CHOSEN.** Read live from Coolify's own docs (`coolify.io/docs/services/supabase`, 2026-09-09): the bundled compose pins **`supabase/postgres:15.6.1.146`** — Postgres **15**, not the **17** this project already decided on ([ADR-021](../DECISIONS.md#adr-021); `supabase/config.toml` `major_version = 17`). Using it would mean hand-editing Coolify's own managed template's compose to swap the database image — and Coolify's own docs already resort to exactly that kind of hand-edit for a lesser fix (a documented database-port-exposure workaround). The template does not spare us editing a compose file; it only relocates the edit into a Coolify-managed resource a future Coolify update could silently revert, instead of a file this repo commits and reviews. |
| A Coolify **Docker Compose** custom resource — the same resource type §3's table already uses for `etl` / `pdf-render` / `provider-sync` — pointed at a compose file adapted from Supabase's reference self-hosting compose (`github.com/supabase/supabase` → `docker/docker-compose.yml`) | We supply the compose content | **CHOSEN.** Read live 2026-09-09: the current reference compose already pins `supabase/postgres:17.6.1.136` — PG 17, on target, no override needed. It also gives a committed, reviewable artifact for the `studio`/`meta` trim below — the same lintability argument §3 already makes for `provider-sync`/`pdf-render`'s Compose-over-bare-Dockerfile choice: a UI-only trim is a setting nothing can check; a committed compose file is. |

**Losing side of the chosen option, stated plainly:** Coolify's one-click services get Coolify's own maintained upgrade path and a curated per-service UI panel; a hand-sourced Compose resource gets neither — DevOps, not Coolify, is responsible for periodically re-pulling the upstream reference compose and re-applying the trim below, rather than clicking an "update" button. Accepted because the PG17 mismatch above is not a stale-snapshot fluke of Coolify's template — it is that template's own committed artifact, and leaning on it for a version-sensitive component like the database is exactly the kind of moving-target dependency this runbook's own Coolify-version-pin discipline (§3) argues against.

**Do not fetch the reference compose once and commit it verbatim into this repo.** Its service set and image tags move — the gateway service alone has been renamed and re-implemented since earlier tree references were written (see the `kong` row below). Pull it fresh at execution time, apply the trim below, and record the exact tags actually deployed in `docs/records/v1final/standup-log.md` (the as-executed log, not this file, per its own "records measurements, not intentions" rule).

**The trimmed compose lives at [`infra/supabase/docker-compose.yml`](../infra/supabase/docker-compose.yml)**, alongside its vendored Envoy config and DB init scripts (see that directory's `README.md` for provenance and the four changes made from the corresponding upstream service blocks). Sibling to the `workers/*/docker-compose.yaml` pattern §3 already uses, not nested under `supabase/` (CLI-config/migration territory) or `docs/` (reference docs, not deploy artifacts).

**⚠ The Coolify resource for this compose MUST be created with `base_directory: /infra/supabase` and `docker_compose_location: /docker-compose.yml`** — not `base_directory: /` with `docker_compose_location: /infra/supabase/docker-compose.yml`, which looks equivalent and is not. Source-verified in Coolify's own deploy code (`ApplicationDeploymentJob.php:791-793`): the deploy job's working directory (against which every relative bind mount in the compose resolves) is the checkout root adjusted by `base_directory`, not the compose file's own location. Get this wrong and the failure is **silent** — Docker auto-creates a missing bind-mount source as an empty directory rather than erroring, so the stack reports healthy while `db` has no init scripts at all and the gateway has an empty config directory. See `infra/supabase/README.md` for the full mechanism and the verification step below.

**Service scope for V1 — decided service by service, evidence-based.** Cross-checked against `supabase/config.toml`'s `enabled` sections and the current reference compose (read live 2026-09-09); the note after the table says why `config.toml`'s flags don't settle this by themselves.

| Service | In/Out | Evidence |
|---|---|---|
| `db` (Postgres) | **IN** | The datastore. The chosen bring-up method's reference compose pins `supabase/postgres:17.6.1.136` — PG 17, matching `config.toml`'s `major_version = 17` with no override needed. |
| `auth` (GoTrue) | **IN** | `api/src/hooks.server.ts`'s `createServerClient()` call is the app's entire session mechanism (`event.locals.supabase`) — no code path works without it. |
| `rest` (PostgREST) | **IN** | The Data API `createServerClient()` talks to for every `pfin`-schema query, per [`supabase/CLAUDE.md`](../supabase/CLAUDE.md)'s RLS-default-trust posture (supabase-js + PostgREST, native RLS). |
| `storage` | **OUT** | Re-grepped 2026-09-09: `grep -rniE "supabase.*storage\|\.storage\.from\(\|createBucket\|getBucket" api/src` and the same over `workers/pdf-render/src` → **zero hits**. Plaid access tokens live in `vault.secrets` (a Postgres extension inside `db`) — a different thing from the Storage service; don't conflate them. **New finding, not previously recorded anywhere in this tree** — revisit if a future PRD story adds file uploads. |
| `realtime` | **OUT** | Re-grepped 2026-09-09, independently reproducing `production-standup.md` §5's finding: `grep -rniE "realtime\|\.channel\(\|supabase\.channel\|postgres_changes\|removeChannel" api/src` → zero genuine hits (only an unrelated `vi.useRealTimers()` fake-timer call). Also confirmed **zero** `createBrowserClient` call sites in `api/src` — no browser-side Supabase client exists to subscribe through even in principle. |
| API gateway (`kong`, historically) | **IN — name drift flagged** | The ingress everything else sits behind; required regardless of name. **Finding:** this tree's prior references (`production-standup.md` §3, runbook §2) call this service `kong`. The **current** reference compose (read live 2026-09-09) no longer ships Kong at all — the gateway is now `api-gw`, built on **Envoy** (`envoyproxy/envoy:v1.39.1`). Supabase has migrated its self-hosted gateway upstream of this tree's prior research. Confirm which gateway actually ships in whatever reference-compose snapshot is pulled at execution time — Kong's plugin config and Envoy's filter config are not interchangeable, so a stale "kong" mental model is a real footgun here, not a naming nicety. |
| `meta` (postgres-meta) | **IN — with `studio`** | Sole consumer is `studio`'s schema browser; nothing else depends on it. It came IN with `studio` at F/CTO's 2026-09-10 keep-ruling, per this table's own rule that the two move together. **No host publish and no Domain**, and the gateway's `/pg/` route to it is DENY'd — that route disables basic auth per-route and is gated only on the service_role key, so a live route would hand arbitrary SQL as `postgres` to any key-holder. Studio reaches it directly on the project network (`STUDIO_PG_META_URL`). |
| `studio` | **IN — F/CTO exception, 2026-09-10, SSH-tunnel only** | F/CTO named the keep-reason: browser-based ad-hoc DB inspection, reachable **the same way the Coolify dashboard is** — over an SSH tunnel, **not** a public Domain. ⚠ **This supersedes the earlier "if kept, it needs its own Coolify Domain" framing in this row and at §3; following that instruction now would publish an admin SQL console to the internet.** Realized as a literal `127.0.0.1:3000:3000` loopback publish in the compose (the *only* `ports:` mapping the datastore fence allowlists), reached with `ssh -L 3000:localhost:3000 root@<box-ip>` → `http://localhost:3000`. Studio has no login of its own, so the loopback bind plus the box's SSH key **are** the access control; the gateway's `/` catch-all to studio is DENY'd so that a future Domain on `api-gw` cannot expose it. `meta` flips IN with it (row above). Sec ruling 2026-09-10 — Sec joint-review before any change to this shape. |
| `imgproxy` | **OUT** | Sole consumer is Storage's image-transformation feature. `storage` is OUT (above), and `config.toml`'s `[storage.image_transformation]` block is commented out regardless — no consumer at either layer. |
| `supavisor` (pooler) | **IN, with a carve-out** | Fronts `rest`/`auth`'s own database connections by default in the reference compose. `config.toml`'s `[db.pooler] enabled = false` is **local-CLI-only** and isn't evidence either way — the local `supabase start` stack (`production-standup.md` §5's 11-container `docker stats` table) doesn't run a pooler container at all, on or off. **DevOps call, named so it can be revisited:** the two direct-Postgres workers (`workers/etl`'s `pfin_etl` connection, `workers/provider-sync`'s `pfin_provider_sync` connection — both via `TenantBoundConnection`/`TenantBoundClient`, Lock 13 mod #3) connect **straight to `db`**, bypassing `supavisor` — each is a long-lived singleton connection that gains nothing from transaction-mode pooling, and routing through `supavisor` adds an unverified prepared-statement-compatibility unknown for no offsetting benefit at V1's single-tenant scale. Open to Architect/Sec revisit; not F/CTO-locked. |
| `analytics` | **OUT** | Re-confirmed 2026-09-09, reproducing the prior finding independently: absent from the current reference compose entirely — a `supabase start` CLI-only convenience add, never part of the production reference stack. |
| `vector` | **OUT** | Same as `analytics` — confirmed absent from the current reference compose. |

**Not in scope of the above list, noted for completeness:** the reference compose also defines a `functions` service (Edge Runtime). No Edge Function is authored anywhere in this tree (`config.toml`'s `[edge_runtime]` block is a local-CLI default with nothing behind it) — **OUT**, same reasoning as the others, just not itemized since it wasn't asked for.

**On `config.toml` generally.** Every `enabled = true` in `supabase/config.toml` (`api`, `db`, `realtime`, `studio`, `storage`, `auth`, `analytics`, `inbucket`, `edge_runtime`) describes what the **local CLI-managed dev stack** turns on for developer convenience — it is not a production service manifest, and per this runbook's own convention this section does not edit that file. Where the table above disagrees with a `config.toml` `enabled = true` (`realtime`, `storage`, `studio`, `analytics`), that is `config.toml` correctly serving local dev, not evidence either service belongs in production. `inbucket` is the clearest case: it's explicitly local-only email-catching (`config.toml`'s own comment: "not actually sent") — production email is wired separately at the `auth` container's own SMTP env per `config.toml`'s commented `[auth.email.smtp]` block, unrelated to this service-scope decision.

**Outbound auth email (signup confirmation, password reset, email-OTP) is unconfigured by default** — `provision-supabase-stack.sh` sets Supabase's own non-functional reference SMTP placeholders (`SMTP_HOST=supabase-mail` etc.) purely so `auth` can start at all (GoTrue FATALs on startup without a parseable `SMTP_PORT`); no real mail sends until an operator wires a real provider. **To wire real delivery, follow [`docs/email-smtp-runbook.md`](email-smtp-runbook.md) end to end** (Resend is the V1 default; Amazon SES is documented as the alternative) — the flow is **scripted, not a Coolify dashboard click**: put your Resend API key in the root, gitignored `.env` as `SMTP_PASS` (see [`scripts/provision.env.example`](../scripts/provision.env.example); optionally also `SMTP_ADMIN_EMAIL`/`SMTP_SENDER_NAME` for your own sending identity), same pattern as `HETZNER_API_TOKEN`/`COOLIFY_ADMIN_PASSWORD` above — `provision-supabase-stack.sh --apply` reads it, pushes it to the box over SSH (never a command-line arg, never printed), and OVERWRITES the stack's placeholder SMTP_* values with it (plus Resend's own fixed `SMTP_HOST`/`SMTP_PORT`/`SMTP_USER`). Leave `SMTP_PASS` unset in `.env` and the script leaves the placeholders alone, printing a one-line reminder every run pointing back here. `SMTP_PASS` is the only secret — declared `production_only` in [`secrets-manifest.yml`](../secrets-manifest.yml) (§5 below; Sec joint-review, same as every manifest change) — set on **this Supabase-stack Coolify resource's env**, not the web-app container's.

**Postgres major version — 17, and how to know it landed.** The chosen bring-up method sources a reference compose that already pins `supabase/postgres:17.6.1.136` as of the 2026-09-09 read, matching `config.toml`'s `major_version = 17` ([ADR-021](../DECISIONS.md#adr-021), forward-target-by-choice, not by prod-match — the cax21/pfindash.com incumbent measured PG 15.8 and is reference-only). This is what discharges this section's "PG-17 confirm-vs-prod" carried follow-up above — **operationally**, by the check below, not by this sentence alone:

```sh
psql "$PROD_DB_URL" -Atc "show server_version;"
# EXPECTED: 17.x
```

Do not accept a Coolify/`docker compose` "healthy" status as this proof — a health check proves a process is listening, not which major version it's running. A wrong image tag reports exactly as healthy as a right one; this is exactly the silent failure mode Coolify's one-click template (pinned to 15.x) would have produced.

**5a. Disable production signup; found the tenant by invitation.** `GOTRUE_DISABLE_SIGNUP` is **hardcoded `"true"`** in the `auth` service block of [`infra/supabase/docker-compose.yml`](../infra/supabase/docker-compose.yml) — **not** a Coolify-settable env var. This is a corrected instruction, not the original one: this section previously told the operator to set a Coolify variable named `GOTRUE_DISABLE_SIGNUP`, but the compose interpolated `${DISABLE_SIGNUP}` — followed literally, that naming mismatch resolves to an empty value and **signup stays enabled**, the exact inverse of F/CTO's Q5 ruling. Caught by the verification probe below, not by re-reading the instruction — which is the case for running it at all rather than trusting the config. Q5 makes signup-disabled a **standing gate** (it stays off through the full V1.final soak until the Plaid Link-token operator allowlist ships — [`BACKLOG.md` §7.36 item 1](../BACKLOG.md)), so it is hardcoded rather than left tunable: lifting it later means editing the compose file (and shipping a PR), which is the correct friction for a one-way-door control, not a dashboard toggle. This is a **container env var on the self-hosted `auth`/GoTrue container**, distinct from and unrelated to `config.toml`'s `[auth] enable_signup` / `[auth.email] enable_signup` (both `true`, local-CLI-only, `config.toml:181,228`) — setting one does not touch the other.

**Verify by probing the endpoint, never by reading a config back — this is what would have caught the naming-mismatch defect above, and is why this step is a live probe rather than a compose-file read:**

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

**Triggering the deploy — merging to `main` does NOT do this, even though this resource's `auto_deploy` setting reads `true`.** Confirmed live, 2026-09-10: merging a PR that changed `infra/supabase/**` queued no deployment and started no containers. `auto_deploy` is inert without a GitHub webhook telling Coolify a push happened, and §3 above already names that webhook as ARCH §6 item (f) — deliberately **not** configured yet (Sec-consult-mandatory, gated on branch-protection admin-bypass controls). So `auto_deploy=true` on a resource with no webhook wired is a setting with no effect, not a contradiction — but it reads as a live trigger to anyone who doesn't know the webhook is missing. Trigger the deploy explicitly instead, from the box:

```sh
curl -s -X POST -H "Authorization: Bearer $COOLIFY_API_TOKEN" \
  "http://localhost:8000/api/v1/deploy?uuid=<app-uuid>"
```

(or the Coolify UI's Deploy button — same effect). Once item (f)'s webhook is wired for a resource, re-verify this note: a push-triggered deploy changes what "merge, then check nothing happened" means for whoever rebuilds from this file next.

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

**(1b) Bind-mount sanity — every kept service healthy is NOT proof its config/init-script mounts resolved to the right files.** `infra/supabase/docker-compose.yml`'s bind mounts are written compose-file-relative (`./volumes/...`), which is only correct if this Coolify resource's `base_directory` was set to `/infra/supabase` (see that directory's `README.md`). Get `base_directory` wrong and Docker does not fail loudly — it auto-creates each missing bind-mount source as an empty directory, so `api-gw` and `db` both come up "healthy" while actually unconfigured.

**(1c) Why `provision-supabase-stack.sh` materializes the compose's file-shaped mounts BEFORE the first deploy, not after a failure.** This used to be a "deploy, watch it fail, repair, redeploy" procedure — it is not one anymore; the script sequences around the failure instead of hitting it. The mechanism, source-verified in `bootstrap/helpers/parsers.php`'s `applicationParser()`: Coolify creates a `local_file_volumes` row for every relative bind mount the moment it **parses** the compose — which happens at resource creation (`LoadComposeFile::dispatch`, fired when the application is created without `instant_deploy`), separately from and before any deploy — defaulting `is_directory=true` when it has no prior row to read the shape from, and pre-creating that path on the host as an empty directory. Nothing in `ApplicationDeploymentJob`'s deploy flow corrects that guess for this application's settings (`is_preserve_repository_enabled=false`, the default) — `LocalFileVolume::saveStorageOnServer()`, the method that would materialize real content, is only ever called when that setting is on. Left alone, every one of this compose's 12 file-shaped bind mounts (4 under `volumes/api/envoy/`, 7 under `volumes/db/`, 1 under `volumes/pooler/`) comes up as a bogus empty host directory on the very first deploy attempt, and Docker refuses to bind a directory onto the container-side file path it's supposed to be — `error mounting ".../docker-entrypoint.sh" to rootfs at "/docker-entrypoint.sh": not a directory`. **The fix is ordering, not repair:** create the application without `instant_deploy`, wait for the `local_file_volumes` rows to appear (proof the parse ran), run `scripts/coolify-materialize-supabase-mounts.sh --apply` to replace the bogus directories with the real files, **then** deploy. The failure this section used to describe never happens.

Fix: `scripts/coolify-materialize-supabase-mounts.sh --apply` (dry-run by default). It replaces each bogus directory with the real file from `infra/supabase/volumes/**` (the repo stays sole source of truth — the script only ever reads that tree) and syncs the corresponding `local_file_volumes.content` + `is_directory=false` through Coolify's own Eloquent model (`php artisan tinker` inside the `coolify` container — never a raw SQL `UPDATE`, because `content` is an `encrypted`-cast column and a plaintext write corrupts it). Safe to re-run any time `infra/supabase/volumes/**` changes (e.g. a future upstream re-vendor). Run it once after the *first* deploy attempt fails this way, then redeploy; it does not need to run again unless the vendored files change, because nothing in this build pack's non-preserve-repository deploy path touches these host paths afterward.

Same first-deploy pass also silently mis-parses the `pooler` service's two-flag volume mode (`:ro,z` in the corresponding upstream syntax) — Docker Compose's single-flag modes (`:ro`, `:Z`) parse fine, but the two-flag combination bled into the `mount_path` Coolify recorded (`/etc/pooler/pooler.exs:ro,z` instead of `/etc/pooler/pooler.exs`). Fixed at the source in `infra/supabase/docker-compose.yml` (dropped the redundant `:z` — this box runs Ubuntu with no SELinux, so the flag was a no-op regardless); the materialize script also corrects any existing row still carrying the mangled `mount_path`.

**(1d) `api-gw` and `supavisor` are `expose:`-only in this compose — never restore upstream's `ports:` mappings.** Discovered on the first deploy attempt that got past (1c)'s mount failure, measured live 2026-09-10: `api-gw`'s upstream `ports: - 8000:8000` collided with **Coolify's own dashboard**, which also listens on the host's port 8000 — `api-gw` failed to start (`Bind for 0.0.0.0:8000 failed: port is already allocated`), and the whole gateway sat in `Created` as a result. Separately (and found only by probing, not by any error — this one is silent): `supavisor`'s upstream `ports:` came up bound to `0.0.0.0:5432` and `0.0.0.0:6543` — a multi-tenant Postgres's wire protocol and pooler proxy on the host's **public** interface, unreachable that day only because the Hetzner cloud firewall (`pfin-prod-fw`, §1) happened to filter those ports, not because anything in this stack's own config stopped it. Matches this repo's existing `expose:`-only precedent for internal-only services (`workers/provider-sync`, `workers/pdf-render`) — apply the same reasoning here: a database's wire port has no more business on a public host interface than an internal admission endpoint does. `app` and `workers/*` reach both services over the shared Coolify project network by service name (`api-gw:8000`; the pooler's service name + `5432`/`6543`) once `connect_to_docker_network` is enabled per-resource at §6 — confirmed **not** automatic and **not** project-scoped, has to be flipped on both sides.

**⚠ Do not `docker logs` by the container names this compose file specifies (`supabase-envoy`, `supabase-db`, ...) — they never reach the running container.** Coolify's `dockercompose` build pack overrides every service's `container_name` (source-verified in `bootstrap/helpers/parsers.php`'s `applicationParser()`: `$containerName = "$serviceName-{$resource->uuid}"`, then merged over the compose file's own value). **Do not construct the resulting name from that formula either** — observed containers on a live deploy carried a further numeric suffix beyond service-name-plus-uuid (e.g. `db-<uuid>-<12-digit-number>`) that this code path alone doesn't explain; something downstream appends more. Read the actual running name from `docker ps` when you need it directly. For this check specifically, sidestep the naming question entirely: `docker compose --project-name <the resource's uuid> logs <service-name>` addresses by the compose **service** name (`api-gw`, `db`, ...), which is unaffected by whatever the final container name turns out to be:

```sh
# Confirm the gateway loaded a real config, not an empty directory.
docker compose --project-name <app-uuid> logs api-gw 2>&1 | tail -30
# EXPECTED: Envoy's own startup log (listener/cluster config lines). A
# near-empty log or an immediate crash-loop means /etc/envoy mounted empty.

# Confirm each DB init script actually ran on first boot (only meaningful
# on a FRESH db-data volume — a script only runs once, at first init).
docker compose --project-name <app-uuid> logs db 2>&1 | grep -iE "roles\.sql|jwt\.sql|webhooks\.sql|realtime\.sql|_supabase\.sql|logs\.sql|pooler\.sql"
# EXPECTED: all seven filenames appear (Postgres logs each init-scripts/
# migrations file it executes). A short or empty result means the init
# directory mounted empty — the base_directory misconfiguration above.
```

**⚠ A `db` container reporting `healthy` after an init-script mount failure is the normal presentation of that failure, not evidence against it — its health check only proves Postgres is accepting connections, not that any init script ran.** Postgres runs everything under `/docker-entrypoint-initdb.d/` exactly once, against an **empty** data directory, at first boot. If that first boot happened with (1c)'s bogus empty-directory mounts in place — even briefly, even from a deploy attempt that then failed for an unrelated reason like `api-gw`'s mount error — the data directory is no longer empty, `roles.sql`/`jwt.sql`/the rest can never run against it, and re-running (1c)'s materialize script and redeploying does **not** fix this: Postgres will happily boot healthy against the already-initialized (and now permanently broken) directory forever. The tell: `pg_authid` shows `authenticator`/`pgbouncer`/`supabase_auth_admin` with a **NULL** password (only the image's own baked-in schema scripts ran — those create the `anon`/`authenticated`/`service_role` roles too, so their presence is not evidence `roles.sql` ran) and `show app.settings.jwt_secret` errors `unrecognized configuration parameter`. Symptomatically this shows up one step downstream: `auth`, `rest`, `api-gw`, and `supavisor` all sit in `Created` and never start, because none of them can authenticate to a `db` that itself reports healthy.

**The remedy is destroying the volume and letting Postgres re-init, never a redeploy alone:**

```sh
# Confirms nothing is preserved by skipping this — no data exists to protect
# before §6's migrations run, so this is cheap now and expensive to diagnose later.
docker compose --project-name <app-uuid> down -v
docker volume ls --filter name=<app-uuid>   # MUST print nothing before redeploying
```

Confirm the volume is actually gone before redeploying — `down` without `-v` leaves `<app-uuid>_db-data` and `<app-uuid>_db-config` in place and silently reproduces the exact same symptom on the next attempt.

**⚠ `rest` (PostgREST) sitting unhealthy after `db`, `auth`, `api-gw`, and `supavisor` are all healthy is expected at this point in the sequence, not evidence of a defect.** Measured live: `rest`'s health probe (`GET /ready`) errors repeatedly —

```
{"code":"3F000","message":"schema \"pfin\" does not exist"}
```

— because `PGRST_DB_SCHEMAS=pfin` is correct, but the `pfin` schema does not exist yet: it is created by `supabase/migrations/**`, which run at §6, not here. PostgREST retries its schema-cache load with its own backoff and goes healthy **on its own**, with no restart needed, the moment §6's `supabase db push` lands. **What would make this a real failure instead of the expected wait:** `rest` still unhealthy with this same error *after* §6's migrations have applied cleanly (check `supabase_migrations.schema_migrations` for the expected row count first), or a different error code entirely (anything other than `3F000`/"schema does not exist" on a schema-not-found race). ⚠ **Unconfirmed against the live box (2026-09-14, standup step 6 Phase B, Sec joint-review PR #753 C-1):** the running stack's `PGRST_DB_SCHEMAS` measured `public,graphql_public` — `pfin` absent — contradicting this paragraph's premise. Not reconciled in this PR; booked at `BACKLOG.md` §7.36.

**This is the third instance of the same pattern in this section, worth naming once rather than re-discovering per check: §4's verifications assume a post-§6 world, and some of them run before §6 in the natural stand-up order.** §4.1's TimeZone read-back, §5's Sec-gate STUB appearing to block §4's own execution, and this `rest`-unhealthy case are the same shape — a check that is correct, and will read as failing, until a later section's work lands. Reordering §4/§5/§6 is not the fix (§5's secrets-before-deploy gate and §6's role-provisioning ordering are both deliberate, not accidental) — the fix is marking each affected check explicitly, which this section now does at each instance rather than leaving a stranger to rediscover the pattern three separate times.

**Secrets this step produces.** Names only — never values, here or anywhere in this repo; most (not all — each row below states whether it is a manifest entry) are drawn from `secrets-manifest.yml`'s `production_only` set. **§5's secrets-provisioning procedure is still a STUB and its Sec joint-review flag is NOT discharged by this section** — this only names where these five land; rotation/injection-order procedure is §5's job.

| Secret | Produced how | Where it goes |
|---|---|---|
| `ANON_KEY` (Supabase compose env) | Minted at Supabase stand-up (signed with the stack's own JWT secret, `role: anon`) — not operator-chosen | The Supabase compose's own env **only** — required so `rest`/the gateway/`auth` recognize it. Not a `secrets-manifest.yml` entry: internal to the self-hosted stack, distinct from the app-facing name below. |
| `PUBLIC_SUPABASE_ANON_KEY` (app-facing) | Same minted value (`role: anon` JWT) — not a separate mint, not operator-chosen | The `app` service's Coolify env, as **non-secret runtime config** — §5's `PUBLIC_`-prefixed injection list, not `secrets-manifest.yml`. Sec ruled the anon key a publishable JWT, not a secret: RLS plus the [ADR-029](../DECISIONS.md#adr-029) aal2 backstop are the controls. Consumed by `api/src/hooks.server.ts`'s boot-time env guard under this exact name. **The naming mismatch previously flagged here is resolved**, by giving the stack-internal consumer and the app consumer two distinct names rather than reconciling one to the other. |
| `SUPABASE_SERVICE_ROLE_KEY` | Same minting step, `role: service_role` | Same two-place pattern as above; consumed under this exact name by `api/src/lib/server/supabase-admin.ts` (verified — no mismatch here). RT-26's §4.1 allowlist confines its **consumption** inside the `app` container to that one file; unaffected by where the value is injected. |
| `PFIN_DB_USER` | Non-secret username, fixed per container (`pfin_etl` / `pfin_provider_sync`) | Coolify env on `workers/etl` / `workers/provider-sync` respectively. |
| `PFIN_DB_PASSWORD` | Generated at the §6.1/§6.2 two-step credential handoff (`openssl rand -hex 32`) — **after** migrations apply, per the ordering dependency §6.1 already states | Coolify env on `workers/etl` / `workers/provider-sync` — **different value per container**, same secret name, per `secrets-manifest.yml`'s own note. |

**Minting the real `ANON_KEY`/`SERVICE_ROLE_KEY` — `scripts/mint-supabase-jwt-keys.sh`.** The `ANON_KEY`/`SERVICE_ROLE_KEY` row above is what `provision-supabase-stack.sh` mints **first** — deliberately inert `secrets.token_hex(32)` random hex (Sec: "safe-but-inert," zero access, no RLS bypass), not a valid JWT, chosen so the stack can stand up before real keys exist. `rest` (PostgREST) and `auth` (GoTrue) verify the `apikey`/bearer value as an HS256 JWT signed with the deployed `JWT_SECRET`; `api-gw` (Envoy) does **not** verify a signature — its RBAC filter does a plain exact-string match of the `apikey` header against the configured `${ANON_KEY}`/`${SERVICE_ROLE_KEY}` values (see [`infra/supabase/volumes/api/envoy/lds.template.yaml`](../infra/supabase/volumes/api/envoy/lds.template.yaml), the `rest-v1-openapi-protected` route's `string_match: exact:` principals). This is exactly why a redeploy is required: Envoy has the key **string** baked in at container start. A request presenting the inert placeholder hex would therefore **pass** Envoy's string match if that hex were the baked value, and is rejected only downstream — `rest`/`auth` reject it because random hex is not a validly-signed JWT. The placeholder **cannot authenticate to anything**, but by the downstream JWT verify, not by `api-gw`. Replace it once the stack is deployed and healthy:

```sh
BOX_IP=<box-ip> scripts/mint-supabase-jwt-keys.sh --apply
# once the `app` (V1 web-app) Coolify resource exists, also propagate app-side:
BOX_IP=<box-ip> scripts/mint-supabase-jwt-keys.sh --apply --app-name <app-resource-name> --verify-live
```

`scripts/standup.sh --apply` runs the plain (stack-only) `--apply --verify-live` form above as its stage 3, right after §4's stack deploy — see the Overview's "One-command scripted spine" note. The `--app-name` propagation form is **not** covered by the wrapper (the `app` Coolify resource doesn't exist yet at this point in the stand-up — that's §7); run it by hand once that resource exists.

**⚠ An env-var overwrite alone does not take effect — Coolify only injects the env store into a container at deploy (container-recreate) time.** `docker restart` is **not** a substitute: it restarts the same container with the same baked-in env, it does not re-read the store. `--apply` therefore triggers a real redeploy of the Supabase-stack Coolify resource immediately after the overwrite (`POST /deploy?uuid=...` + poll to `finished`, the same idiom this section's own "Triggering the deploy" step above uses), then waits for every stack container to report healthy again before returning — so `--apply --verify-live` is one coherent mint → redeploy → verify invocation, not a three-step manual dance. The redeploy is skipped (with a printed reason) only when the stack has no containers yet, in which case `provision-supabase-stack.sh`'s own first deploy picks up the freshly-minted values already written to the env store. Recreating containers this way keeps the `db-data` volume (compose up/down semantics, never `down -v`) — no data loss. **Scope note:** this redeploy covers the stack app only — the app-side propagation (`--app-name`, `PUBLIC_SUPABASE_ANON_KEY`/`SUPABASE_SERVICE_ROLE_KEY`) is env-overwrite only; redeploy that resource separately (Coolify UI Deploy button, or the same `POST /deploy?uuid=<app-uuid>` call) once it exists.

**`--verify-live` runs four probes against the real gateway, not one.** A single anon-key `GET /rest/v1/` probe expecting `200` cannot pass by design: per [`infra/supabase/volumes/api/envoy/lds.template.yaml`](../infra/supabase/volumes/api/envoy/lds.template.yaml)'s `rest-v1-openapi-protected` route, the exact path `/rest/v1/` RBAC-allows `SERVICE_ROLE_KEY` (and its asymmetric counterpart) only — anon on the root is `403` by design, not a broken key. The verify block instead runs and prints all four of:

| Probe | Path | PASS criterion | What it proves |
|---|---|---|---|
| `service_role` | `GET /rest/v1/` | `200` | The minted service_role key authenticates on the RBAC-gated root route. |
| `anon` | `GET /rest/v1/<nonexistent-table>` | **NOT** `401` (expect `404` pre-Wave-6, since no tables exist yet) | The minted anon key authenticates on the `rest-v1-protected` prefix route PostgREST actually serves tables through. |
| no key | `GET /rest/v1/<nonexistent-table>` | `401` | Control — without any key, the gateway/PostgREST still refuses. |
| `anon` | `GET /auth/v1/health` | `200` | Routing sanity for `auth`, independent of the apikey gate. |

A single explicit `VERIFIED`/`NOT VERIFIED` line closes the block. Both keys are read back on the box via the same Eloquent-decrypt `tinker --execute` path already used elsewhere in this script — never echoed to this script's own stdout, only the HTTP status codes are.

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
  - `ci_only` (6 names — reserved distinct names; no production reach): `PLAID_SANDBOX_CLIENT_ID`, `PLAID_SANDBOX_SECRET`, `PDF_WORKER_SIGNING_KEY_TEST`, `SIMPLEFIN_TOKEN_TEST`, `BLS_API_KEY_TEST`, `CI_MIGRATE_SSH_PRIVATE_KEY`.
  - `production_only` (20 names — Coolify-injected on the box; never in CI): `SUPABASE_SERVICE_ROLE_KEY`, `PDF_WORKER_SIGNING_KEY`, `PLAID_CLIENT_ID`, `PLAID_SECRET`, `SIMPLEFIN_TOKEN`, `WORKER_ADMISSION_SHARED_SECRET`, `DISCORD_WEBHOOK_URL`, `PFIN_DB_PASSWORD`, `FMP_API_KEY`, `BLS_API_KEY`, plus the self-hosted Supabase stack's own ten (a dedicated block in [`secrets-manifest.yml`](../secrets-manifest.yml)): `POSTGRES_PASSWORD`, `JWT_SECRET`, `SECRET_KEY_BASE`, `VAULT_ENC_KEY`, `SERVICE_ROLE_KEY`, `ANON_KEY`, `DASHBOARD_PASSWORD`, `PG_META_CRYPTO_KEY`, `SMTP_PASS`, `MIGRATOR_DB_PASSWORD`. ⚠ **Corrected 2026-09-16** — this enumeration said "5 names" / "19 names" and omitted `CI_MIGRATE_SSH_PRIVATE_KEY` (ADR-072 chunk 2, ci-migrate's GitHub Actions secret) and `MIGRATOR_DB_PASSWORD` (ADR-072 Amendment 1, minted on-box for the `migrator` role) — exactly the silent-drift failure mode this section's own next paragraph warns about; the same gap in `scripts/push-production-secrets.sh`'s exclusion set made that script fail closed on every invocation until fixed alongside this correction. **`SUPABASE_ANON_KEY` is deliberately NOT in this set** — see the non-secret runtime-config list immediately below.
  - **Counts are load-bearing — check them, don't skim them.** The two lists above are a **hand-maintained mirror** of [`secrets-manifest.yml`](../secrets-manifest.yml); nothing enforces that they stay in sync, so they drift silently. The failure mode is asymmetric and unpleasant: a secret missing *here* isn't a fence breach (the non-overlap fence still passes — it reads the manifest, not this file), it's a **container that deploys without a secret it needs**. So: the `secrets-nonoverlap` job prints `N ci_only + M production_only` on every PR + push. If those numbers disagree with the `(6 names)` / `(20 names)` above, this enumeration has drifted — **the manifest is source of truth; fix this list.** (Live-checked 2026-09-16, at the same correction that fixed the stale `5`/`19` above: `python3 scripts/ci/check-secrets-nonoverlap.py` prints exactly `6 ci_only + 20 production_only` against the current manifest.) Comparing two integers CI already emits is the cheap check; diffing two prose lists by eye is the one that fails. *(This is not hypothetical: both halves of the `SIMPLEFIN_TOKEN` / `SIMPLEFIN_TOKEN_TEST` pair were missing here and went unnoticed until SELF-214 — with the fence green throughout.)*
  - **Non-secret runtime config (NOT in `secrets-manifest.yml` — Sec-authorized, 2026-09-09):** two names are boot-required but deliberately absent from both the CI/production non-overlap sets above, because neither is a secret:
    - `PUBLIC_SUPABASE_URL` — the self-hosted Supabase stack's own gateway URL. Not confidential; it's the address the app's server process dials.
    - `PUBLIC_SUPABASE_ANON_KEY` — a `role: anon` JWT, publishable by construction. RLS plus the [ADR-029](../DECISIONS.md#adr-029) aal2 backstop are the controls that gate what an anon-scoped request can do — not keeping this value confidential.
    Both are read by `api/src/hooks.server.ts`'s boot-time env guard via SvelteKit's `$env/dynamic/public`, and both are declared (non-secret) in [`api/.env.example`](../api/.env.example). Inject both as **plain (non-secret) Coolify environment variables** on the `app` service, under these exact `PUBLIC_`-prefixed names — omitting either throws at boot. Do not add either to `secrets-manifest.yml` or root [`.env.example`](../.env.example): those enumerate confidential values, and listing a publishable JWT there would assert a blast radius that does not exist and would put a production-tier name on developer machines that must hold the local stack's own value instead.
  - **`PFIN_DB_SSLMODE=disable` — non-secret, required production override (Sec ruling, §7.36 item 26, 2026-09-14).** Set explicitly in the production Coolify env for **both** `workers/etl` and `workers/provider-sync`. `pfin_back_etl/utils.py`'s `load_db_params()` defaults `<prefix>DB_SSLMODE` to `require` (S11, PR #355) so an unspecified environment fails closed — **that code default is NOT changed**; this is the override S11 was built to take. Sec's rationale in one sentence: **plaintext is acceptable only because `db` is `expose:`-only per RT-32** — the moment `db` is host-published, this override (and the migrator's `sslmode=disable`, above/below) must be revisited together. Declare `PFIN_DB_SSLMODE` in the non-secret set alongside `PUBLIC_SUPABASE_URL`/`PUBLIC_SUPABASE_ANON_KEY` above — never in `secrets-manifest.yml`.
  - **`WORKER_ADMISSION_SHARED_SECRET` (SELF-212 Option-C, C6-2) provisioning:** generate 256-bit (`openssl rand -hex 32`). ⚠ **Mechanism corrected 2026-09-11 (Sec + F/CTO ratified, PR #738)** — this line previously said "inject as a Coolify project-scoped SHARED variable ... one edit point." That mechanism does not exist as a scriptable surface: Coolify's `SharedEnvironmentVariable` feature is dashboard-only (Livewire), with no public REST API endpoint (checked against Coolify's own docs — see `scripts/push-production-secrets.sh`'s own KNOT 5 comment for the sources). **Ratified mechanism:** the same literal value is pushed as an ordinary **per-application env var to BOTH** the `app` web-app service and the `provider-sync` worker service, in the **same invocation** of `scripts/push-production-secrets.sh` — one script run is the rotation edit point, not one dashboard row. **Rotation discipline (Sec condition): never hand-edit one side's copy — always re-run the script so both update together.** If the two ever drift (edited outside the script, or a partial failure leaves them out of sync), the failure mode is **fail-closed, never a bypass**: provider-sync's constant-time compare against the relayed value mismatches and admission is DENIED — a brief outage, not an exposure. NOT the service_role key → RT-26 allowlist unchanged. This secret's SAME-value-on-both-tiers shape mirrors `PDF_WORKER_SIGNING_KEY` (web-app + PDF worker per SD-20).
  - **Fail-closed fence:** `scripts/ci/check-secrets-nonoverlap.py` runs as the `secrets-nonoverlap` job in `.github/workflows/security-scan.yml` on every PR + push to `main`; fails closed if the sets intersect, a set is missing/malformed, or a name is duplicated. The **distinct-naming rule** (any CI/test analogue takes a `*_SANDBOX` / `*_TEST` name) is the mechanism that keeps the sets disjoint.
- Per-surface `.env.example` files (each enumerates ONLY its container's permitted secrets — the enumeration *is* the confinement property): ⚠ **NEEDS RE-GRADING, not a flat retraction — measured 2026-09-14.** Measured live on the running stack: every service **inside a multi-service Coolify application** (the Supabase-stack resource — `db`/`auth`/`rest`/`migrator`/etc., one Coolify app UUID) receives the whole env store via `env_file:` in Coolify's own rendered compose, regardless of what its `.env.example` or declared block enumerates. The V1 web app and each worker below are **separately-deployed** single-service Coolify applications and were **not measured** — whether the same mechanism applies to a one-service app is an open question, not assumed either way. [ADR-072](../DECISIONS.md#adr-072) Amendment 3 (PR #760) withdraws Amendment 1's PRESERVED claim for the multi-service case; remedy is booked, not yet built, at `BACKLOG.md` §7.36 items 28–29.
  - [`.env.example`](../.env.example) — V1 web-app container (service_role + PDF signing key + Discord URL). ⚠ **No `PLAID_WEBHOOK_SECRET`, and no Plaid credential at all.** An earlier revision of this line said "Plaid creds + webhook secret"; both halves are wrong at the tree. The webhook secret was retired at [ADR-037](../DECISIONS.md#adr-037) — Plaid v27 webhook verification is asymmetric ES256/JWK against a PUBLIC key, so there is no shared secret to hold, and `.env.example` says so explicitly rather than merely omitting it. `PLAID_CLIENT_ID`/`PLAID_SECRET` are held by the **provider-sync worker only** (the delegated JWK fetch); keeping `api/src` credential-less is the load-bearing property that makes that delegation work. The variable name never appeared in this runbook — what survived here was a **prose paraphrase describing a secret `.env.example` no longer contains**, which is why a name-grep found nothing to sweep.
  - [`workers/etl/.env.example`](../workers/etl/.env.example) — `pfin_back_etl` container (discrete `PFIN_DB_*` + FMP + BLS + Plaid creds).
  - [`workers/pdf-render/.env.example`](../workers/pdf-render/.env.example) — PDF worker container (**exactly one** secret: `PDF_WORKER_SIGNING_KEY` — zero-DB-isolation per Lock 13 mod #2; RT-22 enforces no DB credential ever appears here).

**Scripted injection — `scripts/push-production-secrets.sh` — Sec-reviewed (non-blocking) and F/CTO-ratified 2026-09-11 (PR #738).** Replaces the by-hand Coolify UI entry for the app/worker secrets below with one scripted push, using the same `envs/bulk` API + SSH-stdin pattern `scripts/provision-supabase-stack.sh` already uses for its own `SMTP_PASS` operator override (no new mechanism). Reads secret **names** live from [`secrets-manifest.yml`](../secrets-manifest.yml)'s `production_only` set (never hardcoded — that would be exactly the drift the manifest exists to prevent) and **values** from the operator's gitignored local `.env`; never prints a value; reports names-only, grouped by resource.

`BOX_IP=<box-ip> scripts/push-production-secrets.sh [--apply] [--skip-missing-resource]` — same preflight/`--apply` convention as its siblings. See the script's own header comment for the full reasoning; summarized here as the ratified secret → resource mapping:

| Secret | Resource(s) | Note |
|---|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | `app` | RT-26 §4.1-allowlist-confined |
| `PDF_WORKER_SIGNING_KEY` | `app`, `pdf-render` | same value on both, per SD-20 |
| `DISCORD_WEBHOOK_URL` | `app`, `etl`, `provider-sync` | same value on all three (fourth consumer is Coolify's own control-plane notification setting, not a container env) |
| `WORKER_ADMISSION_SHARED_SECRET` | `app`, `provider-sync` | ⚠ **Ratified deviation (F/CTO + Sec):** pushed as an ordinary per-application env var identically to both, **not** via a Coolify "project-scoped shared variable" — that feature has no documented public REST API endpoint, only a dashboard (Livewire) flow. **Rotation discipline:** both stores are updated ONLY together, via one invocation of this script — never hand-edit one side. Drift between them fails CLOSED (provider-sync's constant-time compare denies admission), never open — an outage, never a bypass. |
| `FMP_API_KEY`, `BLS_API_KEY` | `etl` | |
| `PLAID_CLIENT_ID`, `PLAID_SECRET`, `SIMPLEFIN_TOKEN` | `provider-sync` | sole holder per ADR-011 D17/Lock 13 amendment |

**Explicitly excluded from this script** (fails closed — see script header — if the manifest ever adds a name with no mapping-table entry, rather than silently dropping it):
- The Supabase stack's own 9 `production_only` names (`POSTGRES_PASSWORD`, `JWT_SECRET`, `SECRET_KEY_BASE`, `VAULT_ENC_KEY`, `SERVICE_ROLE_KEY`, `ANON_KEY`, `DASHBOARD_PASSWORD`, `PG_META_CRYPTO_KEY`, `SMTP_PASS`) — already minted/overwritten by `provision-supabase-stack.sh` (+ the real JWT pair by `mint-supabase-jwt-keys.sh`); double-handling here would race that mint-if-absent logic.
- `PFIN_DB_PASSWORD` — **different value per container** (`pfin_etl` vs. `pfin_provider_sync`), and not generated until the interactive §6.1/§6.2 `\password` role handoff **after** migrations apply. Stays exactly where it already lives — never pushed by this script.

**Ordering note — RATIFIED (F/CTO): this runs functionally after §7, not before it, despite being numbered §5.** The `app`/`etl`/`pdf-render`/`provider-sync` Coolify resources are created in §7; this script can only push env vars onto a resource that already exists, and fails closed (naming the missing resource) rather than silently skipping one — `--skip-missing-resource` opts into a deliberate partial run instead (exit code **3**, distinct from a clean full run's exit 0, when it actually skipped one or more resources — see the script's own `--help`). The runbook's document order (§5 secrets, §6 migrations, §7 workers) and this script's actual execution order diverge deliberately; F/CTO ratified the divergence rather than this file's section numbers being resequenced.

**A redeploy is still required after pushing** — Coolify only injects the env store into a container at deploy (container-recreate) time; the script does not auto-redeploy the resources it touches (unlike `mint-supabase-jwt-keys.sh`, which owns exactly one resource and safely can) and prints which resources need a manual redeploy.

**Non-secret `PUBLIC_SUPABASE_URL` / `PUBLIC_SUPABASE_ANON_KEY`** (see the classification note above) are **not** pushed by this script — they're outside its manifest-driven charter and their real values are box state (the stack's own gateway URL and the real `ANON_KEY` already minted on the box), not an operator-`.env` value. Flagged as a natural follow-up, not built here.

> **STUB —** Still open regardless of the scripted push above, and NOT resolved by this PR: (a) ARCH §5 frames the ETL DB secret as a single conn-string while incumbent code consumes discrete `PFIN_DB_*` — representation difference, reconcile deliberately; (b) ARCH §5 frames BLS as "free/open" (no key) while incumbent code requires `BLS_API_KEY` — reconcile with ARCH/Sec. Also open: whether runbook §3's "ETL is one image, two Coolify units" resolves to one Coolify resource or two at §7 resource-creation time — `push-production-secrets.sh` currently assumes one (`ETL_RESOURCE_NAME`, overridable); if §7 registers two, the mapping table needs a second entry.

---

## 6. Apply migrations

Scope: apply the repo's `supabase/migrations/` against the fresh Postgres 17 instance, in order.

- Present migrations (verified): [`001_pfin_foundation.sql`](../supabase/migrations/001_pfin_foundation.sql), [`002_fn_mask_acct_number.sql`](../supabase/migrations/002_fn_mask_acct_number.sql).
- Phase 6 base-table migrations (SELF-187+) land incrementally — append them here as they're authored.
- **Ownership note:** migrations are **Architect-authored**; DevOps operates on CI's *consumption* of them (test-fixture spin-up per RT-15) and, here, on the production *apply* step. This runbook does not author migration content.

**Apply mechanism — the dedicated `migrator` service (Option E, ratified [ADR-072](../DECISIONS.md#adr-072)).** ⚠ **BUILT, NOT YET LIVE** — chunk 1 (container + role + Scheduled Task definition) and chunk 2 (the `ci-migrate` trigger: §6.4 below) are both built, pending this PR's own Sec joint-review; only the RT-27/RT-32 CI-fence extension (ADR-072 Consequences C9) remains unbuilt. **"Built" ≠ "live"**: the trigger does not fire on any push until the two F/CTO `!`-steps §6.4 names (the `CI_MIGRATE_SSH_PRIVATE_KEY` GitHub secret and a `provision-vps.sh --apply` run against the production box) both happen, post-merge. Until then, the interim/bootstrap apply is the operator `supabase db push --db-url "$PROD_DB_URL"` §4 already documents — that is the *same verb* at the bootstrap lifecycle point, not a second mechanism.

- **`$PROD_DB_URL` — where it comes from, for each of the two shells that use it. Gap closed 2026-09-13 (standup step 6, Phase B): §4 and this section use the bare shell variable `$PROD_DB_URL` throughout without ever defining it — it is not an ambient env var on the box, the operator's Mac, or in any `.env` this repo commits.**
  - **Inside the `migrator` container, at steady state:** already defined — `infra/supabase/docker-compose.yml`'s `migrator` service sets `PROD_DB_URL: postgres://${MIGRATOR_DB_USER}:${MIGRATOR_DB_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}` as a container env var, sourced from the mint described above. This is what the Scheduled Task's fixed command (`scripts/migrator-scheduled-task.md`) reads with no further setup, and what the "steady-state" bullet above assumes.
  - **For the FIRST bootstrap apply (§6.3's supervised, `postgres`-run pass) — NOT the same value.** The `migrator` role does not exist yet at this point (migration `118` is what creates it), so the container's own baked `PROD_DB_URL` — which authenticates as `migrator` — cannot be used; connecting as `migrator` before it exists fails at auth. **Neither `db` nor `supavisor` is host-published** (§4 (1d) — `expose:`-only, by design), so there is no address an operator's own machine or a bare box-root shell (outside the Docker project network) can dial directly; `psql`/`supabase db push` invoked from either place has no route to `db:5432` at all. The reachable vehicle is the `migrator` container itself — the one image on the box that bundles the `supabase` CLI and the baked `supabase/migrations/**` (see `infra/supabase/migrator/Dockerfile`) and sits on the same Docker project network as `db`. Run the bootstrap apply as a `postgres`-authenticated override of that container's own `PROD_DB_URL`, addressed by Coolify's compose **project name** (the Supabase-stack application UUID) rather than a guessed container name (§4's own "container names come from the compose" caution applies here too):
    ```sh
    # Source the superuser credential into the shell (never paste the literal --
    # a pasted value lands in ~/.bash_history AND in the docker client's argv,
    # where any local account can read it from `ps`). Then hand it to the
    # container on STDIN so it never appears in any host-side command line.
    set -a; . /root/.pfin/supabase.env; set +a
    printf '%s' "$POSTGRES_PASSWORD" | docker compose --project-name <supabase-stack-app-uuid> \
      exec -T -e PGSSLMODE=disable migrator sh -c '
        IFS= read -r PGPW
        DSN="postgres://postgres:${PGPW}@db:5432/postgres?sslmode=disable"
        printf "DSN sent: %s\n" "$DSN" | sed "s#:${PGPW}@#:***@#"
        supabase db push \
          --db-url "$DSN" \
          --workdir /workspace'
    ```
    Acceptance criterion: **no host-side process argv and no shell-history line may contain the superuser plaintext.** The echoed `DSN sent:` line elides the password (`sed` substitution) so a stranger running this sees exactly the string the CLI received, including the `?sslmode=disable` tail, without the record ever holding the plaintext. `POSTGRES_HOST`/`POSTGRES_PORT`/`POSTGRES_DB` are the same non-secret defaults already in the stack's env store (`db` / `5432` / `postgres`). This is the **same verb, same tracking table** as the container's own steady-state invocation — only the identity in the URL differs, and only for this one supervised pass.

    ⚠ **`PGSSLMODE=disable` is required, not optional — measured (standup step 6 Phase B.4, 2026-09-14 — see PR #759).** The URL's `?sslmode=disable` **did reach the CLI** (the bootstrap's password-elided `DSN sent:` echo shows the tail on the exact string it received) and was **NOT honoured** on the `db push` path. At v2.107.0 the `supabase` binary is a shim that forwards DB-affecting subcommands to the co-located `supabase-go` (the same shim architecture as the PR #753 companion-binary defect); the Go side resolves TLS from libpq environment variables, which is why `PGSSLMODE` takes effect and the query parameter does not. **The cause is not shell quoting** — an earlier note here said the parameter "never survived" and cited the CLI's legacy TypeScript path; that citation is withdrawn (it is the wrong path — `db push` does not take it), and the claim is corrected: the parameter survived and was ignored. **Do not drop `PGSSLMODE` on the belief that fixing "quoting" makes the URL parameter load-bearing** — it is the only mechanism measured to work; the URL param stays too, as the stated, greppable posture, but never rely on it alone. **Forward consequence:** this drop is direction-blind — a silently-ignored `sslmode=verify-full` would be a silent TLS downgrade with no error, so any future TLS-on-`db` work must use `PGSSLMODE`/`PGSSLROOTCERT` as the mechanism of record, never the URL.

    **Transport: plaintext, deliberately and explicitly** (Sec ruling, §7.36 item 26, 2026-09-14). `db` is `expose:`-only and never host-published (§4 (1d), CI-fenced by RT-32), so every Postgres connection in this stack stays on the internal Docker project network. `sslmode=disable` is stated rather than left to libpq's `prefer` default so the posture is visible in the file instead of inferred from a library. **This is void the moment `db` or `supavisor` becomes reachable off-host** — if any RT-32 vector is ever opened, TLS on this hop becomes required, not optional.
  - **The psql / `show server_version` verification snippets elsewhere in this file** (§4's bring-up verification, §4.1's TimeZone read-back) run against the **`db` service**, not the migrator — the migrator image deliberately carries no Postgres client (`infra/supabase/migrator/Dockerfile` installs `ca-certificates curl tar` only; `supabase db push` speaks the wire protocol directly). Use `docker compose --project-name <uuid> exec -T db psql -U postgres -d "$POSTGRES_DB" -c '…'`, which authenticates over the container's local socket and needs no password in any command line. **Do not add `postgresql-client` to the migrator image to make this bullet true** — the lean-image posture is deliberate.

    **The interactive §6.1 / §6.2 / §6.3 handoffs — use the helper, not the raw form (BACKLOG §7.36 item 33):**
    ```sh
    scripts/db-shell.sh --as postgres         # §6.1 / §6.2, as postgres
    scripts/db-shell.sh --as supabase_admin   # §6.3, as supabase_admin (the default)
    scripts/db-shell.sh --as postgres --print # prints the filled-in command instead of running it
    ```
    `scripts/db-shell.sh` reads `BOX_IP` and `MIGRATOR_SERVICE_UUID` from the repo-root `.env` — `BOX_IP` is written there by `scripts/provision-vps.sh --apply`; `MIGRATOR_SERVICE_UUID` by `scripts/record-coolify-uuids.sh --apply` (looks it up on the Coolify API by the resource's **name**, `pfin-supabase-stack`). Neither is a secret — an internal box address and a Coolify resource UUID.

    **The raw form it wraps, for reference or if the helper is unavailable:** `docker compose --project-name <uuid> exec -it db psql -U postgres -d "$POSTGRES_DB"` (§6.1/§6.2) or `-U supabase_admin` (§6.3) — a TTY is required for the prompt, and that prompt is the whole mechanism. `<uuid>` here is `MIGRATOR_SERVICE_UUID` — see above for where it comes from. ⚠ **If reaching any of these from off-box (F/CTO's own Mac, not an already-open box shell), the `ssh` hop itself needs `-t`** (`ssh -t root@<box-ip> 'docker compose ... exec -it db psql ...'`) — measured 2026-09-14: a bare `ssh` here gives `psql` no controlling terminal at all, silently, with no prompt and no error. `<box-ip>` is `BOX_IP` — see above. **The helper carries `-t` and both placeholders already filled in — this is the whole reason it exists.**
- **Verb (fixed):** `supabase db push`. It records each file in `supabase_migrations.schema_migrations` and skips what already applied — idempotent, ordered, safe to re-run after a partial failure. A bare `psql -f` loop is prohibited (no tracking table; would foreclose clean re-runs). This is the same table §4 line ~410 and the §4.1 `061` provenance limb already read.
- **Steady-state (built in chunk 2 — see §6.4 for the operator sequence that makes it live):** a migration merges → `.github/workflows/migrator-trigger.yml` opens SSH to the box as the dedicated non-root `ci-migrate` user (forced-command key) → `scripts/migrator-orchestrate.sh` (the sole thing `ci-migrate`'s `authorized_keys` line will ever run) executes the Coolify **Scheduled Task** that `docker exec`s `supabase db push` in the resident `migrator` container → **on the task's `success` status** the script triggers the app deploy (`GET localhost:8000/api/v1/deploy?uuid=<app-uuid>`); on `failed` (or a poll timeout) it exits non-zero and does NOT deploy, and Coolify→Discord's existing Scheduled-Task-failure routing fires on its own. **Fail-closed lives in the Scheduled Task's own exit status, never in Coolify's deployment status** (which marks FINISHED before a post-deploy command and swallows its failure — the trap ADR-072 Decision 3 records), and GitHub Actions' own step-sequencing is the CI-side half of that gate: the workflow has exactly one box-touching step, so a non-zero exit from the orchestration script fails the job outright with no second "did it deploy" step to paper over it. This trigger path **obviates the §6-item-(f) public auto-deploy webhook**.
- **First bootstrap (supervised, until SELF-395) — rewritten 2026-09-16, ADR-072 [Amendment 5](../DECISIONS.md#adr-072): ownership by construction, held by `pfin_owner`.** §6.3's supervised pre-step (`supabase_admin`, minimal — creates `pfin_owner` and `migrator` via their own migration files, grants `pfin_owner` to `migrator` with `SET TRUE`/no `INHERIT`, flips database ownership to `pfin_owner`, revokes `CREATE` on `pfin` from `migrator`, sets the password, flips `LOGIN`) runs **before** any migration applies → **then `migrator` itself applies the full 001–118 set from its own container, each file entering `pfin_owner` via a paired `set role`/`reset role`**, so every object it creates is `pfin_owner`-owned from the first row (the ledger schema alone stays `migrator`-owned) → **then the interactive §6.1/§6.2 `\password` handoffs below** → §5 env → §7 containers. E cannot perform the interactive handoffs yet; SELF-395 (client-side SCRAM scripting, SECURITY-GATED, not yet built) is what will let it own the full hands-off bootstrap.
- **Two update channels for the migrator itself** (ADR-072 Decision 5): *container side* — migrations baked at build, versioned in `infra/supabase/`, rebuilt on a migration merge, with the load-bearing sequence **rebuild image → run the Scheduled Task → then deploy app**; *box side* — the orchestration script + `ci-migrate` user + `authorized_keys` line versioned in `scripts/`, materialized by `provision-vps.sh`.
- **Credential:** a bounded migrator role (`CREATEROLE` + DB-owner, **distinct** from `postgres`/`authenticator`/`pfin_*`, NOT a member of `service_role`/`authenticated`), confined to the `migrator` service env only — a confinement that holds **by non-reference** (Coolify runs plain, interpolation-only `docker compose`, so a shared-store var reaches only the service whose block references `${VAR}`; only `migrator` references `${MIGRATOR_DB_PASSWORD}`). ⚠ **RETRACTED — measured false, 2026-09-14.** Measured live on the running stack: every service in the Supabase-stack Coolify application receives the whole env store, via `env_file:` in Coolify's own rendered compose — not by reference to what a service's `environment:` block declares. The confinement described above does not hold. [ADR-072](../DECISIONS.md#adr-072) Amendment 3 (PR #760) withdraws Amendment 1's PRESERVED claim; remedy is booked, not yet built, at `BACKLOG.md` §7.36 items 28–29. Because the migrator is a **sibling service in the Supabase-stack compose** (one Coolify app UUID, shared env store), the credential is minted **on-box by `provision-supabase-stack.sh`'s `MINT_SECRETS` (mint-if-absent), NOT by `push-production-secrets.sh`** — realized as a new `production_only` manifest name + a `MINT_SECRETS` entry (`MIGRATOR_DB_PASSWORD`, 32B) + `MIGRATOR_DB_USER` in `NONSECRET_DEFAULTS` + inclusion in the check-if-absent/post-mint assert arrays + the migrator's `.env.example`. See [ADR-072](../DECISIONS.md#adr-072) Amendment 1 (2026-09-12). Built in the Option-E chunk-1 PR (#741).
- **Verify each migration landed:** `schema_migrations` carries the expected head row for the applied chain; RLS policies present on `pfin` relations; `pfin.fn_mask_acct_number` callable. (QA owns the isolation battery; §10 owns the smoke gate.)
- **Coolify-upgrade dependency (CA-1 extension, ADR-072 Decision 7):** after any Coolify upgrade, re-verify the three version-dependent assumptions — Scheduled-Task exit-code `status` semantics, `rolling_update()` health-gated swap, and the deploy-API shape — before trusting E on the upgraded control plane.

### 6.0 Before you start §6.1/§6.2/§6.3 — prepare all three passwords, and know the box's actual privilege shape

**Added 2026-09-14, after F/CTO executed Phase B step 5 live and this section did not match what happened.** Two corrections, both load-bearing:

**`.env` is the main checkout's; agent worktrees have their own and it is discarded.** 2026-09-16 incident: `record-coolify-uuids.sh` and `provision-vps.sh`'s `BOX_IP` writer resolved "repo root" as `dirname "$0"/..`, which inside an agent worktree (`.claude/worktrees/<name>/`) IS the worktree — five names (`BOX_IP`, `MIGRATOR_SERVICE_UUID`, `APP_UUID`, `MIGRATOR_TASK_UUID`, `CI_MIGRATE_SSH_PUBKEY`) were written to the worktree's own throwaway `.env`, not the repo-root one F/CTO's own runs read, and vanished when the worktree was removed at merge. Fixed: these scripts now resolve `REPO_ROOT` via `git rev-parse --git-common-dir` (shared across every worktree of a repo) and refuse outright when invoked from inside `.claude/worktrees/` unless `REPO_ROOT` is set explicitly — no more silent wrong-file writes.

**Step 0 — generate/look up all three passwords BEFORE opening any `psql` session**, so the interactive handoffs below are typed straight through with no context-switching:

1. **`pfin_etl` and `pfin_provider_sync` — generate two fresh values, kept for §5's secrets push as the ETL and provider-sync DB passwords:**
   ```sh
   openssl rand -hex 32   # value 1 -- pfin_etl
   openssl rand -hex 32   # value 2 -- pfin_provider_sync
   ```
2. **`migrator` — do NOT generate a new value.** It is already minted (`provision-supabase-stack.sh`'s `MINT_SECRETS`, §6 above) and baked into the running container. Look it up from there, never printed to this record or any chat — **use the helper, which carries the OPERATOR-ONLY guard below by construction** (BACKLOG §7.36 item 33):
   ```sh
   scripts/db-shell.sh --migrator-url --i-am-a-human
   ```
   Reads `BOX_IP`/`MIGRATOR_SERVICE_UUID` from the repo-root `.env` (see the vehicle note in §6 above for where those come from) and refuses to run unless both stdin and stdout are a real terminal — an agent, a pipe, or a non-interactive caller cannot satisfy that. **The raw form it wraps**, for reference:
   ```sh
   ssh -t root@<box-ip> 'docker compose --project-name <supabase-stack-app-uuid> exec -T migrator sh -c "echo \$PROD_DB_URL"'
   ```
   `<box-ip>` = `BOX_IP`; `<supabase-stack-app-uuid>` = `MIGRATOR_SERVICE_UUID` — both from `.env`, per the vehicle note above. The password is the substring between `migrator:` and `@db` in the printed URL.

   ⚠ **OPERATOR-ONLY, at a human terminal. An agent must NOT run this command.** It deliberately prints a live credential, which is the one case the [SECURITY §4.2](SECURITY/index.html#container-env-dump-credential-disclosure) names-only rule permits — *because the operator needs the value*, not merely its name. **An agent running it writes `MIGRATOR_DB_PASSWORD` into a session transcript, which is precisely the 2026-09-14 disclosure and cost a rotation.** Read it, type it into `\password`, and do not paste it into a report, a PR, a chat, or a commit. The value also lands in this shell's scrollback and in `~/.bash_history` if you edit the line — prefer a fresh shell.

**On this image, `postgres` is NOT a superuser — measured live, 2026-09-14.** `select rolsuper from pg_roles where rolname='postgres'` → `f` (it does hold `rolcreaterole`/`rolcreatedb`, which is why §6.1/§6.2 below still work as `postgres` — `\password` only needs `CREATEROLE`/`ADMIN OPTION` on the role, per each section's own "Operator privilege" line). Its prompt is `postgres=>`. The true superuser on this image is `supabase_admin` (`rolsuper=t`, prompt `postgres=#`) — **§6.3's pre-step (role creation, `ALTER DATABASE … OWNER TO pfin_owner`, and the rest) requires actual superuser and fails as `postgres`** (`ERROR: must be able to SET ROLE`, measured live against the equivalent `migrator` statement before Amendment 5). **Run every one of §6.3's pre-step statements as `supabase_admin`**, not `postgres`. §6.1/§6.2 are unaffected and stay as `postgres`.

**Every interactive vehicle in this section needs `ssh -t` (or `-tt`), not a bare `ssh`.** Measured live: `ssh root@<box-ip> 'docker compose ... exec -it db psql ...'` without `-t` gives `psql` no controlling terminal — no prompt, no output, no error, just silence. `-t` forces pseudo-terminal allocation through the SSH hop so the remote `-it` actually gets a TTY. Every `ssh ... exec -it ...` one-liner below (and in the hand-off block any report gives F/CTO) must carry `-t`.

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

> **Apply mechanism — RESOLVED** at the top of §6 above ([ADR-072](../DECISIONS.md#adr-072), Option E: the resident `migrator` service run by a Coolify Scheduled Task, SSH-triggered, fail-closed on the task's own status; verb fixed to `supabase db push`; idempotency/ordering via `schema_migrations`; verify-each-landed checks listed there). Build is deferred and gated on ADR-072's Sec joint-review. **Keep the migration list at the top of §6 current as Phase 6 adds tables** — that housekeeping remains ongoing.

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

### 6.3 `pfin_owner` + `migrator` provisioning and first bootstrap — SUPERVISED pre-step, then `migrator` applies the full set entering `pfin_owner`

**Replaces the two prior drafts of this section in place — 2026-09-16, ADR-072 [Amendment 5](../DECISIONS.md#adr-072) (Decisions A/B/D/E/F/G), Sec GREEN.** This section went through two shapes before this one: `postgres`-run bootstrap + a later ownership transfer (left every `pfin` object owned by whoever ran the apply — §7.36 item 32 and its wider cousin, measured 2026-09-16: 39 tables/97 indexes/34 sequences/7 views/116 functions/3 enum types, all `postgres`-owned); then "`migrator` applies everything" (accepted goal, but Decision A measured **by execution** that `migrator` cannot reach it — see below). **What follows is the ratified shape: ownership by construction, held by a group role every applier enters, not by the applying identity itself.**

**Why `migrator` alone cannot apply `001`–`118` (Decision A, measured by execution on a disposable PG 17.6 cluster, not inferred from an ACL read).** Four independent walls, each hit at its first site: (1) `auth` schema unreachable — no `USAGE`, no `REFERENCES`/`SELECT` on `auth.users`, and **24 migrations** carry `references auth.users(id)`; (2) `vault` schema unreachable — two owner-semantics decrypt views (`007`, `015`) fail to even `create view`; (3) role-graph grants refused — PG 16+ requires ADMIN OPTION to grant a role, and `055`/`116` grant `service_role`/`authenticated` to the worker roles; (4) `comment on role` refused for any role `migrator` did not create, and **unfixably refused for itself** (`grant migrator to migrator with admin option` is rejected — a role cannot hold ADMIN OPTION on itself). Wall 3 is the one that cannot be bought: closing it needs `migrator` to hold ADMIN OPTION on `service_role`/`authenticated`, which is *stronger* than the app-role membership already refused — a bounded role with ADMIN OPTION on the app roles is not bounded. **Sec vetoed that leg outright.**

**The resolution: `pfin_owner`, a NOLOGIN group role that owns every `pfin` object, entered by every applier via a paired `set role` / `reset role`.** Ownership is then right by construction *whichever identity applies* — the durable property the earlier "migrator applies everything" goal wanted, achieved without widening `migrator` onto the role graph. The handful of statements no bounded role can ever run (role creation, the app-role grants, the `comment on role` statements) stay in a small, named, supervised lane — the pre-step below.

**`pfin_owner`'s exact attributes and reach (Decision E, corrected by G2; vault disposition ⚠ UNSETTLED — see box below).** NOLOGIN, NOINHERIT, no password, **no `CREATEROLE`** (Sec §2 — a `CREATEROLE` creator receives ADMIN OPTION on what it creates, and `055`/`116` then grant an app role to what they create: a transitive path into `service_role` C8 forbids), no app-role membership, not superuser/CREATEDB/BYPASSRLS/REPLICATION. Reach outside `pfin`, **exactly**: `usage on schema auth` plus **column-level** `references (id), select (id) on auth.users` — `id` is the only column any FK site or the `103` seed read needs; table-level would hand every user row, `encrypted_password` included, to a role `PROD_DB_URL` reaches by `SET ROLE`.

**⚠ TODO — vault disposition (iii) is FALSIFIED, not settled. Do not treat the paragraph below as current.** Amendment 5 ratified (iii) — `007`/`015`'s decrypt views become `security_invoker = true`, "removing" the owner's vault dependency — on Architect's basis clause and Sec's grading. **Architect ran it through the CREATE path on 2026-09-17 and it does not hold**: a view body is permission-checked at `CREATE VIEW` time regardless of `security_invoker`; creating such a view as a role with no `vault` privilege is refused (measured, disposable PG 17.6, mid-sweep on `feat/migrations-pfin-owner-sweep`). `security_invoker` moves only the *runtime* identity — wall 2 is **narrowed, not deleted**, `pfin_owner` still needs `vault` USAGE+SELECT to *apply* `007`/`015`, and that re-engages Sec's original §1 veto (grant vault reach to a role `migrator` enters by `SET ROLE`). Architect is choosing among: (i) a separate owner for the two views, not member-reachable from `migrator`; (ii) a dated residual on the 28/29 gate; (iv) the two view CREATEs move into the supervised pre-step so `007`/`015` join the supervised lane for those statements only (Architect's stated cheapest option, not yet ruled). **Do not run the pre-step's `007`/`015` handling as `pfin_owner`-owned-by-construction until this is re-ratified — treat "No vault grant of any kind" below as the pre-Amendment-5-correction claim, not a current fact.**

~~**No vault grant of any kind** — F/CTO ratified disposition (iii) (`007`/`015`'s decrypt views become `security_invoker = true`), which *removes* the owner's vault dependency rather than relocating it; `service_role` already holds `SELECT`+`DELETE` on both `vault` relations in the image's own ACL, so nothing new is granted to anyone and wall 2 is deleted outright, not moved.~~ **(FALSIFIED 2026-09-17 — see TODO above.)**

**⚠ Dependency this section cites but does not author: the `pfin_owner` migration file itself.** Architect's `feat/migrations-pfin-owner-sweep` (BACKLOG §7.36 item 39) adds `pfin_owner` to the `055`/`116`/`118` family — its own file, its own pgTAP battery, single source of truth for its attribute set, run by the pre-step the same way `118` is run below. **That PR is in flight, not yet on `main`.** This runbook cites it by role, not by a migration number, until it merges — treat every `psql -U supabase_admin -f supabase/migrations/<file>` line below naming `055`/`116`/`118` as the pattern the `pfin_owner` file joins once it lands, at whatever number Architect assigns it.

**Ordering — do not reorder:**

> **pre-step, `supabase_admin`, interactive: run the `pfin_owner`, `055`, `116`, `118` files → the `pfin_owner`-specific grants → `ALTER DATABASE … OWNER TO pfin_owner` → the engine backstop `REVOKE` → `\password migrator` → `ALTER ROLE migrator LOGIN`** → **`MIGRATOR_DB_*` env already minted on-box (`provision-supabase-stack.sh` MINT_SECRETS) and injected into the migrator service (§5)** → **`migrator` applies the FULL migration set (001–118, entering `pfin_owner` per-file, including a second, tolerant pass over the role-creation files) from its own container, using its own baked `PROD_DB_URL` — no override** → **§6.1/§6.2 worker-role handoffs, as today** → **§7 containers**

**The pre-step.** Run **once** against the target database, in an interactive `psql` session, **as `supabase_admin`** (the image's true superuser — see §6.0 for why not `postgres`). Each numbered file-run below executes that migration's literal bytes directly, never a hand-mirrored copy — the same drift-proofing principle already established for `118`, extended to every role-creation file: running the file as `supabase_admin` naturally lands its embedded `CREATE ROLE`, its `GRANT service_role`/`authenticated`, and its `COMMENT ON ROLE`, because the applier holds ADMIN OPTION as the creator. **This one run is what lands those comments and grants — see the tolerant-guard note below for why the later re-apply under `migrator` does not need to repeat it.**

```sh
# (0) Role-creation files, run directly, in this order -- the single source
#     of truth for each role's attribute set. Each file creates only its
#     own role, its grants, and its comment.
psql -U supabase_admin -d <app_db> -f supabase/migrations/<pfin_owner_file>.sql   # see dependency note above
psql -U supabase_admin -d <app_db> -f supabase/migrations/055_pfin_etl_role.sql
psql -U supabase_admin -d <app_db> -f supabase/migrations/116_pfin_provider_sync_role.sql
psql -U supabase_admin -d <app_db> -f supabase/migrations/118_migrator_role.sql
```
```sql
-- (1) membership: NOINHERIT means migrator reaches pfin_owner only via SET
-- ROLE, never ambiently; per-membership in PG 16+ and no admin option, so
-- a later ALTER ROLE migrator INHERIT cannot make the reach ambient.
GRANT pfin_owner TO migrator WITH INHERIT FALSE, SET TRUE;
-- (2) the out-of-pfin reach pfin_owner needs and nothing more -- column-
-- level, not table-level (Sec §G2).
GRANT USAGE ON SCHEMA auth TO pfin_owner;
GRANT REFERENCES (id), SELECT (id) ON auth.users TO pfin_owner;
-- (3) superuser-only; pfin_owner is not CREATEDB and cannot run this itself
ALTER DATABASE <app_db> OWNER TO pfin_owner;
-- (4) the ENGINE BACKSTOP -- now the PRIMARY control (Sec §G2), not
-- belt-and-braces: `set role` is session-scoped with no transaction to
-- roll it back, so a migrator session that forgets the pair must fail
-- closed on its own CREATE attempt, not rely on the pair being present.
REVOKE CREATE ON SCHEMA pfin FROM migrator;
-- (5) prompts; verifier computed CLIENT-SIDE; role still NOLOGIN -> inert
\password migrator
-- (6) carries no secret
ALTER ROLE migrator LOGIN;
```

`\password` sets **only** the password — the credential lands while the role is still `NOLOGIN`, and `LOGIN` then flips onto an already-credentialed role, so **LOGIN-with-no-password never exists at any instant**. The single-statement form `ALTER ROLE migrator WITH LOGIN PASSWORD '…'` is **PROHIBITED** (Sec B10). Generate the password with `openssl rand -hex 32` if minting fresh; **in production the value is already minted on-box** — look it up, don't regenerate it (`scripts/db-shell.sh --migrator-url --i-am-a-human`, §6.0 Step 0.2), and set `\password` to match. **Operator privilege:** every pre-step statement requires true superuser (`supabase_admin` on this image, not `postgres` — measured, `postgres` fails `ALTER DATABASE … OWNER` with `ERROR: must be able to SET ROLE`).

**⚠ TODO — migration `119`'s apply mechanism, pending Architect's G4 supplement (2026-09-16, not yet landed).** Amendment 5's Decision G4 gives `119` a disposition (supervised lane, fail-closed — its `comment on role` guard never degrades to skip, unlike `118`) but Sec found the amendment names **no apply mechanism** for it: `119` is not in the pre-step's file list, so the first `migrator db push` would fail closed on it, and every later one would too. Architect is adding a G4 supplement: the supervised pre-step applies `119` through the CLI as `supabase_admin` (mirroring the role-creation files' shape — the ledger row lands there, the `migrator` pass then finds it already tracked and skips it cleanly), landing an exact command and its position in this ordered list. **Do not run this pre-step as written until that command lands here** — this placeholder marks the gap rather than inventing one. **OPERATOR-ONLY, same treatment as the role creation above** (interactive, superuser, never scripted).

**Then the apply, from `migrator`'s own container, as `migrator`, no `--db-url` override:**

```sh
docker compose --project-name <supabase-stack-app-uuid> exec -T migrator supabase db push --workdir /workspace
```

**Expected output:** every one of `001`–`118` applies in order (plus the `pfin_owner`/`055`/`116`/`118` role-creation files' second, tolerant pass), `supabase_migrations.schema_migrations` is created and owned by `migrator` from the start (the ledger stays `migrator`'s — see below, it is the one thing NOT swept into the `pfin_owner` lane), and the CLI reports success with the full row count tracked. **This depends on `001`–`118` already carrying the paired `set role pfin_owner;` / `reset role;` wrapper** (Decision G3's one-time sweep, Architect's `feat/migrations-pfin-owner-sweep`, the same in-flight PR named above) — **without that sweep, this apply creates every object owned by `migrator`, reproducing the original defect.** This is the runbook's second named dependency on that PR.

**⚠ Known-dead-end as written, do not attempt: this apply will currently die at `007` with `permission denied for schema vault`, even with the sweep landed.** Architect ran the end-to-end sweep on 2026-09-17: `001`–`006` applied clean, all `pfin` relations landed `pfin_owner`-owned, 6 ledger rows written — the G3 mechanism itself is proven — then `007` failed because `pfin_owner` has no `vault` grant under the (now-falsified) disposition (iii). See the TODO box above §6.3's attributes paragraph. **This apply block is not runnable past `006` until Architect re-rules the vault disposition** ((i)/(ii)/(iv)) and this section is updated with whichever shape lands — a separate owner, a dated residual, or `007`/`015` moving into the supervised pre-step.

**The paired form, and why it is the only one that works (Decision F1, measured through the real apply path, not inferred).** `set local role pfin_owner;` alone is a **silent no-op** — `supabase db push` does not wrap a migration file in a transaction, so `SET LOCAL` has nothing to scope to and the CLI prints `WARNING 25P01` and moves on, leaving the object `migrator`-owned. A bare `set role pfin_owner;` with no `reset role;` **leaks into the CLI's own ledger `INSERT`**, which then fails with `permission denied for schema supabase_migrations` because `pfin_owner` does not own the ledger. **Only the paired form — `set role pfin_owner;` as the first non-comment statement, `reset role;` as the last — lands the object as `pfin_owner` AND writes the ledger row as `migrator`.** Never `ALTER ROLE … SET role` (migration `116` leg r12 already forbids a per-role session default as a *"POSTURE BYPASS"*, catalog-invisible and self-grantable — the same vector).

**The role-creation files' tolerant guard, and why the second pass needs it.** When `migrator` applies the full set, it re-executes the `pfin_owner`/`055`/`116`/`118` files a second time — this time finding each role **already exists**, its grants and comment already landed by the pre-step. Each guard must **report, not repair** on that pre-existing state (matching `055`/`116`'s existing posture for their own roles) while **still hard-failing a genuine C8 attribute violation**. `118`'s header line — *"`rolcanlogin` is FALSE at migration time and TRUE only in a provisioned environment"* — is worded as an assertion that is no longer accurate once `118` runs twice in the same bootstrap (first pass: `f`; the tolerant second pass under `migrator`: `t`) — **booked for Architect, comment-only, §7.36 item 38.** The `comment on role` statements inside these files are guarded to become a `RAISE WARNING` (never `notice` — Sec's condition, a silent skip is the same defect the `pg_authid` guard degradation already shows) when the applier lacks ADMIN OPTION, landing only on the pre-step's run — §7.36 item 40 names this supervised lane.

**Verify — the ownership census, not the read verb alone** (read-only; run as `supabase_admin`):

```sql
-- (1) migrator's own attributes -- expect: canlogin t, inherit f, createrole f, super f, createdb f, bypassrls f
select rolcanlogin, rolinherit, rolcreaterole, rolsuper, rolcreatedb, rolbypassrls
  from pg_catalog.pg_roles where rolname = 'migrator';
-- (2) pfin_owner membership -- NOINHERIT, SET TRUE, no ADMIN OPTION
select pg_get_userbyid(roleid) as granted_role, admin_option, inherit_option
  from pg_auth_members where member = 'migrator'::regrole and roleid = 'pfin_owner'::regrole;
-- expect: pfin_owner | f | f
-- (3) database ownership -- set by the pre-step; NOT migrator (Decision E)
select d.datname, pg_catalog.pg_get_userbyid(d.datdba) as owner
  from pg_catalog.pg_database d where d.datname = current_database();
-- expect owner = pfin_owner
-- (4) engine backstop still in place
select has_schema_privilege('migrator', 'pfin', 'CREATE');
-- expect: f
-- (5) no app-role membership (defense; the role-creation files also hard-assert this)
select pg_catalog.pg_has_role('migrator','service_role','MEMBER') as in_service_role,
       pg_catalog.pg_has_role('migrator','authenticated','MEMBER') as in_authenticated;
-- expect: f | f
-- (6) worker-role memberships landed (Sec's wall-(c)-relocation verify leg)
select r.rolname, pg_get_userbyid(m.roleid) as granted_role
  from pg_auth_members m join pg_roles r on r.oid = m.member
  where r.rolname in ('pfin_etl','pfin_provider_sync') order by 1,2;
-- expect four rows: each role x {authenticated, service_role}
-- (7) THE OWNERSHIP CENSUS -- expect every pfin object owned by pfin_owner, ZERO by migrator or postgres
select pg_get_userbyid(relowner), relkind, count(*) from pg_class c
  join pg_namespace n on n.oid = c.relnamespace where nspname = 'pfin' group by 1, 2 order by 1, 2;
select pg_get_userbyid(proowner), count(*) from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace where nspname = 'pfin' group by 1;
-- (8) the ledger schema -- expect migrator (NOT pfin_owner -- the one exception, Decision F1/F3)
--     AND the ledger shows one row for 119, owner-side (Architect's G4
--     supplement -- 119 applies through the supervised pre-step's CLI
--     call, TODO above, so its ledger row lands there, not in the
--     migrator pass)
select pg_get_userbyid(nspowner) from pg_namespace where nspname = 'supabase_migrations';
select count(*) from supabase_migrations.schema_migrations;
select version from supabase_migrations.schema_migrations where version like '119%';
-- expect: exactly one row
-- (9) the four seed tables re-populated -- expect asset=7, posting_prototype_default=30, tax_character=5, taxonomy_default=38
select 'asset', count(*) from pfin.asset union all
select 'posting_prototype_default', count(*) from pfin.posting_prototype_default union all
select 'tax_character', count(*) from pfin.tax_character union all
select 'taxonomy_default', count(*) from pfin.taxonomy_default;
```

**Pass criterion.** Every row at (7) reads `pfin_owner` — any `postgres` OR `migrator` row means the pair broke somewhere in the apply and the run must not proceed to Phase C/D; do not paper over it with a manual `ALTER … OWNER TO`, the emergency-transfer shape this design replaced. (8) is the one deliberate exception: the ledger stays `migrator`-owned because `migrator`, not `pfin_owner`, is the connecting role the CLI's own `INSERT` runs as — **and the ledger must show exactly one row for `119`, landed by the pre-step's own CLI call (the TODO above), never by the `migrator` pass**; zero rows means the TODO was skipped and `119` is unapplied, more than one means it applied twice somewhere it shouldn't have. Then confirm `rest` reports `healthy` (`docker inspect .State.Health.Status`) now that `pfin` exists again.

**`SECURITY DEFINER` functions and owner-semantics views — the ownership question is asked once, at authoring time (Decision C).** The governing predicate is *every object that executes with its OWNER's privileges* — DEFINER functions **and** views with `security_invoker = false` — not `prosecdef = true` alone; the same enumeration mistake missed `pfin.linked_source_sync_history` (`040`) and the `044` sync-audit view. ⚠ Disposition (iii) is falsified as of 2026-09-17 (see §6.3's TODO box) — `007`/`015` under `security_invoker = true` still require `pfin_owner` to hold `vault` USAGE+SELECT at CREATE time, so they are **not** free of an owner-privilege dependency; treat the "no owner-privilege dependency" claim as pending Architect's re-ruling among (i)/(ii)/(iv), not current. The remaining `prosecdef = true` functions are `pfin_owner`-owned from creation and need INSERT on the table they write, which ownership already grants (no `force row level security` exists anywhere in the set — measured zero, against 42 `enable` — a watched property, not an assumption: a pgTAP leg asserts it, so a future `force` addition fails loudly). **Co-ownership (function owner = table owner) must be verified post-bootstrap, and `fn_emit_audit_log`'s EXECUTE ACL — the entire perimeter for that function — must be re-measured after this apply.**

**The by-design tripwire, unchanged in intent.** `pfin_owner` holds no `ADMIN OPTION` on `postgres`/`authenticator`/`pfin_etl`/`pfin_provider_sync`/`migrator` and is not superuser, so a future migration needing true superuser (a new extension, `ALTER SYSTEM`) still fails under this design — forcing a supervised, named-lane pass and a Sec conversation, never a silent widening. This is the intended Decision-4 behaviour, now anchored to a role no applier can escalate through.

**Scripted (non-interactive) bind depends on SELF-395.** `\password` is interactive, which is why the pre-step is supervised. SELF-395 (client-side SCRAM scripting, SECURITY-GATED, not yet built) is what will let the bind be scripted for a fully hands-off bootstrap.

---
### 6.4 CI trigger provisioning — `ci-migrate` + GitHub Actions · 🔒 SECURITY-SENSITIVE

**This is the box-side + CI-side half of ADR-072 Option E's steady-state trigger** (§6's "Steady-state" bullet above summarizes the mechanism; this section is the concrete operator sequence). Built in the Option-E chunk-2 PR: `scripts/provision-vps.sh`'s `ci-migrate user` / `orchestration script` / `authorized_keys` / `migrator-trigger Coolify API token` steps, `scripts/migrator-orchestrate.sh`, and `.github/workflows/migrator-trigger.yml`. *(ADR-072 Decision 2 C1–C5; SELF-398 Sec joint-review.)*

**Ordering dependency — do not reorder:**

> **chunk 1 on `main`** (migrator container + role + Scheduled Task exist — §6.3, `scripts/migrator-scheduled-task.md`) → **create the Scheduled Task + the V1 web app resource in Coolify, note both UUIDs** → **generate the `ci_only` keypair** → **`provision-vps.sh --apply` with `CI_MIGRATE_SSH_PUBKEY` + `MIGRATOR_SERVICE_UUID` + `MIGRATOR_TASK_UUID` + `APP_UUID` set** (materializes `ci-migrate`, the forced command, the orchestration script, and the scoped Coolify token — this step is idempotent and safe to re-run) → **put the keypair's PRIVATE half in this repo's GitHub Actions secrets as `CI_MIGRATE_SSH_PRIVATE_KEY`** → **set the `PROD_SSH_HOST` repository *variable*** → **push touching `supabase/migrations/**` exercises the trigger for real.**

**The step (operator, once per box; the last two sub-steps repeat only on key rotation):**

1. **Create the Coolify resources first, if not already done** (§7 creates the V1 web app; `scripts/migrator-scheduled-task.md` documents the Scheduled Task's fields). Read their UUIDs off the dashboard, or `GET /api/v1/services` / `GET /api/v1/applications` through the operator's own SSH tunnel (§3).
2. **Generate the `ci_only` keypair** — `ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519_ci_migrate` (no passphrase; this key authenticates a headless GitHub-Actions runner, never a human — same reasoning as `provision-vps.sh`'s own `SSH_PUBKEYS` automation-key requirement, §1). **Never commit either half.**
3. **Set the local `.env`** (`scripts/provision.env.example` documents all five): `CI_MIGRATE_SSH_PUBKEY` (path to the `.pub` file from step 2), `MIGRATOR_SERVICE_UUID`, `MIGRATOR_TASK_UUID`, `APP_UUID` (from step 1), and `DEPLOY_ON_SUCCESS` (default `0` — Sec-ruled deploy gate, Phase D deploy-gate consult: the first live exercise of a remotely-reachable trigger holding a deploy-capable token should do the smallest thing it can, so a successful migration apply withholds the app deploy until this is deliberately flipped to `1` at §7 step 7).
4. **Run `scripts/provision-vps.sh --apply`.** Preflight (no `--apply`) first to read the plan — every step in this section follows the same "check state, print or apply the diff" idempotence convention as the rest of this script. This creates `ci-migrate`, writes its sole `authorized_keys` forced-command line, materializes `scripts/migrator-orchestrate.sh` onto the box (root-owned, `0755`, not writable by `ci-migrate`), writes the non-secret `/etc/pfin/migrator-trigger.conf` (now carrying `DEPLOY_ON_SUCCESS`, default `0`, alongside the three UUIDs), and mints the scoped `migrator-trigger` Coolify API token (`read`+`write`+`deploy` — **not** `root`; see the script's own step comment for exactly which endpoints need which ability and why this is narrower than ADR-072 C4's "effectively root" framing) into `/etc/pfin/migrator-coolify-token.env` (`ci-migrate:ci-migrate`, `0600`). **Your terminal shows nothing new during this specific step.** The mint's remote output is captured to a local temp file, not streamed live, so its content can be leak-checked before anything reaches your screen (2026-09-16 finding, folded into PR #772) — an "ok ... minted" line (or a FAIL) appears only once the step finishes. Seeing no output for a while here is not evidence of a hang.
5. **Add the GitHub Actions secret** — repo Settings → Secrets and variables → Actions → New repository secret → `CI_MIGRATE_SSH_PRIVATE_KEY` = the keypair's PRIVATE half from step 2. **Never paste it anywhere else** — not into `.env`, not into a PR description, not into a Discord message.
6. **Add the GitHub Actions repository *variable*** (same page, *Variables* tab, not *Secrets* — an SSH destination address is not confidential, the same reasoning `secrets-manifest.yml` already applies to `PUBLIC_SUPABASE_URL`) — `PROD_SSH_HOST` = the box's IP, or `pfindash.com` once DNS is cut over (§2/§9).
7. **Verify** — push a no-op change touching `supabase/migrations/**` (or `workflow_dispatch` if the workflow is later extended to support it) and confirm the Action's single SSH step succeeds. A closed port 22, a missing/rotated key, or a stale `authorized_keys` line all surface as that one step failing — there is no second signal to check.

**Rotation.** Regenerate the keypair, re-run steps 2 (new keypair) → 4 (`provision-vps.sh --apply` overwrites the single `authorized_keys` line — idempotent, safe) → 5 (overwrite the GitHub secret). The box-resident config and the Coolify token are untouched by a key rotation; **to rotate the Coolify token itself**, delete the `migrator-trigger` token row via the Coolify dashboard (or `tinker`, mirroring `provision-vps.sh`'s own orphan-clear branch) and re-run `--apply`.

**What this section does NOT change.** The Scheduled Task's own definition (`scripts/migrator-scheduled-task.md`) and the migrator credential (§6, Amendment 1) are chunk-1 artifacts, untouched here. `scripts/migrator-orchestrate.sh` ignores `$SSH_ORIGINAL_COMMAND` entirely (ADR-072 C2) — this workflow's SSH command is a formality; the box always runs the same script regardless of what is sent.

---

### 6.5 Migrator bring-up — operator execution order

**This is a consolidation index, not a new procedure.** The ADR-072 Option-E migrator (chunks 1–3: #741/#743/#744/#746, plus Amendments 1–2: #742/#745) is code-complete on `main` but **not yet live** — §6 already says so. This section is the single place a stranger reads the whole go-live order; every step below points at the section that owns its commands and detail. **No command or claim here is new** — where a step's detail does not yet exist in a referenced section, that gap is named as a gap, not filled in.

**Ordering dependencies (do not reorder across phases):** Phase A before Phase C — the CI trigger step (§6.4) consumes the UUIDs Phase A produces. Phase B before Phase D — the `migrator` role must exist and be switched on (§6.3) before any unsupervised, CI-triggered apply (§6.4) is safe to exercise. Within Phase B, the `\password`/`LOGIN` handoffs stay a supervised, interactive operator action until SELF-395 (client-side SCRAM scripting) ships — see §6.3's own note.

**Phase A — Coolify resources & migrator container**

1. Create the V1 web-app Coolify resource; note its `APP_UUID`. **Gap:** §7 is still a STUB for this step — it names the web-app as the 3rd fleet container but does not yet carry concrete Coolify resource-creation instructions. Until §7 is filled in, this step has no home to point at beyond the Coolify dashboard itself.
2. Create the migrator Coolify Scheduled Task (`scripts/migrator-scheduled-task.md` — task fields, resource attachment, the fail-closed `status` semantics); note the `MIGRATOR_SERVICE_UUID` (the Supabase-stack resource) and `MIGRATOR_TASK_UUID` (the task itself).
3. Redeploy the Supabase stack so the `migrator` sibling service comes up and `provision-supabase-stack.sh`'s `MINT_SECRETS` mints `MIGRATOR_DB_PASSWORD` (§6's credential bullet; §5).

**Phase B — supervised first bootstrap, `pfin_owner` by construction (rewritten 2026-09-16, ADR-072 [Amendment 5](../DECISIONS.md#adr-072) — §6.3 as `supabase_admin` runs the pre-step and creates `pfin_owner`; `migrator` runs the apply, entering `pfin_owner` per-file)**

4. **Pre-step, `supabase_admin`, interactive, minimal (§6.3):** run the `pfin_owner`/`055`/`116`/`118` role-creation files directly, then `GRANT pfin_owner TO migrator WITH INHERIT FALSE, SET TRUE` → the `auth`-only column-level grants → `ALTER DATABASE … OWNER TO pfin_owner` → `REVOKE CREATE ON SCHEMA pfin FROM migrator` (the engine backstop) → `\password migrator` → `ALTER ROLE migrator LOGIN` → **the `119` apply, pending Architect's G4 supplement (§6.3's TODO — do not run this step until that command lands)**. **If a prior apply already exists on this box, wipe first** (`drop schema pfin cascade; drop schema supabase_migrations cascade;`), behind the three measured gates §6.3 states (zero non-seed `pfin` rows, `auth.users = 0`, the outside-`pfin` enumeration empty — item 36). **Prepare all three passwords before starting — §6.0's Step 0.** **Depends on Architect's `feat/migrations-pfin-owner-sweep` (the `pfin_owner` migration file + the `001`–`118` paired `set role`/`reset role` sweep) being on `main` first — not yet landed.**
5. **The apply, `migrator`, from its own container, no `--db-url` override (§6.3):** `docker compose … exec -T migrator supabase db push --workdir /workspace`. Applies 001–118 in order, each file entering `pfin_owner` via the paired `set role pfin_owner; … reset role;` its own text now carries — including a second, tolerant pass over the role-creation files (report-don't-repair on the pre-existing roles, still hard-fails a real C8 violation) — creating every `pfin` object `pfin_owner`-owned and `supabase_migrations` `migrator`-owned from the first row (**item 32's manual `ALTER SCHEMA`/`ALTER TABLE … OWNER TO` statements are retired**, not carried forward). Then the §6.1 (`pfin_etl`) and §6.2 (`pfin_provider_sync`) worker-role handoffs, same two-step credential shape, same deploy pass, unchanged from before.
6. **Verify — the ownership census, not the read verb alone (§6.3):** `migrator`'s own attributes, its `pfin_owner` membership (NOINHERIT, SET TRUE, no ADMIN OPTION), database ownership = `pfin_owner`, the engine backstop (`migrator` holds no `CREATE` on `pfin`), no app-role membership, the worker-role memberships landed, **zero `postgres`- or `migrator`-owned `pfin` objects — every one `pfin_owner`** (the census query — this is the property the whole rewrite exists to establish), `supabase_migrations` owned by `migrator` with the full row count tracked **including exactly one row for `119`**, the four seed tables re-populated (`asset`=7, `posting_prototype_default`=30, `tax_character`=5, `taxonomy_default`=38), `rest` healthy. **The true write proof is Phase D's first real migration, watched** — and per Sec's ruling, the re-apply above already discharges item 32's write proof, the ownership property, and the from-scratch path in one pass; Phase D now proves the CI **transport**, not content, so its vehicle can be the smallest real `comment on` fixing a stale `pfin` comment, not a no-op.

**Phase C — the CI trigger, makes steady-state live (§6.4)**

7. Generate the `ci_only` keypair (§6.4 step 2).
8. Set the local `.env`: `CI_MIGRATE_SSH_PUBKEY` + `MIGRATOR_SERVICE_UUID` + `MIGRATOR_TASK_UUID` + `APP_UUID` (§6.4 step 3). **`.env` is the main checkout's; agent worktrees have their own and it is discarded when the worktree is removed** (2026-09-16 incident — see §6.0).
9. `scripts/provision-vps.sh --apply` (§6.4 step 4) — materializes the `ci-migrate` user, its forced-command key, the orchestration script, and the scoped Coolify token.
10. Add the GitHub Actions secret `CI_MIGRATE_SSH_PRIVATE_KEY` (§6.4 step 5).
11. Add the GitHub Actions repository variable `PROD_SSH_HOST` (§6.4 step 6).

**Phase D — integration test**

12. Merge a migration touching `supabase/migrations/**` and watch `.github/workflows/migrator-trigger.yml` fire end-to-end (§6's "steady-state" bullet; §6.4 step 7's verify). **With `DEPLOY_ON_SUCCESS=0` (the default), this proves migrate-then-NO-deploy, not the full steady-state**: expect the orchestration script's `"migration apply SUCCEEDED — app deploy SUPPRESSED (DEPLOY_ON_SUCCESS!=1)"` log line and a green (exit 0) job — the suppressed deploy is the PASS condition here, not a failure to chase down. The deploy leg is proven separately at §7 step 7.

---

### 6.6 Re-bootstrap execution plan — THIS box, concrete, 2026-09-16

**§6.3/§6.5 are the general procedure; this is the box-specific walkthrough for the one that already exists** (Amendment 5 Decision B: *"the from-scratch Phase B is the subject and this box's wipe is a footnote"*). Every command below is cited from §6.3, not restated — this section is the order a stranger runs them in, on this box, once.

**Step 0 — the item-36 gate, re-run live, not assumed from a prior record.** Before any `DROP`, re-measure all three gates as `supabase_admin`, read-only:

```sql
-- non-seed pfin rows -- expect zero everywhere except the four named seed tables
select 'asset', count(*) from pfin.asset union all
select 'posting_prototype_default', count(*) from pfin.posting_prototype_default union all
select 'tax_character', count(*) from pfin.tax_character union all
select 'taxonomy_default', count(*) from pfin.taxonomy_default;
-- every OTHER pfin table -- expect zero (enumerate at run time, don't assume the table list is unchanged)
select relname, (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from pfin.%I', relname), false, true, '')))[1]::text::int as n
  from pg_class where relnamespace = 'pfin'::regnamespace and relkind = 'r' order by 1;
-- auth.users -- expect zero
select count(*) from auth.users;
-- outside-pfin catalog census (schema-resident objects) -- expect zero postgres-owned rows outside pfin
select n.nspname, pg_get_userbyid(c.relowner), c.relkind, count(*) from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where pg_get_userbyid(c.relowner) = 'postgres' and n.nspname != 'pfin' and n.nspname !~ '^pg_toast'
  group by 1,2,3;
```

**If any row is non-zero: STOP and route to Sec** (Amendment 5 Decision A's own instruction — a hard gate, not a checklist item). The 2026-09-16 measurement (§6.3, cited above) found all three clean; re-measuring rather than trusting that record is the point of a gate.

**⚠ Do not proceed past Step 0 yet.** As of 2026-09-17, §6.3's apply block is a known dead end past migration `007` (vault disposition (iii) falsified, Architect re-ruling among (i)/(ii)/(iv) — see §6.3's TODO box) and the `119` apply-mechanism TODO is still open. A wipe followed by an apply that cannot complete leaves this box with neither its old state nor a working new one. Confirm both TODOs are closed in §6.3 before running Step 1.

**Step 1 — the wipe.** §6.3's `drop schema pfin cascade; drop schema supabase_migrations cascade;`, as `supabase_admin`. Roles and passwords survive; `auth`/`public`/`storage`/`vault`/`extensions` are untouched.

**Step 2 — the fresh Phase B run.** §6.5 steps 4–6, in order: the pre-step (role-creation files, grants, engine backstop, credential, the `119` TODO), then the `migrator`-run apply, then the ownership-census verify. **Do not skip the `119` TODO's placeholder check** — until Architect's exact command lands in §6.3, this step cannot complete; re-read §6.3 immediately before running this box's re-bootstrap in case the supplement has landed since this plan was last read.

**Step 3 — Phase D's suppressed fire.** §6.5 step 12, box-side pre-check per §6's Phase D preparation record (`DEPLOY_ON_SUCCESS=0` by default — expect the orchestration script's `"migration apply SUCCEEDED — app deploy SUPPRESSED"` line and exit 0). This box's vehicle is the smallest real `comment on` fixing a stale `pfin` comment (Sec's ruling, §6.5 step 6's own note) — not a no-op — once one is identified; not this PR's scope to name.

**Step 4 — the post-apply ownership assertion, as the box's own pass/fail.** Re-run §6.3's verify block query (7) in full:

```sql
select pg_get_userbyid(relowner), relkind, count(*) from pg_class c
  join pg_namespace n on n.oid = c.relnamespace where nspname = 'pfin' group by 1, 2 order by 1, 2;
select pg_get_userbyid(proowner), count(*) from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace where nspname = 'pfin' group by 1;
```

**Pass:** every row reads `pfin_owner`. **Fail:** any `postgres` or `migrator` row — stop before Phase C/D, do not hand-patch with a manual `ALTER … OWNER TO` (§6.3's own instruction: that is the emergency-transfer shape this design replaced). A stranger reading only this section has the full box-specific order; every command's *why* lives in §6.3.

---

## 7. Workers

Scope: deploy the background-worker containers. Per ARCH Lock 13, the V1 runtime is a **hybrid 3-container topology** on Coolify: (1) V1 web-app, (2) `pfin_back_etl` ETL, (3) Node PDF worker — plus the Phase-6/V1.5 cron + scheduled-poll additions.

- **`pfin_back_etl` (ETL)** — `workers/etl/`, Coolify **Base Directory** `workers/etl/`; Dockerfile [`workers/etl/Dockerfile`](../workers/etl/Dockerfile) (DevOps-owned). Python ETL (BLS CPI + FMP financials → Supabase). **Direct-Postgres** transport (`PFIN_DB_*`, login role **`pfin_etl`** — its OWN dedicated identity, *not* provider-sync's `authenticator`; writes AS `service_role` via `SET ROLE`) via **TenantBoundConnection** (Lock 13 mod #3). **`PFIN_DB_USER=pfin_etl`** (non-secret username) + `PFIN_DB_PASSWORD` (the `pfin_etl` credential, `production_only`). **This container cannot start successfully until §6's role-provisioning step has run** — see the ordering dependency there. **Forward discipline:** all `pfin` DB access binds `users_id` via TenantBoundConnection — TBC + `fence-tbc` coverage land Wave 6; incumbent currently uses SQLAlchemy `create_engine`.
  - **`PFIN_DB_SSLMODE=disable`** — non-secret, set explicitly in production (§5; Sec ruling, §7.36 item 26). The code default (`utils.py`, S11) is `require`, unchanged — this is the override, not a code change. Rationale in one sentence: plaintext is acceptable only because `db` is `expose:`-only per RT-32.
- **Node PDF worker** — `workers/pdf-render/`, Dockerfile [`workers/pdf-render/Dockerfile`](../workers/pdf-render/Dockerfile) (a real Puppeteer + system-Chromium render pipeline, **not** a placeholder — landed at SELF-348 A4, superseding the Phase-5 placeholder this line previously described). **Zero DB reach by design** (Lock 13 mod #2) — NO database libraries, credentials, or network reach. **Direction corrected in place:** this line previously said the worker "reaches data only via the web-app's `/internal/pdf-render` endpoint" — backwards. Per the R2 (C) ruling (`api/CLAUDE.md`; `workers/pdf-render/Dockerfile` + `docker-compose.yaml` headers), **`/internal/pdf-render` is RETIRED and does not exist as an app route.** The **web-app** composes and renders HTML server-side, then **PUSHES** the finished HTML to **this worker's own `/render` endpoint** under a short-lived, app-minted signed JWT (SD-20); the worker verifies the JWT and returns PDF bytes, never reaching the data layer itself. The worker's `/render` is the RT-27 internal-only admission surface (reachable only from `app` over the Coolify project network, `http://pdf-render:8080` — see §7.1 below); the app is the caller, never the reverse. RT-22 fence enforces the Dockerfile credential/Postgres-client absence.
  - **`PDF_WORKER_SIGNING_KEY` length precondition (A5 follow-up (3)) — verify BEFORE the worker's first deploy.** The web-app fails closed when `PDF_WORKER_SIGNING_KEY` is under 32 characters; the PDF worker itself enforces no minimum-length floor. That asymmetry means a short value is caught on the web-app side only — if the web-app container happens to start first, or if the two containers are ever given different values, the PDF worker can come up and accept requests under a key too weak for the web-app's own check to have allowed. Before the worker's first deploy: confirm the Coolify-injected `PDF_WORKER_SIGNING_KEY` value is **at least 32 characters**, and confirm it is the **SAME value on both the web-app and PDF worker containers** (per SD-20 — this is the shared-secret pair the signed-JWT handshake depends on).
- **`provider-sync` (Plaid/SimpleFIN ingest)** — `workers/provider-sync/`, Coolify **Base Directory** `workers/provider-sync/`; Dockerfile [`workers/provider-sync/Dockerfile`](../workers/provider-sync/Dockerfile) (DevOps-owned). The 4th Coolify unit (ADR-019 amendment) — the FIRST DB-touching **Node** worker. **Direct-Postgres** transport (`PFIN_DB_*`, login role `authenticator`, writes AS `service_role` via `SET LOCAL ROLE` per ADR-023) via **TenantBoundClient** (Lock 13 mod #3; `fence-tbc-node` enforces at PR-time). **OFF the RT-26 allowlist by design** — no `SUPABASE_SERVICE_ROLE_KEY`, no `@supabase/supabase-js`. Env contract: [`workers/provider-sync/.env.example`](../workers/provider-sync/.env.example).
  - **`PFIN_DB_SSLMODE=disable`** — set per Sec's ruling (§5; §7.36 item 26), same rationale as `pfin_back_etl`. **⚠ Measured to be currently INERT for this worker, flagged rather than silently set:** `TenantBoundClient.ts`'s `#connect()` (`workers/provider-sync/src/db/TenantBoundClient.ts:89-100`) builds its `postgres.js` connection from `host`/`port`/`database`/`username`/`password` only — no `ssl` option, and no code anywhere in this worker reads `PFIN_DB_SSLMODE` (`grep -rn "SSLMODE" workers/provider-sync/` → zero hits, confirmed against both `src/` and `.env.example`). **`postgres.js`'s own documented default, cited not assumed:** the package is pinned `^3.4.5` (`workers/provider-sync/package.json:19`); reading `src/index.js` at tag `v3.4.5`, the library's own `defaults` object sets `ssl: false` (line 449) when no `ssl` option is passed. So this worker does not merely happen to connect in plaintext today — `postgres.js` **explicitly defaults off**, a stronger and more deliberate property than libpq's `prefer` (which the earlier draft of this line incorrectly implied by omission — corrected here). Setting `PFIN_DB_SSLMODE` is harmless (an unused Coolify var) and keeps the two workers' env parity, but **it does not currently do anything** — unlike `pfin_back_etl`, there is no S11-shaped override mechanism here to point it at. Not fixed in this PR (out of scope; no code touched).
- **`provider-sync` SELF-212 admission endpoint (Option C, internal-only) — deploy config:**
  - **Build pack = Compose (b-i).** Coolify consumes the committed [`workers/provider-sync/docker-compose.yaml`](../workers/provider-sync/docker-compose.yaml) (not the bare Dockerfile build pack). This is what makes the admission endpoint's exposure surface **committed + lintable** (the `fence-admission-bind` CI job / RT-27 network-exposure layer). The admission port (`8081`) is `expose:`-only — **NEVER add a published `ports:` mapping and NEVER assign a Coolify Domain / Traefik `Host()` label to this service.**
  - **CA-4 — SAME Coolify project (hard prerequisite):** the api/ web-app service and the provider-sync service **MUST** live in the **same Coolify project** so internal DNS `http://provider-sync:8081` resolves (Coolify's internal network is per-project). Cross-project placement breaks internal reach **and** tempts a public-Domain "fix" — the exact silent-exposure regression RT-27 / §10 fences. Verified at §10 smoke.
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

**⚠ Build-pack correction against this section's own originating brief.** §3's topology table (already on `main`, unchanged by this PR) documents **all three workers as Coolify build pack = Compose**, not Dockerfile: `pdf-render` moved off the plain-Dockerfile pack at SELF-348 A4 item 4c / Sec N-4 (superseding what it shipped with at Phase 5), and `etl` has carried two Compose-defined Coolify units (nightly-ingest + monthly-report) since its own docker-compose header was authored. Only `app` stays on the plain Dockerfile+Base-Directory pack — it is the **one** fleet service still on it. The blocks below follow §3's table and the compose files actually on disk, not a Dockerfile-build-pack assumption for `etl`/`pdf-render` — flagged in the hand-off below as a correction, not silently reconciled.

---

**1. `app` — V1 web-app**

| Field | Value | Grounding |
|---|---|---|
| Base Directory | `api/` | §3 topology table |
| Build pack | Dockerfile — [`api/Dockerfile`](../api/Dockerfile) | §3 table; the one fleet service still on plain Dockerfile+Base-Directory |
| Container port | `3000` (`EXPOSE 3000`, `CMD ["node","build"]` — adapter-node default) | `api/Dockerfile` lines 35–36 |
| Domain | `pfindash.com` (+ `www.pfindash.com` alias) — the **only** public-Domain resource in the project | §2 "Subdomain split: app only"; §3 topology table |
| Domain assignment status | **Blocked on §2's DNS cutover** — not yet assignable | §3 "Status (2026-09-09)" line |
| Networking / CA-4 | **MUST** be created in the **same Coolify project** as `provider-sync` — `app`'s only internal-network dependency is reaching `http://provider-sync:8081` for the SELF-212 admission handshake | §7 provider-sync CA-4 bullet; §10 CA-2/CA-4 |
| Health check | No `/healthz`-shaped route exists under `api/src/routes/` (checked: none found). Until Backend adds one, configure Coolify's HTTP health check against `/` (root) — SvelteKit adapter-node answers 200 there once the app boots. **Flagged to Backend**, not invented here. | `find api/src/routes -iname '*health*'` → empty |
| Resource limits | No repo-side precedent exists for any container's CPU/mem ceiling. See "Resource limits — genuinely open" below rather than a per-container number here. | — |

**Env-var wiring (→ §5; values never re-enumerated here):**

- **Non-secret plain Coolify env** (NOT in `secrets-manifest.yml` — §5's non-secret runtime-config carve-out): `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY`.
- **Secrets** (`production_only`, injected by [`scripts/push-production-secrets.sh`](../scripts/push-production-secrets.sh)'s `SECRET_RESOURCE_MAP → app`): `SUPABASE_SERVICE_ROLE_KEY` (RT-26 §4.1 allowlist — `app` is the sole holder in the fleet), `PDF_WORKER_SIGNING_KEY` (SD-20 — **same value** as the PDF worker, ≥32 chars, verify before `pdf-render`'s first deploy per the existing PDF-worker bullet above), `WORKER_ADMISSION_SHARED_SECRET` (**same value** as `provider-sync` — §5's ratified deviation: pushed as an ordinary per-application env var to both, never a Coolify "shared variable"; rotation only via re-running the script, never a hand-edit to one side), `DISCORD_WEBHOOK_URL`.
- **Real JWT mint** — [`scripts/mint-supabase-jwt-keys.sh --apply --app-name <app-resource-name> --verify-live`](../scripts/mint-supabase-jwt-keys.sh) mints the stack's real `ANON_KEY`/`SERVICE_ROLE_KEY` (HS256, derived from the deployed `JWT_SECRET`) and, when `--app-name` resolves an existing `app` resource, propagates them onto `app` as `PUBLIC_SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` — the script's own step name is "overwriting the placeholders" (its line ~387), so it is built to run **after** any placeholder value is already in place, not before.
- ⚠ **Two writers of `SUPABASE_SERVICE_ROLE_KEY` on `app` — RULED (Sec joint-review, 2026-09-13).** `push-production-secrets.sh`'s `SECRET_RESOURCE_MAP` maps it `→ app` from the operator's local `.env`; `mint-supabase-jwt-keys.sh --apply --app-name` *also* overwrites it, unconditionally, with the real HS256 JWT derived from the deployed `JWT_SECRET`. **`mint-supabase-jwt-keys.sh` is authoritative** — the correct value is *derived* from the on-box `JWT_SECRET` and cannot be authoritatively sourced from a local `.env` (any value there is a placeholder or a hand-copied stale value). **Required ordering: run `push-production-secrets.sh` FIRST, `mint-supabase-jwt-keys.sh --apply --app-name` LAST** — because mint overwrites unconditionally, running it last guarantees the real key wins; the reverse order clobbers the real key with a `.env` value and the app comes up holding a wrong `service_role` key (fail-closed 403s on privileged ops, not an exposure — but a live-app break). **Durable fix (tracked separately, DevOps): drop `SUPABASE_SERVICE_ROLE_KEY` from `push-production-secrets.sh`'s `SECRET_RESOURCE_MAP`**, mirroring how that script already excludes the stack-side `SERVICE_ROLE_KEY`/`ANON_KEY` as mint-owned (`EXCLUDED_SUPABASE_STACK`) — the app-side name is the same mint-derived class and the exclusion was simply not extended to it. That removes the double-writer and the ordering hazard entirely.
- **A redeploy is required after either injection** — Coolify only applies env at container-recreate time (§5).

**§7 step 7 — flip the `DEPLOY_ON_SUCCESS` gate, then re-exercise the trigger once.** Once `app`'s first (manual) deploy above is confirmed healthy and the migrate-only leg of §6.5 Phase D step 12 has passed (the `DEPLOY_ON_SUCCESS=0` suppression line, green job): set `DEPLOY_ON_SUCCESS=1` in `.env`, re-run `BOX_IP=<box-ip> scripts/provision-vps.sh --apply` (idempotent — rewrites only `/etc/pfin/migrator-trigger.conf`), then **push a second no-op migration and watch the trigger fire again**, confirming the orchestration script's `api GET "/deploy?uuid=$APP_UUID"` call actually fires this time. ⚠ **Do not skip the re-exercise** — Sec's condition on this gate: the deploy leg must not ship unexercised; flipping the flag without a second live fire is a qualifier nobody checked.

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
| Networking / CA-4 | **MUST** be created in the **same Coolify project** as `app` — internal DNS `http://provider-sync:8081` is per-project only | compose file header; §7 CA-4 bullet; §10 CA-2 |
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

No CPU/memory ceiling for any Coolify service appears anywhere in this repo — this runbook, ARCH, or any script. CAX21 is 4 vCPU / 8 GB RAM total, shared across the self-hosted Supabase stack (multiple containers), Coolify's own 6 control-plane containers, the `migrator` sibling service, and all four units above — real contention risk on an 8 GB box that this section cannot resolve by assertion. **Flagged to F/CTO** (capacity/cost is an escalation item per DevOps's own remit, not a DevOps unilateral call) rather than shipping invented numbers. If a starting point is wanted before real usage is measured: `pdf-render` (headless Chromium) is the one unit worth ring-fencing first, since an unbounded worker there can starve the Supabase stack on the same box — measure actual RSS after first deploy and set ceilings from that, not from a guess.

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

- **CA-2 — admission-endpoint external-reachability NEGATIVE smoke (SELF-212 Option-C; ship-block; DevOps-owned deploy assertion):** post-deploy, empirically assert the provider-sync admission endpoint (`:8081`) is **NOT** reachable from outside the private Docker network. This is the empirical backstop the limb-(a) env-signal heuristic (§7 CA-1) is only a proxy for — it covers the Coolify FQDN-var non-update fail-open case CA-1's regex is meant to catch.
  - **NEGATIVE assertion (must FAIL to connect):** from a host *outside* the Coolify project network (e.g. the public internet / a non-project host), an HTTP request to any candidate public FQDN + the admission path must be **refused / unreachable / non-routable** — never a 2xx/4xx *from the admission app* (a 4xx from the app means it was reached). Test both (a) any assigned Coolify Domain for the service (there must be none) and (b) the raw host IP on `:8081` (must be closed — `expose:` does not host-publish).
  - **POSITIVE control (must SUCCEED):** from a sibling container *inside* the same Coolify project, `http://provider-sync:8081` health path returns 2xx — proves internal reach works (so the negative result above is "correctly private," not "app simply down").
  - **CA-4 same-project check:** the positive control passing IS the same-project-internal-DNS assertion — if `http://provider-sync:8081` does not resolve from the api/ container, api/ and provider-sync are not co-located in one project (fix before proceeding; do NOT "fix" by assigning a public Domain).
  - Wire this as a go/no-go gate item alongside the §9 teardown gate. QA owns the cross-tenant/RLS assertions; DevOps owns this infra-reachability assertion.

- **CA-7 — Supabase datastore external-reachability NEGATIVE smoke (§4 (1d); ship-block; DevOps-owned deploy assertion).** Same shape as CA-2 above, different subject: post-deploy, empirically assert `api-gw` and `supavisor` are **NOT** reachable from outside the private Docker network, now that both are `expose:`-only (§4 (1d) — the fix for the live 2026-09-10 incident where `supavisor` came up bound to `0.0.0.0:5432`/`0.0.0.0:6543`, caught only by probing, not by any error). This is §1's `nmap` baseline's load-bearing counterpart — §1 checks before anything exists to answer; this checks after the stack is actually up and Docker has programmed its own NAT rules, which is the only point where the assertion means anything.
  - **NEGATIVE assertion (must FAIL to connect):** from a host *outside* the Coolify project network, `nmap -Pn -p 5432,6543,8000 <box-ip>` — all three must read `filtered`/closed, exactly as §1's baseline did, now re-confirmed with the datastore actually running. Also confirm no Coolify Domain is assigned to either service.
  - **POSITIVE control (must SUCCEED) — this doubles as the CA-4-style same-Coolify-project prerequisite for §6, verify it BEFORE §6 runs, not after:** from a sibling container in the **same Coolify project** (the `app`/`workers/*` resources created at §6), `http://api-gw:8000` and the pooler's service name on `5432`/`6543` must resolve and respond. **If they don't resolve, `app` and the Supabase resource are not co-located in one Coolify project** — the CA-4 failure shape (§7's own precedent for `provider-sync` ↔ `app`) — **fix the project placement, do not "fix" it by assigning either Supabase service a public Domain.** `connect_to_docker_network` is not automatic and not project-scoped (§4 (1d)); confirm it is enabled on both sides as part of this check, not assumed from the services merely existing in the same project.
  - Wire alongside CA-2 as a go/no-go gate item before §9 teardown.

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
| 11 | ✅ DB TimeZone pin — **resolved**: this row was stale, claiming the pin migration "needs to be authored." `061_pin_database_timezone_utc.sql` already exists on `main` (verified at `8434d721`) — production's UTC is a declared pin, not an image default. §4.1's own deploy-time read-back still applies fresh **after §6's migrations run**, not at §4 stand-up time (§6 is a stub; running the read-back before migrations apply will show "No row" and should not be read as the pin missing) | Architect (authored) / DevOps (verifies at §6) | §4.1 / §10 |
| 10 | ✅ `ALTER ROLE … PASSWORD` plaintext handling — **resolved**: measured `log_statement = ddl` (exposure real, not theoretical); single-statement form prohibited, replaced by the `\password` + `ALTER ROLE … LOGIN` two-step (§6.1). Sec-ruled | DevOps + Sec | §6.1 |

> **STUB —** This runbook is a skeleton. Each `> **STUB —**` marker above is a fill-in point as Phase 6 reveals the operational detail. Do not treat any section as complete until its STUB marker is removed and (for §5 + fence-touching content) Sec joint-review has signed off.
