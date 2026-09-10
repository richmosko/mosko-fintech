---
name: trimmed-service-leaves-live-routes-in-the-gateway
description: Dropping a service from a compose trim does not drop its routes from the vendored gateway config; restoring the service re-arms every route, including ones whose auth is disabled per-route
metadata:
  type: feedback
---

**A service trimmed OUT of a compose file is still fully routed by the vendored
gateway config. The trim is a claim about CONTAINERS; the routes are a separate
artifact and nobody edited them. Re-adding the service re-arms every route at
once — read the gateway config, not the compose, to learn what a restore exposes.**

**Why:** at the Supabase Studio keep-ruling (2026-09-10) `studio` and `meta` were
OUT of `infra/supabase/docker-compose.yml`, but
`infra/supabase/volumes/api/envoy/lds.template.yaml` was upstream-verbatim and
still carried `/` → `studio`, `/pg/` → `meta`, `/mcp`, `/api/mcp`, plus dead
`cds.yaml` clusters for `realtime`/`storage`/`functions`. Those routes 503 only
because the clusters resolve to nothing. The sharp one was **`/pg/`**: basic auth
`disabled: true` **per-route**, gated solely by an RBAC policy accepting the
service_role key in an `apikey` header — and `meta` connects as `PG_META_DB_USER:
postgres`, the object OWNER and superuser-equivalent. Restoring `meta` alone would
have handed any service_role-key holder (the app tier holds it) arbitrary SQL as
`postgres` through the gateway: outside RLS, outside `TenantBoundConnection`, able
to `ALTER TABLE … DISABLE TRIGGER` on ADR-011 D2 audit-class tables. Neither the
compose header, the runbook, nor the task brief mentioned the routes existed.

**How to apply:**
- When a service is restored to a trim, diff the **gateway/proxy config** for every
  reference to it before ruling on exposure. `grep -n 'cluster:' <lds>` is the census.
- A route with `basic_auth: disabled: true` in its own `typed_per_filter_config` is
  NOT covered by the global filter chain. **Read the per-route overrides; the global
  filter list is the weaker claim.** Same for a per-route RBAC `ALLOW any` sitting
  under a restrictive global policy — the catch-all `/` route did exactly that.
- Prefer **denying the route** over remembering not to expose the service. Upstream's
  own `RBACPerRoute` DENY idiom was already in the file; flipping ALLOW→DENY is
  in-pattern and survives a future Domain assignment, which a convention does not.
- **Reachability couples through the proxy, not just the bind.** Electing a loopback
  publish for the service is worthless if the public-facing gateway still routes to
  it — decide the bind AND the route in the same ruling.

Related: [[feedback_hazard_mechanism_vs_reachability]] ·
[[feedback_fence_sentinel_asserts_subject_not_layer]] ·
[[feedback_a_definer_grant_hands_back_the_channel]] ·
[[project_ci_fenced_set_grep_must_not_be_tightened]]
