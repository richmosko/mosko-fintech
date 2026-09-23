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
- **NOT measured (as of this file's original authoring):** (1) whether a real `{"name": "app", "domain": "https://..."}` element is accepted and takes effect; (2) the runtime string shape `docker_compose_domains` reports on read-back; (3) whether Traefik actually routes traffic to the assigned domain once set.
- **(1) and (3) now measured — run 22, 2026-09-22 (`--only dns --confirm-cutover`, main `469f451d`), per `scripts/assign-app-domain.sh`'s own post-redeploy container-env read instruction (this script does not write to this file itself):** a real `{"name": "app", "domain": "https://pfindash.com,https://www.pfindash.com"}` element takes effect end-to-end. The PATCH read-back exact-set matched (confirming COOLIFY-FACT-15's parser fix); after the mandatory redeploy, the NEW container (`be3ffaff6e57`, confirmed different from the pre-redeploy container and State.Running=true) reported via `docker exec ... env`: `COOLIFY_FQDN=pfindash.com,www.pfindash.com COOLIFY_URL=https://pfindash.com,https://www.pfindash.com SERVICE_FQDN_APP=pfindash.com`. Traefik DOES route real traffic to the assigned domain: `https://pfindash.com/` and `https://www.pfindash.com/` both answer over a Let's Encrypt-issued, chain-verified TLS cert (`ssl_verify_result=0`; issuer Let's Encrypt CN=YR1; subject CN=pfindash.com; notBefore 2026-09-22 20:52:32 GMT) — an unauthenticated `/` 303-redirects to `/login` (200), which is the app's own auth gate working correctly, not a routing failure (see COOLIFY-FACT-06's own consequence for `scripts/assign-app-domain.sh`'s cert-poll fix, run-22 follow-up).
- **Reconfirmed independently — run 24, 2026-09-22 (`--only dns --confirm-cutover`, main `3e9deafc`):** a THIRD live pass (after run 22 above), this time with DNS/ports already correct (no-ops) and the `docker_compose_domains` PATCH read-back exact-matching what was already assigned -- yet the script still redeployed (see BACKLOG.md item 90: this is the idempotence gap that redeploy shouldn't have fired). The new container (`df261696df7e`) again carried the expected env values; the sslip probe again MEASURED both sides identically (http=404, https=503 -- no second route, corroborating COOLIFY-FACT-16 under a second run); and the cert poll's corrected predicate (PR #879, `%{url_effective}` term) reported `final http 200, effective https://pfindash.com/login` for BOTH apex and www -- the first live confirmation of the round-2 corrected predicate specifically (round 1/round 2 were fence-verified only until this run).
- **Reconfirmed a FOURTH time — run 26, 2026-09-22 (`--only dns --confirm-cutover`, main `55d1997f`), first pass with the app-level `fqdn` already cleared:** F/CTO had cleared `pfin-app`'s app-level sslip `fqdn` by hand via tinker (~23:10Z, ahead of this run); this run's own read confirmed `current fqdn: <empty>` going in. The `docker_compose_domains` PATCH read-back again exact-matched; the new container (`6e1c52574b67`) again carried the expected env values (`COOLIFY_FQDN=pfindash.com,www.pfindash.com COOLIFY_URL=https://pfindash.com,https://www.pfindash.com SERVICE_FQDN_APP=pfindash.com`) -- unaffected by the fqdn clear, confirming `docker_compose_domains` and the app-level `fqdn` are genuinely independent routing sources, exactly as PR #882's TINKER-WRITE-ALLOW-09 header reasons. The sslip reachability probe, for the first time in this run sequence, printed **SKIPPED** ("app-level fqdn is empty; nothing to probe") rather than measuring a route -- the first live confirmation that clearing the app-level fqdn does not disturb `docker_compose_domains`-based routing, and that the probe correctly recognizes it has nothing left to check. Cert poll ok for both apex and www, same shape as runs 22/24.
- **Still NOT measured:** whether any OTHER `docker_compose_domains`-consuming endpoint or Coolify version returns the array read-shape instead of the measured object-string shape (COOLIFY-FACT-15's own scope).

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

---

## COOLIFY-FACT-12 — no notification-config REST surface at all; the queued Discord test-send job cannot observe acceptance

- **Date:** 2026-09-21 22:35Z (team-lead)
- **Coolify version:** 4.3.18
- **Box:** production (cax21)
- **Build pack:** N/A (application source measurement, not resource-specific)
- **Exact measurement:** `php artisan route:list --path=api` grepped for `notif`/`team` — zero hits. `discord_notification_settings` has exactly ONE row (`team_id=0`, "Root Team"); the Eloquent model `App\Models\DiscordNotificationSettings` casts `discord_webhook_url` `encrypted`. The test-send path (`app/Livewire/Notifications/Discord.php:208`) dispatches a queued `App\Notifications\Test` job; `app/Jobs/SendMessageToDiscordJob.php::handle()` (read live, `temp/discord-measurements/SendMessageToDiscordJob.php.txt`) ends in `Http::withOptions(...)->post($url, $message->toPayload());` with **no `->throw()` and no status check** — a 4xx from Discord is swallowed and the job still reports success.
- **Result:** unlike every other Coolify-config script in this repo (which go through the documented `ApplicationsController`/`InstanceSettings` REST surface), notification config has NO API path — it must go through the box-side Eloquent model directly. And neither `dispatchSync`-ing the queued job nor watching `failed_jobs` can prove Discord actually accepted a test notification — the job's own swallowed-status bug makes it structurally silent on failure.
- **Fix landed:** `scripts/coolify-discord-notify.sh` (BACKLOG.md §7.36 item 74) writes the settings row directly via the Eloquent model (new `TINKER-WRITE-ALLOW-08` marker) and, for the test-send, builds the SAME payload the queued job would (`(new \App\Notifications\Test(channel: 'discord'))->toDiscord()->toPayload()`) and POSTs it itself inside the same tinker call, asserting the raw HTTP status directly — never going through the queued job at all.
- **NOT measured:** whether `SendMessageToDiscordJob`'s own retries (`$tries = 5`) could ever race this script's direct POST on a run where both fire — not a safety issue (idempotent notification), just an honest gap. See `scripts/coolify-discord-notify.sh`'s own header for the full measurement writeup this fact summarizes.

---

## COOLIFY-FACT-13 — the 15 per-event Discord flag columns all carry a `_discord_notifications` suffix; the display names do not

- **Date:** 2026-09-22T05:54:52Z (team-lead; supersedes an initial 05:55Z same-day pass with the identical result — re-run to get an exact query + `$fillable` capture for this entry)
- **Coolify version:** 4.3.18
- **Box:** production (cax21)
- **Build pack:** N/A (schema-level, not resource-specific)
- **Exact measurement:** `docker exec coolify-db psql -U coolify -d coolify -At -c "select column_name||':'||data_type from information_schema.columns where table_name='discord_notification_settings' order by ordinal_position"` — full column list, in `ordinal_position` order, with type:

  ```
  id:bigint
  team_id:bigint
  discord_enabled:boolean
  discord_webhook_url:text
  deployment_success_discord_notifications:boolean
  deployment_failure_discord_notifications:boolean
  status_change_discord_notifications:boolean
  backup_success_discord_notifications:boolean
  backup_failure_discord_notifications:boolean
  scheduled_task_success_discord_notifications:boolean
  scheduled_task_failure_discord_notifications:boolean
  docker_cleanup_success_discord_notifications:boolean
  docker_cleanup_failure_discord_notifications:boolean
  server_disk_usage_discord_notifications:boolean
  server_reachable_discord_notifications:boolean
  server_unreachable_discord_notifications:boolean
  discord_ping_enabled:boolean
  server_patch_discord_notifications:boolean
  traefik_outdated_discord_notifications:boolean
  restart_limit_reached_discord_notifications:boolean
  ```

  17 boolean columns total (`discord_enabled` + `discord_ping_enabled` + the 15 event flags); `discord_webhook_url` is `text` (`encrypted` cast on the Eloquent model, per FACT-12); `id`/`team_id` are `bigint`.

  Also read live from the box: `App\Models\DiscordNotificationSettings`'s own `$fillable`:

  ```php
      protected $fillable = [
          'team_id',

          'discord_enabled',
          'discord_webhook_url',

          'deployment_success_discord_notifications',
          'deployment_failure_discord_notifications',
          'status_change_discord_notifications',
          'restart_limit_reached_discord_notifications',
          'backup_success_discord_notifications',
          'backup_failure_discord_notifications',
          'scheduled_task_success_discord_notifications',
          'scheduled_task_failure_discord_notifications',
          'docker_cleanup_success_discord_notifications',
          'docker_cleanup_failure_discord_notifications',
          'server_disk_usage_discord_notifications',
          'server_reachable_discord_notifications',
          'server_unreachable_discord_notifications',
          'server_patch_discord_notifications',
          'traefik_outdated_discord_notifications',
          'discord_ping_enabled',
      ];
  ```

  Every one of the 16 columns this script writes (15 event columns + `discord_ping_enabled`) IS present in `$fillable` — confirms `update([...])` with the real column names actually persists, not merely that the column exists in the schema. `id` is absent from `$fillable` (expected, primary key).
- **Result:** every per-event flag column is named `<event>_discord_notifications`, never the bare event name. The 15 real columns are: `deployment_success_discord_notifications`, `deployment_failure_discord_notifications`, `status_change_discord_notifications`, `backup_success_discord_notifications`, `backup_failure_discord_notifications`, `scheduled_task_success_discord_notifications`, `scheduled_task_failure_discord_notifications`, `docker_cleanup_success_discord_notifications`, `docker_cleanup_failure_discord_notifications`, `server_disk_usage_discord_notifications`, `server_reachable_discord_notifications`, `server_unreachable_discord_notifications`, `server_patch_discord_notifications`, `traefik_outdated_discord_notifications`, `restart_limit_reached_discord_notifications`. Three related columns are correctly named with no suffix: `discord_ping_enabled`, `discord_enabled`, `discord_webhook_url`.
- **Defect this corrects:** `scripts/coolify-discord-notify.sh`'s original `--apply`/`--state` implementation (BACKLOG.md §7.36 item 74, run 18) used the bare event name as the column name in both `read_state()`'s `$fields` list and the write's `->update([...])` payload. Eloquent's `update()` silently drops unknown/non-existent keys rather than erroring, so the write reported `WRITE_OK` while touching none of the 15 columns, and `read_state()`'s `$s->$f` on a nonexistent attribute returned `null` → printed `false` for every flag unconditionally — exactly the "VERIFIED but every flag false" symptom run 18 measured. The fake-ssh fixture backing `scripts/ci/fence-coolify-discord-notify-strikes.sh` echoed a canned `WRITE_OK` without inspecting the payload's column names, so the fence stayed green through the defect (fixture-fidelity class, fourth instance in one week per Sec).
- **Fix landed:** `scripts/coolify-discord-notify.sh`'s `EVENT_FLAGS` array (display name : real column : target value) is the single source for both `read_state()`'s field map and the write's update-fields block, generated via `php_field_map()`/`php_update_fields()` so the two cannot drift apart again. The 16 real column names here (15 event columns + `discord_ping_enabled`) are the ones `scripts/ci/fence-coolify-discord-notify-strikes.sh` pins against both the script's own source and the fake-ssh fixture's write-inspection branch. Sec's own review of this fix (PR #873) additionally required `read_state()` to fail closed on a genuinely-NULL column rather than coercing it to `"false"` via a bare ternary — a NULL `backup_failure` would otherwise read as "already false" and make the idempotency check skip a write that was never actually confirmed; `read_state()` now prints a distinct `NULL` token per-flag, which every downstream `== "true"`/`== "false"` bash comparison already fails closed on by construction.
- **NOT measured:** whether any Coolify version upgrade has ever renamed or added a flag column — this fact is a point-in-time schema read, not a migration-tracked guarantee; re-measure after any Coolify version bump that touches notification settings.

---

## COOLIFY-FACT-14 — `getAttributes()`/`array_key_exists()` genuinely omits an unknown column; a bare short-name read yields `null`

- **Date:** 2026-09-22 ~06:25Z (team-lead)
- **Coolify version:** 4.3.18
- **Box:** production (cax21)
- **Build pack:** N/A (Eloquent-model-level, not resource-specific)
- **Exact measurement:** read-only `docker exec coolify php artisan tinker --execute='...'` against the live `discord_notification_settings` row for `team_id=0` (no write verb; no `TINKER-WRITE-ALLOW` marker needed). Four legs on the same `$s`:
  1. `array_key_exists("backup_failure_discord_notifications", $s->getAttributes())` → **present** (positive control — the real column IS a key in `getAttributes()`'s own array).
  2. `array_key_exists("backup_failure", $s->getAttributes())` → **MISSING**.
  3. `is_null($s->backup_failure)` → **null** — a bare property read of the short (wrong) name yields `null`, which the pre-PR-#873 code (`$s->$col ? "true" : "false"`) coerced to `"false"`.
  4. `$s->backup_failure_discord_notifications` → **true** (Coolify's own default; the Sec PR #871 F1 ruling — write `false` — had not yet been applied on the box at measurement time).
- **Result:** confirms the one premise PR #873's F-1 fix (`array_key_exists($col, $s->getAttributes())` guard in `read_state()`) rests on: `getAttributes()` genuinely omits a key for a column that isn't a real DB column on this Coolify/Eloquent version, and a bare `$s->$shortName` read on that same absent key returns `null`, not an exception and not a coerced `false` unless the calling code does that coercion itself (which is exactly the bug PR #873 fixed). Closes the caveat `scripts/ci/fence-coolify-discord-notify-strikes.sh`'s scenarios 30–33 state explicitly (those scenarios drive the fake-ssh transport with a hardcoded token/value and can only prove bash reacts correctly GIVEN that signal — they cannot exercise real PHP, since this fence has no PHP runtime). This measurement is the missing PHP-side half.
- **NOT measured:** any other Eloquent model's `getAttributes()` behavior, any Coolify version other than 4.3.18, or `$fillable`'s write-side omission behavior beyond what FACT-13 already records (this fact is read-only).

---

## COOLIFY-FACT-15 — `docker_compose_domains` reads back as a JSON string whose content is an object keyed by service name, not the array shape the PATCH sends

- **Date:** 2026-09-22 ~17:10Z (team-lead)
- **Coolify version:** 4.3.18
- **Box:** production (cax21)
- **Build pack:** `dockercompose` (measured on `pfin-app`)
- **Exact measurement:** `GET /api/v1/applications/<uuid>` immediately after a `PATCH` with body `{"docker_compose_domains": [{"name": "app", "domain": "https://pfindash.com,https://www.pfindash.com"}]}` had already returned HTTP 200.
- **Result:** `docker_compose_domains` in the GET response is a **string**, whose own content (after the outer JSON parse already unescapes it once) is the literal text:

  ```
  {"app":{"domain":"https://pfindash.com,https://www.pfindash.com"}}
  ```

  i.e. a JSON **object** keyed by compose service name, each value itself an object with a `domain` key carrying the same comma-separated URL list the PATCH sent — NOT the flat comma-separated string, and NOT the array-of-`{name,domain}` shape the PATCH itself accepts. The underlying DB column holds the identical text (confirmed via a separate read). `fqdn` remained the Coolify-assigned sslip.io default (unrelated to this field); `ports_exposes` read back `"3000"` (correct, from the same run's ports_exposes PATCH).
- **Defect this corrects:** `scripts/assign-app-domain.sh`'s original read-back check treated the raw `docker_compose_domains` string AS the domain list and split it on commas directly — against the real value above, that produces a single nonsense "domain" equal to the whole JSON blob, which can never equal the intended set. The PATCH itself was correct (Coolify accepted and stored the write); only the read-back PARSER was wrong. Run 21 (`--only dns --confirm-cutover`, main `bb3ee6eb`) hit this live: `FAIL docker_compose_domains PATCH 200'd but the read-back domain SET does not exactly equal the intended set -- live='{"app":{"domain":"https:\/\/pfindash.com,https:\/\/www.pfindash.com"}}' ...` (log: `temp/runlogs-2026-09-21/realrun21-dns.clean.log`).
- **Fix landed:** the read-back now `json.loads()`s the string a SECOND time (the outer `api()` helper's own `json.loads()` on the whole HTTP response body already unescapes it once) to get the real object, selects the target service key, and compares that service's own `domain` value (split on commas) as an exact SET against the intended domains — the same Sec F-4 exact-set discipline this script already applied, now pointed at the correct field. Tolerates the array shape too (in case a future Coolify version reads back what it was sent), and refuses by name if the target service key is absent or an unexpected second service key is present, rather than guessing which one is authoritative.
- **NOT measured:** whether any OTHER `docker_compose_domains`-consuming endpoint or Coolify version returns the array shape instead of this measured object-string shape — the read-back parser tolerates it defensively, but only THIS shape has actually been observed live.

---

## COOLIFY-FACT-16 — the app's Coolify-assigned sslip default answers identically to a nonexistent-host control post-redeploy (no unintended second route, run 22)

- **Date:** 2026-09-22 (team-lead, run 22, `--only dns --confirm-cutover`, main `469f451d`)
- **Coolify version:** 4.3.18
- **Box:** production (cax21)
- **Build pack:** `dockercompose` (`pfin-app`)
- **Exact measurement:** `scripts/assign-app-domain.sh`'s post-redeploy sslip reachability probe (added for the run-21 fix follow-up) — `curl` against the app's own Coolify-assigned sslip host (`http://<uuid>.<box-ip>.sslip.io` and the https scheme) AND a `nonexistent-<random>.<box-ip>.sslip.io` control, both on the SAME box behind the SAME proxy, immediately after the run's own redeploy finished.
- **Result:** MEASURED (not a false all-clear — see the PR #878 review history for why that distinction is load-bearing: the control answered a real HTTP status on both schemes, so the probe genuinely ran). Both the app's own sslip host and the nonexistent-host control answered **identically**: `http=404`, `https=503`. No divergence, and therefore no FINDING — the sslip default is not serving this app as an unintended second route; `pfindash.com`/`www.pfindash.com` (COOLIFY-FACT-15/16 above) are the only live routes.
- **Consequence:** COOLIFY-FACT-05/06's older "not routed, 404 identical to control" fact (measured BEFORE `docker_compose_domains` existed on this app) is now reconfirmed under the CURRENT domain-assignment state, not just historically — this run is the first live measurement of the sslip route's behavior post-cutover.
- **NOT measured:** whether this holds after a FUTURE redeploy that changes `docker_compose_domains` again, or for any other app on this box — this is a point-in-time measurement for `pfin-app`, re-taken by the same script on every future `--apply` run (informational, never a gate).
