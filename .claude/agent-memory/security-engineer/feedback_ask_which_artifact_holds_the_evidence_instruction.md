---
name: ask-which-artifact-holds-the-evidence-instruction
description: When an assertion changes its evidence channel, grade where the INSTRUCTION that produces the evidence now lives — a tamper analysis of the data store misses the API that edits the instruction
metadata:
  type: feedback
---

When a control's evidence channel moves, three things move and they are usually graded as one: the **evidence**, the **transport**, and the **instruction that produces the evidence**. Grade the third separately and ask which artifact now holds it, and what write-protects that artifact.

**Why:** ADR-072 Amendment 7 moved both migrator assertions from a direct `docker exec` to reading the Scheduled Task's stdout. Its tamper analysis named the right surface for the stored **output** ("whoever can write the Coolify database — already root-equivalent") and **missed** that the **command string** producing that output moved out of the root-owned, `ci-migrate`-unwritable orchestrator that **C5** exists to protect and into Coolify, where the trigger token is scoped `[read, write, deploy]`. If that write reaches the scheduled-task update route, the credential that READS the evidence can REWRITE what produces it — self-fulfilling, needing no root and no database access. Fix shape: re-anchor by reading the instruction back and comparing it to a literal held in an artifact the caller cannot write, failing closed on mismatch.

**How to apply:** on any "we'll read it from X instead" proposal, ask (1) who can edit the thing that emits the value, not just who can edit the value; (2) was that emitter previously covered by a named control — if so the proposal SPENDS that control and must say so; (3) is the objection about privilege or about integrity — an "extends no trust" argument answers privilege and leaves integrity untouched. Related: [[feedback_a_disposition_without_a_mechanism]], [[feedback_a_gate_on_a_status_already_ruled_unreliable]], [[feedback_replacement_control_name_the_losing_side]].
