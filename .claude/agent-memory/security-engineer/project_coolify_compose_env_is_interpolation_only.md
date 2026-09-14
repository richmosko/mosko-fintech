---
name: coolify-compose-env-is-interpolation-only
description: Coolify deploys multi-service compose via plain `docker compose`, so shared-store env is interpolation-only — a secret confines by NON-REFERENCE, not by per-service scoping
metadata:
  type: project
---

Coolify deploys a docker-compose application by shelling to **plain `docker compose --project-name {uuid} --project-directory {workdir} -f ...`** (source-verified: `ApplicationDeploymentJob.php:791-793`, cited verbatim in `infra/supabase/docker-compose.yml` header point 3). Therefore **stock Compose interpolation-only semantics govern**: an app-level (shared env store) variable enters a container **only if that service's own `environment:`/`env_file:` names it**. Coolify does NOT blanket-inject the whole store into every service container.

**Confinement mechanism is by NON-REFERENCE, not by per-service scoping.** A secret placed in the Supabase-stack shared store is confined to service X iff only X's block references `${SECRET}`. Verified 2026-09-12 for MIGRATOR_DB_PASSWORD (PR #741): referenced only inside migrator's `PROD_DB_URL`; no sibling (db/auth/rest/supavisor/meta/studio) references it, so none receive it. Corroborating tell: every service needing POSTGRES_PASSWORD re-declares it explicitly — pointless under blanket injection.

**Two provisioning paths, do not conflate (ADR-072 C7):**
- `scripts/push-production-secrets.sh` — `SECRET_RESOURCE_MAP` targets **standalone Coolify applications** (etl / pdf-render / provider-sync).
- `scripts/provision-supabase-stack.sh` — `MINT_SECRETS` (mint-if-absent) + `NONSECRET_DEFAULTS`, for **sibling services inside the Supabase-stack compose** (one Coolify app UUID, one shared env store): db/auth/rest/supavisor/meta/studio/**migrator**.

Picking the wrong path is a real error: the working proposal assumed migrator rode push-production-secrets.sh; it's a stack sibling, so it mints via provision-supabase-stack.sh. The confinement PROPERTY still held (interpolation-only), so it was a text amendment, not a veto — see [[feedback_read_the_whole_cell_before_diagnosing_doc_drift]].

**Residual NOT closed by this:** whether Coolify's dashboard/API displays the full app-level store to anyone with Coolify access — that's operator/dashboard-visibility exposure, a DIFFERENT class from "lands in a sibling container," and already covered by the standing "box-root / Coolify access is game-over" posture note.

**Why:** PR #741 (migrator chunk 1) diverged from ADR-072 C7's written provisioning path; the C7 verdict turned entirely on this injection semantics.
**How to apply:** For any "is secret S confined to service X" question on a Coolify compose app, grep the compose for `${S}` across ALL service blocks — presence in X's block ONLY = confined; presence elsewhere = leaked. The name-set `check-secrets-nonoverlap.py` fence does NOT observe this (it stops at the fields it parses) — see [[feedback_a_manifest_fence_stops_at_the_fields_it_parses]].
