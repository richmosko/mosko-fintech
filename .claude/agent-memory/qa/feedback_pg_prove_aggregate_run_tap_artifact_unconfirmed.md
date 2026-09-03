---
name: pg-prove-aggregate-run-tap-artifact-unconfirmed
description: "Looks like you planned N tests but ran M" can appear in a full `/tests`-tree pg_prove run for a file that is 100% green in isolation (immediately followed by "ok", absent from the run's own Failed-tests summary) — a real but unroot-caused TAP::Parser artifact specific to the multi-file aggregate run, not a plan-count defect. Don't chase it further without saying so.
metadata:
  type: feedback
---

099's own battery: standalone `pg_prove -r /tests/rls/099_..._rls.sql` → clean `ok / All tests
successful`, zero warnings, 37/37. The SAME file inside a full-tree `pg_prove -r /tests` run
(2188 tests, 91 files) printed `# Looks like you planned 37 tests but ran 35` immediately followed
by `ok` — and the run's own Test Summary Report / Failed-tests list did NOT include 099 (only
054_nav_daily_rls.sql, 3 named tests, was actually failing). 085 and self244 show the identical
shape in full-tree runs (pre-existing, not something this session introduced).

**The discriminator that separates "artifact" from "real failure"** (what actually to check,
not just "it says ok so it's fine"): (1) exit-status `ok` for that file specifically, (2) absence
from the run's own `Failed tests:` list under Test Summary Report, (3) an independent isolated
re-run of the SAME file with a matching pass count and NO such line. All three held here.

**What I do NOT know and didn't chase further** (said explicitly to team-lead rather than
guessing): why the line appears in the aggregate run at all when the isolated run of the identical
file shows nothing. Plausible mechanism (unverified): TAP::Harness's live plan-tracking gets
confused by non-TAP stray output lines from `select set_config('role','postgres',true);` (which
prints the bare returned value `postgres`/`anon` as an unlabeled result row) landing in the
aggregated multi-file stream — but I did not prove this is what causes the counter to reset only
in aggregate mode. Team-lead re-titled the follow-up ticket from "plan-count drift" to
"aggregate-run TAP artifact, mechanism unconfirmed" rather than have it read as a real defect —
that's the right disposition for a claim at this evidence level: report the discriminator, name
what's unconfirmed, don't imply more certainty than the evidence supports.
[[feedback_pg_prove_scope_full_tests_tree_not_rls_only]] — related but different: that one is
about scope (which directory to point pg_prove at), this one is about a counting artifact within
a correctly-scoped run.
