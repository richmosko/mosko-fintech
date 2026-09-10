---
name: entity-encoding-defeats-grep-in-html
description: In the HTML doc artifacts, &nbsp; and friends make a plain-text grep silently miss live text — normalize entities before any count or "already fixed" claim.
metadata:
  type: reference
---

`docs/{ARCH,PRD,SECURITY}/index.html` use `&nbsp;` liberally inside figures and
short phrases. A plain `grep` / `grep -c` over the raw bytes **cannot see that text**,
so a low count reads as "clean" when the defect is one transform away.

**Measured (2026-09-09, PR #699).** team-lead ran
`grep -c '8 ARM vCores' docs/ARCH/index.html` on `main` `ee6e4760` → **1**, concluded
the only occurrence was §5's *correction note* quoting the retired CAX31 figure, and
told me my §1 finding was a false positive. Re-measured with
`perl -pe 's/&nbsp;/ /g' | grep -n` → **2 hits**. Line 64 —
`(8&nbsp;ARM vCores / 16&nbsp;GB / 160&nbsp;GB, ~€9.50/mo)` — sits inside
`<section id="sec-1">` as a live present-tense claim about the host. The finding stood.

**⚠ The normalization set is NOT just `&nbsp;` — this project encodes its two
most-grepped characters as entities.** Measured over `docs/ARCH/index.html` on `main`
`ee6e4760`: `&sect;`×2 (so `grep '§10'` MISSES a live §10-ledger sentence at line 375)
and `&#35;`×6 (so `grep 'mod #1'` MISSES `Lock 13 mod &#35;1`). Lock-mod inventories and
§-anchor sweeps are exactly the searches that get run when an amendment lands.

**How to apply.**
- Before any count or any "already fixed" claim over an HTML artifact, pipe through
  the full pre-filter, not a partial one:
  `perl -pe 's/&nbsp;/ /g; s/&sect;/§/g; s/&#35;/#/g; s/&#9888;/⚠/g; s/&mdash;/—/g; s/&ndash;/–/g; s/&amp;/&/g'`
- The entity-bearing set is small — `grep -c '&[a-zA-Z]*;\|&#[0-9]*;'` over ARCH found
  entities on only **22 lines**. Enumerate and READ them all rather than sampling.
- Prefer **content anchors** over counts in these files — see
  [[feedback_a_filtered_grep_is_a_claim_about_the_filter]].
- ⚠ The inverse hazard is real too and is what misled the reading here: **a correction
  note that quotes the value it retired is indistinguishable from the defect under a
  string search.** So a hit inside a correction note is not proof the defect is gone,
  and a miss is not proof it never existed. Read the enclosing `<section>` of every hit.

**On the exchange itself:** a teammate's counter-measurement is not authority — re-run it
with the filter widened before conceding a finding. See
[[feedback_a_prose_observation_needs_reanchoring_too]].

Related: [[feedback_clean_sweep_claim_is_a_claim_about_the_filter]] · [[feedback_failed_grep_looks_like_a_clean_result]] · [[feedback_state_what_the_count_is_over]]
