# SELF-353 / A9 — Architect notes beyond the report

Branch `feature/self-353`, tip `a295d89`. Files: `supabase/migrations/107_nav_component_daily.sql` (new), `DECISIONS.md` (D3 fold-in).

## F-1 — The capture source is 049, NOT fn_nav_composition (051/105)

ADR-054 Decision 3 names `051` as the function that "already emits per-account leaf values", and AC 3 repeats it. That was true on 2026-08-12. `102` and then `105` replaced `fn_nav_composition`, and it now anti-joins out every tax-authority-designated ledger via `pfin.fn_tax_authority_ledgers()`. `pfin.nav_daily.nav_value` is `fn_compute_nav(current_date, true)`, which keeps its GROSS definition and still includes those ledgers (105's own comment says so; ADR-067 D3 makes nav_daily gross pre-tax permanently).

    Sum(fn_nav_composition leaves) = nav_daily.nav_value - Sum(designated ledger balances)

A worker capturing 051's leaves would fail the AC-6 reconciliation for every user who has designated a ledger and pass for everyone else. The correct source is `pfin.fn_account_unrealized_gl(p_as_of).current_market_value` (049; live body re-issued at `056`, leaf set re-predicated at `059`) — the single leaf substrate 051 itself composes on, whose sum IS fn_compute_nav(as_of, true) exactly (ADR-038/ADR-039).

The AC's coherence note checked A9 against 105 on the **definition** axis and that check is sound. The **leaf-set** axis is a different axis and was not checked. Recorded in 107's header as a finding, not as a correction of the ADR (the ADR sentence is a dated record).

## F-2 — Same-transaction vs ADR-054 Decision 2's independent-failure bullet

Decision 2's third bullet: "A component-capture bug must not be able to corrupt or block the scalar NAV checkpoint." AC 2 / Decision 1 require the same transaction. Same transaction means a leaf-side raise rolls back that tenant's scalar checkpoint for that day.

Resolution taken (stated in 107's header, not resolved unilaterally beyond the migration): same-transaction is load-bearing because it is what makes Sum(leaves) = scalar true by construction — split it and AC 6's property stops being a property. Decision 2's independence argument is about the **surface** (its three bullets are all arguments against widening 054's table), not the write transaction. The residual is real and is stated: the fail surface is minimised to five paths, four of which MUST raise. Routed to Sec and F/CTO.

## F-3 — The #19 fence is trigger-realized because a WITH CHECK would be vacuous

The brief said "matched-tenant validation in the DDL (WITH CHECK, single column)". That phrasing comes from D3's preamble, which names WITH CHECK first for single columns. A WITH CHECK is an RLS **policy** clause and is not evaluated for a `rolbypassrls` role. This table's sole writer is `service_role`. A policy realization would fence nothing.

This sharpens D4's 2026-09-03 amendment rather than contradicting it: the amendment left open that a future single-column instance could take the policy form and survive `session_replication_role = replica`. #19 is single-column and still cannot. **The policy-vs-trigger choice is decided per instance by its WRITER SET, not by column arity.** Recorded in D3's fold-in consequence (c).

Cost accepted and stated: #19 and its FK go inert together under that GUC, taking the RLS-exempt writer's applicable-layer count to zero. The GUC is superuser-context and denied to both service_role and authenticated, so the exposure is operational — any restore / bulk-load / replication runbook owes a post-load validation over this table.

## F-4 — Reachability: #16's pure form, deliberately NOT #17's/#18's

#17 and #18 were each corrected to say the cross-tenant leg is reachable both by a plain `authenticated` ownership forge and by an RLS-exempt writer. On this surface `authenticated` holds no INSERT grant and no INSERT policy, so the forge is refused at the table ACL before any trigger runs. Inheriting that correction mechanically here would be the **mirror-image overclaim** — too broad rather than too narrow — and would point QA's battery at a route that does not exist.

## Open F/CTO decision — unrealized_gl / cost_basis are NOT captured

049 emits four columns per leaf; 107 stores only `current_market_value`. Against capturing the other two: only current_market_value participates in the AC-6 reconciliation, so they would ship as unwatched columns on an append-only table; and 105 records a live named residual — while wash-sale `basis_adjust` and substantive `corp_action` stay Suspense-parked at `035`/`037`, `cost_basis` is understated and `unrealized_gl` overstated, so a captured series would freeze a known-wrong figure into a table with no correction path and be indistinguishable from a measured one.

The cost is real and is not argued away: every day before such a column is added is a permanent hole, and adding it later gives every existing row a NULL nobody measured. ADR-054's own asymmetry argument cuts the other way. F/CTO-decidable; cheap to add in this wave if the answer is yes.

## Behaviour legs run (scratch DB, clean 001..107, real writer posture)

| Leg | Result |
|---|---|
| own-account insert, GUC bound, as service_role | ACCEPTED (1 row) |
| foreign `account_id` under own `users_id` | REJECTED by #19 |
| GUC unset | REJECTED by binding fence |
| GUC = other tenant, self-consistent (users_id, account_id) pair | REJECTED by binding fence |
| owner UPDATE / DELETE / TRUNCATE | REJECTED by the three immutability fences, distinct messages |
| service_role: read arbiter cols / read component_value / `select *` / UPDATE / DELETE | 1 / denied / denied / denied / denied |
| authenticated INSERT | denied at the ACL |
| `'Infinity'::numeric` | rejected by `nav_component_daily_value_finite` |

Legs 2 and 4 together are the disjointness proof: neither BEFORE INSERT fence subsumes the other, so removing either opens a route.

Catalog read-back: 4 triggers all origin-enabled; constraints = PK + 2 FKs + `unique (users_id, nav_date, account_id)` + the finiteness CHECK; 1 policy (SELECT, authenticated); RLS enabled, not forced; ACL `authenticated=r`, `service_role=a`, column ACL `service_role=r` on exactly the three arbiter columns and nothing on `component_value`. Comment render-verify: the only doubled-quote in any rendered comment is the intentional `set search_path = ''` in the four function comments; zero elsewhere.
