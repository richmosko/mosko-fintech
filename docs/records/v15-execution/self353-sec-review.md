# Sec joint-review — PR #633 / SELF-353 (A9) — commit-ready text + memory delta

Reviewed at frozen sha `5df28c2`. PR head at review time `defca86`; the delta is a
`main` merge only (measured: `gh api compare 5df28c2...defca86` → 5 commits, 14 files,
all `api/src/**` + `docs/records/v15-execution/self361-walk.md`; **none of the four
SELF-353 halves**). Verdict transfers to `defca86`.

---

## F-1 — Architect — `DECISIONS.md`, ADR-011 Decision 3, SELF-353 fold-in consequence **(g)**

Current final sentence is factually wrong (copied from the SELF-259 fold-in): it names
migration `101` and a count of two. `107` authors FOUR functions.

**Replace, verbatim:**

> The SECURITY DEFINER allowlist is unchanged: all four functions authored at `107` are `SECURITY INVOKER` with `set search_path = ''`.

(Splice boundary: this replaces only the sentence beginning `The SECURITY DEFINER
allowlist is unchanged:` and ending `both `101` functions are INVOKER.` — everything
before it in bullet (g), through `...and none is reconciled against another.`, stays
byte-for-byte as authored.)

---

## F-2 — QA — `supabase/tests/rls/107_nav_component_daily_rls.sql`, the `(R0)` assertion description

The description currently instructs a future repairer to *"widen the grant"* — the exact
remediation ruling E10 rejected and that `054`'s own header records as
Sec-joint-review-mandatory. When (R0) reds, its message must not name the forbidden fix.

**Replace the third argument of the `(R0)` `throws_like(...)` call, verbatim:**

> '(R0) PERMANENT KNOWN-GAP WATCHER: the `RETURNING nav_id` form of the scalar INSERT is REJECTED for service_role — 054''s column grant is (users_id, nav_date) only, and RETURNING needs SELECT on every returned column even for a just-inserted row. RULING E10: the signal is ROW_COUNT, and 054''s grant is NOT widened. ⚠ IF THIS LEG REDS, the grant was widened — that is a Sec-joint-review-mandatory change per 054''s own header, not a repair to make here'

Also update the `-- (R0)` comment block above it: strike the *"Two remediations,
Architect's call: (a) widen the 054 grant ... or (b) ..."* sentence and state that E10
ruled (b) and that (a) is forbidden without Sec joint review.

---

## F-3 — QA — same file, the `R` section header (line 136 at `5df28c2`)

Reads `--   scalar INSERT first (RETURNING nav_id), then the multi-row leaf INSERT with the`.
Stale against E10 and against this file's own `pg_temp.qa_scalar_insert` helper.

**Replace that one line, verbatim:**

```
--   scalar INSERT first (ROW_COUNT signal, NOT `returning nav_id` — ruling E10; see (R0)),
```

---

## F-4 — QA — no watcher on `nav_component_daily_value_finite`

`107` names the CHECK as FAIL-SURFACE (3) *"MUST raise; a poisoned leaf is worse than a
missing day"*, and its `comment on constraint` asserts NaN **and** +Infinity **and**
-Infinity are all barred. Measured: `grep -i 'finite' supabase/tests/rls/107_nav_component_daily_rls.sql`
→ zero matches. Three `throws_like` legs (one per barred value) plus one `lives_ok`
positive control on an ordinary numeric. Bump `plan(47)` accordingly.

## F-5 — QA — the #19 unresolvable raise leg has no watcher

The ADR-011 D3 **#19** entry claims **two raise legs (unresolvable / cross-tenant)**.
`(M2)` watches cross-tenant only. Add a leg inserting a *nonexistent* `account_id` under
a correctly-bound GUC and assert `:'m_matched'` — which additionally pins that #19 raises
**before** the FK does.

## F-6 — DevOps + Backend — the five new worker tests never run in CI

`workers/etl/tests/test_nav_component_write.py:44` is `pytestmark = pytest.mark.integration`;
`.github/workflows/etl-ci.yml` runs `pytest -m unit` (line 163) and `pytest -m pgtest`
(line 237) only. The module fixture additionally skips on `docker exec <container>`
unavailability. Pre-existing class — `test_nav_backfill_write.py:53` carries the same
marker. Not a merge blocker: the security-load-bearing DB-layer property (same-transaction
rollback) is covered by the pgTAP battery's `(F2a)`/`(F2b)` in `db-tests.yml`. Track as a
lane gap, not as a SELF-353 defect.

---

## Memory delta (could not be written into the shared checkout; coordinator to place)

`.claude/agent-memory/security-engineer/reference_decision3_family_11_labels.md` is stale
the moment #633 merges. Current body says *18 non-contiguous labels / 15 DDL-realized /
#18 allocated at `101` (SELF-259) / next takes #19*.

**Post-merge state, read live from ADR-011 Decision 3 body:** nineteen labeled (#1–#19),
**sixteen DDL-realized**; #5 still DROPPED at `048`; #3 + #4 still DDL-deferred;
**#19 allocated at `107` (SELF-353, 2026-09-05)**. ⚠ **The forward pointer's numeral is
now DROPPED at every forward-claim site rather than advanced** — a future author finds
NO number named and must read the numbered list. The memory line must therefore stop
naming a "next" label at all.

⚠ `feature/self-345` (`9fc6d98`, unmerged) realizes #3/#4 and will move the DDL-realized
figure again. Do not pre-count it.
