---
name: standup-preconditions-scope
description: Stand-up preconditions record Round 3 (2026-09-08 21:00) — ALL §F ruled (Q4 S1; Q5 signup-off-until-allowlist; Q7 refuse; Q8 as drafted); Linear blocks §B.3/§C.8/§C.6 FINAL; §H liaison list; allowlist at BACKLOG §7.36; PR #670 awaiting merge; P-3 re-worded; P-4/P-5 owed.
metadata:
  type: project
---

`docs/records/v1final/standup-preconditions.md` Round 3 on `feature/standup-preconditions-r3` @ `d12ac693` (PR #670, baseline `2387ae74`; no Linear writes). Every §F question is ruled; the liaison creates I-1 / I-2 / I-3 from the record's **§H** after merge.

**Rulings (verify live in §G.2 / §G.4):** Item 1 STRUCK (V2 at BACKLOG §5.4); Q4 → S1 (backfill first, into manual accounts; V1 attach-at-Link build §B); **Q5 → production signup OFF until an operator allowlist on link-token + reauth/start routes exists** (BACKLOG §7.36; sole tenant by invitation through N=2 soak; losing side: open-signup story not re-walked during the soak); **Q7 → refuse the run until the category map is complete**; **Q8 → I-1 parentless in Onboarding, I-2/I-3 under SELF-365**.

**Drift caught (reuse only after re-checking):** `role:architect` does not exist — the label is `role:arch` (`docs/linear-setup.md`); `role:qa`/`role:devops` absent. `supabase/config.toml enable_signup` is local-only — production is self-hosted on Coolify, the signup knob is a DevOps fact at SELF-386 (record D-12). Re-auth start route is `api/src/routes/api/reauth/start/+server.ts`. `015` #6 trigger is BEFORE INSERT OR UPDATE (Round 2 D-8). Onboarding project has no V1.final native milestone on the tree; SELF-365 children sit in Platform · *V1.final — §3.4 close mechanism* (I-2/I-3 corrected to it).

**Owed by PM:** PRD amendment PR — P-1/P-2/**P-3 re-worded** (§7.3: sole tenant by invitation during V1.final; open signup per ADR-036 after §7.36 lands)/P-4 (§2.4.1 attach outcome, §2.4.2 qualified, App. B/C)/P-5 (§2.4.3 one-time-run clause + cutover) — after the Architect ADR ([[365-v1final-protocol]]). §7.36 has no milestone — promote when F/CTO names one.

**How to apply:** if asked about stand-up sequencing, read §D.1 live: deploy → backfill walk → attach-capable Link → Plaid connection → month-1 clock. Never propose an allowlist as a tenant role — §7.3/ADR-036 have tenants, not roles; it is an operator config surface.
