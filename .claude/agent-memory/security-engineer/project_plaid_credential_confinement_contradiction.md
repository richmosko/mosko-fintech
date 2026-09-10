---
name: plaid-credential-confinement-contradiction
description: OPEN unresolved Sec finding (raised 2026-09-09) — three artifacts disagree on which container holds PLAID_CLIENT_ID/PLAID_SECRET; needs a ruling before deployment-runbook §5 locks
metadata:
  type: project
---

**OPEN, unruled as of 2026-09-09.** Three artifacts make three different claims about which
container is permitted to hold the Plaid API credentials:

- root `.env.example` **declares** `PLAID_CLIENT_ID` + `PLAID_SECRET` (V1 web-app container).
- `docs/deployment-runbook.md` §5 says that same file has "no Plaid credential at all" and
  that they are held by the **provider-sync worker only** — calling `api/src` being
  credential-less "the load-bearing property that makes that delegation work".
- `docs/ARCH/index.html` §5 says `PLAID_CLIENT_ID`/`PLAID_SECRET` are **NOT held** in the
  web-app container.
- `secrets-manifest.yml` scopes them to "V1 web-app + ETL scheduled-poll + provider-sync worker".

**Why:** this is a **confinement** question, not a naming one — the per-surface `.env.example`
enumeration IS the confinement property ("a secret not listed here does not belong in this
container"), so a file that declares a credential three other artifacts say it must not hold
means either the enumeration is wrong or the property is not holding. Found while measuring an
unrelated dangling pointer during the PR #695 review; deliberately NOT folded into that PR,
which was scoped to the anon key.

**How to apply:** raise this before `deployment-runbook.md` §5's secrets-provisioning STUB locks
— §5's lock is Sec-joint-review-mandatory and locking it over an unresolved confinement
contradiction is the thing to refuse. Verify all four artifacts live before acting; any of them
may have been corrected since. Do not assume the runbook/ARCH pair is the correct side just
because it is two-to-one: ADR-037's delegated ES256/JWK fetch is the substantive argument for
worker-only confinement, and whether the web-app has any remaining Plaid call path is the
measurement that settles it. Related: [[feedback_correcting_half_a_hand_maintained_mirror]].
