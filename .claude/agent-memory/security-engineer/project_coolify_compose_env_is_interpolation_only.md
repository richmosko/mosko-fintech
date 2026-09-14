---
name: coolify-compose-env-is-interpolation-only
description: ⚠ CONTESTED 2026-09-14 — a live measurement says the migrator container holds EVERY stack secret; the source read below says otherwise. Do not cite this as settled.
metadata:
  type: project
---

> ⚠⚠ **CONTESTED AS OF 2026-09-14 — DO NOT CITE AS SETTLED.** DevOps measured the running `migrator` container holding real values for
> `JWT_SECRET` / `SERVICE_ROLE_KEY` / `POSTGRES_PASSWORD` / `VAULT_ENC_KEY` / `ANON_KEY` / `SECRET_KEY_BASE`, although its compose block declares only
> `PROD_DB_URL`. I re-read Coolify v4.3.18 `parseDockerComposeFile` and it still reads only each service's own declared `environment:` — so the SOURCE and the
> LIVE STATE disagree. **The discriminating measurement is `docker inspect` `.Config.Env` NAMES on the container** (authoritative container env) versus
> `docker compose exec … env` (which can carry the exec path's own environment). Pending that, treat confinement-by-non-reference as UNPROVEN.
>
> **⚠ THE DURABLE LESSON, WHICH HOLDS WHICHEVER WAY IT RESOLVES: this memory recorded a claim about LIVE CONTAINER STATE on the strength of a SOURCE READ.**
> A parser's code is evidence about the parser, not about what is in a running container — an `env_file:` injected downstream, a different compose file than
> the repo's (check `com.docker.compose.project.config_files`), or any post-parse step defeats it. I then carried "C7 confinement HOLDS" into THREE PR
> verdicts (#752, #755, #756) off this one inference, never once measuring the container. **When a confinement claim is load-bearing, measure the artifact the
> claim is ABOUT.** And when an amendment asserts a refactor "PRESERVES" a property, that assertion must be measured on the REFACTORED artifact —
> ADR-072 Amendment 1 moved the migrator into the shared-store stack and declared confinement preserved, and that move is the candidate mechanism for its loss.

Coolify deploys a docker-compose application by shelling to **plain `docker compose --project-name {uuid} --project-directory {workdir} -f ...`** (source-verified: `ApplicationDeploymentJob.php:791-793`, cited verbatim in `infra/supabase/docker-compose.yml` header point 3). Therefore **stock Compose interpolation-only semantics govern**: an app-level (shared env store) variable enters a container **only if that service's own `environment:`/`env_file:` names it**. Coolify does NOT blanket-inject the whole store into every service container.

**Confinement mechanism is by NON-REFERENCE, not by per-service scoping.** A secret placed in the Supabase-stack shared store is confined to service X iff only X's block references `${SECRET}`. Verified 2026-09-12 for MIGRATOR_DB_PASSWORD (PR #741): referenced only inside migrator's `PROD_DB_URL`; no sibling (db/auth/rest/supavisor/meta/studio) references it, so none receive it. Corroborating tell: every service needing POSTGRES_PASSWORD re-declares it explicitly — pointless under blanket injection.

**Two provisioning paths, do not conflate (ADR-072 C7):**
- `scripts/push-production-secrets.sh` — `SECRET_RESOURCE_MAP` targets **standalone Coolify applications** (etl / pdf-render / provider-sync).
- `scripts/provision-supabase-stack.sh` — `MINT_SECRETS` (mint-if-absent) + `NONSECRET_DEFAULTS`, for **sibling services inside the Supabase-stack compose** (one Coolify app UUID, one shared env store): db/auth/rest/supavisor/meta/studio/**migrator**.

Picking the wrong path is a real error: the working proposal assumed migrator rode push-production-secrets.sh; it's a stack sibling, so it mints via provision-supabase-stack.sh. The confinement PROPERTY still held (interpolation-only), so it was a text amendment, not a veto — see [[feedback_read_the_whole_cell_before_diagnosing_doc_drift]].

**Residual NOT closed by this:** whether Coolify's dashboard/API displays the full app-level store to anyone with Coolify access — that's operator/dashboard-visibility exposure, a DIFFERENT class from "lands in a sibling container," and already covered by the standing "box-root / Coolify access is game-over" posture note.

**Why:** PR #741 (migrator chunk 1) diverged from ADR-072 C7's written provisioning path; the C7 verdict turned entirely on this injection semantics.
**How to apply:** For any "is secret S confined to service X" question on a Coolify compose app, grep the compose for `${S}` across ALL service blocks — presence in X's block ONLY = confined; presence elsewhere = leaked. The name-set `check-secrets-nonoverlap.py` fence does NOT observe this (it stops at the fields it parses) — see [[feedback_a_manifest_fence_stops_at_the_fields_it_parses]].
