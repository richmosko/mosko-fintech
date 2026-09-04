---
name: default-tax-schedules-autoprovision-on-first-page-load
description: The app auto-seeds default federal/CA bracket schedules for a user the FIRST time they load an authenticated page, not at account/signup creation — a real user therefore never sees the true no_schedule_any_year bootstrap state; only a synthetic tenant created via the admin API and never logged in does.
metadata:
  type: project
---

Observed live during SELF-268's THE WALK (2026-09-04). Two synthetic tenants:

- `qa-self268-walk@example.com` — created via admin-API magic-link, then LOGGED IN and loaded
  pages. By the time any account existed, `pfin.tax_bracket_schedule` already held THREE rows
  (federal_ordinary / federal_lt_cg / california_ordinary, "SINGLE filer TEMPLATE" labels) —
  seeded before I created a single account.
- `qa-self268-walk-tenantb@example.com` — created the same way but NEVER logged into the app.
  `fn_compute_tax_liability` for this tenant reads `no_schedule_any_year` on both nav_components
  scalars — genuinely zero schedules.

**Implication:** the DB mechanism correctly handles both states (this is a live-app provisioning
fact, not a DB-fence fact — no memory link needed), but the `no_schedule_any_year` reason is
**not reachable by any real signed-up user** who has ever seen the dashboard — only the
`ytd_paid_unavailable` reason (schedule resolved, no ledger designated) is a real user-visible
state for "realized." This matters for future walk design: don't expect to observe the
"no bracket schedule" caption ("no tax bracket schedule on file — enter it in Settings") in a
live walk with a normally-onboarded tenant; it's effectively test-only / defense-in-depth on the
live product, reachable in pgTAP fixtures (which never touch the app's own provisioning path) but
not through the UI.
