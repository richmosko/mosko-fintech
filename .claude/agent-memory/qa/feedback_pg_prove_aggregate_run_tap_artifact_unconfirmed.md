---
name: pg-prove-aggregate-run-tap-artifact-unconfirmed
description: "Looks like you planned N tests but ran M" is now CONFIRMED (not just a discriminated-but-unrootcaused artifact) — root cause found pre-documented in 085/self244's own battery headers, missed on first read. drift = count of TRAILING savepoint-wrapped/rolled-back legs at the file's tail with nothing after them.
metadata:
  type: feedback
---

**⚠ SUPERSEDES the "mechanism unconfirmed" framing this file originally carried — the mechanism
IS confirmed, and I should have found it before reporting it as unknown.** Drafting SELF-257 I
re-read `self244_v12_close_gate.sql`'s own header (its BLOCK E comment), which quotes `085_
taxonomy_element_rls.sql`'s own measured mechanism verbatim: `ok()` prints its `ok N` from a
SEQUENCE (exempt from rollback), but separately calls `_set('curr_test', N)` — an ordinary TABLE
write that a `savepoint ... rollback to savepoint` pair around a trailing leg DOES undo, and
writes an ABSOLUTE value (not an increment), so a later `ok()` normally overwrites a rolled-back
predecessor's loss with its own new absolute value — EXCEPT for legs at the very TAIL of the file,
after which nothing else runs to overwrite it. **drift = the count of consecutive
savepoint-wrapped-and-rolled-back legs sitting at the file's own tail, immediately before
`finish()`.** Confirmed by exact arithmetic across three independent files: 085 has ONE such
trailing leg → "planned 19 ran 18" (drift 1); self244 has THREE (E2/E3/E4) → "planned 35 ran 32"
(drift 3); 099 has TWO (CC0/CC1, the corrupt-the-control pair) → "planned 37 ran 35" (drift 2).
`finish()`'s own `1..N` / `ok`/`not ok` stream is completely correct regardless — this is a
`#`-prefixed TAP COMMENT from `finish()`'s own plan-vs-sequence sanity check, not a real gap, and
pg_prove (the TAP-aware consumer) is unaffected: every `ok N` prints once, in order, and the file
is absent from the run's own Failed-tests list.

**What went wrong the first time:** I discriminated "artifact vs real failure" correctly (exit
status / Failed-list / isolated-rerun) but reported the CAUSE as unconfirmed rather than reading
the two files that already document it — a case of not checking whether a colleague's own battery
header already contains the answer before telling team-lead "I didn't chase it further." The
lesson isn't "don't say unconfirmed" — it's **grep the two files already showing the same symptom
for their own explanation before reporting a mechanism as unknown.**

**How to apply:** a file ending in one or more savepoint-wrapped corrupt-the-control /
inversion legs (SAVEPOINT ... rollback to savepoint, nothing non-rolled-back after) will show this
comment in an aggregate `/tests` run in proportion to how many such legs sit at its tail. It is
NOT a defect and needs no fix — but if it's ever surprising, `grep -c 'savepoint' <file>` near the
tail plus the arithmetic above resolves it in one step, no fresh investigation needed.
[[feedback_pg_prove_scope_full_tests_tree_not_rls_only]] — related but different: that one is
about scope (which directory to point pg_prove at), this one is about this specific counting
comment within a correctly-scoped run.

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
