---
name: correcting-half-a-hand-maintained-mirror
description: When authorizing a fix to one half of a hand-maintained mirror (a prose enumeration of a machine-checked list), verify the OTHER half in the same read — the revision that touches the paragraph is the last chance the drift gets
metadata:
  type: feedback
---

When a doc paragraph hand-mirrors a machine-checked list, and a fix touches ONE half of it,
**verify every half in the same read.** Authorizing the half you came for and skipping the rest
leaves drift inside the paragraph whose own text instructs the reader to fix that drift.

**Why:** on PR #695 (2026-09-09) I ruled `docs/deployment-runbook.md` §5's `production_only`
mirror `11 names` → `10`. I checked only the production half. The `ci_only` half of the SAME
sentence said `(4 names)` while the manifest holds five (`BLS_API_KEY_TEST` was added later and
never mirrored). `scripts/ci/check-secrets-nonoverlap.py` prints
`{len(ci_set)} ci_only + {len(prod_set)} production_only`, so CI had been emitting `5` against a
paragraph claiming `4` — green throughout, because the fence reads the manifest and not the
prose. The paragraph cites the identical `SIMPLEFIN_TOKEN` recurrence as its cautionary tale.

**How to apply:**
- Parse the machine-readable source and print the counts rather than eyeballing the list:
  `git show <sha>:secrets-manifest.yml | python3 -c "import sys,yaml; d=yaml.safe_load(sys.stdin); ..."`.
  Read at the BRANCH sha, not the worktree — see [[feedback_signature_change_invalidates_catalog_assertions]].
- Find where the fence PRINTS its numbers and quote that line. A mirror is only checkable if
  something emits the truth; if nothing does, that is a separate finding.
- Generalize the sweep: if the artifact mirrors N lists, check N, not the one in the brief.
- ⚠ Distinguish **stale prose** from **prose that instructs the failure**. A runbook row that
  merely reads out of date is a follow-up; a row that tells an operator to inject the wrong
  variable name is a MERGE CONDITION. That distinction is what makes a condition defensible
  instead of pedantic — state the operational consequence, not the inconsistency.
- When a stale row is partly RIGHT, the fix is a split, not a deletion. Runbook §4's anon-key
  row correctly required the Supabase stack's own compose `ANON_KEY` while wrongly sending the
  same name to the app service; deleting it would have removed a real requirement.
- ⚠ **A per-surface census over FILES misses scope CLAIMS made INSIDE files that are themselves
  correct.** On PR #697 (2026-09-09, Plaid confinement) team-lead measured all four
  `.env.example` surfaces and ruled `workers/provider-sync/` "correct, untouched" — its
  DECLARATIONS were correct, but its inline comment
  `PLAID_CLIENT_ID=  # secret (production_only) — shared with api/ + workers/etl/` named a
  container the fix had just disqualified. Same class as the `secrets-manifest.yml` scope
  comment. **After a confinement removal, grep the credential NAME across the whole tree, not
  the enumerating files** — the residue lives in the comments of the file that is right.
- Name the miss in the same message as the new findings. Related:
  [[feedback_public_prefix_is_a_declaration_not_an_emission]].
