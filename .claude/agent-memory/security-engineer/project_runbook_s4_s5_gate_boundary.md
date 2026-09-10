---
name: runbook-s4-s5-gate-boundary
description: Ruling 2026-09-10 — runbook §5's Sec gate does NOT block executing §4; the boundary is minting (§4) vs app-facing Coolify injection (§5)
metadata:
  type: project
---

`docs/deployment-runbook.md` §5's Sec-gate STUB does **not** block executing §4 (Supabase stand-up). Ruled (A) on 2026-09-10 at `main` `8434d721`.

**The boundary is MINT vs PLACE, not "is it a catalogued secret."**
- §4 owns the Supabase compose resource's OWN env: `POSTGRES_PASSWORD`, `JWT_SECRET`, `ANON_KEY`, `SERVICE_ROLE_KEY`, plus `GOTRUE_DISABLE_SIGNUP=true` and the founding-tenant invite run from the operator's shell.
- §5 owns injection into the four V1 **service** envs — including `SUPABASE_SERVICE_ROLE_KEY` into the `app` service, and including the non-secret `PUBLIC_SUPABASE_URL` / `PUBLIC_SUPABASE_ANON_KEY`, because §4 line ~398 routes those to "§5's `PUBLIC_`-prefixed injection list" BY NAME. Non-secret ≠ ungated.

**Why:** §4 carries no STUB marker and its own preamble says it "only names where these five land; rotation/injection-order procedure is §5's job."

**Non-objections recorded:** no ADR-016 D1 amendment needed — injecting into the `app` env adds no source-file consumer, so the RT-26 allowlist is untouched.

**Open obligation surfaced, written nowhere on the tree:** rotating `JWT_SECRET` invalidates BOTH `ANON_KEY` and `SERVICE_ROLE_KEY`. §5 must carry that coupling. See [[a-definer-grant-hands-back-the-channel]] for the reachability framing and [[plaid-credential-confinement-contradiction]] for the provisioning-prose precedent.

**How to apply:** when §5 is authored, review it against this boundary — and check §4.1's read-back trap (it asserts migration 061 has applied, but migrations apply at §6, which is still a STUB; run at §4 time it falsely reads "migration did not apply").
