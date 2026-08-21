---
name: outer-fence-masks-inner-fence
description: A denied-access test can demonstrate the wrong layer when multiple independent fences stack — verify which one actually fired, not just that access was denied.
metadata:
  type: feedback
---

Postgres checks schema `USAGE` before function `EXECUTE` is ever consulted. A `set local role anon;
select pfin.fn_some_function(...)` test that returns `permission denied for schema pfin` proves the
**schema USAGE** fence is intact — it says nothing about whether `revoke execute ... from public` /
`grant execute ... to authenticated` is also correctly in place, because that check was never
reached. Confirmed independently via `has_schema_privilege('anon','pfin','USAGE')` = false AND
`has_function_privilege('anon','pfin.fn_x(...)','EXECUTE')` = false — both fences happened to be
correct here, but the ERROR MESSAGE alone (naming the schema, not the function) only demonstrates
the outer one.

**Why:** Architect caught this on the SELF-330 `fn_subcat_contributors` merge-gate report — I'd
written "anon denial matches the authenticated-only grant," which overclaims:
the grant was never independently exercised. Same shape as a QA finding earlier on the same branch
(the liability-route fence's four tests all passed with the load-bearing `lut.users_id = acc.users_id`
conjunct struck, because a DIFFERENT control — `account_select` RLS — was covering for it). Two
controls, one observed conclusion, and the test exercising only the one that was never in question.
**Matters because:** if `anon` ever gets schema USAGE for an unrelated reason, the EXECUTE revoke
becomes the SOLE discriminator, and a test that only ever hit the USAGE fence would never have told
you whether that revoke was intact.

**How to apply:** when a permission-denial test is meant to verify a SPECIFIC grant/revoke (not just
"is this locked down at all"), check the individual privilege directly — `has_schema_privilege(...)`
/ `has_function_privilege(...)` / `pg_proc.proacl` / `pg_namespace.nspacl` — rather than relying on
the error message from an end-to-end call, which only tells you the FIRST fence in the chain that
fired, not which fences exist behind it. This generalizes beyond Postgres ACLs: any layered-fence
system (RLS + grants, CI fences + code review, auth + rate-limit) has the same shape — a green/red
result from the outside proves the outermost fence, not the one you meant to test, unless you check
each layer's own state directly.
