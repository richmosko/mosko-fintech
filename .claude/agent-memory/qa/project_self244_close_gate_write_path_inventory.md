---
name: project-self244-close-gate-write-path-inventory
description: SELF-244 (V1.2 close-gate battery) §2.2.6 write-path coverage must include the SELF-233 planning-target endpoint — flagged 2026-08-17, no action until SELF-244 starts
metadata:
  type: project
---

SELF-233 landed a NEW INVOKER write path: `POST /api/settings/planning-target` →
upsert on `pfin.planning_target (users_id, sub_cat_id)`, anon-key + RLS,
`users_id` from session only. The pgTAP half (Decision-3 #17 fence + the
plan-37 battery) was pre-built at migration `074` and already asserts the DB
layers; the app-layer surface carries its own RT-23 vitest adversarial battery
on its landing branch (Sec joint review in progress there, separate from this
note).

**Why:** Backend routed this to me as a battery-flag event per `api/CLAUDE.md`
convention — informational only, "no work owed today." Team-lead relayed it
2026-08-17.

**How to apply:** When SELF-244 (the V1.2 close-gate battery) starts, its
§2.2.6 verification must COUNT this endpoint among the write paths it covers.
Don't rediscover this from scratch at that point — the DB-layer battery
already exists (074, plan(37)); confirm SELF-244's coverage checklist includes
the planning-target write path specifically, rather than assuming the existing
074 battery alone closes it (074 is DB-layer; SELF-244 is presumably a
broader/different-shaped close-gate sweep — verify what SELF-244 actually
requires against BACKLOG/Linear live before assuming redundancy either way).
