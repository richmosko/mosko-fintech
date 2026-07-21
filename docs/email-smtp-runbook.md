# Email / SMTP runbook (Auth-1 · SELF-290)

Operator guide for wiring outbound auth email. **This runbook *is* the "operator chooses a provider" mechanism** — since mosko-fintech is built as software others run their own copy of, each operator picks their SMTP provider here at deploy time.

## Architecture (why this is a config choice, not a code choice)

In V1, **all email is sent by GoTrue (Supabase Auth), not by the app** — every message is an auth email (signup confirmation, password reset, email-OTP, MFA recovery). GoTrue takes standard **SMTP** config, and Resend / SES / self-host all expose an SMTP interface, so **the app is provider-agnostic by construction** — switching providers is a config swap, never a code change. There is no in-app "switch provider" toggle (it's a per-deployment concern, and GoTrue reads SMTP config at startup, not per-request).

> A code-level `EmailProvider` adapter is only warranted if/when the **app itself** starts sending email (V2 monthly-report delivery) — then mirror the ADR-027 `ProviderAdapter` pattern. Not now.

## The env contract

Configure these on the **self-hosted Supabase / GoTrue** deployment env (Coolify), **not** the web-app container's `.env` (SMTP is a Supabase-stack concern, not a web-app secret). The `pass` is the only secret → Coolify-injected + tracked in `secrets-manifest.yml`; **never committed**.

| Var | Meaning | Resend (default) | SES (alternative) |
|---|---|---|---|
| `SMTP_HOST` | SMTP server | `smtp.resend.com` | `email-smtp.<region>.amazonaws.com` |
| `SMTP_PORT` | port | `465` | `587` |
| `SMTP_USER` | username | `resend` | *(IAM-derived SMTP username)* |
| `SMTP_PASS` | **secret** | *(Resend API key)* | *(IAM-derived SMTP password)* |
| `SMTP_ADMIN_EMAIL` | envelope sender | `noreply@<your-domain>` | `noreply@<your-domain>` |
| `SMTP_SENDER_NAME` | display name | `mosko-fintech` | `mosko-fintech` |

The `supabase/config.toml` `[auth.email.smtp]` block documents this shape (kept **commented** so local dev keeps using Inbucket). The prod flip happens in the GoTrue env, not that file.

## Provider A — Resend (V1 default)

1. Create a Resend account; add + **verify your sending domain** (`<your-domain>`).
2. Add the Resend-generated DNS records to your domain: **SPF**, **DKIM**, and a **DMARC** policy record. Wait for verification to go green.
3. Create an API key → set `SMTP_PASS` in Coolify (and add the entry to `secrets-manifest.yml` — **Sec-review** as a new prod secret).
4. Set the other env vars per the table (`SMTP_USER=resend`, `SMTP_HOST=smtp.resend.com`, `SMTP_PORT=465`).
5. Verify: trigger a signup → the confirmation email lands in a **real inbox, not spam**.

## Provider B — Amazon SES (alternative)

Same env contract; the deltas an operator choosing SES must complete:
1. **Exit the SES sandbox** — new SES accounts can only send to *verified* addresses until you request **production access** (manual AWS approval, usually ~1 day).
2. Verify the sending domain (DKIM via Route53 is near one-click; else add records manually) + SPF + DMARC.
3. Generate **SMTP credentials from IAM** → `SMTP_USER` / `SMTP_PASS`. Pick the region → `SMTP_HOST=email-smtp.<region>.amazonaws.com`, `SMTP_PORT=587`. (An EU region keeps auth mail EU-resident.)
4. **Wire bounce/complaint handling** — SES expects you to process bounces/complaints (an SNS topic) and will **pause sending** if those rates climb unhandled.

## Self-hosting (discouraged)

Running your own SMTP (Postfix / mailcow / …) is **not recommended** for this app: cloud hosts (incl. **Hetzner**) block outbound port 25 by default; fresh VPS IPs have no sending reputation (and many ranges are pre-blocklisted); you own SPF/DKIM/DMARC + rDNS/PTR + blocklist monitoring + delisting; and email is on the **auth critical path** (a silent deliverability failure = users can't sign up, reset, or complete 2FA). The dollar cost is trivial; the deliverability + ops risk is not. Choose this only for a hard zero-third-party requirement.

## Local development

**Nothing to configure.** The Supabase CLI stack routes all mail to **Inbucket** (`http://127.0.0.1:54324`) — read confirmation/reset/OTP emails there. `enable_confirmations` stays `false` locally (dev convenience); the custom templates in `supabase/templates/` are active locally too.

## No domain yet, or local-only (no public email)

**Key distinction:** the app's URL/hostname and the email **sending** domain are independent — you can run the app at `localhost`, an IP, or a `.local` name and still send from a verified sending domain. "No domain" only blocks email when you actually need to deliver to real inboxes.

**No domain yet (deploying publicly later):**
- *Interim (test-to-self):* use Resend's shared sender **`onboarding@resend.dev`** — works immediately with no domain verification, but **only delivers to the email you registered with Resend.** Enough to build + test the whole signup / reset / OTP flow against your own inbox. Set `SMTP_ADMIN_EMAIL=onboarding@resend.dev`.
- *Real fix (before real users):* register any cheap domain (~$10/yr — needn't be fancy), verify it on Resend (ideally a `mail.` subdomain to isolate sending reputation), then set `SMTP_ADMIN_EMAIL=noreply@<your-domain>`. The app does **not** need to run at that domain — it's only the `From:` identity.

**Local server that will never have a domain:**
- *Pure local / solo (just you on `localhost`):* configure nothing — **Inbucket** catches every email at `http://127.0.0.1:54324`. Zero domain, zero provider, zero cost (see [Local development](#local-development) above).
- *Closed instance, a few real users, no domain* — two postures:
  1. **Relay through a personal mailbox's SMTP.** GoTrue only needs SMTP creds, e.g. Gmail with an **app password**: `SMTP_HOST=smtp.gmail.com`, `SMTP_PORT=587`, `SMTP_USER=<your-gmail>`, `SMTP_PASS=<app-password>` (needs 2FA on that Google account to mint one). Fine for low volume to known recipients; caveats: Gmail's ~500/day limit + mail sends from your personal address.
  2. **Turn email off entirely.** Set `enable_confirmations = false`, have the **admin provision accounts**, use **TOTP** for MFA (needs no email), and rely on an **admin/DB break-glass** for recovery instead of email reset. A fully email-free posture for a closed, admin-managed instance — no domain, no SMTP provider.

## Posture notes

- **`enable_confirmations`**: `true` in prod (real signups verify their email), `false` local. Set on the GoTrue env at deploy.
- **Rate limits** (`config.toml [auth.rate_limit]`): review `email_sent` (per-hour) and `token_verifications` (per-5-min) before go-live; the defaults are conservative — raise deliberately.
- **Templates** (`supabase/templates/*.html`): `confirmation` (signup), `recovery` (Auth-5 reset), `magic_link` (Auth-4 email-OTP — emphasizes the code). Plain-text-safe, system-authored.

## Out-of-band / follow-up (not in the repo)

- Resend account + domain verification + DNS records — operator action.
- `secrets-manifest.yml` `SMTP_PASS` entry — **DevOps + Sec joint-review** (new prod secret on the Supabase-stack surface).
- Prod GoTrue env wiring — done when the self-hosted Supabase stack is stood up (deploy phase).
