---
name: service-role-key-authoritative-writer
description: mint-supabase-jwt-keys.sh is authoritative for SUPABASE_SERVICE_ROLE_KEY on app; push-production-secrets.sh is a second writer that should drop it
metadata:
  type: project
---

`SUPABASE_SERVICE_ROLE_KEY` on the `app` Coolify resource has TWO writers — ruled at PR #748 (2026-09-13, Sec joint-review of runbook §7):

- `mint-supabase-jwt-keys.sh --apply --app-name` — **authoritative**. Mints the real HS256 JWT *derived from the deployed on-box `JWT_SECRET`* and overwrites unconditionally. Only this can produce the correct value.
- `push-production-secrets.sh` — `SECRET_RESOURCE_MAP["SUPABASE_SERVICE_ROLE_KEY"]=[app]`, sourced from the operator's local `.env` (only ever a placeholder or hand-copied stale value).

**Ordering if both run: push FIRST, mint LAST.** Reverse order clobbers the real key → app holds a wrong service_role key → fail-closed 403s on privileged ops (a live-app break, NOT an exposure).

**Durable fix (DevOps, not yet done as of #748): drop `SUPABASE_SERVICE_ROLE_KEY` from push's `SECRET_RESOURCE_MAP`** — the script already excludes the stack-side `SERVICE_ROLE_KEY`/`ANON_KEY` as mint-owned (`EXCLUDED_SUPABASE_STACK`); the app-side name is the same mint-derived class, exclusion just not extended.

**Why:** the value being *derived* from JWT_SECRET is what makes it mint-owned — same reason the stack-side JWT pair is excluded from push. A wrong value fails closed, so this is correctness/availability, not a bypass.

**How to apply:** any change to either script's variable map, or to the §5/§6/§7 provisioning ordering, must preserve mint-authoritative + mint-last (or land the drop-from-push fix). Related: [[project_runbook_s4_s5_gate_boundary]], [[reference_section10_count_3_rt27]].
