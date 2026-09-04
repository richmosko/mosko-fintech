---
name: lock-join-lists-are-dated-artifacts
description: A ratified Lock's join list / mod inventory names the schema of its authoring day — Lock 11 names `pfin.nav`, which never existed on the tree. Verify a Lock's IDENTIFIERS live; its RULING still stands.
metadata:
  type: reference
---

**A Lock's *ruling* is durable; the *identifiers* inside it are a dated snapshot. Verify the second, honor the first — they fail independently.**

Measured at the V1.5 pre-flight (`b90b846`, 2026-09-04). ADR-011 Decision 15 / **Lock 11** locks read-time composition joining *"`holdings_checkpoint` + `eod_price` + `account_trans` + `tax_character` + **`pfin.nav`**"*. `holdings_checkpoint`, `eod_price`, `account_trans` and `tax_character` all exist; **`pfin.nav` appears in no `create table` in the migration tree** — the live substrate is `nav_daily` + `fn_compute_nav` / `fn_nav_composition`. **Lock 12** likewise locks a live-staleness join reading *"`plaid_items.state` direct"*, but the R-14 fold (`015`) generalized that surface to `linked_source.connection_status`.

Neither falsifies the ruling. Lock 11 still rules read-time composition; Lock 12 still rules the sibling child table. What is stale is the vocabulary they are written in — Locks 11–15 were ratified at Phase 1 Step 4 (2026-05), before the GL, tax and provider-agnostic substrates landed.

**How to apply:** when drafting DDL against a Lock, `grep` every identifier the Lock names before copying it, and re-express the Lock's ruling over the live substrate rather than transcribing its nouns. State the substitution explicitly in the migration header so a reader does not think the Lock was ignored. ⚠ **Do not "correct" the Lock's text as a cleanup** — it records what was locked at that moment; the correction belongs in the implementing migration or a dated amendment. This is the same generator BACKLOG §7.19 exists to retire ([[project_prd_predates_gl_recalibration]]); companion to [[feedback_ratified_name_is_not_a_built_table]] and [[feedback_cited_precedent_transmits_its_retracted_half]].
