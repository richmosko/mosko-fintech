# Self-hosted Supabase — trimmed stand-up compose

Coolify Compose resource for the V1 data layer, per [`docs/deployment-runbook.md`](../../docs/deployment-runbook.md) §4. Owned by DevOps.

## Provenance

Derived from Supabase's own reference self-hosting compose — **not committed verbatim**, per §4's own guidance (upstream's service set and image tags move; a stale snapshot silently drifts). This trim was produced fresh from a live fetch:

- Source: `https://raw.githubusercontent.com/supabase/supabase/master/docker/docker-compose.yml`
- Read: 2026-09-10 07:22 UTC
- Pinned to upstream commit: `8c7a4d9dbbaf8b552893822e89d7bf06f33f9220` ("chore(self-hosted): update 2026-09-09 - 0.8.1 (#50172)")

Every file under `volumes/` here was vendored from that same commit (`docker/volumes/...` in the upstream repo) so the compose, its Envoy config, and its DB init scripts all come from one consistent snapshot rather than being mixed across reads taken at different times.

**Re-pulling later:** fetch the current reference compose + its `volumes/` tree fresh, re-apply the two changes below and the service trim, and update this file's recorded source commit. Do not hand-patch an old vendored copy against a new upstream diff.

## Coolify resource settings — required exactly as stated

- **Base Directory:** `/infra/supabase`
- **Docker Compose Location:** `/docker-compose.yml`

**⚠ Not `base_directory: /` with `docker_compose_location: /infra/supabase/docker-compose.yml`** — that looks equivalent and is not. See point 3 below.

## Service trim (§4)

**IN:** `db`, `auth`, `rest`, `api-gw` (the gateway — upstream renamed this from `kong` to `api-gw`/Envoy; see `docker-compose.yml`'s header comment), `supavisor`.

**OUT:** `studio`, `meta`, `storage`, `imgproxy`, `realtime`, `analytics`, `vector`, `functions`. None of the kept services retain a `depends_on`, healthcheck, volume, or env var pointing at a dropped one — checked explicitly, not inferred.

## Four changes from the corresponding upstream service blocks

1. **`api-gw`'s `depends_on: studio` removed.** Upstream's gateway waits on `studio` being healthy before starting. `studio` is OUT of this trim; left in place, `docker compose up` hard-errors on the undefined service reference and the gateway never starts.

2. **`auth`'s `GOTRUE_DISABLE_SIGNUP` is hardcoded `"true"`**, not read from a `${DISABLE_SIGNUP}` Coolify env var. §4 step 5a (F/CTO Q5) makes signup-disabled a **standing gate** — it stays off through the full V1.final soak until the Plaid Link-token operator allowlist ships (`BACKLOG.md` §7.36 item 1) — not an operator-tunable value. The env-var form was also a live defect in §4 as originally written: the runbook instructed setting a Coolify variable named `GOTRUE_DISABLE_SIGNUP`, but the compose interpolates `${DISABLE_SIGNUP}`; followed literally, the mismatch resolves empty and signup stays **enabled** — the exact inverse of the Q5 ruling. Hardcoding closes this by construction: lifting the gate later requires an edit to this file (and a PR), which is the correct friction for a one-way-door control.

3. **Relative bind-mount sources are left compose-file-relative (`./volumes/...`), matching upstream — on condition that this resource's `base_directory` is `/infra/supabase`, not `/`.** Source-verified in Coolify's own deploy code (`ApplicationDeploymentJob.php:791-793`): the deploy job runs `docker compose --project-name {uuid} --project-directory {workdir} -f {workdir}{docker_compose_location} ...`, where `workdir` is the checkout root **adjusted by `base_directory`** — and Compose resolves every relative bind mount against `--project-directory`, not against the compose file's own location. With `base_directory` left at the repo root, `workdir` is the checkout root, and every `./volumes/...` mount would resolve to `<checkout-root>/volumes/...`, which does not exist. **⚠ The failure mode is silent**: Docker does not error on a missing bind-mount source — it auto-creates it as an **empty directory**. The stack reports "healthy" while `db` has no init scripts at all and `api-gw` has an empty `/etc/envoy`. Setting `base_directory: /infra/supabase` makes `workdir` equal to this directory, so `./volumes/...` resolves correctly.

   **Verify at first deploy anyway** — a healthy status cannot distinguish this from success. Check the gateway container's own log for a real config load (not just "container running"), and check the `db` container's boot log for each init-script filename actually executing. See §4's verification step.

4. **`db`'s data directory is a named volume (`db-data`), not upstream's relative bind mount (`./volumes/db/data`).** Independent of point 3's path-resolution question: a bind mount under the application's git checkout is not guaranteed to survive a redeploy (the checkout can be cleared/re-cloned — corroborated by multiple Coolify sources: "if you use a bind mount with a path that gets cleared during deploy instead of a named volume, you'll lose data"), whereas a named volume is managed by Docker/Coolify directly and does survive. Upstream's own compose is written for a manually-run, never-re-cloned checkout, where this distinction doesn't matter — it does here. This change is correct regardless of how point 3 resolves.

## Vendored support files — deliberately unmodified, all seven/four

The compose file alone does not stand up `api-gw` or `db`; both mount static config that isn't inline in the compose:

- `volumes/api/envoy/{envoy.yaml,cds.yaml,lds.template.yaml,docker-entrypoint.sh}` — Envoy's routing/filter config.
- `volumes/db/{realtime.sql,webhooks.sql,roles.sql,jwt.sql,_supabase.sql,logs.sql,pooler.sql}` — Postgres init scripts, run once against the empty data directory.
- `volumes/pooler/pooler.exs` — supavisor's pooler config.

**All of these are vendored unmodified, deliberately, even the ones (`realtime.sql`, `_supabase.sql`, `logs.sql`) that provision schema/data for services this trim drops.** The asymmetry: an init script that sets up a schema for an absent service costs nothing at runtime; a dropped one that a *kept* service actually needs breaks the stack in a way that's awkward to diagnose after the fact (a missing role, a missing schema, discovered only when `auth` or `rest` fails to connect). `roles.sql` and `jwt.sql` are confirmed load-bearing regardless of trim — they set passwords Postgres's own baked-in roles need and seed the JWT secret GUCs `auth`/`rest` read. Whether the other three are safe to drop is a **separate, unresolved question with its own blast radius** — not decided here, and not blocking this PR.

## Known gap, flagged, not resolved

**`SMTP_PASS`** sits in the `auth` service's environment block, syntactically identical to non-secret config like `SMTP_SENDER_NAME` — but it's a real credential. It's intentionally **left unset** in this pass: SMTP/email is not required to bring the stack up, and V1's email-confirmation flow is a later concern. Needs a `secrets-manifest.yml` decision before it's wired up — routed to Sec separately, not carried in this PR.

## What this file does NOT cover

- Minting the five secrets §4 names (`ANON_KEY`, `SERVICE_ROLE_KEY`, `POSTGRES_PASSWORD`, `PFIN_DB_USER`, `PFIN_DB_PASSWORD`) and injecting them into Coolify env — §5 (stub) + the live Sec-ruled boundary on which service gets which value.
- Applying migrations (§6) or the `pfin_etl`/`pfin_provider_sync` credential handoffs (§6.1/§6.2).
- Anything DNS/TLS/cutover-related (§2/§9).
