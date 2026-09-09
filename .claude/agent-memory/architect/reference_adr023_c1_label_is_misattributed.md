---
name: adr023-c1-label-is-misattributed
description: The "ADR-023 condition C1" label on the PostgREST/provider-sync rotation coupling is MIS-ATTRIBUTED, not unsupported. F/CTO RULED 2026-09-09: the home is ADR-019 condition C1, reconstructed by ADR amendment. Find carriers by grep, never by a stored list.
metadata:
  type: reference
---

**The label is MIS-ATTRIBUTED, not unsupported.** Right content, wrong pointer.
Measured at `d83dfdaf` (2026-09-08); the earlier "unsupported" version of this note was
**refuted** by Sec at the PR #671 joint-review and this file replaces it.

- **ADR-041 DOES attach the label to the rotation coupling** — in several paragraphs,
  including the sub-decision promoting ADR-019 C2 to a Phase-7 deploy gate (the paragraph
  migration `116` realizes). So the claim *"no text in DECISIONS.md attaches the coupling
  to a condition labeled C1"* is **FALSE**. Do not restate it, and do not cite this file
  for it. **No count and no site list here.** An earlier revision of this note enumerated
  the sites and omitted the ADR-019-C2 one — the site most likely to be left
  un-re-attributed; a corrected count would re-arm the same trap. Find them with the grep
  below, bracketed to ADR-041's body by its `## ADR-041` heading.
- **ADR-023's own enumerated C1 is a different condition** — *"exposure-readiness artifact
  (per-table RLS + policy proof) reviewed before exposure"*. That pairing (both halves
  separately real) is the [[feedback_false_composite_citation]] class at cross-artifact
  scale, which is why it survives every spot-check.
- **The coupling itself is real** — provider-sync's `PFIN_DB_PASSWORD` holds the
  `authenticator` password, which is also PostgREST's credential.

**The home is RULED, no longer inferred (F/CTO, 2026-09-09).** It is **ADR-019's
Sec condition C1**, whose text is **reconstructed by ADR amendment** rather than
recovered — `DECISIONS.md` enumerated only C2 of the C1–C4 set ADR-019's Status line
ratifies, and the reconstruction is sourced from `workers/provider-sync/.env.example`
(*"(F/CTO-ratified; Sec conditions C1/C3)"*, then *"CONDITION C1 (rotation coupling —
Sec-load-bearing)"*). The earlier *"do not re-point the label until F/CTO rules"*
instruction is **DISCHARGED**.

**C3 and C4 were ruled in the same amendment: TEXT UNRECOVERABLE, NUMBERS
RETAINED, and NO ARTIFACT MAY CITE C3 OR C4 AS A RULE.** The tree evidences that
they exist and belong to the set; nothing evidences what they require. ⚠ Do not
resolve C3 from a nearby `"C3"` elsewhere in the tree — the bare token labels
ADR-023's own C3, the SC-3 admission conditions and the CA-2 conditions in
`workers/provider-sync/src/`, and adopting one would produce the same
false-composite failure. ⚠ The PR #671 Sec review has its OWN C1 and C4 —
different review, different numbering, not this set's.

**Re-pointed form:** *"ADR-019 condition C1 (reconstructed 2026-09-09)"*. Migration
`117` carries it into `055`'s `comment on role` (PR #675 — ⚠ verify it MERGED before
relying on this; it was a draft awaiting Sec joint-review when written). **`117` must
not merge ahead of the `DECISIONS.md` PR that lands the reconstruction** — a label is
a reference, and one that resolves to nothing is worse than the wrong one it replaced.

**Carriers: find them by grep. This file names none and counts none.** The earlier
enumeration here (and in `116`'s header) was incomplete — it missed every carrier under
`workers/etl/`. Run, at the sha being corrected, unscoped beyond these exclusions:

    git grep -n -E '(^|[^A-Za-z0-9])C1([^0-9A-Za-z]|$)' \
      -- ':!node_modules' ':!.claude/agent-memory' ':!docs/archive'

then keep only hits whose surrounding text is about the `PFIN_DB_PASSWORD` /
`authenticator` rotation coupling. ⚠ `git grep -E '\bC1\b'` **matches nothing** — git's
default ERE engine has no `\b` and it exits 1 silently, which reads exactly like "no
carriers" ([[feedback_failed_grep_looks_like_a_clean_result]]).

**How to apply:** the correction is **re-attribution plus enumeration, never deletion** —
a condition label is a reference into a canonical enumeration, and stripping it leaves a
reader holding a rule with no way to look up the instance. The earlier "name the property
instead of the label" remedy is **WITHDRAWN**. Vehicle follows where the text lives; the
current vehicle-class list is `116`'s header, which is authoritative over this note.
Do not carry a carrier count anywhere — [[feedback_derivable_counts_get_dropped_judged_counts_get_owned]].
