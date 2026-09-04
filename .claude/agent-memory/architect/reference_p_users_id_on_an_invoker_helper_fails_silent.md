---
name: p-users-id-on-an-invoker-helper-fails-silent
description: A tenant parameter on a SECURITY INVOKER helper either does nothing or returns EMPTY instead of erroring when a caller passes a foreign id — a wrong question answered as "no data". Ruled twice on the tree; drop it.
metadata:
  type: reference
---

**Do not give a SECURITY INVOKER helper a `p_users_id` parameter.** Under INVOKER, RLS already scopes every read to `auth.uid()`. A tenant argument then has two possible fates and both are bad: it is ignored (misleading — the signature advertises a control that does not exist), or it is ANDed into the predicate, in which case a caller passing **another tenant's id gets zero rows rather than an error**. That is a wrong question answered as *"you have no data"* — indistinguishable at the consumer from a genuinely empty tenant, a broken join, or an RLS regression.

**Ruled twice on the tree, independently:**
- `105` `fn_nav_composition` — *"p_users_id DROPPED (INVOKER + RLS scope by auth.uid())"*. (`p_scope` was dropped in the same breath, because `pfin.scope` is not a type.)
- `101` `fn_tax_bracket_schedule_replace_all` — *"takes NO tenant parameter (`users_id` from `auth.uid()`, R4 rider 4 / Sec D-2)"*, and its first statement's `FOR UPDATE` **is** the tenant fence: a foreign or absent id resolves to zero rows and the function refuses.

**How to apply:** the tenant comes from the session, never from the argument list. If a caller has no session — a cron loop, a service-to-service endpoint — the answer is to **bind an identity** (`SET LOCAL ROLE authenticated` + `set_config('request.jwt.claims', …, true)`, the shipped `TenantBoundConnection` shape in `workers/etl/src/pfin_back_etl/connection.py`), not to pass an id. ⚠ That binding carries its own trap: `auth.uid()` prefers the singular `request.jwt.claim.sub` over the plural claims blob, so a session-scoped singular GUC left set serves **one tenant's data for every tenant, with no code bug and no app-layer assertion failure** (`054`'s comment; `connection.py` nulls it, N7). Companion to [[reference_join_key_decides_failure_direction]] and [[reference_fence_reachability_is_a_property_of_the_caller]].
