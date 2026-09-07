# Sec-B clearance read — VETO-1 + batteries 112–115

Frozen shas graded: `feature/self-345-qa @ 57f3952` (against unit `feature/self-345 @ 72c3e5c`)
and `feature/self-355-db-qa @ 365a9b9` (base `feature/self-355-db @ 924085d`).
Read-only from refs (`git show <ref>:<path>`). Nothing was applied and nothing was executed —
no clean-apply, no `pg_prove`. Every verdict below is a source + catalog-text grade.

---

## VETO-1 — CLEARS at `57f3952`

The required set holds, leg by leg (`git show 57f3952:supabase/tests/rls/111_audit_log_rls.sql`):

| requirement | where | verdict |
|---|---|---|
| 7d counter-advance, aborted WRITING subxact between write and emit | L361–398, `(7d-T1)` | present, `lives_ok` |
| 7d matched NON-writing abort control, asserted as a pair | L399–403, `(7d-T2)` | present, asserted |
| 7e (i) explicit `SAVEPOINT`/`RELEASE` sub-commit | L412–417 | present |
| 7e (ii) plpgsql exception block exiting normally (113's real path) | L419–431 | present |
| 7f disclosure, NOT a leg | L434–445 | comment only; zero assertions in the block |
| 7g exactly-one executable `from pfin.monthly_report`, comment-stripped, case-insensitive | L466–474 | `count(*) = 1` over `regexp_matches(regexp_replace(prosrc,'--[^\n]*','','g'), 'from\s+pfin\.monthly_report','gi')` |
| 7g inversion-proven on three bodies | L455–465 (comment) | claimed by author; not re-executed by me |
| invented-surface leg re-aimed to the C2 dispatch `else` | L230–236, `(4a)`, `:'m_no_binding'` | matches migration L890 |
| owner-path direct INSERT reaching `audit_log_surface_name_vocab` | L248–262, `(4d)` | present |
| every `prosrc` assertion comment-stripped | only two exist: `(7g)` L470, `(9)` L566 | both stripped + `~*`/`'gi'` |

`select plan(34)` vs 34 top-level pgTAP assertion calls — matched.

Fail-closed check on both `prosrc` legs: a NULL `prosrc` (PG14+ `BEGIN ATOMIC`) yields
`regexp_replace → NULL`, `regexp_matches(NULL,…) → 0 rows`, `count(*) = 0 ≠ 1` → RED.
Same for the migration's apply-time `do $watch$` (111 L946–967) via `and m is not null`.
Both fail closed. This is the OPPOSITE direction from the C3 fence's NULL case and is correct here.

Non-objection: I considered whether an unqualified `from monthly_report` split would evade
7g's schema-qualified pattern. It cannot — `fn_emit_audit_log` carries `set search_path = ''`
(111 L683), so an unqualified read does not resolve at all. **I do NOT require widening the pattern.**

---

## FLAG-1 — `DECISIONS.md` ADR-011 D9 amendment names the DROPPED six-argument signature

`git show 72c3e5c:DECISIONS.md`, line **5328**:

> …**is realized as `pfin.fn_emit_audit_log(text, text, text, date, text, bigint)` at `111`**…

That is **six** arguments. The shipped function is **five**:
`(text, text, date, text, bigint)` — 111 L674–680, and the `revoke`/`grant`/`comment on`
at L909/910/911/968 all use the five-arg form. The six-arg form is the signature C1's
`drop function if exists` at 111 L672 exists to **remove**. The ADR names a function that
does not exist after apply, in the amendment that records the DEFINER-allowlist realization.

Single occurrence in the tree — measured:
`for f in DECISIONS.md docs/ARCH/index.html docs/SECURITY/index.html supabase/migrations/111_audit_log.sql; do git show 72c3e5c:$f | grep -n 'fn_emit_audit_log('; done`
→ one hit outside 111 itself.

**Commit-ready fix (Architect's pen — one token):** in that sentence replace
`pfin.fn_emit_audit_log(text, text, text, date, text, bigint)`
with
`pfin.fn_emit_audit_log(text, text, date, text, bigint)`.
Nothing else in the amendment changes.

---

## FLAG-2 — 111's `comment on function` documents the ruled-UNSOUND predicate as the shipped one

`git show 72c3e5c:supabase/migrations/111_audit_log.sql`, L968–969, inside the
`comment on function` string:

> ⚠ THE TRANSACTION TEST IS A SNAPSHOT-VISIBILITY TEST, NOT AN xid EQUALITY TEST, AND THAT IS A MEASURED DEFECT AVOIDED: …

The shipped predicate is `pg_xact_status(r.xmin::text::xid8) = 'in progress'` (111 L841).
It is a commit-log test and explicitly not a snapshot test. Three sources in the same tree
contradict this sentence:

- the function's own inline comment (c), 111 L770: *"THE CLOG TEST, NOT AN xid EQUALITY TEST AND NOT A SNAPSHOT TEST"*;
- 111 L779–803, which argues `pg_visible_in_snapshot` **IS ALSO WRONG**;
- ADR-068 at `git show 72c3e5c:DECISIONS.md` L180: *"THE TRANSACTION TEST IS A COMMIT-LOG TEST — `pg_xact_status(xmin) = 'in progress'` — AND IT REPLACED A SNAPSHOT TEST THAT WAS ITSELF DEFECTIVE."*

The sentence's *negative* half (rejecting xid equality) is still true. Its *positive* half
names the expression E49/E50 ruled unsound, and it sits in the one place a future maintainer
consults before touching this predicate — so it actively licenses re-introducing the defect.
This is the same class C4 was written to close; the E50 predicate replacement created a third
instance after C4's two were fixed. No battery leg observes the function comment.

**Commit-ready replacement (Architect's pen).** Replace the whole sentence above, up to and
including *"…not wrapped in an exception block."*, with the following. It sits inside a SQL
single-quoted string, so every apostrophe is doubled; keep it that way on paste.

> ⚠ THE TRANSACTION TEST IS A COMMIT-LOG TEST — `pg_xact_status(xmin::text::xid8) = ''in progress''` — AND IT REPLACED A SNAPSHOT-VISIBILITY TEST THAT WAS ITSELF MEASURED UNSOUND. TWO WRONG EXPRESSIONS WERE MEASURED OUT, AND NEITHER FAILURE IS VISIBLE TO AN ORDINARY BATTERY LEG. (i) xid EQUALITY: fn_open_monthly_report_draft INSERTs inside a plpgsql exception block, i.e. a SUBTRANSACTION with its own xid, while pg_current_xact_id_if_assigned() returns the TOP-LEVEL xid — measured 2026-09-05 as top 1664121 against row xmin 1664122, equality FALSE — so a naive equality check would refuse the very path C2 exists to permit while passing every test whose INSERT was not wrapped in an exception block. (ii) SNAPSHOT VISIBILITY: `not pg_visible_in_snapshot(xmin, pg_current_snapshot())` depends on latestCompletedXid, which is CLUSTER-WIDE — ANY xid completing anywhere between the subject write and this call advances snapshot xmax past our own row''s xid, which is never in our own xip, so our own write reads as already-visible and the emit falsely refuses, rolling the whole generation back non-deterministically on any non-idle database. pg_xact_status consults the commit log for that ONE xid and depends on nothing cluster-wide. ⚠ ANY FUTURE REPLACEMENT OF THIS EXPRESSION MUST NOT DEPEND ON latestCompletedXid, SNAPSHOT xmax, OR ANY OTHER CLUSTER-WIDE COUNTER — that is the disqualifier both prior attempts failed.

---

## FLAG-3 — C2 guard (b) has no observer; `\set m_bad_subject` is declared and never used

111 L760–765 (guard (b)):

```
if p_subject_table is distinct from 'pfin.monthly_report' or p_subject_id is null then
  raise exception 'pfin.fn_emit_audit_log refused: surface monthly_report_generation requires p_subject_table = ''pfin.monthly_report'' and a non-null p_subject_id. …'
```

`p_subject_table` is written **verbatim** into the row (111 L896–902 — the INSERT passes
`p_subject_table`, not a literal). Guard (b) is therefore the only thing preventing an
otherwise-fully-valid emit — real, own, same-transaction `report_id` — from carrying a
**forged locator** naming a table the write never touched. That is the locator-forgery half
of the original VETO-1 finding.

The battery declares `\set m_bad_subject '%requires p_subject_table%'` at
`57f3952:supabase/tests/rls/111_audit_log_rls.sql` **L145** and never references it —
measured: `git show 57f3952:… | grep -n m_bad_subject` returns exactly one line, the `\set`.
That unused variable is the tell that a leg was lost across the re-leg. Delete guard (b)
today and the battery stays green at 34/34.

**Commit-ready legs (QA's pen). `select plan(34)` → `select plan(36)`.** Insert after leg 4d
(after L262), before the LEG 5 banner:

```sql
-- =====================================================================
-- LEG 4e/4f (Sec) — C2 GUARD (b) HAS NO OTHER OBSERVER. p_subject_table is
-- written VERBATIM into the row, so this guard is the only thing standing
-- between a caller holding EXECUTE and a FORGED LOCATOR on an emit that is
-- valid in every other respect: real subject row, own tenant, this
-- transaction. The guard is a DISJUNCTION, so both branches are asserted —
-- one leg alone leaves the other unwatched.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2028-01-01', '2028-01-31') returning report_id as leg4e_subj \gset
select throws_like(
  format($$ select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2028-01-31', 'pfin.account', %s) $$, :leg4e_subj),
  :'m_bad_subject',
  '(4e) THE LEG: a REAL, OWN, same-transaction report_id submitted with a FORGED p_subject_table is refused by C2 guard (b) — the column is written verbatim into the row, so without this guard an otherwise-valid emit records a locator pointing at a table the write never touched'
);
select throws_like(
  $$ select pfin.fn_emit_audit_log('monthly_report_generation', 'impersonated session: request.jwt.claims.sub', '2028-01-31', 'pfin.monthly_report', null) $$,
  :'m_bad_subject',
  '(4f) the NULL p_subject_id half of the SAME disjunctive guard, asserted separately'
);
select set_config('role', 'postgres', true);
```

Reachability checked against the body's own order: tenant → surface → chain →
`p_surface_name = 'monthly_report_generation'` → (a) xid assigned (`plan()` already assigned
one) → (b) fires. Neither leg reaches (c), so neither depends on the C2 predicate.

---

## FLAG-4 — "a payload version bump is a Sec-review event" is a convention with no mechanism

`12ccd2f` records, in 115's migration and in the battery's 14i disclosure, that the four
FLAG-7 guards do not catch *accounts relocated to an additional sibling key while `groups`
stays a legitimate `'[]'`* — indistinguishable from 14g's zero-account tenant, and the report
freezes permanently with an empty child set. A `payload_schema_version` pin would catch it and
was deliberately declined so the bump stays a **Sec-review event**.

I accept the reasoning and I do NOT require the pin inside `115`. What I flag is that the
routing has no carrier. Measured:

- `git grep -n payload_schema_version 365a9b9 -- supabase/tests` — every hit is a fixture
  assignment or 115 leg 13, which deliberately compares the column to the payload's own field
  rather than to a constant. **Zero pins.**
- `grep -rn fence .github/required-contexts.tsv` and `grep -rln payload_schema_version .github/workflows/`
  — no fence, no required context.

So a bump lands with nothing that stops, labels, or notifies. Options, in my order:

- **A — battery-side pin (cheapest, my preference).** One leg in the 110 battery asserting the
  version constant, comment-stripped, against `fn_render_monthly_report`'s installed body. A bump
  REDs a test rather than breaking production, and the forced edit lands in a file whose reviewer
  is QA + Sec. Cost: one leg, one plan bump. Does not touch 115, so the declined tradeoff is preserved.
- **B — CI fence.** `fence-payload-version` in `security-scan.yml` + a `required-contexts.tsv` row,
  failing when the literal changes without a `joint-review:sec` label. Strongest routing, highest
  build cost, and it needs a golden fixture to not be theater.
- **C — accept and book.** BACKLOG item naming the residual. Cheapest now; it is the option that
  rots, because nothing observes it.

---

## Merge-order conditions (both are verifiable, not advisory)

**M-1 — the C3 CI half is not in `main`.** Measured: `git merge-base --is-ancestor f788788 origin/main`
→ not an ancestor; `git branch -r --contains f788788` → `origin/feature/self-345-devops` only.
`grep -rln set_config .github/workflows/` → no hits; `.github/required-contexts.tsv` has no
`fence-set-config` row. E46 recorded C3 as a **two-layer** watcher and recorded Sec's fork: if the
CI half cannot be built this wave, C1 cannot carry `'cron'` alone and the trigger replaces it. The
CI half WAS built and is GREEN at `f788788` — it is simply not in the tree yet. So #636 merging
alone lands C1 with one of its two layers absent. The devops branch must merge in the same wave.

**M-2 — `feature/self-355-db-qa` carries a stale `111` battery that would OVERWRITE the clearance evidence.**
Measured at `365a9b9` and at the current tip `41eede8`: `supabase/tests/rls/111_audit_log_rls.sql`
is `select plan(19)` with **zero** `pg_xact_status` references, against `57f3952`'s 665-line,
`plan(34)` version. Merging 355-db-qa after #636 without dropping that file silently deletes the
entire VETO-1 clearance artifact and leaves a battery that is RED against the shipped function.
**Gate:** before merging 355-db-qa, `git diff origin/main <tip> -- supabase/tests/rls/111_audit_log_rls.sql`
must be **empty**. Not "QA is rebasing" — the empty diff.

---

## Frozen-sha drift on surface (2)

Brief froze `365a9b9`; `origin/feature/self-355-db-qa` is now `41eede8`. `365a9b9` is NOT an
ancestor of `41eede8` — merge-base is `924085d`, so `41eede8` is the rebase onto `12ccd2f`
(comment-only over `924085d`) plus one commit. I graded `365a9b9` as instructed and read the
delta: `git diff 365a9b9 41eede8 -- supabase/tests` is **one file, +11/−1**, the 14i disclosure
comment in the 115 battery. No leg, `plan(53)` unchanged. **The verdict carries to `41eede8`.**

---

## Stated non-objections

- **Lock 12 `service_role`-bypass mod, and the parent re-tenant fence, are covered in `109`'s
  battery, not `115`'s** — `72c3e5c:supabase/tests/rls/109_…_rls.sql` legs (4b)/(5b) open a
  temporary `service_role` grant so the TRIGGER is what refuses, and (7a) refuses re-tenanting the
  parent while children exist. `115`'s 14e runs owner-path only. **I do NOT require 115 to duplicate them.**
- **I do NOT require a cross-tenant child leg in `115`.** D3 label #4's fence
  (`fn_monthly_report_account_snapshot_matched_account`) has its observer at `109` leg (3b), and
  115's writer composes from the caller's own RLS-scoped payload, so the cross-tenant shape is not
  reachable through it.
- **I do NOT require a behavioural leg for 7f.** Another session's uncommitted row is excluded by
  MVCC, not by an assertion; it is unbuildable single-connection and the file says so instead of
  implying coverage. 14i takes the same shape and is equally correct.
- **The `aal2` `passkey` arm still has no behavioural observer** across 112/113/114/115 — the legs
  pin the `totp` arm. This is the standing family-wide QA item, **not** a condition on this surface.
- **Commentary text → rendered document.** `git grep -n '@html' -- api/src workers` returns one hit,
  the TOTP QR SVG at `settings/security/+page.svelte:176`, server-sourced. No user commentary reaches
  a raw-HTML interpolation. **No finding.** I did not re-review the PDF worker's own rendering on
  this pass — that is A5's surface and it is already GREEN.
- **The §10 catalogued ledger and the CI-fenced RT set are untouched.** ADR-011 D4 read live: three
  catalogued instances, RT-22 first / RT-26 second / RT-27 third, Path B, no count carried into the
  branch. `grep -rhoE 'RT-[0-9]{2}' .github/workflows/` → RT-05 RT-22 RT-26 RT-27 RT-30. They overlap
  on three and **are different sets; they must not be reconciled.** 111 L247–252 states the
  Decision-9-is-not-a-§10-event de-conflation correctly.
- **D9 allowlist:** 111 realizes the reserved, previously-unauthored general audit-log insert entry.
  The committed allowlist does not change size; the authored-in-migrations count moves by one. No
  size stated here — read D9's body live.
- **D3 family:** read live from the branch (`72c3e5c:DECISIONS.md` L5081/5085/5086/5101). #3 and #4
  are DDL-realized at `108`/`109` and no label is DDL-deferred any longer; `111` and `115` allocate
  nothing. `audit_log.subject_id` is correctly argued out as a polymorphic locator rather than a
  family member, with its revival condition stated.

---

## My own errors and limits, stated here rather than in a follow-up

- I initially treated an unqualified `from monthly_report` as a 7g evasion before reading
  `set search_path = ''` two lines above the function body. Corrected before it left this file;
  it is recorded as a non-objection above rather than a finding.
- I executed nothing. Every "measured" above is a `git show` / `git grep` / `git merge-base` over a
  ref, named at the point of the claim. QA's inversion proofs for 7g and 7d-T1, and Architect's
  clean-apply, stand **unverified by me**.
