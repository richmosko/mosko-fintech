---
name: db-template-clone-tool
description: scripts/db-template-clone.sh (docs/db-template.md) — the DevOps-built fast scratch-DB clone that replaces the manual sequential-apply recipe for QA verification work. First real-use report, SELF-257, 2026-09-03.
metadata:
  type: reference
---

`scripts/db-template-clone.sh <name>` clones a pre-built `pfin_tmpl` template database in
under 1 second (measured: ~1.08s wall including the staleness check), vs. the ~5s
`reference_scratch_db_full_chain_recipe.md` sequential-apply-by-hand recipe (which itself
replaces the earlier, much slower, fully-manual dump/create/apply dance).
`scripts/db-template-build.sh` builds/refreshes `pfin_tmpl` (needed once per session, or after
editing an already-numbered migration — the clone script's own staleness check, keyed on a
sha256 of the whole migrations tree plus the container image id, refuses to clone against a
stale template rather than silently serving one).

**First real-use report (SELF-257, ~8-10 clone-and-drop cycles in one session):**
- Worked exactly as documented every time — no gotchas, no retries, no `docker exec -i`
  stdin-swallow, no ownership-transfer surprise, no `--no-privileges` posture drop.
- pgTAP is NOT pre-installed in the template or the clone — still need
  `create extension pgtap schema public;` once per clone before running `pg_prove` (same as
  the old recipe; this is unchanged, not a regression).
- **The speed genuinely changed my debugging behavior, not just my wait time.** Because
  re-cloning costs ~1s, I debugged interactively — clone, probe with a throwaway psql script,
  drop, edit the fixture, re-clone, re-probe — rather than nursing one throwaway scratch DB
  through many in-place fixture edits (which is what the old ~5s-to-build recipe encouraged,
  since the apply cost made "just fix it in place and re-run the ONE failing file" feel cheaper
  than rebuilding). This surfaced the SELF-257 fixture-clock bug ([[feedback_fixture_clock_trap_
  recurred_self257]]) faster than the old workflow would have, since drop+reclone+reprobe was
  cheaper than reasoning about whether stale state might be confounding a measurement.
- Reused ONE scratch name (`self257test`) across every cycle rather than a fresh name each
  time — `db-template-clone.sh` drops-then-clones unconditionally into the given name per its
  own doc, so this is safe (no accidental-reuse guard needed, and none exists) as long as YOU
  remember to actually re-clone before trusting a result, not just re-run pg_prove against
  possibly-stale prior state — same discipline the OLD recipe already required
  ([[feedback_scratch_db_perf_seed_must_be_rolled_back]]).
- Host guard / name guard (refuses `postgres`/`template0`/`template1`/`pfin_tmpl` as a target,
  refuses to run against a non-local host) never fired — never had reason to test them.
- Confirmed the clone genuinely carries the `061` `TimeZone=UTC` per-database pin (DevOps's own
  measured claim in the doc) — did not independently re-verify this myself this session, took
  it as given since I wasn't touching timezone-sensitive legs.

**How to apply:** default to `scripts/db-template-clone.sh <name>` for any future scratch-DB
need instead of the manual sequential-apply recipe — it is strictly faster with no measured
downside, and the manual recipe's own gotcha catalog
([[feedback_scratch_db_pgtap_harness_gotchas]]) simply doesn't apply anymore for the steps this
tool automates. Still need to install pgtap per clone, and still need to `drop database` when
done (the tool does not do this for you on exit).
