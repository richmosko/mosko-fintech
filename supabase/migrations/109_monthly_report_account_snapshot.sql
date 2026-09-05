-- ============================================================================
-- Migration: pfin.monthly_report_account_snapshot — the Lock 12 per-account CHILD
--   of pfin.monthly_report (`108`). Phase 6 Build Loop, Linear SELF-346 / A2.
--   Realizes [ADR-011](DECISIONS.md#adr-011) Decision 16 / Lock 12 and the V1.5
--   pre-flight rulings R1 / R5. apply-migration procedure applied.
--   JOINT-REVIEW-MANDATORY (Sec veto surface). ⚠ Reviewed as ONE design unit with
--   `108` (A1) and `110`/`111` (A3 + the R7 audit helper) under ONE Sec
--   joint-review — R1 rider 8, R13 step 6. Do not review this file alone.
--
-- ----------------------------------------------------------------------------
-- ⚠ WHAT THIS TABLE IS FOR, AND THE RULE THAT DECIDES ITS COLUMN SET. R1 (A)
--   settles the role: **the child is the per-account QUERYABLE INDEX over the frozen
--   artifact, not a second copy of it.** The artifact is `108`'s `rendered_payload`.
--   That rule decides every column: this table carries what a QUERY must answer on
--   — per-account facts the JSONB payload cannot be filtered or joined on — and
--   **nothing that exists only to be read back whole**, because reading it back
--   whole is what the payload is for.
--   THE TEST TO APPLY BEFORE ADDING A COLUMN HERE: *would a caller FILTER, JOIN or
--   GROUP on it?* If the answer is "no, they would display it", it belongs in the
--   payload and adding it here creates a second copy that can drift from the frozen
--   one — on a table whose rows are immutable, so the drift would be permanent.
--
-- ----------------------------------------------------------------------------
-- ⚠⚠ EVERY COLUMN BEYOND LOCK 12's LOCKED THREE IS A **LOCK 12 AMENDMENT**,
--   RATIFIED IN THE CONSOLIDATED ADR THAT SHIPS IN THIS PR — NOT AN IMPLEMENTATION
--   DETAIL (R1 rider 3; Architect F-7). The amendment ENUMERATES the widened set;
--   this file does not widen it by writing DDL and calling it detail. The
--   enumeration is authored at this migration and lands in the same PR.
--
--   LOCK 12's LOCKED THREE, verbatim: `(monthly_report_id, account_id,
--     acct_name_at_generation)`.
--   THE AMENDED SET ADDS EXACTLY ONE PAYLOAD COLUMN — `tax_treatment_at_generation`
--     — plus a surrogate key and a timestamp:
--       · `snapshot_id`   — surrogate PK. Structural, not a report fact.
--       · `created_at`    — insert instant. Structural, not a report fact.
--       · `tax_treatment_at_generation` — the ONE substantive widening. It passes
--         the queryable-index test: PRD §2.6.6 / the P10 battery filter reports
--         BY TAX TREATMENT (the tri-axis leg exists only where `tax_treatment`
--         does), and a JSONB payload cannot be filtered on. `pfin.account.tax_treatment`
--         is real (`003`, `text not null`). It is a **COPY OF THE ACCOUNT'S VALUE AT
--         GENERATION TIME, NAMED AS SUCH** — the account's live value may since have
--         changed, and this column deliberately does not follow it.
--
--   ⚠ `scope` IS DROPPED (R1 rider 3), and it was already unavailable as a typed
--     column: **`pfin.scope` DOES NOT EXIST as a type at this sha**;
--     `pfin.account.scope` is `text not null`, a free-text
--     [ADR-004](DECISIONS.md#adr-004) Decision B label. Carrying it would have added
--     a free-text axis nothing filters on.
--
--   COLUMNS DELIBERATELY **NOT** CARRIED, recorded so their absence is not later
--   read as an oversight — each fails the queryable-index test in the same way:
--     · any per-account MONETARY VALUE (market value, unrealized G/L, allocation
--       percentage). These are displayed, not filtered, and they live in the frozen
--       payload. Copying them here would create a SECOND FROZEN COPY of a money
--       figure on an immutable table — two rows that must agree forever, with no
--       mechanism to make them agree. **That is the exact shape ADR-054 Decision 5
--       declines for the Σ(leaves) identity, applied one table over.**
--     · `account_type`. It is the §2.1.5 grouping key, and the payload already
--       groups by it. Nothing in §2.6 filters report rows by account type.
--     · `currency`, `acct_number`, `linked_source_id`. No §2.6 query keys on them,
--       and `acct_number` is an SD-15 masked-rendering surface that has no business
--       being copied onto a report artifact at all.
--
-- ----------------------------------------------------------------------------
-- ⚠ ADR-011 DECISION 3 — PER-COLUMN DISPOSITION. This migration **REALIZES** label
--   #4 and **ALLOCATES NOTHING** (R5 consequences). Decision 3's body read LIVE at
--   authoring (2026-09-05). **NO COUNT IS CARRIED IN THIS FILE.** This table has TWO
--   FK-shaped columns and Decision 3's rule is written over *any* of them, so both
--   get an explicit disposition — Sec F-1 requires the label and the fence-pattern
--   class named per column.
--
--   · `account_id` → `pfin.account(account_id)` — **CANONICAL LABEL #4**, carried
--     UNREALIZED since ADR-011 authoring and DDL-realized here. Matched-tenant
--     BEFORE INSERT trigger. BEFORE INSERT **only**: this table is immutable
--     audit-class, so UPDATE and DELETE are trigger-blocked and an UPDATE fence
--     would be dead code (the `019` / `044` / `057` / `107` immutable-audit shape,
--     as distinct from the `012` / `022` / `074` / `101` mutable-settings shape,
--     which fences INSERT OR UPDATE because a repoint path exists there).
--     ⚠⚠ **FINDING, ROUTED TO SEC — THE FENCE-PATTERN CLASS IS NOT THE `P1` LABEL
--     #4's ENTRY NAMES; IT IS `CR`.** Decision 3 defines **P1** as *"referring row
--     has its own `users_id`; `new.users_id` equality, 012-shape"* and **CR** as
--     *"referring row has no own `users_id`; the fence JOINs the account chain to
--     resolve the owning tenant."* **THIS CHILD HAS NO `users_id` COLUMN** — Lock 12
--     locks three columns and none of them is a tenant anchor, and A2's own AC
--     mandates *"RLS via the parent FK chain"*, which presupposes exactly that. So
--     the fence must chain-resolve the tenant through `monthly_report_id →
--     pfin.monthly_report.users_id`, which is CR's mechanism by CR's own definition.
--     The entry's `P1` was written at ADR-011 authoring, before Lock 12's column set
--     was realized. **The instance, its label and its target are unchanged; the
--     CLASS is corrected by an AMENDMENT beneath the entry in this same PR** — never
--     by editing the dated entry, which records what was believed then.
--     ⚠ THE OTHER HALF OF INSTANCE #4 IS NOT BUILT HERE. Label #4's own text names a
--     **parent-immutability extension fencing `monthly_report.users_id` UPDATE
--     post-creation** as part of this instance. That half is built at `108`
--     (`fn_monthly_report_immutability`, which refuses `users_id` and `target_month`
--     in EVERY state including draft) and is **verified from this side**: without
--     it, re-tenanting a parent would silently move every child row to a new tenant
--     with no fence firing, because this child's tenant is *defined* by its parent.
--
--   · `monthly_report_id` → `pfin.monthly_report(report_id)` — **NOT a Decision 3
--     instance, ARGUED OUT, with the reasoning recorded here as R5's consequences
--     require.** This resolves the `⟨OPEN⟩` the sitting left to Architect: the
--     sitting ruled the OBLIGATION to dispose of this FK explicitly, not the answer.
--     **THE ANSWER IS: NOT A FAMILY MEMBER**, and the reasoning is structural rather
--     than a judgement about risk —
--       (1) **It is this table's SOLE TENANT ANCHOR.** The child carries no
--           `users_id`; its tenant IS whatever the parent's is. There is therefore
--           no second tenant fact for a matched-tenant fence to compare against, and
--           a fence over it could only ever compare the parent's tenant with itself.
--           That is *the leg that cannot fail* ([ADR-062](DECISIONS.md#adr-062)
--           Decision 2), and it is the same disposition `024` / `054` / `107` record
--           for their `users_id`, and the same one the family already applies to
--           `pfin.account_trans.account_id` — which is that table's anchor and is
--           NOT a labelled instance, while its self-FK `replaces_trans_id` (label
--           #2) is.
--       (2) **The chain-attack Decision 3 exists to fence runs the OTHER WAY here.**
--           Decision 3's hazard is a row REFERENCING a foreign row. This column
--           cannot reference a foreign parent usefully: RLS on this table is
--           evaluated THROUGH this very column, so a row pointed at another tenant's
--           report is invisible to both tenants — it fails closed rather than
--           leaking. **The genuine hazard is the parent MOVING under the child, and
--           that is fenced at `108`, not here.**
--     ⚠ **WHERE THIS DISPOSITION BORROWS ITS SUFFICIENCY, NAMED because it comes
--       from outside this file:** argument (1) holds only while this table has no
--       `users_id` of its own, and argument (2) holds only while
--       `monthly_report.users_id` is immutable. **Give this child a `users_id`
--       column and `monthly_report_id` BECOMES a Decision 3 instance requiring a
--       newly-allocated label** — because there would then be two tenant facts that
--       can disagree, which is precisely the R4 grain ruling that made `#18` an
--       instance at `101`. Whoever adds one must re-derive this paragraph rather
--       than re-read it.
--     ⚠ **NO LABEL IS ALLOCATED HERE, AND NONE IS RESERVED.** Decision 18's
--       amendment bars drafting a label in advance; a label is allocated AT the
--       migration that realizes it or not at all.
--
-- ----------------------------------------------------------------------------
-- LOCK 12's THREE V1-SHIP-BLOCK MODS, IN FULL, AND WHERE EACH LIVES:
--   (i)   matched-tenant trigger on `account_id` — **this file**
--         (`fn_monthly_report_account_snapshot_matched_account`).
--   (ii)  parent `users_id` + `target_month` immutability — **`108`**
--         (`fn_monthly_report_immutability`), verified from this side; see the
--         Decision 3 block above for why it is half of instance #4 rather than a
--         separate control.
--   (iii) **`service_role` bypass DB-trigger on the child** — **this file**, and it
--         is NOT a separate trigger: it is the fact that
--         `fn_monthly_report_account_snapshot_immutability` carries **no role test
--         at all**, so it binds `service_role` exactly as it binds `authenticated`.
--         `service_role` carries `rolbypassrls`, so on this surface the trigger is
--         its ONLY applicable layer — there is no RLS behind it to catch a miss.
--         ⚠ Stated explicitly because "a service_role bypass trigger" reads like a
--         named object, and a reviewer looking for one and not finding it could
--         reasonably conclude mod (iii) was skipped. **The absence of a role test IS
--         the mod.** ⚠ And `108` now carries its equivalent, so the pair is
--         symmetric — **a child fenced against a role its parent is not is a fence
--         with a door beside it.**
--
-- ----------------------------------------------------------------------------
-- DECISION 2 ON THIS SURFACE — the **IMMUTABLE** half, and only that half (R4
--   ratifies the split; `108` item 5). A snapshot row is a captured per-account fact
--   about a month that has closed. **There is no correction-by-INSERT-new-version
--   path on this table and there is not meant to be:** a correction is made by
--   REGENERATING THE REPORT — a new parent row with its own children — which is the
--   INSERT-new-version half operating one level up, where the version identity
--   (`generation_status`) actually lives. Adding a version column here would create
--   a second, finer versioning axis that nothing reads and that could disagree with
--   the parent's.
--   Rows are read-only post-write: UPDATE and DELETE are blocked by trigger for ALL
--   roles, and TRUNCATE by a statement-level fence.
--   ⚠ INTERACTION WITH `108`'s DRAFT-DELETE BRANCH, stated so it is not discovered:
--   `108`'s trigger permits deleting a `draft` parent, and the FK below is ON DELETE
--   RESTRICT, so **a draft parent that has children cannot be deleted.** That is
--   coherent rather than accidental — children are written at finalization, so a
--   genuine draft has none; and if one somehow did, silently discarding captured
--   rows is the outcome RESTRICT exists to prevent. Both paths are dormant today
--   (no role holds a DELETE grant on either table).
--
-- ----------------------------------------------------------------------------
-- ON DELETE RESTRICT ON BOTH FKs — Lock 12 verbatim for the parent (*"not
--   CASCADE"*), and the same choice for `account_id` on the `057` / `107` reasoning.
--   On an append-only table a CASCADE is **the one deletion path that bypasses the
--   immutability fences**: the fences see UPDATE and DELETE issued against this
--   table, and a cascade from elsewhere would remove rows without any of them
--   raising. RESTRICT converts that into a loud refusal at the other end.
--
-- ----------------------------------------------------------------------------
-- RLS — VIA THE PARENT FK CHAIN (`090` standard: USING **and** WITH CHECK per verb;
--   plus the [ADR-029](DECISIONS.md#adr-029) / `025` aal2 clause per Sec F-9).
--   ⚠ **THE JOIN KEYS ON THE SURROGATE `monthly_report_id`, NEVER ON A
--   `(users_id, target_month)` VALUE PAIR** (AC 5, verbatim). The direction of
--   failure is the whole reason: a **surrogate-id join fails CLOSED** under an RLS
--   regression — if the parent row is not visible, the `exists` is false and the
--   child row disappears — whereas a **shared-vocabulary join fails OPEN**, matching
--   rows across tenants on a value both happen to hold.
--   ⚠ ON THE aal2 CONJUNCT, HONESTLY: the `exists` subquery reads
--   `pfin.monthly_report`, whose own policy already carries the aal2 clause and is
--   evaluated under the caller's RLS — so **today the conjunct here is redundant
--   through the parent's policy.** It is stated anyway, and NOT on the weak ground
--   that explicit beats inherited (a fence justified that way invites its own
--   removal). The ground is that **redundancy through ANOTHER TABLE'S policy is a
--   dependency, not a guarantee**: `108`'s policy can be edited by a migration that
--   never mentions this file, and the day it is, this table's aal2 posture would
--   change with no diff here to mark it. Sec F-9 requires the clause named on this
--   surface; this is why naming it is more than bookkeeping.
--   ⚠ NO UPDATE POLICY, NO DELETE POLICY, and no UPDATE or DELETE grant — the table
--   is read-only post-write, so the ACL denies before RLS is consulted and the
--   trigger stands behind both.
--
-- ----------------------------------------------------------------------------
-- CANONICAL TEST LABEL: **RT-20**, not RT-21 (Sec D-3; default-and-notify, taken).
--   [ADR-011](DECISIONS.md#adr-011) Decision 16 names **RT-20 HIGH** for this
--   surface (fourth-instance FK-bypass + `service_role` bypass + the parent
--   immutability extension). ⚠ **RT-21 IS A DIFFERENT SURFACE** — the PDF-worker JWT
--   battery — and the drafted *"RT-21 HIGH"* here was a FALSE COMPOSITE: two real
--   labels wrongly paired, which passes every spot-check. **Built as drafted, the
--   RT-20 battery would never be written and nothing would notice, because an RT-21
--   battery exists and is green.**
--   SD: the **SD-12 CHILD SUB-CLASS ADDENDUM** is the correct home — **not** a new
--   SD class (Sec M-3 and Sec §5 both confirm; PRD §2.6.6 resolves it as a
--   derivative surface).
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per Lock 11); NOT SECURITY DEFINER.
--   This migration authors THREE functions and ALL THREE are SECURITY INVOKER with
--   `set search_path = ''`. The Decision 9 allowlist is UNCHANGED BY THIS FILE —
--   read Decision 9 live; no size is stated here.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK ([ADR-011](DECISIONS.md#adr-011) Decision 4 read VERBATIM
--   and LIVE before drafting, 2026-09-05. Path B — the catalogued list is NOT
--   restated and NO COUNT is carried).
--   (i)   INSTANCE-NUMBERING — nothing added, removed, reordered or renumbered.
--         Realizing a Decision 3 label is a DIFFERENT ledger and is not a §10 event.
--   (ii)  LAYER-ATTRIBUTION — nothing moves; no surface becomes "four-layer". This
--         table's grants are DB-layer ACLs.
--   (iii) VERBATIM-VS-PARAPHRASE — Decision 4 is LINKED, never restated.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED RT set are DIFFERENT SETS and are not
--   reconciled here. RT-20 above is a TEST label, which is a third thing again.
--
-- ----------------------------------------------------------------------------
-- Numbering: 109 follows 108 and DEPENDS ON IT (the parent FK). Also depends on 001
--   (pfin schema), 003 (pfin.account), 024 + 025 (the aal2 clause and its subquery
--   target). `110` does not depend on this file at the DDL layer.
--
-- ----------------------------------------------------------------------------
-- QA PAIRING LIST for this file (two-tenant pgTAP battery, same PR; RT-20):
--   1. cross-tenant read via the parent chain → fail closed; owner reads own rows →
--      pass.
--   2. **aal2 leg as a SEPARATE leg** from the cross-tenant leg (Sec F-9).
--   3. **Decision 3 #4 fires:** INSERT a child under the caller's OWN report naming
--      ANOTHER tenant's `account_id` → refused. ⚠ This is a **behavioural** leg, not
--      a construction-only one — unlike `108`'s #3 leg, this fence has a live writer.
--   4. UPDATE any column → refused, **as `authenticated` AND as `service_role`**
--      (Lock 12 mod (iii): the mod IS the absence of a role test).
--   5. DELETE a row → refused under both roles.
--   6. TRUNCATE → refused.
--   7. **The parent-immutability half of instance #4, verified FROM THIS SIDE:**
--      UPDATE the parent's `users_id` while children exist → refused at `108`; the
--      children's tenant attribution is unchanged.
--   8. ON DELETE RESTRICT: deleting a referenced `pfin.account` → refused (23503),
--      and the snapshot row survives.
--   9. the RLS join is on the surrogate: a child whose `monthly_report_id` names
--      another tenant's report is invisible to BOTH tenants (fails closed).
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.monthly_report_account_snapshot — the per-account queryable index over one
--     report. Columns: snapshot_id (surrogate PK) · monthly_report_id bigint (→
--     pfin.monthly_report ON DELETE RESTRICT; the SOLE tenant anchor, resolved
--     through the parent — NOT a Decision 3 instance, argued out above) ·
--     account_id bigint (→ pfin.account ON DELETE RESTRICT; Decision 3 label #4) ·
--     acct_name_at_generation text · tax_treatment_at_generation text ·
--     created_at timestamptz. UNIQUE (monthly_report_id, account_id).
--   MUTATION SURFACE, per role:
--     · authenticated — SELECT and INSERT on rows whose parent it owns,
--       aal2-claused. NO UPDATE and NO DELETE grant or policy.
--     · service_role — SELECT and INSERT. NO UPDATE, NO DELETE, NO TRUNCATE. It
--       bypasses RLS but NOT the triggers, and cannot suppress them.
--     · any owner-class role — blocked by the same triggers, which carry no role
--       test. KNOWN LIMIT: an owner-class role can suppress them; the `108` runbook
--       line applies verbatim to this table.
--   pfin.fn_monthly_report_account_snapshot_matched_account() — INVOKER; BEFORE
--     INSERT (row-level); Decision 3 label #4, chain-resolved (CR). set search_path = ''.
--   pfin.fn_monthly_report_account_snapshot_immutability() — INVOKER; BEFORE UPDATE
--     OR DELETE (row-level); raise. NO ROLE TEST — that absence is Lock 12 mod
--     (iii). set search_path = ''.
--   pfin.fn_monthly_report_account_snapshot_block_truncate() — INVOKER; BEFORE
--     TRUNCATE (statement-level); raise. set search_path = ''. + REVOKE TRUNCATE.
--   RLS: SELECT and INSERT to authenticated, USING / WITH CHECK keyed on an EXISTS
--     over the parent by SURROGATE ID, AND the aal2 backstop. UPDATE and DELETE have
--     no policy and no grant → default-deny.
-- ============================================================================

create schema if not exists pfin;

create table if not exists pfin.monthly_report_account_snapshot (
  snapshot_id                  bigint      generated always as identity primary key,
  monthly_report_id            bigint      not null
                                             references pfin.monthly_report (report_id) on delete restrict,
  account_id                   bigint      not null
                                             references pfin.account (account_id) on delete restrict,
  acct_name_at_generation      text        not null,
  tax_treatment_at_generation  text        not null,
  created_at                   timestamptz not null default now(),
  unique (monthly_report_id, account_id)
);

comment on table pfin.monthly_report_account_snapshot is
  'The Lock 12 per-account CHILD of pfin.monthly_report ([ADR-011](DECISIONS.md#adr-011) '
  'Decision 16; SELF-346 / A2; V1.5 pre-flight rulings R1 / R5). ⚠ ITS ROLE IS '
  'SETTLED: it is the per-account QUERYABLE INDEX over the frozen artifact, NOT a '
  'second copy of it. The artifact is pfin.monthly_report.rendered_payload. That '
  'rule decides the column set — this table carries what a QUERY must answer on '
  '(per-account facts a JSONB payload cannot be filtered, joined or grouped on) and '
  'NOTHING that exists only to be read back whole. THE TEST BEFORE ADDING A COLUMN: '
  'would a caller FILTER, JOIN or GROUP on it? If they would merely display it, it '
  'belongs in the payload, and adding it here creates a second copy that can drift '
  'from the frozen one — permanently, because these rows are immutable. ⚠ EVERY '
  'COLUMN BEYOND LOCK 12''S LOCKED THREE (monthly_report_id, account_id, '
  'acct_name_at_generation) IS A LOCK 12 AMENDMENT ratified in the consolidated ADR '
  'that ships with this migration, not an implementation detail; the amendment '
  'enumerates the widened set. The one substantive widening is '
  'tax_treatment_at_generation, which passes the queryable-index test because §2.6 '
  'reporting filters BY TAX TREATMENT; it is a COPY OF THE ACCOUNT''S VALUE AT '
  'GENERATION TIME and deliberately does not follow the account''s live value. '
  '`scope` is DROPPED — pfin.scope does not exist as a type and pfin.account.scope '
  'is a free-text ADR-004 Decision B label. Per-account MONETARY VALUES are '
  'deliberately absent: they are displayed rather than filtered, they live in the '
  'frozen payload, and copying them here would create a second frozen copy of a '
  'money figure on an immutable table with no mechanism to keep the two in '
  'agreement. ADR-011 DECISION 3, per column: account_id REALIZES CANONICAL LABEL '
  '#4 (matched-tenant BEFORE INSERT fence; read Decision 3 live, no count is stated '
  'here) — and the fence CHAIN-RESOLVES the tenant through monthly_report_id -> '
  'pfin.monthly_report.users_id, because THIS TABLE HAS NO users_id COLUMN, which is '
  'the CR class by Decision 3''s own definitions and not the P1 that label''s entry '
  'names; the class is corrected by an amendment beneath that entry in this same PR. '
  'The OTHER HALF of instance #4 — the parent-immutability extension fencing '
  'monthly_report.users_id and target_month in every state — is built at 108 and '
  'verified from this side: without it, re-tenanting a parent would silently move '
  'every child row with no fence firing, because this child''s tenant is DEFINED by '
  'its parent. monthly_report_id is NOT a Decision 3 instance and NO LABEL IS '
  'ALLOCATED FOR IT: it is this table''s sole tenant anchor, so there is no second '
  'tenant fact to compare and a fence over it is the leg that cannot fail (ADR-062 '
  'Decision 2); and the chain attack runs the other way here, since RLS is evaluated '
  'THROUGH this column, so a row pointed at another tenant''s report is invisible to '
  'both and fails closed. ⚠ THAT DISPOSITION DEPENDS ON THIS TABLE HAVING NO users_id '
  'OF ITS OWN: give it one and monthly_report_id BECOMES an instance requiring a '
  'newly-allocated label, because two tenant facts would then exist that can '
  'disagree. LOCK 12 MOD (iii), the service_role bypass DB-trigger, is NOT a '
  'separate object — it is the fact that this table''s immutability fence carries NO '
  'ROLE TEST AT ALL, so it binds service_role exactly as it binds authenticated; '
  'service_role carries rolbypassrls, so on this surface the trigger is its ONLY '
  'applicable layer. DECISION 2''s IMMUTABLE half governs this table and only that '
  'half: there is NO correction-by-INSERT-new-version path here, because a '
  'correction is made by REGENERATING THE REPORT — a new parent with its own '
  'children — which is the INSERT-new-version half operating one level up, where the '
  'version identity lives. Both FKs are ON DELETE RESTRICT (Lock 12 verbatim for the '
  'parent): on an append-only table a CASCADE is the ONE deletion path that bypasses '
  'the immutability fences. RLS is via the PARENT FK CHAIN, keyed on the SURROGATE '
  'monthly_report_id and never on a (users_id, target_month) value pair — a '
  'surrogate-id join fails CLOSED under an RLS regression, a shared-vocabulary join '
  'fails OPEN. The aal2 clause is carried on this surface even though the parent''s '
  'policy already supplies it, because redundancy through ANOTHER TABLE''S policy is '
  'a dependency rather than a guarantee. CANONICAL TEST LABEL RT-20 — ⚠ NOT RT-21, '
  'which is the PDF-worker JWT battery on a different surface; the pairing was a '
  'false composite, and built as drafted the RT-20 battery would never be written '
  'and nothing would notice because an RT-21 battery exists and is green. SD: the '
  'SD-12 CHILD SUB-CLASS ADDENDUM, not a new SD class. JOINT-REVIEW-MANDATORY, and '
  'reviewed as ONE design unit with pfin.monthly_report and the read-composition '
  'helper.';

comment on column pfin.monthly_report_account_snapshot.monthly_report_id is
  'The report this snapshot row belongs to. FK -> pfin.monthly_report(report_id) ON '
  'DELETE RESTRICT (Lock 12 verbatim — not CASCADE; on an append-only table a '
  'CASCADE is the one deletion path that bypasses the immutability fences). ⚠ IT IS '
  'ALSO THIS TABLE''S SOLE TENANT ANCHOR: the child carries no users_id, so its '
  'tenant is whatever the parent''s is, and RLS on this table is evaluated THROUGH '
  'this column by an EXISTS over the parent keyed on this SURROGATE id — never on a '
  '(users_id, target_month) value pair, because a surrogate-id join fails CLOSED '
  'under an RLS regression while a shared-vocabulary join fails OPEN. ⚠ NOT an '
  'ADR-011 Decision 3 instance and NO LABEL IS ALLOCATED FOR IT: there is no second '
  'tenant fact for a matched-tenant fence to compare against, so such a fence could '
  'only compare the parent''s tenant with itself — the leg that cannot fail (ADR-062 '
  'Decision 2); and a row pointed at another tenant''s report is invisible to both '
  'tenants rather than leaking, because the RLS predicate reads through this very '
  'column. The genuine hazard is the PARENT MOVING UNDER THE CHILD, and that is '
  'fenced at 108 by the parent-immutability trigger, not here. ⚠ THIS DISPOSITION '
  'DEPENDS ON TWO THINGS OUTSIDE THIS COLUMN: that this table never gains a users_id '
  'of its own, and that monthly_report.users_id stays immutable. Add a users_id here '
  'and this column BECOMES a Decision 3 instance requiring a newly-allocated label, '
  'because two tenant facts that can disagree would then exist. Whoever does either '
  'must re-derive this comment rather than re-read it.';

comment on column pfin.monthly_report_account_snapshot.account_id is
  'The account this row indexes. FK -> pfin.account(account_id) ON DELETE RESTRICT — '
  'RESTRICT rather than CASCADE because the table is append-only and a CASCADE would '
  'be the one deletion path that bypasses the immutability fences (the 057 / 107 '
  'choice, for the same reason). ⚠ ADR-011 DECISION 3 CANONICAL INSTANCE #4, carried '
  'UNREALIZED since ADR-011 authoring and DDL-REALIZED here; this realizes an '
  'existing label and ALLOCATES NOTHING (read Decision 3 live; no count is stated '
  'here). An FK validates that the referenced row EXISTS, never that it is within '
  'the referring row''s isolation scope — matched-tenant validation is supplied by '
  'pfin.fn_monthly_report_account_snapshot_matched_account, BEFORE INSERT only '
  '(UPDATE and DELETE are trigger-blocked on this immutable table, so an UPDATE '
  'fence would be dead code). ⚠ FENCE-PATTERN CLASS IS CR, NOT THE P1 THAT LABEL''S '
  'ENTRY NAMES: the entry''s P1 requires the referring row to carry its own '
  'users_id, and THIS TABLE HAS NONE — the tenant is chain-resolved through '
  'monthly_report_id -> pfin.monthly_report.users_id, which is CR''s mechanism by '
  'Decision 3''s own definition. The entry predates Lock 12''s realized column set; '
  'the class is corrected by an amendment beneath it in this same PR, and the label, '
  'the target and the instance are unchanged.';

comment on column pfin.monthly_report_account_snapshot.acct_name_at_generation is
  'The account''s display name AS IT STOOD when the report was generated — one of '
  'Lock 12''s locked three. Copied rather than joined live because the report is a '
  'frozen artifact and an account rename after generation must not retroactively '
  'change what the report said. It is ALSO the queryable form of that fact: the '
  'payload holds the name for display, this column holds it for filtering and '
  'ordering.';

comment on column pfin.monthly_report_account_snapshot.tax_treatment_at_generation is
  'A COPY OF pfin.account.tax_treatment AS IT STOOD AT GENERATION TIME, named as '
  'such — it deliberately does not follow the account''s live value. ⚠ THE ONE '
  'SUBSTANTIVE COLUMN BEYOND LOCK 12''S LOCKED THREE, and therefore a LOCK 12 '
  'AMENDMENT ratified in the consolidated ADR shipping with this migration, not an '
  'implementation detail. It earns its place by the queryable-index test: §2.6 '
  'reporting filters report rows BY TAX TREATMENT and a JSONB payload cannot be '
  'filtered on, whereas a per-account monetary value would only ever be displayed '
  'and therefore stays in the payload. NOT NULL, mirroring pfin.account.tax_treatment '
  '(003), which is text NOT NULL.';

comment on column pfin.monthly_report_account_snapshot.created_at is
  'Insert instant; immutable post-write. Structural rather than a report fact — the '
  'report''s own generation instant is pfin.monthly_report.generated_at, and these '
  'two can differ by the duration of the finalization transaction.';

-- ----------------------------------------------------------------------------
-- RLS — via the parent FK chain, keyed on the SURROGATE monthly_report_id (AC 5,
-- verbatim), plus the 025 aal2 clause. grant-before-RLS shape (PR #106).
-- ⚠ NO UPDATE and NO DELETE policy or grant — the table is read-only post-write.
-- ----------------------------------------------------------------------------
alter table pfin.monthly_report_account_snapshot enable row level security;

create policy monthly_report_account_snapshot_select on pfin.monthly_report_account_snapshot
  for select to authenticated
  using (
    exists (
      select 1 from pfin.monthly_report r
       where r.report_id = monthly_report_account_snapshot.monthly_report_id
         and r.users_id  = auth.uid()
    )
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

create policy monthly_report_account_snapshot_insert on pfin.monthly_report_account_snapshot
  for insert to authenticated
  with check (
    exists (
      select 1 from pfin.monthly_report r
       where r.report_id = monthly_report_account_snapshot.monthly_report_id
         and r.users_id  = auth.uid()
    )
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

comment on policy monthly_report_account_snapshot_select on pfin.monthly_report_account_snapshot is
  'SELECT: owner-only VIA THE PARENT FK CHAIN — an EXISTS over pfin.monthly_report '
  'keyed on the SURROGATE monthly_report_id, never on a (users_id, target_month) '
  'value pair. ⚠ THE KEY CHOICE IS THE FAILURE DIRECTION: a surrogate-id join fails '
  'CLOSED under an RLS regression (no visible parent -> no visible child), while a '
  'shared-vocabulary join fails OPEN by matching rows across tenants on a value both '
  'happen to hold. AND the ADR-029 / 025 aal2 step-up backstop. ⚠ ON THE aal2 '
  'CONJUNCT, HONESTLY: the EXISTS subquery reads pfin.monthly_report under the '
  'caller''s RLS, and that table''s own policy already carries the clause, so today '
  'this conjunct is REDUNDANT THROUGH THE PARENT. It is stated anyway — and not on '
  'the ground that explicit beats inherited, which is the kind of justification that '
  'invites its own removal. The ground is that redundancy through ANOTHER TABLE''S '
  'policy is a DEPENDENCY, not a guarantee: 108''s policy can be edited by a '
  'migration that never mentions this file, and the day it is, this table''s aal2 '
  'posture would change with no diff here to mark it.';

comment on policy monthly_report_account_snapshot_insert on pfin.monthly_report_account_snapshot is
  'INSERT: WITH CHECK the same parent-chain EXISTS on the surrogate id, AND the 025 '
  'aal2 clause (the 090 standard — USING and WITH CHECK per verb; INSERT has no '
  'USING). A caller may write snapshot rows only under a report it owns. ⚠ THE '
  'POLICY IS NOT THE TENANT FENCE ON account_id: it constrains WHOSE REPORT the row '
  'attaches to and says nothing about whose ACCOUNT the row names. A row naming '
  'ANOTHER tenant''s account_id under the caller''s OWN report satisfies this policy '
  'completely and is refused by '
  'pfin.fn_monthly_report_account_snapshot_matched_account (Decision 3 #4). Two '
  'controls answering two different questions, and neither subsumes the other. There '
  'is deliberately NO UPDATE and NO DELETE policy, and no grant for either verb — '
  'the table is read-only post-write, so those default-deny at the ACL before RLS is '
  'consulted, with the immutability trigger behind them for any role that bypasses '
  'RLS.';

grant select, insert on pfin.monthly_report_account_snapshot to authenticated;
grant select, insert on pfin.monthly_report_account_snapshot to service_role;

revoke truncate on pfin.monthly_report_account_snapshot from public;

-- ----------------------------------------------------------------------------
-- Fence 1 — ADR-011 DECISION 3 LABEL #4 (CR, chain-resolved). BEFORE INSERT only:
-- the table is immutable audit-class, so an UPDATE fence would be dead code.
-- The tenant is resolved through the PARENT, because this table has no users_id.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_monthly_report_account_snapshot_matched_account()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_report_tenant uuid;
  v_report_status pfin.report_generation_status_enum;
begin
  -- Resolve this row's tenant through the parent. NULL-safe by construction: the
  -- variable stays NULL when the parent is absent or invisible, and the comparison
  -- below is written so NULL rejects rather than passing.
  select r.users_id, r.generation_status
    into v_report_tenant, v_report_status
    from pfin.monthly_report r
   where r.report_id = new.monthly_report_id;

  if v_report_tenant is null then
    raise exception
      'monthly_report_account_snapshot INSERT rejected: parent report % does not resolve (absent, or invisible under this caller''s RLS). The child''s tenant is defined by its parent, so an unresolvable parent is a fail-closed refusal (ADR-011 Decision 3 #4 chain resolution).',
      new.monthly_report_id;
  end if;

  if not exists (
    select 1 from pfin.account a
     where a.account_id = new.account_id
       and a.users_id   = v_report_tenant
  ) then
    raise exception
      'cross-tenant monthly_report_account_snapshot rejected: account_id % is not owned by the report''s tenant % (ADR-011 Decision 3 #4 matched-tenant fence, chain-resolved through monthly_report_id).',
      new.account_id, v_report_tenant;
  end if;

  -- ⚠ THE SNAPSHOT SET CLOSES AT FINALIZATION (Sec FLAG-4, PR #636). Without this
  -- predicate the child set stays OPEN on a `final` parent: a caller could append a
  -- snapshot row to a report whose payload was frozen days earlier, and every other
  -- fence would permit it — the tenant still matches, the account still belongs to
  -- that tenant, and 108's immutability trigger governs the PARENT's columns, not the
  -- arrival of new CHILDREN. The result is a finalized report whose stored artifact
  -- and whose per-account children disagree, permanently, with the children immutable
  -- too. THE PARENT'S DRAFT WINDOW IS THE CHILD SET'S WRITE WINDOW.
  -- ⚠ Placed AFTER the tenant resolution deliberately: an unresolvable parent must go
  -- on reporting as unresolvable rather than as not-a-draft, because under RLS
  -- "another tenant's report" and "absent" are ONE condition, and this message must
  -- not become a second way to probe existence.
  -- ⚠ `IS DISTINCT FROM`, not `<>`: v_report_status cannot be NULL here (the
  -- resolution above already refused that case), but the NULL-safe form is what keeps
  -- that true if the refusal above is ever loosened — `NULL <> 'draft'` is NULL, not
  -- true, and would fail OPEN.
  if v_report_status is distinct from 'draft' then
    raise exception
      'monthly_report_account_snapshot INSERT rejected: parent report % is % — the snapshot set CLOSES at finalization (Sec FLAG-4). Per-account snapshot rows are written during the parent''s draft window only; a report whose payload is frozen cannot acquire new children, or its stored artifact and its children would permanently disagree. Regenerate the month to open a new draft with its own children.',
      new.monthly_report_id, v_report_status;
  end if;

  return new;
end;
$$;

revoke execute on function pfin.fn_monthly_report_account_snapshot_matched_account() from public;

comment on function pfin.fn_monthly_report_account_snapshot_matched_account() is
  'BEFORE INSERT matched-tenant fence on pfin.monthly_report_account_snapshot.account_id — ADR-011 DECISION 3 CANONICAL INSTANCE #4, carried UNREALIZED since ADR-011 authoring and DDL-REALIZED at this migration. REALIZES an existing label and ALLOCATES NOTHING; read Decision 3 live, no count is stated here. SECURITY INVOKER + set search_path = '''' — NOT a SECURITY DEFINER allowlist entry (read ADR-011 Decision 9 live). An FK validates that the referenced row EXISTS, never that it is within the referring row''s isolation scope; this fence supplies the tenant half. ⚠ FENCE-PATTERN CLASS IS **CR**, NOT THE **P1** THAT LABEL #4''s ENTRY NAMES, and the divergence is structural rather than a preference: Decision 3 defines P1 as "referring row has its own users_id" and CR as "referring row has no own users_id; the fence resolves the owning tenant through a chain". THIS TABLE HAS NO users_id COLUMN — Lock 12 locks three columns and none is a tenant anchor, and A2''s own AC mandates RLS via the parent FK chain, which presupposes exactly that. So the tenant is resolved through monthly_report_id -> pfin.monthly_report.users_id and THEN compared to pfin.account.users_id. The entry''s P1 was written before Lock 12''s column set was realized; the class is corrected by an amendment beneath that entry in this same PR, and the label, target and instance are unchanged. BEFORE INSERT ONLY: the table is immutable audit-class, so UPDATE and DELETE are trigger-blocked and an UPDATE fence would be dead code (the 019 / 044 / 057 / 107 immutable-audit shape, not the 012 / 022 / 074 / 101 mutable-settings shape that must also fence a repoint path). TWO RAISE LEGS with different meanings and deliberately distinct messages so a battery can assert which fired: (1) the parent does not resolve — absent, or INVISIBLE under an RLS-subject caller — which fails CLOSED because the child''s tenant is DEFINED by its parent and an unresolvable parent leaves no tenant to compare; (2) the named account is not owned by the report''s tenant, which is the cross-tenant forge. ⚠ LEG 2 IS REACHABLE BY A PLAIN `authenticated` CALLER: this table grants authenticated INSERT for the on-demand generation path, so a caller can submit their OWN report id with a FOREIGN account_id, which resolves, mismatches and raises here — the ownership-forge route, reachable BEFORE any RLS WITH CHECK question arises because a BEFORE trigger precedes WITH CHECK evaluation. It is ADDITIONALLY reachable by an RLS-exempt writer. Stating only the second would be the ADR-042 / ADR-056 overclaim and it is deliberately not inherited here. ⚠ THE OTHER HALF OF INSTANCE #4 IS NOT IN THIS FUNCTION: label #4''s own text names a parent-immutability extension fencing monthly_report.users_id and target_month post-creation, built at 108. Without it this fence is sufficient only at INSERT time — re-tenanting the parent afterwards would move every child with nothing here firing, because the tenant this function reads is the parent''s. THAT IS WHERE THIS FENCE''S SUFFICIENCY COMES FROM, and it comes from another file. ⚠ Running SECURITY INVOKER, leg 1 cannot distinguish an absent parent from an invisible one, and the message says so rather than claiming to have distinguished them.';

create trigger monthly_report_account_snapshot_matched_account
  before insert on pfin.monthly_report_account_snapshot
  for each row execute function pfin.fn_monthly_report_account_snapshot_matched_account();

-- ----------------------------------------------------------------------------
-- Fence 2 — immutability (Decision 2's IMMUTABLE half; Lock 12 mod (iii)).
-- ⚠ THERE IS NO ROLE TEST IN THIS BODY, AND THAT ABSENCE **IS** LOCK 12 MOD (iii),
-- the "service_role bypass DB-trigger". service_role bypasses RLS but not triggers.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_monthly_report_account_snapshot_immutability()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.monthly_report_account_snapshot is immutable (ADR-011 Decision 2, immutable half; Lock 12). % blocked — a snapshot row is a captured per-account fact about a closed month. A correction is made by REGENERATING THE REPORT (a new parent row with its own children), never by editing these.', tg_op;
end;
$$;

revoke execute on function pfin.fn_monthly_report_account_snapshot_immutability() from public;

comment on function pfin.fn_monthly_report_account_snapshot_immutability() is
  'BEFORE UPDATE OR DELETE immutability fence on pfin.monthly_report_account_snapshot (ADR-011 Decision 2 IMMUTABLE half — the half R4 ratifies as governing this table; Lock 12; SELF-346 / A2). SECURITY INVOKER, set search_path = '''' — NOT a SECURITY DEFINER allowlist entry (read ADR-011 Decision 9 live). raise exception (fail loud, never return null — a silent no-op would read as success). ⚠ THERE IS NO ROLE TEST ANYWHERE IN THIS BODY, AND THAT ABSENCE **IS** LOCK 12 MOD (iii), the "service_role bypass DB-trigger": service_role carries rolbypassrls, so on this surface the trigger is its ONLY applicable layer, and a role-conditional exemption would remove that layer entirely with no RLS behind it to catch the miss. Stated because "a service_role bypass trigger" reads like a named object, and a reviewer looking for a separate one and not finding it could reasonably conclude the mod was skipped. A battery must prove refusal UNDER BOTH roles. ⚠ ONLY THE IMMUTABLE HALF OF DECISION 2 IS IN FORCE HERE: there is deliberately NO correction-by-INSERT-new-version path on this table, because a correction is made by REGENERATING THE REPORT — a new parent row with its own children — which is the INSERT-new-version half operating one level up, where the version identity (generation_status) actually lives. A version column here would create a second, finer versioning axis that nothing reads and that could disagree with the parent''s. INTERACTION WITH THE PARENT: 108''s trigger permits deleting a DRAFT parent and both FKs here are ON DELETE RESTRICT, so a draft parent that has children cannot be deleted — coherent rather than accidental, since children are written at finalization and a genuine draft has none. Both paths are dormant today because no role holds a DELETE grant on either table. KNOWN LIMIT: an owner-class role can suppress this trigger (ALTER TABLE ... DISABLE TRIGGER / session_replication_role = replica); ADR-011 Decision 4''s 2026-09-03 amendment puts the applicable-layer count for an RLS-exempt writer at ZERO under that GUC, not at one, so any bulk-load or restore path touching this table owes an explicit post-load validation step.';

create trigger monthly_report_account_snapshot_immutability
  before update or delete on pfin.monthly_report_account_snapshot
  for each row execute function pfin.fn_monthly_report_account_snapshot_immutability();

-- ----------------------------------------------------------------------------
-- Fence 3 — statement-level TRUNCATE block. Row-level triggers do not fire on
-- TRUNCATE, so Fence 2 cannot see a table-wipe.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_monthly_report_account_snapshot_block_truncate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.monthly_report_account_snapshot TRUNCATE blocked (ADR-011 Decision 2; Lock 12). The per-account report index cannot be wiped; PRD §2.6.4 commits to indefinite retention of the reports it indexes.';
end;
$$;

revoke execute on function pfin.fn_monthly_report_account_snapshot_block_truncate() from public;

comment on function pfin.fn_monthly_report_account_snapshot_block_truncate() is
  'BEFORE TRUNCATE (statement-level) fence on pfin.monthly_report_account_snapshot (ADR-011 Decision 2 / Lock 10 mod #8 pattern; SELF-346 / A2). SECURITY INVOKER, set search_path = '''' — NOT a SECURITY DEFINER allowlist entry (read ADR-011 Decision 9 live). Closes the TRUNCATE bypass: row-level UPDATE/DELETE triggers do NOT fire on TRUNCATE, so the row-level immutability fence cannot see a table-wipe. Paired with REVOKE TRUNCATE FROM PUBLIC so a broad platform default cannot reintroduce the privilege; the trigger is the regardless-of-grant guarantee. The message is deliberately distinct from the row-level fence''s so a battery can assert which fired.';

create trigger monthly_report_account_snapshot_block_truncate
  before truncate on pfin.monthly_report_account_snapshot
  for each statement execute function pfin.fn_monthly_report_account_snapshot_block_truncate();

-- ----------------------------------------------------------------------------
-- No separate monthly_report_id index: the `unique (monthly_report_id, account_id)`
-- btree already serves the RLS predicate's join, the per-report fetch, and the
-- uniqueness guarantee — all three are leading-column prefixes of it. A separate
-- account_id index is NOT created: no §2.6 read starts from an account and asks
-- which reports mention it; add one when such a reader exists, not before.
-- ----------------------------------------------------------------------------
