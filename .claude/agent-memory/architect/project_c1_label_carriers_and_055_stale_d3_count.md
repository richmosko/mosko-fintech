---
name: c1-label-carriers-and-055-stale-d3-count
description: The rotation-coupling "ADR-023 C1" label is mis-attributed (inferred home ADR-019 C1, F/CTO ruling pending); BACKLOG §7.6 S5 DOES carry it; 055's header carries a stale Decision-3 count.
metadata:
  type: project
---

Three facts from discharging Sec's C1/C5 on PR #671 (2026-09-08, branch
`feature/s5-c1c5-arch`).

**1. The "ADR-023 condition C1" rotation-coupling label is MIS-ATTRIBUTED, not
invented.** ADR-023's own enumerated C1 is an exposure-readiness artifact
(per-table RLS + policy proof reviewed before exposure). The rotation coupling's
inferred home is **ADR-019's Sec condition C1** — evidence is
`workers/provider-sync/.env.example` ("Sec conditions C1/C3", then "CONDITION C1
(rotation coupling — Sec-load-bearing)"). ADR-019's Status line ratifies
"Sec conditions C1–C4" but `DECISIONS.md` enumerates **only C2**. Whether the
C1/C3/C4 text is recoverable is an **OPEN F/CTO ruling**. Carriers: ADR-041 (×3),
`055` header + `comment on role`, `secrets-manifest.yml`, `deployment-runbook.md`
§6.1, BACKLOG §7.6 S5, `.env.example`.

**Why:** the correction is re-attribution + enumeration, **never deletion** — a
condition label is a reference into a canonical enumeration.

**How to apply:** do not re-point the label anywhere until F/CTO rules. `055`'s
`comment on role` is a DATABASE object → comment-only migration `117` (booked,
not authored). See [[reference_schema_impossible_ac_traces_to_incumbent]].

**2. ⚠ Sec's own C1 measurement had an error: BACKLOG §7.6 S5 DOES carry the
label.** Sec measured one `C1` hit in S5 and called it "no C1 label at all". The
AC line reads *"Discharges the remainder of [ADR-023](DECISIONS.md#adr-023)
condition C1"*. `116`'s original enumeration was RIGHT about S5.

**Why:** a reviewer's grep hit that is then glossed as "carries no label" is the
sound-quote/false-gloss class — the measurement is real, the gloss inverts it.

**How to apply:** re-read the matched LINE, never the reviewer's characterization
of it. Applies in both directions — I was refuted on two claims and vindicated on
a third in the same block.

**3. `055`'s header carries a STALE copied Decision-3 count** — *"Decision-3
family = 15 labeled / 12 DDL-realized (unchanged)"*. Live ADR-011 Decision 3 reads
**nineteen labeled / eighteen DDL-realized**. Same class for `055`'s DEFINER
allowlist "= 4". Not fixed (out of the C1/C5 brief scope); booked as a residual.

**Why:** Step 0 of `apply-migration` forbids copying a ledger count into a
migration; `055` predates the enforcement and the count rotted.

**How to apply:** any future `055` header touch sweeps these counts to Path B
(link, do not enumerate) in the same pass. See
[[feedback_catalog_comment_staleness_needs_the_catalog]].
