---
name: feedback-structural-picker-over-validation-only
description: When a UI boundary is a correctness/security concern (not just UX), make it structural in the picker (limit selectable options) rather than relying only on post-submit validation to reject the wrong choice.
metadata:
  type: feedback
  score: n/a
---

On SELF-325 (manual purchase-path, 088), F/CTO+Architect ruled the market-security "resolve"
call must never admit the 4 personal asset types (real_estate/vehicle/collectible/private) —
routing one through resolve mints a permanently unpriceable, unrepairable GLOBAL row. The
instruction was to build the fork so the boundary is structural, "not just labeled."

I implemented it by giving the resolve step's asset-type picker a NARROWER option list
(`RESOLVABLE_ASSET_TYPES`, 9 values) than the personal-asset (MINT) picker's (`MINT_ASSET_TYPES`,
13 values) — so a personal type is never a selectable `<option>` in the resolve dropdown at all,
rather than being selectable-then-rejected by a client/server Zod refine.

Architect's review (2026-08-21) called this out unprompted as going *past* what was ruled: "That's
the house/car fork enforced by construction rather than by validation, which is strictly better...
It also means the server-side rejection becomes a defense-in-depth backstop rather than the
primary control, which is the right ordering."

**Why:** A validation-only rejection still lets the user select the wrong thing and only tells
them after; it also means the *only* thing preventing the mistake is a check that could regress.
Narrowing the picker's own option set makes the wrong choice unreachable through the UI, and downgrades
the validation layer to what it should be — a backstop for a stale tab / non-UI caller, not the
primary control.

**How to apply:** When a design ruling frames a UI choice as a correctness or security boundary
(not a UX nicety), check whether the affected control is a picker/select with a bounded option
set. If so, prefer narrowing the option set itself over adding a rejection rule on the full set —
and keep the validation-layer check too, explicitly reframed as defense-in-depth, not the primary
fence. This generalizes beyond SELF-325: any picker feeding a write path with an irreversible or
narrow-consequence branch (mint vs. resolve, a one-way state transition, an admin-only action) is
a candidate for the same treatment.
