---
name: adr023-c1-label-is-unsupported
description: Five artifacts label the PostgREST/provider-sync rotation coupling "ADR-023 condition C1"; ADR-023's actual C1 is the exposure-readiness artifact. Substance real, label unsupported.
metadata:
  type: reference
---

**"ADR-023 condition C1" is NOT the rotation coupling.** Verified against `DECISIONS.md`
as merged at `2bb6b0e6` (2026-09-08).

- **ADR-023's enumerated C1** = *"exposure-readiness artifact (per-table RLS + policy
  proof) reviewed before exposure"*. C2 = anon zero-grant. C3 = `access_token_secret_id`
  withheld. C4 = decrypt view service_role-only. C5/C6 = write surfaces / standing battery.
- **No text anywhere in `DECISIONS.md` attaches the rotation coupling to a condition
  labeled C1.** The nearest real home is **ADR-019's login-role note**, whose "Sec
  conditions C1–C4" are *referenced but never enumerated*, and whose **C2** states the
  substance directly: *"decouples the worker's credential from PostgREST's
  authenticator-password rotation."*

**Carriers of the wrong label** (grep `C1 rotation` / `condition C1`): ADR-041's
Consequences bullet · `055`'s `comment on role` (⚠ a **database object** — only a
comment-only migration can fix it) · `secrets-manifest.yml` PFIN_DB_PASSWORD entry ·
`docs/deployment-runbook.md` §6.1 · `BACKLOG.md` §7.6 S5 AC.

**The coupling itself is real** — provider-sync's `PFIN_DB_PASSWORD` holds the
`authenticator` password, which is also PostgREST's credential.

**How to apply:** name the **property** and its evidence, never the label. This is the
[[feedback_false_composite_citation]] class at cross-artifact scale — right content,
wrong pointer, propagated by verbatim carry through five artifacts, which is exactly why
it survives every spot-check. Flagged to Sec + F/CTO at PR #671; do not propagate.
