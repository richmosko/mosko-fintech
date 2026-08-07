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

Consequence for anyone hardening this: **pinning or inspecting `authenticated` protects nothing.** The login roles are `authenticator` (Data API / web app) and `pfin_etl` (`workers/etl`, direct psycopg login). And a read-back executed as `postgres` — which is how `pg_prove` and a plain `psql` connect — observes **`postgres`'s** login-time settings, so it will read a clean `UTC | database` while every PostgREST request runs in another zone. **Inspect the catalog, or connect as the login role; do not infer from a `postgres` session.**

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
  - `ci_only` (4 names — reserved distinct names; no production reach): `PLAID_SANDBOX_CLIENT_ID`, `PLAID_SANDBOX_SECRET`, `PDF_WORKER_SIGNING_KEY_TEST`, `SIMPLEFIN_TOKEN_TEST`.
  - `production_only` (11 names — Coolify-injected on the box; never in CI): `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `PDF_WORKER_SIGNING_KEY`, `PLAID_CLIENT_ID`, `PLAID_SECRET`, `SIMPLEFIN_TOKEN`, `WORKER_ADMISSION_SHARED_SECRET`, `DISCORD_WEBHOOK_URL`, `PFIN_DB_PASSWORD`, `FMP_API_KEY`, `BLS_API_KEY`.
  - **Counts are load-bearing — check them, don't skim them.** The two lists above are a **hand-maintained mirror** of [`secrets-manifest.yml`](../secrets-manifest.yml); nothing enforces that they stay in sync, so they drift silently. The failure mode is asymmetric and unpleasant: a secret missing *here* isn't a fence breach (the non-overlap fence still passes — it reads the manifest, not this file), it's a **container that deploys without a secret it needs**. So: the `secrets-nonoverlap` job prints `N ci_only + M production_only` on every PR + push. If those numbers disagree with the `(4 names)` / `(11 names)` above, this enumeration has drifted — **the manifest is source of truth; fix this list.** Comparing two integers CI already emits is the cheap check; diffing two prose lists by eye is the one that fails. *(This is not hypothetical: both halves of the `SIMPLEFIN_TOKEN` / `SIMPLEFIN_TOKEN_TEST` pair were missing here and went unnoticed until SELF-214 — with the fence green throughout.)*
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

> **⚠ Open flag (#10) — secret-in-statement handling, Sec-review before this section locks.** The `ALTER ROLE … PASSWORD '<literal>'` above carries the plaintext credential in a SQL statement. Two exposure paths to close deliberately rather than by habit: **(a) shell history** — run it inside an interactive `psql` session, never as a `psql -c '<statement>'` shell argument; **(b) server logs** — a database configured with `log_statement = 'ddl'` or `'all'` would capture the statement text. I have **not** verified what the self-hosted Supabase stack sets, or whether it redacts; do not assume it does. Mitigations to weigh with Sec: confirm/disable statement logging for the duration of this one statement, or pass a **pre-computed SCRAM-SHA-256 verifier** instead of a plaintext literal (Postgres accepts a verifier string in the same syntax, so no plaintext ever reaches the server). Resolve before §5/§6.1 lock.

> **STUB —** Fill in: the apply mechanism against self-hosted Supabase (`supabase db push` / `supabase migration up` vs. a CI/Coolify-driven apply), the idempotency/ordering guarantees, and how to verify each migration landed (e.g., RLS policies present, `fn_mask_acct_number` callable). Keep the migration list current as Phase 6 adds tables.

---

## 7. Workers

Scope: deploy the background-worker containers. Per ARCH Lock 13, the V1 runtime is a **hybrid 3-container topology** on Coolify: (1) V1 web-app, (2) `pfin_back_etl` ETL, (3) Node PDF worker — plus the Phase-6/V1.5 cron + scheduled-poll additions.

- **`pfin_back_etl` (ETL)** — `workers/etl/`, Coolify **Base Directory** `workers/etl/`; Dockerfile [`workers/etl/Dockerfile`](../workers/etl/Dockerfile) (DevOps-owned). Python ETL (BLS CPI + FMP financials → Supabase). **Direct-Postgres** transport (`PFIN_DB_*`, login role **`pfin_etl`** — its OWN dedicated identity, *not* provider-sync's `authenticator`; writes AS `service_role` via `SET ROLE`) via **TenantBoundConnection** (Lock 13 mod #3). **`PFIN_DB_USER=pfin_etl`** (non-secret username) + `PFIN_DB_PASSWORD` (the `pfin_etl` credential, `production_only`). **This container cannot start successfully until §6's role-provisioning step has run** — see the ordering dependency there. **Forward discipline:** all `pfin` DB access binds `users_id` via TenantBoundConnection — TBC + `fence-tbc` coverage land Wave 6; incumbent currently uses SQLAlchemy `create_engine`.
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
  - **Run it as each LOGIN role (`authenticator`, `pfin_etl`) — never as `postgres` — and add the catalog sweep.** MEASURED (§4.1): per-role settings apply at login and `SET ROLE` does not re-apply them, so `ALTER ROLE authenticator SET TimeZone` moves every Data API request while a `postgres` session still reads `UTC | database`. A read-back that connects as `postgres` **structurally cannot see the one role-level vector that exists.** Pinning or inspecting `authenticated` protects nothing — it is not the login role.
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
