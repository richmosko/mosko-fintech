---
name: seed-reprovision-vs-user-delete-interaction
description: An idempotent "provision defaults on every load" guard keyed to a static seed tuple silently un-deletes a user's intentional deletion of that exact row, when the provisioning call runs on every request (e.g. root layout load). Confirmed live, SELF-265/103.
metadata:
  type: feedback
---

Live-walked SELF-265's delete affordance on `/settings/tax-brackets`: deleted the
seeded California 2025 bracket schedule (the one `pfin.fn_provision_tax_brackets()`
auto-creates at signup, per SELF-260/migration 103). The DB delete succeeded and the
row genuinely disappeared. On the VERY NEXT page navigation, it silently REAPPEARED
as a brand-new row (new id, byte-identical seed content).

**Mechanism, generalizable:** `api/src/routes/+layout.server.ts` calls
`provisionDefaultTaxonomy(...)` → `provisionTaxBrackets(...)` on EVERY authenticated
request (this is a root layout load, so it also re-runs on the `update()`-triggered
reload that follows the delete action itself). `fn_provision_tax_brackets()`'s own
existence guard is `on conflict (users_id, tax_year, schedule_type) do nothing`,
keyed to the STATIC TEMPLATE's exact (tax_year, schedule_type) tuple — it has no
concept of "the user deleted this on purpose," so the very next provisioning call
re-inserts it as if it had never existed.

**Why this is a SEAM bug, not obviously either issue's fault:** the provisioning
function/guard was built in an EARLIER issue (SELF-260) for a world with no delete
affordance; the delete affordance was built in a LATER issue (SELF-265) against a
table it didn't know had an every-request re-seed guard pointed at one of its own
rows. Neither issue's own tests catch it — SELF-260's tests never exercise DELETE,
SELF-265's tests never exercise the layout-level provisioning call. Only a live,
multi-navigation walk surfaces it.

**How to apply:** whenever a DELETE affordance ships for a table that is ALSO
populated by an idempotent "provision on every load / every login" seed function,
check whether the seed function's existence guard is keyed to the SAME identity the
delete targets (here: the literal seed tuple) — if so, deleting that exact row is not
durable. This generalizes beyond this table: any `ensure*`/`provision*` call wired
into a root layout or hooks path is a candidate for this interaction the moment a
delete (or an edit that changes the identity key) ships against its target table.
