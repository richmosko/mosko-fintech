# `--no-privileges` inversion-probe fixture (Sec-booked, 2026-09-02)

Sec's advisory on the template-DB snapshot mechanism (docs/db-template.md)
booked this as the discharge evidence for BACKLOG §7.14's "Scratch-harness
ACL parity (permissive-direction hazard)" entry: build a template DB the
SAME way `db-template-build.sh` does, except with `--no-privileges
--no-owner` on the auth/extensions/vault/etc. dump step, and diff its ACL
census (`GRANT`/`REVOKE` statements, `pg_dump --schema-only`) against the
real `pfin_tmpl`. A delta demonstrates the hazard is real for THIS recipe,
not merely theoretical; no delta would mean the protection is prospective.

**Result: DELTA DEMONSTRATED.** 181 GRANT/REVOKE lines on the `--no-privileges`
probe vs. 266 on the real template — 85 lines of privilege posture silently
dropped, concentrated entirely in the `auth`/`extensions` schemas (the ones
the dump step actually filters to). Representative losses: `GRANT USAGE ON
SCHEMA auth TO anon/authenticated/service_role` gone (the QA gotcha this
already predicted — `auth.uid()`'s resolvability from a fresh session
depends on it), the full `dashboard_user`/`supabase_admin` grant-option
posture on `auth.*` tables gone, and two explicit
`REVOKE ALL ... FROM supabase_admin` statements gone (the fence itself, not
just a grant). This is the exact direction QA's 2026-08-12 measurement
predicted — the harness silently becomes MORE permissive, not less — now
reproduced against this specific template-build recipe rather than inferred
from a prior, differently-shaped measurement.

**Files:**
- `pfin_tmpl-real-acls.txt` — the correct census (266 lines), from the real
  `pfin_tmpl` as built by `scripts/db-template-build.sh` (no `--no-privileges`).
- `no-privileges-probe-acls.txt` — the inverted census (181 lines), from a
  throwaway candidate built identically except for `--no-privileges
  --no-owner` on the auth-schema dump step.
- `no-privileges-inversion-delta.diff` — `diff no-privileges-probe-acls.txt
  pfin_tmpl-real-acls.txt`. Every `>` line is a grant/revoke the real
  template carries and the inverted probe silently drops.

**Provenance:** both censuses are `docker exec ... pg_dump -U postgres -d
<db> --schema-only --schema=pfin --schema=public --schema=auth
--schema=extensions --schema=vault | grep -E '^(GRANT|REVOKE)' | sort`. The
throwaway `inversion_probe` database used to produce the probe census was
dropped after capture — these three files are the fixture, not a live DB.

**Regression use:** if `db-template-build.sh`'s dump step is ever changed to
add `--no-privileges`/`--no-owner` (or an equivalent flag), re-running this
same probe should reproduce this same delta shape. A future CI/test hook
could diff a fresh probe against `pfin_tmpl-real-acls.txt` and fail if the
delta reappears; not wired up as an automated check in this pass — these
files are the recorded evidence, not yet an enforced gate.
