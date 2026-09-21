# Coolify API — measured facts

Durable, tracked record of every Coolify API fact this repo's scripts have
measured against the production box, per team-lead's instruction (PR #866
review, 2026-09-21) after the same fact (`fqdn` PATCH 422) had to be
re-measured because it existed only in a script comment nobody cross-
referenced.

**Conventions, every entry:**
- **Date** the measurement was taken.
- **Coolify version** running on the box at that time.
- **Box** — which host (there is one production box; stated for when that
  stops being true).
- **Build pack** of the application/resource the measurement was taken
  against (`dockercompose` vs `dockerfile` behave differently for several
  of these — never generalize across build packs without a fresh
  measurement).
- **Exact request** — method, path, and the literal request body.
- **Result** — literal response (status code + body text where available).
- **NOT measured** — stated explicitly, every entry. A fact with nothing
  in this line has not been checked for edge cases; say so rather than
  leaving it implicit.
- **Cite this file by anchor** (`COOLIFY-FACT-NN`) from script comments —
  never restate the fact's own prose in a second place; a fact restated
  in two places is a fact that can drift in one of them unnoticed (see
  COOLIFY-FACT-05's own history below).

---

## COOLIFY-FACT-01 — `GET /applications?name=X` ignores the `name` query parameter

- **Date:** 2026-09-20 (team-lead)
- **Coolify version:** 4.3.18
- **Box:** production (cax21)
- **Build pack:** N/A (list endpoint, not resource-specific)
- **Exact request:** `GET /applications?name=etl`, `?name=app`, `?name=pfin-app`, `?name=does-not-exist`
- **Result:** all four returned the SAME unfiltered 3-element application list — the query parameter had no filtering effect whatsoever.
- **Fix landed:** every resolver in this repo fetches the full `/applications` list unfiltered and matches by name LOCALLY (Python list comprehension), never trusting a `?name=` query string. See `scripts/push-production-secrets.sh`'s own resolution-step header for the fuller narrative.
- **NOT measured:** whether any OTHER Coolify list endpoint (`/projects`, `/servers`, `/databases`, …) has the same defect — assume it does until measured, since this repo's own resolvers already treat every by-name lookup as unfiltered-fetch-then-local-match on principle, not per-endpoint verification.

---

## COOLIFY-FACT-02 — `project_uuid` is required on `POST /applications/public`

- **Date:** 2026-09-20 (team-lead)
- **Coolify version:** 4.3.18
- **Box:** production (cax21)
- **Build pack:** N/A (create endpoint)
- **Exact request:** `POST /applications/public` with `project_uuid` omitted from the body.
- **Result:** HTTP 422, body `{"project_uuid":["This field is required."]}`.
- **Corrects:** an earlier in-repo comment (since removed) that claimed "Coolify's create endpoint accepts `environment_uuid` alone alongside `server_uuid`" — that claim was false; both `project_uuid` and `environment_uuid` must be resolved and sent.
- **NOT measured:** whether `project_uuid` alone (with `environment_uuid` omitted) is also required-and-422s the same way — assume yes (this repo's own scripts always resolve and send both) but not independently confirmed.

---

## COOLIFY-FACT-03 — compose-parse creates EMPTY placeholder env rows for plain `${VAR}` interpolation

- **Date:** 2026-09-21 (Sec, run-6 stop)
- **Coolify version:** 4.3.18
- **Box:** production (cax21)
- **Build pack:** `dockercompose`
- **Trigger:** a compose file interpolating a name in PLAIN `${NAME}` form (e.g. `${PFIN_DB_PASSWORD}` at `workers/etl/docker-compose.yaml:97` and `workers/provider-sync/docker-compose.yaml:124`).
- **Result:** Coolify's own compose-parse creates an env-store row for `NAME` with an EMPTY value at parse time — the row EXISTS before any script ever writes to it. This is a create-if-absent side effect of parsing, not a reset-on-every-parse.
- **First recorded in-tree here** — this fact previously existed only in cross-session agent memory (not a tracked file); this entry is its first landing in the repo itself.
- **Consequence for every script that checks "does this env name already have a value":** row-count ≥ 1 is NOT the same fact as "the value is non-empty" — store-presence must be checked as (one row AND non-empty value), never row-count alone. See `scripts/db-role-handoff.sh` and sibling scripts for where this distinction is load-bearing.
- **NOT measured:** whether the SAME placeholder-row behavior applies to `${VAR:-default}` or `${VAR:?err}` interpolation forms, or only the bare `${VAR}` form measured here.

---

## COOLIFY-FACT-04 — default `fqdn` + `ports_exposes` assigned at create

- **Date:** 2026-09-19 (run-8, `realrun8.clean.log`, team-lead)
- **Coolify version:** 4.3.18
- **Box:** production (cax21)
- **Build pack:** `dockercompose`
- **Exact request:** `POST /applications/public` create body — no `fqdn`, `domains`, or `ports_exposes` key sent at all.
- **Result:** the created application carries a DEFAULT `fqdn` of the shape `http://<uuid>.<box-ip>.sslip.io` and `ports_exposes` of `"80"` — assigned by Coolify itself, unrequested. No Traefik labels exist for this default host and the proxy 404s for it (no LIVE exposure), but the RESOURCE RECORD itself claims a public domain, which is what CA-1's `admissionGuard.ts` correctly refuses to boot on (`COOLIFY_FQDN` non-empty).
- **NOT measured:** whether this default-assignment behavior differs for `build_pack=dockerfile` (this repo's only dockerfile-pack resources are legacy/incumbent, never freshly created since this measurement).

---

## COOLIFY-FACT-05 — `fqdn`/`domains` PATCH refuses on a `dockercompose` app; `docker_compose_domains` is the field name

- **Date:** 2026-09-21 (PR #862 review)
- **Coolify version:** 4.3.18
- **Box:** production (cax21)
- **Build pack:** `dockercompose` (measured on `pfin-provider-sync`)
- **Exact requests and results:**
  - `PATCH /applications/<uuid>` body `{"fqdn": ""}` → **HTTP 422**, body `{"message":"This field is not allowed."}` (paraphrased field name from the message).
  - `PATCH /applications/<uuid>` body `{"domains": ""}` → **HTTP 422**, body naming: *"The domains field cannot be used for dockercompose applications. Use docker_compose_domains instead."*
  - `PATCH /applications/<uuid>` body `{"docker_compose_domains": ""}` (a bare string) → rejected; Coolify's own error pointed at the array shape (see COOLIFY-FACT-06).
  - `PATCH /applications/<uuid>` body `{"docker_compose_domains": []}` (empty array) → **HTTP 200**. Read-back: the app-level `fqdn` column was UNCHANGED — `docker_compose_domains` is per-service compose routing, a DIFFERENT column than `fqdn`, and clearing it does not touch `fqdn`.
- **Scope, stated precisely (Sec F-1, PR #866 review):** the `fqdn`/`domains` 422s above were measured with an EMPTY value (`""`). Whether a non-empty valid URL is accepted by either field on a `dockercompose` app is **UNMEASURED** — "This field is not allowed" reads field-level (rejects the key regardless of value), so the honest position is "probably rejected regardless of value, not proven for a non-empty one." No script in this repo attempts a non-empty `fqdn`/`domains` PATCH.
- **Consequence:** the ONLY mechanism this repo uses to actually clear `fqdn` is a box-side Laravel tinker write (`TINKER-WRITE-ALLOW-07`, `scripts/provision-worker.sh`), Sec-ruled acceptable under three conditions (see that script's own header). The ONLY mechanism used to ASSIGN a real domain is `docker_compose_domains` (see COOLIFY-FACT-06) — never a tinker write for assignment; a tinker-based assignment mechanism would be a NEW allowlist site requiring its own Sec proposal, not an extension of ALLOW-07.
- **NOT measured:** the non-empty-value case for `fqdn`/`domains`, as stated above.

---

## COOLIFY-FACT-06 — `docker_compose_domains` write shape (array) vs read shape (string), per Coolify's own v4.3.18 OpenAPI schema

- **Date documented:** 2026-09-21 (this file's own authoring — sourced from Coolify's published schema, NOT a fresh live-box measurement; see "measured vs documented" note below)
- **Coolify version:** 4.3.18 (exact tag `v4.3.18`, `github.com/coollabsio/coolify`, `openapi.yaml`)
- **Source:** `openapi.yaml`, `update-application-by-uuid` PATCH operation (`/applications/{uuid}`), request-body schema:
  ```yaml
  docker_compose_domains:
    type: array
    description: 'Array of URLs to be applied to containers of a dockercompose application.'
    items:
      properties:
        name: { type: string, description: 'The service name as defined in docker-compose.' }
        domain: { type: string, description: 'Comma-separated list of URLs (e.g. "https://app.coolify.io,https://app2.coolify.io")' }
        redirect: { type: string, nullable: true, enum: [www, non-www, both] }
      type: object
  ```
  So a PATCH body element is `{"name": "<compose service>", "domain": "<comma-separated URLs>"}` — `redirect` optional.
- **Read-shape asymmetry (same OpenAPI file, the `Application` response-model schema, ~line 13959):** the RESPONSE model's own `docker_compose_domains` field is declared `type: string, nullable: true` — a plain string, NOT an array. Coolify evidently serializes this field differently for read than it accepts for write. The exact runtime string shape (a re-serialized JSON array? a bare comma-list? something else entirely?) has not been read off a live GET response by any script in this repo.
- **Measured vs documented — stated precisely:** the ARRAY WRITE SHAPE above is sourced from Coolify's own published API schema for the exact version tag running on the box, not from a live PATCH this repo has issued. PR #862 DID measure a live `docker_compose_domains` PATCH — but only with `[]` (empty array), confirming the endpoint accepts an array and 200s (see COOLIFY-FACT-05) — never with a real `{"name":..., "domain":...}` element. So: the FIELD NAME and the "it's an array, `[]` works" fact are LIVE-MEASURED; the ELEMENT SHAPE (`name`/`domain`/`redirect` keys) is SCHEMA-DOCUMENTED, not yet independently confirmed by a live PATCH with real content.
- **NOT measured:** (1) whether a real `{"name": "app", "domain": "https://..."}` element is accepted and takes effect; (2) the runtime string shape `docker_compose_domains` reports on read-back; (3) whether Traefik actually routes traffic to the assigned domain once set — full confirmation is step 22's live DNS cutover, not this file.

---

## COOLIFY-FACT-07 — `PATCH {"ports_exposes": ""}` clears successfully via the public API

- **Date:** 2026-09-21 (team-lead, `pfin-provider-sync` uuid `hmjeuhdaolhw8tlz3qi6lopi`)
- **Coolify version:** 4.3.18
- **Box:** production (cax21)
- **Build pack:** `dockercompose`
- **Exact request:** `PATCH /applications/<uuid>` body `{"ports_exposes": ""}`.
- **Result:** HTTP 200; a fresh `GET /applications/<uuid>` immediately after confirmed `ports_exposes` no longer SET (ABSENT/EMPTY). Unlike `fqdn`, this field DOES have a working public-API clear path.
- **NOT measured:** the SET direction with a non-default value beyond what `scripts/assign-app-domain.sh`'s own ports_exposes-preflight write-and-readback already exercises (3000, matching this repo's own compose `expose:` values) — that specific case IS covered by that script's own read-back, just not recorded as a standalone fact here.

---

## COOLIFY-FACT-08 — box-side Laravel tinker write clears `fqdn`

- **Date:** 2026-09-21 (PR #862 review, Sec-ruled acceptable)
- **Coolify version:** 4.3.18
- **Box:** production (cax21)
- **Build pack:** `dockercompose`
- **Exact request (not a public API call — a box-side `docker exec` into the `coolify` container):**
  ```
  docker exec coolify php artisan tinker --execute='/* TINKER-WRITE-ALLOW-07 */$app = \App\Models\Application::where("uuid","<uuid>")->firstOrFail(); $app->fqdn = null; $app->save(); $app->refresh(); echo $app->fqdn === null ? "CLEARED" : "STILL_SET";'
  ```
- **Result:** echoes `CLEARED`; a subsequent `GET /applications/<uuid>` confirms `fqdn` ABSENT/EMPTY. This is a direct DB/model-layer mutation bypassing the API's own validation and authorization — a materially more privileged mechanism than every other write in this repo, allowlisted under marker `TINKER-WRITE-ALLOW-07` (`scripts/ci/fence-tinker-write-allowlist.sh`) with three Sec-ruled conditions (narrow/literal body, split done-predicate, tree-wide allowlist fence) — see `scripts/provision-worker.sh`'s own header for the full conditions.
- **NOT measured:** whether the SAME tinker mechanism, generalized to SET `$app->fqdn` to a real domain string (rather than `null`), would work or would need a different write path — this repo does not use tinker for domain ASSIGNMENT, only for clearing (see COOLIFY-FACT-05's consequence note); any such use would be a new allowlist site requiring its own Sec proposal.

---

## COOLIFY-FACT-09 — `COOLIFY_RESOURCE_UUID` (container env) equals the resolved application uuid

- **Date:** 2026-09-21, ~20:35Z (team-lead, run-10)
- **Coolify version:** 4.3.18
- **Box:** production (cax21)
- **Build pack:** `dockercompose` (all three measured resources)
- **Exact measurement:** `docker exec <container> env | grep COOLIFY_RESOURCE_UUID` against the running container for each of three resources, compared against that resource's own resolved application uuid (via `GET /applications`).
- **Result:**
  - `pfin-provider-sync` — `COOLIFY_RESOURCE_UUID=hmjeuhdaolhw8tlz3qi6lopi`, equal to its own resolved app uuid.
  - `pfin-back-etl` (both containers) — `COOLIFY_RESOURCE_UUID=drlazsooiksh4wakbldll5uo`, equal to its own resolved app uuid.
  - `pfin-app` — `COOLIFY_RESOURCE_UUID=7frkiyqnetb4bgev7j7sw5eg`, equal to its own resolved app uuid.
- **Consequence:** `scripts/verify-worker-ca1-clear.sh`'s positive-token assertion (distinguishing "read failed" / "read succeeded but absent" / "read succeeded but wrong value") relies on this equality holding for every worker.
- **NOT measured:** whether this equality holds for a NON-worker, non-app resource type (e.g. a Coolify database service) — no script in this repo currently needs that.

---

## COOLIFY-FACT-10 — deployment status polling via `GET /deployments/<uuid>`

- **Date:** not explicitly dated in the source comment; landed as part of `scripts/deploy-app.sh`'s own deploy-wait logic.
- **Coolify version:** 4.3.18 (consistent with every other fact here; not independently re-stated in the source).
- **Box:** production (cax21)
- **Build pack:** N/A (deployment-status endpoint, not build-pack-specific)
- **Exact request:** `GET /deployments/<deployment-uuid>`, polled up to 90 times at 4-second intervals (a 360-second ceiling), from a single SSH session server-side (not 90 separate SSH round trips from the caller).
- **Result:** the response's `status` field reaches `"finished"` or `"failed"`; on any other terminal state after the poll ceiling, `scripts/deploy-app.sh` fetches the deployment's own `logs` field (a JSON-encoded string) for diagnostic output.
- **NOT measured:** the full enumerated set of possible `status` values beyond `finished`/`failed` (e.g. `queued`, `in_progress` — inferred from the polling shape, never explicitly enumerated against the live API).

---

## COOLIFY-FACT-11 — `docker events` is non-functional on the box

- **Date:** 2026-09-21 (run-8 stop)
- **Coolify version:** 4.3.18 (Docker daemon version not separately recorded)
- **Box:** production (cax21)
- **Build pack:** N/A (daemon-level, not application-specific)
- **Exact measurement:** `docker events` invoked directly on the box.
- **Result:** returns nothing — no event stream observed, even across an action expected to emit one (a container start/stop).
- **First recorded in-tree here** — this fact previously existed only in cross-session agent memory (not a tracked file); this entry is its first landing in the repo. Consequence: no script in this repo relies on `docker events` for state observation; every liveness/state check here polls a REST endpoint or reads `docker ps`/`docker inspect` directly instead.
- **NOT measured:** the root cause (daemon config, cgroup driver, a Coolify-managed proxy in front of the Docker socket) — reported as an operational fact to route around, not diagnosed.
