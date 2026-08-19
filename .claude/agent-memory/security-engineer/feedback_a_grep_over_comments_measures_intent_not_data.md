---
name: a-grep-over-comments-measures-intent-not-data
description: A partition/coverage claim measured by grepping migration COMMENTS measures declared intent; when the rule those comments describe is app-layer, the ROWS can violate it — demand the row counts before any migration is authored
metadata:
  type: feedback
---

**A `grep` over migration text measures what the authors INTENDED, never what the data IS. The two
diverge exactly where the rule is unenforced — which is precisely where a review matters.**

**The instance.** The GL-split ADR (2026-08-18) rested its whole cost case on a measurement:
`grep -noE "Matched-DOMAIN[^.]*\.|domain = '[a-z]*'"` over four migrations, concluding *"the four
referents partition cleanly two-and-two along the cut seam … no row's identity has to be
adjudicated."* The very table presenting that result recorded **three of the four rules as "app-layer
only, NOT enforced in the fence"**. An unenforced rule is the one the rows can break. The command was
run correctly, reported honestly, and answered a different question than the one the conclusion
claimed.

**Why: the conclusion was about ROWS ("no row's identity has to be adjudicated"), the command was
about FILES.** Check the noun in the conclusion against the noun the command ranges over. When they
differ, the measurement is not wrong — its scope is.

**How to apply.** Any time a structural change is justified by "the data partitions cleanly / nothing
spans the seam / no adjudication needed", require the **row counts against production-shaped data**
before DDL is authored — one query per referent, both directions across the seam. Put them in the
migration header with their commands, and require an F/CTO disposition for any non-zero.

⚠ **Then triage each violation by its failure DIRECTION, and say so — it changes the severity, not
just the fix.** In that split, three of four candidate violations were caught by `on delete restrict`
FKs or by FK validation, so they abort the migration: a **deploy-time scheduling failure, not a
security one**. The fourth lived on a deliberately **FK-less audit snapshot** (`031`), where the same
violation is silent and permanent. **The one with no constraint is the one that turns a
cheap-now/expensive-later invariant into a hard condition.** Naming which counts fail closed keeps the
finding proportionate and makes the one that doesn't impossible to wave off.

Related: [[verify-the-stated-correctness-mechanism]], [[measure-the-fence-regex-not-its-comment]],
[[my-review-measurements-become-quoted-sources]].
