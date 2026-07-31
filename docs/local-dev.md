# Local development runbook

**Status:** Phase 6 (Build Loop). There is **no deployed/hosted dev site** — V1 is greenfield and deploys at Phase 7 (see [`deployment-runbook.md`](deployment-runbook.md)). Everything below runs on your machine. The incumbent `pfindash.com` / Hetzner cax21 box is **reference-only**, never a dependency (ADR-021).

This is the hand-assembled local run (there is no `Makefile`/`justfile` yet). The authoritative "where each secret goes" is always the committed `.env.example` files + [`secrets-manifest.yml`](../secrets-manifest.yml); this doc is the operator walkthrough on top of them.

---

## Prerequisites

- **Supabase CLI** (`supabase`) + a container runtime (Docker/OrbStack) — runs the full local stack.
- **Node** (per `api/` + `workers/provider-sync/` `package.json` engines) + `npm`.
- A **Plaid** dashboard account (sandbox keys) and/or a **SimpleFIN Bridge** setup token — for provider connections (optional to just browse the app).

---

## First run (do this once)

```bash
# 1) Local Supabase stack — run from the repo root (discovers supabase/config.toml)
supabase start

# 2) Apply all migrations (001 → latest) + the seed
supabase db reset
#    (supabase test db  → runs the pgTAP RLS battery, optional)

# 3) Create api/.env (gitignored) with your LOCAL stack values.
#    Get the anon key from the running stack:
supabase status -o env | grep ANON_KEY
#    Then create api/.env with exactly these three (non-secret) vars:
#      PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
#      PUBLIC_SUPABASE_ANON_KEY=<the ANON_KEY value from above — the local publishable key>
#      PLAID_ENV=sandbox
#    (Do NOT put any Plaid/SimpleFIN secret here — those go in the worker .env; see below.)

# 4) The web app (SvelteKit, in api/)
cd api && npm run dev          # http://localhost:5173  (Vite dev)
#    …or, to exercise auth flows end-to-end (see the :3000 note below):
#    npm run build && node build   # http://localhost:3000  (matches site_url)
```

**Then in the browser:** `localhost:5173` redirects to **`/login`** when you're not signed in — **sign up** there (email confirmation is off locally, so it just works), and you're in (empty/connect state until you add accounts). Day-to-day after the first run, you just need the stack up (`supabase start`) + `npm run dev`.

### Local services & ports (`supabase/config.toml`)

| Service | URL / port |
|---|---|
| API gateway (PostgREST / GoTrue under `/auth/v1`) | `http://127.0.0.1:54321` |
| Postgres | `127.0.0.1:54322` (db name `postgres`) |
| Studio (DB UI) | `http://127.0.0.1:54323` |
| **Inbucket (local email inbox)** | `http://127.0.0.1:54324` |
| Web app — Vite dev | `http://localhost:5173` |
| Web app — built (`node build`) / `site_url` | `http://127.0.0.1:3000` |

### ⚠️ The `:5173` vs `:3000` gotcha (auth flows)

GoTrue's `site_url` is `http://127.0.0.1:3000`, so **auth redirects — email confirmation and password-reset links — target `:3000`, not the `:5173` dev server.** Plain login works on `:5173` (`enable_confirmations = false` locally), but to test the **password-reset / recovery flow**, run the **built** app on `:3000` (`npm run build && node build`). All local auth email lands in **Inbucket** (`http://127.0.0.1:54324`) — that's where the reset link shows up.

---

## Provider-sync worker (Plaid / SimpleFIN)

The provider sync is a **separate Node package** (`workers/provider-sync/`), not part of the web-app dev server. Three CLI entrypoints:

```bash
cd workers/provider-sync

npm run serve-admission   # internal HTTP endpoint the app calls for link-token mint /
                          # public-token exchange / SimpleFIN claim (binds :8081;
                          # requires ADMISSION_PRIVATE_ONLY=true, else fails closed)

npm run poll              # one sync pass over active linked accounts (the daily-cron entrypoint)

npm run admit -- --owner <your-user-uuid>   # dev shortcut: admit a Plaid *sandbox* Item
                                            # directly (hard-refuses anything but sandbox)
```

**Local DB override:** the worker's `.env.example` DB defaults are *production-container* values (`PFIN_DB_HOST=localhost`, `PFIN_DB_PORT=5432`, `PFIN_DB_NAME=pfin`). Point them at your local Supabase Postgres instead — host `127.0.0.1`, port `54322`, db `postgres`. `config/env.ts` validates these at boot and throws on any missing required key.

---

## Environment / keys

Secrets **never** go in the repo — every `.env` is gitignored; real values are yours locally and Coolify-injected in prod. Create each `.env` from its committed `.env.example` template. The credential split is deliberate: **the worker holds the Plaid secret; the `api/` relay is credential-less.**

| File | Copy from | Holds |
|---|---|---|
| `api/.env` | `api/.env.example` | **non-secret only** — `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY`, `PLAID_ENV` |
| `workers/provider-sync/.env` | `workers/provider-sync/.env.example` | Plaid client_id/secret, SimpleFIN token, `PFIN_DB_*`, admission secret |
| `workers/etl/.env` | `workers/etl/.env.example` | Plaid creds (ETL poll) + BLS/FMP |
| root `.env` | `.env.example` | web-app container secret-surface contract (`WORKER_ADMISSION_SHARED_SECRET`, …) |

### Plaid

Put your Plaid creds in **`workers/provider-sync/.env`** (from your Plaid dashboard, **sandbox** keys):

```
PLAID_ENV=sandbox          # leave as sandbox for local (production tier is F/CTO-gated)
PLAID_CLIENT_ID=…
PLAID_SECRET=…
```

- In **`api/.env`** set only `PLAID_ENV=sandbox` (it drives the browser CSP `connect-src` host). **Do not** put the Plaid secret in `api/.env` — that file is public-vars only; the relay never reads a Plaid secret.
- Mirror the two Plaid vars into `workers/etl/.env` too if you run the ETL poll.
- There is **no `PLAID_WEBHOOK_SECRET`** — Plaid v27 webhook verification is asymmetric ES256/JWK; the worker fetches Plaid's public key at verify time. (The `PLAID_SANDBOX_*` names in `secrets-manifest.yml` are CI-only QA fixtures — not what you set locally; sandbox-vs-production is the `PLAID_ENV` value.)

### SimpleFIN

SimpleFIN uses a **setup-token → Access-URL** model (not a client-id/secret). Two ways to supply it:

1. **Bootstrap via env** — `SIMPLEFIN_TOKEN=<your Bridge setup token/URL>` in `workers/provider-sync/.env` (optional; `z.string().optional()`).
2. **The real per-user flow (recommended)** — run the app + `serve-admission`, then connect in-app: `POST /api/simplefin/connect` with a setup token obtained from a **SimpleFIN Bridge**. The worker claims it, vaults the long-lived Access URL (ciphertext in `vault.secrets`; `linked_source` holds only a UUID handle), and the daily `poll` reads the vaulted credential — not `SIMPLEFIN_TOKEN`.

### Shared secret & DB

Set **`WORKER_ADMISSION_SHARED_SECRET`** to the *same* value in root `.env` and `workers/provider-sync/.env` (`openssl rand -hex 32`) so the app↔worker admission handshake works. Point the worker's `PFIN_DB_*` at your local Supabase Postgres (above).

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| **`:5173` → "500 Internal Error"** | Most often **`api/.env` is missing or empty** → the server-side Supabase client can't init on load. Create it (First-run step 3). If you created it *after* starting the dev server, **restart `npm run dev`** — Vite only reads `.env` at startup. Also confirm the stack is up (`supabase status`) and migrations are applied (`supabase db reset`). |
| **`:3000` → "This site can't be reached"** | Expected — nothing runs there unless you `npm run build && node build`. You only need `:3000` for auth-email flows (below). |
| **Password-reset / signup-confirm link goes to a dead `:3000`** | The `:5173`/`:3000` gotcha — GoTrue's `site_url` is `:3000`. Run the built app on `:3000` to complete those flows; the email itself is in Inbucket (`:54324`). |
| **Worker throws on boot** (`config/env.ts`) | A required var is missing/empty — check `workers/provider-sync/.env`, and point `PFIN_DB_*` at the local Postgres (`127.0.0.1:54322`, db `postgres`), not the production defaults. |

## Notes

- **Secrets discipline:** never commit a `.env`; never paste real keys into `api/.env` (public-vars file). See [`secrets-manifest.yml`](../secrets-manifest.yml) for the CI/production non-overlap ledger.
- **Email:** all local auth mail → Inbucket (`:54324`). Prod email delivery is deploy-gated on Auth-1 SMTP (Resend).
- This runbook is best-effort until the deploy runbook (Phase 7) fills in; corrections welcome as the local flow evolves.
