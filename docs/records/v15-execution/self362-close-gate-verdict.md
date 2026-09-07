# SELF-362 (P10) close-gate verdict — AC item 14

**sha:** `main` = `ab92187fd3830039eb904371de9c775533cb2f23`, verified via `git rev-parse origin/main` immediately before starting. Independently confirmed `supabase/tests/rls/self362_v15_close_gate.sql` is reachable at this sha (`git cat-file -e ab92187:supabase/tests/rls/self362_v15_close_gate.sql`) before proceeding — this same file was absent at the prior dispatch sha (`eda1179`), the STOP that produced PR #654.

**Steps 1–2 (migrations/scratch-DB premise): carried from the `eda1179` run, not re-derived.** `git diff --stat eda1179 ab92187 -- supabase/migrations/` is empty — PR #654 (feature/self-362) added test files only, the migrations tree is byte-identical to the prior run. Rebuilt `pfin_tmpl` at `ab92187` regardless (`scripts/db-template-build.sh`, 115 migrations, clean apply) as the base for every scratch clone below, and confirmed its `content_sha256` (`cb1284d4...`) matches the `eda1179` build exactly, corroborating the empty diff independently of the diff command alone.

## Step 2 — full pg_prove battery

`pg_prove --ext .pg --ext .sql -r /tests` (the whole `supabase/tests` tree, not `rls/` alone — the merge-gate scope), against a fresh `db-template-clone.sh` clone of `pfin_tmpl` at this sha.

```
Files=110, Tests=2893, 26 wallclock secs
Result: FAIL (pg_prove's own aggregate exit — driven entirely by the two items below)
```

Exactly the two pre-existing, structurally local-only failures, nothing else red:

- **`054_nav_daily_rls.sql`** — subtests 25, 28–29 (Wstat 0, Tests 75, Failed 3). Duplicate-grantor `pfin_etl` cluster-role membership drift (h12/h18) plus h14b's own explicitly-labelled EXPECTED-DIFFERENT-LOCALLY leg (the retained-password local-stack state, ADR-053 reissue / the 2026-08-14 incident record) — cluster state, not this sha's content.
- **`111_audit_log_rls.sql`** — aborts with `ERROR: password or GSSAPI delegated credentials required` inside LEG 8-i's `dblink_connect`, the file's own documented EXPECTED-DIFFERENT-LOCALLY leg (this local Postgres role is not a cluster superuser; dblink refuses trust auth for a non-superuser caller regardless of the connection string). Bad plan: 36 planned, 26 ran — the script aborts mid-file, so everything from LEG 8-i onward (including LEG 10, cited below) does not execute in this local run.

`115_fn_finalize_monthly_report_rls.sql` and `self362_v15_close_gate.sql` both show a clean `ok` with no plan/ran drift note — the `_get()` qualification fix (feature/self-362 @ `01a39c1`..`a115830`) holds.

## Step 3 — standalone close-gate run

```
pg_prove --ext .pg --ext .sql -r /tests/rls/self362_v15_close_gate.sql
Files=1, Tests=6
Result: PASS (6/6, plan/ran match — no drift)
```

## Step 4 — citation walk

Every pgTAP `COMPOSED` citation in `self362_v15_close_gate.sql`'s header was grepped against this sha's actual file content to confirm the named leg still exists under that name (not moved, not renamed):

| AC item(s) | Citation | Confirmed at ab92187 |
|---|---|---|
| AC1/AC2 (A1) | `108_monthly_report_rls.sql` LEG 1, 2 | ✅ present |
| AC1/AC2 (A2) | `109_monthly_report_account_snapshot_rls.sql` LEG 1, 2 | ✅ present |
| AC6 (i–v) | `108` LEG 3, 4, 5, 6, 7 | ✅ present |
| AC7 (CHECK half) | `108` LEG 9 | ✅ present |
| AC1/AC3 (A3) | `110_fn_render_monthly_report_rls.sql` LEG 8, LEG 1, LEG 2 | ✅ present |
| AC1 (A10) | `113`/`114`/`115` LEG 1 each | ✅ present |
| AC3 (standing no-rolbypassrls-EXECUTE, ×5) | `110` LEG 2, `113` LEG 10, `114` LEG 10, `115` LEG 16 | ✅ present |
| AC11 (RT-25) | `113_fn_open_monthly_report_draft_rls.sql` LEG 8 | ✅ present |
| AC9 (AH) | `111_audit_log_rls.sql` LEG 1, 2, 4a, 4d, 6, **10** | ✅ present by grep; **LEG 10 not locally re-executed** — see disclosure below |
| AC1/AC2 (A8) | `106_owner_identification_rls.sql` (R2)/(X1), (M5)/(M7), (S1)–(S6) | ✅ present |
| AC9/RT-11 (P3) | `112_fn_save_monthly_commentary_rls.sql` LEG 1, 2, 3, 4, 6, 6b, 8 | ✅ present |
| AC11 (owner header frozen) | `115` LEG 11 | ✅ present |

All files above are covered by Step 2's full-battery run and showed `ok` there, EXCEPT the one disclosed exception below.

### Non-pgTAP citations — run fresh at this sha

**`workers/etl` pytest** (`uv sync --group test && uv pip install -e . && uv run --no-sync pytest`, per the CI recipe in `etl-ci.yml` — `pyproject.toml` declares no `[build-system]`, so the editable install step is required):

- `tests/test_connection.py::TestLegacySingularGuc` (all 6 parametrized cases — the two-GUC-names-disjoint mechanism, N7) — **6/6 PASS**.
- `tests/test_connection.py::TestImpersonationAssertion::test_reset_role_tears_down_impersonation` and `::test_full_worker_transaction_sequence` — **PASS** (both). ⚠ **Disclosed discrepancy**: the close-gate file's header (line 110) cites the class as `TestImpersonationInvariants`; the real class in `test_connection.py` is `TestImpersonationAssertion`. The cited METHODS exist verbatim and pass under the real class name — this is a citation-text error (wrong class name typed when the file was authored), not a moved or missing test. Flagged for a follow-up doc-only fix to the close-gate file's citation text; not treated as a FAIL because the underlying assertions are real, exist, and are green.
- `tests/test_monthly_report_cron.py::test_open_draft_for_tenant_inserts_one_draft_and_one_audit_row`, `::test_open_draft_for_tenant_audit_row_names_the_resolved_tenant_and_chain`, `::test_audit_row_trigger_source_is_cron_when_the_provenance_guc_is_set`, `::test_audit_row_trigger_source_falls_to_on_demand_when_the_guc_is_forgotten`, `::test_cross_tenant_isolation_tenant_b_never_opens_or_sees_tenant_as_draft`, `::test_reset_role_discipline_teardown_actually_fires`, `::test_reset_role_discipline_a_fresh_tenant_connection_is_unaffected_by_a_prior_one` — **7/7 PASS**, against a live `CREATE DATABASE ... TEMPLATE pfin_tmpl` scratch clone this test module manages itself (confirms the AH/A7/A10 non-pgTAP citations at this exact sha, real Postgres round-trip, not mocked).

**`api` vitest** (`npx vitest run`, full suite — not a hand-picked subset, to also cover whatever "the asOf census leg" names; no literal string `census` exists anywhere in `api/src` outside two unrelated CSS-coverage comments, so the full run is the safer scope than guessing a single file):

```
Test Files  203 passed | 5 skipped (208)
     Tests  2628 passed | 23 skipped (2651)
```

Zero failures. The 5 skipped files are all accounted for: 2 (`nonReAllocation.catGroupOrderEquality`, `nonReAllocation.tenant-isolation`) are gated behind `QA_SELF238_POSTGREST_URL`/`QA_SELF238_JWT_SECRET`, explicitly documented in their own header as expected-skipped in a default CI run (no PostgREST leg today) — unrelated to any P10 citation. The other skipped items are individual `it()` cases whose titles happen to contain the word "skip" describing tested behavior, not unexecuted coverage. Explicitly confirmed present and green within this run: `src/lib/server/pdf/renderClient.test.ts` (27 assertions, all of RT-21 (a)–(g) plus the SD-20 claim-set leg), `pdf/pdf.escaping.test.ts` (4), `MonthlyReportView.cssCoverage.test.ts` (4), `MonthlyReportView.renderContextParity.test.ts` (3).

**`workers/pdf-render` node test** (`node --test`, with `PUPPETEER_EXECUTABLE_PATH` set to a local Chrome-for-Testing binary — unset by default, which silently skips the render battery; re-ran with it set to avoid a false-clean result):

```
tests 26
pass 26
fail 0
```

Confirms, by name, all four AC8 resource-loading-fence citations: `file:// iframe + metadata-IP img` (Sec's exact payload, count=1 per the struck "two aborts" correction), `file://` refused by Chromium's own policy, the non-vacuous `http://` positive control, and `data:` URIs NOT aborted (the discriminating negative). Together with `pdf.escaping.test.ts` (app side, confirmed above), **both halves of the AC8 inert-`<script>` composed citation are green at this sha** (item 5 of the brief).

### Disclosed residual — AC11 pending-queue half's stated premise is stale

The close-gate file's own text for AC11's pending-queue-tenant-scoped half says the P5 UI is "not yet merged to main (verified live, no `api/src/routes` entry... exists at this sha)." At `ab92187`, P5 (`feature/self-357`, PR #649) **has** merged — `api/src/routes/reports/monthly/+page.server.ts` exists and is live. Re-verified the underlying claim directly rather than trusting the stale premise: the file's `load()` and its actions query only `pfin.monthly_report` (`.from('monthly_report')`) and the four already-exhaustively-covered RPCs (`fn_render_monthly_report`, `fn_open_monthly_report_draft`, `fn_regenerate_monthly_report`, `fn_finalize_monthly_report`) — no new DB object (view, function) was introduced for the listing. The close-gate's underlying conclusion ("COMPOSED BY INHERITANCE... through the SAME RLS this gate already exercises exhaustively for A1") **still holds**; only its stated justification ("not yet merged") is now factually outdated. Flagged as a doc-only follow-up, not a coverage gap.

## Step 5 — item AC8 P6 inert-`<script>` (previously OPEN)

Both legs confirmed green at this sha (see the non-pgTAP section above): app side `pdf.escaping.test.ts`, worker side `render.test.js`'s resource-loading fence tests. No longer open.

## Step 6 — item (d), re-measured

Fresh fixture on a fresh scratch clone at `ab92187` (10 accounts, mixed depository/investment/scope/tax_treatment, ×12 months of `account_trans` = 120 rows — same shape as the original 2026-09-06 measurement):

```
fn_render_monthly_report('2026-08-01','2026-08-31') alone:      127.108 ms  (COLD)
fn_open_monthly_report_draft + fn_finalize_monthly_report:
  1.548 ms + 109.389 ms =                                       110.937 ms  (WARM)
```

Consistent with the original measurement (122.391 ms cold / 110.325 ms warm) within normal run-to-run variance. Both comfortably inside the 2000ms p95 budget — roughly 15x–18x margin. No probe leg added, per the original documented reasoning (a hard wall-clock assertion in shared CI is the flaky-exclusion class this discipline refuses). **P4's per-pending-row cost claim re-checked directly against the now-merged `main` tree** (previously a read-only citation against `feature/self-356`): `reports/monthly/+page.server.ts`'s `load()` still issues exactly one `fn_render_monthly_report` RPC per pending (draft) row (confirmed live in the file, `draftRows.map(...)` → `.rpc('fn_render_monthly_report', ...)`, the file's own comment unchanged: "One RPC per pending row: bounded in ordinary use"). Unchanged conclusion: at most ~127ms extra per pending draft on the listing load, structurally capped at one live draft per month by 108's own partial unique index.

## Summary table

| Item | Mechanism | Status |
|---|---|---|
| AC1, AC2 | COMPOSED (108/109/106/112) | PASS |
| AC3 | COMPOSED (110) + non-pgTAP (etl RESET ROLE) | PASS |
| AC4 | NEW (BLOCK AC4, this file) | PASS |
| AC5 | Statement only, no leg | N/A by design |
| AC6 (i–v) | COMPOSED (108) | PASS |
| AC7 | COMPOSED (108) + NEW (BLOCK AC7, this file) | PASS |
| AC8 | COMPOSED (renderClient.test.ts, render.test.js, pdf.escaping.test.ts) | PASS — the previously-OPEN inert-`<script>` item is now confirmed both halves green |
| AC9 | COMPOSED (111) + non-pgTAP (etl cron) | PASS, with the LEG 10 / class-name disclosure above |
| AC10 | non-pgTAP (etl connection/cron) | PASS |
| AC11 | COMPOSED (113, 115) + inheritance (P5, disclosure above) | PASS |
| Item (d) | MEASUREMENT, not a graded leg | Recorded, well within budget |

## Verdict

**V1.5 close-gate: PASS at `ab92187fd3830039eb904371de9c775533cb2f23`.**

Two disclosed residuals, neither blocking: (1) `self362_v15_close_gate.sql`'s citation of `TestImpersonationInvariants` should read `TestImpersonationAssertion` (the cited methods are real and green under the correct name); (2) the same file's AC11 pending-queue prose ("P5 not yet merged") is stale now that P5 is on `main` — the underlying RLS-inheritance conclusion was re-verified directly and still holds. Both are doc-only fixes for a follow-up commit to the close-gate file, not gaps in coverage.

---

## Addendum — Sec ratification (2026-09-07; `self362-close-gate-ratification.md`)

RATIFIED at `main` = `ab92187` (md5 of this file as read by Sec: `b9df4dbbbc09f230d26b408b23dd868d`, computed independently). The one grep-only citation — `111` LEG 10 (AC9), unexecuted locally because `111` aborts at LEG 8-i's EXPECTED-DIFFERENT-LOCALLY dblink leg (36 planned / 26 ran; the 2893-vs-2903 count difference is exactly those ten legs) — is discharged by CI evidence: run 34142070004 on `01a39c1` reported Files=110, Tests=2903, Result: PASS with zero `not ok`, which includes all 36 of `111`'s legs; `01a39c1..a115830` changes zero executable lines (two-sided filter; `plan(54)`/54-assertion parity) and `a115830..ab92187` is a merge commit only, so the evidence carries to `ab92187` by executable identity. The two doc-only residuals disclosed above are corrected in the close-gate file on `main` by PR #655.
