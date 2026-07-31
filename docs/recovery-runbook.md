# Recovery Runbook — last-resort account recovery (break-glass)

> **Owner: Security Reviewer.** Operational last-resort procedures for a self-hosted,
> single-owner instance. Peer to [`deployment-runbook.md`](./deployment-runbook.md) and
> [`email-smtp-runbook.md`](./email-smtp-runbook.md) — this is an **operations runbook**,
> not product security posture (canonical posture lives in
> [`docs/SECURITY/index.html`](./SECURITY/index.html)). Authored for **SELF-288 (Auth-5) AC #3**.

## Recovery ladder — try these in order

Break-glass is the **bottom** of the ladder. Exhaust the self-service rungs first:

1. **Forgot password** ([SELF-288](./SECURITY/index.html), this flow). User has email
   control but forgot the password → `/forgot-password` → email link → `/reset-password`.
   For a **non-MFA** user this proves **email control only**. For an **MFA** user (F/CTO
   Option A) the reset additionally requires a **TOTP step-up to aal2** *before* the new
   password is accepted — so it proves email control **and** the 2nd factor. The reset never
   touches the factor itself, and the post-reset sign-in still re-runs the `025` aal2
   step-up. A user who lost the authenticator too falls through to rung 2. See
   `api/src/routes/{forgot,reset}-password/`.
2. **MFA recovery code** ([`026`](../supabase/migrations/026_mfa_recovery_code.sql) /
   `027`, Slice-2b). User lost their TOTP authenticator but kept a one-time recovery code →
   `/mfa/recover` un-enrolls the verified factor server-side (the 4th RT-26 service_role
   allowlist surface per [ADR-016](../DECISIONS.md#adr-016)).
3. **Break-glass (this document).** User is **locked out with no recovery code** (lost the
   authenticator *and* the recovery code, or the recovery endpoint is unavailable). Because
   the operator owns the database, a direct **service_role / SQL un-enroll** is the final
   backstop. This is a documented procedure, **not** a UI — by design.

## Why break-glass needs the DB (not an in-app path)

For the locked-out MFA user, an in-app fix is impossible:

- **`025` MB-1 guard** blocks an authenticated **aal1** session from lowering `mfa_policy`
  out of the aal2-capable set. A recovering user *is* aal1 (they can sign in with the
  password but cannot complete step-up), so the downgrade cannot run on their JWT. Only
  `service_role` / `postgres` are guard-exempt.
- **CV-R1 (observed, GoTrue v2.189):** an aal1 session `mfa.unenroll()` of a **verified**
  factor returns `422 insufficient_aal` ("AAL2 required to unenroll verified factor"). The
  factor row **must** be removed — otherwise GoTrue keeps `nextLevel = aal2` and the
  fail-closed app guard (`requireStepUp`, `hooks.server.ts`) keeps blocking the user. Only
  `service_role` admin `deleteFactor` (or a direct DB delete) can remove it.

So break-glass is intrinsically a privileged-context operation. In the self-hosted
single-owner model, **DB access is the trust root** — whoever holds it can already read and
rewrite any tenant's data. Break-glass adds no new trust boundary; it just documents the one
safe way to exercise it.

## Preconditions

- Direct DB access to the Supabase Postgres instance (`psql` as `postgres`, or a
  `service_role`-keyed admin client). This bypasses **all RLS and the `025` aal2 backstop** —
  handle accordingly.
- You have independently confirmed the person requesting recovery is the account owner
  (out-of-band; the whole point is that the normal factors are unavailable).

## Procedure (exact, scoped to ONE user)

Run every statement scoped to a single `user_id`. **Verify the `WHERE` clause carries the
`user_id` before you execute** — a broad `DELETE`/`UPDATE` here strips MFA off every account.

**1. Resolve the user id.**
```sql
select id, email from auth.users where email = 'owner@example.com';
```

**2. Inspect the factors (confirm exactly what you're removing).**
```sql
select id, user_id, factor_type, status
from auth.mfa_factors
where user_id = '<uuid>';
```
You are looking for the `status = 'verified'` TOTP factor. Note its `id`.

**3. Remove the verified factor.**
- **Preferred — GoTrue admin API** (keeps GoTrue's internal state consistent):
  `auth.admin.mfa.deleteFactor({ userId: '<uuid>', factorId: '<factor_id>' })` from a
  `service_role`-keyed admin client (observed SUCCESS, `026`).
- **DB fallback** (when the admin API is unreachable):
  ```sql
  delete from auth.mfa_factors where id = '<factor_id>' and user_id = '<uuid>';
  ```
  Associated `auth.mfa_challenges` rows drop via FK cascade. Removing the factor is what
  makes GoTrue report `nextLevel = aal1` again, which is what unblocks the app guard.

**4. Downgrade the policy mirror (N2 reconciliation).** Run as `postgres` / `service_role`
(the `025` MB-1 guard forbids an aal1 JWT from doing this):
```sql
update pfin.user_settings set mfa_policy = 'none' where users_id = '<uuid>';
```
> **Order matters:** the verified factor (step 3) is the **source of truth**; `mfa_policy` is
> only a mirror. If you downgrade the policy but leave the factor, GoTrue still reports
> `nextLevel = aal2` and the fail-closed guard **still blocks** the user. Always remove the
> factor first (or in the same maintenance window). A stale `mfa_policy='totp'` with no factor
> is benign (the guard keys off AAL, not the policy) but leaves a confusing mismatch — keep
> them consistent.

**5. Hand back + force immediate re-enrollment.** The owner signs in (now aal1, no verified
factor → no step-up) and **re-enrolls a fresh TOTP factor immediately** in Security settings.
Normal enrollment re-writes `mfa_policy='totp'` via the standard N2b path. The old TOTP secret
is dead — a new authenticator entry is required.

## Caveats — read before running

- **This is an account-takeover primitive.** It strips the second factor off an account.
  It is gated only by DB access. Run **only** the exact statements above, each scoped to the
  one `user_id`. Never a bare `DELETE FROM auth.mfa_factors` / `UPDATE ... set mfa_policy`.
- **Log it out-of-band** — who ran it, when, for which account, and why (which prior rungs of
  the ladder failed). There is no in-app audit row for a `service_role`/`postgres` action that
  bypasses the backstop.
- **Do not touch other `auth.*` tables.** Do **not** delete the `auth.users` row, rotate
  identities, or edit sessions/tokens. Un-enroll the **factor** only; leave everything else.
- **Prefer the higher rungs.** If the recovery-code endpoint (`026`/`027`) or password reset
  (SELF-288) can do the job, use them — they leave an app-level trail and don't require DB
  access.
- **After break-glass the account is momentarily MFA-off.** Close the loop by confirming the
  owner re-enrolled before considering the recovery complete.

## Cross-references

- [`docs/SECURITY/index.html`](./SECURITY/index.html) — MFA / recovery security posture (canonical).
- [`025_aal2_step_up_backstop.sql`](../supabase/migrations/025_aal2_step_up_backstop.sql) — the DB aal2 backstop + MB-1 guard this procedure works around.
- [`026_mfa_recovery_code.sql`](../supabase/migrations/026_mfa_recovery_code.sql) — the in-app recovery-code path (rung 2) + the CV-R1 observation.
- [ADR-016](../DECISIONS.md#adr-016) — RT-26 `SUPABASE_SERVICE_ROLE_KEY` allowlist (the recovery endpoint is the 4th surface).
- [`supabase/config.toml`](../supabase/config.toml) `[auth.mfa]` — TOTP factor configuration.
- [`email-smtp-runbook.md`](./email-smtp-runbook.md) — email/SMTP posture (the delivery layer the password-reset + recovery-code emails ride).
