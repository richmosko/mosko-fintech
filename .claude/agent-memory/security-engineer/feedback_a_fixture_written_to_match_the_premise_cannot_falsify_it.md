---
name: a-fixture-written-to-match-the-premise-cannot-falsify-it
description: A fence whose mock was authored alongside the code encodes the code's assumption — it proves the parsing, never the premise. Ask which API ROUTE/shape the field was actually measured on.
metadata:
  type: feedback
---

A green offline fence over a hand-written mock proves **the code parses what the mock emits.**
It cannot prove the mock resembles production, because the same author wrote both in the same
hour from the same belief. **Never let a passing strike leg discharge a premise about an
external system's response shape.**

The specific axis that bit: **LIST route vs DETAIL route serialization.** I asked for a
`base_directory` check as defence-in-depth; DevOps built it reading
`GET /applications/{uuid}` (detail) and cited `provision-migrator-app.sh:184` as precedent —
but **every existing reader of that field in the repo uses `GET /applications` (the list
route).** Frameworks routinely serialize `index` and `show` differently (API resources, hidden
attributes, eager-loaded columns). The fixture supplied the field on the detail route, so the
fence validated the code against the assumption instead of testing it.

**How to apply.** When a review adds a NEW read of an external API field:

1. Grep every existing reader of that field and **name the route/endpoint each one uses.** A
   cited precedent on a different route is not a precedent.
2. Ask what happens if the field is ABSENT. Here: `!=` a hard-coded literal → fail-closed
   exit 16 → **every production fire blocked.** Fail-closed makes it availability, not security
   — say so, and grade it as a flag, not a veto.
3. The discharge is a **measurement, not a code change**: one read-only GET against the live
   system before the next real fire. Route it to whoever runs that fire.

⚠ **Own it when the unmeasured premise is one I ASKED for.** The defence-in-depth check was my
request; the availability risk it introduced is mine to name in the same message, not the
builder's to discover later. See [[feedback_my_requirement_can_be_voided_by_an_artifact_i_did_not_read]],
[[feedback_a_described_control_is_not_a_built_one]], [[feedback_an_accepted_residual_must_not_silently_widen]].
