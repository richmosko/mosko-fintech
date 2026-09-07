---
name: aal2-passkey-arm-has-no-behavioural-observer
description: The 025 aal2 backstop's `passkey` arm is untested family-wide; every battery exercises only a totp tenant; only 106's text-pins name 'passkey' (PR #629)
metadata:
  type: project
---

The ADR-029 / `025` aal2 step-up conjunct reads
`coalesce(..., 'none') not in ('totp', 'passkey') or (auth.jwt() ->> 'aal') = 'aal2'`.
**No battery in the tree exercises a `passkey` tenant** — measured 2026-09-05 at
`2c94d3d`, `grep -n passkey supabase/tests/rls/074*.sql 090*.sql 101*.sql 106*.sql`
→ zero hits (at `79f6fa7` the grep hits `106` only, and only in its TEXT pins).
Text-pin coverage varies by member — `106`'s S6a/S6b pin `aal2` + `totp` +
`passkey` (PR #629, `79f6fa7`; QA measured the `'passkey'` strike flips S6a
alone); earlier members (`074` / `090` / `101`) pin `aal2` alone, and there a
regression narrowing the clause to `totp` alone passes every leg. **No member
has a behavioural passkey observer** — no leg drives a session whose
`mfa_policy = 'passkey'` and asserts the step-up actually gates. The mechanical
tell for this class is the NEGATIVE membership shape — dropping a list element
WIDENS the exemption, and a bare `%aal2%` pin is blind in the weakening direction.

**Why:** the fixture convention started at `074` with one totp tenant (D) and was
copied forward byte-for-byte through `090` / `101` / `106`. Nobody chose to skip
`passkey`; it was never in the shape being copied.

**How to apply:** it is family-wide and predates any single PR, so do **not**
condition one member's merge on it — flagging it only at the last member would be
a new requirement imposed on whoever happens to be last. Route it as a standing
QA item across all five batteries. Cheapest correct catch criterion needs no new
tenant: extend S6a/S6b to require **both** `'totp'` and `'passkey'` present in the
pinned expression text, on the `polqual` and `polwithcheck` halves separately.

Same class as [[feedback_enumeration_and_watcher_stop_one_short]] — the watcher
observes one element of an enumeration and reads as if it observed the set. Also
relevant: the migration-side byte-faithfulness of the clause IS verifiable and
does hold (clause-line md5 identical across `025`/`074`/`090`/`101`/`106`), so the
gap is purely in the batteries, never in the DDL.
