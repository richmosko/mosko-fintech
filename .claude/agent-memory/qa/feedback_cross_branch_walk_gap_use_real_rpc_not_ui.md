---
name: cross-branch-walk-gap-use-real-rpc-not-ui
description: A branch cut before a sibling V1.5 PR merged in won't have that sibling's UI wired (recurred TWICE in one walk — P8/self-360 and P6/self-358 both predate P4/self-356 and/or P7/self-359) — call the same RPC/PostgREST path the missing UI would eventually call, don't fabricate a DB bypass or block on it.
metadata:
  type: feedback
---

During the V1.5 browser walk (7 PRs, 2026-09-06/07), two separate branch checkouts hit the same
class of gap: `feature/self-360` (P8, staleness markers) and `feature/self-358` (P6, PDF export)
were both cut before `feature/self-356` (P4, finalize/skip) and/or `feature/self-359` (P7,
owner-id settings) merged into `main`, so their commentary-editor Finalize button read
"Not yet available (P4)" and there was no `/settings/owner-id` route at all.

**Resolution used both times, successfully**: don't block the walk on it, and don't reach for a
raw `UPDATE`/psql bypass either. Read the migration source for the RPC the missing UI would
eventually call (`fn_finalize_monthly_report`, or a direct `PATCH` to `pfin.owner_identification`
under RLS) and call it directly via PostgREST with the walk user's own JWT
([[reference_magic_link_cookie_login_for_live_walks]]). This is a LEGITIMATE app-level write —
same RLS, same triggers, same audit trail a real click would produce — not a bypass; it just
skips a UI affordance that genuinely isn't wired on this specific checkout yet.

**How to apply**: when a walk brief names 7+ sibling branches and one's checkout is missing
another's feature, first confirm it's a genuine integration-order gap
(`git merge-base --is-ancestor <sibling>/tip <this>/tip`) rather than a real defect. Then find
the DB function or PostgREST-writable table the missing UI targets (grep the sibling branch's
own route source for the RPC/table name) and call it with the walk user's real session — never a
raw admin-role UPDATE for this class of gap, since the RPC/RLS path IS reachable and is the
truer test of what a real click would eventually do. Flag the gap in the walk report's bubble-up
either way, since it's still worth a coordinator knowing about, even though it's not a defect.
