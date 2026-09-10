---
name: a-correction-pass-inherits-the-reviewers-filter
description: When my review enumerates carrier sites for a label/claim, the correction pass adopts my list as THE list — so an incomplete enumeration silently scopes the fix. Run the UNFILTERED grep and hand over a grep, not a list.
metadata:
  type: feedback
---

**When I enumerate the sites carrying a defective label or claim, that enumeration BECOMES the
correction scope.** Downstream artifacts cite it, defer to it, and stop there. Hand over the
**grep command**, not the list — or state explicitly that the list is a floor.

**Why:** PR #671 (2026-09-08). Round 1 I listed 8 carriers of the mis-attributed "ADR-023 C1"
rotation-coupling label from a *filtered* grep. Round 2's unfiltered
`git grep -n -E '(^|[^A-Za-z0-9])C1([^0-9A-Za-z]|$)' <sha> -- ':!node_modules' ':!.claude/agent-memory' ':!docs/archive'`
found **6 more sites in 3 `workers/etl/` files** my filter never reached. By then `116`'s header
had adopted my list verbatim as "Carriers of the label", `055`'s header **deferred to `116`'s list**,
and two BACKLOG bookings scoped their ACs to it. One incomplete measurement had scoped four artifacts.
This is ADR-011 D4's own PR #476 bullet operating inside the PR that cites it: *"found by grepping the
bare label across branch-authored text rather than by visiting the sites the reviewer had enumerated —
the reviewer's own filtered grep had missed the fourth. A filtered grep is a claim about the filter,
not about the tree."*

**Same round, same class, second instance:** I asserted BACKLOG §7.6 S5's AC "carries no C1 label",
from a scoped `awk` range with **no positive control**. It carried it, on `main`, before the branch
existed. See [[feedback_my_review_measurements_become_quoted_sources]] — a scoped command that returns
the reassuring answer is a prompt to re-measure, not a result.

**Third instance, and the cheapest one to have avoided — PR #699 (2026-09-10).** I issued two
merge conditions naming **two files** (`secrets-manifest.yml`, `docs/local-dev.md`) as the carriers
of the falsified Plaid-on-ETL claim. DevOps swept `local-dev.md` correctly and found no third hit
*in that file* — the sweep inherited my file scope, not just my line scope. The tree-wide
`git grep -nE 'PLAID_(CLIENT_ID|SECRET)' <ref>` (32 carrying files) surfaced a live carrier in
**neither** file: `workers/provider-sync/.env.example:39`, whose comment asserted the credential was
*"also declared (unconsumed) in workers/etl/"*. ⚠ **That line was inside the file my OWN #697
conditions had already corrected** (`8931c53d`) — a discharged condition re-falsified by a later PR.
Two compounding lessons: **(a)** naming FILES scopes a sweep as hard as naming LINES; **(b)** the
files a previous condition touched are the *first* place to re-grep, not a place to assume clean —
see [[feedback_a_discharge_can_go_stale_against_its_own_pr]] and
[[feedback_correcting_half_a_hand_maintained_mirror]].

**How to apply:**
0. **Before issuing conditions, run the tree-wide grep over the CLAIM, not over the files you
   happen to be reading** — and re-grep every file a prior condition of mine touched.
1. Run the **unfiltered** grep first; filter only for READING, never for the deliverable.
2. Exclude `node_modules`, `.claude/agent-memory`, `docs/archive` — then `cut -c1-200` so a minified
   or long-line file cannot blow the output and force you into a narrower filter.
3. In the finding, give the **command**. If you also give a list, label it explicitly:
   *"this list is a floor; the command is the definition."*
4. Grep `workers/`, per-directory `CLAUDE.md`, and `docs/records/` — the three places my filters keep
   missing. A per-directory `CLAUDE.md` is auto-loaded context, so a false claim there outranks the
   same false claim in a doc.
