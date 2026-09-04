# SELF-267 live walk-through — tax jurisdiction designation

**Branch:** `feature/self-267-walk` (record-only; no source edited)
**Assembled branch under test:** `origin/feature/self-267` at `46f896d`
**Migration under test:** `102_tax_jurisdiction_ytd_paid.sql`
**Test user:** `qa-self256-walk@example.com` (`c86126ed-60dd-4420-babe-a11c10f422eb`)
**Date:** 2026-09-04 (server `current_date`)

## Setup outcomes

1. **Local stack** — already running (`supabase status` from `~/Projects/mosko-fintech`): Studio/Mailpit/MCP up on 54321-54324. (`imgproxy`/`edge_runtime`/`pooler` were stopped but not needed for this walk — not touched.)
2. **Migration 102** — `supabase migration up` in the worktree failed (`Cannot find project ref` — worktree isn't `supabase link`-ed). Fell back to the documented psql path: applied cleanly, zero errors. Verified `\d pfin.account` shows `tax_jurisdiction pfin.tax_jurisdiction_enum`. Manually registered the version row in `supabase_migrations.schema_migrations` (102 wasn't auto-recorded by the psql-fallback path) so the local DB's migration ledger stays consistent for any later `migration up`.
3. **App** — copied `~/Projects/mosko-fintech/api/.env` into the worktree's `api/.env` (was absent). `npm run dev`: port 5173 was already in use (another running instance — not investigated/touched), Vite landed on **5174**.
4. **Login** — used the sanctioned magic-link + session-cookie-transplant method (Supabase local-dev admin API `generate_link` → navigate to the `action_link` → read `access_token`/`refresh_token` off the resulting URL fragment → set the `sb-127-auth-token` cookie on the app origin). No password ever created or entered. Confirmed working end-to-end; landed on the real authenticated dashboard as `qa-self256-walk@example.com`.
5. **Browser** — Chrome MCP tools, fresh tab. 9 screenshots saved under `temp/self267-walk/` (gitignored, not part of this commit).

**Seed accounts used** (pre-existing, `qa-self256-walk@example.com`):
- `4285` "QA Checking 256" — Plaid-linked (provider), depository, taxable
- `4286` "QA Empty 256" — manual, depository, taxable (renamed to "QA Empty 256 (renamed)" during leg G; FTB-designated during leg C)
- `4287` "IRS ledger (walk)" — **new**, created during leg B, IRS-designated then cleared during leg D

## Legs A–G

| Leg | Result | Evidence |
|---|---|---|
| A — default state legible | **SEEN** | 4286 read view shows "Not a tax authority ledger" explicitly; edit-form dropdown shows the same option as a real selected value (not a placeholder), with helper text "Marks this as your IRS or FTB ledger — its balance feeds the §2.5.3 YTD Paid column and is excluded from net worth." `legA_default_state_readview.jpg` |
| B — mark → both figures move | **SEEN** | See detail below. `legB_after_headline_3891.jpg`, `legB_after_composition_headline_divergence.jpg` |
| C — one per authority | **SEEN** | Designating 4286 as IRS while 4287 holds IRS → inline error "Another account is already designated as your tax authority ledger." (4287 confirmed unchanged in DB.) Designating 4286 as FTB → accepted. `legC_second_irs_inline_error.jpg`, `legC_ftb_accepted.jpg` |
| D — clear | **SEEN** | Cleared 4287 back to "Not a tax authority ledger" → `ytd_irs` NULL again; composition identity restored (`gross_total = nav`, both 3890.50000 — now 4287 counted again, 4286 excluded as the FTB ledger). `legD_cleared.jpg` |
| E — provider-linked | **SEEN** | 4285 (Plaid, "Action needed"): Tax Authority control absent from **both** read view and edit form (confirmed via accessibility tree — not CSS-hidden, simply not rendered). Edited Scope → "Personal (walk-edit)" → succeeded; DB confirms `tax_jurisdiction` stayed NULL, untouched. `legE_provider_linked_readview_no_control.jpg`, `legE_provider_linked_editform_no_control.jpg` |
| F — copy | **SEEN** | No raw enum literal appears anywhere in user-visible text across any screen in this walk; all copy uses "IRS (Federal)" / "FTB (California)" / "tax authority" phrasing. Helper text consistently names §2.5.3 YTD Paid + the composition exclusion. (Evidenced across every screenshot above.) |
| G — edit-other-attribute keeps designation | **SEEN** | On the now-FTB account (4286), changed only Name → "QA Empty 256 (renamed)"; DB confirms `tax_jurisdiction` stayed `ftb` (absent-key = no-change rule holds). `legG_name_edit_keeps_ftb.jpg` |

## Leg B detail — BEFORE / AFTER (the walk's defining leg)

Queried as the test user (`set role authenticated` + `request.jwt.claims` sub = user id), matching the battery pattern.

**BEFORE** (accounts 4285 depository $2,890.50 + 4286 depository $0, neither tax-designated):
```
ytd_irs_before   = NULL
comp.gross_total = 2890.50000
nav (fn_compute_nav) = 2890.50000   -- equal, as expected pre-mark
```

**Action:** created manual account 4287 "IRS ledger (walk)", opening balance 1000, tax authority = IRS (Federal), as-of date = today (server `current_date` = 2026-09-04 — deliberately not left blank/backdated, per the known fixture-clock trap where an as-of before "today" silently empties reader-composed functions).

**AFTER:**
```
ytd_irs_after     = 1000.0000        -- E11: the opening acct_setup row counts — confirmed as SEEN, matches PRD §2.5.3 ("every cash row on that ledger counts")
comp.gross_total  = 2890.50000       -- unchanged: new IRS-designated account excluded from composition groups
nav (fn_compute_nav) = 3890.50000    -- includes it; difference = 1000, exactly the new account's balance
```

**UI, same page (`/`, Net Worth dashboard):**
- Headline "NET WORTH" = **$3,891** — matches `fn_compute_nav` (includes the new IRS ledger)
- "COMPOSITION" section further down the same page, "Net Assets Value (NAV)" foot = **$2,891** — matches `comp.gross_total` (excludes it)

**This $1,000 divergence between the page's own headline and its own Composition foot is SEEN and EXPECTED** — the headline's read source is not yet migrated per SELF-268; recording it as observed-and-expected, not a defect, per the dispatch brief.

## Defects

**None blocking.** No non-blocking defects found either — all seven legs behaved exactly per the ratified conditions, including the one condition (leg B's headline/foot divergence) explicitly called out as an accepted interim state.

## Notes for the record (not defects)

- The "Add a manual account" form requires an **As-of date** field with no default pre-fill and no inline warning about backdating consequences. A walk-through operator without the fixture-clock-trap context could set it to a date before "today" and see YTD Paid / composition read as if the account didn't exist — silently, not as an error. Worth a PM/Frontend judgment call on whether a default of "today" or an inline hint is warranted; not scored against SELF-267's ACs since none of them specify as-of-date UX.
- `supabase migration up` needs the worktree `supabase link`-ed to work directly; the psql fallback path (per the dispatch brief) worked without issue, but the migration's version row required a manual insert into `supabase_migrations.schema_migrations` to keep the local ledger consistent for any later CLI-driven migration commands against this DB.
